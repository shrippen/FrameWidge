import QtQuick
import QtTest

import "../../package/contents/ui/js/ColorGrading.js" as ColorGrading

TestCase {
    name: "ColorGrading"

    readonly property var colors: ({
        disabled: "gray", negative: "red", neutral: "orange", positive: "green", text: "black"
    })

    function test_sensorColor_isDeterministic() {
        compare(ColorGrading.sensorColor("CPU"), ColorGrading.sensorColor("CPU"));
    }

    function test_sensorColor_differsForDifferentNames() {
        // Not a strict guarantee for arbitrary strings (hash collisions are possible),
        // but must hold for the small, real sensor name set used in practice.
        verify(ColorGrading.sensorColor("CPU") !== ColorGrading.sensorColor("GPU"));
    }

    function test_sensorColor_alwaysReturnsAValidHexColor() {
        var names = ["CPU", "GPU", "SSD", "Battery", "VRM", ""];
        for (var i = 0; i < names.length; i++) {
            var c = ColorGrading.sensorColor(names[i]);
            verify(/^#[0-9a-f]{6}$/.test(c), "not a #rrggbb color for '" + names[i] + "': " + c);
        }
    }

    function test_sensorColor_isLighterInDarkTheme() {
        // Same hue (same name) needs a different lightness per theme: light
        // lines are unreadable on a light background and vice versa.
        var light = ColorGrading.sensorColor("CPU", false);
        var dark = ColorGrading.sensorColor("CPU", true);
        function luminance(hex) {
            var r = parseInt(hex.substr(1, 2), 16);
            var g = parseInt(hex.substr(3, 2), 16);
            var b = parseInt(hex.substr(5, 2), 16);
            return 0.299 * r + 0.587 * g + 0.114 * b;
        }
        verify(luminance(dark) > luminance(light), "dark-theme color must be lighter than the light-theme one");
    }

    function test_sensorColor_defaultsToLightTheme() {
        compare(ColorGrading.sensorColor("CPU"), ColorGrading.sensorColor("CPU", false));
    }

    function test_hslToHex_primaryHues() {
        compare(ColorGrading.hslToHex(0, 100, 50), "#ff0000");
        compare(ColorGrading.hslToHex(120, 100, 50), "#00ff00");
        compare(ColorGrading.hslToHex(240, 100, 50), "#0000ff");
        compare(ColorGrading.hslToHex(0, 0, 100), "#ffffff");
        compare(ColorGrading.hslToHex(0, 0, 0), "#000000");
    }

    function test_gradeIndicatorColor_offlineIsAlwaysDisabled() {
        compare(ColorGrading.gradeIndicatorColor(false, "temp", 95, colors), colors.disabled);
        compare(ColorGrading.gradeIndicatorColor(false, "rpm", 10, colors), colors.disabled);
    }

    function test_gradeIndicatorColor_tempThresholds() {
        compare(ColorGrading.gradeIndicatorColor(true, "temp", 40, colors), colors.positive);
        compare(ColorGrading.gradeIndicatorColor(true, "temp", 70, colors), colors.positive, "70 is the inclusive boundary, still positive");
        compare(ColorGrading.gradeIndicatorColor(true, "temp", 71, colors), colors.neutral);
        compare(ColorGrading.gradeIndicatorColor(true, "temp", 85, colors), colors.neutral, "85 is the inclusive boundary, still neutral");
        compare(ColorGrading.gradeIndicatorColor(true, "temp", 86, colors), colors.negative);
    }

    function test_gradeIndicatorColor_defaultsToTempModeWhenUndefined() {
        compare(ColorGrading.gradeIndicatorColor(true, undefined, 90, colors), colors.negative);
    }

    function test_gradeIndicatorColor_nonTempModesUseTextColor() {
        compare(ColorGrading.gradeIndicatorColor(true, "rpm", 95, colors), colors.text);
        compare(ColorGrading.gradeIndicatorColor(true, "soc", 95, colors), colors.text);
        compare(ColorGrading.gradeIndicatorColor(true, "icon", 95, colors), colors.text);
    }
}
