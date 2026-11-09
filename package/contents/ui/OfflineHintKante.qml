import QtQuick
import QtQuick.Layouts

import "Kante"
import "KantePlasma"

// Service-unreachable / outdated / framework_tool-missing state in the Kante styles
// (KanteEmptyState). Same texts and actions as OfflineHint.qml, which the
// System style keeps.
ColumnLayout {
    // Anchors, not Layout.*: the Loader that holds this ignores them.
    anchors.fill: parent
    anchors.margins: KanteStyle.unit(12)

    Item { Layout.fillHeight: true }

    KanteEmptyState {
        Layout.fillWidth: true
        title: {
            if (!root.serviceOnline) return i18n("Service Not Reachable");
            if (!root.serviceCurrent) return i18n("Service Out of Date");
            return i18n("framework_tool Not Found");
        }
        text: {
            if (!root.serviceOnline)
                return i18n("The FrameWidge service (framewidged) is not running or not installed.\n\nInstall it with the command below, or start it if already installed.");
            if (!root.serviceCurrent)
                return i18n("The installed service (framewidged %1) is older than this widget.\n\nUpdate it with the command below.", root.serviceVersion);
            return i18n("The service is running but cannot find framework_tool.\nCheck the service logs for details.");
        }
    }

    // Install (or update) command
    ColumnLayout {
        Layout.fillWidth: true
        visible: !root.serviceOnline || !root.serviceCurrent
        spacing: KanteStyle.unit(8)

        KantePlasmaHeading {
            Layout.fillWidth: true
            level: 4
            text: root.serviceOnline ? i18n("Update:") : i18n("Install:")
        }

        KanteCommandBox {
            Layout.fillWidth: true
            text: "curl -fsSL https://raw.githubusercontent.com/shrippen/FrameWidge/main/install.sh | bash"
            copyText: i18n("Copy")
            copiedText: i18n("Copied")
        }
    }

    // Start command
    ColumnLayout {
        Layout.fillWidth: true
        visible: !root.serviceOnline
        spacing: KanteStyle.unit(8)

        KantePlasmaHeading {
            Layout.fillWidth: true
            level: 4
            text: i18n("Already installed? Start the service:")
        }

        KanteCommandBox {
            Layout.fillWidth: true
            text: "sudo systemctl enable --now framewidged"
            copyText: i18n("Copy")
            copiedText: i18n("Copied")
        }
    }

    Item { Layout.fillHeight: true }
}
