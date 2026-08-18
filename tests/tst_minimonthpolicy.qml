// The sidebar mini-month's arithmetic.
//
// August 2026 again, for the same reason `tst_monthpolicy.qml` picks it: it
// opens on a Saturday and closes on a Monday, so with a Sunday-first week both
// its first and last rows straddle a month boundary — which is exactly where a
// band that is "the week you are looking at" either survives or turns into a
// band that stops at the edge of the month.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "MiniMonthPolicy"

    MiniMonthPolicy { id: policy }
    MonthPolicy { id: months }

    /// August 2026, Sunday-first. Row 0 is 26 July - 1 August; row 3 holds
    /// Tuesday the 18th.
    readonly property var grid: months.grid("2026-08-18", 0, "2026-08-18")

    function isos(row: var): string {
        return (row || []).map(cell => cell.iso).join(",");
    }

    // --- the letters ---------------------------------------------------------

    function test_initials_are_two_letters_each() {
        compare(policy.initials(0).join(" "), "Su Mo Tu We Th Fr Sa");
        compare(policy.initials(1).join(" "), "Mo Tu We Th Fr Sa Su");
    }

    function test_initials_are_never_ambiguous() {
        // The point of the second letter: at one letter both Ts and both Ss
        // collide, so the row cannot say which end the week starts at.
        const seen = policy.initials(1);
        for (let i = 0; i < seen.length; i++) {
            compare(seen[i].length, 2);
            compare(seen.indexOf(seen[i]), i, seen.join(" "));
        }
    }

    // --- the band ------------------------------------------------------------

    function test_week_band_covers_the_whole_row() {
        const row = testCase.grid[3];
        verify(testCase.isos(row).indexOf("2026-08-18") >= 0);
        const band = policy.band(row, "week", "2026-08-18");
        compare(band.start, 0);
        compare(band.end, 6);
    }

    function test_week_band_is_absent_from_other_rows() {
        compare(policy.band(testCase.grid[2], "week", "2026-08-18"), null);
        compare(policy.band(testCase.grid[4], "week", "2026-08-18"), null);
    }

    /// The 1st of August lives in row 0 beside six days of July. A week view
    /// anchored there is showing those six July days, so the band is the whole
    /// row and not a stub that stops where the month starts.
    function test_week_band_survives_a_row_that_straddles_two_months() {
        const row = testCase.grid[0];
        compare(testCase.isos(row).split(",")[0], "2026-07-26");
        const band = policy.band(row, "week", "2026-08-01");
        compare(band.start, 0);
        compare(band.end, 6);
    }

    function test_day_band_is_one_cell() {
        const band = policy.band(testCase.grid[3], "day", "2026-08-18");
        compare(band.start, 2);
        compare(band.end, 2);
    }

    function test_month_view_gets_no_band() {
        compare(policy.band(testCase.grid[3], "month", "2026-08-18"), null);
    }

    function test_band_refuses_rubbish() {
        compare(policy.band(testCase.grid[3], "week", ""), null);
        compare(policy.band(testCase.grid[3], "week", "not-a-day"), null);
        compare(policy.band([], "week", "2026-08-18"), null);
        compare(policy.band(null, "week", "2026-08-18"), null);
    }

    function test_in_band_matches_the_range() {
        verify(policy.inBand(testCase.grid[3], "week", "2026-08-18", 0));
        verify(policy.inBand(testCase.grid[3], "week", "2026-08-18", 6));
        verify(!policy.inBand(testCase.grid[2], "week", "2026-08-18", 3));
        verify(policy.inBand(testCase.grid[3], "day", "2026-08-18", 2));
        verify(!policy.inBand(testCase.grid[3], "day", "2026-08-18", 3));
    }

    // --- the month the sidebar is showing ------------------------------------

    function test_snap_month_keeps_a_paged_sidebar_within_the_anchor_month() {
        // Paged to the 1st of August while the grid sits on the 18th: same
        // month, so the sidebar keeps the day it was paged to.
        compare(policy.snapMonth("2026-08-01", "2026-08-18"), "2026-08-01");
    }

    function test_snap_month_follows_the_anchor_out_of_the_month() {
        compare(policy.snapMonth("2026-12-01", "2026-08-18"), "2026-08-18");
    }

    function test_snap_month_recovers_from_an_empty_display() {
        compare(policy.snapMonth("", "2026-08-18"), "2026-08-18");
        compare(policy.snapMonth("2026-08-01", ""), "2026-08-01");
    }

    function test_step_clamps_the_day_like_the_toolbar_does() {
        compare(policy.step("2026-08-18", 1), months.shiftMonths("2026-08-18", 1));
        compare(policy.step("2026-01-31", 1), "2026-02-28");
        compare(policy.step("2026-08-18", -1), "2026-07-18");
    }

    // --- the calendar list ---------------------------------------------------

    function test_rows_title_case_every_hue_in_wheel_order() {
        const hues = { "names": ["glacier", "moss", "stone"] };
        const rows = policy.rows(hues);
        compare(rows.length, 3);
        compare(rows[0].index, 0);
        compare(rows[0].label, "Glacier");
        compare(rows[2].name, "stone");
        compare(rows[2].label, "Stone");
    }

    function test_rows_of_nothing_is_an_empty_list() {
        compare(policy.rows(null).length, 0);
        compare(policy.rows({}).length, 0);
    }
}
