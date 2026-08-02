pragma Singleton

// The bluetooth facade (#36, #12 §3): the only place in the shell that knows
// what a BlueZ adapter is.
//
//     Bluetooth.present         // does this machine have a radio at all
//     Bluetooth.enabled         // is it on
//     Bluetooth.connectedCount  // how many devices are on the other end
//     Bluetooth.icon
//     Bluetooth.deviceRows      // the drill-in's list (#45)
//     Bluetooth.beginDiscovery()
//     Bluetooth.pressDevice(address)
//
// Native (#4 §2.8): `Quickshell.Bluetooth` is a real BlueZ client, so nothing
// here shells out to `bluetoothctl` and nothing polls.
//
// **The upstream module is imported under an alias**, for the reason spelled
// out in Services/Networking/Networking.qml: it exports a singleton called
// `Bluetooth` too. `Bz.` here always means upstream's; the unqualified name
// means this facade everywhere else in the shell.
//
// Nothing here starts a scan on its own — a discovering adapter is a radio kept
// awake, and the idle budget (#22 §5) is why every property below is a pushed
// DBus signal. The drill-in (#45) holds one for its own lifetime through
// `beginDiscovery`/`endDiscovery`, which is the whole of when this shell scans.
//
// The bar's half of this facade answers "is the radio on, and is anything
// connected to it". The drill-in's half is the list under it, with pairing,
// per-device battery and the four verbs a row can be pressed for.
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
    readonly property string label: root.policy.label(root.enabled, root.connectedCount)

    /// The radio switch (#44) — the caller #36 left this note waiting for.
    ///
    /// A function and not a writable `enabled`, the same shape the network
    /// facade uses: assigning to a property that carries a binding destroys the
    /// binding, and this one is what carries BlueZ's answer back — including
    /// when it refuses.
    function setEnabled(value: bool): void {
        if (!root.present) {
            Logger.warn("bluetooth", "no adapter — unchanged");
            return;
        }
        root.adapter.enabled = value;
    }

    function toggle(): void {
        root.setEnabled(!root.enabled);
    }

    // --- the drill-in's list (#45) -------------------------------------------
    //
    // Native throughout: `BluetoothDevice` carries `pair()`, `connect()`,
    // `disconnect()`, `cancelPair()` and `forget()`, so none of this shells out
    // to `bluetoothctl`. What it does need is a scan, which the bar deliberately
    // never started — see the header, and `beginDiscovery` below for who holds
    // it now.

    /// Every device BlueZ knows about, as plain rows — the same shape
    /// `devices` above uses for the count, with the per-device state the panel
    /// needs added and the live handle attached.
    ///
    /// Rebuilt whenever anything on any device moves, which includes a battery
    /// level ticking down, and then thrown away unless the signature changed.
    /// `deviceRows` says why.
    readonly property var deviceCandidates: {
        const rows = [];
        const model = Bz.Bluetooth.devices ? Bz.Bluetooth.devices.values : [];
        for (const device of model) {
            rows.push({
                address: device.address,
                name: device.name,
                connected: device.connected === true,
                paired: device.paired === true,
                bonded: device.bonded === true,
                pairing: device.pairing === true,
                trusted: device.trusted === true,
                battery: device.battery,
                batteryAvailable: device.batteryAvailable === true,
                // BlueZ's own icon name for the device class — the policy maps
                // it to a glyph, because "audio-headset" is a freedesktop name
                // and not a Lucide one.
                kind: device.icon,
                live: device
            });
        }
        return rows;
    }

    /// What the panel's `Repeater` is given. A property written by a handler
    /// and not a binding, for the reason Services/Networking/Networking.qml
    /// spells out at length about the wifi list: a `Repeater` over a JS array
    /// rebuilds every delegate when the array identity changes (#75), and this
    /// array is rebuilt every time a headset reports one percent less battery.
    /// The live handle on each row is what carries those numbers to the screen
    /// without a rebuild.
    property var deviceRows: []
    property string deviceSignature: ""

    onDeviceCandidatesChanged: {
        const rows = root.policy.deviceRows(root.deviceCandidates);
        const signature = root.policy.deviceSignature(rows);
        if (signature === root.deviceSignature)
            return;
        root.deviceSignature = signature;
        root.deviceRows = rows;
    }

    /// Discovery, held for as long as a panel is looking — counted for the same
    /// reason the wifi scanner is, and off by default for the same one: a
    /// discovering adapter is a radio kept awake against an idle budget of one
    /// wakeup a minute (#22 §5).
    property int discoveryHolders: 0

    function beginDiscovery(): void {
        if (!root.present) {
            Logger.warn("bluetooth", "no adapter — cannot scan");
            return;
        }
        if (!root.enabled) {
            // Not an error: the panel is the place you go to turn the radio on,
            // and it will start discovering when you do (`onEnabledChanged`).
            Logger.log("bluetooth", "radio off — scan deferred");
        }
        root.discoveryHolders++;
        if (root.discoveryHolders === 1)
            root.applyDiscovery();
    }

    function endDiscovery(): void {
        if (root.discoveryHolders < 1)
            return;
        root.discoveryHolders--;
        if (root.discoveryHolders === 0)
            root.applyDiscovery();
    }

    /// The one place `discovering` is written, so the two things that decide it
    /// — somebody looking, and a radio that is on — cannot disagree.
    function applyDiscovery(): void {
        if (!root.present)
            return;
        const wanted = root.discoveryHolders > 0 && root.enabled;
        if (root.adapter.discovering === wanted)
            return;
        root.adapter.discovering = wanted;
        Logger.log("bluetooth", root.policy.discovery(wanted));
    }

    /// The row for an address, or null — the lookup the IPC door needs, since a
    /// keybind has a name and not an object.
    function rowFor(address: string): var {
        for (const row of root.deviceRows)
            if (row.address === address)
                return row;
        return null;
    }

    // --- what a press on a row does ------------------------------------------
    //
    // One function per verb, each with the refusal spelled out: BlueZ is the
    // subsystem most likely to say no, and a press that does nothing and says
    // nothing is #81 exactly.

    /// Pair and connect, which is one gesture: nobody who presses an unpaired
    /// headset wants to be paired to it and then have to press it again. BlueZ
    /// connects on its own after a successful pair for most device classes; the
    /// ones it does not are covered by pressing the row a second time, which by
    /// then reads "connect".
    function pairDevice(address: string): void {
        const row = root.rowFor(address);
        if (row === null || row.live === null) {
            Logger.warn("bluetooth", root.policy.deviceRefused(address, "no such device"));
            return;
        }
        Logger.log("bluetooth", root.policy.asked("pair", row.name));
        row.live.pair();
    }

    function cancelPairing(address: string): void {
        const row = root.rowFor(address);
        if (row === null || row.live === null) {
            Logger.warn("bluetooth", root.policy.deviceRefused(address, "no such device"));
            return;
        }
        Logger.log("bluetooth", root.policy.asked("cancel pairing with", row.name));
        row.live.cancelPair();
    }

    function connectDevice(address: string): void {
        const row = root.rowFor(address);
        if (row === null || row.live === null) {
            Logger.warn("bluetooth", root.policy.deviceRefused(address, "no such device"));
            return;
        }
        if (!row.paired) {
            // Connecting an unpaired device is a call BlueZ rejects several
            // seconds later. Refused up front, naming what to do instead.
            Logger.warn("bluetooth", root.policy.deviceRefused(row.name, "not paired yet"));
            return;
        }
        Logger.log("bluetooth", root.policy.asked("connect", row.name));
        row.live.connect();
    }

    function disconnectDevice(address: string): void {
        const row = root.rowFor(address);
        if (row === null || row.live === null) {
            Logger.warn("bluetooth", root.policy.deviceRefused(address, "no such device"));
            return;
        }
        Logger.log("bluetooth", root.policy.asked("disconnect", row.name));
        row.live.disconnect();
    }

    /// Forget a paired device — the one act here that destroys something, so it
    /// is its own verb rather than a flag on `disconnect`.
    function forgetDevice(address: string): void {
        const row = root.rowFor(address);
        if (row === null || row.live === null) {
            Logger.warn("bluetooth", root.policy.deviceRefused(address, "no such device"));
            return;
        }
        if (!row.paired) {
            Logger.warn("bluetooth",
                        root.policy.deviceRefused(row.name, "nothing paired to forget"));
            return;
        }
        Logger.log("bluetooth", root.policy.asked("forget", row.name));
        row.live.forget();
    }

    /// One press, routed by what the row is now — the same table the panel uses,
    /// so `qs ipc call controlcenter device <address>` does what a finger does.
    function pressDevice(address: string): void {
        const row = root.rowFor(address);
        if (row === null) {
            Logger.warn("bluetooth", root.policy.deviceRefused(address, "no such device"));
            return;
        }
        switch (root.policy.deviceAction(row)) {
        case "cancel":     root.cancelPairing(address); return;
        case "disconnect": root.disconnectDevice(address); return;
        case "connect":    root.connectDevice(address); return;
        case "pair":       root.pairDevice(address); return;
        }
    }

    // A line per state change worth asserting on (#81).
    //
    // The discovery re-apply is what makes "radio off — scan deferred" true
    // rather than a promise: a panel opened on a dark adapter holds the count,
    // and turning the radio on from the tile above it starts the scan it was
    // waiting for.
    onEnabledChanged: {
        Logger.log("bluetooth", "radio " + (root.enabled ? "on" : "off"));
        root.applyDiscovery();
    }
    onConnectedCountChanged: Logger.log("bluetooth", root.label)

    Component.onCompleted: Logger.log("bluetooth", root.present
        ? "bluez facade ready — adapter " + root.adapter.name
        : "no bluetooth adapter — facade inert")
}
