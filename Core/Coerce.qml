// The coercers the spec table's `coerce` slots are built from (#21, #33).
//
// Contract: a coercer takes whatever `JSON.parse` produced for a key and
// returns a value the shell can use, or `undefined` when it cannot be salvaged
// — the store then falls back to that key's default and records an issue. One
// bad value costs one key, never the file.
//
// Coercing rather than rejecting is deliberate. `settings.json` is meant to be
// hand-edited, and `"true"` in a bool key or `"36"` in an int is a typo, not a
// corrupt config; losing the whole bar over it would be the wrong lesson. Where
// there is no obvious reading — an unknown enum name — the key falls back
// instead of guessing.
//
// This is a closed vocabulary, not a grab-bag: bool, string, path, number,
// integer, enum, object, array is the whole set a schema line may use, and a
// key whose value does not fit one of them is a sign the key wants splitting.
// Some have no caller yet only because their section's ticket has not landed —
// they are what the schema is written *in*, so they stay.
//
// `shape` and `arrayOf` at the bottom are **combinators over that vocabulary**,
// not additions to it: they exist because a few leaves are whole sub-objects
// that may not be split (#56 — a theme preset replaces a group atomically), and
// those still have to be validated key by key.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    function boolean(value) {
        if (typeof value === "boolean")
            return value;
        if (typeof value === "number")
            return value !== 0;
        if (typeof value === "string") {
            const text = value.trim().toLowerCase();
            if (text === "true" || text === "yes" || text === "1")
                return true;
            if (text === "false" || text === "no" || text === "0")
                return false;
        }
        return undefined;
    }

    function string(value) {
        if (typeof value === "string")
            return value;
        if (typeof value === "number" || typeof value === "boolean")
            return String(value);
        return undefined;
    }

    // A leading `~` is left alone on purpose: Paths.fileUrl expands it at use
    // time, and expanding it here would bake this machine's home directory into
    // a config that is meant to travel between the laptop and the desktop.
    function path(value) {
        return string(value);
    }

    // `max` may be omitted for an open-ended range.
    function number(min, max) {
        return function (value) {
            const asNumber = typeof value === "number"
                ? value
                : (typeof value === "string" && value.trim() !== "" ? Number(value) : NaN);
            if (!isFinite(asNumber))
                return undefined;
            return clamp(asNumber, min, max);
        };
    }

    function integer(min, max) {
        const asNumber = number(min, max);
        return function (value) {
            const coerced = asNumber(value);
            return coerced === undefined ? undefined : Math.round(coerced);
        };
    }

    function clamp(value, min, max) {
        if (min !== undefined && value < min)
            return min;
        if (max !== undefined && value > max)
            return max;
        return value;
    }

    function oneOf(allowed) {
        return function (value) {
            return allowed.indexOf(value) >= 0 ? value : undefined;
        };
    }

    // Whole sub-objects are leaves in the spec table (theme-flagged groups like
    // `bar.surface`), so this is the coercer that keeps them atomic.
    function object(value) {
        return (value !== null && typeof value === "object" && !Array.isArray(value))
            ? value : undefined;
    }

    function array(value) {
        return Array.isArray(value) ? value : undefined;
    }

    // --- combinators ---------------------------------------------------------

    /// A whole sub-object, validated key by key.
    ///
    /// `fields` is `{ key: { def, coerce } }` — the same two slots a spec-table
    /// leaf carries, one level down. The result is always **complete**: a key
    /// the file omits gets its default, and a key that cannot be salvaged gets
    /// its default and a warning, so one bad value inside a group costs one
    /// key rather than the group.
    ///
    /// Needed because the theme-flagged groups (`bar.surface`,
    /// `bar.ridgeline`) are single leaves so a preset can replace them
    /// atomically (#56), and the plain `object` coercer waves whatever is
    /// inside them straight through. That is how a hand-edited bar opacity of
    /// `"loud"` — or of 0.2, which #10 measured at 1.25:1 against the
    /// wallpaper — would reach the screen.
    ///
    /// Keys the shape does not name are carried through untouched, not pruned.
    /// A themed group is one key, so the settings GUI (#54) serializes the
    /// *resolved* group back into the file sparsely — if resolution dropped an
    /// unknown key here, an older shell's first slider move would prune a group
    /// written by a newer one, which is exactly the pruning the sparse-write
    /// rule exists to prevent (Core/SpecStore.qml).
    function shape(fields, label) {
        return function (value) {
            if (object(value) === undefined)
                return undefined;

            const out = {};
            for (const key in fields) {
                const field = fields[key];
                const raw = value[key];
                if (raw === undefined) {
                    out[key] = field.def;
                    continue;
                }
                const coerced = field.coerce(raw);
                if (coerced === undefined) {
                    console.warn("settings: ignoring " + (label ? label + "." : "") + key
                                 + " = " + JSON.stringify(raw));
                    out[key] = field.def;
                } else {
                    out[key] = coerced;
                }
            }
            for (const key in value)
                if (!(key in fields))
                    out[key] = value[key];
            return out;
        };
    }

    /// String-keyed map whose *values* all coerce the same way — one key
    /// holding many independent entries, like `notifications.apps` holding a
    /// rule per app. Entries the value coercer refuses are dropped rather than
    /// failing the key: a typo in one app's rule must not silently switch every
    /// other app back to normal. The dropped entry is not reported here — these
    /// are pure, and the store's issue list is per key.
    function mapOf(valueCoerce) {
        return function (value) {
            const source = object(value);
            if (source === undefined)
                return undefined;

            const out = {};
            for (const key in source) {
                const coerced = valueCoerce(source[key]);
                if (coerced !== undefined)
                    out[key] = coerced;
            }
            return out;
        };
    }

    /// The defaults of a `shape` field table, as the leaf's `def`. Derived
    /// rather than written twice — a group whose default and whose validation
    /// disagreed would resolve differently on the first run than on the second.
    function shapeDefaults(fields) {
        const out = {};
        for (const key in fields)
            out[key] = fields[key].def;
        return out;
    }

    /// A homogeneous list. Entries that do not coerce are **dropped** with a
    /// warning, because a list has no per-slot default to fall back to — a hole
    /// in a module order is not a thing the bar can render.
    function arrayOf(item, label) {
        return function (value) {
            if (array(value) === undefined)
                return undefined;
            const out = [];
            for (const entry of value) {
                const coerced = item(entry);
                if (coerced === undefined)
                    console.warn("settings: dropping " + (label ? label + " " : "")
                                 + "entry " + JSON.stringify(entry));
                else
                    out.push(coerced);
            }
            return out;
        };
    }
}
