// The knob machinery behind the schema's theme-flagged groups (#56): one
// declaration line per knob, from which the group default, the knob-by-knob
// coercer and the settings-GUI control table are all derived, so a range
// cannot drift away from the control that offers it.
//
// Split out of Core/SettingsSchema.qml so a section file (for example
// Core/SettingsSchemaBar.qml) can instantiate it without reaching back into
// the aggregate schema — dependencies point one way only. Pure data, no
// Quickshell imports, so tests/ can reach it.
import QtQuick

QtObject {
    id: knobsMachinery

    readonly property QtObject c: Coerce {}

    /// Builds one theme-flagged group leaf (#56) from a table of knobs.
    ///
    /// A themed group is a *single* leaf carrying a whole sub-object, so that a
    /// preset replaces it atomically. That shape has nowhere to write down what
    /// each knob is, which the settings GUI needs — so the knobs are declared
    /// here, one line each, and this derives the three things that follow from
    /// them: the group's default object, the coercer that repairs a hand-edited
    /// group knob by knob, and the table the Bar tab renders its controls from.
    /// Nothing is written twice, so a range cannot drift away from the control
    /// that offers it.
    ///
    /// A knob is `{ def, label }` plus at most one of:
    ///
    ///   - `min`/`max` — a number. Integer or real is taken from the default,
    ///     since a knob whose default is `14` is not one you want at `14.3`;
    ///   - `values` — one of a closed list;
    ///   - nothing — a bool, from a bool default.
    ///
    /// `coerce` may still be given outright for a knob none of that fits, and
    /// is what a future knob type lands as before it earns a shorthand here.
    function group(label, knobs) {
        const fields = {};
        for (const key in knobs) {
            const knob = knobs[key];
            fields[key] = { def: knob.def, coerce: knob.coerce ?? coercerFor(knob) };
        }

        return { def: c.shapeDefaults(fields), coerce: c.shape(fields, label),
                 themed: true, knobs: knobs };
    }

    /// What kind of knob this is: `choice`, `range` or `toggle`. One answer,
    /// read by both things that need it — the coercer below, and the control
    /// the settings GUI renders (Surfaces/Settings/Controls/KnobRow.qml). Asking
    /// the same three questions in two places is how a knob ends up validated
    /// as one thing and edited as another.
    ///
    /// Integer or real is not part of the kind: it follows from the default,
    /// since a knob whose default is `14` is not one anybody wants at `14.3`.
    function knobKind(knob): string {
        if (knob.values !== undefined)
            return "choice";
        if (knob.min !== undefined || knob.max !== undefined)
            return "range";
        if (typeof knob.def === "boolean")
            return "toggle";
        // Reached only by a knob line that declares nothing this understands —
        // a schema bug, and one worth failing loudly on rather than admitting
        // an uncoerced value into a hand-edited file.
        throw new Error("SchemaKnobs: cannot tell what kind of knob this is: "
                        + JSON.stringify(knob));
    }

    function coercerFor(knob) {
        switch (knobKind(knob)) {
        case "choice":
            return c.oneOf(knob.values);
        case "range":
            return Number.isInteger(knob.def) ? c.integer(knob.min, knob.max)
                                              : c.number(knob.min, knob.max);
        default:
            return c.boolean;
        }
    }
}
