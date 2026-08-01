pragma Singleton

// The Hyprland facade (#12 §3, #35): the only place `hyprctl` and dispatch
// live.
//
// Everything above this file speaks in shell terms — "the workspace row on this
// screen", "focus workspace 3", "blur this layer" — and never learns that
// Hyprland exists. That is what makes the compositor replaceable later without
// a rewrite of every surface, and what keeps IPC quirks (a workspace list that
// only holds *existing* workspaces, window counts that arrive one refresh
// late) in one file with the comment explaining them.
//
// What is deliberately *not* here: anything only one surface needs. This is the
// compositor, not the bar's data source.
//
// `pragma Singleton` leads this file for the reason Core/Config.qml explains at
// length: Quickshell's scan for it gives up at the first line that looks like
// the start of an object body, comment or not.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Core

Singleton {
    id: root

    readonly property QtObject slots: WorkspaceSlots {}

    /// Bumped on every compositor event that can change what a surface draws.
    ///
    /// Bindings read this alongside the data they want. Property capture across
    /// a function call is subtle enough — `monitorFor()` is a method, not a
    /// property — that a binding on the row could quietly stop re-evaluating
    /// after a refactor upstream. One integer makes the dependency explicit,
    /// and it moves only on real events: nothing here ticks.
    property int revision: 0

    // Events that change the row or the focus. Deliberately a list rather than
    // "any event": Hyprland's socket is chatty (`activewindow` fires on every
    // focus change inside a workspace), and each bump re-evaluates every bar.
    readonly property var watchedEvents: [
        "workspace", "workspacev2", "createworkspace", "createworkspacev2",
        "destroyworkspace", "destroyworkspacev2", "moveworkspace", "moveworkspacev2",
        "focusedmon", "focusedmonv2", "openwindow", "closewindow",
        "movewindow", "movewindowv2", "urgent"
    ]

    // --- reading -------------------------------------------------------------

    /// Live workspaces as plain data: `[{ id, windows }]`.
    ///
    /// `windows` is `undefined` until a refresh has filled `lastIpcObject` —
    /// the row treats that as occupied, because Hyprland does not keep
    /// workspaces that have no reason to exist.
    readonly property var liveWorkspaces: {
        void root.revision;
        const model = Hyprland.workspaces;
        const values = model ? model.values : [];
        const out = [];
        for (const workspace of values) {
            const ipc = workspace.lastIpcObject;
            out.push({
                id: workspace.id,
                windows: ipc ? ipc.windows : undefined
            });
        }
        return out;
    }

    /// The workspace focused on `screen` — a `ShellScreen`, or null for
    /// wherever focus currently is. Every screen has an active workspace even
    /// when the keyboard is elsewhere, which is what lets a bar on an unfocused
    /// monitor still say where that monitor is.
    function focusedWorkspaceId(screen: var): int {
        void root.revision;
        const monitor = screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor;
        const workspace = monitor ? monitor.activeWorkspace : Hyprland.focusedWorkspace;
        return workspace ? workspace.id : -1;
    }

    /// The workspace row for one screen: `slotCount` fixed slots unioned with
    /// every live workspace, with this screen's own focus marked.
    ///
    /// The row is *not* filtered to the screen's own workspaces. Hyprland binds
    /// a workspace to a monitor, so filtering would give each bar a different
    /// row length that shuffles as workspaces move between outputs — and
    /// multi-monitor is a correctness tier here, not a tuned one (#22 §1). One
    /// row everywhere, focus marked per screen, is the same on one monitor and
    /// legible on three.
    function workspaceRow(screen: var, slotCount: int): var {
        return root.slots.cells(slotCount, root.liveWorkspaces, root.focusedWorkspaceId(screen));
    }

    /// Whether anything is open on the workspace `screen` is showing. What the
    /// bar's adaptive opacity asks: transparency exists to show wallpaper, and
    /// over a used workspace there is none to show.
    function hasWindows(screen: var): bool {
        const focused = root.focusedWorkspaceId(screen);
        for (const workspace of root.liveWorkspaces)
            if (workspace.id === focused)
                return workspace.windows === undefined || workspace.windows > 0;
        return false;
    }

    // --- writing -------------------------------------------------------------

    /// Focus a workspace by id. The one dispatch the shell has so far, and the
    /// reason `Hyprland.dispatch` appears exactly once in the repo.
    function focusWorkspace(id: int) {
        Hyprland.dispatch("workspace " + id);
    }

    /// Ask the compositor to blur what is behind a layer-shell namespace.
    ///
    /// Blur is the compositor's job, never the shell's: a QML-side full-screen
    /// blur is ruled out outright on the T480's fill rate (#22 §5), and a
    /// `layerrule` costs the shell nothing per frame. Applied as a live
    /// `hyprctl keyword` rather than asking the user to edit hyprland.conf, so
    /// the surface arrives correct on first run — and the shell is built to
    /// look right if it never lands (86% fill, #10 §2).
    ///
    /// This is a subprocess because it is a compositor *keyword*, not a
    /// dispatch, and the IPC socket only carries the latter. It runs once.
    function blurLayer(namespace: string) {
        if (root.blurredLayers.indexOf(namespace) >= 0)
            return;
        root.blurredLayers.push(namespace);
        root.pendingLayers.push(namespace);
        applyNextLayerRule();
    }

    /// Namespaces already asked for, so a bar per screen does not run `hyprctl`
    /// once per screen for the same rule.
    property var blurredLayers: []
    property var pendingLayers: []

    function applyNextLayerRule() {
        if (layerRule.running || root.pendingLayers.length === 0)
            return;
        const namespace = root.pendingLayers.shift();
        layerRule.command = ["hyprctl", "keyword", "layerrule", "blur, " + namespace];
        layerRule.running = true;
    }

    Process {
        id: layerRule
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                Logger.warn("compositor", "layerrule blur failed (exit " + exitCode
                            + ") — the bar is legible without it");
            root.applyNextLayerRule();
        }
    }

    // --- events --------------------------------------------------------------

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (root.watchedEvents.indexOf(event.name) < 0)
                return;
            root.revision++;
            // Window counts live in `lastIpcObject`, which only a refresh
            // fills. Debounced because opening a window on a fresh workspace
            // fires several of these in a row, and each refresh is an IPC
            // round trip.
            refresh.restart();
        }
    }

    Timer {
        id: refresh
        interval: 60
        onTriggered: {
            Hyprland.refreshWorkspaces();
            root.revision++;
        }
    }

    Component.onCompleted: Logger.stage("compositor facade ready")
}
