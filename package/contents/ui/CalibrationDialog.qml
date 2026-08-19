import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "js/Api.js" as Api

QQC2.Dialog {
    id: calibrationDialog
    title: i18n("Fan Calibration")
    modal: true
    standardButtons: QQC2.Dialog.NoButton
    width: Kirigami.Units.gridUnit * 20
    height: Kirigami.Units.gridUnit * 12

    property bool running: false
    property real progress: 0
    property string info: ""
    property string prevMode: "curve"

    signal calibrationDone(var points)

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: !running
            text: i18n("Calibrate to enable accurate RPM overlay.\nThis takes about a minute and will spin the fan at different speeds.\nYour current fan settings will be restored after calibration.")
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: running
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: info
            }

            QQC2.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 100
                value: progress
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Item { Layout.fillWidth: true }

            PlasmaComponents.Button {
                text: running ? i18n("Cancel") : i18n("Cancel")
                onClicked: {
                    running = false;
                    calibrationDialog.close();
                }
            }

            PlasmaComponents.Button {
                text: i18n("Start Calibration")
                visible: !running
                highlighted: true
                onClicked: startCalibration()
            }
        }
    }

    function startCalibration() {
        running = true;
        progress = 10;
        info = i18n("Starting calibration...");

        // Save current mode
        Api.get(root.baseUrl + "/api/config", function(ok, data) {
            if (ok && data && data.fan && data.fan.mode) {
                prevMode = data.fan.mode;
            }
            runDuties([100, 80, 60, 40, 20], 0, []);
        });
    }

    function runDuties(duties, index, results) {
        if (!running || index >= duties.length) {
            finishCalibration(results);
            return;
        }

        var duty = duties[index];
        info = i18n("Testing %1% duty...", duty);
        progress = Math.round(((index + 1) / duties.length) * 90);

        // Set manual mode at duty
        root.saveConfig({
            fan: {
                mode: "manual",
                manual: { duty_pct: duty }
            }
        }, function(ok) {
            // Wait for RPM to stabilize, then read
            stabilizeTimer.duty = duty;
            stabilizeTimer.duties = duties;
            stabilizeTimer.index = index;
            stabilizeTimer.results = results;
            stabilizeTimer.attempts = 0;
            stabilizeTimer.readings = [];
            stabilizeTimer.start();
        });
    }

    Timer {
        id: stabilizeTimer
        interval: 500
        repeat: true
        property int duty: 0
        property var duties: []
        property int index: 0
        property var results: []
        property int attempts: 0
        property var readings: []

        onTriggered: {
            if (!running) { stop(); return; }
            attempts++;

            Api.get(root.baseUrl + "/api/thermal", function(ok, data) {
                if (!ok || !data || !data.fans || data.fans.length === 0) {
                    if (attempts > 20) {
                        stop();
                        results.push([duty, 0]);
                        runDuties(duties, index + 1, results);
                    }
                    return;
                }

                var rpm = data.fans[0].rpm || 0;
                if (rpm > 0) readings.push(rpm);

                if (readings.length >= 5) {
                    // Check stability
                    var sum = 0;
                    for (var i = 0; i < readings.length; i++) sum += readings[i];
                    var mean = sum / readings.length;
                    var variance = 0;
                    for (var j = 0; j < readings.length; j++) {
                        var d = readings[j] - mean;
                        variance += d * d;
                    }
                    var stdev = Math.sqrt(variance / readings.length);

                    if (stdev <= 30 || attempts > 20) {
                        stop();
                        var sorted = readings.slice().sort(function(a, b) { return a - b; });
                        var median = sorted[Math.floor(sorted.length / 2)];
                        results.push([duty, median]);
                        runDuties(duties, index + 1, results);
                        return;
                    }

                    if (readings.length > 5) readings.shift();
                }

                if (attempts > 20) {
                    stop();
                    results.push([duty, 0]);
                    runDuties(duties, index + 1, results);
                }
            });
        }
    }

    function finishCalibration(results) {
        if (!running) return;
        progress = 95;
        info = i18n("Saving calibration...");

        results.push([0, 0]);
        results.sort(function(a, b) { return a[0] - b[0]; });

        root.saveConfig({
            fan: {
                mode: prevMode,
                calibration: {
                    points: results,
                    updated_at: Math.floor(Date.now() / 1000)
                }
            }
        }, function(ok) {
            progress = 100;
            info = i18n("Done!");
            running = false;
            calibrationDone(results);
            calibrationDialog.close();
        });
    }
}
