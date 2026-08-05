pragma Singleton

// The shared drawer window's state — which drawer is open, where, and the one
// focus grab all of them share (#38, topology from #12 §3).
//
//     Drawers.toggle("session")        from a bar button, through Core/SurfaceBus.qml
//     qs ipc call session toggle       from a keybind, a script, the shell switcher
//
// The launcher (#39), the notification centre (#43), the control centre (#44)
// and the dashboard (#49) all land in this window. What they share is a window
// per screen, an input mask, and one open-drawer name — one name because two
// panels each holding their own is the multi-panel focus fight #12 named, where
// dismissing either can hand focus to the other instead of to the desktop.
//
// **There is no focus grab any more (#187), and the reason is worth keeping.**
//
// What #187 reported was a click on the bar reaching neither the button under
// it nor the fog: swallowed in between, so a drawer could not be swapped,
// closed from its own button, or dismissed from the bar. The cause was not
// here. It was one word in DrawerWindow.qml — the open window asked for
// `keyboardFocus: Exclusive`, and in Hyprland an exclusive layer surface does
// not merely hold the keyboard, it takes every *pointer* event as well
// ("forced above all", `CInputManager::mouseMoveUnified`). The bar's surface
// took a `Leave` the instant a drawer opened and never got another `Enter`.
// The header there says the rest; `OnDemand` is the fix.
//
// This file's grab went with it, for a reason of its own. It existed so a click
// on the bar would be *delivered* rather than eaten (#38, and #27's "the bar
// renders above the fog and stays clickable"), and the bar's windows joined it
// through a registry — Core/FocusGrabWindows.qml, now gone — to make that true.
// But a Hyprland grab hands *keyboard* focus to whichever of its windows the
// pointer is over, and the pointer is over the bar exactly when a bar button
// opened the drawer: keeping it would have put the keyboard on the bar and left
// Escape dead in the one case the fix exists for. tools/bar-click-harness.sh
// check 7 is that case.
//
// What it was for, the fog already does. It covers every screen while a drawer
// is open and stops only at the bar's reserved strip, so a click on the desktop
// lands on it and closes the drawer; a click on the bar lands on the bar, where
// `barHandle` below routes it. Nothing is left for a grab to catch.
//
// The decisions — which drawer a toggle leaves open, what a click on the bar
// means, which screen it opens on, what a hotplug does to that — are in
// DrawerPolicy.qml, on the QtQuick-only side of the line where `tests/` can
// reach them. What is here is the part that needs Quickshell: the IPC door, the
// bus registration and the screen list.
//
// The windows themselves are DrawerWindow.qml, mounted from shell.qml. This
// file deliberately does not own them: they are one per screen inside a
// `Variants`, created and destroyed by hotplug, and a singleton holding
// references to those is the dangling-`ShellScreen` bug
// Services/Compositor/Compositor.qml refuses to have.
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

    // --- a click on the bar ----------------------------------------------------
    //
    // Routed here from Core/SurfaceBus.qml, because the bar cannot answer it:
    // it does not know which of five drawers is open, and #187 wants one home
    // for the decision rather than a dismissal rule per module. The table is
    // `DrawerPolicy.barClick`; this is the part that needs the state.
    readonly property QtObject barHandle: QtObject {
        function barClick(target: string): void {
            const action = root.policy.barClick(root.current, target);
            if (action === "dismiss")
                root.close("bar");
            else if (action === "toggle")
                // Back out through the bus rather than straight to `toggle()`
                // next door. It is the same verb either way, but the bus is
                // where a bar button's log line and its absent-surface warning
                // live (#37), and a door should not lose those for having come
                // through the routing table.
                SurfaceBus.toggle(target);
        }

        /// A bar indicator with a panel behind it (#184). `id` is the
        /// indicator's own name; the panel it opens is `DrillInPolicy`'s table
        /// and the routing is `DrawerPolicy.barIndicatorClick` — this is again
        /// only the part that needs the state, which here is two pieces: which
        /// drawer is open and what is drilled inside it.
        function barIndicator(id: string): void {
            const wanted = ControlCenterActions.drillPolicy.panelForIndicator(id);
            const action = root.policy.barIndicatorClick(root.current,
                                                         ControlCenterActions.panel,
                                                         wanted);
            if (action === "none")
                return;

            // Both of the actions that move the drawer go back out through the
            // bus, for the reason `barClick` above gives: that is where a bar
            // press's log line and its absent-surface warning live (#37).
            if (action === "close") {
                SurfaceBus.toggle("controlcenter");
                return;
            }
            if (action === "open")
                SurfaceBus.toggle("controlcenter");

            // `show` and not the tiles' `drill`: a glyph names where to arrive,
            // and `drill` toggles. The difference is only visible in a hurry —
            // the drilled panel is cleared when the control centre is destroyed,
            // which is after its exit animation, so a glyph clicked twice inside
            // that window would toggle its own panel shut and reopen at the
            // root. `show` cannot do that (ControlCenterActions.qml).
            ControlCenterActions.show(wanted);
        }
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

    readonly property QtObject launcherHandle: QtObject {
        function toggle(): void { root.toggle("launcher"); }
    }

    readonly property QtObject notificationCenterHandle: QtObject {
        function toggle(): void { root.toggle("notificationcenter"); }
    }

    readonly property QtObject controlCenterHandle: QtObject {
        function toggle(): void { root.toggle("controlcenter"); }
    }

    /// The dashboard's (#49). Its button is the bar's *clock* — the one module
    /// that was a readout until this ticket and is now also a door.
    readonly property QtObject dashboardHandle: QtObject {
        function toggle(): void { root.toggle("dashboard"); }
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

    // The launcher's door, and the one the shell-switch contract names (#7):
    // `qs ipc call launcher toggle`, lowercase, `toggle` and not `show` — the
    // name is constrained twice over and Core/SurfaceBusPolicy.qml holds it.
    IpcHandler {
        target: "launcher"

        function open(): void { root.open("launcher"); }
        function close(): void { root.close("ipc"); }
        function toggle(): void { root.toggle("launcher"); }
        function isOpen(): bool { return root.current === "launcher"; }
    }

    // The notification centre's door (#43). `notificationcenter` and not
    // `notifications`: the notification service owns that target for DND, and
    // the second IpcHandler on a name is the one that quietly does not answer.
    //
    //     bind = SUPER, N, exec, qs ipc call notificationcenter toggle
    IpcHandler {
        target: "notificationcenter"

        function open(): void { root.open("notificationcenter"); }
        function close(): void { root.close("ipc"); }
        function toggle(): void { root.toggle("notificationcenter"); }
        function isOpen(): bool { return root.current === "notificationcenter"; }
    }

    // The control centre's door (#44). `controlcenter`, lowercase and one word,
    // which is the spelling Core/SurfaceBusPolicy.qml already wrote down for
    // the bar button that has been dispatching to it since #37 — the surface
    // lands against the name the bar is using rather than inventing a second.
    //
    //     bind = SUPER, C, exec, qs ipc call controlcenter toggle
    //
    // The four doors every drawer has, and four more this one does: the panel's
    // controls are reachable without the panel. That is a feature —
    //
    //     bind = SUPER, N, exec, qs ipc call controlcenter press nightlight
    //
    // — and it is also the only way the ticket's "the eight toggles are
    // functional" can be checked at all: a tile is a `TapHandler` inside a
    // drawer, and this repo has no pointer- or key-injection tool it may assume
    // (tools/drawer-harness.sh says so at length about Escape). The routing is
    // Surfaces/Drawers/ControlCenterActions.qml, which the tiles call too — one
    // table, so a harness driving `press` drives what a finger drives.
    //
    // On this handler and not a second one of its own: two `IpcHandler`s on one
    // target is one of them quietly not answering, which is the trap the
    // notification centre's own door is named around.
    IpcHandler {
        target: "controlcenter"

        function open(): void { root.open("controlcenter"); }
        function close(): void { root.close("ipc"); }
        function toggle(): void { root.toggle("controlcenter"); }
        function isOpen(): bool { return root.current === "controlcenter"; }

        function press(control: string): void { ControlCenterActions.press(control); }
        function slide(control: string, percent: int): void {
            ControlCenterActions.slide(control, percent);
        }
        function nudge(control: string, direction: int): void {
            ControlCenterActions.nudge(control, direction);
        }
        function mute(control: string): void { ControlCenterActions.mute(control); }

        // The drill-ins (#45), on this handler for the same reason the rest are:
        // two `IpcHandler`s on one target is one of them quietly not answering.
        //
        // Every row inside every detail view is reachable from here, and it has
        // to be — a row is a `TapHandler` inside a drawer, so without these
        // doors "Wi-Fi: scan, join, disconnect" and "Bluetooth: pair, connect,
        // disconnect" would be claims with no seam under them at all. What they
        // drive is exactly what a finger drives: one routing table, called from
        // both sides (Surfaces/Drawers/ControlCenterActions.qml).
        //
        //     qs ipc call controlcenter drill wifi
        //     qs ipc call controlcenter network PUMPKINCURRY
        //     qs ipc call controlcenter passphrase PUMPKINCURRY hunter2hunter2
        //     qs ipc call controlcenter back
        function drill(panel: string): void { ControlCenterActions.drill(panel); }
        function back(): void { ControlCenterActions.back("ipc"); }
        function panel(): string { return ControlCenterActions.panel; }

        function network(ssid: string): void { ControlCenterActions.network(ssid); }
        function passphrase(ssid: string, secret: string): void {
            ControlCenterActions.passphrase(ssid, secret);
        }
        function forgetNetwork(ssid: string): void {
            ControlCenterActions.forgetNetwork(ssid);
        }
        function device(address: string): void { ControlCenterActions.device(address); }
        function forgetDevice(address: string): void {
            ControlCenterActions.forgetDevice(address);
        }
        function output(id: string): void { ControlCenterActions.output(id); }
        function stream(id: string, percent: int): void {
            ControlCenterActions.stream(id, percent);
        }
        function muteStream(id: string): void { ControlCenterActions.muteStream(id); }
        function tunnel(name: string): void { ControlCenterActions.tunnel(name); }
        function wallpaper(path: string): void { ControlCenterActions.wallpaper(path); }
    }

    // The dashboard's door (#49). `dashboard`, lowercase and one word, which is
    // the spelling Core/SurfaceBusPolicy.qml wrote down for the clock that
    // dispatches to it.
    //
    //     bind = SUPER, D, exec, qs ipc call dashboard toggle
    //
    // The four doors and no more, unlike the control centre's twelve. The
    // dashboard's cards have nothing to press that a door would have to reach:
    // the calendar's paging is arithmetic `tests/` drives directly
    // (Surfaces/Drawers/CalendarPolicy.qml), and the media card's transport and
    // seek are the *player's*, so they are driven where the player is —
    // `busctl` from the fixture's side, and `qs ipc call media seek` from the
    // service that owns it (Services/Media/Mpris.qml).
    IpcHandler {
        target: "dashboard"

        function open(): void { root.open("dashboard"); }
        function close(): void { root.close("ipc"); }
        function toggle(): void { root.toggle("dashboard"); }
        function isOpen(): bool { return root.current === "dashboard"; }
    }

    // --- Super+Space ---------------------------------------------------------
    //
    // The summon (#39), registered from QML rather than shelled out to. In the
    // user's hyprland.conf that is:
    //
    //     bind = SUPER, SPACE, global, forest-shell:launcher
    //
    // and it is the one binding in the shell with no `qs ipc call … || fallback`
    // behind it. That idiom keeps a compositor usable when the shell is not
    // running, and it cannot be written here: a `global` dispatch has no
    // subprocess to fail, and the keybind template forbids the `|` the fallback
    // needs. What it buys instead is the reason to prefer it — no `qs`
    // subprocess spawn per keypress on the shell's most-pressed key.
    //
    // Nothing happens if the user has not written the bind. That is not a
    // failure worth logging on a timer: the IPC door above answers the same
    // question, and a shell that complains every start about a keybind it
    // cannot see is a shell nobody reads the log of.
    GlobalShortcut {
        appid: "forest-shell"
        name: "launcher"
        description: "Open the launcher"

        onPressed: root.toggle("launcher")
    }

    Component.onCompleted: {
        SurfaceBus.register("session", root.sessionHandle);
        SurfaceBus.register("launcher", root.launcherHandle);
        SurfaceBus.register("notificationcenter", root.notificationCenterHandle);
        SurfaceBus.register("controlcenter", root.controlCenterHandle);
        SurfaceBus.register("dashboard", root.dashboardHandle);
        SurfaceBus.registerBar(root.barHandle);
        Logger.stage("drawers armed (ipc targets: session, launcher, "
                     + "notificationcenter, controlcenter, dashboard)");
        if (Startup.deferredRan)
            root.applyBlurRule();
    }
}
