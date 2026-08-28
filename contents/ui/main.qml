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
    readonly property int topGap: Math.min(Math.max(KWin.readConfig("topGap", 60), 20), Math.max(activationDistance - 20, 20))

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
        x = screenArea.x + Math.floor((screenArea.width - popupW) / 2);
        y = screenArea.y + topGap;
        setWidth(popupW);
        setHeight(popupH);
    }

    Component.onCompleted: {
        var outputs = Workspace.screens;
        if (outputs.length === 0) {
            return;
        }
        var area = Workspace.clientArea(KWin.MaximizeArea, outputs[0], Workspace.currentDesktop);
        screenArea = Qt.rect(area.x, area.y, area.width, area.height);

        var order = Workspace.stackingOrder;
        for (var i = 0; i < order.length; i++) {
            connectWindow(order[i]);
        }
        Workspace.windowAdded.connect(connectWindow);
    }

    function connectWindow(window) {
        if (!window.normalWindow) {
            return;
        }
        window.interactiveMoveResizeStarted.connect(function() {
            dragging = true;
            pollTimer.start();
            onTick();
        });
        window.interactiveMoveResizeFinished.connect(function() {
            onDrop();
        });
    }

    function onTick() {
        if (!dragging) {
            return;
        }
        var pos = Workspace.cursorPos;
        var inBand = pos.y >= screenArea.y && pos.y <= screenArea.y + activationDistance;
        if (inBand) {
            showAtTop();
            visible = true;
            highlightedLayout = Logic.hitTest(pos.x, pos.y, x, y, cardW, cardH, gap, pad);
        } else {
            highlightedLayout = "";
            visible = false;
        }
    }

    function onDrop() {
        dragging = false;
        pollTimer.stop();
        var chosen = highlightedLayout;
        highlightedLayout = "";
        visible = false;
        if (chosen !== "") {
            pendingLayout = chosen;
            commitTimer.start();
        }
    }

    function onCommit() {
        var layout = pendingLayout;
        pendingLayout = "";
        var l = Logic.layoutById(layout);
        if (l) {
            Workspace[l.slot]();
        }
    }

    // KZones puts all UI objects and non-Item children (Timers, Connections)
    // inside a plain Item, because Dialog's default property only accepts Items.
    Item {
        id: mainItem
        anchors.fill: parent

        // Theme colors (follow the system color scheme, live).
        // Each consumer owns a local ColorHelper (as in KZones) so Kirigami.Theme
        // resolves in the same context where the colors are consumed.
        Rectangle {
            id: panel
        anchors.fill: parent
        radius: 12
        color: colorHelper.backgroundColor
        border.width: 1
        border.color: colorHelper.borderColor

        Components.ColorHelper {
            id: colorHelper
        }

        Row {
            id: row
            spacing: gap
            anchors.centerIn: parent

            Repeater {
                id: repeater
                model: Logic.LAYOUTS

                delegate: Item {
                    id: cardItem
                    width: cardW
                    height: cardH

                    readonly property string layoutId: modelData.id
                    readonly property bool isActive: popup.highlightedLayout === modelData.id

                    Components.ColorHelper {
                        id: colorHelper
                    }

                    Rectangle {
                        id: cardBg
                        anchors.fill: parent
                        radius: 8
                        color: isActive ? colorHelper.cardBgActive : colorHelper.cardBgIdle
                        border.width: isActive ? 2 : 1
                        border.color: isActive ? colorHelper.cardBorderActive : colorHelper.cardBorderIdle
                        Behavior on color { ColorAnimation { duration: 90 } }
                        Behavior on border.color { ColorAnimation { duration: 90 } }
                    }

                    Item {
                        id: mini
                        anchors.fill: parent
                        anchors.margins: 9

                        Rectangle {
                            id: screenBg
                            anchors.fill: parent
                            radius: 3
                            color: colorHelper.miniScreenBg
                            border.color: colorHelper.miniScreenBorder
                            border.width: 1
                        }

                        Rectangle {
                            id: fillArea
                            x: mini.width * modelData.fx
                            y: mini.height * modelData.fy
                            width: mini.width * modelData.fw
                            height: mini.height * modelData.fh
                            radius: 2
                            color: isActive ? colorHelper.miniFillActive : colorHelper.miniFillIdle
                            Behavior on color { ColorAnimation { duration: 90 } }
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
