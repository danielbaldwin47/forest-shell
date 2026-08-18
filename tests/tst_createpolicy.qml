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
}
