// One event at month scale — a 21px line, not a box with a time in it.
//
// ## Why this is not `EventChip` with a flag
//
// `EventChip.qml` is a chip sized by its *duration*: it has a 4px accent bar
// down its left edge, a tinted body, a title line and a time line, and it is
// tall enough for all of that because an hour of the week grid is 56px. None of
// that survives the trip here. A month cell gets ~90px for its whole stack, so
// a chip is 21px tall, and at 21px the accent bar is a stripe of colour with
// nothing beside it — noise, as the visual spec puts it — while the second line
// has nowhere to go. The two components share a hue table and a format object
// and nothing else; a `compact` flag on one file would be two layouts wearing
// one name, and the week chip's own `compact` already means something different
// (a short *meeting*, still in the time grid).
//
// ## One body, two fills
//
// Both shapes are the same 21px box with the same radius, the same padding and
// the same left edge — the review that produced this pass found the previous
// one drawing all-day events as filled bars and timed events as bare text on
// the cell, which read as half a grid rendered. What differs is the *fill*, and
// it differs the way the week view already differs: a **banner** (all-day, or a
// timed event that outlives its day) is solid in the hue with `bgBase` text, a
// **timed chip** is `tint(hue)` with `onTint(hue)` text. The inversion is the
// information — a bar that looks like a chip is a bar that reads as a meeting.
//
// ## The atom is one line, laid out left to right, tight
//
// Dot, time, title — each starting immediately after the one before it, with a
// single `space1` between them. It is deliberately **not** a table. The pass
// before this gave the time a fixed-width column with the digits right-aligned
// in it, reasoning that a pinned title origin would make a stack scannable.
// Measured off the capture it did the opposite: a 42px void opened between the
// 6px dot and the time on every chip whose time was short, which on a 194px
// cell is 22% of the row spent on nothing, and four of six chips elided their
// titles at widths where the reference fits them whole. A month chip's job is
// the title; every pixel the layout reserves for alignment is a pixel taken
// from it. So the line packs left, and the eye gets its column from the chip
// bodies' shared left edge instead — which is free, because they all have one.
//
// ## Squared ends mean "this is not the end"
//
// A banner cut by the end of a row keeps its rounded corners on the side where
// the event really begins or ends and squares off the side where the grid cut
// it. That is `continuesLeft` / `continuesRight`, and it is a shape rather than
// an arrow glyph on purpose: the cut edge is a full chip's height of colour
// running flush into the row boundary, which reads as continuation at the size
// the eye actually sees it, where a 7px arrow does not.
//
// Between its true ends a banner is **one unbroken pill**. It draws no day
// boundaries of its own: the pass before this creased the fill at every column
// edge it crossed, and the creases measured as ~3px dark gaps, so a three-day
// event read as a dashed row of slabs rather than one run. Which days a banner
// covers is already said by the numerals it passes under.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: chip

    /// The event itself, as the store holds it.
    required property var event

    /// Which of the eight hues, already resolved by `CalendarTokens.hues`.
    property int hue: 0

    /// A solid bar across its days rather than a tinted line in one cell.
    property bool banner: false

    /// The row cut this banner: keep the corners on the true ends only.
    property bool continuesLeft: false
    property bool continuesRight: false

    property bool selected: false
    property bool use24: false

    /// The hue dot's diameter. Handed in by the view so the grid owns it.
    property int dotD: 6

    /// The air between the body's edge and its content, and between the three
    /// things on the line. `space1` on the leading edge rather than `space2`:
    /// the body's own left edge is already the cell's content inset, so a
    /// second inset inside it would push the text a second time.
    property int pad: Theme.space1
    property int itemGap: Theme.space1

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

    readonly property bool showsTime: !chip.banner && chip.timeLabel.length > 0

    signal activated

    implicitHeight: 21

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
            if (chip.selected || chip.hovered)
                return CalendarTokens.fillHover(chip.hue);
            return CalendarTokens.fill(chip.hue);
        }

        // Selection is a ring in the hue. Inside the chip rather than outside
        // it: at this pitch a ring 1px proud of the body would touch the chip
        // above it, and two selected chips in a stack would share an edge.
        border.width: chip.selected ? 1 : 0
        border.color: CalendarTokens.bar(chip.hue)

        /// The hue, as a dot. The week grid's 4px bar shrunk to a circle: same
        /// information, and at 21px a circle is the shape that still reads as
        /// deliberate. A banner has no dot — it *is* the hue.
        Rectangle {
            id: dot

            x: chip.leadPad + chip.pad
            anchors.verticalCenter: parent.verticalCenter
            width: chip.dotD
            height: chip.dotD
            radius: Theme.radiusFull
            color: CalendarTokens.bar(chip.hue)
            visible: !chip.banner
        }

        /// `9a Standup`, packed. The time reads before the title because that
        /// is the order the question is asked in a month cell — *when*, then
        /// *what* — and it takes exactly the width its digits need.
        Text {
            id: time

            x: dot.visible ? dot.x + dot.width + chip.itemGap : chip.leadPad + chip.pad
            anchors.verticalCenter: parent.verticalCenter
            text: chip.timeLabel
            visible: chip.showsTime
            color: CalendarTokens.text(chip.hue)
            opacity: 0.72
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11)
            font.weight: Theme.weightRegular
        }

        Text {
            id: title

            x: time.visible ? time.x + time.implicitWidth + chip.itemGap
             : dot.visible ? dot.x + dot.width + chip.itemGap
             : chip.leadPad + chip.pad
            width: Math.max(0, body.width - title.x - chip.pad)
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label
            elide: Text.ElideRight
            maximumLineCount: 1
            color: chip.banner ? Theme.bgBase : CalendarTokens.text(chip.hue)
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
