import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "js/Api.js" as Api

ColumnLayout {
    id: settingsPage
    spacing: Kirigami.Units.smallSpacing

    property string serviceVersion: root.serviceVersion
    property var systemInfo: null
    property var versionsInfo: null
    property string logs: ""
    property bool logsVisible: false

    Component.onCompleted: {
        Api.get(root.baseUrl + "/api/system", function(ok, data) {
            if (ok && data) systemInfo = data;
        });
        Api.get(root.baseUrl + "/api/versions", function(ok, data) {
            if (ok && data) versionsInfo = data;
        });
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Service version:")
            text: serviceVersion || "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("CPU:")
            text: systemInfo ? (systemInfo.cpu || "—") : "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Memory:")
            text: systemInfo ? (systemInfo.memory_total_mb + " MB") : "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("OS:")
            text: systemInfo ? (systemInfo.os || "—") : "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("BIOS:")
            text: versionsInfo && versionsInfo.uefi_version ? versionsInfo.uefi_version : "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Mainboard:")
            text: versionsInfo && versionsInfo.mainboard_type ? versionsInfo.mainboard_type : "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("framework_tool:")
            text: versionsInfo && versionsInfo.tool_version ? versionsInfo.tool_version : "—"
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // Telemetry config
    PlasmaExtras.Heading {
        Layout.leftMargin: Kirigami.Units.smallSpacing
        level: 5
        text: i18n("Telemetry")
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label { text: i18n("Poll (ms):") }

        QQC2.SpinBox {
            from: 500
            to: 10000
            stepSize: 500
            value: root.configData && root.configData.telemetry ? root.configData.telemetry.poll_ms : 2000
            editable: true
            onValueModified: {
                root.saveConfig({ telemetry: { poll_ms: value, retain_seconds: 1800 } });
            }
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // Logs
    PlasmaComponents.Button {
        Layout.leftMargin: Kirigami.Units.largeSpacing
        text: logsVisible ? i18n("Hide Logs") : i18n("Show Logs")
        icon.name: "utilities-log-viewer"
        onClicked: {
            if (!logsVisible) {
                Api.get(root.baseUrl + "/api/logs", function(ok, data) {
                    // /api/logs returns plain text, but Api.js tries JSON parse
                    // Handled gracefully: data will be null, use raw approach
                    logsVisible = true;
                });
                // Direct fetch for plain text
                var xhr = new XMLHttpRequest();
                xhr.onreadystatechange = function() {
                    if (xhr.readyState === XMLHttpRequest.DONE) {
                        logs = xhr.status === 200 ? xhr.responseText : i18n("Failed to load logs");
                    }
                };
                xhr.open("GET", root.baseUrl + "/api/logs");
                xhr.send();
            } else {
                logsVisible = false;
            }
        }
    }

    QQC2.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: logsVisible

        QQC2.TextArea {
            readOnly: true
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: logs
            wrapMode: TextEdit.WrapAnywhere
        }
    }

    Kirigami.Separator { Layout.fillWidth: true; visible: !logsVisible }

    // Links
    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        visible: !logsVisible
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: i18n("Web UI: http://127.0.0.1:%1", plasmoid.configuration.servicePort)
            opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally("http://127.0.0.1:" + plasmoid.configuration.servicePort)
            }
        }

        PlasmaComponents.Label {
            text: '<a href="https://github.com/ozturkkl/framework-control">github.com/ozturkkl/framework-control</a>'
            textFormat: Text.RichText
            opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            onLinkActivated: function(link) { Qt.openUrlExternally(link); }
        }
    }

    Item { Layout.fillHeight: true; visible: !logsVisible }
}
