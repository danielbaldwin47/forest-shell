// The time grid: a run of day columns with a gutter of hours down the left.
//
// **`dayCount` is the only difference between the day view and the week view.**
// `TimeGridPolicy.dayColumns` aligns a run of seven to the locale's first
// weekday and starts any other run at the anchor itself, so `dayCount: 1` is a
// day view built from the same file, with the same chips, the same now-line and
// the same all-day band. There is no second code path to keep in step, which is
// the whole reason the count is a property rather than two components.
//
// ## What this file decides: nothing
//
// Every number here came from somewhere testable. Column edges and widths are
// `TimeGridPolicy`; where a chip sits in its column is `EventLayoutPolicy`;
// which events belong on the all-day band rather than in the grid is
// `EventLayoutPolicy.isBanded`; every label is `CalendarFormat`; every colour
// and every fixed pixel is `CalendarTokens`. What is left is anchoring, and
// anchoring is the one thing no test can check and no policy should hold.
//
// ## The three layers, and why they are not one column
//
// The column washes — weekend and today — run the **full height of the view,
// through the header, through the all-day band and behind the scrolling grid**.
// That is what makes the week's shape readable out of the corner of an eye, and
// it is why the washes are a layer of their own underneath everything rather
// than a background on each of three stacked rows. Three separately shaded rows
// would show two seams across the wash wherever the rows meet.
//
// Above them: the header and the all-day band, which do not scroll, and the
// `Flickable` grid, which does. The grid is the only clipping item — a chip at
// 23:00 has to disappear under the band rather than over it.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Core

Item {
    id: view

    /// Seven is a week, one is a day, and anything else is a run of days
    /// beginning at `anchorDate`.
    property int dayCount: 7

    /// The day the run is built around: any day in the week for `dayCount: 7`,
    /// the day itself otherwise.
    property string anchorDate: ""

    /// The locale's first weekday, `Locale.Sunday === 0`. Handed down rather
    /// than read here so the sidebar's mini-month and this grid can never
    /// disagree about where a week begins.
    property int firstDay: 1

    /// Today, as `YYYY-MM-DD`, and the wall clock as `YYYY-MM-DDTHH:MM`.
    ///
    /// Both are passed in and neither is read from a clock here. That is what
    /// makes `tools/capture-harness.sh --cal-now` produce the same picture
    /// twice: a now-line drawn from `new Date()` moves a pixel a minute, and a
    /// diff between two captures of this surface would be unreadable.
    property string todayIso: ""
    property string nowStamp: ""

    /// The events to draw — the whole store's worth. The view splits them into
    /// band and grid itself, because the split is `EventLayoutPolicy`'s rule
    /// and not the caller's.
    property var events: []

    property string selectedId: ""

    property bool use24: false

    signal eventActivated(string id)

    property TimeGridPolicy grid: TimeGridPolicy {}
    property EventLayoutPolicy layoutPolicy: EventLayoutPolicy {}
    property CalendarFormat format: CalendarFormat {}

    // --- the geometry, all of it from the policy -------------------------------

    readonly property int gutterW: CalendarTokens.gutterW
    readonly property int hourRow: CalendarTokens.hourRow

    /// A fresh array on every change, never mutated in place: a `Repeater`
    /// handed a model of the same length does not rebuild its delegates, so
    /// stepping a week with seven columns in and seven columns out would
    /// otherwise leave last week's dates on screen (measured, #195).
    readonly property var columns: view.grid.dayColumns(view.anchorDate, view.firstDay,
                                                        view.dayCount, view.todayIso)

    readonly property real columnW: view.columns.length > 0
        ? view.grid.columnWidth(view.gutterW, view.width, view.columns.length)
        : 0

    readonly property string rangeStart: view.columns.length > 0 ? view.columns[0].iso : ""

    readonly property var bandEvents: view.layoutPolicy.bandEvents(view.events)
    readonly property var gridDayEvents: view.layoutPolicy.gridEvents(view.events)

    /// The all-day band, packed into lanes. `allDayLanes` clips to a week, so a
    /// shorter run drops the columns past its own right edge here rather than
    /// asking the policy to learn a second width.
    readonly property var bandLanes: {
        if (!view.rangeStart)
            return [];
        const all = view.layoutPolicy.allDayLanes(view.bandEvents, view.rangeStart);
        const n = view.columns.length;
        const out = [];
        for (let i = 0; i < all.length; i++) {
            const span = all[i];
            if (span.startCol >= n)
                continue;
            out.push({
                "id": span.id,
                "lane": span.lane,
                "startCol": span.startCol,
                "span": Math.min(span.span, n - span.startCol),
                "continuesLeft": span.continuesLeft,
                "continuesRight": span.continuesRight || (span.startCol + span.span > n)
            });
        }
        return out;
    }

    readonly property int bandLaneCount: {
        let lanes = 0;
        for (let i = 0; i < view.bandLanes.length; i++)
            lanes = Math.max(lanes, view.bandLanes[i].lane + 1);
        return lanes;
    }

    readonly property int bandHeight: Math.max(
        CalendarTokens.allDayMinH,
        Theme.space1 * 2 + view.bandLaneCount * CalendarTokens.allDayLaneH
            + Math.max(0, view.bandLaneCount - 1) * CalendarTokens.allDayLaneGap)

    /// Where the now-line goes, and which column it belongs on. `-1` for both
    /// when the clock is outside the run — the line then draws nothing rather
    /// than parking at the top of Monday.
    readonly property real nowY: view.grid.nowLineY(view.nowStamp, view.hourRow)
    readonly property int nowColumn: {
        if (view.nowY < 0)
            return -1;
        const day = view.nowStamp.split("T")[0];
        for (let i = 0; i < view.columns.length; i++)
            if (view.columns[i].iso === day)
                return i;
        return -1;
    }
    /// The three column questions, all answered from `TimeGridPolicy`'s whole-
    /// pixel edges rather than from `columnW`. Multiplying a fractional width
    /// out per column drifted 148/150/148/149 across a week — the same design
    /// drawn four different widths — so the edges are rounded once and every
    /// x and width here is a difference between two of them.
    function columnX(index: int): real {
        const x = view.grid.xForColumn(index, view.gutterW, view.width, view.columns.length);
        return isNaN(x) ? 0 : x;
    }
    function columnWidthFor(index: int): real {
        const w = view.grid.columnWidthAt(index, view.gutterW, view.width,
                                          view.columns.length);
        return isNaN(w) ? 0 : w;
    }
    function columnRight(index: int): real {
        return view.columnX(index) + view.columnWidthFor(index);
    }

    /// One column's chips, joined from the two policies that decided them:
    /// `layout` says how the width is shared, `eventRect` says where the top
    /// and bottom edges are. Joining is all this does — every number in the
    /// result was computed on the other side of a test.
    function chipsFor(iso: string, columnWidth: real): var {
        const onDay = view.layoutPolicy.eventPolicy.forDay(view.gridDayEvents, iso);
        const placed = view.layoutPolicy.layout(onDay, columnWidth);
        const byId = {};
        for (let p = 0; p < placed.length; p++)
            byId[placed[p].id] = placed[p];

        // Hues are spread across **the day**, not across the overlap cluster.
        // The cluster is where chips touch side to side, but a 2 pm meeting
        // ending where a 3 pm one begins touches too, and the fixture's
        // Thursday drew those two a family apart — one column, two chips, one
        // apparent colour. A day is the unit the eye compares, so it is the
        // unit the spreading works over.
        const daySpread = CalendarTokens.hues.spread(onDay);
        const hueOf = {};
        for (let h = 0; h < onDay.length; h++)
            hueOf[onDay[h].id] = daySpread[h];

        const out = [];
        for (let e = 0; e < onDay.length; e++) {
            const event = onDay[e];
            const rect = view.grid.eventRect(event.start, event.end, iso, view.hourRow);
            const slot = byId[event.id];
            if (!rect || !slot)
                continue;
            out.push({
                "event": event,
                "id": event.id,
                "y": rect.y,
                "h": Math.max(CalendarTokens.chipMinH, rect.h),
                "continuesAbove": rect.continuesAbove,
                "continuesBelow": rect.continuesBelow,
                "xFrac": slot.xFrac,
                "wFrac": slot.wFrac,
                "depth": slot.depth,
                // Minutes of clear box turned into pixels of it, on the one
                // conversion the grid owns. `Infinity` stays infinite — the
                // chip hands it straight back to a `Math.min`.
                "clearH": isFinite(slot.clearMinutes)
                          ? view.grid.minutesToY(slot.clearMinutes, view.hourRow)
                          : Infinity,
                "minutes": view.layoutPolicy.time.diffMinutes(event.start, event.end),
                "hue": hueOf[event.id] !== undefined
                       ? hueOf[event.id] : CalendarTokens.hues.forEvent(event)
            });
        }
        return out;
    }

    function eventById(id: string): var {
        for (let i = 0; i < view.events.length; i++)
            if (view.events[i].id === id)
                return view.events[i];
        return null;
    }

    // --- layer 1: the column washes -------------------------------------------

    Repeater {
        model: view.columns

        delegate: Rectangle {
            required property var modelData
            required property int index

            x: view.columnX(index)
            width: view.columnWidthFor(index)
            y: 0
            height: view.height
            // Today wins over the weekend, and does not add to it: a Saturday
            // that is today should read as *today*, not as the one column with
            // two washes on it.
            color: modelData.isToday ? CalendarTokens.todayWash
                 : modelData.isWeekend ? CalendarTokens.weekendWash
                 : "transparent"
        }
    }

    // --- layer 2: the sticky header -------------------------------------------

    Item {
        id: headerBand

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: CalendarTokens.dayHeaderH

        Repeater {
            model: view.columns

            delegate: Item {
                id: dayHead

                required property var modelData
                required property int index

                readonly property var header: view.format.dayHeader(dayHead.modelData.iso)

                x: view.columnX(dayHead.index)
                width: view.columnWidthFor(dayHead.index)
                height: headerBand.height

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dayHead.header ? dayHead.header.weekday : ""
                        color: dayHead.modelData.isToday ? Theme.accentPrimary : Theme.textMuted
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(Theme.capsSize)
                        font.weight: Theme.weightMedium
                        font.letterSpacing: Theme.pt(Theme.capsSize) * Theme.capsTrackingEm
                        font.capitalization: Font.AllUppercase
                    }

                    /// The numeral, and today's circle behind it. The circle is
                    /// the item and the numeral is centred in it, so the
                    /// numeral's own baseline never moves between a day that is
                    /// today and one that is not.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 28
                        height: 28
                        radius: Theme.radiusFull
                        color: dayHead.modelData.isToday ? Theme.accentPrimary : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: dayHead.header ? dayHead.header.day : ""
                            color: dayHead.modelData.isToday ? Theme.bgBase
                                 : dayHead.modelData.isWeekend ? Theme.textSecondary
                                 : Theme.textPrimary
                            font.features: CalendarTokens.tabularFigures
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(17)
                            font.weight: Theme.weightMedium
                        }
                    }
                }
            }
        }

        /// The day separators, drawn over the header as well as the grid so a
        /// column reads as one channel from its date to midnight.
        Repeater {
            model: view.columns.length

            delegate: Rectangle {
                required property int index

                x: view.columnX(index)
                width: 1
                height: headerBand.height
                color: Theme.borderSubtle
                visible: index > 0
            }
        }
    }

    // --- layer 2b: the all-day band -------------------------------------------

    Item {
        id: allDayBand

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerBand.bottom
        height: view.bandHeight

        /// One line, vertically centred in the band — the same convention as
        /// every other label in this gutter.
        ///
        /// It was two lines, because "ALL DAY" tracked at `capsTrackingEm` is
        /// 68px and the gutter is 56. Two lines then overflowed a 28px band and
        /// were cut in half by the rule under it, which is worse than the
        /// problem it solved. The tracking is what does not fit, so the tracking
        /// goes: caps at `capsSize` are legible untracked at this size, and one
        /// uncut line says more than two cut ones.
        Text {
            x: 0
            width: view.gutterW - Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            text: "ALL DAY"
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(10)
            font.weight: Theme.weightMedium
        }

        Repeater {
            model: view.columns.length

            delegate: Rectangle {
                required property int index

                x: view.columnX(index)
                width: 1
                height: allDayBand.height
                color: Theme.borderSubtle
                visible: index > 0
            }
        }

        /// The bars, in **the same chip language as the grid** — accent bar,
        /// tinted fill, text in the hue.
        ///
        /// They used to be solid in the hue with `bgBase` text, on the argument
        /// that the inversion stops a one-day all-day bar reading as a very
        /// short meeting. Captured, that argument lost: a week showed two
        /// unrelated visual languages a centimetre apart, saturated blocks above
        /// tinted ones, and the row they belong to already says which is which.
        /// One language, one row that reads as one calendar.
        Repeater {
            model: view.bandLanes

            delegate: Rectangle {
                id: bandBar

                required property var modelData

                readonly property var event: view.eventById(modelData.id)
                readonly property int hue: CalendarTokens.hues.forEvent(bandBar.event)

                /// The same lead-in a grid chip takes, so the two rows are one
                /// language — and **the trailing gap is the continuation cue**.
                ///
                /// Two bars ended on the same pixel of the frame and only one
                /// carried an arrow, which read as an arrow that had been
                /// forgotten rather than as one bar ending and another running
                /// on. The gap is what tells them apart before the glyph does: a
                /// span that ends inside this week stops six pixels short with
                /// both right corners rounded, and a span that continues runs
                /// hard into the column edge and is cut by it. Same for the left
                /// edge, so a span arriving from last week has no inset either.
                readonly property bool runsOn: modelData.continuesRight === true
                readonly property bool runsIn: modelData.continuesLeft === true

                readonly property real lead: view.columnX(modelData.startCol)
                    + (bandBar.runsIn ? 0 : CalendarTokens.chipInset)
                readonly property real trail:
                    view.columnRight(modelData.startCol + modelData.span - 1)
                    - (bandBar.runsOn ? 0 : CalendarTokens.chipGap * 3)

                x: Math.round(bandBar.lead)
                width: Math.max(0, Math.round(bandBar.trail) - Math.round(bandBar.lead))
                y: Theme.space1 + modelData.lane
                   * (CalendarTokens.allDayLaneH + CalendarTokens.allDayLaneGap)
                height: CalendarTokens.allDayLaneH
                radius: Theme.radiusSm - 2
                clip: true
                color: CalendarTokens.fill(bandBar.hue)
                border.width: 1
                border.color: CalendarTokens.chipBorder(bandBar.hue)

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: CalendarTokens.chipBar
                    color: CalendarTokens.bar(bandBar.hue)
                }

                /// The continuation marker, **outside the elided string**.
                ///
                /// It used to be concatenated onto the title, which meant the one
                /// bar most likely to need it — a long title running off the week
                /// — was the one whose arrow got elided away. Anchored, it is the
                /// last thing the bar gives up rather than the first.
                Text {
                    id: runOn

                    visible: bandBar.runsOn
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space1
                    anchors.verticalCenter: parent.verticalCenter
                    text: "→"
                    color: CalendarTokens.text(bandBar.hue)
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                    font.weight: Theme.weightMedium
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: CalendarTokens.chipBar + Theme.space2
                    anchors.rightMargin: bandBar.runsOn
                        ? runOn.width + Theme.space1 * 2 : Theme.space2
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: (bandBar.runsIn ? "← " : "")
                          + (bandBar.event ? (bandBar.event.title || "Untitled") : "")
                    color: CalendarTokens.text(bandBar.hue)
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                    font.weight: Theme.weightMedium
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: view.eventActivated(modelData.id)
                }
            }
        }
    }

    /// The band's floor. Heavier than an hour rule, because it separates two
    /// kinds of row rather than two hours of one.
    Rectangle {
        id: bandRule

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: allDayBand.bottom
        height: 1
        color: Qt.alpha(Theme.borderStrong, 0.5)
    }

    // --- layer 3: the scrolling grid ------------------------------------------

    Flickable {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: bandRule.bottom
        anchors.bottom: parent.bottom
        clip: true

        contentWidth: width
        contentHeight: view.grid.dayHeight(view.hourRow)
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 4000

        /// Opened on the working day rather than at midnight. Set once, when
        /// the viewport first has a height — a binding would fight every scroll
        /// the user makes, and a `Component.onCompleted` would run against a
        /// height of zero and clamp to the top.
        property bool parked: false
        onHeightChanged: {
            if (!body.parked && body.height > 0) {
                body.contentY = view.grid.visibleScrollY(view.grid.defaultStartHour,
                                                         view.hourRow, body.height);
                body.parked = true;
            }
        }

        Item {
            id: content

            width: body.width
            height: body.contentHeight

            /// The half-hour hairlines first, so an hour rule always wins where
            /// the two could ever land on the same pixel.
            Repeater {
                model: 24

                delegate: Rectangle {
                    required property int index

                    x: view.gutterW
                    width: content.width - view.gutterW
                    y: Math.round(view.grid.minutesToY(index * 60 + 30, view.hourRow))
                    height: 1
                    // 0.22 and not 0.4. At 0.4 a half-hour hairline is within a
                    // hair of an hour rule's own weight, so a two-hour block
                    // reads as four identical bands and the hour — the thing the
                    // gutter actually names — stops being the beat. The
                    // half-hour is a *hint* for where 2:30 is; it only has to be
                    // findable when looked for.
                    color: Qt.alpha(Theme.borderSubtle, 0.22)
                }
            }

            Repeater {
                model: view.grid.hourLabels(view.use24, view.hourRow)

                delegate: Rectangle {
                    required property var modelData

                    x: view.gutterW
                    width: content.width - view.gutterW
                    y: Math.round(modelData.y)
                    height: 1
                    color: Theme.borderSubtle
                }
            }

            /// The gutter. **The label is centred on its own rule**, which is
            /// the one convention this gutter has.
            ///
            /// It used to sit 3px above the rule, on the argument that the
            /// number names the band starting there. The live-time stamp, which
            /// replaces whichever label it lands on, was centred on the now-line
            /// — so the gutter ran two conventions at once and the eye had to
            /// decide, per label, whether a number meant the line beside it or
            /// the space under it. A stamp that *replaces* a label has to sit
            /// where that label sat, so both are centred and the substitution is
            /// invisible.
            Repeater {
                model: view.grid.hourLabels(view.use24, view.hourRow)

                delegate: Text {
                    required property var modelData

                    readonly property real nowRef: view.nowColumn >= 0 ? view.nowY : -1

                    x: 0
                    width: view.gutterW - Theme.space2
                    // Nudged clear of the live stamp where the two would crowd,
                    // suppressed only where they are genuinely on top of each
                    // other. Both are distances rather than "the current hour",
                    // and both belong to `TimeGridPolicy`.
                    y: Math.round(modelData.y
                                  + view.grid.hourLabelShift(modelData.y, nowRef)
                                  - height / 2)
                    horizontalAlignment: Text.AlignRight
                    text: modelData.label
                    visible: !view.grid.hourLabelHidden(modelData.y, nowRef)
                    color: Theme.textMuted
                    font.features: CalendarTokens.tabularFigures
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11)
                }
            }

            Repeater {
                model: view.columns.length

                delegate: Rectangle {
                    required property int index

                    x: view.columnX(index)
                    width: 1
                    height: content.height
                    color: Theme.borderSubtle
                }
            }

            /// One column of chips per day. The model is the column array, so a
            /// column rebuilds when its date changes and not when the array is
            /// merely reassigned.
            Repeater {
                model: view.columns

                delegate: Item {
                    id: column

                    required property var modelData
                    required property int index

                    x: view.columnX(index)
                    width: view.columnWidthFor(column.index)
                    height: content.height

                    Repeater {
                        model: view.chipsFor(column.modelData.iso, column.width
                                             - CalendarTokens.chipInset
                                             - CalendarTokens.chipGap)

                        delegate: EventChip {
                            required property var modelData

                            // The packing, verbatim from the policy: `xFrac`
                            // and `wFrac` are shares of one track. Side by side
                            // wherever the lanes clear `minLaneWidth`, and a
                            // cascade only past it — which the policy has
                            // already resolved into these two numbers, so
                            // nothing here offsets or stacks anything. `depth`
                            // is only ever read as a paint order: a cascaded
                            // chip must sit over the one it indents from.
                            //
                            // Both edges are rounded off the *same* track and
                            // the width is their difference, so three shares of
                            // a 122px column come out 38/38/38 with an exact
                            // 2px between them — rounding a width independently
                            // is what leaves a half-pixel seam under one
                            // neighbour and a 3px canyon under the next.
                            //
                            // `chipInset` of lead-in clears the day separator
                            // the grid draws at the column's own x and leaves a
                            // visible gutter beside it; the gap is then taken
                            // off each chip's right edge, so the air lands
                            // between neighbours and once at the trailing edge.
                            // Two chips in adjacent *days* are then
                            // `chipGap + rule + chipInset` apart and never abut.
                            readonly property real track:
                                column.width - CalendarTokens.chipInset
                            readonly property real lead:
                                CalendarTokens.chipInset + modelData.xFrac * track
                            readonly property real trail:
                                CalendarTokens.chipInset
                                + (modelData.xFrac + modelData.wFrac) * track

                            z: modelData.depth
                            x: Math.round(lead)
                            width: Math.max(CalendarTokens.chipGap,
                                            Math.round(trail) - CalendarTokens.chipGap
                                                - Math.round(lead))
                            y: Math.round(modelData.y)
                            height: Math.max(CalendarTokens.chipMinH,
                                             Math.round(modelData.h) - 1)

                            event: modelData.event
                            hue: modelData.hue
                            depth: modelData.depth
                            clearHeight: modelData.clearH
                            minutes: modelData.minutes
                            continuesAbove: modelData.continuesAbove
                            continuesBelow: modelData.continuesBelow
                            use24: view.use24
                            selected: view.selectedId === modelData.id
                            onActivated: id => view.eventActivated(id)
                        }
                    }
                }
            }

            /// The now-line's reach, and the thing that makes the gutter stamp
            /// a label rather than an orphan.
            ///
            /// The rail itself is one column wide, because "now" happens on
            /// today and marking six other days with it would be a lie. But the
            /// *time* is printed in the gutter, and with only today's column
            /// drawn there was a 270px hole between the number and the thing it
            /// named — the reader had to guess they were the same fact. A hair
            /// of the same ember runs the whole width and closes it: too faint
            /// to read as a mark on any day it crosses, loud enough to be a line
            /// the eye follows from the label to the rail.
            ///
            /// 0.38 and not 0.22. 0.22 of `accentEmber` on `bgBase` is 1.14:1 —
            /// arithmetic rather than a line, and the note off the capture was
            /// that the stamp sat two columns from its rail "with no connecting
            /// rule". A connector that cannot be seen is not one. 0.38 is
            /// 1.36:1: still a quarter of the rail's own weight, still no
            /// competition for it, and now a thing the eye can actually run
            /// along.
            Rectangle {
                visible: view.nowColumn >= 0
                x: view.gutterW
                width: content.width - view.gutterW
                y: Math.round(view.nowY) + (Theme.rail - 1) / 2
                height: 1
                // **Under** the chips, where the rail itself is over them. The
                // rail marks today and has to survive crossing a saturated fill;
                // the connector only has to get the eye from the gutter to the
                // rail, and drawing it across other days' chips scored a tinted
                // line through the middle of a meeting on a day where nothing is
                // happening now. Behind a chip it simply stops and starts again,
                // which the eye completes for free.
                z: -1
                color: Qt.alpha(Theme.accentEmber, 0.38)
            }

            /// The now-line, above every chip it crosses.
            Item {
                id: nowLine

                visible: view.nowColumn >= 0
                x: view.nowColumn >= 0 ? view.columnX(view.nowColumn) : 0
                width: view.columnWidthFor(view.nowColumn)
                y: Math.round(view.nowY)
                z: 10

                /// A one-pixel halo of the page colour under the rail, so the
                /// line survives crossing a saturated chip instead of dissolving
                /// into it.
                Rectangle {
                    x: 0
                    y: -1
                    width: parent.width
                    height: Theme.rail + 2
                    color: Theme.bgBase
                    opacity: 0.55
                }

                Rectangle {
                    width: parent.width
                    height: Theme.rail
                    color: Theme.accentEmber
                }

                /// The dot that says *which column* is now.
                ///
                /// It used to be centred on the column's own left edge, which
                /// is the boundary it shares with yesterday — so half of it was
                /// drawn on Monday, over the right edge of Monday's 1pm chip,
                /// and it read as a mark on that event rather than on today.
                /// A marker for a column belongs inside the column: the dot's
                /// left edge sits on the boundary and every pixel of it is on
                /// today's side.
                Rectangle {
                    x: 0
                    y: (Theme.rail - 7) / 2
                    width: 7
                    height: 7
                    radius: Theme.radiusFull
                    color: Theme.accentEmber
                }
            }

            /// The live time, in the gutter, at the line's own height — this is
            /// the label the current hour gave up above.
            Text {
                visible: view.nowColumn >= 0
                x: 0
                width: view.gutterW - Theme.space2
                y: Math.round(view.nowY) - height / 2
                z: 10
                horizontalAlignment: Text.AlignRight
                text: view.format.stampTime(view.nowStamp, view.use24)
                color: Theme.accentEmber
                font.features: CalendarTokens.tabularFigures
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(11)
                font.weight: Theme.weightMedium
            }
        }
    }

    /// The gutter's own right edge, drawn last so it sits over the rules that
    /// run up to it.
    Rectangle {
        x: view.gutterW
        y: 0
        width: 1
        height: view.height
        color: Theme.borderSubtle
    }

    /// And the grid's own right edge, which nothing drew. Every column has a
    /// separator on its left, so the seventh had a rule on one side and open
    /// air on the other — a bar or a chip in Saturday ended against nothing and
    /// read as running off the window. The same hairline closes the frame, and
    /// it is what the trailing gap on a band bar is a gap *from*.
    Rectangle {
        x: view.width - 1
        y: 0
        width: 1
        height: view.height
        color: Theme.borderSubtle
    }
}
