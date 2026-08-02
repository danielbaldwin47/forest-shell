// What the control centre decides (#44): which tiles the grid has, what each
// one says, which sliders this machine can offer, and the words in the bottom
// strip.
//
// The shape is the one Services/Networking/NetworkPolicy.qml uses and for the
// same reason: the surface next door imports Quickshell and so cannot be
// reached from `tests/`, and everything here is a decision rather than a
// picture. Facts arrive as a plain object the surface assembles from the
// services — no `Quickshell` type crosses this line, which is what lets a test
// describe a tower with no battery, no radio and no backlight in four lines.
//
// ## The one rule the whole grid follows
//
// **Absent hardware has no tile; a subsystem that is off keeps its tile.** A
// machine with no bluetooth radio shows no bluetooth control, because a
// control nobody can act on is furniture (the same rule
// Services/Networking/BluetoothPolicy.qml states for the bar). A radio that is
// merely *off* is the opposite case: that tile is the one you press to turn it
// back on, so it stays, unlit.
//
// The order is fixed and does not depend on what is present, because grid
// position is muscle memory — the tile you reach for without looking must not
// move because a VPN profile got configured. What a missing tile does is close
// the gap behind it, so the grid is always full rows and never a hole.
import QtQuick

QtObject {
    id: policy

    /// The grid, in the order it is drawn. Nine on a full laptop, which is the
    /// 3×3 the ticket asks for; fewer on a machine missing the hardware.
    readonly property var tileOrder: [
        "wifi", "bluetooth", "dnd", "nightlight", "keepawake",
        "mode", "powerprofile", "vpn", "wallpaper"
    ]

    readonly property int columns: 3

    /// The sliders, in the order they are drawn, above the grid.
    readonly property var sliderOrder: ["volume", "mic", "brightness"]

    /// One notch of a wheel or an arrow key, in percent. The same step
    /// Services/Media/AudioPolicy.qml and Services/Hardware/BacklightPolicy.qml
    /// use for the bar's scroll, so a notch means one thing in the shell rather
    /// than two.
    readonly property int step: 5

    // --- the grid ------------------------------------------------------------

    /// Every tile this machine has, in `tileOrder`, each already resolved to
    /// what it draws: `{ id, on, icon, label, detail, drillIn }`.
    ///
    /// `on` is what fills the tile teal, and it means *engaged*, not
    /// *available* — see `modeTile` for the one place that distinction has a
    /// visible consequence.
    function tiles(facts: var): var {
        const out = [];
        for (const id of policy.tileOrder) {
            const tile = policy.tile(id, facts ?? ({}));
            if (tile !== null)
                out.push(tile);
        }
        return out;
    }

    /// One tile, or `null` when this machine has no such hardware.
    function tile(id: string, facts: var): var {
        switch (id) {
        case "wifi":         return policy.wifiTile(facts.wifi ?? ({}));
        case "bluetooth":    return policy.bluetoothTile(facts.bluetooth ?? ({}));
        case "dnd":          return policy.dndTile(facts.dnd ?? ({}));
        case "nightlight":   return policy.nightLightTile(facts.nightlight ?? ({}));
        case "keepawake":    return policy.keepAwakeTile(facts.keepawake ?? ({}));
        case "mode":         return policy.modeTile(facts.dark !== false);
        case "powerprofile": return policy.powerProfileTile(facts.powerprofile ?? ({}));
        case "vpn":          return policy.vpnTile(facts.vpn ?? ({}));
        case "wallpaper":    return policy.wallpaperTile();
        }
        return null;
    }

    /// The tiles chunked into rows of `columns`. A short last row is short
    /// rather than padded — the layout left-aligns it, and a padded row is a
    /// row with an invisible pressable hole in it.
    function rows(list: var): var {
        const flat = list ?? [];
        const out = [];
        for (let i = 0; i < flat.length; i += policy.columns)
            out.push(flat.slice(i, i + policy.columns));
        return out;
    }

    // --- one tile at a time --------------------------------------------------
    //
    // Each is a function rather than a table because every one of them decides
    // something: which of two glyphs, whether the detail line is a state word
    // or a name the user chose.

    /// One tile, as the grid draws it. Named `makeTile` and not `row`, which is
    /// what it was: `rows()` twenty lines up chunks tiles into *grid rows*, and
    /// two meanings of "row" one screen apart is one of them being read wrong.
    function makeTile(id: string, on: bool, icon: string, label: string,
                      detail: string): var {
        return { id: id, on: on === true, icon: icon, label: label,
                 detail: detail, drillIn: false };
    }

    function wifiTile(wifi: var): var {
        if (wifi.available !== true)
            return null;
        const on = wifi.on === true;
        // The network's own name when there is one — "Wi-Fi / PUMPKINCURRY" is
        // the line that answers "am I on the right network", which is the
        // question anybody opens this for.
        return policy.makeTile("wifi", on, on ? "wifi" : "wifi-off", "Wi-Fi",
                          on ? (wifi.label || "Not connected") : "Off");
    }

    function bluetoothTile(bluetooth: var): var {
        if (bluetooth.present !== true)
            return null;
        const on = bluetooth.on === true;
        return policy.makeTile("bluetooth", on, on ? "bluetooth" : "bluetooth-off",
                          "Bluetooth", on ? (bluetooth.label || "No devices") : "Off");
    }

    function dndTile(dnd: var): var {
        const on = dnd.on === true;
        return policy.makeTile("dnd", on, "bell-off", "Do Not Disturb",
                          policy.stateWord(on));
    }

    /// Night light, with the temperature it is holding. The number is the
    /// reason this is not just a lamp: "on" says nothing about how warm, and
    /// the warmth is the part the user tuned.
    function nightLightTile(nightlight: var): var {
        if (nightlight.available !== true)
            return null;
        const on = nightlight.on === true;
        return policy.makeTile("nightlight", on, on ? "moon-star" : "moon", "Night Light",
                          on ? policy.temperatureLabel(nightlight.temperature) : "Off");
    }

    function temperatureLabel(kelvin: var): string {
        const value = Math.round(Number(kelvin));
        return isFinite(value) && value > 0 ? value + "K" : "On";
    }

    function keepAwakeTile(keepawake: var): var {
        const on = keepawake.on === true;
        return policy.makeTile("keepawake", on, "coffee", "Keep Awake",
                          policy.stateWord(on));
    }

    /// Dark/Light. The tile is lit for **light**, which is the mode that is not
    /// the default: v1 ships dark-first (#8), so a tile that was filled on a
    /// dark shell would be filled almost always, and a grid with something
    /// permanently lit in it teaches nobody what lit means.
    function modeTile(dark: bool): var {
        const light = dark !== true;
        return policy.makeTile("mode", light, light ? "sun" : "moon", "Theme",
                          light ? "Light" : "Dark");
    }

    /// The three profiles power-profiles-daemon ships, plus whatever else it
    /// offers. An unrecognised profile is shown under its own name rather than
    /// hidden — a machine running a vendor profile this shell has never heard
    /// of is a machine whose user should be able to see that.
    ///
    /// Lit for anything that is not `balanced`, which is the daemon's own
    /// default: the same rule as the mode tile, one rung down.
    function powerProfileTile(profile: var): var {
        if (profile.available !== true)
            return null;
        const name = profile.profile || "balanced";
        return policy.makeTile("powerprofile", name !== "balanced",
                          policy.profileIcon(name), "Power Profile",
                          policy.profileLabel(name));
    }

    function profileIcon(name: string): string {
        if (name === "performance")
            return "zap";
        return name === "power-saver" ? "leaf" : "gauge";
    }

    function profileLabel(name: string): string {
        if (name === "performance")
            return "Performance";
        if (name === "power-saver")
            return "Power Saver";
        return name === "balanced" ? "Balanced" : name;
    }

    /// The VPN, named. A tunnel that is up is one the user chose by name, and
    /// "On" would drop the only part of it worth reading.
    function vpnTile(vpn: var): var {
        if (vpn.available !== true)
            return null;
        const on = vpn.on === true;
        return policy.makeTile("vpn", on, on ? "shield" : "shield-off", "VPN",
                          on ? (vpn.name || "On") : "Off");
    }

    /// The one tile that is a door rather than a switch: it opens the wallpaper
    /// drill-in, so it has no on-state to show. Stub until that ticket lands —
    /// `drillIn` is what tells the surface to open a panel instead of calling a
    /// service.
    function wallpaperTile(): var {
        const tile = policy.makeTile("wallpaper", false, "wallpaper", "Wallpaper", "");
        tile.drillIn = true;
        return tile;
    }

    function stateWord(on: bool): string {
        return on === true ? "On" : "Off";
    }

    // --- the sliders ---------------------------------------------------------

    /// The sliders this machine can offer: `{ id, percent, icon, label, muted,
    /// mutable }`. A tower on a DisplayPort monitor has no
    /// `/sys/class/backlight` and a machine with no microphone has no source —
    /// in both cases a slider that moves nothing is worse than an absent one.
    function sliders(facts: var): var {
        const out = [];
        for (const id of policy.sliderOrder) {
            const slider = policy.slider(id, facts ?? ({}));
            if (slider !== null)
                out.push(slider);
        }
        return out;
    }

    function slider(id: string, facts: var): var {
        switch (id) {
        case "volume":     return policy.volumeSlider(facts.volume ?? ({}));
        case "mic":        return policy.micSlider(facts.mic ?? ({}));
        case "brightness": return policy.brightnessSlider(facts.brightness ?? ({}));
        }
        return null;
    }

    function track(id: string, percent: var, icon: string, label: string,
                   muted: bool, mutable: bool): var {
        return { id: id, percent: policy.clampPercent(percent), icon: icon,
                 label: label, muted: muted === true, mutable: mutable === true };
    }

    function volumeSlider(volume: var): var {
        if (volume.available !== true)
            return null;
        const muted = volume.muted === true;
        return policy.track("volume", volume.percent, muted ? "volume-x" : "volume-2",
                            "Volume", muted, true);
    }

    function micSlider(mic: var): var {
        if (mic.available !== true)
            return null;
        const muted = mic.muted === true;
        return policy.track("mic", mic.percent, muted ? "mic-off" : "mic",
                            "Microphone", muted, true);
    }

    /// The one slider with no mute: a screen at 0% is not the same act as a
    /// muted speaker, and there is nothing to restore it to.
    function brightnessSlider(brightness: var): var {
        if (brightness.available !== true)
            return null;
        return policy.track("brightness", brightness.percent, "sun", "Brightness",
                            false, false);
    }

    // --- moving a slider -----------------------------------------------------

    /// A service fraction as a whole percent. Clamped: PipeWire allows
    /// over-unity volume and the track does not, so a sink at 140% draws full
    /// rather than off the end.
    function percent(fraction: real): int {
        if (!isFinite(fraction))
            return 0;
        return Math.round(Math.max(0, Math.min(1, fraction)) * 100);
    }

    /// The inverse, for a drag: what the service is handed back.
    function fraction(percentValue: real): real {
        return policy.clampPercent(percentValue) / 100;
    }

    function clampPercent(value: var): int {
        const number = Number(value);
        if (!isFinite(number))
            return 0;
        return Math.round(Math.max(0, Math.min(100, number)));
    }

    /// One notch, in `direction` ±1. Lands *on* the step grid rather than
    /// stepping from wherever a drag left the value: nudging 43 up gives 45,
    /// not 48, so a few notches from an arbitrary position converge on round
    /// numbers instead of carrying the offset forever.
    function nudge(from: real, direction: int): int {
        const current = policy.clampPercent(from);
        const next = direction > 0
                   ? (Math.floor(current / policy.step) + 1) * policy.step
                   : (Math.ceil(current / policy.step) - 1) * policy.step;
        return policy.clampPercent(next);
    }

    // --- the bottom strip ----------------------------------------------------

    /// The power line: level, and what is happening to it. Empty on a machine
    /// with no battery, where the strip is a media card and a settings gear.
    ///
    /// Takes the words Services/Hardware/PowerPolicy.qml already decided rather
    /// than the numbers behind them — two definitions of "3h 20m" would be
    /// visible as a disagreement between the bar and this panel.
    function batteryLine(battery: var): string {
        const facts = battery ?? ({});
        if (facts.hasBattery !== true)
            return "";

        const level = facts.label || "";
        const time = facts.timeRemaining || "";

        // Nothing more is going to happen to it, and "0m to full" on a machine
        // that has been plugged in overnight is a readout that looks broken.
        if (facts.state === "full")
            return "Fully charged";

        if (facts.state === "charging")
            return time ? "Charging · " + level + " · " + time + " to full"
                        : "Charging · " + level;

        return time ? level + " · " + time + " left" : level;
    }

    // --- what the log says ---------------------------------------------------
    //
    // One line per act worth asserting on, which is what makes the grid
    // drivable from tools/drawer-harness.sh. #81 was a lifecycle with
    // no log line, and one bug then had two candidate causes for a week.

    /// What the shell *asked for*, logged before the call — the facade next
    /// logs what happened. Two lines and not one, because they answer different
    /// questions: this one says the tile is wired to something, and the
    /// facade's says the hardware agreed. A press that produces only the first
    /// is a service that swallowed it; only the second is impossible.
    function toggled(id: string, on: bool): string {
        return id + (on ? " on" : " off");
    }

    /// For the controls that are not a boolean: the power profile cycles
    /// through whatever the daemon offers, and the wallpaper tile opens a door.
    /// Neither has an "on" to name, and both still need the line.
    function pressed(id: string): string {
        return id + " pressed";
    }

    /// A toggle that could not run, and why — the case a bare absence of a log
    /// line would leave indistinguishable from a button that was never pressed.
    function refused(id: string, reason: string): string {
        return id + " unchanged — " + reason;
    }

    function moved(id: string, percentValue: int): string {
        return id + " " + policy.clampPercent(percentValue) + "%";
    }
}
