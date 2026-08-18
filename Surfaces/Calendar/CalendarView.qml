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
        anchors.fill: parent
        focus: true

        // Escape, from wherever the focus is. An unhandled key walks up the
        // focus chain, so the window needs exactly one handler for it and no
        // control inside needs to know the window can be closed.
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                window.closeRequested("escape");
                event.accepted = true;
            }
        }

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

            // The mini-month, the calendar list and the "Add calendar" row land
            // here in a later piece. Empty is the honest state for now: a
            // sidebar drawn with placeholder rows would be a picture of
            // something that does not exist.

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

        /// The month grid is a later piece. Saying so out loud beats an empty
        /// panel that reads as a grid that failed to draw.
        Text {
            anchors.centerIn: grid
            visible: window.view === "month"
            text: "month view — not built yet"
            color: Theme.textMuted
            font.family: Theme.fontUi
            font.pointSize: Theme.pt(15)
        }
    }
}
