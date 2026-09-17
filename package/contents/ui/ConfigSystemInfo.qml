import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "js/Api.js" as Api

// Everything that used to be the popup's separate "Settings" tab, moved
// here so configuration lives in one place (the right-click "Configure..."
// dialog) instead of being split between it and an in-popup tab. This page
// is self-contained: it fetches its own data straight from the backend
// using plasmoid.configuration.servicePort, since the config dialog runs
// outside main.qml's object tree and has no access to root's live state
// (root.configData, root.thermalData, ...).
KCM.SimpleKCM {
    id: page

    readonly property string baseUrl: "http://127.0.0.1:" + plasmoid.configuration.servicePort

    property string serviceVersion: ""
    property var systemInfo: null
    property var versionsInfo: null
    property int telemetryPollMs: 2000
    property string logs: ""
    property bool logsLoaded: false

    Component.onCompleted: {
        Api.get(baseUrl + "/api/health", function(ok, data) {
            if (ok && data) page.serviceVersion = data.service_version || "";
        });
        Api.get(baseUrl + "/api/system", function(ok, data) {
            if (ok && data) page.systemInfo = data;
        });
        Api.get(baseUrl + "/api/versions", function(ok, data) {
            if (ok && data) page.versionsInfo = data;
        });
        Api.get(baseUrl + "/api/config", function(ok, data) {
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
                    Api.post(baseUrl + "/api/config", { telemetry: { poll_ms: value, retain_seconds: 1800 } }, function() {});
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: i18n("Web UI:")
            }
            QQC2.Label {
                text: "http://127.0.0.1:" + plasmoid.configuration.servicePort
                textFormat: Text.RichText
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally(page.baseUrl)
                }
            }
            Item { Layout.fillWidth: true }
            QQC2.Label {
                text: '<a href="https://github.com/ozturkkl/framework-control">framework-control on GitHub</a>'
                textFormat: Text.RichText
                onLinkActivated: function(link) { Qt.openUrlExternally(link); }
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
                    var xhr = new XMLHttpRequest();
                    xhr.onreadystatechange = function() {
                        if (xhr.readyState === XMLHttpRequest.DONE) {
                            page.logs = xhr.status === 200 ? xhr.responseText : i18n("Failed to load logs");
                            page.logsLoaded = true;
                        }
                    };
                    xhr.open("GET", page.baseUrl + "/api/logs");
                    xhr.send();
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
