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

    // Zone outline overlay tokens (v1.2.1 pattern): translucent accent fill
    // with a stronger accent border, over the Kirigami highlight color.
    property var highColor: Kirigami.Theme.highlightColor
    property var overlayFill: withAlpha(highColor, 0.32)
    property var overlayBorder: withAlpha(highColor, 0.85)

    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    function getBorderColor(color) {
        if (theme === "light")
            return Kirigami.ColorUtils.tintWithAlpha(color, "black", 0.15);

        if (theme === "dark")
            return Kirigami.ColorUtils.tintWithAlpha(color, "white", 0.1);
    }
}
