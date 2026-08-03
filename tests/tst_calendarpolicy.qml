// The month grid (#49): where a month starts, what fills the corners of the
// grid around it, and which cell is today.
//
// Every case here is a boundary — a month that starts on the first column, one
// that starts on the last, a February that has a 29th and one that does not,
// and the two seams where December meets January. A calendar is right or it is
// furniture, and the failures are all off-by-one.
import QtQuick
import QtTest
import "../Surfaces/Drawers"

TestCase {
    id: testCase

    name: "CalendarPolicy"

    CalendarPolicy { id: policy }

    // Days in the current month of a grid, in order, as `d/m` — the shape most
    // of these assertions read best in.
    function cells(year, month, firstDay) {
        const out = [];
        for (const week of policy.weeks(year, month, firstDay))
            for (const cell of week)
                out.push(cell.day + "/" + cell.month);
        return out;
    }

    // --- how long a month is --------------------------------------------------

    function test_the_months_have_their_own_lengths() {
        compare(policy.daysInMonth(2026, 1), 31);
        compare(policy.daysInMonth(2026, 4), 30);
        compare(policy.daysInMonth(2026, 12), 31);
    }

    function test_february_follows_the_whole_leap_rule() {
        compare(policy.daysInMonth(2026, 2), 28);
        compare(policy.daysInMonth(2024, 2), 29);   // divisible by 4
        compare(policy.daysInMonth(1900, 2), 28);   // and by 100 — not a leap year
        compare(policy.daysInMonth(2000, 2), 29);   // and by 400 — one again
    }

    // --- which weekday a month opens on --------------------------------------

    function test_a_month_knows_which_weekday_it_opens_on() {
        // Sunday is 0, the numbering QML's `Locale.Sunday` uses.
        compare(policy.firstWeekday(2026, 8), 6);   // 1 August 2026 is a Saturday
        compare(policy.firstWeekday(2026, 2), 0);   // 1 February 2026 is a Sunday
        compare(policy.firstWeekday(2024, 2), 4);   // 1 February 2024 is a Thursday
    }

    function test_the_weekday_is_computed_rather_than_taken_from_a_two_digit_year() {
        // `new Date(26, 0, 1)` is 1926 in JavaScript, silently. The policy does
        // its own arithmetic, so a year outside the four-digit habit still
        // answers about itself.
        compare(policy.firstWeekday(26, 1), 4);     // 1 January 26 AD, proleptic Gregorian
        compare(policy.firstWeekday(1926, 1), 5);   // which is not what 1926 answers
        compare(policy.firstWeekday(2026, 1), 4);   // 1 January 2026 is a Thursday
    }

    // --- the header row -------------------------------------------------------

    function test_the_weekday_header_starts_where_the_locale_starts() {
        compare(policy.weekdays(1), [1, 2, 3, 4, 5, 6, 0]);   // Monday first
        compare(policy.weekdays(0), [0, 1, 2, 3, 4, 5, 6]);   // Sunday first
        compare(policy.weekdays(6), [6, 0, 1, 2, 3, 4, 5]);   // Saturday first
    }

    // --- the grid -------------------------------------------------------------

    function test_the_grid_is_always_six_rows_of_seven() {
        // A card that changed height with the month would move the cards under
        // it as you paged, so the grid is a fixed size and short months carry
        // more neighbours.
        for (const month of [1, 2, 5, 9, 12]) {
            const weeks = policy.weeks(2026, month, 1);
            compare(weeks.length, 6, "month " + month);
            for (const week of weeks)
                compare(week.length, 7, "month " + month);
        }
    }

    function test_the_first_of_the_month_lands_under_its_own_weekday() {
        // August 2026 opens on a Saturday: Monday-first puts it in the last
        // column, Sunday-first in the second.
        const mondayFirst = policy.weeks(2026, 8, 1)[0];
        compare(mondayFirst[5].day, 1);
        compare(mondayFirst[5].current, true);

        const sundayFirst = policy.weeks(2026, 8, 0)[0];
        compare(sundayFirst[6].day, 1);
        compare(sundayFirst[6].current, true);
    }

    function test_a_month_that_opens_on_the_first_column_still_gets_a_leading_week() {
        // February 2026 opens on a Sunday, so Sunday-first has nothing to pad
        // with. The row above is the previous month's last week rather than a
        // blank one — a grid with a hole in it reads as a missing day.
        const weeks = policy.weeks(2026, 2, 0);
        compare(weeks[0][0].day, 1);
        compare(weeks[0][0].current, true);
        compare(weeks[5][6].day, 14);          // 14 March, the far corner
        compare(weeks[5][6].current, false);
        compare(weeks[5][6].month, 3);
    }

    function test_the_corners_carry_the_neighbouring_months_own_dates() {
        // The cells outside the month are not blanks: they are real days, with
        // their own month and year, so a click on one could page to it.
        const weeks = policy.weeks(2026, 8, 1);   // August, Monday-first
        compare(weeks[0][0].day, 27);
        compare(weeks[0][0].month, 7);
        compare(weeks[0][0].year, 2026);
        compare(weeks[0][0].current, false);

        const last = weeks[5][6];
        compare(last.month, 9);
        compare(last.year, 2026);
        compare(last.current, false);
    }

    function test_every_day_of_the_month_appears_exactly_once() {
        for (const month of [1, 2, 4, 8, 12]) {
            const days = [];
            for (const week of policy.weeks(2026, month, 1))
                for (const cell of week)
                    if (cell.current)
                        days.push(cell.day);

            compare(days.length, policy.daysInMonth(2026, month), "month " + month);
            for (let i = 0; i < days.length; i++)
                compare(days[i], i + 1, "month " + month);
        }
    }

    function test_the_grid_runs_without_a_gap_across_the_year_boundary() {
        // January's leading cells are December of the year before, and
        // December's trailing cells are January of the year after. Both are the
        // case a `month - 1` gets wrong.
        const january = policy.weeks(2026, 1, 1);
        compare(january[0][0].day, 29);
        compare(january[0][0].month, 12);
        compare(january[0][0].year, 2025);

        const december = policy.weeks(2025, 12, 1);
        const last = december[5][6];
        compare(last.month, 1);
        compare(last.year, 2026);
    }

    function test_the_leap_day_is_in_the_grid_and_the_next_year_it_is_not() {
        verify(testCase.cells(2024, 2, 1).indexOf("29/2") >= 0);
        verify(testCase.cells(2025, 2, 1).indexOf("29/2") < 0);
    }

    // --- today ----------------------------------------------------------------

    function test_today_is_the_cell_that_matches_all_three_of_year_month_day() {
        const weeks = policy.weeks(2026, 8, 1);
        const first = weeks[0][5];               // 1 August 2026
        verify(policy.isToday(first, 2026, 8, 1));
        verify(!policy.isToday(first, 2026, 8, 2));
        verify(!policy.isToday(first, 2026, 9, 1));
        verify(!policy.isToday(first, 2025, 8, 1));
    }

    function test_today_never_highlights_the_same_number_in_a_neighbouring_month() {
        // The 1st of September sits in August's last row. Highlighting it while
        // today is the 1st of August would put two "todays" in one grid.
        const weeks = policy.weeks(2026, 8, 1);
        let neighbours = 0;
        for (const week of weeks)
            for (const cell of week)
                if (!cell.current && policy.isToday(cell, 2026, 8, cell.day))
                    neighbours++;
        compare(neighbours, 0);
    }

    // --- paging ---------------------------------------------------------------

    function test_paging_rolls_the_year_over_at_both_ends() {
        compare(policy.shift(2026, 8, 1), { year: 2026, month: 9 });
        compare(policy.shift(2026, 12, 1), { year: 2027, month: 1 });
        compare(policy.shift(2026, 1, -1), { year: 2025, month: 12 });
        compare(policy.shift(2026, 8, -1), { year: 2026, month: 7 });
    }

    function test_paging_a_whole_year_at_a_time_still_lands_on_a_real_month() {
        compare(policy.shift(2026, 8, 12), { year: 2027, month: 8 });
        compare(policy.shift(2026, 8, -12), { year: 2025, month: 8 });
        compare(policy.shift(2026, 8, -8), { year: 2025, month: 12 });
    }
}
