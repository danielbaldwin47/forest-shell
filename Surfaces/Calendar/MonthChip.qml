// One event at month scale — a 20px line, not a box with a time in it.
//
// ## Why this is not `EventChip` with a flag
//
// `EventChip.qml` is a chip sized by its *duration*: it has a 4px accent bar
// down its left edge, a tinted body, a title line and a time line, and it is
// tall enough for all of that because an hour of the week grid is 56px. None of
// that survives the trip here. A month cell gets ~90px for its whole stack, so
// a chip is 20px tall, and at 20px the accent bar is a stripe of colour with
// nothing beside it — noise, as the visual spec puts it — while the second line
// has nowhere to go. The two components share a hue table and a format object
// and nothing else; a `compact` flag on one file would be two layouts wearing
// one name, and the week chip's own `compact` already means something different
// (a short *meeting*, still in the time grid).
//
// ## The two shapes
//
// **A timed chip** is a 6px dot in the hue, the start time, and the title, on
// no background at all. The cell it sits in is the background, which is what
// keeps six weeks of these from reading as a wall of coloured boxes; the hue
// arrives as a dot, which is enough to tell two calendars apart at a glance.
//
// **A banner** — an all-day event, or a timed one that outlives its day — is
// the inverse: solid in the hue with `bgBase` text, spanning the cells it
// covers. It is the same inversion the week view's all-day band makes, for the
// same reason: a bar that looks like a chip is a bar that reads as a meeting.
//
// ## Squared ends mean "this is not the end"
//
// A banner cut by the end of a row keeps its rounded corners on the side where
// the event really begins or ends and squares off the side where the grid cut
// it. That is `continuesLeft` / `continuesRight`, and it is a shape rather than
// an arrow glyph on purpose: the cut edge is a full chip's height of colour
// running flush into
// the row boundary, which reads as continuation at the size the eye actually
// sees it, where a 7px arrow does not.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: chip

    /// The event itself, as the store holds it.
    required property var event

    /// Which of the eight hues, already resolved by `CalendarTokens.hues`.
    property int hue: 0

    /// A solid bar across its days rather than a dotted line in one cell.
    property bool banner: false

    /// The row cut this banner: keep the corners on the true ends only.
    property bool continuesLeft: false
    property bool continuesRight: false

    property bool selected: false
    property bool use24: false

    /// The hue dot's diameter, and where the *text* column starts behind it.
    /// Handed in by the view: the "+N more" row has no dot and still has to
    /// land in the same column, so the number belongs to the grid rather than
    /// to one chip.
    property int dotD: 6
    property int titleInset: 10

    /// Extra left padding for a bar the row start cut. Such a bar runs flush
    /// into the grid edge — that is what says it continues — so it pays the
    /// cell's inset back here and its label still lands in the text column.
    property real leadPad: 0

    property CalendarFormat format: CalendarFormat {}

    readonly property bool hovered: pointer.containsMouse

    readonly property string label: (chip.event && chip.event.title) ? chip.event.title : "Untitled"

    /// The start time, and only the start: an end time in a month cell's width is
    /// the thing that elides the title, and the title is what the month view is
    /// for. Banners have no time to show — that is what makes them banners.
    readonly property string timeLabel: (chip.banner || !chip.event)
        ? "" : chip.format.chipTime(chip.event.start, chip.use24)

    /// How much room the title keeps before the time is allowed to exist at
    /// all. The rule is stated on the *title* rather than on the chip because
    /// that is the thing being protected: at a 1180-wide window a month column
    /// is ~117px, and a right-hand time slot leaves the title 39px — "Design
    /// review" elides to "Des…", which is a chip that has stopped saying
    /// anything. 96px is roughly sixteen characters at `pt(11.5)`, measured off
    /// the fixture's own titles.
    readonly property int titleFloor: 96

    readonly property bool showsTime: chip.timeLabel.length > 0
        && (chip.width - chip.leadPad - chip.titleInset
            - time.implicitWidth - Theme.space2) >= chip.titleFloor

    signal activated

    implicitHeight: 20

    Rectangle {
        id: body

        anchors.fill: parent
        radius: 4

        // Per-corner radii, so a cut end is flush with the grid line it runs
        // into. Qt gives these on Rectangle since 6.7; the fallback would be a
        // second rectangle behind the first, which is a frame's worth of
        // overdraw in every banner cell.
        topLeftRadius: chip.continuesLeft ? 0 : body.radius
        bottomLeftRadius: chip.continuesLeft ? 0 : body.radius
        topRightRadius: chip.continuesRight ? 0 : body.radius
        bottomRightRadius: chip.continuesRight ? 0 : body.radius

        color: {
            if (chip.banner)
                return CalendarTokens.bar(chip.hue);
            if (chip.selected)
                return CalendarTokens.fill(chip.hue);
            if (chip.hovered)
                return Theme.surfaceOverlay;
            return "transparent";
        }

        // Selection is a ring in the hue. Inside the chip rather than outside
        // it: at this pitch a ring 1px proud of the body would touch the chip
        // above it, and two selected chips in a stack would share an edge.
        border.width: chip.selected ? 1 : 0
        border.color: CalendarTokens.bar(chip.hue)

        /// **Two columns, not a row of three things.** The first pass laid dot,
        /// time and title out in a `Row`, and because the time is variable width
        /// every title in the stack started on a different x — measured 20px of
        /// drift between two chips in one cell. The time is now a right-aligned
        /// slot at the chip's trailing edge, so titles make one clean left
        /// column and times make one clean right one, which is what a month
        /// stack has to look like to be scannable at all.

        /// The hue, as a dot. The week grid's 4px bar shrunk to a circle: same
        /// information, and at 20px a circle is the shape that still reads as
        /// deliberate.
        Rectangle {
            id: dot

            anchors.left: parent.left
            anchors.leftMargin: chip.leadPad
            anchors.verticalCenter: parent.verticalCenter
            width: chip.dotD
            height: chip.dotD
            radius: Theme.radiusFull
            color: CalendarTokens.bar(chip.hue)
            visible: !chip.banner
        }

        Text {
            id: time

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: chip.timeLabel
            visible: chip.showsTime
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11)
            font.weight: Theme.weightRegular
        }

        Text {
            id: title

            anchors.left: parent.left
            anchors.leftMargin: chip.leadPad + chip.titleInset
            anchors.right: time.visible ? time.left : parent.right
            anchors.rightMargin: time.visible ? Theme.space2 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label
            elide: Text.ElideRight
            maximumLineCount: 1
            color: chip.banner ? Theme.bgBase : Theme.textPrimary
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11.5)
            font.weight: Theme.weightMedium
        }

        MouseArea {
            id: pointer

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activated()
        }
    }
}
