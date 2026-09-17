import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "js/ColorGrading.js" as ColorGrading

// Editor for one display mode's list of value->color bands (see
// ColorGrading.js for the schema). Bands are edited as rows of
// [threshold SpinBox | color swatch | remove button]; the last row is the
// open-ended "and above" catch-all and has no threshold. Emits bandsEdited
// on user edits only - external assignment to `bands` (seeding) stays silent.
//
// Internally the rows live in a ListModel (with -1 as the open-ended
// sentinel, since ListModel roles dislike null): editing a role updates the
// delegate in place, whereas reassigning a plain JS array would make the
// Repeater rebuild every row - including the SpinBox currently being typed
// into, which would lose focus on every keystroke.
ColumnLayout {
    id: editor

    // "temp" | "rpm" | "soc" - used for the reset-to-defaults action.
    property string mode: ""
    property string title: ""
    property string unit: ""
    property int maxValue: 100
    property var bands: []

    // True while bands<->model sync is running, to tell external assignment
    // (reseed the model) apart from our own commit (already in sync).
    property bool syncing: false

    signal bandsEdited

    onBandsChanged: {
        if (syncing) return;
        syncing = true;
        bandModel.clear();
        for (var i = 0; i < bands.length; i++) {
            bandModel.append({ bandUpTo: bands[i].upTo === null ? -1 : bands[i].upTo, bandColor: bands[i].color });
        }
        syncing = false;
    }

    // Pushes the ListModel state out to the `bands` property and notifies
    // the parent (KCM serialization) about a user edit.
    function commit() {
        var out = [];
        for (var i = 0; i < bandModel.count; i++) {
            var row = bandModel.get(i);
            out.push({ upTo: row.bandUpTo < 0 ? null : row.bandUpTo, color: row.bandColor });
        }
        syncing = true;
        bands = out;
        syncing = false;
        bandsEdited();
    }

    function addBand() {
        // Subdivide the open-ended top band: the new band inherits its color
        // and lands halfway between the previous threshold and maxValue.
        var prev = bandModel.count >= 2 ? bandModel.get(bandModel.count - 2).bandUpTo : 0;
        var mid = Math.min(maxValue, Math.round(prev + (maxValue - prev) / 2));
        bandModel.insert(bandModel.count - 1, { bandUpTo: mid, bandColor: bandModel.get(bandModel.count - 1).bandColor });
        commit();
    }

    function removeBand(index) {
        if (bandModel.count <= 1) return;
        bandModel.remove(index);
        commit();
    }

    function resetToDefaults() {
        var defaults = ColorGrading.defaultOverlayBands()[mode];
        syncing = true;
        bandModel.clear();
        for (var i = 0; i < defaults.length; i++) {
            bandModel.append({ bandUpTo: defaults[i].upTo === null ? -1 : defaults[i].upTo, bandColor: defaults[i].color });
        }
        syncing = false;
        commit();
    }

    // Resolves a band color (theme token or #rrggbb) for the swatch preview.
    function resolveColor(c) {
        switch (c) {
        case "positive": return Kirigami.Theme.positiveTextColor;
        case "neutral": return Kirigami.Theme.neutralTextColor;
        case "negative": return Kirigami.Theme.negativeTextColor;
        case "disabled": return Kirigami.Theme.disabledTextColor;
        case "text": return Kirigami.Theme.textColor;
        }
        return c;
    }

    function colorToHex(c) {
        function h(v) {
            var s = Math.round(v * 255).toString(16);
            return s.length === 1 ? "0" + s : s;
        }
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    ListModel { id: bandModel }

    spacing: Kirigami.Units.smallSpacing

    Kirigami.Heading {
        text: editor.title
        level: 4
        Layout.fillWidth: true
    }

    Repeater {
        model: bandModel

        delegate: RowLayout {
            id: bandRow
            required property int index
            required property int bandUpTo
            required property string bandColor
            readonly property bool isLast: index === bandModel.count - 1

            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                // "Above N" only makes sense relative to the previous threshold
                text: bandRow.isLast
                    ? (bandModel.count > 1 ? i18nc("color band: everything above N", "Above %1:", bandModel.get(bandModel.count - 2).bandUpTo) : i18n("Any value:"))
                    : i18n("Up to:")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
            }

            QQC2.SpinBox {
                visible: !bandRow.isLast
                from: bandRow.index > 0 ? bandModel.get(bandRow.index - 1).bandUpTo + 1 : 0
                to: editor.maxValue
                editable: true
                value: bandRow.bandUpTo
                onValueModified: {
                    bandModel.setProperty(bandRow.index, "bandUpTo", value);
                    editor.commit();
                }
            }

            QQC2.Label {
                text: editor.unit
            }

            Item { Layout.fillWidth: true }

            // Color swatch; opens a ColorDialog for a custom hex color.
            QQC2.Button {
                implicitWidth: Kirigami.Units.gridUnit * 2
                implicitHeight: Kirigami.Units.gridUnit * 1.2
                onClicked: {
                    colorDialog.targetIndex = bandRow.index;
                    colorDialog.selectedColor = editor.resolveColor(bandRow.bandColor);
                    colorDialog.open();
                }
                background: Rectangle {
                    radius: 3
                    color: editor.resolveColor(bandRow.bandColor)
                    border.color: Kirigami.Theme.textColor
                    border.width: 1
                }
                QQC2.ToolTip.text: i18n("Band color (defaults follow the system color scheme; picking one here sets a fixed custom color)")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
                Accessible.name: i18n("Color for band %1", bandRow.index + 1)
            }

            QQC2.ToolButton {
                icon.name: "list-remove"
                enabled: bandModel.count > 1
                onClicked: editor.removeBand(bandRow.index)
                QQC2.ToolTip.text: i18n("Remove this band")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: 500
                Accessible.name: i18n("Remove band %1", bandRow.index + 1)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        QQC2.Button {
            icon.name: "list-add"
            text: i18n("Add band")
            onClicked: editor.addBand()
        }
        Item { Layout.fillWidth: true }
        QQC2.Button {
            icon.name: "edit-undo"
            text: i18n("Reset to defaults")
            onClicked: editor.resetToDefaults()
        }
    }

    ColorDialog {
        id: colorDialog
        property int targetIndex: -1
        onAccepted: {
            if (targetIndex >= 0) {
                bandModel.setProperty(targetIndex, "bandColor", editor.colorToHex(selectedColor));
                editor.commit();
            }
        }
    }
}