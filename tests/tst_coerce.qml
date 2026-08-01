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

}
