// Probe 4 for issue #19 — all three colour-capable mechanisms rendering the
// *same* accent, isolated on a black field so stroke profiles can be measured
// numerically rather than eyeballed. Layout is fixed-pitch: each cell is
// 128x128 at row y = 0/128/256, so the PNG can be sliced by arithmetic.
import QtQuick
import QtQuick.Window
import QtQuick.Effects

Window {
    id: win
    visible: true
    width: 640
    height: 420
    color: "#000000"

    readonly property color accent: "#7fb3b8"
    readonly property string root: Qt.resolvedUrl(".").toString().replace("file://", "")
    readonly property string pristine: root + "../../../assets/icons/lucide/"
    readonly property string preWhite: root + "gen/pre-white/"
    readonly property string preBaked: root + "gen/pre-baked/"
    readonly property string icon: "settings"

    function themed(name) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + pristine + name + ".svg", false);
        xhr.send();
        return "data:image/svg+xml;utf8," + encodeURIComponent(xhr.responseText.replace('stroke="currentColor"', 'stroke="' + accent + '"').replace(/stroke-width="[^"]*"/, 'stroke-width="1.5"'));
    }

    Item {
        id: canvas
        width: 640
        height: 420

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    // row 0: G pre-baked teal file   row 1: D data-URI teal   row 2: C pre-white + MultiEffect
    Item {
        x: 0
        y: 0
        width: 128
        height: 128
        Image {
            anchors.centerIn: parent
            width: 96
            height: 96
            source: "file://" + win.preBaked + win.icon + ".svg"
            sourceSize: Qt.size(96, 96)
            smooth: true
        }
    }
    Item {
        x: 0
        y: 128
        width: 128
        height: 128
        Image {
            anchors.centerIn: parent
            width: 96
            height: 96
            source: win.themed(win.icon)
            sourceSize: Qt.size(96, 96)
            smooth: true
        }
    }
    Item {
        x: 0
        y: 256
        width: 128
        height: 128
        Image {
            id: cSrc
            anchors.centerIn: parent
            width: 96
            height: 96
            source: "file://" + win.preWhite + win.icon + ".svg"
            sourceSize: Qt.size(96, 96)
            visible: false
        }
        MultiEffect {
            anchors.fill: cSrc
            source: cSrc
            colorization: 1.0
            colorizationColor: win.accent
        }
    }

    // same three, at 16px bar size, column x = 200
    Item {
        x: 200
        y: 0
        width: 128
        height: 128
        Image {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: "file://" + win.preBaked + win.icon + ".svg"
            sourceSize: Qt.size(16, 16)
            smooth: true
        }
    }
    Item {
        x: 200
        y: 128
        width: 128
        height: 128
        Image {
            anchors.centerIn: parent
            width: 16
            height: 16
            source: win.themed(win.icon)
            sourceSize: Qt.size(16, 16)
            smooth: true
        }
    }
    Item {
        x: 200
        y: 256
        width: 128
        height: 128
        Image {
            id: cSrc16
            anchors.centerIn: parent
            width: 16
            height: 16
            source: "file://" + win.preWhite + win.icon + ".svg"
            sourceSize: Qt.size(16, 16)
            visible: false
        }
        MultiEffect {
            anchors.fill: cSrc16
            source: cSrc16
            colorization: 1.0
            colorizationColor: win.accent
        }
    }

    }

    Timer {
        running: true
        interval: 1500
        onTriggered: canvas.grabToImage(function (r) {
            console.log("saved:", r.saveToFile(win.root + "probe4.png"));
            Qt.exit(0);
        })
    }
}
