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

    // --- Configurable overlay bands ---

    function test_defaultOverlayBands_coverAllModesAndAreOpenEnded() {
        var bands = ColorGrading.defaultOverlayBands();
        var modes = ["temp", "rpm", "soc"];
        for (var i = 0; i < modes.length; i++) {
            var list = bands[modes[i]];
            verify(Array.isArray(list) && list.length >= 1, "mode " + modes[i] + " needs at least one band");
            compare(list[list.length - 1].upTo, null, "last band of " + modes[i] + " must be open-ended");
        }
    }

    function test_parseOverlayBands_invalidJsonFallsBackToDefaults() {
        compare(JSON.stringify(ColorGrading.parseOverlayBands("not json {")),
                JSON.stringify(ColorGrading.defaultOverlayBands()));
        compare(JSON.stringify(ColorGrading.parseOverlayBands("")),
                JSON.stringify(ColorGrading.defaultOverlayBands()));
    }

    function test_parseOverlayBands_invalidModeFallsBackPerMode() {
        var json = JSON.stringify({
            temp: [{ upTo: 50, color: "text" }, { upTo: null, color: "#ff0080" }],
            rpm: "garbage",
            soc: [{ upTo: "x", color: "positive" }]
        });
        var parsed = ColorGrading.parseOverlayBands(json);
        compare(parsed.temp.length, 2, "valid temp bands survive");
        compare(parsed.temp[1].color, "#ff0080");
        compare(JSON.stringify(parsed.rpm), JSON.stringify(ColorGrading.defaultOverlayBands().rpm));
        compare(JSON.stringify(parsed.soc), JSON.stringify(ColorGrading.defaultOverlayBands().soc));
    }

    function test_parseOverlayBands_normalizesOpenEndedBands() {
        // An interior null threshold would swallow all higher bands; it must
        // be dropped, and the final band is always forced open-ended.
        var json = JSON.stringify({
            temp: [
                { upTo: 50, color: "positive" },
                { upTo: null, color: "neutral" },
                { upTo: 90, color: "negative" }
            ],
            rpm: [{ upTo: 3000, color: "text" }],
            soc: []
        });
        var parsed = ColorGrading.parseOverlayBands(json);
        compare(parsed.temp.length, 2);
        compare(parsed.temp[0].upTo, 50);
        compare(parsed.temp[1].upTo, null);
        compare(parsed.temp[1].color, "negative", "original last band becomes the catch-all");
        compare(parsed.rpm.length, 1);
        compare(parsed.rpm[0].upTo, null, "single band is always open-ended");
        compare(JSON.stringify(parsed.soc), JSON.stringify(ColorGrading.defaultOverlayBands().soc),
                "empty band list falls back to defaults");
    }

    function test_gradeBandColor_offlineIsAlwaysDisabled() {
        var bands = ColorGrading.defaultOverlayBands().temp;
        compare(ColorGrading.gradeBandColor(false, 95, bands, colors), colors.disabled);
    }

    function test_gradeBandColor_thresholdsAreInclusive() {
        var bands = [
            { upTo: 60, color: "positive" },
            { upTo: 80, color: "neutral" },
            { upTo: null, color: "negative" }
        ];
        compare(ColorGrading.gradeBandColor(true, 60, bands, colors), colors.positive, "60 is the inclusive boundary");
        compare(ColorGrading.gradeBandColor(true, 61, bands, colors), colors.neutral);
        compare(ColorGrading.gradeBandColor(true, 80, bands, colors), colors.neutral);
        compare(ColorGrading.gradeBandColor(true, 8000, bands, colors), colors.negative, "open-ended last band catches everything above");
    }

    function test_gradeBandColor_supportsSingleAndManyBands() {
        var one = [{ upTo: null, color: "text" }];
        compare(ColorGrading.gradeBandColor(true, 42, one, colors), colors.text);
        var five = [
            { upTo: 10, color: "positive" }, { upTo: 20, color: "positive" },
            { upTo: 30, color: "neutral" }, { upTo: 40, color: "negative" },
            { upTo: null, color: "disabled" }
        ];
        compare(ColorGrading.gradeBandColor(true, 5, five, colors), colors.positive);
        compare(ColorGrading.gradeBandColor(true, 35, five, colors), colors.negative);
        compare(ColorGrading.gradeBandColor(true, 100, five, colors), colors.disabled);
    }

    function test_gradeBandColor_hexColorsPassThrough() {
        var bands = [{ upTo: null, color: "#12ab34" }];
        compare(ColorGrading.gradeBandColor(true, 1, bands, colors), "#12ab34");
    }

    function test_gradeBandColor_invalidValueUsesTextColor() {
        var bands = ColorGrading.defaultOverlayBands().temp;
        compare(ColorGrading.gradeBandColor(true, -1, bands, colors), colors.text);
        compare(ColorGrading.gradeBandColor(true, NaN, bands, colors), colors.text);
        compare(ColorGrading.gradeBandColor(true, 50, [], colors), colors.text);
    }
}
