pragma Singleton

// The network facade (#36, #12 §3): the only place in the shell that knows what
// a NetworkManager device is.
//
//     Networking.icon           // the glyph the bar draws
//     Networking.connected      // is this machine on a network at all
//     Networking.label          // "PUMPKINCURRY", "Not connected", "Wi-Fi off"
//     Networking.wifiEnabled    // the radio switch, written through setWifiEnabled
//     Networking.devices        // [{ kind, connected, name, strength }]
//     Networking.wifiNetworks   // the drill-in's list (#45), one row per SSID
//     Networking.beginScan()    // held for as long as a panel is looking
//     Networking.join(ssid, psk)
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
//   - **no scan by default.** `WifiDevice.scannerEnabled` stays off. The
//     network the machine is *on* is reported without one — measured: with the
//     scanner off the connected AP is still listed, with its live signal
//     strength. A picker that needs the full list turns the scanner on while it
//     is open, and since #45 that is exactly what `beginScan`/`endScan` below
//     are: the Wi-Fi drill-in holds the scanner for its own lifetime and hands
//     it back on the way out.
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
    /// Read-only *here*, and written through `setWifiEnabled` below — #36 left
    /// the note and #44 is the caller it was waiting for. Still a binding
    /// rather than a writable property, for the reason that note gave:
    /// assigning to a property that carries a binding destroys the binding, so
    /// the one call that turned the radio off would also be the last time this
    /// facade heard about it changing.
    readonly property bool wifiEnabled: Nm.Networking.wifiEnabled

    /// Whether the radio can be switched at all. A laptop with its rfkill
    /// switch flipped — or a lid slider, on the machines that still have one —
    /// reports the hardware off, and NetworkManager will not bring it up for
    /// anybody. The tile stays visible and says so, rather than accepting a
    /// press that silently does nothing.
    readonly property bool wifiSwitchable: root.available && Nm.Networking.wifiHardwareEnabled

    /// The radio switch (#44). Writes upstream's property, which is the one
    /// place the value lives; the binding above is what carries the answer
    /// back, including when NetworkManager refuses.
    function setWifiEnabled(value: bool): void {
        if (!root.available) {
            Logger.warn("network", "no networkmanager — wifi unchanged");
            return;
        }
        if (!root.wifiSwitchable) {
            Logger.warn("network", "wifi is blocked in hardware — unchanged");
            return;
        }
        Nm.Networking.wifiEnabled = value;
    }

    function toggleWifi(): void {
        root.setWifiEnabled(!root.wifiEnabled);
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

    // --- the drill-in's list (#45) -------------------------------------------
    //
    // Native throughout: `WifiNetwork` carries `connect()`, `connectWithPsk()`,
    // `disconnect()` and `forget()`, so joining an access point is a method call
    // on a DBus proxy and not an `nmcli` subprocess. The VPN half of this facade
    // still shells out (Services/Networking/Vpn.qml) because NetworkManager's
    // *connection profiles* have no upstream surface — access points do.

    readonly property WifiPolicy wifi: WifiPolicy {}

    /// The radio, as a `WifiDevice`, or null. The first one: a machine with two
    /// wifi cards is rare enough that picking between them is a setting nobody
    /// has asked for, and the first is the one NetworkManager itself prefers.
    readonly property var wifiDevice: {
        const model = Nm.Networking.devices ? Nm.Networking.devices.values : [];
        for (const device of model)
            if (device.type === Nm.DeviceType.Wifi)
                return device;
        return null;
    }

    /// Whether the scanner is running. Off unless a panel is holding it — see
    /// the header, and Surfaces/Drawers/DrillInPolicy.qml for who holds it.
    readonly property bool scanning: root.wifiDevice !== null
                                     && root.wifiDevice.scannerEnabled === true

    /// Start scanning, for as long as somebody is looking.
    ///
    /// Counted rather than a flag: the panel holds it, and so could a second
    /// caller, and the first `endScan` must not take the scanner away from the
    /// second holder. One integer is cheaper than working out afterwards why the
    /// list stopped updating.
    property int scanHolders: 0

    function beginScan(): void {
        if (root.wifiDevice === null) {
            Logger.warn("network", "no wifi device — cannot scan");
            return;
        }
        root.scanHolders++;
        if (root.scanHolders === 1) {
            root.wifiDevice.scannerEnabled = true;
            // Forgotten at the start of every scan, so the first list this scan
            // produces is logged even when it holds the same number the last
            // scan ended on. Otherwise the count is deduplicated across scans
            // and a fresh scan says nothing at all (#141).
            root.lastVisible = -1;
            Logger.log("network", root.wifi.scanning(true));
        }
    }

    function endScan(): void {
        if (root.scanHolders < 1)
            return;
        root.scanHolders--;
        if (root.scanHolders === 0 && root.wifiDevice !== null) {
            root.wifiDevice.scannerEnabled = false;
            // A scan during which nothing at all changed never reached the
            // handler below, and "no networks visible" is exactly the answer
            // #141 needed and the one silence used to stand for.
            if (root.lastVisible < 0)
                Logger.log("network", root.wifi.visible(root.wifiCandidates.length));
            Logger.log("network", root.wifi.scanning(false));
        }
    }

    /// Every access point the radio can see, as plain rows the policy shapes.
    ///
    /// Rebuilt whenever anything on any network moves, which with signal
    /// strength in it is every few seconds forever — and then *thrown away*
    /// unless the signature changed. See `wifiNetworks` for why.
    readonly property var wifiCandidates: {
        const rows = [];
        const networks = root.wifiDevice && root.wifiDevice.networks
                       ? root.wifiDevice.networks.values : [];
        for (const network of networks) {
            rows.push({
                ssid: network.name,
                security: root.securityKind(network.security),
                known: network.known === true,
                connected: network.connected === true,
                connecting: network.state === Nm.ConnectionState.Connecting,
                strength: network.signalStrength,
                live: network
            });
        }
        return rows;
    }

    /// What the panel's `Repeater` is given — and the reason it is a property
    /// written by a handler rather than a binding.
    ///
    /// A `Repeater` over a JS array rebuilds every delegate when the array
    /// identity changes, and a rebuilt delegate loses its hover, restarts its
    /// animations and drops anything the user was in the middle of (#75, which
    /// was an indicator that never animated for exactly this reason). Bound
    /// straight to `wifiCandidates` this list would rebuild every few seconds on
    /// a machine sitting still, because signal strength drifts on its own.
    ///
    /// So the rows are republished only when
    /// Services/Networking/WifiPolicy.qml's signature moves — which is made of
    /// the fields that change when something *happens*. Strength still reaches
    /// the screen: each row carries the live `WifiNetwork`, and the delegate
    /// binds its glyph to `row.live.signalStrength` directly. Nothing has to be
    /// rebuilt for a number to change.
    property var wifiNetworks: []
    property string wifiSignature: ""

    /// How many networks the log last said were visible. Deduplicated for the
    /// reason the rows are: this handler runs every few seconds forever on a
    /// machine sitting still, and a line per run would be a log nobody reads.
    /// The count is the field that moves when something *happened*.
    property int lastVisible: -1

    onWifiCandidatesChanged: {
        const rows = root.wifi.rows(root.wifiCandidates);
        // Above the signature gate rather than below it: the gate returns early
        // whenever the published rows would not change, and the count still
        // needs saying on the first list a scan produces (#141).
        if (rows.length !== root.lastVisible) {
            root.lastVisible = rows.length;
            Logger.log("network", root.wifi.visible(rows.length));
        }
        const signature = root.wifi.signature(rows);
        if (signature === root.wifiSignature)
            return;
        root.wifiSignature = signature;
        root.wifiNetworks = rows;
    }

    /// NetworkManager's twelve security types as the four kinds the policy
    /// reasons about. Translated here and not there for the reason
    /// Services/System/SystemTray.qml gives about status: the policy has no
    /// `WifiSecurityType` to name, and one that took an integer would be one
    /// nobody can read.
    function securityKind(security: var): string {
        switch (security) {
        case Nm.WifiSecurityType.Open:           return "open";
        case Nm.WifiSecurityType.Owe:            return "owe";
        case Nm.WifiSecurityType.StaticWep:
        case Nm.WifiSecurityType.DynamicWep:     return "wep";
        case Nm.WifiSecurityType.WpaPsk:
        case Nm.WifiSecurityType.Wpa2Psk:
        case Nm.WifiSecurityType.Sae:
        case Nm.WifiSecurityType.Wpa3SuiteB192:  return "psk";
        case Nm.WifiSecurityType.WpaEap:
        case Nm.WifiSecurityType.Wpa2Eap:
        case Nm.WifiSecurityType.Leap:           return "eap";
        }
        return "unknown";
    }

    /// The row for an SSID, or null — the lookup the IPC door needs, since a
    /// keybind has a name and not an object.
    function rowFor(ssid: string): var {
        for (const row of root.wifiNetworks)
            if (row.ssid === ssid)
                return row;
        return null;
    }

    // --- joining and leaving -------------------------------------------------
    //
    // Every one of these ends in a log line, and the failing paths end in one
    // *naming the reason* — a join that fails silently is #81 at its worst,
    // because the surface it fails behind is a password prompt and the user's
    // next move is to assume they typed it wrong.

    /// Join a network. `passphrase` is empty for an open or already-saved one:
    /// NetworkManager holds the secret for the second case, and asking again
    /// for something the machine knows is how a user comes to believe the shell
    /// forgot it.
    function join(ssid: string, passphrase: string): void {
        const row = root.rowFor(ssid);
        if (row === null || row.live === null) {
            Logger.warn("network", root.wifi.refused(ssid, "no such network"));
            return;
        }
        if (!root.wifi.joinable(row)) {
            // Enterprise. A prompt asking for a "password" would fail after the
            // typing, so the refusal is up front and names what to use instead.
            Logger.warn("network",
                        root.wifi.refused(ssid, "enterprise networks are configured "
                                                + "in NetworkManager, not here"));
            return;
        }

        const secret = String(passphrase ?? "");
        if (secret !== "" && !root.wifi.passphraseAccepted(row, secret)) {
            Logger.warn("network", root.wifi.refused(ssid, "passphrase too short"));
            return;
        }

        // Attached per join rather than once per network: the signal carries a
        // reason and no SSID, so the only way to say *which* join failed is to
        // close over the name of the one being started. Disconnected again on
        // the way out, or a network joined five times would report five times.
        root.watchFailure(row.live, ssid);

        Logger.log("network", root.wifi.asked("join", ssid));
        if (secret === "")
            row.live.connect();
        else
            row.live.connectWithPsk(secret);
    }

    /// Take down whatever is on this network's device. `disconnect()` is on the
    /// network rather than the device because a machine with two radios has two
    /// answers to "disconnect", and the row the user pressed is the one that
    /// names which.
    function leave(ssid: string): void {
        const row = root.rowFor(ssid);
        if (row === null || row.live === null) {
            Logger.warn("network", root.wifi.refused(ssid, "no such network"));
            return;
        }
        Logger.log("network", root.wifi.asked("leave", ssid));
        row.live.disconnect();
    }

    /// Forget a saved network — the one act here that destroys something, so it
    /// is a separate verb rather than a flag on `leave`. NetworkManager drops
    /// the profile and the secret with it.
    function forget(ssid: string): void {
        const row = root.rowFor(ssid);
        if (row === null || row.live === null) {
            Logger.warn("network", root.wifi.refused(ssid, "no such network"));
            return;
        }
        if (!row.known) {
            Logger.warn("network", root.wifi.refused(ssid, "nothing saved to forget"));
            return;
        }
        Logger.log("network", root.wifi.asked("forget", ssid));
        row.live.forget();
    }

    /// The most recent failure, for the panel to show under the prompt. A
    /// property and not only a log line: the log is for the harness, and the
    /// person who just typed a passphrase is owed the answer on screen.
    property string lastFailure: ""
    property string lastFailureSsid: ""

    /// The one handler currently attached, and what it is attached to.
    ///
    /// One, and that is the whole of why this is a property rather than a
    /// closure left to look after itself. `connectionFailed` carries a reason
    /// and no SSID, so the only way to say *which* join failed is to close over
    /// the name — but a handler that only removes itself when it fires is one
    /// that stays attached forever after a join that *worked*, and the tenth
    /// successful join to the same access point would leave ten of them waiting
    /// to report the eleventh failure ten times over.
    ///
    /// So the attachment is single: taking a new one releases the old, and so
    /// does leaving the panel.
    property var failureWatch: null

    function watchFailure(network: var, ssid: string): void {
        root.unwatchFailure();

        const handler = reason => {
            root.unwatchFailure();
            root.lastFailureSsid = ssid;
            root.lastFailure = root.wifi.failureWords(
                Nm.ConnectionFailReason.toString(reason));
            Logger.warn("network", root.wifi.failure(
                ssid, Nm.ConnectionFailReason.toString(reason)));
        };
        network.connectionFailed.connect(handler);
        root.failureWatch = { network: network, handler: handler };
    }

    function unwatchFailure(): void {
        if (root.failureWatch === null)
            return;
        // The network object can outlive the access point it stands for —
        // NetworkManager drops one that goes off the air — so this is guarded
        // rather than trusted.
        try {
            root.failureWatch.network.connectionFailed.disconnect(
                root.failureWatch.handler);
        } catch (error) {
            // Already gone. Nothing to release, and nothing worth a line: this
            // is the ordinary end of an access point that stopped broadcasting.
        }
        root.failureWatch = null;
    }

    /// Cleared when the user starts over, so a stale "wrong passphrase" does
    /// not sit under a second attempt at a different network — and the watch
    /// goes with it, which is what bounds the attachment to the panel's life.
    function clearFailure(): void {
        root.unwatchFailure();
        root.lastFailure = "";
        root.lastFailureSsid = "";
    }

    // --- what surfaces read --------------------------------------------------

    readonly property var primary: root.policy.primary(root.devices)
    readonly property bool connected: root.primary !== null && root.primary.connected === true
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
