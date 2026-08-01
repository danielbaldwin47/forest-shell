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
// integer, enum, object, array, and the two collection combinators below are
// the whole set a schema line may use, and a key whose value does not fit one
// of them is a sign the key wants splitting. Some have no caller yet only
// because their section's ticket has not landed — they are what the schema is
// written *in*, so they stay.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    readonly property QtObject json: JsonMerge {}

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

    // --- collections -----------------------------------------------------------
    //
    // The two combinators above the scalars: a key whose value is a *collection
    // of* something the vocabulary already covers. They exist because the
    // one-bad-value-costs-one-key rule needs a level below the key for these —
    // `notifications.appRules` is one key holding a rule per app, and a typo in
    // one app's rule must not silently switch every other app back to normal.
    //
    // So they drop the bad entry and keep the rest, rather than returning
    // `undefined` for the whole key. The dropped entry is not reported here:
    // these are pure, and the store's issue list is per key. The value the user
    // sees in the GUI is the surviving map, which is the honest answer.

    /// String-keyed map whose *values* all coerce the same way. Entries the
    /// value coercer refuses are dropped.
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

    /// A whole sub-object leaf — a theme-flagged group (#56) — merged over its
    /// own defaults and then coerced knob by knob.
    ///
    /// This is what stops `themed: true` atomicity from becoming a trap. The
    /// group is one key: a preset replaces it wholesale and never half-merges
    /// into keys the user left behind. But a *user* who writes
    /// `"bar": { "surface": { "opacity": 0.7 } }` by hand means "that one knob",
    /// not "and drop the other nine" — and without the merge every consumer, and
    /// every control in the settings GUI (#54), would read `undefined` for the
    /// rest. Unknown keys inside the group survive, same as anywhere else in the
    /// file: a group written by a newer shell is not pruned by an older one.
    ///
    /// `coercers` is per knob and optional per knob. A knob that fails falls
    /// back to its own default, so the one-bad-value-costs-one-key rule reaches
    /// inside the group — a bar opacity of `0.2` is unreadable text, and it must
    /// cost the opacity rather than the whole surface.
    function shape(defaults, coercers) {
        return function (value) {
            const source = object(value);
            if (source === undefined)
                return undefined;

            const out = json.merge(defaults, source);
            for (const key in (coercers || {})) {
                if (out[key] === undefined)
                    continue;
                const coerced = coercers[key](out[key]);
                out[key] = coerced === undefined ? json.deepCopy(defaults[key]) : coerced;
            }
            return out;
        };
    }

    /// List whose entries all coerce the same way. Entries the item coercer
    /// refuses are dropped, so an unknown module id in the bar registry costs
    /// that module and not the user's whole layout.
    function listOf(itemCoerce) {
        return function (value) {
            const source = array(value);
            if (source === undefined)
                return undefined;

            const out = [];
            for (const item of source) {
                const coerced = itemCoerce(item);
                if (coerced !== undefined)
                    out.push(coerced);
            }
            return out;
        };
    }
}
