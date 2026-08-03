// One clock-format decision, and the check that it stays one (#49, #93).
//
// #93 was two surfaces answering the same question differently — the bar in
// 24-hour, the lock following the locale. There is one rule now
// (Core/ClockFormat.qml) behind one key (`weatherTime.clock.format`), so this
// file covers the rule itself: what the key says, what `auto` falls back to,
// and that the two are separable — the surfaces have nothing left to get
// wrong beyond calling it.
import QtQuick
import QtTest
import "../Core"

TestCase {
    id: testCase

    name: "ClockFormat"

    ClockFormat { id: clock }

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

    function test_the_key_overrides_the_locale_in_both_directions() {
        // The reason the key exists: a locale is not a preference. Someone on
        // en_US who reads 24-hour had no way to say so, and "change your system
        // language" is not a clock setting.
        for (const format of testCase.localeFormats) {
            verify(clock.is24Hour("24h", format), format);
            verify(!clock.is24Hour("12h", format), format);
        }
    }

    function test_auto_is_the_locale_and_so_is_anything_unrecognised() {
        // `auto` is the default, so this is what nearly every machine gets.
        // Unrecognised falls the same way rather than to a hardcoded clock:
        // Coerce.oneOf keeps Config.values inside schema.clockFormats, so a
        // strange value here is a caller that went around the schema — and for
        // one of those the locale is a better answer than 24-hour is in
        // Chicago.
        for (const format of testCase.localeFormats)
            for (const preference of ["auto", "", "12", "24", "twenty-four"])
                compare(clock.is24Hour(preference, format),
                        clock.use24Hour(format), preference + " / " + format);
    }

    function test_the_composed_call_is_the_two_decisions_in_order() {
        // What the surfaces call, so that none of them nests the pair itself.
        for (const format of testCase.localeFormats)
            for (const preference of ["auto", "12h", "24h"])
                compare(clock.timeFormatFor(preference, format),
                        clock.timeFormat(clock.is24Hour(preference, format)),
                        preference + " / " + format);
        compare(clock.timeFormatFor("auto", "HH:mm"), "HH:mm");
        compare(clock.timeFormatFor("auto", "h:mm AP"), "h:mm AP");
        compare(clock.timeFormatFor("12h", "HH:mm"), "h:mm AP");
        compare(clock.timeFormatFor("24h", "h:mm AP"), "HH:mm");
    }

    function test_the_two_surfaces_that_disagreed_now_read_the_same_minute() {
        // #93 as it was reported, at the seam: the bar showed `19:26` and the
        // lock `7:30 PM`. The surfaces differ in *shape* — the bar puts the
        // date beside the time, the lock puts it under — but the minute is one
        // string, built once, and both of them pass the same two arguments.
        const evening = new Date(2026, 7, 1, 19, 30);
        for (const preference of ["auto", "12h", "24h"])
            for (const format of testCase.localeFormats) {
                const time = Qt.formatDateTime(
                    evening, clock.timeFormatFor(preference, format));
                const bar = Qt.formatDateTime(
                    evening, clock.dateFormatCompact + "   "
                             + clock.timeFormatFor(preference, format));
                verify(bar.endsWith(time), bar + " vs " + time);
            }
        compare(Qt.formatDateTime(evening, clock.timeFormatFor("24h", "h:mm AP")),
                "19:30");
        compare(Qt.formatDateTime(evening, clock.timeFormatFor("12h", "HH:mm")),
                "7:30 PM");
        compare(Qt.formatDateTime(evening, clock.dateFormat), "Saturday, 1 August");
    }

    function test_the_date_formats_say_the_date_and_not_the_time() {
        for (const format of [clock.dateFormat, clock.dateFormatCompact]) {
            verify(format.indexOf("m") < 0, format + " carries minutes");
            verify(format.indexOf("H") < 0 && format.indexOf("h") < 0,
                   format + " carries an hour");
            verify(/d/.test(format) && /M/.test(format), format);
        }
    }

    function test_every_word_the_key_accepts_is_a_word_this_file_reads() {
        // The schema's `clockFormats` and this file's `is24Hour` are the two
        // halves of one key, in two files, and nothing else pins them together.
        // Spelled out rather than imported: Core/SettingsSchema.qml pulls in
        // Coerce, which qmltestrunner cannot load, so this is the list as
        // written there — tst_schemas.qml checks that end of it.
        const words = ["auto", "12h", "24h"];
        compare(words.filter(w => clock.is24Hour(w, "h:mm AP")), ["24h"]);
        compare(words.filter(w => !clock.is24Hour(w, "HH:mm")), ["12h"]);
    }
}
