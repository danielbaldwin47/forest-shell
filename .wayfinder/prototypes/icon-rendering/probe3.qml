// Probe 3 for issue #19 — why does the runtime-rewritten data: URI render soft?
// Four spellings of the same idea, plus the on-disk control.
import QtQuick
import QtQuick.Window

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

    function raw(name) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file://" + pristine + name + ".svg", false);
        xhr.send();
        return xhr.responseText;
    }

    function themed(name, px, setSize) {
        var svg = raw(name).replace('stroke="currentColor"', 'stroke="' + accent + '"').replace(/stroke-width="[^"]*"/, 'stroke-width="1.5"');
        if (setSize)
            svg = svg.replace('width="24"', 'width="' + px + '"').replace('height="24"', 'height="' + px + '"');
        return svg;
    }

    component Cell: Item {
        id: cell
        property string variant
        property string icon
        property int sz
        width: sz
        height: sz

        Image {
            anchors.fill: parent
            smooth: true
            source: {
                switch (cell.variant) {
                case "D1":
                    // utf8 data URI, sourceSize set (what probe2 used)
                    return "data:image/svg+xml;utf8," + encodeURIComponent(win.themed(cell.icon, cell.sz, false));
                case "D2":
                    // width/height rewritten to target px, no sourceSize
                    return "data:image/svg+xml;utf8," + encodeURIComponent(win.themed(cell.icon, cell.sz, true));
                case "D3":
                    // base64 data URI, sourceSize set
                    return "data:image/svg+xml;base64," + Qt.btoa(win.themed(cell.icon, cell.sz, false));
                case "D4":
                    // control: preprocessed file on disk, sourceSize set
                    return "file://" + win.preWhite + cell.icon + ".svg";
                }
            }
            sourceSize: cell.variant === "D2" ? undefined : Qt.size(cell.sz, cell.sz)
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#0d1417"
    }

    readonly property var labels: ({
            "D1": "D1  data:utf8 + sourceSize",
            "D2": "D2  data:utf8, size in SVG",
            "D3": "D3  data:base64 + sourceSize",
            "D4": "D4  file on disk (control)"
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
                    model: ["D1", "D2", "D3", "D4"]
                    delegate: Row {
                        id: vRow
                        required property string modelData
                        readonly property string v: modelData
                        spacing: 12
                        Text {
                            width: 230
                            text: win.labels[vRow.v]
                            color: "#6f8380"
                            font.pixelSize: 11
                            font.family: "IBM Plex Mono"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Repeater {
                            model: win.names
                            delegate: Cell {
                                required property string modelData
                                variant: vRow.v
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
        onTriggered: win.contentItem.grabToImage(function (r) {
            console.log("saved:", r.saveToFile(win.root + "probe3.png"));
            Qt.exit(0);
        }, Qt.size(win.width, win.height))
    }
}
