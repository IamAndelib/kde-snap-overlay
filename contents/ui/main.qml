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
    // topGap is clamped so the whole card row (pad + cardH below the popup top,
    // and the popup top at least 20px down to clear the maximize zone) always
    // lands inside the activation band.
    readonly property int topGap: Math.min(Math.max(KWin.readConfig("topGap", 60), 20), Math.max(activationDistance - (pad + cardH), 20))
    // Fraction of the screen width to ignore on each side of the trigger band,
    // so dragging to the corners (quarter-tile intent) doesn't open the popup.
    readonly property real edgeGapRatio: Math.min(Math.max(KWin.readConfig("edgeGapRatio", 0.25), 0), 0.5)
    // Horizontal trigger margin on each side, derived from the current screen width.
    readonly property real edgeGap: screenArea.width * edgeGapRatio

    // ---- Card / popup metrics ----
    readonly property int cardW: 84
    readonly property int cardH: 56
    readonly property int gap: 8
    readonly property int pad: 12
    readonly property int popupW: Logic.popupSize(cardW, cardH, gap, pad).width
    readonly property int popupH: Logic.popupSize(cardW, cardH, gap, pad).height

    // ---- State ----
    property rect screenArea: Qt.rect(0, 0, 1920, 1080)
    property bool dragging: false
    property string highlightedLayout: ""
    property string pendingLayout: ""
    // Window being dragged right now; used to abort a stuck drag if it is
    // closed without ever finishing the move.
    property var dragWindow: null
    // Output the drag happens on; the tile tree is per-output/per-desktop.
    property var dragScreen: null

    // Current quick-tile grid splits (relative to screenArea), read from
    // KWin's live tile tree at drag start so the highlight matches the space
    // the native outline would fill. 0.5/0.5 = the default grid.
    property real hSplit: 0.5
    property real vSplit: 0.5

    // The screen-space region the highlighted layout maps to. Uses the
    // dynamic grid splits instead of the static layout fractions, matching
    // the geometry KWin's quickTileGeometry()/tileForMode() would report.
    // hSplit/vSplit are read directly here (not through a JS call) so the
    // binding re-evaluates when the grid changes.
    readonly property rect highlightGeometry: {
        var l = Logic.layoutById(highlightedLayout)
        if (!l) {
            return Qt.rect(0, 0, 0, 0)
        }
        var hs = hSplit
        var vs = vSplit
        var f
        switch (highlightedLayout) {
        case "left":        f = { fx: 0,   fy: 0,  fw: hs,     fh: 1 }; break
        case "right":       f = { fx: hs,  fy: 0,  fw: 1 - hs, fh: 1 }; break
        case "top":         f = { fx: 0,   fy: 0,  fw: 1,      fh: vs }; break
        case "bottom":      f = { fx: 0,   fy: vs, fw: 1,      fh: 1 - vs }; break
        case "topLeft":     f = { fx: 0,   fy: 0,  fw: hs,     fh: vs }; break
        case "topRight":    f = { fx: hs,  fy: 0,  fw: 1 - hs, fh: vs }; break
        case "bottomLeft":  f = { fx: 0,   fy: vs, fw: hs,     fh: 1 - vs }; break
        case "bottomRight": f = { fx: hs,  fy: vs, fw: 1 - hs, fh: 1 - vs }; break
        default:            f = { fx: 0,   fy: 0,  fw: 0,      fh: 0 }; break
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
        // Clamp so the popup never starts off-screen on narrow screens.
        x = Math.max(screenArea.x, screenArea.x + Math.floor((screenArea.width - popupW) / 2))
        y = screenArea.y + topGap
        setWidth(popupW)
        setHeight(popupH)
    }

    Component.onCompleted: {
        refreshScreenArea()
        var order = Workspace.stackingOrder
        for (var i = 0; i < order.length; i++) {
            connectWindow(order[i])
        }
        Workspace.windowAdded.connect(connectWindow)
        Workspace.windowClosed.connect(onWindowClosed)
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
            refreshScreenArea()
            dragWindow = window
            // Re-read the grid from KWin's tile tree. A snapped window
            // being re-dragged is still in its tile, so the empty space it
            // is leaving keeps being reflected.
            splitsFromTileTree()
            dragging = true
            pollTimer.start()
            onTick()
        })
        window.interactiveMoveResizeFinished.connect(function() {
            onDrop()
        })
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
            // Position once on entry; the popup is anchored to the screen, so
            // it does not need repositioning while the cursor stays in band.
            if (!visible) {
                showAtTop()
                visible = true
            }
            // Only update the layout when the hit test result actually
            // changes; keeps the overlay binding quiet while hovering.
            var hit = Logic.hitTest(pos.x, pos.y, x, y, cardW, cardH, gap, pad)
            if (hit !== highlightedLayout) {
                highlightedLayout = hit
            }
        } else {
            highlightedLayout = ""
            visible = false
        }
    }

    function resetDrag() {
        dragging = false
        pollTimer.stop()
        dragWindow = null
        highlightedLayout = ""
        visible = false
    }

    function onDrop() {
        var chosen = highlightedLayout
        resetDrag()
        if (chosen !== "") {
            pendingLayout = chosen
            // Delay so KWin has committed the drop before we snap the window.
            commitTimer.start()
        }
    }

    // If the window being dragged is destroyed without emitting
    // interactiveMoveResizeFinished (rare), reset so the popup/poll never
    // get stuck.
    function onWindowClosed(window) {
        if (dragging && window === dragWindow) {
            resetDrag()
        }
    }

    function onCommit() {
        var layout = pendingLayout
        pendingLayout = ""
        // A new drag may have started while the commit was pending. The tile
        // slots act on whichever window KWin is currently handling, so
        // applying now could tile the wrong window; drop the stale intent.
        if (dragging) {
            return
        }
        var l = Logic.layoutById(layout)
        if (l && Workspace[l.slot]) {
            Workspace[l.slot]()
        }
    }

    // Dialog's default property only accepts Items, so all UI and non-Item
    // children (Timers) live inside a plain Item (the KZones pattern).
    Item {
        anchors.fill: parent

        // Theme colors follow the active color scheme live. Each consumer owns
        // a local ColorHelper so Kirigami.Theme resolves in the same context
        // where the colors are consumed.
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: colorHelper.backgroundColor
            border.width: 1
            border.color: colorHelper.borderColor

            Components.ColorHelper {
                id: colorHelper
            }

            Row {
                spacing: gap
                anchors.centerIn: parent

                Repeater {
                    model: Logic.LAYOUTS

                    delegate: Item {
                        width: cardW
                        height: cardH

                        readonly property bool isActive: popup.highlightedLayout === modelData.id

                        Components.ColorHelper {
                            id: cardHelper
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: cardHelper.cardBgIdle
                            border.width: isActive ? 2 : 1
                            border.color: isActive ? cardHelper.cardBorderActive : cardHelper.cardBorderIdle
                            Behavior on border.color { ColorAnimation { duration: 90 } }
                        }

                        Item {
                            id: mini
                            anchors.fill: parent
                            anchors.margins: 9

                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: cardHelper.miniScreenBg
                                border.color: cardHelper.miniScreenBorder
                                border.width: 1
                            }

                            Rectangle {
                                x: mini.width * modelData.fx
                                y: mini.height * modelData.fy
                                width: mini.width * modelData.fw
                                height: mini.height * modelData.fh
                                radius: 2
                                color: cardHelper.miniFillIdle
                            }

                            Rectangle {
                                width: 1
                                height: mini.height
                                anchors.horizontalCenter: mini.horizontalCenter
                                visible: modelData.fw === 0.5
                                color: cardHelper.dividerColor
                            }
                            Rectangle {
                                width: mini.width
                                height: 1
                                anchors.verticalCenter: mini.verticalCenter
                                visible: modelData.fh === 0.5
                                color: cardHelper.dividerColor
                            }
                        }
                    }
                }
            }
        }

        // Fullscreen, click-through overlay that mirrors the native KWin outline
        // while a layout card is hovered. Position/size come from the same
        // MaximizeArea-based math KWin's quickTileGeometry() uses.
        PlasmaCore.Dialog {
            id: zoneOverlay
            // Shown only while the popup is up AND a layout card is hovered.
            // Declarative binding: reacts only when the highlighted layout
            // (or popup visibility/drag state) actually changes, so nothing
            // is churned on the 16ms poll.
            visible: popup.dragging && popup.visible && popup.highlightedLayout !== ""
            type: PlasmaCore.Dialog.OnScreenDisplay
            location: PlasmaCore.Types.Desktop
            backgroundHints: PlasmaCore.Types.NoBackground
            flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
            hideOnWindowDeactivate: false
            outputOnly: true
            x: popup.screenArea.x
            y: popup.screenArea.y
            // Declared full-screen size properties (mirroring kzones'
            // mainDialog), so the overlay window is born at the full client
            // area instead of being sized to its first highlight.
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
                // rectangle just fills it (kzones zone pattern).
                Item {
                    id: highlightHost
                    x: popup.highlightGeometry.x - popup.screenArea.x
                    y: popup.highlightGeometry.y - popup.screenArea.y
                    width: popup.highlightGeometry.width
                    height: popup.highlightGeometry.height

                    Rectangle {
                        id: highlight
                        anchors.fill: parent
                        radius: 12
                        color: overlayHelper.overlayFill
                        border.color: overlayHelper.overlayBorder
                        border.width: 2
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
    }
}
