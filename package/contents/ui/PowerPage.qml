import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

import "js/Api.js" as Api

ColumnLayout {
    id: powerPage
    spacing: Kirigami.Units.smallSpacing

    property var capabilities: root.powerData ? root.powerData.power_control.capabilities : null
    property var currentState: root.powerData ? root.powerData.power_control.current_state : null
    property var battery: root.powerData ? root.powerData.battery : null

    property string activeProfile: "ac"

    // Power config mirrors
    property var powerConfig: ({
        ac: {
            epp_preference: { enabled: false, value: "" },
            governor: { enabled: false, value: "" },
            min_freq_mhz: { enabled: false, value: 1000 },
            max_freq_mhz: { enabled: false, value: 4000 },
            tdp_watts: { enabled: false, value: 75 },
            thermal_limit_c: { enabled: false, value: 90 }
        },
        battery: {
            epp_preference: { enabled: false, value: "" },
            governor: { enabled: false, value: "" },
            min_freq_mhz: { enabled: false, value: 1000 },
            max_freq_mhz: { enabled: false, value: 3000 },
            tdp_watts: { enabled: false, value: 60 },
            thermal_limit_c: { enabled: false, value: 90 }
        }
    })

    property var activeConfig: powerConfig[activeProfile] || powerConfig.ac
    property bool hasAnyCapability: capabilities &&
        (capabilities.supports_epp || capabilities.supports_governor ||
         capabilities.supports_frequency_limits || capabilities.supports_tdp ||
         capabilities.supports_thermal)

    Component.onCompleted: loadPowerConfig()

    function loadPowerConfig() {
        Api.get(root.baseUrl + "/api/config", function(ok, data) {
            if (!ok || !data || !data.power) return;
            var p = data.power;
            if (p.ac) mergeProfile("ac", p.ac);
            if (p.battery) mergeProfile("battery", p.battery);
            powerConfig = powerConfig; // trigger binding update
        });
    }

    function mergeProfile(key, src) {
        var dst = powerConfig[key];
        var fields = ["epp_preference", "governor", "min_freq_mhz", "max_freq_mhz", "tdp_watts", "thermal_limit_c"];
        for (var i = 0; i < fields.length; i++) {
            var f = fields[i];
            if (src[f]) {
                dst[f].enabled = !!src[f].enabled;
                dst[f].value = src[f].value !== undefined ? src[f].value : dst[f].value;
            }
        }
    }

    function applyField(field) {
        var setting = activeConfig[field];
        if (!setting) return;
        var patch = { power: {} };
        patch.power[activeProfile] = {};
        patch.power[activeProfile][field] = { enabled: setting.enabled, value: setting.value };
        root.saveConfig(patch);
    }

    function applyFreqLimits() {
        var patch = { power: {} };
        patch.power[activeProfile] = {
            min_freq_mhz: { enabled: activeConfig.min_freq_mhz.enabled, value: activeConfig.min_freq_mhz.value },
            max_freq_mhz: { enabled: activeConfig.max_freq_mhz.enabled, value: activeConfig.max_freq_mhz.value }
        };
        root.saveConfig(patch);
    }

    // --- Current state bar ---
    Kirigami.FormLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("AC:")
            text: battery && battery.ac_present !== undefined ? (battery.ac_present ? i18n("Plugged in") : i18n("On battery")) : "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("TDP:")
            visible: currentState && currentState.tdp_limit_watts !== undefined
            text: currentState && currentState.tdp_limit_watts !== undefined ? currentState.tdp_limit_watts + " W" : ""
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Thermal:")
            visible: currentState && currentState.thermal_limit_c !== undefined
            text: currentState && currentState.thermal_limit_c !== undefined ? currentState.thermal_limit_c + " °C" : ""
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("EPP:")
            visible: currentState && currentState.epp_preference
            text: currentState ? (currentState.epp_preference || "") : ""
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Governor:")
            visible: currentState && currentState.governor
            text: currentState ? (currentState.governor || "") : ""
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Frequency:")
            visible: currentState && currentState.min_freq_mhz !== undefined
            text: {
                if (!currentState || currentState.min_freq_mhz === undefined) return "";
                return (currentState.min_freq_mhz / 1000).toFixed(2) + " - " + (currentState.max_freq_mhz / 1000).toFixed(2) + " GHz";
            }
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // No capabilities
    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        visible: !hasAnyCapability
        wrapMode: Text.WordWrap
        text: i18n("No supported power management interface detected.")
        opacity: 0.6
    }

    // --- Profile selector ---
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        visible: hasAnyCapability
        spacing: Kirigami.Units.smallSpacing

        QQC2.RadioButton {
            text: i18n("AC")
            checked: activeProfile === "ac"
            onClicked: activeProfile = "ac"
        }
        QQC2.RadioButton {
            text: i18n("Battery")
            checked: activeProfile === "battery"
            onClicked: activeProfile = "battery"
        }
    }

    // --- Controls ---
    ColumnLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        visible: hasAnyCapability
        spacing: Kirigami.Units.smallSpacing

        // EPP
        RowLayout {
            Layout.fillWidth: true
            visible: capabilities && capabilities.supports_epp
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                checked: activeConfig.epp_preference.enabled
                onToggled: {
                    activeConfig.epp_preference.enabled = checked;
                    applyField("epp_preference");
                }
            }

            PlasmaComponents.Label { text: i18n("EPP:") }

            QQC2.ComboBox {
                Layout.fillWidth: true
                model: capabilities && capabilities.available_epp_preferences ? capabilities.available_epp_preferences : []
                currentIndex: model.indexOf(activeConfig.epp_preference.value)
                enabled: activeConfig.epp_preference.enabled
                onActivated: function(index) {
                    activeConfig.epp_preference.value = model[index];
                    applyField("epp_preference");
                }
            }
        }

        // Governor
        RowLayout {
            Layout.fillWidth: true
            visible: capabilities && capabilities.supports_governor
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                checked: activeConfig.governor.enabled
                onToggled: {
                    activeConfig.governor.enabled = checked;
                    applyField("governor");
                }
            }

            PlasmaComponents.Label { text: i18n("Governor:") }

            QQC2.ComboBox {
                Layout.fillWidth: true
                model: capabilities && capabilities.available_governors ? capabilities.available_governors : []
                currentIndex: model.indexOf(activeConfig.governor.value)
                enabled: activeConfig.governor.enabled
                onActivated: function(index) {
                    activeConfig.governor.value = model[index];
                    applyField("governor");
                }
            }
        }

        // TDP
        RowLayout {
            Layout.fillWidth: true
            visible: capabilities && capabilities.supports_tdp
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                checked: activeConfig.tdp_watts.enabled
                onToggled: {
                    activeConfig.tdp_watts.enabled = checked;
                    applyField("tdp_watts");
                }
            }

            PlasmaComponents.Label { text: i18n("TDP (W):") }

            QQC2.Slider {
                Layout.fillWidth: true
                from: capabilities ? (capabilities.tdp_min_watts || 5) : 5
                to: capabilities ? (capabilities.tdp_max_watts || 120) : 120
                stepSize: 1
                value: activeConfig.tdp_watts.value
                enabled: activeConfig.tdp_watts.enabled
                onMoved: {
                    activeConfig.tdp_watts.value = Math.round(value);
                    applyField("tdp_watts");
                }
            }

            PlasmaComponents.Label {
                text: activeConfig.tdp_watts.value + " W"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            }
        }

        // Thermal limit
        RowLayout {
            Layout.fillWidth: true
            visible: capabilities && capabilities.supports_thermal
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                checked: activeConfig.thermal_limit_c.enabled
                onToggled: {
                    activeConfig.thermal_limit_c.enabled = checked;
                    applyField("thermal_limit_c");
                }
            }

            PlasmaComponents.Label { text: i18n("Thermal (°C):") }

            QQC2.Slider {
                Layout.fillWidth: true
                from: 60
                to: 100
                stepSize: 1
                value: activeConfig.thermal_limit_c.value
                enabled: activeConfig.thermal_limit_c.enabled
                onMoved: {
                    activeConfig.thermal_limit_c.value = Math.round(value);
                    applyField("thermal_limit_c");
                }
            }

            PlasmaComponents.Label {
                text: activeConfig.thermal_limit_c.value + " °C"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            }
        }

        // Min frequency
        RowLayout {
            Layout.fillWidth: true
            visible: capabilities && capabilities.supports_frequency_limits
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                checked: activeConfig.min_freq_mhz.enabled
                onToggled: {
                    activeConfig.min_freq_mhz.enabled = checked;
                    applyFreqLimits();
                }
            }

            PlasmaComponents.Label { text: i18n("Min freq (MHz):") }

            QQC2.SpinBox {
                from: capabilities ? (capabilities.frequency_min_mhz || 400) : 400
                to: capabilities ? (capabilities.frequency_max_mhz || 6000) : 6000
                stepSize: 100
                value: activeConfig.min_freq_mhz.value
                enabled: activeConfig.min_freq_mhz.enabled
                editable: true
                onValueModified: {
                    activeConfig.min_freq_mhz.value = value;
                    applyFreqLimits();
                }
            }
        }

        // Max frequency
        RowLayout {
            Layout.fillWidth: true
            visible: capabilities && capabilities.supports_frequency_limits
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                checked: activeConfig.max_freq_mhz.enabled
                onToggled: {
                    activeConfig.max_freq_mhz.enabled = checked;
                    applyFreqLimits();
                }
            }

            PlasmaComponents.Label { text: i18n("Max freq (MHz):") }

            QQC2.SpinBox {
                from: capabilities ? (capabilities.frequency_min_mhz || 400) : 400
                to: capabilities ? (capabilities.frequency_max_mhz || 6000) : 6000
                stepSize: 100
                value: activeConfig.max_freq_mhz.value
                enabled: activeConfig.max_freq_mhz.enabled
                editable: true
                onValueModified: {
                    activeConfig.max_freq_mhz.value = value;
                    applyFreqLimits();
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
