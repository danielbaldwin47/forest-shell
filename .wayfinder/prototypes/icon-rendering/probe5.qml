// Probe 5 for issue #19 — what does a MultiEffect per icon actually cost on the
// T480's UHD 620? Renders N icons, animates the accent so every frame is dirty,
// counts frames for 6s. MODE=plain|effect|font, N=<count>.
import QtQuick
import QtQuick.Window
import QtQuick.Effects

Window {
    id: win
    visible: true
    width: 900
    height: 900
    color: "#0d1417"

    readonly property string mode: (Qt.application.arguments.indexOf("--mode") >= 0) ? Qt.application.arguments[Qt.application.arguments.indexOf("--mode") + 1] : "effect"
    readonly property int count: (Qt.application.arguments.indexOf("--count") >= 0) ? parseInt(Qt.application.arguments[Qt.application.arguments.indexOf("--count") + 1]) : 400
    readonly property int sz: 24

    readonly property string root: Qt.resolvedUrl(".").toString().replace("file://", "")
    readonly property string preWhite: root + "gen/pre-white/"
    readonly property string preBaked: root + "gen/pre-baked/"
    readonly property var names: ["settings", "wifi", "cloud-fog", "bell", "sun", "cpu", "search", "volume-2", "battery-medium", "mountain-snow"]

    property color accent: "#7fb3b8"
    property var codepoints: ({})

    FontLoader {
        id: lucideFont
        source: "file:///home/daniel/.claude/jobs/467a8320/tmp/lfont/lucide.ttf"
    }

    // every frame is dirty: the accent cycles continuously
    NumberAnimation on hueShift {
        from: 0
        to: 1
        duration: 3000
        loops: Animation.Infinite
        running: true
    }
    property real hueShift: 0
    onHueShiftChanged: accent = Qt.hsla(0.45 + 0.1 * hueShift, 0.3, 0.6, 1.0)

    Component.onCompleted: {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file:///home/daniel/.claude/jobs/467a8320/tmp/lfont/codepoints.json", false);
        xhr.send();
        codepoints = JSON.parse(xhr.responseText);
        console.log("MODE=" + mode + " COUNT=" + count);
    }

    Grid {
        anchors.fill: parent
        columns: Math.floor(win.width / (win.sz + 4))
        spacing: 4

        Repeater {
            model: win.count
            delegate: Loader {
                required property int index
                readonly property string iconName: win.names[index % win.names.length]
                width: win.sz
                height: win.sz
                sourceComponent: win.mode === "plain" ? plainC : (win.mode === "font" ? fontC : effectC)
            }
        }
    }

    Component {
        id: plainC
        Image {
            source: "file://" + win.preBaked + parent.iconName + ".svg"
            sourceSize: Qt.size(win.sz * 1.5, win.sz * 1.5)
            smooth: true
            // keep the node dirty without a shader, for a fair baseline
            opacity: 0.5 + 0.5 * win.hueShift
        }
    }

    Component {
        id: effectC
        Item {
            Image {
                id: src
                anchors.fill: parent
                source: "file://" + win.preWhite + parent.parent.iconName + ".svg"
                sourceSize: Qt.size(win.sz * 1.5, win.sz * 1.5)
                visible: false
            }
            MultiEffect {
                anchors.fill: parent
                source: src
                colorization: 1.0
                colorizationColor: win.accent
            }
        }
    }

    Component {
        id: fontC
        Text {
            anchors.centerIn: parent
            font.family: lucideFont.name
            font.pixelSize: win.sz
            color: win.accent
            text: {
                var cp = win.codepoints[parent.iconName];
                return cp ? String.fromCharCode(cp) : "?";
            }
        }
    }

    // frame counter
    property int frames: 0
    property double t0: 0
    Connections {
        target: win
        function onFrameSwapped() {
            if (win.t0 === 0)
                win.t0 = Date.now();
            win.frames++;
        }
    }

    Timer {
        running: true
        interval: 6000
        onTriggered: {
            var dt = (Date.now() - win.t0) / 1000;
            console.log("RESULT mode=" + win.mode + " count=" + win.count + " frames=" + win.frames + " secs=" + dt.toFixed(2) + " fps=" + (win.frames / dt).toFixed(1));
            Qt.exit(0);
        }
    }
}
