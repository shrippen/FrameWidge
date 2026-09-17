import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "js/ColorGrading.js" as ColorGrading

ColumnLayout {
    id: fullRoot

    // Brand accent per DESIGN.md - reserved for the icon mark and small
    // live-status accents, everything else stays on Kirigami.Theme.*
    readonly property color brandAccent: "#E8DCC4"

    // Width is fixed: the tab content (sliders, ComboBoxes, curve graph)
    // doesn't reflow sensibly when squeezed or stretched horizontally, so
    // min/max/preferred all pin to the same value and only height can be
    // resized. The minimum height guarantees header + tab bar + a usable
    // sliver of content always fit; the ScrollView below is the safety net
    // for whatever a window manager lets the user shrink it to anyway (some
    // Plasma popup dialogs don't strictly enforce this floor at screen
    // edges), so controls scroll into view instead of being clipped under
    // the panel.
    readonly property int fixedWidth: Kirigami.Units.gridUnit * 24
    Layout.minimumWidth: fixedWidth
    Layout.maximumWidth: fixedWidth
    Layout.preferredWidth: fixedWidth
    Layout.minimumHeight: Kirigami.Units.gridUnit * 18
    Layout.preferredHeight: Kirigami.Units.gridUnit * 28

    spacing: 0

    // Offline / CLI missing state
    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        active: !root.serviceOnline || !root.cliPresent
        visible: active
        opacity: active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
        sourceComponent: OfflineHint {}
    }

    // Main content when online
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.serviceOnline && root.cliPresent
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.longDuration } }
        spacing: 0

        // Header
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                id: brandMark
                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.6
                Layout.preferredHeight: width
                radius: Kirigami.Units.cornerRadius
                color: fullRoot.brandAccent
                Accessible.ignored: true // decorative; the heading label next to it carries the name

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    text: "F"
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
                    color: "#282828" // fixed dark ink on the fixed-light brand chip, not theme-dependent
                }
            }

            PlasmaExtras.Heading {
                level: 4
                text: "FrameWidge"
            }

            Item { Layout.fillWidth: true }

            // Live at-a-glance status: colored dot + current CPU temperature
            RowLayout {
                spacing: Kirigami.Units.smallSpacing / 2

                Rectangle {
                    Layout.preferredWidth: Kirigami.Units.smallSpacing
                    Layout.preferredHeight: width
                    radius: width / 2
                    color: ColorGrading.gradeIndicatorColor(root.serviceOnline, "temp", root.cpuTemp, {
                        disabled: Kirigami.Theme.disabledTextColor,
                        negative: Kirigami.Theme.negativeTextColor,
                        neutral: Kirigami.Theme.neutralTextColor,
                        positive: Kirigami.Theme.positiveTextColor,
                        text: Kirigami.Theme.textColor
                    })
                    Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
                    Accessible.ignored: true // decorative; the label next to it carries the same info as text
                }

                PlasmaComponents.Label {
                    text: root.cpuTemp >= 0 ? i18n("%1 °C", Math.round(root.cpuTemp)) : ""
                    opacity: 0.9
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.3
                    Accessible.name: root.cpuTemp >= 0 ? i18n("CPU temperature: %1 °C", Math.round(root.cpuTemp)) : i18n("CPU temperature unavailable")
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Tab bar
        QQC2.TabBar {
            id: tabBar
            Layout.fillWidth: true

            QQC2.TabButton {
                text: i18n("Sensors")
                // "-symbolic" specifically: the plain names resolve to
                // Breeze's full-color status icons, not monochrome ones -
                // confirmed by rendering both side by side before this change.
                icon.name: "temperature-warm-symbolic"
            }
            QQC2.TabButton {
                text: i18n("Fan")
                icon.name: "speedometer-symbolic"
            }
            QQC2.TabButton {
                id: powerTab
                text: i18n("Power")
                // No "-symbolic" icon fit "power management" well enough, so
                // this is our own glyph. icon.color does NOT recolor a custom
                // icon.source on QQC2.TabButton (verified empirically - it
                // only auto-tints named theme icons), so Kirigami.Icon's
                // isMask is used directly via a custom contentItem instead.
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: width
                        source: Qt.resolvedUrl("icons/tab-power.svg")
                        isMask: true
                        color: Kirigami.Theme.textColor
                    }
                    PlasmaComponents.Label {
                        text: powerTab.text
                    }
                }
            }
            QQC2.TabButton {
                text: i18n("Battery")
                icon.name: "battery-100-symbolic"
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // Tab content - scrollable so a popup squeezed shorter than its
        // contents still lets you reach every control, instead of clipping
        // the bottom of the page off under the panel.
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            StackLayout {
                width: parent.width
                currentIndex: tabBar.currentIndex

                SensorsPage {}
                FanPage {}
                PowerPage {}
                BatteryPage {}
            }
        }
    }
}
