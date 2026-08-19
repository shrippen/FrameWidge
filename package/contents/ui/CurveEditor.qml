import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: curveEditor

    property var points: [[40, 0], [60, 40], [75, 80], [85, 100]]
    property int dragIndex: -1

    // Axis ranges
    readonly property int tempMin: 0
    readonly property int tempMax: 100
    readonly property int dutyMin: 0
    readonly property int dutyMax: 100

    // Padding
    readonly property int padLeft: 36
    readonly property int padRight: 12
    readonly property int padTop: 12
    readonly property int padBottom: 22

    function tempToX(temp) {
        var w = width - padLeft - padRight;
        return padLeft + ((temp - tempMin) / (tempMax - tempMin)) * w;
    }

    function dutyToY(duty) {
        var h = height - padTop - padBottom;
        return padTop + (1 - (duty - dutyMin) / (dutyMax - dutyMin)) * h;
    }

    function xToTemp(x) {
        var w = width - padLeft - padRight;
        return Math.round(Math.max(tempMin, Math.min(tempMax, tempMin + ((x - padLeft) / w) * (tempMax - tempMin))));
    }

    function yToDuty(y) {
        var h = height - padTop - padBottom;
        return Math.round(Math.max(dutyMin, Math.min(dutyMax, dutyMax - ((y - padTop) / h) * (dutyMax - dutyMin))));
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            // Grid
            ctx.strokeStyle = Kirigami.Theme.disabledTextColor;
            ctx.lineWidth = 0.5;
            for (var t = 0; t <= 100; t += 20) {
                var x = tempToX(t);
                ctx.beginPath();
                ctx.moveTo(x, padTop);
                ctx.lineTo(x, height - padBottom);
                ctx.stroke();
            }
            for (var d = 0; d <= 100; d += 20) {
                var y = dutyToY(d);
                ctx.beginPath();
                ctx.moveTo(padLeft, y);
                ctx.lineTo(width - padRight, y);
                ctx.stroke();
            }

            // Axis labels
            ctx.fillStyle = Kirigami.Theme.textColor;
            ctx.font = "10px sans-serif";
            ctx.textAlign = "center";
            for (var t2 = 0; t2 <= 100; t2 += 20) {
                ctx.fillText(t2 + "°", tempToX(t2), height - 4);
            }
            ctx.textAlign = "right";
            for (var d2 = 0; d2 <= 100; d2 += 20) {
                ctx.fillText(d2 + "%", padLeft - 4, dutyToY(d2) + 4);
            }

            // Curve line
            if (points.length > 0) {
                ctx.strokeStyle = Kirigami.Theme.highlightColor;
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.moveTo(tempToX(points[0][0]), dutyToY(points[0][1]));
                for (var i = 1; i < points.length; i++) {
                    ctx.lineTo(tempToX(points[i][0]), dutyToY(points[i][1]));
                }
                ctx.stroke();
            }

            // Points
            for (var j = 0; j < points.length; j++) {
                var px = tempToX(points[j][0]);
                var py = dutyToY(points[j][1]);
                ctx.fillStyle = j === dragIndex ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor;
                ctx.beginPath();
                ctx.arc(px, py, 6, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        onPressed: function(mouse) {
            for (var i = 0; i < points.length; i++) {
                var px = tempToX(points[i][0]);
                var py = dutyToY(points[i][1]);
                if (Math.abs(mouse.x - px) < 12 && Math.abs(mouse.y - py) < 12) {
                    dragIndex = i;
                    return;
                }
            }
            // Add new point
            var newTemp = xToTemp(mouse.x);
            var newDuty = yToDuty(mouse.y);
            var newPoints = points.slice();
            newPoints.push([newTemp, newDuty]);
            newPoints.sort(function(a, b) { return a[0] - b[0]; });
            points = newPoints;
            for (var k = 0; k < points.length; k++) {
                if (points[k][0] === newTemp && points[k][1] === newDuty) {
                    dragIndex = k;
                    break;
                }
            }
            canvas.requestPaint();
        }

        onPositionChanged: function(mouse) {
            if (dragIndex < 0) return;
            var newTemp = xToTemp(mouse.x);
            var newDuty = yToDuty(mouse.y);
            var newPoints = points.slice();
            newPoints[dragIndex] = [newTemp, newDuty];
            newPoints.sort(function(a, b) { return a[0] - b[0]; });
            // Find new index after sort
            for (var i = 0; i < newPoints.length; i++) {
                if (newPoints[i][0] === newTemp && newPoints[i][1] === newDuty) {
                    dragIndex = i;
                    break;
                }
            }
            points = newPoints;
            canvas.requestPaint();
        }

        onReleased: {
            if (dragIndex >= 0) {
                dragIndex = -1;
                curveEditor.pointsChanged();
            }
            canvas.requestPaint();
        }

        onDoubleClicked: function(mouse) {
            if (points.length <= 2) return;
            for (var i = 0; i < points.length; i++) {
                var px = tempToX(points[i][0]);
                var py = dutyToY(points[i][1]);
                if (Math.abs(mouse.x - px) < 12 && Math.abs(mouse.y - py) < 12) {
                    var newPoints = points.slice();
                    newPoints.splice(i, 1);
                    points = newPoints;
                    curveEditor.pointsChanged();
                    canvas.requestPaint();
                    return;
                }
            }
        }
    }

    onPointsChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
