import QtQuick
import QtTest

import "../../package/contents/ui/js/Api.js" as Api
import "MockBus.js" as MockBus

// Api.js calls framewidged over D-Bus. tests/run_unit_tests.sh runs
// tests/fixtures/mock_backend.py on a private bus and points
// DBUS_SYSTEM_BUS_ADDRESS at it. Without it the tests skip().
TestCase {
    name: "Api"

    property bool mockRunning: false

    function initTestCase() {
        var answered = false;
        Api.get("Health", function(ok) { mockRunning = ok; answered = true; });
        tryVerify(function() { return answered; }, 3000);
    }

    function init() {
        if (!mockRunning) return;
        var done = false;
        MockBus.call("Reset", function() { done = true; });
        tryVerify(function() { return done; }, 2000);
    }

    function requireMock() {
        if (!mockRunning) skip("mock backend not running; run via tests/run_unit_tests.sh");
    }

    function test_get_deliversParsedJsonOnSuccess() {
        requireMock();
        var result = null;
        Api.get("Health", function(ok, data) { result = { ok: ok, data: data }; });
        tryVerify(function() { return result !== null; }, 2000);
        verify(result.ok);
        compare(result.data.cli_present, true);
    }

    function test_get_reportsFailureForUnknownMethod() {
        requireMock();
        var result = null;
        Api.get("DoesNotExist", function(ok, data, error) { result = { ok: ok, data: data, error: error }; });
        tryVerify(function() { return result !== null; }, 2000);
        compare(result.ok, false);
        compare(result.data, null);
        verify(result.error.length > 0);
    }

    function test_get_reportsFailureWhenServiceIsMissing() {
        // The normal offline path: no framewidged on the bus.
        var saved = Api.SERVICE;
        Api.SERVICE = "io.github.shrippen.NobodyHome";
        var result = null;
        Api.get("Health", function(ok, data) { result = { ok: ok, data: data }; });
        Api.SERVICE = saved;
        tryVerify(function() { return result !== null; }, 3000);
        compare(result.ok, false);
    }

    function test_setConfig_roundTripsPatch() {
        requireMock();
        var result = null;
        Api.setConfig({ fan: { mode: "manual" } }, function(ok, data) { result = { ok: ok, data: data }; });
        tryVerify(function() { return result !== null; }, 2000);
        verify(result.ok);
        compare(result.data.fan.mode, "manual");
        compare(result.data.fan.manual.duty_pct, 50, "untouched keys stay");
    }

    function test_setPowerProfile_reachesService() {
        requireMock();
        var done = null;
        Api.setPowerProfile("performance", function(ok) { done = ok; });
        tryVerify(function() { return done !== null; }, 2000);
        verify(done);

        var power = null;
        Api.get("Power", function(ok, data) { power = data; });
        tryVerify(function() { return power !== null; }, 2000);
        compare(power.profile.active, "performance");
    }

    function test_setPowerProfile_unknownProfileFails() {
        requireMock();
        var done = null;
        Api.setPowerProfile("turbo", function(ok) { done = ok; });
        tryVerify(function() { return done !== null; }, 2000);
        compare(done, false);
    }

    function test_callText_returnsPlainText() {
        requireMock();
        var text = null;
        Api.callText("Logs", [], function(ok, t) { text = t; });
        tryVerify(function() { return text !== null; }, 2000);
        verify(text.indexOf("mock backend started") >= 0);
    }
}
