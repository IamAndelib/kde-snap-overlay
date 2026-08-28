import QtQuick
import org.kde.kirigami as Kirigami

Item {
    Kirigami.Theme.colorSet: Kirigami.Theme.View

    property var theme: {
        const brightness = Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor);
        return brightness === Kirigami.ColorUtils.Light ? "light" : "dark";
    }
    function getBorderColor(c) {
        if (theme === "light") return Kirigami.ColorUtils.tintWithAlpha(c, "black", 0.15)
        if (theme === "dark") return Kirigami.ColorUtils.tintWithAlpha(c, "white", 0.10)
        return c
    }
    function withAlpha(c, a) {
        if (!c) return c
        return Qt.rgba(c.r, c.g, c.b, a)
    }
    property var backgroundColor: {
        if (theme === "light") return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "white", 0.45)
        if (theme === "dark") return Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, "black", 0.30)
    }
    property var borderColor: getBorderColor(backgroundColor)
    property var fgColor: Kirigami.Theme.textColor
    property var highColor: Kirigami.Theme.highlightColor
    property var cardBgIdle: withAlpha(fgColor, 0.08)
    property var cardBgActive: highColor
    property var cardBorderIdle: withAlpha(fgColor, 0.18)
    property var cardBorderActive: withAlpha(highColor, 0.95)
    property var miniScreenBg: backgroundColor
    property var miniScreenBorder: withAlpha(fgColor, 0.35)
    property var miniFillIdle: withAlpha(highColor, 0.5)
    property var miniFillActive: highColor
    property var dividerColor: withAlpha(fgColor, 0.3)
}
