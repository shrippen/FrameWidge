import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_servicePort: portField.value
    property alias cfg_pollIntervalMs: pollField.value
    property alias cfg_compactDisplay: displayCombo.currentValue

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
    }
}
