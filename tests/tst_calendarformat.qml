// The calendar's words (piece b): headers, column headings, hour labels, time
// ranges, durations and the compact stamp on a month chip.
//
// Formatting has one kind of bug and it is the boundary too: noon and midnight
// on a 12-hour clock, the week that changes month halfway, the week that
// changes year halfway, the duration that lands exactly on an hour or exactly
// on a day, and the range whose two ends share a meridiem but not a day. Every
// case below is one of those; the pretty middle of the range is checked once
// each and then left alone.
//
// The clock is an *argument* everywhere, never read — `Core/ClockFormat.qml`
// decided 12- vs 24-hour for the whole shell in #93 — so every clock case is
// asserted twice, once per format.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "CalendarFormat"

    CalendarFormat { id: format }

    // --- names ----------------------------------------------------------------

    function test_month_names_are_indexed_by_the_month_number() {
        compare(format.monthLong[1], "January");
        compare(format.monthLong[8], "August");
        compare(format.monthLong[12], "December");
        compare(format.monthShort[8], "Aug");
        compare(format.monthShort[9], "Sep");
        // Index 0 is the placeholder that keeps 1-12 honest, never a month.
        compare(format.monthShort[0], "");
        compare(format.monthLong.length, 13);
    }

    function test_weekday_names_rotate_to_the_locales_first_day() {
        compare(format.weekdayShort(0), ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]);
        compare(format.weekdayShort(1), ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]);
        compare(format.weekdayShort(6), ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"]);
        compare(format.weekdayLong(1)[0], "Monday");
        compare(format.weekdayLong(1)[6], "Sunday");
    }

    function test_a_first_day_outside_the_week_still_yields_seven_columns() {
        compare(format.weekdayShort(7).length, 7);
        compare(format.weekdayShort(7)[0], "Sun");
        compare(format.weekdayShort(-1)[0], "Sat");
    }

    function test_headings_are_the_caps_and_the_two_grids_share_them() {
        compare(format.weekdayHeadings(1), ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]);
        // The names themselves stay in the case prose uses them in.
        compare(format.weekdayShort(1)[0], "Mon");
    }

    // --- titles ---------------------------------------------------------------

    function test_the_month_header_names_the_month_and_the_year() {
        compare(format.title("month", "2026-08-18", 1), "August 2026");
        compare(format.title("month", "2026-01-01", 0), "January 2026");
    }

    function test_the_day_header_spells_the_weekday_out() {
        compare(format.title("day", "2026-08-18", 1), "Tuesday, August 18, 2026");
        // Single-digit days are unpadded in prose.
        compare(format.title("day", "2026-08-01", 1), "Saturday, August 1, 2026");
    }

    function test_the_week_header_follows_the_locales_first_day() {
        // 2026-08-18 is a Tuesday: a Monday week opens on the 17th and a Sunday
        // week on the 16th, and the header must not claim otherwise.
        compare(format.title("week", "2026-08-18", 1), "Aug 17 – 23, 2026");
        compare(format.title("week", "2026-08-18", 0), "Aug 16 – 22, 2026");
    }

    function test_a_week_that_changes_month_names_both() {
        // 2026-08-31 is a Monday, so this week is the seam.
        compare(format.title("week", "2026-09-02", 1), "Aug 31 – Sep 6, 2026");
    }

    function test_a_week_that_changes_year_names_both_years() {
        // 2025-12-29 is a Monday.
        compare(format.title("week", "2025-12-31", 1), "Dec 29, 2025 – Jan 4, 2026");
    }

    function test_a_range_repeats_only_what_the_two_ends_disagree_about() {
        compare(format.dayRange("2026-08-18", "2026-08-24"), "Aug 18 – 24, 2026");
        compare(format.dayRange("2026-08-31", "2026-09-06"), "Aug 31 – Sep 6, 2026");
        compare(format.dayRange("2025-12-29", "2026-01-04"), "Dec 29, 2025 – Jan 4, 2026");
        compare(format.dayRange("2026-08-18", "2026-08-18"), "Aug 18, 2026");
    }

    function test_the_mini_month_names_the_month_it_is_showing() {
        compare(format.miniMonthTitle("2026-02-14"), "February 2026");
    }

    function test_a_title_it_cannot_write_is_empty_rather_than_wrong() {
        compare(format.title("month", "2026-02-30", 1), "");   // February is not that long
        compare(format.title("week", "not-a-day", 1), "");
        compare(format.title("day", "", 1), "");
        compare(format.title("agenda", "2026-08-18", 1), "");  // a view this file does not write
        compare(format.dayRange("2026-08-18", "2026-13-01"), "");
    }

    // --- column headers -------------------------------------------------------

    function test_a_week_column_header_is_two_pieces() {
        const h = format.dayHeader("2026-08-18");
        compare(h.weekday, "TUE");
        compare(h.day, "18");
    }

    function test_a_column_header_day_carries_no_leading_zero() {
        compare(format.dayHeader("2026-08-01").day, "1");
        compare(format.dayHeader("2024-02-29").weekday, "THU");   // leap day, and it exists
    }

    function test_a_column_header_for_a_day_that_is_not_one_is_null() {
        compare(format.dayHeader("2026-02-30"), null);
        compare(format.dayHeader(""), null);
    }

    // --- hour gutter ----------------------------------------------------------

    function test_the_hour_gutter_writes_whole_hours() {
        compare(format.hourLabel(13, false), "1 PM");
        compare(format.hourLabel(13, true), "13:00");
        compare(format.hourLabel(9, false), "9 AM");
        compare(format.hourLabel(9, true), "09:00");
    }

    function test_noon_and_midnight_are_twelve_on_a_twelve_hour_clock() {
        compare(format.hourLabel(0, false), "12 AM");
        compare(format.hourLabel(12, false), "12 PM");
        compare(format.hourLabel(11, false), "11 AM");
        compare(format.hourLabel(0, true), "00:00");
        compare(format.hourLabel(12, true), "12:00");
        compare(format.hourLabel(23, true), "23:00");
    }

    function test_an_hour_off_the_clock_has_no_label() {
        compare(format.hourLabel(24, true), "");
        compare(format.hourLabel(-1, false), "");
    }

    // --- clock times ----------------------------------------------------------

    function test_a_single_time_keeps_its_minutes() {
        compare(format.stampTime("2026-08-18T09:15", false), "9:15 AM");
        compare(format.stampTime("2026-08-18T09:15", true), "09:15");
        compare(format.stampTime("2026-08-18T13:00", false), "1:00 PM");
        compare(format.stampTime("2026-08-18T00:05", false), "12:05 AM");
        compare(format.stampTime("2026-08-18T12:00", false), "12:00 PM");
        compare(format.stampTime("2026-08-18", false), "");   // a day is not a stamp
    }

    // --- time ranges ----------------------------------------------------------

    function test_a_range_inside_one_half_of_the_day_writes_the_meridiem_once() {
        compare(format.timeRange("2026-08-18T09:15", "2026-08-18T10:00", false), "9:15 – 10:00 AM");
        compare(format.timeRange("2026-08-18T13:00", "2026-08-18T14:30", false), "1:00 – 2:30 PM");
    }

    function test_a_range_that_crosses_noon_writes_both() {
        compare(format.timeRange("2026-08-18T11:30", "2026-08-18T13:00", false), "11:30 AM – 1:00 PM");
        // Noon itself is PM, so a meeting up to noon still crosses.
        compare(format.timeRange("2026-08-18T11:30", "2026-08-18T12:00", false), "11:30 AM – 12:00 PM");
    }

    function test_a_range_that_crosses_midnight_never_shares_a_meridiem() {
        // Both ends are AM, and sharing would describe a half hour instead of
        // a day and a half hour.
        compare(format.timeRange("2026-08-18T09:00", "2026-08-19T09:30", false), "9:00 AM – 9:30 AM");
        compare(format.timeRange("2026-08-18T23:30", "2026-08-19T00:30", false), "11:30 PM – 12:30 AM");
    }

    function test_a_twenty_four_hour_range_is_two_padded_times() {
        compare(format.timeRange("2026-08-18T09:15", "2026-08-18T10:00", true), "09:15 – 10:00");
        compare(format.timeRange("2026-08-18T23:30", "2026-08-19T00:30", true), "23:30 – 00:30");
    }

    function test_a_range_it_cannot_read_is_empty() {
        compare(format.timeRange("2026-08-18", "2026-08-18T10:00", false), "");
        compare(format.timeRange("2026-08-18T09:15", "", true), "");
    }

    // --- durations ------------------------------------------------------------

    function test_a_duration_under_an_hour_is_minutes() {
        compare(format.duration(45), "45m");
        compare(format.duration(1), "1m");
        compare(format.duration(59), "59m");
    }

    function test_a_whole_hour_drops_the_minutes() {
        compare(format.duration(60), "1h");
        compare(format.duration(120), "2h");
        compare(format.duration(90), "1h 30m");
        compare(format.duration(1439), "23h 59m");
    }

    function test_a_whole_day_drops_everything_under_it() {
        compare(format.duration(1440), "1d");
        compare(format.duration(2880), "2d");
        compare(format.duration(1500), "1d 1h");
    }

    function test_a_duration_writes_two_units_at_most() {
        // 1d 1h 30m — the third unit is what pushes an event title out of a chip.
        compare(format.duration(1530), "1d 1h");
        // The two are the largest non-zero ones, so a zero hour is skipped
        // rather than counted.
        compare(format.duration(1470), "1d 30m");
    }

    function test_a_duration_that_is_not_one_says_so() {
        compare(format.duration(0), "0m");
        compare(format.duration(-15), "");
        compare(format.duration(NaN), "");
    }

    // --- month chips ----------------------------------------------------------

    function test_a_chip_drops_the_zero_minutes_and_shortens_the_meridiem() {
        compare(format.chipTime("2026-08-18T09:00", false), "9a");
        compare(format.chipTime("2026-08-18T09:15", false), "9:15a");
        compare(format.chipTime("2026-08-18T13:00", false), "1p");
        compare(format.chipTime("2026-08-18T13:05", false), "1:05p");
    }

    function test_a_chip_at_noon_and_at_midnight() {
        compare(format.chipTime("2026-08-18T00:00", false), "12a");
        compare(format.chipTime("2026-08-18T12:00", false), "12p");
        compare(format.chipTime("2026-08-18T12:30", false), "12:30p");
    }

    function test_a_twenty_four_hour_chip_keeps_both_digits() {
        // No letter to drop, and the padding is what lines a stack of chips up.
        compare(format.chipTime("2026-08-18T09:00", true), "09:00");
        compare(format.chipTime("2026-08-18T09:15", true), "09:15");
        compare(format.chipTime("2026-08-18T13:05", true), "13:05");
        compare(format.chipTime("2026-08-18T00:00", true), "00:00");
    }

    function test_a_chip_for_a_stamp_that_is_not_one_is_empty() {
        compare(format.chipTime("2026-08-18", false), "");
        compare(format.chipTime("2026-08-18T24:00", true), "");
    }

    // --- relative days --------------------------------------------------------

    function test_the_three_days_with_names() {
        compare(format.relativeDay("2026-08-18", "2026-08-18"), "Today");
        compare(format.relativeDay("2026-08-19", "2026-08-18"), "Tomorrow");
        compare(format.relativeDay("2026-08-17", "2026-08-18"), "Yesterday");
    }

    function test_the_named_days_cross_months_and_years() {
        compare(format.relativeDay("2026-09-01", "2026-08-31"), "Tomorrow");
        compare(format.relativeDay("2025-12-31", "2026-01-01"), "Yesterday");
        compare(format.relativeDay("2024-02-29", "2024-03-01"), "Yesterday");   // leap day
    }

    function test_every_other_day_has_no_name() {
        compare(format.relativeDay("2026-08-20", "2026-08-18"), null);
        compare(format.relativeDay("2026-08-16", "2026-08-18"), null);
        compare(format.relativeDay("2026-02-30", "2026-08-18"), null);
        compare(format.relativeDay("2026-08-18", "nope"), null);
    }

    // --- probes (adversarial pass) --------------------------------------------

    function test_a_range_that_runs_backwards_is_empty_rather_than_impossible() {
        // "Aug 24 – 18, 2026" is a header nobody reads as an error; the same
        // argument `duration` makes about "-15m" applies to a span of days.
        compare(format.dayRange("2026-08-24", "2026-08-18"), "");
        compare(format.dayRange("2026-01-04", "2025-12-29"), "");
        compare(format.timeRange("2026-08-18T10:00", "2026-08-18T09:15", false), "");
        compare(format.timeRange("2026-08-19T00:30", "2026-08-18T23:30", true), "");
        // A zero-length span is not backwards: `duration(0)` is "0m", so this is
        // a real thing to print rather than a store bug.
        compare(format.dayRange("2026-08-18", "2026-08-18"), "Aug 18, 2026");
        compare(format.timeRange("2026-08-18T09:00", "2026-08-18T09:00", false), "9:00 – 9:00 AM");
    }

    function test_the_week_header_folds_a_first_day_outside_the_week() {
        // `weekdayShort` folds 7 back to Sunday; the header must fold the same
        // way or the columns and the title name different weeks.
        compare(format.title("week", "2026-08-18", 7), format.title("week", "2026-08-18", 0));
        compare(format.title("week", "2026-08-18", -1), format.title("week", "2026-08-18", 6));
        compare(format.title("week", "2026-08-18", 8), "Aug 17 – 23, 2026");
    }

    function test_the_column_headers_of_a_week_are_the_heading_row_in_order() {
        // The two paths to a weekday name — `dayHeader` per column and
        // `weekdayHeadings` for the row above them — must not disagree by one.
        for (let first = 0; first < 7; first++) {
            const headings = format.weekdayHeadings(first);
            const days = format.time.weekDays("2026-08-18", first);
            for (let i = 0; i < 7; i++)
                compare(format.dayHeader(days[i]).weekday, headings[i]);
        }
    }

    function test_an_hour_that_is_not_a_whole_number_still_labels_a_whole_hour() {
        // The gutter's rows are hours; a caller that computes one by division
        // must not print "12.5 PM".
        compare(format.hourLabel(12.5, false), "12 PM");
        compare(format.hourLabel(9.9, true), "09:00");
        compare(format.hourLabel(23, false), "11 PM");
    }

    function test_a_duration_rounds_to_the_minute_it_prints() {
        compare(format.duration(44.6), "45m");
        // 59.6 minutes is an hour, and "60m" is not a thing this file writes.
        compare(format.duration(59.6), "1h");
        compare(format.duration(1439.5), "1d");
        compare(format.duration(0.4), "0m");
    }

    function test_a_duration_of_many_days_stays_two_units() {
        compare(format.duration(10080), "7d");
        compare(format.duration(4379), "3d 59m");
        compare(format.duration(43200), "30d");
    }

    function test_a_view_name_is_matched_exactly() {
        // The views are named by IPC and by the toolbar; a near miss must be
        // empty rather than the month header over a week grid.
        compare(format.title("Week", "2026-08-18", 1), "");
        compare(format.title("", "2026-08-18", 1), "");
        compare(format.title("week", "2026-08-18", 1), "Aug 17 – 23, 2026");
    }

    function test_the_leap_day_gets_the_header_it_earned() {
        compare(format.title("day", "2024-02-29", 1), "Thursday, February 29, 2024");
        compare(format.title("month", "2024-02-29", 1), "February 2024");
        compare(format.title("week", "2024-02-29", 1), "Feb 26 – Mar 3, 2024");
    }

    // --- the toolbar's two faces ----------------------------------------------

    function test_titleParts_lifts_the_trailing_year() {
        compare(format.titleParts("month", "2026-08-18", 1),
                { "lead": "August", "year": "2026" });
        compare(format.titleParts("week", "2026-08-18", 1),
                { "lead": "Aug 17 – 23,", "year": "2026" });
        compare(format.titleParts("day", "2026-08-18", 1),
                { "lead": "Tuesday, August 18,", "year": "2026" });
    }

    function test_titleParts_keeps_the_comma_on_the_lead() {
        // The seam is the space, not the punctuation. Split at the comma and
        // the toolbar sets "Aug 17 – 23" beside "2026" with a gap and no
        // connective, which reads as two fragments rather than one range.
        const parts = format.titleParts("week", "2026-08-18", 1);
        verify(/,$/.test(parts.lead), parts.lead);
        compare(parts.lead + " " + parts.year, format.title("week", "2026-08-18", 1));
    }

    function test_titleParts_takes_only_the_last_year() {
        // The cross-year week names two years and only the second is trailing.
        // Lifting both would leave "Dec 29 – Jan 4", which is a week in no
        // particular year and reads as a bug in the header rather than in the
        // split.
        compare(format.title("week", "2025-12-31", 1), "Dec 29, 2025 – Jan 4, 2026");
        compare(format.titleParts("week", "2025-12-31", 1),
                { "lead": "Dec 29, 2025 – Jan 4,", "year": "2026" });
    }

    function test_titleParts_never_hands_back_undefined() {
        // The toolbar binds straight onto `.lead`, once per frame. A `null`
        // here is a TypeError on every repaint of the window.
        compare(format.titleParts("fortnight", "2026-08-18", 1), { "lead": "", "year": "" });
        compare(format.titleParts("week", "not-a-day", 1), { "lead": "", "year": "" });
    }

    function test_titleParts_rejoins_to_the_title() {
        // The split may drop a separator but never a word: whatever comes back
        // must still be the title `title()` built.
        const views = ["day", "week", "month"];
        const days = ["2026-08-18", "2026-01-01", "2025-12-31", "2024-02-29"];
        for (let v = 0; v < views.length; v++) {
            for (let d = 0; d < days.length; d++) {
                const parts = format.titleParts(views[v], days[d], 1);
                const full = format.title(views[v], days[d], 1);
                verify(full.indexOf(parts.lead) === 0, views[v] + " " + days[d] + ": " + full);
                verify(full.indexOf(parts.year) === full.length - parts.year.length,
                       views[v] + " " + days[d] + ": " + full);
            }
        }
    }

    // --- the week chip's start-only time ---------------------------------------

    function test_a_start_time_is_the_range_s_own_first_token() {
        // One clock grammar per surface. `timeRange` opens `10:30 – 11:45 AM`;
        // a chip too narrow for the range prints `10:30 AM`, and where even the
        // meridiem will not fit, `10:30` — the same first token, never
        // `chipTime`'s `10:30a`, which is the month grid's notation.
        compare(format.timeRange("2026-08-18T10:30", "2026-08-18T11:45", false),
                "10:30 – 11:45 AM");
        compare(format.startTime("2026-08-18T10:30", false, true), "10:30 AM");
        compare(format.startTime("2026-08-18T10:30", false, false), "10:30");
        compare(format.startTime("2026-08-18T09:00", false, true), "9:00 AM");
        // `:00` is kept, unlike `chipTime`: a stack of chips lines its times up
        // only if every one of them is the same shape.
        compare(format.startTime("2026-08-18T09:00", false, false), "9:00");
        compare(format.startTime("2026-08-18T13:05", false, true), "1:05 PM");
        compare(format.startTime("2026-08-18T12:00", false, true), "12:00 PM");
        compare(format.startTime("2026-08-18T00:15", false, true), "12:15 AM");
    }

    function test_a_24_hour_start_time_has_no_meridiem_to_drop() {
        compare(format.startTime("2026-08-18T09:00", true, true), "09:00");
        compare(format.startTime("2026-08-18T09:00", true, false), "09:00");
        compare(format.startTime("2026-08-18T13:05", true, false), "13:05");
    }

    function test_an_unparseable_start_time_prints_nothing() {
        compare(format.startTime("2026-08-18", false, true), "");
        compare(format.startTime("", false, true), "");
        compare(format.startTime("2026-08-18T24:00", true, false), "");
    }

    function test_a_day_header_carries_both_lengths_of_its_weekday() {
        // Seven columns take the abbreviation; one column has room for the
        // whole word, and both come off the one function so they can never
        // disagree about which Tuesday they mean.
        const h = format.dayHeader("2026-08-18");
        compare(h.weekday, "TUE");
        compare(h.weekdayFull, "Tuesday");
        compare(format.dayHeader("2026-08-23").weekdayFull, "Sunday");
        compare(format.dayHeader("2024-02-29").weekdayFull, "Thursday");
    }

    // --- the two labels a surface used to spell for itself ---------------------

    function test_a_chip_shows_the_range_it_has_room_for() {
        const start = "2026-08-18T09:00";
        const end = "2026-08-18T10:30";

        // The whole range when nothing says otherwise.
        compare(format.chipTimeLabel(start, end, true, {}),
                format.timeRange(start, end, true));

        // The start alone once the layout says the range will not fit.
        compare(format.chipTimeLabel(start, end, true, { "form": "start" }), "09:00");
        compare(format.chipTimeLabel(start, end, false, { "form": "start" }), "9:00");
        compare(format.chipTimeLabel(start, end, false,
                                     { "form": "start", "meridiem": true }), "9:00 AM");
    }

    function test_a_chip_running_off_the_top_shows_where_it_ends() {
        const start = "2026-08-17T22:00";
        const end = "2026-08-18T10:30";

        // Continuing above, the start is on yesterday's column — the end is the
        // only time of day this chip is actually about.
        compare(format.chipTimeLabel(start, end, true, { "continuesAbove": true }),
                "→ 10:30");
        // Continuing below, the end is tomorrow's, so the start stands alone.
        compare(format.chipTimeLabel(start, end, true, { "continuesBelow": true }),
                "22:00");
        // Both, which is a chip that is only middle: the top wins, because the
        // end is what the reader cannot see anywhere else.
        compare(format.chipTimeLabel(start, end, true,
                                     { "continuesAbove": true, "continuesBelow": true }),
                "→ 10:30");
    }

    function test_a_chip_with_no_event_behind_it_says_nothing() {
        compare(format.chipTimeLabel("", "2026-08-18T10:30", true, {}), "");
        compare(format.chipTimeLabel("", "", true, undefined), "");
    }

    function test_an_upcoming_row_drops_the_day_while_it_is_today() {
        compare(format.upcomingWhen("2026-08-18T14:00", false, "2026-08-18", true),
                "14:00");
        compare(format.upcomingWhen("2026-08-18T14:00", false, "2026-08-18", false),
                "2:00 PM");
        // All day, where a time would be a lie.
        compare(format.upcomingWhen("2026-08-18T00:00", true, "2026-08-18", true),
                "All day");
    }

    function test_an_upcoming_row_names_the_day_once_it_is_not_today() {
        compare(format.upcomingWhen("2026-08-19T09:15", false, "2026-08-18", true),
                "Tomorrow · 09:15");
        // Past the friendly names, the weekday carries it.
        compare(format.upcomingWhen("2026-08-21T09:15", false, "2026-08-18", true),
                "Friday · 09:15");
        compare(format.upcomingWhen("2026-08-21T00:00", true, "2026-08-18", true),
                "Friday · All day");
        compare(format.upcomingWhen("", false, "2026-08-18", true), "");
    }

    // --- elapsed --------------------------------------------------------------

    // Both stamps in the same kind, so the assertion is arithmetic and not the
    // machine's zone. The mixed pair — a UTC instant against a local wall clock,
    // which is what the status line actually holds — gets its own case below.
    function test_the_ladder_of_words_for_how_long_ago() {
        compare(format.relativeAgo("2026-08-18T14:00:00Z", "2026-08-18T14:00:30Z"),
                "just now");
        // The boundary: 59s is still "just now", 60 is a minute.
        compare(format.relativeAgo("2026-08-18T14:00:00Z", "2026-08-18T14:00:59Z"),
                "just now");
        compare(format.relativeAgo("2026-08-18T14:00:00Z", "2026-08-18T14:01:00Z"),
                "1 min ago");
        compare(format.relativeAgo("2026-08-18T14:00:00Z", "2026-08-18T14:03:00Z"),
                "3 min ago");
        compare(format.relativeAgo("2026-08-18T14:00:00Z", "2026-08-18T14:59:59Z"),
                "59 min ago");
        compare(format.relativeAgo("2026-08-18T14:00:00Z", "2026-08-18T15:00:00Z"),
                "1 hr ago");
        compare(format.relativeAgo("2026-08-18T14:00:00Z", "2026-08-19T13:59:00Z"),
                "23 hr ago");
        compare(format.relativeAgo("2026-08-18T14:00:00Z", "2026-08-19T14:00:00Z"),
                "1 day ago");
        compare(format.relativeAgo("2026-08-18T14:00:00Z", "2026-08-22T14:00:00Z"),
                "4 days ago");
    }

    // A server's clock a little ahead of this machine's is ordinary; "in -2 min"
    // is not a thing a status line should ever say.
    function test_an_instant_in_the_future_is_just_now_and_not_a_negative() {
        compare(format.relativeAgo("2026-08-18T14:05:00Z", "2026-08-18T14:00:00Z"),
                "just now");
    }

    // The real pair: `GoogleSync.lastSync` is UTC off a server, `now` is the
    // shell's own local wall-clock stamp. Built with `Date` here on purpose, so
    // the case holds in any zone the test runs in — which is the whole claim.
    function test_a_utc_instant_is_compared_against_a_local_wall_clock() {
        const now = "2026-08-18T14:15";
        const threeMinutesBefore = new Date(Date.parse(now) - 3 * 60 * 1000).toISOString();
        compare(format.relativeAgo(threeMinutesBefore, now), "3 min ago");
    }

    function test_a_stamp_that_is_not_one_answers_empty() {
        compare(format.relativeAgo("", "2026-08-18T14:00"), "");
        compare(format.relativeAgo("2026-08-18T14:00", ""), "");
        compare(format.relativeAgo("never", "2026-08-18T14:00"), "");
    }
}
