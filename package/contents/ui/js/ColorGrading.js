.pragma library

// Pure color-selection logic, decoupled from Kirigami.Theme/plasmoid so it
// can be unit tested with plain values instead of a live Plasma host.

var SENSOR_PALETTE = ["#e63946", "#457b9d", "#2a9d8f", "#e9c46a", "#f4a261", "#264653", "#6a0572", "#d62828", "#003049"];

function sensorColor(name) {
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
        hash = ((hash << 5) - hash) + name.charCodeAt(i);
        hash |= 0;
    }
    return SENSOR_PALETTE[Math.abs(hash) % SENSOR_PALETTE.length];
}

// colors: { disabled, negative, neutral, positive, text }
function gradeIndicatorColor(serviceOnline, mode, cpuTemp, colors) {
    if (!serviceOnline) return colors.disabled;
    if (mode === "temp" || mode === undefined) {
        if (cpuTemp > 85) return colors.negative;
        if (cpuTemp > 70) return colors.neutral;
        return colors.positive;
    }
    return colors.text;
}
