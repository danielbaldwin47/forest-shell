pragma Singleton

// Theme presets — the half that knows what a directory is (#56, #26).
//
//     Themes.entries          // [{ name, path, applied, drifted }], ready to draw
//     Themes.save("Nord")     // the current skin, as ~/.config/forest-shell/themes/Nord.json
//     Themes.apply("Nord")    // copies its keys into settings.json
//     Themes.apply(Themes.policy.defaultName)   // "Forest (default)" — deletes them
//     Themes.undo()           // "Previous settings" — back to just before the last apply
//     Themes.remove("Nord")   // deletes the file, never the settings
//
// Every decision is in Core/ThemePolicy.qml where tests/ can reach it; this
// file is the listing, the four file operations and the log.
//
// ## Apply is a copy, and the copy goes through `Config.set`
//
// There is no live link. A theme is read once, its keys are handed to the
// config engine one at a time, and after that nothing in the shell knows the
// file existed — editing `Nord.json` afterwards changes nothing until it is
// applied again, and editing `settings.json` afterwards is not a change *to*
// Nord. `ShellState`'s `theme.lastApplied` is the only trace, and it is a label
// rather than a link: the list stops ticking a theme the moment a knob moves.
//
// Going through `Config.set` rather than writing the file is what makes the
// guarantees true by construction rather than restated here: the group coercers
// clamp a bar opacity a theme carries below #79's floor, keys this build does
// not know survive inside a group, the write is sparse, and a burst of sets is
// one atomic write. A theme that names a key the schema does not have is
// refused key by key, and says so.
//
// ## What a save captures
//
// The skin the shell is wearing, sparsely: only what differs from the shipped
// defaults, which is exactly what `settings.json` itself holds. A theme is
// therefore a *fragment* and never a whole config — it cannot carry a bar
// height across, and it cannot freeze a knob nobody touched at today's default
// (#21: a later change to a shipped default must still reach the user).
//
// `pragma Singleton` leads the file for the reason Core/Config.qml explains.
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property ThemePolicy policy: ThemePolicy {}

    /// The safe parse the config engine reads its own files with — `{ ok, value,
    /// error }`, so a hand-written theme fails the way a hand-written
    /// settings.json does. Named here rather than walked to at each call site,
    /// which is three objects deep.
    readonly property QtObject json: root.policy.store.json

    /// The saved themes, ready to draw. The two built-in entries — "Forest
    /// (default)" and "Previous settings" — are not in here: they are not files,
    /// and the surface draws them as what they are.
    property var entries: []

    /// Which preset the shell is wearing. A breadcrumb in the state file, not a
    /// link (see the header).
    ///
    /// A shell that has never been told reads as the shipped look, which is what
    /// it is: nothing named it, so the only theme it can be wearing is the one
    /// that is the absence of the others — and if it has drifted from that, the
    /// drift mark below is exactly the right thing to say about it.
    readonly property string applied: {
        const name = ShellState.values.theme?.lastApplied ?? "";
        return name === "" ? root.policy.defaultName : name;
    }

    /// What applying the current theme would do — held so that the drift check
    /// below does not re-migrate and re-plan the same file on every keystroke a
    /// settings control writes.
    readonly property var appliedPlan: {
        if (root.applied === root.policy.defaultName)
            return root.policy.plan(Config.schema, root.policy.defaultFile(Config.schema));
        if (root.appliedText === "")
            return null;   // the theme was deleted, or is not readable
        const parsed = root.json.parse(root.appliedText);
        return parsed.ok ? root.policy.plan(Config.schema, parsed.value) : null;
    }

    /// Whether the settings have moved since that theme was applied. What keeps
    /// the tick honest: a knob nudged afterwards — in the GUI or by hand — means
    /// the shell is no longer wearing that theme.
    ///
    /// Judged against the shell's *resolved* values, which is the only reading
    /// that survives an apply: a theme is copied through the config engine, so
    /// what lands is coerced and written sparsely and is not the theme file byte
    /// for byte (Core/ThemePolicy.qml `wears`).
    readonly property bool drifted: {
        if (root.appliedPlan === null)
            return false;
        return !root.policy.wears(Config.schema, Config.values, root.appliedPlan);
    }

    /// Whether there is anything to undo. The slot is written on every apply, so
    /// this is false only until the first one.
    readonly property bool canUndo: root.undoText !== ""

    /// The shell's skin as it stands, in theme-file form. Live, so a control
    /// that has just written a value is already in it.
    function current(): var {
        return root.policy.snapshot(Config.schema, Config.values, Config.raw);
    }

    // --- saving ---------------------------------------------------------------

    /// Saves the current skin under a name. False when the name is refused —
    /// the GUI shows why, and so does the log (#78: a write that failed and said
    /// nothing is the shape of bug that costs a session).
    function save(name: string): bool {
        const why = root.policy.refusal(name);
        if (why !== "") {
            Logger.warn("theme", root.policy.refusedLine(name, why));
            return false;
        }

        const clean = String(name).trim();
        const file = root.current();
        root.writeFile(root.themePath(clean), file);
        Logger.log("theme", root.policy.savedLine(clean,
                                                  root.policy.carriedCount(Config.schema, file)));

        // Saving the current look *is* being on that theme: the file and the
        // settings are identical by construction at this instant.
        ShellState.set("theme.lastApplied", clean);
        return true;
    }

    // --- applying -------------------------------------------------------------

    /// Applies a theme by name. The two built-in names work here too, so the
    /// list has one verb: `policy.defaultName` restores the shipped look by
    /// deleting the flagged keys, and `policy.undoName` is the undo slot.
    function apply(name: string): bool {
        const wanted = String(name ?? "").trim();
        if (wanted === root.policy.undoName)
            return root.undo();

        let file = null;
        let label = wanted;

        if (wanted === "" || wanted === root.policy.defaultName) {
            file = root.policy.defaultFile(Config.schema);
            label = root.policy.defaultName;
        } else {
            const why = root.policy.refusal(wanted);
            if (why !== "") {
                Logger.warn("theme", root.policy.refusedLine(wanted, why));
                return false;
            }
            const read = root.readFile(root.themePath(wanted));
            if (!read.ok) {
                Logger.warn("theme", root.policy.refusedLine(wanted, read.error));
                return false;
            }
            file = read.value;
        }

        return root.applyFile(file, label, "");
    }

    /// Back to the skin as it was just before the last apply.
    ///
    /// Undo is itself an apply, snapshot and all — so pressing it twice returns
    /// you, and the slot is always "the other one" rather than a stack that can
    /// be walked off the end of.
    function undo(): bool {
        if (!root.canUndo) {
            Logger.warn("theme", root.policy.refusedLine(root.policy.undoName,
                                                         "nothing has been applied yet"));
            return false;
        }
        const parsed = root.json.parse(root.undoText);
        if (!parsed.ok) {
            Logger.warn("theme", root.policy.refusedLine(root.policy.undoName, parsed.error));
            return false;
        }
        // The slot carries the label the shell wore at the time, so undoing an
        // apply puts the *name* back as well as the keys. A slot hand-edited to
        // carry something that is not a name falls back to the shipped look's,
        // which is what an unnamed skin is.
        const was = typeof parsed.value.themeName === "string" ? parsed.value.themeName : "";
        return root.applyFile(parsed.value,
                              was === "" ? root.policy.defaultName : was,
                              root.policy.undoName);
    }

    /// The one path every apply takes: snapshot, plan, write, breadcrumb, log.
    function applyFile(file: var, label: string, spokenAs: string): bool {
        const planned = root.policy.plan(Config.schema, file);
        if (!planned.ok) {
            Logger.warn("theme", root.policy.refusedLine(spokenAs ? spokenAs : label,
                                                         planned.error));
            return false;
        }

        // Taken before the first write and from the live values, so the slot
        // holds the skin the user is looking at — not the file, which the config
        // engine has up to a debounce still to write.
        root.snapshotUndo();

        let writes = 0;
        let resets = 0;
        let refused = 0;
        for (const op of planned.ops) {
            const ok = op.reset ? Config.reset(op.path) : Config.set(op.path, op.value);
            if (!ok)
                refused++;
            else if (op.reset)
                resets++;
            else
                writes++;
        }

        if (planned.applied.length > 0)
            Logger.log("theme", "migrated \"" + label + "\" v" + planned.from + " to v"
                       + planned.to + " (" + planned.applied.join("; ") + ")");

        Logger.log("theme", root.policy.appliedLine(spokenAs ? spokenAs : label, writes, resets)
                   + (refused > 0 ? " — " + refused + " key(s) the config refused" : ""));

        // The shipped look is written out by name rather than as an empty
        // string: "I chose the default" and "nobody has ever chosen" are the
        // same look and read the same in the list, but only one of them is a
        // thing the user did, and the state file is where that is recorded.
        ShellState.set("theme.lastApplied", label);
        return true;
    }

    function snapshotUndo(): void {
        const file = root.current();
        // Not a settings key, and deliberately outside the fragment: the plan
        // only ever reads the paths the schema flags, so this rides along
        // without being applied to anything.
        file.themeName = root.applied;
        root.writeUndoFile(file);
    }

    // --- deleting -------------------------------------------------------------

    /// Deletes a theme file. The settings are untouched — deleting the theme you
    /// are wearing does not undress the shell, it only takes the name away.
    function remove(name: string): bool {
        const why = root.policy.refusal(name);
        if (why !== "") {
            Logger.warn("theme", root.policy.refusedLine(name, why));
            return false;
        }

        const clean = String(name).trim();
        // No `-f`: a delete that removed nothing must not report a deletion.
        // `rm` answers non-zero for a file that was not there, and that answer
        // is the difference between "gone" and "was never here" (#78).
        remover.command = ["rm", "--", root.themePath(clean)];
        remover.removing = clean;
        remover.running = true;
        return true;
    }

    // --- files ----------------------------------------------------------------

    /// Where a theme lives, or "" for a name that has no file — which is what a
    /// refused name is. Never `themesDir + "/"`: pointing a FileView at the
    /// directory itself is a read that fails in a way that reads like a missing
    /// theme, and a write that fails in a way that reads like nothing at all.
    function themePath(name: string): string {
        const file = root.policy.fileName(name);
        return file === "" ? "" : Paths.themesDir + "/" + file;
    }

    /// `{ ok, value, error }`, the same shape the config engine's parse returns.
    /// Blocking, and allowed to be: this is one small file read in answer to a
    /// press, on no critical path (#12 §4 is about the first frame).
    function readFile(path: string): var {
        // Cleared first so that reading the same path twice re-reads it: a theme
        // edited by hand between two applies is a theme that changed.
        reader.path = "";
        reader.path = path;
        const text = reader.text();
        if (!reader.loaded)
            return { ok: false, value: null, error: "cannot read " + path };
        return root.json.parse(text);
    }

    /// A theme on disk, formatted like every other file the shell writes:
    /// two-space JSON with a trailing newline, so a hand-editor and the shell
    /// produce the same diff.
    function encode(object: var): string {
        return JSON.stringify(object, null, 2) + "\n";
    }

    /// Writes a theme file, once there is a directory to write it into. The
    /// directories are made at construction, so the queue below only ever holds
    /// a press made in the first frames of a session.
    ///
    /// Deliberately not the path the undo slot takes: that has a `FileView` of
    /// its own, so the two writes an apply issues in the same tick are never two
    /// paths through one view. Core/SpecFile.qml draws the same line in its own
    /// words — *"writing the backup through `file` would point the watcher at
    /// the wrong path"*.
    function writeFile(path: string, object: var): void {
        if (path === "")
            return;
        if (!root.dirsMade) {
            root.pending.push({ path: path, text: root.encode(object) });
            return;
        }
        writer.path = path;
        writer.setText(root.encode(object));
        root.refreshListing();
    }

    function writeUndoFile(object: var): void {
        const text = root.encode(object);
        // Held as well as written, because the watcher cannot see a file that
        // did not exist when it started: on a machine whose first apply
        // *creates* the slot, `undoFile` has already failed to load and nothing
        // brings it back — so the undo button would stay dead for the rest of
        // the session, which is the #81 shape (measured in
        // tools/theme-harness.sh before this line existed).
        root.undoText = text;
        if (!root.dirsMade) {
            root.pendingUndo = text;
            return;
        }
        undoFile.setText(text);
    }

    function flushPending(): void {
        for (const item of root.pending) {
            writer.path = item.path;
            writer.setText(item.text);
        }
        root.pending = [];
        if (root.pendingUndo !== "") {
            undoFile.setText(root.pendingUndo);
            root.pendingUndo = "";
        }
        root.refreshListing();
    }

    /// Re-scans the themes directory. Needed because the model cannot watch a
    /// directory that does not exist, and on a fresh machine it does not: the
    /// folder is made by the first save, and without this the theme that made it
    /// would not appear in the list until the next start.
    function refreshListing(): void {
        listing.folder = "";
        listing.folder = Paths.fileUrl(Paths.themesDir);
    }

    property var pending: []
    property string pendingUndo: ""
    property bool dirsMade: false

    // The undo slot's text, kept live so the button knows whether there is
    // anything behind it.
    property string undoText: ""

    // The applied theme's file, for the drift mark. Reloaded when the file
    // changes, so hand-editing the theme you are wearing shows up as drift
    // rather than as a stale tick.
    property string appliedText: ""

    // --- the listing ----------------------------------------------------------

    FolderListModel {
        id: listing

        folder: Paths.fileUrl(Paths.themesDir)
        nameFilters: ["*.json"]
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name

        function rebuild(): void {
            const files = [];
            for (let i = 0; i < listing.count; i++)
                files.push({ path: listing.get(i, "filePath") });
            root.entries = root.policy.entries(files, root.applied, root.drifted);
        }

        onCountChanged: listing.rebuild()
        onStatusChanged: if (status === FolderListModel.Ready) listing.rebuild();
    }

    // The tick and the drift mark are properties of the rows, so the list is
    // rebuilt when either moves.
    onAppliedChanged: listing.rebuild()
    onDriftedChanged: listing.rebuild()

    // --- the files themselves -------------------------------------------------

    FileView {
        id: reader

        blockLoading: true
        watchChanges: false
        printErrors: false   // a missing theme is a refusal, not a crash
    }

    FileView {
        id: writer

        atomicWrites: true
        printErrors: false

        onSaveFailed: error => Logger.warn("theme", "could not write " + writer.path + ": "
                                           + FileViewError.toString(error))
    }

    // The slot's own view, which is also the one that writes it — its path never
    // moves, so it is the one file in here a shared writer could not serve.
    FileView {
        id: undoFile

        path: Paths.previousThemeFile
        atomicWrites: true
        watchChanges: true
        printErrors: false   // absent until the first apply

        onLoaded: root.undoText = undoFile.text()
        onLoadFailed: root.undoText = ""
        onSaveFailed: error => Logger.warn("theme", "could not write " + undoFile.path + ": "
                                           + FileViewError.toString(error))
    }

    FileView {
        id: appliedFile

        // Empty for the shipped look, which is not a file — and for a breadcrumb
        // hand-edited into something that is not a name.
        path: root.applied === root.policy.defaultName ? "" : root.themePath(root.applied)
        watchChanges: true
        printErrors: false

        onLoaded: root.appliedText = appliedFile.text()
        onLoadFailed: root.appliedText = ""
    }

    // FileView writes files, not the directories above them. Both are made at
    // once: the state directory may be as absent as the themes one on a machine
    // whose first act is to save a theme.
    Process {
        id: makeDirs

        command: ["mkdir", "-p", "--", Paths.themesDir, Paths.stateDir]
        onExited: {
            root.dirsMade = true;
            root.flushPending();
        }
    }

    Process {
        id: remover

        property string removing: ""

        onExited: exitCode => {
            if (exitCode !== 0) {
                Logger.warn("theme", root.policy.refusedLine(remover.removing,
                                                             "rm exited " + exitCode));
                return;
            }
            Logger.log("theme", root.policy.deletedLine(remover.removing));
            // The label would otherwise go on naming a theme that is not there.
            // The look stays exactly as it is — deleting a theme is not undoing
            // it, so what the shell is wearing becomes an unnamed skin, which is
            // the shipped look's row saying "modified since".
            if (root.applied === remover.removing)
                ShellState.set("theme.lastApplied", root.policy.defaultName);
            root.refreshListing();
        }
    }

    // Functions need explicit signatures to be callable over IPC, and `qs ipc
    // show target theme` lists exactly what is below — so this is also the
    // documented external surface. It is what makes apply, save, delete and undo
    // drivable from tools/theme-harness.sh (#81: a state change with no door and
    // no log line is a state change nobody can check), and it is a real
    // affordance besides — a keybind that puts the laptop into its dim evening
    // skin is one line of Hyprland config.
    IpcHandler {
        target: "theme"

        function apply(name: string): void { root.apply(name); }
        function save(name: string): void { root.save(name); }
        function remove(name: string): void { root.remove(name); }
        function undo(): void { root.undo(); }
        function reset(): void { root.apply(root.policy.defaultName); }

        /// The saved themes, one per line, with the applied one marked. Named
        /// `names` and not `list` for the reason Surfaces/Settings/SettingsWindow.qml
        /// gives about `show`: a name the CLI's own parser owns is a function
        /// nobody can call.
        function names(): string {
            return root.entries.map(row => (row.applied ? "* " : "  ") + row.name
                                    + (row.drifted ? " (modified)" : "")).join("\n");
        }

        function current(): string {
            return (root.applied === "" ? root.policy.defaultName : root.applied)
                + (root.drifted ? " (modified)" : "");
        }
    }

    // Made once per session rather than on the first save: a `mkdir` in front of
    // a press is a press that does nothing until a subprocess comes back, and
    // this one costs nothing on a machine that already has the directories.
    Component.onCompleted: {
        makeDirs.running = true;
        Logger.stage("themes armed (ipc target: theme)");
    }
}
