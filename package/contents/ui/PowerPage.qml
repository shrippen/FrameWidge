import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

import "Kante"

// Power tab: the system's power profile from power-profiles-daemon (or
// tuned-ppd), the same switch as in Plasma's battery applet. That daemon
// owns governor, EPP and platform profile; the service only passes the
// choice on (see DESIGN.md).
ColumnLayout {
    id: powerPage
    spacing: Kirigami.Units.smallSpacing

    readonly property var battery: root.powerData ? root.powerData.battery : null
    // { active, available } or null without a profile daemon
    readonly property var profile: root.powerData ? root.powerData.profile : null
    readonly property bool loaded: root.powerData !== null

    // The clicked profile shows at once, until the service answered.
    property string pendingProfile: ""
    readonly property string activeProfile: pendingProfile !== "" ? pendingProfile : (profile ? profile.active : "")

    function profileLabel(name) {
        if (name === "power-saver") return i18n("Power Saver");
        if (name === "balanced") return i18n("Balanced");
        if (name === "performance") return i18n("Performance");
        return name;
    }

    function choose(name) {
        if (name === activeProfile) return;
        pendingProfile = name;
        root.setPowerProfile(name, function() { powerPage.pendingProfile = ""; });
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("AC:")
            text: battery && battery.ac_present !== undefined && battery.ac_present !== null
                ? (battery.ac_present ? i18n("Plugged in") : i18n("On battery")) : "—"
        }
    }

    // Loading
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        visible: !loaded
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.BusyIndicator {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: width
            running: !loaded
        }
        PlasmaComponents.Label {
            text: i18n("Loading power profiles…")
            opacity: 0.6
        }
    }

    // No profile daemon
    PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        visible: loaded && !profile
        wrapMode: Text.WordWrap
        text: i18n("No power profile service is running (power-profiles-daemon or tuned-ppd).")
        opacity: 0.6
    }

    // --- Profiles ---
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        visible: !!profile
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: i18n("Power profile:")
            HoverHandler { id: profileHover }
            QQC2.ToolTip.visible: profileHover.hovered
            QQC2.ToolTip.delay: 500
            QQC2.ToolTip.text: i18n("The system's power profile, the same setting as in Plasma's battery applet. It sets the CPU's energy preference and the firmware's platform profile.")
        }

        Repeater {
            model: profile ? profile.available : []

            QQC2.RadioButton {
                KanteCheckSkin { control: parent; shape: KanteCheckSkin.Shape.Radio }
                required property string modelData
                text: powerPage.profileLabel(modelData)
                checked: powerPage.activeProfile === modelData
                onClicked: powerPage.choose(modelData)
            }
        }
    }

    Item { Layout.fillHeight: true }
}
