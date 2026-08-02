// Everything the bluetooth indicator decides, as pure functions (#36).
//
// Three states and a count. Pairing, trust, per-device battery and the device
// list itself belong to the control centre (#44) — the bar answers "is the
// radio on, and is anything on the other end of it".
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
}
