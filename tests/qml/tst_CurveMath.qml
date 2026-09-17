import QtQuick
import QtTest

import "../../package/contents/ui/js/CurveMath.js" as CurveMath

TestCase {
    name: "CurveMath"

    // A 200x100 canvas with the CurveEditor's real padding/axis constants.
    readonly property int w: 200
    readonly property int h: 100
    readonly property int padLeft: 36
    readonly property int padRight: 12
    readonly property int padTop: 12
    readonly property int padBottom: 22

    function test_tempToX_boundsMapToPlotEdges() {
        compare(CurveMath.tempToX(0, w, padLeft, padRight, 0, 100), padLeft);
        compare(CurveMath.tempToX(100, w, padLeft, padRight, 0, 100), w - padRight);
    }

    function test_dutyToY_isInverted() {
        // duty 100 (max) must be at the top (smallest y), duty 0 at the bottom.
        var yAt100 = CurveMath.dutyToY(100, h, padTop, padBottom, 0, 100);
        var yAt0 = CurveMath.dutyToY(0, h, padTop, padBottom, 0, 100);
        verify(yAt100 < yAt0);
        compare(yAt100, padTop);
        compare(yAt0, h - padBottom);
    }

    function test_xToTemp_roundTripsThroughTempToX() {
        var temps = [0, 1, 25, 50, 63, 99, 100];
        for (var i = 0; i < temps.length; i++) {
            var x = CurveMath.tempToX(temps[i], w, padLeft, padRight, 0, 100);
            var back = CurveMath.xToTemp(x, w, padLeft, padRight, 0, 100);
            compare(back, temps[i], "round-trip failed for temp " + temps[i]);
        }
    }

    function test_yToDuty_roundTripsThroughDutyToY() {
        var duties = [0, 1, 40, 80, 99, 100];
        for (var i = 0; i < duties.length; i++) {
            var y = CurveMath.dutyToY(duties[i], h, padTop, padBottom, 0, 100);
            var back = CurveMath.yToDuty(y, h, padTop, padBottom, 0, 100);
            compare(back, duties[i], "round-trip failed for duty " + duties[i]);
        }
    }

    function test_xToTemp_clampsBeyondPlotArea() {
        // Mouse can move outside the canvas while dragging; must clamp, not extrapolate.
        compare(CurveMath.xToTemp(-1000, w, padLeft, padRight, 0, 100), 0);
        compare(CurveMath.xToTemp(10000, w, padLeft, padRight, 0, 100), 100);
    }

    function test_yToDuty_clampsBeyondPlotArea() {
        compare(CurveMath.yToDuty(-1000, h, padTop, padBottom, 0, 100), 100);
        compare(CurveMath.yToDuty(10000, h, padTop, padBottom, 0, 100), 0);
    }
}
