// One spec-table-backed JSON file (#12 §5, #21, #33).
//
// `settings.json` and `state.json` are the same component with a different
// schema — this is the only place the config engine touches the disk, and it is
// deliberately thin: every decision about what a file *means* lives in the pure
// files next to it (Core/SpecStore.qml, Core/Migrations.qml), where tests can
// reach it without a Quickshell runtime.
//
// The four behaviours that are not obvious:
//
//   Reading is blocking for settings and lazy for state. Stage one has to hand
//   the wallpaper to the first frame (#12 §4), so `settings.json` is read
//   synchronously; state has no such claim and must not be on that path.
//
//   Migrations run before resolution, on the raw JSON, and write the file back
//   with a `.bak-vN` of what was there first. This is one of exactly two
//   reasons the shell ever rewrites a file the user owns (#21) — the other is
//   an explicit GUI action.
//
//   Writes are sparse and debounced: only keys that differ from their default
//   are written, unknown keys are carried through untouched, and a burst of
//   set() calls (a slider being dragged) is one atomic write.
//
//   Save → watch → reload is broken twice over. The watcher's reload is
//   debounced (an atomic write is a temp file plus a rename, so it arrives as
//   several inotify events), a reload whose text is still exactly what we last
//   wrote is skipped inside the save cooldown, and — the backstop that does not
//   depend on timing at all — a reload that resolves to the same values
//   dispatches nothing.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    // --- what the owning singleton supplies ---------------------------------
    required property string path
    required property QtObject schema
    // Log tag, and the word used in user-facing notices: "config" / "state".
    required property string label

    // Stage one reads block; everything else must not.
    property bool blocking: false

    property int reloadDebounceMs: 100
    property int writeDebounceMs: 250

    // How long after our own write a reload of identical text is assumed to be
    // that write coming back. Bounded rather than permanent so a hand edit that
    // lands in the same instant is never ignored for longer than this.
    property int saveCooldownMs: 2000

    // --- what consumers read ------------------------------------------------

    // Every leaf in the schema, resolved. Complete from construction: bindings
    // formed before the first read still see the defaults, never `undefined`.
    property var values: ({})

    // False until the first read settles — found, missing, or broken. Surfaces
    // gate content instantiation on this (#12 §4: no defaults-flash-then-snap).
    property bool ready: false

    signal reloaded()
    signal keyChanged(string path, var value, var previous)

    // The file as it is on disk, including every key this build does not know.
    // A sparse write starts from here, which is what preserves them.
    property var raw: ({})

    property string lastWrittenText: ""
    property string lastReadText: ""
    property bool hasRead: false
    property bool seeded: false
    property bool defaultsApplied: false

    // `values` cannot be initialised in a binding: with `blockLoading` the
    // FileView reads — and can fail, and seed — while this object is still
    // being constructed, so every entry point seeds the defaults itself rather
    // than assuming an ordering.
    function ensureDefaults() {
        if (root.defaultsApplied)
            return;
        root.defaultsApplied = true;
        root.values = store.defaults(root.schema.spec);
    }

    function get(path) {
        return store.getPath(root.values, path);
    }

    // Returns false when the key or the value is refused, so the GUI (#54) can
    // say so rather than silently doing nothing.
    function set(path, value) {
        const leaf = store.leafAt(root.schema.spec, path);
        if (!leaf) {
            Logger.warn(root.label, "no such key: " + path);
            return false;
        }

        const coerced = leaf.coerce ? leaf.coerce(value) : value;
        if (coerced === undefined) {
            Logger.warn(root.label, path + ": refusing " + JSON.stringify(value));
            return false;
        }

        const previous = store.getPath(root.values, path);
        if (store.equals(previous, coerced))
            return true;

        const next = store.json.deepCopy(root.values);
        store.setPath(next, path, coerced);
        root.values = next;

        dispatch(path, coerced, previous);
        writeTimer.restart();
        return true;
    }

    // Reset-to-default is deletion, not a write of the current default: the key
    // leaves the file, so a later change to the shipped default reaches the
    // user (#21).
    function reset(path) {
        const leaf = store.leafAt(root.schema.spec, path);
        if (!leaf) {
            Logger.warn(root.label, "no such key: " + path);
            return false;
        }
        if (!set(path, leaf.def))
            return false;

        // The value may already have *been* the default while the key was still
        // written out explicitly, in which case set() had nothing to change —
        // but clearing the key is the whole point of a reset.
        if (store.getPath(root.raw, path) !== undefined)
            writeTimer.restart();
        return true;
    }

    function flush() {
        if (writeTimer.running)
            write();
    }

    // --- reading ------------------------------------------------------------

    function readNow() {
        ensureDefaults();

        // Ignore a read that brings back bytes we have already taken in. This
        // is what stops the forced first read from being processed twice — the
        // FileView delivers its `loaded` signal *after* the blocking read has
        // already handed us the text — and it is exact rather than timed: text
        // identical to what we last read cannot mean anything new, whoever
        // triggered the read.
        const text = file.text();
        if (root.hasRead && text === root.lastReadText)
            return;
        root.hasRead = true;
        root.lastReadText = text;

        const parsed = store.json.parse(text);
        if (!parsed.ok) {
            // Last good values stay in place and the file is not touched — a
            // half-typed edit must not cost the user their config. (#42 turns
            // this into a notification; until then the log is the notice.)
            Logger.warn(root.label, "ignoring " + root.path + ": " + parsed.error
                        + " — keeping the last good " + root.label + ", file untouched");
            return;
        }
        apply(parsed.value);
    }

    function apply(rawValue) {
        const spec = root.schema.spec;
        const migrated = migrations.run(rawValue, root.schema.migrations,
                                        root.schema.versionKey, root.schema.version);
        const resolved = store.resolve(spec, migrated.raw);
        const before = root.values;
        const beforeRaw = root.raw;
        const changed = store.changedPaths(spec, before, resolved.values);

        root.raw = migrated.raw;
        root.values = resolved.values;

        for (const issue of resolved.issues)
            Logger.warn(root.label, issue.path + ": cannot use "
                        + JSON.stringify(issue.value) + " — using the default");

        // A migration that produces the file that is already there writes
        // nothing: the version bump alone is not a reason to touch a file the
        // user owns.
        if (migrated.to !== migrated.from && !store.equals(migrated.raw, beforeRaw)) {
            // The backup is taken from the text still on disk, before the
            // migrated file replaces it.
            if (migrated.rewritten)
                writeBackup(migrated.from, file.text());
            Logger.log(root.label, "migrated " + root.path + " v" + migrated.from
                       + " to v" + migrated.to
                       + (migrated.applied.length > 0 ? " (" + migrated.applied.join("; ") + ")" : ""));
            write();
        }

        // Nothing is dispatched for the first read: consumers are constructed
        // after it and read `values` directly. Only later reloads are changes.
        if (!root.ready || changed.length === 0)
            return;

        for (const path of changed)
            dispatch(path, store.getPath(root.values, path), store.getPath(before, path));

        Logger.log(root.label, "reloaded " + root.path + " (" + changed.length + " key(s) changed)");
        root.reloaded();
    }

    function dispatch(path, value, previous) {
        const leaf = store.leafAt(root.schema.spec, path);
        if (leaf && leaf.onChange)
            leaf.onChange(value, previous, path);
        root.keyChanged(path, value, previous);
    }

    function settle() {
        if (root.ready)
            return;
        ensureDefaults();
        root.ready = true;
        root.reloaded();
    }

    // --- writing ------------------------------------------------------------

    function write() {
        writeTimer.stop();
        ensureDefaults();

        let out = store.serialize(root.schema.spec, root.values, root.raw);
        const versionKey = root.schema.versionKey;
        if (typeof out[versionKey] !== "number") {
            // Stamp first, so a file opened by hand leads with the version it
            // was written for.
            const stamped = {};
            stamped[versionKey] = root.schema.version;
            for (const key in out)
                stamped[key] = out[key];
            out = stamped;
        }

        root.raw = out;
        root.lastWrittenText = JSON.stringify(out, null, 2) + "\n";
        cooldownTimer.restart();
        file.setText(root.lastWrittenText);
    }

    function writeBackup(fromVersion, text) {
        backupFile.path = root.path + ".bak-v" + fromVersion;
        backupFile.setText(text);
        Logger.log(root.label, "kept the pre-migration file as " + backupFile.path);
    }

    // A missing file is the normal first run: write the stamp so there is
    // something to hand-edit, and so the version is anchored before any
    // migration can think this is an ancient file.
    function seed() {
        if (root.seeded)
            return;
        root.seeded = true;
        Logger.log(root.label, "no " + root.path + " yet — seeding it");
        makeDir.running = true;
    }

    Component.onCompleted: {
        ensureDefaults();
        if (!root.blocking) {
            // The read is in flight; onLoaded or onLoadFailed settles this.
            return;
        }

        // `blockLoading` does not read eagerly — asking for the text is what
        // forces the read, and `loaded` is false until something does. Any
        // failure signal fires inside this call, so by the line after it the
        // answer is final either way, and stage one is not left waiting on a
        // config file that is never coming.
        file.text();
        if (file.loaded)
            readNow();
        settle();
    }

    // A debounced write still pending when the shell reloads or quits would be
    // lost — and for state.json that is the tab the user just opened.
    Component.onDestruction: flush()

    SpecStore { id: store }
    Migrations { id: migrations }

    FileView {
        id: file

        path: root.path
        blockLoading: root.blocking
        watchChanges: true
        atomicWrites: true
        printErrors: false   // a missing file is the normal first run

        onFileChanged: reloadTimer.restart()

        onLoaded: {
            if (cooldownTimer.running && file.text() === root.lastWrittenText)
                return;   // our own write, arriving back through the watcher
            root.readNow();
            root.settle();
        }

        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.seed();
            else
                Logger.warn(root.label, "could not read " + root.path + ": "
                            + FileViewError.toString(error));
            root.settle();
        }

        onSaveFailed: error => {
            Logger.warn(root.label, "could not write " + root.path + ": "
                        + FileViewError.toString(error));
        }
    }

    // Separate view: writing the backup through `file` would point the watcher
    // at the wrong path.
    FileView {
        id: backupFile
        atomicWrites: true
        printErrors: false
    }

    Timer {
        id: reloadTimer
        interval: root.reloadDebounceMs
        onTriggered: file.reload()
    }

    Timer {
        id: writeTimer
        interval: root.writeDebounceMs
        onTriggered: root.write()
    }

    Timer {
        id: cooldownTimer
        interval: root.saveCooldownMs
    }

    // FileView writes the file, not the directory above it. This runs once per
    // machine, on the first run that finds no config at all.
    Process {
        id: makeDir
        command: ["mkdir", "-p", root.path.slice(0, root.path.lastIndexOf("/"))]
        onExited: root.write()
    }
}
