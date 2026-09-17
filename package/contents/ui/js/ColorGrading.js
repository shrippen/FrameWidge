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

// --- Configurable value bands for the tray overlay text color ---
//
// Each display mode (temp/rpm/soc) maps to an ordered list of bands
// [{ upTo: <number|null>, color: <token|#rrggbb> }, ...]. A band matches when
// value <= upTo; the last band is always open-ended (upTo: null) so every
// value above the last threshold still gets a color.
//
// Band colors are either theme tokens ("positive"/"neutral"/"negative"/
// "text"/"disabled"), resolved against the colors map the caller passes in so
// the defaults automatically follow the active Plasma/Breeze color scheme, or
// literal "#rrggbb" strings for custom colors picked in the KCM color dialog.

function defaultOverlayBands() {
    return {
        temp: [
            { upTo: 60, color: "positive" },
            { upTo: 80, color: "neutral" },
            { upTo: null, color: "negative" }
        ],
        rpm: [
            { upTo: 2500, color: "positive" },
            { upTo: 4000, color: "neutral" },
            { upTo: null, color: "negative" }
        ],
        // SoC is inverted: low charge is bad, high charge is good.
        soc: [
            { upTo: 20, color: "negative" },
            { upTo: 50, color: "neutral" },
            { upTo: null, color: "positive" }
        ]
    };
}

var overlayBandModes = ["temp", "rpm", "soc"];
var bandColorTokens = ["positive", "neutral", "negative", "text", "disabled"];

function isValidBand(band) {
    if (!band || typeof band !== "object") return false;
    if (band.upTo !== null && typeof band.upTo !== "number") return false;
    if (typeof band.color !== "string") return false;
    if (bandColorTokens.indexOf(band.color) !== -1) return true;
    return /^#[0-9a-fA-F]{6}$/.test(band.color);
}

// Parses the kcfg JSON string into a { temp, rpm, soc } band map, falling
// back to the defaults per mode whenever the stored value is missing or
// invalid - the tray must never end up colorless because of a hand-edited
// config file.
function parseOverlayBands(json) {
    var defaults = defaultOverlayBands();
    var parsed;
    try {
        parsed = JSON.parse(json);
    } catch (e) {
        return defaults;
    }
    if (!parsed || typeof parsed !== "object") return defaults;

    var result = {};
    for (var i = 0; i < overlayBandModes.length; i++) {
        var mode = overlayBandModes[i];
        var bands = parsed[mode];
        if (!Array.isArray(bands)) { result[mode] = defaults[mode]; continue; }

        var cleaned = [];
        // Interior bands (all but the last) must have a real threshold; a
        // null there would swallow every higher band, so it gets dropped.
        for (var j = 0; j < bands.length - 1; j++) {
            if (!isValidBand(bands[j])) continue;
            if (bands[j].upTo !== null) cleaned.push({ upTo: bands[j].upTo, color: bands[j].color });
        }
        // The last band always becomes the open-ended catch-all.
        var last = bands[bands.length - 1];
        if (isValidBand(last)) cleaned.push({ upTo: null, color: last.color });

        result[mode] = cleaned.length > 0 ? cleaned : defaults[mode];
    }
    return result;
}

function resolveBandColor(color, colors) {
    if (colors[color] !== undefined) return colors[color]; // theme token
    return color; // literal #rrggbb
}

// colors: { disabled, negative, neutral, positive, text }
function gradeBandColor(serviceOnline, value, bands, colors) {
    if (!serviceOnline) return colors.disabled;
    if (value === undefined || value === null || isNaN(value) || value < 0) return colors.text;
    for (var i = 0; i < bands.length; i++) {
        if (bands[i].upTo === null || value <= bands[i].upTo) {
            return resolveBandColor(bands[i].color, colors);
        }
    }
    return colors.text; // unreachable for normalized bands, defensive
}
