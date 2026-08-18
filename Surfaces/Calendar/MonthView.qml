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
    /// 21 and 2, the visual spec's numbers. An earlier pass shaved the chip to
    /// 20 to buy back a line in the rows that carry a banner lane; the review
    /// read that back off the capture as the one place the month grid did not
    /// match its own spec, and a line bought by breaking the shared metric is
    /// not worth the line.
    readonly property int chipH: 21
    readonly property int chipGap: 2

    /// The room the day numeral takes above the first chip: the 21px today
    /// circle, its 2px inset, and 1px of air under it. Sized off the circle
    /// because the circle is the tallest thing in the row — a header measured
    /// off the numeral alone puts the first banner through today's mark.
    readonly property int numeralD: 21
    readonly property int cellHeaderH: 24

    /// Breathing room at the bottom of a cell, so the last chip never sits on
    /// the grid line under it.
    readonly property int cellFootH: 2

    /// **One left edge for the whole cell.** The numeral, the banner bars, the
    /// chips and the "+N more" row all start here, and the chips' text column
    /// starts one dot-plus-gap further in — which is also where a banner's own
    /// label starts, so a cell reads as two columns and not five. Measured: the
    /// previous pass had the banner at cell+2, the chip dot at cell+12 and the
    /// "+N more" at cell+22, which is a ragged stack at a glance.
    readonly property int contentInset: Theme.space2

    /// The hue dot the chip carries. Handed down rather than left to the
    /// chip's default so the grid owns every metric that repeats 42 times.
    ///
    /// **There is no title column, and that is the point.** A previous pass
    /// gave the time a fixed slot measured off the widest string the formatter
    /// can produce and right-aligned the digits inside it, so that every title
    /// in a stack began at one x. Measured off the capture, that slot opened a
    /// 42px void between the dot and the time on every short time — 22% of a
    /// 194px cell spent on nothing — and elided four of six titles at widths
    /// where the reference fits them whole. The chips already share a left
    /// edge, because their bodies do; buying a second alignment with the
    /// title's own width is the wrong trade at this size.
    readonly property int chipDotD: 6

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
    //     weekday, in      surfaceRaised                        g 38
    //     weekday, out     the same, sunk 28%                   g 30
    //     weekend, in      surfaceRaised sunk 60%               g 21
    //     weekend, out     the same, sunk 28%                   g 18
    //     grid rule        borderSubtle                         g 56
    //
    // The weekday→weekend step is 17 and the rule now clears its cell by 18 —
    // comparable, where before the rule was `borderSubtle` lightened 35% (g 76,
    // a 38 step) and so shouted down a weekend delta of 11. A rule louder than
    // every wash in the grid is a rule the eye reads instead of the shape.
    //
    // The weekend *recedes*, which is what a weekend is: the brief asks for the
    // week's shape to be readable peripherally, and a receding Saturday says
    // "quiet" where a lifted one said "look here". Out of month, the fill moves
    // one small step and the numeral's 40% opacity and the chips' 55% carry the
    // rest — the boundary is a change in *weight*, not a change in ground.
    //
    // **Today wears no wash at all.** The spec asks for one mark on today, a
    // 22px filled circle behind the numeral, and a previous pass added a cell
    // tint on top of it that measured (43,65,62) — a teal shift, not a lift, so
    // today's cell was the one square in the grid whose ground had a hue. The
    // circle is unambiguous and it is enough.
    //
    // Light mode walks the same ladder downward from paper; `surfaceRaised`
    // there is pure white and `bgSunken` is the bottom of the token set, so the
    // same two mixes land in the same relative places.
    readonly property color cellWeekday: Theme.surfaceRaised
    readonly property color cellWeekend: Qt.tint(Theme.surfaceRaised,
        Qt.alpha(Theme.bgSunken, 0.6))

    /// How far out of the month a cell sinks, on whichever rung it started.
    /// Applied as arithmetic rather than as a translucent layer so every cell
    /// in the grid is one opaque colour — stacked washes are what let a
    /// Saturday out-shout today in the pass before last.
    function outsideOf(base: color): color {
        return Qt.tint(base, Qt.alpha(Theme.bgSunken, 0.28));
    }

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
        for (let r = 0; r < grid.length; r++) {
            const week = grid[r];
            const rowStart = week.length > 0 ? week[0].iso : "";
            const segments = view.policy.spans(view.events, rowStart);
            const lanes = view.policy.laneCount(segments);
            const cells = [];
            for (let c = 0; c < week.length; c++) {
                const day = week[c];
                // Per column, not per row: a Monday with no bar over it keeps
                // its own height. `laneDepthAt` states why.
                const depth = view.policy.laneDepthAt(segments, c);
                const capacity = view.policy.chipCapacity(
                    view.rowH - view.cellFootH, depth,
                    view.chipH, view.cellHeaderH, view.chipGap, view.chipH);
                const chips = view.policy.cellChips(view.events, day.iso, capacity);
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
        const all = view.events || [];
        for (let i = 0; i < all.length; i++)
            if (all[i].id === id)
                return all[i];
        return null;
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

                /// The weekend cue runs *through* the header rather than
                /// starting under it, on the same rung the weekend cells take,
                /// so the header cannot disagree with its own grid about which
                /// two columns are quiet.
                Rectangle {
                    anchors.fill: parent
                    color: view.cellWeekend
                    visible: cap.isWeekend
                }

                Text {
                    // Left-aligned on the cell's own content inset, with every
                    // numeral, banner and chip below it. Centred caps over
                    // left-aligned content was the header reading as a separate
                    // object from the grid.
                    x: view.contentInset
                    anchors.verticalCenter: parent.verticalCenter
                    text: cap.modelData
                    color: Theme.textMuted
                    opacity: cap.isWeekend ? 0.75 : 1
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

                        /// **One rectangle, one colour.** The column's fill
                        /// picks the rung; the month boundary sinks it. Both
                        /// resolve to a single opaque value before anything is
                        /// painted, so no cell can be lifted by a wash that
                        /// belongs to another cue.
                        Rectangle {
                            anchors.fill: parent

                            readonly property color base: wash.cell && wash.cell.isWeekend
                                ? view.cellWeekend : view.cellWeekday

                            color: wash.cell && wash.cell.inMonth
                                ? base : view.outsideOf(base)
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
                        y: 2
                        width: view.numeralD
                        height: view.numeralD

                        /// Today is a filled circle in the accent, with the
                        /// numeral knocked out of it — the same mark the week
                        /// header and the mini-month make, so one calendar
                        /// answers "which day is it" one way. Centred on the
                        /// digits rather than on the cell, so it travels with
                        /// them.
                        Rectangle {
                            anchors.centerIn: dayText
                            width: view.numeralD
                            height: view.numeralD
                            radius: Theme.radiusFull
                            color: Theme.accentPrimary
                            visible: numeral.cell ? numeral.cell.isToday : false
                        }

                        Text {
                            id: dayText

                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.topMargin: (view.numeralD - dayText.implicitHeight) / 2
                            text: numeral.cell ? numeral.cell.day : ""
                            color: !numeral.cell ? Theme.textSecondary
                                 : numeral.cell.isToday ? Theme.bgBase
                                 : Theme.textPrimary
                            opacity: numeral.cell && !numeral.cell.inMonth
                                ? Theme.opacityInert : 1
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12.5)
                            font.weight: Theme.weightMedium
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

                        // A cut end runs flush into the row's edge — that is
                        // what says "this continues". A *true* end takes the
                        // cell's own content inset, the same one the chips and
                        // the numeral take, which does two things at once: the
                        // bars line up with the column under them, and two
                        // different events either side of a day boundary are
                        // separated by a full 16px gutter instead of the 6px
                        // nick that read as one striped bar.
                        readonly property real leftInset: bar.segment && bar.segment.continuesLeft
                            ? 0 : view.contentInset
                        readonly property real rightInset: bar.segment && bar.segment.continuesRight
                            ? 0 : view.contentInset
                        readonly property real startX: view.colEdges[
                            bar.segment ? bar.segment.startCol : 0]
                        readonly property real endX: view.colEdges[Math.min(
                            view.policy.columns,
                            (bar.segment ? bar.segment.startCol : 0)
                            + (bar.segment ? bar.segment.span : 0))]

                        x: bar.startX + bar.leftInset
                        y: view.cellHeaderH + (bar.segment ? bar.segment.lane : 0)
                           * (view.chipH + view.chipGap)
                        width: Math.max(0, bar.endX - bar.startX - bar.leftInset - bar.rightInset)
                        height: view.chipH

                        // A bar cut by the row start has no inset of its own, so
                        // it pays the inset back in text padding — its label
                        // still lands in the one text column.
                        leadPad: bar.leftInset > 0 ? 0 : view.contentInset
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
                        dotD: view.chipDotD
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
                        opacity: stack.cell && !stack.cell.inMonth ? 0.55 : 1

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
                                    dotD: view.chipDotD
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
                                height: view.chipH
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
