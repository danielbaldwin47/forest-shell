// What the control centre's drill-ins decide (#45): which control opens which
// panel, what a press on a tile means once that tile has a door in it, when a
// radio is allowed to scan, and which way the slide goes.
//
// Five panels, one at a time, inside the panel that is already open — the
// ticket's "slide-in within the same panel". So this is navigation with a depth
// of exactly one: there is a root and there is a detail view, and `back` from a
// detail view is always the root. That is not a limitation to design around, it
// is the shape: a control centre you can get lost two levels down in is one
// where the way out is a guess.
//
// Everything here imports nothing but QtQuick, so `tests/` reaches all of it.
// The panels themselves are Surfaces/Drawers/DrillIn/*.qml and each needs a
// compositor; what a press *does* once routed is each service's own facade,
// where the exit-status checks (#78) and the log lines (#81) already live.
import QtQuick

QtObject {
    id: policy

    /// The five, in no particular order — nothing draws this list, it is what
    /// `known` is asked about. A name that is not here is a name nothing opens,
    /// which over IPC is something a person typed into a keybind and deserves a
    /// line saying why it did nothing.
    readonly property var panels: ["wifi", "bluetooth", "audio", "vpn", "wallpaper"]

    /// The title bar of each. "Sound" and not "Audio", because the panel holds
    /// an output picker *and* a per-application mixer and neither is what a
    /// person calls "audio".
    readonly property var titles: ({
        wifi: "Wi-Fi",
        bluetooth: "Bluetooth",
        audio: "Sound",
        vpn: "VPN",
        wallpaper: "Wallpaper"
    })

    readonly property var icons: ({
        wifi: "wifi",
        bluetooth: "bluetooth",
        audio: "volume-2",
        vpn: "shield",
        wallpaper: "image"
    })

    function known(name: var): bool {
        return policy.panels.indexOf(String(name ?? "")) >= 0;
    }

    function title(name: var): string {
        return policy.titles[String(name ?? "")] ?? "";
    }

    function icon(name: var): string {
        return policy.icons[String(name ?? "")] ?? "chevron-right";
    }

    // --- which control opens which panel -------------------------------------

    /// The panel a tile's chevron opens, or `""` for a tile that is only a
    /// switch. Three of the nine have both halves — Wi-Fi, Bluetooth and VPN are
    /// a state to toggle *and* a list to choose from — and one, the wallpaper,
    /// has only the door.
    ///
    /// Night Light and the power profile deliberately do not: both are a single
    /// value the settings window already owns a full editor for (#54), and a
    /// third place to set a colour temperature is a third place for it to
    /// disagree with itself.
    function panelFor(tileId: var): string {
        switch (String(tileId ?? "")) {
        case "wifi":      return "wifi";
        case "bluetooth": return "bluetooth";
        case "vpn":       return "vpn";
        case "wallpaper": return "wallpaper";
        }
        return "";
    }

    /// The tiles where the door is the *whole* tile rather than a chevron on
    /// it. Only the wallpaper: it has no on-state, so there is no toggle for a
    /// body press to mean and a chevron alone would leave five sixths of the
    /// tile dead.
    function doorOnly(tileId: var): bool {
        return String(tileId ?? "") === "wallpaper";
    }

    /// The panel a *slider* opens. The sound panel has no tile — the volume
    /// slider is the control it belongs behind, which is also where a person
    /// looks for it: "which speakers is this slider moving" is asked while
    /// looking at the slider.
    ///
    /// The microphone opens the same panel, because it is one panel about the
    /// machine's sound. Brightness opens nothing: there is one backlight.
    function panelForSlider(sliderId: var): string {
        const id = String(sliderId ?? "");
        return id === "volume" || id === "mic" ? "audio" : "";
    }

    /// The panel a *bar indicator* opens (#184), or `""` for a reading that is
    /// only a reading. The bar's status cluster shows the same four things
    /// three of these panels are about, and a click on one is the request the
    /// matching tile's chevron already makes — "which network is this" gets
    /// asked while looking at the wifi glyph, not after opening the control
    /// centre and finding the tile.
    ///
    /// Its own switch rather than a call to `panelFor` and `panelForSlider`,
    /// even though the answers agree today: those two are asked by controls
    /// inside the control centre, where `vpn` and `wallpaper` are also answers,
    /// and neither of those has a bar indicator.
    ///
    /// An indicator listed here needs a click that asks for it — the bar
    /// deliberately does not import the drawers, so the request goes through
    /// Core/SurfaceBus.qml `barIndicator` and the name has to match on both
    /// sides. The cursor is no longer part of that pairing: #184 had the bar
    /// carry an `opensPanel` flag so a hand meant a door specifically, and #185
    /// replaced it with the flag that gates the input, because a bar with no
    /// hover highlight needs the pointer to mean the broader thing. Battery,
    /// brightness and the system monitor have no panel here — building one for
    /// them is a separate piece of work.
    function panelForIndicator(indicatorId: var): string {
        switch (String(indicatorId ?? "")) {
        case "wifi":      return "wifi";
        case "bluetooth": return "bluetooth";
        case "volume":    return "audio";
        case "mic":       return "audio";
        }
        return "";
    }

    // --- moving between them -------------------------------------------------

    /// Where a request to open `name` lands, given what is open now.
    ///
    /// Pressing the door you are already behind takes you back out, which is
    /// the same rule Surfaces/Drawers/DrawerPolicy.qml applies one level up:
    /// the control that opened a thing closes it, so no press is ever a no-op
    /// the user has to find another way out of.
    function next(current: var, name: var): string {
        const wanted = String(name ?? "");
        if (!policy.known(wanted))
            return String(current ?? "");
        return String(current ?? "") === wanted ? "" : wanted;
    }

    /// Depth of exactly one, so there is one answer.
    function back(): string {
        return "";
    }

    /// Whether the panel is showing a detail view at all. The root is `""` and
    /// not a name, so "am I drilled in" is one comparison and not a lookup.
    function drilled(current: var): bool {
        return policy.known(current);
    }

    // --- what an open costs --------------------------------------------------

    /// Whether opening this panel has to start a radio scanning.
    ///
    /// Two of the five do, and the reason they are not scanning already is the
    /// idle budget (#22 §5): Services/Networking/Networking.qml leaves
    /// `scannerEnabled` off and Services/Networking/Bluetooth.qml starts no
    /// discovery, because both are a radio kept awake for a list nobody is
    /// looking at. This is the moment somebody is looking at it — and `back`
    /// is the moment they stop, which is why the scan is tied to the panel's
    /// lifetime rather than to a button.
    function scans(name: var): bool {
        const id = String(name ?? "");
        return id === "wifi" || id === "bluetooth";
    }

    // --- the slide -----------------------------------------------------------
    //
    // #27's in-place step: the panel is already on screen and only its contents
    // change, so this is `motionFast` (140 ms) and not the drawer's own 320 —
    // the same rung Surfaces/Drawers/ControlTile.qml fades its fill on.
    // `Theme.duration` is what actually takes it away under reduced effects;
    // nothing here knows about the ladder.

    /// How far the incoming view starts off to the side, as a fraction of the
    /// panel's width. A tenth: enough to read as arriving from the right,
    /// small enough that the whole slide happens inside the panel's own edges
    /// rather than looking like something flying in from off screen.
    readonly property real slideFraction: 0.1

    /// Which way a view moves, in units of `slideFraction × width`.
    ///
    /// Going in, the detail arrives from the right and the root leaves to the
    /// left; coming back, both reverse. That is the one convention that makes a
    /// depth-of-one navigation legible without a breadcrumb: forward is
    /// leftward, so the way back is always the way you came.
    function offset(forward: bool, incoming: bool): real {
        const direction = forward ? 1 : -1;
        return (incoming ? direction : -direction) * policy.slideFraction;
    }

    // --- what the log says ---------------------------------------------------
    //
    // One line per act, which is what makes the drill-ins drivable from
    // tools/drawer-harness.sh — a panel is a `TapHandler` inside a drawer and
    // this repo has no pointer-injection tool it may assume, so the IPC door and
    // these lines are the whole of the seam-2 evidence (#81).

    function opened(name: string): string {
        return name + " panel opened";
    }

    function closed(name: string, reason: string): string {
        return name + " panel closed (" + reason + ")";
    }

    function refused(name: string, reason: string): string {
        return "no " + name + " panel — " + reason;
    }
}
