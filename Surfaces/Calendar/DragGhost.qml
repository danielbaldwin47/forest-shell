// The chip that does not exist yet, or the one that has not landed yet.
//
// A drag has to answer one question continuously — *what will I get if I let
// go now* — and the only honest answer is a box the size and shape of the
// event, at the minute it would take, carrying the range it would run. That is
// this file, and it is deliberately the only thing on screen that says so: a
// tooltip beside the pointer would put the number somewhere the box is not, and
// the person is looking at the box.
//
// ## Why it is not an `EventChip`
//
// A chip is a *record*: it reads a title, a guest list, a duration, and it
// decides what fits with `EventLayoutPolicy.chipContent`. A ghost has none of
// that — during a create there is no event at all, and during a move the
// content is beside the point because the thing that changed is the time. So
// the ghost prints the range and, when it has the height for it, one word about
// what will happen. Reusing the chip here would mean teaching the chip about a
// record that does not exist.
//
// ## What it decides: nothing
//
// Position, size and label are the caller's, straight off
// `DragPolicy.proposal` and `CalendarFormat.timeRange`. What is here is the
// look: the hue's own fill so a moved chip keeps its colour under the finger, a
// hard 2px edge in that hue so the ghost reads as a *proposal* rather than as a
// second event, and the range on a plate so it survives whatever chip it is
// dragged over.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: ghost

    /// `create`, `move`, `resizeTop` or `resizeBottom` — the label under the
    /// range says which, when there is room for it.
    property string mode: "create"

    /// The hue index: a create ghost borrows the accent, a move ghost keeps the
    /// event's own colour so it does not change identity while it travels.
    property int hue: 0

    /// `CalendarFormat.timeRange` for the proposal, and the duration beside it.
    property string rangeLabel: ""
    property string durationLabel: ""

    /// A move drags a real chip, so its title is worth carrying; a create has
    /// none yet and says what it is instead.
    property string title: ""

    readonly property bool creating: ghost.mode === "create"

    /// Two lines need about 34px of box. Under that the range alone wins — it
    /// is the number the drag exists to choose.
    readonly property bool roomy: ghost.height >= 34

    /// And the line *under* the range needs the range's second line's worth on
    /// top of that, or a wrapped range and a title would run out of the plate.
    readonly property bool tall: ghost.height >= 56

    /// The lift: `0.92` and `1.02`, both the spec's, and both guarded by
    /// `Theme.animateTransforms` so `appearance.reducedEffects` drops the
    /// transform rather than the ghost.
    opacity: 0.92
    scale: Theme.animateTransforms ? 1.02 : 1

    /// The elevation, two flat plates — see `CalendarTokens.shadowKey` for why
    /// it is not a blur.
    Rectangle {
        anchors.fill: plate
        anchors.margins: -6
        radius: Theme.radiusSm + 6
        color: CalendarTokens.shadowAmbient
    }

    Rectangle {
        anchors.fill: plate
        anchors.margins: -1
        anchors.bottomMargin: -3
        radius: Theme.radiusSm + 1
        color: CalendarTokens.shadowKey
    }

    Rectangle {
        id: plate

        anchors.fill: parent
        radius: Theme.radiusSm
        clip: true
        color: Qt.alpha(CalendarTokens.fill(ghost.hue), 0.94)
        border.width: Theme.rail
        border.color: CalendarTokens.bar(ghost.hue)

        /// The accent bar, exactly where the chip's own is, so the ghost lands
        /// on the grid as the same object rather than as a differently drawn
        /// one.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: CalendarTokens.chipBar
            color: CalendarTokens.bar(ghost.hue)
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: CalendarTokens.chipBar + Theme.space2
            anchors.rightMargin: Theme.space2
            anchors.topMargin: ghost.roomy ? Theme.space1 : 1
            spacing: 0

            /// The range **wraps rather than elides**, and that is the one
            /// rule this box has. A week column is about 105px of text and a
            /// range that crosses noon — "11:00 AM – 12:30 PM" — is wider than
            /// that at any size worth reading, so the first capture of this
            /// ghost printed "11:00 AM – 12:30 …". A ghost whose end time is
            /// an ellipsis has failed at the only job it has. Vertical room is
            /// the thing a drag ghost always has (its height *is* the
            /// duration), so the second line is where the rest goes.
            Text {
                width: parent.width
                text: ghost.rangeLabel
                wrapMode: Text.WordWrap
                maximumLineCount: ghost.roomy ? 2 : 1
                elide: Text.ElideRight
                lineHeight: 1.1
                color: CalendarTokens.text(ghost.hue)
                font.family: Theme.fontUi
                font.features: CalendarTokens.tabularFigures
                font.pointSize: Theme.pt(11)
                font.weight: Theme.weightMedium
            }

            Text {
                width: parent.width
                visible: ghost.tall && text.length > 0
                text: ghost.creating ? (ghost.durationLabel || "New event")
                                     : ghost.title
                elide: Text.ElideRight
                color: Qt.alpha(CalendarTokens.text(ghost.hue), 0.72)
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(11)
            }
        }
    }
}
