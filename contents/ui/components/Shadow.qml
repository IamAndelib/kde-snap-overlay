// Ported from KZones (https://github.com/gerritdevriese/kzones), Shadow.qml
// as of 0.9.3 (GPL-3.0). Used under the project's license; see NOTICE.
import QtQuick
import QtQuick.Effects

MultiEffect {
    property Item target: null

    anchors.fill: target
    visible: target ? target.visible : false
    opacity: target ? target.opacity : 0
    scale: target ? target.scale : 1
    source: target
    shadowEnabled: true
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 0
    shadowBlur: 1
    shadowColor: colorHelper.getShadowColor()
    autoPaddingEnabled: true

    ColorHelper {
        id: colorHelper
    }
}