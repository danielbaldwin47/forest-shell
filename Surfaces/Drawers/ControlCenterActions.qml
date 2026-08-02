pragma Singleton

// What a control-centre control actually does (#44) — the routing table, split
// out of the panel.
//
//     ControlCenterActions.press("wifi")
//     qs ipc call controlcenter press nightlight
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
// Pulled out here it is reachable from `tools/control-center-harness.sh`, and
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

Singleton {
    id: root

    readonly property ControlCenterPolicy policy: ControlCenterPolicy {}

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
        switch (id) {
        case "wifi":
        case "bluetooth":
        case "dnd":
        case "nightlight":
        case "keepawake":
        case "mode":
        case "vpn":
            Logger.log("control-centre", root.policy.toggled(id, !root.stateOf(id)));
            break;
        case "powerprofile":
        case "wallpaper":
            // No on-state to name: one cycles and one opens a door.
            Logger.log("control-centre", root.policy.pressed(id));
            break;
        default:
            Logger.warn("control-centre", root.policy.refused(id, "no such control"));
            return;
        }

        switch (id) {
        case "wifi":         Networking.toggleWifi(); return;
        case "bluetooth":    Bluetooth.toggle(); return;
        case "dnd":          Notifications.toggleDnd(); return;
        case "nightlight":   NightLight.toggle(); return;
        case "keepawake":    KeepAwake.toggle(); return;
        case "mode":         Theme.setDark(!Theme.dark); return;
        case "powerprofile": PowerProfiles.cycle(); return;
        case "vpn":          Vpn.toggle(); return;
        case "wallpaper":    root.drillIn("wallpaper"); return;
        }
    }

    /// The one tile that is a door. Stubbed until the wallpaper ticket builds
    /// the panel behind it — and logged rather than silent, because a press
    /// that does nothing and says nothing is #81 exactly.
    function drillIn(name: string): void {
        Logger.log("control-centre",
                   root.policy.refused(name, "the picker is not built yet"));
    }

    /// Move a slider, in whole percent. Run continuously through a drag rather
    /// than on release: every service here takes a live value, and a volume you
    /// cannot hear yourself setting is a volume you set twice.
    function slide(id: string, percent: int): void {
        const value = root.policy.clampPercent(percent);
        if (["volume", "mic", "brightness"].indexOf(id) < 0) {
            Logger.warn("control-centre", root.policy.refused(id, "no such slider"));
            return;
        }

        // Not on every frame of a drag — that would be a log nobody can read,
        // and the same objection Services/Networking/Networking.qml makes about
        // logging signal strength. Only when the whole-percent value actually
        // moves, which for a drag across a 300px track is fifty lines rather
        // than one per frame.
        if (root.lastSlide[id] !== value) {
            const next = Object.assign({}, root.lastSlide);
            next[id] = value;
            root.lastSlide = next;
            Logger.log("control-centre", root.policy.moved(id, value));
        }

        switch (id) {
        case "volume":     Audio.setVolume(root.policy.fraction(value)); return;
        case "mic":        Audio.setSourceVolume(root.policy.fraction(value)); return;
        case "brightness": Backlight.setPercent(value); return;
        }
    }

    /// The last value logged per slider, so a drag that passes over the same
    /// whole percent twice does not say so twice.
    property var lastSlide: ({})

    /// One notch, for the wheel and the arrow keys — and for a keybind, which
    /// is the caller that cannot read the current value to nudge from.
    function nudge(id: string, direction: int): void {
        switch (id) {
        case "volume":     Audio.stepVolume(direction); return;
        case "mic":
            root.slide("mic", root.policy.nudge(root.policy.percent(Audio.sourceVolume),
                                                direction));
            return;
        case "brightness": Backlight.step(direction); return;
        }
        Logger.warn("control-centre", root.policy.refused(id, "no such slider"));
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
