pragma Singleton

// What a control-centre control actually does (#44) — the routing table, split
// out of the panel.
//
//     ControlCenterActions.press("wifi")
//     qs ipc call controlcenter press nightlight
//     qs ipc call controlcenter drill wifi        # the detail views (#45)
//     qs ipc call controlcenter back
//
// ## Why this is not inside ControlCenter.qml
//
// It was, and the ticket's acceptance criteria could not be checked. "Wi-Fi,
// BT, DND, Night Light, Keep Awake, Dark/Light, Power Profile, VPN toggles
// functional" is a seam-2 claim — it is about services talking to real
// hardware, a real `powerprofilesctl`, a real NetworkManager. But a tile is a
// `TapHandler` inside a drawer, and this repo has no key- or pointer-injection
// tool it may assume (tools/drawer-harness.sh says so at length about Escape).
// A routing table reachable only by clicking is a routing table nothing can
// assert on, which is #81 restated: the failure would be a tile that silently
// does nothing, and the log would not say which of nine.
//
// Pulled out here it is reachable from `tools/drawer-harness.sh`, and
// there is exactly one copy of it — the panel calls the same function the IPC
// door does, so a harness that drives `press` is driving what the tile drives.
//
// It is also a feature rather than a test hook, which is why it is a documented
// door and not a `harnessOnly` flag:
//
//     bind = SUPER, N, exec, qs ipc call controlcenter press nightlight
//
// ## What is not here
//
// The checks. Every branch below is one call into a service facade, and the
// facade is where the "no adapter", "busy", "nothing configured" and exit-status
// cases live (#78) along with the log line for each (#81). Two places deciding
// whether bluetooth can be toggled is how they come to disagree.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import qs.Core
import qs.Services.Media
import qs.Services.Hardware
import qs.Services.Networking
import qs.Services.Notifications
import qs.Services.Recorder
import qs.Surfaces.Background

Singleton {
    id: root

    readonly property ControlCenterPolicy policy: ControlCenterPolicy {}
    readonly property DrillInPolicy drillPolicy: DrillInPolicy {}

    /// What each toggle is currently showing, so the line logged below can say
    /// what the press is *asking for* rather than just that it happened.
    ///
    /// Read here and not from the panel's `facts`: a press can arrive over IPC
    /// with no panel open at all, and a second source of truth for "is wifi on"
    /// is how the two come to disagree.
    function stateOf(id: string): bool {
        switch (id) {
        case "wifi":       return Networking.wifiEnabled;
        case "bluetooth":  return Bluetooth.enabled;
        case "dnd":        return Notifications.dnd;
        case "nightlight": return NightLight.on;
        case "keepawake":  return KeepAwake.on;
        case "mode":       return !Theme.dark;    // the tile is lit for light
        case "vpn":        return Vpn.on;
        case "recording":  return Recorder.active;
        }
        return false;
    }

    /// Press a tile, by the id ControlCenterPolicy gave it.
    ///
    /// **Every branch logs before it routes**, and that is the ticket's own ask
    /// (#44, "a log line per toggle so seam 2 can assert it", #81). The facades
    /// log their outcomes, but three of them log nothing on success at all —
    /// DND writes state, Keep Awake writes state, the theme mode writes a config
    /// key — so without this line a press on any of the three would be
    /// indistinguishable from a tile wired to nothing.
    ///
    /// It says what was *asked for*. The facade's own line, when there is one,
    /// says what happened; the two together are what tell a refusal apart from
    /// a dead control.
    ///
    /// An id no tile has is a warning and not a silent return: over IPC this is
    /// a name someone typed into a keybind, and a keybind that does nothing is
    /// worth one line saying why.
    function press(id: string): void {
        // One switch and not two on the same id: the log line and the call
        // have to stay in step, and two cascades a screen apart are two places
        // to forget a tile.
        switch (id) {
        case "wifi":         root.announce(id); Networking.toggleWifi(); return;
        case "bluetooth":    root.announce(id); Bluetooth.toggle(); return;
        case "dnd":          root.announce(id); Notifications.toggleDnd(); return;
        case "nightlight":   root.announce(id); NightLight.toggle(); return;
        case "keepawake":    root.announce(id); KeepAwake.toggle(); return;
        case "mode":         root.announce(id); Theme.setDark(!Theme.dark); return;
        case "vpn":          root.announce(id); Vpn.toggle(); return;
        // A toggle like the others, and the only one that leaves a file
        // behind. Whole-screen: the region variant is a drag, so it goes
        // through the launcher and a keybind rather than through a tile the
        // drawer would have to close first.
        case "recording":    root.announce(id); Recorder.toggle("control-centre"); return;
        // The two with no on-state to name: one cycles through whatever the
        // daemon offers, one opens a door.
        case "powerprofile":
            Logger.log("control-centre", root.policy.pressed(id));
            PowerProfiles.cycle();
            return;
        case "wallpaper":
            Logger.log("control-centre", root.policy.pressed(id));
            root.drill("wallpaper");
            return;
        }
        Logger.warn("control-centre", root.policy.refused(id, "no such control"));
    }

    /// The line a boolean toggle logs before it routes: what is being asked
    /// for, which is the current state inverted.
    function announce(id: string): void {
        Logger.log("control-centre", root.policy.toggled(id, !root.stateOf(id)));
    }

    // --- the drill-ins (#45) -------------------------------------------------
    //
    // Which detail view is open, and the two verbs that move between them. State
    // and not a surface property, for the same reason the routing table above is
    // here: a panel is a `TapHandler` inside a drawer and nothing can click it,
    // so `qs ipc call controlcenter drill wifi` is both a feature and the only
    // seam-2 evidence that any of this is wired at all.
    //
    // One value and not a flag per panel, which is what makes two detail views
    // open at once unrepresentable — the same shape Drawers.qml uses one level
    // up.

    /// The open panel's name, or `""` for the root. Written by `drill()` and
    /// `back()` and by nothing else: those two are where the log line and the
    /// scanner handoff live, and a state change that did not go through them is
    /// one the harness cannot see (#81) and a radio nobody turned off.
    property string panel: ""

    /// Which way the last transition went, so the surface knows which way to
    /// slide. Forward is into a panel; back is out of one.
    property bool forward: true

    /// The network whose passphrase prompt is open, or `""`. Here rather than
    /// inside the row's delegate on purpose: the wifi list republishes when a
    /// network appears or drops (#75), and a prompt living in a delegate would
    /// lose what the user had typed the moment a neighbouring access point came
    /// or went.
    property string prompt: ""

    /// Open a detail view, or close the one whose door was pressed again.
    function drill(name: string): void {
        const next = root.drillPolicy.next(root.panel, name);
        if (next === root.panel) {
            Logger.warn("control-centre",
                        root.drillPolicy.refused(name, "no such panel"));
            return;
        }
        root.forward = next !== "";
        root.setPanel(next, "toggle");
    }

    /// Leave whatever is open. `reason` travels into the log because a panel the
    /// user backed out of and one the closing drawer took down look identical
    /// afterwards, and the harness has to tell them apart.
    function back(reason: string): void {
        if (root.panel === "")
            return;
        root.forward = false;
        root.setPanel(root.drillPolicy.back(), reason);
    }

    /// The one place `panel` is written — so the scanner a panel holds is
    /// always released by whatever closes it, including the drawer closing
    /// under it. A radio left discovering because a code path forgot is exactly
    /// the class of bug the idle budget (#22 §5) is written against, and it is
    /// invisible: nothing on screen looks different.
    function setPanel(next: string, reason: string): void {
        if (next === root.panel)
            return;

        if (root.drillPolicy.scans(root.panel))
            root.releaseScan(root.panel);
        if (root.panel !== "")
            Logger.log("control-centre", root.drillPolicy.closed(root.panel, reason));

        root.panel = next;
        root.prompt = "";
        Networking.clearFailure();

        if (next !== "") {
            Logger.log("control-centre", root.drillPolicy.opened(next));
            if (root.drillPolicy.scans(next))
                root.holdScan(next);
        }
    }

    function holdScan(name: string): void {
        if (name === "wifi")
            Networking.beginScan();
        else if (name === "bluetooth")
            Bluetooth.beginDiscovery();
    }

    function releaseScan(name: string): void {
        if (name === "wifi")
            Networking.endScan();
        else if (name === "bluetooth")
            Bluetooth.endDiscovery();
    }

    // --- what a row inside a panel does --------------------------------------
    //
    // Each is one call into the facade that owns the thing, and the checks are
    // all over there (#78) along with the log line for each (#81). Two places
    // deciding whether a device can be connected is how they come to disagree.

    /// Press a Wi-Fi row. Everything except a network that needs a passphrase
    /// happens immediately; that one raises the prompt instead, which is a
    /// surface state and so is the one branch that stays here.
    function network(ssid: string): void {
        const row = Networking.rowFor(ssid);
        if (row === null) {
            Logger.warn("control-centre",
                        root.policy.refused(ssid, "no such network"));
            return;
        }
        switch (Networking.wifi.action(row)) {
        // Cancelling a join in flight and disconnecting a joined network are
        // the same call to NetworkManager — it is the same association being
        // taken down, at two different points in its life.
        case "cancel":
        case "disconnect":  root.prompt = ""; Networking.leave(ssid); return;
        case "connect":     root.prompt = ""; Networking.join(ssid, ""); return;
        case "prompt":      root.askPassphrase(ssid); return;
        // A network this shell cannot join. The facade owns the words, so it is
        // called anyway and refuses out loud rather than being second-guessed.
        case "unsupported": Networking.join(ssid, ""); return;
        }
    }

    function askPassphrase(ssid: string): void {
        Networking.clearFailure();
        root.prompt = ssid;
        Logger.log("control-centre", "passphrase asked for " + ssid);
    }

    /// Submit one. Empty is a cancel rather than an attempt — a prompt closed
    /// with nothing in it is a user who changed their mind, not one asking to
    /// join an open network by that name.
    function passphrase(ssid: string, secret: string): void {
        if (String(secret ?? "") === "") {
            root.prompt = "";
            Logger.log("control-centre", "passphrase cancelled for " + ssid);
            return;
        }
        root.prompt = "";
        Networking.join(ssid, secret);
    }

    function forgetNetwork(ssid: string): void {
        root.prompt = "";
        Networking.forget(ssid);
    }

    function device(address: string): void {
        Bluetooth.pressDevice(address);
    }

    function forgetDevice(address: string): void {
        Bluetooth.forgetDevice(address);
    }

    function output(id: string): void {
        Audio.setDefaultSink(id);
    }

    function stream(id: string, percent: int): void {
        Audio.setStreamVolume(id, root.policy.fraction(percent));
    }

    function muteStream(id: string): void {
        Audio.toggleStreamMute(id);
    }

    function tunnel(name: string): void {
        Vpn.pressTunnel(name);
    }

    function wallpaper(path: string): void {
        Wallpapers.choose(path);
    }

    /// Move a slider, in whole percent. Run continuously through a drag rather
    /// than on release: every service here takes a live value, and a volume you
    /// cannot hear yourself setting is a volume you set twice.
    function slide(id: string, percent: int): void {
        const value = root.policy.clampPercent(percent);
        if (root.policy.sliderOrder.indexOf(id) < 0) {
            Logger.warn("control-centre", root.policy.refused(id, "no such slider"));
            return;
        }

        // Not on every frame of a drag — that would be a log nobody can read,
        // and the same objection Services/Networking/Networking.qml makes about
        // logging signal strength. Only when the whole-percent value actually
        // moves, which for a drag across a 300px track is fifty lines rather
        // than one per frame.
        if (root.lastSlide[id] !== value) {
            root.lastSlide[id] = value;
            Logger.log("control-centre", root.policy.moved(id, value));
        }

        switch (id) {
        case "volume":     Audio.setVolume(root.policy.fraction(value)); return;
        case "mic":        Audio.setSourceVolume(root.policy.fraction(value)); return;
        case "brightness": Backlight.setPercent(value); return;
        }
    }

    /// The last value logged per slider, so a drag that passes over the same
    /// whole percent twice does not say so twice. Mutated in place: nothing
    /// binds to it, so there is no notification to preserve.
    property var lastSlide: ({})

    /// One notch, for the wheel and the arrow keys — and for a keybind, which
    /// is the caller that cannot read the current value to nudge from.
    /// Routed through `slide` rather than through each service's own `step`,
    /// so all three land on the policy's grid and all three log — an earlier
    /// version called `Audio.stepVolume` and `Backlight.step` directly and
    /// those two notches produced no `control-centre:` line at all, which is
    /// the rule this file states two functions up broken by its own author.
    function nudge(id: string, direction: int): void {
        const from = root.currentPercent(id);
        if (from < 0) {
            Logger.warn("control-centre", root.policy.refused(id, "no such slider"));
            return;
        }
        root.slide(id, root.policy.nudge(from, direction));
    }

    /// Where a slider is now, or -1 for an id that is not one. The nudge needs
    /// it because a keybind, unlike a wheel over a track, has no on-screen
    /// value to step from.
    function currentPercent(id: string): int {
        switch (id) {
        case "volume":     return root.policy.percent(Audio.volume);
        case "mic":        return root.policy.percent(Audio.sourceVolume);
        case "brightness": return Backlight.percent;
        }
        return -1;
    }

    function mute(id: string): void {
        if (id === "volume")
            Audio.toggleMute();
        else if (id === "mic")
            Audio.toggleSourceMute();
        else
            Logger.warn("control-centre", root.policy.refused(id, "does not mute"));
    }
}
