pragma Singleton

// The Hyprland facade (#12 §3): the only place in the shell that dispatches,
// runs `hyprctl`, or knows what a `lastIpcObject` is.
//
//     Compositor.workspaces        // [{ id, occupied, active }], slot-free
//     Compositor.activeWorkspaceId
//     Compositor.focusWorkspace(3)
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

    /// Bumped when a refresh has landed, purely to re-trigger the binding
    /// above. Hyprland's own workspace model does not signal window-count
    /// changes, so there is nothing else to depend on.
    property int occupancyEpoch: 0

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

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (root.occupancyEvents.indexOf(event.name) >= 0)
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

    Component.onCompleted: Logger.log("compositor",
        root.available ? "hyprland facade ready" : "no hyprland session — facade inert")
}
