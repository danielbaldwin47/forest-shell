// Everything the network indicator decides, as pure functions (#36).
//
// The devices arrive as plain data — `{ kind, connected, name, strength }` —
// which is what keeps this file free of NetworkManager and therefore reachable
// from tests/. Services/Networking/Networking.qml is the half that knows what a
// `NetworkDevice` is, and it hands over rows of that shape.
import QtQuick

QtObject {
    id: policy

    /// The two device kinds the bar can speak for. VPN and the rest of
    /// NetworkManager's zoo are the control centre's business (#44); a bar
    /// glyph answers one question, which is whether this machine is on a
    /// network and how well.
    readonly property var kinds: ["wired", "wifi"]

    /// Signal strength as a whole percent, whichever scale it arrived in.
    ///
    /// NetworkManager reports 0-100 and Quickshell types `signalStrength` as a
    /// double, so a 0-1 fraction is the plausible other reading and both
    /// normalize here rather than at every threshold below. 1 is read as full
    /// rather than as one percent — a one-percent link is not a state anything
    /// stays in, and reading full as 1% would draw a connected machine as
    /// having no signal.
    function strength(value: real): int {
        if (!isFinite(value) || value <= 0)
            return 0;
        const percent = value <= 1 ? value * 100 : value;
        return Math.round(Math.min(100, percent));
    }

    /// The device the cluster speaks for, or null on a machine with neither.
    ///
    /// A connected wire wins: it is the one carrying the traffic, and a wifi
    /// glyph over a docked laptop is a lie. With nothing connected the wifi
    /// radio still speaks, because "wifi, not connected" is a state the user
    /// can act on and an empty slot reads as a bar that lost a module.
    function primary(devices: var): var {
        const rows = devices || [];
        return policy.pick(rows, d => d.kind === "wired" && d.connected)
            ?? policy.pick(rows, d => d.kind === "wifi" && d.connected)
            ?? policy.pick(rows, d => d.kind === "wifi")
            ?? policy.pick(rows, d => d.kind === "wired")
            ?? null;
    }

    function pick(devices: var, matches: var): var {
        for (const device of devices)
            if (device && matches(device))
                return device;
        return null;
    }

    /// The four wifi glyphs, weakest first, and the strength at which each
    /// gives way to the next.
    readonly property var barGlyphs: ["wifi-zero", "wifi-low", "wifi-high", "wifi"]
    readonly property var barThresholds: [25, 50, 75]

    /// How far past a threshold the signal must go to change the glyph, when
    /// that means *leaving* the glyph it is on.
    ///
    /// Measured, not guessed: without it, an access point sitting near a
    /// boundary — 0.72 to 0.78 on this laptop, which is an ordinary desk —
    /// flips the glyph every few seconds forever, and every flip is a bar
    /// repaint. A 195 s idle window measured 17 repaints, five of them this
    /// (tools/idle-budget.sh), against a budget of one a minute (#22 §5). A
    /// deadband is what turns a live measurement into a stable reading.
    readonly property int barHysteresis: 8

    /// The glyph. `wifiEnabled` is the radio's own switch, read off the
    /// NetworkManager backend rather than off the device, so airplane mode
    /// shows as itself instead of as "no signal" — it is the one network state
    /// the user chose on purpose.
    ///
    /// `current` is the glyph on screen now, and it is what makes the
    /// hysteresis possible: this answer depends on its own last answer, so the
    /// caller carries it rather than the function keeping state. Pass "" (or
    /// nothing) for a fresh reading with no memory.
    function icon(wifiEnabled: bool, device: var, current: string): string {
        if (device && device.kind === "wired" && device.connected)
            return "ethernet-port";
        if (!wifiEnabled)
            return "wifi-off";
        if (!device || !device.connected)
            return "wifi-zero";
        return policy.bars(policy.strength(device.strength), current);
    }

    /// Which bars a strength reads as, given which it is already showing.
    ///
    /// A move *into* a neighbouring bucket has to clear the boundary by the
    /// deadband; a glyph that is not one of these — "wifi-off", the wired one,
    /// or nothing yet — has no bucket to stay in, so the reading is taken
    /// fresh.
    function bars(strength: int, current: string): string {
        const now = policy.barBucket(strength);
        const was = policy.barGlyphs.indexOf(current);
        if (was < 0 || was === now)
            return policy.barGlyphs[now];

        // Rising: the threshold being left behind is the one above the old
        // bucket. Falling: it is the one above the new bucket. Both are
        // `barThresholds[min(was, now)]`, widened away from where we are.
        const boundary = policy.barThresholds[Math.min(was, now)];
        const moved = now > was ? strength >= boundary + policy.barHysteresis
                                : strength <= boundary - policy.barHysteresis;
        return policy.barGlyphs[moved ? now : was];
    }

    function barBucket(strength: int): int {
        let bucket = 0;
        for (const threshold of policy.barThresholds)
            if (strength >= threshold)
                bucket++;
        return bucket;
    }

    /// How loudly to draw it: "off", "idle" or "connected". A word rather than
    /// a colour, because this file has no Theme to ask — and because the three
    /// indicators in the cluster then share one rule for what each state looks
    /// like instead of three near-identical ones.
    function emphasis(wifiEnabled: bool, device: var): string {
        if (device && device.connected)
            return "connected";
        return wifiEnabled ? "idle" : "off";
    }

    /// The words for a tooltip or the control centre's row (#44). Nothing on
    /// the bar shows these yet — the cluster is glyphs only (#9) — but the
    /// state they name is decided here either way, and a second place deciding
    /// it later is how a bar and a panel come to disagree.
    function label(wifiEnabled: bool, device: var): string {
        if (device && device.connected)
            return device.name || "Connected";
        if (device)
            return "Not connected";
        return wifiEnabled ? "No network" : "Wi-Fi off";
    }
}
