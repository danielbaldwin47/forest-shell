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
}
