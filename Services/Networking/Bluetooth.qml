pragma Singleton

// The bluetooth facade (#36, #12 §3): the only place in the shell that knows
// what a BlueZ adapter is.
//
//     Bluetooth.present         // does this machine have a radio at all
//     Bluetooth.enabled         // is it on — writable via setEnabled()
//     Bluetooth.connectedCount  // how many devices are on the other end
//     Bluetooth.icon
//
// Native (#4 §2.8): `Quickshell.Bluetooth` is a real BlueZ client, so nothing
// here shells out to `bluetoothctl` and nothing polls.
//
// **The upstream module is imported under an alias**, for the reason spelled
// out in Services/Networking/Networking.qml: it exports a singleton called
// `Bluetooth` too. `Bz.` here always means upstream's; the unqualified name
// means this facade everywhere else in the shell.
//
// Nothing here starts a scan — a discovering adapter is a radio kept awake, and
// the idle budget (#22 §5) is why every property below is a pushed DBus signal.
// Pairing, trust and per-device battery are the control centre's (#44); the bar
// answers "is the radio on, and is anything connected to it".
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Bluetooth as Bz
import qs.Core

Singleton {
    id: root

    // Held as its own property rather than declared inline — see Core/Config.qml.
    readonly property BluetoothPolicy policy: BluetoothPolicy {}

    readonly property var adapter: Bz.Bluetooth.defaultAdapter

    /// Whether there is a radio. A machine without one shows no glyph at all,
    /// rather than a permanently crossed-out one nobody can act on.
    readonly property bool present: root.policy.present(root.adapter)

    readonly property bool enabled: root.present && root.adapter.enabled
    readonly property bool discovering: root.present && root.adapter.discovering

    /// Devices as plain data, so the count is decided next door rather than
    /// here. BlueZ keeps reporting devices it remembers after the adapter goes
    /// down, which is why the policy makes "off" outrank the count.
    readonly property var devices: {
        const rows = [];
        const model = Bz.Bluetooth.devices ? Bz.Bluetooth.devices.values : [];
        for (const device of model)
            rows.push({ name: device.name, connected: device.connected === true });
        return rows;
    }

    readonly property int connectedCount: root.enabled ? root.policy.connectedCount(root.devices) : 0

    readonly property string icon: root.policy.icon(root.enabled, root.connectedCount, root.discovering)
    readonly property string emphasis: root.policy.emphasis(root.enabled, root.connectedCount)
    readonly property string label: root.policy.label(root.enabled, root.connectedCount)

    /// Turn the radio on or off. A function rather than a writable property, so
    /// the read stays a live binding — see Networking.qml for what assigning to
    /// a bound property costs.
    function setEnabled(enabled: bool) {
        if (!root.present) {
            Logger.warn("bluetooth", "no adapter — ignoring enable " + enabled);
            return;
        }
        root.adapter.enabled = enabled;
    }

    // A line per state change worth asserting on (#81).
    onEnabledChanged: Logger.log("bluetooth", "radio " + (root.enabled ? "on" : "off"))
    onConnectedCountChanged: Logger.log("bluetooth", root.connectedCount + " device(s) connected")

    Component.onCompleted: Logger.log("bluetooth", root.present
        ? "bluez facade ready — adapter " + root.adapter.name
        : "no bluetooth adapter — facade inert")
}
