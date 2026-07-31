// The proposed seam for issue #19 — the one component the rest of the shell
// calls to put a Lucide glyph on screen.
//
//     Icon { name: "wifi"; size: 16; color: Theme.fgMuted }
//
// Icons are addressed by *name* (the Lucide file stem), never by path: callers
// never learn where the set lives or that it was normalized. Swapping the
// rendering mechanism later is a change to this file alone.
import QtQuick
import QtQuick.Effects

Item {
    id: root

    /// Lucide icon name, e.g. "wifi" — the file stem of the vendored set.
    property string name

    /// Rendered colour. Any token; changes are live, no reload.
    property color color: "#e6efec"

    /// Logical edge length in px. The icon is always square.
    property int size: 16

    /// SVG is rasterized at size * oversample and downsampled by the GPU.
    /// 1x is visibly mushy at bar sizes on a fractional-scale display; 3x is
    /// the measured sweet spot (see findings.md). Deliberately NOT derived
    /// from Screen.devicePixelRatio, which reports 2 on a 1.5-scale display.
    property real oversample: 3.0

    /// Root of the normalized icon set. In the shipping shell this is
    /// `assets/icons/lucide/` — the vendored set is normalized in place, so
    /// there is no second directory and no generate-before-run step. The
    /// prototype points at its own `gen/` output instead.
    property url setRoot: Qt.resolvedUrl("gen/normalized/")

    /// True once the named icon has actually loaded — false for a typo'd name.
    readonly property bool valid: src.status === Image.Ready

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        id: src
        anchors.fill: parent
        // Normalized set: stroke-width 1.5, stroke/fill #ffffff.
        source: root.name ? root.setRoot + root.name + ".svg" : ""
        sourceSize: Qt.size(root.size * root.oversample, root.size * root.oversample)
        fillMode: Image.PreserveAspectFit
        cache: true
        visible: false
        onStatusChanged: if (status === Image.Error)
            console.warn("Icon: no such lucide icon:", root.name)
    }

    MultiEffect {
        anchors.fill: parent
        source: src
        colorization: 1.0
        colorizationColor: root.color
        visible: root.valid
    }

    // Missing-name affordance: a hollow box, obvious in dev, quiet in shape.
    Rectangle {
        anchors.fill: parent
        visible: src.status === Image.Error
        color: "transparent"
        border.color: root.color
        border.width: 1
        radius: 2
        opacity: 0.5
    }
}
