"""A real, headless KWin to test kde-snap-overlay against.

Each Sandbox starts its own `kwin_wayland --virtual` with N virtual outputs,
its own D-Bus session bus and its own HOME/XDG dirs under a temp folder, so
nothing reaches the user's real session or config. Inside it:

- the working tree's script is installed and enabled (debugLog on);
- test windows are plain QML windows (tests/kwin/window.qml), decorated by
  Breeze, so drags start on a real titlebar;
- the pointer is driven through KWin's org_kde_kwin_fake_input protocol,
  and monitors are moved, rescaled or unplugged through
  kde_output_management_v2 (tests/kwin/outputctl.c);
- KWin's state is read by loading tiny JS "probe" scripts over D-Bus that
  print JSON into KWin's log;
- screenshots come from KWin's ScreenShot2 D-Bus interface.

Run inside the dev container only (needs kwin, pywayland, gcc, wayland-devel,
dbus-python): python3 -I tests/kwin/scenarios.py
"""

import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import uuid
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
# KSO_ROOT=/path/to/checkout tests another copy of the script (mutation checks).
REPO = Path(os.environ.get("KSO_ROOT") or HERE.parents[1])
PKG_ID = "kde-snap-overlay"
QDBUS = shutil.which("qdbus-qt6") or shutil.which("qdbus6") or "/usr/lib64/qt6/bin/qdbus"
QML = shutil.which("qml") or "/usr/lib64/qt6/bin/qml"
BTN_LEFT = 0x110
KEY_LEFTMETA = 125


class SandboxError(RuntimeError):
    pass


def _write_png(path, raw, width, height, stride):
    """Write KWin's ARGB32 (little-endian BGRA) screenshot buffer as a PNG."""
    rows = []
    for y in range(height):
        line = raw[y * stride:y * stride + width * 4]
        rgba = bytearray(len(line))
        rgba[0::4] = line[2::4]
        rgba[1::4] = line[1::4]
        rgba[2::4] = line[0::4]
        rgba[3::4] = line[3::4]
        rows.append(b"\x00" + bytes(rgba))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"".join(rows), 6))
    png += chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def build_outputctl(out_dir):
    """Compile tests/kwin/outputctl.c (see there for why it is C)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    proto = "/usr/share/plasma-wayland-protocols/"
    sources = [str(HERE / "outputctl.c")]
    for xml in ("kde-output-device-v2", "kde-output-management-v2"):
        subprocess.run(["wayland-scanner", "client-header", proto + xml + ".xml",
                        str(out_dir / (xml + "-client-protocol.h"))], check=True)
        subprocess.run(["wayland-scanner", "private-code", proto + xml + ".xml",
                        str(out_dir / (xml + "-protocol.c"))], check=True)
        sources.append(str(out_dir / (xml + "-protocol.c")))
    binary = out_dir / "kso-outputctl"
    subprocess.run(["gcc", "-O1", "-Wall", "-Wextra", "-Werror", "-I", str(out_dir), "-o", str(binary),
                    *sources, "-lwayland-client", "-lm"], check=True)
    return binary


class Wayland:
    """The driver's own Wayland client for pointer and keyboard input,
    through org_kde_kwin_fake_input (pywayland; bindings generated on the
    fly). Monitor changes go through kso-outputctl instead."""

    def __init__(self, socket_path, proto_dir):
        # The generated modules import each other relatively, so they need a
        # parent package.
        pkg = proto_dir / "kso_proto"
        pkg.mkdir(parents=True, exist_ok=True)
        (pkg / "__init__.py").touch()
        subprocess.run([sys.executable, "-m", "pywayland.scanner", "-i",
                        "/usr/share/wayland/wayland.xml",
                        "/usr/share/plasma-wayland-protocols/fake-input.xml",
                        "-o", str(pkg)], check=True, capture_output=True)
        sys.path.insert(0, str(proto_dir))
        from pywayland.client import Display  # noqa: E402
        from kso_proto.fake_input import OrgKdeKwinFakeInput  # noqa: E402

        self.display = Display(str(socket_path))
        self.display.connect()
        self.fake = None
        registry = self.display.get_registry()

        def on_global(reg, name, interface, version):
            if interface == "org_kde_kwin_fake_input":
                self.fake = reg.bind(name, OrgKdeKwinFakeInput, min(version, 4))

        registry.dispatcher["global"] = on_global
        self.display.roundtrip()
        if self.fake is None:
            raise SandboxError("KWin offers no org_kde_kwin_fake_input")
        self.fake.authenticate("kso-tests", "kde-snap-overlay integration tests")
        self.display.roundtrip()
        self.pos = (0.0, 0.0)

    def move(self, x, y):
        self.fake.pointer_motion_absolute(float(x), float(y))
        self.display.flush()
        self.pos = (float(x), float(y))

    def button(self, pressed, button=BTN_LEFT):
        self.fake.button(button, 1 if pressed else 0)
        self.display.flush()

    def key(self, pressed, key):
        self.fake.keyboard_key(key, 1 if pressed else 0)
        self.display.flush()

    def close(self):
        try:
            self.display.disconnect()
        except Exception:
            pass


class Sandbox:
    def __init__(self, outputs=2, width=1920, height=1080, script_config=None,
                 windows_config=None, desktops=1, keep=False, label="sandbox"):
        self.outputs = outputs
        self.width = width
        self.height = height
        self.script_config = {"debugLog": "true", **(script_config or {})}
        self.windows_config = windows_config or {}
        self.desktops = desktops
        self.keep = keep
        self.label = label
        self.procs = []
        self.clients = []
        self.pointer = None
        # /var/tmp is the container's own (distrobox shares /tmp and $HOME
        # with the host); KSO_SANDBOX_DIR overrides.
        self.root = Path(tempfile.mkdtemp(prefix="kso-kwin-",
                                          dir=os.environ.get("KSO_SANDBOX_DIR", "/var/tmp")))
        self.log_path = self.root / "kwin.log"
        self._log_offset = 0

    # ---- lifecycle -------------------------------------------------------

    def __enter__(self):
        try:
            self.start()
        except BaseException:
            # __exit__ never runs for a failed start: don't leak KWin.
            self.stop()
            raise
        return self

    def __exit__(self, *exc):
        self.stop()

    def _env(self):
        env = {k: v for k, v in os.environ.items()
               if k not in ("WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS",
                            "XDG_SESSION_TYPE", "KDE_FULL_SESSION")}
        env.update({
            "HOME": str(self.root / "home"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_RUNTIME_DIR": str(self.root / "run"),
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=" + str(self.root / "bus"),
            "WAYLAND_DISPLAY": str(self.root / "run" / "wayland-kso"),
            "QT_QPA_PLATFORM": "wayland",
            "KWIN_WAYLAND_NO_PERMISSION_CHECKS": "1",
            "KWIN_SCREENSHOT_NO_PERMISSION_CHECKS": "1",
            "QT_LOGGING_RULES": "js=true;qml=true;kwin_scripting=true",
            # Qt logs to the journal when stderr is no terminal; keep it in our log.
            "QT_FORCE_STDERR_LOGGING": "1",
        })
        return env

    def _write_config(self):
        cfg = self.root / "config"
        lines = ["[Plugins]", PKG_ID + "Enabled=true", "",
                 "[Script-" + PKG_ID + "]"]
        lines += ["%s=%s" % kv for kv in self.script_config.items()]
        lines += ["", "[Windows]"] + ["%s=%s" % kv for kv in self.windows_config.items()]
        lines += ["", "[Desktops]", "Number=%d" % self.desktops, "Rows=1"]
        lines += ["", "[Compositing]", "AnimationSpeed=0"]
        (cfg / "kwinrc").write_text("\n".join(lines) + "\n")
        # No animations: positions settle at once, so probes are deterministic.
        (cfg / "kdeglobals").write_text("[KDE]\nAnimationDurationFactor=0\n")

    def start(self):
        for d in ("home", "config", "data", "cache", "state", "run"):
            (self.root / d).mkdir(parents=True, exist_ok=True)
        os.chmod(self.root / "run", 0o700)
        self._write_config()
        env = self._env()
        self.outputctl = build_outputctl(self.root / "build")

        stage = self.root / "stage"
        stage.mkdir()
        shutil.copy(REPO / "metadata.json", stage)
        shutil.copytree(REPO / "contents", stage / "contents")
        subprocess.run(["kpackagetool6", "--type", "KWin/Script", "--install", str(stage)],
                       env=env, check=True, capture_output=True)

        bus = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--nopidfile",
                                "--address=unix:path=" + str(self.root / "bus")],
                               env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.procs.append(bus)
        self._wait(lambda: (self.root / "bus").exists(), 5, "dbus-daemon")

        log = open(self.log_path, "wb")
        kwin = subprocess.Popen(
            ["kwin_wayland", "--virtual", "--no-lockscreen",
             "--output-count", str(self.outputs),
             "--width", str(self.width), "--height", str(self.height),
             "--socket", "wayland-kso"],
            env=env, stdout=log, stderr=subprocess.STDOUT)
        self.procs.append(kwin)
        self._wait(lambda: self._dbus_ok(), 20, "kwin_wayland on D-Bus")
        self._wait(lambda: self.probe("return workspace.screens.length")["result"] == self.outputs,
                   10, "outputs")
        self.pointer = Wayland(self.root / "run" / "wayland-kso", self.root / "proto")
        self.settle(0.3)

    def stop(self):
        if self.pointer:
            self.pointer.close()
        for p in self.clients + list(reversed(self.procs)):
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(3)
                except subprocess.TimeoutExpired:
                    p.kill()
        if not self.keep:
            shutil.rmtree(self.root, ignore_errors=True)

    def _wait(self, cond, timeout, what):
        end = time.time() + timeout
        while time.time() < end:
            try:
                if cond():
                    return
            except Exception:
                pass
            for p in self.procs:
                if p.poll() is not None:
                    raise SandboxError(what + ": a sandbox process died; see " + str(self.log_path))
            time.sleep(0.1)
        raise SandboxError("timed out waiting for " + what + "; see " + str(self.log_path))

    def settle(self, seconds=0.15):
        time.sleep(seconds)

    # ---- D-Bus / probes ---------------------------------------------------

    def qdbus(self, *args, check=True):
        r = subprocess.run([QDBUS, *args], env=self._env(), capture_output=True, text=True, timeout=10)
        if check and r.returncode != 0:
            raise SandboxError("qdbus %s: %s" % (" ".join(args), r.stderr.strip()))
        return r.stdout.strip()

    def _dbus_ok(self):
        return "/Scripting" in self.qdbus("org.kde.KWin", check=False)

    def log_text(self):
        return self.log_path.read_text(errors="replace")

    def new_log(self):
        """Log lines written since the previous call."""
        text = self.log_text()
        new = text[self._log_offset:]
        self._log_offset = len(text)
        return new

    def probe(self, body, timeout=5):
        """Run JS `body` inside KWin (a function body; `return` a JSON-able
        value) and return {"result": value}. Helpers g(rect) and win(caption)
        are in scope."""
        token = uuid.uuid4().hex
        name = "kso-probe-" + token[:8]
        path = self.root / (name + ".js")
        path.write_text(
            "function g(r){return r?{x:r.x,y:r.y,w:r.width,h:r.height}:null}\n"
            "function win(c){var o=workspace.stackingOrder;for(var i=0;i<o.length;i++)"
            "{if(o[i].caption===c)return o[i]}return null}\n"
            "var __r;try{__r={result:(function(){" + body + "})()}}"
            "catch(e){__r={error:String(e)}}\n"
            "print('KSOPROBE " + token + " '+JSON.stringify(__r));\n")
        sid = self.qdbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript",
                         str(path), name)
        try:
            self.qdbus("org.kde.KWin", "/Scripting/Script" + sid, "org.kde.kwin.Script.run")
            marker = "KSOPROBE " + token + " "
            end = time.time() + timeout
            while time.time() < end:
                for line in self.log_text().splitlines():
                    i = line.find(marker)
                    if i >= 0:
                        out = json.loads(line[i + len(marker):])
                        if "error" in out:
                            raise SandboxError("probe error: " + out["error"])
                        return out
                time.sleep(0.03)
            raise SandboxError("probe produced no output")
        finally:
            self.qdbus("org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript",
                       name, check=False)

    def state(self):
        """Screens, desktops and every window KWin knows (incl. our OSDs)."""
        return self.probe("""
            var s = workspace.screens.map(function (o) {
                var d = workspace.currentDesktopForScreen(o);
                return {name: o.name, geo: g(o.geometry), scale: o.devicePixelRatio,
                        desktop: d ? d.name : null};
            });
            var w = workspace.stackingOrder.map(function (x) {
                return {caption: x.caption, normal: x.normalWindow, osd: x.onScreenDisplay,
                        geo: g(x.frameGeometry), output: x.output ? x.output.name : null,
                        tile: x.tile ? g(x.tile.absoluteGeometry) : null,
                        move: x.move, active: workspace.activeWindow === x,
                        desktops: x.onAllDesktops ? ['*'] : x.desktops.map(function (d) { return d.name; }),
                        visible: !x.minimized && !x.hidden};
            });
            return {screens: s, windows: w, cursor: {x: workspace.cursorPos.x, y: workspace.cursorPos.y},
                    active: workspace.activeScreen ? workspace.activeScreen.name : null,
                    desktop: workspace.currentDesktop ? workspace.currentDesktop.name : null};
        """)["result"]

    def screens(self):
        return self.state()["screens"]

    def layout(self, **changes):
        """Reconfigure monitors, e.g. layout(**{"Virtual-1": {"pos": (0, 1080),
        "scale": 1.5}}) or {"enabled": False}; verified against KWin's view."""
        args = []
        for name, ch in changes.items():
            spec = name
            if "enabled" in ch:
                spec += ":enabled=%d" % (1 if ch["enabled"] else 0)
            if "pos" in ch:
                spec += ":x=%d:y=%d" % tuple(ch["pos"])
            if "scale" in ch:
                spec += ":scale=%s" % ch["scale"]
            args.append(spec)
        r = subprocess.run([str(self.outputctl), *args], env=self._env(),
                           capture_output=True, text=True, timeout=10)
        if r.returncode != 0:
            raise SandboxError("kso-outputctl %s: %s" % (" ".join(args), r.stderr.strip()))
        def applied():
            screens = {s["name"]: s for s in self.screens()}
            for name, ch in changes.items():
                if ch.get("enabled") is False:
                    if name in screens:
                        return False
                    continue
                s = screens.get(name)
                if s is None:
                    return False
                if "pos" in ch and (s["geo"]["x"], s["geo"]["y"]) != tuple(ch["pos"]):
                    return False
                if "scale" in ch and abs(s["scale"] - ch["scale"]) > 0.01:
                    return False
            return True
        self._wait(applied, 5, "layout %s" % changes)
        self.settle(0.3)

    # ---- windows ------------------------------------------------------------

    def open_window(self, caption, x, y, w, h):
        p = subprocess.Popen([QML, str(HERE / "window.qml"), "--", caption], env=self._env(),
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.clients.append(p)
        self._wait(lambda: self.probe("return !!win(%s)" % json.dumps(caption))["result"],
                   10, "window " + caption)
        self.place(caption, x, y, w, h)
        return caption

    def place(self, caption, x, y, w, h):
        """Move/resize a window and activate it. With per-output desktops it
        also joins the desktop its new output shows, as if opened there."""
        self.probe("var c = win(%s); c.frameGeometry = {x:%d,y:%d,width:%d,height:%d};"
                   " return 1" % (json.dumps(caption), x, y, w, h))
        self.settle(0.3)
        self.probe("var c = win(%s); var d = workspace.currentDesktopForScreen(c.output);"
                   " if (!c.onAllDesktops && c.desktops.indexOf(d) < 0) c.desktops = [d];"
                   " workspace.activeWindow = c; return 1" % json.dumps(caption))
        self.settle(0.2)

    def open_panel(self, screen_index, height):
        """A layer-shell top panel (tests/kwin/panel.qml) on one screen;
        waits until KWin's MaximizeArea there starts below it."""
        screen = self.screens()[screen_index]
        name = screen["name"]
        # The bar opens on the active screen, which follows the pointer.
        self.pointer.move(screen["geo"]["x"] + screen["geo"]["w"] / 2,
                          screen["geo"]["y"] + screen["geo"]["h"] / 2)
        self.settle(0.1)
        p = subprocess.Popen([QML, str(HERE / "panel.qml"), "--", str(height)],
                             env=self._env(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.clients.append(p)
        self._wait(lambda: self.max_area(name)[1] == self.screens()[screen_index]["geo"]["y"] + height,
                   10, "panel on " + name)
        self.settle(0.2)

    def max_area(self, name):
        """KWin's MaximizeArea (x, y, w, h) of the named screen."""
        a = self.probe("var o = workspace.screens.filter(function (s) { return s.name === %s; })[0];"
                       " return g(workspace.clientArea(KWin.MaximizeArea, o, workspace.currentDesktop))"
                       % json.dumps(name))["result"]
        return (a["x"], a["y"], a["w"], a["h"])

    def window(self, caption):
        for w in self.state()["windows"]:
            if w["caption"] == caption:
                return w
        return None

    def osds(self):
        return [w for w in self.state()["windows"] if w["osd"]]

    # ---- pointer --------------------------------------------------------------

    def drag(self, path, step_ms=16, steps=12, hold_ms=400, release=True, meta=False):
        """Press at path[0], glide through each later point in `steps`
        increments, rest `hold_ms` at the end, then release (unless asked not
        to). meta=True holds Meta (KWin's unrestricted move) for the drag."""
        p = self.pointer
        p.move(*path[0])
        time.sleep(0.05)
        if meta:
            p.key(True, KEY_LEFTMETA)
        p.button(True)
        time.sleep(0.05)
        for a, b in zip(path, path[1:]):
            for i in range(1, steps + 1):
                p.move(a[0] + (b[0] - a[0]) * i / steps, a[1] + (b[1] - a[1]) * i / steps)
                time.sleep(step_ms / 1000)
        time.sleep(hold_ms / 1000)
        if release:
            self.release(meta)

    def release(self, meta=False):
        self.pointer.button(False)
        if meta:
            self.pointer.key(False, KEY_LEFTMETA)
        time.sleep(0.4)

    def hover(self, x, y, ms=300, steps=6):
        """Glide from the current pointer position to (x, y), then rest."""
        sx, sy = self.pointer.pos
        for i in range(1, steps + 1):
            self.pointer.move(sx + (x - sx) * i / steps, sy + (y - sy) * i / steps)
            time.sleep(0.016)
        time.sleep(ms / 1000)

    # ---- screenshots -------------------------------------------------------------

    def capture(self):
        """The whole workspace as (raw ARGB32 bytes, width, height, stride),
        logical pixels, origin at the workspace's top-left."""
        import dbus
        bus = dbus.bus.BusConnection(self._env()["DBUS_SESSION_BUS_ADDRESS"])
        obj = bus.get_object("org.kde.KWin", "/org/kde/KWin/ScreenShot2")
        iface = dbus.Interface(obj, "org.kde.KWin.ScreenShot2")
        r, w = os.pipe()
        meta = iface.CaptureWorkspace({"native-resolution": False}, dbus.types.UnixFd(w))
        os.close(w)
        chunks = []
        while True:
            b = os.read(r, 1 << 20)
            if not b:
                break
            chunks.append(b)
        os.close(r)
        return b"".join(chunks), int(meta["width"]), int(meta["height"]), int(meta["stride"])

    def screenshot(self, path):
        raw, width, height, stride = self.capture()
        _write_png(path, raw, width, height, stride)
        return path

    def max_alpha(self, x0, y0, x1, y1):
        """Highest alpha drawn in [x0, x1) x [y0, y1); the empty desktop is
        fully transparent, so anything > 0 is something KWin painted."""
        raw, width, height, stride = self.capture()
        m = 0
        for y in range(max(0, y0), min(height, y1)):
            row = raw[y * stride:(y + 1) * stride]
            m = max(m, max(row[max(0, x0) * 4 + 3:min(width, x1) * 4:4] or b"\0"))
        return m
