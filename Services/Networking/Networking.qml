pragma Singleton

// The network facade (#36, #12 §3): the only place in the shell that knows what
// a NetworkManager device is.
//
//     Networking.icon           // the glyph the bar draws
//     Networking.connected      // is this machine on a network at all
//     Networking.label          // "PUMPKINCURRY", "Not connected", "Wi-Fi off"
//     Networking.wifiEnabled    // the radio switch — writable
//     Networking.devices        // [{ kind, connected, name, strength }]
//
// Native, and that is newer than most shells assume: `Quickshell.Networking` is
// a real NetworkManager client (#4 §2.7), so nothing here shells out to `nmcli`
// and nothing polls. Everything below is a binding on a DBus-pushed property.
//
// **The upstream module is imported under an alias**, and it has to be: it
// exports a singleton called `Networking` too, and a file that imported both
// unqualified would get whichever the resolver preferred — the same silent
// class of failure as a singleton named `State` being shadowed by QtQuick's
// (Core/Config.qml). `Nm.` in this file always means upstream's; the
// unqualified name always means this facade, everywhere else in the shell.
//
// Two behaviours are deliberately absent, both because they cost wakeups the
// idle budget (#22 §5) does not have:
//
//   - **no scan.** `WifiDevice.scannerEnabled` stays off. The network the
//     machine is *on* is reported without one — measured: with the scanner off
//     the connected AP is still listed, with its live signal strength. A
//     picker that needs the full list turns the scanner on while it is open,
//     which is the control centre's job (#44), not the bar's.
//   - **no connectivity check.** `Networking.connectivityCheckEnabled` is left
//     as NetworkManager set it (off, on this machine), because turning it on
//     buys a periodic HTTP round trip to detect captive portals. So
//     `connectivity` is not read here at all — a portal reads as connected,
//     which is what every other bar on this machine already says.
//
// Every decision — which device speaks, which glyph, what the words are — is in
// Services/Networking/NetworkPolicy.qml, which imports nothing but QtQuick so
// tests/ can reach it. This file is the wiring.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Networking as Nm
import qs.Core

Singleton {
    id: root

    // Held as its own property rather than declared inline — see Core/Config.qml.
    readonly property NetworkPolicy policy: NetworkPolicy {}

    /// Whether there is a NetworkManager to talk to. False on a machine running
    /// iwd or systemd-networkd alone, where every property below degrades to
    /// "no network" rather than erroring.
    readonly property bool available: Nm.Networking.backend !== Nm.NetworkBackendType.None

    /// The wifi radio's own switch — airplane mode.
    ///
    /// Read as a binding and written through a function, rather than shipped as
    /// a plain writable property: assigning to a property that carries a
    /// binding *destroys* the binding, so the one call that turned the radio
    /// off would also be the last time this facade heard about it changing.
    readonly property bool wifiEnabled: Nm.Networking.wifiEnabled

    function setWifiEnabled(enabled: bool) {
        if (!root.available) {
            Logger.warn("network", "no networkmanager — ignoring wifi " + enabled);
            return;
        }
        Nm.Networking.wifiEnabled = enabled;
    }

    /// Every device the bar could speak for, as plain data — which is what lets
    /// the policy next door decide between them without meeting NetworkManager.
    ///
    /// A wifi device's `name` and `strength` come from the network it is *on*,
    /// not from the interface: "wlan0" is not what anybody calls their network.
    readonly property var devices: {
        const rows = [];
        const model = Nm.Networking.devices ? Nm.Networking.devices.values : [];
        for (const device of model) {
            const kind = root.kindOf(device);
            if (!kind)
                continue;
            const network = root.activeNetwork(device);
            rows.push({
                kind: kind,
                connected: device.connected === true,
                name: network && network.name ? network.name : device.name,
                strength: network ? network.signalStrength : 0
            });
        }
        return rows;
    }

    function kindOf(device: var): string {
        if (device.type === Nm.DeviceType.Wifi)
            return "wifi";
        return device.type === Nm.DeviceType.Wired ? "wired" : "";
    }

    /// The network a device is currently on, or null.
    ///
    /// A wifi device lists the AP it is associated with whether or not the
    /// scanner is running; a wired device carries its connection directly.
    function activeNetwork(device: var): var {
        if (device.network !== undefined)
            return device.network;
        const networks = device.networks ? device.networks.values : [];
        for (const network of networks)
            if (network.connected)
                return network;
        return null;
    }

    // --- what surfaces read --------------------------------------------------

    readonly property var primary: root.policy.primary(root.devices)
    readonly property bool connected: root.primary !== null && root.primary.connected === true
    readonly property string emphasis: root.policy.emphasis(root.wifiEnabled, root.primary)
    readonly property string label: root.policy.label(root.wifiEnabled, root.primary)

    /// The glyph — and the one property here that is *not* a binding, because
    /// the policy's answer depends on its own previous answer: the bars have a
    /// deadband, and without one an access point sitting near a threshold flips
    /// the glyph every few seconds and repaints the bar every time (measured,
    /// tools/idle-budget.sh — five of a 195 s window's seventeen repaints).
    ///
    /// A binding cannot read the property it is assigned to, so the value is
    /// pushed instead, from the two things that can change it.
    property string icon: ""

    function refreshIcon() {
        root.icon = root.policy.icon(root.wifiEnabled, root.primary, root.icon);
    }

    onPrimaryChanged: root.refreshIcon()

    // A line per state change worth asserting on (#81). The glyph rather than
    // the signal strength: strength moves on its own every few seconds as the
    // radio re-measures, and a line per measurement is a log nobody can read —
    // the glyph only moves when the picture on the bar does.
    onIconChanged: Logger.log("network", "indicator " + root.icon + " — " + root.label)

    onWifiEnabledChanged: {
        root.refreshIcon();
        Logger.log("network", "wifi radio " + (root.wifiEnabled ? "on" : "off"));
    }

    Component.onCompleted: {
        // NetworkManager answers about a second after it is first touched, so
        // this is the reading before it has said anything — and the first
        // `onPrimaryChanged` is what replaces it.
        root.refreshIcon();
        Logger.log("network", root.available
            ? "networkmanager facade ready"
            : "no networkmanager — facade inert");
    }
}
