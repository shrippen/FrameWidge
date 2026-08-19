import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "js/Api.js" as Api

ColumnLayout {
    id: fanPage
    spacing: Kirigami.Units.smallSpacing

    property string fanMode: "disabled" // disabled = Auto, manual, curve
    property int manualDutyPct: 50
    property int hysteresisC: 2
    property int rateLimitPctPerStep: 100
    property int rateLimitDownPctPerStep: 100
    property bool rateLimitDownEnabled: false
    property int pollMs: 2000
    property var curvePoints: [[40, 0], [60, 40], [75, 80], [85, 100]]
    property var selectedSensors: []
    property var availableSensors: []

    // Per-fan overrides
    property int fanCount: 0
    property var fanNames: []
    property var overrides: []
    property var activeFan: "all" // "all" or fan index

    // Live data
    property int liveRpm: root.fanRpm
    property real liveTemp: root.cpuTemp

    property bool configLoaded: false

    Component.onCompleted: loadFanConfig()

    function loadFanConfig() {
        Api.get(root.baseUrl + "/api/config", function(ok, data) {
            if (!ok || !data || !data.fan) return;
            var fan = data.fan;
            fanMode = fan.mode || "disabled";
            if (fan.manual) manualDutyPct = fan.manual.duty_pct || 50;
            if (fan.curve) {
                var c = fan.curve;
                curvePoints = c.points || curvePoints;
                hysteresisC = c.hysteresis_c !== undefined ? c.hysteresis_c : 2;
                rateLimitPctPerStep = Math.max(1, c.rate_limit_pct_per_step || 100);
                rateLimitDownEnabled = c.rate_limit_down_pct_per_step !== undefined;
                rateLimitDownPctPerStep = c.rate_limit_down_pct_per_step || rateLimitPctPerStep;
                pollMs = c.poll_ms || 2000;
                selectedSensors = c.sensors || [];
            }
            overrides = fan.overrides || [];
            configLoaded = true;
        });

        // Fetch available sensors
        Api.get(root.baseUrl + "/api/thermal", function(ok, data) {
            if (ok && data && data.temps) {
                availableSensors = Object.keys(data.temps);
            }
            if (ok && data && data.fans) {
                fanCount = data.fans.length;
                var names = [];
                for (var i = 0; i < data.fans.length; i++) {
                    names.push(data.fans[i].name || ("Fan " + (i + 1)));
                }
                fanNames = names;
            }
        });
    }

    function applyMode() {
        var patch = { fan: { mode: fanMode } };
        if (fanMode === "manual") {
            patch.fan.manual = { duty_pct: Math.max(0, Math.min(100, manualDutyPct)) };
        }
        if (fanMode === "curve") {
            patch.fan.curve = buildCurveConfig();
        }
        if (overrides.length > 0) {
            patch.fan.overrides = overrides;
        }
        root.saveConfig(patch);
    }

    function buildCurveConfig() {
        var cfg = {
            points: curvePoints,
            hysteresis_c: hysteresisC,
            rate_limit_pct_per_step: rateLimitPctPerStep,
            poll_ms: pollMs,
            sensors: selectedSensors
        };
        if (rateLimitDownEnabled) {
            cfg.rate_limit_down_pct_per_step = rateLimitDownPctPerStep;
        }
        return cfg;
    }

    // --- Live info ---
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents.Label {
            text: {
                if (fanMode === "disabled") return i18n("Mode: Auto");
                if (fanMode === "manual") return i18n("Mode: Manual (%1%)", manualDutyPct);
                if (fanMode === "curve") return i18n("Mode: Curve");
                return "";
            }
            font.bold: true
        }

        Item { Layout.fillWidth: true }

        PlasmaComponents.Label {
            visible: liveTemp >= 0
            text: i18n("CPU: %1 °C", Math.round(liveTemp))
            opacity: 0.7
        }

        PlasmaComponents.Label {
            visible: liveRpm >= 0
            text: i18n("Fan: %1 RPM", liveRpm)
            opacity: 0.7
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // --- Mode selector ---
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        QQC2.RadioButton {
            text: i18n("Auto")
            checked: fanMode === "disabled"
            onClicked: { fanMode = "disabled"; applyMode(); }
        }
        QQC2.RadioButton {
            text: i18n("Manual")
            checked: fanMode === "manual"
            onClicked: { fanMode = "manual"; applyMode(); }
        }
        QQC2.RadioButton {
            text: i18n("Curve")
            checked: fanMode === "curve"
            onClicked: { fanMode = "curve"; applyMode(); }
        }
    }

    // --- Fan tabs (multi-fan) ---
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        visible: fanCount > 1 && fanMode !== "disabled"
        spacing: Kirigami.Units.smallSpacing

        QQC2.TabButton {
            text: i18n("All")
            checked: activeFan === "all"
            onClicked: activeFan = "all"
        }

        Repeater {
            model: fanCount
            QQC2.TabButton {
                text: fanNames[index] || i18n("Fan %1", index + 1)
                checked: activeFan === index
                onClicked: activeFan = index
            }
        }
    }

    // --- Manual duty ---
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: fanMode === "manual"
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label { text: i18n("Duty:") }

        QQC2.Slider {
            Layout.fillWidth: true
            from: 0
            to: 100
            stepSize: 1
            value: manualDutyPct
            onMoved: {
                manualDutyPct = Math.round(value);
                applyMode();
            }
        }

        PlasmaComponents.Label {
            text: manualDutyPct + "%"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
        }
    }

    // --- Curve controls ---
    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        visible: fanMode === "curve"
        spacing: Kirigami.Units.smallSpacing

        // Curve editor placeholder — will be replaced by CurveEditor
        CurveEditor {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 12
            points: fanPage.curvePoints
            onPointsChanged: {
                fanPage.curvePoints = points;
                applyMode();
            }
        }

        // Hysteresis
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label { text: i18n("Hysteresis (°C):") }

            QQC2.SpinBox {
                from: 0
                to: 20
                value: hysteresisC
                editable: true
                onValueModified: {
                    hysteresisC = value;
                    applyMode();
                }
            }
        }

        // Rate limit
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label { text: i18n("Rate limit (%/step):") }

            QQC2.SpinBox {
                from: 1
                to: 100
                value: rateLimitPctPerStep
                editable: true
                onValueModified: {
                    rateLimitPctPerStep = value;
                    applyMode();
                }
            }
        }

        // Down rate limit
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                text: i18n("Separate down rate:")
                checked: rateLimitDownEnabled
                onToggled: {
                    rateLimitDownEnabled = checked;
                    applyMode();
                }
            }

            QQC2.SpinBox {
                from: 1
                to: 100
                value: rateLimitDownPctPerStep
                enabled: rateLimitDownEnabled
                editable: true
                onValueModified: {
                    rateLimitDownPctPerStep = value;
                    applyMode();
                }
            }
        }

        // Poll interval
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label { text: i18n("Poll (ms):") }

            QQC2.SpinBox {
                from: 100
                to: 10000
                stepSize: 100
                value: pollMs
                editable: true
                onValueModified: {
                    pollMs = value;
                    applyMode();
                }
            }
        }

        // Sensor selection
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: availableSensors.length > 0

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
                        applyMode();
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
