// One event at month scale — a 21px line, not a box with a time in it.
//
// ## Why this is not `EventChip` with a flag
//
// `EventChip.qml` is a chip sized by its *duration*: it has a 4px accent bar
// down its left edge, a tinted body, a title line and a time line, and it is
// tall enough for all of that because an hour of the week grid is 56px. None of
// that survives the trip here. A month cell gets ~87px for its whole stack, so
// a chip is 21px tall, and at that height a full-height accent bar on a *timed* chip
// is a stripe of colour with nothing beside it — noise, as the visual spec puts
// it — while the second line has nowhere to go. The two components share a hue table and a format object
// and nothing else; a `compact` flag on one file would be two layouts wearing
// one name, and the week chip's own `compact` already means something different
// (a short *meeting*, still in the time grid).
//
// ## Two shapes, one title column, and the difference is loud on purpose
//
// A month view exists to answer one question per row of a cell: *is this at a
// time, or is it all day?* The pass before this answered it with a 3px bar
// versus a 6px dot on a 21px chip, and dropped the time from any chip whose
// title wanted the width — measured on the capture, six of the day's events
// carried no time at all, so a third of the grid could not be classified at
// reading distance. Two cues fix it and neither is subtle:
//
//   - **A timed chip always shows its time.** Not "if there is room": the time
//     *is* the classification, and a title elided two glyphs earlier costs less
//     than an event of unknown kind. Only a cell too narrow for the digits plus
//     a word drops it (`titleFloor`), and there the title alone is all that fits
//     anyway.
//   - **A banner is filled, a chip is tinted.** All-day and multi-day events are
//     solid in the hue with `bgBase` ink — the same treatment the week grid's
//     all-day band already gives them, so one calendar says "background fact"
//     one way — while a timed chip keeps the pale `tint(hue)` body under
//     `onTint(hue)` and carries the raw hue only as a 6px dot. Fill versus tint
//     survives peripheral vision; 3px of bar does not.
//
// **And both shapes start their text at the same x.** The dot's column is the
// title's column, banner or not: the previous pass had a banner's label at 8px
// from the body edge, a timed title at 15px and a bar-chip title at 11px — three
// left edges inside one cell, which is the ragged stack the whole layout was
// meant to avoid. A banner has no dot to draw there; it keeps the space anyway,
// because a column that moves is worse than a column with air in it.
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
// an arrow glyph on purpose: a squared cap is a full chip's height of colour
// with no end drawn on it, which reads as continuation at the size the eye
// actually sees it, where a 7px arrow does not.
//
// Where the two halves *sit* is `MonthView`'s call and its comment carries the
// measurement: the sending half runs flush into the row's right edge, the
// receiving half keeps the cell's ordinary content inset. Both square the cut
// cap, which is the part this file owns.
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

    /// Extra left padding, for a caller that has to place the body flush
    /// against something and still wants its content in the ordinary column.
    /// `MonthView` no longer needs it — both halves of a week wrap now keep the
    /// cell's inset — but the knob is what makes that a choice rather than a
    /// constraint.
    property real leadPad: 0

    property CalendarFormat format: CalendarFormat {}

    readonly property bool hovered: pointer.containsMouse

    readonly property string label: (chip.event && chip.event.title) ? chip.event.title : "Untitled"

    /// Whether this event owns whole days rather than a slot in one.
    readonly property bool allDay: !!(chip.event && chip.event.allDay === true)

    /// Ground and ink, and the one place the two shapes part company. A banner
    /// is solid in the hue under `bgBase`; a timed chip is the pale `tint(hue)`
    /// under `onTint(hue)` with the raw hue kept for its dot.
    readonly property color ground: chip.banner
        ? CalendarTokens.bar(chip.hue) : CalendarTokens.fill(chip.hue)
    readonly property color groundHover: chip.banner
        ? Qt.lighter(CalendarTokens.bar(chip.hue), 1.12) : CalendarTokens.fillHover(chip.hue)
    readonly property color ink: chip.banner ? Theme.bgBase : CalendarTokens.text(chip.hue)

    /// The start time, and only the start: an end time in a month cell's width
    /// is the thing that elides the title.
    ///
    /// An **all-day** event has no time to show — that is what makes it all-day.
    /// A *timed* multi-day one does: "Nordic QML Days" starts at 09:00 on the
    /// Thursday, and the pass before this promoted it to a banner and threw the
    /// hour away, so the grid asserted a three-day all-day event that is not
    /// one. The continuation half stays silent, because it did not start there —
    /// which is also the mark that tells the two halves apart.
    readonly property string timeLabel: (!chip.event || chip.allDay || chip.continuesLeft)
        ? "" : chip.format.chipTime(chip.event.start, chip.use24)

    /// **One text column, whatever the shape.** Past the dot and its gap — and a
    /// banner, which draws no dot, keeps the space regardless. See the header.
    readonly property real textX: chip.leadPad + chip.pad + chip.dotD + chip.itemGap

    /// The width the line actually has for words.
    readonly property real freeWidth: Math.max(0, chip.width - chip.textX - chip.pad)

    /// How much title has to survive beside the time before the time is worth
    /// keeping. Three or four glyphs: below that the line says "10:30a D…",
    /// which classifies the event but names nothing, and at that width the
    /// title alone is the better half.
    property int titleFloor: 30

    /// **The time is the classification, so it is not negotiable.**
    ///
    /// The spec's ">90px free" rule and the elision rule the pass before this
    /// added on top of it were both measured on the capture and both wrong in
    /// the same direction: between them they stripped the time from six of the
    /// day's events — "Design review", "Vendor call", "Lunch w/ Birch",
    /// "Deploy window", "Quarter close" — leaving a 6px dot as the only thing
    /// separating a 10:00 meeting from an all-day one. A month grid where a
    /// third of the entries cannot be classified has failed at the one job it
    /// has. So a timed chip shows its time unless the digits plus `titleFloor`
    /// do not fit, and the title elides instead.
    readonly property bool showsTime: chip.timeLabel.length > 0
        && chip.freeWidth >= timeMetrics.width + chip.itemGap + chip.titleFloor

    signal activated

    implicitHeight: 21

    TextMetrics {
        id: titleMetrics

        font: title.font
        text: chip.label
    }

    TextMetrics {
        id: timeMetrics

        font: time.font
        text: chip.timeLabel
    }

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

        // Solid for a banner, tinted for a chip — see the header.
        color: (chip.selected || chip.hovered) ? chip.groundHover : chip.ground

        // Selection is a ring in the hue. Inside the chip rather than outside
        // it: at this pitch a ring 1px proud of the body would touch the chip
        // above it, and two selected chips in a stack would share an edge.
        border.width: chip.selected ? 1 : 0
        border.color: chip.banner ? Theme.bgBase : CalendarTokens.bar(chip.hue)

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

            x: chip.textX
            anchors.verticalCenter: parent.verticalCenter
            text: chip.timeLabel
            visible: chip.showsTime
            color: chip.ink
            opacity: chip.banner ? 0.82 : 0.72
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11)
            font.weight: Theme.weightRegular
            renderType: Text.NativeRendering
        }

        Text {
            id: title

            x: time.visible ? time.x + timeMetrics.width + chip.itemGap : chip.textX
            width: Math.max(0, body.width - title.x - chip.pad)
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label
            elide: Text.ElideRight
            maximumLineCount: 1
            // The shape decides the ink; both are ≥4.5:1 on their own ground.
            color: chip.ink
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11.5)
            font.weight: Theme.weightMedium
            renderType: Text.NativeRendering
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
