// Drag/drop lifecycle: extracts the real Dialog-level functions from
// contents/ui/main.qml and drives them against a fake KWin (Workspace,
// windows with connectable signals, timers, an activation policy). Each
// scenario guards a behaviour verified against KWin's source; see
// docs/kwin-notes.md. QML bindings are modelled as plain variables.
//
// KSO_ROOT=/path/to/copy runs the suite against another checkout (handy for
// mutation-testing a change: break the code, confirm a test fails).
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import assert from 'node:assert/strict'

const ROOT = process.env.KSO_ROOT || fileURLToPath(new URL('..', import.meta.url))
const qml = readFileSync(ROOT + '/contents/ui/main.qml', 'utf8')
const logicSrc = readFileSync(ROOT + '/contents/code/main.js', 'utf8').replace(/^\s*\.pragma library.*$/m, '')

// Dialog-level functions are declared at 4-space indent in main.qml.
function extract(src) {
    const out = {}
    const re = /^    function (\w+)\(([^)]*)\) \{/gm
    let m
    while ((m = re.exec(src))) {
        const start = m.index + m[0].length - 1
        let depth = 0
        let end = -1
        for (let i = start; i < src.length; i++) {
            if (src[i] === '{') depth++
            else if (src[i] === '}' && --depth === 0) { end = i; break }
        }
        out[m[1]] = `function ${m[1]}(${m[2]}) ${src.slice(start, end + 1)}`
    }
    return out
}
const fns = extract(qml)
for (const n of ['startup', 'connectSignal', 'screenAt', 'screenForCursor', 'refreshScreenArea', 'connectWindow',
    'onDragStarted', 'retarget', 'onDesktopChanged', 'pointInRect', 'clearZoneState', 'onTick', 'resetDrag',
    'onDrop', 'onWindowRemoved', 'onCommit', 'findQuickTiles', 'zoneRect', 'tileEdge', 'desktopFor',
    'moveToScreen']) {
    assert.ok(fns[n], 'harness drift: main.qml no longer defines ' + n)
}

const signal = () => {
    const hs = []
    return { connect: (f) => hs.push(f), emit: (...a) => hs.slice().forEach((f) => f(...a)), hs }
}
const mkOutput = (name, x, y, w, h) => ({ name, geometry: { x, y, width: w, height: h } })

const D1 = { id: 'd1' }
const D2 = { id: 'd2' }

// perOutputDesktops: { screenName: desktop } enables KWin 6.7's
// currentDesktopForScreen (absent before 6.7); Workspace.currentDesktop
// stays the active output's (D1).
function runtime({ screens = [mkOutput('A', 0, 0, 1920, 1080)], config = {}, perOutputDesktops = null } = {}) {
    const calls = []
    const logs = []
    const timer = () => ({ running: false, start() { this.running = true }, stop() { this.running = false },
        restart() { this.running = true } })
    const Workspace = {
        screens, stackingOrder: [], cursorPos: { x: 960, y: 500 }, currentDesktop: D1,
        windowAdded: signal(), windowRemoved: signal(), currentDesktopChanged: signal(),
        _active: null, refuseActivation: false, clientAreaDesktops: [],
        get activeWindow() { return this._active },
        set activeWindow(w) { if (!this.refuseActivation) this._active = w },
        clientArea(_area, screen, desktop) {
            this.clientAreaDesktops.push(desktop)
            return { ...screen.geometry }
        },
        // Window::sendToOutput: keeps the relative position (moveToArea),
        // then finishInteractiveOutputChange: with per-output desktops, a
        // window not on the new output's desktop swaps the old output's
        // desktop for it.
        sendClientToScreen(w, screen) {
            calls.push({ send: screen.name, window: w })
            const from = w.output
            const to = screen.geometry
            w.x = to.x + (w.x - from.geometry.x) * to.width / from.geometry.width
            w.y = to.y + (w.y - from.geometry.y) * to.height / from.geometry.height
            w.output = screen
            if (this.currentDesktopForScreen && w.desktops.length) {
                const now = this.currentDesktopForScreen(screen)
                const before = this.currentDesktopForScreen(from)
                if (!w.desktops.includes(now) && now !== before) {
                    w.desktops = w.desktops.filter((d) => d !== before).concat([now])
                }
            }
        },
    }
    if (perOutputDesktops) {
        Workspace.currentDesktopForScreen = (screen) => perOutputDesktops[screen.name] || D1
    }
    // KWin's slots tile the *active* window (Workspace::quickTileWindow).
    for (const z of ['Left', 'Right', 'Top', 'Bottom', 'TopLeft', 'TopRight', 'BottomLeft', 'BottomRight']) {
        Workspace['slotWindowQuickTile' + z] = () => calls.push({ slot: z, window: Workspace._active })
    }
    const env = new Function('Workspace', 'KWin', 'Qt', 'console', 'timers', 'readConfig', `
        ${logicSrc}
        var Logic = { LAYOUTS: LAYOUTS, zoneRectFrac: zoneRectFrac, zoneIndexInLayout: zoneIndexInLayout,
                      zoneSlot: zoneSlot, zoneRectInPopup: zoneRectInPopup, hitTestZones: hitTestZones,
                      quickTilesOf: quickTilesOf, clampNumber: clampNumber, revealPositions: revealPositions };
        var pad = 14, cardW = 130, cardH = 70, gap = 10;
        var activationDistance = Logic.clampNumber(readConfig("activationDistance", 150), 150, 100, 400);
        var topGap = Logic.clampNumber(readConfig("topGap", 25), 25, 0, Math.max(activationDistance - (pad + cardH), 0));
        var showDistance = Logic.clampNumber(readConfig("showDistance", 75), 75, topGap + 10,
                                             Math.max(activationDistance - 10, topGap + 10));
        var edgeGapRatio = Logic.clampNumber(readConfig("edgeGapRatio", 0.25), 0.25, 0, 0.5);
        var highlightDelay = 150, debugLog = true, compensateLeft = 0, compensateTop = 0;
        var screenArea = { x: 0, y: 0, width: 1920, height: 1080 };
        var screenGeometry = { x: 0, y: 0, width: 1920, height: 1080 }, otherScreens = [], switchingScreen = false;
        // edgeGap is a binding on screenArea in main.qml.
        Object.defineProperty(globalThis, 'edgeGap', { configurable: true,
            get: function () { return screenArea.width * edgeGapRatio } });
        var dragging = false, fullZone = false, retracted = true, visible = false;
        var highlightedZone = "", overlayZone = "", dwellCandidate = "", pendingZone = "", pendingWindow = null;
        var pendingScreen = null;
        var dropHandled = false, dragStartPos = { x: 0, y: 0 }, dragWindow = null, dragScreen = null, quickTiles = null;
        var hSplit = 0.5, vSplit = 0.5;
        var pollTimer = timers.poll, commitTimer = timers.commit, dwellTimer = timers.dwell, hideTimer = timers.hide;
        var zoneSelector = { width: 438, height: 98, mapToGlobal: function () {
            return { x: screenArea.x + Math.floor((screenArea.width - 438) / 2), y: screenArea.y + topGap } } };
        ${Object.values(fns).join('\n')}
        return { get: function (k) { return eval(k) }, startup: startup, onTick: onTick, onCommit: onCommit,
                 desktopFor: desktopFor };
    `)
    const timers = { poll: timer(), commit: timer(), dwell: timer(), hide: timer() }
    const readConfig = (k, d) => (k in config ? config[k] : d)
    const rt = env.call({}, Workspace, { MaximizeArea: 2 },
        { rect: (x, y, w, h) => ({ x, y, width: w, height: h }), point: (x, y) => ({ x, y }) },
        { info: (...a) => logs.push(a.join(' ')) }, timers, readConfig)
    return { rt, Workspace, calls, logs, timers }
}

let windowIds = 0
function mkWindow(W, { x = 300, y = 300, width = 800, height = 500, output, desktops = null } = {}) {
    const w = { id: ++windowIds, normalWindow: true, move: false, x, y, width, height,
        output: output || W.screens[0], tile: null,
        onAllDesktops: !desktops, desktops: desktops || [],
        get frameGeometry() { return { x: this.x, y: this.y, width: this.width, height: this.height } },
        interactiveMoveResizeStarted: signal(), interactiveMoveResizeFinished: signal(),
        requestedTileChanged: signal(), maximizedAboutToChange: signal(), frameGeometryChanged: signal() }
    W.stackingOrder.push(w)
    return w
}

// Cursor over the topRight zone of the third (quadrants) card.
function overTopRight(rt) {
    const sa = rt.get('screenArea')
    const gx = sa.x + Math.floor((sa.width - 438) / 2)
    return { x: gx + 14 + 2 * 140 + 100, y: sa.y + rt.get('topGap') + 14 + 10 }
}

function dragOntoCard(env, w, { active = true } = {}) {
    const { rt, Workspace } = env
    if (active) Workspace._active = w
    w.move = true
    w.interactiveMoveResizeStarted.emit()
    Workspace.cursorPos = { x: 960, y: 600 }
    w.x = 700
    w.y = 400
    w.frameGeometryChanged.emit()
    Workspace.cursorPos = overTopRight(rt)
    rt.onTick()
    rt.onTick()
    assert.equal(rt.get('highlightedZone'), 'topRight')
}
// dragOntoCard on the screen under the current cursor position.
function dragOntoCardOn(env, w) {
    const { rt, Workspace } = env
    Workspace._active = w
    w.move = true
    w.interactiveMoveResizeStarted.emit()
    Workspace.cursorPos = overTopRight(rt)
    rt.onTick()
    rt.onTick()
    assert.equal(rt.get('highlightedZone'), 'topRight')
}

// KWin's finish: move goes false, any restore/tiling happens, then the signal.
const finish = (w, kwinActions) => {
    w.move = false
    if (kwinActions) kwinActions()
    w.interactiveMoveResizeFinished.emit()
}
const fireCommit = (env) => {
    if (env.timers.commit.running) {
        env.timers.commit.running = false
        env.rt.onCommit()
    }
}
const setup = (opts) => {
    const env = runtime(opts)
    env.rt.startup()
    return env
}
const addWindow = (env, opts) => {
    const w = mkWindow(env.Workspace, opts)
    env.Workspace.windowAdded.emit(w)
    return w
}

test('normal hover + drop snaps the dropped window', () => {
    const env = setup()
    const w = addWindow(env)
    dragOntoCard(env, w)
    finish(w)
    fireCommit(env)
    assert.deepEqual(env.calls, [{ slot: 'TopRight', window: w }])
})

test('Escape cancel of a floating window (restored to its start position) does not snap', () => {
    const env = setup()
    const w = addWindow(env)
    dragOntoCard(env, w)
    finish(w, () => { w.x = 300; w.y = 300; w.frameGeometryChanged.emit() }) // moveResize(initialGeometry)
    fireCommit(env)
    assert.deepEqual(env.calls, [])
})

test('Escape cancel of a tiled / maximized window does not snap', () => {
    for (const sig of ['requestedTileChanged', 'maximizedAboutToChange']) {
        const env = setup()
        const w = addWindow(env)
        env.Workspace._active = w
        w.move = true
        w.interactiveMoveResizeStarted.emit()
        w[sig].emit() // untile/unmaximize on the first step: move still true, ignored
        env.Workspace.cursorPos = overTopRight(env.rt)
        env.rt.onTick()
        finish(w, () => w[sig].emit()) // cancel restores tile/maximize with move false
        fireCommit(env)
        assert.deepEqual(env.calls, [], sig)
    }
})

test('mid-drag untile (move still true) does not suppress a normal drop', () => {
    const env = setup()
    const w = addWindow(env)
    env.Workspace._active = w
    w.move = true
    w.interactiveMoveResizeStarted.emit()
    w.requestedTileChanged.emit()
    env.Workspace.cursorPos = overTopRight(env.rt)
    env.rt.onTick()
    finish(w)
    fireCommit(env)
    assert.equal(env.calls.length, 1)
})

test('KWin repositioning elsewhere at finish (not the start position) still snaps', () => {
    const env = setup()
    const w = addWindow(env)
    dragOntoCard(env, w)
    finish(w, () => { w.x = 1234; w.frameGeometryChanged.emit() })
    fireCommit(env)
    assert.equal(env.calls.length, 1)
})

test('Meta+drag of an inactive window activates it, then tiles it (not the active one)', () => {
    const env = setup()
    const other = mkWindow(env.Workspace)
    const w = addWindow(env)
    env.Workspace._active = other
    dragOntoCard(env, w, { active: false })
    finish(w)
    fireCommit(env)
    assert.deepEqual(env.calls, [{ slot: 'TopRight', window: w }])
})

test('a window refusing activation: nothing is tiled (never the wrong window)', () => {
    const env = setup()
    const other = mkWindow(env.Workspace)
    const w = addWindow(env)
    env.Workspace._active = other
    env.Workspace.refuseActivation = true
    dragOntoCard(env, w, { active: false })
    finish(w)
    fireCommit(env)
    assert.deepEqual(env.calls, [])
})

test('window closed during the commit delay: nothing is tiled', () => {
    const env = setup()
    const w = addWindow(env)
    dragOntoCard(env, w)
    finish(w)
    env.Workspace.windowRemoved.emit(w)
    fireCommit(env)
    assert.deepEqual(env.calls, [])
    assert.equal(env.timers.commit.running, false)
})

test('a new drag during the commit delay drops the stale snap', () => {
    const env = setup()
    const a = addWindow(env)
    const b = addWindow(env)
    dragOntoCard(env, a)
    finish(a)
    env.Workspace._active = b
    b.move = true
    b.interactiveMoveResizeStarted.emit()
    env.Workspace.cursorPos = { x: 960, y: 700 }
    env.rt.onTick()
    finish(b)
    fireCommit(env)
    assert.deepEqual(env.calls, [])
})

test('watchdog: a drag whose finish never arrives is ended without snapping', () => {
    const env = setup()
    const w = addWindow(env)
    dragOntoCard(env, w)
    w.move = false // finish signal lost
    env.rt.onTick()
    assert.equal(env.rt.get('dragging'), false)
    assert.equal(env.timers.poll.running, false)
    fireCommit(env)
    assert.deepEqual(env.calls, [])
})

test('multi-monitor: crossing to another screen retargets it; popup + snap work there', () => {
    const B = mkOutput('B', 1920, 0, 2560, 1440)
    const env = setup({ screens: [mkOutput('A', 0, 0, 1920, 1080), B] })
    const w = addWindow(env)
    dragOntoCard(env, w)
    env.Workspace.cursorPos = { x: 3000, y: 700 }
    env.rt.onTick()
    assert.equal(env.rt.get('dragScreen'), B)
    assert.deepEqual(env.rt.get('screenArea'), B.geometry)
    assert.equal(env.rt.get('highlightedZone'), '', 'old selection cleared on retarget')
    env.Workspace.cursorPos = overTopRight(env.rt)
    env.rt.onTick()
    assert.equal(env.rt.get('highlightedZone'), 'topRight')
    finish(w)
    fireCommit(env)
    // The (fake) window never left A, so it is sent to B before tiling.
    assert.deepEqual(env.calls, [{ send: 'B', window: w }, { slot: 'TopRight', window: w }])
    assert.ok(env.logs.some((l) => l.includes('screen=B')))
})

// KWin quick-tiles on the output under the window's centre, the popup
// follows the cursor (tests/kwin: s_wide_window_off_centre).
test('multi-monitor: a window whose centre is off the drop screen is sent there, then tiled', () => {
    const A = mkOutput('A', 0, 0, 1920, 1080)
    const B = mkOutput('B', 1920, 0, 1920, 1080)
    const env = setup({ screens: [A, B] })
    const w = addWindow(env, { width: 2400 })
    env.Workspace._active = w
    w.move = true
    w.interactiveMoveResizeStarted.emit()
    env.Workspace.cursorPos = { x: 2500, y: 600 }
    env.rt.onTick()
    w.x = 300                              // centre 1500: on A, cursor on B
    env.Workspace.cursorPos = overTopRight(env.rt)
    env.rt.onTick()
    finish(w)
    fireCommit(env)
    assert.deepEqual(env.calls, [{ send: 'B', window: w }, { slot: 'TopRight', window: w }])
    assert.equal(w.output, B)
})

test('multi-monitor: a window centred on the drop screen is not moved', () => {
    const A = mkOutput('A', 0, 0, 1920, 1080)
    const B = mkOutput('B', 1920, 0, 1920, 1080)
    const env = setup({ screens: [A, B] })
    const w = addWindow(env, { output: B, x: 2300 })
    env.Workspace.cursorPos = { x: 2500, y: 600 }
    dragOntoCardOn(env, w)
    finish(w)
    fireCommit(env)
    assert.deepEqual(env.calls, [{ slot: 'TopRight', window: w }])
})

test('multi-monitor: drop screen unplugged before the commit: tiled where it is, not sent', () => {
    const A = mkOutput('A', 0, 0, 1920, 1080)
    const B = mkOutput('B', 1920, 0, 1920, 1080)
    const env = setup({ screens: [A, B] })
    const w = addWindow(env)
    dragOntoCard(env, w)
    env.Workspace.cursorPos = { x: 2500, y: 600 }
    env.rt.onTick()
    env.Workspace.cursorPos = overTopRight(env.rt)
    env.rt.onTick()
    finish(w)
    env.Workspace.screens = [A]
    fireCommit(env)
    assert.deepEqual(env.calls, [{ slot: 'TopRight', window: w }])
})

test('per-output desktops: a window sent to the drop screen joins the desktop it shows', () => {
    const A = mkOutput('A', 0, 0, 1920, 1080)
    const B = mkOutput('B', 1920, 0, 1920, 1080)
    const D3 = { id: 'd3' }
    const env = setup({ screens: [A, B], perOutputDesktops: { A: D1, B: D2 } })
    const w = addWindow(env, { width: 2400, desktops: [D1, D3] })
    env.Workspace._active = w
    w.move = true
    w.interactiveMoveResizeStarted.emit()
    env.Workspace.cursorPos = { x: 2500, y: 600 }
    env.rt.onTick()
    w.x = 300
    env.Workspace.cursorPos = overTopRight(env.rt)
    env.rt.onTick()
    finish(w)
    fireCommit(env)
    assert.equal(env.calls[0].send, 'B')
    // KWin's own swap (finishInteractiveOutputChange): A's desktop for B's.
    assert.deepEqual(w.desktops, [D3, D2])
})

test('per-output desktops: a window already on the drop screen\'s desktop keeps all its desktops', () => {
    const A = mkOutput('A', 0, 0, 1920, 1080)
    const B = mkOutput('B', 1920, 0, 1920, 1080)
    const env = setup({ screens: [A, B], perOutputDesktops: { A: D1, B: D2 } })
    const w = addWindow(env, { width: 2400, desktops: [D1, D2] })
    env.Workspace._active = w
    w.move = true
    w.interactiveMoveResizeStarted.emit()
    env.Workspace.cursorPos = { x: 2500, y: 600 }
    env.rt.onTick()
    w.x = 300
    env.Workspace.cursorPos = overTopRight(env.rt)
    env.rt.onTick()
    finish(w)
    fireCommit(env)
    assert.equal(env.calls[0].send, 'B')
    assert.deepEqual(w.desktops, [D1, D2])
})

test('per-output desktops: the drag screen\'s own desktop is used, not the active output\'s', () => {
    const A = mkOutput('A', 0, 0, 1920, 1080)
    const B = mkOutput('B', 1920, 0, 1920, 1080)
    const env = setup({ screens: [A, B], perOutputDesktops: { A: D1, B: D2 } })
    env.Workspace.clientAreaDesktops.length = 0
    const w = addWindow(env, { output: B, x: 2300 })
    env.Workspace.cursorPos = { x: 2500, y: 600 }
    dragOntoCardOn(env, w)
    assert.equal(env.rt.get('dragScreen'), B)
    assert.equal(env.Workspace.clientAreaDesktops.at(-1), D2)
    assert.equal(env.rt.desktopFor(B), D2)
    assert.equal(env.rt.desktopFor(null), D1)
})

test('desktop switch mid-drag retargets and clears the selection', () => {
    const env = setup()
    const w = addWindow(env)
    dragOntoCard(env, w)
    const gridLogs = () => env.logs.filter((l) => l.includes('grid')).length
    const before = gridLogs()
    env.Workspace.currentDesktopChanged.emit()
    assert.equal(env.rt.get('highlightedZone'), '')
    assert.equal(gridLogs(), before + 1)
})

// KWin emits currentDesktopChanged(previous, current, output) per output
// (tests/kwin: s_desktop_switch_other_monitor).
test('desktop switch on another output mid-drag keeps the selection', () => {
    const A = mkOutput('A', 0, 0, 1920, 1080)
    const B = mkOutput('B', 1920, 0, 1920, 1080)
    const env = setup({ screens: [A, B] })
    const w = addWindow(env)
    dragOntoCard(env, w)
    env.Workspace.currentDesktopChanged.emit(D1, D2, B)
    assert.equal(env.rt.get('highlightedZone'), 'topRight')
    env.Workspace.currentDesktopChanged.emit(D1, D2, A)
    assert.equal(env.rt.get('highlightedZone'), '')
})

test('startup: a throwing window does not stop the others or windowAdded', () => {
    const env = runtime()
    const good = mkWindow(env.Workspace)
    env.Workspace.stackingOrder.unshift({ get normalWindow() { throw new Error('boom') } })
    env.rt.startup()
    assert.equal(env.Workspace.windowAdded.hs.length, 1)
    assert.equal(good.interactiveMoveResizeStarted.hs.length, 1)
    const late = mkWindow(env.Workspace)
    env.Workspace.windowAdded.emit(late)
    assert.equal(late.interactiveMoveResizeStarted.hs.length, 1)
})

test('bad config values fall back to defaults; valid ones clamp as before', () => {
    const bad = runtime({ config: { activationDistance: 'abc', edgeGapRatio: 'x', topGap: NaN } }).rt
    assert.equal(bad.get('activationDistance'), 150)
    assert.equal(bad.get('edgeGapRatio'), 0.25)
    assert.equal(bad.get('topGap'), 25)
    const ok = runtime({ config: { activationDistance: 999, showDistance: 5, topGap: 30 } }).rt
    assert.equal(ok.get('activationDistance'), 400)
    assert.equal(ok.get('showDistance'), 40)
})
