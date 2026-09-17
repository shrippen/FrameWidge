import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

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

    // Per-fan overrides
    property var overrides: []
    property var activeFan: "all" // "all" or fan index

    // Live data
    property int liveRpm: root.fanRpm
    property real liveTemp: root.cpuTemp

    // The temperature actually driving the curve: the max of whichever
    // sensors are selected for it, matching how the backend's curve
    // controller picks a value when several sensors feed one curve. Falls
    // back to the general CPU reading when no sensor is selected yet.
    readonly property real curveInputTemp: {
        if (!root.thermalData || !root.thermalData.temps || selectedSensors.length === 0) return liveTemp;
        var temps = root.thermalData.temps;
        var max = -1;
        for (var i = 0; i < selectedSensors.length; i++) {
            var v = temps[selectedSensors[i]];
            if (v !== undefined && v > max) max = v;
        }
        return max >= 0 ? max : liveTemp;
    }

    // Sensors / fan topology come from the shared thermal poll, not a private fetch
    readonly property var availableSensors: root.thermalData && root.thermalData.temps ? Object.keys(root.thermalData.temps) : []
    readonly property int fanCount: root.thermalData && root.thermalData.fans ? root.thermalData.fans.length : 0
    readonly property var fanNames: {
        if (!root.thermalData || !root.thermalData.fans) return [];
        var names = [];
        for (var i = 0; i < root.thermalData.fans.length; i++) {
            names.push(root.thermalData.fans[i].name || i18n("Fan %1", i + 1));
        }
        return names;
    }

    property bool configLoaded: false
    property bool applyGuard: false // suppress re-apply while seeding from server state

    // --- Curve presets ---
    // Stored client-side in the widget's own KConfig (JSON-encoded), not
    // round-tripped through the backend's /api/config - see main.xml.
    property var presets: []
    property int selectedPresetIndex: -1

    function loadPresets() {
        try {
            var parsed = JSON.parse(plasmoid.configuration.fanCurvePresetsJson || "[]");
            presets = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            presets = [];
        }
    }

    function persistPresets() {
        plasmoid.configuration.fanCurvePresetsJson = JSON.stringify(presets);
    }

    function saveCurrentAsPreset(name) {
        var preset = {
            name: name,
            points: curvePoints,
            hysteresis_c: hysteresisC,
            rate_limit_pct_per_step: rateLimitPctPerStep,
            rate_limit_down_enabled: rateLimitDownEnabled,
            rate_limit_down_pct_per_step: rateLimitDownPctPerStep,
            poll_ms: pollMs,
            sensors: selectedSensors
        };
        var updated = presets.slice();
        var existingIndex = updated.findIndex(function(p) { return p.name === name; });
        if (existingIndex >= 0) updated[existingIndex] = preset;
        else updated.push(preset);
        presets = updated;
        persistPresets();
        selectedPresetIndex = updated.findIndex(function(p) { return p.name === name; });
    }

    function applyPreset(index) {
        if (index < 0 || index >= presets.length) return;
        var p = presets[index];
        curvePoints = p.points || curvePoints;
        hysteresisC = p.hysteresis_c !== undefined ? p.hysteresis_c : hysteresisC;
        rateLimitPctPerStep = p.rate_limit_pct_per_step || rateLimitPctPerStep;
        rateLimitDownEnabled = !!p.rate_limit_down_enabled;
        rateLimitDownPctPerStep = p.rate_limit_down_pct_per_step || rateLimitPctPerStep;
        pollMs = p.poll_ms || pollMs;
        selectedSensors = p.sensors || selectedSensors;
        applyMode();
    }

    function deletePreset(index) {
        if (index < 0 || index >= presets.length) return;
        var updated = presets.slice();
        updated.splice(index, 1);
        presets = updated;
        persistPresets();
        selectedPresetIndex = -1;
    }

    Component.onCompleted: {
        if (root.configData) seedFromConfig(root.configData);
        loadPresets();
    }

    // Coalesces rapid slider drags into a single request instead of one POST per pixel
    Timer {
        id: applyDebounce
        interval: 350
        onTriggered: applyMode()
    }
    function scheduleApply() { applyDebounce.restart(); }

    Connections {
        target: root
        function onConfigDataChanged() { seedFromConfig(root.configData); }
    }

    function seedFromConfig(data) {
        if (!data || !data.fan) return;
        applyGuard = true;
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
        applyGuard = false;
    }

    function applyMode() {
        if (applyGuard) return;
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

    // --- Loading state ---
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        visible: !configLoaded
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.BusyIndicator {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: width
            running: !configLoaded
        }
        PlasmaComponents.Label {
            text: i18n("Loading fan configuration…")
            opacity: 0.6
        }
    }

    // --- Mode selector ---
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        enabled: configLoaded
        opacity: configLoaded ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

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
        enabled: configLoaded
        opacity: configLoaded ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
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
                scheduleApply();
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
        enabled: configLoaded
        opacity: configLoaded ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        spacing: Kirigami.Units.smallSpacing

        // Curve editor placeholder — will be replaced by CurveEditor
        CurveEditor {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 12
            points: fanPage.curvePoints
            liveTemp: fanPage.curveInputTemp
            onPointsChanged: {
                fanPage.curvePoints = points;
                scheduleApply();
            }
        }

        // Hysteresis + rate limit share a row - neither needs the full width.
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

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

            Item { Layout.fillWidth: true }
        }

        // Down-rate override + poll interval likewise share a row.
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

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

            Item { Layout.fillWidth: true }
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

        // Presets
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label { text: i18n("Preset:") }

            QQC2.ComboBox {
                id: presetCombo
                Layout.fillWidth: true
                model: presets.map(function(p) { return p.name; })
                currentIndex: selectedPresetIndex
                enabled: presets.length > 0
                displayText: currentIndex >= 0 ? currentText : i18n("(none selected)")
                onActivated: function(index) { selectedPresetIndex = index; }
            }

            PlasmaComponents.Button {
                icon.name: "dialog-ok-apply"
                text: i18n("Load")
                enabled: selectedPresetIndex >= 0
                onClicked: applyPreset(selectedPresetIndex)
            }

            PlasmaComponents.Button {
                icon.name: "document-save"
                text: i18n("Save as…")
                onClicked: {
                    presetNameField.text = selectedPresetIndex >= 0 ? presets[selectedPresetIndex].name : "";
                    savePresetDialog.open();
                }
            }

            PlasmaComponents.Button {
                icon.name: "edit-delete"
                enabled: selectedPresetIndex >= 0
                QQC2.ToolTip.text: i18n("Delete preset")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
                onClicked: deletePreset(selectedPresetIndex)
            }
        }
    }

    QQC2.Dialog {
        id: savePresetDialog
        title: i18n("Save Fan Curve Preset")
        modal: true
        standardButtons: QQC2.Dialog.Save | QQC2.Dialog.Cancel

        onAccepted: {
            if (presetNameField.text.length > 0) saveCurrentAsPreset(presetNameField.text);
        }

        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                text: i18n("Saves the current curve, hysteresis, rate limit, and sensor selection under this name.")
                wrapMode: Text.WordWrap
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                opacity: 0.7
            }

            QQC2.TextField {
                id: presetNameField
                Layout.fillWidth: true
                placeholderText: i18n("Preset name")
                onAccepted: savePresetDialog.accept()
            }
        }
    }

    Item { Layout.fillHeight: true }
}
