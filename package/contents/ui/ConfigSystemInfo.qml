import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "js/Api.js" as Api

// Everything that used to be the popup's separate "Settings" tab, moved
// here so configuration lives in one place (the right-click "Configure..."
// dialog) instead of being split between it and an in-popup tab. This page
// is self-contained: it fetches its own data straight from the service
// (js/Api.js), since the config dialog runs
// outside main.qml's object tree and has no access to root's live state
// (root.configData, root.thermalData, ...).
KCM.SimpleKCM {
    id: page

    property alias cfg_debugBackgroundPolling: debugPollCheck.checked

    property string serviceVersion: ""
    property var systemInfo: null
    property var versionsInfo: null
    property int telemetryPollMs: 2000
    property string logs: ""
    property bool logsLoaded: false

    Component.onCompleted: {
        Api.get("Health", function(ok, data) {
            if (ok && data) page.serviceVersion = data.service_version || "";
        });
        Api.get("System", function(ok, data) {
            if (ok && data) page.systemInfo = data;
        });
        Api.get("Versions", function(ok, data) {
            if (ok && data) page.versionsInfo = data;
        });
        Api.get("Config", function(ok, data) {
            if (ok && data && data.telemetry) page.telemetryPollMs = data.telemetry.poll_ms || 2000;
        });
    }

    ColumnLayout {
        width: page.width
        spacing: Kirigami.Units.smallSpacing

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Label {
                Kirigami.FormData.label: i18n("Service version:")
                text: page.serviceVersion || "—"
            }
            QQC2.Label {
                Kirigami.FormData.label: i18n("CPU:")
                text: page.systemInfo ? (page.systemInfo.cpu || "—") : "—"
            }
            QQC2.Label {
                Kirigami.FormData.label: i18n("Memory:")
                text: page.systemInfo ? (page.systemInfo.memory_total_mb + " MB") : "—"
            }
            QQC2.Label {
                Kirigami.FormData.label: i18n("OS:")
                text: page.systemInfo ? (page.systemInfo.os || "—") : "—"
            }
            QQC2.Label {
                Kirigami.FormData.label: i18n("BIOS:")
                text: page.versionsInfo && page.versionsInfo.uefi_version ? page.versionsInfo.uefi_version : "—"
            }
            QQC2.Label {
                Kirigami.FormData.label: i18n("Mainboard:")
                text: page.versionsInfo && page.versionsInfo.mainboard_type ? page.versionsInfo.mainboard_type : "—"
            }
            QQC2.Label {
                Kirigami.FormData.label: i18n("framework_tool:")
                text: page.versionsInfo && page.versionsInfo.tool_version ? page.versionsInfo.tool_version : "—"
            }

            QQC2.SpinBox {
                Kirigami.FormData.label: i18n("Telemetry poll (ms):")
                from: 500
                to: 10000
                stepSize: 500
                value: page.telemetryPollMs
                editable: true
                onValueModified: {
                    page.telemetryPollMs = value;
                    Api.setConfig({ telemetry: { poll_ms: value } });
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.Label {
                Kirigami.FormData.isSection: true
                text: i18n("Debug")
            }

            QQC2.CheckBox {
                id: debugPollCheck
                Kirigami.FormData.label: i18n("Background polling:")
                text: i18n("Keep polling while the popup is closed")
                QQC2.ToolTip.text: i18n("Keeps the tray readout live with the popup closed. Off by default because the service logs every request to the journal.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                level: 5
                text: i18n("Service Logs")
            }
            Item { Layout.fillWidth: true }
            QQC2.Button {
                text: i18n("Reload")
                icon.name: "view-refresh"
                onClicked: {
                    page.logs = i18n("Loading…");
                    Api.callText("Logs", [], function(ok, text) {
                        page.logs = ok ? text : i18n("Failed to load logs");
                        page.logsLoaded = true;
                    });
                }
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 12

            QQC2.TextArea {
                readOnly: true
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: page.logsLoaded ? page.logs : i18n("Click Reload to fetch the service log (last 500 lines).")
                wrapMode: TextEdit.WrapAnywhere
            }
        }
    }
}
