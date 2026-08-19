import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: offlineRoot
    spacing: Kirigami.Units.largeSpacing

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.margins: Kirigami.Units.largeSpacing

    Item { Layout.fillHeight: true }

    Kirigami.Icon {
        Layout.alignment: Qt.AlignHCenter
        width: Kirigami.Units.iconSizes.huge
        height: width
        source: root.serviceOnline ? "dialog-warning" : "network-disconnect"
        opacity: 0.6
    }

    PlasmaExtras.Heading {
        Layout.alignment: Qt.AlignHCenter
        level: 3
        text: {
            if (!root.serviceOnline)
                return i18n("Service Not Reachable");
            if (!root.cliPresent)
                return i18n("framework_tool Not Found");
            return "";
        }
    }

    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.7
        text: {
            if (!root.serviceOnline)
                return i18n("The framework-control backend service is not running or not installed.\n\nInstall it with the command below, or start it if already installed.");
            if (!root.cliPresent)
                return i18n("The service is running but cannot find framework_tool.\nCheck the service logs for details.");
            return "";
        }
    }

    // Install command
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: !root.serviceOnline
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            Layout.fillWidth: true
            font.bold: true
            text: i18n("Install:")
        }

        QQC2.TextArea {
            id: installCmd
            Layout.fillWidth: true
            readOnly: true
            wrapMode: TextEdit.WrapAnywhere
            font.family: "monospace"
            text: "curl -fsSL https://raw.githubusercontent.com/ozturkkl/framework-control/main/install-linux.sh | sudo bash"
            background: Rectangle {
                color: Kirigami.Theme.alternateBackgroundColor
                radius: 4
            }
        }

        PlasmaComponents.Button {
            Layout.alignment: Qt.AlignRight
            icon.name: "edit-copy"
            text: i18n("Copy")
            onClicked: {
                installCmd.selectAll();
                installCmd.copy();
                installCmd.deselect();
            }
        }
    }

    // Start hint
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: !root.serviceOnline
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            Layout.fillWidth: true
            font.bold: true
            text: i18n("Already installed? Start the service:")
        }

        QQC2.TextArea {
            Layout.fillWidth: true
            readOnly: true
            font.family: "monospace"
            text: "sudo systemctl start framework-control && sudo systemctl enable framework-control"
            wrapMode: TextEdit.WrapAnywhere
            background: Rectangle {
                color: Kirigami.Theme.alternateBackgroundColor
                radius: 4
            }
        }
    }

    // Port info
    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: !root.serviceOnline
        wrapMode: Text.WordWrap
        opacity: 0.5
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        text: i18n("Trying port %1. Change in widget settings if different.", plasmoid.configuration.servicePort)
    }

    Item { Layout.fillHeight: true }
}
