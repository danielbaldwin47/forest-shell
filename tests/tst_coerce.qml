// Per-key coercion (#33). The rule being pinned here: a bad *value* costs one
// key, never the file — it is coerced if there is an obvious reading, and
// otherwise falls back to that key's default with everything else untouched.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "Coerce"

    Coerce { id: c }

    function test_boolean_passes_bools_through() {
        compare(c.boolean(true), true);
        compare(c.boolean(false), false);
    }

    function test_boolean_reads_hand_typed_strings() {
        // Quoting a bool is the single most common hand-editing slip.
        compare(c.boolean("true"), true);
        compare(c.boolean("FALSE"), false);
        compare(c.boolean(" yes "), true);
    }

    function test_boolean_rejects_nonsense() {
        compare(c.boolean("maybe"), undefined);
        compare(c.boolean(null), undefined);
        compare(c.boolean({}), undefined);
    }

    function test_string_stringifies_scalars() {
        compare(c.string("hi"), "hi");
        compare(c.string(4), "4");
        compare(c.string(true), "true");
    }

    function test_string_rejects_structures() {
        compare(c.string({}), undefined);
        compare(c.string([1]), undefined);
        compare(c.string(null), undefined);
    }

    function test_integer_rounds_and_clamps() {
        const height = c.integer(20, 96);
        compare(height(36), 36);
        compare(height(36.6), 37);
        compare(height(2), 20);
        compare(height(500), 96);
    }

    function test_integer_reads_quoted_numbers() {
        compare(c.integer(0, 100)("42"), 42);
    }

    function test_integer_rejects_non_numbers() {
        compare(c.integer(0, 100)("tall"), undefined);
        compare(c.integer(0, 100)(""), undefined);
        compare(c.integer(0, 100)(null), undefined);
    }

    function test_number_keeps_fractions() {
        compare(c.number(0, 3)(1.5), 1.5);
        compare(c.number(0, 3)(-1), 0);
    }

    function test_number_open_ended_range() {
        // Only a lower bound: `undefined` for max means "no ceiling".
        compare(c.number(1)(9999), 9999);
    }

    function test_one_of_accepts_known_names() {
        compare(c.oneOf(["top", "bottom"])("bottom"), "bottom");
    }

    function test_one_of_rejects_unknown_names() {
        // Unlike a number there is no nearest valid value for a typo'd name,
        // so the key falls back to its default rather than guessing.
        compare(c.oneOf(["top", "bottom"])("topp"), undefined);
        compare(c.oneOf(["top", "bottom"])(3), undefined);
    }

    function test_object_accepts_only_plain_objects() {
        compare(Object.keys(c.object({ a: 1 })).length, 1);
        compare(c.object([1]), undefined);
        compare(c.object(null), undefined);
        compare(c.object("{}"), undefined);
    }

    function test_array_accepts_only_arrays() {
        compare(c.array([1, 2]).length, 2);
        compare(c.array({}), undefined);
    }

    // --- combinators ---------------------------------------------------------

    // The field table a themed group is written with — the bar surface, cut
    // down to the two keys that matter here.
    readonly property var surfaceFields: ({
        opacity: { def: 0.86, coerce: c.number(0.65, 1.0) },
        grain: { def: 0.03, coerce: c.number(0, 0.1) }
    })

    function test_shape_defaults_come_from_the_field_table() {
        // The leaf's `def` is derived from the same table its coercer reads, so
        // the two cannot drift apart.
        const defaults = c.shapeDefaults(surfaceFields);
        compare(defaults.opacity, 0.86);
        compare(defaults.grain, 0.03);
    }

    function test_shape_always_returns_every_key() {
        // Whatever the file says, the group the shell reads is complete — a
        // half-written group is the failure mode `themed` groups exist to
        // prevent.
        const out = c.shape(surfaceFields)({ opacity: 0.7 });
        compare(out.opacity, 0.7);
        compare(out.grain, 0.03);
    }

    function test_shape_clamps_inside_the_group() {
        // The whole reason for the combinator: 20% fill measured 1.25:1 against
        // the brightest wallpaper (#10), so the floor is not advisory.
        compare(c.shape(surfaceFields)({ opacity: 0.2 }).opacity, 0.65);
        compare(c.shape(surfaceFields)({ opacity: 4 }).opacity, 1.0);
    }

    function test_one_bad_key_costs_one_key() {
        ignoreWarning(/ignoring bar.surface.opacity/);
        const out = c.shape(surfaceFields, "bar.surface")({ opacity: "loud", grain: 0.05 });
        compare(out.opacity, 0.86);
        compare(out.grain, 0.05);
    }

    function test_shape_keeps_keys_it_does_not_name() {
        // A group written by a newer shell must not be pruned by an older one:
        // the settings GUI serializes the *resolved* group back sparsely, so a
        // key dropped here would be a key dropped from the user's file (#54).
        const out = c.shape(surfaceFields)({ opacity: 0.9, mystery: 1 });
        compare(out.mystery, 1);
        compare(Object.keys(out).length, 3);
    }

    function test_shape_rejects_a_non_object_wholesale() {
        // Nothing to salvage per key, so the leaf falls back as one.
        compare(c.shape(surfaceFields)([]), undefined);
        compare(c.shape(surfaceFields)("0.86"), undefined);
    }

    function test_array_of_coerces_entries() {
        compare(c.arrayOf(c.string)(["workspaces", 3]), ["workspaces", "3"]);
    }

    function test_array_of_drops_what_it_cannot_read() {
        // A list has no per-slot default, so a bad entry leaves rather than
        // becoming a hole the bar would have to render.
        ignoreWarning(/dropping module entry/);
        compare(c.arrayOf(c.string, "module")(["clock", {}]), ["clock"]);
    }

    function test_array_of_still_rejects_non_arrays() {
        compare(c.arrayOf(c.string)("clock"), undefined);
        compare(c.arrayOf(c.string)({ a: "b" }), undefined);
    }

    function test_map_of_drops_only_the_bad_entry() {
        const rules = c.mapOf(c.oneOf(["normal", "silent", "blocked"]));
        const out = rules({ firefox: "silent", slack: "screaming", mail: "blocked" });

        compare(out.firefox, "silent");
        compare(out.mail, "blocked");
        // Not "normal" — an entry that cannot be read is absent, and absent is
        // what normal already means.
        compare(out.slack, undefined);
    }

    function test_map_of_still_rejects_a_non_object() {
        compare(c.mapOf(c.string)(["silent"]), undefined);
        compare(c.mapOf(c.string)("silent"), undefined);
    }
}
