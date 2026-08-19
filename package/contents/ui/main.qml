import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

import "js/Api.js" as Api

PlasmoidItem {
    id: root

    // Service state
    property bool serviceOnline: false
    property bool cliPresent: false
    property string serviceVersion: ""

    // Thermal data
    property var thermalData: null
    property var thermalHistory: []

    // Power data
    property var powerData: null

    // Config data
    property var configData: null

    // Computed
    property real cpuTemp: {
        if (!thermalData || !thermalData.temps) return -1;
        var temps = thermalData.temps;
        if (temps["APU"] !== undefined) return temps["APU"];
        if (temps["CPU"] !== undefined) return temps["CPU"];
        var keys = Object.keys(temps);
        if (keys.length > 0) return temps[keys[0]];
        return -1;
    }

    property int fanRpm: {
        if (!thermalData || !thermalData.fans || thermalData.fans.length === 0) return -1;
        return thermalData.fans[0].rpm || -1;
    }

    property int batterySoc: {
        if (!powerData || !powerData.battery) return -1;
        return powerData.battery.percentage !== undefined ? powerData.battery.percentage : -1;
    }

    Plasmoid.icon: "cpu"
    toolTipMainText: "FrameWidge"
    toolTipSubText: {
        if (!serviceOnline) return i18n("Service offline");
        if (!cliPresent) return i18n("framework_tool not found");
        var parts = [];
        if (cpuTemp >= 0) parts.push(i18n("CPU: %1 °C", Math.round(cpuTemp)));
        if (fanRpm >= 0) parts.push(i18n("Fan: %1 RPM", fanRpm));
        if (batterySoc >= 0) parts.push(i18n("Battery: %1%", batterySoc));
        return parts.length > 0 ? parts.join(" | ") : i18n("Connected");
    }

    switchWidth: Kirigami.Units.gridUnit * 20
    switchHeight: Kirigami.Units.gridUnit * 24

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    property string baseUrl: "http://127.0.0.1:" + plasmoid.configuration.servicePort

    Timer {
        id: healthTimer
        interval: plasmoid.configuration.pollIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollHealth()
    }

    Timer {
        id: dataTimer
        interval: Math.max(1000, plasmoid.configuration.pollIntervalMs)
        running: root.serviceOnline
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollData()
    }

    function pollHealth() {
        Api.get(baseUrl + "/api/health", function(ok, data) {
            if (ok && data) {
                serviceOnline = true;
                cliPresent = data.cli_present || false;
                serviceVersion = data.service_version || "";
            } else {
                serviceOnline = false;
                cliPresent = false;
            }
        });
    }

    function pollData() {
        if (!serviceOnline || !cliPresent) return;

        Api.get(baseUrl + "/api/thermal", function(ok, data) {
            if (ok && data) thermalData = data;
        });

        Api.get(baseUrl + "/api/power", function(ok, data) {
            if (ok && data) powerData = data;
        });
    }

    function loadConfig() {
        Api.get(baseUrl + "/api/config", function(ok, data) {
            if (ok && data) configData = data;
        });
    }

    function saveConfig(patch, callback) {
        Api.post(baseUrl + "/api/config", patch, function(ok, data) {
            if (ok) loadConfig();
            if (callback) callback(ok);
        });
    }

    function loadThermalHistory() {
        Api.get(baseUrl + "/api/thermal/history", function(ok, data) {
            if (ok && data) thermalHistory = data;
        });
    }

    Component.onCompleted: {
        pollHealth();
    }
}
