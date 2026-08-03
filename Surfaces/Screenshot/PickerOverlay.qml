// What the region picker looks like (#51) — the frozen screen, the veil over
// the part you are not taking, and the rectangle you are.
//
// Split from PickerWindow.qml so that seam 3 can render it (CLAUDE.md):
// `tools/capture-harness.sh --surface screenshot` poses this component with a
// generated wallpaper standing in for the freeze and a hand-written window
// list, and grabs it offscreen. Everything here is `Image`, `Rectangle` and
// `Text` for exactly that reason — no `MultiEffect` and no Lucide glyph, both
// of which draw nothing on the offscreen scenegraph, so what the harness
// captures is what the screen shows.
//
// ## The veil is four rectangles, not a mask
//
// Qt has no cheap "punch a hole in this" primitive, and the shader that would
// do it is the one thing seam 3 cannot see. Four panels around the selection
// is the same picture, costs four batched quads, and has the useful property
// that with no selection the whole screen is one panel.
import QtQuick
import qs.Core

Item {
    id: root

    /// The frozen screen, as a URL. Empty draws nothing rather than drawing
    /// black: an empty picker over a live desktop is at least honest about
    /// having no freeze, and the window never comes up in that state.
    property string freezeSource: ""

    /// Window rectangles to snap to, in the same logical coordinates as this
    /// item. Only the hovered one is drawn — outlining all of them turns the
    /// screen into a wireframe and makes the selection harder to see, which is
    /// the opposite of the help.
    property var windows: []

    /// The committed selection, and whether a drag is in flight. A zero-size
    /// selection means "nothing chosen yet", which is the veil-everything case.
    property rect selection: Qt.rect(0, 0, 0, 0)
    property bool dragging: false

    /// The window under the pointer, or null. This is what a click would take,
    /// and drawing it is the whole of "window snapping highlights window rects".
    property var hovered: null

    /// The output's scale, for the readout — the numbers a person wants are the
    /// pixels they will get, not the logical ones they drew.
    property real outputScale: 1

    readonly property bool hasSelection: root.selection.width > 0 && root.selection.height > 0

    // --- the frozen screen ---------------------------------------------------

    Image {
        id: frozen
        anchors.fill: parent
        source: root.freezeSource
        // The freeze is the whole output at native resolution and this item is
        // the same output in logical pixels, so it is a pure downscale to fit —
        // never a crop, never letterboxed.
        fillMode: Image.Stretch
        smooth: true
        // Decoded at full size on purpose: the crop is grabbed from this same
        // pixmap, and a `sourceSize` bound to the logical width would throw the
        // resolution away before the grab ever ran.
        cache: false
        asynchronous: false
    }

    // --- the veil ------------------------------------------------------------

    // Nothing selected: one panel over everything. Something selected: four
    // around it. Both are the same statement — "this is not what you are
    // taking" — so they share an opacity and a colour.
    readonly property color veilColour: Qt.rgba(0, 0, 0, 1)
    readonly property real veilOpacity: 0.45

    Rectangle {
        anchors.fill: parent
        visible: !root.hasSelection
        color: root.veilColour
        opacity: root.veilOpacity
    }

    Item {
        anchors.fill: parent
        visible: root.hasSelection

        Rectangle {   // above
            x: 0; y: 0
            width: parent.width
            height: Math.max(0, root.selection.y)
            color: root.veilColour; opacity: root.veilOpacity
        }
        Rectangle {   // below
            x: 0
            y: root.selection.y + root.selection.height
            width: parent.width
            height: Math.max(0, parent.height - y)
            color: root.veilColour; opacity: root.veilOpacity
        }
        Rectangle {   // left
            x: 0
            y: root.selection.y
            width: Math.max(0, root.selection.x)
            height: root.selection.height
            color: root.veilColour; opacity: root.veilOpacity
        }
        Rectangle {   // right
            x: root.selection.x + root.selection.width
            y: root.selection.y
            width: Math.max(0, parent.width - x)
            height: root.selection.height
            color: root.veilColour; opacity: root.veilOpacity
        }
    }

    // --- the window under the pointer ----------------------------------------

    // Drawn under the selection border, so that a drag started inside a window
    // does not fight the highlight it started from.
    Rectangle {
        visible: !!root.hovered && !root.hasSelection
        x: root.hovered ? root.hovered.x : 0
        y: root.hovered ? root.hovered.y : 0
        width: root.hovered ? root.hovered.width : 0
        height: root.hovered ? root.hovered.height : 0

        color: "transparent"
        border.width: Theme.rail
        border.color: Theme.accentPrimary
        radius: Theme.radiusSm

        // A wash rather than an outline alone: an outline on a busy screenshot
        // is easy to lose, and the wash is what makes "click takes this window"
        // legible at a glance.
        Rectangle {
            anchors.fill: parent
            anchors.margins: Theme.rail
            color: Theme.accentPrimary
            opacity: 0.12
            radius: Theme.radiusSm
        }
    }

    // --- the selection -------------------------------------------------------

    Rectangle {
        id: marquee
        visible: root.hasSelection
        x: root.selection.x
        y: root.selection.y
        width: root.selection.width
        height: root.selection.height

        color: "transparent"
        border.width: Theme.hairline
        border.color: Theme.accentPrimary
    }

    // The four corner ticks. They are what tells a still screenshot of the
    // picker apart from a window that merely has a border, and they are the
    // affordance for "this rectangle is the thing".
    Repeater {
        model: root.hasSelection ? 4 : 0

        Rectangle {
            required property int index

            readonly property bool atRight: index === 1 || index === 3
            readonly property bool atBottom: index >= 2
            readonly property int arm: 14

            width: arm
            height: Theme.rail
            color: Theme.accentPrimary
            x: atRight ? root.selection.x + root.selection.width - arm : root.selection.x
            y: atBottom ? root.selection.y + root.selection.height - Theme.rail : root.selection.y

            Rectangle {
                width: Theme.rail
                height: parent.arm
                color: Theme.accentPrimary
                x: parent.atRight ? parent.arm - Theme.rail : 0
                y: parent.atBottom ? -(parent.arm - Theme.rail) : 0
            }
        }
    }

    // --- the readout ---------------------------------------------------------

    // The pixel count, in the pixels the file will have. Placed outside the
    // selection when there is room above it and inside when there is not, so it
    // never covers the top edge of what is being taken.
    Rectangle {
        id: readout

        readonly property int gap: Theme.space2
        readonly property bool above: root.selection.y - height - gap >= 0

        visible: root.hasSelection
        x: Math.min(Math.max(0, root.selection.x),
                    Math.max(0, root.width - width))
        y: above ? root.selection.y - height - gap
                 : root.selection.y + gap

        width: label.implicitWidth + Theme.space3 * 2
        height: label.implicitHeight + Theme.space2 * 2
        radius: Theme.radiusSm
        color: Theme.surfaceOverlay
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        Text {
            id: label
            anchors.centerIn: parent
            color: Theme.textPrimary
            font.family: Theme.fontMono
            font.pointSize: Theme.capsSize * 72 / 96
            // Native pixels, not logical: the number a person checks a
            // screenshot against is the one in the file's properties.
            text: Math.round(root.selection.width * root.outputScale)
                  + " × " + Math.round(root.selection.height * root.outputScale)
        }
    }

    // --- the instruction -----------------------------------------------------

    // Only before the first drag. Once there is a selection it is in the way,
    // and by then the gesture has explained itself.
    Rectangle {
        visible: !root.hasSelection
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.space9

        width: hint.implicitWidth + Theme.space5 * 2
        height: hint.implicitHeight + Theme.space3 * 2
        radius: Theme.radiusFull
        color: Theme.surfaceOverlay
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        Text {
            id: hint
            anchors.centerIn: parent
            color: Theme.textSecondary
            font.family: Theme.fontUi
            font.pointSize: 12.5 * 72 / 96
            font.weight: Theme.weightText
            text: root.hovered
                  ? "Click to take " + root.hovered.title + "  ·  drag for a region  ·  Esc to cancel"
                  : "Drag to select a region  ·  click a window to take it  ·  Esc to cancel"
        }
    }
}
