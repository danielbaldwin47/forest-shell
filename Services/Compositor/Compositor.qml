pragma Singleton

// The Hyprland facade (#12 §3): the only place in the shell that dispatches,
// runs `hyprctl`, or knows what a `lastIpcObject` is.
//
//     Compositor.workspaces        // [{ id, occupied, active }], slot-free
//     Compositor.activeWorkspaceId
//     Compositor.focusWorkspace(3)
//     Compositor.focusedScreenName // popups render on the focused screen (#22 §1)
//     Compositor.focusedFullscreen // a fullscreen focus suppresses popups (#9)
//
// Everything above the facade speaks in workspace ids and intentions. That is
// what keeps the compositor swappable in principle and, far more practically,
// keeps the two Hyprland quirks below in one file instead of in every widget
// that shows a workspace:
//
//   - **Empty workspaces do not exist.** Hyprland creates a workspace when
//     something lands on it and destroys it when the last window leaves, so the
//     list is not a fixed row of slots. Padding it out to a stable row is the
//     bar's decision, not this file's — the facade reports what is there.
//   - **Occupancy is not live.** `HyprlandWorkspace` tracks creation and
//     destruction natively, but the window *count* comes from the last IPC
//     snapshot, which nothing refreshes on its own. Without the event wiring
//     below, a workspace you just emptied keeps rendering as occupied until you
//     switch to it.
//
// Event-driven throughout — no polling, so an idle shell wakes for this exactly
// never (#22 §5).
//
// `pragma Singleton` leads the file for the reason spelled out in
// Core/Config.qml.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    /// Whether we are running under Hyprland at all. Every call below degrades
    /// to a logged no-op when this is false, so the shell stays loadable on
    /// another compositor instead of erroring per keypress.
    readonly property bool available: (Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "") !== ""

    /// The focused workspace's id, or 1 before Hyprland has answered — the
    /// workspace list populates asynchronously, so this is a binding and never
    /// a value read once at startup.
    readonly property int activeWorkspaceId:
        Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1

    /// Live workspaces, ascending, as plain data: `{ id, occupied, active }`.
    ///
    /// Special workspaces (scratchpads) have negative ids and are left out —
    /// they are not places you move along a row, and putting them in one would
    /// make the row jump.
    readonly property var workspaces: {
        // Re-evaluate when the refresh below lands: `lastIpcObject` is a plain
        // JS value, so reading it creates no dependency of its own.
        root.occupancyEpoch;

        const model = Hyprland.workspaces ? Hyprland.workspaces.values : [];
        const out = [];
        for (const workspace of model) {
            if (workspace.id < 1)
                continue;
            const snapshot = workspace.lastIpcObject;
            out.push({
                id: workspace.id,
                // Unknown means "assume it has something in it": a workspace
                // Hyprland is telling us about exists, and drawing it as empty
                // would be the more wrong of the two guesses.
                occupied: snapshot && snapshot.windows !== undefined ? snapshot.windows > 0 : true,
                active: workspace.id === root.activeWorkspaceId
            });
        }
        out.sort((a, b) => a.id - b.id);
        return out;
    }

    /// Bumped when a refresh has landed, purely to re-trigger the bindings
    /// above and below. Hyprland's own workspace model does not signal
    /// window-count changes, so there is nothing else to depend on.
    property int occupancyEpoch: 0

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
    ///
    /// The refresh is coalesced, so the answer can be one tick stale: a
    /// notification arriving in the same instant as a window going fullscreen
    /// may still pop. Nothing is lost when it does — it is in history either
    /// way, and the next notification is decided on the current snapshot.
    readonly property bool focusedFullscreen: {
        root.occupancyEpoch;

        const workspace = Hyprland.focusedWorkspace;
        const ipc = workspace ? workspace.lastIpcObject : null;
        return ipc ? ipc.hasfullscreen === true : false;
    }

    function focusWorkspace(id: int) {
        root.dispatch("workspace " + id);
    }

    /// Run a Hyprland dispatcher. The one door in the wall.
    function dispatch(request: string) {
        if (!root.available) {
            Logger.warn("compositor", "no Hyprland session — ignoring dispatch: " + request);
            return;
        }
        Hyprland.dispatch(request);
    }

    /// Push a layer rule for one of our own namespaces, live.
    ///
    /// `hyprctl` rather than `Hyprland.dispatch`, because `keyword` is a
    /// hyprctl command and not a dispatcher — this is the one subprocess the
    /// facade owns, and it runs once at startup rather than per frame or per
    /// keypress. Re-running it appends a duplicate rule that has no additional
    /// effect (it is the same rule), which is what a shell hot-reload does
    /// during development; a compositor reload clears them.
    function setLayerRule(rule: string, namespace: string) {
        if (!root.available) {
            Logger.warn("compositor", "no Hyprland session — skipping layerrule "
                        + rule + " for " + namespace);
            return;
        }
        keyword.command = ["hyprctl", "keyword", "layerrule", rule + ", " + namespace];
        keyword.running = true;
        Logger.log("compositor", "layerrule " + rule + " → " + namespace);
    }

    Process { id: keyword }

    // Occupancy has to be asked for. These are the events after which the
    // window count under a workspace can differ from the last snapshot;
    // everything else Hyprland emits — window titles, focus, monitor changes —
    // is either tracked natively or none of our business.
    readonly property var occupancyEvents: [
        "openwindow", "closewindow", "movewindow", "movewindowv2",
        "movetoworkspace", "movetoworkspacesilent",
        "createworkspace", "createworkspacev2",
        "destroyworkspace", "destroyworkspacev2"
    ]

    // `hasfullscreen` lives in the same snapshot. These are the events after
    // which it can have changed — a window entering or leaving fullscreen, the
    // fullscreen window closing or moving away, and any move of focus that
    // changes which workspace the answer is about. (`closewindow` and
    // `movewindow` are already in the occupancy list.)
    readonly property var fullscreenEvents: [
        "fullscreen", "workspace", "workspacev2", "focusedmon"
    ]

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (root.occupancyEvents.indexOf(event.name) >= 0
                    || root.fullscreenEvents.indexOf(event.name) >= 0)
                coalesce.restart();
        }
    }

    // Opening a single window emits three or four events in a burst. One
    // refresh per burst, not one per event: each is an IPC round trip.
    Timer {
        id: coalesce
        interval: 40
        onTriggered: {
            Hyprland.refreshWorkspaces();
            root.occupancyEpoch++;
        }
    }

    Component.onCompleted: {
        Logger.log("compositor",
            root.available ? "hyprland facade ready" : "no hyprland session — facade inert");
        // The shell can start inside a fullscreen window, in which case no
        // event is coming and the first snapshot is the only one that matters.
        if (root.available)
            coalesce.restart();
    }
}
