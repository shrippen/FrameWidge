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

    // "icon" mode shows the plain icon (+ a small status dot); the other
    // modes (temp/rpm/soc) replace it with the live number itself, since an
    // icon and a readable number rarely both fit in a ~16-22px tray slot.
    readonly property bool showIconOnly: plasmoid.configuration.compactDisplay === "icon"

    Kirigami.Icon {
        id: trayIcon
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        source: "cpu"
        active: compactRoot.containsMouse
        opacity: root.serviceOnline ? 1.0 : 0.4
        visible: compactRoot.showIconOnly
        Accessible.ignored: true // compactRoot already exposes the accessible name/description
    }

    Rectangle {
        id: statusDot
        visible: compactRoot.showIconOnly && root.serviceOnline
        width: Math.max(4, trayIcon.width * 0.22)
        height: width
        radius: width / 2
        color: compactRoot.indicatorColor
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
        anchors.fill: parent
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
