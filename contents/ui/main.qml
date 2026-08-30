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

    // ---- Card / popup metrics (KZones indicator sizing) ----
    readonly property int cardW: 130
    readonly property int cardH: 70
    readonly property int gap: 10
    readonly property int pad: 14
    readonly property int popupW: Logic.popupSize(Logic.LAYOUTS.length, cardW, cardH, gap, pad).width
    readonly property int popupH: Logic.popupSize(Logic.LAYOUTS.length, cardW, cardH, gap, pad).height

    // ---- State ----
    property rect screenArea: Qt.rect(0, 0, 1920, 1080)
    property bool dragging: false
    // Hovered zone id (member of one of the three layouts), "" when none.
    property string highlightedZone: ""
    // The layout whose full-screen cells the overlay currently shows.
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
    // KWin's live tile tree so the highlight matches the space the native
    // outline would fill. 0.5/0.5 = the default grid.
    property real hSplit: 0.5
    property real vSplit: 0.5

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
        // Slide the panel in from just above the band; the y Behavior eases it
        // down onto its resting spot.
        x = Math.max(screenArea.x, screenArea.x + Math.floor((screenArea.width - popupW) / 2))
        setWidth(popupW)
        setHeight(popupH)
        var targetY = screenArea.y + topGap
        y = targetY - 60
        y = targetY
    }

    Behavior on y {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
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

    function onTick() {
        if (!dragging) {
            return
        }
        var pos = Workspace.cursorPos
        var inBand =
            pos.y >= screenArea.y && pos.y <= screenArea.y + activationDistance &&
            pos.x >= screenArea.x + edgeGap && pos.x <= screenArea.x + screenArea.width - edgeGap
        if (inBand) {
            // Keep the grid live: re-read it whenever the cursor moved so the
            // diagrams and overlay track the re-tiled layout. Equal splits are
            // no-ops, so this stays quiet while KWin does not re-tile.
            if (pos.x !== lastTickPos.x || pos.y !== lastTickPos.y) {
                lastTickPos = pos
                splitsFromTileTree()
            }
            if (!visible) {
                showAtTop()
                visible = true
            }
            // Zones in the popup cards take priority; otherwise fall back to
            // the full-screen zones of the current layout (KZones behavior).
            var hit = Logic.hitTestZones(pos.x, pos.y, x, y, cardW, cardH, gap, pad, hSplit, vSplit)
            if (hit !== "") {
                highlightedZone = hit
                currentLayout = Logic.layoutOf(hit)
            } else {
                highlightedZone = Logic.zoneAtPosition(pos.x, pos.y, currentLayout, screenArea, hSplit, vSplit)
            }
        } else {
            highlightedZone = ""
            visible = false
        }
    }

    function resetDrag() {
        dragging = false
        pollTimer.stop()
        dragWindow = null
        highlightedZone = ""
        visible = false
    }

    function onDrop() {
        var chosen = highlightedZone
        resetDrag()
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
            resetDrag()
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

        // Panel: KZones selector styling (rounded backgroundColor card, 1px
        // border, drop shadow) holding one Indicator per merged layout.
        Rectangle {
            id: panelBg
            anchors.fill: parent
            radius: 10
            color: colorHelper.backgroundColor
            border.width: 1
            border.color: colorHelper.getBorderColor(color)

            Row {
                spacing: gap
                anchors.centerIn: parent

                Repeater {
                    model: Logic.LAYOUTS

                    delegate: Components.Indicator {
                        zones: modelData.zones
                        activeZone: Logic.zoneIndexInLayout(modelData.id, popup.highlightedZone)
                        hs: popup.hSplit
                        vs: popup.vSplit
                        width: cardW
                        height: cardH
                        hovering: modelData.id === popup.currentLayout
                    }
                }
            }
        }

        // KZones-style drop shadow under the panel.
        Components.Shadow {
            target: panelBg
        }

        Components.ColorHelper {
            id: colorHelper
        }

        // Fullscreen, click-through overlay showing the current layout's zones
        // as KZones-style cells; the highlighted zone snaps on drop.
        PlasmaCore.Dialog {
            id: zoneOverlay
            visible: popup.dragging && popup.visible && popup.highlightedZone !== ""
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

            Item {
                anchors.fill: parent

                Repeater {
                    model: Logic.zonesForLayout(popup.currentLayout)

                    delegate: Item {
                        property string zoneId: modelData.id
                        property bool active: popup.highlightedZone === zoneId
                        property var frac: Logic.zoneRectFrac(zoneId, popup.hSplit, popup.vSplit)

                        x: frac.fx * parent.width
                        y: frac.fy * parent.height
                        width: frac.fw * parent.width
                        height: frac.fh * parent.height

                        // Delineation for every cell of the current layout.
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: overlayHelper.accentColor
                            opacity: active ? 0.12 : 0.04
                            Behavior on opacity {
                                NumberAnimation { duration: 90 }
                            }
                        }

                        // Highlight border on the active cell (KZones zoneBorder).
                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: "transparent"
                            border.width: active ? 3 : 1
                            border.color: active ? overlayHelper.accentColor : Qt.rgba(overlayHelper.accentColor.r, overlayHelper.accentColor.g, overlayHelper.accentColor.b, 0.25)
                            Behavior on border.color {
                                ColorAnimation { duration: 90 }
                            }
                        }
                    }
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