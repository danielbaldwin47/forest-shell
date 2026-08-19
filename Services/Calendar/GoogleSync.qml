pragma Singleton

// The Google half of the calendar, as thin as it can be made.
//
// Everything this file knows how to do is: decide *when* a round happens, run
// `tools/gcal-sync.py` once, hand what came back to the two pure policies, and
// do what they say. It holds no arithmetic and no mapping — `SyncPolicy` decides
// what to apply and what to push, `GoogleEventPolicy` turns payloads into events
// and back — for the reason the whole calendar is built this way: this file
// imports Quickshell and is therefore unreachable from `tests/`, so anything
// worth checking has to live on the other side of it.
//
// ## One process at a time
//
// A `Process` handed a new command while it is running is killed
// (Services/Compositor/Compositor.qml measured it; Services/Networking/Vpn.qml
// is the pattern this follows). A sync round is two runs — a pull, then a push
// of what the pull left queued — so "busy" here means the *round*, not the
// process: a trigger that arrives mid-round is dropped and the round it would
// have started is the next one on the timer. Dropping rather than queueing is
// right because a round is not about a particular edit. `pendingOps` is what
// remembers the edits, it survives a restart, and the next round drains it.
//
// ## Why the helper and not XHR
//
// `Services/Weather/Weather.qml` argues the other way — XHR, because curl would
// be a dependency added for nothing. Google is the Vpn shape instead: OAuth needs
// a loopback TCP listener QML cannot open, the token file needs 0600, and PKCE,
// refresh rotation, syncToken handling and 410 recovery are a body of logic we
// want under `tests/run.sh` in a language that can fake `urlopen`. Splitting it —
// refresh in QML, the rest in Python — would put the secret in two places.
//
// Nothing from the token file passes through this file or its log. The helper
// prints exactly one JSON object on stdout and human text on stderr, and the
// only field of a token it will ever print is the account's address.
//
// ## The log contract
//
// Six lines, and they are what `tools/calendar-harness.sh` asserts on, so their
// shape is the contract rather than a debugging aid:
//
//   calendar: sync pull N changes
//   calendar: sync push evt-N ok|failed
//   calendar: sync auth needed
//   calendar: sync error <code>
//   calendar: sync idle <iso>
//   calendar: sync full resync
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property var store: CalendarStore
    property SyncPolicy policy: SyncPolicy {}
    property GoogleEventPolicy mapping: GoogleEventPolicy {}

    readonly property var settings: Config.values.calendar.google
    readonly property bool enabled: root.settings.enabled === true
    readonly property string calendarId: root.settings.calendarId

    /// Where the helper is. Overridable so the seam-2 fake can stand in for it
    /// without a network, the way Screenshot.qml lets a fake `grim` stand in.
    readonly property string helper:
        Quickshell.env("FOREST_GCAL_HELPER") || (Paths.shellDir + "/tools/gcal-sync.py")
    readonly property bool helperIsScript: root.helper.slice(-3) === ".py"

    /// `off`, `idle`, `syncing`, `auth` (an account has to be connected) or
    /// `error`. What `syncStatus()` answers, and one word on purpose: it is read
    /// by a script and by a status line, and neither wants a sentence.
    property string status: "off"

    /// When the last round finished, UTC. Empty until one has.
    property string lastSync: ""

    /// The last thing that went wrong, for the status line. Never a token, never
    /// a URL with one in it — the helper's error strings are API messages and
    /// exit codes.
    property string lastError: ""

    /// `{syncToken, pendingOps}` — what survives a restart. Owned by
    /// `SyncPolicy`, persisted below, and never edited here except by replacing
    /// it wholesale with what a plan returned.
    property var state: ({ "syncToken": "", "pendingOps": [] })

    /// Whether a round is in flight. A round is a pull *and* the push it leads
    /// to, so this outlives either process.
    property bool busy: false

    /// Set when a plan came back needing a full resync, and cleared by the pull
    /// that serves it. One retry and not a loop: a second 410 in a row on an
    /// empty token is the server saying something this shell cannot fix by
    /// asking again.
    property bool retryingFull: false

    /// Failed rounds in a row, which is what `SyncPolicy.backoffMs` reads. Reset
    /// by any round that finishes.
    property int attempt: 0

    // --- the machine's zone -----------------------------------------------------

    /// The zone name push bodies carry. A naive `dateTime` with nothing beside
    /// it is rejected by the API per-event, so an unstated zone would fail
    /// exactly the events somebody had just made.
    ///
    /// `Intl` first because it answers with the zone the machine is actually in;
    /// `TZ` second because it is the only other thing that knows. Empty is
    /// survivable and not silent: the helper fills one in from the machine as a
    /// backstop, which is documented at `fill_timezone`.
    readonly property string zone: root.detectZone()

    function detectZone(): string {
        try {
            const named = Intl.DateTimeFormat().resolvedOptions().timeZone;
            if (typeof named === "string" && named.length > 0)
                return named;
        } catch (error) {
            // No Intl in this engine. The next line is the answer.
        }
        return Quickshell.env("TZ") || "";
    }

    /// This machine's offset in minutes east of UTC, at one instant. Passed to
    /// the mapping as a *function* rather than a number on purpose: an event
    /// that straddles a DST change needs a different answer for its start than
    /// for its end, and only asking per instant gives one.
    function offsetAt(utcStamp: string): real {
        const at = new Date(utcStamp);
        if (isNaN(at.getTime()))
            return -new Date().getTimezoneOffset();
        return -at.getTimezoneOffset();
    }

    // --- the address book, as the mapping wants it -------------------------------

    function contactByEmail(email: string): var {
        const wanted = (email || "").toLowerCase();
        for (const contact of root.store.contacts)
            if (contact.email && contact.email.toLowerCase() === wanted)
                return contact;
        return null;
    }

    function contactById(id: string): var {
        return root.store.contactById(id);
    }

    // --- triggers ----------------------------------------------------------------

    /// Run a round now. The IPC verb, the timer, and the window all end here.
    function sync(): void {
        if (!root.enabled) {
            Logger.log("calendar", "sync off — nothing to do");
            return;
        }
        if (root.busy)
            return;
        root.busy = true;
        root.status = "syncing";
        root.startPull(root.state.syncToken);
    }

    /// The calendar window opened. A person looking at a calendar is the one
    /// moment a stale one is worth a request.
    function syncOnOpen(): void {
        if (root.enabled)
            root.sync();
    }

    /// Connect an account: the helper's consent flow, which opens a browser and
    /// listens on loopback. Runs whether or not `enabled` is set — connecting is
    /// how you get to a state where switching it on means anything.
    function connect(): void {
        if (auth.running) {
            Logger.log("calendar", "sync auth already running");
            return;
        }
        auth.command = root.helperCommand(["auth"]);
        auth.running = true;
    }

    function helperCommand(args: var): var {
        // A `.py` is run through the interpreter this shell already depends on
        // (tests/run.sh does too); anything else is taken as an executable, which
        // is what lets the seam-2 fake be a shell script.
        const head = root.helperIsScript ? ["python3", root.helper] : [root.helper];
        return head.concat(args);
    }

    // --- the pull ------------------------------------------------------------------

    function startPull(token: string): void {
        pull.command = root.helperCommand(
            ["pull", "--calendar", root.calendarId, "--sync-token", token || ""]);
        pull.running = true;
    }

    function finishPull(exitCode: int, text: string): void {
        if (root.failed(exitCode, pullErr.text))
            return;

        const answer = root.parse(text);
        if (!answer) {
            root.fail("bad-json", "the helper's pull was not JSON");
            return;
        }

        // The mapping is per item and the store's address book is the same for
        // all of them, so it is bound once here rather than per event.
        const byEmail = function (email) { return root.contactByEmail(email); };
        const localOffset = function (utcStamp) { return root.offsetAt(utcStamp); };

        const items = Array.isArray(answer.events) ? answer.events : [];
        const mapped = [];
        const strangers = [];
        for (const item of items) {
            mapped.push(root.mapping.fromGoogle(item, localOffset, byEmail));
            for (const person of root.mapping.newContacts(item, byEmail))
                strangers.push(person);
        }
        root.store.rememberContacts(strangers);

        const delta = {
            "events": mapped,
            "gone": answer.gone === true,
            "nextSyncToken": typeof answer.nextSyncToken === "string" ? answer.nextSyncToken : ""
        };
        const plan = root.policy.plan(root.store.events, delta, root.state,
                                      root.store.nowStamp());

        const upserts = [];
        const removes = [];
        for (const step of plan.toApplyLocally) {
            if (step.op === "upsert")
                upserts.push(step.event);
            else
                removes.push(step.id);
        }
        Logger.log("calendar", "sync pull " + plan.toApplyLocally.length + " changes");
        if (plan.toApplyLocally.length > 0)
            root.store.applyRemote(upserts, removes);

        root.state = plan.newState;
        root.persist();

        if (plan.needsFullSync && !root.retryingFull) {
            // The token named a point in history the server no longer keeps. The
            // queue is untouched and still goes up; only the token is dropped,
            // and an empty one is what makes the next pull a full one.
            Logger.log("calendar", "sync full resync");
            root.retryingFull = true;
            root.startPull("");
            return;
        }
        root.retryingFull = false;

        if (plan.toPush.length > 0) {
            root.startPush(plan.toPush);
            return;
        }
        root.settle();
    }

    // --- the push ------------------------------------------------------------------

    function startPush(operations: var): void {
        const ops = [];
        const byId = function (id) { return root.contactById(id); };
        for (const step of operations) {
            const op = { "id": step.id, "op": step.op, "googleId": step.googleId };
            if (step.op !== "delete")
                op.body = root.mapping.toGoogle(step.event, root.zone, byId);
            ops.push(op);
        }
        push.command = root.helperCommand(["push", "--calendar", root.calendarId, "--stdin"]);
        push.pending = ops;
        push.running = true;
    }

    function finishPush(exitCode: int, text: string): void {
        if (root.failed(exitCode, pushErr.text))
            return;

        const answer = root.parse(text);
        if (!answer) {
            root.fail("bad-json", "the helper's push was not JSON");
            return;
        }
        const results = Array.isArray(answer.results) ? answer.results : [];
        for (const result of results)
            Logger.log("calendar", "sync push " + result.id
                       + (result.ok === true ? " ok" : " failed"));

        // The store may have moved while the push was in flight, so only the
        // events the answer actually stamped are written back — the whole list
        // `markPushed` returns would carry a snapshot over the top of an edit
        // made a moment ago.
        const before = root.store.events;
        const folded = root.policy.markPushed(before, root.state, results);
        const changed = [];
        for (let i = 0; i < folded.events.length; i++)
            if (folded.events[i] !== before[i])
                changed.push(folded.events[i]);
        if (changed.length > 0)
            root.store.applyRemote(changed, []);

        root.state = folded.newState;
        root.persist();
        root.settle();
    }

    // --- endings ---------------------------------------------------------------

    /// True when the run failed, having already said so. `3` is the helper's
    /// "this account is not connected", which is a state and not an error: it is
    /// what a shell says when nobody has run the consent flow yet, and retrying
    /// it on a backoff would be a subprocess every few seconds forever.
    function failed(exitCode: int, complaint: string): bool {
        if (exitCode === 0)
            return false;
        if (exitCode === 3) {
            Logger.log("calendar", "sync auth needed");
            root.status = "auth";
            root.lastError = "not connected";
            root.busy = false;
            root.retryingFull = false;
            return true;
        }
        root.fail(String(exitCode), complaint);
        return true;
    }

    function fail(code: string, complaint: string): void {
        Logger.warn("calendar", "sync error " + code);
        root.status = "error";
        root.lastError = (complaint || "").trim().split("\n").pop() || ("exit " + code);
        root.attempt += 1;
        root.busy = false;
        root.retryingFull = false;
        retry.interval = root.policy.backoffMs(root.attempt);
        retry.restart();
    }

    function settle(): void {
        root.attempt = 0;
        root.busy = false;
        root.status = "idle";
        root.lastSync = root.store.nowStamp();
        retry.stop();
        Logger.log("calendar", "sync idle " + root.lastSync);
    }

    function parse(text: string): var {
        try {
            const obj = JSON.parse(text || "");
            return (obj && typeof obj === "object") ? obj : null;
        } catch (error) {
            return null;
        }
    }

    // --- persistence -------------------------------------------------------------

    function persist(): void {
        stateWriteTimer.restart();
    }

    function writeState(): void {
        stateWriteTimer.stop();
        stateFile.setText(JSON.stringify({
            "version": 1,
            "syncToken": root.state.syncToken,
            "pendingOps": root.state.pendingOps
        }, null, 2) + "\n");
    }

    function readState(): void {
        const text = stateFile.text();
        const parsed = root.parse(text) || {};
        root.state = {
            "syncToken": typeof parsed.syncToken === "string" ? parsed.syncToken : "",
            "pendingOps": root.policy.dedupe(parsed.pendingOps)
        };
    }

    Component.onDestruction: {
        if (stateWriteTimer.running)
            root.writeState();
    }

    onEnabledChanged: {
        if (root.enabled) {
            if (root.status === "off")
                root.status = "idle";
        } else {
            root.status = "off";
            retry.stop();
        }
    }

    FileView {
        id: stateFile

        path: Paths.googleSyncFile
        atomicWrites: true
        // Blocking, for CalendarStore.qml's reason one file over: a round that
        // started before the queue was read would push an empty queue and then
        // write it over the real one. The file is small and read once.
        blockLoading: true
        printErrors: false
        // Not watched: this file has exactly one writer, and a watcher would
        // read our own write back in and replace a queue mid-round with the
        // version that was current when the write started.

        onLoaded: {
            try {
                root.readState();
            } catch (error) {
                Logger.warn("calendar", "ignoring " + Paths.googleSyncFile + ": " + error);
            }
        }

        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                Logger.warn("calendar", "could not read " + Paths.googleSyncFile + ": "
                            + FileViewError.toString(error));
        }

        onSaveFailed: error => {
            // Worth a warning and not a silence: what is lost is the queue, and
            // a queue lost on a machine that then goes offline is an edit that
            // never reaches the server.
            Logger.warn("calendar", "could not write " + Paths.googleSyncFile + ": "
                        + FileViewError.toString(error));
        }
    }

    Timer {
        id: stateWriteTimer
        interval: 250
        onTriggered: root.writeState()
    }

    // --- the triggers, as objects --------------------------------------------------

    Timer {
        id: rounds
        interval: Math.max(1, root.settings.intervalMin) * 60000
        repeat: true
        // Not `triggeredOnStart`: the shell's first seconds are the startup
        // budget #22 §5 measures, and a subprocess spawn is exactly what it
        // counts. The window opening is the trigger that matters to a person
        // anyway, and it fires long before this one would have.
        running: root.enabled
        onTriggered: root.sync()
    }

    Timer {
        id: debounce
        // Three seconds, because a drag is a stream of edits and each one
        // commits: pushing per commit would send a moved event once per frame it
        // crossed. Long enough to be one push, short enough that letting go of
        // an event and looking at your phone shows it there.
        interval: 3000
        onTriggered: root.sync()
    }

    Timer {
        id: retry
        interval: root.policy.backoffFirstMs
        onTriggered: root.sync()
    }

    Connections {
        target: root.store
        function onMutated(): void {
            if (root.enabled)
                debounce.restart();
        }
    }

    // --- the processes ---------------------------------------------------------------

    Process {
        id: pull
        stdout: StdioCollector { id: pullOut }
        stderr: StdioCollector { id: pullErr }
        onExited: exitCode => root.finishPull(exitCode, pullOut.text)
    }

    Process {
        id: push

        /// The ops this run is answering. Written to stdin once the process is
        /// up, because a `Process` has no stdin before it is running.
        property var pending: []

        stdinEnabled: true
        stdout: StdioCollector { id: pushOut }
        stderr: StdioCollector { id: pushErr }

        onRunningChanged: {
            if (!push.running)
                return;
            push.write(JSON.stringify(push.pending));
            // The helper reads stdin to EOF, so a stream left open is a helper
            // that never answers and a round that never ends.
            push.stdinEnabled = false;
        }

        onExited: exitCode => {
            push.stdinEnabled = true;
            root.finishPush(exitCode, pushOut.text);
        }
    }

    Process {
        id: auth
        stdout: StdioCollector { id: authOut }
        stderr: StdioCollector { id: authErr }

        onExited: exitCode => {
            if (exitCode !== 0) {
                Logger.warn("calendar", "sync error " + exitCode);
                root.status = "auth";
                root.lastError = "consent failed";
                return;
            }
            const answer = root.parse(authOut.text) || {};
            // The address, and nothing else the token file holds.
            Logger.log("calendar", "sync connected "
                       + (typeof answer.email === "string" && answer.email.length > 0
                          ? answer.email : "(no address reported)"));
            root.status = root.enabled ? "idle" : "off";
            root.lastError = "";
            if (root.enabled)
                root.sync();
        }
    }

    Component.onCompleted: {
        // Forcing the read here rather than letting it happen whenever: a round
        // that started before the queue was read would push an empty queue and
        // then persist it over the real one.
        stateFile.text();
        root.status = root.enabled ? "idle" : "off";
        Logger.stage("calendar sync armed (" + (root.enabled ? "on" : "off")
                     + ", helper " + root.helper + ")");
    }
}
