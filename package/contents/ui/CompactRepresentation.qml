import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

import "js/ColorGrading.js" as ColorGrading

MouseArea {
    id: compactRoot
    acceptedButtons: Qt.LeftButton
    onClicked: root.expanded = !root.expanded

    hoverEnabled: true

    // The tray entry is a single icon with no visible text, so it needs an
    // explicit accessible name/description for screen readers - the
    // tooltip alone isn't exposed to assistive tech the same way.
    Accessible.role: Accessible.Button
    Accessible.name: root.toolTipMainText
    Accessible.description: root.toolTipSubText

    property real displayValue: {
        var mode = plasmoid.configuration.compactDisplay;
        if (mode === "rpm") return root.fanRpm;
        if (mode === "soc") return root.batterySoc;
        return root.cpuTemp; // default: temp
    }

    property string displayUnit: {
        var mode = plasmoid.configuration.compactDisplay;
        if (mode === "rpm") return "";
        if (mode === "soc") return "%";
        return "°";
    }

    // Overlay scale factor from the KCM (percent of the default size).
    // Clamped defensively: the SpinBox enforces 50-200, but the kcfg value
    // itself has no bounds and could be hand-edited in the config file.
    readonly property real overlayScale: Math.max(0.5, Math.min(2.0, plasmoid.configuration.compactOverlayScale / 100))

    // Shared color map for all ColorGrading calls; the band color tokens in
    // the KCM config ("positive" etc.) resolve against these, so the default
    // band colors automatically follow the active Breeze color scheme.
    readonly property var themeColors: ({
        disabled: Kirigami.Theme.disabledTextColor,
        negative: Kirigami.Theme.negativeTextColor,
        neutral: Kirigami.Theme.neutralTextColor,
        positive: Kirigami.Theme.positiveTextColor,
        text: Kirigami.Theme.textColor
    })

    // The overlay text color is graded by the displayed value through the
    // user-configurable bands (KCM). parseOverlayBands falls back to the
    // built-in defaults on any invalid/missing config, so this never fails.
    readonly property var overlayBands: ColorGrading.parseOverlayBands(plasmoid.configuration.compactOverlayBands)
    readonly property color overlayTextColor: ColorGrading.gradeBandColor(
        root.serviceOnline, displayValue,
        overlayBands[plasmoid.configuration.compactDisplay] || [],
        themeColors)

    // The status dot is a health indicator, not a data readout - it must
    // always grade by temperature regardless of what compactDisplay is
    // showing (unlike the overlay text, which grades by the displayed value
    // through the configurable bands). Passing compactDisplay's actual mode
    // here (e.g. "icon") made gradeIndicatorColor fall through to a flat,
    // never-changing text color - this is the fix for that.
    property color statusDotColor: ColorGrading.gradeIndicatorColor(
        root.serviceOnline, "temp", root.cpuTemp, themeColors)

    // "icon" mode shows the plain icon (+ a small status dot). The other
    // modes (temp/rpm/soc) show the live number by itself, unless
    // compactShowIcon is also set, in which case both share the slot
    // (icon on top, number below) rather than one replacing the other.
    readonly property bool showIconOnly: plasmoid.configuration.compactDisplay === "icon"
    readonly property bool showCombined: !showIconOnly && plasmoid.configuration.compactShowIcon

    // The icon always keeps its original size and centered position,
    // whether it's shown alone or combined with a data value - only the
    // value's presence/absence changes, never the icon's layout.
    Kirigami.Icon {
        id: trayIcon
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        source: Qt.resolvedUrl("icons/framewidge.svg")
        // isMask repaints the SVG as a flat silhouette in `color`, the same
        // way Breeze's own symbolic tray icons adapt to light/dark panels -
        // the source file's own fill/stroke colors are irrelevant once masked.
        isMask: true
        color: Kirigami.Theme.textColor
        active: compactRoot.containsMouse
        opacity: root.serviceOnline ? 1.0 : 0.4
        visible: compactRoot.showIconOnly || compactRoot.showCombined
        Accessible.ignored: true // compactRoot already exposes the accessible name/description
    }

    Rectangle {
        id: statusDot
        visible: compactRoot.showIconOnly && root.serviceOnline
        width: Math.max(4, trayIcon.width * 0.22)
        height: width
        radius: width / 2
        color: compactRoot.statusDotColor
        border.color: Kirigami.Theme.backgroundColor
        border.width: 1
        anchors.right: trayIcon.right
        anchors.bottom: trayIcon.bottom
        anchors.rightMargin: -width * 0.15
        anchors.bottomMargin: -width * 0.15
        Accessible.ignored: true
    }

    // The overlay texts sit on a pill background again: value-graded colored
    // text directly on the panel is unreadable against some wallpapers/theme
    // colors. Semi-transparent (0.75) rather than the fully opaque fill the
    // badge originally had, so the panel's blur still shows through a bit.
    function pillColor() {
        var c = Kirigami.Theme.backgroundColor;
        return Qt.rgba(c.r, c.g, c.b, 0.75);
    }

    // Combined mode: the value sits on a small pill at the icon's
    // bottom-right corner, instead of stacking it directly under/over the
    // icon - the icon stays exactly as it looks in icon-only mode, with the
    // number as a secondary annotation rather than competing for the same
    // space. No border, per the earlier design pass.
    Rectangle {
        id: valueBadge
        visible: compactRoot.showCombined && root.serviceOnline
        width: badgeText.contentWidth + height * 0.7
        // Only marginally taller than the text: contentHeight already
        // includes the font's line spacing, so just 2px of slack on top.
        height: badgeText.contentHeight + 2
        radius: height / 2
        color: compactRoot.pillColor()
        anchors.right: trayIcon.right
        anchors.bottom: trayIcon.bottom
        anchors.rightMargin: -width * 0.3
        anchors.bottomMargin: -height * 0.25
        Accessible.ignored: true

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: compactRoot.displayValue >= 0 ? Math.round(compactRoot.displayValue) + compactRoot.displayUnit : "–"
            color: compactRoot.overlayTextColor
            font.bold: true
            font.pixelSize: Math.max(5, trayIcon.height * 0.35 * compactRoot.overlayScale)
        }
    }

    // Data-only mode (compactShowIcon off): the number fills the whole slot,
    // on the same semi-transparent pill as the combined-mode badge.
    Rectangle {
        id: valuePill
        visible: valueLabel.visible
        opacity: root.serviceOnline ? 1.0 : 0.4
        anchors.centerIn: parent
        width: Math.min(parent.width, valueLabel.contentWidth + Kirigami.Units.largeSpacing)
        // Only marginally taller than the text: contentHeight already
        // includes the font's line spacing, so just 2px of slack on top.
        height: Math.min(parent.height, valueLabel.contentHeight + 2)
        radius: height / 2
        color: compactRoot.pillColor()
        Accessible.ignored: true
    }

    Text {
        id: valueLabel
        anchors.fill: parent
        visible: !compactRoot.showIconOnly && !compactRoot.showCombined
        opacity: root.serviceOnline ? 1.0 : 0.4
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.serviceOnline && compactRoot.displayValue >= 0
            ? Math.round(compactRoot.displayValue) + compactRoot.displayUnit
            : "–"
        color: compactRoot.overlayTextColor
        font.bold: true
        fontSizeMode: Text.Fit
        minimumPixelSize: 6
        font.pixelSize: height * compactRoot.overlayScale
        Accessible.ignored: true // compactRoot already exposes the accessible name/description
    }

    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: root.toolTipMainText
        subText: root.toolTipSubText
    }
}
