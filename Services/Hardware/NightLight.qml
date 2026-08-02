pragma Singleton

// The night-light facade (#44, #12 §3).
//
//     NightLight.available     // is there a command configured to run
//     NightLight.on            // is the screen warmed right now
//     NightLight.temperature   // how warm, in K
//     NightLight.toggle()      // one press of the control-centre tile
//
// **Where the keys live, and why they are split.** The command and the
// temperature are config, under `weatherTime.nightLight` beside the location
// and sunset keys #50 will land — they are part of "my setup" and travel
// between machines. Whether it is *on* is state (`state.json`), by the
// portability test Core/StateSchema.qml states: a night light left on last
// night is not a setting, and a shell that restored it at nine in the morning
// would be wrong in the one way the toggle exists to avoid.
//
// **No schedule.** Turning on at sunset needs a sunset, which needs a location,
// which is #50. The key shape here leaves room for it and this ticket ships the
// manual toggle only.
//
// The decisions — argv, the clamp, and whether a finished run did anything —
// are in Services/Hardware/NightLightPolicy.qml, which imports nothing but
// QtQuick so `tests/` can reach them. This file is the wiring.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property NightLightPolicy policy: NightLightPolicy {}

    readonly property var keys: Config.values.weatherTime.nightLight

    /// Whether there is anything to run. A user on a compositor none of the
    /// shipped defaults fit empties the key and the tile goes away
    /// (Surfaces/Drawers/ControlCenterPolicy.qml) rather than failing on every
    /// press.
    readonly property bool available: root.policy.available(root.keys.command,
                                                            root.keys.offCommand)

    readonly property int temperature: root.policy.clamp(root.keys.temperature)

    /// Whether the screen is warmed. Read from state, and written only by
    /// `apply` below once the command has actually come back — the tile shows
    /// what happened rather than what was asked for, which is the same rule
    /// Services/Compositor/Compositor.qml holds for a layout switch.
    readonly property bool on: ShellState.values.nightLight.on

    function toggle(): void {
        root.set(!root.on);
    }

    function set(value: bool): void {
        if (!root.available) {
            Logger.warn("night-light", "nothing configured to run "
                        + "(set weatherTime.nightLight.command)");
            return;
        }
        if (apply.running) {
            // Handing a running `Process` a new command kills it
            // (Services/Compositor/Compositor.qml). A second press inside the
            // few ms a run takes is dropped rather than queued — a queue here
            // would be a list of screen temperatures nobody asked to see.
            Logger.warn("night-light", "busy — press ignored");
            return;
        }

        apply.target = value;
        apply.command = root.policy.argv(value ? root.keys.command : root.keys.offCommand,
                                         root.temperature);
        apply.running = true;
    }

    /// Re-run the current state at the current temperature. What a temperature
    /// change rides: the tool holds one value until it is given another, so a
    /// slider that moved while the light was on has to say so.
    function reapply(): void {
        if (root.on)
            root.set(true);
    }

    Process {
        id: apply

        /// What is in flight, kept for the log line and for the state write:
        /// the reply says nothing about which press it is answering.
        property bool target: false

        stdout: StdioCollector { id: applyOut }
        stderr: StdioCollector { id: applyErr }

        onExited: (exitCode, exitStatus) => {
            if (root.policy.accepted(exitCode, applyOut.text)) {
                ShellState.set("nightLight.on", apply.target);
                Logger.log("night-light", root.policy.applied(apply.target,
                                                              root.temperature));
                return;
            }
            // The state is *not* written, so the tile stays where it was: a
            // control that lights up for a command that did nothing is a
            // control that lies. The reply is the evidence rather than the exit
            // code — hyprctl exits 0 when it refuses (#78).
            Logger.warn("night-light",
                        root.policy.complaint(apply.target, root.temperature, exitCode,
                                              applyOut.text || applyErr.text));
        }
    }

    // A temperature edited in the settings file while the light is on takes
    // effect without a toggle. Guarded on the deferred stage for the reason
    // Surfaces/Drawers/Drawers.qml gives: this singleton is constructed by that
    // handler, so an unguarded reapply would run one statement into startup.
    Connections {
        target: Config
        function onKeyChanged(path) {
            if (Startup.deferredRan && path === "weatherTime.nightLight.temperature")
                root.reapply();
        }
    }

    // The state outlives the shell and the warmth does not: `hyprsunset` and
    // `gammastep` are per-session, so a restart leaves a screen at 6500K under
    // a tile that says 4000. Re-running at the deferred stage is what makes the
    // two agree again — and it costs a subprocess only on a machine that had it
    // on, which is a machine that has already opted into one.
    Connections {
        target: Startup
        function onDeferredStage() { root.reapply(); }
    }

    Component.onCompleted: {
        Logger.log("night-light", root.available
            ? "ready — " + root.temperature + "K, currently " + (root.on ? "on" : "off")
            : "nothing configured — facade inert");
        if (Startup.deferredRan)
            root.reapply();
    }
}
