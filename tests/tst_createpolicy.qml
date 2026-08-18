// Where the sidebar's `+` puts an event.
//
// The frozen clock is the capture harness's own — 2026-08-18T13:40 — so a
// failure here and a wrong-looking chip in a capture are the same number.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "CreatePolicy"

    CreatePolicy { id: policy }

    readonly property int nowMin: 13 * 60 + 40

    function test_today_gets_the_next_snap_boundary() {
        compare(policy.startMinute("2026-08-18", "2026-08-18", testCase.nowMin, 15, 60),
                13 * 60 + 45);
    }

    function test_a_boundary_now_still_moves_forward() {
        // 13:45 exactly must give 14:00, not 13:45: a chip created *at* now
        // starts in the past by the time it is drawn, and an event whose start
        // is behind the now-line reads as one that was missed.
        compare(policy.startMinute("2026-08-18", "2026-08-18", 13 * 60 + 45, 15, 60),
                14 * 60);
    }

    function test_another_day_gets_the_working_morning() {
        compare(policy.startMinute("2026-08-20", "2026-08-18", testCase.nowMin, 15, 60),
                9 * 60);
        // Yesterday is "another day" too — the clock says nothing about a day
        // that is over.
        compare(policy.startMinute("2026-08-17", "2026-08-18", testCase.nowMin, 15, 60),
                9 * 60);
    }

    function test_a_late_press_clamps_inside_the_day() {
        // 23:58 would snap to 24:00, which is not a time this day has.
        compare(policy.startMinute("2026-08-18", "2026-08-18", 23 * 60 + 58, 15, 60),
                23 * 60);
        compare(policy.startMinute("2026-08-18", "2026-08-18", 23 * 60 + 58, 15, 30),
                23 * 60 + 30);
    }

    function test_a_missing_snap_or_length_falls_back() {
        // The view hands these down from tokens; a zero means a binding that
        // has not resolved yet, and a divide by it would put the chip at NaN.
        compare(policy.startMinute("2026-08-18", "2026-08-18", testCase.nowMin, 0, 0),
                13 * 60 + 45);
    }

    function test_no_today_at_all_is_still_a_time() {
        // Before the clock has ticked once, `todayIso` is "". A create then is
        // rare but must not land at NaN.
        compare(policy.startMinute("2026-08-18", "", testCase.nowMin, 15, 60), 9 * 60);
    }

    // --- where the quick-create panel goes ------------------------------------

    readonly property var chip: ({ "x": 300, "y": 200, "width": 120, "height": 84 })

    function test_the_panel_sits_to_the_right_of_its_chip() {
        const at = policy.popoverAnchor(testCase.chip, 320, 260, 1000, 700, 8, 8);
        compare(at.x, 428);          // 300 + 120 + 8
        compare(at.y, 200);          // aligned with the chip's own top edge
        compare(at.flipped, false);
    }

    function test_a_chip_against_the_right_edge_flips_the_panel() {
        // Saturday's column: 320 of panel plus both gaps will not fit to the
        // right, and the whole panel does fit to the left, so it goes there
        // rather than sliding back over the chip it names.
        const at = policy.popoverAnchor({ "x": 820, "y": 100, "width": 120, "height": 84 },
                                        320, 260, 1000, 700, 8, 8);
        compare(at.x, 492);          // 820 - 8 - 320
        compare(at.flipped, true);
    }

    function test_a_grid_too_narrow_for_either_side_clamps_instead() {
        // 400px of view, 320 of panel: neither side fits, so it gives up on
        // beside and stays on screen — the one case where it overlaps.
        const at = policy.popoverAnchor({ "x": 200, "y": 40, "width": 100, "height": 60 },
                                        320, 260, 400, 700, 8, 8);
        compare(at.x, 72);           // 400 - 320 - 8
        verify(at.x >= 8);
    }

    function test_a_chip_at_the_bottom_slides_the_panel_up_to_fit() {
        const at = policy.popoverAnchor({ "x": 100, "y": 640, "width": 120, "height": 30 },
                                        320, 260, 1000, 700, 8, 8);
        compare(at.y, 432);          // 700 - 260 - 8
    }

    function test_a_panel_taller_than_the_view_still_starts_on_screen() {
        // The margin wins over the clamp: a panel that cannot fit is pinned to
        // the top rather than pushed off it by a negative maximum.
        const at = policy.popoverAnchor(testCase.chip, 320, 900, 1000, 700, 8, 8);
        compare(at.y, 8);
    }

    function test_the_gap_and_the_margin_may_both_be_left_out() {
        // A caller mid-binding hands zeros; the panel must still be beside the
        // chip and on screen rather than at NaN.
        const at = policy.popoverAnchor(null, 320, 260, 1000, 700, -1, -1);
        compare(at.x, 8);
        compare(at.y, 8);
    }

    // --- the caret ----------------------------------------------------------------
    //
    // The panel sits *beside* its chip with a gap between them, and a gap says
    // nothing about which of the six chips in that column the panel is about.
    // The caret does, so where it points is a decision and not a decoration.

    function test_the_caret_points_at_the_middle_of_the_chip() {
        // A 60-tall chip at y=200 in a panel placed at its own top: the middle
        // is 30 below the panel's top edge.
        const at = policy.popoverAnchor({ "x": 100, "y": 200, "width": 120, "height": 60 },
                                        320, 200, 1000, 800, 8, 8);
        compare(at.y, 200);
        compare(at.caretY, 30);
    }

    // A chip near the bottom pushes the panel up, and the caret has to follow
    // the chip rather than the panel — otherwise it points at the wrong hour.
    function test_the_caret_follows_the_chip_when_the_panel_slides_up() {
        const at = policy.popoverAnchor({ "x": 100, "y": 700, "width": 120, "height": 40 },
                                        320, 300, 1000, 800, 8, 8);
        compare(at.y, 492);
        compare(at.caretY, 228);
    }

    // And when the chip is so far off that the middle would land on the panel's
    // rounded corner, the caret stops at the inset instead of hanging off it.
    function test_the_caret_never_lands_on_a_corner() {
        const high = policy.popoverAnchor({ "x": 100, "y": 0, "width": 120, "height": 20 },
                                          320, 300, 1000, 800, 8, 8);
        compare(high.caretY, 12);
        const low = policy.popoverAnchor({ "x": 100, "y": 780, "width": 120, "height": 20 },
                                         320, 300, 1000, 800, 8, 8);
        compare(low.caretY, 288);
    }

    function test_an_anchor_with_no_height_still_gets_a_caret() {
        const at = policy.popoverAnchor({ "x": 100, "y": 200, "width": 120 },
                                        320, 200, 1000, 800, 8, 8);
        compare(at.caretY, 12);
    }
}
