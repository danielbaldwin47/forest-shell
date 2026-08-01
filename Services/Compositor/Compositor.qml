pragma Singleton

// The Hyprland facade (#12 §3) — the only place in the shell that talks to the
// compositor, so every other file asks a question in shell terms and never
// learns which compositor answered it.
//
// Two questions so far, both of them #42's:
//
//   focusedScreenName  — notification popups and the OSD exist on every screen
//                        and render on the focused one only (#22 §1). The
//                        windows never move; the *content* is what follows
//                        focus.
//   focusedFullscreen  — a fullscreen focus suppresses popups (#9).
//
// Deliberately thin. The workspace model, the toplevel list and `dispatch()`
// belong to the tickets that need them (#35 the ridgeline, #38 the drawers) and
// will land here; guessing their shape now would commit an API those tickets
// would have to undo.
//
// Nothing here polls: Quickshell's `Hyprland` singleton is fed by the
// compositor's own event socket (#22 §5 — the shell stays out of powertop).
// `hasfullscreen` is the one value that arrives only with an explicit refresh,
// so the events that can change it ask for one.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains:
// Quickshell's scan for it gives up at the first line that looks like the start
// of an object body, comment or not.
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    /// The screen the compositor considers focused, by `ShellScreen.name`.
    ///
    /// A name rather than a `ShellScreen`, because that is what the comparison
    /// needs and a name cannot go stale: a `ShellScreen` held across a hotplug
    /// is a dangling reference, and per-screen surfaces are created and
    /// destroyed by hotplug (#22 §3).
    readonly property string focusedScreenName: {
        const monitor = Hyprland.focusedMonitor;
        if (monitor && monitor.name)
            return monitor.name;

        // No compositor answer yet — during startup, or on a session that is
        // not Hyprland at all. With exactly one screen there is nothing to
        // choose between, and both calibration machines are single-monitor
        // (#22): the alternative is a shell whose popups never appear because
        // one property arrived late.
        const screens = Quickshell.screens;
        return screens.length === 1 ? screens[0].name : "";
    }

    /// Whether a screen is the focused one. Bound, not sampled — the surfaces
    /// that call this re-evaluate when focus moves.
    function isFocused(screen: ShellScreen): bool {
        return screen !== null && screen.name === root.focusedScreenName;
    }

    /// Whether the focused workspace is showing a fullscreen window.
    ///
    /// Read off the workspace rather than the toplevel: what matters is "is the
    /// screen given over to one window", which is exactly what the workspace
    /// reports, and it stays right when the fullscreen window is not the one
    /// with keyboard focus.
    readonly property bool focusedFullscreen: {
        const workspace = Hyprland.focusedWorkspace;
        const ipc = workspace ? workspace.lastIpcObject : null;
        return ipc ? ipc.hasfullscreen === true : false;
    }

    // `hasfullscreen` is part of the workspace's IPC snapshot, and a snapshot
    // is only as current as its last refresh. These are the events after which
    // it can have changed — a window entering or leaving fullscreen, the
    // fullscreen window closing, and any move of focus that changes which
    // workspace the answer is about.
    readonly property var fullscreenEvents: [
        "fullscreen", "closewindow", "workspace", "workspacev2", "focusedmon"
    ]

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent) {
            if (root.fullscreenEvents.indexOf(event.name) >= 0)
                Hyprland.refreshWorkspaces();
        }
    }

    // The shell can start inside a fullscreen window, in which case no event is
    // coming and the first snapshot is the only one that matters.
    Component.onCompleted: Hyprland.refreshWorkspaces()
}
