// Forked from KZones (https://github.com/gerritdevriese/kzones), Selector.qml
// as of 0.9.3 (GPL-3.0). Used under the project's license; see NOTICE.
// Adaptations: the panel background, border, shadow and margin state machine
// are handled by the owning PlasmaCore.Dialog (native theme background with
// system translucency and blur); this component is the card row with this
// project's dynamic-grid Indicators driven by the live KWin tile splits.
import QtQuick

import "../../code/main.js" as Logic

Item {
    id: selector

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

    // Implicit size drives the owning Dialog's auto-sizing (the standard
    // plasmashell pattern), so the window is born at the panel's size.
    implicitWidth: row.implicitWidth + 2 * selector.pad
    implicitHeight: row.implicitHeight + 2 * selector.pad

    Row {
        id: row

        spacing: selector.gap
        anchors.fill: parent

        Repeater {
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
