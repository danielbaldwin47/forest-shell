// The calendar's day and minute arithmetic.
//
// Every case here is a boundary, because that is the only kind of bug this
// file can have: a month end, a year end, a leap day, the two seams where
// December meets January, midnight in both directions, and the week whose
// first day is not the one the machine's locale would pick. A calendar is
// right or it is furniture, and the failures are all off-by-one.
//
// The `Date`-free claim is checked too, in the one way it can be from here: a
// two-digit year is a real year and not 1926, which is exactly what a `Date`
// constructor would silently make of it.
import QtQuick
import QtTest
import "../Services/Calendar"

TestCase {
    id: testCase

    name: "CalendarTime"

    CalendarTime { id: time }

    // --- parsing --------------------------------------------------------------

    function test_a_day_parses_into_three_numbers() {
        const d = time.parseDay("2026-08-18");
        compare(d.year, 2026);
        compare(d.month, 8);
        compare(d.day, 18);
    }

    function test_a_day_that_is_not_one_parses_to_null() {
        compare(time.parseDay("2026-8-18"), null);    // unpadded
        compare(time.parseDay("2026-13-01"), null);   // no thirteenth month
        compare(time.parseDay("2026-00-10"), null);
        compare(time.parseDay("2026-02-30"), null);   // February is not that long
        compare(time.parseDay("2026-04-31"), null);   // April is not either
        compare(time.parseDay(""), null);
        compare(time.parseDay("today"), null);
        compare(time.parseDay(17), null);
    }

    function test_february_29_exists_only_in_a_leap_year() {
        verify(time.isDay("2024-02-29"));
        verify(!time.isDay("2026-02-29"));
        verify(!time.isDay("1900-02-29"));   // divisible by 100
        verify(time.isDay("2000-02-29"));    // and by 400
    }

    function test_a_stamp_carries_its_minutes() {
        const s = time.parseStamp("2026-08-18T09:15");
        compare(s.day, 18);
        compare(s.hour, 9);
        compare(s.minute, 15);
        compare(s.minutes, 555);
    }

    function test_a_stamp_that_is_not_one_parses_to_null() {
        compare(time.parseStamp("2026-08-18"), null);         // a day is not a stamp
        compare(time.parseStamp("2026-08-18T24:00"), null);   // midnight is 00:00 next day
        compare(time.parseStamp("2026-08-18T09:60"), null);
        compare(time.parseStamp("2026-08-18 09:15"), null);   // space, not T
        compare(time.parseStamp("2026-02-30T09:15"), null);   // the day still has to exist
    }

    // --- ordinals -------------------------------------------------------------

    function test_the_epoch_is_day_zero() {
        compare(time.toOrdinal("1970-01-01"), 0);
        compare(time.fromOrdinal(0), "1970-01-01");
    }

    function test_ordinals_round_trip_across_a_century() {
        for (const iso of ["1899-12-31", "1900-01-01", "1969-12-31", "2000-02-29",
                           "2026-08-18", "2100-03-01", "0001-01-01"]) {
            compare(time.fromOrdinal(time.toOrdinal(iso)), iso);
        }
    }

    function test_a_bad_day_has_no_ordinal() {
        verify(isNaN(time.toOrdinal("2026-02-30")));
        verify(isNaN(time.toOrdinal("")));
    }

    // --- weekdays -------------------------------------------------------------

    function test_the_weekday_is_sunday_first() {
        compare(time.dayOfWeek("2026-08-16"), 0);   // Sunday
        compare(time.dayOfWeek("2026-08-17"), 1);   // Monday
        compare(time.dayOfWeek("2026-08-18"), 2);   // Tuesday
        compare(time.dayOfWeek("2026-08-22"), 6);   // Saturday
    }

    function test_the_weekday_agrees_with_the_month_grid_across_the_seams() {
        compare(time.dayOfWeek("1999-12-31"), 5);   // Friday
        compare(time.dayOfWeek("2000-01-01"), 6);   // Saturday
        compare(time.dayOfWeek("2024-02-29"), 4);   // Thursday
    }

    function test_a_bad_day_has_no_weekday() {
        compare(time.dayOfWeek("nope"), -1);
    }

    // --- addDays --------------------------------------------------------------

    function test_adding_days_inside_a_month() {
        compare(time.addDays("2026-08-18", 3), "2026-08-21");
        compare(time.addDays("2026-08-18", -3), "2026-08-15");
        compare(time.addDays("2026-08-18", 0), "2026-08-18");
    }

    function test_adding_days_crosses_a_month_end() {
        compare(time.addDays("2026-08-31", 1), "2026-09-01");
        compare(time.addDays("2026-09-01", -1), "2026-08-31");
        compare(time.addDays("2026-04-30", 1), "2026-05-01");
        compare(time.addDays("2026-01-31", 1), "2026-02-01");
    }

    function test_adding_days_crosses_february() {
        compare(time.addDays("2026-02-28", 1), "2026-03-01");
        compare(time.addDays("2024-02-28", 1), "2024-02-29");
        compare(time.addDays("2024-02-29", 1), "2024-03-01");
        compare(time.addDays("2024-03-01", -1), "2024-02-29");
    }

    function test_adding_days_crosses_a_year_end() {
        compare(time.addDays("2026-12-31", 1), "2027-01-01");
        compare(time.addDays("2027-01-01", -1), "2026-12-31");
        compare(time.addDays("2026-12-31", 365), "2027-12-31");
    }

    function test_a_year_under_a_hundred_is_that_year_and_not_1926() {
        // The whole reason this file does not use `Date`: `new Date(26, 7, 18)`
        // is 1926, and the wrong answer looks like a plausible date.
        compare(time.addDays("0026-08-18", 1), "0026-08-19");
        compare(time.dayOfWeek("0026-08-18"), 2);
    }

    function test_adding_days_to_a_non_day_answers_nothing() {
        compare(time.addDays("2026-02-30", 1), "");
    }

    function test_diffDays_is_signed_and_symmetric() {
        compare(time.diffDays("2026-08-18", "2026-08-21"), 3);
        compare(time.diffDays("2026-08-21", "2026-08-18"), -3);
        compare(time.diffDays("2026-12-31", "2027-01-01"), 1);
        verify(isNaN(time.diffDays("2026-08-18", "junk")));
    }

    // --- weeks ----------------------------------------------------------------

    function test_weekStart_with_sunday_first() {
        compare(time.weekStart("2026-08-18", 0), "2026-08-16");
        compare(time.weekStart("2026-08-16", 0), "2026-08-16");   // already Sunday
        compare(time.weekStart("2026-08-22", 0), "2026-08-16");   // Saturday
    }

    function test_weekStart_with_monday_first() {
        compare(time.weekStart("2026-08-18", 1), "2026-08-17");
        compare(time.weekStart("2026-08-17", 1), "2026-08-17");   // already Monday
        compare(time.weekStart("2026-08-16", 1), "2026-08-10");   // Sunday belongs to the week before
    }

    function test_weekStart_reaches_back_over_a_month_end() {
        compare(time.weekStart("2026-09-01", 1), "2026-08-31");
        compare(time.weekStart("2027-01-01", 0), "2026-12-27");
    }

    function test_weekStart_takes_any_firstDay_including_a_silly_one() {
        compare(time.weekStart("2026-08-18", 6), "2026-08-15");   // weeks opening Saturday
        compare(time.weekStart("2026-08-18", 7), time.weekStart("2026-08-18", 0));
        compare(time.weekStart("2026-08-18", -1), time.weekStart("2026-08-18", 6));
    }

    function test_weekDays_is_seven_days_in_order() {
        const days = time.weekDays("2026-08-18", 1);
        compare(days.length, 7);
        compare(days[0], "2026-08-17");
        compare(days[6], "2026-08-23");
    }

    function test_weekDays_of_a_non_day_is_empty() {
        compare(time.weekDays("nope", 1).length, 0);
    }

    // --- minutes --------------------------------------------------------------

    function test_dayOf_and_parseMinutes_split_a_stamp() {
        compare(time.dayOf("2026-08-18T09:15"), "2026-08-18");
        compare(time.parseMinutes("2026-08-18T09:15"), 555);
        compare(time.parseMinutes("2026-08-18T00:00"), 0);
        compare(time.parseMinutes("2026-08-18T23:59"), 1439);
        compare(time.parseMinutes("nope"), -1);
        compare(time.dayOf("nope"), "");
    }

    function test_formatStamp_pads_both_halves() {
        compare(time.formatStamp("2026-08-18", 555), "2026-08-18T09:15");
        compare(time.formatStamp("2026-08-18", 0), "2026-08-18T00:00");
        compare(time.formatStamp("2026-08-18", 1439), "2026-08-18T23:59");
    }

    function test_formatStamp_rolls_the_day_rather_than_the_hour() {
        // 90 minutes past 23:00 is 00:30 the next day, not 24:30 the same one.
        compare(time.formatStamp("2026-08-18", 1470), "2026-08-19T00:30");
        compare(time.formatStamp("2026-08-18", -30), "2026-08-17T23:30");
        compare(time.formatStamp("2026-12-31", 1440), "2027-01-01T00:00");
    }

    function test_addMinutes_crosses_midnight_in_both_directions() {
        compare(time.addMinutes("2026-08-18T09:15", 45), "2026-08-18T10:00");
        compare(time.addMinutes("2026-08-18T23:30", 60), "2026-08-19T00:30");
        compare(time.addMinutes("2026-08-18T00:30", -60), "2026-08-17T23:30");
        compare(time.addMinutes("2026-08-18T09:15", 0), "2026-08-18T09:15");
        compare(time.addMinutes("nope", 30), "");
    }

    function test_diffMinutes_within_a_day() {
        compare(time.diffMinutes("2026-08-18T09:00", "2026-08-18T10:30"), 90);
        compare(time.diffMinutes("2026-08-18T10:30", "2026-08-18T09:00"), -90);
        compare(time.diffMinutes("2026-08-18T09:00", "2026-08-18T09:00"), 0);
    }

    function test_diffMinutes_across_days_and_years() {
        compare(time.diffMinutes("2026-08-18T23:00", "2026-08-19T01:00"), 120);
        compare(time.diffMinutes("2026-08-18T00:00", "2026-08-21T00:00"), 3 * 1440);
        compare(time.diffMinutes("2026-12-31T23:30", "2027-01-01T00:30"), 60);
        verify(isNaN(time.diffMinutes("2026-08-18T09:00", "nope")));
    }

    function test_compare_orders_days_and_stamps() {
        compare(time.compare("2026-08-18", "2026-08-19"), -1);
        compare(time.compare("2026-08-19", "2026-08-18"), 1);
        compare(time.compare("2026-08-18", "2026-08-18"), 0);
        compare(time.compare("2026-08-18T09:00", "2026-08-18T10:00"), -1);
        compare(time.compare("2026-09-01T09:00", "2026-08-31T23:00"), 1);
    }

    // --- the calendar-shaped composition --------------------------------------

    function test_a_week_of_stamps_is_stable_under_round_tripping() {
        // The composition the week view actually performs: take a day, find its
        // week, and place a 09:15 event on each column.
        const days = time.weekDays("2026-08-20", 1);
        for (const day of days) {
            const stamp = time.formatStamp(day, 555);
            compare(time.dayOf(stamp), day);
            compare(time.parseMinutes(stamp), 555);
        }
        compare(time.diffMinutes(time.formatStamp(days[0], 555),
                                 time.formatStamp(days[6], 555)), 6 * 1440);
    }
}
