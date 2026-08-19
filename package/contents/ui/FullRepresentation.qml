import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: fullRoot

    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
    Layout.minimumHeight: Kirigami.Units.gridUnit * 26
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.preferredHeight: Kirigami.Units.gridUnit * 28

    spacing: 0

    // Offline / CLI missing state
    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: !root.serviceOnline || !root.cliPresent
        visible: active
        sourceComponent: OfflineHint {}
    }

    // Main content when online
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.serviceOnline && root.cliPresent
        spacing: 0

        // Header
        PlasmaExtras.Heading {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            level: 4
            text: "FrameWidge"
            opacity: 0.8
        }

        // Tab bar
        QQC2.TabBar {
            id: tabBar
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing

            QQC2.TabButton {
                text: i18n("Sensors")
                icon.name: "temperature-warm"
            }
            QQC2.TabButton {
                text: i18n("Fan")
                icon.name: "speedometer"
            }
            QQC2.TabButton {
                text: i18n("Power")
                icon.name: "battery-charging"
            }
            QQC2.TabButton {
                text: i18n("Battery")
                icon.name: "battery-100"
            }
            QQC2.TabButton {
                text: i18n("Settings")
                icon.name: "configure"
            }
        }

        // Tab content
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            SensorsPage {}
            FanPage {}
            PowerPage {}
            BatteryPage {}
            SettingsPage {}
        }
    }
}
