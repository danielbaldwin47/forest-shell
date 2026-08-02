// The session drawer's five actions (#38) — the first tenant of the shared
// drawer window.
//
// Four of them are commands and one is not, and that asymmetry is the whole of
// this file. Logging out, suspending, rebooting and shutting down are things
// only the system can do, they differ by init system and by machine, and so
// they are strings in `settings.json` (`system.session.commands.*`). Locking is a
// surface this shell already owns (#47): it is reached in-process through
// `SessionLock.lock()`, not by spawning `loginctl lock-session` so that the
// shell can ask itself to do something it is sitting on top of — the mistake
// Core/SurfaceBus.qml exists to avoid, one process further out.
//
// The ticket was written before the lock landed and asks for the lock action to
// "no-op with a log until the lock surface lands". It has landed, so it does
// the thing instead; the no-op is the empty-command case below, which is a
// different and permanent one.
//
// Imports nothing but QtQuick so `tests/` can reach it; `Process` and
// `SessionLock` are on the other side of the line, in SessionMenu.qml.
import QtQuick

QtObject {
    id: policy

    /// What the menu shows, top to bottom. Least destructive first, which is
    /// also least surprising under a mis-aimed click: the two that end the
    /// session are at the far end of the travel from the one that does not.
    ///
    /// `id` is both the config key under `system.session.commands` and the log
    /// name.
    readonly property var actions: [
        { id: "lock", label: "Lock", icon: "lock" },
        { id: "logout", label: "Log out", icon: "log-out" },
        { id: "suspend", label: "Suspend", icon: "moon" },
        { id: "reboot", label: "Restart", icon: "rotate-ccw" },
        { id: "shutdown", label: "Shut down", icon: "power" }
    ]

    function known(id: string): bool {
        return policy.actions.some(action => action.id === id);
    }

    /// The one action that is the shell's own rather than the system's.
    function routesToLock(id: string): bool {
        return id === "lock";
    }

    /// What an action runs, given `system.session.commands` from the config.
    /// Empty
    /// for the lock, which is not a command, and empty for a key the user has
    /// blanked — "not on this machine" is a thing a config should be able to
    /// say, and an empty argv reaching `Process` is a button that spins and
    /// reports nothing.
    function command(id: string, commands: var): string {
        if (!policy.known(id) || policy.routesToLock(id))
            return "";
        return String((commands ?? {})[id] ?? "").trim();
    }

    /// A command as argv. Split here rather than handed to `sh -c`: the config
    /// holds a command, and routing it through a shell brings that shell's
    /// quoting, globbing and word-splitting along with it for no gain — the
    /// same argument Services/Compositor/LayerRulePolicy.qml makes for layer
    /// rules.
    function argv(command: string): var {
        const trimmed = String(command ?? "").trim();
        return trimmed === "" ? [] : trimmed.split(/\s+/);
    }

    // --- what the log says ---------------------------------------------------

    function fired(id: string, command: string): string {
        return id + " → " + (command !== "" ? command : "the shell's own lock");
    }

    /// Pressed, and nothing to run. Names the key to edit, because the fix is
    /// one line of config and the alternative is a button that looks broken.
    function refused(id: string): string {
        return "nothing to run for " + id + " (set system.session.commands." + id + ")";
    }
}
