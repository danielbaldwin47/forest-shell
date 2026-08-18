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
// ## Only one of the two shapes is filled, and that is the whole design
//
// Every pass before this one drew a month cell's events as a stack of filled
// bricks — a tint of the hue behind every chip, timed and all-day alike. On one
// chip it looks like an object; on a 42-cell grid carrying 90 of them it is a
// mosaic, and the review said so twice: the grid's own structure (rules, dates,
// today's mark) was reading *behind* a field of coloured rectangles, and the
// loudest object in the window was whichever event happened to span three
// columns. Raising or lowering the tint does not fix that. **The count of
// filled rectangles is the problem, and the fix is to draw far fewer of them.**
//
// So the two shapes stop being two strengths of one shape:
//
//   - **A timed event is not a box at all.** It is a hue-coloured lozenge, then
//     its time, then its title — three marks on the cell's own ground, with no
//     fill, no border and no shape of its own. The reference draws it exactly
//     this way, and the reason it works is that a timed event *is* a line item:
//     it owns a moment, not a span, so there is nothing for a box to enclose.
//     A cell of these reads as a list, which is what it is.
//   - **A banner is the filled pill**, and now it is the only filled thing in
//     the grid. It has earned the fill: it owns whole days, it runs across
//     columns, and its shape is the statement. Because nothing else is filled,
//     it needs no extra tint strength to be distinguishable — it is one step
//     from its own cell rather than one step from the chip beside it — so it
//     keeps the plain `tint(hue)` body the spec asks for, plus the 4px accent
//     bar at its true start that says which hue it is at a glance.
//
// The hierarchy that falls out of this is the one a month grid wants: today's
// mark first, the dates second, the banners third, the timed lines last. Before
// this pass that order was exactly inverted.
//
// ## Strength splits past from future, not calendar from calendar
//
// Colour already says which calendar an event came from. The one thing the grid
// could not say was *what has already happened*, so a reader had to find today's
// row before the month meant anything. A finished event now recedes — the whole
// row at `pastOpacity`, mark and text together, so the split is one gesture and
// not a second colour system. The rule itself is `MonthPolicy.isPast`, which
// compares the event's **end** against now, so a meeting running right now is
// still future.
//
// ## One text column
//
// Both shapes start their text on one rule and the marks in front of it are the
// same width, so a cell's timed lines and its banners' labels stand in a single
// column. The previous pass had a banner's label at 8px from the body edge, a
// timed title at 15px and a bar-chip title at 11px — three left edges inside one
// cell.
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

    /// Already over at the view's `nowStamp` — decided by `MonthPolicy.isPast`,
    /// never here. See the header: this is the grid's second axis and its only
    /// one that is not colour.
    property bool past: false

    /// How far a finished **banner** recedes. A timed line spends its past-ness
    /// on the title's ink instead (see `ink`); a banner cannot, because its ink
    /// is solved against its own fill and moving one without the other breaks
    /// the pair. So the pill dims as a whole, and 0.8 is where it stops: below
    /// that the worst hue's ink-on-fill drops under 4.5:1 (0.75 measures 4.48,
    /// 0.8 measures 4.81).
    property real pastOpacity: 0.8

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

    /// **A banner is filled; a timed chip has no ground at all.**
    ///
    /// The banner's fill is `HuePolicy.bannerAlpha` over the cell rather than
    /// the chip table's `tintAlpha`, and the difference is what the fill is
    /// being measured against. A week-grid chip's tint is one step from the
    /// tinted chips beside it; a month banner has no tinted neighbours left, so
    /// its step is against the bare cell, and at 0.16 the capture came back with
    /// six banners that read as smudges rather than as pills — the one shape
    /// carrying "this owns the day" was the faintest object in the grid.
    ///
    /// A timed chip's ground is the cell, and the only time it paints one is
    /// under the pointer or under a selection — where the mark being made is
    /// "this row", not "this hue", so it is the shell's own `surfaceOverlay`
    /// rather than a tint. That is also what keeps hover legible on a shape
    /// with no edge of its own.
    readonly property color bannerFill: CalendarTokens.hues.tint(
        String(CalendarTokens.bar(chip.hue)), String(Theme.surfaceRaised),
        CalendarTokens.hues.bannerAlpha(Theme.dark))

    readonly property color ground: chip.banner ? chip.bannerFill : "transparent"
    readonly property color groundHover: chip.banner
        ? Qt.tint(chip.bannerFill, Qt.alpha(Theme.surfaceOverlay, 0.12))
        : Theme.surfaceOverlay

    /// The title's ink, and **the one thing a finished event changes.**
    ///
    /// A timed line's title is the page's own primary text, because that is what
    /// it sits on: a month cell's list of the day should read as text first and
    /// as colour-coding second. Past, it steps to `textMuted` — a whole token
    /// down, not an opacity — which is what the reference does and what makes a
    /// finished row recede without anything in it becoming unreadable. Both
    /// values are measured on the cell ground: 13:1 and 4.56:1.
    ///
    /// This is deliberately *not* an opacity on the row. Dimming the whole line
    /// to 0.55 took the time label with it, and a `textMuted` time at 0.55
    /// composites to **2.35:1** — the smallest type in the surface, below any
    /// reading threshold. The title is the only thing that has room to move.
    readonly property color ink: chip.banner
        ? CalendarTokens.text(chip.hue)
        : (chip.past ? Theme.textMuted : Theme.textPrimary)

    /// The time in front of the title, one rung quieter, and the **same** rung
    /// whether the event has happened or not. On a banner it shares the title's
    /// ink (there is no muted token solved against a hue fill); on a timed line
    /// it is `textMuted` — 4.56:1 on the cell, which is all the headroom it has,
    /// so past-ness is spent on the title instead.
    readonly property color timeInk: chip.banner ? chip.ink : Theme.textMuted

    /// The hue mark: a full-height accent bar down a banner's true start, and a
    /// short rounded lozenge in front of a timed line. Same width and same left
    /// rule for both, so one cell's marks make a column. Past, it drops to half
    /// alpha over whatever ground it is on — still plainly its own colour, which
    /// is the point of it, and plainly the quieter of two marks side by side.
    readonly property color markInk: chip.past
        ? Qt.alpha(CalendarTokens.bar(chip.hue), 0.5)
        : CalendarTokens.bar(chip.hue)

    readonly property int markW: 4
    readonly property int markH: 13

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

    /// Where the hue mark stands. A banner's accent bar is flush with the
    /// pill's own left edge — it *is* the edge, in colour — while a timed
    /// lozenge stands on the chip's left edge, which the view has already set
    /// to the cell's content inset. Both therefore land on the same rule.
    readonly property real markX: chip.banner ? 0 : chip.leadPad

    /// **One text column, whatever the shape.** Mark width plus one gap, both
    /// the same for a banner and for a timed line, so a cell's labels stand in
    /// a single column no matter which shapes it happens to hold. A cut banner
    /// draws no accent but still reserves its width, because the column is the
    /// point.
    readonly property real textX: chip.banner
        ? chip.leadPad + chip.pad + chip.markW
        : chip.markX + chip.markW + Theme.space2

    /// The air after the last glyph. A banner has a body to stay inside; a
    /// timed line's row is already inset by the cell, so a second inset there
    /// would only shorten titles.
    readonly property real tailPad: chip.banner ? chip.pad : 0

    /// The chevron a cut end carries, and the width it costs the title.
    readonly property int chevronSize: 12

    /// **The time is kept while the title can still be read, and not one pixel
    /// past that.** The threshold is `MonthPolicy.chipText` — a share of the
    /// title's own glyphs rather than a width of the chip — so the rule is
    /// stated once, tested at seam 1, and the same on every chip in the grid.
    /// The room a title actually has: the body less its lead, its tail and any
    /// chevron. **Handed to `chipText` already subtracted, with a zero inset**,
    /// because that function's `inset` is one side of a symmetric pair and this
    /// layout is not symmetric — a timed line leads with a mark and ends flush.
    /// Passing the lead as if it were both sides charged every chip twice for
    /// padding it does not have, and the measured cost was the *time* label
    /// falling off chips with 146px of room and a 90px floor.
    readonly property real titleRoom: chip.width - chip.textX - chip.tailPad
        - (chip.continuesRight ? chip.chevronSize + chip.itemGap : 0)

    readonly property bool showsTime: chip.timeLabel.length > 0
        && chip.policy.chipText(chip.titleRoom, chip.label.length,
                                timeMetrics.width, titleMetrics.width,
                                0, chip.itemGap).showsTime

    signal activated

    implicitHeight: 21

    /// Only a banner recedes as a whole object. See `pastOpacity`: a timed
    /// line's smallest type has no headroom for an opacity, so its past-ness is
    /// a token step on the title and a half-alpha mark, both of which are
    /// measured on the ground they actually land on.
    opacity: (chip.past && chip.banner) ? chip.pastOpacity : 1

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

        // Filled for a banner; for a timed line, nothing at all until the
        // pointer or a selection asks for a row to be marked.
        color: (chip.selected || chip.hovered) ? chip.groundHover : chip.ground

        // Selection is a ring in the hue. Inside the chip rather than outside
        // it: at this pitch a ring 1px proud of the body would touch the chip
        // above it, and two selected chips in a stack would share an edge.
        //
        // **Only a selection draws one now.** A banner carried a permanent
        // hairline while it had to out-read a grid of tinted chips; with the
        // chips unfilled it is the only filled object in its cell and the edge
        // was one more line in a picture already full of them.
        border.width: chip.selected ? 1 : 0
        border.color: CalendarTokens.bar(chip.hue)

        /// The hue, as a mark rather than as a wash.
        ///
        /// A banner gets the reference's 4px accent bar down its true start —
        /// full height, flush, sharing the pill's own left rounding, and absent
        /// on a half the row cut, because a bar in the middle of a run would
        /// claim that run started there.
        ///
        /// A timed line gets a short rounded lozenge on the same rule. It is
        /// the *only* colour that line carries, which is why it is a solid bar
        /// colour and not a tint: a 4x13 mark has to be legible at a glance
        /// from four feet away, and a tint of it would not be.
        Rectangle {
            id: mark

            x: chip.markX
            width: chip.markW
            height: chip.banner ? parent.height : chip.markH
            anchors.verticalCenter: parent.verticalCenter
            color: chip.markInk
            radius: chip.banner ? 0 : chip.markW / 2
            topLeftRadius: chip.banner ? body.topLeftRadius : mark.radius
            bottomLeftRadius: chip.banner ? body.bottomLeftRadius : mark.radius
            visible: !(chip.banner && chip.continuesLeft)
        }

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
            color: chip.timeInk
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
            width: Math.max(0, body.width - title.x - chip.tailPad
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
