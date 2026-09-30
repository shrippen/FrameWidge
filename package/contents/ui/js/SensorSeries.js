.pragma library

// Shapes the Sensors tab history for KanteLineChart, which takes one list of
// plain numbers per line, evenly spaced, and colors lines by their index.

// series: { name: [[ts_ms, temp], ...] }, names: the sensor list in its fixed
// order. Returns { values: [[temp, ...] per name], times: [ts_ms, ...] }.
// Every line runs over the same timeline; a sensor without a sample at a
// timestamp keeps its last value (its first one before it starts). A sensor
// without any data (e.g. deselected) gets an empty list, so it draws nothing
// but the other lines keep their colors.
function align(series, names) {
    var seen = {};
    var times = [];
    for (var n = 0; n < names.length; n++) {
        var pts = series[names[n]] || [];
        for (var p = 0; p < pts.length; p++) {
            if (seen[pts[p][0]]) continue;
            seen[pts[p][0]] = true;
            times.push(pts[p][0]);
        }
    }
    times.sort(function(a, b) { return a - b; });

    var values = [];
    for (var i = 0; i < names.length; i++) {
        var data = series[names[i]] || [];
        if (data.length === 0) { values.push([]); continue; }

        var byTime = {};
        for (var d = 0; d < data.length; d++) byTime[data[d][0]] = data[d][1];

        var line = [];
        var last = data[0][1];
        for (var t = 0; t < times.length; t++) {
            if (byTime[times[t]] !== undefined) last = byTime[times[t]];
            line.push(last);
        }
        values.push(line);
    }
    return { values: values, times: times };
}

// Scale of the temperature axis: starts at a whole ten and spans a multiple
// of 20, so the quarter grid lines land on multiples of 5. Returns { min, max }.
function scale(values) {
    var lo = Infinity, hi = -Infinity;
    for (var i = 0; i < values.length; i++) {
        for (var k = 0; k < values[i].length; k++) {
            lo = Math.min(lo, values[i][k]);
            hi = Math.max(hi, values[i][k]);
        }
    }
    if (lo === Infinity) return { min: 0, max: 100 };

    var min = Math.floor(lo / 10) * 10;
    var span = Math.max(20, Math.ceil((hi - min) / 20) * 20);
    return { min: min, max: min + span };
}
