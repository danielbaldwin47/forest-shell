// The month view's arithmetic.
//
// Three shapes are checked here and they fail in three different ways. The
// **grid** fails at its corners — the days of the neighbouring months that fill
// the first and last rows, where a cell that knows only its number cannot say
// which September the 1st it is. **Cell contents** fail at the cap: what a
// short cell hides, and in which order, is the whole of the month view's
// information design, and "+2 more" that is really +3 is a lie the user cannot
// see. **Spans** fail at the row boundary — an event crossing Saturday into
// Sunday is two bars, and every off-by-one in this file lives in the four
// columns of that seam.
//
// August 2026 is the fixture month throughout because it is the awkward one:
// it opens on a Saturday, so with a Sunday-first week its first row is six
// days of July, and it closes on a Monday, so its last row is five days of
// September.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "MonthPolicy"

    MonthPolicy { id: policy }

    /// Tuesday the 18th of August 2026, and the days around it. Deliberately
    /// mixed: two banners of different kinds (an all-day one and a timed one
    /// that outlives its day) against three ordinary chips.
    readonly property var sample: [
        { "id": "evt-a", "title": "Standup", "start": "2026-08-18T09:00", "end": "2026-08-18T09:30", "allDay": false },
        { "id": "evt-b", "title": "Design review", "start": "2026-08-18T10:00", "end": "2026-08-18T11:30", "allDay": false },
        { "id": "evt-c", "title": "Coffee with Opal", "start": "2026-08-18T15:00", "end": "2026-08-18T15:45", "allDay": false },
        { "id": "evt-d", "title": "Deploy freeze", "start": "2026-08-18T00:00", "end": "2026-08-19T00:00", "allDay": true },
        { "id": "evt-e", "title": "Nordic QML Days", "start": "2026-08-17T09:00", "end": "2026-08-20T17:00", "allDay": false }
    ]

    function ids(list: var): string {
        return (list || []).map(function (event) {
            return event.id;
        }).join(",");
    }

    function segmentIds(segments: var): string {
        return (segments || []).map(function (segment) {
            return segment.id;
        }).join(",");
    }

    function byId(segments: var, id: string): var {
        for (const segment of (segments || [])) {
            if (segment.id === id)
                return segment;
        }
        return null;
    }

    // --- the grid -------------------------------------------------------------

    function test_the_grid_is_always_six_rows_of_seven() {
        const grid = policy.grid("2026-08-18", 0, "");
        compare(grid.length, 6);
        for (const row of grid)
            compare(row.length, 7);
    }

    function test_august_2026_opens_on_a_saturday_so_six_july_days_lead_it() {
        // Sunday-first: the 1st is a Saturday, so it lands in the last column.
        const grid = policy.grid("2026-08-18", 0, "");
        compare(grid[0][0].iso, "2026-07-26");
        compare(grid[0][0].inMonth, false);
        compare(grid[0][6].iso, "2026-08-01");
        compare(grid[0][6].day, 1);
        compare(grid[0][6].inMonth, true);
    }

    function test_the_last_row_is_september_and_says_so() {
        const grid = policy.grid("2026-08-18", 0, "");
        compare(grid[5][0].iso, "2026-08-30");
        compare(grid[5][0].inMonth, true);
        compare(grid[5][2].iso, "2026-09-01");
        compare(grid[5][2].day, 1);
        compare(grid[5][2].inMonth, false);
    }

    function test_a_monday_first_week_shifts_the_whole_grid_by_one() {
        const grid = policy.grid("2026-08-18", 1, "");
        compare(grid[0][0].iso, "2026-07-27");
        compare(grid[3][0].iso, "2026-08-17");
        compare(grid[3][1].iso, "2026-08-18");
    }

    function test_a_first_day_outside_zero_to_six_wraps_rather_than_breaking() {
        compare(policy.grid("2026-08-18", 7, "")[0][0].iso,
                policy.grid("2026-08-18", 0, "")[0][0].iso);
        // -1 is Saturday-first, and August 2026 opens on a Saturday — so that
        // grid needs no leading days at all.
        compare(policy.grid("2026-08-18", -1, "")[0][0].iso, "2026-08-01");
    }

    function test_the_weekend_is_saturday_and_sunday_whatever_the_first_day() {
        const sundayFirst = policy.grid("2026-08-18", 0, "");
        compare(sundayFirst[3][0].isWeekend, true);    // Sunday the 16th
        compare(sundayFirst[3][1].isWeekend, false);   // Monday
        compare(sundayFirst[3][6].isWeekend, true);    // Saturday the 22nd

        const mondayFirst = policy.grid("2026-08-18", 1, "");
        compare(mondayFirst[3][0].isWeekend, false);   // Monday the 17th
        compare(mondayFirst[3][5].isWeekend, true);    // Saturday the 22nd
        compare(mondayFirst[3][6].isWeekend, true);    // Sunday the 23rd
    }

    /// The header's weekend columns have to agree with the cells under them —
    /// a header washed on the wrong two columns is worse than an unwashed one.
    function test_the_header_marks_the_same_two_columns_the_cells_do() {
        const monday = policy.weekendColumns(1);
        compare(monday.length, 7);
        compare(monday, [false, false, false, false, false, true, true]);

        const sunday = policy.weekendColumns(0);
        compare(sunday, [true, false, false, false, false, false, true]);

        // Every column agrees with the row of cells beneath it, which is the
        // only claim that actually matters.
        for (const first of [0, 1, 3, 6]) {
            const cols = policy.weekendColumns(first);
            const week = policy.grid("2026-08-18", first, "")[3];
            for (let c = 0; c < 7; c++)
                compare(cols[c], week[c].isWeekend, "column " + c + " first " + first);
        }
    }

    function test_a_header_first_day_outside_the_week_wraps_like_the_grid() {
        compare(policy.weekendColumns(8), policy.weekendColumns(1));
        compare(policy.weekendColumns(-6), policy.weekendColumns(1));
        compare(policy.weekendColumns(15), policy.weekendColumns(1));
        // Junk never reaches the arithmetic: the parameter is typed `int`, so
        // the engine coerces a NaN to 0 before the function is entered. Asserted
        // so nobody "fixes" the NaN guard into a different default.
        compare(policy.weekendColumns(NaN), policy.weekendColumns(0));
    }

    /// The bug CalendarPolicy.isToday was written against: the 1st of September
    /// sits in August's last row, and a day-number match alone would light two
    /// cells on the 1st of August.
    function test_exactly_one_cell_is_today_even_when_today_is_a_corner() {
        function todays(grid) {
            let count = 0;
            for (const row of grid) {
                for (const cell of row) {
                    if (cell.isToday)
                        count++;
                }
            }
            return count;
        }
        const first = policy.grid("2026-08-18", 0, "2026-09-01");
        compare(todays(first), 1);
        compare(first[5][2].isToday, true);
        compare(todays(policy.grid("2026-08-18", 0, "2026-08-01")), 1);
    }

    function test_no_today_is_claimed_when_none_is_given() {
        for (const grid of [policy.grid("2026-08-18", 0, ""),
                            policy.grid("2026-08-18", 0),
                            policy.grid("2026-08-18", 0, "not a day")]) {
            for (const row of grid) {
                for (const cell of row)
                    compare(cell.isToday, false);
            }
        }
    }

    function test_a_bad_anchor_is_an_empty_grid_and_not_a_guess() {
        compare(policy.grid("2026-8-18", 0, "").length, 0);
        compare(policy.grid("2026-02-30", 0, "").length, 0);
        compare(policy.grid("", 0, "").length, 0);
    }

    /// The grid is a window onto the calendar and not six independent weeks:
    /// walking it cell by cell has to be the same thing as adding a day at a
    /// time, corners and year boundaries included. A one-cell slip in the
    /// leading-days arithmetic survives every spot check above and dies here.
    function test_a_grid_is_forty_two_consecutive_days_from_the_first_day() {
        for (const anchor of ["2026-08-18", "2026-12-15", "2027-01-04", "2028-02-10"]) {
            for (const firstDay of [0, 1, 6]) {
                const flat = [];
                for (const row of policy.grid(anchor, firstDay, "")) {
                    for (const cell of row)
                        flat.push(cell.iso);
                }
                compare(flat.length, 42, anchor);
                compare(policy.time.dayOfWeek(flat[0]), firstDay, anchor);
                for (let i = 1; i < flat.length; i++)
                    compare(flat[i], policy.time.addDays(flat[i - 1], 1), anchor + " cell " + i);
            }
        }
    }

    /// February 2027 opens on a Monday and holds 28 days, so a Sunday-first
    /// grid is full after five rows — and the sixth is March from end to end.
    /// Six rows always, even when the month has nothing left to put in one.
    function test_a_month_can_end_with_a_whole_row_of_the_next_one() {
        const grid = policy.grid("2027-02-15", 0, "");
        compare(grid[5][0].iso, "2027-03-07");
        compare(grid[5][6].iso, "2027-03-13");
        for (const cell of grid[5])
            compare(cell.inMonth, false);
    }

    /// A cell carries the real date of the day it draws, so today lands on it
    /// wherever it falls — the July days leading August included. The anchor's
    /// month decides `inMonth`; it never decides `isToday`.
    function test_today_lights_a_neighbour_month_cell_too() {
        const grid = policy.grid("2026-08-18", 0, "2026-07-28");
        compare(grid[0][2].iso, "2026-07-28");
        compare(grid[0][2].isToday, true);
        compare(grid[0][2].inMonth, false);

        let count = 0;
        for (const row of policy.grid("2026-08-18", 0, "2026-12-25")) {
            for (const cell of row) {
                if (cell.isToday)
                    count++;
            }
        }
        compare(count, 0);
    }

    // --- what a cell shows ----------------------------------------------------

    function test_a_banner_is_all_day_or_longer_than_a_day() {
        compare(policy.isBanner(testCase.sample[3]), true);   // all-day
        compare(policy.isBanner(testCase.sample[4]), true);   // timed, four days
        compare(policy.isBanner(testCase.sample[0]), false);  // 30 minutes
        compare(policy.isBanner(null), false);
    }

    function test_a_cell_splits_its_day_into_banners_and_chips() {
        const cell = policy.cellEvents(testCase.sample, "2026-08-18", -1);
        compare(testCase.ids(cell.allDay), "evt-e,evt-d");
        compare(testCase.ids(cell.timed), "evt-a,evt-b,evt-c");
        compare(cell.moreCount, 0);
    }

    function test_the_shown_order_is_banners_first_then_time_of_day() {
        const cell = policy.cellEvents(testCase.sample, "2026-08-18", 10);
        compare(testCase.ids(cell.shown), "evt-e,evt-d,evt-a,evt-b,evt-c");
    }

    function test_the_cap_decides_the_more_count() {
        const three = policy.cellEvents(testCase.sample, "2026-08-18", 3);
        compare(testCase.ids(three.shown), "evt-e,evt-d,evt-a");
        compare(three.moreCount, 2);

        // A cell too short for even one chip still tells the truth about how
        // much it is hiding.
        const none = policy.cellEvents(testCase.sample, "2026-08-18", 0);
        compare(none.shown.length, 0);
        compare(none.moreCount, 5);
    }

    function test_the_middle_day_of_a_span_shows_it_too() {
        // The 19th holds no event of its own — only the conference passing
        // through, which a naive start-of-day match would miss entirely.
        const cell = policy.cellEvents(testCase.sample, "2026-08-19", 5);
        compare(testCase.ids(cell.allDay), "evt-e");
        compare(cell.timed.length, 0);
        compare(cell.moreCount, 0);
    }

    function test_an_all_day_event_ends_the_day_it_ends_on() {
        // evt-d runs 18th 00:00 to 19th 00:00, which is one day and not two.
        compare(testCase.ids(policy.cellEvents(testCase.sample, "2026-08-19", -1).allDay), "evt-e");
    }

    function test_an_empty_day_and_a_bad_day_are_both_empty() {
        for (const cell of [policy.cellEvents(testCase.sample, "2026-08-25", 3),
                            policy.cellEvents(testCase.sample, "nope", 3),
                            policy.cellEvents(null, "2026-08-18", 3)]) {
            compare(cell.shown.length, 0);
            compare(cell.timed.length, 0);
            compare(cell.allDay.length, 0);
            compare(cell.moreCount, 0);
        }
    }

    /// Midnight decides banner from chip: an evening booked through to 00:00
    /// ends on the day it started, so it stays a chip in that cell and never
    /// becomes a bar across the next morning.
    function test_a_timed_event_running_to_midnight_stays_a_chip() {
        const evening = [{ "id": "evt-m", "title": "Release window",
                           "start": "2026-08-18T21:00", "end": "2026-08-19T00:00",
                           "allDay": false }];
        compare(policy.isBanner(evening[0]), false);
        compare(testCase.ids(policy.cellEvents(evening, "2026-08-18", -1).timed), "evt-m");
        compare(policy.cellEvents(evening, "2026-08-19", -1).shown.length, 0);
        compare(policy.spans(evening, "2026-08-16").length, 0);
    }

    function test_a_cap_above_the_day_hides_nothing_and_a_fraction_floors() {
        const generous = policy.cellEvents(testCase.sample, "2026-08-18", 99);
        compare(generous.shown.length, 5);
        compare(generous.moreCount, 0);

        // chipsPerCell answers in whole chips, but a caller doing its own
        // arithmetic can hand over a fraction — and half a chip shows nothing.
        const fraction = policy.cellEvents(testCase.sample, "2026-08-18", 2.9);
        compare(testCase.ids(fraction.shown), "evt-e,evt-d");
        compare(fraction.moreCount, 3);
    }

    // --- chip capacity --------------------------------------------------------

    function test_chips_fit_with_gaps_between_them_and_not_after() {
        // 22 header + 3x20 chip + 2x2 gap = 86, and a fourth would need 108.
        compare(policy.chipsPerCell(100), 3);
        compare(policy.chipsPerCell(108), 4);
        compare(policy.chipsPerCell(107), 3);
    }

    function test_one_chip_needs_no_gap_at_all() {
        compare(policy.chipsPerCell(42), 1);   // 22 + 20, exactly
        compare(policy.chipsPerCell(41), 0);
    }

    function test_a_cell_shorter_than_its_header_shows_nothing() {
        compare(policy.chipsPerCell(10), 0);
        compare(policy.chipsPerCell(0), 0);
        compare(policy.chipsPerCell(-40), 0);
    }

    function test_the_chip_metrics_can_be_overridden() {
        compare(policy.chipsPerCell(100, 10, 0, 0), 10);
        compare(policy.chipsPerCell(100, 18, 22, 4), 3);   // 22 + 3x18 + 2x4 = 84
    }

    /// The overrides are optional one at a time and not all or nothing: a view
    /// that only draws shorter chips says that much and keeps the header and
    /// the gap it was given.
    function test_an_omitted_chip_metric_falls_back_to_its_default() {
        compare(policy.chipsPerCell(100, undefined, undefined, undefined), 3);
        compare(policy.chipsPerCell(100, null, null, null), 3);
        compare(policy.chipsPerCell(100, 20), 3);
        compare(policy.chipsPerCell(100, 10), 6);   // 22 + 6x10 + 5x2 = 92
    }

    // --- capacity once the banners have been paid for -------------------------
    //
    // `chipsPerCell` and `laneCount` do not compose on their own, and the bug
    // that gap hides is invisible in either half: a view that sizes its chip
    // stack from the raw cell height draws one chip too many in exactly the
    // rows that have a multi-day bar in them, and it draws it under the cell's
    // own floor.

    function test_a_row_with_no_banners_costs_nothing() {
        compare(policy.chipCapacity(100, 0), policy.chipsPerCell(100));
        compare(policy.chipCapacity(100, 0), 3);
    }

    function test_each_banner_lane_costs_one_chip_row() {
        // 100px, 22 header: three chips bare, and each lane is a chip's height
        // plus the gap under it — the gap that separates the last bar from the
        // first chip.
        compare(policy.chipCapacity(100, 1), 2);
        compare(policy.chipCapacity(100, 2), 1);
        compare(policy.chipCapacity(100, 3), 0);
        compare(policy.chipCapacity(100, 9), 0);   // never negative
    }

    function test_capacity_takes_the_view_s_own_chip_metrics() {
        // The month grid draws 21px chips, not the policy's default 20, and a
        // lane that is a different height again is sayable without a second
        // function: 26 header + 1 lane of 30+2 + 2x21 + 1x2 = 102.
        compare(policy.chipCapacity(105, 1, 21, 26, 2, 30), 2);
        compare(policy.chipCapacity(101, 1, 21, 26, 2, 30), 1);
    }

    function test_lanes_that_are_not_a_number_are_no_lanes() {
        compare(policy.chipCapacity(100, undefined), 3);
        compare(policy.chipCapacity(100, -4), 3);
    }

    // --- the chips a cell draws when its banners are bars ----------------------

    function test_cell_chips_leave_the_banners_to_the_row() {
        // The 18th carries five events, two of them banners drawn as bars.
        const chips = policy.cellChips(testCase.sample, "2026-08-18", 99);
        compare(testCase.ids(chips.shown), "evt-a,evt-b,evt-c");
        compare(chips.moreCount, 0);
    }

    function test_the_more_row_is_itself_a_row() {
        // Three timed events and room for two rows: one chip and "+2 more",
        // never two chips and a third row hanging below the cell.
        const tight = policy.cellChips(testCase.sample, "2026-08-18", 2);
        compare(testCase.ids(tight.shown), "evt-a");
        compare(tight.moreCount, 2);

        // Room for exactly what is there hides nothing.
        const exact = policy.cellChips(testCase.sample, "2026-08-18", 3);
        compare(exact.shown.length, 3);
        compare(exact.moreCount, 0);
    }

    function test_a_cell_with_no_room_hides_everything_and_says_so() {
        const none = policy.cellChips(testCase.sample, "2026-08-18", 0);
        compare(none.shown.length, 0);
        compare(none.moreCount, 3);
    }

    function test_cell_chips_uncapped_and_empty() {
        compare(policy.cellChips(testCase.sample, "2026-08-18", -1).shown.length, 3);
        compare(policy.cellChips(testCase.sample, "2026-08-25", 4).shown.length, 0);
        compare(policy.cellChips(testCase.sample, "not-a-day", 4).moreCount, 0);
    }

    // --- multi-day bars -------------------------------------------------------

    function test_a_span_inside_one_row_is_one_uncut_segment() {
        const row = policy.spans(testCase.sample, "2026-08-16");
        const conference = testCase.byId(row, "evt-e");
        compare(conference.startCol, 1);          // Monday the 17th
        compare(conference.span, 4);              // through Thursday the 20th
        compare(conference.continuesLeft, false);
        compare(conference.continuesRight, false);
    }

    function test_only_banners_get_bars() {
        compare(testCase.segmentIds(policy.spans(testCase.sample, "2026-08-16")), "evt-e,evt-d");
        compare(policy.spans(testCase.sample, "2026-08-09").length, 0);
    }

    function test_an_event_crossing_a_row_boundary_is_two_cut_segments() {
        const crossing = [{ "id": "evt-x", "title": "Sprint",
                            "start": "2026-08-14T09:00", "end": "2026-08-18T12:00",
                            "allDay": false }];

        const before = testCase.byId(policy.spans(crossing, "2026-08-09"), "evt-x");
        compare(before.startCol, 5);              // Friday the 14th
        compare(before.span, 2);                  // to the end of the row
        compare(before.continuesLeft, false);
        compare(before.continuesRight, true);

        const after = testCase.byId(policy.spans(crossing, "2026-08-16"), "evt-x");
        compare(after.startCol, 0);
        compare(after.span, 3);                   // Sunday through Tuesday
        compare(after.continuesLeft, true);
        compare(after.continuesRight, false);
    }

    function test_a_row_entirely_inside_a_span_is_cut_at_both_ends() {
        const long = [{ "id": "evt-y", "title": "Sabbatical",
                        "start": "2026-08-03T00:00", "end": "2026-09-01T00:00",
                        "allDay": true }];
        const middle = testCase.byId(policy.spans(long, "2026-08-16"), "evt-y");
        compare(middle.startCol, 0);
        compare(middle.span, 7);
        compare(middle.continuesLeft, true);
        compare(middle.continuesRight, true);
    }

    function test_bars_stack_into_the_lowest_free_lane() {
        const stacked = [
            { "id": "evt-1", "start": "2026-08-16T00:00", "end": "2026-08-23T00:00", "allDay": true },
            { "id": "evt-2", "start": "2026-08-16T00:00", "end": "2026-08-18T00:00", "allDay": true },
            { "id": "evt-3", "start": "2026-08-19T00:00", "end": "2026-08-21T00:00", "allDay": true }
        ];
        const row = policy.spans(stacked, "2026-08-16");
        // Same start column, so the longer bar takes the top lane.
        compare(testCase.byId(row, "evt-1").lane, 0);
        compare(testCase.byId(row, "evt-1").span, 7);
        compare(testCase.byId(row, "evt-2").lane, 1);
        // The lane freed by evt-2 on Wednesday is reused rather than a third
        // one opened — that is what greedy buys.
        compare(testCase.byId(row, "evt-3").lane, 1);
        compare(policy.laneCount(row), 2);
    }

    function test_segments_come_back_ordered_by_lane_then_column() {
        const stacked = [
            { "id": "evt-1", "start": "2026-08-16T00:00", "end": "2026-08-23T00:00", "allDay": true },
            { "id": "evt-2", "start": "2026-08-16T00:00", "end": "2026-08-18T00:00", "allDay": true },
            { "id": "evt-3", "start": "2026-08-19T00:00", "end": "2026-08-21T00:00", "allDay": true }
        ];
        compare(testCase.segmentIds(policy.spans(stacked, "2026-08-16")), "evt-1,evt-2,evt-3");
    }

    function test_a_row_with_nothing_in_it_costs_no_lanes() {
        compare(policy.laneCount([]), 0);
        compare(policy.laneCount(null), 0);
        compare(policy.laneCount(policy.spans(testCase.sample, "2026-08-09")), 0);
    }

    function test_a_bad_row_start_is_no_segments() {
        compare(policy.spans(testCase.sample, "2026-8-16").length, 0);
        compare(policy.spans(testCase.sample, "").length, 0);
        compare(policy.spans(null, "2026-08-16").length, 0);
    }

    /// The right-hand arrow is an off-by-one waiting to happen: a bar whose
    /// last day *is* the row's last column ends there, and only a day past it
    /// continues. The midnight rule has to hold at the row edge as well.
    function test_a_bar_ending_in_the_last_column_draws_no_arrow() {
        const flush = testCase.byId(policy.spans(
            [{ "id": "evt-f", "start": "2026-08-20T00:00",
               "end": "2026-08-23T00:00", "allDay": true }], "2026-08-16"), "evt-f");
        compare(flush.startCol, 4);              // Thursday the 20th
        compare(flush.span, 3);                  // through Saturday the 22nd
        compare(flush.continuesRight, false);

        const over = testCase.byId(policy.spans(
            [{ "id": "evt-f", "start": "2026-08-20T00:00",
               "end": "2026-08-23T00:01", "allDay": true }], "2026-08-16"), "evt-f");
        compare(over.span, 3);                   // still clipped at the row
        compare(over.continuesRight, true);
    }

    /// Greedy packing earns its keep in the middle of a row and not only at
    /// its start: once a bar has ended its lane is free for anything beginning
    /// after it, and a bar overlapping only the front of it goes below.
    function test_a_lane_freed_mid_row_is_reused() {
        const row = policy.spans([
            { "id": "evt-1", "start": "2026-08-16T00:00", "end": "2026-08-20T00:00", "allDay": true },
            { "id": "evt-2", "start": "2026-08-18T00:00", "end": "2026-08-23T00:00", "allDay": true },
            { "id": "evt-3", "start": "2026-08-20T00:00", "end": "2026-08-23T00:00", "allDay": true }
        ], "2026-08-16");
        compare(testCase.byId(row, "evt-1").lane, 0);   // columns 0-3
        compare(testCase.byId(row, "evt-2").lane, 1);   // columns 2-6, so below
        compare(testCase.byId(row, "evt-3").lane, 0);   // columns 4-6, lane 0 again
        compare(policy.laneCount(row), 2);
        // Lane, then column: the reused lane-0 bar reports before the lane-1 one.
        compare(testCase.segmentIds(row), "evt-1,evt-3,evt-2");
    }

    // --- paging ---------------------------------------------------------------

    function test_paging_keeps_the_day_and_clamps_it_into_the_month() {
        compare(policy.nextMonth("2026-01-31"), "2026-02-28");
        compare(policy.nextMonth("2028-01-31"), "2028-02-29");   // leap
        compare(policy.prevMonth("2026-03-31"), "2026-02-28");
        compare(policy.nextMonth("2026-08-31"), "2026-09-30");
    }

    function test_paging_rolls_the_year_at_both_ends() {
        compare(policy.nextMonth("2026-12-15"), "2027-01-15");
        compare(policy.prevMonth("2026-01-15"), "2025-12-15");
        compare(policy.shiftMonths("2026-08-18", 5), "2027-01-18");
        compare(policy.shiftMonths("2026-08-18", -20), "2024-12-18");
        compare(policy.shiftMonths("2026-08-18", 0), "2026-08-18");
    }

    /// The accepted cost of clamping, written down so nobody "fixes" it: a day
    /// that had to be clamped does not come back. Every day the clamp did not
    /// touch does, which is the case people page through.
    function test_paging_is_reversible_except_where_it_clamped() {
        compare(policy.prevMonth(policy.nextMonth("2026-08-18")), "2026-08-18");
        compare(policy.prevMonth(policy.nextMonth("2026-01-31")), "2026-01-28");
    }

    function test_a_bad_anchor_pages_nowhere() {
        compare(policy.nextMonth("2026-02-30"), "");
        compare(policy.prevMonth("nope"), "");
        compare(policy.shiftMonths("", 3), "");
    }
}
