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
// here polls, and every verb but one is a method on the device object.
//
// The exception is pairing, and #153 is why. BlueZ hands an authentication
// request to a *pairing agent* on the bus; with no agent registered, an
// outgoing `Pair()` bonds and is then torn down seconds later — measured on
// real hardware, `Paired: yes` at t+5s and `Paired: no` at t+9s. Neither this
// shell nor the upstream module registers one (checked: the binary carries no
// `org.bluez.Agent1`), and QML cannot export a DBus object to do it. So the
// pair verb alone is driven through `bluetoothctl`, which registers an agent
// for as long as it runs — see `pairer` below.
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
import Quickshell.Io
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

    /// `discoveryHolders` and not `discovering` alone: the glyph follows the
    /// scans this shell is holding, so a background scan somebody else started
    /// does not wake the bar (#137 — see the policy).
    readonly property string icon: root.policy.icon(root.enabled, root.connectedCount,
                                                    root.discovering,
                                                    root.discoveryHolders > 0)
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
    // Native but for one verb: `BluetoothDevice` carries `connect()`,
    // `disconnect()`, `cancelPair()` and `forget()`, and it carries `pair()`
    // too — but a pair with no agent behind it is #153, so that one goes
    // through `bluetoothctl` instead. The header argues it; `pairer` below is
    // where it happens.
    //
    // What all of it needs is a scan, which the bar deliberately never started
    // — see the header, and `beginDiscovery` below for who holds it now.

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
                // A pairing this shell is driving is a pairing in flight, and
                // BlueZ's own flag does not carry it: the request belongs to
                // the `bluetoothctl` the facade started, not to this object.
                // Without this the row would read "Not paired" for the whole
                // attempt and a second press would start a second one.
                pairing: device.pairing === true || device.address === root.pairingAddress,
                trusted: device.trusted === true,
                // BlueZ's own answer to "is a connection being set up", read
                // here for the first time (#189). Reading it inside this
                // binding is also what makes the binding re-evaluate when it
                // moves, which is what `watchConnect` below is waiting for.
                connecting: device.state === Bz.BluetoothDeviceState.Connecting,
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

    /// What the log last said about each device, by address. Not a binding and
    /// not notified: nothing reads it but the handler below, and its whole job
    /// is to be the *previous* reading (#141).
    property var deviceHistory: ({})

    /// Say what BlueZ actually did, as opposed to what it was asked to do.
    ///
    /// A device seen for the first time is not a transition — an adapter coming
    /// up with three paired headsets on it would otherwise announce all three
    /// as having just paired.
    function noteDeviceChanges(): void {
        for (const row of root.deviceCandidates) {
            const was = root.deviceHistory[row.address] ?? null;
            const now = {
                paired: row.paired, connected: row.connected, pairing: row.pairing,
                trusted: row.trusted
            };
            root.deviceHistory[row.address] = now;
            if (was === null)
                continue;
            for (const line of root.policy.settled(row.name, was, now))
                Logger.log("bluetooth", line);
            root.grantTrust(row, was, now);
        }
    }

    /// Mark a device that has just bonded trusted (#153).
    ///
    /// Here and not only in the pair script, because a bond can arrive without
    /// this shell asking for one — a headset paired from its own side ends up
    /// in exactly the state the ticket describes: bonded, untrusted, and unable
    /// to reconnect itself afterwards. BlueZ materialises the device object
    /// when it shows up rather than when the bond completes, so that arrives
    /// here as a transition like any other.
    ///
    /// What it is not is the shell starting up next to devices that are already
    /// paired. Those have no previous reading, `noteDeviceChanges` skips them,
    /// and `trustNeeded` says why that is the wanted answer rather than a gap:
    /// an old bond left untrusted was left that way by a decision this shell
    /// knows nothing about.
    ///
    /// `trusted` is one of the two writable properties on the upstream device
    /// object, so this half needs no helper.
    function grantTrust(row: var, was: var, now: var): void {
        if (row.live === null || !root.policy.trustNeeded(was, now))
            return;
        row.live.trusted = true;
        // Written back so the next reading does not see the transition again
        // before BlueZ's own signal has come round.
        now.trusted = true;
        Logger.log("bluetooth", root.policy.trustGranted(row.name));
    }

    onDeviceCandidatesChanged: {
        // Above the signature gate, and not folded into it: the gate decides
        // whether the *panel* is worth rebuilding, and what the log says must
        // not be a consequence of a repaint decision. Today the signature
        // carries paired/connected/pairing and the two would agree; a field
        // dropped from it for a drawing reason would silence this.
        root.noteDeviceChanges();
        // Above the gate too, and for the same reason: whether a connect in
        // flight has ended is not a drawing decision, and a reading that does
        // not change the list is still the reading that carries the answer —
        // `Connecting` is deliberately not in the signature.
        root.watchConnect();
        root.handleGenerations = root.policy.handleGenerations(root.deviceCandidates,
                                                              root.handleGenerations);
        const rows = root.policy.deviceRows(root.deviceCandidates, root.handleGenerations);
        const signature = root.policy.deviceSignature(rows);
        if (signature === root.deviceSignature)
            return;
        root.deviceSignature = signature;
        root.deviceRows = rows;
    }

    /// How many objects BlueZ has used for each address so far (#189) — the one
    /// part of the signature that is not a fact about the device. Not a binding
    /// and not notified, like `deviceHistory` next door: nothing reads it but the
    /// handler above and `refreshDevices`.
    property var handleGenerations: ({})

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
        if (root.adapter.discovering === wanted) {
            // Wanting a scan that is already running writes nothing — the
            // property is upstream's mirror of the adapter's flag and setting it
            // to what it already is calls no method. Said out loud rather than
            // returned in silence (#189): this is the case where the panel opens
            // and nothing at all appears in the log, and the hold it thinks it
            // took is somebody else's scan. `onDiscoveringChanged` below is what
            // makes the hold real again the moment that scan stops.
            if (wanted)
                Logger.log("bluetooth", root.policy.discoveryShared());
            return;
        }
        root.adapter.discovering = wanted;
        Logger.log("bluetooth", root.policy.discovery(wanted));
    }

    /// The adapter's own flag moving, whoever moved it (#189).
    ///
    /// Discovery on this machine is not only ever the shell's: blueman, a
    /// `bluetoothctl scan on` in a terminal, anything else on the bus can start
    /// and stop it, and something here does so on a roughly 60 s cycle (measured
    /// in #137). Before this, a hold taken while one of those was running was
    /// never really the shell's, and was never re-applied when the other party
    /// stopped — the panel sat open over an adapter that had gone quiet, which is
    /// the "not always scanning" half of the ticket.
    ///
    /// Only ever re-*asserts*. A flag going up while nobody holds it is somebody
    /// else's scan and is left alone — stopping it would be this shell reaching
    /// into another program's business, and #22 §5's rule is that the shell does
    /// not scan at rest, not that nothing may.
    onDiscoveringChanged: {
        if (root.discoveryHolders > 0 && root.enabled && !root.discovering)
            root.applyDiscovery();
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

    /// The address being paired right now, "" when nothing is. One at a time:
    /// the helper below is one process holding one agent, and BlueZ's own
    /// pairing is one at a time anyway.
    property string pairingAddress: ""
    property string pairingName: ""

    /// Pair and connect, which is one gesture: nobody who presses an unpaired
    /// headset wants to be paired to it and then have to press it again.
    ///
    /// Through `bluetoothctl` rather than `live.pair()`, for the reason the
    /// header gives: the native call has no agent behind it, and #153 is what
    /// that looks like on real hardware — a bond that appears and is torn down
    /// four seconds later, with the log holding the one hopeful line this
    /// function writes before it starts.
    function pairDevice(address: string): void {
        const row = root.rowFor(address);
        if (row === null || row.live === null) {
            Logger.warn("bluetooth", root.policy.deviceRefused(address, "no such device"));
            return;
        }
        if (root.pairingAddress !== "") {
            Logger.warn("bluetooth",
                        root.policy.deviceRefused(row.name, "already pairing with "
                                                  + root.pairingName));
            return;
        }
        if (pairer.live) {
            // The helper of the attempt just cancelled has not exited yet, and
            // starting inside that window hands the new attempt to the old
            // process's exit handler. Refused rather than queued: the press is
            // a finger, and a finger can press again.
            Logger.warn("bluetooth",
                        root.policy.deviceRefused(row.name, "the last pairing helper "
                                                  + "has not stopped yet"));
            return;
        }
        Logger.log("bluetooth", root.policy.asked("pair", row.name));
        root.pairingAddress = row.address;
        root.pairingName = row.name;
        // Re-enabled and not merely started: the previous attempt turned
        // writing off on its way out, and a helper that cannot be written to is
        // a helper that registers no agent.
        pairer.stdinEnabled = true;
        pairer.running = true;
        pairTimeout.restart();
    }

    function cancelPairing(address: string): void {
        const row = root.rowFor(address);
        if (row === null || row.live === null) {
            Logger.warn("bluetooth", root.policy.deviceRefused(address, "no such device"));
            return;
        }
        Logger.log("bluetooth", root.policy.asked("cancel pairing with", row.name));
        // Both halves: `CancelPairing` is what stops a request already on the
        // bus, whoever made it, and ending the helper is what takes its agent
        // back off the bus so a later attempt can register a fresh one.
        root.attemptLive(row, () => row.live.cancelPair());
        if (root.pairingAddress === address)
            root.endPairing();
    }

    // --- the pairing agent (#153) --------------------------------------------

    /// `bluetoothctl`, driven for the length of one pairing and no longer.
    ///
    /// Held open for the whole attempt on purpose: the agent lives as long as
    /// this process does, and a process that exits when its script has been
    /// written is an agent that goes away halfway through the authentication it
    /// was registered to answer. What ends it is an answer on stdout, a cancel,
    /// or the timeout below.
    Process {
        id: pairer

        command: ["bluetoothctl"]
        stdinEnabled: true

        onStarted: {
            pairer.live = true;
            for (const line of root.policy.pairScript(root.pairingAddress))
                pairer.write(line + "\n");
        }

        // bluetoothctl narrates the whole scan while it waits, and says the two
        // things that matter on the same stream.
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root.readPairing(line)
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => root.readPairing(line)
        }

        onExited: (exitCode, exitStatus) => {
            pairer.live = false;
            if (root.pairingAddress === "")
                return;     // an answer or a cancel already ended it
            root.failPairing("bluetoothctl exited " + exitCode);
        }

        /// Between `onStarted` and `onExited`, which is not the same as
        /// `running`: ending the helper asks it to terminate and the exit
        /// arrives later. A second attempt started inside that gap would be
        /// ended by the *previous* process's exit — this is what makes a
        /// cancel followed immediately by a press refuse rather than eat the
        /// attempt it started.
        property bool live: false
    }

    /// A pairing nobody ever answers — the headset that was put down, the
    /// device that stopped advertising mid-attempt. Without this the row reads
    /// "Pairing…" until the shell restarts.
    Timer {
        id: pairTimeout

        interval: root.policy.pairTimeoutMs
        onTriggered: {
            if (root.pairingAddress === "")
                return;
            root.failPairing("timed out");
        }
    }

    /// One line of the helper's output, which is almost always nothing.
    function readPairing(line: string): void {
        if (root.pairingAddress === "")
            return;
        const outcome = root.policy.pairOutcome(line);
        if (!outcome.done)
            return;

        const address = root.pairingAddress;
        const name = root.endPairing();
        if (outcome.ok)
            Logger.log("bluetooth", root.policy.paired(name, outcome));
        else
            Logger.warn("bluetooth", root.policy.paired(name, outcome));

        // The second half of the one gesture. BlueZ connects on its own after a
        // pair for most device classes and this is the case where it does not;
        // asking twice costs an `AlreadyConnected` error on the bus, and not
        // asking costs a headset that is bonded and silent.
        if (outcome.ok)
            root.connectAfterPair(address);
    }

    /// End the attempt and say why, for the two endings that are nobody's
    /// answer: the helper dying, and the minute running out.
    function failPairing(reason: string): void {
        const name = root.endPairing();
        Logger.warn("bluetooth",
                    root.policy.paired(name, { done: true, ok: false, reason: reason }));
    }

    /// The second half of the one gesture, through the same door as a press
    /// (#189) — it was its own copy of `connect()`-and-forget, which made the
    /// half of the gesture nobody explicitly asked for the half with no ending.
    function connectAfterPair(address: string): void {
        const row = root.rowFor(address);
        if (row === null || row.live === null || row.connected)
            return;
        root.connectDevice(address);
    }

    /// Take the in-flight flag back out of the last reading, so the pairing
    /// this shell drove is not also reported as a transition next door.
    ///
    /// `settled` watches the flag going down without a bond and calls that a
    /// pairing failure (#141) — which is right when BlueZ is the one pairing,
    /// and a second line saying less when the helper is: it has already
    /// written the same failure with the reason attached. The flag going down
    /// after a *cancel* would be a failure line for something the user asked
    /// for on purpose.
    function forgetPairingFlag(address: string): void {
        const seen = root.deviceHistory[address];
        if (seen)
            seen.pairing = false;
    }

    /// End the helper and take its agent off the bus. `running = false`
    /// terminates rather than closing stdin, for the reason
    /// Services/System/LogindBridge.qml measured: 0.3.0's `stdinEnabled = false`
    /// stops writing to the child rather than closing its input, so a child
    /// waiting on stdin outlives it.
    function stopPairer(): void {
        pairer.stdinEnabled = false;
        pairer.running = false;
    }

    /// End whatever is in flight and hand back the name it was for, so the
    /// caller can say what became of it. The one teardown: every ending —
    /// an answer, a cancel, a timeout, a helper that died — goes through here,
    /// because four of them written out four times is four chances to drop the
    /// timer or leave the flag up.
    function endPairing(): string {
        const name = root.pairingName;
        pairTimeout.stop();
        root.forgetPairingFlag(root.pairingAddress);
        root.pairingAddress = "";
        root.pairingName = "";
        root.stopPairer();
        return name;
    }

    // --- a connect that reaches an ending (#189) ------------------------------
    //
    // What this ticket found: `connectDevice` logged one hopeful line, called
    // `connect()` and forgot about it. Three different things then look the same
    // from the outside — BlueZ refusing asynchronously, the handle having been
    // replaced under the row, and the press landing on an LE transport that
    // cannot carry audio — and all three read as a dead button, because the row
    // said "Paired" before the press and "Paired" afterwards and the log held
    // only the optimistic line.
    //
    // Shaped after the pairing path above, which already had all of this: one
    // attempt at a time, a timeout, an outcome parser, one teardown. What is
    // different is where the outcome comes from — a pairing is read off
    // `bluetoothctl`'s stdout, and a connect is read off the device's own
    // `state`, which is upstream's answer and needs no helper.

    /// The address being connected right now, "" when nothing is. One at a time
    /// for the reason the pairing flag is: the row is the acknowledgement, and
    /// two attempts sharing one flag is a row that lies about one of them.
    property string connectingAddress: ""
    property string connectingName: ""

    /// Whether BlueZ has been seen to actually start on the attempt in flight.
    ///
    /// This is the difference between "not connected yet" and "not connected":
    /// `connect()` returns before `state` moves, so a device still reading
    /// `Disconnected` one signal later has not failed — it has not started. Only
    /// once `Connecting` has been seen does dropping back to `Disconnected` mean
    /// BlueZ said no; before that, the timeout is what ends it.
    property bool connectStarted: false

    /// The address whose last attempt failed, for as long as the row says so.
    property string failedAddress: ""

    /// `BluetoothDeviceState.Connecting`, for the panel to compare against
    /// without importing the BlueZ module into a surface.
    readonly property int connectingState: Bz.BluetoothDeviceState.Connecting

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
        if (root.connectingAddress === address) {
            // A second press on a row that already says "Connecting…". Refused
            // rather than started again, and *logged*: pressing twice because
            // nothing appeared to happen is exactly what the ticket describes
            // someone doing, and the answer to it has to be a line that says
            // the first press is still in flight.
            Logger.warn("bluetooth",
                        root.policy.deviceRefused(row.name, "already connecting"));
            return;
        }
        if (root.connectingAddress !== "") {
            Logger.warn("bluetooth",
                        root.policy.deviceRefused(row.name, "already connecting to "
                                                  + root.connectingName));
            return;
        }
        if (root.policy.leShadow(row, root.deviceRows))
            Logger.warn("bluetooth", root.policy.leWarning(row.name));
        Logger.log("bluetooth", root.policy.asked("connect", row.name));
        root.connectingAddress = row.address;
        root.connectingName = row.name;
        root.connectStarted = false;
        root.clearFailed();
        connectTimeout.restart();
        if (!root.attemptLive(row, () => row.live.connect()))
            root.endConnect();
    }

    /// Call something on a device's live handle, and survive the handle having
    /// been destroyed since the row was published (#189).
    ///
    /// The published row holds a reference to a BlueZ device object, and BlueZ
    /// replaces those: an adapter cycling, a device leaving and re-entering
    /// range. Before this, the call on a dead one threw to the QML console —
    /// where nothing that reads this shell's log will ever look — and the row
    /// went on pointing at it, so the *next* press threw as well. Both halves are
    /// here: the log line, and the republish that makes the second press land on
    /// the object BlueZ has now.
    function attemptLive(row: var, action: var): bool {
        try {
            action();
            return true;
        } catch (error) {
            Logger.warn("bluetooth",
                        root.policy.deviceRefused(row.name, "its bluez handle is gone"));
            root.refreshDevices();
            return false;
        }
    }

    /// A connect nobody ever answers — the headset in a bag, the speaker that is
    /// off at the wall. Without this the row reads "Connecting…" until the shell
    /// restarts, which is the same lie as "Paired" with a slower onset.
    Timer {
        id: connectTimeout

        interval: root.policy.connectTimeoutMs
        onTriggered: {
            if (root.connectingAddress === "")
                return;
            root.failConnect("timed out");
        }
    }

    /// How long the failure stays on the row before it goes back to resting.
    Timer {
        id: failedShown

        interval: root.policy.failedShownMs
        onTriggered: root.failedAddress = ""
    }

    /// Read the attempt's outcome off the device itself, on every reading of
    /// BlueZ — which is every time any property of any device moves, including
    /// the `state` this is watching.
    function watchConnect(): void {
        if (root.connectingAddress === "")
            return;
        const row = root.rowFor(root.connectingAddress);
        if (row === null) {
            // The device object went away mid-attempt: the adapter cycled, or
            // BlueZ dropped a device it no longer sees. Not a timeout, and not
            // silence either.
            root.failConnect("bluez no longer knows the device");
            return;
        }
        if (row.connected) {
            const name = root.endConnect();
            Logger.log("bluetooth", root.policy.connectOutcome(name, ""));
            return;
        }
        if (row.connecting) {
            root.connectStarted = true;
            return;
        }
        if (root.connectStarted)
            root.failConnect("refused by bluez");
    }

    /// End the attempt and say why. Every ending that is not success comes
    /// through here, for the reason `endPairing` gives: four endings written out
    /// four times is four chances to leave the row saying "Connecting…".
    function failConnect(reason: string): void {
        const address = root.connectingAddress;
        const name = root.endConnect();
        root.failedAddress = address;
        failedShown.restart();
        Logger.warn("bluetooth", root.policy.connectOutcome(name, reason));
    }

    function clearFailed(): void {
        failedShown.stop();
        root.failedAddress = "";
    }

    /// The one teardown, handing back the name so the caller can say what became
    /// of it — the same shape as `endPairing`.
    function endConnect(): string {
        const name = root.connectingName;
        connectTimeout.stop();
        root.connectingAddress = "";
        root.connectingName = "";
        root.connectStarted = false;
        return name;
    }

    /// Republish the list whatever the signature says (#189).
    ///
    /// For the case the gate cannot see: a handle replaced behind an address
    /// whose name and flags did not move. `handleGenerations` makes that visible
    /// to the signature on the *next* reading, and this is what forces the
    /// reading rather than waiting for BlueZ to change something else — so the
    /// second press lands on the live object instead of throwing again.
    function refreshDevices(): void {
        root.handleGenerations = root.policy.handleGenerations(root.deviceCandidates,
                                                              root.handleGenerations);
        root.deviceRows = root.policy.deviceRows(root.deviceCandidates,
                                                 root.handleGenerations);
        root.deviceSignature = root.policy.deviceSignature(root.deviceRows);
    }

    function disconnectDevice(address: string): void {
        const row = root.rowFor(address);
        if (row === null || row.live === null) {
            Logger.warn("bluetooth", root.policy.deviceRefused(address, "no such device"));
            return;
        }
        Logger.log("bluetooth", root.policy.asked("disconnect", row.name));
        root.attemptLive(row, () => row.live.disconnect());
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
        root.attemptLive(row, () => row.live.forget());
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
