import QtQuick
import QtTest

import "../../package/contents/ui" as UI

// SensorsPage.qml does real XMLHttpRequest calls (via Api.js) against
// root.baseUrl, so unlike the other *Logic tests this one needs a live
// HTTP endpoint. tests/run_unit_tests.sh starts tests/fixtures/mock_backend.py
// and writes its port to tests/.runtime/mock_port.txt before invoking
// qmltestrunner. Tests that need the network skip() themselves if it's absent.
Item {
    id: root

    // QML has no Qt.getenv(), so tests/run_unit_tests.sh hands the mock
    // backend's port to this file instead of an environment variable.
    // Requires QML_XHR_ALLOW_FILE_READ=1 (also set by that script).
    readonly property string mockPort: {
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", Qt.resolvedUrl("../.runtime/mock_port.txt"), false);
            xhr.send();
            return xhr.status === 200 ? xhr.responseText.trim() : "";
        } catch (e) {
            return "";
        }
    }
    property string baseUrl: mockPort.length > 0 ? ("http://127.0.0.1:" + mockPort) : "http://127.0.0.1:1"
    property var configData: null
    property var thermalData: null

    // Synchronous introspection request against the mock backend's request log.
    function requestCount(method, path) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", root.baseUrl + "/__requests", false); // sync: fine for a test-only local call
        xhr.send();
        var log = JSON.parse(xhr.responseText);
        return log.filter(function(r) { return r.method === method && r.path === path; }).length;
    }

    function resetMockBackend() {
        var xhr = new XMLHttpRequest();
        xhr.open("POST", root.baseUrl + "/__reset", false);
        xhr.send();
    }

    Component { id: sensorsPageComponent; UI.SensorsPage {} }

    TestCase {
        name: "SensorsPageLogic"
        property var sensorsPage: null

        function init() {
            root.configData = null;
            root.thermalData = null;
            if (root.mockPort.length > 0) root.resetMockBackend();
            sensorsPage = createTemporaryObject(sensorsPageComponent, root);
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
            if (root.mockPort.length === 0) skip("mock backend not running; run via tests/run_unit_tests.sh");
            sensorsPage.selectedSensors = ["CPU", "GPU"];
            sensorsPage.windowSeconds = 3600;
            sensorsPage.fetchHistory();
            tryVerify(function() { return Object.keys(sensorsPage.series).length > 0; }, 2000);
            verify(sensorsPage.series.CPU.length > 0);
        }

        function test_windowSlider_debouncesRapidMovesIntoOneFetch() {
            if (root.mockPort.length === 0) skip("mock backend not running; run via tests/run_unit_tests.sh");
            wait(50); // let the Component.onCompleted fetch land before we start counting
            var before = root.requestCount("GET", "/api/thermal/history");

            sensorsPage.windowSeconds = 60; sensorsPage.scheduleFetch();
            sensorsPage.windowSeconds = 120; sensorsPage.scheduleFetch();
            sensorsPage.windowSeconds = 300; sensorsPage.scheduleFetch();

            wait(500);
            var after = root.requestCount("GET", "/api/thermal/history");
            compare(after - before, 1, "three rapid slider moves must coalesce into a single history fetch");
        }
    }
}
