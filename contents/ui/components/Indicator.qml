// Ported from KZones (https://github.com/gerritdevriese/kzones), Indicator.qml
// as of 0.9.3 (GPL-3.0). Used under the project's license; see NOTICE.
// Modified: zone rectangles are resolved live from the current KWin tile-grid
// splits (hs/vs) via Logic.zoneRectFrac instead of static percentages, so the
// mini diagrams track the real split while KWin re-tiles windows. Cells are
// painted with Kirigami theme tokens — KWin's trimmed org.kde.plasma.core
// module does not export FrameSvgItem to scripts.
import QtQuick

import "../../code/main.js" as Logic

Rectangle {
    id: indicator

    property int activeZone: -1
    property var zones: []
    property real hs: 0.5
    property real vs: 0.5

    // Sized by the Selector delegate (cardW/cardH).
    color: "transparent"

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

            Rectangle {
                property int padding: 2

                anchors.fill: parent
                anchors.margins: padding
                color: activeZone === index
                    ? colorHelper.accentColor
                    : colorHelper.buttonColor
                border.color: colorHelper.getBorderColor(color)
                border.width: 1
                radius: 5

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }
        }
    }

    ColorHelper {
        id: colorHelper
    }
}
