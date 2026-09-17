import QtQuick
import QtTest

import "../../package/contents/ui/js/Api.js" as Api

// Api.js wraps XMLHttpRequest, so these need a live HTTP endpoint. Run via
// tests/run_unit_tests.sh, which starts tests/fixtures/mock_backend.py and
// writes its port to tests/.runtime/mock_port.txt.
TestCase {
    name: "Api"

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
    readonly property string baseUrl: mockPort.length > 0 ? ("http://127.0.0.1:" + mockPort) : ""

    function init() {
        if (baseUrl.length === 0) return;
        var xhr = new XMLHttpRequest();
        xhr.open("POST", baseUrl + "/__reset", false);
        xhr.send();
    }

    function test_get_deliversParsedJsonOnSuccess() {
        if (baseUrl.length === 0) skip("mock backend not running; run via tests/run_unit_tests.sh");
        var result = null;
        Api.get(baseUrl + "/api/health", function(ok, data) { result = { ok: ok, data: data }; });
        tryVerify(function() { return result !== null; }, 2000);
        verify(result.ok);
        compare(result.data.cli_present, true);
    }

    function test_get_reportsFailureOn404() {
        if (baseUrl.length === 0) skip("mock backend not running; run via tests/run_unit_tests.sh");
        var result = null;
        Api.get(baseUrl + "/api/does-not-exist", function(ok, data) { result = { ok: ok, data: data }; });
        tryVerify(function() { return result !== null; }, 2000);
        compare(result.ok, false);
        compare(result.data, null);
    }

    function test_get_reportsFailureOnConnectionRefused() {
        // Port 1 is a privileged, essentially-never-listening port - simulates the
        // backend being down, which is the normal offline path for this widget.
        var result = null;
        Api.get("http://127.0.0.1:1/api/health", function(ok, data) { result = { ok: ok, data: data }; });
        tryVerify(function() { return result !== null; }, 3000);
        compare(result.ok, false);
    }

    function test_post_roundTripsJsonBody() {
        if (baseUrl.length === 0) skip("mock backend not running; run via tests/run_unit_tests.sh");
        var result = null;
        Api.post(baseUrl + "/api/config", { fan: { mode: "manual" } }, function(ok, data) {
            result = { ok: ok, data: data };
        });
        tryVerify(function() { return result !== null; }, 2000);
        verify(result.ok);
        compare(result.data.fan.mode, "manual");
    }

    function test_post_reportsFailureOnServerError() {
        if (baseUrl.length === 0) skip("mock backend not running; run via tests/run_unit_tests.sh");
        var result = null;
        Api.post(baseUrl + "/does-not-exist", {}, function(ok, data) { result = { ok: ok, data: data }; });
        tryVerify(function() { return result !== null; }, 2000);
        compare(result.ok, false);
    }
}
