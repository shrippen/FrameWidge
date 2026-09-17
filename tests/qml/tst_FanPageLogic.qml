import QtQuick
import QtTest

import "../../package/contents/ui" as UI

// FanPage.qml reads/writes through an unqualified `root` identifier, which
// QML resolves via the surrounding id scope rather than an import. So the
// fake `root` below just needs `id: root` and the handful of properties/
// functions FanPage actually touches - no real Plasmoid host required.
Item {
    id: root

    property var configData: null
    property var thermalData: null
    property bool serviceOnline: true
    property bool cliPresent: true
    property real cpuTemp: 42
    property int fanRpm: 2000
    property string baseUrl: "http://127.0.0.1:1" // unused: FanPage no longer fetches directly

    property var savedPatches: []
    function saveConfig(patch, callback) {
        savedPatches.push(patch);
        if (callback) callback(true);
    }

    // FanPage's preset storage writes through the unqualified `plasmoid`
    // identifier (a real context property in the actual widget); mocked the
    // same way `root` is, since persistPresets() is imperative code where an
    // unresolved reference throws instead of just failing a binding silently.
    QtObject {
        id: plasmoid
        property QtObject configuration: QtObject {
            property string fanCurvePresetsJson: "[]"
        }
    }

    Component { id: fanPageComponent; UI.FanPage {} }

    TestCase {
        name: "FanPageLogic"
        property var fanPage: null

        // A fresh FanPage per test avoids one test's mutation of shared
        // objects (curvePoints, overrides, ...) leaking into the next.
        function init() {
            root.savedPatches = [];
            root.configData = null;
            root.thermalData = null;
            plasmoid.configuration.fanCurvePresetsJson = "[]";
            fanPage = createTemporaryObject(fanPageComponent, root);
        }

        function test_seedingFromConfigDoesNotTriggerSave() {
            root.configData = {
                fan: { mode: "curve", curve: { points: [[30, 10]], hysteresis_c: 5, rate_limit_pct_per_step: 20, poll_ms: 1000, sensors: ["CPU"] } }
            };
            compare(root.savedPatches.length, 0, "seeding must not itself POST a config patch");
            compare(fanPage.fanMode, "curve");
            compare(fanPage.hysteresisC, 5);
            verify(fanPage.configLoaded);
        }

        function test_reseedingOnExternalConfigChangeUpdatesLocalState() {
            root.configData = { fan: { mode: "manual", manual: { duty_pct: 30 } } };
            compare(fanPage.fanMode, "manual");
            compare(fanPage.manualDutyPct, 30);

            // Simulate another tab (or the web UI) changing the mode meanwhile.
            root.configData = { fan: { mode: "disabled" } };
            compare(fanPage.fanMode, "disabled", "page must re-sync to the latest server state");
        }

        function test_manualDutySlider_debounceFlushesFinalValue() {
            fanPage.fanMode = "manual";
            root.savedPatches = [];

            fanPage.manualDutyPct = 10; fanPage.scheduleApply();
            fanPage.manualDutyPct = 55; fanPage.scheduleApply();
            fanPage.manualDutyPct = 42; fanPage.scheduleApply();

            compare(root.savedPatches.length, 0, "must not save before the debounce window elapses");
            wait(500);
            compare(root.savedPatches.length, 1, "three rapid moves must coalesce into a single save");
            compare(root.savedPatches[0].fan.manual.duty_pct, 42);
        }

        function test_curveEditorDrag_debouncesIntoOneSave() {
            fanPage.fanMode = "curve";
            root.savedPatches = [];

            fanPage.curvePoints = [[40, 0], [60, 50]]; fanPage.scheduleApply();
            fanPage.curvePoints = [[40, 0], [60, 60]]; fanPage.scheduleApply();
            fanPage.curvePoints = [[40, 0], [60, 70]]; fanPage.scheduleApply();

            wait(500);
            compare(root.savedPatches.length, 1);
            compare(root.savedPatches[0].fan.curve.points, [[40, 0], [60, 70]]);
        }

        function test_buildCurveConfig_omitsDownRateWhenDisabled() {
            fanPage.rateLimitDownEnabled = false;
            var cfg = fanPage.buildCurveConfig();
            verify(cfg.rate_limit_down_pct_per_step === undefined);
        }

        function test_buildCurveConfig_includesDownRateWhenEnabled() {
            fanPage.rateLimitDownEnabled = true;
            fanPage.rateLimitDownPctPerStep = 33;
            var cfg = fanPage.buildCurveConfig();
            compare(cfg.rate_limit_down_pct_per_step, 33);
        }

        function test_applyMode_clampsManualDutyToRange() {
            fanPage.fanMode = "manual";
            fanPage.manualDutyPct = 250; // out of range, e.g. from a stale/bad config
            fanPage.applyMode();
            compare(root.savedPatches[0].fan.manual.duty_pct, 100);
        }

        function test_sensorTopology_derivedFromThermalData() {
            root.thermalData = { temps: { CPU: 50, GPU: 40 }, fans: [{ name: "Left" }, { name: "Right" }] };
            compare(fanPage.availableSensors, ["CPU", "GPU"]);
            compare(fanPage.fanCount, 2);
            compare(fanPage.fanNames, ["Left", "Right"]);
        }

        // --- Presets ---
        // The real org.kde.activities model is exercised live (see roadmap.md
        // for how its id/name/current roles were verified against
        // org.kde.ActivityManager's D-Bus API); these tests drive the pure
        // logic directly via currentActivityId/availableActivities, which
        // FanPage's onCurrentActivityIdChanged handler reacts to the same way
        // regardless of what set them.

        function test_saveCurrentAsPreset_storesActivityMapping() {
            fanPage.curvePoints = [[30, 0], [70, 100]];
            fanPage.saveCurrentAsPreset("Gaming", "activity-123");
            compare(fanPage.presets.length, 1);
            compare(fanPage.presets[0].activity_id, "activity-123");
            compare(fanPage.presets[0].points, [[30, 0], [70, 100]]);
        }

        function test_saveCurrentAsPreset_withoutActivityStoresEmptyString() {
            fanPage.saveCurrentAsPreset("Quiet", "");
            compare(fanPage.presets[0].activity_id, "");
        }

        function test_saveCurrentAsPreset_overwritesByName() {
            fanPage.saveCurrentAsPreset("Gaming", "activity-123");
            fanPage.curvePoints = [[50, 50]];
            fanPage.saveCurrentAsPreset("Gaming", "activity-456");
            compare(fanPage.presets.length, 1, "saving under an existing name must replace it, not duplicate it");
            compare(fanPage.presets[0].activity_id, "activity-456");
        }

        function test_applyPreset_forcesCurveMode() {
            fanPage.fanMode = "manual";
            fanPage.saveCurrentAsPreset("Gaming", "");
            fanPage.fanMode = "manual"; // saving doesn't change mode; reset for the actual assertion
            fanPage.applyPreset(0);
            compare(fanPage.fanMode, "curve", "loading a curve preset only means something in curve mode");
        }

        function test_activityChange_autoAppliesMatchingPreset() {
            fanPage.curvePoints = [[20, 0], [80, 100]];
            fanPage.saveCurrentAsPreset("Gaming", "activity-123");
            fanPage.fanMode = "disabled";
            root.savedPatches = [];

            fanPage.currentActivityId = "activity-123";

            compare(fanPage.fanMode, "curve");
            compare(fanPage.curvePoints, [[20, 0], [80, 100]]);
            compare(fanPage.selectedPresetIndex, 0);
        }

        function test_activityChange_ignoresWhenNoPresetMatches() {
            fanPage.saveCurrentAsPreset("Gaming", "activity-123");
            fanPage.fanMode = "disabled";

            fanPage.currentActivityId = "some-other-activity";

            compare(fanPage.fanMode, "disabled", "an unmapped activity must not touch the current fan mode");
        }

        function test_activityNameFor_looksUpAvailableActivities() {
            fanPage.availableActivities = [{ id: "a1", name: "Gaming" }, { id: "a2", name: "Work" }];
            compare(fanPage.activityNameFor("a2"), "Work");
            compare(fanPage.activityNameFor("missing"), "");
        }
    }
}
