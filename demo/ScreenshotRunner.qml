import QtQuick
import org.kde.kirigami as Kirigami

import "js/Api.js" as Api  // resolved in the staged package copy

/**
 * Landing-page screenshots, only against the demo backend: once the service is online
 * the runner asks it for a plan at /__shots (only demo/backend.py serves one, the real
 * framework-control answers 404 and nothing happens). Plan:
 *   { "dir": "/out", "shots": [ { "name": "sensors", "tab": 0 } ] }
 * Each tab of the popup is grabbed into dir/name.png, then the viewer quits
 * ("FRAMEWIDGE_SCREENSHOT_DONE" in the log). Plasma draws the popup frame outside the grabbed
 * item, and the offscreen grab has no alpha (the gaps come out black), so while a plan runs a
 * rectangle in the colour scheme's window colour stands in for that frame.
 *
 * Internal only: this file is not part of the widget package. demo/common.sh copies it into
 * the staged package copy and adds it to main.qml there.
 */
Item {
    id: runner

    property var plasmoidRoot: null
    property var plan: null
    property var queue: []
    property int shotCount: 0
    property bool asked: false
    readonly property bool active: plan !== null

    function trace(msg) {
        console.warn(msg)
    }

    function ask() {
        if (asked) {
            return
        }
        asked = true
        Api.get(plasmoidRoot.baseUrl + "/__shots", function(ok, data) {
            if (ok && data && data.dir && data.shots) {
                runner.plan = data
                trace("FRAMEWIDGE_SCREENSHOT_START " + data.dir)
                var q = [{ act: "expand" }]
                for (var i = 0; i < data.shots.length; ++i) {
                    q.push({ act: "tab", value: data.shots[i].tab || 0 })
                    q.push({ act: "shot", name: data.shots[i].name })
                }
                q.push({ act: "done" })
                runner.queue = q
                runner.step()
            }
        })
    }

    function step() {
        if (queue.length === 0) {
            return
        }
        var item = queue[0]
        queue = queue.slice(1)
        var wait = 300
        switch (item.act) {
        case "expand":
            plasmoidRoot.expanded = true
            wait = 4000
            break
        case "tab":
            plasmoidRoot.fullRepresentationItem.currentTab = item.value
            wait = 2500
            break
        case "shot": {
            // The popup's container (same size as the popup) holds the frame stand-in below it.
            var target = plasmoidRoot.fullRepresentationItem.parent
            trace("FRAMEWIDGE_SCREENSHOT " + item.name + " " + Math.round(target.width) + "x" + Math.round(target.height))
            var ok = target.grabToImage(function(result) {
                result.saveToFile(runner.plan.dir + "/" + item.name + ".png")
                runner.shotCount += 1
                ticker.restart()
            })
            if (!ok) {
                trace("FRAMEWIDGE_SCREENSHOT_FAILED " + item.name)
                ticker.restart()
            }
            return
        }
        case "done":
            trace("FRAMEWIDGE_SCREENSHOT_DONE " + shotCount)
            Qt.quit()
            return
        }
        ticker.interval = wait
        ticker.restart()
    }

    Timer {
        id: ticker
        repeat: false
        onTriggered: runner.step()
    }

    // Stand-in for Plasma's popup frame, in the window colour (not the widget's own colour set).
    // A sibling behind the popup: inside it, the ColumnLayout would lay it out as a row.
    Rectangle {
        parent: runner.active && runner.plasmoidRoot ? runner.plasmoidRoot.fullRepresentationItem.parent : null
        anchors.fill: parent
        z: -100
        visible: runner.active
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        color: Kirigami.Theme.backgroundColor
    }

    Connections {
        target: runner.plasmoidRoot
        function onServiceOnlineChanged() {
            if (runner.plasmoidRoot.serviceOnline) {
                runner.ask()
            }
        }
    }

}
