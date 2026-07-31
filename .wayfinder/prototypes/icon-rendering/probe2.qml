// Probe 2 for issue #19 — stroke weight and small-size crispness.
// Renders only the mechanisms that produce colour, at 96px (weight) and at
// 16px (bar size, to be upscaled nearest-neighbour afterwards).
import QtQuick
import QtQuick.Window
import QtQuick.Effects

Window {
    id: win
    visible: true
    width: 700
    height: 900
    color: "#0d1417"

    readonly property color accent: "#7fb3b8"
    readonly property string root: Qt.resolvedUrl(".").toString().replace("file://", "")
    readonly property string pristine: root + "../../../assets/icons/lucide/"
    readonly property string preWhite: root + "gen/pre-white/"
    readonly property var names: ["settings", "wifi", "cloud-fog"]

    function svgSource(name, stroke, width) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + pristine + name + ".svg", false);
        xhr.send();
        var svg = xhr.responseText.replace('stroke="currentColor"', 'stroke="' + stroke + '"').replace(/stroke-width="[^"]*"/, 'stroke-width="' + width + '"');
        return "data:image/svg+xml;utf8," + encodeURIComponent(svg);
    }

    FontLoader {
        id: lucideFont
        source: "file:///home/daniel/.claude/jobs/467a8320/tmp/lfont/lucide.ttf"
    }
    property var codepoints: ({})
    Component.onCompleted: {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file:///home/daniel/.claude/jobs/467a8320/tmp/lfont/codepoints.json", false);
        xhr.send();
        codepoints = JSON.parse(xhr.responseText);
    }

    // one column per mechanism, one row per size
    component Cell: Item {
        id: cell
        property string mech
        property string icon
        property int sz
        width: sz
        height: sz

        Loader {
            anchors.fill: parent
            sourceComponent: {
                switch (cell.mech) {
                case "B":
                    return cB;
                case "C":
                    return cC;
                case "D":
                    return cD;
                case "F":
                    return cF;
                }
            }
        }

        Component {
            id: cB
            Item {
                Image {
                    id: bi
                    anchors.fill: parent
                    source: "file://" + win.pristine + cell.icon + ".svg"
                    sourceSize: Qt.size(cell.sz, cell.sz)
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: bi
                    brightness: 1.0
                    colorization: 1.0
                    colorizationColor: win.accent
                }
            }
        }
        Component {
            id: cC
            Item {
                Image {
                    id: ci
                    anchors.fill: parent
                    source: "file://" + win.preWhite + cell.icon + ".svg"
                    sourceSize: Qt.size(cell.sz, cell.sz)
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: ci
                    colorization: 1.0
                    colorizationColor: win.accent
                }
            }
        }
        Component {
            id: cD
            Image {
                source: win.svgSource(cell.icon, win.accent, 1.5)
                sourceSize: Qt.size(cell.sz, cell.sz)
                smooth: true
            }
        }
        Component {
            id: cF
            Text {
                anchors.centerIn: parent
                font.family: lucideFont.name
                font.pixelSize: cell.sz
                color: win.accent
                renderType: Text.NativeRendering
                text: {
                    var cp = win.codepoints[cell.icon];
                    return cp ? String.fromCharCode(cp) : "?";
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#0d1417"
    }

    readonly property var mechLabels: ({
            "B": "B  pristine + MultiEffect",
            "C": "C  pre-white 1.5 + MultiEffect",
            "D": "D  runtime-rewritten SVG",
            "F": "F  lucide.ttf icon font"
        })

    Column {
        x: 20
        y: 14
        spacing: 20

        Repeater {
            model: [96, 24, 16]
            delegate: Column {
                id: sizeCol
                required property int modelData
                readonly property int px: modelData
                spacing: 6

                Text {
                    text: "── " + sizeCol.px + "px ──────────────"
                    color: "#8fa7a3"
                    font.pixelSize: 12
                    font.family: "IBM Plex Mono"
                }

                Repeater {
                    model: ["B", "C", "D", "F"]
                    delegate: Row {
                        id: mechRow
                        required property string modelData
                        readonly property string mech: modelData
                        spacing: 12
                        Text {
                            width: 230
                            text: win.mechLabels[mechRow.mech]
                            color: "#6f8380"
                            font.pixelSize: 11
                            font.family: "IBM Plex Mono"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Repeater {
                            model: win.names
                            delegate: Cell {
                                required property string modelData
                                mech: mechRow.mech
                                icon: modelData
                                sz: sizeCol.px
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        running: true
        interval: 1500
        onTriggered: {
            win.contentItem.grabToImage(function (r) {
                console.log("saved:", r.saveToFile(win.root + "probe2.png"));
                Qt.exit(0);
            }, Qt.size(win.width, win.height));
        }
    }
}
