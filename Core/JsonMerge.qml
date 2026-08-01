// Defaults-under-user-settings merge, and JSON parsing that never throws.
//
// The merge rule the config engine (#33) is built on: nested sections merge key
// by key, leaves (scalars, arrays, null) replace wholesale, and keys the shell
// does not know about survive untouched — a settings file written by a newer
// forest-shell must not lose data when read by an older one.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    function isPlainObject(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    // Nothing is shared with either argument: a merged config that aliased the
    // defaults would let one consumer's in-place edit rewrite the defaults for
    // every later reload.
    function deepCopy(value) {
        if (Array.isArray(value))
            return value.map(deepCopy);
        if (!isPlainObject(value))
            return value;

        const copy = {};
        for (const key in value)
            copy[key] = deepCopy(value[key]);
        return copy;
    }

    // Returns a new object; neither argument is mutated.
    function merge(defaults, overrides) {
        const out = deepCopy(defaults);
        if (!isPlainObject(overrides))
            return out;

        for (const key in overrides) {
            const override = overrides[key];
            out[key] = isPlainObject(override) && isPlainObject(out[key])
                ? merge(out[key], override)
                : deepCopy(override);
        }
        return out;
    }

    // { ok, value, error }. A missing or empty file is an empty config, not an
    // error; anything that is not a JSON object is corrupt.
    function parse(text) {
        const trimmed = (text || "").trim();
        if (trimmed === "")
            return { ok: true, value: {}, error: "" };

        let parsed;
        try {
            parsed = JSON.parse(trimmed);
        } catch (error) {
            return { ok: false, value: null, error: String(error.message || error) };
        }

        if (!isPlainObject(parsed))
            return { ok: false, value: null, error: "expected a JSON object at the top level" };

        return { ok: true, value: parsed, error: "" };
    }
}
