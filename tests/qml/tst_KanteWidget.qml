import QtQuick
import QtTest

import "../../package/contents/ui" as UI
import "../../package/contents/ui/Kante"

// The Kante-styled parts of the popup load and survive switching the style
// System -> Kante -> Kante Light -> System. Like the page tests, `root` and
// `plasmoid` stand in for what main.qml provides.
Item {
    id: root

    property bool serviceOnline: false
    property bool cliPresent: true
    property string baseUrl: "http://127.0.0.1:1"
    property int visualStyle: 0
    readonly property var plasmoid: ({ configuration: { servicePort: 30912 } })

    Binding {
        target: KanteStyle
        property: "kind"
        value: root.visualStyle
    }

    function saveConfig(patch, callback) {}

    Component { id: hintComponent; UI.OfflineHintKante {} }
    Component { id: calibrationComponent; UI.CalibrationDialog {} }

    TestCase {
        name: "KanteWidget"

        function cleanup() {
            root.visualStyle = 0;
        }

        function test_offlineHintInEveryStyle() {
            var hint = createTemporaryObject(hintComponent, root);
            verify(hint);
            for (var style = 0; style <= 2; style++) {
                root.visualStyle = style;
                verify(hint.visible);
            }
            root.visualStyle = 0;
        }

        function test_calibrationDialogInEveryStyle() {
            var dialog = createTemporaryObject(calibrationComponent, root);
            verify(dialog);
            for (var style = 0; style <= 2; style++) {
                root.visualStyle = style;
                dialog.running = true;
                dialog.progress = 40;
                compare(dialog.progress, 40);
            }
            root.visualStyle = 0;
        }

        function test_calibrationDialogTitleStripFollowsTheStyle() {
            var dialog = createTemporaryObject(calibrationComponent, root);
            var platformHeader = dialog.header;
            root.visualStyle = 1;
            verify(dialog.header !== platformHeader);
            compare(dialog.header.text, dialog.title);
            root.visualStyle = 0;
            verify(dialog.header === platformHeader);
        }
    }
}
