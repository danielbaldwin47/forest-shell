// Where a sample lands in the row (#50).
//
// The one decision inside Widgets/Sparkline.qml: the newest sample is at the
// right edge, the row is a fixed number of slots wide, and a history shorter
// than the row leaves the left of it empty rather than stretching to fill it.
// Everything else in that file is geometry a capture judges (seam 3).
import QtQuick
import QtTest
import "../Widgets"

TestCase {
    name: "Sparkline"

    Sparkline {
        id: line
        slots: 4
    }

    function test_a_full_history_fills_the_row_in_order() {
        line.values = [0.1, 0.2, 0.3, 0.4];
        compare(Math.round(line.sample(0) * 10), 1);
        compare(Math.round(line.sample(3) * 10), 4);
    }

    function test_the_newest_sample_is_at_the_right_edge() {
        // Which is what makes the row read as time passing: a card left open
        // shows its history sliding left, rather than a bar appearing in a
        // different place each second.
        line.values = [0.9];
        verify(isNaN(line.sample(0)));
        verify(isNaN(line.sample(2)));
        compare(Math.round(line.sample(3) * 10), 9);
    }

    function test_a_history_longer_than_the_row_is_cropped_from_the_left() {
        line.values = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6];
        compare(Math.round(line.sample(0) * 10), 3);
        compare(Math.round(line.sample(3) * 10), 6);
    }

    function test_a_slot_nothing_has_reached_yet_is_not_a_zero() {
        // A bar at the floor is "the machine was idle"; an empty slot is "there
        // was no reading". Drawing the first as the second is the one way a
        // monitor can lie.
        line.values = [];
        verify(isNaN(line.sample(0)));
        verify(isNaN(line.sample(3)));
    }

    function test_a_gap_in_the_middle_of_a_history_stays_a_gap() {
        // The first CPU sample of a freshly-opened card, which has no previous
        // snapshot to be a delta of.
        line.values = [0.5, NaN, 0.5, 0.5];
        verify(isNaN(line.sample(1)));
    }

    function test_a_sample_out_of_range_is_clamped_to_the_row() {
        line.values = [-1, 2, 0.5, 0.5];
        compare(line.sample(0), 0);
        compare(line.sample(1), 1);
    }

    function test_values_that_are_not_a_list_draw_an_empty_row() {
        line.values = null;
        verify(isNaN(line.sample(0)));
        // A string has a `length` and is not a list of anything.
        line.values = "busy";
        verify(isNaN(line.sample(0)));
        line.values = 7;
        verify(isNaN(line.sample(0)));
        line.values = [];
    }

    function test_a_history_that_arrives_as_a_sequence_still_draws() {
        // The failure this pins: a JavaScript array handed through a
        // `Repeater`'s `modelData` comes out the other side as a QML sequence,
        // and `Array.isArray` is false for one. The row drew nothing at all
        // while sixty samples sat behind it — measured on the dashboard card,
        // which is exactly this path.
        const sequence = { length: 4, 0: 0.1, 1: 0.2, 2: 0.3, 3: 0.4 };
        line.values = sequence;
        compare(Math.round(line.sample(3) * 10), 4);
        line.values = [];
    }
}
