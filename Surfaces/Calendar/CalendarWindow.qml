pragma Singleton

// The calendar window's entry points — who may open it, and how.
//
// The window itself is `CalendarView.qml`; this is the handle everything else
// holds, and it is `Surfaces/Settings/SettingsWindow.qml`'s shape line for
// line, for the same reasons that file gives: the window is built when it is
// first opened and destroyed when it is closed, because nothing about it needs
// to survive being hidden.
//
// What *does* have to survive it lives here rather than in the view: which view
// is on screen and which day it is anchored to. Those are answers to "where was
// I", and a window rebuilt from scratch has to come back to the same place — so
// they are properties of the singleton, and the view binds to them.
//
// The IPC target is `calendar`, lowercase, matching the surface name — the
// convention the shell-switch contract fixes for every surface with an external
// entry point.
//
// There is deliberately no IPC `show`, which is #77 and is a Quickshell CLI
// collision rather than a preference: `show` is also a subcommand of `ipc`
// itself, so every form of `qs ipc call calendar show` is parsed as `qs ipc
// show`, prints the target listing and exits 0 without calling anything. `open`
// is the no-argument door.
//
// Two of the verbs below — `create` and `guestAdd` — exist so the second seam
// can prove the store without a pointer. A drag is the way a person makes an
// event and `tools/calendar-harness.sh` drives that too, but a verb that fails
// for a reason that has nothing to do with pointers should say so on its own.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core
import qs.Services.Calendar

Singleton {
    id: root

    /// Whether the window exists. Named `shown` and not `open` because `open()`
    /// is one of the verbs below, and a property and a function that differ only
    /// by parentheses are a bug waiting for a hurried reader.
    readonly property bool shown: loader.active

    /// `day`, `week` or `month`. Survives the window being closed, so reopening
    /// comes back to what was on screen.
    property string view: "week"

    /// The day the view is built around: the day itself in the day view, the
    /// week containing it in the week view, its month in the month view.
    property string anchorDate: root.todayIso()

    /// The selected event's id, or `""`. Held here rather than in the view for
    /// the same reason the two above are.
    property string selectedId: ""

    /// The views this surface knows. Stated once so an unknown name can be
    /// refused with a list rather than silently ignored.
    readonly property var views: ["day", "week", "month"]

    property CalendarTime time: CalendarTime {}

    /// Today, as a local wall-clock day.
    ///
    /// The one place in the calendar a `Date` is allowed, and it is allowed
    /// because the question really is "what does the machine's clock say now" —
    /// which is exactly what CalendarTime refuses to answer and exactly what a
    /// clock is for. Everything downstream of this line is string arithmetic.
    function todayIso(): string {
        const now = new Date();
        return root.time.dayIso(now.getFullYear(), now.getMonth() + 1, now.getDate());
    }

    function show(): void {
        const wasShown = root.shown;
        loader.active = true;
        if (!loader.item)
            return;

        // One line per state change worth asserting on, which is what makes the
        // window drivable from tools/calendar-harness.sh — #81's lifecycle bug
        // was silent for a week for want of exactly this.
        Logger.log("calendar", (wasShown ? "window raised" : "window opened")
                   + " (view " + root.view + ", " + root.anchorDate + ")");

        // Asking is all the shell may do — whether the request is honoured is
        // the compositor's call. Guarded because raising a toplevel is not part
        // of the surface's documented API.
        if (typeof loader.item.requestActivate === "function")
            loader.item.requestActivate();
    }

    /// Closes the window. `reason` is for the log and travels with whatever
    /// closed it: `"escape"`, `"compositor"`, `"ipc"`, `"toggle"`.
    function close(reason: string): void {
        if (root.shown)
            Logger.log("calendar", "window closed (" + (reason ? reason : "request") + ")");
        loader.active = false;
    }

    function toggle(): void {
        if (root.shown)
            root.close("toggle");
        else
            root.show();
    }

    /// Switch view. An unknown name is refused out loud rather than ignored:
    /// the caller is a keybind or a script, and a silently dropped argument
    /// looks exactly like a window that does not answer.
    function setView(name: string): void {
        if (root.views.indexOf(name) < 0) {
            Logger.warn("calendar", "unknown view: " + name
                        + " (" + root.views.join(", ") + ")");
            return;
        }
        root.view = name;
        Logger.log("calendar", "view " + name);
    }

    /// Anchor the view on a day. Same argument for refusing a bad one.
    function goToDay(iso: string): void {
        if (!root.time.isDay(iso)) {
            Logger.warn("calendar", "not a date: " + iso + " (want YYYY-MM-DD)");
            return;
        }
        root.anchorDate = iso;
        Logger.log("calendar", "goto " + iso);
    }

    function goToday(): void {
        root.anchorDate = root.todayIso();
        Logger.log("calendar", "today " + root.anchorDate);
    }

    function select(id: string): void {
        root.selectedId = id;
        Logger.log("calendar", "select " + id);
    }

    /// One hour, on the day in view, at the minute the chrome worked out. The
    /// new event is selected as well as made, because the reason to press a
    /// create button is to edit the thing it creates — and because a chip that
    /// appeared somewhere off the visible hours would otherwise be a button
    /// that looked like it did nothing.
    ///
    /// Same call `ipc call calendar create` makes, so a click and a script land
    /// on one code path and log one line.
    function newEvent(iso: string, startMin: int): void {
        const id = CalendarStore.createEvent(iso, startMin, 60, "");
        if (id)
            root.select(id);
    }

    LazyLoader {
        id: loader

        component: Component {
            CalendarView {
                // One direction only: the singleton owns where the calendar is
                // looking, the view reads it. A window that owned its own view
                // name would lose it on every close, which is the thing these
                // properties live up here to prevent.
                view: root.view
                anchorDate: root.anchorDate
                selectedId: root.selectedId

                // Closed by something that is not one of the functions above:
                // the compositor's own close button, or Escape inside the
                // window. The reason travels with the signal so the log says
                // which — a window that vanished and a window that was
                // dismissed look identical afterwards.
                onCloseRequested: reason => root.close(reason)

                // The toolbar's three verbs and the grid's one, arriving as
                // signals rather than as calls into this singleton — the view
                // is built here, so a view that reached back would be a cycle,
                // and the capture harness builds the same view with no
                // singleton anywhere. They land on exactly the functions IPC
                // lands on, so a click and `qs ipc call calendar view month`
                // are the same event and log the same line.
                onViewRequested: name => root.setView(name)
                onDateRequested: iso => root.goToDay(iso)
                onTodayRequested: root.goToday()
                onEventSelected: id => root.select(id)
                onCreateRequested: (iso, startMin) => root.newEvent(iso, startMin)
            }
        }
    }

    // Functions need explicit signatures to be callable over IPC, and `qs ipc
    // show target calendar` lists exactly what is below — so this is also the
    // window's documented external surface, not just its plumbing.
    IpcHandler {
        target: "calendar"

        // The window, where it was left. The one to bind a key to.
        function open(): void { root.show(); }
        function close(): void { root.close("ipc"); }
        function toggle(): void { root.toggle(); }
        /// Whether it is on screen. A question and not a command, so a script
        /// can branch without opening anything.
        function isOpen(): bool { return root.shown; }

        /// `day`, `week` or `month`.
        function view(name: string): void { root.setView(name); }
        /// Anchor on a day, as `YYYY-MM-DD`. Named `goto` because that is what
        /// a person types; the QML-facing spelling is `goToDay`.
        function goto(iso: string): void { root.goToDay(iso); }
        function today(): void { root.goToday(); }

        /// Make an event without a pointer: the day, minutes after midnight,
        /// how long, and what it is called. Answers with the id it made, so a
        /// caller can drive the rest of the verbs at it.
        function create(iso: string, startMin: int, minutes: int, title: string): string {
            return CalendarStore.createEvent(iso, startMin, minutes, title);
        }
        function openEvent(id: string): void { root.show(); root.select(id); }
        function guestAdd(id: string, contact: string): bool {
            return CalendarStore.addGuest(id, contact);
        }
        function deleteEvent(id: string): bool { return CalendarStore.deleteEvent(id); }
    }

    Component.onCompleted: Logger.stage("calendar window armed (ipc target: calendar)")
}
