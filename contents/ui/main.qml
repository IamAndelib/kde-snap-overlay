import QtQuick
import org.kde.kwin
import org.kde.plasma.core as PlasmaCore
import "../code/main.js" as Logic
import "components" as Components

PlasmaCore.Dialog {
    id: popup
    visible: false
    type: PlasmaCore.Dialog.OnScreenDisplay
    location: PlasmaCore.Types.Desktop
    // Default background hints: the Plasma theme's dialog background with
    // theme translucency and KWin blur-behind — the system shell look. (Do
    // not assign PlasmaCore.Types.NormalBackground explicitly: KWin's
    // trimmed org.kde.plasma.core module does not define that enum value.)
    flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint
    hideOnWindowDeactivate: false
    outputOnly: true
    // The Dialog auto-sizes from the mainItem's implicit size (the standard
    // plasmashell pattern), so the window is born at the panel's size — no
    // empty-map races and no manual setWidth/setHeight.
    // Reveal via window position (two-stage, KZones-style): retracted = fully
    // above the screen, peek = bottom sliver on-screen, expanded = resting
    // offset below the top edge. The Behavior animates every transition and
    // the fly-out is the retracted position plus a delayed hide.
    x: screenArea.x + Math.floor((screenArea.width - width) / 2)
    y: retracted ? screenArea.y - height
        : (fullZone ? screenArea.y + topGap
                    : screenArea.y - height + peekHeight)
    Behavior on y {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    // ---- Configuration ----
    readonly property int activationDistance: Logic.clampNumber(KWin.readConfig("activationDistance", 150), 150, 100, 400)
    // topGap is the popup's resting offset below the top edge. The 25px
    // default replicates the old design's selector chrome — the panel top
    // sits 25px below the screen edge. Clamped so the whole card row (pad +
    // cardH below the popup top) always lands inside the band.
    readonly property int topGap: Logic.clampNumber(KWin.readConfig("topGap", 25), 25, 0, Math.max(activationDistance - (pad + cardH), 0))
    // Cursor distance from the screen top below which the popup fully drops
    // (two-stage KZones-style reveal: peek sliver beyond this, full panel
    // within it). Defaults to KZones' trigger distance
    // (zoneSelectorTriggerDistance 1 -> 1*50+25 = 75px).
    readonly property int showDistance: Logic.clampNumber(KWin.readConfig("showDistance", 75), 75,
        topGap + 10, Math.max(activationDistance - 10, topGap + 10))
    // Fraction of the screen width to ignore on each side of the trigger band,
    // so dragging to the corners (quarter-tile intent) doesn't open the popup.
    readonly property real edgeGapRatio: Logic.clampNumber(KWin.readConfig("edgeGapRatio", 0.25), 0.25, 0, 0.5)
    // Horizontal trigger margin on each side, derived from the current screen width.
    readonly property real edgeGap: screenArea.width * edgeGapRatio

    // ---- Overlay behavior (FancyZones' animation model) ----
    // Dwell time (ms) the cursor must rest on one zone before the fullscreen
    // overlay engages. The popup cards highlight instantly; only the big
    // screen overlay waits, so sweeping across the cards never pops it.
    // 0 = engage instantly (FancyZones' own behavior).
    readonly property int highlightDelay: Logic.clampNumber(KWin.readConfig("highlightDelay", 150), 150, 0, 500)
    // Fade-in duration (ms) of the overlay — FancyZones' FadeInDurationMillis
    // 200, a linear alpha ramp. This is the ONLY animation in the overlay:
    // upstream redraws zone switches instantly and hides instantly, and so
    // do we (the dip/slide/fade-out refinements kept reading as a blink).
    // 0 = instant.
    readonly property int overlayFadeIn: Logic.clampNumber(KWin.readConfig("overlayFadeIn", 200), 200, 0, 1000)
    // Alpha of the overlay's accent fill — FancyZones' highlightOpacity
    // (default 50). The border stays near-opaque; colors remain the live
    // Kirigami tokens.
    readonly property real highlightOpacity: Logic.clampNumber(KWin.readConfig("highlightOpacity", 50), 50, 5, 100) / 100
    // Journal diagnostics (grid source per drag/screen, overlay engage/
    // switch/map, skipped snaps), off by default. Read with:
    //   journalctl --user -b | grep kde-snap-overlay
    readonly property bool debugLog: KWin.readConfig("debugLog", false)

    // ---- Card / popup metrics (KZones indicator sizing) ----
    readonly property int cardW: 130
    readonly property int cardH: 70
    readonly property int gap: 10
    readonly property int pad: 14
    readonly property int popupH: cardH + 2 * pad
    // Visible sliver while the popup peeks: 15px matches the old design's
    // visible panel sliver (KZones showed 30px of selector = 15px of panel).
    readonly property int peekHeight: Logic.clampNumber(KWin.readConfig("peekHeight", 15), 15, 10, popupH - 20)

    // ---- State ----
    property rect screenArea: Qt.rect(0, 0, 1920, 1080)
    property bool dragging: false
    // Cursor within showDistance of the screen top: the selector is fully
    // expanded; hovering the selector also keeps it expanded (KZones).
    property bool fullZone: false
    // Fly-out / fully-retracted state: the panel sits fully above the screen
    // edge (retracted position), inside the still-visible dialog.
    property bool retracted: true
    // Own static zone outline: the full-screen click-through overlay below
    // mirrors the native KWin outline look while a zone is hovered. Unlike
    // KWin's shared Outline — which the interactive-move code hides on every
    // motion step of the drag, tearing the visual's platform window down —
    // this is our window, so it stays up without churn while the cursor
    // moves. Screen-space rect of the highlighted zone; a plain binding, so
    // it only changes when the zone, the grid splits or the screen do.
    readonly property rect zoneOutlineRect: zoneRect(highlightedZone)

    // Theme dialog frames have asymmetric shadow borders (heavier at the
    // bottom/right). Compensate the content insets by half the difference
    // so the cards stay optically centered in the window. Guarded: falls
    // back to 0 if the margins property is not exposed on this build.
    readonly property real compensateTop: {
        try {
            return Math.max(0, (popup.margins.bottom - popup.margins.top) / 2)
        } catch (e) {
            return 0
        }
    }
    readonly property real compensateLeft: {
        try {
            return Math.max(0, (popup.margins.right - popup.margins.left) / 2)
        } catch (e) {
            return 0
        }
    }

    // Hovered zone id (member of one of the three layouts), "" when none.
    property string highlightedZone: ""
    // Dwell-gated zone driving the fullscreen overlay (FancyZones' model:
    // cards highlight instantly, but the screen overlay only engages after
    // the cursor has rested highlightDelay on the same zone). Cleared as
    // soon as the cursor leaves the zone or the drag ends.
    property string overlayZone: ""
    // Zone the cursor is currently resting on, awaiting the dwell timer.
    property string dwellCandidate: ""
    // Zone chosen on drop and the dropped window, applied by commitTimer
    // once KWin has committed the drop.
    property string pendingZone: ""
    property var pendingWindow: null
    // Set while a drop is being finished if KWin itself handled it — a
    // cancelled move (Escape) putting the window back, or KWin's own edge
    // tiling/maximize — so the popup never snaps on top of that.
    property bool dropHandled: false
    // Where the dragged window was when the drag started; a cancelled move
    // restores it there.
    property point dragStartPos: Qt.point(0, 0)
    // Window being dragged right now; used to abort a stuck drag if it is
    // closed without ever finishing the move.
    property var dragWindow: null
    // Output the drag happens on; the tile tree is per-output/per-desktop.
    property var dragScreen: null

    // KWin's eight quick tiles for the drag's screen and desktop, keyed by
    // zone id (Logic.quickTilesOf), or null when no window there is
    // quick-tiled. Found at drag start; kept after the drop so the cards do
    // not jump back to the default grid during the fly-out.
    property var quickTiles: null

    // Current quick-tile grid splits (relative to the screen), read live
    // from KWin's own tiles. relativeGeometry notifies, so a split that
    // changes mid-drag (e.g. KWin resetting the grid when the dragged window
    // leaves its tile) updates the cards and the overlay at once. 0.5/0.5 is
    // the default grid — also what KWin resets to once nothing is
    // quick-tiled.
    readonly property real hSplit: tileEdge(quickTiles ? quickTiles.left : null, true)
    readonly property real vSplit: tileEdge(quickTiles ? quickTiles.top : null, false)

    onOverlayZoneChanged: {
        // Diagnostic only: upstream switches zones by redrawing the scene
        // instantly — there is no transition to trigger here.
        if (debugLog && overlayZone !== "" && zoneOverlay.engaged) {
            console.info("[kde-snap-overlay] overlay switch ->", overlayZone,
                "rect", JSON.stringify(zoneOutlineRect))
        }
    }

    // Right (horizontal) or bottom edge of a quick tile's relative geometry;
    // 0.5 when the tile is unavailable (none found, or destroyed with its
    // output).
    function tileEdge(tile, horizontal) {
        var g = tile ? tile.relativeGeometry : null
        if (!g) {
            return 0.5
        }
        return horizontal ? g.x + g.width : g.y + g.height
    }

    // The screen-space region a zone snaps to: the zone's own quick tile's
    // absoluteGeometry — exactly the rect KWin's quick tiling moves the
    // window to (quick tiles have no padding). Without quick tiles, the
    // default-grid math on the drag's screen. Zero rect for "" (no zone).
    // (Window.quickTileGeometry() is not scriptable: protected, not
    // Q_INVOKABLE.)
    function zoneRect(zoneId) {
        var tile = quickTiles ? quickTiles[zoneId] : null
        var g = tile ? tile.absoluteGeometry : null
        if (g && g.width > 0 && g.height > 0) {
            return Qt.rect(g.x, g.y, g.width, g.height)
        }
        var f = Logic.zoneRectFrac(zoneId, hSplit, vSplit)
        if (f.fw === 0 && f.fh === 0) {
            return Qt.rect(0, 0, 0, 0)
        }
        return Qt.rect(
            screenArea.x + screenArea.width * f.fx,
            screenArea.y + screenArea.height * f.fy,
            screenArea.width * f.fw,
            screenArea.height * f.fh)
    }

    // Find KWin's quick tiles for the drag's screen and current desktop.
    // Scripts cannot reach the quick-tile root directly (Workspace.rootTile()
    // is the custom-tiling root), so it is reached through any window that
    // is quick-tiled there: its tile's parent is the root holding all eight
    // tiles. Windows in a custom (Meta+T) layout are skipped. null when no
    // window qualifies.
    function findQuickTiles() {
        try {
            var wins = Workspace.stackingOrder
            var desktopId = Workspace.currentDesktop ? Workspace.currentDesktop.id : null
            for (var i = 0; i < wins.length; i++) {
                var w = wins[i]
                if (!w || !w.normalWindow || !w.tile) {
                    continue
                }
                if (desktopId !== null && !w.onAllDesktops && w.desktops) {
                    var onCurrent = false
                    for (var k = 0; k < w.desktops.length; k++) {
                        if (w.desktops[k].id === desktopId) {
                            onCurrent = true
                            break
                        }
                    }
                    if (!onCurrent) {
                        continue
                    }
                }
                if (dragScreen && (!w.output || w.output !== dragScreen)) {
                    continue
                }
                var tiles = Logic.quickTilesOf(w.tile)
                if (tiles) {
                    return tiles
                }
            }
        } catch (e) {
            // Tile tree not reachable here: use the default grid.
        }
        return null
    }

    Component.onCompleted: startup()

    // Workspace signals are connected first, and every existing window is
    // hooked up on its own, so a surprise from one window (or an API
    // difference) can never leave the script deaf to new windows.
    // windowRemoved: a window closed mid-drag (before the move ever
    // finishes) must not leave the popup and poll stuck.
    function startup() {
        connectSignal(Workspace, "windowAdded", connectWindow)
        connectSignal(Workspace, "windowRemoved", onWindowRemoved)
        connectSignal(Workspace, "currentDesktopChanged", onDesktopChanged)
        var order = Workspace.stackingOrder
        for (var i = 0; i < order.length; i++) {
            connectWindow(order[i])
        }
        try {
            refreshScreenArea()
        } catch (e) {
            // Refreshed again at every drag start.
        }
    }

    // Connect a handler to obj's signal `name`; false (never a throw) if
    // the signal does not exist on this KWin build.
    function connectSignal(obj, name, handler) {
        try {
            if (obj && obj[name]) {
                obj[name].connect(handler)
                return true
            }
        } catch (e) {
            // Fall through.
        }
        return false
    }

    // Screen containing the given position, or null.
    function screenAt(pos) {
        var screens = Workspace.screens
        for (var i = 0; i < screens.length; i++) {
            var g = screens[i].geometry
            if (g && pos.x >= g.x && pos.x < g.x + g.width && pos.y >= g.y && pos.y < g.y + g.height) {
                return screens[i]
            }
        }
        return null
    }

    // Screen under the given position, falling back to the first screen.
    function screenForCursor(pos) {
        var screens = Workspace.screens
        return screenAt(pos) || (screens.length > 0 ? screens[0] : null)
    }

    // Re-query the client area (workspace geometry can change on monitor
    // hotplug, rotation or resolution change). Called at startup and on each
    // drag start so the band/popup/overlay always match the current screen.
    function refreshScreenArea() {
        var screen = screenForCursor(Workspace.cursorPos)
        if (!screen) {
            return
        }
        var area = Workspace.clientArea(KWin.MaximizeArea, screen, Workspace.currentDesktop)
        if (area.width > 0 && area.height > 0) {
            screenArea = Qt.rect(area.x, area.y, area.width, area.height)
        }
        dragScreen = screen
    }

    function connectWindow(window) {
        try {
            if (!window || !window.normalWindow) {
                return
            }
            connectSignal(window, "interactiveMoveResizeStarted", function() {
                if (window.move) {
                    onDragStarted(window)
                }
            })
            connectSignal(window, "interactiveMoveResizeFinished", function() {
                // Resize finishes and other windows' move ends must not
                // disturb an active drag or the idle state.
                if (dragWindow === window) {
                    onDrop()
                }
            })
            // KWin handles some drops itself, and does so after the move
            // has ended (move is false) but before announcing the finish: a
            // cancelled move (Escape) restores the window — back to its
            // start position, or into its previous tile/maximize state —
            // and KWin's own edge tiling/maximize or Shift custom tiling
            // applies. Any of these while this window's drop is being
            // finished means the popup must not snap it as well. (Moving
            // an already tiled/maximized window untiles/unmaximizes it with
            // move still true, which is ignored.)
            var handledByKWin = function() {
                if (dragging && dragWindow === window && !window.move) {
                    dropHandled = true
                }
            }
            connectSignal(window, "requestedTileChanged", handledByKWin)
            connectSignal(window, "maximizedAboutToChange", handledByKWin)
            connectSignal(window, "frameGeometryChanged", function() {
                if (dragging && dragWindow === window && !window.move
                    && Math.abs(window.x - dragStartPos.x) < 1
                    && Math.abs(window.y - dragStartPos.y) < 1) {
                    dropHandled = true
                }
            })
        } catch (e) {
            // This window simply gets no popup.
        }
    }

    function onDragStarted(window) {
        // KZones' activation: the dialog maps at grab time — long before
        // the cursor ever reaches the band — and the selector starts
        // fully retracted inside it.
        retracted = true
        hideTimer.stop()
        // A snap still pending from an earlier drop is stale now.
        commitTimer.stop()
        pendingZone = ""
        pendingWindow = null
        dragWindow = window
        dropHandled = false
        dragStartPos = Qt.point(window.x, window.y)
        // Zone state starts clean every drag; the screen area and KWin's
        // quick tiles are located for the screen under the cursor (the
        // tiles themselves are then read live: hSplit/vSplit/
        // zoneOutlineRect bind to them). A re-dragged snapped window is
        // still in its tile at this point, so it can serve as the way in.
        retarget()
        dragging = true
        // KZones' show(): visible at grab, so the first map after login
        // happens with seconds of slack instead of at the moment of
        // truth. The dialog starts retracted (fully above the screen).
        visible = true
        pollTimer.start()
        onTick()
    }

    // (Re)target the drag at the screen under the cursor and the current
    // desktop: drag start, the cursor crossing to another monitor, or a
    // desktop switch mid-drag. Any selection belongs to the old target.
    function retarget() {
        clearZoneState()
        refreshScreenArea()
        quickTiles = findQuickTiles()
        if (debugLog) {
            console.info("[kde-snap-overlay] grid h=" + hSplit.toFixed(3),
                "v=" + vSplit.toFixed(3),
                "source=" + (quickTiles ? "quick-tiles" : "default"),
                "screen=" + (dragScreen ? dragScreen.name : "?"))
        }
    }

    function onDesktopChanged() {
        if (dragging) {
            retarget()
        }
    }

    // KZones' isHovering pattern: cursor inside an item's global rect.
    function pointInRect(pos, rect) {
        return pos.x >= rect.x && pos.x <= rect.x + rect.width &&
            pos.y >= rect.y && pos.y <= rect.y + rect.height
    }

    // Drop every zone selection: card highlight, dwell and overlay.
    function clearZoneState() {
        highlightedZone = ""
        dwellCandidate = ""
        dwellTimer.stop()
        overlayZone = ""
        fullZone = false
    }

    function onTick() {
        if (!dragging) {
            return
        }
        // Watchdog: the move is over (or the window is gone) without its
        // finish ever arriving — end the drag without snapping rather than
        // leave the popup and poll running.
        if (!dragWindow || !dragWindow.move) {
            resetDrag(true)
            return
        }
        var pos = Workspace.cursorPos
        // Multi-monitor: follow the cursor to the screen it is on.
        var screen = screenAt(pos)
        if (screen && screen !== dragScreen) {
            retarget()
        }
        var inBand =
            pos.y >= screenArea.y && pos.y <= screenArea.y + activationDistance &&
            pos.x >= screenArea.x + edgeGap && pos.x <= screenArea.x + screenArea.width - edgeGap
        if (inBand) {
            // Back inside the band: reveal the selector again. The dialog
            // may have been hidden by the fly-out — remapping is safe, the
            // window is sized from the mainItem's implicit size.
            retracted = false
            if (!visible) {
                visible = true
            }
            // Two-stage KZones-style reveal: peek sliver in the outer band,
            // full drop within showDistance of the top. Hovering the selector
            // (panel + chrome) keeps it fully shown (the popup never slides
            // out from under the cursor).
            var g = zoneSelector.mapToGlobal(Qt.point(0, 0))
            var hovering = pointInRect(pos, Qt.rect(g.x, g.y, zoneSelector.width, zoneSelector.height))
            fullZone = hovering || (pos.y - screenArea.y) < showDistance
            // Card-row origin exactly as the Selector lays it out: its
            // insets are pad plus the shadow compensation on top/left.
            var ox = g.x + compensateLeft
            var oy = g.y + compensateTop
            // Selection is popup-area-only: only the cards highlight; the
            // panel padding and the rest of the screen stay inert, and
            // leaving the panel (it retracts to the peek sliver) clears the
            // zone, so a drop off the cards never snaps.
            var hit = fullZone
                ? Logic.hitTestZones(pos.x, pos.y, ox, oy, cardW, cardH, gap, pad, hSplit, vSplit)
                : ""
            // Leave-margin hysteresis: a zone change — to another zone or
            // to "" — only commits once the cursor sits 6px clear of the
            // current zone's rect. The mini zone targets inside the cards
            // are small (a quadrant is ~65x35px) and a resting hand
            // trembles 1-2px; without the margin, edge jitter on a single
            // poll tick would flip the zone state, tear down the overlay
            // and re-arm the dwell. Entering from "" stays instant;
            // decisive moves commit within one tick. The margin is well
            // inside the panel padding, so it never holds a zone off-panel.
            if (hit !== highlightedZone && highlightedZone !== "") {
                var r = Logic.zoneRectInPopup(highlightedZone, ox, oy, cardW, cardH, gap, pad, hSplit, vSplit)
                var margin = 6
                if (pointInRect(pos, Qt.rect(r.x - margin, r.y - margin, r.width + 2 * margin, r.height + 2 * margin))) {
                    hit = highlightedZone
                }
            }
            if (hit !== highlightedZone) {
                highlightedZone = hit
            }
            // Dwell gating for the fullscreen overlay: track the candidate
            // zone and (re)arm the dwell timer only when it changes — the
            // cursor moving within one zone neither resets nor blocks the
            // dwell. highlightDelay 0 engages instantly (FancyZones).
            if (hit !== dwellCandidate) {
                dwellCandidate = hit
                if (hit === "") {
                    dwellTimer.stop()
                    overlayZone = ""
                } else if (highlightDelay <= 0) {
                    dwellTimer.stop()
                    overlayZone = hit
                } else {
                    dwellTimer.restart()
                }
            }
        } else {
            // Outside the band: fly the panel up off the top edge, then hide
            // the dialog once the animation has finished.
            clearZoneState()
            retracted = true
            if (!hideTimer.running) {
                hideTimer.restart()
            }
        }
    }

    // End the drag. flyOut=true: nothing was dropped on a layout, so the
    // panel flies away the same way it dropped in, and the dialog hides once
    // the animation finishes. flyOut=false: hide instantly (successful snap,
    // or stuck-drag cleanup).
    function resetDrag(flyOut) {
        dragging = false
        pollTimer.stop()
        dragWindow = null
        clearZoneState()
        retracted = true
        if (flyOut) {
            hideTimer.restart()
        } else {
            visible = false
        }
    }

    function onDrop() {
        var window = dragWindow
        // Never snap a drop KWin already handled (see connectWindow).
        var chosen = dropHandled ? "" : highlightedZone
        if (dropHandled && highlightedZone !== "" && debugLog) {
            console.info("[kde-snap-overlay] drop handled by KWin (cancel or native tiling), not snapping")
        }
        resetDrag(chosen === "")
        if (chosen !== "") {
            pendingZone = chosen
            pendingWindow = window
            // Delay so KWin has committed the drop before we snap the window.
            // restart(), not start(): start() is a no-op on a running timer,
            // which would fire a quick second drop early.
            commitTimer.restart()
        }
    }

    // A window going away: reset a drag it was the subject of (if its move
    // never finished), and forget a snap still pending for it.
    function onWindowRemoved(window) {
        if (window === pendingWindow) {
            commitTimer.stop()
            pendingZone = ""
            pendingWindow = null
        }
        if (dragging && window === dragWindow) {
            resetDrag(false)
        }
    }

    function onCommit() {
        var zone = pendingZone
        var window = pendingWindow
        pendingZone = ""
        pendingWindow = null
        // A new drag started meanwhile: the intent is stale.
        if (dragging || !window) {
            return
        }
        var slot = Logic.zoneSlot(zone)
        if (slot === "" || !Workspace[slot]) {
            return
        }
        // KWin's quick-tile slots tile the *active* window
        // (Workspace::quickTileWindow), and a Meta+drag moves a window
        // without activating it. Activate the dropped window first, and
        // never tile a different window if that did not take.
        if (Workspace.activeWindow !== window) {
            Workspace.activeWindow = window
        }
        if (Workspace.activeWindow !== window) {
            if (debugLog) {
                console.info("[kde-snap-overlay] dropped window could not be activated, not snapping")
            }
            return
        }
        Workspace[slot]()
    }

    // Dialog's default property only accepts Items, so all UI and non-Item
    // children (Timers) live inside a plain Item (the KZones pattern). The
    // implicit size drives the Dialog's auto-sizing (the standard plasmashell
    // pattern), so the window is born at the panel's size.
    Item {
        implicitWidth: zoneSelector.implicitWidth
        implicitHeight: zoneSelector.implicitHeight

        // KZones-style selector (forked from KZones' Selector.qml): the row
        // of three layout cards. The panel skin is this Dialog's own theme
        // background, and the reveal (resting offset / peek sliver /
        // retracted) is the Dialog's y Behavior above.
        Components.Selector {
            id: zoneSelector

            pad: popup.pad
            gap: popup.gap
            cardW: popup.cardW
            cardH: popup.cardH
            extraTop: popup.compensateTop
            extraLeft: popup.compensateLeft
            layouts: Logic.LAYOUTS
            highlightedZone: popup.highlightedZone
            hSplit: popup.hSplit
            vSplit: popup.vSplit
        }

        // Fullscreen, click-through overlay that mirrors the native KWin
        // outline while a zone is hovered. Unlike the shared Outline — which
        // KWin's own interactive-move code hides on every motion step of the
        // drag — this is our window: it stays up without churn while the
        // cursor moves, so the highlight reads as static. Position/size come
        // from zoneOutlineRect (KWin's own quick tile rect).
        PlasmaCore.Dialog {
            id: zoneOverlay
            // Engaged: the dwell-approved overlay should be on screen. The
            // dialog maps and hides directly on this binding — FancyZones'
            // model, where Show()/Hide() are plain window operations and
            // the only animation is the content's fade-in.
            readonly property bool engaged: popup.dragging && popup.visible
                && popup.overlayZone !== "" && popup.zoneOutlineRect.width > 0
            visible: engaged
            type: PlasmaCore.Dialog.OnScreenDisplay
            location: PlasmaCore.Types.Desktop
            backgroundHints: PlasmaCore.Types.NoBackground
            flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
            hideOnWindowDeactivate: false
            outputOnly: true
            x: popup.screenArea.x
            y: popup.screenArea.y
            // Declared full-screen size properties, so the overlay window is
            // born at the full client area instead of being sized to its
            // first highlight.
            width: popup.screenArea.width
            height: popup.screenArea.height
            // Explicit resize whenever shown, never on the poll. The debug
            // line exposes the window's width BEFORE the imperative resize:
            // if the Dialog ever maps at a stale/auto-sized dimension and is
            // corrected a frame later, that shows up here as a blink whose
            // cause no animation code can explain.
            onVisibleChanged: {
                if (visible) {
                    if (popup.debugLog) {
                        console.info("[kde-snap-overlay] overlay map at",
                            zoneOverlay.width + "x" + zoneOverlay.height,
                            "-> resize to", popup.screenArea.width + "x" + popup.screenArea.height)
                    }
                    setWidth(popup.screenArea.width)
                    setHeight(popup.screenArea.height)
                }
            }

            // Full-size content host so the highlight always has a correctly
            // sized parent context. The explicit implicit size keeps the
            // Dialog's auto-sizing (from the mainItem) in agreement with the
            // declared window size, so mapping cannot thrash the dimensions.
            Item {
                id: overlayContent
                implicitWidth: popup.screenArea.width
                implicitHeight: popup.screenArea.height
                width: zoneOverlay.width
                height: zoneOverlay.height

                // FancyZones' ONE animation: a linear alpha ramp over
                // overlayFadeIn on show (upstream FadeInDurationMillis 200).
                // The Behavior is gated on `engaged` so a disengage snaps the
                // alpha back to 0 immediately (upstream hides instantly) —
                // otherwise a re-engage during the invisible fade-out would
                // start mid-way and read as a blink.
                opacity: zoneOverlay.engaged ? 1 : 0
                Behavior on opacity {
                    enabled: zoneOverlay.engaged
                    NumberAnimation {
                        duration: popup.overlayFadeIn
                        easing.type: Easing.Linear
                    }
                }

                // Highlight, positioned by the zone geometry. No geometry
                // animation: FancyZones redraws zone switches by repainting
                // instantly, so the highlight is placed directly at its new
                // rect.
                Rectangle {
                    id: highlight
                    x: popup.zoneOutlineRect.x - popup.screenArea.x
                    y: popup.zoneOutlineRect.y - popup.screenArea.y
                    width: popup.zoneOutlineRect.width
                    height: popup.zoneOutlineRect.height
                    radius: 12
                    color: overlayHelper.overlayFill
                    border.color: overlayHelper.overlayBorder
                    border.width: 2
                }

                Components.ColorHelper {
                    id: overlayHelper
                    // FancyZones' highlightOpacity (default 50) on the fill.
                    fillAlpha: popup.highlightOpacity
                }
            }
        }

        Timer {
            id: pollTimer
            interval: 16
            repeat: true
            onTriggered: onTick()
        }

        Timer {
            id: commitTimer
            interval: 80
            onTriggered: onCommit()
        }

        // Dwell timer for the fullscreen overlay (FancyZones-style rest):
        // armed only when the candidate zone changes, so the cursor moving
        // within one zone neither resets nor blocks the dwell. The overlay
        // engages within the same beat (zoneOutlineRect is a binding).
        Timer {
            id: dwellTimer
            interval: popup.highlightDelay
            repeat: false
            onTriggered: {
                if (dragging && dwellCandidate !== "") {
                    overlayZone = dwellCandidate
                    if (popup.debugLog) {
                        console.info("[kde-snap-overlay] overlay engage", overlayZone,
                            "rect", JSON.stringify(zoneOutlineRect))
                    }
                }
            }
        }

        // One-shot delay so the fly-out animation (the y Behavior easing the
        // panel above the screen) finishes before the dialog hides.
        Timer {
            id: hideTimer
            interval: 170
            repeat: false
            onTriggered: {
                // retracted is already true whenever no drag is running.
                if (!dragging) {
                    visible = false
                }
            }
        }
    }
}
