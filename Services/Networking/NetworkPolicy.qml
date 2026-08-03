// Everything the network indicator decides, as pure functions (#36).
//
// The devices arrive as plain data — `{ kind, connected, name, strength }` —
// which is what keeps this file free of NetworkManager and therefore reachable
// from tests/. Services/Networking/Networking.qml is the half that knows what a
// `NetworkDevice` is, and it hands over rows of that shape.
import QtQuick

QtObject {
    id: policy

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

    /// How much of each new sample the reading takes — the rest is what it
    /// already had.
    ///
    /// The deadband above answers a signal that *wanders* across a threshold.
    /// It does nothing about one that jumps clean over it, and this radio does:
    /// measured on a real session (#137, tools/idle-budget.sh), it reported 63,
    /// then 84, then 63 again inside two seconds, sitting still on a desk. Eight
    /// points of margin either side of 75 is no margin at all against a
    /// 21-point swing — the glyph flipped both ways and the bar repainted four
    /// times for a signal that never actually changed.
    ///
    /// So the bars are read off an average rather than off the last sample, and
    /// the deadband holds that. A quarter is the weight the measured sequence
    /// needed: it keeps the mean of a swinging signal well inside the deadband,
    /// while a signal that really moved arrives within four samples — a walk
    /// across the flat, not a fade.
    readonly property real barSmoothing: 0.25

    /// The smoothed strength, given the one carried so far.
    ///
    /// Zero means *no reading*: nothing connected, no wifi, or a wire — all
    /// three have no strength, and the next network must not inherit the last
    /// one's bars. It is also what a first reading is taken against, and that
    /// one is taken whole: a bar that faded in from nothing over ten seconds at
    /// startup would look broken rather than careful.
    ///
    /// Carried by the caller for the same reason `current` is: this answer
    /// depends on its own last answer, and a policy that kept the state would
    /// be a policy the tests could not wind forward.
    function track(previous: real, wifiEnabled: bool, device: var): real {
        if (!wifiEnabled || !device || device.kind !== "wifi" || !device.connected)
            return 0;
        const sample = policy.strength(device.strength);
        if (!(previous > 0))
            return sample;
        return previous + policy.barSmoothing * (sample - previous);
    }

    /// The glyph. `wifiEnabled` is the radio's own switch, read off the
    /// NetworkManager backend rather than off the device, so airplane mode
    /// shows as itself instead of as "no signal" — it is the one network state
    /// the user chose on purpose.
    ///
    /// `current` is the glyph on screen now, and it is what makes the
    /// hysteresis possible: this answer depends on its own last answer, so the
    /// caller carries it rather than the function keeping state. Pass "" (or
    /// nothing) for a fresh reading with no memory.
    /// `reading` is `track`'s answer — the smoothed strength. Zero, or nothing
    /// at all, falls back to the sample on the device: a caller asking a
    /// one-off question gets the plain reading rather than no bars.
    function icon(wifiEnabled: bool, device: var, current: string, reading: real): string {
        if (device && device.kind === "wired" && device.connected)
            return "ethernet-port";
        if (!wifiEnabled)
            return "wifi-off";
        if (!device || !device.connected)
            return "wifi-zero";
        const strength = reading > 0 ? Math.round(reading)
                                     : policy.strength(device.strength);
        return policy.bars(strength, current);
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

        // The boundary to clear is the one at the edge of the bucket being
        // *left*: the threshold above it when rising, the one below it when
        // falling. Taken from `was` and never from `now`, because a signal that
        // collapses several buckets at once still only has to get out of the
        // one it is in — reading it off `now` instead asks a 20% signal to fall
        // below 17 before full bars will admit anything changed.
        const boundary = now > was ? policy.barThresholds[was]
                                   : policy.barThresholds[was - 1];
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
