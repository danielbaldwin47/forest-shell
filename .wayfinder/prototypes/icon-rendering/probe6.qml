// Probe 6 for issue #19 — at a fractional scale (this T480 runs 1.5), does
// sourceSize need the devicePixelRatio applied by hand? Same 16px icon, three
// raster sizes, measured off the grab.
import QtQuick
import QtQuick.Window
import QtQuick.Effects

Window {
    id: win
    visible: true
    width: 400
    height: 200
    color: "#000000"

    readonly property color accent: "#7fb3b8"
    readonly property string root: Qt.resolvedUrl(".").toString().replace("file://", "")
    readonly property string preWhite: root + "gen/pre-white/"

    Item {
        id: canvas
        width: 400
        height: 200

        Rectangle {
            anchors.fill: parent
            color: "#000000"
        }

        Repeater {
            model: [16, 24, 32, 48]
            delegate: Item {
                id: cell
                required property int index
                required property int modelData
                x: index * 64
                y: 0
                width: 64
                height: 64

                Image {
                    id: src
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    source: "file://" + win.preWhite + "settings.svg"
                    sourceSize: Qt.size(cell.modelData, cell.modelData)
                    visible: false
                }
                MultiEffect {
                    anchors.fill: src
                    source: src
                    colorization: 1.0
                    colorizationColor: win.accent
                }
            }
        }

        Component.onCompleted: console.log("dpr", Screen.devicePixelRatio)
    }

    Timer {
        running: true
        interval: 1200
        onTriggered: canvas.grabToImage(function (r) {
            console.log("saved:", r.saveToFile(win.root + "probe6.png"));
            Qt.exit(0);
        })
    }
}
