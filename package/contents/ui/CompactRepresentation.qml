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

    property color indicatorColor: ColorGrading.gradeIndicatorColor(
        root.serviceOnline, plasmoid.configuration.compactDisplay, root.cpuTemp,
        {
            disabled: Kirigami.Theme.disabledTextColor,
            negative: Kirigami.Theme.negativeTextColor,
            neutral: Kirigami.Theme.neutralTextColor,
            positive: Kirigami.Theme.positiveTextColor,
            text: Kirigami.Theme.textColor
        })

    // The status dot is a health indicator, not a data readout - it must
    // always grade by temperature regardless of what compactDisplay is
    // showing, unlike indicatorColor above (which only grades when the
    // *displayed value itself* is temp). Passing compactDisplay's actual
    // mode here (e.g. "icon") made gradeIndicatorColor fall through to a
    // flat, never-changing text color - this is the fix for that.
    property color statusDotColor: ColorGrading.gradeIndicatorColor(
        root.serviceOnline, "temp", root.cpuTemp,
        {
            disabled: Kirigami.Theme.disabledTextColor,
            negative: Kirigami.Theme.negativeTextColor,
            neutral: Kirigami.Theme.neutralTextColor,
            positive: Kirigami.Theme.positiveTextColor,
            text: Kirigami.Theme.textColor
        })

    // "icon" mode shows the plain icon (+ a small status dot). The other
    // modes (temp/rpm/soc) show the live number by itself, unless
    // compactShowIcon is also set, in which case both share the slot
    // (icon on top, number below) rather than one replacing the other.
    readonly property bool showIconOnly: plasmoid.configuration.compactDisplay === "icon"
    readonly property bool showCombined: !showIconOnly && plasmoid.configuration.compactShowIcon

    Kirigami.Icon {
        id: trayIcon
        anchors.horizontalCenter: parent.horizontalCenter
        y: compactRoot.showCombined ? 0 : (parent.height - height) / 2
        width: compactRoot.showCombined ? parent.height * 0.55 : Math.min(parent.width, parent.height)
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

    Text {
        id: valueLabel
        // Combined mode: number takes the bottom portion, under the icon.
        // Data-only mode: number fills the whole slot.
        y: compactRoot.showCombined ? parent.height * 0.55 : 0
        height: compactRoot.showCombined ? parent.height * 0.45 : parent.height
        width: parent.width
        visible: !compactRoot.showIconOnly
        opacity: root.serviceOnline ? 1.0 : 0.4
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.serviceOnline && compactRoot.displayValue >= 0
            ? Math.round(compactRoot.displayValue) + compactRoot.displayUnit
            : "–"
        color: compactRoot.indicatorColor
        font.bold: true
        fontSizeMode: Text.Fit
        minimumPixelSize: 6
        font.pixelSize: height
        Accessible.ignored: true // compactRoot already exposes the accessible name/description
    }

    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: root.toolTipMainText
        subText: root.toolTipSubText
    }
}
