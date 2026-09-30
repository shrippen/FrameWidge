import QtQuick
import QtTest

import "../../package/contents/ui/js/SensorSeries.js" as SensorSeries

TestCase {
    name: "SensorSeries"

    function test_align_sharesOneTimeline() {
        var series = { CPU: [[1000, 40], [2000, 50], [3000, 60]], GPU: [[2000, 30], [3000, 35]] };
        var out = SensorSeries.align(series, ["CPU", "GPU"]);
        compare(out.times, [1000, 2000, 3000]);
        compare(out.values[0], [40, 50, 60]);
        // GPU starts late: its first value fills the gap.
        compare(out.values[1], [30, 30, 35]);
    }

    function test_align_keepsLastValueOverAGap() {
        var series = { CPU: [[1000, 40], [2000, 50], [3000, 60]], GPU: [[1000, 30], [3000, 35]] };
        compare(SensorSeries.align(series, ["CPU", "GPU"]).values[1], [30, 30, 35]);
    }

    function test_align_keepsSensorOrderForMissingData() {
        var series = { GPU: [[1000, 30]] };
        var out = SensorSeries.align(series, ["CPU", "GPU"]);
        compare(out.values[0], []);
        compare(out.values[1], [30]);
    }

    function test_align_emptyHistory() {
        var out = SensorSeries.align({}, ["CPU"]);
        compare(out.times, []);
        compare(out.values, [[]]);
    }

    function test_scale_roundsToWholeTens() {
        var s = SensorSeries.scale([[41, 57], [33]]);
        compare(s.min, 30);
        compare(s.max, 60);
    }

    function test_scale_flatDataStillHasARange() {
        var s = SensorSeries.scale([[50, 50]]);
        compare(s.min, 50);
        compare(s.max, 60);
    }

    function test_scale_withoutDataUsesFullRange() {
        var s = SensorSeries.scale([[]]);
        compare(s.min, 0);
        compare(s.max, 100);
    }
}
