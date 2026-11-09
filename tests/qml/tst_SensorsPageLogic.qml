import QtQuick
import QtTest

import "../../package/contents/ui" as UI
import "MockBus.js" as MockBus

// SensorsPage.qml calls the service (via Api.js) itself, so unlike the other
// *Logic tests this one needs the mock backend: tests/run_unit_tests.sh runs
// it on a private bus. Tests that need it skip() themselves if it's absent.
Item {
    id: root

    property bool mockRunning: false
    property var configData: null
    property var thermalData: null
    property bool expanded: false


    Component { id: sensorsPageComponent; UI.SensorsPage {} }

    TestCase {
        name: "SensorsPageLogic"
        property var sensorsPage: null

        function initTestCase() {
            var answered = false;
            MockBus.call("Requests", function(ok) { root.mockRunning = ok; answered = true; });
            tryVerify(function() { return answered; }, 3000);
        }

        function init() {
            root.configData = null;
            root.thermalData = null;
            if (root.mockRunning) {
                var done = false;
                MockBus.call("Reset", function() { done = true; });
                tryVerify(function() { return done; }, 2000);
            }
            sensorsPage = createTemporaryObject(sensorsPageComponent, root);
        }

        // Calls of `member` in the mock backend's request log.
        function requests(member) {
            var list = null;
            MockBus.call("Requests", function(ok, text) {
                list = JSON.parse(text).filter(function(r) { return r.member === member; });
            });
            tryVerify(function() { return list !== null; }, 2000);
            return list;
        }

        function requestCount(member) {
            var count = -1;
            MockBus.call("Requests", function(ok, text) {
                count = JSON.parse(text).filter(function(r) { return r.member === member; }).length;
            });
            tryVerify(function() { return count >= 0; }, 2000);
            return count;
        }

        function test_seedTelemetryConfig_setsPollIntervalFromConfig() {
            root.configData = { telemetry: { poll_ms: 5000 } };
            compare(sensorsPage.telemetryPollMs, 5000);
        }

        function test_sensorList_derivedFromThermalData() {
            root.thermalData = { temps: { CPU: 50, GPU: 40, SSD: 35 } };
            compare(sensorsPage.availableSensors, ["CPU", "GPU", "SSD"]);
            // First population seeds the selection too, so the chart has something to show.
            compare(sensorsPage.selectedSensors, ["CPU", "GPU", "SSD"]);
        }

        function test_sensorSelection_notOverwrittenByLaterThermalUpdates() {
            root.thermalData = { temps: { CPU: 50, GPU: 40 } };
            sensorsPage.selectedSensors = ["CPU"]; // user deselected GPU
            root.thermalData = { temps: { CPU: 51, GPU: 41 } }; // next poll tick
            compare(sensorsPage.selectedSensors, ["CPU"], "user's selection must survive further polling");
        }

        function test_fetchHistory_populatesSeriesFromMockBackend() {
            if (!root.mockRunning) skip("mock backend not running; run via tests/run_unit_tests.sh");
            sensorsPage.selectedSensors = ["CPU", "GPU"];
            sensorsPage.windowSeconds = 3600;
            sensorsPage.fetchHistory();
            tryVerify(function() { return Object.keys(sensorsPage.series).length > 0; }, 2000);
            verify(sensorsPage.series.CPU.length > 0);
        }

        function test_windowSlider_debouncesRapidMovesIntoOneFetch() {
            if (!root.mockRunning) skip("mock backend not running; run via tests/run_unit_tests.sh");
            wait(50); // let the Component.onCompleted fetch land before we start counting
            var before = requestCount("ThermalHistorySince");

            sensorsPage.windowSeconds = 60; sensorsPage.scheduleFetch();
            sensorsPage.windowSeconds = 120; sensorsPage.scheduleFetch();
            sensorsPage.windowSeconds = 300; sensorsPage.scheduleFetch();

            wait(500);
            var after = requestCount("ThermalHistorySince");
            compare(after - before, 1, "three rapid slider moves must coalesce into a single history fetch");
        }

        // The pages share one StackLayout; another tab hides this one. Each
        // fetch parses the whole history (~170 KB at 30 min) in plasmashell.
        function test_hiddenPage_fetchesNoHistory() {
            if (!root.mockRunning) skip("mock backend not running; run via tests/run_unit_tests.sh");
            root.configData = { telemetry: { poll_ms: 1000 } };
            sensorsPage.visible = false;
            root.expanded = true;
            wait(50);
            var before = requestCount("ThermalHistorySince");

            wait(2500);
            compare(requestCount("ThermalHistorySince") - before, 0, "no fetch while another tab shows");

            sensorsPage.visible = true;
            tryVerify(function() { return requestCount("ThermalHistorySince") - before === 1; }, 500,
                      "showing the tab fetches at once");
            root.expanded = false;
        }
    
        // The page keeps its samples and asks only for newer ones: the whole
        // history is ~170 KB at 30 min, parsed in plasmashell every 2 s.
        function test_fetchHistory_asksOnlyForNewSamples() {
            if (!root.mockRunning) skip("mock backend not running; run via tests/run_unit_tests.sh");
            sensorsPage.selectedSensors = ["CPU", "GPU"];
            sensorsPage.windowSeconds = 3600;
            sensorsPage.fetchHistory();
            tryVerify(function() { return sensorsPage.series.CPU && sensorsPage.series.CPU.length >= 3; }, 2000);
            wait(50); // the mock's newest sample is "now"; let fetches in flight land
            var cpu = sensorsPage.series.CPU;
            var newest = sensorsPage.samples[sensorsPage.samples.length - 1].ts_ms;
            sensorsPage.fetchHistory();
            tryVerify(function() { return sensorsPage.series.CPU.length > cpu.length; }, 2000);

            var asked = requests("ThermalHistorySince");
            compare(asked[asked.length - 1].args[0], newest, "asks from the newest sample on");
            var times = sensorsPage.series.CPU.map(function(p) { return p[0]; });
            for (var i = 1; i < times.length; i++) {
                verify(times[i] > times[i - 1], "no sample twice");
            }
        }

        function test_firstFetch_asksOnlyForTheWindow() {
            if (!root.mockRunning) skip("mock backend not running; run via tests/run_unit_tests.sh");
            wait(50);
            var asked = requests("ThermalHistorySince");
            var since = asked[asked.length - 1].args[0];
            verify(Math.abs(since - (Date.now() - sensorsPage.windowSeconds * 1000)) < 2000,
                   "the service keeps 30 min, the chart shows " + sensorsPage.windowSeconds + " s");
        }

        function test_widerWindow_fetchesAgainFromItsStart() {
            if (!root.mockRunning) skip("mock backend not running; run via tests/run_unit_tests.sh");
            sensorsPage.windowSeconds = 5;
            sensorsPage.scheduleFetch();
            wait(400);
            compare(sensorsPage.series.CPU.length, 1, "5 s window: only the newest sample");

            sensorsPage.windowSeconds = 3600;
            sensorsPage.scheduleFetch();
            tryVerify(function() { return sensorsPage.series.CPU.length === 3; }, 2000,
                      "the older samples come back");
        }
    }
}
