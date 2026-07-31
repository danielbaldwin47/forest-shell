// Throwaway probe for issue #19 — which mechanism puts a themed, 1.5px-stroke
// Lucide icon on screen? Renders every candidate side by side, grabs a PNG,
// prints pixel readings, exits.
//
//   QT_ASSUME_STDERR_HAS_CONSOLE=1 qml6 probe.qml
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.VectorImage

Window {
    id: win
    visible: true
    width: 1180
    height: 620
    color: "#10171a" // forest ink, roughly
    title: "icon-rendering probe"

    readonly property color accent: "#7fb3b8" // glacier teal
    readonly property string root: Qt.resolvedUrl(".").toString().replace("file://", "")
    readonly property string pristine: root + "../../../assets/icons/lucide/"
    readonly property string preWhite: root + "gen/pre-white/"
    readonly property string preBaked: root + "gen/pre-baked/"
    readonly property var names: ["wifi", "battery-medium", "volume-2", "bell", "settings", "search", "sun", "cloud-fog", "mountain-snow", "cpu"]

    // --- runtime SVG rewriting (mechanism D) ------------------------------
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

    // name -> codepoint, loaded from the font release's codepoints.json
    property var codepoints: ({})

    Component.onCompleted: {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file:///home/daniel/.claude/jobs/467a8320/tmp/lfont/codepoints.json", false);
        xhr.send();
        codepoints = JSON.parse(xhr.responseText);
        console.log("font status", lucideFont.status, "name:", lucideFont.name);
        console.log("codepoints loaded:", Object.keys(codepoints).length);
    }

    component Bank: Item {
        id: bank
        property string label
        property Component cell
        height: 84
        width: parent.width

        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: bank.label
            color: "#9fb0ae"
            font.pixelSize: 13
            font.family: "IBM Plex Sans"
            width: 250
            wrapMode: Text.WordWrap
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: "#1b2528"
        }

        Repeater {
            model: win.names
            delegate: Loader {
                required property int index
                required property string modelData
                x: 280 + index * 60
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: bank.cell
                property string iconName: modelData
            }
        }

        // large sample, to judge stroke weight
        Loader {
            x: 280 + 10 * 60 + 24
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: bank.cell
            property string iconName: "settings"
            property int bigSize: 56
        }
    }

    Column {
        anchors.fill: parent

        Bank {
            label: "A. pristine Image (baseline)"
            cell: Item {
                property int sz: parent && parent.bigSize ? parent.bigSize : 24
                width: sz
                height: sz
                Image {
                    anchors.fill: parent
                    source: "file://" + win.pristine + parent.parent.iconName + ".svg"
                    sourceSize: Qt.size(parent.sz * 2, parent.sz * 2)
                    smooth: true
                }
            }
        }

        Bank {
            label: "B. pristine + MultiEffect (brightness 1, colorization 1)"
            cell: Item {
                property int sz: parent && parent.bigSize ? parent.bigSize : 24
                width: sz
                height: sz
                Image {
                    id: bimg
                    anchors.fill: parent
                    source: "file://" + win.pristine + parent.parent.iconName + ".svg"
                    sourceSize: Qt.size(parent.sz * 2, parent.sz * 2)
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: bimg
                    brightness: 1.0
                    colorization: 1.0
                    colorizationColor: win.accent
                }
            }
        }

        Bank {
            label: "C. pre-white 1.5 + MultiEffect (colorization only)"
            cell: Item {
                property int sz: parent && parent.bigSize ? parent.bigSize : 24
                width: sz
                height: sz
                Image {
                    id: cimg
                    anchors.fill: parent
                    source: "file://" + win.preWhite + parent.parent.iconName + ".svg"
                    sourceSize: Qt.size(parent.sz * 2, parent.sz * 2)
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: cimg
                    colorization: 1.0
                    colorizationColor: win.accent
                }
            }
        }

        Bank {
            label: "D. runtime-rewritten SVG via data: URI"
            cell: Item {
                property int sz: parent && parent.bigSize ? parent.bigSize : 24
                width: sz
                height: sz
                Image {
                    anchors.fill: parent
                    source: win.svgSource(parent.parent.iconName, win.accent, 1.5)
                    sourceSize: Qt.size(parent.sz * 2, parent.sz * 2)
                    smooth: true
                }
            }
        }

        Bank {
            label: "E. VectorImage (pristine, currentColor)"
            cell: Item {
                property int sz: parent && parent.bigSize ? parent.bigSize : 24
                width: sz
                height: sz
                VectorImage {
                    anchors.fill: parent
                    source: "file://" + win.pristine + parent.parent.iconName + ".svg"
                    preferredRendererType: VectorImage.CurveRenderer
                    fillMode: VectorImage.Stretch
                }
            }
        }

        Bank {
            label: "F. Text + lucide.ttf (Text.color)"
            cell: Item {
                property int sz: parent && parent.bigSize ? parent.bigSize : 24
                width: sz
                height: sz
                Text {
                    anchors.centerIn: parent
                    font.family: lucideFont.name
                    font.pixelSize: parent.sz
                    color: win.accent
                    text: {
                        var cp = win.codepoints[parent.parent.iconName];
                        return cp ? String.fromCharCode(cp) : "?";
                    }
                }
            }
        }

        Bank {
            label: "G. pre-baked colour 1.5 (plain Image)"
            cell: Item {
                property int sz: parent && parent.bigSize ? parent.bigSize : 24
                width: sz
                height: sz
                Image {
                    anchors.fill: parent
                    source: "file://" + win.preBaked + parent.parent.iconName + ".svg"
                    sourceSize: Qt.size(parent.sz * 2, parent.sz * 2)
                    smooth: true
                }
            }
        }
    }

    Timer {
        running: true
        interval: 1500
        onTriggered: {
            win.contentItem.grabToImage(function (result) {
                var ok = result.saveToFile(win.root + "probe.png");
                console.log("grab saved:", ok, win.root + "probe.png");
                Qt.exit(0);
            });
        }
    }
}
