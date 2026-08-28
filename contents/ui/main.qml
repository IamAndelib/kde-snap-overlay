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
    // topGap is clamped so it always lands inside the trigger band; the floor is
    // activationDistance - 20 because the popup must fit below the maximize zone.
    readonly property int topGap: Math.min(Math.max(KWin.readConfig("topGap", 60), 20), Math.max(activationDistance - 20, 20))
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

    function showAtTop() {
        x = screenArea.x + Math.floor((screenArea.width - popupW) / 2)
        y = screenArea.y + topGap
        setWidth(popupW)
        setHeight(popupH)
    }

    Component.onCompleted: {
        var outputs = Workspace.screens
        if (outputs.length === 0) {
            return
        }
        var area = Workspace.clientArea(KWin.MaximizeArea, outputs[0], Workspace.currentDesktop)
        screenArea = Qt.rect(area.x, area.y, area.width, area.height)

        var order = Workspace.stackingOrder
        for (var i = 0; i < order.length; i++) {
            connectWindow(order[i])
        }
        Workspace.windowAdded.connect(connectWindow)
    }

    function connectWindow(window) {
        if (!window.normalWindow) {
            return
        }
        window.interactiveMoveResizeStarted.connect(function() {
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
            showAtTop()
            visible = true
            highlightedLayout = Logic.hitTest(pos.x, pos.y, x, y, cardW, cardH, gap, pad)
        } else {
            highlightedLayout = ""
            visible = false
        }
    }

    function onDrop() {
        dragging = false
        pollTimer.stop()
        var chosen = highlightedLayout
        highlightedLayout = ""
        visible = false
        if (chosen !== "") {
            pendingLayout = chosen
            // Delay so KWin has committed the drop before we snap the window.
            commitTimer.start()
        }
    }

    function onCommit() {
        var layout = pendingLayout
        pendingLayout = ""
        var l = Logic.layoutById(layout)
        if (l) {
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
                            id: colorHelper
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: colorHelper.cardBgIdle
                            border.width: isActive ? 2 : 1
                            border.color: isActive ? colorHelper.cardBorderActive : colorHelper.cardBorderIdle
                            Behavior on border.color { ColorAnimation { duration: 90 } }
                        }

                        Item {
                            id: mini
                            anchors.fill: parent
                            anchors.margins: 9

                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                color: colorHelper.miniScreenBg
                                border.color: colorHelper.miniScreenBorder
                                border.width: 1
                            }

                            Rectangle {
                                x: mini.width * modelData.fx
                                y: mini.height * modelData.fy
                                width: mini.width * modelData.fw
                                height: mini.height * modelData.fh
                                radius: 2
                                color: colorHelper.miniFillIdle
                            }

                            Rectangle {
                                width: 1
                                height: mini.height
                                anchors.horizontalCenter: mini.horizontalCenter
                                visible: modelData.fw === 0.5
                                color: colorHelper.dividerColor
                            }
                            Rectangle {
                                width: mini.width
                                height: 1
                                anchors.verticalCenter: mini.verticalCenter
                                visible: modelData.fh === 0.5
                                color: colorHelper.dividerColor
                            }
                        }
                    }
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
