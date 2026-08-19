// The calendar window: a floating toplevel holding the day, week and month
// views.
//
// ## Why a FloatingWindow and not a layer surface
//
// This is the decision most likely to be "improved" later, so it is written
// down here rather than in a ticket nobody will find.
//
// A layer surface that wants the keyboard has to say how much of it it wants,
// and Hyprland's answer to `keyboardFocus: Exclusive` is not scoped to the
// keyboard at all: an exclusive layer surface captures **pointer** input as
// well, and while one is up, hit-testing among ordinary surfaces stops
// happening. That is #187 — a bar whose buttons were unreachable while a
// drawer was open, where every IPC-driven check passed throughout because the
// verb was never the broken part. `Surfaces/Drawers/DrawerWindow.qml` carries
// the measurement.
//
// This surface is nine parts pointer to one part keyboard: dragging on a grid
// to make an event, dragging a chip to move it, dragging an edge to resize it,
// and three text fields. A focus model that quietly breaks pointer routing is
// the worst possible fit for it.
//
// A `FloatingWindow` is an ordinary toplevel, so it gets ordinary focus and
// ordinary hit-testing, and placement, movement, resizing, tiling and the close
// button stay the compositor's job — the same argument
// `Surfaces/Settings/SettingsView.qml` makes, and it applies harder here.
//
// **If a layer variant is ever wanted, it is `OnDemand`, never `Exclusive`.**
//
// ## What this file is
//
// The window's chrome and its state: a sidebar, a toolbar, and whichever view
// the toolbar last asked for. It holds no calendar arithmetic of its own —
// which day the chevrons land on is `KeyNavPolicy.shiftPeriod`, what the title
// says is `CalendarFormat`, and what the grid draws is `WeekView` reading the
// two grid policies. This file decides where those things sit and nothing else.
//
// ## Why the verbs leave as signals
//
// The controls do not call `CalendarWindow` directly, even though that is where
// every one of them ends up. The singleton builds this view, so a view that
// reached back into it would be a cycle — and, more usefully, it would be a
// cycle the capture harness cannot break: `tools/capture-harness.sh` builds
// `CalendarView` on its own, with no singleton anywhere, precisely so a picture
// can be posed without a shell. Signals out, properties in.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Core
import qs.Services.Calendar
import qs.Widgets

FloatingWindow {
    id: window

    /// `day`, `week` or `month`. Bound from `CalendarWindow` by whoever built
    /// this, so it survives the window being closed and reopened.
    property string view: "week"

    /// The day the view is built around.
    property string anchorDate: ""

    // --- which way the window is travelling --------------------------------------
    //
    // Two grids share one rectangle and cross-fade between them; `travelSign`
    // is which side the incoming one arrives from. It is `+1` for a widening
    // change (day → week → month) and `-1` for a narrowing one, and it is
    // `KeyNavPolicy.viewSign`'s answer rather than this file's — the same policy
    // that knows what "next week" means is the one that knows which way "next"
    // points, and a slide that disagrees with the date is worse than no slide.
    //
    // It is a stored `int` and not a binding because the sign has to *survive*
    // the change that caused it: by the time the fade is running, `view` is
    // already the new one and the old one is gone.
    property int travelSign: 0

    /// The view we were in, kept only long enough to work out the direction out
    /// of it.
    property string travelFrom: window.view

    onViewChanged: {
        if (window.view === window.travelFrom)
            return;
        window.travelSign = window.keyNav.viewSign(window.travelFrom, window.view);
        // Seam 2's handle on the whole of §10: a transition either fired or it
        // did not, and a log line is the only way to tell from outside a
        // compositor that cannot present a frame (`tools/nested-session.sh`).
        Logger.log("calendar", "transition view " + window.travelFrom
                   + "->" + window.view);
        window.travelFrom = window.view;
    }

    /// The same slide, for a step *within* a scale — next week, last month.
    ///
    /// `periodPhase` runs 0 → 1 over the change and the grids read it as a
    /// distance, so the whole thing is one animated number rather than a
    /// storyboard. It rests at 1, which is what makes a capture safe: nothing
    /// animates until a date actually changes, so the harness never grabs a
    /// grid mid-flight.
    ///
    /// The sign is read off the *dates* rather than off the press, so a `goto`
    /// arriving over IPC travels the same way a chevron click does.
    property real periodPhase: 1
    property string travelDate: window.anchorDate

    onAnchorDateChanged: {
        if (!window.travelDate || !window.anchorDate
            || window.travelDate === window.anchorDate) {
            window.travelDate = window.anchorDate;
            return;
        }
        const sign = window.keyNav.periodSign(
            window.keyNav.time.compare(window.anchorDate, window.travelDate));
        window.travelDate = window.anchorDate;
        if (sign === 0 || !Theme.animateTransforms)
            return;
        window.travelSign = sign;
        periodSlide.restart();
    }

    SequentialAnimation {
        id: periodSlide

        PropertyAction { target: window; property: "periodPhase"; value: 0 }

        NumberAnimation {
            target: window
            property: "periodPhase"
            to: 1
            duration: Theme.duration(CalendarTokens.motionView)
            easing.type: Easing.OutCubic
        }
    }

    /// The selected event's id, or `""`.
    property string selectedId: ""

    /// The overlays, as plain properties so the capture harness can pose either
    /// one without driving a key. At most one is ever true — `setOverlay` is
    /// what enforces that, and it is the only thing that should write them.
    property bool commandOpen: false
    property bool shortcutsOpen: false

    /// What the command menu's field has in it. A property rather than the
    /// menu's own state, for the same reason: a picture of an empty field says
    /// nothing about whether filtering works.
    property string commandQuery: ""

    readonly property bool overlayOpen: window.commandOpen || window.shortcutsOpen

    /// The event whose editor is up, or `""`. Owned by `CalendarWindow` for the
    /// same reason `selectedId` is — a panel that closed with the window would
    /// be a panel `ipc call calendar openEvent` could not reopen onto.
    property string editorId: ""

    readonly property bool editorOpen: window.editorId !== ""

    /// The guest picker's field and dropdown, posed from outside for
    /// tools/capture-harness.sh. A photograph of a closed picker says nothing
    /// about whether searching works, which is the whole claim worth taking a
    /// picture of.
    property string editorQuery: ""
    property bool editorListOpen: false

    /// The editor asked to go away, and why. Out as a signal for the same
    /// reason every other verb is: the singleton owns what is open.
    signal editorDismissed(string reason)

    /// The window wants to go away, and why: `"compositor"` for the close
    /// button or a window-manager kill, `"escape"` for the key. Whoever opened
    /// the window owns tearing it down; this only reports it, and the reason is
    /// what the log line at the other end says.
    signal closeRequested(string reason)

    /// What the chrome asked for. `CalendarWindow` owns all three — see the
    /// header for why they leave as signals rather than as calls.
    signal viewRequested(string name)
    signal dateRequested(string iso)
    signal todayRequested
    signal eventSelected(string id)

    /// Make an event on `iso` starting `startMin` minutes after midnight — the
    /// sidebar's `+`. The view works out *where* (`CreatePolicy`, because the
    /// button has no y coordinate to read a time off) and the singleton owns
    /// the store, for the same reason the other four leave as signals.
    signal createRequested(string iso, int startMin)

    /// Enter on a selection, and Backspace/Delete on one. Out as signals for
    /// the same reason the five above are: the singleton owns the store.
    signal openRequested(string id)
    signal deleteRequested(string id)

    /// An overlay opened or closed — `"command menu"`, `"shortcuts"`. The
    /// window logs it; this file does not, so a posed capture (which has no
    /// singleton at all) is not writing lines into a log nobody is reading.
    signal overlayToggled(string name, bool open)

    onCommandOpenChanged: window.overlayToggled("command menu", window.commandOpen)
    onShortcutsOpenChanged: window.overlayToggled("shortcuts", window.shortcutsOpen)

    /// Show one overlay or hide one. At most one is up at a time: the command
    /// menu and the shortcuts sheet are both modal over the same grid, and two
    /// scrims stacked on one window is a picture of a bug.
    function setOverlay(name: string, open: bool): void {
        if (open) {
            // The query is cleared before the menu exists, so a menu that
            // opens is a menu with an empty field rather than one showing the
            // last thing anybody searched for.
            if (name === "command")
                window.commandQuery = "";
            window.commandOpen = name === "command";
            window.shortcutsOpen = name === "shortcuts";
        } else if (name === "command") {
            window.commandOpen = false;
        } else {
            window.shortcutsOpen = false;
        }
    }

    function closeOverlays(): void {
        window.commandOpen = false;
        window.shortcutsOpen = false;
        // The editor counts as an overlay here even though it is not modal:
        // it is anchored to a chip, and every command that closes overlays
        // also moves the grid the chip is on.
        if (window.editorOpen)
            window.editorDismissed("overlay");
    }

    /// A new hour-long event on the day in view, at the slot `CreatePolicy`
    /// picks. The sidebar's `+` and the `C` key are one call, so a click and a
    /// keystroke cannot land on different minutes.
    function createHere(): void {
        window.createRequested(
            window.anchorDate,
            window.createPolicy.startMinute(
                window.anchorDate, window.todayIso,
                window.keyNav.time.parseMinutes(window.nowStamp),
                CalendarTokens.snapMin, 60));
    }

    /// The events on screen, in the order `Up`/`Down` walk them.
    ///
    /// Which days count is `KeyNavPolicy.visibleRange` and the ordering is
    /// `EventPolicy.sort` underneath `forRange`, so the arrows follow the same
    /// order the grid draws in rather than the file's.
    readonly property var visibleEventIds: {
        const range = window.keyNav.visibleRange(window.view, window.anchorDate,
                                                 window.firstDay);
        if (!range)
            return [];
        const inRange = CalendarStore.policy.forRange(CalendarStore.events,
                                                      range.from, range.to);
        const ids = [];
        for (let i = 0; i < inRange.length; i++)
            ids.push(inRange[i].id);
        return ids;
    }

    /// Everything `KeyNavPolicy.action` needs to answer a key. Assembled here
    /// and nowhere else, so there is one description of "what is on screen".
    ///
    /// `typing` is the command menu's field having the caret: with it set the
    /// policy drops every bare letter, which is what stops `d` typed into a
    /// search box from flipping the calendar to the day view.
    readonly property var keyContext: ({
        "view": window.view,
        "anchorIso": window.anchorDate,
        "nowIso": window.nowStamp,
        "selectedId": window.selectedId,
        "selectedTitle": window.selectedTitle,
        "visibleEventIds": window.visibleEventIds,
        // The editor is not modal, but Escape has to reach it before it
        // reaches the window: a person dismissing an event panel is not asking
        // for the calendar to close behind it.
        "overlayOpen": window.overlayOpen || window.editorOpen,
        // And its fields hold a caret, so bare letters are text rather than
        // shortcuts for exactly as long as it is up.
        "typing": window.commandOpen || window.editorOpen
    })

    /// The selected event's title, for the command menu's "Delete “…”" row.
    readonly property string selectedTitle: {
        if (!window.selectedId)
            return "";
        const event = CalendarStore.policy.byId(CalendarStore.events, window.selectedId);
        return event && event.title ? event.title : "";
    }

    /// One key, resolved by `KeyNavPolicy` and dispatched. Everything the
    /// keyboard does to this surface goes through here, which is what keeps the
    /// keymap a table rather than a scattering of `Keys.on…` handlers.
    function handleKey(event: var): void {
        const decided = window.keyNav.action(event.key, event.modifiers, window.keyContext);
        if (!decided)
            return;
        event.accepted = true;
        switch (decided.kind) {
        case "view":
            window.viewRequested(decided.arg);
            break;
        case "today":
            window.todayRequested();
            break;
        case "period": {
            const next = window.keyNav.shiftPeriod(window.view, window.anchorDate,
                                                   decided.arg);
            if (next)
                window.dateRequested(next);
            break;
        }
        case "select":
            window.eventSelected(decided.arg);
            break;
        case "create":
            window.createHere();
            break;
        case "open":
            window.openRequested(decided.arg);
            break;
        case "delete":
            window.deleteRequested(decided.arg);
            break;
        case "command":
            window.setOverlay("command", !window.commandOpen);
            break;
        case "shortcuts":
            window.setOverlay("shortcuts", !window.shortcutsOpen);
            break;
        case "close":
            // The overlay first, then the window — one Escape per layer, which
            // is the only behaviour that lets a person dismiss a menu without
            // losing the window behind it.
            if (decided.arg === "overlay")
                window.closeOverlays();
            else
                window.closeRequested("escape");
            break;
        }
    }

    /// Runs a command menu row. The ids are `KeyNavPolicy.commands`', so this
    /// switch and that list are the two halves of one table.
    function runCommand(id: string): void {
        window.closeOverlays();
        switch (id) {
        case "view.day":
            window.viewRequested("day");
            break;
        case "view.week":
            window.viewRequested("week");
            break;
        case "view.month":
            window.viewRequested("month");
            break;
        case "today":
            window.todayRequested();
            break;
        case "period.previous":
        case "period.next": {
            const next = window.keyNav.shiftPeriod(
                window.view, window.anchorDate, id === "period.next" ? 1 : -1);
            if (next)
                window.dateRequested(next);
            break;
        }
        case "event.create":
            window.createHere();
            break;
        case "event.open":
            if (window.selectedId)
                window.openRequested(window.selectedId);
            break;
        case "event.delete":
            if (window.selectedId)
                window.deleteRequested(window.selectedId);
            break;
        case "help.shortcuts":
            window.setOverlay("shortcuts", true);
            break;
        }
    }

    /// The wall clock the now-line and the today-circle are drawn from,
    /// `"2026-08-18T13:40"`.
    ///
    /// Always `shellStamp`, handed down by whoever built the window —
    /// `CalendarWindow.nowStamp`, which is the surface's one clock (including
    /// under `--cal-now`, which freezes it there), so the singleton's idea of
    /// today and this view's cannot drift apart.
    readonly property string nowStamp: window.shellStamp

    /// The clock the builder handed down. Assigned rather than read off the
    /// singleton directly, because a view is a plain component and importing
    /// the module it lives in to reach its own owner is a circle.
    property string shellStamp: ""

    readonly property string todayIso: window.keyNav.time.dayOf(window.nowStamp)

    /// The locale's first weekday, `Locale.Sunday === 0` — the same source
    /// `Surfaces/Drawers/Cards/CalendarCard.qml` reads, so the shell's two
    /// calendars start their weeks on the same day.
    readonly property int firstDay: Qt.locale().firstDayOfWeek

    /// A 24-hour clock or not, resolved once for the whole shell in
    /// `Core/TimeFormat.qml`. Read here and handed down, so one calendar cannot
    /// show two clocks.
    readonly property bool use24: TimeFormat.rule.is24Hour(
        TimeFormat.preference, Qt.locale().timeFormat(Locale.ShortFormat))

    property KeyNavPolicy keyNav: KeyNavPolicy {}
    property CreatePolicy createPolicy: CreatePolicy {}
    property UpcomingPolicy upcomingPolicy: UpcomingPolicy {}
    property CalendarFormat railFormat: CalendarFormat {}
    property SyncStatusPolicy syncPolicy: SyncStatusPolicy {}

    /// The Google half's four status properties, handed in the way every other
    /// piece of state is — `GoogleSync` is a singleton, and this view is also
    /// built by `tools/capture-harness.sh` with no singleton anywhere, so
    /// reading it here would make the connected state unphotographable. It
    /// arrives as one object because it is read as one: no field of it means
    /// anything without the others.
    ///
    /// The default is the off state, which is what an unbound view draws.
    property var syncState: ({
        "status": "off", "account": "", "lastSync": "",
        "error": "", "connecting": false
    })

    /// What the rail's Google block draws, and what the toolbar's dot is handed
    /// — `SyncStatusPolicy`'s answer, so the four states are a table checked in
    /// `tests/tst_syncstatuspolicy.qml` rather than branches in two surfaces.
    ///
    /// An object literal rather than a function body: a binding built inside a
    /// function does not see the properties the body read, so a status that
    /// changed would leave the rail showing the old word.
    readonly property var syncFacts: ({
        "status": window.syncState.status ?? "off",
        "account": window.syncState.account ?? "",
        "lastSync": window.syncState.lastSync ?? "",
        // Recomputed as the shell's clock ticks, which is what turns "just now"
        // into "3 min ago" with nothing driving it.
        "ago": window.railFormat.relativeAgo(window.syncState.lastSync ?? "",
                                             window.nowStamp),
        "error": window.syncState.error ?? "",
        "connecting": window.syncState.connecting === true
    })

    readonly property var syncBlock: window.syncPolicy.block(window.syncFacts)

    /// *Sync now* and *Connect*. Signals for the reason the header gives: the
    /// singleton that owns `GoogleSync` is the one that built this view.
    signal syncRequested()
    signal syncConnectRequested()

    /// When one of the sidebar's upcoming rows happens. `CalendarFormat` spells
    /// it; this only unpacks the event the rail is holding.
    function upcomingWhen(event: var): string {
        if (!event)
            return "";
        return window.railFormat.upcomingWhen(event.start, event.allDay === true,
                                              window.todayIso, window.use24);
    }

    title: "forest-shell — calendar"
    // Stated rather than assumed: the window exists only while it is open, so
    // it is mapped as soon as it is built, and the assignment the compositor
    // makes when the close button is hit is what `wasShown` below reads.
    visible: true
    implicitWidth: 1180
    implicitHeight: 760
    minimumSize: Qt.size(900, 600)
    color: Theme.bgBase

    // A window that has been shown and is now not is a window that was closed.
    // The flag is what keeps the not-yet-mapped state — visible is false for a
    // moment after construction — from reading as a close.
    property bool wasShown: false
    onVisibleChanged: {
        if (window.visible)
            window.wasShown = true;
        else if (window.wasShown)
            window.closeRequested("compositor");
    }

    Item {
        id: page

        anchors.fill: parent
        focus: true

        // Every key, from wherever the focus is. An unhandled key walks up the
        // focus chain, so the window needs exactly one handler and no control
        // inside needs to know what the keyboard does — including the command
        // menu's own field, which keeps only the three keys that are about its
        // list and lets the rest bubble to here.
        Keys.onPressed: event => window.handleKey(event)

        // --- the body ---------------------------------------------------------
        //
        // Sidebar down the left at its full height, toolbar across what is
        // left, grid under it. The sidebar is full height rather than starting
        // under the toolbar because the toolbar's title names the *grid's*
        // period, and a title that spanned the sidebar too would look like it
        // named both.

        Rectangle {
            id: sidebar

            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: CalendarTokens.sidebarW
            // The chrome plane. `CalendarTokens.chromeGround` carries the
            // measurement: `Theme.surface` beside a `bgBase` canvas was a 4%
            // step, which is a hairline doing the work of a zone.
            color: CalendarTokens.chromeGround

            /// The sidebar's own share of the chrome band, the same 52 tall as
            /// the toolbar beside it and closed by the same hairline, so the
            /// window opens with one bar across its whole width instead of a
            /// toolbar that stops at a column of empty sidebar.
            ///
            /// **What fills it is the mini-month's own heading**, hung from the
            /// toolbar title's baseline so the two headings read as one line of
            /// type across the divider. An earlier pass spent the band on a
            /// mark, a wordmark and a create button — the trio Notion puts
            /// there — and paid for it twice: the window's one *creating*
            /// control sat in the column that holds its two *filtering* lists,
            /// and the month name it displaced landed 30px below the title
            /// beside it, close enough to be measured against it and never
            /// close enough to match. The create button is on the toolbar now;
            /// a window this small does not need to be told its own name.
            ///
            /// This item is the hairline alone — the heading is drawn by
            /// `mini` below, which owns the month it names.
            Item {
                id: sidebarHeader

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: CalendarTokens.toolbarH

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.borderSubtle
                }
            }

            /// The map, spanning the chrome band: its heading sits *in* the
            /// band, its grid starts `space2` under the hairline. Outside
            /// `sidebarBody` because that item's whole job is the inset margin
            /// under the band, and this one is the thing that crosses it.
            MiniMonth {
                id: mini

                anchors.left: parent.left
                anchors.leftMargin: CalendarTokens.sidebarPad
                anchors.right: parent.right
                anchors.rightMargin: CalendarTokens.sidebarPad + 1
                anchors.top: parent.top
                height: mini.implicitHeight

                headingH: CalendarTokens.toolbarH + Theme.space2
                headingBaseline: CalendarTokens.titleBaseline

                view: window.view
                anchorDate: window.anchorDate
                todayIso: window.todayIso
                firstDay: window.firstDay

                onDayRequested: iso => window.dateRequested(iso)
            }

            /// Everything under that band, inset by one `space4` on every
            /// edge. `clip` because the calendar list is a fixed number of rows
            /// against a window that can be dragged to 600px tall — a list that
            /// spilled would draw over the compositor's own bottom edge rather
            /// than stopping at the sidebar's.
            Item {
                id: sidebarBody

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: mini.bottom
                anchors.bottom: parent.bottom
                // The horizontal inset is the map's, so that every left edge in
                // this column is one edge; the vertical one is its own, because
                // `sidebarPad` is arithmetic about seven cells and has nothing
                // to say about how much air a list wants above it — and three
                // extra pixels at each end is one calendar row off the bottom.
                anchors.leftMargin: CalendarTokens.sidebarPad
                anchors.rightMargin: CalendarTokens.sidebarPad + 1
                anchors.topMargin: Theme.space4
                anchors.bottomMargin: Theme.space4
                clip: true

                /// **The rail is separated by space and headings, not by three
                /// identical hairlines.**
                ///
                /// It used to draw a rule between the map and the calendars, a
                /// second between the calendars and *Upcoming*, and a third
                /// above the account footer — the same 1px `borderSubtle` line
                /// at three different joins. A rule repeated at every join
                /// stops being a division and becomes a texture: the column
                /// read as four undifferentiated slabs, and nothing said which
                /// of the joins was the structural one.
                ///
                /// Two of the three are gone. The lists carry their own caps
                /// headings — `CALENDARS`, `UPCOMING` — and a heading with air
                /// above it is already a division; adding a line to it is
                /// saying the same thing twice. The one rule left is the
                /// account footer's, which is the only join that is not two
                /// lists in a row: it closes the panel the way the toolbar's
                /// hairline closes the chrome band, and being the column's only
                /// line is exactly what makes it read as that.
                ///
                /// The calendars. Static on purpose: there are no calendar
                /// accounts to switch off yet, so every row is drawn checked
                /// and nothing here takes a click. A row that toggled a filter
                /// nothing reads would be worse than a row that plainly does
                /// not move.
                ///
                /// **The rail is budgeted rather than stacked.** Three lists,
                /// a footer and four gaps have to clear a 760px window with the
                /// map taking 270 of it, so the rows are sized from what is
                /// left: 26 for a calendar, 34 for an upcoming event, and the
                /// inert *Add calendar* row is gone. It was the one line here
                /// that promised something — a row with a `+` on it says a
                /// dialog opens — and spending 32px of a full rail on a promise
                /// nothing keeps, while a live list of what is next got cut off
                /// below it, is the wrong trade twice over.
                Column {
                    id: calendarList

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: Theme.space2

                    /// Bounded against the footer rather than left to run.
                    /// Eight rows plus the add row clear a 760px window with
                    /// room to spare and do not clear the 560px minimum, and a
                    /// `Column` has no opinion about that — it would simply
                    /// draw through the account block and out of the panel.
                    ///
                    /// **Whole rows, and the heading is not one of them.** The
                    /// bound is a pixel count and `clip` is honest about it, so
                    /// the list used to end in whatever fraction of a row the
                    /// arithmetic left — a 6px sliver of a colour swatch under
                    /// the last name, which reads as a rendering fault rather
                    /// than as a list that ran out of room. Floored to the row
                    /// pitch it ends on a row, and the leftover pixels become
                    /// air above *UPCOMING*, where they are invisible. The
                    /// Google block below moves this bound whenever sync is
                    /// switched on, which is what made the sliver a picture
                    /// somebody had to look at.
                    readonly property int rowH: 26
                    readonly property int headingH: 22

                    height: Math.min(
                        calendarList.implicitHeight,
                        calendarList.headingH
                        + Math.max(0, Math.floor(
                            (upcoming.y - calendarList.y - Theme.space3
                             - calendarList.headingH) / calendarList.rowH))
                          * calendarList.rowH)
                    clip: true

                    Item {
                        width: calendarList.width
                        height: calendarList.headingH

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "CALENDARS"
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(Theme.capsSize)
                            font.weight: Theme.weightMedium
                            font.letterSpacing: Theme.capsTrackingEm * Theme.pt(Theme.capsSize)
                        }
                    }

                    Repeater {
                        model: mini.policy.rows(CalendarTokens.hues)

                        delegate: Item {
                            id: calendarRow

                            required property var modelData

                            width: calendarList.width
                            height: calendarList.rowH

                            /// The hover wash the rest of the shell's list rows
                            /// wear. It is feedback, not a promise: the row
                            /// still takes no click, and the wash is what says
                            /// the pointer is on *this* calendar rather than
                            /// the one above it while the eye runs the column.
                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: -Theme.space2
                                anchors.rightMargin: -Theme.space2
                                radius: Theme.radiusSm
                                color: calendarHover.containsMouse
                                       ? CalendarTokens.chromeHover : "transparent"
                                opacity: calendarHover.containsMouse ? 1 : 0

                                Behavior on opacity {
                                    enabled: Theme.animateTransforms
                                    NumberAnimation {
                                        duration: Theme.duration(Theme.motionFast)
                                    }
                                }
                            }

                            MouseArea {
                                id: calendarHover

                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                            }

                            /// A filled, ticked box rather than the 10px dot
                            /// the first pass drew. The dot said *this
                            /// calendar is that colour*; the box says that and
                            /// *it is switched on*, which is the second half
                            /// of what the row is for — and 10px is too small
                            /// to carry a tick.
                            Rectangle {
                                id: swatch

                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 15
                                height: 15
                                radius: 4
                                color: CalendarTokens.bar(calendarRow.modelData.index)

                                Icon {
                                    anchors.centerIn: parent
                                    name: "check"
                                    size: 11
                                    color: Theme.bgBase
                                }
                            }

                            Text {
                                anchors.left: swatch.right
                                anchors.leftMargin: Theme.space3
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: calendarRow.modelData.label
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                font.family: Theme.fontUi
                                font.pointSize: Theme.pt(13)
                                font.weight: Theme.weightRegular
                            }
                        }
                    }

                }

                /// What is next, standing between the calendars list and the
                /// footer — see `UpcomingPolicy.qml` for why the rail carries
                /// it rather than being spaced out to hide the gap.
                ///
                /// Pinned above the account row rather than flowing under the
                /// calendars, so the rail has a fixed skeleton at every window
                /// height: map at the top, footer at the floor, and the two
                /// lists between them, of which only the calendars one is
                /// allowed to lose rows when the window is short.
                Column {
                    id: upcoming

                    anchors.left: parent.left
                    anchors.right: parent.right
                    // The Google block when there is one, the footer when there
                    // is not: the rail's skeleton is fixed from the floor up, so
                    // a shell with sync switched off draws exactly the column it
                    // drew before this existed.
                    anchors.bottom: google.visible ? google.top : account.top
                    anchors.bottomMargin: Theme.space4

                    readonly property var rows:
                        window.upcomingPolicy.next(CalendarStore.events,
                                                   window.nowStamp,
                                                   window.upcomingPolicy.defaultLimit)

                    /// **A heading with nothing under it is worse than no
                    /// heading.** A calendar with nothing coming up drew
                    /// `UPCOMING` over 200px of empty rail, which reads as a
                    /// list that failed to load rather than as a diary with
                    /// nothing in it. The whole section leaves together, and
                    /// the grid's own empty hint is where "there is nothing
                    /// here" gets said once.
                    visible: upcoming.rows.length > 0

                    /// The heading carries the join on its own — see the
                    /// calendars list above for why the hairline that used to
                    /// sit here went. The row is 34 rather than 28 so the air
                    /// it took is air the heading keeps.
                    Item {
                        width: upcoming.width
                        height: 34

                        Text {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            text: "UPCOMING"
                            color: Theme.textMuted
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(Theme.capsSize)
                            font.weight: Theme.weightMedium
                            font.letterSpacing: Theme.capsTrackingEm * Theme.pt(Theme.capsSize)
                        }
                    }

                    Repeater {
                        model: upcoming.rows

                        /// A row is a hue rail, a title and when. The rail is
                        /// 2px and full height rather than the list's rounded
                        /// swatch: a checkbox above and a checkbox here would
                        /// say these rows can be switched off too, and they
                        /// cannot — they are the grid's events, seen from the
                        /// side.
                        delegate: Item {
                            id: upcomingRow

                            required property var modelData

                            /// **38, and the two lines inside it are set 3
                            /// apart.** At 34 with a 1px lead the row's own two
                            /// lines were as close to each other as the row was
                            /// to its neighbour — "All day" sat a hair under
                            /// the title above it and a hair over the title
                            /// below, so a three-row list read as six loose
                            /// lines. The pairing has to be visible before the
                            /// list is: 3 inside against 8 between is the
                            /// smallest ratio that reads as two lines belonging
                            /// to one event.
                            width: upcoming.width
                            height: 38

                            Rectangle {
                                id: upcomingRail

                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 2
                                height: 26
                                radius: 1
                                color: CalendarTokens.bar(
                                    CalendarTokens.hues.forEvent(upcomingRow.modelData))
                            }

                            Column {
                                anchors.left: upcomingRail.right
                                anchors.leftMargin: Theme.space3
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 3

                                Text {
                                    width: parent.width
                                    text: upcomingRow.modelData.title
                                    color: Theme.textPrimary
                                    elide: Text.ElideRight
                                    font.family: Theme.fontUi
                                    font.pointSize: Theme.pt(12.5)
                                    font.weight: Theme.weightRegular
                                }

                                Text {
                                    width: parent.width
                                    text: window.upcomingWhen(upcomingRow.modelData)
                                    color: Theme.textMuted
                                    elide: Text.ElideRight
                                    font.family: Theme.fontUi
                                    font.pointSize: Theme.pt(11)
                                    font.weight: Theme.weightRegular
                                    font.features: CalendarTokens.tabularFigures
                                }
                            }
                        }
                    }
                }

                /// The Google half, drawn as **the other source row** — the
                /// same tile, the same two lines, the same text origin as
                /// *This device* directly beneath it. Two members of one class
                /// get one treatment.
                ///
                /// It used to get a full-rank `GOOGLE CALENDAR` heading, peer
                /// to *CALENDARS* and *UPCOMING*, over an address in the
                /// sidebar's top ink. That was a feature advertisement for
                /// plumbing: a status readout is not a section, and *This
                /// device* had already settled how a calendar source is
                /// rendered here — a tile, a name, a dim subtitle, no heading
                /// at all. The rank is flipped with it: the sync time is the
                /// only string on this row that ever changes, so it takes the
                /// line *This device* spends on its name, and the address —
                /// which never changes and cannot be acted on — takes the dim
                /// one under it. `SyncStatusPolicy.block` decides both.
                ///
                /// The rule above it is the rail's only divider, and it now
                /// separates the pair of sources from *UPCOMING* rather than
                /// separating the two siblings from each other. `account`'s
                /// own hairline stands down whenever this row is drawn.
                Item {
                    id: google

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: account.top
                    // The footer's height exactly: whatever else these two rows
                    // disagree about, their pitch is not it.
                    height: 52
                    visible: window.syncBlock.visible

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: Theme.borderSubtle
                    }

                    Rectangle {
                        id: googleMark

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 1
                        width: 28
                        height: 28
                        radius: Theme.radiusSm
                        color: Qt.alpha(Theme.accentPrimary, 0.14)

                        /// A cloud against the footer's hard drive: the tile
                        /// says *which kind of source*, which is the one thing
                        /// that genuinely differs between these two rows. State
                        /// stays in the words, where it can be read rather than
                        /// decoded — a tile that changed colour would be the
                        /// invisible dot again, one size up.
                        Icon {
                            anchors.centerIn: parent
                            name: "cloud"
                            size: 15
                            color: Theme.accentPrimary
                        }
                    }

                    Column {
                        anchors.left: googleMark.right
                        anchors.leftMargin: Theme.space3
                        anchors.right: connectButton.visible
                                       ? connectButton.left : parent.right
                        anchors.rightMargin: connectButton.visible
                                             ? Theme.space2 : 0
                        // 248px of rail, minus the tile, minus the button, is
                        // what *Not connected* has to fit inside — so the
                        // button is padded to `space2` rather than the `space3`
                        // a toolbar control gets. At `space3` the title elided
                        // to "Not connect…", which is the one string in this
                        // row nobody can guess the end of.
                        anchors.verticalCenter: googleMark.verticalCenter
                        spacing: 1

                        /// What the last round did. The row's payload, at the
                        /// row's top rank.
                        Text {
                            width: parent.width
                            text: window.syncBlock.title
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12.5)
                            font.weight: Theme.weightMedium
                            font.features: CalendarTokens.tabularFigures
                        }

                        /// Whose account it is — or, when a round has failed,
                        /// what went wrong, in the one ink this shell reserves
                        /// for urgent. The address is what a failure displaces:
                        /// it is the least useful string on the row, and
                        /// *This device* proves the row reads without one.
                        Text {
                            width: parent.width
                            text: window.syncBlock.subtitle
                            color: window.syncBlock.tone === "error"
                                   ? Theme.accentEmber : Theme.textMuted
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11)
                            font.weight: Theme.weightRegular
                        }
                    }

                    /// *Connect*, and only in the state that has nothing to
                    /// connect with. The outlined ghost the toolbar's *Today*
                    /// button is — the same kind of thing, one deliberate
                    /// press — sitting on the row it belongs to rather than
                    /// across a gutter from it.
                    Rectangle {
                        id: connectButton

                        anchors.right: parent.right
                        anchors.verticalCenter: googleMark.verticalCenter
                        width: connectLabel.implicitWidth + Theme.space2 * 2
                        height: 28
                        radius: Theme.radiusSm
                        visible: window.syncBlock.action === "Connect"
                        color: connectPointer.containsMouse
                               ? CalendarTokens.chromeHover : "transparent"
                        border.width: 1
                        border.color: Theme.borderSubtle

                        Behavior on color {
                            enabled: Theme.animateTransforms
                            ColorAnimation {
                                duration: Theme.duration(Theme.motionFast)
                            }
                        }

                        Text {
                            id: connectLabel

                            anchors.centerIn: parent
                            text: window.syncBlock.action
                            color: Theme.textPrimary
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11.5)
                            font.weight: Theme.weightMedium
                        }

                        MouseArea {
                            id: connectPointer

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.syncConnectRequested()
                        }
                    }
                }

                /// Whose calendars these are, pinned to the floor of the
                /// panel.
                ///
                /// The sidebar used to end with its last colour swatch, which
                /// on a full-height window left roughly 380px of bare surface
                /// under it — a third of the column saying nothing. Notion ends
                /// this column with the account the calendars belong to, and
                /// the reason is structural rather than decorative: a list of
                /// eight calendars raises the question *whose*, and a panel
                /// that never answers it reads as unfinished no matter how the
                /// rows above are spaced.
                ///
                /// It answers honestly. There are no cloud accounts here — the
                /// events live in one file on this machine — so the row says
                /// that, and the count comes from the hue table rather than
                /// from a number typed into a mock.
                Item {
                    id: account

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 52

                    /// The rule that closes the rail — and it stands down when
                    /// the Google row is drawn, because that row brings its own
                    /// and two sources of the same kind are not separated from
                    /// each other. One rule above the pair, none between them.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: Theme.borderSubtle
                        visible: !google.visible
                    }

                    Rectangle {
                        id: accountMark

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 1
                        width: 28
                        height: 28
                        radius: Theme.radiusSm
                        color: Qt.alpha(Theme.accentPrimary, 0.14)

                        Icon {
                            anchors.centerIn: parent
                            name: "hard-drive"
                            size: 15
                            color: Theme.accentPrimary
                        }
                    }

                    Column {
                        anchors.left: accountMark.right
                        anchors.leftMargin: Theme.space3
                        anchors.right: parent.right
                        anchors.verticalCenter: accountMark.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: "This device"
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(12.5)
                            font.weight: Theme.weightMedium
                        }

                        Text {
                            width: parent.width
                            text: CalendarTokens.hues.count + " calendars · local"
                            color: Theme.textMuted
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(11)
                            font.weight: Theme.weightRegular
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.borderSubtle
            }
        }

        CalendarToolbar {
            id: toolbar

            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: parent.top
            height: CalendarTokens.toolbarH
            // Above the grid, and only just: the sync control's hover label
            // hangs below the chrome band's hairline, and a sibling declared
            // after this one would otherwise paint over it. The overlays stay
            // above at z 40.
            z: 2

            view: window.view
            anchorDate: window.anchorDate
            todayIso: window.todayIso
            firstDay: window.firstDay
            syncFacts: window.syncFacts

            onViewRequested: name => window.viewRequested(name)
            onSyncRequested: window.syncRequested()
            onTodayRequested: window.todayRequested()
            onCreateRequested: window.createHere()
            onStepRequested: delta => {
                const next = window.keyNav.shiftPeriod(window.view, window.anchorDate, delta);
                if (next)
                    window.dateRequested(next);
            }
        }

        /// The grid. `dayCount` is the only thing that separates the day view
        /// from the week view — see `WeekView.qml`'s header — so both are this
        /// one instance, and stepping between them is a property change rather
        /// than a component swap that would drop the scroll position.
        WeekView {
            id: grid

            anchors.left: sidebar.right
            anchors.right: parent.right
            anchors.top: toolbar.bottom
            anchors.bottom: parent.bottom

            /// The crossfade half of a view change. See `window.travelSign` for
            /// the slide half and for why the sign is a policy's answer.
            ///
            /// `visible` follows the opacity rather than the view, so the grid
            /// on its way out keeps painting until it has finished leaving —
            /// binding `visible` to `window.view` would cut the fade off on its
            /// first frame, which is how an earlier pass "had a transition" that
            /// nothing could see.
            readonly property bool shown: window.view !== "month"

            opacity: grid.shown ? 1 : 0
            visible: grid.opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.duration(CalendarTokens.motionView)
                    easing.type: Easing.OutCubic
                }
            }

            transform: Translate {
                x: Theme.animateTransforms
                   ? ((1 - grid.opacity) * (grid.shown ? window.travelSign
                                                       : -window.travelSign)
                      + (1 - window.periodPhase) * window.travelSign)
                     * CalendarTokens.motionSlide
                   : 0
            }

            dayCount: window.view === "day" ? 1 : 7
            anchorDate: window.anchorDate
            firstDay: window.firstDay
            todayIso: window.todayIso
            nowStamp: window.nowStamp
            events: CalendarStore.events
            selectedId: window.selectedId
            use24: window.use24

            // A click on a chip opens it. `openRequested` selects on the way
            // through (`CalendarWindow.openEvent`), so this is the same one
            // gesture Enter is rather than a select that needs a second click
            // to become an open — which is what the reference does and what a
            // calendar with an editor should do.
            onEventActivated: id => window.openRequested(id)
        }

        /// The month grid, in the same rectangle as the week one and swapped by
        /// `visible` rather than a `Loader`. Both views are cheap and neither
        /// holds state a rebuild would lose — but the week view *does* hold a
        /// scroll position, and a `Loader` would drop it every time somebody
        /// looked at the month and came back.
        MonthView {
            id: monthGrid

            anchors.fill: grid

            readonly property bool shown: window.view === "month"

            opacity: monthGrid.shown ? 1 : 0
            visible: monthGrid.opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.duration(CalendarTokens.motionView)
                    easing.type: Easing.OutCubic
                }
            }

            transform: Translate {
                x: Theme.animateTransforms
                   ? ((1 - monthGrid.opacity) * (monthGrid.shown ? window.travelSign
                                                                 : -window.travelSign)
                      + (1 - window.periodPhase) * window.travelSign)
                     * CalendarTokens.motionSlide
                   : 0
            }

            anchorDate: window.anchorDate
            firstDay: window.firstDay
            todayIso: window.todayIso
            nowStamp: window.nowStamp
            events: CalendarStore.events
            selectedId: window.selectedId
            use24: window.use24

            onEventActivated: id => window.openRequested(id)

            // "+N more" is a day too full to draw, so the answer is the day
            // view on that day rather than a popover of the overflow: the
            // surface already has a view whose whole job is one day, and a
            // second place to read a day's events is a second layout to keep
            // honest. Logged with its own reason, because a `goto` from here
            // and one from the mini-month are the same line otherwise.
            onMoreActivated: iso => {
                if (!iso)
                    return;
                Logger.log("calendar", "goto " + iso + " (more)");
                window.dateRequested(iso);
                window.viewRequested("day");
            }
        }

        // --- the overlays -----------------------------------------------------
        //
        // Last in the file, so they are last in the stacking order and cover
        // the grid, the toolbar and the sidebar alike — an overlay that a
        // toolbar button could still be clicked through is the #187 failure
        // wearing different clothes.
        //
        // `Loader`s and not `visible`, because both are keyboard surfaces:
        // building one is what gives it the caret, and destroying it is what
        // gives the caret back rather than leaving a hidden field holding it.

        /// The event editor, anchored to the chip it belongs to.
        ///
        /// Hosted here rather than in `WeekView` — which is where the
        /// quick-create panel lives — because this one opens over the month
        /// grid too, and over a day the week grid is not showing at all
        /// (`ipc call calendar openEvent` can name any event in the file). The
        /// grid still owns the chip's rectangle; it just hands it out through
        /// `chipAnchor` rather than being the thing that places the panel.
        ///
        /// The anchor is worked out when the editor opens and not on every
        /// frame after: `chipAnchor` reads the grid's scroll offset inside a
        /// function, so this binding does not depend on it. That is the
        /// behaviour worth having anyway — a panel that slid up the window
        /// while the grid scrolled under it would be a panel nobody could
        /// finish typing into.
        readonly property rect editorAnchor: {
            if (!window.editorOpen)
                return Qt.rect(0, 0, 0, 0);
            if (grid.visible) {
                const chip = grid.chipAnchor(window.editorId);
                if (chip.width > 0) {
                    const at = grid.mapToItem(page, chip.x, chip.y);
                    return Qt.rect(at.x, at.y, chip.width, chip.height);
                }
            }
            // The month view, or an event on a day the grid is not showing.
            // Anchored on the grid's own top-left, so the panel still lands
            // over the calendar rather than in the window's corner.
            const origin = grid.mapToItem(page, 0, 0);
            return Qt.rect(origin.x + Theme.space4, origin.y + Theme.space4, 0, 0);
        }

        Loader {
            id: editorLoader

            readonly property var placement: window.createPolicy.popoverAnchor(
                page.editorAnchor,
                editorLoader.width > 0 ? editorLoader.width : 360,
                editorLoader.height, page.width, page.height,
                Theme.space3, Theme.space3)

            active: window.editorOpen
            z: 40
            x: editorLoader.placement.x
            y: editorLoader.placement.y

            sourceComponent: EventEditor {
                event: CalendarStore.policy.byId(CalendarStore.events, window.editorId)
                hue: CalendarTokens.hues.forEvent(
                    CalendarStore.policy.byId(CalendarStore.events, window.editorId))
                contacts: CalendarStore.contacts
                use24: window.use24
                flipped: editorLoader.placement.flipped
                caretY: editorLoader.placement.caretY

                // One way down and nothing back. These two are a *pose* — the
                // state a fresh panel opens in — not a mirror of what the
                // field currently holds. Written back, they would outlive the
                // panel: the next event's picker would open holding the last
                // one's query, which is exactly what happened when they were
                // bound both ways (measured at seam 2 — a rebuilt panel
                // searched for "mimi").
                guestQuery: window.editorQuery
                guestListOpen: window.editorListOpen

                onRenamed: title => CalendarStore.renameEvent(window.editorId, title)
                onRecoloured: colour => CalendarStore.recolourEvent(window.editorId, colour)
                onGuestAdded: contactId => CalendarStore.addGuest(window.editorId, contactId)
                onGuestRemoved: contactId => CalendarStore.removeGuest(window.editorId, contactId)
                // Out as the window's own signal, so a delete from the panel
                // and a delete from the command menu are one code path.
                onDeleted: window.deleteRequested(window.editorId)
                // Back into the one keymap. The panel does not know what a
                // chord means; `KeyNavPolicy` does, and it accepts the event
                // only for the chords it claims — so the ones it does not are
                // still the text field's.
                onChordPressed: keyEvent => window.handleKey(keyEvent)

                onDismissed: reason => window.editorDismissed(reason)
            }
        }

        Loader {
            id: commandLoader

            anchors.fill: parent
            active: window.commandOpen

            sourceComponent: CommandMenu {
                keyNav: window.keyNav
                ctx: window.keyContext

                // Bound both ways: the harness poses a query by setting
                // `commandQuery`, and typing writes back the same string.
                query: window.commandQuery
                onQueryChanged: window.commandQuery = query

                onAccepted: commandId => window.runCommand(commandId)
                onDismissed: window.setOverlay("command", false)
            }
        }

        Loader {
            id: shortcutsLoader

            anchors.fill: parent
            active: window.shortcutsOpen

            sourceComponent: ShortcutsSheet {
                keyNav: window.keyNav
                onDismissed: window.setOverlay("shortcuts", false)
            }
        }
    }
}
