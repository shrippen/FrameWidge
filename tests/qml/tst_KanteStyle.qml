import QtQuick
import QtTest

import "../../package/contents/ui/Kante"

// Mirrors the Binding in main.qml: config key visualStyle -> KanteStyle.kind.
Item {
    id: root

    property int visualStyle: 0

    Binding {
        target: KanteStyle
        property: "kind"
        value: root.visualStyle
    }

    TestCase {
        name: "KanteStyle"

        function cleanup() {
            root.visualStyle = 0;
        }

        function test_systemIsTheDefault() {
            compare(KanteStyle.kind, KanteStyle.Kind.System);
            verify(!KanteStyle.active);
            verify(!KanteStyle.themed);
        }

        function test_kanteSetting() {
            root.visualStyle = 1;
            compare(KanteStyle.kind, KanteStyle.Kind.Kante);
            verify(KanteStyle.active);
            verify(KanteStyle.themed);
        }

        function test_kanteLightSetting() {
            root.visualStyle = 2;
            compare(KanteStyle.kind, KanteStyle.Kind.KanteLight);
            verify(KanteStyle.active);
            verify(!KanteStyle.themed);
        }

        function test_backToSystemRestores() {
            root.visualStyle = 1;
            root.visualStyle = 0;
            compare(KanteStyle.kind, KanteStyle.Kind.System);
            verify(!KanteStyle.active);
        }
    }
}
