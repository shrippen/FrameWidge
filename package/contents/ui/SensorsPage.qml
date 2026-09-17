import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "js/Api.js" as Api
import "js/ColorGrading.js" as ColorGrading

ColumnLayout {
    id: sensorsPage
    spacing: Kirigami.Units.smallSpacing

    property var availableSensors: []
    property var selectedSensors: []
    property var series: ({})
    property int windowSeconds: 300
    property int telemetryPollMs: 2000

    // Relative luminance of the theme background, used to tune sensor line
    // colors for contrast (see ColorGrading.sensorColor) instead of relying
    // on one fixed hex palette that only reads well in one color scheme.
    readonly property bool darkTheme: {
        var bg = Kirigami.Theme.backgroundColor;
        return (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b) < 0.5;
    }

    Component.onCompleted: {
        seedTelemetryConfig(root.configData);
        fetchHistory();
    }

    onDarkThemeChanged: sensorChart.requestPaint()

    Connections {
        target: root
        function onConfigDataChanged() { seedTelemetryConfig(root.configData); }
        function onThermalDataChanged() {
            if (!root.thermalData || !root.thermalData.temps) return;
            availableSensors = Object.keys(root.thermalData.temps);
            if (selectedSensors.length === 0) {
                selectedSensors = availableSensors.slice();
            }
        }
    }

    Timer {
        id: historyTimer
        interval: Math.max(1000, telemetryPollMs)
        running: true
        repeat: true
        onTriggered: fetchHistory()
    }

    // Debounces the window-size slider so dragging doesn't fire a fetch per pixel
    Timer {
        id: fetchDebounce
        interval: 250
        onTriggered: fetchHistory()
    }
    function scheduleFetch() { fetchDebounce.restart(); }

    function seedTelemetryConfig(data) {
        if (!data || !data.telemetry) return;
        telemetryPollMs = data.telemetry.poll_ms || 2000;
        historyTimer.interval = Math.max(1000, telemetryPollMs);
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
                    Accessible.ignored: true // decorative; the label next to it names the sensor
                }
                PlasmaComponents.Label {
                    text: modelData
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }
    }

    // --- Chart ---
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10

        readonly property bool hasData: Object.keys(series).length > 0

        Canvas {
            id: sensorChart
            anchors.fill: parent

            // The drawn lines carry no information for screen reader users,
            // so summarize the latest reading per sensor as text instead.
            Accessible.role: Accessible.Graphic
            Accessible.name: {
                var keys = Object.keys(series);
                if (keys.length === 0) return i18n("Sensor temperature chart, no data yet");
                var parts = [];
                for (var i = 0; i < keys.length; i++) {
                    var pts = series[keys[i]];
                    if (pts.length === 0) continue;
                    parts.push(keys[i] + ": " + pts[pts.length - 1][1].toFixed(1) + "°C");
                }
                return i18n("Sensor temperature chart. Latest: %1", parts.join(", "));
            }

            readonly property int padLeft: 36
            readonly property int padRight: 12
            readonly property int padTop: 12
            readonly property int padBottom: 22

            // Set by the MouseArea below; -1 means "not hovering".
            property real hoverX: -1
            property var hoverInfo: null // { time, entries: [{name, value, color}] }

            function xPx(t, tMin, tMax, w) { return padLeft + ((t - tMin) / (tMax - tMin)) * w; }
            function yPx(v, h) { return padTop + (1 - (v - 0) / 100) * h; }

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                var allTimes = [];
                var seriesKeys = Object.keys(series);
                for (var k = 0; k < seriesKeys.length; k++) {
                    var pts = series[seriesKeys[k]];
                    for (var p = 0; p < pts.length; p++) allTimes.push(pts[p][0]);
                }
                if (allTimes.length === 0) { hoverInfo = null; return; }

                var tMin = Math.min.apply(null, allTimes);
                var tMax = Math.max.apply(null, allTimes);
                if (tMax === tMin) tMax = tMin + 1;

                var w = width - padLeft - padRight;
                var h = height - padTop - padBottom;

                // Grid
                ctx.strokeStyle = Kirigami.Theme.disabledTextColor;
                ctx.lineWidth = 0.5;
                for (var d = 0; d <= 100; d += 20) {
                    var gy = yPx(d, h);
                    ctx.beginPath(); ctx.moveTo(padLeft, gy); ctx.lineTo(width - padRight, gy); ctx.stroke();
                    ctx.fillStyle = Kirigami.Theme.textColor;
                    ctx.font = "10px sans-serif";
                    ctx.textAlign = "right";
                    ctx.fillText(d + "°C", padLeft - 4, gy + 4);
                }

                // Lines
                for (var si = 0; si < seriesKeys.length; si++) {
                    var name = seriesKeys[si];
                    var data = series[name];
                    if (data.length === 0) continue;

                    ctx.strokeStyle = sensorColor(name);
                    ctx.lineWidth = 2;
                    ctx.lineJoin = "round";
                    ctx.beginPath();
                    ctx.moveTo(xPx(data[0][0], tMin, tMax, w), yPx(data[0][1], h));
                    for (var di = 1; di < data.length; di++) {
                        ctx.lineTo(xPx(data[di][0], tMin, tMax, w), yPx(data[di][1], h));
                    }
                    ctx.stroke();
                }

                // Hover crosshair: nearest sample per series to the cursor's time
                if (hoverX >= padLeft && hoverX <= width - padRight) {
                    var hoverTime = tMin + ((hoverX - padLeft) / w) * (tMax - tMin);
                    var entries = [];
                    for (var hi = 0; hi < seriesKeys.length; hi++) {
                        var hname = seriesKeys[hi];
                        var hdata = series[hname];
                        if (hdata.length === 0) continue;
                        var nearest = hdata[0];
                        for (var hj = 1; hj < hdata.length; hj++) {
                            if (Math.abs(hdata[hj][0] - hoverTime) < Math.abs(nearest[0] - hoverTime)) nearest = hdata[hj];
                        }
                        entries.push({ name: hname, value: nearest[1], color: sensorColor(hname) });

                        // Highlight the nearest point on its line
                        ctx.fillStyle = sensorColor(hname);
                        ctx.beginPath();
                        ctx.arc(xPx(nearest[0], tMin, tMax, w), yPx(nearest[1], h), 3, 0, 2 * Math.PI);
                        ctx.fill();
                    }
                    hoverInfo = { entries: entries };

                    ctx.strokeStyle = Kirigami.Theme.textColor;
                    ctx.globalAlpha = 0.3;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.moveTo(hoverX, padTop);
                    ctx.lineTo(hoverX, height - padBottom);
                    ctx.stroke();
                    ctx.globalAlpha = 1;
                } else {
                    hoverInfo = null;
                }
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onHoverXChanged: requestPaint()

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: function(mouse) { sensorChart.hoverX = mouse.x; }
                onExited: sensorChart.hoverX = -1
            }
        }

        // Floating readout following the crosshair
        ColumnLayout {
            visible: sensorChart.hoverInfo !== null && sensorChart.hoverInfo.entries.length > 0
            x: Math.min(Math.max(sensorChart.hoverX + Kirigami.Units.smallSpacing, 0), parent.width - width)
            y: Kirigami.Units.smallSpacing
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: readoutColumn.implicitHeight + Kirigami.Units.smallSpacing
                color: Kirigami.Theme.backgroundColor
                opacity: 0.9
                radius: Kirigami.Units.cornerRadius
                border.color: Kirigami.Theme.disabledTextColor
                border.width: 1

                ColumnLayout {
                    id: readoutColumn
                    anchors.centerIn: parent
                    spacing: 0

                    Repeater {
                        model: sensorChart.hoverInfo ? sensorChart.hoverInfo.entries : []
                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing / 2
                            Rectangle { width: 8; height: 8; radius: 4; color: modelData.color; Accessible.ignored: true }
                            PlasmaComponents.Label {
                                text: modelData.name + ": " + modelData.value.toFixed(1) + "°C"
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                    }
                }
            }
        }

        // Empty state
        ColumnLayout {
            anchors.centerIn: parent
            visible: !parent.hasData
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                source: "office-chart-line"
                width: Kirigami.Units.iconSizes.medium
                height: width
                opacity: 0.4
            }
            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignHCenter
                text: i18n("Waiting for sensor data…")
                opacity: 0.5
            }
        }
    }

    function sensorColor(name) {
        return ColorGrading.sensorColor(name, darkTheme);
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
                scheduleFetch();
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
