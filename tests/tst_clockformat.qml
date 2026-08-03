// One clock-format decision, and the check that it stays one (#49, #93).
//
// #93 is two surfaces answering the same question differently. This file covers
// the shared answer, and — while the lock still holds its own copy of the rule —
// pins the two together, so the drift that produced #93 cannot happen again
// silently between here and there.
import QtQuick
import QtTest
import "../Core"
import "../Surfaces/Lock"

TestCase {
    id: testCase

    name: "ClockFormat"

    ClockFormat { id: clock }
    LockPolicy { id: lock }

    // The short-time formats Qt hands back for the locales this shell is likely
    // to meet, plus the two degenerate answers a missing locale gives.
    readonly property var localeFormats: [
        "HH:mm",        // en_GB, de_DE, fr_FR — 24-hour
        "H:mm",         // a locale that does not pad the hour
        "h:mm AP",      // en_US — 12-hour, Qt's own spelling
        "h:mm ap",      // the lowercase meridiem
        "hh:mm a",      // and the CLDR one
        "",             // no locale at all
        "HH:mm:ss t"    // seconds and a zone, which change nothing here
    ]

    function test_the_meridiem_is_what_makes_a_locale_twelve_hour() {
        verify(clock.use24Hour("HH:mm"));
        verify(clock.use24Hour("H:mm"));
        verify(!clock.use24Hour("h:mm AP"));
        verify(!clock.use24Hour("h:mm ap"));
        verify(!clock.use24Hour("hh:mm a"));
    }

    function test_a_locale_the_shell_cannot_read_is_written_as_24_hour() {
        // Empty is what `Qt.locale().timeFormat()` gives with no locale at all.
        // 24-hour is the unambiguous reading of a time, so it is the one to
        // fall back to rather than the one that needs a suffix to be right.
        verify(clock.use24Hour(""));
    }

    function test_a_zone_suffix_is_not_a_meridiem() {
        // `t` is the timezone and `AP`/`ap` is the meridiem; the rule keys off
        // the `a` alone, so a format carrying both still reads as 24-hour.
        verify(clock.use24Hour("HH:mm:ss t"));
    }

    function test_neither_clock_shows_seconds() {
        // At 60 wakeups a minute to redraw a glyph nobody is watching, seconds
        // would cost most of the idle budget on their own (#22 §5).
        verify(clock.timeFormat(true).indexOf("s") < 0);
        verify(clock.timeFormat(false).indexOf("s") < 0);
    }

    function test_the_two_formats_are_the_two_readings_of_the_same_minute() {
        compare(clock.timeFormat(true), "HH:mm");
        compare(clock.timeFormat(false), "h:mm AP");
    }

    function test_the_composed_call_is_the_two_decisions_in_order() {
        // What the surfaces call, so that none of them nests the pair itself.
        for (const format of testCase.localeFormats)
            compare(clock.timeFormatFor(format),
                    clock.timeFormat(clock.use24Hour(format)), format);
        compare(clock.timeFormatFor("HH:mm"), "HH:mm");
        compare(clock.timeFormatFor("h:mm AP"), "h:mm AP");
    }

    function test_the_date_formats_say_the_date_and_not_the_time() {
        for (const format of [clock.dateFormat, clock.dateFormatCompact]) {
            verify(format.indexOf("m") < 0, format + " carries minutes");
            verify(format.indexOf("H") < 0 && format.indexOf("h") < 0,
                   format + " carries an hour");
            verify(/d/.test(format) && /M/.test(format), format);
        }
    }

    function test_the_lock_and_this_file_answer_the_same_way() {
        // The drift #93 is about, caught at the seam: the lock still holds its
        // own copy of the rule, and while it does, the two have to agree for
        // every locale — otherwise the dashboard and the lock become the next
        // pair of surfaces that disagree.
        for (const format of testCase.localeFormats) {
            compare(clock.use24Hour(format), lock.use24Hour(format), format);
            compare(clock.timeFormat(clock.use24Hour(format)),
                    lock.timeFormat(lock.use24Hour(format)), format);
        }
        compare(clock.dateFormat, lock.dateFormat);
    }
}
