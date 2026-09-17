import QtQuick
import QtTest

import "../../package/contents/ui" as UI

Item {
    id: root

    property var configData: null
    property var powerData: null

    property var savedPatches: []
    function saveConfig(patch, callback) {
        savedPatches.push(patch);
        if (callback) callback(true);
    }

    Component { id: powerPageComponent; UI.PowerPage {} }

    TestCase {
        name: "PowerPageLogic"
        property var powerPage: null

        // A fresh PowerPage per test: its powerConfig holds mutable nested
        // objects, so reusing one instance would let a mutation in one test
        // (e.g. toggling activeConfig.governor.enabled) leak into the next.
        function init() {
            root.savedPatches = [];
            root.configData = null;
            root.powerData = null;
            powerPage = createTemporaryObject(powerPageComponent, root);
        }

        function test_seedingFromConfigDoesNotTriggerSave() {
            root.configData = { power: { ac: { tdp_watts: { enabled: true, value: 45 } } } };
            compare(root.savedPatches.length, 0);
            verify(powerPage.configLoaded);
            compare(powerPage.powerConfig.ac.tdp_watts.value, 45);
            compare(powerPage.powerConfig.ac.tdp_watts.enabled, true);
        }

        function test_mergeProfile_leavesUnspecifiedFieldsAtDefault() {
            root.configData = { power: { ac: { tdp_watts: { enabled: true, value: 45 } } } };
            // governor wasn't in the patch, so its default from PowerPage's own initial state must survive.
            compare(powerPage.powerConfig.ac.governor.enabled, false);
        }

        function test_mergeProfile_keepsProfilesIndependent() {
            root.configData = {
                power: {
                    ac: { tdp_watts: { enabled: true, value: 45 } },
                    battery: { tdp_watts: { enabled: true, value: 15 } }
                }
            };
            compare(powerPage.powerConfig.ac.tdp_watts.value, 45);
            compare(powerPage.powerConfig.battery.tdp_watts.value, 15);
        }

        function test_applyField_sendsOnlyTheChangedField() {
            root.configData = { power: { ac: { tdp_watts: { enabled: true, value: 45 } } } };
            root.savedPatches = [];
            powerPage.activeConfig.governor.enabled = true;
            powerPage.applyField("governor");
            var patch = root.savedPatches[0];
            compare(Object.keys(patch.power.ac).length, 1);
            verify(patch.power.ac.governor !== undefined);
            verify(patch.power.ac.tdp_watts === undefined, "unrelated fields must not be resent");
        }

        function test_applyField_targetsTheActiveProfile() {
            powerPage.activeProfile = "battery";
            powerPage.activeConfig.tdp_watts.enabled = true;
            powerPage.applyField("tdp_watts");
            verify(root.savedPatches[0].power.battery !== undefined);
            verify(root.savedPatches[0].power.ac === undefined);
        }

        function test_tdpSlider_debouncesRapidMovesIntoOneSave() {
            powerPage.activeConfig.tdp_watts.value = 40; powerPage.scheduleTdpApply();
            powerPage.activeConfig.tdp_watts.value = 60; powerPage.scheduleTdpApply();
            powerPage.activeConfig.tdp_watts.value = 55; powerPage.scheduleTdpApply();

            compare(root.savedPatches.length, 0, "must not save before the debounce window elapses");
            wait(500);
            compare(root.savedPatches.length, 1, "three rapid moves must coalesce into a single save");
            compare(root.savedPatches[0].power.ac.tdp_watts.value, 55);
        }

        function test_thermalSlider_debouncesRapidMovesIntoOneSave() {
            powerPage.activeConfig.thermal_limit_c.value = 70; powerPage.scheduleThermalApply();
            powerPage.activeConfig.thermal_limit_c.value = 80; powerPage.scheduleThermalApply();

            wait(500);
            compare(root.savedPatches.length, 1);
            compare(root.savedPatches[0].power.ac.thermal_limit_c.value, 80);
        }

        function test_hasAnyCapability_falseWhenNoneSupported() {
            root.powerData = { power_control: { capabilities: {
                supports_epp: false, supports_governor: false,
                supports_frequency_limits: false, supports_tdp: false, supports_thermal: false
            }, current_state: {} } };
            compare(powerPage.hasAnyCapability, false);
        }

        function test_hasAnyCapability_trueWhenAnySupported() {
            root.powerData = { power_control: { capabilities: {
                supports_epp: false, supports_governor: false,
                supports_frequency_limits: false, supports_tdp: true, supports_thermal: false
            }, current_state: {} } };
            compare(powerPage.hasAnyCapability, true);
        }
    }
}
