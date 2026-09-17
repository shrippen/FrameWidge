import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "js/ColorGrading.js" as ColorGrading

KCM.SimpleKCM {
    id: generalKcm

    property alias cfg_servicePort: portField.value
    property alias cfg_pollIntervalMs: pollField.value
    property alias cfg_compactDisplay: displayCombo.currentValue
    property alias cfg_compactShowIcon: showIconCheck.checked
    property alias cfg_compactOverlayScale: overlayScaleField.value

    // The band editors are too stateful for a property alias: they hold a
    // list of {threshold, color} rows while kcfg stores a JSON string, so
    // this property is synced manually in both directions below.
    property string cfg_compactOverlayBands: ""

    // Guards against a seed->edit->reseed feedback loop: assigning
    // cfg_compactOverlayBands from the editors refires its change handler.
    property bool seedingBands: false

    function editorsBandsJson() {
        return JSON.stringify({
            temp: tempBands.bands, rpm: rpmBands.bands, soc: socBands.bands
        });
    }

    function seedBandEditors() {
        var parsed = ColorGrading.parseOverlayBands(cfg_compactOverlayBands);
        seedingBands = true;
        tempBands.bands = parsed.temp;
        rpmBands.bands = parsed.rpm;
        socBands.bands = parsed.soc;
        seedingBands = false;
    }

    // Fires both on the KCM's initial assignment (saved value or the kcfg
    // default) and on our own edits; the JSON comparison keeps the latter
    // from needlessly rebuilding the editors mid-interaction.
    onCfg_compactOverlayBandsChanged: {
        var normalized = JSON.stringify(ColorGrading.parseOverlayBands(cfg_compactOverlayBands));
        if (normalized !== editorsBandsJson()) seedBandEditors();
    }

    function onBandsEdited() {
        if (seedingBands) return;
        cfg_compactOverlayBands = editorsBandsJson();
    }

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: portField
            Kirigami.FormData.label: i18n("Service port:")
            from: 1
            to: 65535
            editable: true
        }

        QQC2.SpinBox {
            id: pollField
            Kirigami.FormData.label: i18n("Poll interval (ms):")
            from: 500
            to: 30000
            stepSize: 500
            editable: true
        }

        QQC2.ComboBox {
            id: displayCombo
            Kirigami.FormData.label: i18n("Tray display:")
            model: [
                { value: "temp", text: i18n("CPU Temperature") },
                { value: "rpm", text: i18n("Fan RPM") },
                { value: "soc", text: i18n("Battery %") },
                { value: "icon", text: i18n("Icon only") }
            ]
            textRole: "text"
            valueRole: "value"
        }

        QQC2.CheckBox {
            id: showIconCheck
            Kirigami.FormData.label: i18n("With data value:")
            text: i18n("Also show the icon")
            enabled: displayCombo.currentValue !== "icon"
            QQC2.ToolTip.text: i18n("Shows the plain chip icon together with the data value above, instead of the number filling the whole tray slot by itself.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.SpinBox {
            id: overlayScaleField
            Kirigami.FormData.label: i18n("Overlay size:")
            from: 50
            to: 200
            stepSize: 10
            editable: true
            enabled: displayCombo.currentValue !== "icon"
            textFromValue: function(value, locale) { return i18n("%1 %", value) }
            valueFromText: function(text, locale) { return parseInt(text) }
            QQC2.ToolTip.text: i18n("Scales the data value shown on the tray icon, in percent of its default size.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: 500
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            text: i18n("Overlay text colors by value")
            visible: displayCombo.currentValue !== "icon"
        }

        BandEditor {
            id: tempBands
            visible: displayCombo.currentValue !== "icon"
            mode: "temp"
            title: i18n("CPU temperature")
            unit: "°C"
            maxValue: 120
            Layout.fillWidth: true
            onBandsEdited: generalKcm.onBandsEdited()
        }

        BandEditor {
            id: rpmBands
            visible: displayCombo.currentValue !== "icon"
            mode: "rpm"
            title: i18n("Fan speed")
            unit: "RPM"
            maxValue: 8000
            Layout.fillWidth: true
            onBandsEdited: generalKcm.onBandsEdited()
        }

        BandEditor {
            id: socBands
            visible: displayCombo.currentValue !== "icon"
            mode: "soc"
            title: i18n("Battery charge")
            unit: "%"
            maxValue: 100
            Layout.fillWidth: true
            onBandsEdited: generalKcm.onBandsEdited()
        }
    }
}
