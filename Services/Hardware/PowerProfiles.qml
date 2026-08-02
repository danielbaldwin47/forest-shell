pragma Singleton

// The power-profile facade (#44, #12 §3): the only place in the shell that
// knows power-profiles-daemon exists.
//
//     PowerProfiles.available   // is there a daemon to talk to
//     PowerProfiles.profile     // "balanced", "performance", …
//     PowerProfiles.cycle()     // one press of the control-centre tile
//
// Shelled out to `powerprofilesctl` rather than spoken natively: the daemon is
// on DBus and Quickshell has no client for it, so this is the one hardware
// facade in the shell with a subprocess behind it. That is what makes the exit
// status load-bearing (#78) and the log line per press mandatory (#81) — both
// decided in Services/Hardware/PowerProfilePolicy.qml, which imports nothing
// but QtQuick so `tests/` can reach them.
//
// **No polling.** The list is read once at the deferred stage and re-read after
// every set the shell makes. A profile changed by `powerprofilesctl` in a
// terminal is not noticed until the next press, which is the trade the idle
// budget (#22 §5) asks for: the alternative is a subprocess on a timer for a
// value that changes a handful of times a day.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property PowerProfilePolicy policy: PowerProfilePolicy {}

    /// Every profile the daemon offers, in its own order — which is also the
    /// order `cycle()` walks.
    property var profiles: []

    /// The one that is running, or `""` before the first read finishes.
    property string profile: ""

    /// Whether there is a daemon at all. False on a machine with no
    /// power-profiles-daemon and on one where `powerprofilesctl` is not
    /// installed; in both cases the tile is absent rather than dead
    /// (Surfaces/Drawers/ControlCenterPolicy.qml).
    readonly property bool available: root.profiles.length > 0

    /// One press of the tile: the next profile the daemon offers, wrapping.
    /// A no-op on a machine with nothing to move to, and it says so — a press
    /// that changed nothing and logged nothing is #81.
    function cycle(): void {
        const next = root.policy.next(root.profile, root.profiles);
        if (next === "") {
            Logger.warn("power-profile", "nothing to cycle to");
            return;
        }
        root.set(next);
    }

    function set(name: string): void {
        const command = root.policy.setCommand(name);
        if (command.length === 0)
            return;
        if (apply.running) {
            // Handing a running `Process` a new command kills it
            // (Services/Compositor/Compositor.qml). A press during the ~100 ms
            // a set takes is dropped rather than queued: the queue would be a
            // list of profiles nobody asked to pass through.
            Logger.warn("power-profile", "busy — press ignored");
            return;
        }
        apply.target = name;
        apply.command = command;
        apply.running = true;
    }

    /// Re-read the daemon. Called once at startup and after every set, which is
    /// the whole of when this shell believes the value can have moved.
    function refresh(): void {
        if (list.running)
            return;
        list.command = root.policy.listCommand();
        list.running = true;
    }

    Process {
        id: list

        stdout: StdioCollector { id: listOut }

        onExited: (exitCode, exitStatus) => {
            if (!root.policy.accepted(exitCode)) {
                // Not a failure worth a warning: a machine with no
                // power-profiles-daemon is a normal machine, and this line is
                // why the tile is not on it.
                root.profiles = [];
                root.profile = "";
                Logger.log("power-profile", "no power-profiles-daemon — facade inert");
                return;
            }
            root.profiles = root.policy.parseList(listOut.text);
            root.profile = root.policy.parseActive(listOut.text);
            Logger.log("power-profile", root.available
                ? "profiles " + root.profiles.join(", ") + " — on " + root.profile
                : "no power-profiles-daemon — facade inert");
        }
    }

    Process {
        id: apply

        /// What is in flight, kept for the log line: the reply arrives after the
        /// call and says nothing about which profile it is answering.
        property string target: ""

        stderr: StdioCollector { id: applyErr }

        onExited: (exitCode, exitStatus) => {
            if (root.policy.accepted(exitCode)) {
                Logger.log("power-profile", root.policy.applied(apply.target));
                // The daemon is the authority on what took: it can refuse a
                // profile it just listed, and this is the read that catches it.
                root.refresh();
            } else {
                Logger.warn("power-profile",
                            root.policy.complaint(apply.target, exitCode, applyErr.text));
            }
        }
    }

    // Deferred, not immediate: a subprocess spawn during the first frames is
    // the startup budget #22 §5 measures, and nothing on screen needs a power
    // profile before the drawer is opened.
    Connections {
        target: Startup
        function onDeferredStage() { root.refresh(); }
    }

    Component.onCompleted: if (Startup.deferredRan) root.refresh();
}
