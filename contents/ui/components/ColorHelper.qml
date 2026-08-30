// Design tokens ported from KZones (https://github.com/gerritdevriese/kzones),
// ColorHelper.qml as of 0.9.3 (GPL-3.0). Used under the project's license;
// see NOTICE at the repo root.
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    Kirigami.Theme.colorSet: Kirigami.Theme.View

    property var theme: {
        const brightness = Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor);
        return brightness === Kirigami.ColorUtils.Light ? "light" : "dark";
    }

    property var backgroundColor: {
        if (theme === "light")
            return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "white", 0.45);

        if (theme === "dark")
            return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "black", 0.30);
    }

    property var buttonColor: {
        if (theme === "light")
            return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "black", 0.15);

        if (theme === "dark")
            return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "white", 0.10);
    }

    property var accentColor: {
        return Kirigami.Theme.hoverColor;
    }

    function getShadowColor() {
        if (theme === "light")
            return Qt.rgba(0, 0, 0, 0.2);

        if (theme === "dark")
            return Qt.rgba(0, 0, 0, 0.4);
    }

    function getBorderColor(color) {
        if (theme === "light")
            return Kirigami.ColorUtils.tintWithAlpha(color, "black", 0.15);

        if (theme === "dark")
            return Kirigami.ColorUtils.tintWithAlpha(color, "white", 0.1);
    }
}