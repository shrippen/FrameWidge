import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

MouseArea {
    id: compactRoot
    acceptedButtons: Qt.LeftButton
    onClicked: root.expanded = !root.expanded

    hoverEnabled: true

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

    property color indicatorColor: {
        if (!root.serviceOnline) return Kirigami.Theme.disabledTextColor;
        var mode = plasmoid.configuration.compactDisplay;
        if (mode === "temp" || mode === undefined) {
            if (root.cpuTemp > 85) return Kirigami.Theme.negativeTextColor;
            if (root.cpuTemp > 70) return Kirigami.Theme.neutralTextColor;
            return Kirigami.Theme.positiveTextColor;
        }
        return Kirigami.Theme.textColor;
    }

    Kirigami.Icon {
        id: trayIcon
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        source: "cpu"
        active: compactRoot.containsMouse
        opacity: root.serviceOnline ? 1.0 : 0.4
    }

    PlasmaCore.ToolTipArea {
        anchors.fill: parent
        mainText: root.toolTipMainText
        subText: root.toolTipSubText
    }
}
