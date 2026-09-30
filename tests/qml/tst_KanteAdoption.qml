import QtQuick
import QtTest

import "../../package/contents/ui" as UI
import "../../package/contents/ui/Kante"

// The pages use Kante elements in the Kante styles and keep the platform ones
// in System. `root` and `plasmoid` stand in for what main.qml provides.
Item {
    id: root

    property var configData: null
    property var thermalData: null
    property bool serviceOnline: true
    property bool cliPresent: true
    property real cpuTemp: 42
    property int fanRpm: 2000
    property string baseUrl: "http://127.0.0.1:1"
    property int visualStyle: 0
    property var savedPatches: []

    function saveConfig(patch, callback) {
        savedPatches.push(patch);
        if (callback) callback(true);
    }

    // Plasma injects i18n(); a plain %N substitution is enough here.
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++) {
            text = text.replace("%" + i, arguments[i]);
        }
        return text;
    }
    function i18nc(context, text) {
        return i18n.apply(null, Array.prototype.slice.call(arguments, 1));
    }

    SignalSpy { id: bandsSpy; signalName: "bandsEdited" }

    QtObject {
        id: plasmoid
        property QtObject configuration: QtObject {
            property string fanCurvePresetsJson: "[]"
        }
    }

    Binding {
        target: KanteStyle
        property: "kind"
        value: root.visualStyle
    }

    Component { id: fanPageComponent; UI.FanPage {} }
    Component { id: sensorsPageComponent; UI.SensorsPage {} }
    Component { id: bandEditorComponent; UI.BandEditor {} }
    Component { id: bandSectionComponent; UI.KanteBandSection {} }
    Component { id: hintComponent; UI.OfflineHintKante {} }

    // First item below `item` for which `match` is true.
    function find(item, match) {
        if (match(item)) return item;
        var kids = item.children;
        for (var i = 0; i < kids.length; i++) {
            var found = find(kids[i], match);
            if (found) return found;
        }
        return null;
    }

    function findAll(item, match, into) {
        if (match(item)) into.push(item);
        for (var i = 0; i < item.children.length; i++) findAll(item.children[i], match, into);
        return into;
    }

    function isCurveEditor(item) { return item.setPoint !== undefined && item.addPoint !== undefined; }
    function isPlatformCurveEditor(item) { return item.liveMarkers !== undefined; }
    function isLineChart(item) { return item.hoverIndex !== undefined && item.pointsOf !== undefined; }
    function isChip(item) { return item.chipColor !== undefined && item.checkable !== undefined; }
    function isBandEditor(item) { return item.bands !== undefined && item.cycleColor !== undefined; }
    function isCommandBox(item) { return item.copyText !== undefined && item.copiedText !== undefined; }

    TestCase {
        name: "KanteAdoption"

        function init() {
            root.savedPatches = [];
            root.thermalData = null;
            root.configData = null;
        }

        property var sections: []

        function cleanup() {
            root.visualStyle = 0;
            // Before the source goes: the section binds to it.
            for (var i = 0; i < sections.length; i++) sections[i].destroy();
            sections = [];
        }

        // --- Fan curve ---

        function seededFanPage() {
            var page = createTemporaryObject(fanPageComponent, root);
            root.thermalData = { temps: { CPU: 55, GPU: 40 }, fans: [{ name: "Left" }] };
            root.configData = {
                fan: { mode: "curve", curve: { points: [[40, 0], [60, 50], [80, 90]], hysteresis_c: 2, rate_limit_pct_per_step: 20, poll_ms: 1000, sensors: ["CPU", "GPU"] } }
            };
            return page;
        }

        function test_curveEditorFollowsTheStyle() {
            var page = seededFanPage();
            var kante = find(page, isCurveEditor);
            var platform = find(page, isPlatformCurveEditor);
            verify(kante);
            verify(platform);

            verify(!kante.visible);
            verify(platform.visible);

            root.visualStyle = 1;
            verify(kante.visible);
            verify(!platform.visible);

            root.visualStyle = 2;
            verify(kante.visible);
        }

        function test_kanteCurveEditorShowsTheConfiguredCurve() {
            root.visualStyle = 1;
            var kante = find(seededFanPage(), isCurveEditor);
            compare(kante.points.length, 3);
            compare(kante.points[1].x, 60);
            compare(kante.points[1].y, 50);
        }

        function test_kanteCurveEditorEditSavesOnce() {
            root.visualStyle = 1;
            var page = seededFanPage();
            var kante = find(page, isCurveEditor);
            wait(600);
            root.savedPatches = [];

            kante.setPoint(1, 65, 60);
            kante.setPoint(1, 66, 62);

            compare(page.curvePoints, [[40, 0], [66, 62], [80, 90]]);
            wait(600);
            compare(root.savedPatches.length, 1, "edits coalesce into one save");
            compare(root.savedPatches[0].fan.curve.points, [[40, 0], [66, 62], [80, 90]]);
        }

        function test_kanteCurveEditorDoesNotForceARisingCurve() {
            root.visualStyle = 1;
            var page = seededFanPage();
            var kante = find(page, isCurveEditor);
            kante.setPoint(2, 80, 20);
            compare(page.curvePoints[2], [80, 20]);
        }

        function test_reseedingDoesNotSave() {
            root.visualStyle = 1;
            seededFanPage();
            wait(600);
            compare(root.savedPatches.length, 0);
        }

        function test_liveReadingsAreMarkersInDataColors() {
            root.visualStyle = 1;
            var kante = find(seededFanPage(), isCurveEditor);
            compare(kante.markers.length, 2);
            compare(kante.markers[0].x, 55);
            compare(kante.markers[0].color, KanteStyle.dataColor(0));
            compare(kante.markers[1].color, KanteStyle.dataColor(1));
            verify(kante.markers[0].label.indexOf("CPU") >= 0);
        }

        function test_curveHandlesAreNoDataColor() {
            root.visualStyle = 1;
            for (var i = 0; i < 6; i++) {
                verify(!Qt.colorEqual(KanteStyle.strongTextColor, KanteStyle.dataColor(i)));
            }
        }

        // --- Sensors chart ---

        function seededSensorsPage() {
            var page = createTemporaryObject(sensorsPageComponent, root);
            page.availableSensors = ["CPU", "GPU"];
            page.selectedSensors = ["GPU"];
            page.series = { GPU: [[1000, 41], [2000, 57]] };
            return page;
        }

        function test_sensorChartFollowsTheStyle() {
            var page = seededSensorsPage();
            var chart = find(page, isLineChart);
            verify(chart);
            verify(!chart.visible);

            root.visualStyle = 1;
            verify(chart.visible);
        }

        function test_sensorChartKeepsColorsOfDeselectedSensors() {
            root.visualStyle = 1;
            var page = seededSensorsPage();
            var chart = find(page, isLineChart);
            compare(chart.series.length, 2);
            compare(chart.series[0], [], "CPU is deselected: no line, index kept");
            compare(chart.series[1], [41, 57]);
            compare(chart.minValue, 40);
            compare(chart.maxValue, 60);
            verify(chart.axis);
            compare(chart.labels.length, 2);
        }

        function test_sensorLegendChipUsesTheLineColor() {
            root.visualStyle = 1;
            var page = seededSensorsPage();
            var chips = findAll(page, isChip, []).filter(function(c) { return c.visible; });
            compare(chips.length, 1);
            compare(chips[0].text, "GPU");
            compare(chips[0].chipColor, KanteStyle.dataColor(1));
        }

        // --- Band editor ---

        function seededBands() {
            var source = createTemporaryObject(bandEditorComponent, root, { mode: "temp", maxValue: 120 });
            source.bands = [
                { upTo: 60, color: "positive" }, { upTo: 80, color: "neutral" }, { upTo: null, color: "negative" }
            ];
            var section = createTemporaryObject(bandSectionComponent, root, { source: source });
            sections.push(section);
            return { source: source, section: section, editor: find(section, isBandEditor) };
        }

        function test_bandSectionShowsTheThresholdsAsLowerBounds() {
            var b = seededBands();
            verify(b.editor);
            compare(b.editor.bands.map(function(x) { return x.value; }), [0, 60, 80]);
            compare(b.editor.max, 120);
            verify(b.editor.pick);
        }

        function test_bandSectionWritesBackThresholds() {
            var b = seededBands();
            bandsSpy.clear();
            bandsSpy.target = b.source;

            b.editor.setValue(1, 50);

            compare(bandsSpy.count, 1);
            compare(b.source.bands, [
                { upTo: 50, color: "positive" }, { upTo: 80, color: "neutral" }, { upTo: null, color: "negative" }
            ]);
            compare(b.editor.bands[1].value, 50, "editor follows the source");
        }

        function test_bandSectionKeepsThemeTokens() {
            var b = seededBands();
            b.editor.cycleColor(0);
            compare(b.source.bands[0].color, "neutral");
        }

        function test_bandSectionAddAndRemove() {
            var b = seededBands();
            b.editor.addBand();
            compare(b.source.bands.length, 4);
            compare(b.source.bands[b.source.bands.length - 1].upTo, null);

            b.editor.removeBand(0);
            compare(b.source.bands.length, 3);
        }

        // --- Offline state ---

        function test_offlineHintUsesCommandBoxes() {
            root.visualStyle = 1;
            root.serviceOnline = false;
            var hint = createTemporaryObject(hintComponent, root);
            var boxes = findAll(hint, isCommandBox, []);
            compare(boxes.length, 2);
            verify(boxes[0].text.indexOf("install-linux.sh") >= 0);
            root.serviceOnline = true;
        }
    }
}
