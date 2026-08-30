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
    backgroundHints: PlasmaCore.Types.NoBackground
    flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
    hideOnWindowDeactivate: false
    outputOnly: true

    // ---- Configuration ----
    readonly property int activationDistance: Math.max(KWin.readConfig("activationDistance", 150), 100)
    // topGap is the popup's resting offset below the top edge (0 = KZones
    // style, panel glued to the top). It is clamped so the whole card row
    // (pad + cardH below the popup top) always lands inside the band.
    readonly property int topGap: Math.min(Math.max(KWin.readConfig("topGap", 0), 0), Math.max(activationDistance - (pad + cardH), 0))
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
    readonly property int popupW: Logic.popupSize(Logic.LAYOUTS.length, cardW, cardH, gap, pad).width
    readonly property int popupH: Logic.popupSize(Logic.LAYOUTS.length, cardW, cardH, gap, pad).height
    // Visible sliver while the popup peeks (KZones uses a fixed 30px).
    readonly property int peekHeight: Math.min(Math.max(KWin.readConfig("peekHeight", 30), 10), popupH - 20)
    // The dialog is a static top strip sized to hold the peeking and
    // expanded selector (the selector adds 30 side / 40 vertical chrome).
    readonly property int stripW: popupW + 30
    readonly property int stripH: topGap + popupH + 40

    // ---- State ----
    property rect screenArea: Qt.rect(0, 0, 1920, 1080)
    property bool dragging: false
    // Cursor within showDistance of the screen top: the selector is fully
    // expanded; hovering the selector also keeps it expanded (KZones).
    property bool fullZone: false
    // Fly-out in progress: the selector is retracting to the retracted margin
    // (flying up off the top edge) before the dialog actually hides.
    property bool hideFlying: false
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

    // The screen-space region the highlighted zone maps to. Uses the
    // dynamic grid splits instead of the static layout fractions, matching
    // the geometry KWin's quickTileGeometry()/tileForMode() would report.
    readonly property rect highlightGeometry: {
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
        // anchored to the screen edges. Frame geometry is used so the
        // measured edges sit exactly on the tile partition lines. With
        // margins/gaps in a custom tiling the frame stays inset from the
        // edges, so such setups fall through to the default grid.
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

        // Union of the client rects of every window a tile manages. For a
        // quick leaf that is one window; for a custom tile holding several
        // stacked windows, the union is the cell they jointly fill.
        function addLeaf(tile) {
            if (!tile) {
                return
            }
            var kids = tile.childTiles
            if (kids && kids.length > 0) {
                for (var i = 0; i < kids.length; i++) {
                    addLeaf(kids[i])
                }
                return
            }
            var wins = tile.windows
            var u
            for (var j = 0; j < wins.length; j++) {
                var g = wins[j].frameGeometry
                if (!g || g.width < 50 || g.height < 50) {
                    continue
                }
                if (!u) {
                    u = Qt.rect(g.x, g.y, g.width, g.height)
                } else {
                    var ux1 = Math.min(u.x, g.x)
                    var uy1 = Math.min(u.y, g.y)
                    var ux2 = Math.max(u.x + u.width, g.x + g.width)
                    var uy2 = Math.max(u.y + u.height, g.y + g.height)
                    u = Qt.rect(ux1, uy1, ux2 - ux1, uy2 - uy1)
                }
            }
            if (u) {
                consider(u)
            }
        }

        // Walk to the tree root from the first tiled window on this screen
        // and desktop, then collect every leaf's windows.
        var root = null
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
                root = w.tile
                break
            }
            if (root) {
                // Assumes a single tile tree per desktop (the quick grid).
                // Custom tilings with several independent roots would only
                // contribute the tree the first tiled window belongs to.
                var p = root.parentTile
                while (p) {
                    root = p
                    p = root.parentTile
                }
                addLeaf(root)
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

    function showAtTop() {
        // Position once on band entry: a static top strip holding the
        // peeking and expanded selector. The selector's own margin Behavior
        // (inside Selector.qml) animates the two-stage reveal inside it.
        x = Math.max(screenArea.x, screenArea.x + Math.floor((screenArea.width - stripW) / 2))
        y = screenArea.y
        setWidth(stripW)
        setHeight(stripH)
    }

    Component.onCompleted: {
        refreshScreenArea()
        var order = Workspace.stackingOrder
        for (var i = 0; i < order.length; i++) {
            connectWindow(order[i])
        }
        Workspace.windowAdded.connect(connectWindow)
        // Not exposed by every KWin build; guard so an unguarded connect
        // would abort Component.onCompleted and break the whole instance.
        if (Workspace.windowClosed) {
            Workspace.windowClosed.connect(onWindowClosed)
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
            // A new drag cancels any pending fly-out.
            hideFlying = false
            hideTimer.stop()
            refreshScreenArea()
            dragWindow = window
            // Re-read the grid from KWin's tile tree. A snapped window
            // being re-dragged is still in its tile, so the empty space it
            // is leaving keeps being reflected.
            splitsFromTileTree()
            dragging = true
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
            // Re-entering the band cancels a pending fly-out; the panel
            // animates straight back down from wherever it is.
            if (hideFlying) {
                hideFlying = false
                hideTimer.stop()
            }
            // Position once on entry; the popup is anchored to the screen, so
            // it does not need repositioning while the cursor stays in band.
            if (!visible) {
                showAtTop()
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
            // panel padding and the rest of the screen stay inert. Hover
            // checks pause while the margin animation runs (KZones parity).
            var hit = ""
            if (fullZone && !zoneSelector.animating) {
                var g = zoneSelector.panel.mapToGlobal(Qt.point(0, 0))
                hit = Logic.hitTestZones(pos.x, pos.y, g.x, g.y, cardW, cardH, gap, pad, hSplit, vSplit)
            }
            if (hit !== highlightedZone) {
                highlightedZone = hit
                if (hit !== "") {
                    currentLayout = Logic.layoutOf(hit)
                }
            }
        } else {
            // Fly out the same way the popup dropped in: retract the selector
            // (its margin Behavior animates it up off the top edge) and hide
            // the dialog once the animation has finished.
            highlightedZone = ""
            if (!hideFlying) {
                hideFlying = true
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
        highlightedZone = ""
        fullZone = false
        if (flyOut) {
            hideFlying = true
            hideTimer.restart()
        } else {
            hideFlying = false
            hideTimer.stop()
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

    // If the window being dragged is destroyed without emitting
    // interactiveMoveResizeFinished (rare), reset so the popup/poll never
    // get stuck.
    function onWindowClosed(window) {
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
    // children (Timers) live inside a plain Item (the KZones pattern).
    Item {
        anchors.fill: parent

        // KZones-style selector (forked from KZones' Selector.qml): panel
        // skin, three merged layout cards and the three-state topMargin
        // (fully shown at the resting offset / peek sliver at the screen
        // top / retracted) with the margin Behavior providing the drop
        // animation.
        Components.Selector {
            id: zoneSelector

            shownMargin: popup.topGap
            peekHeight: popup.peekHeight
            pad: popup.pad
            gap: popup.gap
            cardW: popup.cardW
            cardH: popup.cardH
            layouts: Logic.LAYOUTS
            currentLayout: popup.currentLayout
            highlightedZone: popup.highlightedZone
            hSplit: popup.hSplit
            vSplit: popup.vSplit
            expanded: popup.fullZone && !popup.hideFlying
            peeking: !popup.fullZone && !popup.hideFlying
        }

        // Fullscreen, click-through overlay that mirrors the native KWin
        // outline while a layout card is hovered (target-cell preview).
        // Position/size come from the same MaximizeArea-based math KWin's
        // quickTileGeometry() uses.
        PlasmaCore.Dialog {
            id: zoneOverlay
            // Shown only while the popup is up AND a layout card is hovered.
            // Declarative binding: reacts only when the highlighted zone
            // (or popup visibility/drag state) actually changes, so nothing
            // is churned on the 16ms poll.
            visible: popup.dragging && popup.visible && popup.highlightedZone !== ""
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
            // Explicit resize whenever shown, never on the poll.
            onVisibleChanged: {
                if (visible) {
                    setWidth(popup.screenArea.width)
                    setHeight(popup.screenArea.height)
                }
            }

            // Full-size content host so the highlight always has a correctly
            // sized parent context.
            Item {
                id: overlayContent
                width: zoneOverlay.width
                height: zoneOverlay.height

                // Highlight region, positioned by geometry; the visible
                // rectangle just fills it (KZones zone pattern).
                Item {
                    id: highlightHost
                    x: popup.highlightGeometry.x - popup.screenArea.x
                    y: popup.highlightGeometry.y - popup.screenArea.y
                    width: popup.highlightGeometry.width
                    height: popup.highlightGeometry.height

                    Rectangle {
                        id: highlight
                        anchors.fill: parent
                        radius: 8
                        color: overlayHelper.accentColor
                        opacity: 0.12
                        border.color: overlayHelper.accentColor
                        border.width: 3
                    }

                    Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    Behavior on width { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                }

                Components.ColorHelper {
                    id: overlayHelper
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

        // One-shot delay so the fly-out retract animation (150ms margin
        // Behavior inside Selector.qml) finishes before the dialog hides.
        Timer {
            id: hideTimer
            interval: 170
            repeat: false
            onTriggered: {
                if (!dragging) {
                    visible = false
                    hideFlying = false
                }
            }
        }
    }
}
