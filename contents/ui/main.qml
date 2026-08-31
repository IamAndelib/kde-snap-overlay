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
    readonly property int activationDistance: Math.min(Math.max(KWin.readConfig("activationDistance", 150), 100), 400)
    // topGap is the popup's resting offset below the top edge. The 25px
    // default replicates the old design's selector chrome — the panel top
    // sits 25px below the screen edge. Clamped so the whole card row (pad +
    // cardH below the popup top) always lands inside the band.
    readonly property int topGap: Math.min(Math.max(KWin.readConfig("topGap", 25), 0), Math.max(activationDistance - (pad + cardH), 0))
    // Cursor distance from the screen top below which the popup fully drops
    // (two-stage KZones-style reveal: peek sliver beyond this, full panel
    // within it). Defaults to KZones' trigger distance
    // (zoneSelectorTriggerDistance 1 -> 1*50+25 = 75px).
    readonly property int showDistance: {
        var v = KWin.readConfig("showDistance", 75)
        return Math.min(Math.max(v, topGap + 10), Math.max(activationDistance - 10, topGap + 10))
    }
    // Fraction of the screen width to ignore on each side of the trigger band,
    // so dragging to the corners (quarter-tile intent) doesn't open the popup.
    readonly property real edgeGapRatio: Math.min(Math.max(KWin.readConfig("edgeGapRatio", 0.25), 0), 0.5)
    // Horizontal trigger margin on each side, derived from the current screen width.
    readonly property real edgeGap: screenArea.width * edgeGapRatio

    // ---- Card / popup metrics (KZones indicator sizing) ----
    readonly property int cardW: 130
    readonly property int cardH: 70
    readonly property int gap: 10
    readonly property int pad: 14
    readonly property int popupH: Logic.popupSize(Logic.LAYOUTS.length, cardW, cardH, gap, pad).height
    // Visible sliver while the popup peeks: 15px matches the old design's
    // visible panel sliver (KZones showed 30px of selector = 15px of panel).
    readonly property int peekHeight: Math.min(Math.max(KWin.readConfig("peekHeight", 15), 10), popupH - 20)

    // ---- State ----
    property rect screenArea: Qt.rect(0, 0, 1920, 1080)
    property bool dragging: false
    // Cursor within showDistance of the screen top: the selector is fully
    // expanded; hovering the selector also keeps it expanded (KZones).
    property bool fullZone: false
    // Fly-out / fully-retracted state: the panel sits fully above the screen
    // edge (retracted position), inside the still-visible dialog.
    property bool retracted: true
    // Whether the native outline currently on screen is OURS (shown via
    // showOutline for a hovered card). Only ever hide an outline we own —
    // unconditional hides would erase KWin's own native edge/corner
    // drag previews.
    property bool outlineShown: false

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
    // The layout the overlay currently previews (owns the hovered zone).
    property string currentLayout: "columns"
    property string pendingZone: ""
    // Window being dragged right now; used to abort a stuck drag if it is
    // closed without ever finishing the move.
    property var dragWindow: null
    // Output the drag happens on; the tile tree is per-output/per-desktop.
    property var dragScreen: null
    // Last poll position; the live grid is only re-read when the cursor moves.
    property var lastTickPos: Qt.point(-1, -1)

    // Current quick-tile grid splits (relative to screenArea), read from
    // KWin's live tile tree at drag start so the highlight matches the space
    // the native outline would fill. 0.5/0.5 = the default grid.
    property real hSplit: 0.5
    property real vSplit: 0.5

    // The screen-space region the highlighted zone maps to, evaluated fresh
    // on every call — a cached binding would go stale between highlight
    // changes, since cursorPos is not a notifiable dependency. Resolution
    // order: (1) KWin's own quickTileGeometry — the bit-exact geometry
    // native snapping feeds its outline (probed, not exposed on every
    // build); (2) the live grid splits measured from the real tile tree.
    function currentZoneRect() {
        if (dragWindow && highlightedZone !== "") {
            try {
                if (dragWindow.quickTileGeometry) {
                    var native = dragWindow.quickTileGeometry(
                        Logic.zoneMode(highlightedZone), Workspace.cursorPos)
                    if (native && native.width > 0 && native.height > 0) {
                        return Qt.rect(native.x, native.y, native.width, native.height)
                    }
                }
            } catch (e) {
                // Not scriptable here: fall through to the tile-tree splits.
            }
        }
        var f = Logic.zoneRectFrac(highlightedZone, hSplit, vSplit)
        if (!f || (f.fw === 0 && f.fh === 0)) {
            return Qt.rect(0, 0, 0, 0)
        }
        return Qt.rect(
            screenArea.x + screenArea.width * f.fx,
            screenArea.y + screenArea.height * f.fy,
            screenArea.width * f.fw,
            screenArea.height * f.fh)
    }

    // Read the current quick-tile grid (hSplit/vSplit) straight from KWin's
    // tile tree, reproducing what QuickRootTile::relayoutToFit() computes:
    // the split follows the inner edge of the tiled windows. The quick slot
    // grid itself is not scripting-accessible, so the tree is reached by
    // scanning the stacking order for a window that reports an owning tile
    // (window.tile); ascending to the tree root and reading its leaves gives
    // exactly the partition KWin previews. Only windows KWin placed in a tile
    // can contribute, so floating windows never skew the grid. Falls back to
    // the default grid.
    function splitsFromTileTree() {
        hSplit = 0.5
        vSplit = 0.5
        var leftRights = []
        var rightLefts = []
        var topBottoms = []
        var bottomTops = []

        // A leaf rect contributes split values only if it is clearly
        // anchored to the screen edges. Tile.absoluteGeometry is used so the
        // measured edges sit exactly on the tile partition lines — layered
        // windows cannot skew them. Custom tilings whose cells stay inset
        // from the edges fall through to the default grid.
        function consider(rect) {
            if (!rect || rect.width < 50 || rect.height < 50) {
                return
            }
            var sa = screenArea
            var w = sa.width
            var h = sa.height
            var x1 = Math.max(rect.x, sa.x)
            var y1 = Math.max(rect.y, sa.y)
            var x2 = Math.min(rect.x + rect.width, sa.x + w)
            var y2 = Math.min(rect.y + rect.height, sa.y + h)
            if (x2 - x1 < 50 || y2 - y1 < 50) {
                return
            }
            var relL = (x1 - sa.x) / w
            var relT = (y1 - sa.y) / h
            var relR = (x2 - sa.x) / w
            var relB = (y2 - sa.y) / h
            var hFrac = (x2 - x1) / w
            var vFrac = (y2 - y1) / h

            var epsH = 0.02
            var epsV = 0.05
            var left = relL < epsH
            var right = relR > 1 - epsH
            var top = relT < epsV
            var bottom = relB > 1 - 0.005

            if (vFrac >= 0.8 && hFrac <= 0.95) {
                // Full-height column.
                if (left && !right) {
                    leftRights.push(relR)
                } else if (right && !left) {
                    rightLefts.push(relL)
                }
            } else if (hFrac >= 0.8 && vFrac <= 0.95) {
                // Full-width row.
                if (top && !bottom) {
                    topBottoms.push(relB)
                } else if (bottom && !top) {
                    bottomTops.push(relT)
                }
            } else if (hFrac >= 0.2 && vFrac >= 0.2) {
                // Corner.
                if (left && top && !right && !bottom) {
                    leftRights.push(relR)
                    topBottoms.push(relB)
                } else if (right && top && !left && !bottom) {
                    rightLefts.push(relL)
                    topBottoms.push(relB)
                } else if (left && bottom && !right && !top) {
                    leftRights.push(relR)
                    bottomTops.push(relT)
                } else if (right && bottom && !left && !top) {
                    rightLefts.push(relL)
                    bottomTops.push(relT)
                }
            }
        }

        // Exact partition lines from KWin's real quick-tile tree. Entry is
        // the proven walk (rootTile() returns the custom-tiling root, not
        // the tree the quick-grid splits live in); the measurement is the
        // exact one: leaves' Tile.absoluteGeometry — KWin's own tile rects,
        // so layered windows can never skew them the way window-frame
        // unions did.
        function addTileRects(tile) {
            if (!tile) {
                return
            }
            var kids = tile.childTiles
            if (kids && kids.length > 0) {
                for (var i = 0; i < kids.length; i++) {
                    addTileRects(kids[i])
                }
                return
            }
            if (tile.absoluteGeometry) {
                consider(tile.absoluteGeometry)
            }
        }

        try {
            var root = null
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
                root = w.tile
                break
            }
            if (root) {
                var p = root.parentTile
                while (p) {
                    root = p
                    p = root.parentTile
                }
                addTileRects(root)
            }
        } catch (e) {
            // Tile tree not reachable here: keep the default grid.
        }

        var hs = 0.5
        var vs = 0.5
        if (leftRights.length > 0) {
            hs = Math.max.apply(null, leftRights)
        } else if (rightLefts.length > 0) {
            hs = Math.min.apply(null, rightLefts)
        }
        if (topBottoms.length > 0) {
            vs = Math.max.apply(null, topBottoms)
        } else if (bottomTops.length > 0) {
            vs = Math.min.apply(null, bottomTops)
        }
        hSplit = Math.min(0.9, Math.max(0.1, hs))
        vSplit = Math.min(0.9, Math.max(0.1, vs))
    }

    Component.onCompleted: {
        refreshScreenArea()
        var order = Workspace.stackingOrder
        for (var i = 0; i < order.length; i++) {
            connectWindow(order[i])
        }
        Workspace.windowAdded.connect(connectWindow)
        // KWin 6's signal for a window going away. Without it a window
        // closed mid-drag (before the move ever finishes) would leave the
        // popup and poll stuck. Guarded like the old connect so an API
        // surprise cannot abort Component.onCompleted and break the
        // whole instance.
        if (Workspace.windowRemoved) {
            Workspace.windowRemoved.connect(onWindowRemoved)
        }
    }

    Component.onDestruction: {
        // Never leave our outline on screen after the script goes away
        // (disable/reload while a card is hovered).
        if (outlineShown) {
            Workspace.hideOutline()
            outlineShown = false
        }
    }

    // Screen under the given position, falling back to the first screen.
    function screenForCursor(pos) {
        var screens = Workspace.screens
        for (var i = 0; i < screens.length; i++) {
            var g = screens[i].geometry
            if (g && pos.x >= g.x && pos.x < g.x + g.width && pos.y >= g.y && pos.y < g.y + g.height) {
                return screens[i]
            }
        }
        return screens.length > 0 ? screens[0] : null
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
        if (!window.normalWindow) {
            return
        }
        window.interactiveMoveResizeStarted.connect(function() {
            if (!window.move) {
                return
            }
            // KZones' activation: the dialog maps at grab time — long before
            // the cursor ever reaches the band — and the selector starts
            // fully retracted inside it.
            retracted = true
            hideTimer.stop()
            refreshScreenArea()
            dragWindow = window
            // Re-read the grid from KWin's tile tree. A snapped window
            // being re-dragged is still in its tile, so the empty space it
            // is leaving keeps being reflected.
            splitsFromTileTree()
            dragging = true
            // KZones' show(): visible at grab, so the first map after login
            // happens with seconds of slack instead of at the moment of
            // truth. The dialog starts retracted (fully above the screen).
            visible = true
            lastTickPos = Qt.point(-1, -1)
            pollTimer.start()
            onTick()
        })
        window.interactiveMoveResizeFinished.connect(function() {
            onDrop()
        })
    }

    // KZones' isHovering pattern: cursor inside an item's global rect.
    function pointInRect(pos, rect) {
        return pos.x >= rect.x && pos.x <= rect.x + rect.width &&
            pos.y >= rect.y && pos.y <= rect.y + rect.height
    }

    // Global rect of the selector (panel + chrome) in its current state.
    function selectorRect() {
        var g = zoneSelector.mapToGlobal(Qt.point(0, 0))
        return Qt.rect(g.x, g.y, zoneSelector.width, zoneSelector.height)
    }

    function onTick() {
        if (!dragging) {
            return
        }
        var pos = Workspace.cursorPos
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
            // Keep the grid live: re-read it whenever the cursor moved so the
            // diagrams and overlay track the re-tiled layout.
            if (pos.x !== lastTickPos.x || pos.y !== lastTickPos.y) {
                lastTickPos = pos
                splitsFromTileTree()
            }
            // Two-stage KZones-style reveal: peek sliver in the outer band,
            // full drop within showDistance of the top. Hovering the selector
            // keeps it fully shown (the popup never slides out from under
            // the cursor).
            var hovering = pointInRect(pos, selectorRect())
            fullZone = hovering || (pos.y - screenArea.y) < showDistance
            // Selection is popup-area-only: only the cards highlight; the
            // panel padding and the rest of the screen stay inert.
            var hit = highlightedZone
            if (fullZone) {
                var g = zoneSelector.mapToGlobal(Qt.point(0, 0))
                hit = Logic.hitTestZones(pos.x, pos.y, g.x, g.y, cardW, cardH, gap, pad, hSplit, vSplit)
            }
            if (hit !== highlightedZone) {
                highlightedZone = hit
                if (hit !== "") {
                    currentLayout = Logic.layoutOf(hit)
                }
            }
        } else {
            // Outside the band: fly the panel up off the top edge, then hide
            // the dialog once the animation has finished.
            highlightedZone = ""
            fullZone = false
            retracted = true
            if (!hideTimer.running) {
                hideTimer.restart()
            }
        }
        // KWin's native snap outline (the same renderer native edge-dragging
        // uses) tracks the highlight and moves with live grid changes. We
        // only ever hide an outline we showed ourselves — unconditional
        // hides would erase KWin's own native edge/corner drag previews.
        // Inside the native maximize strip (top edge, ≤ 5px) the outline is
        // left strictly alone: a hide there can erase the preview KWin shows
        // on entering the strip, and KWin only re-shows on zone transitions
        // — that erased the native maximize overlay on quick flicks through
        // the card row. resetDrag() still cleans up our own outline once
        // the drag ends.
        if (pos.y - screenArea.y >= 5) {
            var outlineRect = currentZoneRect()
            if (highlightedZone !== "" && outlineRect.width > 0) {
                Workspace.showOutline(outlineRect)
                outlineShown = true
            } else if (outlineShown) {
                Workspace.hideOutline()
                outlineShown = false
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
        highlightedZone = ""
        fullZone = false
        if (outlineShown) {
            Workspace.hideOutline()
            outlineShown = false
        }
        if (flyOut) {
            retracted = true
            hideTimer.restart()
        } else {
            retracted = true
            visible = false
        }
    }

    function onDrop() {
        var chosen = highlightedZone
        resetDrag(chosen === "")
        if (chosen !== "") {
            pendingZone = chosen
            // Delay so KWin has committed the drop before we snap the window.
            commitTimer.start()
        }
    }

    // If the window being dragged goes away without emitting
    // interactiveMoveResizeFinished (rare), reset so the popup/poll never
    // get stuck.
    function onWindowRemoved(window) {
        if (dragging && window === dragWindow) {
            resetDrag(false)
        }
    }

    function onCommit() {
        var zone = pendingZone
        pendingZone = ""
        // A new drag may have started while the commit was pending. The tile
        // slots act on whichever window KWin is currently handling, so
        // applying now could tile the wrong window; drop the stale intent.
        if (dragging) {
            return
        }
        var slot = Logic.zoneSlot(zone)
        if (slot !== "" && Workspace[slot]) {
            Workspace[slot]()
        }
    }

    // Dialog's default property only accepts Items, so all UI and non-Item
    // children (Timers) live inside a plain Item (the KZones pattern). The
    // implicit size drives the Dialog's auto-sizing (the standard plasmashell
    // pattern), so the window is born at the panel's size.
    Item {
        implicitWidth: zoneSelector.implicitWidth
        implicitHeight: zoneSelector.implicitHeight

        // KZones-style selector (forked from KZones' Selector.qml): panel
        // skin, three merged layout cards and the three-state topMargin
        // (fully shown at the resting offset / peek sliver at the screen
        // top / retracted) with the margin Behavior providing the drop
        // animation.
        Components.Selector {
            id: zoneSelector

            pad: popup.pad
            gap: popup.gap
            cardW: popup.cardW
            cardH: popup.cardH
            extraTop: popup.compensateTop
            extraLeft: popup.compensateLeft
            layouts: Logic.LAYOUTS
            currentLayout: popup.currentLayout
            highlightedZone: popup.highlightedZone
            hSplit: popup.hSplit
            vSplit: popup.vSplit
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

        // One-shot delay so the fly-out animation (the y Behavior easing the
        // panel above the screen) finishes before the dialog hides.
        Timer {
            id: hideTimer
            interval: 170
            repeat: false
            onTriggered: {
                if (!dragging) {
                    visible = false
                    retracted = true
                }
            }
        }
    }
}
