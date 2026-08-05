pragma Singleton

// How one surface asks another to open (#37).
//
//     SurfaceBus.register("launcher", launcherWindow)   // from the surface
//     SurfaceBus.toggle("launcher")                     // from the bar button
//
// The bar's launcher and control-centre buttons have to reach surfaces that do
// not exist yet (#39, #44). They cannot hold a reference to a singleton nobody
// has written, and they must not shell out to `qs ipc call` — that is the door
// for things *outside* the process, and using it from inside would spawn a
// subprocess so the shell could talk to itself.
//
// So a surface registers itself here when it is constructed, and a button asks
// for it by name. Until the surface lands the ask is a logged no-op, which is
// this ticket's acceptance criterion and the #81 lesson: a button that does
// nothing quietly is indistinguishable from a button that is broken.
//
// **Core and not Services**, though it is a singleton that outlives every
// caller: it holds no state about the machine and speaks to nothing outside
// the process. It is the shell's own wiring between two of its surfaces, which
// is what Core is for — and it is not in Core/ServiceInit.qml for the same
// reason, since a bus with nothing registered has nothing to start.
//
// **This is a name table, not a message queue.** Nothing is buffered: a toggle
// arriving before the surface registers is dropped with a line in the log, and
// that is the correct behaviour — a launcher that opened by itself a minute
// after startup because someone pressed a button while it was loading would be
// a bug. What may be asked for at all is in Core/SurfaceBusPolicy.qml, on the
// QtQuick-only side of the line where tests/ can read it.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property SurfaceBusPolicy policy: SurfaceBusPolicy {}

    /// name → the object holding the surface's own `toggle()`. Replaced rather
    /// than mutated on every registration: an in-place edit of a `var` object
    /// notifies nothing, and `available()` is read from bindings.
    property var handlers: ({})

    /// Announce a surface. Called by the surface itself, on construction — the
    /// same moment it registers its IPC target, so the two doors open together.
    ///
    /// `handler` is any object with a `toggle()` function; in practice it is
    /// the surface's own singleton (`SettingsWindow`-shaped), which is what
    /// keeps the verb the surface's business rather than this file's.
    function register(name: string, handler: var): void {
        if (!root.policy.known(name)) {
            Logger.warn("surfaces", root.policy.unknown(name));
            return;
        }

        const next = {};
        for (const key in root.handlers)
            next[key] = root.handlers[key];
        next[name] = handler;
        root.handlers = next;

        Logger.log("surfaces", name + " registered (" + root.policy.command(name) + ")");
    }

    /// Whether a surface is there to be asked. A binding, so a button can be
    /// drawn differently before its surface exists — nothing does that today,
    /// and the bar deliberately still *shows* both buttons, because a button
    /// that appears halfway through startup is a bar that jumps.
    function available(name: string): bool {
        return root.handlers[name] !== undefined && root.handlers[name] !== null;
    }

    /// Ask a surface to open or close. The one verb, because it is the one the
    /// shell-switch contract fixed for the launcher and the only thing a bar
    /// button can sensibly mean.
    function toggle(name: string): void {
        if (!root.available(name)) {
            Logger.warn("surfaces", root.policy.absent(name));
            return;
        }

        const handler = root.handlers[name];
        if (typeof handler.toggle !== "function") {
            Logger.warn("surfaces", name + " registered something with no toggle()");
            return;
        }

        Logger.log("surfaces", name + " toggled from the bar");
        handler.toggle();
    }

    // --- a click on the bar that no control wanted -----------------------------
    //
    // #187: while a drawer is open, the bar is the only surface over its own
    // strip, so a click on the gaps between modules reaches nothing. It should
    // put the drawer away — and the bar cannot decide that itself, because it
    // does not know which of five drawers is open and must not learn. That is
    // the same problem `toggle` above solves, one step further along: not "open
    // the surface called X" but "here is what happened on the bar, do whatever
    // it means to you".

    /// Who answers that. Registered once, by the surface that covers the
    /// desktop; `null` until it does, and a click before then is a no-op rather
    /// than a warning — an early click on a bar whose drawers have not armed
    /// yet means nothing and has nothing to put away.
    ///
    /// A slot of its own rather than a sixth name in `handlers`, because it is
    /// not a name being asked for: every drawer is one tenant of one controller,
    /// and it is that controller — not a drawer — that knows whether anything is
    /// open at all.
    property var barHandler: null

    function registerBar(handler: var): void {
        root.barHandler = handler;
        Logger.log("surfaces", "bar clicks routed to the drawers");
    }

    /// `target` is what the click landed on: `""` for dead space or a readout,
    /// a drawer's name for one of its doors. The answer is the controller's —
    /// see Surfaces/Drawers/DrawerPolicy.qml `barClick` for the table.
    ///
    /// **Every** click on the bar comes here, doors included, which is what
    /// makes that table the one home the ticket asked for rather than a
    /// description of behaviour decided in four other places. A door's answer
    /// is `toggle`, and the controller sends it straight back through `toggle`
    /// above — so the bus's own name check, its absent-surface warning and its
    /// log line are all still on the path a bar button takes.
    function barClick(target: string): void {
        if (root.barHandler === null) {
            // A door pressed before the drawers arm still has something to say,
            // and it is `toggle`'s to say: #37 wants a button for a surface
            // that has not landed to log the miss rather than fail silently.
            if (target !== "")
                root.toggle(target);
            // Dead space, though, is a click with nothing to put away — and the
            // bar is clickable from its first frame, so this is the ordinary
            // state for a moment on every start. Nothing to report.
            return;
        }

        // A registered handler that cannot answer is the other thing entirely —
        // a wiring mistake, and one that would otherwise present as dead space
        // that stopped dismissing. `toggle` warns about its own version of this
        // for the same reason.
        if (typeof root.barHandler.barClick !== "function") {
            Logger.warn("surfaces", "the bar's click handler has no barClick()");
            return;
        }

        root.barHandler.barClick(target);
    }
}
