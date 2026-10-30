"""Multi-monitor scenarios for kde-snap-overlay, run against a real KWin.

Each scenario builds its own sandbox (tests/kwin/sandbox.py), drives real
pointer drags and checks what KWin actually did: where the popup and the
zone overlay were shown, and where the dropped window was tiled.

Usage (inside the dev container):
    python3 -I tests/kwin/scenarios.py [-k substring] [--shots DIR]
"""

import argparse
import json
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sandbox import Sandbox  # noqa: E402

CARD_W, CARD_H, GAP = 130, 70, 10
ROW_W = 3 * CARD_W + 2 * GAP
LAYOUT_OF = {"left": 0, "right": 0, "top": 1, "bottom": 1,
             "topLeft": 2, "topRight": 2, "bottomLeft": 2, "bottomRight": 2}
SHOTS = None


class Fail(AssertionError):
    pass


def check(cond, msg):
    if not cond:
        raise Fail(msg)


def rect(d):
    return (d["x"], d["y"], d["w"], d["h"])


def near(a, b, tol=2):
    return a is not None and b is not None and all(abs(p - q) <= tol for p, q in zip(a, b))


def contains(screen_geo, x, y):
    gx, gy, gw, gh = screen_geo
    return gx <= x < gx + gw and gy <= y < gy + gh


def screen_of(sb, name):
    for s in sb.screens():
        if s["name"] == name:
            return rect(s["geo"])
    raise Fail("no screen " + name)


def popup(sb):
    """Our selector dialog: the small caption-less internal window."""
    c = [w for w in sb.state()["windows"]
         if w["caption"] == "" and w["geo"]["w"] < 800 and w["visible"]]
    return c[0] if c else None


def overlay(sb):
    c = [w for w in sb.state()["windows"]
         if w["caption"] == "" and w["geo"]["w"] >= 800 and w["visible"]]
    return c[0] if c else None


def zone_point(p, zone, h=0.5, v=0.5):
    """Centre of a zone's mini-target in the popup (card row centred in the
    dialog frame; good to a few px, and every zone is >= 39x21 px)."""
    px, py, pw, ph = rect(p["geo"])
    x0 = px + (pw - ROW_W) / 2 + LAYOUT_OF[zone] * (CARD_W + GAP)
    y0 = py + (ph - CARD_H) / 2
    fx = {"left": (0, h), "right": (h, 1), "top": (0, 1), "bottom": (0, 1),
          "topLeft": (0, h), "topRight": (h, 1), "bottomLeft": (0, h), "bottomRight": (h, 1)}[zone]
    fy = {"left": (0, 1), "right": (0, 1), "top": (0, v), "bottom": (v, 1),
          "topLeft": (0, v), "topRight": (0, v), "bottomLeft": (v, 1), "bottomRight": (v, 1)}[zone]
    return (x0 + CARD_W * (fx[0] + fx[1]) / 2, y0 + CARD_H * (fy[0] + fy[1]) / 2)


def zone_rect(screen_geo, zone, h=0.5, v=0.5):
    x, y, w, hh = screen_geo
    fx = {"left": (0, h), "right": (h, 1), "top": (0, 1), "bottom": (0, 1),
          "topLeft": (0, h), "topRight": (h, 1), "bottomLeft": (0, h), "bottomRight": (h, 1)}[zone]
    fy = {"left": (0, 1), "right": (0, 1), "top": (0, v), "bottom": (v, 1),
          "topLeft": (0, v), "topRight": (0, v), "bottomLeft": (v, 1), "bottomRight": (v, 1)}[zone]
    return (round(x + w * fx[0]), round(y + hh * fy[0]),
            round(w * (fx[1] - fx[0])), round(hh * (fy[1] - fy[0])))


def popup_on_screen(sb):
    """Screens the popup currently covers any part of (by name)."""
    p = popup(sb)
    if p is None:
        return []
    px, py, pw, ph = rect(p["geo"])
    hits = []
    for s in sb.screens():
        x, y, w, h = rect(s["geo"])
        if px < x + w and px + pw > x and py < y + h and py + ph > y:
            hits.append(s["name"])
    return hits


def shot(sb, name):
    if SHOTS:
        SHOTS.mkdir(parents=True, exist_ok=True)
        sb.screenshot(SHOTS / (name + ".png"))


def titlebar(sb, caption, dx=None):
    """A point on the window's titlebar, dx px from its left (default: centre)."""
    g = rect(sb.window(caption)["geo"])
    return (g[0] + (g[2] / 2 if dx is None else dx), g[1] + 14)


def snap_via_popup(sb, caption, grab, band_point, zone, name, meta=False, h=0.5, v=0.5):
    """Drag `caption` from `grab` into the band at `band_point`, hover `zone`
    on the popup, drop. Returns (popup, overlay, window-after)."""
    sb.drag([grab, (band_point[0], band_point[1] + 150), band_point], release=False, meta=meta)
    p = popup(sb)
    check(p is not None, "popup not shown at " + str(band_point))
    sb.hover(*zone_point(p, zone, h, v), ms=450)
    p = popup(sb)
    o = overlay(sb)
    shot(sb, name)
    sb.release(meta)
    time.sleep(0.3)
    return p, o, sb.window(caption)


# ---- scenarios -------------------------------------------------------------------

def s_side_by_side_each_screen(sb_factory):
    """Popup, overlay and snap all land on the monitor the cursor is on."""
    with sb_factory(outputs=2) as sb:
        sb.open_window("W", 300, 300, 800, 500)
        for scr, zone in (("Virtual-0", "left"), ("Virtual-1", "bottomRight"), ("Virtual-1", "top")):
            g = screen_of(sb, scr)
            sb.place("W", g[0] + 300, g[1] + 300, 800, 500)
            p, o, w = snap_via_popup(sb, "W", titlebar(sb, "W"), (g[0] + g[2] / 2, g[1] + 40),
                                     zone, "side-%s-%s" % (scr, zone))
            check(contains(g, p["geo"]["x"] + 5, p["geo"]["y"] + 5), "popup not on %s: %s" % (scr, p["geo"]))
            check(o is not None and near(rect(o["geo"]), g), "overlay not covering %s: %s" % (scr, o and o["geo"]))
            check(near(rect(w["geo"]), zone_rect(g, zone)),
                  "%s on %s: window at %s, expected %s" % (zone, scr, w["geo"], zone_rect(g, zone)))


def s_cross_monitor_drag(sb_factory):
    """Start on one monitor, drop on the other monitor's popup."""
    with sb_factory(outputs=2) as sb:
        sb.open_window("W", 300, 300, 800, 500)
        g1 = screen_of(sb, "Virtual-1")
        p, o, w = snap_via_popup(sb, "W", titlebar(sb, "W"), (g1[0] + g1[2] / 2, 40), "left", "cross")
        check(near(rect(w["geo"]), zone_rect(g1, "left")),
              "window at %s, expected left half of Virtual-1 %s" % (w["geo"], zone_rect(g1, "left")))


def s_wide_window_off_centre(sb_factory):
    """A wide window grabbed near its right end: the cursor (and so the
    popup and the preview) is on monitor B while the window's centre is
    still on A. KWin tiles on the output under the window's centre
    (Window::handleQuickTileShortcut), so the snap must still follow the
    popup."""
    with sb_factory(outputs=2) as sb:
        g0, g1 = screen_of(sb, "Virtual-0"), screen_of(sb, "Virtual-1")
        sb.open_window("W", 0, 300, 2400, 600)
        grab = titlebar(sb, "W", dx=2150)          # 950 px right of the centre, clear of the buttons
        band = (g1[0] + g1[2] * 0.25 + 30, 40)     # just inside B's trigger band
        sb.drag([grab, (band[0], band[1] + 150), band], release=False)
        p = popup(sb)
        check(p is not None and contains(g1, p["geo"]["x"] + 5, p["geo"]["y"] + 5),
              "popup not on Virtual-1: %s" % (p and p["geo"]))
        sb.hover(*zone_point(p, "left"), ms=450)
        w = sb.window("W")
        centre = (w["geo"]["x"] + w["geo"]["w"] / 2, w["geo"]["y"] + w["geo"]["h"] / 2)
        check(contains(g0, *centre), "precondition: window centre %s should be on Virtual-0" % (centre,))
        o = overlay(sb)
        shot(sb, "wide-offcentre")
        sb.release()
        w = sb.window("W")
        check(o is not None and near(rect(o["geo"]), g1), "preview not on Virtual-1: %s" % (o and o["geo"]))
        check(near(rect(w["geo"]), zone_rect(g1, "left")),
              "the preview showed Virtual-1's left half %s, but the window was tiled at %s on %s"
              % (zone_rect(g1, "left"), w["geo"], w["output"]))


def _stacked(sb_factory, upper_is_1):
    with sb_factory(outputs=2) as sb:
        if upper_is_1:
            sb.layout(**{"Virtual-1": {"pos": (0, 0)}, "Virtual-0": {"pos": (0, 1080)}})
        else:
            sb.layout(**{"Virtual-0": {"pos": (0, 0)}, "Virtual-1": {"pos": (0, 1080)}})
        upper, lower = ("Virtual-1", "Virtual-0") if upper_is_1 else ("Virtual-0", "Virtual-1")
        gu, gl = screen_of(sb, upper), screen_of(sb, lower)
        sb.open_window("W", gl[0] + 300, gl[1] + 300, 800, 500)
        # Grab and move a little on the lower screen: the popup maps retracted.
        grab = titlebar(sb, "W")
        sb.drag([grab, (grab[0] + 40, grab[1] + 40)], release=False, hold_ms=300)
        p = popup(sb)
        check(p is not None, "setup: popup is not mapped at grab time")
        pg = rect(p["geo"])
        on_upper = pg[1] < gu[1] + gu[3] and pg[1] + pg[3] > gu[1]
        shot(sb, "stacked-retracted-%s" % ("upper1" if upper_is_1 else "upper0"))
        check(not on_upper, "retracted popup %s is visible on the upper monitor %s %s"
              % (pg, upper, gu))
        # Outer band (beyond showDistance): no peek here, nothing on the upper monitor.
        sb.hover(gl[0] + gl[2] / 2, gl[1] + 120, ms=300)
        shot(sb, "stacked-outer-band-%s" % ("upper1" if upper_is_1 else "upper0"))
        check(upper not in popup_on_screen(sb), "popup shows on the upper monitor while peeking")
        # Inner band: the popup drops in, on the lower monitor only, and does
        # not slide there across the upper one (sampled during the 150 ms
        # the slide would take).
        sb.pointer.move(gl[0] + gl[2] / 2, gl[1] + 40)
        seen = set()
        end = time.time() + 0.35
        while time.time() < end:
            seen.update(popup_on_screen(sb))
        check(upper not in seen, "popup crossed the upper monitor while dropping in")
        shown = popup_on_screen(sb)
        check(shown == [lower], "expanded popup on %s, expected only %s" % (shown, lower))
        sb.release()
        # A snap on the lower screen's top (shared) edge still targets the lower screen.
        sb.place("W", gl[0] + 300, gl[1] + 300, 800, 500)
        p, o, w = snap_via_popup(sb, "W", titlebar(sb, "W"), (gl[0] + gl[2] / 2, gl[1] + 40),
                                 "right", "stacked-snap")
        check(near(rect(w["geo"]), zone_rect(gl, "right")), "window at %s, expected %s"
              % (w["geo"], zone_rect(gl, "right")))


def s_stacked_lower_below(sb_factory):
    """Virtual-1 below Virtual-0: the popup for the lower screen must not
    show on the upper one while retracted or peeking."""
    _stacked(sb_factory, upper_is_1=False)


def s_stacked_lower_is_primary(sb_factory):
    _stacked(sb_factory, upper_is_1=True)


def s_cross_into_shared_edge(sb_factory):
    """A above L, R beside L with nothing above it. Crossing from R (free
    top edge) to L (shared) and back mid-drag: the parked popup must never
    be drawn on A, not even while switching screens."""
    with sb_factory(outputs=3) as sb:
        sb.layout(**{"Virtual-0": {"pos": (0, 0)}, "Virtual-1": {"pos": (0, 1080)},
                     "Virtual-2": {"pos": (1920, 1080)}})
        gl, gr = screen_of(sb, "Virtual-1"), screen_of(sb, "Virtual-2")
        sb.open_window("W", gr[0] + 300, gr[1] + 300, 800, 500)
        grab = titlebar(sb, "W")
        sb.drag([grab, (grab[0] + 40, grab[1] + 300)], release=False, hold_ms=200)
        seen = set()
        for x, y in ((gl[0] + 600, gl[1] + 700), (gr[0] + 600, gr[1] + 700), (gl[0] + 900, gl[1] + 500)):
            sb.pointer.move(x, y)
            end = time.time() + 0.3
            while time.time() < end:
                seen.update(popup_on_screen(sb))
        # and into L's band, where it drops in on L only
        sb.pointer.move(gl[0] + gl[2] / 2, gl[1] + 40)
        end = time.time() + 0.3
        while time.time() < end:
            seen.update(popup_on_screen(sb))
        shot(sb, "cross-into-shared")
        sb.release()
        check("Virtual-0" not in seen, "popup drawn on the upper monitor Virtual-0 while switching screens")


def s_top_panel(sb_factory):
    """A 44 px top panel on Virtual-1 only. While the drag is away from the
    top, the popup must not show over the panel; the band, the resting
    popup and the snaps respect the panel (MaximizeArea)."""
    with sb_factory(outputs=2) as sb:
        sb.open_panel(1, 44)
        g1 = screen_of(sb, "Virtual-1")
        a1 = sb.max_area("Virtual-1")
        sb.open_window("W", g1[0] + 300, 300, 800, 500)
        grab = titlebar(sb, "W")
        sb.drag([grab, (grab[0] + 40, grab[1] + 200)], release=False, hold_ms=300)
        shot(sb, "panel-retracted")
        hidden = popup_on_screen(sb)
        # Outer band: the peek sliver hangs off the real top edge, over the
        # panel (a sliver below the panel would need the popup's body to
        # cover the panel).
        sb.hover(g1[0] + g1[2] / 2, a1[1] + 120, ms=300)
        p = popup(sb)
        peek_bottom = p and p["geo"]["y"] + p["geo"]["h"]
        sb.release()
        check(not hidden, "retracted popup is visible (over the panel) on %s" % hidden)
        check(peek_bottom == g1[1] + 15, "peek: popup bottom at %s, expected %s" % (peek_bottom, g1[1] + 15))
        sb.place("W", g1[0] + 300, 300, 800, 500)
        p, o, w = snap_via_popup(sb, "W", titlebar(sb, "W"), (g1[0] + g1[2] / 2, a1[1] + 40),
                                 "topRight", "panel-snap")
        check(abs(p["geo"]["y"] - (a1[1] + 25)) <= 2, "resting popup at y=%s, expected %s (below the panel)"
              % (p["geo"]["y"], a1[1] + 25))
        check(near(rect(w["geo"]), zone_rect(a1, "topRight")),
              "W at %s, expected %s" % (w["geo"], zone_rect(a1, "topRight")))


def s_retracted_never_visible(sb_factory):
    """Plain side-by-side: during a drag away from the top the (mapped,
    retracted) popup covers no screen at all."""
    with sb_factory(outputs=2) as sb:
        for i, scr in enumerate(("Virtual-0", "Virtual-1")):
            g = screen_of(sb, scr)
            sb.open_window("W%d" % i, g[0] + 300, 300, 800, 500)
            grab = titlebar(sb, "W%d" % i)
            sb.drag([grab, (grab[0] + 60, grab[1] + 200)], release=False, hold_ms=300)
            hidden = popup_on_screen(sb)
            check(popup(sb) is not None, "setup: popup is not mapped at grab time on %s" % scr)
            sb.release()
            check(not hidden, "retracted popup visible on %s while dragging on %s" % (hidden, scr))


def s_peek_unchanged(sb_factory):
    """Where the top edge is free, the two-stage reveal is unchanged: a
    peekHeight sliver in the outer band, the resting popup topGap below
    the top within showDistance (reference: KZones-style reveal)."""
    with sb_factory(outputs=2) as sb:
        g1 = screen_of(sb, "Virtual-1")
        sb.open_window("W", g1[0] + 300, 300, 800, 500)
        grab = titlebar(sb, "W")
        sb.drag([grab, (g1[0] + g1[2] / 2, 300), (g1[0] + g1[2] / 2, 120)], release=False, hold_ms=300)
        p = popup(sb)
        check(p is not None and p["geo"]["y"] + p["geo"]["h"] == g1[1] + 15,
              "peek: popup bottom at %s, expected %s" % (p and p["geo"]["y"] + p["geo"]["h"], g1[1] + 15))
        sb.hover(g1[0] + g1[2] / 2, 40, ms=300)
        p = popup(sb)
        check(p["geo"]["y"] == g1[1] + 25, "rest: popup at y=%s, expected %s" % (p["geo"]["y"], g1[1] + 25))
        sb.release()


def s_no_shadow_line(sb_factory):
    """Nothing of the retracted popup, not even its theme shadow (drawn
    outside the window), may show along the top edge: single monitor, and
    the topmost monitor of a stacked pair where the lower one parks."""
    with sb_factory(outputs=2) as sb:
        sb.layout(**{"Virtual-0": {"pos": (0, 0)}, "Virtual-1": {"pos": (0, 1080)}})
        for scr in ("Virtual-0", "Virtual-1"):
            g = screen_of(sb, scr)
            sb.open_window("W" + scr, g[0] + 300, g[1] + 300, 800, 500)
            grab = titlebar(sb, "W" + scr)
            sb.drag([grab, (grab[0] + 60, grab[1] + 250)], release=False, hold_ms=300)
            p = popup(sb)
            check(p is not None, "setup: popup not mapped at grab time on %s" % scr)
            px = p["geo"]["x"]
            a = sb.max_alpha(int(px) - 40, 0, int(px + p["geo"]["w"]) + 40, 30)
            shot(sb, "no-shadow-%s" % scr)
            sb.release()
            check(a == 0, "dragging on %s: popup shadow drawn at the top edge (alpha %d)" % (scr, a))
            sb.probe("win('W%s').closeWindow(); return 1" % scr)
            sb.settle(0.3)


def s_offset_heights(sb_factory):
    """Side-by-side but vertically offset monitors (B starts 300 px lower)."""
    with sb_factory(outputs=2) as sb:
        sb.layout(**{"Virtual-1": {"pos": (1920, 300)}})
        g1 = screen_of(sb, "Virtual-1")
        sb.open_window("W", 300, 300, 800, 500)
        p, o, w = snap_via_popup(sb, "W", titlebar(sb, "W"), (g1[0] + g1[2] / 2, g1[1] + 40),
                                 "topLeft", "offset")
        check(contains(g1, p["geo"]["x"] + 5, p["geo"]["y"] + 5), "popup not on Virtual-1: %s" % p["geo"])
        check(near(rect(w["geo"]), zone_rect(g1, "topLeft")),
              "window at %s, expected %s" % (w["geo"], zone_rect(g1, "topLeft")))


def s_mixed_scale(sb_factory):
    """Virtual-1 at 150 % scale (logical 1280x720)."""
    with sb_factory(outputs=2) as sb:
        sb.layout(**{"Virtual-1": {"scale": 1.5}})
        g1 = screen_of(sb, "Virtual-1")
        check(g1[2] == 1280, "scale not applied: %s" % (g1,))
        sb.open_window("W", 300, 300, 800, 500)
        p, o, w = snap_via_popup(sb, "W", titlebar(sb, "W"), (g1[0] + g1[2] / 2, g1[1] + 40),
                                 "bottom", "scale150")
        check(o is not None and near(rect(o["geo"]), g1), "overlay %s not covering %s" % (o and o["geo"], g1))
        check(near(rect(w["geo"]), zone_rect(g1, "bottom")),
              "window at %s, expected %s" % (w["geo"], zone_rect(g1, "bottom")))


def s_three_monitors_sweep(sb_factory):
    """Sweep across three monitors mid-drag, back and forth, then snap on
    the middle one: retargeting never leaves a stale popup or selection."""
    with sb_factory(outputs=3) as sb:
        gs = [screen_of(sb, "Virtual-%d" % i) for i in range(3)]
        sb.open_window("W", 300, 300, 800, 500)
        grab = titlebar(sb, "W")
        path = [grab] + [(g[0] + g[2] / 2, 40) for g in (gs[0], gs[2], gs[0], gs[1])]
        sb.drag(path, release=False, steps=20)
        p = popup(sb)
        check(p is not None and contains(gs[1], p["geo"]["x"] + 5, p["geo"]["y"] + 5),
              "popup not on the middle monitor: %s" % (p and p["geo"]))
        sb.hover(*zone_point(p, "right"), ms=450)
        shot(sb, "three-sweep")
        sb.release()
        w = sb.window("W")
        check(near(rect(w["geo"]), zone_rect(gs[1], "right")),
              "window at %s, expected %s" % (w["geo"], zone_rect(gs[1], "right")))
        check(popup(sb) is None and overlay(sb) is None, "popup/overlay left behind after the drop")


def s_grid_is_per_monitor(sb_factory):
    """A custom quick-tile split on monitor A must not leak into B's preview."""
    with sb_factory(outputs=2) as sb:
        g0, g1 = screen_of(sb, "Virtual-0"), screen_of(sb, "Virtual-1")
        sb.open_window("A", 300, 300, 800, 500)
        snap_via_popup(sb, "A", titlebar(sb, "A"), (g0[0] + g0[2] / 2, 40), "left", "grid-a")
        # Move A's split to 70 % (resize the tiled window's right edge).
        sb.probe("var t = win('A').tile; t.resizeByPixels(%d, 4 /* Qt.RightEdge */); return 1"
                 % int(g0[2] * 0.2))
        sb.settle(0.3)
        a = sb.window("A")
        sb.open_window("B", 300, 600, 700, 400)
        sb.new_log()
        p, o, w = snap_via_popup(sb, "B", titlebar(sb, "B"), (g1[0] + g1[2] / 2, 40), "left", "grid-b")
        grid = [l for l in sb.new_log().splitlines() if "grid h=" in l and "Virtual-1" in l]
        check(grid and "h=0.500" in grid[-1], "Virtual-1 grid not default: %s (A tiled at %s)" % (grid, a["geo"]))
        check(near(rect(w["geo"]), zone_rect(g1, "left")), "B at %s, expected %s"
              % (w["geo"], zone_rect(g1, "left")))


def s_per_output_desktops(sb_factory):
    """Per-monitor virtual desktops: B shows desktop 2 while A shows desktop 1.
    B's quick tiles (split 0.65 on desktop 2) drive the preview there, and
    the dropped window ends up on desktop 2, tiled on B."""
    with sb_factory(outputs=2, desktops=2, windows_config={"PerOutputVirtualDesktops": "true"}) as sb:
        g0, g1 = screen_of(sb, "Virtual-0"), screen_of(sb, "Virtual-1")
        sb.probe("var d = workspace.desktops; workspace.setCurrentDesktopForScreen(d[1], "
                 "workspace.screens[1]); return 1")
        sb.settle(0.3)
        st = sb.state()
        check([s["desktop"] for s in st["screens"]] == ["Desktop 1", "Desktop 2"],
              "desktops per screen: %s" % [s["desktop"] for s in st["screens"]])
        # A window quick-tiled on B / desktop 2 with a 65 % split.
        sb.open_window("T", g1[0] + 300, 300, 700, 400)
        check(sb.window("T")["desktops"] == ["Desktop 2"], "setup: T not on Desktop 2")
        snap_via_popup(sb, "T", titlebar(sb, "T"), (g1[0] + g1[2] / 2, 40), "left", "pod-t")
        sb.probe("win('T').tile.resizeByPixels(%d, 4 /* Qt.RightEdge */); return 1" % int(g1[2] * 0.15))
        sb.settle(0.3)
        t = sb.window("T")
        h = round(t["geo"]["w"] / g1[2], 2)
        # Now drag a window from A (desktop 1) to B.
        sb.open_window("W", 300, 300, 800, 500)
        sb.new_log()
        p, o, w = snap_via_popup(sb, "W", titlebar(sb, "W"), (g1[0] + g1[2] * 0.6, 40),
                                 "right", "pod-w", h=h)
        grid = [l for l in sb.new_log().splitlines() if "grid h=" in l and "Virtual-1" in l]
        check(grid and ("h=%.3f" % h)[:5] in grid[-1],
              "B's grid not used (expected h=%.2f): %s" % (h, grid))
        check(near(rect(w["geo"]), zone_rect(g1, "right", h=h), tol=3),
              "W at %s, expected %s" % (w["geo"], zone_rect(g1, "right", h=h)))
        check(w["desktops"] == ["Desktop 2"], "W on desktops %s, expected Desktop 2" % w["desktops"])


def s_per_output_wide_off_centre(sb_factory):
    """Per-monitor desktops (A: 1, B: 2) and a wide window on A grabbed on
    its part over B. Clicking it makes A KWin's active output, so the
    "current desktop" is A's. B's own quick tiles (65 % split, desktop 2)
    must still drive the preview, and the snapped window must end up tiled
    on B and visible there (on desktop 2), not left on desktop 1."""
    with sb_factory(outputs=2, desktops=2, windows_config={"PerOutputVirtualDesktops": "true"}) as sb:
        g1 = screen_of(sb, "Virtual-1")
        sb.probe("workspace.setCurrentDesktopForScreen(workspace.desktops[1], workspace.screens[1]); return 1")
        sb.settle(0.3)
        sb.open_window("T", g1[0] + 300, 300, 700, 400)
        snap_via_popup(sb, "T", titlebar(sb, "T"), (g1[0] + g1[2] / 2, 40), "left", "pow-t")
        sb.probe("win('T').tile.resizeByPixels(%d, 4 /* Qt.RightEdge */); return 1" % int(g1[2] * 0.15))
        sb.settle(0.3)
        h = round(sb.window("T")["geo"]["w"] / g1[2], 2)
        sb.open_window("W", 0, 300, 2400, 600)
        check(sb.window("W")["desktops"] == ["Desktop 1"], "setup: W not on Desktop 1")
        sb.new_log()
        grab = titlebar(sb, "W", dx=2150)
        band = (g1[0] + g1[2] * 0.25 + 30, 40)
        sb.drag([grab, (band[0], band[1] + 150), band], release=False)
        p = popup(sb)
        check(p is not None, "popup not shown")
        sb.hover(*zone_point(p, "right", h=h), ms=450)
        w = sb.window("W")
        centre = (w["geo"]["x"] + w["geo"]["w"] / 2, w["geo"]["y"] + w["geo"]["h"] / 2)
        check(not contains(g1, *centre), "precondition: W's centre %s should be off Virtual-1" % (centre,))
        shot(sb, "pow-wide")
        sb.release()
        time.sleep(0.3)
        grid = [l for l in sb.new_log().splitlines() if "grid h=" in l and "Virtual-1" in l]
        w = sb.window("W")
        check(grid and ("h=%.3f" % h)[:5] in grid[-1], "B's grid not used (expected h=%.2f): %s" % (h, grid))
        check(near(rect(w["geo"]), zone_rect(g1, "right", h=h), tol=3),
              "W at %s on %s, expected %s on Virtual-1" % (w["geo"], w["output"], zone_rect(g1, "right", h=h)))
        check(w["desktops"] == ["Desktop 2"], "W on %s, but Virtual-1 shows Desktop 2" % w["desktops"])


def s_desktop_switch_other_monitor(sb_factory):
    """Per-monitor desktops: switching the desktop of the *other* monitor
    mid-drag must not blink the overlay off. A 500 ms dwell makes a
    retarget unmistakable: it would keep the overlay off for half a second."""
    with sb_factory(outputs=2, desktops=2, windows_config={"PerOutputVirtualDesktops": "true"},
                    script_config={"highlightDelay": "500"}) as sb:
        g1 = screen_of(sb, "Virtual-1")
        sb.open_window("W", g1[0] + 300, 300, 800, 500)
        sb.drag([titlebar(sb, "W"), (g1[0] + g1[2] / 2, 190), (g1[0] + g1[2] / 2, 40)], release=False)
        p = popup(sb)
        sb.hover(*zone_point(p, "left"), ms=800)
        check(overlay(sb) is not None, "setup: overlay not engaged")
        sb.probe("workspace.setCurrentDesktopForScreen(workspace.desktops[1], workspace.screens[0]); return 1")
        gone = [overlay(sb) is None for _ in range(3)]
        sb.release()
        check(not any(gone), "overlay on Virtual-1 went off when Virtual-0 switched desktop")


def s_hotplug_mid_drag(sb_factory):
    """The monitor under the drag is disabled mid-drag: nothing may stick."""
    with sb_factory(outputs=2) as sb:
        g1 = screen_of(sb, "Virtual-1")
        sb.open_window("W", g1[0] + 300, 300, 800, 500)
        sb.drag([titlebar(sb, "W"), (g1[0] + g1[2] / 2, 190), (g1[0] + g1[2] / 2, 40)], release=False)
        p = popup(sb)
        sb.hover(*zone_point(p, "left"), ms=450)
        sb.layout(**{"Virtual-1": {"enabled": False}})
        sb.pointer.move(960, 500)
        time.sleep(0.3)
        sb.release()
        time.sleep(0.5)
        st = sb.state()
        check(popup(sb) is None and overlay(sb) is None, "popup/overlay stuck after hotplug")
        check(sb.probe("return 1")["result"] == 1, "KWin unresponsive")
        # A normal snap still works afterwards on the remaining screen.
        g0 = screen_of(sb, "Virtual-0")
        sb.place("W", 300, 300, 800, 500)
        p, o, w = snap_via_popup(sb, "W", titlebar(sb, "W"), (g0[2] / 2, 40), "right", "hotplug-after")
        check(near(rect(w["geo"]), zone_rect(g0, "right")), "after hotplug: W at %s" % w["geo"])
        errs = [l for l in sb.log_text().splitlines() if "kde-snap-overlay" in l and
                ("TypeError" in l or "ReferenceError" in l or "Error:" in l)]
        check(not errs, "script errors: %s" % errs[:3])
        del st


def s_meta_drag_cross(sb_factory):
    """Meta+drag (no activation) across monitors."""
    with sb_factory(outputs=2) as sb:
        g1 = screen_of(sb, "Virtual-1")
        sb.open_window("X", 1000, 600, 500, 300)       # stays active
        sb.open_window("W", 300, 300, 800, 500)
        sb.probe("workspace.activeWindow = win('X'); return 1")
        mid = (300 + 400, 300 + 250)
        p, o, w = snap_via_popup(sb, "W", mid, (g1[0] + g1[2] / 2, 40), "bottomLeft", "meta", meta=True)
        check(near(rect(w["geo"]), zone_rect(g1, "bottomLeft")),
              "W at %s, expected %s" % (w["geo"], zone_rect(g1, "bottomLeft")))


SCENARIOS = [
    s_side_by_side_each_screen,
    s_cross_monitor_drag,
    s_wide_window_off_centre,
    s_stacked_lower_below,
    s_stacked_lower_is_primary,
    s_cross_into_shared_edge,
    s_top_panel,
    s_retracted_never_visible,
    s_peek_unchanged,
    s_no_shadow_line,
    s_offset_heights,
    s_mixed_scale,
    s_three_monitors_sweep,
    s_grid_is_per_monitor,
    s_per_output_desktops,
    s_per_output_wide_off_centre,
    s_desktop_switch_other_monitor,
    s_hotplug_mid_drag,
    s_meta_drag_cross,
]


def main():
    global SHOTS
    ap = argparse.ArgumentParser()
    ap.add_argument("-k", default="")
    ap.add_argument("--shots")
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    SHOTS = Path(a.shots) if a.shots else None

    def factory(**kw):
        return Sandbox(keep=a.keep, **kw)

    failed = 0
    for s in SCENARIOS:
        if a.k not in s.__name__:
            continue
        t = time.time()
        try:
            s(factory)
            print("PASS  %-36s %5.1fs" % (s.__name__, time.time() - t), flush=True)
        except Fail as e:
            failed += 1
            print("FAIL  %-36s %5.1fs  %s" % (s.__name__, time.time() - t, e), flush=True)
        except Exception:
            failed += 1
            print("ERROR %-36s %5.1fs\n%s" % (s.__name__, time.time() - t, traceback.format_exc()), flush=True)
    print(json.dumps({"failed": failed}))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
