// Demo for issue #19 — the Icon seam driving a mock bar, with the accent
// swapped live to show that colour stays dynamic after the 1.5 stroke is baked.
import QtQuick
import QtQuick.Window

Window {
    id: win
    visible: true
    width: 900
    height: 260
    color: "#0d1417"

    // stand-ins for the design-system tokens (#8)
    readonly property color bg: "#111a1c"
    readonly property color fg: "#dce7e3"
    readonly property color fgMuted: "#8fa7a3"
    readonly property var accents: ["#7fb3b8", "#d9a14b", "#8fbf8a", "#b98ec4"]
    property int accentIndex: 0
    readonly property color accent: accents[accentIndex]

    Timer {
        running: true
        interval: 1200
        repeat: true
        onTriggered: win.accentIndex = (win.accentIndex + 1) % win.accents.length
    }

    Item {
        id: canvas
        width: 900
        height: 260

        Rectangle {
            anchors.fill: parent
            color: "#0d1417"
        }

        // --- mock bar -----------------------------------------------------
        Rectangle {
            id: bar
            x: 20
            y: 24
            width: 860
            height: 34
            radius: 10
            color: win.bg

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Icon {
                    name: "mountain-snow"
                    size: 16
                    color: win.accent
                }
                Icon {
                    name: "search"
                    size: 16
                    color: win.fgMuted
                }
                Icon {
                    name: "calendar"
                    size: 16
                    color: win.fgMuted
                }
            }

            Text {
                anchors.centerIn: parent
                text: "09:41"
                color: win.fg
                font.family: "Newsreader"
                font.weight: 300
                font.pixelSize: 18
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Icon {
                    name: "cloud-fog"
                    size: 16
                    color: win.fgMuted
                }
                Icon {
                    name: "bluetooth"
                    size: 16
                    color: win.fgMuted
                }
                Icon {
                    name: "wifi"
                    size: 16
                    color: win.accent
                }
                Icon {
                    name: "volume-2"
                    size: 16
                    color: win.fgMuted
                }
                Icon {
                    name: "battery-medium"
                    size: 16
                    color: win.fgMuted
                }
                Icon {
                    name: "settings"
                    size: 16
                    color: win.fgMuted
                }
            }
        }

        // --- size ramp ----------------------------------------------------
        Row {
            x: 20
            y: 90
            spacing: 20
            Repeater {
                model: [16, 20, 24, 32, 48, 64]
                delegate: Column {
                    required property int modelData
                    spacing: 6
                    Icon {
                        name: "settings"
                        size: parent.modelData
                        color: win.accent
                    }
                    Text {
                        text: parent.modelData + "px"
                        color: "#5d716e"
                        font.pixelSize: 9
                        font.family: "IBM Plex Mono"
                    }
                }
            }
        }

        // --- a bad name, to show the affordance ---------------------------
        Row {
            x: 20
            y: 190
            spacing: 10
            Icon {
                name: "definitely-not-an-icon"
                size: 16
                color: "#c46b6b"
            }
            Text {
                text: 'Icon { name: "definitely-not-an-icon" } — hollow box, warning on stderr'
                color: "#5d716e"
                font.pixelSize: 11
                font.family: "IBM Plex Mono"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // grab three frames across the accent cycle, then quit
    property int shots: 0
    Timer {
        running: true
        interval: 1300
        repeat: true
        onTriggered: {
            canvas.grabToImage(function (r) {
                r.saveToFile(Qt.resolvedUrl(".").toString().replace("file://", "") + "demo-" + win.shots + ".png");
                win.shots++;
                if (win.shots >= 3)
                    Qt.exit(0);
            });
        }
    }
}
