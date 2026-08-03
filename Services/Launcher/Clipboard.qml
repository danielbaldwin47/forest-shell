pragma Singleton

// The clipboard-history provider (#53) — `cliphist`'s database, as launcher
// rows, and Enter putting one of them back on the selection.
//
//     Clipboard.ask(query, routed)     what is being asked, and whether it is us
//     Clipboard.rows(query)            what the launcher should show
//     Clipboard.silence(query)         what it says when that is empty
//     Clipboard.copyEntry(row)         Enter
//
// The decisions are ClipboardPolicy.qml next door, where `tests/` can reach
// them: the parse, the ranking, the three argvs, the four silences. What is
// here is the part that needs Quickshell — four `Process`es, a cache directory
// full of decoded pictures, and the distinction between an absent binary and an
// empty history.
//
// ## The listing is the probe
//
// CalculatorPolicy spends a process at startup asking whether `qalc` exists,
// because the answer is needed before the first sum and a version probe is
// cheaper than an evaluation. Here the two questions have the same answer:
// `cliphist list` exits 0 with the history on stdout, or never starts at all.
// So there is one run at startup, and it is both the probe and the first
// listing — which also means the first `;` shows rows immediately rather than
// spawning something and spinning.
//
// A spawn that never happened emits **no `exited` signal** on Quickshell
// 0.3.0 — only `running` going false — so `started` is tracked for the reason
// Calculator.qml's header sets out. It matters more here than there: an absent
// `cliphist` and an empty history both produce zero bytes on stdout, so output
// can never be the test (#78, and the ticket's own maintenance pass).
//
// ## When it re-reads
//
// On becoming the routed provider, and not per keystroke. The history changes
// outside this shell — every copy in every application writes it — so a list
// cached for the session would go stale within a minute. But a list per
// keystroke is a fork per keystroke on the launcher's 60 Hz path, which is the
// cost #40 built the calculator's debounce to avoid. Opening the room is the
// event worth re-reading on: typing `;` is exactly when the user is about to
// look, and filtering after that is done against what was there when they
// looked.
//
// ## Thumbnails
//
// A picture only exists as bytes inside cliphist's database, so a thumbnail is
// a decode to a file — one process per image, capped per query, cached by id.
// They arrive *after* the rows do, which is deliberate: a list that waited for
// twelve decodes before drawing anything would be a `;` that hangs, and the
// rows are useful with a placeholder icon on them.
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    readonly property ClipboardPolicy policy: ClipboardPolicy {}

    /// Whether `cliphist` is on the machine. Optimistic until the first listing
    /// answers, so the first frames do not accuse a machine that has it.
    property bool available: true
    property bool probed: false

    /// The history as of the last listing, newest first and deduped.
    property var entries: []
    readonly property int count: root.entries.length

    /// The last listing ran and came back broken — distinct from `available`,
    /// which is about the binary existing, and distinct from an empty history,
    /// which is a listing that worked. `failedCode` is what it exited with, and
    /// is the only thing the sentence can say.
    property bool failed: false
    property int failedCode: 0

    /// Decoded pictures, `{ [id]: fileUrl }`. Replaced rather than mutated on
    /// each arrival — a `var` map edited in place changes no binding, so the
    /// rows would keep their placeholder icons until something else happened to
    /// re-evaluate them.
    property var thumbnails: ({})

    /// What the launcher is asking, and whether it is asking *us*. Kept because
    /// the thumbnail queue is a function of the query and not of the history:
    /// only the rows a query actually matched are worth decoding.
    property string query: ""
    property bool routed: false

    readonly property bool pending: lister.running

    // --- asking --------------------------------------------------------------

    /// Tell the provider what is being asked. Called from Providers.prime() on
    /// every query change, which is once per keystroke.
    ///
    /// The re-read is gated on *becoming* routed rather than on being routed —
    /// see the header. Everything else here is filtering against a list already
    /// in memory, which costs no process.
    function ask(text: string, isRouted: bool): void {
        const was = root.routed;
        root.routed = isRouted === true;
        root.query = root.routed ? String(text ?? "") : "";

        if (!root.routed || !root.available)
            return;
        if (!was)
            root.refresh();

        root.enqueueThumbnails();
    }

    /// The rows for a query, thumbnails filled in.
    function rows(text: string): var {
        return root.policy.rows(root.entries, text, root.thumbnails);
    }

    /// What to say instead of rows. The provider's own state, handed to the
    /// policy — see `LauncherPolicy.empty()` for where this ends up.
    function silence(text: string): var {
        return root.policy.silence(text, {
            available: root.available,
            probed: root.probed,
            pending: root.pending,
            failed: root.failed,
            exitCode: root.failedCode,
            count: root.count
        });
    }

    // --- reading the history -------------------------------------------------

    /// Re-read the history. Skipped while a read is in flight rather than
    /// queued behind it: the answer to "what is in the clipboard now" does not
    /// improve by being asked twice in the same frame, and the run already out
    /// is about to answer it.
    function refresh(): void {
        if (lister.running)
            return;
        lister.started = false;
        lister.command = root.policy.listArgv();
        lister.running = true;
    }

    Process {
        id: lister

        /// Whether the process ever got as far as existing. See the header.
        property bool started: false

        stdout: StdioCollector { id: listed }
        stderr: StdioCollector { id: listedErr }

        onStarted: lister.started = true

        onExited: (exitCode, exitStatus) => {
            // It exited, so it exists. That is the only thing the exit code is
            // *not* asked about — see the header: `cliphist list` exits 1 on a
            // store that has never been written, and reading that as an absent
            // binary tells a fresh machine to install what it already has.
            root.probed = true;
            root.available = true;

            if (!root.policy.accepted(exitCode)) {
                root.entries = [];
                root.failed = !root.policy.emptyStore(listedErr.text);
                root.failedCode = exitCode;
                if (root.failed)
                    Logger.warn("launcher", root.policy.listFailed(exitCode));
                else
                    Logger.log("launcher", root.policy.listed(0));
                return;
            }

            root.failed = false;
            root.entries = root.policy.dedupe(root.policy.parse(listed.text));
            Logger.log("launcher", root.policy.listed(root.count));
            root.enqueueThumbnails();
        }

        onRunningChanged: {
            // False without ever having started: the binary is not there. The
            // one case with no exit code to read, and the reason this handler
            // exists at all.
            if (lister.running || lister.started)
                return;
            root.available = false;
            root.probed = true;
            root.entries = [];
            Logger.warn("launcher", root.policy.absent());
        }
    }

    // --- Enter ---------------------------------------------------------------

    /// Put an entry back on the selection. Returns whether the launcher should
    /// close, which is always: the work outlives the surface, because the
    /// process belongs to this singleton and not to the row that started it.
    ///
    /// Two paths, and the split is the whole of why this is not
    /// `Providers.copy()`. Text goes through `Quickshell.clipboardText` — the
    /// compositor's own selection, no process, the argument Providers.qml makes.
    /// An image cannot: the bytes would have to pass through a QML string on the
    /// way, which decodes them as UTF-8 and re-encodes them, and what reached
    /// the clipboard would not be the picture. So a picture is piped, in a shell,
    /// with the id as an argument rather than as syntax (`ClipboardPolicy.copyArgv`).
    function copyEntry(row: var): bool {
        const id = String((row ?? {}).entryId ?? "");
        const entry = root.entryFor(id);

        if (!entry) {
            // The history moved under the launcher — a wipe, or the ring buffer
            // rolling over between the keystroke and the Enter. Rare and real,
            // and the same shape as the apps provider's stale desktop entry.
            Logger.warn("launcher", "no clipboard entry " + id + " any more");
            return false;
        }

        if (entry.image) {
            copier.queued = entry;
            copier.start();
            return true;
        }

        decoder.queued = entry;
        decoder.start();
        return true;
    }

    function entryFor(id: string): var {
        if (!root.policy.validId(id))
            return null;
        return root.entries.find(entry => entry.id === String(id)) ?? null;
    }

    /// The text path: decode to stdout, and hand what comes back to the
    /// compositor.
    Process {
        id: decoder

        /// The entry this run is for. Kept for the reason Calculator.qml keeps
        /// its expression: the reply arrives after the fact and says nothing
        /// about which question it answers.
        property var queued: null
        property var asked: null

        stdout: StdioCollector { id: decoded }

        function start(): void {
            // A run already out is allowed to finish. Assigning a command to a
            // running `Process` kills it (Services/Compositor/Compositor.qml),
            // and a half-decoded entry on the clipboard is worse than a copy
            // that lands 20 ms late.
            if (decoder.running)
                return;
            const entry = decoder.queued;
            decoder.queued = null;
            if (!entry)
                return;
            decoder.asked = entry;
            decoder.command = root.policy.decodeArgv(entry.id);
            decoder.running = true;
        }

        onExited: (exitCode, exitStatus) => {
            const entry = decoder.asked;
            decoder.asked = null;

            if (!root.policy.accepted(exitCode)) {
                Logger.warn("launcher",
                            root.policy.decodeFailed(entry ? entry.id : "", exitCode));
            } else {
                Quickshell.clipboardText = decoded.text;
                Logger.log("launcher", root.policy.copied(entry));
            }

            decoder.start();
        }

        onRunningChanged: {
            // `cliphist` gone since the listing — uninstalled mid-session, or a
            // PATH that changed under the shell. Without this the copy would
            // fail in perfect silence, which is the one outcome this provider is
            // built not to have (#78).
            if (decoder.running || decoder.asked === null)
                return;
            decoder.asked = null;
            root.available = false;
            Logger.warn("launcher", root.policy.absent());
            decoder.start();
        }
    }

    /// The image path: decode, piped into `wl-copy` with a MIME type on it.
    ///
    /// Nothing is read back. `wl-copy` forks and stays alive to serve the
    /// offer — that is how the Wayland data-device protocol works, and it is why
    /// the *text* path does not use it — so this process exiting says the
    /// handoff happened, not that the paste did.
    Process {
        id: copier

        property var queued: null
        property var asked: null

        function start(): void {
            if (copier.running)
                return;
            const entry = copier.queued;
            copier.queued = null;
            if (!entry)
                return;
            copier.asked = entry;
            copier.command = root.policy.copyArgv(entry.id, entry.format);
            copier.running = true;
        }

        onExited: (exitCode, exitStatus) => {
            const entry = copier.asked;
            copier.asked = null;

            if (root.policy.accepted(exitCode))
                Logger.log("launcher", root.policy.copied(entry));
            else
                Logger.warn("launcher",
                            root.policy.copyFailed(entry ? entry.id : "", exitCode));

            copier.start();
        }

        onRunningChanged: {
            // The other two handlers' case, and it means something different
            // here. This command is `sh`, so a spawn that never happens is a
            // machine with no shell rather than one with no `cliphist` — a
            // missing `cliphist` or `wl-copy` is *inside* the pipe and comes
            // back as exit 127 through `onExited` above. So `available` is left
            // alone; what this is for is the state, which would otherwise
            // strand `asked` and leave the next Enter queued behind a run that
            // already ended.
            if (copier.running || copier.asked === null)
                return;
            const entry = copier.asked;
            copier.asked = null;
            Logger.warn("launcher", root.policy.copyFailed(entry ? entry.id : "", -1));
            copier.start();
        }
    }

    // --- thumbnails ----------------------------------------------------------

    /// Which pictures the current query wants, queued. Only the entries the
    /// query actually matched: `;` on a two-hundred-entry history shows twelve
    /// rows, and decoding the other hundred and eighty would be a hundred and
    /// eighty forks for pictures nobody is looking at.
    property var queue: []

    function enqueueThumbnails(): void {
        if (!root.routed || !root.available)
            return;

        const matched = root.policy.search(root.entries, root.query);
        const wanted = root.policy.thumbnailQueue(matched, root.thumbnails);
        if (wanted.length === 0)
            return;

        const known = {};
        for (const entry of root.queue)
            known[entry.id] = true;

        const next = root.queue.slice();
        for (const entry of wanted) {
            if (known[entry.id] !== true)
                next.push(entry);
        }
        root.queue = next;
        thumbnailer.start();
    }

    Process {
        id: thumbnailer

        property var asked: null
        property string path: ""

        function start(): void {
            if (thumbnailer.running || root.queue.length === 0)
                return;

            const next = root.queue.slice();
            const entry = next.shift();
            root.queue = next;

            const path = root.policy.thumbnailPath(Paths.clipboardDir, entry);
            if (path === "") {
                thumbnailer.start();
                return;
            }

            thumbnailer.asked = entry;
            thumbnailer.path = path;
            thumbnailer.command = root.policy.thumbnailArgv(entry.id, path);
            thumbnailer.running = true;
        }

        onExited: (exitCode, exitStatus) => {
            const entry = thumbnailer.asked;
            const path = thumbnailer.path;
            thumbnailer.asked = null;
            thumbnailer.path = "";

            if (entry && root.policy.accepted(exitCode)) {
                // A new object rather than an edit: see `thumbnails` above.
                const next = Object.assign({}, root.thumbnails);
                next[entry.id] = Paths.fileUrl(path);
                root.thumbnails = next;
                Logger.log("launcher", root.policy.thumbnailed(entry.id, path));
            } else if (entry) {
                Logger.warn("launcher", root.policy.decodeFailed(entry.id, exitCode));
            }

            thumbnailer.start();
        }

        onRunningChanged: {
            // The decode's own version of the lister's handler. Without it a
            // machine that lost `cliphist` mid-session would leave a queue that
            // never drains and a row that never gets its picture.
            if (thumbnailer.running || thumbnailer.asked === null)
                return;
            thumbnailer.asked = null;
            thumbnailer.path = "";
            thumbnailer.start();
        }
    }

    // --- coming up -----------------------------------------------------------

    Component.onCompleted: {
        // The probe and the first listing, in one run. See the header.
        root.refresh();
        Logger.stage("clipboard provider armed");
    }
}
