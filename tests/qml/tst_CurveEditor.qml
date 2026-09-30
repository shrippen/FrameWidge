import QtQuick
import QtTest

import "../../package/contents/ui" as UI

// System-style CurveEditor: marker captions must stay clear of the
// point handles (a handle drawn over "CPU 58°" left "U 58°").
Item {
    id: root
    width: 420
    height: 220

    function i18n(text) { return text; }

    Component { id: editorComponent; UI.CurveEditor { width: 420; height: 220 } }

    TestCase {
        name: "CurveEditor"

        readonly property real captionWidth: 40

        function test_captionAvoidsNearbyHandle() {
            var editor = createTemporaryObject(editorComponent, root, { points: [[40, 0], [60, 40], [85, 100]] });
            var cx = editor.tempToX(58);
            var cy = editor.dutyToY(editor.interpolatedDutyAt(58));

            var x = editor.captionX(cx, cy, captionWidth);
            verify(!editor.captionHitsPoint(x, cy - editor.captionHeight, captionWidth), "caption at " + x + " covered by a handle");
            verify(x < cx, "caption moved left of the guide");
        }

        function test_captionStaysRightWhenClear() {
            var editor = createTemporaryObject(editorComponent, root, { points: [[40, 0], [85, 100]] });
            var cx = editor.tempToX(58);
            var cy = editor.dutyToY(editor.interpolatedDutyAt(58));

            verify(editor.captionX(cx, cy, captionWidth) > cx);
        }
    }
}
