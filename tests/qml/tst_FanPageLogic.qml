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
    }
}
