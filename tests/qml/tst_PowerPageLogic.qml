import QtQuick
import QtTest

import "../../package/contents/ui" as UI

Item {
    id: root

    property var powerData: null

    function i18n(text) { return text; }

    property var chosen: []
    property var pendingCallback: null
    function setPowerProfile(name, callback) {
        chosen.push(name);
        pendingCallback = callback;
    }

    Component { id: powerPageComponent; UI.PowerPage {} }

    TestCase {
        name: "PowerPageLogic"
        property var powerPage: null

        function init() {
            root.chosen = [];
            root.pendingCallback = null;
            root.powerData = null;
            powerPage = createTemporaryObject(powerPageComponent, root);
        }

        function power(active) {
            return {
                battery: { ac_present: true },
                profile: { active: active, available: ["power-saver", "balanced", "performance"] }
            };
        }

        function test_notLoadedUntilPowerData() {
            verify(!powerPage.loaded);
            root.powerData = power("balanced");
            verify(powerPage.loaded);
            compare(powerPage.activeProfile, "balanced");
        }

        function test_choose_callsServiceOnceAndShowsChoiceAtOnce() {
            root.powerData = power("balanced");
            powerPage.choose("performance");
            compare(root.chosen, ["performance"]);
            compare(powerPage.activeProfile, "performance");

            // The service answered; the next poll brings the new state.
            root.pendingCallback(true);
            root.powerData = power("performance");
            compare(powerPage.activeProfile, "performance");
        }

        function test_choose_activeProfileDoesNothing() {
            root.powerData = power("balanced");
            powerPage.choose("balanced");
            compare(root.chosen.length, 0);
        }

        function test_failedChoiceFallsBackToReportedProfile() {
            root.powerData = power("balanced");
            powerPage.choose("power-saver");
            root.pendingCallback(false);
            compare(powerPage.activeProfile, "balanced");
        }

        function test_profileLabel_knownAndUnknownNames() {
            compare(powerPage.profileLabel("power-saver"), "Power Saver");
            compare(powerPage.profileLabel("custom"), "custom");
        }

        function test_withoutProfileDaemon() {
            root.powerData = { battery: { ac_present: false }, profile: null };
            verify(powerPage.loaded);
            compare(powerPage.activeProfile, "");
        }
    }
}
