import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_servicePort: portField.value
    property alias cfg_pollIntervalMs: pollField.value
    property alias cfg_compactDisplay: displayCombo.currentValue
    property alias cfg_compactShowIcon: showIconCheck.checked

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
    }
}
