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
import qs.Services.Calendar

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

    /// The contact book, and it is here for exactly one reason: a chip wide
    /// enough for a guest line has to name the people on it, and an event
    /// carries ids. Defaulted to the store rather than required from the
    /// caller, because a view that draws nothing without it would be a view
    /// that breaks the day the caller forgets — and the day view is the only
    /// place the width for a guest line ever exists.
    property var contacts: CalendarStore.contacts

    property TimeGridPolicy grid: TimeGridPolicy {}
    property EventPolicy eventPolicy: EventPolicy {}
    property GuestPolicy guestPolicy: GuestPolicy {}
    property EventLayoutPolicy layoutPolicy: EventLayoutPolicy {}
    property CalendarFormat format: CalendarFormat {}
    property DragPolicy dragPolicy: DragPolicy {}
    property CreatePolicy createPolicy: CreatePolicy {}

    /// The name seam 3 finds this by. `CalendarView` owns the instance and the
    /// capture harness cannot reach its id, so the grid says what it is and the
    /// harness walks the tree for it — see `capture-harness.qml`.
    objectName: "calendarWeekGrid"

    /// **A drag, posed with no pointer.** `{mode, eventId, fromIso, fromMin,
    /// toIso, toMin}` — the harness names two grid coordinates and the view
    /// runs `DragPolicy.begin`/`update` on them, so a mid-drag picture is a
    /// deterministic still rather than a race against a synthetic pointer. This
    /// is the whole payoff of keeping the drag arithmetic pure: the same code
    /// path a real pointer takes, driven by a day and a minute.
    property var posedDrag: null

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

    /// The margin every column keeps on **both** of its edges — the hairline a
    /// week column can afford, or a real one once the column is a page wide.
    /// `EventLayoutPolicy.columnInset` is the rule; the header, the all-day bar
    /// and the chips all read it from here, which is what stops the day view
    /// setting its date on one left edge and its events on another.
    readonly property real colInset:
        view.layoutPolicy.columnInset(view.columnW, CalendarTokens.chipInset)

    readonly property string rangeStart: view.columns.length > 0 ? view.columns[0].iso : ""

    readonly property var bandEvents: view.layoutPolicy.bandEvents(view.events)
    readonly property var gridDayEvents: view.layoutPolicy.gridEvents(view.events)

    /// Nothing at all in the days on screen — no chip, no all-day bar.
    ///
    /// A grid with nothing in it is the one state where the surface has to say
    /// something out loud, because an empty week and a week that failed to load
    /// draw the same picture: 24 ruled rows and no other mark. The hint below
    /// makes them different, and it is only ever asked for on the *visible*
    /// range, not on the store — a calendar with 400 events in September is
    /// still an empty first week of August.
    readonly property bool isEmpty: {
        if (view.bandLanes.length > 0)
            return false;
        for (let i = 0; i < view.columns.length; i++) {
            const day = view.layoutPolicy.eventPolicy.forDay(view.gridDayEvents,
                                                             view.columns[i].iso);
            if (day.length > 0)
                return false;
        }
        return true;
    }

    /// What the pointer says over each part of the grid. Pure and tested next
    /// door; this file only reads the answer.
    property CursorPolicy cursors: CursorPolicy {}

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
    readonly property int nowColumn: view.nowY < 0
        ? -1
        : view.columnIndexOf(view.eventPolicy.time.dayOf(view.nowStamp))
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
                "columns": slot.columns,
                "depth": slot.depth,
                // Minutes of clear box turned into pixels of it, on the one
                // conversion the grid owns. `Infinity` stays infinite — the
                // chip hands it straight back to a `Math.min`.
                "clearH": isFinite(slot.clearMinutes)
                          ? view.grid.minutesToY(slot.clearMinutes, view.hourRow)
                          : Infinity,
                "minutes": view.layoutPolicy.time.diffMinutes(event.start, event.end),
                // Resolved here, where the contact book is, rather than in the
                // chip — the chip is handed a picture's worth of facts and no
                // lookups, the same as every other field on this record.
                "guests": view.guestPolicy.summary(event.guests, view.contacts, 3),
                "hue": hueOf[event.id] !== undefined
                       ? hueOf[event.id] : CalendarTokens.hues.forEvent(event)
            });
        }
        return out;
    }

    /// The event behind an id, or null. `EventPolicy` owns the lookup — the
    /// list's own order and identity rules are its business, not this file's.
    function eventById(id: string): var {
        return view.eventPolicy.byId(view.events, id);
    }

    function columnIndexOf(iso: string): int {
        for (let i = 0; i < view.columns.length; i++)
            if (view.columns[i].iso === iso)
                return i;
        return -1;
    }

    /// The horizontal middle of a column, in `content` coordinates. Only the
    /// posed drag needs it — a real pointer brings its own x.
    function columnCentreX(index: int): real {
        return view.columnX(index) + view.columnWidthFor(index) / 2;
    }

    // --- the drag -------------------------------------------------------------
    //
    // Four functions and two strings of state. Everything that is a *decision*
    // — where the press anchors, which way it grew, what snaps, which day the
    // pointer crossed into, whether the gesture was really a click — is
    // `DragPolicy`, on the other side of `tests/tst_dragpolicy.qml`. What is
    // here is the translation: pointer coordinates into the grid's own space,
    // and a committed proposal into the one store call that matches it.
    //
    // Two things are logged that no store call would log: `drag begin <mode>`
    // and `drag cancel`. They are here because #81's argument applies to a
    // gesture as much as to a lifecycle — a drag that begins and produces
    // nothing has two candidate causes (the press missed, or the commit
    // refused) and no way to tell them apart from the outside.

    /// Which event is under the finger, and in which mode. Empty between drags.
    property string dragMode: ""
    property string dragEventId: ""

    /// The context `DragPolicy` works in: the grid's own geometry plus the
    /// event being dragged, rebuilt per gesture so a week stepped mid-drag
    /// cannot leave stale columns behind.
    function dragContext(record: var): var {
        const isos = [];
        for (let i = 0; i < view.columns.length; i++)
            isos.push(view.columns[i].iso);
        return {
            "hourHeight": view.hourRow,
            "gutterWidth": view.gutterW,
            "gridWidth": content.width,
            "columns": isos,
            "event": record || null,
            "snap": CalendarTokens.snapMin,
            "minMinutes": CalendarTokens.snapMin,
            "threshold": 4
        };
    }

    function beginDrag(mode: string, x: real, y: real, record: var): void {
        view.closeQuickCreate("drag");
        const proposal = view.dragPolicy.begin(mode, x, y, view.dragContext(record));
        if (!proposal.active) {
            view.dragMode = "";
            view.dragEventId = "";
            return;
        }
        view.dragMode = mode;
        view.dragEventId = record ? record.id : "";
        Logger.log("calendar", "drag begin " + mode
                   + (view.dragEventId ? " " + view.dragEventId : "")
                   + " " + proposal.start + " " + proposal.end);
    }

    function updateDrag(x: real, y: real): void {
        if (view.dragMode)
            view.dragPolicy.update(x, y);
    }

    /// Let go. The proposal is read *before* `end()` resets the machine, which
    /// is the one ordering trap in this file.
    function endDrag(): void {
        if (!view.dragMode)
            return;
        const mode = view.dragMode;
        const id = view.dragEventId;
        const done = view.dragPolicy.end();
        const p = done.proposal;
        view.dragMode = "";
        view.dragEventId = "";

        if (!done.committed) {
            // A press that never travelled is a click, and a click on a chip
            // selects it. On empty grid it is nothing at all: the create
            // affordance is the drag, and a stray click that made a
            // 15-minute event would be a store write nobody asked for.
            if (done.kind === "click" && id)
                view.eventActivated(id);
            return;
        }

        if (mode === "create") {
            const minutes = view.layoutPolicy.time.diffMinutes(p.start, p.end);
            const startMin = view.layoutPolicy.time.parseMinutes(p.start);
            const made = CalendarStore.createEvent(p.dayIso, startMin, minutes, "");
            if (made)
                view.openQuickCreate(made, p.dayIso, p.start, p.end);
            return;
        }
        if (mode === "move") {
            CalendarStore.moveEvent(id, p.start);
            return;
        }
        CalendarStore.resizeEvent(id, mode === "resizeTop" ? "start" : "end",
                                  mode === "resizeTop" ? p.start : p.end);
    }

    function cancelDrag(): void {
        if (!view.dragMode)
            return;
        view.dragPolicy.cancel();
        view.dragMode = "";
        view.dragEventId = "";
        Logger.log("calendar", "drag cancel");
    }

    /// Escape, but only while something is in flight. A `Shortcut` and not a
    /// key handler on purpose: the window already has exactly one Escape
    /// handler (`CalendarView.qml`) and it closes the calendar, so a second
    /// handler in the focus chain would be a race about who saw the key first.
    /// A disabled shortcut is not in the running at all, so outside a drag
    /// Escape means what it has always meant.
    Shortcut {
        sequence: "Escape"
        enabled: view.dragMode !== ""
        onActivated: view.cancelDrag()
    }

    /// The live proposal, or a dead one. Everything the ghost draws is read off
    /// this and nothing is recomputed.
    readonly property var proposal: view.dragPolicy.proposal

    /// The ghost is drawn once the gesture has actually travelled. Before that
    /// a `move` would paint a second chip exactly on top of the first, and the
    /// picture would say "you are dragging" to somebody who had only clicked.
    readonly property bool dragShown:
        view.proposal.active && view.proposal.moved && view.proposal.column >= 0

    // --- the quick-create panel -----------------------------------------------

    property string quickCreateId: ""
    property rect quickCreateAnchor: Qt.rect(0, 0, 0, 0)

    function openQuickCreate(id: string, dayIso: string, start: string, end: string): void {
        const col = view.columnIndexOf(dayIso);
        const rect = view.grid.eventRect(start, end, dayIso, view.hourRow);
        if (col < 0 || !rect)
            return;
        view.quickCreateId = id;
        view.quickCreateAnchor = Qt.rect(
            view.columnX(col) + view.colInset,
            rect.y - body.contentY + body.y,
            Math.max(0, view.columnWidthFor(col) - view.colInset * 2),
            Math.max(CalendarTokens.chipMinH, rect.h));
        Logger.log("calendar", "quick-create open " + id);
    }

    /// Where a chip is, in this grid's own coordinates, so something outside
    /// the grid can anchor a panel to it. A zero-width rect means "not on
    /// screen" — the event is on another day, or scrolled past — and whoever
    /// asked is expected to fall back rather than to place a panel on 0,0.
    ///
    /// It exists because the event editor is hosted at the *window*: it opens
    /// over the month grid too, and a panel that only the week grid could place
    /// would be a panel the month view had to grow its own copy of. The chip
    /// rectangle is still a thing only this file knows — column x, column
    /// width, scroll offset, the band's height — so this hands out the answer
    /// rather than the four numbers behind it.
    function chipAnchor(id: string): rect {
        const event = view.eventById(id);
        if (!event)
            return Qt.rect(0, 0, 0, 0);
        const dayIso = view.grid.time.dayOf(event.start);
        const col = view.columnIndexOf(dayIso);
        const box = view.grid.eventRect(event.start, event.end, dayIso, view.hourRow);
        if (col < 0 || !box)
            return Qt.rect(0, 0, 0, 0);
        return Qt.rect(
            view.columnX(col) + view.colInset,
            box.y - body.contentY + body.y,
            Math.max(0, view.columnWidthFor(col) - view.colInset * 2),
            Math.max(CalendarTokens.chipMinH, box.h));
    }

    function closeQuickCreate(reason: string): void {
        if (!view.quickCreateId)
            return;
        Logger.log("calendar", "quick-create dismissed (" + reason + ")");
        view.quickCreateId = "";
    }

    // --- what seam 2 aims by --------------------------------------------------
    //
    // A nested Hyprland tiles this window to its output, so nothing about the
    // grid's geometry is knowable from outside: the harness cannot assume a
    // column width, a scroll position or where the grid starts under the
    // toolbar. So the grid says. Every number is in *window* coordinates and
    // the columns carry their own dates, which is what lets the harness ask for
    // "Wednesday at 09:00" rather than for a pixel and hope.
    //
    // Debounced rather than bound to a signal, because `contentY` changes a
    // frame at a time while the grid settles and one line per frame would bury
    // the log the harness reads.
    readonly property string geometryLine: {
        if (!view.visible || view.width <= 0 || view.columns.length === 0)
            return "";
        const origin = view.mapToItem(null, 0, body.y);
        const cols = [];
        for (let i = 0; i < view.columns.length; i++)
            cols.push(view.columns[i].iso + ":"
                      + Math.round(view.mapToItem(null, view.columnX(i), 0).x) + ":"
                      + Math.round(view.columnWidthFor(i)));
        return "geometry gutter=" + view.gutterW
             + " hourHeight=" + view.hourRow
             + " gridX=" + Math.round(origin.x)
             + " gridTop=" + Math.round(origin.y)
             + " viewH=" + Math.round(body.height)
             + " contentY=" + Math.round(body.contentY)
             + " cols=" + cols.join(",");
    }

    onGeometryLineChanged: geometryLog.restart()

    Timer {
        id: geometryLog

        interval: 250
        onTriggered: {
            if (view.geometryLine)
                Logger.log("calendar", view.geometryLine);
        }
    }

    // --- the posed drag, for seam 3 -------------------------------------------

    function poseDrag(): void {
        const pose = view.posedDrag;
        if (!pose || view.columns.length === 0 || view.width <= 0)
            return;
        const record = pose.eventId ? view.eventById(pose.eventId) : null;
        const mode = pose.mode || "create";
        // Days and not column indices: which index Wednesday is depends on the
        // locale's first weekday, and a pose that named column 2 would be a
        // different picture in en_GB and en_US.
        const fromCol = view.columnIndexOf(pose.fromIso);
        const toCol = view.columnIndexOf(pose.toIso);
        if (fromCol < 0 || toCol < 0)
            return;
        const from = view.dragPolicy.begin(
            mode, view.columnCentreX(fromCol),
            view.grid.minutesToY(pose.fromMin, view.hourRow),
            view.dragContext(record));
        if (!from.active)
            return;
        view.dragMode = mode;
        view.dragEventId = record ? record.id : "";
        view.dragPolicy.update(view.columnCentreX(toCol),
                               view.grid.minutesToY(pose.toMin, view.hourRow));
        // Scrolled to the gesture, because a posed drag two screens below the
        // parked position is a picture of an empty morning.
        body.contentY = view.grid.visibleScrollY(
            Math.max(0, Math.floor(Math.min(pose.fromMin, pose.toMin) / 60) - 2),
            view.hourRow, body.height);
        // Claim the park, or the first `onHeightChanged` after this would put
        // the grid back at the working day and the pose would be off screen.
        body.parked = true;
    }

    onPosedDragChanged: poseTimer.restart()
    onWidthChanged: {
        if (view.posedDrag)
            poseTimer.restart();
    }

    Timer {
        id: poseTimer

        interval: 32
        onTriggered: view.poseDrag()
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
            // Which wash, including the day view's answer of none at all, is
            // `TimeGridPolicy.columnWash` — a comparison between columns is
            // meaningless when there is one column, and the capture of a single
            // teal column 870px wide is why that is written down and tested
            // rather than left to a `dayCount > 1` here.
            readonly property string wash:
                view.grid.columnWash(modelData.isToday === true,
                                     modelData.isWeekend === true,
                                     view.columns.length)

            color: wash === "today" ? CalendarTokens.todayWash
                 : wash === "weekend" ? CalendarTokens.weekendWash
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

                /// One column is a day view, and a day view's header is set
                /// **along** the column rather than stacked in the middle of
                /// it. Centring a two-line stack over 870px of column leaves
                /// the date floating in the middle of the window with the grid
                /// it names starting at the far left; the same two facts set on
                /// one line at the column's leading edge sit over the chips
                /// they belong to, and there is room for the weekday's whole
                /// name where seven columns have room for three letters.
                readonly property bool solo: view.columns.length === 1

                /// Only the day view asks — a week header has no room for it
                /// and seven of them would be a row of arithmetic.
                readonly property var load: dayHead.solo
                    ? view.layoutPolicy.dayLoad(
                        view.layoutPolicy.eventPolicy.forDay(view.gridDayEvents,
                                                             dayHead.modelData.iso),
                        view.bandLanes.length)
                    : null

                x: view.columnX(dayHead.index)
                width: view.columnWidthFor(dayHead.index)
                height: headerBand.height

                Column {
                    visible: !dayHead.solo
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

                /// The day view's header: numeral, then the weekday's whole
                /// name, hard against the column's leading edge.
                Row {
                    visible: dayHead.solo
                    // The chips' own left edge, not a margin of its own.
                    x: view.colInset
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space2

                    Rectangle {
                        width: 28
                        height: 28
                        radius: Theme.radiusFull
                        color: dayHead.modelData.isToday ? Theme.accentPrimary : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: dayHead.header ? dayHead.header.day : ""
                            color: dayHead.modelData.isToday ? Theme.bgBase : Theme.textPrimary
                            font.features: CalendarTokens.tabularFigures
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(17)
                            font.weight: Theme.weightMedium
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dayHead.header ? dayHead.header.weekdayFull : ""
                        // Set as a word, not as tracked caps: `TUESDAY` at
                        // `capsTrackingEm` is a banner, and the numeral beside
                        // it is already the loud half of the pair.
                        color: dayHead.modelData.isToday ? Theme.accentPrimary
                             : Theme.textSecondary
                        font.family: Theme.fontUi
                        font.pointSize: Theme.pt(13.5)
                        font.weight: Theme.weightMedium
                    }
                }

                /// What the day header spends its 48px on that the toolbar has
                /// not already said. The toolbar prints the whole date above
                /// this row; a header that only repeated it would be a band of
                /// pixels making no claim. The count and the booked total are
                /// the two facts a reader is scanning a day for, and they are
                /// set at the column's *trailing* edge so the date stays the
                /// one thing on the leading one. `EventLayoutPolicy` decides
                /// the wording; this prints it.
                Text {
                    visible: dayHead.solo && text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: view.colInset
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.layoutPolicy.dayLoadLabel(
                              dayHead.load,
                              dayHead.load
                                  ? view.format.duration(dayHead.load.minutes) : "")
                    color: Theme.textMuted
                    font.features: CalendarTokens.tabularFigures
                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                    font.weight: Theme.weightRegular
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

        /// One line, on the **first lane's** centre rather than the band's.
        ///
        /// Centring it in the band was right only while the band held one row.
        /// The moment a second row of all-day chips appears the band grows
        /// downward, the label slides to the middle of the two, and it stops
        /// naming the row it sits beside: at three rows it labels the gap
        /// between the second and the third. A gutter label points at a lane,
        /// so it rides the lane — which is also what the hour labels beside it
        /// do, each one on the rule it names.
        ///
        /// It is set at `capsSize` in `textSecondary`, not a tenth of a point
        /// smaller in `textMuted`. It was the one label in the window below the
        /// shell's caps size and the only one dimmer than the hour labels under
        /// it, which made the band read as an afterthought rather than as the
        /// row it is — the row that holds the three things happening today.
        ///
        /// It was two lines, because "ALL DAY" tracked at `capsTrackingEm` is
        /// 68px and the gutter is 56. Two lines then overflowed a 28px band and
        /// were cut in half by the rule under it, which is worse than the
        /// problem it solved. The tracking is what does not fit, so the tracking
        /// goes: caps at `capsSize` are legible untracked at this size, and one
        /// uncut line says more than two cut ones.
        Text {
            id: allDayLabel

            x: 0
            width: view.gutterW - Theme.space2
            y: Theme.space1 + (CalendarTokens.allDayLaneH - allDayLabel.height) / 2
            text: "ALL DAY"
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            // Exactly the hour labels' class — `pt(11)`, `textMuted`, regular.
            // It names its row the way `9 AM` names its rule, and a gutter that
            // labels two kinds of row in two different sizes and two different
            // values is a gutter with two voices in it. It was `capsSize` in
            // `textSecondary`, which made the one label with no number in it the
            // loudest thing in the column.
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(11)
            font.weight: Theme.weightRegular
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
                    + (bandBar.runsIn ? 0 : view.colInset)
                readonly property real trail:
                    view.columnRight(modelData.startCol + modelData.span - 1)
                    - (bandBar.runsOn ? 0 : CalendarTokens.chipGap * 3)

                /// What the bar's own contents measure, which is the one number
                /// `bandBarWidth` cannot work out for itself — a font metric,
                /// and a policy that could read a font could not be tested
                /// offscreen. The rule about what to do with it is the policy's.
                readonly property real natural: CalendarTokens.chipBar
                    + Theme.space2 + bandTitleMetrics.width + Theme.space2

                readonly property real track:
                    Math.max(0, Math.round(bandBar.trail) - Math.round(bandBar.lead))

                TextMetrics {
                    id: bandTitleMetrics

                    font.family: Theme.fontUi
                    font.pointSize: Theme.pt(11.5)
                    font.weight: Theme.weightMedium
                    text: bandBar.event ? (bandBar.event.title || "Untitled") : ""
                }

                x: Math.round(bandBar.lead)
                // Natural width where the span ends inside the run, the whole
                // track where it runs off an edge — `EventLayoutPolicy`
                // explains why, and a day view is where the difference is 800
                // pixels of tint.
                width: Math.round(view.layoutPolicy.bandBarWidth(
                    bandBar.track, bandBar.natural, bandBar.runsOn || bandBar.runsIn))
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
                    // 0.4, and it was 0.22. The argument for 0.22 was that a
                    // half-hour hairline at 0.4 competes with an hour rule for
                    // the beat, and it does — at arm's length. At 100% it
                    // vanished outright: the note off the capture was a grid
                    // with *no* half-hour rules at all and no way to eyeball
                    // 2:30 across an empty afternoon. A hint nobody can see is
                    // not a hint, and the hour keeps the beat by being the
                    // solid one. At 0.4 a half-hour hairline is within a
                    // hair of an hour rule's own weight, so a two-hour block
                    // reads as four identical bands and the hour — the thing the
                    // gutter actually names — stops being the beat. The
                    // half-hour is a *hint* for where 2:30 is; it only has to be
                    // findable when looked for.
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

            /// **Hover-to-create.** The empty grid answers the pointer with the
            /// slot a click would make, which is the affordance Notion has and
            /// the first capture of this grid did not: a wall of chips with no
            /// sign that the space between them is a place you can put
            /// something.
            ///
            /// It sits **under the chips**, so a press on a meeting reaches the
            /// meeting: a chip's own pointer area is declared after this one and
            /// consumes both the hover and the press, which is what stops the
            /// hint appearing under a chip and a create starting on top of one.
            ///
            /// It is the drag surface too, and it starts at the gutter's right
            /// edge rather than filling the content: `DragPolicy` clamps a
            /// press left of the first column *into* it, which is right for a
            /// pointer that wandered a pixel and wrong for one resting on the
            /// hour ruler. Not covering the ruler at all is how the ruler stays
            /// a ruler — no hand cursor over it, no create under it.
            ///
            /// `DragPolicy` measures `x` from the left of the whole grid, so
            /// the gutter is added back on the way out; `y` is already the
            /// distance from midnight, because `content` is exactly that space.
            ///
            /// Every number in the hint is already a policy: `columnForX` picks
            /// the day, `yToMinutes` and `snap` pick the quarter hour,
            /// `minutesToY` puts it back. Nothing new is decided here.
            MouseArea {
                id: createHover

                x: view.gutterW
                y: 0
                width: content.width - view.gutterW
                height: content.height
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                preventStealing: true

                /// **A crosshair, not a hand.** A hand promises that a press
                /// opens the thing under it, and there is nothing under it — a
                /// press here *draws* a new event. `CursorPolicy` owns the
                /// mapping, and the whole window reads it from there so the
                /// grid, the chip and its edges cannot drift apart again.
                //
                // pointer-exempt: this is the one surface in the shell whose
                // press does not *activate* anything — it draws. #185's rule
                // exists so a clickable thing never looks unclickable, and a
                // crosshair is a stronger affordance here than the hand, not a
                // missing one; `tests/tst_cursorpolicy.qml` pins the choice.
                cursorShape: Qt.CrossCursor

                /// Seam 2's only handle on a cursor. The nested compositor
                /// cannot present a frame, so nothing here can be photographed;
                /// what it can do is say what it asked for, once per change.
                onContainsMouseChanged: {
                    if (createHover.containsMouse)
                        Logger.log("calendar",
                                   "cursor " + view.cursors.name("grid"));
                }

                onPressed: mouse => view.beginDrag("create", mouse.x + view.gutterW,
                                                   mouse.y, null)
                onPositionChanged: mouse => {
                    if (createHover.pressed)
                        view.updateDrag(mouse.x + view.gutterW, mouse.y);
                }
                onReleased: view.endDrag()
                onCanceled: view.cancelDrag()
            }

            Rectangle {
                id: createHint

                readonly property int col: createHover.containsMouse
                                           && !view.dragPolicy.active
                    ? view.grid.columnForX(createHover.mouseX + view.gutterW,
                                           view.gutterW, content.width,
                                           view.columns.length)
                    : -1
                readonly property real startMin: view.grid.snap(
                    view.grid.yToMinutes(createHover.mouseY, view.hourRow),
                    CalendarTokens.snapMin)

                visible: createHint.col >= 0
                x: view.columnX(Math.max(0, createHint.col)) + view.colInset
                width: Math.max(0, view.columnWidthFor(Math.max(0, createHint.col))
                                - view.colInset * 2)
                y: Math.round(view.grid.minutesToY(createHint.startMin, view.hourRow))

                /// **One snap, not half an hour.** The hint used to be a 30-min
                /// box, which drew a slot twice the size of the one a press
                /// actually starts — the pointer said "this much" and the drag
                /// gave that much again. A `snapMin` slot is 14px at
                /// `hourRow` 56, which is the same 14px `TimeGridPolicy.snap`
                /// rounds to, so the outline under the pointer *is* the unit.
                height: Math.round(view.grid.minutesToY(CalendarTokens.snapMin,
                                                        view.hourRow))
                radius: Theme.radiusSm - 2

                /// And faint. It follows the pointer down 96 rows of grid, so
                /// anything with weight to it turns a scan of the week into a
                /// flicker; at 0.30 over the wash it is a shape the eye finds
                /// where it is already looking and nowhere else.
                color: Qt.alpha(Theme.surfaceOverlay, 0.30)
                border.width: 1
                border.color: Qt.alpha(Theme.borderStrong, 0.7)
            }

            /// **The drop slot.** A wash down the whole of the column the
            /// proposal has landed in, plus a hairline at each end of the slot
            /// itself, drawn in the dragged event's own hue.
            ///
            /// The ghost alone answers "how long" and "at what minute", and it
            /// answered "which day" badly: a chip dragged across a week is
            /// under the pointer, the pointer is over a column boundary as
            /// often as not, and the two columns either side of it look
            /// identical. Washing the target column says which one will take it
            /// before the finger lifts — the same job the today wash does for
            /// the date, in the same grammar, in the hue of the thing being
            /// moved so it is plainly *this* event's destination and not a
            /// selection.
            ///
            /// Under the ghost in z, so it never dulls the box the drag is
            /// aimed with, and above the grid rules so it reads as a slot
            /// rather than as a change of paper.
            Rectangle {
                id: dropSlot

                readonly property int col: Math.max(0, view.proposal.column)
                readonly property int hue: view.dragEventId
                    ? CalendarTokens.hues.forEvent(view.eventById(view.dragEventId))
                    : 0

                visible: view.dragShown
                z: 2
                x: view.columnX(dropSlot.col)
                width: view.columnWidthFor(dropSlot.col)
                y: 0
                height: content.height
                color: Qt.alpha(CalendarTokens.bar(dropSlot.hue), 0.09)

                /// The two ends of the slot, full column width, so the minute
                /// the proposal starts and ends on is readable across the day
                /// rather than only along the ghost's own edge.
                Rectangle {
                    y: Math.round(view.proposal.y)
                    width: parent.width
                    height: 1
                    color: Qt.alpha(CalendarTokens.bar(dropSlot.hue), 0.45)
                }

                Rectangle {
                    y: Math.round(view.proposal.y + view.proposal.h) - 1
                    width: parent.width
                    height: 1
                    color: Qt.alpha(CalendarTokens.bar(dropSlot.hue), 0.45)
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
                        model: view.chipsFor(
                            column.modelData.iso,
                            view.layoutPolicy.columnTrack(column.width, view.colInset,
                                                          CalendarTokens.chipGap)
                            - CalendarTokens.chipGap)

                        delegate: EventChip {
                            id: chipItem

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
                            //
                            // **Which gap depends on what is beside it.** A
                            // chip that ends at the track's right edge pays the
                            // column's own `chipGap` and nothing more, so the
                            // trailing margin stays equal to the leading one.
                            // A chip with a neighbour to its right pays
                            // `EventLayoutPolicy.laneGap` instead — a share of
                            // the lane, so the gutter is as visible in a 433px
                            // day lane as two pixels are in a 39px week one.
                            // Without it the day view's packed lanes abut, and
                            // the picture reads as a cascade of occlusions
                            // rather than as meetings side by side.
                            readonly property real track:
                                view.layoutPolicy.columnTrack(
                                    column.width, view.colInset,
                                    CalendarTokens.chipGap)
                            readonly property real lead:
                                view.colInset + modelData.xFrac * track
                            readonly property real trail:
                                view.colInset
                                + (modelData.xFrac + modelData.wFrac) * track
                            readonly property bool atTrackEnd:
                                modelData.xFrac + modelData.wFrac >= 0.999
                            readonly property int rightGap:
                                atTrackEnd ? CalendarTokens.chipGap
                                    : view.layoutPolicy.laneGap(
                                        track / Math.max(1, modelData.columns),
                                        CalendarTokens.chipGap)

                            z: modelData.depth
                            x: Math.round(lead)
                            width: Math.max(CalendarTokens.chipGap,
                                            Math.round(trail) - rightGap
                                                - Math.round(lead))
                            y: Math.round(modelData.y)
                            height: Math.max(CalendarTokens.chipMinH,
                                             Math.round(modelData.h) - 1)

                            event: modelData.event
                            guests: modelData.guests
                            hue: modelData.hue
                            depth: modelData.depth
                            clearHeight: modelData.clearH
                            minutes: modelData.minutes
                            continuesAbove: modelData.continuesAbove
                            continuesBelow: modelData.continuesBelow
                            use24: view.use24
                            selected: view.selectedId === modelData.id

                            /// One state machine for the whole grid, handed
                            /// down: a `DragPolicy` per chip would be a hundred
                            /// idle objects and, worse, a hundred places a
                            /// gesture could be half-started.
                            dragPolicy: view.dragPolicy
                            dragging: view.dragMode !== ""
                                      && view.dragEventId === modelData.id
                            ghosted: view.dragShown
                                     && view.dragEventId === modelData.id

                            /// The chip reports in its own coordinates; the two
                            /// offsets that turn those into the grid's are the
                            /// column's x and the chip's own, both of which are
                            /// right here. `mapToItem` would do the same sum
                            /// through a matrix and be wrong the moment the
                            /// chip is scaled, which it is while it is dragged.
                            onDragBegin: (zone, mx, my) => view.beginDrag(
                                zone === "top" ? "resizeTop"
                                    : zone === "bottom" ? "resizeBottom" : "move",
                                column.x + chipItem.x + mx, chipItem.y + my,
                                modelData.event)
                            onDragMoved: (mx, my) => view.updateDrag(
                                column.x + chipItem.x + mx, chipItem.y + my)
                            onDragReleased: view.endDrag()
                            onDragCancelled: view.cancelDrag()

                            onActivated: id => view.eventActivated(id)
                        }
                    }
                }
            }

            /// **The empty week says so.** One quiet line, centred in the
            /// grid, naming both ways to make an event.
            ///
            /// An empty grid and a grid that failed to load draw the same
            /// picture — 24 ruled rows — and the reader has no way to tell
            /// which they are looking at. This is the difference, and it is the
            /// *hint* rather than an illustration or a button: it says what to
            /// do with the surface already in front of them (drag), and names
            /// the key that does it without one (`C`), so the empty state
            /// teaches the shortcut the full state never has room to.
            ///
            /// `textMuted` and nothing else — no panel, no border, no icon. It
            /// is an aside on a working grid, not a screen of its own, and it
            /// disappears the instant the week has anything in it.
            ///
            /// The month view gets none of this on purpose: a month cell is
            /// captioned by its own date numeral, so an empty month already
            /// looks like a month with nothing in it rather than like a failure.
            Text {
                id: emptyHint

                visible: view.isEmpty && !view.dragPolicy.active
                z: 3
                x: view.gutterW
                    + (content.width - view.gutterW - emptyHint.width) / 2
                y: body.contentY + (body.height - emptyHint.height) / 2
                text: "Drag to create an event · C"
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pointSize: Theme.pt(12.5)
            }

            /// The proposal, drawn. Above every chip because it is the thing
            /// being aimed, and below the now-line because the clock outranks
            /// an intention.
            DragGhost {
                readonly property int col: Math.max(0, view.proposal.column)

                visible: view.dragShown
                z: 15
                x: view.columnX(col) + view.colInset
                width: Math.max(CalendarTokens.chipMinH,
                                view.columnWidthFor(col) - view.colInset * 2)
                y: Math.round(view.proposal.y)
                height: Math.max(CalendarTokens.chipMinH, Math.round(view.proposal.h))

                mode: view.proposal.mode
                // A create ghost wears the accent — it has no identity yet and
                // hue 0 is `accentPrimary`, the colour every other "this is
                // about to happen" on the surface uses. A move or a resize
                // keeps the event's own, so the chip does not appear to change
                // what it is on the way across.
                hue: view.dragEventId
                     ? CalendarTokens.hues.forEvent(view.eventById(view.dragEventId))
                     : 0
                rangeLabel: view.dragShown
                    ? view.format.timeRange(view.proposal.start, view.proposal.end,
                                            view.use24)
                    : ""
                durationLabel: view.dragShown
                    ? view.format.duration(view.layoutPolicy.time.diffMinutes(
                          view.proposal.start, view.proposal.end))
                    : ""
                title: view.dragEventId && view.eventById(view.dragEventId)
                       ? view.eventById(view.dragEventId).title : ""
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

    /// The quick-create panel, hosted here rather than at the window.
    ///
    /// It is anchored to a *chip*, and the chip's rectangle is a thing only the
    /// grid knows — column x, column width, scroll offset, the band's height.
    /// Hosting it at the window would mean handing all four of those upwards
    /// every frame. It sits outside the `Flickable` on purpose: a panel that
    /// scrolled away from under the cursor while it was being typed into would
    /// be a panel nobody could finish.
    Loader {
        id: quickCreate

        readonly property var placement: view.createPolicy.popoverAnchor(
            view.quickCreateAnchor,
            quickCreate.width > 0 ? quickCreate.width : 320,
            quickCreate.height, view.width, view.height,
            Theme.space3, Theme.space3)

        active: view.quickCreateId !== ""
        z: 30
        x: quickCreate.placement.x
        y: quickCreate.placement.y

        sourceComponent: QuickCreatePopover {
            event: view.eventById(view.quickCreateId)
            hue: CalendarTokens.hues.forEvent(view.eventById(view.quickCreateId))
            use24: view.use24
            flipped: quickCreate.placement.flipped
            caretY: quickCreate.placement.caretY

            onRenamed: title => CalendarStore.renameEvent(view.quickCreateId, title)
            onRecoloured: colour => CalendarStore.recolourEvent(view.quickCreateId, colour)
            onGuestAdded: contactId => CalendarStore.addGuest(view.quickCreateId, contactId)
            onGuestRemoved: contactId => CalendarStore.removeGuest(view.quickCreateId, contactId)
            onDiscarded: CalendarStore.deleteEvent(view.quickCreateId)
            onDismissed: reason => view.closeQuickCreate(reason)
        }
    }
}
