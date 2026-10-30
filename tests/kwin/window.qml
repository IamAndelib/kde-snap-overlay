// A plain test window for the KWin sandbox. The title comes from the last
// command-line argument, so the driver can find the window by caption.
import QtQuick

Window {
    visible: true
    width: 800
    height: 500
    color: "#3b6ea5"
    title: Qt.application.arguments[Qt.application.arguments.length - 1]
}
