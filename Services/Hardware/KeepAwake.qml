pragma Singleton

// Keep Awake (#44, semantics from #30 §"Keep Awake"): the shell holding the
// Wayland idle inhibitor on the user's behalf.
//
//     KeepAwake.on         // is the machine being held awake
//     KeepAwake.toggle()   // one press of the control-centre tile
//
// Native, not `systemd-inhibit`: `Quickshell.Wayland.IdleInhibitor` speaks
// `zwp_idle_inhibit_manager_v1` to the compositor directly, which is the same
// protocol a video player uses and the one Hyprland's idle daemon actually
// listens to. Shelling out to `systemd-inhibit` would hold a *logind* lock,
// which stops suspend but not the screen blanking on top of the film.
//
// ## The window this hangs on
//
// The protocol inhibits idling *for a surface*, so the inhibitor needs a
// window, and it must be one that stays mapped: the control centre is a drawer
// that closes a second after the tile is pressed, and an inhibitor on it would
// last exactly that long. So this owns a window of its own — one pixel,
// transparent, no input, on the background layer — created when the toggle goes
// on and destroyed when it goes off.
//
// That is a layer-shell surface for something invisible, which #22 §5 would
// normally refuse. It earns it by existing *only* while the user has asked to
// be kept awake: an idle shell has no such window, and the one case where it
// does is the case where the machine is deliberately not idling anyway.
//
// State, not config (Core/StateSchema.qml's portability test): "keep this
// machine awake" is about this afternoon, and a shell that restored it on
// Monday because a film ran on Friday would be holding a lock nobody asked for.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io

import qs.Core

Singleton {
    id: root

    /// Whether the machine is being held awake. Read from state so it survives
    /// a shell reload within the session, and written by the two calls below.
    readonly property bool on: ShellState.values.keepAwake

    /// Whether the compositor took the inhibitor. Not the same question as
    /// `on`: a compositor with no `zwp_idle_inhibit_manager_v1` binds nothing,
    /// and the tile lighting up over a machine that will still blank is the
    /// failure #81 is about.
    readonly property bool held: holder.inhibiting

    function toggle(): void {
        root.set(!root.on);
    }

    function set(value: bool): void {
        if (value === root.on)
            return;
        ShellState.set("keepAwake", value);
        Logger.log("keep-awake", value ? "on — inhibiting idle" : "off");
    }

    // The window, loaded only while the toggle is on. A `Loader` rather than a
    // `visible: false` window, because a layer-shell surface that exists
    // unmapped is still a surface the compositor is tracking — and the whole
    // argument for this window is that it is not there when it is not wanted.
    //
    // A `source` URL and not an inline `Component`, which is not a style
    // choice: an inline component is compiled with this file, and a
    // `PanelWindow` cannot be compiled without a window backend. There is none
    // under `QT_QPA_PLATFORM=offscreen`, so an inline one made this singleton —
    // and every file that transitively imports `Services/Hardware`, which is
    // the whole shell — unloadable from tools/capture-harness.sh. A URL is
    // resolved when the loader activates, which offscreen never does. See the
    // header of KeepAwakeWindow.qml.
    Loader {
        id: holder

        /// Whether the inhibitor is actually up. Not named `active`: that is
        /// `Loader`'s own property, and shadowing it is a load error rather
        /// than a subtle bug — the loader would have two values for whether it
        /// should load at all.
        readonly property bool inhibiting: holder.item !== null
                                           && holder.item.inhibiting === true

        active: root.on
        source: "KeepAwakeWindow.qml"

        onInhibitingChanged: if (Startup.deferredRan && !holder.inhibiting && root.on)
            Logger.warn("keep-awake", "compositor did not take the inhibitor")
    }

    // Scripting, keybinds, and tools/idle-harness.sh (#48):
    //
    //   qs ipc call keepawake toggle
    //   bind = SUPER SHIFT, C, exec, qs ipc call keepawake toggle
    //
    // The tile in the control centre was the only way in until the idle ladder
    // landed, and the ladder is the thing this now suppresses — "does Keep Awake
    // freeze the ladder" is a question a harness has to be able to ask without a
    // pointer (#48). `set` and not `on`, which would shadow the property above
    // in the reading even though QML would allow it.
    IpcHandler {
        target: "keepawake"

        function toggle(): bool {
            root.toggle();
            return root.on;
        }

        function set(value: bool): void { root.set(value); }
        function isOn(): bool { return root.on; }
        function isHeld(): bool { return root.held; }
    }

    Component.onCompleted: Logger.log("keep-awake",
        root.on ? "restored on" : "ready")
}
