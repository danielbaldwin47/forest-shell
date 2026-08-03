// What a theme preset *is*, as pure functions (#56, #26).
//
// A theme is a named sparse fragment of the settings file: the keys the schema
// flags as skin, and nothing else. Core/Themes.qml is the half that knows what a
// directory is; every decision below is reachable from tests/.
//
// ## Skin, not layout
//
// Which keys travel is not a list written here — it is read off the schema, so
// a section that gains a styling group gains it in themes too, in one line and
// in one place. A key travels when its leaf carries `themed: true` and does not
// carry `derived: true`:
//
//   - `themed` is the flag the settings schema already had for the whole
//     sub-objects a preset replaces atomically (`bar.surface`,
//     `bar.ridgeline`, `appearance.paletteOverrides`), plus `appearance.mode`,
//     because the ticket asks for the mode *choice* to travel;
//   - `derived` is its exception: `appearance.dynamic` is what a wallpaper-
//     coupled mode *produced* on one machine (#58, #59), and a preset that
//     carried it would pin another machine's wallpaper into the palette.
//
// Geometry, module lists, wallpaper and every service setting stay where they
// are. That is the whole distinction the ticket draws — a theme changes how the
// shell looks, never what is on it.
//
// ## Apply is a copy, and it goes through the config engine
//
// `plan()` returns writes, not a file. Core/Themes.qml hands each one to
// `Config.set` / `Config.reset`, which is what makes the promises true rather
// than restated: the group coercers clamp what a theme carries (a bar opacity
// below #79's floor is applied at the floor, never raw), unknown keys inside a
// group survive, and the write is sparse. A theme is never a live link — after
// an apply the settings file is the only thing the shell reads.
//
// A carried path the theme does *not* have is a `reset`, not a skip. That is
// what makes "Forest (default)" a real theme with an empty body: applying it
// deletes the flagged keys, and deletion — rather than writing today's defaults
// — is what lets a later change to a shipped default still reach the user (#21).
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    id: policy

    readonly property QtObject store: SpecStore {}
    readonly property QtObject migrations: Migrations {}

    /// The shipped look, which is the absence of every carried key rather than
    /// a file. Shown in the list beside the saved themes because it is the same
    /// verb — apply — and a user who has drifted needs a way back that is not
    /// "reset the Appearance tab and also the Bar tab".
    readonly property string defaultName: "Forest (default)"

    /// The undo slot, snapshotted before every apply. A name and not a file
    /// name: it lives in the state directory, not among the user's themes.
    readonly property string undoName: "Previous settings"

    readonly property string extension: ".json"

    // --- which keys a theme carries -------------------------------------------

    /// Every carried path, depth first in schema order. One walk of the spec,
    /// and the only place the two flags are read.
    function carriedPaths(spec: var): var {
        const out = [];
        for (const path of policy.store.leafPaths(spec)) {
            const leaf = policy.store.leafAt(spec, path);
            if (leaf.themed === true && leaf.derived !== true)
                out.push(path);
        }
        return out;
    }

    // --- saving ---------------------------------------------------------------

    /// A theme's body, taken from the settings file **as it is on disk** rather
    /// than from resolved values.
    ///
    /// The file is sparse: a key that is not in it is a key the user never moved
    /// off its default. Reading resolved values instead would write today's
    /// complete defaults into every theme — freezing every knob the user never
    /// touched at the value it happened to have on the day they pressed save,
    /// and making a later change to a shipped default unreachable for anyone who
    /// ever saved a theme.
    function fragment(spec: var, raw: var): var {
        const out = {};
        for (const path of policy.carriedPaths(spec)) {
            const value = policy.store.getPath(raw, path);
            if (value !== undefined)
                policy.store.setPath(out, path, policy.store.json.deepCopy(value));
        }
        return out;
    }

    /// The file to write for a theme, version stamp first: a theme travels
    /// between machines and settingsVersions, so it carries its own stamp and is
    /// migrated on the way in like any other settings file.
    function themeFile(schema: var, raw: var): var {
        const out = {};
        out[schema.versionKey] = schema.version;
        const body = policy.fragment(schema.spec, raw);
        for (const key in body)
            out[key] = body[key];
        return out;
    }

    /// The theme the shell is wearing *right now*, from the live values and the
    /// file they were resolved against.
    ///
    /// Not read from the file alone, which lags: the config engine debounces its
    /// writes, so `raw` is up to a quarter of a second behind a slider that has
    /// just stopped moving, and "save the look I am looking at" is a button
    /// pressed exactly then. Serializing the live values against the file is the
    /// same operation the engine performs on its own write, so this is what the
    /// file is *about* to be — including the keys this build does not know,
    /// which the serializer carries through.
    function snapshot(schema: var, values: var, raw: var): var {
        return policy.themeFile(schema, policy.store.serialize(schema.spec, values, raw));
    }

    // --- applying -------------------------------------------------------------

    /// What applying a theme file does: `{ ok, error, from, to, applied, ops }`.
    ///
    /// The file is migrated first — on the raw JSON, by the settings file's own
    /// migration chain, since a theme is a fragment of that file and a rename
    /// that moved a key moved it in both. A migration that throws is a refusal:
    /// `ok` is false and there are no ops, because half-applying a theme is the
    /// one outcome with no way back.
    ///
    /// One op per carried path, in schema order:
    ///
    ///   { path, value }        — the theme carries it; write it
    ///   { path, reset: true }  — it does not; delete the key
    ///
    /// Coercion is deliberately *not* here. These go to `Config.set`, whose
    /// coercers are the same ones a hand-edited file meets — so a theme cannot
    /// smuggle in a value the file format would refuse, and there is one
    /// implementation of every range rather than two that must agree.
    function plan(schema: var, file: var): var {
        const migrated = policy.migrations.run(file, schema.migrations,
                                               schema.versionKey, schema.version);
        if (!migrated.ok)
            return { ok: false, error: migrated.error, from: migrated.from,
                     to: migrated.from, applied: [], ops: [] };

        const ops = [];
        for (const path of policy.carriedPaths(schema.spec)) {
            const value = policy.store.getPath(migrated.raw, path);
            if (value === undefined)
                ops.push({ path: path, reset: true });
            else
                ops.push({ path: path, value: value });
        }
        return { ok: true, error: "", from: migrated.from, to: migrated.to,
                 applied: migrated.applied, ops: ops };
    }

    /// The empty theme — what "Forest (default)" applies. Every carried key
    /// resets, which is what the shipped look *is*.
    function defaultFile(schema: var): var {
        const out = {};
        out[schema.versionKey] = schema.version;
        return out;
    }

    /// Whether the shell is still wearing this theme, given the plan that
    /// applying it produces and the shell's **resolved** values.
    ///
    /// The breadcrumb says which theme was applied, and this is what keeps it
    /// honest: a knob moved afterwards — in the GUI or by hand — means the file
    /// is no longer that theme, and the list says so rather than ticking a row
    /// the shell has since departed from.
    ///
    /// Resolved values and not the file, and the theme's values put through the
    /// same coercers, because applying is not a byte copy. A theme carrying a
    /// bar opacity of 0.2 is applied at the 0.65 floor (#79) and a theme
    /// spelling out a knob at its default has that knob dropped from the sparse
    /// file — compared raw, both would read as drift the instant they were
    /// applied, and the tick would never survive its own apply.
    function wears(schema: var, values: var, planned: var): bool {
        if (!planned.ok)
            return false;
        for (const op of planned.ops) {
            const leaf = policy.store.leafAt(schema.spec, op.path);
            if (!leaf)
                return false;
            const current = policy.store.getPath(values, op.path);
            const wanted = op.reset ? leaf.def
                                    : (leaf.coerce ? leaf.coerce(op.value) : op.value);
            if (wanted === undefined || !policy.store.equals(current, wanted))
                return false;
        }
        return true;
    }

    /// The same question asked of a theme file rather than a plan, for a caller
    /// with no reason to hold one.
    function matches(schema: var, values: var, file: var): bool {
        return policy.wears(schema, values, policy.plan(schema, file));
    }

    /// How many of the flagged keys a theme actually carries — the number in the
    /// log line, and not `Object.keys(file).length`, which counts the sections
    /// the keys are nested in plus the version stamp.
    function carriedCount(schema: var, file: var): int {
        let count = 0;
        for (const path of policy.carriedPaths(schema.spec))
            if (policy.store.getPath(file, path) !== undefined)
                count++;
        return count;
    }

    // --- names ----------------------------------------------------------------

    /// Why a name cannot be saved, or "" when it can. The GUI shows this and
    /// the log prints it — a refused save that says nothing is the shape of bug
    /// #78 is about.
    ///
    /// The name is the file name, so the rules are the file system's plus the
    /// two names the list already uses. Nothing is silently rewritten: a theme
    /// saved as `Nord` and listed as `nord` would be a rename nobody asked for.
    function refusal(name: var): string {
        const text = String(name ?? "").trim();
        if (text === "")
            return "a theme needs a name";
        // The slash before the dot: `../escape` fails both rules, and the one
        // worth saying out loud is the one about where the file would land.
        if (/[\/\\]/.test(text))
            return "a name cannot contain a slash";
        if (text.startsWith("."))
            return "a name cannot start with a dot";
        if (/[\x00-\x1f]/.test(text))
            return "a name cannot contain control characters";
        if (text.length > 64)
            return "a name cannot be longer than 64 characters";
        if (policy.isReserved(text))
            return "\"" + text + "\" is the name of a built-in entry";
        return "";
    }

    function isReserved(name: var): bool {
        const text = String(name ?? "").trim().toLowerCase();
        return text === policy.defaultName.toLowerCase()
            || text === policy.undoName.toLowerCase();
    }

    /// The file a theme is stored in, or "" for a name that is refused.
    function fileName(name: var): string {
        if (policy.refusal(name) !== "")
            return "";
        return String(name).trim() + policy.extension;
    }

    /// The theme a file is. The name is the file name without its extension —
    /// identity is the file, so renaming the file renames the theme and there is
    /// no second copy of the name inside it to disagree.
    function nameOf(path: var): string {
        const text = String(path ?? "");
        const base = text.slice(text.lastIndexOf("/") + 1);
        return base.toLowerCase().endsWith(policy.extension)
            ? base.slice(0, base.length - policy.extension.length)
            : "";
    }

    // --- the list -------------------------------------------------------------

    /// The saved themes, in the order they are drawn: alphabetical by name,
    /// case-insensitively, for the reason the wallpaper grid is
    /// (Surfaces/Background/WallpaperPolicy.qml) — this is a list people scan
    /// for a name they remember.
    ///
    /// `applied` is the breadcrumb and `drifted` says whether the file still
    /// matches it, so the list can tick the current theme without claiming a
    /// look the user has since edited away from.
    function entries(files: var, lastApplied: var, drifted: var): var {
        const current = String(lastApplied ?? "");
        const out = [];
        for (const file of files ?? []) {
            const path = String(file?.path ?? "");
            const name = policy.nameOf(path);
            if (name === "")
                continue;
            out.push({
                name: name,
                path: path,
                applied: name === current,
                drifted: name === current && drifted === true
            });
        }
        return out.sort((a, b) => {
            const left = a.name.toLowerCase();
            const right = b.name.toLowerCase();
            if (left !== right)
                return left < right ? -1 : 1;
            return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
        });
    }

    // --- the log (#81) --------------------------------------------------------
    //
    // Apply, save, delete and undo are the state changes a harness asserts on,
    // and the words are here so the harness and the shell cannot drift apart.

    function savedLine(name: string, keys: int): string {
        return "saved \"" + name + "\" (" + keys + " key(s))";
    }

    function appliedLine(name: string, writes: int, resets: int): string {
        return "applied \"" + name + "\" (" + writes + " written, " + resets + " reset)";
    }

    function deletedLine(name: string): string {
        return "deleted \"" + name + "\"";
    }

    function refusedLine(name: var, why: string): string {
        return "refusing \"" + String(name ?? "") + "\": " + why;
    }
}
