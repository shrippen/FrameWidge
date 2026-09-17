.pragma library

// Pure coordinate math for the fan curve editor, kept free of any QML
// Item state so it can be unit tested without instantiating a Canvas.

function tempToX(temp, width, padLeft, padRight, tempMin, tempMax) {
    var w = width - padLeft - padRight;
    return padLeft + ((temp - tempMin) / (tempMax - tempMin)) * w;
}

function dutyToY(duty, height, padTop, padBottom, dutyMin, dutyMax) {
    var h = height - padTop - padBottom;
    return padTop + (1 - (duty - dutyMin) / (dutyMax - dutyMin)) * h;
}

function xToTemp(x, width, padLeft, padRight, tempMin, tempMax) {
    var w = width - padLeft - padRight;
    var raw = tempMin + ((x - padLeft) / w) * (tempMax - tempMin);
    return Math.round(Math.max(tempMin, Math.min(tempMax, raw)));
}

function yToDuty(y, height, padTop, padBottom, dutyMin, dutyMax) {
    var h = height - padTop - padBottom;
    var raw = dutyMax - ((y - padTop) / h) * (dutyMax - dutyMin);
    return Math.round(Math.max(dutyMin, Math.min(dutyMax, raw)));
}
