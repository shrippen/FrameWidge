import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: batteryPage
    spacing: Kirigami.Units.smallSpacing

    property var battery: root.powerData ? root.powerData.battery : null

    // Config-seeded values
    property bool clEnabled: false
    property int clValue: 100
    property bool rateEnabled: false
    property real rateC: 1.0
    property var socThresholdPct: undefined

    property bool configLoaded: false
    property bool applyGuard: false // suppress re-apply while seeding from server state

    Component.onCompleted: {
        if (root.configData) seedFromConfig(root.configData);
    }

    Connections {
        target: root
        function onConfigDataChanged() { seedFromConfig(root.configData); }
    }

    function seedFromConfig(data) {
        if (!data || !data.battery) return;
        applyGuard = true;
        var bat = data.battery;
        if (bat.charge_limit_max_pct) {
            clEnabled = !!bat.charge_limit_max_pct.enabled;
            clValue = bat.charge_limit_max_pct.value || 100;
        }
        if (bat.charge_rate_c) {
            rateEnabled = !!bat.charge_rate_c.enabled;
            rateC = bat.charge_rate_c.value || 1.0;
        }
        socThresholdPct = bat.charge_rate_soc_threshold_pct;
        configLoaded = true;
        applyGuard = false;
    }

    function applyChargeLimit() {
        if (applyGuard) return;
        root.saveConfig({
            battery: {
                charge_limit_max_pct: {
                    enabled: clEnabled,
                    value: Math.max(25, Math.min(100, clValue))
                }
            }
        });
    }

    function applyRateLimit() {
        if (applyGuard) return;
        var value = rateEnabled ? Math.max(0.05, Math.min(1.0, rateC)) : 1.0;
        var patch = {
            battery: {
                charge_rate_c: {
                    enabled: rateEnabled,
                    value: value
                },
                charge_rate_soc_threshold_pct: socThresholdPct
            }
        };
        root.saveConfig(patch);
    }

    // Coalesce rapid slider drags into a single request each
    Timer {
        id: chargeLimitDebounce
        interval: 350
        onTriggered: applyChargeLimit()
    }
    Timer {
        id: rateLimitDebounce
        interval: 350
        onTriggered: applyRateLimit()
    }
    function scheduleChargeLimitApply() { chargeLimitDebounce.restart(); }
    function scheduleRateLimitApply() { rateLimitDebounce.restart(); }

    // --- Info bar ---
    Kirigami.FormLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("State of Charge:")
            text: battery && battery.percentage !== undefined ? battery.percentage + "%" : "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Power:")
            text: {
                if (!battery || battery.present_rate_ma === undefined || battery.present_voltage_mv === undefined) return "—";
                var watts = (battery.present_rate_ma * battery.present_voltage_mv) / 1000000;
                var sign = battery.charging ? "+" : "-";
                return sign + watts.toFixed(2) + " W";
            }
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Health:")
            text: {
                if (!battery || !battery.design_capacity_mah || !battery.last_full_charge_capacity_mah) return "—";
                var pct = Math.round((battery.last_full_charge_capacity_mah / battery.design_capacity_mah) * 100);
                return pct + "%";
            }
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Cycles:")
            text: battery && battery.cycle_count !== undefined ? battery.cycle_count : "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("Charge Limit:")
            text: battery && battery.charge_limit_max_pct !== undefined ? battery.charge_limit_max_pct + "%" : "—"
        }

        PlasmaComponents.Label {
            Kirigami.FormData.label: i18n("AC:")
            text: battery && battery.ac_present !== undefined ? (battery.ac_present ? i18n("Plugged in") : i18n("On battery")) : "—"
        }
    }

    Kirigami.Separator { Layout.fillWidth: true }

    // --- Loading state ---
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        visible: !configLoaded
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.BusyIndicator {
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: width
            running: !configLoaded
        }
        PlasmaComponents.Label {
            text: i18n("Loading battery configuration…")
            opacity: 0.6
        }
    }

    // --- Charge Limit Control ---
    PlasmaExtras.Heading {
        Layout.leftMargin: Kirigami.Units.smallSpacing
        level: 5
        text: i18n("Charge Limit")
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        enabled: configLoaded
        opacity: configLoaded ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

        QQC2.CheckBox {
            id: clCheck
            checked: clEnabled
            onToggled: {
                clEnabled = checked;
                applyChargeLimit();
            }
        }

        QQC2.Slider {
            Layout.fillWidth: true
            from: 25
            to: 100
            stepSize: 5
            value: clValue
            enabled: clEnabled
            onMoved: {
                clValue = Math.round(value);
                scheduleChargeLimitApply();
            }
        }

        PlasmaComponents.Label {
            text: clValue + "%"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5
        }
    }

    // --- Charge Rate Control ---
    PlasmaExtras.Heading {
        Layout.leftMargin: Kirigami.Units.smallSpacing
        level: 5
        text: i18n("Charge Rate Limit")
        HoverHandler { id: chargeRateHeadingHover }
        QQC2.ToolTip.visible: chargeRateHeadingHover.hovered
        QQC2.ToolTip.delay: 500
        QQC2.ToolTip.text: i18n("Limits charging speed in \"C-rate\": 1.0C charges the battery in about an hour, 0.5C in about two. Slower charging generates less heat and can extend battery lifespan.")
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        enabled: configLoaded
        opacity: configLoaded ? 1 : 0.4
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

        QQC2.CheckBox {
            checked: rateEnabled
            onToggled: {
                rateEnabled = checked;
                applyRateLimit();
            }
        }

        QQC2.Slider {
            Layout.fillWidth: true
            from: 0.05
            to: 1.0
            stepSize: 0.05
            value: rateC
            enabled: rateEnabled
            onMoved: {
                rateC = Math.round(value * 20) / 20;
                scheduleRateLimitApply();
            }
        }

        PlasmaComponents.Label {
            text: rateC.toFixed(2) + " C"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
        }
    }

    // SoC threshold
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing * 2
        Layout.rightMargin: Kirigami.Units.largeSpacing
        visible: rateEnabled
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            text: i18n("SoC threshold:")
        }

        QQC2.SpinBox {
            from: 0
            to: 100
            value: socThresholdPct !== undefined ? socThresholdPct : 0
            editable: true
            onValueModified: {
                socThresholdPct = value > 0 ? value : undefined;
                applyRateLimit();
            }
        }

        PlasmaComponents.Label { text: "%" }

        PlasmaComponents.Button {
            text: i18n("Clear")
            visible: socThresholdPct !== undefined
            onClicked: {
                socThresholdPct = undefined;
                applyRateLimit();
            }
        }
    }

    Item { Layout.fillHeight: true }
}
