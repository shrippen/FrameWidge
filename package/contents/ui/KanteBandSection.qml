import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "Kante"
import "KantePlasma"
import "js/ColorGrading.js" as ColorGrading

// The Kante style of one BandEditor: a KanteBandEditor over the same bands.
// `source` stays the state holder (KCM seeding and serialization); this only
// converts between its threshold list and KanteBandEditor's lower bounds.
ColumnLayout {
    id: section

    required property Item source

    readonly property var tokens: ({
        positive: Kirigami.Theme.positiveTextColor,
        neutral: Kirigami.Theme.neutralTextColor,
        negative: Kirigami.Theme.negativeTextColor,
        text: Kirigami.Theme.textColor,
        disabled: Kirigami.Theme.disabledTextColor
    })

    spacing: Kirigami.Units.smallSpacing

    KantePlasmaHeading {
        level: 4
        text: section.source.title
        Layout.fillWidth: true
    }

    KanteBandEditor {
        Layout.fillWidth: true
        // The tray text uses these colors, so the swatches cycle through them.
        colors: [section.tokens.positive, section.tokens.neutral, section.tokens.negative, section.tokens.text, section.tokens.disabled]
        min: 0
        max: section.source.maxValue
        unit: section.source.unit
        addText: i18n("Add band")
        bands: ColorGrading.toKanteBands(section.source.bands, min, section.tokens)
        onEdited: function (edited) {
            section.source.bands = ColorGrading.fromKanteBands(edited, min, max, section.tokens);
            section.source.bandsEdited();
        }
    }

    KantePlasmaButton {
        icon.name: "edit-undo"
        text: i18n("Reset to defaults")
        onClicked: section.source.resetToDefaults()
    }
}
