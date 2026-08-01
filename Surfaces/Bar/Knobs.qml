// Coercion for the bar's two theme-flagged config groups (#35).
//
// `bar.surface` and `bar.ridgeline` are *atomic* leaves in the spec table
// (Core/SettingsSchema.qml): a theme preset replaces the whole group rather
// than merging into it (#56), which is why the schema cannot describe their
// individual keys — and so cannot coerce them either. That job lands here, at
// the one place that knows what a fill opacity or a falloff means.
//
// The shape is deliberately not Core/Coerce.qml's: a coercer there returns
// `undefined` so the *store* can substitute a default and record an issue,
// while a knob has no store behind it and takes its default inline. Same
// forgiving spirit — a hand-edited `"0.9"` is a typo, not a broken bar — with
// nothing to report to.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    function number(value, fallback, min, max) {
        const parsed = typeof value === "number"
            ? value
            : (typeof value === "string" && value.trim() !== "" ? Number(value) : NaN);
        if (!isFinite(parsed))
            return fallback;
        return Math.min(max, Math.max(min, parsed));
    }

    function integer(value, fallback, min, max) {
        return Math.round(number(value, fallback, min, max));
    }

    function flag(value, fallback) {
        if (typeof value === "boolean")
            return value;
        if (typeof value === "string") {
            const text = value.trim().toLowerCase();
            if (text === "true" || text === "yes" || text === "1")
                return true;
            if (text === "false" || text === "no" || text === "0")
                return false;
        }
        return fallback;
    }

    /// The group as a plain object, whatever arrived. A group that is not an
    /// object at all reads as "no overrides", so every knob below it takes its
    /// shipped value rather than the whole bar losing its surface.
    function group(value) {
        return (value !== null && typeof value === "object" && !Array.isArray(value))
            ? value : {};
    }
}
