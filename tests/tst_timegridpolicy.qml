// The week grid's arithmetic: minutes to pixels, pixels to days.
//
// The cases here are the ones a picture cannot show you. A grid that is off by
// one column or by one hour still looks like a calendar — every line is where
// a line belongs — so the failures are silent ones: an event drawn on Tuesday
// that is Wednesday's, a drag that lands fifteen minutes from where the pointer
// was, a 22:00-02:00 event that vanishes instead of appearing twice.
//
// So the boundaries are what is checked: the edge between the gutter and the
// first column, the right edge of the last one, midnight in both directions,
// the week whose first day is not Sunday, and the month end a run of days
// crosses.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "TimeGridPolicy"

    TimeGridPolicy { id: grid }

    // The grid the tests measure against: a 60 px hour and seven 100 px columns
    // behind a 60 px gutter, so every expected number below is arithmetic a
    // reader can do in their head.
    readonly property real gutter: 60
    readonly property real gridWidth: 760

    // --- the vertical axis ----------------------------------------------------

    function test_minutes_and_pixels_are_inverses() {
        compare(grid.minutesToY(0, 60), 0);
        compare(grid.minutesToY(90, 60), 90);
        compare(grid.minutesToY(90, 80), 120);
        compare(grid.minutesToY(1440, 60), 1440);
        compare(grid.yToMinutes(120, 80), 90);
        compare(grid.yToMinutes(grid.minutesToY(555, 44), 44), 555);
    }

    function test_the_hour_height_falls_back_to_the_property() {
        compare(grid.minutesToY(60), 60);
        grid.hourHeight = 96;
        compare(grid.minutesToY(60), 96);
        compare(grid.dayHeight(), 24 * 96);
        // An explicit argument still wins over it.
        compare(grid.minutesToY(60, 60), 60);
        grid.hourHeight = 60;
    }

    function test_a_collapsed_hour_is_loud_rather_than_midnight() {
        // A zero-height hour would put every minute of the day at y=0 and every
        // drag at midnight, which reads as a working grid.
        verify(isNaN(grid.hourPixels(0)));
        verify(isNaN(grid.hourPixels(-20)));
        verify(isNaN(grid.minutesToY(600, 0)));
        verify(isNaN(grid.dayHeight(0)));
    }

    function test_snap_rounds_to_the_nearest_line() {
        compare(grid.snap(547), 540);
        compare(grid.snap(548), 555);
        compare(grid.snap(7.5), 15);      // a half goes forward
        compare(grid.snap(0), 0);
        compare(grid.snap(1440), 1440);
        compare(grid.snap(547, 30), 540);
        compare(grid.snap(547, 5), 545);
        compare(grid.snap(547, 0), 547);  // a no-op, not a division by zero
    }

    function test_clampMinutes_keeps_a_point_inside_the_day() {
        compare(grid.clampMinutes(-30), 0);
        compare(grid.clampMinutes(0), 0);
        compare(grid.clampMinutes(555), 555);
        compare(grid.clampMinutes(1440), 1440);   // midnight is a real bound
        compare(grid.clampMinutes(1500), 1440);
        verify(isNaN(grid.clampMinutes(NaN)));
    }

    // --- the hour gutter ------------------------------------------------------

    function test_a_twelve_hour_label_names_noon_and_midnight() {
        compare(grid.hourLabel(0, false), "12 AM");
        compare(grid.hourLabel(1, false), "1 AM");
        compare(grid.hourLabel(11, false), "11 AM");
        compare(grid.hourLabel(12, false), "12 PM");
        compare(grid.hourLabel(13, false), "1 PM");
        compare(grid.hourLabel(23, false), "11 PM");
    }

    function test_a_twenty_four_hour_label_is_padded() {
        compare(grid.hourLabel(1, true), "01:00");
        compare(grid.hourLabel(9, true), "09:00");
        compare(grid.hourLabel(13, true), "13:00");
        compare(grid.hourLabel(23, true), "23:00");
    }

    function test_the_gutter_runs_one_to_twenty_three() {
        // Midnight and 24:00 sit on the edges of the grid, where half the glyph
        // would be clipped, so neither is drawn.
        const labels = grid.hourLabels(false, 60);
        compare(labels.length, 23);
        compare(labels[0].hour, 1);
        compare(labels[0].label, "1 AM");
        compare(labels[0].y, 60);
        compare(labels[22].hour, 23);
        compare(labels[22].label, "11 PM");
        compare(labels[22].y, 1380);
        compare(grid.hourLabels(true, 80)[12].label, "13:00");
        compare(grid.hourLabels(true, 80)[12].y, 13 * 80);
    }

    // --- the now-line ---------------------------------------------------------

    function test_the_now_line_reads_the_minutes_of_a_stamp() {
        compare(grid.nowLineY("2026-08-18T13:40", 60), 820);
        compare(grid.nowLineY("2026-08-18T00:00", 60), 0);
        compare(grid.nowLineY("2026-08-18T23:59", 60), 1439);
    }

    function test_a_stamp_that_is_not_one_hides_the_now_line() {
        compare(grid.nowLineY("", 60), -1);
        compare(grid.nowLineY("2026-08-18", 60), -1);
        compare(grid.nowLineY("nope", 60), -1);
    }

    // --- columns --------------------------------------------------------------

    function test_the_weekend_is_saturday_and_sunday() {
        verify(grid.isWeekend("2026-08-22"));   // Saturday
        verify(grid.isWeekend("2026-08-23"));   // Sunday
        verify(!grid.isWeekend("2026-08-18"));  // Tuesday
        verify(!grid.isWeekend("nope"));
    }

    function test_seven_columns_are_the_week_the_anchor_falls_in() {
        // 2026-08-18 is a Tuesday; a Monday-first week opens on the 17th.
        const cols = grid.dayColumns("2026-08-18", 1, 7, "2026-08-18");
        compare(cols.length, 7);
        compare(cols[0].iso, "2026-08-17");
        compare(cols[6].iso, "2026-08-23");
        compare(cols[0].weekday, 1);
        compare(cols[0].dayNumber, 17);
        compare(cols[1].isToday, true);
        compare(cols[0].isToday, false);
        compare(cols[4].isWeekend, false);   // Friday
        compare(cols[5].isWeekend, true);    // Saturday
        compare(cols[6].isWeekend, true);    // Sunday
    }

    function test_the_first_day_moves_the_week_but_not_the_weekend() {
        const cols = grid.dayColumns("2026-08-18", 0, 7, "");
        compare(cols[0].iso, "2026-08-16");   // the Sunday before
        compare(cols[6].iso, "2026-08-22");
        compare(cols[0].isWeekend, true);     // Sunday, now first
        compare(cols[6].isWeekend, true);     // Saturday, now last
        compare(cols[1].isWeekend, false);
    }

    function test_one_column_is_the_anchor_itself() {
        const cols = grid.dayColumns("2026-08-18", 1, 1, "2026-08-18");
        compare(cols.length, 1);
        compare(cols[0].iso, "2026-08-18");
        compare(cols[0].dayNumber, 18);
        compare(cols[0].weekday, 2);
        compare(cols[0].isToday, true);
    }

    function test_any_other_count_is_a_run_from_the_anchor() {
        const cols = grid.dayColumns("2026-08-30", 1, 3, "");
        compare(cols.length, 3);
        compare(cols[0].iso, "2026-08-30");
        compare(cols[1].dayNumber, 31);
        compare(cols[2].iso, "2026-09-01");   // the month end is not a wall
        compare(cols[2].dayNumber, 1);
    }

    function test_a_view_with_no_days_has_no_columns() {
        compare(grid.dayColumns("2026-08-18", 1, 0, "").length, 0);
        compare(grid.dayColumns("2026-02-30", 1, 7, "").length, 0);
        compare(grid.dayColumns("", 1, 7, "").length, 0);
    }

    function test_every_call_returns_a_fresh_array() {
        // A same-length model edited in place does not rebuild its delegates
        // (#195), so navigation has to hand the Repeater a new array.
        const a = grid.dayColumns("2026-08-18", 1, 7, "");
        const b = grid.dayColumns("2026-08-18", 1, 7, "");
        verify(a !== b);
        verify(a[0] !== b[0]);
    }

    // --- x to column ----------------------------------------------------------

    function test_a_column_is_the_grid_minus_the_gutter_divided_up() {
        compare(grid.columnWidth(testCase.gutter, testCase.gridWidth, 7), 100);
        compare(grid.columnWidth(testCase.gutter, testCase.gridWidth, 1), 700);
        verify(isNaN(grid.columnWidth(60, 60, 7)));    // nothing left over
        verify(isNaN(grid.columnWidth(60, 760, 0)));
    }

    function test_x_lands_in_the_column_it_is_over() {
        compare(grid.columnForX(60, testCase.gutter, testCase.gridWidth, 7), 0);
        compare(grid.columnForX(159, testCase.gutter, testCase.gridWidth, 7), 0);
        compare(grid.columnForX(160, testCase.gutter, testCase.gridWidth, 7), 1);
        compare(grid.columnForX(360, testCase.gutter, testCase.gridWidth, 7), 3);
        compare(grid.columnForX(759.9, testCase.gutter, testCase.gridWidth, 7), 6);
        compare(grid.columnForX(400, testCase.gutter, testCase.gridWidth, 1), 0);
    }

    function test_the_gutter_and_the_edges_belong_to_no_column() {
        // -1 is what lets a view refuse a drag rather than start one on Monday.
        compare(grid.columnForX(0, testCase.gutter, testCase.gridWidth, 7), -1);
        compare(grid.columnForX(59.9, testCase.gutter, testCase.gridWidth, 7), -1);
        compare(grid.columnForX(760, testCase.gutter, testCase.gridWidth, 7), -1);
        compare(grid.columnForX(2000, testCase.gutter, testCase.gridWidth, 7), -1);
        compare(grid.columnForX(-5, testCase.gutter, testCase.gridWidth, 7), -1);
        compare(grid.columnForX(100, 60, 60, 7), -1);
    }

    function test_a_column_index_and_an_x_round_trip() {
        for (let i = 0; i < 7; i++) {
            const x = grid.xForColumn(i, testCase.gutter, testCase.gridWidth, 7);
            compare(x, 60 + i * 100);
            compare(grid.columnForX(x, testCase.gutter, testCase.gridWidth, 7), i);
        }
        verify(isNaN(grid.xForColumn(7, testCase.gutter, testCase.gridWidth, 7)));
        verify(isNaN(grid.xForColumn(-1, testCase.gutter, testCase.gridWidth, 7)));
    }

    // --- a point on the grid --------------------------------------------------

    function test_a_grid_point_is_a_day_and_a_snapped_minute() {
        const cols = grid.dayColumns("2026-08-18", 1, 7, "");
        const p = grid.gridPointToStamp(360, 547, cols, testCase.gutter, testCase.gridWidth, 60, 15);
        compare(p.iso, "2026-08-20");   // the fourth column of a Monday week
        compare(p.minutes, 540);
    }

    function test_a_grid_point_clamps_to_the_end_of_the_day() {
        const cols = grid.dayColumns("2026-08-18", 1, 7, "");
        // 1450 px is past midnight; snapping alone would round it further past.
        const p = grid.gridPointToStamp(100, 1450, cols, testCase.gutter, testCase.gridWidth, 60, 15);
        compare(p.minutes, 1440);
        compare(grid.gridPointToStamp(100, -30, cols, testCase.gutter, testCase.gridWidth, 60, 15).minutes, 0);
    }

    function test_a_grid_point_off_the_columns_is_null() {
        const cols = grid.dayColumns("2026-08-18", 1, 7, "");
        compare(grid.gridPointToStamp(30, 500, cols, testCase.gutter, testCase.gridWidth, 60, 15), null);
        compare(grid.gridPointToStamp(800, 500, cols, testCase.gutter, testCase.gridWidth, 60, 15), null);
        compare(grid.gridPointToStamp(360, 500, [], testCase.gutter, testCase.gridWidth, 60, 15), null);
        compare(grid.gridPointToStamp(360, 500, null, testCase.gutter, testCase.gridWidth, 60, 15), null);
    }

    function test_a_day_view_point_uses_the_only_column() {
        const cols = grid.dayColumns("2026-08-18", 1, 1, "");
        const p = grid.gridPointToStamp(400, 600, cols, testCase.gutter, testCase.gridWidth, 60, 15);
        compare(p.iso, "2026-08-18");
        compare(p.minutes, 600);
    }

    // --- opening scroll -------------------------------------------------------

    function test_the_view_opens_on_the_working_day() {
        compare(grid.visibleScrollY(), 420);            // 7am at a 60 px hour
        compare(grid.visibleScrollY(7, 80), 560);
        compare(grid.visibleScrollY(0, 60), 0);
    }

    function test_the_opening_scroll_never_runs_off_the_bottom() {
        // With a viewport the last hour still has to be reachable.
        compare(grid.visibleScrollY(20, 60, 400), 1040);   // 1440 - 400
        compare(grid.visibleScrollY(7, 60, 2000), 0);      // taller than the day
        compare(grid.visibleScrollY(7, 60, 400), 420);     // no clamp needed
        compare(grid.visibleScrollY(7, 60), 420);          // unclamped without one
    }

    // --- events ---------------------------------------------------------------

    function test_an_event_inside_one_day_is_its_own_rect() {
        const r = grid.eventRect("2026-08-18T09:00", "2026-08-18T10:30", "2026-08-18", 60);
        compare(r.y, 540);
        compare(r.h, 90);
        compare(r.continuesAbove, false);
        compare(r.continuesBelow, false);
    }

    function test_an_event_crossing_midnight_is_clipped_to_each_day() {
        const first = grid.eventRect("2026-08-18T22:00", "2026-08-19T02:00", "2026-08-18", 60);
        compare(first.y, 1320);
        compare(first.h, 120);          // 22:00 to the bottom of the day
        compare(first.continuesBelow, true);
        compare(first.continuesAbove, false);

        const second = grid.eventRect("2026-08-18T22:00", "2026-08-19T02:00", "2026-08-19", 60);
        compare(second.y, 0);
        compare(second.h, 120);
        compare(second.continuesAbove, true);
        compare(second.continuesBelow, false);
    }

    function test_a_multi_day_event_fills_the_days_between() {
        const middle = grid.eventRect("2026-08-18T00:00", "2026-08-21T00:00", "2026-08-19", 60);
        compare(middle.y, 0);
        compare(middle.h, 1440);
        compare(middle.continuesAbove, true);
        compare(middle.continuesBelow, true);

        const last = grid.eventRect("2026-08-18T00:00", "2026-08-21T00:00", "2026-08-20", 60);
        compare(last.h, 1440);
        compare(last.continuesBelow, false);   // it ends exactly at midnight
    }

    function test_an_event_that_is_not_on_the_day_has_no_rect() {
        compare(grid.eventRect("2026-08-18T09:00", "2026-08-18T10:00", "2026-08-19", 60), null);
        compare(grid.eventRect("2026-08-18T09:00", "2026-08-18T10:00", "2026-08-17", 60), null);
        // `end` is exclusive, so midnight belongs to the day before it only.
        compare(grid.eventRect("2026-08-18T22:00", "2026-08-19T00:00", "2026-08-19", 60), null);
    }

    function test_a_zero_length_or_backwards_event_has_no_rect() {
        compare(grid.eventRect("2026-08-18T09:00", "2026-08-18T09:00", "2026-08-18", 60), null);
        compare(grid.eventRect("2026-08-18T10:00", "2026-08-18T09:00", "2026-08-18", 60), null);
    }

    function test_an_event_with_a_bad_stamp_has_no_rect() {
        compare(grid.eventRect("nope", "2026-08-18T10:00", "2026-08-18", 60), null);
        compare(grid.eventRect("2026-08-18T09:00", "", "2026-08-18", 60), null);
        compare(grid.eventRect("2026-08-18T09:00", "2026-08-18T10:00", "2026-02-30", 60), null);
    }

    // --- the cases a round grid hides -----------------------------------------
    //
    // Everything above measures a 100 px column. No real window gives one: a
    // week is seven columns of whatever is left after the gutter, so the width
    // is fractional almost always, and the arithmetic has to survive that.

    function test_a_fractional_column_and_an_x_still_round_trip() {
        // `gutter + i * w` and `(x - gutter) / w` are two roundings of the same
        // number and disagree by an ulp on a width that does not divide evenly,
        // which put a click on a column's own left edge one day earlier. Each
        // pair below is one that did: 80/800 lost Thursday and Sunday, 60/1115
        // lost Thursday, 60/800.5 lost Tuesday and Wednesday.
        const grids = [[80, 800], [60, 1115], [64, 1112], [60, 800.5], [72, 802]];
        for (let g = 0; g < grids.length; g++) {
            const gut = grids[g][0];
            const wide = grids[g][1];
            for (let i = 0; i < 7; i++)
                compare(grid.columnForX(grid.xForColumn(i, gut, wide, 7), gut, wide, 7), i);
        }
    }

    function test_a_sweep_across_a_fractional_grid_never_goes_backwards() {
        // A column that is skipped or revisited is a drag that jumps a day
        // mid-gesture, which no picture shows.
        let prev = -1;
        for (let k = 0; k < 2000; k++) {   // the right edge itself is -1, by design
            const x = 60 + (761 - 60) * k / 2000;
            const c = grid.columnForX(x, 60, 761, 7);
            verify(c >= prev);
            prev = c;
        }
        compare(prev, 6);
    }

    function test_the_week_is_aligned_even_when_the_anchor_precedes_its_first_day() {
        // The Sunday of a Monday-first week belongs to the week that *opened*
        // on the Monday before it, not to the one starting the next day.
        const mon = grid.dayColumns("2026-08-16", 1, 7, "");   // Sunday anchor
        compare(mon[0].iso, "2026-08-10");
        compare(mon[6].iso, "2026-08-16");
        compare(mon[6].isWeekend, true);
        // And the mirror case: a Saturday anchor in a Sunday-first week.
        const sun = grid.dayColumns("2026-08-22", 0, 7, "");
        compare(sun[0].iso, "2026-08-16");
        compare(sun[6].iso, "2026-08-22");
    }

    function test_columns_cross_a_year_end() {
        const run = grid.dayColumns("2026-12-30", 1, 4, "");
        compare(run[2].iso, "2027-01-01");
        compare(run[3].dayNumber, 2);
        const week = grid.dayColumns("2027-01-01", 1, 7, "");
        compare(week[0].iso, "2026-12-28");
        compare(week[6].iso, "2027-01-03");
    }

    function test_a_count_that_is_not_a_whole_positive_number() {
        compare(grid.dayColumns("2026-08-18", 1, -3, "").length, 0);
        compare(grid.dayColumns("2026-08-18", 1, 2.6, "").length, 3);
        // 6.5 rounds to seven, which is the *week*, not six days plus a half.
        compare(grid.dayColumns("2026-08-18", 1, 6.5, "")[0].iso, "2026-08-17");
    }

    function test_a_step_that_does_not_divide_the_day_still_stops_at_midnight() {
        // Snap runs to the nearest line and can leave the day; the clamp after
        // it is what keeps a drag near midnight out of tomorrow.
        const cols = grid.dayColumns("2026-08-18", 1, 7, "");
        compare(grid.gridPointToStamp(100, 1439, cols, testCase.gutter, testCase.gridWidth, 60, 7).minutes, 1440);
        compare(grid.snap(1439, 7), 1442);
    }

    function test_the_opening_scroll_clamps_an_hour_outside_the_day() {
        compare(grid.visibleScrollY(30, 60), 1440);
        compare(grid.visibleScrollY(-5, 60), 0);
        compare(grid.visibleScrollY(24, 60, 400), 1040);
    }

    function test_a_time_that_is_not_on_a_clock_hides_the_now_line() {
        compare(grid.nowLineY("2026-08-18T24:00", 60), -1);
        compare(grid.nowLineY("2026-08-18T09:60", 60), -1);
        compare(grid.nowLineY("2026-13-01T09:00", 60), -1);
    }

    function test_an_event_rect_falls_back_to_the_property_hour_height() {
        grid.hourHeight = 96;
        const r = grid.eventRect("2026-08-18T09:00", "2026-08-18T10:30", "2026-08-18");
        grid.hourHeight = 60;   // restored before the asserts: TestCase shares
                                // one `grid`, so a throw here would otherwise
                                // leave every later case measuring a 96 px hour
        compare(r.y, 9 * 96);
        compare(r.h, 1.5 * 96);
    }
}
