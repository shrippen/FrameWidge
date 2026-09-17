import QtQuick
import QtTest

import "../../package/contents/ui" as UI

Item {
    id: root

    property var powerData: null
    property var configData: null

    property var savedPatches: []
    function saveConfig(patch, callback) {
        savedPatches.push(patch);
        if (callback) callback(true);
    }

    Component { id: batteryPageComponent; UI.BatteryPage {} }

    TestCase {
        name: "BatteryPageLogic"
        property var batteryPage: null

        function init() {
            root.savedPatches = [];
            root.configData = null;
            batteryPage = createTemporaryObject(batteryPageComponent, root);
        }

        function test_seedingFromConfigDoesNotTriggerSave() {
            root.configData = {
                battery: {
                    charge_limit_max_pct: { enabled: true, value: 80 },
                    charge_rate_c: { enabled: true, value: 0.5 },
                    charge_rate_soc_threshold_pct: 60
                }
            };
            compare(root.savedPatches.length, 0);
            verify(batteryPage.configLoaded);
            compare(batteryPage.clValue, 80);
            compare(batteryPage.rateC, 0.5);
            compare(batteryPage.socThresholdPct, 60);
        }

        function test_applyChargeLimit_clampsToValidRange() {
            batteryPage.clEnabled = true;
            batteryPage.clValue = 5; // below the hardware minimum of 25
            batteryPage.applyChargeLimit();
            compare(root.savedPatches[0].battery.charge_limit_max_pct.value, 25);

            root.savedPatches = [];
            batteryPage.clValue = 500;
            batteryPage.applyChargeLimit();
            compare(root.savedPatches[0].battery.charge_limit_max_pct.value, 100);
        }

        function test_applyRateLimit_forcesFullRateWhenDisabled() {
            batteryPage.rateEnabled = false;
            batteryPage.rateC = 0.2; // stale value from before the checkbox was unticked
            batteryPage.applyRateLimit();
            compare(root.savedPatches[0].battery.charge_rate_c.value, 1.0);
            compare(root.savedPatches[0].battery.charge_rate_c.enabled, false);
        }

        function test_applyRateLimit_clampsToValidRange() {
            batteryPage.rateEnabled = true;
            batteryPage.rateC = 0.01; // below the 0.05C minimum
            batteryPage.applyRateLimit();
            compare(root.savedPatches[0].battery.charge_rate_c.value, 0.05);
        }

        function test_chargeLimitSlider_debouncesRapidMovesIntoOneSave() {
            batteryPage.clEnabled = true;
            batteryPage.clValue = 60; batteryPage.scheduleChargeLimitApply();
            batteryPage.clValue = 70; batteryPage.scheduleChargeLimitApply();
            batteryPage.clValue = 90; batteryPage.scheduleChargeLimitApply();

            compare(root.savedPatches.length, 0, "must not save before the debounce window elapses");
            wait(500);
            compare(root.savedPatches.length, 1, "three rapid moves must coalesce into a single save");
            compare(root.savedPatches[0].battery.charge_limit_max_pct.value, 90);
        }

        function test_rateLimitSlider_debouncesRapidMovesIntoOneSave() {
            batteryPage.rateEnabled = true;
            batteryPage.rateC = 0.3; batteryPage.scheduleRateLimitApply();
            batteryPage.rateC = 0.6; batteryPage.scheduleRateLimitApply();

            wait(500);
            compare(root.savedPatches.length, 1);
            compare(root.savedPatches[0].battery.charge_rate_c.value, 0.6);
        }

        function test_socThreshold_canBeCleared() {
            batteryPage.rateEnabled = true;
            batteryPage.socThresholdPct = 50;
            batteryPage.applyRateLimit();
            compare(root.savedPatches[0].battery.charge_rate_soc_threshold_pct, 50);

            batteryPage.socThresholdPct = undefined;
            batteryPage.applyRateLimit();
            verify(root.savedPatches[1].battery.charge_rate_soc_threshold_pct === undefined);
        }
    }
}
