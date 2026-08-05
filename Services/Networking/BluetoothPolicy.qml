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
    /// The searching glyph is for a scan *this shell is holding* — the control
    /// centre's device list (#45), which turns the radio's scanner on for as
    /// long as it is open. `ours` is what says so.
    ///
    /// #36 drew every discovering adapter, whoever started it, on the argument
    /// that an adapter doing something should look like it. Measured on a real
    /// session (#137, tools/idle-budget.sh), that is a bar that repaints on
    /// somebody else's schedule: something on this machine discovers on a 60 s
    /// cycle, and the glyph flipped six times in a 179 s idle window — twenty of
    /// its thirty repaints, against a budget of one a minute (#22 §5).
    ///
    /// A background scan the user did not ask for is not something they can act
    /// on, and it is not worth waking the bar for. The panel that *did* ask
    /// still says so in words, off the adapter directly
    /// (Surfaces/Drawers/DrillIn/BluetoothPanel.qml).
    function icon(enabled: bool, connected: int, discovering: bool, ours: bool): string {
        if (!enabled)
            return "bluetooth-off";
        if (connected > 0)
            return "bluetooth-connected";
        return discovering && ours ? "bluetooth-searching" : "bluetooth";
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
    /// A nameless device is a real device with a real address, and BlueZ hands
    /// those over constantly during a scan; hiding them would make the list
    /// shorter than what is on the air, which is the opposite of what a
    /// discovery view is for. The one thing that does not get its own row is
    /// the LE shadow of a device already listed over classic — see
    /// `foldTransports`, which is #153 and not a tidiness preference.
    /// `generations` is `handleGenerations`' answer, or nothing at all — the bar
    /// builds rows without one, because which object a row points at is only the
    /// panel's problem (#189).
    function deviceRows(devices: var, generations: var): var {
        const out = [];
        const seen = generations ?? ({});
        for (const device of devices ?? []) {
            const address = String(device?.address ?? "").trim();
            if (address === "")
                continue;       // BlueZ has not filled the object in yet
            out.push(policy.deviceRow(device, address,
                                      Number(seen[address]?.generation ?? 0)));
        }
        return policy.foldTransports(out).sort(policy.compareDevices);
    }

    /// How many times the handle behind each address has been replaced (#189).
    ///
    /// A BlueZ device object that goes away and comes back — the adapter
    /// cycling, the device leaving and re-entering range — arrives carrying the
    /// same address, the same name and the same flags. Every field the signature
    /// was made of is identical, so the republish gate held the list still and
    /// the rows went on pointing at a destroyed object; the press after that
    /// threw to the QML console rather than connecting anything, which from the
    /// outside is the same dead button as a refused connect.
    ///
    /// Identity is not something one reading can show, so it is counted instead:
    /// this takes the last count and hands back the next one, and the number
    /// goes into the signature. An address BlueZ has forgotten leaves the map
    /// rather than being kept at its last count — a device re-appearing after
    /// that is a new row anyway, and a map that only grows is a map that grows
    /// for as long as the session lasts.
    function handleGenerations(rows: var, previous: var): var {
        const before = previous ?? ({});
        const next = ({});
        for (const row of rows ?? []) {
            const address = String(row?.address ?? "").trim();
            if (address === "")
                continue;
            const was = before[address];
            const moved = was !== undefined && was.live !== (row.live ?? null);
            next[address] = {
                live: row.live ?? null,
                generation: was === undefined ? 0
                          : (moved ? was.generation + 1 : was.generation)
            };
        }
        return next;
    }

    /// The name a `LE-…` advertisement is shadowing, or "" for anything that is
    /// not one.
    ///
    /// BlueZ names a device it has only seen advertise over LE after the
    /// advertisement, and a dual-mode headset advertising while it is also
    /// discoverable over BR/EDR turns up twice: once as "Zen Zone" and once as
    /// "LE-Zen Zone", under two different addresses.
    function classicName(name: var): string {
        const match = /^LE[-_](.+)$/i.exec(String(name ?? "").trim());
        return match ? match[1].trim() : "";
    }

    /// Drop the LE advertisement of a device that is also on the list over
    /// classic (#153).
    ///
    /// The pass that filed it pressed "LE-Zen Zone" and got a bond that carried
    /// no A2DP — LE has no such profile, so PipeWire never made a card and no
    /// sink appeared. The two rows are one headset, and only one of them is a
    /// row you can get audio out of.
    ///
    /// Only a bare scan result is folded away. An LE entry that is connected,
    /// bonded or pairing is the row holding the verb for whatever is actually
    /// happening, and hiding it would leave a live device with no way to
    /// disconnect it. An LE device with no classic twin — a tag, a watch, half
    /// the mice — keeps its row, because it is the only one it has.
    function foldTransports(rows: var): var {
        const byName = ({});
        for (const row of rows ?? [])
            byName[String(row.name ?? "").trim().toLowerCase()] = true;

        const out = [];
        for (const row of rows ?? []) {
            const base = policy.classicName(row.name);
            const shadowed = base !== "" && byName[base.toLowerCase()] === true;
            if (shadowed && policy.nothingHappeningTo(row))
                continue;
            out.push(row);
        }
        return out;
    }

    /// Whether a press has landed on the LE transport of a device that is also
    /// on the list over classic (#189).
    ///
    /// `foldTransports` folds the LE row away while it is only a scan result, and
    /// deliberately keeps it once it is bonded or connected — it is then the only
    /// row carrying the verb for what is actually happening. Which leaves the
    /// case this answers: the row is still there, and a press on it asks for a
    /// connection on a transport that has no A2DP to give. #153 spent a session
    /// on a bond that carried no audio for exactly this reason.
    ///
    /// Reported rather than prevented, and this is the argument: the row is real,
    /// BlueZ will connect it, and an LE device does carry other profiles. What
    /// was wrong was that it was attempted in silence, so a press that produced
    /// no sound produced no explanation either.
    function leShadow(row: var, rows: var): bool {
        const base = policy.classicName(row?.name);
        if (base === "")
            return false;
        for (const other of rows ?? [])
            if (String(other?.name ?? "").trim().toLowerCase() === base.toLowerCase())
                return true;
        return false;
    }

    function leWarning(name: string): string {
        return name + " is the LE transport — audio needs its classic row";
    }

    /// A row that is only a scan result: nothing connected, nothing bonded,
    /// nothing in flight. Asked as a question rather than compared against
    /// `deviceBand`'s last band, so that adding a band stays a change to the
    /// order rather than a silent change to what the list contains.
    function nothingHappeningTo(row: var): bool {
        const facts = row ?? ({});
        return facts.connected !== true && facts.paired !== true
            && facts.pairing !== true;
    }

    function deviceRow(device: var, address: string, generation: int): var {
        const name = String(device?.name ?? "").trim();
        return {
            address: address,
            // Not a fact about the device — a count of how many objects BlueZ
            // has used to represent it. It exists to be in the signature.
            generation: Number(generation ?? 0),
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
            connecting: device?.connecting === true,
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
    ///
    /// The generation is here for the opposite reason (#189): it is the one part
    /// of a row that is not a fact about the device, and without it a handle
    /// BlueZ replaced hides behind an unchanged address, name and set of flags.
    /// `connecting` is deliberately *not* here — an attempt in flight is a word
    /// on a row read live off the handle, and republishing the list for it would
    /// rebuild every delegate on every press.
    function deviceSignature(rows: var): string {
        return (rows ?? []).map(row => row.address + " " + row.name
                                + (row.connected ? "c" : "-")
                                + (row.paired ? "p" : "-")
                                + (row.pairing ? "…" : "-")
                                + "#" + Number(row.generation ?? 0)).join("");
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
    ///
    /// `connecting` and `failed` are #189's halves of the acknowledgement: until
    /// them this line read "Paired" before a press and "Paired" after the attempt
    /// had silently died, which is a row indistinguishable from a dead button.
    /// The order is what keeps a stale marker on either side from outranking the
    /// truth: a device that has arrived reads "Connected" whatever was in flight
    /// a moment ago, and a second press over a failure that is still on screen
    /// reads as trying rather than as the last failure.
    function deviceDetail(row: var): string {
        const facts = row ?? ({});
        if (facts.pairing === true)
            return "Pairing…";
        if (facts.connected === true)
            return facts.batteryAvailable === true
                 ? "Connected · " + policy.batteryLabel(facts.battery)
                 : "Connected";
        if (facts.connecting === true)
            return "Connecting…";
        if (facts.failed === true)
            return "Connect failed";
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

    /// The scan the shell wanted was already running when it asked (#189).
    ///
    /// Its own line because the alternative is the silence the ticket found: a
    /// panel opened over somebody else's scan wrote nothing at all, so "the hold
    /// was taken and did nothing" and "the panel never asked" read identically in
    /// the log.
    /// The panel's activity line (#189): whether a scan is *running*, asked as a
    /// question about the radio and not about the request.
    ///
    /// A panel holding a scan the adapter is not running is the case that had no
    /// words at all — the line was empty, which is what a panel that never asked
    /// looks like. Nothing is said when nobody is holding one, because a panel
    /// that is closed is not making a claim about the radio.
    function activity(wanted: bool, discovering: bool): string {
        if (!wanted)
            return "";
        return discovering ? "scanning…" : "not scanning";
    }

    function discoveryShared(): string {
        return "already discovering — somebody else started it";
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

    // --- trust (#153) ---------------------------------------------------------

    /// Whether a device that has just bonded still needs marking trusted.
    ///
    /// Without `Trusted: yes` BlueZ will not accept a connection the device
    /// itself starts, so a headset that has been powered off and on again sits
    /// there advertising and nothing happens — the bond is intact and useless.
    /// The facade read `trusted` from the moment the drill-in was written (#45)
    /// and never set it; the pass that filed #153 is what that costs.
    ///
    /// The transition and not the reading, for the same reason `settled` takes
    /// two: a device that was already paired and untrusted when the shell
    /// started was left that way by somebody else's decision — blueman, a
    /// `bluetoothctl untrust`, a policy this shell knows nothing about — and
    /// starting up is not the moment to overrule it.
    function trustNeeded(was: var, now: var): bool {
        if (was === null || was === undefined || now === null || now === undefined)
            return false;
        return was.paired !== true && now.paired === true && now.trusted !== true;
    }

    function trustGranted(name: string): string {
        return name + " trusted";
    }

    // --- the pairing agent (#153) --------------------------------------------
    //
    // The one thing in this facade that is not native, and the header of
    // Services/Networking/Bluetooth.qml argues the case: pairing needs an agent
    // on the bus to answer BlueZ's authentication request, nothing in QML can
    // export one, and `bluetoothctl` registers one for as long as it runs.
    // These two functions are the whole of what it is told and the whole of
    // what is read back.

    /// How long an attempt is given before it is called off. BlueZ's own
    /// pairing window is about this long, and the number is here rather than on
    /// the Timer for the reason LogindBridge's confirm timeout is: it is a
    /// threshold, and thresholds are decisions (CLAUDE.md, seam 1).
    readonly property int pairTimeoutMs: 60000

    /// How long a *connect* is given (#189), and how long its failure stays on
    /// the row afterwards.
    ///
    /// Shorter than a pairing, because the two are waiting for different things:
    /// a pairing waits on a human reading a code off a screen or holding a
    /// button, and a connect waits on a radio that either answers or does not.
    /// BlueZ's own `Connect` on an out-of-range device gives up in about ten
    /// seconds; this is that with room, and it exists at all because the
    /// alternative — what the ticket found — is a row that reads "Connecting…"
    /// until the shell restarts.
    ///
    /// The failure is shown for long enough to read and then the row goes back
    /// to resting: a permanent "Connect failed" is a row that lies about the
    /// next press as badly as the silent one did.
    readonly property int connectTimeoutMs: 15000
    readonly property int failedShownMs: 4000

    /// What the log says about a connect that has ended — either way (#189).
    ///
    /// One function for both endings rather than two, so that a failure cannot
    /// be the one someone forgot to write: the reason is the only argument that
    /// decides which line this is, and "" is the only spelling of success.
    function connectOutcome(name: string, reason: string): string {
        const why = String(reason ?? "").trim();
        return why === "" ? "connected " + name
                          : name + " not connected — " + why;
    }

    /// What to write to `bluetoothctl` to pair one device, in order.
    ///
    /// The order is the fix. An agent first, made the default second — a
    /// registered agent BlueZ has not been told to prefer answers nothing —
    /// then trust, then pair. Trust *before* pair because that is the sequence
    /// that held on real hardware (#153): a device trusted while the bond is
    /// being made never has an unattended moment where BlueZ would refuse it.
    function pairScript(address: var): var {
        const target = String(address ?? "").trim();
        if (target === "")
            return [];
        return ["agent NoInputNoOutput", "default-agent",
                "trust " + target, "pair " + target];
    }

    /// What one line of `bluetoothctl` output means, if anything.
    ///
    /// `done` is the important half: it is what ends the attempt, and ending
    /// the attempt is what closes the process and unregisters the agent. It
    /// narrates the whole scan while it waits — every `[NEW] Device` on the
    /// air — and treating any of that as an answer is how a pairing loses its
    /// agent halfway through, which is the shape of the bug this fixes.
    ///
    /// The escape sequences are stripped first: bluetoothctl colours its output
    /// with no terminal on the far end, and a `[0;92m` in front of the text is
    /// what makes a match that works by hand fail in a pipe.
    function pairOutcome(text: var): var {
        const line = String(text ?? "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
        if (/Pairing successful/i.test(line))
            return { done: true, ok: true, reason: "" };
        const failed = /Failed to pair:?\s*(.*)$/i.exec(line);
        if (failed)
            return { done: true, ok: false, reason: failed[1].trim() };
        // An address bluetoothctl holds no object for — a device that walked
        // out of range between the scan and the press. Measured against 5.87:
        // it says this instead of failing to pair, and reading it as narration
        // is a row stuck on "Pairing…" until the timeout.
        if (/Device \S+ not available/i.test(line))
            return { done: true, ok: false, reason: "not available" };
        return { done: false, ok: false, reason: "" };
    }

    /// What the log says once the attempt is over. The reason is BlueZ's own
    /// error name, kept verbatim: `org.bluez.Error.AuthenticationCanceled` is
    /// searchable and "pairing failed" is not.
    function paired(name: string, outcome: var): string {
        if (outcome?.ok === true)
            return name + " paired";
        const reason = String(outcome?.reason ?? "").trim();
        return reason === "" ? name + " pairing failed"
                             : name + " pairing failed — " + reason;
    }
}
