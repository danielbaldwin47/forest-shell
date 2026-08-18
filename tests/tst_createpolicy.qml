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
}
