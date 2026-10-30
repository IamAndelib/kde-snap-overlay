// A plain test window for the KWin sandbox. The title comes from the last
// command-line argument, so the driver can find the window by caption;
// --fixed-size makes it non-resizable (minimum = maximum size).
import QtQuick

Window {
    readonly property var args: Qt.application.arguments
    readonly property bool fixedSize: args.indexOf("--fixed-size") >= 0

    visible: true
    width: 800
    height: 500
    minimumWidth: fixedSize ? 800 : 0
    maximumWidth: fixedSize ? 800 : 16777215
    minimumHeight: fixedSize ? 500 : 0
    maximumHeight: fixedSize ? 500 : 16777215
    color: "#3b6ea5"
    title: args[args.length - 1]
}
