// What the pointer turns into over each part of the calendar.
//
// Two things are pinned here and neither is "does it look right". The first is
// that the *word* and the *protocol number* never come apart: the shell logs the
// word and seam 2 greps the number out of a `WAYLAND_DEBUG` log, so a rename on
// one side and not the other turns a passing cursor check into a check of
// nothing. The second is that a chip's hover zones and its press zones agree —
// a pointer that shows resize arrows where a press starts a move is a lie the
// surface tells before the hand has committed to anything.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "CursorPolicy"

    CursorPolicy { id: cursor }

    function test_each_zone_has_a_word() {
        compare(cursor.name("chip"), "pointing-hand");
        compare(cursor.name("chrome"), "pointing-hand");
        compare(cursor.name("chip-edge"), "ns-resize");
        compare(cursor.name("grid"), "crosshair");
        compare(cursor.name("idle"), "default");
    }

    // The grid is the one that has been wrong: a hand there promises a press
    // that opens something, and a press there draws a new event.
    function test_the_grid_is_not_a_hand() {
        verify(cursor.name("grid") !== cursor.name("chip"));
    }

    function test_an_unknown_zone_is_the_arrow_not_an_exception() {
        compare(cursor.name(""), "default");
        compare(cursor.name("nonsense"), "default");
        compare(cursor.name(undefined), "default");
        compare(cursor.waylandShape(undefined), 1);
    }

    // The numbers are `wp_cursor_shape_device_v1`'s, not Qt's. Written out
    // rather than derived, because the whole point of the pair is that the log
    // and the protocol can be compared without trusting either.
    function test_the_word_and_the_protocol_number_agree() {
        compare(cursor.waylandShape("chip"), 4);
        compare(cursor.waylandShape("chrome"), 4);
        compare(cursor.waylandShape("grid"), 8);
        compare(cursor.waylandShape("chip-edge"), 27);
        compare(cursor.waylandShape("idle"), 1);
    }

    function test_every_named_zone_resolves() {
        for (let i = 0; i < cursor.zones.length; i++) {
            const zone = cursor.zones[i];
            verify(cursor.name(zone).length > 0);
            verify(cursor.waylandShape(zone) >= 1);
        }
    }

    // A 60px chip with 6px strips: the top 6 and the bottom 6 resize, the 48
    // between them move.
    function test_a_chips_edges_are_the_resize_strips() {
        compare(cursor.chipZone(0, 60, 6), "chip-edge");
        compare(cursor.chipZone(6, 60, 6), "chip-edge");
        compare(cursor.chipZone(7, 60, 6), "chip");
        compare(cursor.chipZone(30, 60, 6), "chip");
        compare(cursor.chipZone(53, 60, 6), "chip");
        compare(cursor.chipZone(54, 60, 6), "chip-edge");
        compare(cursor.chipZone(60, 60, 6), "chip-edge");
    }

    // The failure this guards is a 20px chip whose two 6px strips would meet in
    // the middle and leave no body to grab: the depth is capped at half the
    // height, so a short chip still has a middle.
    function test_a_short_chip_keeps_a_middle() {
        compare(cursor.chipZone(10, 20, 12), "chip-edge");
        compare(cursor.chipZone(9, 20, 6), "chip");
        compare(cursor.chipZone(20, 20, 40), "chip-edge");
    }

    function test_a_chip_with_no_edges_is_all_body() {
        compare(cursor.chipZone(0, 40, 0), "chip");
        compare(cursor.chipZone(40, 40, 0), "chip");
    }
}
