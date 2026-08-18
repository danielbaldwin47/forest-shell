// The month grid: six rows of seven days, and every event that touches them.
//
// ## What this file decides: nothing
//
// The same rule `WeekView.qml` states. Which six rows of seven days a month is,
// what a cell shows and what it hides behind "+N more", how many chips fit once
// the banner bars have been paid for, and where a multi-day bar is cut — all of
// it is `MonthPolicy`, tested offscreen in `tests/tst_monthpolicy.qml`. Every
// label is `CalendarFormat`, every colour and fixed pixel is `CalendarTokens`.
// What is left here is anchoring.
//
// ## Two stacks per cell, and why the row owns one of them
//
// A month cell holds two kinds of thing and only one of them belongs to the
// cell. A timed event is a chip *inside* Tuesday. A conference running Thursday
// to Saturday is one bar *across* three cells, and the cell that tried to own
// it would either draw a third of a bar or draw the whole thing three times.
// So banners are drawn by the row, in lanes, from `MonthPolicy.spans`, and the
// cells draw only what is left — `MonthPolicy.cellChips`, which exists so that
// the split is arithmetic rather than a filter written twice.
//
// The join between them is the one number a view could plausibly get wrong on
// its own, which is why it is not here either: `MonthPolicy.chipCapacity` takes
// the row's lane count off the cell height *before* counting chips. Without it
// every row with a multi-day event in it draws one chip too many, hanging below
// the cell's own floor — and no test of either half would have seen it.
//
// ## Fresh arrays, always
//
// Six rows in and six rows out is a `Repeater` model of unchanged length, and
// such a model does not rebuild its delegates (measured, #195). Every delegate
// therefore reads its data by index out of `rowModels` — a single binding that
// is *reassigned* whole on every anchor change — rather than trusting a
// `modelData` that a stale delegate may still be holding from last month.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: view

    /// Any day in the month to draw.
    property string anchorDate: ""

    /// The locale's first weekday, `Locale.Sunday === 0`. Handed down from the
    /// window so the grid, the toolbar and the sidebar cannot disagree.
    property int firstDay: 1

    /// Today, as `YYYY-MM-DD`. Passed in and never read from a clock here, for
    /// the reason `WeekView` gives: a capture has to take the same photograph
    /// twice.
    property string todayIso: ""

    /// Now, as `YYYY-MM-DDTHH:MM`, and the axis every chip's strength is split
    /// on (`MonthPolicy.isPast`). Passed in for the same reason `todayIso` is —
    /// a capture has to take the same photograph twice.
    ///
    /// **Empty falls back to the end of `todayIso`**, so a caller that has a
    /// date but no clock still gets the useful half of the split: every week
    /// before this one recedes, and today's own cell stays at full strength
    /// rather than guessing at an hour nobody supplied.
    property string nowStamp: ""

    readonly property string nowBound: view.nowStamp.length > 0
        ? view.nowStamp
        : (view.todayIso.length > 0 ? view.todayIso + "T00:00" : "")

    /// The whole store's worth of events. The view splits them into bars and
    /// chips itself, because the split is the policy's rule and not the
    /// caller's.
    property var events: []

    property string selectedId: ""

    property bool use24: false

    signal eventActivated(string id)

    /// A cell's hidden events were asked for — the day popover's cue. Nothing
    /// listens yet; the affordance is drawn and says what it would do.
    signal moreActivated(string iso)

    property MonthPolicy policy: MonthPolicy {}
    property CalendarFormat format: CalendarFormat {}

    // --- geometry --------------------------------------------------------------

    /// The weekday caps above the grid, and the hairline under them.
    readonly property int headingH: 28

    /// Month-scale chip metrics, stated here and handed to the policy rather
    /// than left to its defaults, so the arithmetic that caps the stack and the
    /// delegate that draws it are reading one number.
    ///
    /// **The cell's density is arithmetic, and it was one pixel out.** At
    /// 1180x760 a month row is 113px. The pass before this spent 24 on the
    /// numeral band and 21+2 per chip, which asks for 24 + 3*23 + 21 = 114 to
    /// show three chips and a "+N more" line — one pixel more than the row
    /// has — so every busy cell in the fixture dropped to two chips and hid
    /// the rest. A month view that can only ever show two events is a month
    /// view the reader has to click to use.
    ///
    /// The row the pixel came out of is the **"+N more" line**, and it was
    /// being charged as a chip. It is one line of 11pt text, not an event: at
    /// 16 it costs five pixels less than a chip, which is exactly what the
    /// spec's 21px chip needs to keep three events *and* the affordance in a
    /// 113px row — 26 + 3*21 + 2*2 + 2 + 16 = 111. So the chip is the spec's
    /// 21, and `MonthPolicy.cellCapacity` answers with both numbers (`full`
    /// when nothing is hidden, `withMore` when the line is drawn) rather than
    /// one number that has to be right for both cases.
    readonly property int chipH: 21
    readonly property int chipGap: 2

    /// The affordance's own row. See above: it is text, not a chip.
    readonly property int moreH: 16

    /// The room the day numeral takes above the first chip, and the shape of
    /// today's mark inside that room.
    ///
    /// **Today is a pill sized to its glyphs, not a fixed disc.** A 22px circle
    /// leaves 3px of air around "18" — the review called it cramped, and it was
    /// cramped by a *different* amount on the 8th, because one date fills a
    /// circle and the other does not. `numeralPadH` either side is one constant
    /// that reads the same on every day of the month, and the mark stays the
    /// grid's primary "today": at 20 tall it is still the tallest solid colour
    /// in the header band, and the mini-month's is 20 in a 30px cell so the two
    /// calendars agree.
    ///
    /// `numeralRadius` is a rounded rectangle rather than a full round, which is
    /// what lets the shape stay compact on a two-digit date without either
    /// stretching into a lozenge or clipping its own digits.
    readonly property int numeralD: 22
    readonly property int numeralH: 20
    readonly property int numeralPadH: 5
    readonly property int numeralRadius: 5
    readonly property int numeralTop: 4
    readonly property int numeralClearance: 6
    readonly property int cellHeaderH: 26

    /// The month names the numeral asks for when a cell is the 1st. Resolved
    /// once here rather than per cell: `numeralLabel` would otherwise build a
    /// twelve-entry locale table 42 times a repaint.
    readonly property var monthNames: Array.from(
        { "length": 12 },
        (_, i) => Qt.locale().standaloneMonthName(i, Locale.LongFormat))

    /// What a neighbouring month's chips keep. **0.8, not 0.45.** The ground
    /// under them has already moved 17 units of green; an opacity deep enough
    /// to say "another month" a second time walked the chip's own ink to
    /// 3.6:1 against its own fill, which breaks the spec's contrast promise on
    /// events that are perfectly real — they just belong to September. At 0.8
    /// the worst hue measures 4.7:1 and the cell still reads as outside.
    ///
    /// **It carries more weight now than it did**, because the ground no longer
    /// says anything about the month boundary (see the cell-ground section) —
    /// so it steps to 0.72, which is as far as it can go before the weakest hue
    /// on the weekend ground drops under the spec's 4.5:1. The rest of the cue
    /// is the numeral, which is a whole colour apart rather than an opacity.
    readonly property real outsideOpacity: 0.72

    /// Breathing room at the bottom of a cell. Zero: the chip stack already
    /// stops 1px above the row edge by arithmetic, and a foot on top of that
    /// is the pixel that costs the third chip.
    readonly property int cellFootH: 0

    /// **One left edge for the whole cell.** The numeral, the today disc, the
    /// banner bars, the chips and the "+N more" row all start here, and the
    /// text inside a chip or a banner starts one `pad` further in — one rule
    /// for the cell and one for its labels, and no third. Measured: an earlier
    /// pass had the banner at cell+2, a chip's dot at cell+12 and the "+N more"
    /// at cell+22, which is a ragged stack at a glance.
    ///
    /// It is also the gutter every banner keeps at both of its ends, so no bar
    /// ever touches a rule or the window frame (`MonthPolicy.barSpan`).
    readonly property int contentInset: Theme.space2


    // --- the cell ground: two tones, and only two ---------------------------------
    //
    // **The ground channel carries one cue, and it is the weekend.** Three passes
    // running, this grid painted four different tones on one axis — weekday-in,
    // weekend-in, weekday-out, weekend-out — and each pass re-derived the
    // magnitudes to keep the two cues from being mistaken for each other. The
    // arithmetic got better every time and the picture did not, because the
    // premise was wrong: four flat tones across 42 large rectangles is a
    // *pattern*, and the eye reads the pattern before it reads any one step in
    // it. The trailing row checkering dark/light mid-week was not a magnitude
    // bug. It was the fourth tone existing.
    //
    // The reference paints two: weekend columns a shade below weekday columns,
    // and nothing else. Its leading and trailing days sit on exactly the ground
    // their column gives them, and the month boundary is said entirely in ink —
    // a muted numeral and receded events. That works because *ink is the
    // stronger channel here anyway*: a numeral and three chips changing value
    // is a bigger signal than 17 units of grey under them, and it lands where
    // the reader is already looking.
    //
    // So: one sink, one axis, no interaction to order.
    //
    //     weekday      surfaceRaised                        g 38
    //     weekend      surfaceRaised sunk 28%               g 30   Δ 8
    //     grid rule    borderSubtle                         g 56
    //
    // The weekend *recedes*, which is what a weekend is: the brief asks for the
    // week's shape to be readable peripherally, and a receding Saturday says
    // "quiet" where a lifted one said "look here".
    //
    // **Today gets no wash at all.** Its mark is the pill behind the numeral,
    // and a third ground tone would be a second answer to a question already
    // answered — which is how this section acquired its fourth tone the first
    // time.
    //
    // Light mode walks the same step downward from paper; `surfaceRaised` there
    // is pure white and `bgSunken` the bottom of the token set, so the one mix
    // lands in the same relative place.
    readonly property color cellWeekday: Theme.surfaceRaised

    readonly property real weekendSink: 0.28

    /// One opaque colour per cell rather than a stack of translucent layers —
    /// stacked washes are what let a Saturday out-shout today two passes ago.
    /// `inMonth` is still in the signature and still ignored: the month
    /// boundary is an ink cue (`numeralOutside`, `outsideOpacity`), and a caller
    /// that hands both facts in should not have to know which of them the ground
    /// spends.
    function cellGround(inMonth: bool, isWeekend: bool): color {
        return isWeekend
            ? Qt.tint(view.cellWeekday, Qt.alpha(Theme.bgSunken, view.weekendSink))
            : view.cellWeekday;
    }

    /// A neighbouring month's date: `textMuted` at full strength, not
    /// `textPrimary` behind an opacity. Measured on the sunk grounds it is
    /// 5.4:1 and 5.6:1 — legible, plainly quieter than the 13:1 an in-month
    /// numeral has, and, because it is one colour rather than an opacity that
    /// composites differently on every ground, it means one thing everywhere.
    readonly property color numeralOutside: Theme.textMuted

    /// The grid lines. `borderSubtle` at full strength: 18/255 over the weekday
    /// rung, which is the same order as the weekday→weekend step, so the rule
    /// draws the grid without becoming the loudest thing in it.
    readonly property color ruleColor: Theme.borderSubtle

    readonly property real rowH: view.policy.rows > 0
        ? Math.max(0, (view.height - view.headingH) / view.policy.rows) : 0
    readonly property real columnW: view.policy.columns > 0
        ? view.width / view.policy.columns : 0

    /// **One edge table, shared by everything that draws a column.** A cell's
    /// fill, its rule, its numeral and its chips all read the same two numbers,
    /// so a cell ends exactly where its neighbour begins — no seam, no
    /// double-covered pixel, and no rule that measures 2px in one column and
    /// 1px in the next because `index * columnW` landed either side of a half.
    ///
    /// The snap is to whole *logical* pixels and deliberately not to device
    /// ones: `Screen.devicePixelRatio` cannot be trusted here — it reports 2 on
    /// the 1.5-scale display this shell is captured on, the same lie
    /// `Widgets/Icon.qml` and the capture harness both document — so snapping
    /// "to the device grid" with it would land every edge on a half pixel and
    /// make the problem worse. Under a fractional output scale a 1px hairline
    /// still rasterises to one or two device pixels — measured 1,1,2,1,1 across
    /// the horizontals at 1.5x. What makes that survivable is `ruleColor`,
    /// which at 1.14:1 against the cell it sits on carries too little weight
    /// for the extra pixel to read as a heavier line.
    readonly property real dpr: 1

    readonly property var colEdges: {
        const out = [];
        const d = view.dpr;
        const w = view.columnW;
        for (let i = 0; i <= view.policy.columns; i++)
            out.push(Math.round(i * w * d) / d);
        return out;
    }

    readonly property var rowEdges: {
        const out = [];
        const d = view.dpr;
        const h = view.rowH;
        for (let i = 0; i <= view.policy.rows; i++)
            out.push(Math.round(i * h * d) / d);
        return out;
    }

    /// One device pixel where there is more than one to spend, and never less
    /// than a logical pixel's worth of coverage — a rule thinner than the
    /// device grid is a rule that renders at a different strength per column.
    readonly property real ruleW: Math.max(1, Math.round(view.dpr)) / view.dpr

    readonly property var headings: view.format.weekdayHeadings(view.firstDay)

    /// Which header columns are weekend columns — asked of the policy, not
    /// worked out here, so the header and the cells cannot disagree.
    readonly property var weekendColumns: view.policy.weekendColumns(view.firstDay)

    /// Everything the delegates draw, computed once per change and handed out
    /// by index. One binding rather than a policy call inside each of 42 cells:
    /// `spans` is a per-row question and asking it in a cell would ask it seven
    /// times for one answer.
    readonly property var rowModels: {
        const grid = view.policy.grid(view.anchorDate, view.firstDay, view.todayIso);
        const out = [];
        // What the row above hands down: the lane each bar that ran off its
        // right edge was in. A bar that crosses the week wrap holds its lane,
        // so the eye can follow one horizontal thread across the break.
        let hints = ({});
        for (let r = 0; r < grid.length; r++) {
            const week = grid[r];
            const rowStart = week.length > 0 ? week[0].iso : "";
            const segments = view.policy.spans(view.events, rowStart, hints);
            hints = view.policy.laneHintsOf(segments);
            const lanes = view.policy.laneCount(segments);
            const cells = [];
            for (let c = 0; c < week.length; c++) {
                const day = week[c];
                // Per column, not per row: a Monday with no bar over it keeps
                // its own height. `laneDepthAt` states why.
                const depth = view.policy.laneDepthAt(segments, c);
                const capacity = view.policy.cellCapacity(
                    view.rowH - view.cellFootH, depth,
                    view.chipH, view.cellHeaderH, view.chipGap, view.chipH, view.moreH);
                const chips = view.policy.cellChipsFor(view.events, day.iso, capacity);
                cells.push({
                    "iso": day.iso,
                    "day": day.day,
                    "inMonth": day.inMonth,
                    "isToday": day.isToday,
                    "isWeekend": day.isWeekend,
                    "laneDepth": depth,
                    "shown": chips.shown,
                    "moreCount": chips.moreCount
                });
            }
            out.push({
                "rowStart": rowStart,
                "segments": segments,
                "lanes": lanes,
                "cells": cells
            });
        }
        return out;
    }

    /// The event behind a span segment. `spans` carries ids rather than events
    /// so the policy never has to copy an event body around; this is the one
    /// place the id is turned back.
    function eventById(id: string): var {
        return view.policy.events.byId(view.events || [], id);
    }

    // --- the weekday header ----------------------------------------------------

    Item {
        id: heading

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: view.headingH

        /// **The band is grid, not chrome.** It was previously transparent,
        /// which let the window's `bgBase` through — so the caps read as the
        /// bottom of the toolbar and the grid appeared to start a row late.
        /// Painting it on the same rung the weekday cells use puts it on the
        /// grid's own ground, and the toolbar's `bgBase` above it is then a
        /// 22/255 step that separates the two without a second rule.
        Rectangle {
            anchors.fill: parent
            color: view.cellWeekday
        }

        Repeater {
            model: view.headings

            delegate: Item {
                id: cap

                required property int index
                required property string modelData

                readonly property bool isWeekend: view.weekendColumns.length > cap.index
                    ? view.weekendColumns[cap.index] : false

                // Snapped to whole pixels the same way the cells are, so a cap
                // sits over its own column and not half over the next one.
                x: view.colEdges[cap.index]
                width: view.colEdges[cap.index + 1] - view.colEdges[cap.index]
                height: heading.height

                Text {
                    /// **Centred over the column.** It was left-aligned on the
                    /// cell's content inset, which was right while the dates
                    /// were on that inset too — the header and the first line
                    /// of every cell shared one rule. The dates have moved to
                    /// the right edge, so a left-aligned cap now sits over
                    /// nothing in particular: it agrees with the events and
                    /// disagrees with the date it names. Centred, it belongs to
                    /// the whole column rather than to either edge of it, which
                    /// is what a column heading is, and it is what the reference
                    /// does.
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    text: cap.modelData
                    /// Every cap the same weight. The weekend is said once, by
                    /// the ground of the column beneath — a second, fainter
                    /// version of it up here was the header disagreeing with
                    /// itself about how much a Saturday matters.
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(Theme.capsSize)
                    font.weight: Theme.weightMedium
                    font.letterSpacing: Theme.capsTrackingEm * Theme.pt(Theme.capsSize)
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: view.ruleW
            color: view.ruleColor
        }
    }

    // --- the grid --------------------------------------------------------------

    Item {
        id: grid

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: heading.bottom
        anchors.bottom: parent.bottom
        clip: true

        Repeater {
            model: view.policy.rows

            delegate: Item {
                id: row

                required property int index

                readonly property var rowData: view.rowModels.length > row.index
                    ? view.rowModels[row.index] : null
                readonly property var cells: row.rowData ? row.rowData.cells : []
                readonly property var segments: row.rowData ? row.rowData.segments : []

                /// Where a cell's chips begin: under the numeral, and under the
                /// banner lanes that cross *that* column. A row-wide reservation
                /// charged a bar-free Monday for a Wednesday conference and left
                /// it no room for its own events — `MonthPolicy.laneDepthAt`
                /// carries the measurement.
                function chipTop(depth: int): real {
                    return view.cellHeaderH + depth * (view.chipH + view.chipGap);
                }

                // Whole-pixel rows, and each row ends exactly where the next
                // one begins. A fractional `rowH` used directly gave a grid
                // whose 1px rules measured 1px and 2px alternately — the eye
                // reads that as a heavy/light rhythm the design never asked
                // for.
                x: 0
                y: view.rowEdges[row.index]
                width: grid.width
                height: view.rowEdges[row.index + 1] - view.rowEdges[row.index]

                // --- cell washes, one layer under everything ------------------
                //
                // Two cues, in the order the eye should read them: the month
                // boundary as a fill, and the weekend as a wash on top of
                // whichever fill the cell already has.

                Repeater {
                    model: row.cells.length

                    delegate: Item {
                        id: wash

                        required property int index

                        readonly property var cell: row.cells[index]

                        x: view.colEdges[wash.index]
                        width: view.colEdges[wash.index + 1] - view.colEdges[wash.index]
                        height: row.height

                        /// **One rectangle, one colour, four possible values.**
                        /// The ground is where both of the grid's quiet cues
                        /// live — in/out of month and weekday/weekend — and
                        /// `cellGround` composites them into a single opaque
                        /// colour so nothing is ever painted twice. Today is
                        /// still a disc and not a ground: a wash that answered
                        /// "which day is it" would be a third cue competing
                        /// with the mark that already answers it.
                        Rectangle {
                            anchors.fill: parent
                            color: wash.cell
                                ? view.cellGround(wash.cell.inMonth, wash.cell.isWeekend)
                                : view.cellWeekday
                        }
                    }
                }

                // --- rules ----------------------------------------------------

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: view.ruleW
                    color: view.ruleColor
                    visible: row.index > 0
                }

                Repeater {
                    model: view.policy.columns

                    delegate: Rectangle {
                        id: rule

                        required property int index

                        // Snapped, for the reason the row is: an unrounded x
                        // spreads a 1px rule over two device columns and the
                        // seven verticals stop matching each other.
                        x: view.colEdges[rule.index]
                        width: view.ruleW
                        height: row.height
                        color: view.ruleColor
                        visible: rule.index > 0
                    }
                }


                // --- the day numerals -----------------------------------------

                Repeater {
                    model: row.cells.length

                    delegate: Item {
                        id: numeral

                        required property int index

                        readonly property var cell: row.cells[index]

                        /// `"18"`, or `"September 1"` where the month turns —
                        /// `MonthPolicy.numeralLabel`. A six-row grid always
                        /// shows three months and the title band names one of
                        /// them; naming the other two exactly where they start
                        /// costs one cell's width and settles all six rows.
                        readonly property string label:
                            view.policy.numeralLabel(numeral.cell, view.monthNames)

                        /// **The date sits at the top right, and the events own
                        /// the left.** The pass before this put the numeral at
                        /// the head of the same column the chips stand in, so
                        /// the top line of every cell was a date where the six
                        /// lines under it were titles, and a cell's list began
                        /// one row lower than it looked. Moved across, the whole
                        /// left edge belongs to events — a cell reads straight
                        /// down as a list — and the dates become their own
                        /// column down the right of each week, which is what
                        /// makes a week's row scannable. The reference does
                        /// this, and it is the reason its grid reads as a
                        /// calendar rather than as a table of labels.
                        x: view.colEdges[numeral.index]
                        y: view.numeralTop
                        width: view.colEdges[numeral.index + 1] - view.colEdges[numeral.index]
                        height: view.numeralD

                        /// Today is a filled pill in the accent with the numeral
                        /// knocked out of it — the same statement the week
                        /// header and the mini-month make, so one calendar
                        /// answers "which day is it" one way.
                        ///
                        /// **Sized to its own glyphs, not to a fixed circle.**
                        /// A 22px disc is 3px of air around a two-digit date:
                        /// the review called it cramped and it was, and worse,
                        /// it was cramped by a different amount on the 8th than
                        /// on the 18th because only one of them fills a circle.
                        /// A pill with a constant `numeralPadH` either side is
                        /// the same shape on both, and the digits stay on the
                        /// column the other dates are in.
                        Rectangle {
                            width: dayText.implicitWidth + 2 * view.numeralPadH
                            height: view.numeralH
                            anchors.horizontalCenter: dayText.horizontalCenter
                            anchors.verticalCenter: dayText.verticalCenter
                            radius: view.numeralRadius
                            color: Theme.accentPrimary
                            visible: numeral.cell ? numeral.cell.isToday : false
                        }

                        Text {
                            id: dayText

                            /// **The pill is what lines up, not the digits.**
                            /// Today's numeral steps in by its own padding so
                            /// the mark's right edge lands on the same rule
                            /// every other date's does — otherwise the one cell
                            /// the eye is looking for is the one whose marker
                            /// hangs 5px closer to the grid line than the rest.
                            anchors.right: parent.right
                            anchors.rightMargin: view.contentInset
                                + (numeral.cell && numeral.cell.isToday ? view.numeralPadH : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            text: numeral.label
                            /// **Today, in the month, or out of it — and a
                            /// weekend is none of those.** Saturday's date is
                            /// a Tuesday's date; the weekend lives in the
                            /// ground (see `weekendSink`), so this ink carries
                            /// exactly one meaning and no two states share a
                            /// value.
                            color: !numeral.cell ? Theme.textSecondary
                                 : numeral.cell.isToday ? Theme.bgBase
                                 : numeral.cell.inMonth ? Theme.textPrimary
                                 : view.numeralOutside
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12.5)
                            font.weight: Theme.weightMedium
                            /// **Greyscale antialiasing.** The default
                            /// subpixel pass fringes a 12.5pt numeral red and
                            /// cyan on this ground, and at 1.5x output scale
                            /// those fringes land on whole device pixels — a
                            /// date that reads as slightly coloured on a grid
                            /// where colour is the event channel.
                            renderType: Text.NativeRendering
                        }
                    }
                }

                // --- the banner bars, laid across the cells --------------------

                Repeater {
                    model: row.segments.length

                    delegate: MonthChip {
                        id: bar

                        required property int index

                        // Read out of the row's own array by index rather than
                        // through `modelData`: two months whose rows carry the
                        // same number of bars are a model of unchanged length,
                        // and such a model rebuilds no delegates (#195).
                        readonly property var segment: row.segments[index]
                        readonly property var source: bar.segment
                            ? view.eventById(bar.segment.id) : null

                        // **A week wrap is one bar cut in two, and the cut is
                        // drawn rather than implied.** Both halves keep the
                        // cell's gutter — the same one the chips below them
                        // keep — because a bar run flush into the grid line
                        // reads as sliding under the next cell, and in the last
                        // column it runs into the *window frame*, the one line
                        // in the picture that is not the grid. What says
                        // "continued" is the pair of marks `MonthPolicy.barCaps`
                        // states: a squared cap where the row cut it, a chevron
                        // pointing the way it went on the sending half, and no
                        // time on the receiving one.
                        //
                        // **The cut end runs flush into the rule; the text does
                        // not move.** The receiving half kept the cell's inset
                        // for a pass and was measured indistinguishable from a
                        // fresh one-day event — same left edge, same rounding
                        // at 4px on a 21px bar, and a repeated title. A bar
                        // that touches the grid line has visibly not ended
                        // there. `leadPad` then gives the *label* back the
                        // gutter the body gave up, so the title still stands on
                        // the one text rule the numeral and the chips below it
                        // share, and only the colour crosses the line.
                        readonly property var geometry: view.policy.barSpan(
                            bar.segment, view.colEdges, view.contentInset)

                        leadPad: (bar.segment && bar.segment.continuesLeft)
                            ? view.contentInset : 0

                        x: bar.geometry.x
                        y: view.cellHeaderH + (bar.segment ? bar.segment.lane : 0)
                           * (view.chipH + view.chipGap)
                        width: bar.geometry.width
                        height: view.chipH

                        visible: !!bar.source

                        /// **One unbroken pill between its true ends.** The
                        /// pass before this had the bar crease itself at every
                        /// column edge it crossed, so that the grid still read
                        /// through it; the review measured those creases as
                        /// ~3px dark gaps and a three-day event as a dashed row
                        /// of slabs. Which days a banner covers is already said
                        /// by the numerals it runs under, and a continuous run
                        /// is the only shape that says "one event" at a glance.

                        event: bar.source
                        hue: CalendarTokens.hues.forEvent(bar.source)
                        policy: view.policy
                        banner: true
                        past: view.policy.isPast(bar.source, view.nowBound)
                        continuesLeft: bar.segment ? bar.segment.continuesLeft : false
                        continuesRight: bar.segment ? bar.segment.continuesRight : false
                        selected: bar.segment ? view.selectedId === bar.segment.id : false
                        use24: view.use24
                        format: view.format

                        onActivated: if (bar.segment) view.eventActivated(bar.segment.id)
                    }
                }

                // --- the chips, and what did not fit --------------------------

                Repeater {
                    model: row.cells.length

                    delegate: Item {
                        id: stack

                        required property int index

                        readonly property var cell: row.cells[index]
                        readonly property var shown: stack.cell ? stack.cell.shown : []
                        readonly property int moreCount: stack.cell ? stack.cell.moreCount : 0

                        // The same inset as the numeral above and the banners
                        // beside: one left edge per cell.
                        readonly property real stackTop: row.chipTop(
                            stack.cell ? stack.cell.laneDepth : 0)

                        x: view.colEdges[stack.index] + view.contentInset
                        y: stack.stackTop
                        width: Math.max(0, view.colEdges[stack.index + 1]
                                           - view.colEdges[stack.index]
                                           - 2 * view.contentInset)
                        height: Math.max(0, row.height - stack.stackTop)

                        // A neighbouring month's events still happened, and a
                        // cell that hid them would be lying about the row it is
                        // in. They recede with the numeral above them instead.
                        opacity: stack.cell && !stack.cell.inMonth
                            ? view.outsideOpacity : 1

                        Column {
                            width: parent.width
                            spacing: view.chipGap

                            Repeater {
                                model: stack.shown.length

                                delegate: MonthChip {
                                    id: chipItem

                                    required property int index

                                    readonly property var source: stack.shown[index]

                                    width: stack.width
                                    height: view.chipH
                                    visible: !!chipItem.source

                                    event: chipItem.source
                                    hue: CalendarTokens.hues.forEvent(chipItem.source)
                                    policy: view.policy
                                    past: view.policy.isPast(chipItem.source, view.nowBound)
                                    selected: chipItem.source
                                        ? view.selectedId === chipItem.source.id : false
                                    use24: view.use24
                                    format: view.format

                                    onActivated: if (chipItem.source) view.eventActivated(chipItem.source.id)
                                }
                            }

                            /// What the cell could not fit. A row of its own,
                            /// which is why `cellChips` gives up a chip to make
                            /// room for it rather than letting it hang below the
                            /// cell.
                            Item {
                                width: stack.width
                                height: view.moreH
                                visible: stack.moreCount > 0

                                Text {
                                    anchors.left: parent.left
                                    // Flush with the chip bodies above it and
                                    // the numeral above them — the cell has one
                                    // left edge and this row is on it. The pass
                                    // before this indented it to where chip
                                    // *titles* began, which measured 87px into
                                    // a cell whose content starts at 13 and
                                    // read as a caption floating mid-cell.
                                    anchors.leftMargin: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    /// **`"2 more"`, not `"+2 more"`.** The
                                    /// wording is `MonthPolicy.moreLabel`: the
                                    /// row is a sentence about the cell, and
                                    /// the one `+` in this surface already
                                    /// means *create* on the toolbar.
                                    text: view.policy.moreLabel(stack.moreCount)
                                    color: Theme.textSecondary
                                    font.family: Theme.fontUi
                                    font.pointSize: Theme.pt(11)
                                    font.weight: Theme.weightMedium
                                    font.underline: moreArea.containsMouse
                                }

                                MouseArea {
                                    id: moreArea

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: view.moreActivated(stack.cell ? stack.cell.iso : "")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// **The grid has four sides.** Only the internal rules were drawn before,
    /// so Saturday ran off the right edge of the window with nothing closing it
    /// and the last row sat on bare background — the grid read as a fragment of
    /// a larger table scrolled out of view. This is the outer frame, drawn last
    /// and over everything, so the header band and the grid are one object.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: view.ruleW
        border.color: view.ruleColor
        z: 6
    }
}
