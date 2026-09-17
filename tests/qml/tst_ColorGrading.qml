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

    function test_sensorColor_alwaysReturnsAPaletteEntry() {
        var names = ["CPU", "GPU", "SSD", "Battery", "VRM", ""];
        for (var i = 0; i < names.length; i++) {
            var c = ColorGrading.sensorColor(names[i]);
            verify(typeof c === "string" && c.length > 0, "no color for '" + names[i] + "'");
        }
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
