// Everything the bluetooth indicator decides, as pure functions (#36) — and,
// since #45, everything the drill-in's device list decides too.
//
// The bar's half is three states and a count: "is the radio on, and is anything
// on the other end of it". The drill-in's half is the list under it — which
// devices are worth a row, in what order, what one press means, and the words
// on each.
//
// Both are here rather than in two files because they are one vocabulary: the
// count the bar draws and the rows the panel draws have to agree about what
// "connected" means, and two files deciding that is how they come to disagree.
// The devices arrive as plain rows either way, which is what keeps this file
// free of BlueZ and reachable from tests/.
import QtQuick

QtObject {
    id: policy

    /// Whether this machine has a bluetooth adapter at all.
    ///
    /// A desktop with no radio shows nothing rather than a permanently
    /// crossed-out glyph: an indicator nobody can act on is furniture.
    function present(adapter: var): bool {
        return adapter !== null && adapter !== undefined;
    }

    function connectedCount(devices: var): int {
        let count = 0;
        for (const device of devices || [])
            if (device && device.connected)
                count++;
        return count;
    }

    /// The glyph. A radio that is off outranks everything, including a stale
    /// count — BlueZ keeps reporting devices it remembers after the adapter
    /// goes down, and drawing those as connected would be a headset the user
    /// cannot hear.
    ///
    /// `discovering` is never something the shell started: nothing here scans,
    /// because a scan is a radio kept awake and the idle budget (#22 §5) is the
    /// whole reason this cluster is event-driven. It is here because blueman or
    /// bluetoothctl may have, and an adapter that is doing something should
    /// look like it.
    function icon(enabled: bool, connected: int, discovering: bool): string {
        if (!enabled)
            return "bluetooth-off";
        if (connected > 0)
            return "bluetooth-connected";
        return discovering ? "bluetooth-searching" : "bluetooth";
    }

    function label(enabled: bool, connected: int): string {
        if (!enabled)
            return "Bluetooth off";
        if (connected < 1)
            return "No devices";
        return connected === 1 ? "1 device" : connected + " devices";
    }

    // --- the drill-in's list (#45) -------------------------------------------
    //
    // The same argument Services/Networking/WifiPolicy.qml makes at length: the
    // order is made only of fields that change when something *happens*, never
    // of a live measurement. A battery percentage that drifts one point must not
    // move a row, because the row it moves is the one under the pointer.

    /// Every device worth a row, in the order it is drawn: connected, then the
    /// pairing in flight, then paired, then everything the scan turned up —
    /// alphabetical within each band.
    ///
    /// Nothing is filtered out. A nameless device is a real device with a real
    /// address, and BlueZ hands those over constantly during a scan; hiding
    /// them would make the list shorter than what is on the air, which is the
    /// opposite of what a discovery view is for.
    function deviceRows(devices: var): var {
        const out = [];
        for (const device of devices ?? []) {
            const address = String(device?.address ?? "").trim();
            if (address === "")
                continue;       // BlueZ has not filled the object in yet
            out.push(policy.deviceRow(device, address));
        }
        return out.sort(policy.compareDevices);
    }

    function deviceRow(device: var, address: string): var {
        const name = String(device?.name ?? "").trim();
        return {
            address: address,
            // The address is the fallback name and not a placeholder: it is
            // what the user will match against the label on the back of the
            // thing they are holding.
            name: name === "" ? address : name,
            connected: device?.connected === true,
            paired: device?.paired === true || device?.bonded === true,
            pairing: device?.pairing === true,
            trusted: device?.trusted === true,
            battery: Number(device?.battery ?? 0),
            batteryAvailable: device?.batteryAvailable === true,
            kind: String(device?.kind ?? ""),
            // The upstream `BluetoothDevice`, untouched here: it is what the
            // facade calls pair()/connect()/disconnect() on.
            live: device?.live ?? null
        };
    }

    function compareDevices(a: var, b: var): int {
        const rank = policy.deviceBand(a) - policy.deviceBand(b);
        if (rank !== 0)
            return rank;
        const left = a.name.toLowerCase();
        const right = b.name.toLowerCase();
        return left < right ? -1 : left > right ? 1 : 0;
    }

    function deviceBand(row: var): int {
        if (row.connected === true)
            return 0;
        if (row.pairing === true)
            return 1;
        return row.paired === true ? 2 : 3;
    }

    /// What the facade compares before it republishes the list (#75).
    /// Battery is deliberately absent — it moves on its own, and a rebuilt
    /// delegate is a row that loses its hover and restarts its animation.
    function deviceSignature(rows: var): string {
        return (rows ?? []).map(row => row.address + " " + row.name
                                + (row.connected ? "c" : "-")
                                + (row.paired ? "p" : "-")
                                + (row.pairing ? "…" : "-")).join("");
    }

    /// What one press asks for. Pairing and connecting are one gesture on
    /// purpose: nobody who presses an unpaired headset wants to be paired to it
    /// and then press it again — the facade pairs and connects, and this is the
    /// word for the first half of that.
    function deviceAction(row: var): string {
        const facts = row ?? ({});
        if (facts.pairing === true)
            return "cancel";
        if (facts.connected === true)
            return "disconnect";
        return facts.paired === true ? "connect" : "pair";
    }

    /// The words under the name. Battery only when BlueZ actually reports one —
    /// a headset that does not publish its level must not read as flat.
    function deviceDetail(row: var): string {
        const facts = row ?? ({});
        if (facts.pairing === true)
            return "Pairing…";
        if (facts.connected === true)
            return facts.batteryAvailable === true
                 ? "Connected · " + policy.batteryLabel(facts.battery)
                 : "Connected";
        return facts.paired === true ? "Paired" : "Not paired";
    }

    function batteryLabel(value: var): string {
        const percent = Math.round(Number(value));
        return isFinite(percent) ? Math.max(0, Math.min(100, percent)) + "%" : "";
    }

    /// The glyph for a row, from the BlueZ device class the facade passes
    /// through. A device kind BlueZ does not name gets the bluetooth glyph
    /// rather than nothing: a row with a hole where an icon goes reads as a
    /// broken row rather than as an unrecognised device.
    function deviceIcon(kind: var): string {
        switch (String(kind ?? "")) {
        case "audio-headset":
        case "audio-headphones":  return "headphones";
        case "audio-card":
        case "audio-speaker":     return "speaker";
        case "input-mouse":       return "mouse";
        case "input-keyboard":    return "keyboard";
        case "input-gaming":      return "gamepad-2";
        case "input-tablet":      return "tablet";
        case "phone":             return "smartphone";
        case "computer":          return "laptop";
        case "video-display":     return "monitor";
        case "printer":           return "printer";
        case "camera-photo":
        case "camera-video":      return "camera";
        case "watch":             return "watch";
        }
        return "bluetooth";
    }

    // --- what the log says ---------------------------------------------------

    function discovery(on: bool): string {
        return on ? "scanning for devices" : "scan stopped";
    }

    function asked(action: string, name: string): string {
        return action + " " + name;
    }

    function deviceRefused(name: string, reason: string): string {
        return "device " + name + " unchanged — " + reason;
    }

    /// What changed about one device between two readings of BlueZ, as the
    /// lines the log should carry — none, when nothing did (#141).
    ///
    /// `asked` above logs the *attempt*: "pair Zen Zone" is written the moment
    /// the button is pressed and says nothing about what BlueZ then did. The
    /// pass that filed this ticket had a device that never paired, and the log
    /// held the same single line it would have held on success.
    ///
    /// A list rather than a string because one reading can carry two: a device
    /// that pairs and connects in the same round trip did both, and a log that
    /// picked one of them would be inventing an order BlueZ did not give.
    ///
    /// Pure, and given both readings, because the *transition* is the decision
    /// here — "paired" is not news, "became paired" is.
    function settled(name: string, was: var, now: var): var {
        const lines = [];
        if (was === null || was === undefined || now === null || now === undefined)
            return lines;

        // A pairing that started and stopped without the device becoming
        // paired is the failure this exists for. BlueZ reports it as the flag
        // going back down — there is no error on the property — so the
        // transition is the only evidence there is.
        if (was.pairing === true && now.pairing !== true && now.paired !== true)
            lines.push(name + " pairing failed");

        if (was.paired !== true && now.paired === true)
            lines.push(name + " paired");
        else if (was.paired === true && now.paired !== true)
            lines.push(name + " no longer paired");

        if (was.connected !== true && now.connected === true)
            lines.push(name + " connected");
        else if (was.connected === true && now.connected !== true)
            lines.push(name + " disconnected");

        return lines;
    }
}
