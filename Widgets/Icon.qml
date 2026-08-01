// The one component the rest of the shell calls to put a Lucide glyph on
// screen (#19, #34).
//
//     Icon { name: "wifi"; size: 16; color: Theme.textSecondary }
//
// Icons are addressed by **name** — the Lucide file stem — never by path, so
// callers never learn where the set lives, that it was normalized, or how it is
// recoloured. Swapping the rendering mechanism later is a change to this file
// alone.
//
// Dumb by contract, like everything in Widgets/: no Services, no Config, no
// Theme. `color` is a plain property and the caller passes the token.
//
// How it renders, and why (all measured in `.wayfinder/prototypes/icon-rendering`):
//
//   - The vendored set is normalized in place — `stroke-width` 1.5, and
//     `stroke`/`fill` `currentColor` baked to white. Qt's SVG renderer does not
//     resolve `currentColor`; it draws opaque black, and an `Image` has no
//     colour property to override that with.
//   - White plus `MultiEffect { colorization: 1.0 }` is **pixel-identical** to a
//     file with the colour baked in, so the dynamic path costs nothing in
//     fidelity — and `color` stays live, which the opt-in dynamic accent (#6)
//     needs. Rewriting the SVG at runtime into a `data:` URI is measurably
//     soft, because Qt ignores `sourceSize` on a `data:` URI and rasterizes at
//     the intrinsic 24×24.
//   - `MultiEffect` needs a real GPU context: under `QT_QPA_PLATFORM=offscreen`
//     it draws nothing at all, silently. A headless screenshot check of an icon
//     would "pass" with the icon missing, which is why the gallery
//     (`gallery.qml`) is run on a real session instead.
import QtQuick
import QtQuick.Effects

Item {
    id: root

    /// Lucide icon name, e.g. "wifi" — the file stem of the vendored set. The
    /// filenames *are* the names; there is no manifest to keep in step.
    property string name

    /// Rendered colour, live — no reload. Defaults to the normalized source's
    /// own white, i.e. no tint, so an un-themed Icon is visible rather than
    /// invisible. Real call sites pass a Theme role.
    property color color: "white"

    /// Logical edge length in px. The icon is always square.
    property int size: 16

    /// The SVG is rasterized at `size * oversample` and downsampled by the GPU.
    /// 1× is visibly mushy at bar sizes; 3× measured tightest. Deliberately
    /// **not** derived from `Screen.devicePixelRatio`, which reports 2 on a
    /// 1.5-scale display — it lies on exactly the machine we calibrate to.
    property real oversample: 3.0

    /// Root of the normalized icon set — the one thing in the shell that knows
    /// where the icons live. Readonly, because there is exactly one set: it is
    /// normalized in place, so there is no second directory and no
    /// generate-before-run step for a caller to point at.
    readonly property url setRoot: Qt.resolvedUrl("../assets/icons/lucide/")

    /// True once the named icon has actually loaded — false for a typo'd name.
    readonly property bool valid: src.status === Image.Ready

    /// A name that did not resolve. Distinct from `!valid`, which is also true
    /// while an icon is still loading and when no name is set at all.
    readonly property bool missing: src.status === Image.Error

    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        id: src
        anchors.fill: parent
        source: root.name ? root.setRoot + root.name + ".svg" : ""
        sourceSize: Qt.size(root.size * root.oversample, root.size * root.oversample)
        fillMode: Image.PreserveAspectFit
        cache: true
        visible: false   // the MultiEffect below is what gets drawn
        // Tests `status` and not `root.missing`: inside the handler the binding
        // that derives `missing` has not necessarily been re-evaluated yet, and
        // a warning that only sometimes fires is worse than none.
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

    // Missing-name affordance: a hollow box — obvious in dev, quiet in shape,
    // and it keeps the layout honest. Rendering nothing would hide the typo.
    Rectangle {
        anchors.fill: parent
        visible: root.missing
        color: "transparent"
        border.color: root.color
        border.width: 1
        radius: 2
        opacity: 0.5
    }
}
