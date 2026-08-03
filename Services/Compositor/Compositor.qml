pragma Singleton

// The Hyprland facade (#12 §3): the only place in the shell that dispatches,
// runs `hyprctl`, or knows what a `lastIpcObject` is.
//
//     Compositor.workspaces        // [{ id, occupied, active }], slot-free
//     Compositor.activeWorkspaceId
//     Compositor.focusWorkspace(3)
//     Compositor.focusedScreenName // popups render on the focused screen (#22 §1)
//     Compositor.focusedFullscreen // a fullscreen focus suppresses popups (#9)
//     Compositor.activeWindow      // what the bar's window module shows (#37)
//     Compositor.keyboardLayout    // "DE", or "" with one layout configured
//     Compositor.cycleKeyboardLayout()
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
//   - **Input devices are not modelled at all.** Hyprland's Quickshell module
//     has monitors, workspaces and toplevels natively and nothing for
//     keyboards, so the layout comes from `hyprctl devices -j` — one subprocess
//     per layout switch, parsed on the QtQuick-only side of the line in
//     Services/Compositor/KeyboardPolicy.qml.
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

    // The one state change everything on the bar's left cluster is downstream
    // of, and it had no log line: #75 was an indicator that never animated, and
    // the first question — is it being told, or is it not drawing? — had no
    // evidence either way. One line per real workspace change, which is a
    // keypress, not a frame.
    onActiveWorkspaceIdChanged: Logger.log("compositor", "workspace " + root.activeWorkspaceId + " focused")

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

    // --- the focused window (#37) --------------------------------------------

    /// What the bar's window module shows: the focused window's title, its app
    /// id if it has not set one, and "" on an empty workspace. The rules are in
    /// ActiveWindowPolicy next door, on the side of the line tests/ can reach.
    ///
    /// Read off `Hyprland.activeToplevel` rather than `ToplevelManager`, which
    /// would answer the same question compositor-agnostically: this is the
    /// Hyprland facade, everything else here is already Hyprland's, and the
    /// toplevel it hands back carries the workspace and monitor a later module
    /// will want.
    ///
    /// The app id comes off `toplevel.wayland` — the Wayland handle for the
    /// same window — and **not** off `lastIpcObject.class`, which is the
    /// obvious-looking field and is a trap: that snapshot is only refreshed by
    /// an explicit `refreshToplevels()`, which nothing here calls, so for any
    /// window mapped after startup it is empty. The fallback would then be
    /// dead exactly where it is needed, and the module would hide instead of
    /// naming the application.
    readonly property string activeWindow: {
        const toplevel = Hyprland.activeToplevel;
        if (!toplevel)
            return "";
        return windows.label(toplevel.title,
                             toplevel.wayland ? toplevel.wayland.appId : "");
    }

    /// Whether the module belongs on the bar — an empty workspace has no
    /// focused window and nothing to say about one.
    readonly property bool hasActiveWindow: windows.showing(root.activeWindow)

    // --- window geometry (#51) -----------------------------------------------
    //
    // The region picker snaps to window rectangles, and this is where it asks.
    // Raw snapshots rather than filtered ones: which windows are worth snapping
    // to is a decision, and it lives in Services/Screenshot/ScreenshotPolicy.qml
    // where tests/ can pose a three-window desktop.

    /// Every toplevel's own `hyprctl clients` snapshot — `at`, `size`,
    /// `workspace`, `monitor`, `mapped`, `hidden`, `title`, `class`.
    ///
    /// Bound, never read imperatively: Hyprland's models populate
    /// asynchronously and a read at `Component.onCompleted` answers zero with
    /// every window on screen.
    readonly property var toplevelSnapshots:
        Hyprland.toplevels.values.map(toplevel => toplevel.lastIpcObject)

    /// The focused monitor's snapshot — position, *native* size, scale, and
    /// its active workspace. The size is native and the windows above are
    /// logical; whoever divides is the caller's business, not this file's.
    readonly property var monitorSnapshot:
        Hyprland.focusedMonitor ? Hyprland.focusedMonitor.lastIpcObject : null

    /// Ask the compositor to re-take those snapshots.
    ///
    /// **Mandatory before reading a rectangle off them**, and the same trap
    /// `activeWindow` documents above from the other side: `lastIpcObject` is
    /// refreshed only by an explicit call, so every window mapped since startup
    /// carries a stale one — or an empty one. A picker that skipped this would
    /// snap to where windows used to be, which is worse than not snapping,
    /// because it looks like it worked.
    ///
    /// Asynchronous. The caller reads the snapshots on the far side of
    /// something else — for the picker, the ~50ms the screen freeze takes.
    function refreshWindowGeometry(): void {
        Hyprland.refreshToplevels();
        Hyprland.refreshMonitors();
    }

    // One line per focused window, which is a keypress and not a frame — and
    // the evidence tools/services-harness.sh reads to check the module tracks
    // focus at all. Retitling is the same event class: a browser that renames
    // its window on every tab switch logs a line per tab switch, which is the
    // right cadence for something a person did.
    onActiveWindowChanged: Logger.log("compositor", root.activeWindow === ""
        ? "no focused window"
        : "focused window: " + root.activeWindow.slice(0, 80))

    ActiveWindowPolicy { id: windows }

    // --- the keyboard layout (#37) -------------------------------------------
    //
    // The one part of this facade that is not event-driven, because there is
    // nothing to drive it: Quickshell models no input devices, so the layout is
    // read with `hyprctl devices -j` at startup and again after each
    // `activelayout` event. That is one subprocess per layout switch — a
    // keypress — and none at all on a machine with one layout, since the event
    // never fires.

    /// What the last `hyprctl devices` reply said, as the policy reads it:
    /// `{ device, layouts, active }` — the keyboard to switch on, the layout
    /// codes in the order Hyprland cycles them, and which of them is live.
    ///
    /// One property and not three, because it is one answer: three flat
    /// properties assigned from the same reply can be read a frame apart, and
    /// a device paired with another read's layouts is a switch aimed at the
    /// wrong keyboard.
    property var keyboard: ({ device: "", layouts: [], active: 0 })

    /// What the bar shows — "DE" — or "" when there is nothing to show.
    readonly property string keyboardLayout:
        keys.label(root.keyboard.layouts, root.keyboard.active)

    /// Whether there is more than one layout to be in. False on the
    /// overwhelmingly common single-layout machine, which is what takes the
    /// module off the bar entirely (#9, and this ticket's own criterion).
    readonly property bool keyboardSwitchable: keys.showing(root.keyboard.layouts)

    onKeyboardLayoutChanged: if (root.keyboardLayout !== "")
        Logger.log("compositor", "keyboard layout " + root.keyboardLayout
                   + " (" + root.keyboard.layouts.join(",") + ")")

    /// Move to the next layout.
    ///
    /// A subprocess and not a dispatch: `switchxkblayout` is a hyprctl command,
    /// and `Hyprland.dispatch` answers `Invalid dispatcher` for it (see the
    /// policy, where the measurement is). A click on a bar module is exactly
    /// the cadence a subprocess is fine at — one per press.
    function cycleKeyboardLayout() {
        if (!root.keyboardSwitchable) {
            Logger.warn("compositor", "one keyboard layout — nothing to cycle to");
            return;
        }
        if (!root.available) {
            Logger.warn("compositor", "no Hyprland session — ignoring layout switch");
            return;
        }
        if (switcher.running) {
            // A held key, or an impatient second click. Dropped rather than
            // queued: giving a Process a new command while it runs kills the
            // run in flight (#78), and two switches from one gesture is not
            // what the user asked for either.
            Logger.warn("compositor", "a layout switch is already in flight");
            return;
        }
        switcher.command = keys.cycleCommand(root.keyboard.device);
        switcher.running = true;
        // No optimistic update: the `activelayout` event that follows is what
        // re-reads the devices, so the bar shows what the compositor did rather
        // than what it was asked to do.
    }

    Process {
        id: switcher

        stdout: StdioCollector { id: switcherOut }
        stderr: StdioCollector { id: switcherErr }

        onExited: (exitCode, exitStatus) => {
            if (keys.switched(exitCode, switcherOut.text))
                return;
            // The reply is the evidence, not the exit code — hyprctl exits 0
            // when it refuses (#78). A refusal here is silent otherwise: the
            // layout simply does not change, which reads as a dead module.
            Logger.warn("compositor", "hyprland refused a layout switch on "
                        + root.keyboard.device + ": "
                        + (String(switcherOut.text ?? "").trim()
                           || String(switcherErr.text ?? "").trim() || "no reply"));
        }
    }

    /// Ask `hyprctl` what the keyboards are doing. Coalesced onto one process
    /// for the reason the layer rule is: handing a `Process` a new command
    /// while it is running kills the run in flight, and a layout switch held
    /// down on the keyboard is exactly how two land at once.
    function refreshKeyboard() {
        if (!root.available)
            return;
        if (deviceQuery.running) {
            root.keyboardRefreshPending = true;
            return;
        }
        deviceQuery.running = true;
    }

    /// A refresh that arrived while the last one was still running — a held
    /// key, or two layout switches in a burst. One is remembered rather than
    /// queued: the reply is a snapshot of the current state, so any number of
    /// missed asks are answered by one more read.
    property bool keyboardRefreshPending: false

    KeyboardPolicy { id: keys }

    Process {
        id: deviceQuery

        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector { id: deviceOut }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                Logger.warn("compositor",
                            "hyprctl devices failed (exit " + exitCode + ") — "
                            + "the keyboard layout module has nothing to show");
            } else {
                root.keyboard = keys.read(deviceOut.text);
            }

            if (root.keyboardRefreshPending) {
                root.keyboardRefreshPending = false;
                root.refreshKeyboard();
            }
        }
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
    /// keypress. Re-running it appends a rule rather than replacing one, so a
    /// rule is turned off by pushing its opposite (`blur 0` over `blur 1`);
    /// there is no clearing verb in the 0.5x syntax. A compositor reload drops
    /// the lot.
    ///
    /// `rule` is a `<field> <value>` pair — the caller's business, since only
    /// the caller knows what off means for its rule. The match clause is this
    /// file's, via LayerRulePolicy next door, which is also where the reply is
    /// read: #78 spent four PRs pushing a rule Hyprland refused every time,
    /// because nothing here ever looked at what came back.
    function setLayerRule(rule: string, namespace: string) {
        if (!root.available) {
            Logger.warn("compositor", "no Hyprland session — skipping layerrule "
                        + rule + " for " + namespace);
            return;
        }
        // Queued rather than pushed, because there is one Process and giving it
        // a new `command` while it is running **kills the run in progress**:
        // measured, the first command's output never arrives and only the
        // second one's does. A rule silently discarded that way is exactly the
        // failure this ticket is about, and two rules at once is not exotic —
        // it is what flipping `bar.surface.blur` while `reducedEffects` also
        // changes looks like from here.
        root.queuedRules = root.queuedRules.concat([{ rule: rule, namespace: namespace }]);
        root.pushNextRule();
    }

    /// Rules waiting on the one `hyprctl` process. Empty almost always: rules
    /// are pushed at startup and on a settings change, never per frame.
    property var queuedRules: []

    /// Hand the next queued rule to the process, if it is free. Called on
    /// arrival and again when a run finishes, which is what drains the queue.
    function pushNextRule() {
        if (keyword.running || root.queuedRules.length === 0)
            return;
        const next = root.queuedRules[0];
        root.queuedRules = root.queuedRules.slice(1);
        keyword.rule = next.rule;
        keyword.ruleNamespace = next.namespace;
        keyword.command = layerRules.command(next.rule, next.namespace);
        keyword.running = true;
    }

    LayerRulePolicy { id: layerRules }

    Process {
        id: keyword

        // What is in flight, kept for the log line: the reply arrives long
        // after the call and says nothing about which rule it is answering.
        property string rule: ""
        property string ruleNamespace: ""

        stdout: StdioCollector { id: keywordOut }
        stderr: StdioCollector { id: keywordErr }

        // hyprctl exits 0 whether it applied the rule or refused it, so the
        // reply text is the evidence and the exit code only catches a hyprctl
        // that could not run at all. Both are in `accepted`. Which line is
        // written, and what it says, is the policy's — a harness reads these,
        // and a log format nothing owns is one nothing can check.
        onExited: (exitCode, exitStatus) => {
            if (layerRules.accepted(exitCode, keywordOut.text))
                Logger.log("compositor", layerRules.applied(keyword.rule, keyword.ruleNamespace));
            else
                Logger.warn("compositor",
                            layerRules.complaint(keyword.rule, keyword.ruleNamespace, exitCode,
                                                 keywordOut.text, keywordErr.text));
            root.pushNextRule();
        }
    }

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
            // Not coalesced with the workspace refresh above: that one is an
            // IPC round trip per burst of window events, and this one is a
            // subprocess that only ever follows a deliberate layout switch.
            if (keys.layoutEvents.indexOf(event.name) >= 0)
                root.refreshKeyboard();
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
        if (root.available) {
            coalesce.restart();
            // Same argument for the keyboard, and a stronger one: a machine
            // whose layouts never change emits no `activelayout` at all, so
            // this first read is the only one that will ever happen.
            root.refreshKeyboard();
        }
    }
}
