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
    function columnX(index: int): real {
        const x = view.grid.xForColumn(index, view.gutterW, view.width, view.columns.length);
        return isNaN(x) ? 0 : x;
    }

    /// One column's chips, joined from the two policies that decided them:
    /// `layout` says how the width is shared, `eventRect` says where the top
    /// and bottom edges are. Joining is all this does — every number in the
    /// result was computed on the other side of a test.
    function chipsFor(iso: string): var {
        const onDay = view.layoutPolicy.eventPolicy.forDay(view.gridDayEvents, iso);
        const placed = view.layoutPolicy.layout(onDay);
        const byId = {};
        for (let p = 0; p < placed.length; p++)
            byId[placed[p].id] = placed[p];

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
                "compact": view.layoutPolicy.isCompact(
                    view.layoutPolicy.time.diffMinutes(event.start, event.end)),
                "hue": CalendarTokens.hues.forEvent(event)
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
            width: view.columnW
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
                width: view.columnW
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
                            color: dayHead.modelData.isToday ? Theme.bgBase : Theme.textPrimary
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

        /// Two lines, because "ALL DAY" tracked at `capsTrackingEm` is 68px and
        /// the gutter is 56. A `Text` wider than its own `width` with
        /// `AlignRight` hangs off the left edge rather than clipping, so the
        /// one-line form silently printed into the sidebar.
        Text {
            x: 0
            width: view.gutterW - Theme.space2
            anchors.top: parent.top
            anchors.topMargin: Theme.space1 - 1
            text: "ALL\nDAY"
            lineHeight: 0.95
            horizontalAlignment: Text.AlignRight
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(Theme.capsSize)
            font.letterSpacing: Theme.pt(Theme.capsSize) * Theme.capsTrackingEm
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

        /// The bars. Solid in the hue with `bgBase` text — the inverse of a
        /// timed chip, which is what keeps a one-day all-day bar from reading
        /// as a very short meeting.
        Repeater {
            model: view.bandLanes

            delegate: Rectangle {
                id: bandBar

                required property var modelData

                readonly property var event: view.eventById(modelData.id)
                readonly property int hue: CalendarTokens.hues.forEvent(bandBar.event)

                x: view.columnX(modelData.startCol) + 2
                width: Math.max(0, view.columnW * modelData.span - 4)
                y: Theme.space1 + modelData.lane
                   * (CalendarTokens.allDayLaneH + CalendarTokens.allDayLaneGap)
                height: CalendarTokens.allDayLaneH
                radius: 4
                color: CalendarTokens.bar(bandBar.hue)

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space2
                    anchors.rightMargin: Theme.space2
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: (modelData.continuesLeft ? "← " : "")
                          + (bandBar.event ? (bandBar.event.title || "Untitled") : "")
                          + (modelData.continuesRight ? " →" : "")
                    color: Theme.bgBase
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
                    color: Qt.alpha(Theme.borderSubtle, 0.4)
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

            /// The gutter. The label sits *above* its own rule rather than
            /// astride it, so the number reads as the name of the band starting
            /// there and not as a label for the line itself.
            Repeater {
                model: view.grid.hourLabels(view.use24, view.hourRow)

                delegate: Text {
                    required property var modelData

                    x: 0
                    width: view.gutterW - Theme.space2
                    y: Math.round(modelData.y) - height - 3
                    horizontalAlignment: Text.AlignRight
                    text: modelData.label
                    // Suppressed where the live time is printing over it —
                    // a distance, not "the current hour". See
                    // `TimeGridPolicy.hourLabelHidden`.
                    visible: !view.grid.hourLabelHidden(
                        modelData.y, view.nowColumn >= 0 ? view.nowY : -1)
                    color: Theme.textMuted
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
                    width: view.columnW
                    height: content.height

                    Repeater {
                        model: view.chipsFor(column.modelData.iso)

                        delegate: EventChip {
                            required property var modelData

                            // One pixel of air at the column's edges and between
                            // two packed chips, which is what the selection ring
                            // hangs in.
                            x: 1 + modelData.xFrac * (column.width - 2)
                            width: Math.max(1, modelData.wFrac * (column.width - 2) - 1)
                            y: Math.round(modelData.y)
                            height: Math.round(modelData.h) - 1

                            event: modelData.event
                            hue: modelData.hue
                            compact: modelData.compact
                            continuesAbove: modelData.continuesAbove
                            continuesBelow: modelData.continuesBelow
                            use24: view.use24
                            selected: view.selectedId === modelData.id
                            onActivated: id => view.eventActivated(id)
                        }
                    }
                }
            }

            /// The now-line, above every chip it crosses.
            Item {
                id: nowLine

                visible: view.nowColumn >= 0
                x: view.nowColumn >= 0 ? view.columnX(view.nowColumn) : 0
                width: view.columnW
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

                Rectangle {
                    x: -3
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
}
