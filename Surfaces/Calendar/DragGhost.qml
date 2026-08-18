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
// look, and it is deliberately the *chip's* look one level up: the same tint
// grammar, the same 3px rail, the same light ink, mixed on `surfaceRaised` and
// standing on a stacked shadow. A moved chip must not change what it is on the
// way across the week — only where it is.
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

    /// And the line *under* the range needs its own row on top of that. It was
    /// 56 while the range could take two lines; a single-line range gives the
    /// second row back, so a 40px ghost — an hour and a half at `hourRow` 56 —
    /// now says what it will do as well as when.
    readonly property bool tall: ghost.height >= 40

    /// The lift: `0.92` and `1.02`, both the spec's, and both guarded by
    /// `Theme.animateTransforms` so `appearance.reducedEffects` drops the
    /// transform rather than the ghost.
    opacity: 0.92
    scale: Theme.animateTransforms ? 1.02 : 1

    /// Which end of the box the gesture has hold of, if either. A resize is the
    /// one drag whose ghost sits almost exactly on top of the chip it came
    /// from, so it is also the one that has to say *which edge is moving*.
    readonly property bool gripBottom: ghost.mode === "resizeBottom"
    readonly property bool gripTop: ghost.mode === "resizeTop"

    /// The elevation — a stacked falloff, not a plate. The ramp itself and the
    /// argument for it are `CalendarTokens.liftShadow`; what is here is only the
    /// geometry, and the one thing the geometry has to get right is that every
    /// ring is **concentric with the plate and rounded to match it**. The three
    /// flat plates this replaced were offset down *and* left of a rounded card
    /// with square corners of their own, which photographed as a second, badly
    /// registered rectangle rather than as a shadow.
    Repeater {
        model: CalendarTokens.liftShadow

        delegate: Rectangle {
            required property var modelData

            anchors.fill: plate
            anchors.margins: -modelData.spread
            anchors.topMargin: -modelData.spread + modelData.drop
            anchors.bottomMargin: -modelData.spread - modelData.drop
            radius: Theme.radiusSm + modelData.spread
            color: CalendarTokens.liftShadowInk(modelData.alpha)
        }
    }

    /// **The chip's own grammar, raised a level.**
    ///
    /// Two answers have been wrong here in opposite directions. `tint(hue)` at
    /// 0.94 — the resting fill exactly — measured 1.18:1 against the column and
    /// did not look picked up at all. `bar(hue)` solid, with the ink inverted
    /// onto it, looked picked up and stopped looking like *this surface*: a
    /// flat light block with near-black text, dropped into a week where every
    /// chip is a dark tint with a rail and light type.
    ///
    /// `liftFill` is the middle the two of them bracket, and the rail and ink
    /// below come back with it. See `CalendarTokens.liftFill` for the numbers.
    Rectangle {
        id: plate

        anchors.fill: parent
        radius: Theme.radiusSm
        clip: true
        color: CalendarTokens.liftFill(ghost.hue)

        /// The rail, at the width and colour a resting chip wears it.
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: CalendarTokens.chipBar
            color: CalendarTokens.liftRail(ghost.hue)
        }

        /// A hairline of the hue. A resting chip carries the same edge at 0.28;
        /// the lifted one takes it at 0.55, which is the only place the card
        /// still says out loud that it is off the page rather than on it.
        border.width: 1
        border.color: CalendarTokens.liftEdge(ghost.hue)

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: CalendarTokens.chipBar + Theme.space2
            anchors.rightMargin: Theme.space2
            anchors.topMargin: ghost.roomy ? Theme.space1 : 1
            spacing: 0


            /// The range, **on one line and never elided**.
            ///
            /// This is the one rule the box has, and it has now been solved
            /// twice. A week column is about 105px of text and a range that
            /// crosses noon — `"11:00 AM – 12:30 PM"` — is wider than that at
            /// any size worth reading, so the first capture printed
            /// `"11:00 AM – 12:30 …"`. A ghost whose end time is an ellipsis
            /// has failed at the only job it has.
            ///
            /// Wrapping it onto a second line fixed the ellipsis and cost the
            /// thing the line is for: a two-line time is read as two facts, and
            /// during a drag the eye is sampling it forty times a second while
            /// tracking a box that is also moving. It has to be one glance.
            ///
            /// So the type shrinks instead. `Text.HorizontalFit` keeps the
            /// range on one line down to `pt(9)` — enough for the widest range
            /// this grammar produces in the narrowest week column — and the
            /// number is whole at every width. A time half a point smaller for
            /// the two hours a day that cross noon is a cost nobody can see;
            /// a wrapped one is not.
            Text {
                width: parent.width
                text: ghost.rangeLabel
                maximumLineCount: 1
                elide: Text.ElideRight
                fontSizeMode: Text.HorizontalFit
                minimumPointSize: Theme.pt(9)
                lineHeight: 1.1
                color: CalendarTokens.liftText(ghost.hue)
                font.family: Theme.fontUi
                font.features: CalendarTokens.tabularFigures
                font.pointSize: Theme.pt(11)
                font.weight: Theme.weightMedium
            }

            /// The second line carries two facts and they are not the same
            /// kind. The **title** says what is being moved; the **duration**
            /// says how much of the day it will take, and during a resize that
            /// is the number the gesture is choosing. So the title elides and
            /// the duration never does — it is pinned to the right edge and the
            /// title is given whatever is left.
            ///
            /// One label, and only one. The first resize capture drew this
            /// number twice: the chip underneath kept rendering its own time
            /// line while the ghost drew the live one on top of it, two `Text`
            /// items a few pixels apart compositing into a smear. The view now
            /// hides the chip it is dragging outright (see `WeekView`'s vacated
            /// slot), which leaves the ghost as the only thing on the grid
            /// saying a time.
            Item {
                width: parent.width
                height: ghost.tall ? titleText.implicitHeight : 0
                visible: ghost.tall

                Text {
                    id: durationText

                    anchors.right: parent.right
                    anchors.top: parent.top
                    visible: ghost.durationLabel.length > 0
                    text: ghost.durationLabel
                    color: Qt.alpha(CalendarTokens.liftText(ghost.hue), 0.86)
                    font.family: Theme.fontUi
                    font.features: CalendarTokens.tabularFigures
                    font.pointSize: Theme.pt(11)
                    font.weight: Theme.weightMedium
                }

                Text {
                    id: titleText

                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.right: durationText.visible ? durationText.left
                                                        : parent.right
                    anchors.rightMargin: durationText.visible ? Theme.space2 : 0
                    text: ghost.creating ? "New event" : ghost.title
                    elide: Text.ElideRight
                    color: Qt.alpha(CalendarTokens.liftText(ghost.hue), 0.92)
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11)
                }
            }
        }

        /// The grip, on the edge the gesture has hold of. The chip has one of
        /// these on hover; a resize in flight is the moment it matters most,
        /// and until now the ghost dropped it — so a resize mid-picture had
        /// nothing on it saying which end was travelling and read as a plain
        /// selected event that happened to be the wrong length.
        Rectangle {
            visible: ghost.gripBottom || ghost.gripTop
            width: 24
            height: 3
            radius: Theme.radiusFull
            color: Qt.alpha(CalendarTokens.liftRail(ghost.hue), 0.9)
            x: Math.round((plate.width - width) / 2)
            y: ghost.gripBottom ? plate.height - height - 3 : 3
        }
    }
}
