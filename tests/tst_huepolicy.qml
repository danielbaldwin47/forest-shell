// Which hue an event wears.
//
// The property under test is not "is this the right colour" — no test can say
// that — it is **stability**: the same event gets the same hue on every run, on
// every machine, before and after its neighbours are deleted. That is what makes
// two captures of the same fixture the same picture, and it is the only thing
// the surface is entitled to assume.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "HuePolicy"

    HuePolicy { id: hues }

    function test_eight_names() {
        compare(hues.count, 8);
        compare(hues.names.length, 8);
        // Named rather than counted: the table in DESIGN-SPEC.md is indexed by
        // this order, so a reordering that kept the count would silently
        // repaint every calendar.
        compare(hues.names, ["glacier", "moss", "lamplight", "ember",
                             "lake", "lichen", "heather", "stone"]);
    }

    function test_named_colour_wins() {
        compare(hues.indexFor("glacier", "evt-1"), 0);
        compare(hues.indexFor("stone", "evt-1"), 7);
        compare(hues.indexFor("Heather", "evt-1"), 6);
        compare(hues.indexFor("  lake  ", "evt-1"), 4);
    }

    function test_numeric_colour_accepted() {
        compare(hues.indexFor("3", "evt-1"), 3);
        compare(hues.indexFor("0", "evt-1"), 0);
        compare(hues.indexFor("7", "evt-1"), 7);
    }

    function test_out_of_range_number_falls_through() {
        // 8 is not a hue. It must not clamp to 7 and must not become 0 — both
        // would hide the mistake behind a plausible colour.
        compare(hues.indexFor("8", "evt-1"), hues.indexFor("", "evt-1"));
        compare(hues.indexFor("-1", "evt-1"), hues.indexFor("", "evt-1"));
    }

    function test_unknown_name_falls_through_not_to_zero() {
        // A typo must not make every mistyped event glacier: two different
        // typos on two different events stay two different events.
        compare(hues.indexFor("gclaier", "evt-1"), hues.indexFor("", "evt-1"));
        compare(hues.indexFor("gclaier", "evt-2"), hues.indexFor("", "evt-2"));
    }

    function test_uncoloured_is_stable_and_in_range() {
        for (let i = 1; i <= 200; i++) {
            const id = "evt-" + i;
            const first = hues.indexFor("", id);
            verify(first >= 0 && first < hues.count, id + " -> " + first);
            compare(hues.indexFor("", id), first);
            // Nothing about the *other* events may reach the answer: it is a
            // function of the id alone, so deleting evt-1 never repaints evt-2.
            compare(hues.forEvent({ "id": id, "colour": "" }), first);
        }
    }

    function test_uncoloured_spreads_over_the_wheel() {
        // Not a distribution proof — just the guard against a hash that
        // collapses. The fixture's eleven events would be one colour if djb2
        // were replaced with something that ignored short suffixes.
        const seen = {};
        for (let i = 1; i <= 40; i++)
            seen[hues.indexFor("", "evt-" + i)] = true;
        verify(Object.keys(seen).length >= 6, Object.keys(seen).join(","));
    }

    function test_missing_event_is_not_an_exception() {
        compare(hues.forEvent(null), 0);
        compare(hues.forEvent(undefined), 0);
    }

    function test_undefined_colour_reads_as_absent() {
        const byId = hues.indexFor("", "evt-9");
        compare(hues.forEvent({ "id": "evt-9" }), byId);
        compare(hues.forEvent({ "id": "evt-9", "colour": null }), byId);
    }
}
