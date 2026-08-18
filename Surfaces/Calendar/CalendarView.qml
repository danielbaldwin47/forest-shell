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

    /// What the now-line should believe the time is, as `"2026-08-18T13:40"`,
    /// or `""` for the real clock.
    ///
    /// This exists for tools/capture-harness.sh and it is not a debugging
    /// nicety: a now-line drawn from the wall clock means no two captures of
    /// this surface are ever the same picture, so a diff between two runs is
    /// unreadable. `--cal-now` freezes it, exactly as `--lock-state` poses PAM.
    property string nowOverride: ""

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
        "overlayOpen": window.overlayOpen,
        "typing": window.commandOpen
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
    /// `nowOverride` wins outright when it is set. A picture whose now-line is
    /// frozen at 13:40 on the 18th but whose today-circle sits on whatever day
    /// the machine happens to be running is two clocks in one window, and the
    /// harness would have posed half a surface.
    ///
    /// Otherwise it is `Core/Time.qml`, which ticks once a minute for the whole
    /// shell — the now-line moves 0.93px a minute, so a per-minute tick is
    /// exactly the resolution it can show.
    readonly property string nowStamp: {
        if (window.nowOverride.length > 0)
            return window.nowOverride;
        const now = Time.now;
        return window.keyNav.time.formatStamp(
            window.keyNav.time.dayIso(now.getFullYear(), now.getMonth() + 1, now.getDate()),
            now.getHours() * 60 + now.getMinutes());
    }

    readonly property string todayIso: window.nowStamp.split("T")[0]

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
            color: Theme.surface

            /// The sidebar's own share of the chrome band, the same 52 tall as
            /// the toolbar beside it and closed by the same hairline, so the
            /// window opens with one bar across its whole width instead of a
            /// toolbar that stops at a column of empty sidebar.
            ///
            /// That emptiness was the loudest thing about the first pass: an
            /// application with nothing above its first heading reads as a
            /// panel someone cropped out of a bigger window. What belongs there
            /// is what the window *is* and the one thing it makes — a mark, a
            /// name, and a create button — which is the same trio Notion puts
            /// at the top of its own sidebar.
            Item {
                id: sidebarHeader

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: CalendarTokens.toolbarH

                Icon {
                    id: mark

                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space4
                    anchors.verticalCenter: parent.verticalCenter
                    name: "calendar-days"
                    size: 17
                    color: Theme.accentPrimary
                }

                /// The wordmark in the display face, matching the toolbar's
                /// month title across the divider — the two of them on one
                /// line is what makes the band read as one bar.
                Text {
                    id: wordmark

                    anchors.left: mark.right
                    anchors.leftMargin: Theme.space2
                    y: CalendarTokens.titleBaseline - wordmark.baselineOffset
                    text: "Calendar"
                    color: Theme.textPrimary
                    font.family: Theme.fontDisplay
                    font.pointSize: Theme.pt(15)
                    font.weight: Theme.weightDisplay
                }

                /// New event. It was a filled accent tile, on the argument that
                /// the one thing the window makes deserves the one saturated
                /// background — and the picture said otherwise: a 28px block of
                /// `accentPrimary` was the loudest pixel in a 1180px window,
                /// louder than today's column, today's disc in the map below it
                /// and every event on the grid. In a calendar, saturation has
                /// exactly one job, which is saying *here is now*; a control
                /// that outshouts it is a control competing with the data.
                ///
                /// So it wears the chrome's own hairline-and-fill treatment,
                /// the same box as the toolbar's chevrons and Today, and keeps
                /// its rank in the *glyph* — teal strokes rather than a teal
                /// field, which is a tenth of the area at the same hue.
                Rectangle {
                    id: createButton

                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space4 + 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: CalendarTokens.controlH
                    height: CalendarTokens.controlH
                    radius: Theme.radiusSm
                    color: createPointer.containsMouse ? Theme.surfaceOverlay : Theme.surfaceRaised
                    border.width: 1
                    border.color: Theme.borderSubtle

                    Behavior on color {
                        enabled: Theme.animateTransforms
                        ColorAnimation { duration: Theme.duration(Theme.motionFast) }
                    }

                    Icon {
                        anchors.centerIn: parent
                        name: "plus"
                        size: 16
                        color: Theme.accentPrimary
                    }

                    MouseArea {
                        id: createPointer

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.createHere()
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Theme.borderSubtle
                }
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
                anchors.top: sidebarHeader.bottom
                anchors.bottom: parent.bottom
                anchors.margins: Theme.space4
                anchors.rightMargin: Theme.space4 + 1
                clip: true

                MiniMonth {
                    id: mini

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: mini.implicitHeight

                    view: window.view
                    anchorDate: window.anchorDate
                    todayIso: window.todayIso
                    firstDay: window.firstDay

                    onDayRequested: iso => window.dateRequested(iso)
                }

                /// The hairline between the map and the legend. The sidebar
                /// holds two unrelated lists and nothing but a gap would say
                /// where one ends.
                Rectangle {
                    id: sidebarRule

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: mini.bottom
                    anchors.topMargin: Theme.space4
                    height: 1
                    color: Theme.borderSubtle
                }

                /// The calendars. Static on purpose: there are no calendar
                /// accounts to switch off yet, so every row is drawn checked
                /// and nothing here takes a click. A row that toggled a filter
                /// nothing reads would be worse than a row that plainly does
                /// not move.
                Column {
                    id: calendarList

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: sidebarRule.bottom
                    anchors.topMargin: Theme.space4

                    /// Bounded against the footer rather than left to run.
                    /// Eight rows plus the add row clear a 760px window with
                    /// room to spare and do not clear the 560px minimum, and a
                    /// `Column` has no opinion about that — it would simply
                    /// draw through the account block and out of the panel.
                    height: Math.min(calendarList.implicitHeight,
                                     account.y - calendarList.y - Theme.space3)
                    clip: true

                    Item {
                        width: calendarList.width
                        height: 22

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
                            height: 32

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

                    /// The row that says what kind of list this is. It takes no
                    /// click, for the same reason the rows above it take none —
                    /// there is no calendar-account flow behind it yet — and it
                    /// is drawn one value quieter than they are so that it
                    /// reads as the list's edge rather than as a ninth
                    /// calendar. Without it the eight rows simply stop, and a
                    /// list of colours that simply stops is a legend; a list
                    /// that ends in *Add calendar* is a set of things you own.
                    Item {
                        width: calendarList.width
                        height: 32

                        Item {
                            id: addGlyph

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 15
                            height: 15

                            Icon {
                                anchors.centerIn: parent
                                name: "plus"
                                size: 14
                                color: Theme.textMuted
                            }
                        }

                        Text {
                            anchors.left: addGlyph.right
                            anchors.leftMargin: Theme.space3
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Add calendar"
                            color: Theme.textMuted
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pointSize: Theme.pt(13)
                            font.weight: Theme.weightRegular
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

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: Theme.borderSubtle
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

            view: window.view
            anchorDate: window.anchorDate
            todayIso: window.todayIso
            firstDay: window.firstDay

            onViewRequested: name => window.viewRequested(name)
            onTodayRequested: window.todayRequested()
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
            visible: window.view !== "month"

            dayCount: window.view === "day" ? 1 : 7
            anchorDate: window.anchorDate
            firstDay: window.firstDay
            todayIso: window.todayIso
            nowStamp: window.nowStamp
            events: CalendarStore.events
            selectedId: window.selectedId
            use24: window.use24

            onEventActivated: id => window.eventSelected(id)
        }

        /// The month grid, in the same rectangle as the week one and swapped by
        /// `visible` rather than a `Loader`. Both views are cheap and neither
        /// holds state a rebuild would lose — but the week view *does* hold a
        /// scroll position, and a `Loader` would drop it every time somebody
        /// looked at the month and came back.
        MonthView {
            id: monthGrid

            anchors.fill: grid
            visible: window.view === "month"

            anchorDate: window.anchorDate
            firstDay: window.firstDay
            todayIso: window.todayIso
            events: CalendarStore.events
            selectedId: window.selectedId
            use24: window.use24

            onEventActivated: id => window.eventSelected(id)
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
