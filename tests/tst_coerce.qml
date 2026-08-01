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

    // --- collections ---------------------------------------------------------
    //
    // The rule at the top of this file needs a level below the key for these:
    // one key holds many independent things, and a typo in one of them must not
    // take the rest of them with it.

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

    function test_list_of_drops_only_the_bad_entry() {
        const modules = c.listOf(c.oneOf(["clock", "battery", "tray"]));
        const out = modules(["clock", "aquarium", "tray"]);

        compare(out.length, 2);
        compare(out[0], "clock");
        compare(out[1], "tray");
    }

    function test_list_of_still_rejects_a_non_array() {
        compare(c.listOf(c.string)({ a: "b" }), undefined);
    }

    // --- theme-flagged groups ------------------------------------------------

    function test_shape_fills_in_the_knobs_a_hand_edit_left_out() {
        // The trap `shape` exists to close: a themed group is one key, so
        // without the merge, naming one knob would drop the rest.
        const surface = c.shape({ opacity: 0.86, blur: true, grain: 0.03 },
                                { opacity: c.number(0.65, 1) });
        const out = surface({ opacity: 0.7 });

        compare(out.opacity, 0.7);
        compare(out.blur, true);
        compare(out.grain, 0.03);
    }

    function test_shape_clamps_a_knob_without_touching_its_neighbours() {
        const surface = c.shape({ opacity: 0.86, blur: true },
                                { opacity: c.number(0.65, 1) });
        const out = surface({ opacity: 0.2, blur: false });

        // 0.2 is unreadable text over a bright wallpaper, so it comes back at
        // the floor — and the blur the user turned off stays off.
        compare(out.opacity, 0.65);
        compare(out.blur, false);
    }

    function test_shape_falls_back_one_knob_at_a_time() {
        const ridge = c.shape({ shape: "strata", unitWidth: 14 },
                              { shape: c.oneOf(["strata"]), unitWidth: c.integer(4, 24) });
        const out = ridge({ shape: "pills", unitWidth: 9 });

        compare(out.shape, "strata");   // unreadable name → this knob's default
        compare(out.unitWidth, 9);      // the knob next to it is untouched
    }

    function test_shape_keeps_keys_it_does_not_know() {
        // A group written by a newer shell must not be pruned by an older one.
        const out = c.shape({ opacity: 0.86 }, {})({ opacity: 0.9, sheen: 3 });
        compare(out.sheen, 3);
    }

    function test_shape_still_rejects_a_non_object() {
        compare(c.shape({ opacity: 1 }, {})(0.5), undefined);
    }
}
