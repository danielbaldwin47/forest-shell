// The sound detail view (#45): which output the machine is playing through, and
// one slider per application playing into it.
//
// Two lists in one panel because they answer the same question from two ends —
// "why can I not hear this" is either the wrong output or one application turned
// down, and a panel that held only one of the two would send the user to the
// settings window for the other.
//
// ## The mixer is the one list with a live control in every row
//
// Which makes it the sharpest case of #75 in the shell: a rebuilt delegate is a
// slider that loses the drag currently moving it. `Services/Media/Audio.qml`
// republishes only when the *set* of streams changes, and each row's slider is
// bound through the live PipeWire node — so a volume moving, whether from this
// panel or from the application's own controls, moves the handle without
// rebuilding anything.
//
// The other trap is one scale up from the one Services/Media/Audio.qml's header
// names: **a PipeWire node's properties are empty until something tracks it.**
// The facade's `PwObjectTracker` holds every sink and stream for exactly this
// panel, because a mixer built on the default sink alone draws every
// application at silence while they play.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Core
import qs.Widgets
import qs.Services.Media
import qs.Surfaces.Drawers

DrillInPanel {
    id: panel

    name: "audio"

    note: !Audio.ready ? "PipeWire is not answering."
        : Audio.sinks.length === 0 ? "No outputs." : ""

    onBackRequested: ControlCenterActions.back("back")

    SectionLabel {
        text: "Output"
    }

    Repeater {
        model: Audio.sinks

        DrillInRow {
            id: sinkRow

            required property var modelData

            glyph: sinkRow.modelData.isDefault ? "volume-2" : "speaker"
            label: sinkRow.modelData.name
            active: sinkRow.modelData.isDefault

            onActivated: ControlCenterActions.output(sinkRow.modelData.id)

            // The tick, and only on the one that is current: a row per output
            // with a radio button on each is five controls where there is one
            // choice.
            Icon {
                visible: sinkRow.modelData.isDefault
                name: "check"
                size: 14
                color: Theme.accentPrimary
            }
        }
    }

    SectionLabel {
        text: "Applications"
        // Absent rather than a heading over nothing: silence is the normal
        // state of a machine, and "Applications / (nothing)" is a heading that
        // spent a line saying so.
        visible: Audio.streams.length > 0
    }

    Repeater {
        model: Audio.streams

        DrillInRow {
            id: streamRow

            required property var modelData

            readonly property var node: streamRow.modelData.live
            readonly property bool muted: streamRow.node && streamRow.node.audio
                                          ? streamRow.node.audio.muted : false

            glyph: streamRow.muted ? "volume-x" : streamRow.modelData.icon
            label: streamRow.modelData.name
            detail: streamRow.modelData.subtitle

            // The row's own press is the mute, which is the gesture a per-app
            // mixer is opened for most often — "shut this one up". The level is
            // the slider on the right.
            onActivated: ControlCenterActions.muteStream(streamRow.modelData.id)

            StreamSlider {
                id: level

                width: 96
                // Bound through the live node, so a volume changed by the
                // application itself moves this handle without the list being
                // republished.
                percent: streamRow.node && streamRow.node.audio
                         ? Audio.policy.percent(streamRow.node.audio.volume) : 0
                dimmed: streamRow.muted

                onMoved: value => ControlCenterActions.stream(streamRow.modelData.id, value)
            }
        }
    }

    // A heading over a list. Local to this file because this is the only panel
    // with two lists in it — the other four are one list and their title bar is
    // their heading.
    component SectionLabel: Text {
        width: parent ? parent.width : 0
        topPadding: Theme.space2
        // Lined up with the *text* of the rows under it, not with the card's
        // edge: a heading that starts left of everything it heads reads as
        // belonging to the panel rather than to the list (measured offscreen —
        // the first capture had it hanging off the left of the rows).
        leftPadding: Theme.space2
        color: Theme.textMuted
        font.family: Theme.fontUi
        font.pointSize: Theme.pt(10)
        font.weight: Theme.weightMedium
    }

    // A bare track. Not Surfaces/Drawers/ControlSlider.qml, which is the panel's
    // full-width control with an icon, a label and a readout — twelve of those
    // stacked would be a mixer taller than the screen. This is the same drag
    // arithmetic with none of the furniture.
    component StreamSlider: Item {
        id: slider

        property int percent: 0
        property bool dimmed: false

        signal moved(int value)

        implicitHeight: 20

        function valueAt(x: real): int {
            return Audio.policy.percent(Math.max(0, Math.min(1, x / slider.width)));
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: height / 2
            color: Theme.surfaceOverlay

            Rectangle {
                width: parent.width * slider.percent / 100
                height: parent.height
                radius: parent.radius
                color: slider.dimmed ? Theme.textMuted : Theme.accentPrimary
            }
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        // Both handlers, because a mixer is used both ways: a tap to put one
        // application at roughly half, a drag to find the level under a track
        // that is already playing.
        TapHandler {
            onTapped: point => slider.moved(slider.valueAt(point.position.x))
        }

        DragHandler {
            target: null
            onActiveTranslationChanged: slider.moved(slider.valueAt(centroid.position.x))
        }
    }
}
