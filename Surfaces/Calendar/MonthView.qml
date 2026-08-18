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

    /// The room the day numeral takes above the first chip, and where its disc
    /// starts inside that room. **6px of clearance from the vertical rule**: a
    /// disc pinned 2px off the grid line read as a sticker half off the cell,
    /// and the clearance is what makes it sit *in* the square.
    ///
    /// The disc is the spec's **22**, and it is the grid's primary "today", so
    /// nothing secondary may outrank it: the sidebar's mini-month drew a 26px
    /// disc in a 30px cell, which measured 1.4x the mark in a cell seven times
    /// the size — the weaker marker was the louder one. The mini-month's is now
    /// 20 and this one is 22. 4 + 22 = 26, the numeral band.
    readonly property int numeralD: 22
    readonly property int numeralTop: 4
    readonly property int numeralClearance: 6
    readonly property int cellHeaderH: 26

    /// What a neighbouring month's chips keep. **0.8, not 0.45.** The ground
    /// under them has already moved 17 units of green; an opacity deep enough
    /// to say "another month" a second time walked the chip's own ink to
    /// 3.6:1 against its own fill, which breaks the spec's contrast promise on
    /// events that are perfectly real — they just belong to September. At 0.8
    /// the worst hue measures 4.7:1 and the cell still reads as outside.
    readonly property real outsideOpacity: 0.8

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


    // --- the cell ladder --------------------------------------------------------
    //
    // **Two cues, and they are not the same cue.** Weekday/weekend is a *fill*
    // and runs the full height of a column; in/out of month is a *recede* and
    // applies to whichever fill the cell already had. Collapsing both onto one
    // four-rung ladder is what the pass before this did, and the review
    // measured the result: out-of-month landed on `bgSunken` at g 10, darker
    // than every in-month cell by 17, so the leading row read as a hole punched
    // in the surface rather than a month falling away — and the trailing row
    // checkered dark/light mid-week where the two cues crossed.
    //
    // So (green channel, dark palette, where the eye's response is steepest):
    //
    // **And the two cues have to be ordered.** The pass before this had them
    // the wrong way round, measured off the capture (green channel, dark
    // palette): weekday-in 38, weekend-in 21, out-of-month-weekday 30. A
    // Saturday inside the month was 17 steps from its neighbour and the *month
    // boundary* only 8 — so the grid's loudest edge ran down two columns that
    // are merely quiet, and the edge that actually matters, where August stops,
    // was the faintest thing in the picture.
    //
    // The invariant, and it is checkable off any capture:
    //
    //     |weekend − weekday|  <  |out-of-month − weekday|
    //
    // **And both steps have to clear the threshold at which a step is a step.**
    // The pass before this had the ordering right and the magnitudes far too
    // small — measured off the capture, in-month weekday g 38, weekend g 32,
    // out-of-month g 25: four states spread over 13 units of 255, ~6 apart, on
    // large flat areas seen peripherally. Neither cue read, and each could be
    // mistaken for the other. So the weekend wash goes to 34% and the month sink
    // to 72%, which roughly doubles both gaps and holds the 1:2 ratio between
    // them:
    //
    //     weekday, in      surfaceRaised                        g 38
    //     weekend, in      surfaceRaised sunk 34%               g 28   Δ 10
    //     weekday, out     the same, sunk 72%                   g 17   Δ 21
    //     weekend, out     both                                 g 14
    //     grid rule        borderSubtle                         g 56
    //
    // The weekend *recedes*, which is what a weekend is: the brief asks for the
    // week's shape to be readable peripherally, and a receding Saturday says
    // "quiet" where a lifted one said "look here". Out of month the ground
    // moves twice as far, and the numerals' and chips' 45% opacity carries the
    // rest.
    //
    // **Today's wash is 2.2% and no more.** The mark is the filled circle
    // behind the numeral; an earlier pass tinted the whole cell hard enough to
    // measure (43,65,62), a hue shift rather than a lift, and today's square
    // was the one ground in the grid that was a different colour. 2.2% lifts
    // the green channel by 3 where the weekend drops it by 6, so the faintest
    // thing in the grid stays the faintest — it just stops the circle looking
    // stuck to an ordinary Tuesday.
    //
    // Light mode walks the same ladder downward from paper; `surfaceRaised`
    // there is pure white and `bgSunken` is the bottom of the token set, so the
    // same two mixes land in the same relative places.
    readonly property color cellWeekday: Theme.surfaceRaised

    /// **Two cues, two channels, and neither may borrow the other's.** The pass
    /// before this moved the weekend off the ground and onto the numeral, which
    /// collided head-on with the one cue that was already a numeral: measured
    /// on the capture, an in-month Saturday's date (125,143,134) and an
    /// out-of-month Thursday's (113,119,115) were the same grey saying two
    /// different things, and an out-of-month *weekend* stacked both dimmings
    /// onto one glyph and landed at 2.6:1 — below any reading threshold. The
    /// reference never dims a weekend numeral, for exactly this reason.
    ///
    /// So the channels are separated by construction and each says one thing:
    ///
    ///     weekend        ground only    — a sink of 28% toward `bgSunken`
    ///     out of month   ground + ink   — a sink of 62%, and a muted numeral
    ///
    /// A weekend's date is `textPrimary`, identical to a Tuesday's, because a
    /// Saturday in this month is exactly as real as a Tuesday in it. The four
    /// grounds, green channel, dark palette:
    ///
    ///     weekday, in      surfaceRaised                        g 38
    ///     weekend, in      sunk 28%                             g 30   Δ  8
    ///     weekday, out     sunk 62%                             g 21   Δ 17
    ///     weekend, out     sunk 75%                             g 17
    ///
    /// which keeps the invariant the month boundary has to win:
    ///
    ///     |weekend − weekday|  <  |out-of-month − weekday|
    ///
    /// Light mode walks the same ladder downward from paper; `surfaceRaised`
    /// there is pure white and `bgSunken` the bottom of the token set, so the
    /// same four mixes land in the same relative places.
    readonly property real weekendSink: 0.28
    readonly property real monthSink: 0.62
    readonly property real bothSink: 0.75

    /// One opaque colour per cell rather than a stack of translucent layers —
    /// stacked washes are what let a Saturday out-shout today two passes ago,
    /// and what made the out-of-month weekend unreadable in the last one.
    function cellGround(inMonth: bool, isWeekend: bool): color {
        const sink = inMonth ? (isWeekend ? view.weekendSink : 0)
                             : (isWeekend ? view.bothSink : view.monthSink);
        return sink > 0 ? Qt.tint(view.cellWeekday, Qt.alpha(Theme.bgSunken, sink))
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
                    // Left-aligned on the cell's own content inset, with every
                    // numeral, banner and chip below it. Centred caps over
                    // left-aligned content was the header reading as a separate
                    // object from the grid.
                    x: view.contentInset
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

                        // The *glyph* starts on the content inset, not the
                        // circle around it: the numeral is the top of the same
                        // column the chips make, and a box centred on the inset
                        // would push the digits 4px right of everything under
                        // them.
                        x: view.colEdges[numeral.index] + view.contentInset
                        y: view.numeralTop
                        width: view.numeralD
                        height: view.numeralD

                        /// Today is a filled circle in the accent, with the
                        /// numeral knocked out of it — the same mark the week
                        /// header and the mini-month make, so one calendar
                        /// answers "which day is it" one way.
                        ///
                        /// **Its left edge is the numeral rule.** Centring the
                        /// disc on the digits was measured to move it: 3px
                        /// right on a two-digit day and hard against the
                        /// vertical rule on a one-digit one, so today's mark
                        /// landed in a different place depending on the date,
                        /// and on the 1st it sat closer to the grid line than
                        /// anything else in the cell. Pinned to the same rule
                        /// every other numeral starts on, it is 8px clear of
                        /// the rule (`contentInset`, above the 6px floor) on
                        /// every day of the month, and the column of dates
                        /// down the left of the grid stays a column.
                        Rectangle {
                            x: 0
                            width: view.numeralD
                            height: view.numeralD
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.radiusFull
                            color: Theme.accentPrimary
                            visible: numeral.cell ? numeral.cell.isToday : false
                        }

                        Text {
                            id: dayText

                            /// Knocked out of the disc means centred in it;
                            /// every other numeral sits on the rule the disc's
                            /// left edge is on.
                            x: numeral.cell && numeral.cell.isToday
                                ? (view.numeralD - dayText.implicitWidth) / 2 : 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: numeral.cell ? numeral.cell.day : ""
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
                                    text: "+" + stack.moreCount + " more"
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
