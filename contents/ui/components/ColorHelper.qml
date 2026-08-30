// Accent color token for the popup cards. The panel background is the native
// Plasma dialog theme and the cards use the Plasma theme's widget background
// frames; only the active-zone highlight needs a token. (Originally derived
// from KZones' ColorHelper — see NOTICE.)
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    // The system accent (hover) color used to highlight the active zone.
    property var accentColor: Kirigami.Theme.hoverColor
}
