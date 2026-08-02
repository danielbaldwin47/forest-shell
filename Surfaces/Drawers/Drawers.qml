pragma Singleton

// The shared drawer window's state — which drawer is open, where, and the one
// focus grab all of them share (#38, topology from #12 §3).
//
//     Drawers.toggle("session")        from a bar button, through Core/SurfaceBus.qml
//     qs ipc call session toggle       from a keybind, a script, the shell switcher
//
// The launcher (#39), the control centre (#44), the dashboard (#49) and the
// notification centre (#50) all land in this window. What they share is a
// window per screen, an input mask and *one* `HyprlandFocusGrab` — one grab
// because two panels each holding one is the multi-panel focus fight #12 named,
// where dismissing either can hand focus to the other instead of to the desktop.
//
// The decisions — which drawer a toggle leaves open, which screen it opens on,
// what a hotplug does to that — are in DrawerPolicy.qml, on the QtQuick-only
// side of the line where `tests/` can reach them. What is here is the part that
// needs Quickshell: the grab, the IPC door, the bus registration and the screen
// list.
//
// The windows themselves are DrawerWindow.qml, mounted from shell.qml. This
// file deliberately does not own them: they are one per screen inside a
// `Variants`, created and destroyed by hotplug, and a singleton holding
// references to those is the dangling-`ShellScreen` bug
// Services/Compositor/Compositor.qml refuses to have. The open window announces
// itself for the grab instead, and announces nothing else.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Core
import qs.Services.Compositor

Singleton {
    id: root

    readonly property DrawerPolicy policy: DrawerPolicy {}

    /// The layer-shell namespace, and so the handle every Hyprland rule for the
    /// drawer window is written against.
    readonly property string layerNamespace: "forest-shell:drawers"

    /// The open drawer's name, or `""`. One value and not a flag per surface,
    /// which is what makes two drawers open at once unrepresentable.
    ///
    /// Written by `open()` and `close()` below and by nothing else — those two
    /// are where the log line lives, and a state change that did not go through
    /// them is one the harness cannot see (#81).
    property string current: ""

    /// The screen it is open on, by name. A name and not a `ShellScreen`, for
    /// the reason Compositor.qml holds the focused screen as one.
    property string screen: ""

    /// The window currently drawing the open drawer, which is the window the
    /// grab is held for. Set by DrawerWindow.qml as it opens — see the header
    /// for why it arrives that way round — and dropped again on close, because
    /// a per-screen window held past its usefulness is the dangling reference
    /// the header says this file refuses to have.
    property var grabWindow: null

    readonly property var screenNames: Quickshell.screens.map(output => output.name)
    property var seenScreens: []

    // --- opening and closing -------------------------------------------------

    function open(name: string): void {
        if (!root.policy.known(name)) {
            Logger.warn("drawers", root.policy.closed(name, "no such drawer"));
            return;
        }

        const target = root.policy.openOn(Compositor.focusedScreenName, root.screenNames);
        if (target === "") {
            Logger.warn("drawers", "no screen to open " + name + " on");
            return;
        }

        // A drawer replacing another is #27's cross-drawer transition: the
        // scrim is untouched and only the contents change, so this is one
        // assignment and the window does the choreography.
        if (root.current !== "" && root.current !== name)
            Logger.log("drawers", root.policy.switched(root.current, name));
        else
            Logger.log("drawers", root.policy.opened(name, target));

        root.current = name;
        root.screen = target;
    }

    /// `reason` travels into the log because a drawer that was dismissed and
    /// one that was toggled shut look identical afterwards, and the harness has
    /// to tell them apart (#81).
    function close(reason: string): void {
        if (root.current === "")
            return;

        Logger.log("drawers", root.policy.closed(root.current, reason));
        root.current = "";
        root.screen = "";
        root.grabWindow = null;
    }

    function toggle(name: string): void {
        const next = root.policy.next(root.current, name);
        if (next === root.current)
            return;         // a drawer nobody built; the bus has already said so
        if (next === "")
            close("toggle");
        else
            open(next);
    }

    // --- the one focus grab --------------------------------------------------
    //
    // Clicking the desktop closes the drawer; clicking the bar does not, and
    // that asymmetry is #27's "the bar renders above the fog and stays
    // clickable" made real — the bar's windows join the grab through
    // Core/FocusGrabWindows.qml, so a click on another bar icon reaches the
    // button and starts the cross-drawer transition instead of being eaten on
    // its way to dismissing this one.
    HyprlandFocusGrab {
        id: grab

        windows: root.grabWindow
                 ? [root.grabWindow].concat(FocusGrabWindows.windows)
                 : []
        active: root.current !== "" && root.grabWindow !== null

        // Also fires when the shell drops the grab itself, one assignment after
        // `close()` has already emptied the state. `close()` on an already
        // closed drawer returns without logging, so this second, wrong reason
        // never reaches the log.
        onCleared: root.close("dismissed")
    }

    // --- hotplug -------------------------------------------------------------

    onScreenNamesChanged: {
        const before = root.seenScreens;
        root.seenScreens = root.screenNames.slice();

        if (root.current === "")
            return;
        if (!root.policy.survivesScreenChange(root.screen, before, root.screenNames))
            root.close("monitor change");
    }

    // --- the blur behind the fog ---------------------------------------------
    //
    // The wash is 10% of a pale grey and does nothing on its own: what makes it
    // fog is the compositor blurring the desktop underneath, which is a
    // layerrule against this window's namespace (#22 §6 forbids QML-side
    // full-screen blur outright). Pushed once, not per screen and not per open:
    // the rule is namespaced, the window carries the namespace, and #27 wants
    // the blur to *snap* with the window mapping rather than animate — so
    // mapping the window is the whole of turning it on.
    //
    // No setting of its own. The bar's blur is a Bar-tab toggle because the bar
    // is a surface you look past; the fog is a surface that exists to obscure,
    // and a scrim with the blur off is a 10% wash over a legible desktop rather
    // than a cheaper version of the same thing. `reducedEffects` still takes it
    // — that is rung 1 of the ladder, and the reduced look is a flat wash.
    function applyBlurRule(): void {
        Compositor.setLayerRule(Theme.blurRequested(true) ? "blur 1" : "blur 0",
                                root.layerNamespace);
    }

    // Not a `Connections` on `Startup.onDeferredStage` the way the bar's is:
    // this singleton is *constructed by* that handler (shell.qml names it in
    // `initSurfaces`), so it would arm the connection one statement after the
    // signal it wanted. `deferredRan` is set before the signal is emitted, so
    // asking is the same question a frame later.
    Connections {
        target: Startup
        function onDeferredStage() { root.applyBlurRule(); }
    }

    Connections {
        target: Config
        function onKeyChanged(path) {
            if (Startup.deferredRan && path === "appearance.reducedEffects")
                root.applyBlurRule();
        }
    }

    // --- the doors -----------------------------------------------------------

    /// What Core/SurfaceBus.qml hands a bar button: an object with `toggle()`,
    /// which is the whole handler contract. One per tenant, so the bus name
    /// stays the drawer's name rather than becoming an argument.
    readonly property QtObject sessionHandle: QtObject {
        function toggle(): void { root.toggle("session"); }
    }

    // Functions need explicit signatures to be callable over IPC. No `show`:
    // `qs ipc call session show` is parsed as `qs ipc show` and prints the
    // target listing instead (#77, and Core/SurfaceBusPolicy.qml).
    IpcHandler {
        target: "session"

        function open(): void { root.open("session"); }
        function close(): void { root.close("ipc"); }
        function toggle(): void { root.toggle("session"); }
        function isOpen(): bool { return root.current === "session"; }
    }

    Component.onCompleted: {
        SurfaceBus.register("session", root.sessionHandle);
        Logger.stage("drawers armed (ipc target: session)");
        if (Startup.deferredRan)
            root.applyBlurRule();
    }
}
