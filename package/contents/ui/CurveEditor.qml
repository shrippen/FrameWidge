import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

import "js/CurveMath.js" as CurveMath

Item {
    id: curveEditor

    property var points: [[40, 0], [60, 40], [75, 80], [85, 100]]
    property int dragIndex: -1
    // Selected point for keyboard control; independent of mouse dragIndex
    // so Tab/arrow-key users don't need to click first.
    property int selectedIndex: points.length > 0 ? 0 : -1

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

    activeFocusOnTab: true
    focus: false
    Accessible.role: Accessible.Slider
    Accessible.name: {
        if (selectedIndex < 0 || selectedIndex >= points.length) return i18n("Fan curve editor");
        return i18n("Fan curve editor, selected point: %1°C → %2%", points[selectedIndex][0], points[selectedIndex][1]);
    }
    Accessible.description: i18n("Click to add a point, drag to move it, double-click to remove it. Use arrow keys to fine-tune the selected point, Tab to select another, Delete to remove it.")

    function tempToX(temp) {
        return CurveMath.tempToX(temp, width, padLeft, padRight, tempMin, tempMax);
    }

    function dutyToY(duty) {
        return CurveMath.dutyToY(duty, height, padTop, padBottom, dutyMin, dutyMax);
    }

    function xToTemp(x) {
        return CurveMath.xToTemp(x, width, padLeft, padRight, tempMin, tempMax);
    }

    function yToDuty(y) {
        return CurveMath.yToDuty(y, height, padTop, padBottom, dutyMin, dutyMax);
    }

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    // Re-sorting points can shift indices; re-locate the same logical point
    // (by reference equality on the pair we just wrote) after a sort.
    function reindexAfterSort(newPoints, temp, duty) {
        for (var i = 0; i < newPoints.length; i++) {
            if (newPoints[i][0] === temp && newPoints[i][1] === duty) return i;
        }
        return -1;
    }

    Keys.onPressed: function(event) {
        if (selectedIndex < 0 || selectedIndex >= points.length) return;

        var step = (event.modifiers & Qt.ShiftModifier) ? 5 : 1;
        var temp = points[selectedIndex][0];
        var duty = points[selectedIndex][1];
        var moved = true;

        if (event.key === Qt.Key_Left) temp = clamp(temp - step, tempMin, tempMax);
        else if (event.key === Qt.Key_Right) temp = clamp(temp + step, tempMin, tempMax);
        else if (event.key === Qt.Key_Up) duty = clamp(duty + step, dutyMin, dutyMax);
        else if (event.key === Qt.Key_Down) duty = clamp(duty - step, dutyMin, dutyMax);
        else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            if (points.length > 2) {
                var afterDelete = points.slice();
                afterDelete.splice(selectedIndex, 1);
                points = afterDelete;
                selectedIndex = clamp(selectedIndex, 0, points.length - 1);
                curveEditor.pointsChanged();
            }
            event.accepted = true;
            return;
        } else {
            moved = false;
        }

        if (moved) {
            var newPoints = points.slice();
            newPoints[selectedIndex] = [temp, duty];
            newPoints.sort(function(a, b) { return a[0] - b[0]; });
            selectedIndex = reindexAfterSort(newPoints, temp, duty);
            points = newPoints;
            curveEditor.pointsChanged();
            event.accepted = true;
        }
    }

    Keys.onTabPressed: {
        if (points.length > 0) selectedIndex = (selectedIndex + 1) % points.length;
    }
    Keys.onBacktabPressed: {
        if (points.length > 0) selectedIndex = (selectedIndex - 1 + points.length) % points.length;
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        Accessible.ignored: true // curveEditor itself carries the accessible name/description
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
                ctx.lineJoin = "round";
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
                var isActive = j === dragIndex || j === selectedIndex;
                ctx.fillStyle = isActive ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor;
                ctx.beginPath();
                ctx.arc(px, py, j === selectedIndex && curveEditor.activeFocus ? 7 : 6, 0, 2 * Math.PI);
                ctx.fill();
                if (j === selectedIndex && curveEditor.activeFocus) {
                    ctx.strokeStyle = Kirigami.Theme.highlightColor;
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    ctx.arc(px, py, 10, 0, 2 * Math.PI);
                    ctx.stroke();
                }
            }
        }
    }

    // Floating readout for the point currently being dragged or hovered
    PlasmaComponents.Label {
        id: readout
        readonly property int shownIndex: dragIndex >= 0 ? dragIndex : hoverIndex
        visible: shownIndex >= 0 && shownIndex < points.length
        text: visible ? i18n("%1°C → %2%", points[shownIndex][0], points[shownIndex][1]) : ""
        x: Math.min(Math.max((visible ? tempToX(points[shownIndex][0]) : 0) - width / 2, 0), parent.width - width)
        y: visible ? Math.max(0, dutyToY(points[shownIndex][1]) - Kirigami.Units.gridUnit) : 0
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        font.bold: true
        color: Kirigami.Theme.highlightColor

        property int hoverIndex: -1
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        onPressed: function(mouse) {
            curveEditor.forceActiveFocus();
            for (var i = 0; i < points.length; i++) {
                var px = tempToX(points[i][0]);
                var py = dutyToY(points[i][1]);
                if (Math.abs(mouse.x - px) < 12 && Math.abs(mouse.y - py) < 12) {
                    dragIndex = i;
                    selectedIndex = i;
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
                    selectedIndex = k;
                    break;
                }
            }
            canvas.requestPaint();
        }

        onPositionChanged: function(mouse) {
            if (dragIndex < 0) {
                readout.hoverIndex = -1;
                for (var h = 0; h < points.length; h++) {
                    var hx = tempToX(points[h][0]);
                    var hy = dutyToY(points[h][1]);
                    if (Math.abs(mouse.x - hx) < 12 && Math.abs(mouse.y - hy) < 12) {
                        readout.hoverIndex = h;
                        break;
                    }
                }
                return;
            }
            var newTemp = xToTemp(mouse.x);
            var newDuty = yToDuty(mouse.y);
            var newPoints = points.slice();
            newPoints[dragIndex] = [newTemp, newDuty];
            newPoints.sort(function(a, b) { return a[0] - b[0]; });
            // Find new index after sort
            for (var i = 0; i < newPoints.length; i++) {
                if (newPoints[i][0] === newTemp && newPoints[i][1] === newDuty) {
                    dragIndex = i;
                    selectedIndex = i;
                    break;
                }
            }
            points = newPoints;
            canvas.requestPaint();
        }

        onExited: readout.hoverIndex = -1

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
                    selectedIndex = clamp(selectedIndex, 0, points.length - 1);
                    curveEditor.pointsChanged();
                    canvas.requestPaint();
                    return;
                }
            }
        }
    }

    onPointsChanged: canvas.requestPaint()
    onSelectedIndexChanged: canvas.requestPaint()
    onActiveFocusChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
}
