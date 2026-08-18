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
//   - **A timed chip shows its time while the title can still be read.** The
//     time *is* the classification, and a title elided two glyphs earlier costs
//     less than an event of unknown kind — but a title cut to a stump costs
//     more, so the trade is arithmetic and lives at seam 1
//     (`MonthPolicy.chipText`, a share of the title's own glyphs).
//   - **A banner is a stronger tint with an edge, a chip is a plain tint.** The
//     pass before this made banners solid in the hue with `bgBase` ink, borrowed
//     from the week grid's all-day band, and at month scale the borrow lost:
//     a three-column saturated slab out-shouted today's accent disc, which is
//     the one mark a month grid may not lose. So a banner mixes 15% of the bar
//     colour into the same `tint(hue)` body and carries a hairline of the hue,
//     one step from the chip beside it rather than five — and it keeps the same
//     ink, so the ≥4.5:1 promise is one measurement for both shapes. What
//     really says "all day" is the shape: a bar that spans its days.
//
// **And there is no hue dot on a tinted chip.** The pass before this drew a 6px
// dot at the head of every timed chip, which said in a second voice what the
// body's own tint already says — the chip *is* that colour — and cost the title
// ten pixels and a second left edge for it. So both shapes start their text on
// one rule, `pad` in from the body edge, with nothing in front of it: the
// previous pass had a banner's label at 8px from the body edge, a timed title at
// 15px and a bar-chip title at 11px — three left edges inside one cell.
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
// it. That is `continuesLeft` / `continuesRight`, and the square cap is the
// shape that carries it: a full chip's height of colour with no end drawn on
// it reads as continuation at the size the eye actually sees.
//
// The *sending* half adds a chevron at that cap — the square end alone says
// "not finished" but not which way — and the *receiving* half says the rest by
// what it leaves out: no time, because it did not start there. Both halves keep
// the gutter (`MonthPolicy.barSpan`); a bar run flush into the grid line reads
// as sliding under the next cell, and in the last column it runs into the
// window frame, which is the one line in the picture that is not the grid.
//
// Between its true ends a banner is **one unbroken pill**. It draws no day
// boundaries of its own: the pass before this creased the fill at every column
// edge it crossed, and the creases measured as ~3px dark gaps, so a three-day
// event read as a dashed row of slabs rather than one run. Which days a banner
// covers is already said by the numerals it passes under.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core
import qs.Widgets

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

    /// Kept for callers that still name it; nothing draws a dot any more. See
    /// the header: on a tinted body the fill *is* the hue, and the dot was a
    /// second answer to a question already answered.
    property int dotD: 0

    /// The air between the body's edge and its content, and between the time
    /// and the title. **8 on both edges, banner and chip alike** — one text
    /// rule per cell, with no dead column in front of it.
    property int pad: Theme.space2
    property int itemGap: Theme.space1

    /// The arithmetic that decides whether the time is worth its width. Handed
    /// down by the view so 42 cells share one object.
    property MonthPolicy policy: MonthPolicy {}

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

    /// Ground and ink — **one step apart, not five.**
    ///
    /// A banner was solid in the hue under `bgBase` ink for a pass, borrowed
    /// from the week grid's all-day band. Measured on the month capture, the
    /// borrow does not survive the change of scale: the week band holds two or
    /// three bars against an empty strip, while a month row puts a saturated
    /// slab across three columns of tinted chips, and the three-column tan of
    /// "Nordic QML Days" was the loudest object in the window — louder than
    /// today's marker, which is the one thing in a month grid that must win.
    /// The spec's month section says it plainly: chip fill = `tint(hue)`.
    ///
    /// So both shapes are tints of the same hue and the banner is one step up —
    /// 15% of the bar colour mixed into the chip's own fill, plus a hairline of
    /// the hue around it. That is enough to read as "a different kind of thing"
    /// beside a chip and nowhere near enough to outrank the accent disc. The
    /// ink is the same `text(hue)` both ways, which is what keeps the contrast
    /// promise a single measurement instead of two (≥4.5:1 on both grounds, in
    /// both modes).
    readonly property color ground: chip.banner
        ? Qt.tint(CalendarTokens.fill(chip.hue), Qt.alpha(CalendarTokens.bar(chip.hue), 0.15))
        : CalendarTokens.fill(chip.hue)
    readonly property color groundHover: chip.banner
        ? Qt.tint(CalendarTokens.fillHover(chip.hue), Qt.alpha(CalendarTokens.bar(chip.hue), 0.15))
        : CalendarTokens.fillHover(chip.hue)
    readonly property color ink: CalendarTokens.text(chip.hue)

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

    /// **One text column, whatever the shape.** The body's own inset and
    /// nothing else — a banner has no accent to clear and a tinted chip needs
    /// none, so neither reserves a column for one. See the header.
    readonly property real textX: chip.leadPad + chip.pad

    /// The chevron a cut end carries, and the width it costs the title.
    readonly property int chevronSize: 12

    /// **The time is kept while the title can still be read, and not one pixel
    /// past that.** The threshold is `MonthPolicy.chipText` — a share of the
    /// title's own glyphs rather than a width of the chip — so the rule is
    /// stated once, tested at seam 1, and the same on every chip in the grid.
    readonly property bool showsTime: chip.timeLabel.length > 0
        && chip.policy.chipText(chip.width - (chip.continuesRight ? chip.chevronSize + chip.itemGap : 0),
                                chip.label.length, timeMetrics.width, titleMetrics.width,
                                chip.pad, chip.itemGap).showsTime

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
        //
        // A banner carries the same hairline unselected at a third of the
        // weight — the edge is what lets a one-step-stronger tint read as a
        // different kind of object rather than as a chip caught mid-hover.
        border.width: (chip.selected || chip.banner) ? 1 : 0
        border.color: chip.selected
            ? CalendarTokens.bar(chip.hue)
            : Qt.alpha(CalendarTokens.bar(chip.hue), 0.45)

        /// The way the event went, at the end the grid cut. Only the sending
        /// half draws it, and it sits inside the gutter the bar already keeps,
        /// so the arrow points at the rule rather than through it.
        Icon {
            id: chevron

            anchors.right: parent.right
            anchors.rightMargin: chip.pad - 2
            anchors.verticalCenter: parent.verticalCenter
            size: chip.chevronSize
            name: "chevron-right"
            color: chip.ink
            visible: chip.continuesRight
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
            /// **Full strength, and the hierarchy comes from weight.** The time
            /// carried 0.62 alpha for a pass and measured 3.36–3.39:1 against
            /// its own fill on every hue — the smallest text in the view was
            /// the only text failing the ≥4.5:1 the spec promises, while the
            /// title beside it sat at 6:1. Alpha is the wrong lever for
            /// "secondary" on a tinted ground: it walks the ink toward the fill
            /// and there is nowhere for it to go. Regular against the title's
            /// medium, and 11pt against 11.5, say the same thing and cost the
            /// reader nothing. Tabular, so a column of times does not look
            /// kerned by hand.
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11)
            font.weight: Theme.weightRegular
            font.features: CalendarTokens.tabularFigures
            renderType: Text.NativeRendering
        }

        Text {
            id: title

            x: time.visible ? time.x + timeMetrics.width + chip.itemGap : chip.textX
            width: Math.max(0, body.width - title.x - chip.pad
                               - (chevron.visible ? chip.chevronSize + chip.itemGap : 0))
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
