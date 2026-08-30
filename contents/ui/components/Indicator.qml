// Ported from KZones (https://github.com/gerritdevriese/kzones), Indicator.qml
// as of 0.9.3 (GPL-3.0). Used under the project's license; see NOTICE.
// Modified: zone rectangles are resolved live from the current KWin tile-grid
// splits (hs/vs) via Logic.zoneRectFrac instead of static percentages, so the
// mini diagrams track the real split while KWin re-tiles windows; idle cells
// use the Plasma theme's widget background (native translucency per theme)
// and the active cell is highlighted with the system accent color.
import QtQuick
import org.kde.plasma.core as PlasmaCore

import "../../code/main.js" as Logic

Rectangle {
    id: indicator

    property int activeZone: -1
    property bool hovering: false
    property var zones: []
    property real hs: 0.5
    property real vs: 0.5

    width: parent.width
    height: parent.height
    color: "transparent"
    opacity: 1

    Repeater {
        id: indicators

        model: zones

        Item {
            id: zone

            property var frac: Logic.zoneRectFrac(modelData.id, indicator.hs, indicator.vs)

            x: frac.fx * indicator.width
            y: frac.fy * indicator.height
            width: frac.fw * indicator.width
            height: frac.fh * indicator.height

            // Idle + active cells share the Plasma theme's widget background:
            // native translucency and border, consistent with shell widgets.
            PlasmaCore.FrameSvgItem {
                anchors.fill: parent
                anchors.margins: 2
                imagePath: "widgets/background"
            }

            // Active cell: the system accent highlight layered on top of the
            // themed frame.
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                color: colorHelper.accentColor
                opacity: activeZone === index ? 0.35 : 0
                border.color: colorHelper.accentColor
                border.width: activeZone === index ? 2 : 0
                radius: 5

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }
        }
    }

    ColorHelper {
        id: colorHelper
    }
}
