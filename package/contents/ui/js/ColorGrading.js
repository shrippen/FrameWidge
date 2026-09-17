.pragma library

// Pure color-selection logic, decoupled from Kirigami.Theme/plasmoid so it
// can be unit tested with plain values instead of a live Plasma host.

// QML's color property doesn't accept CSS hsl() strings (only #hex, named
// colors, and Qt.hsla()), and Canvas expects a plain string too - so this
// converts HSL to a #rrggbb string itself rather than depending on either.
function hslToHex(hue, saturationPct, lightnessPct) {
    var s = saturationPct / 100, l = lightnessPct / 100;
    var c = (1 - Math.abs(2 * l - 1)) * s;
    var x = c * (1 - Math.abs((hue / 60) % 2 - 1));
    var m = l - c / 2;
    var r = 0, g = 0, b = 0;
    if (hue < 60) { r = c; g = x; b = 0; }
    else if (hue < 120) { r = x; g = c; b = 0; }
    else if (hue < 180) { r = 0; g = c; b = x; }
    else if (hue < 240) { r = 0; g = x; b = c; }
    else if (hue < 300) { r = x; g = 0; b = c; }
    else { r = c; g = 0; b = x; }

    function toHex(v) {
        var hex = Math.round((v + m) * 255).toString(16);
        return hex.length === 1 ? "0" + hex : hex;
    }
    return "#" + toHex(r) + toHex(g) + toHex(b);
}

// Deterministic per-sensor hue, with lightness tuned for the active Plasma
// color scheme: dark themes need lighter lines to read against a dark
// chart background, light themes need darker, more saturated ones to keep
// contrast against white - a single fixed hex palette can't do both.
function sensorColor(name, isDark) {
    var hash = 0;
    for (var i = 0; i < name.length; i++) {
        hash = ((hash << 5) - hash) + name.charCodeAt(i);
        hash |= 0;
    }
    var hue = Math.abs(hash) % 360;
    var saturation = 65;
    var lightness = isDark ? 68 : 40;
    return hslToHex(hue, saturation, lightness);
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
