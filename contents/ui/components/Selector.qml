// Forked from KZones (https://github.com/gerritdevriese/kzones), Selector.qml
// as of 0.9.3 (GPL-3.0). Used under the project's license; see NOTICE.
// Adaptations: KZones' hardcoded margins (0 / -height + 30 / -height) become
// shownMargin / -(height - peekHeight) / -height; the cards are this project's
// dynamic-grid Indicators driven by the live KWin tile splits; expansion is
// driven by the owner's distance band (showDistance) plus selector hover.
import QtQuick

import "../../code/main.js" as Logic

Item {
    id: selector

    // Expansion state machine (KZones): fully shown, peeking, or retracted.
    property bool expanded: false
    property bool peeking: false
    // True while the margin animation runs; hover checks pause during it.
    property bool animating: false
    // Margin between the strip top and the selector when fully shown.
    property int shownMargin: 0
    // Visible sliver height while peeking.
    property int peekHeight: 30
    // Panel metrics (this project's card layout).
    property int pad: 14
    property int gap: 10
    property int cardW: 130
    property int cardH: 70
    property var layouts: []
    property string currentLayout: ""
    property string highlightedZone: ""
    property real hSplit: 0.5
    property real vSplit: 0.5

    property alias panel: background

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: expanded ? shownMargin
                        : (peeking ? -(height - peekHeight) : -height)

    Behavior on anchors.topMargin {
        NumberAnimation {
            duration: 150
            onRunningChanged: {
                selector.animating = running
            }
        }
    }

    width: background.width + 30
    height: background.height + 40

    Rectangle {
        id: background

        width: row.implicitWidth + 2 * selector.pad
        height: row.implicitHeight + 2 * selector.pad
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 15
        radius: 10
        color: colorHelper.backgroundColor
        border.color: colorHelper.getBorderColor(color)
        border.width: 1

        Row {
            id: row

            spacing: selector.gap
            anchors.fill: parent
            anchors.margins: selector.pad

            Repeater {
                id: repeater

                model: selector.layouts

                Indicator {
                    zones: modelData.zones
                    activeZone: Logic.zoneIndexInLayout(modelData.id, selector.highlightedZone)
                    hs: selector.hSplit
                    vs: selector.vSplit
                    width: selector.cardW
                    height: selector.cardH
                    hovering: modelData.id === selector.currentLayout
                }
            }
        }
    }

    Shadow {
        target: background
    }

    ColorHelper {
        id: colorHelper
    }
}
