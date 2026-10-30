// A stand-in for a Plasma top panel in the KWin sandbox: a layer-shell bar
// with an exclusive zone, so KWin's MaximizeArea starts below it. It opens
// on the active screen (the driver puts the pointer there first; QML cannot
// hand layer-shell-qt a QScreen). Argument: <height>.
import QtQuick
import org.kde.layershell as LayerShell

Window {
    height: parseInt(Qt.application.arguments[Qt.application.arguments.length - 1])
    width: 400
    visible: true
    color: "#202326"
    title: "panel"

    LayerShell.Window.wantsToBeOnActiveScreen: true
    LayerShell.Window.scope: "kso-test-panel"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: height
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone
}
