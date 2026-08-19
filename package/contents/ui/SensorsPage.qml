import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "js/Api.js" as Api

ColumnLayout {
    id: sensorsPage
    spacing: Kirigami.Units.smallSpacing

    property var availableSensors: []
    property var selectedSensors: []
    property var series: ({})
    property int windowSeconds: 300
    property int telemetryPollMs: 2000

    Component.onCompleted: {
        loadTelemetryConfig();
        fetchHistory();
    }

    Timer {
        id: historyTimer
        interval: Math.max(1000, telemetryPollMs)
        running: true
        repeat: true
        onTriggered: fetchHistory()
    }

    function loadTelemetryConfig() {
        Api.get(root.baseUrl + "/api/config", function(ok, data) {
            if (ok && data && data.telemetry) {
                telemetryPollMs = data.telemetry.poll_ms || 2000;
                historyTimer.interval = Math.max(1000, telemetryPollMs);
            }
        });
        Api.get(root.baseUrl + "/api/thermal", function(ok, data) {
            if (ok && data && data.temps) {
                availableSensors = Object.keys(data.temps);
                if (selectedSensors.length === 0) {
                    selectedSensors = availableSensors.slice();
                }
            }
        });
    }

    function fetchHistory() {
        Api.get(root.baseUrl + "/api/thermal/history", function(ok, data) {
            if (!ok || !data) return;
            var cutoff = Date.now() - windowSeconds * 1000;
            var ser = {};
            for (var i = 0; i < data.length; i++) {
                var s = data[i];
                if (s.ts_ms < cutoff) continue;
                var temps = s.temps || {};
                var keys = Object.keys(temps);
                for (var j = 0; j < keys.length; j++) {
                    var name = keys[j];
                    if (selectedSensors.length > 0 && selectedSensors.indexOf(name) < 0) continue;
                    if (!ser[name]) ser[name] = [];
                    ser[name].push([s.ts_ms, temps[name]]);
                }
            }
            series = ser;
            sensorChart.requestPaint();
        });
    }

    // --- Legend ---
    Flow {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: selectedSensors
            RowLayout {
                spacing: 2
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: sensorColor(modelData)
                }
                PlasmaComponents.Label {
                    text: modelData
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }
    }

    // --- Chart ---
    Canvas {
        id: sensorChart
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10

        readonly property int padLeft: 36
        readonly property int padRight: 12
        readonly property int padTop: 12
        readonly property int padBottom: 22

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            // Collect all timestamps
            var allTimes = [];
            var seriesKeys = Object.keys(series);
            for (var k = 0; k < seriesKeys.length; k++) {
                var pts = series[seriesKeys[k]];
                for (var p = 0; p < pts.length; p++) allTimes.push(pts[p][0]);
            }
            if (allTimes.length === 0) return;

            var tMin = Math.min.apply(null, allTimes);
            var tMax = Math.max.apply(null, allTimes);
            if (tMax === tMin) tMax = tMin + 1;

            var yMin = 0, yMax = 100;
            var w = width - padLeft - padRight;
            var h = height - padTop - padBottom;

            function xPx(t) { return padLeft + ((t - tMin) / (tMax - tMin)) * w; }
            function yPx(v) { return padTop + (1 - (v - yMin) / (yMax - yMin)) * h; }

            // Grid
            ctx.strokeStyle = Kirigami.Theme.disabledTextColor;
            ctx.lineWidth = 0.5;
            for (var d = 0; d <= 100; d += 20) {
                var gy = yPx(d);
                ctx.beginPath(); ctx.moveTo(padLeft, gy); ctx.lineTo(width - padRight, gy); ctx.stroke();
                ctx.fillStyle = Kirigami.Theme.textColor;
                ctx.font = "10px sans-serif";
                ctx.textAlign = "right";
                ctx.fillText(d + "°C", padLeft - 4, gy + 4);
            }

            // Lines
            var colors = ["#e63946", "#457b9d", "#2a9d8f", "#e9c46a", "#f4a261", "#264653", "#6a0572"];
            for (var si = 0; si < seriesKeys.length; si++) {
                var name = seriesKeys[si];
                var data = series[name];
                if (data.length === 0) continue;

                ctx.strokeStyle = sensorColor(name);
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.moveTo(xPx(data[0][0]), yPx(data[0][1]));
                for (var di = 1; di < data.length; di++) {
                    ctx.lineTo(xPx(data[di][0]), yPx(data[di][1]));
                }
                ctx.stroke();
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    function sensorColor(name) {
        var colors = ["#e63946", "#457b9d", "#2a9d8f", "#e9c46a", "#f4a261", "#264653", "#6a0572", "#d62828", "#003049"];
        var hash = 0;
        for (var i = 0; i < name.length; i++) {
            hash = ((hash << 5) - hash) + name.charCodeAt(i);
            hash |= 0;
        }
        return colors[Math.abs(hash) % colors.length];
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // --- Controls ---
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label { text: i18n("Sensors:") }

        Repeater {
            model: availableSensors
            QQC2.CheckBox {
                text: modelData
                checked: selectedSensors.indexOf(modelData) >= 0
                onToggled: {
                    var s = selectedSensors.slice();
                    var idx = s.indexOf(modelData);
                    if (checked && idx < 0) s.push(modelData);
                    else if (!checked && idx >= 0) s.splice(idx, 1);
                    selectedSensors = s;
                    fetchHistory();
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label { text: i18n("Window:") }

        QQC2.Slider {
            Layout.fillWidth: true
            from: 30
            to: 1800
            stepSize: 30
            value: windowSeconds
            onMoved: {
                windowSeconds = Math.round(value);
                fetchHistory();
            }
        }

        PlasmaComponents.Label {
            text: {
                var m = Math.floor(windowSeconds / 60);
                var s = windowSeconds % 60;
                return m + ":" + (s < 10 ? "0" : "") + s;
            }
            Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
        }
    }
}
