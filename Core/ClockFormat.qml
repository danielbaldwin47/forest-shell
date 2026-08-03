// How this shell writes the time — the whole shell, one answer (#49, #93).
//
// Four surfaces show a clock — the bar, the lock, the dashboard's header and
// the settings tab that describes it — and #93 is what happens when each
// decides for itself: the bar read `19:26` while the lock read `7:30 PM`, on
// the same machine, minutes apart. Every one of them now asks this file, which
// is a home for the decision that is not any one surface's, and which imports
// nothing but QtQuick, so `tests/` reaches it.
//
// **This file holds the rule; `weatherTime.clock.format` holds the choice.**
// The key is three-valued — `auto`, `12h`, `24h` — and `auto` is the default,
// because a shell that has not been told anything should read the time the way
// the rest of the machine does. The locale reading and the key are kept as two
// functions rather than one because they are two decisions: `use24Hour` is what
// the locale says, `is24Hour` is what the shell shows, and `tests/` checks them
// separately.
//
// Nothing here reads `Config` itself. A file that imported `qs.Core`'s
// singletons would be a file `qmltestrunner` cannot load (see CLAUDE.md's first
// seam), so the caller passes the key's value in — which is one argument at
// four call sites against an untestable rule, and the wrong trade in the other
// direction.
import QtQuick

QtObject {
    id: policy

    /// Whether the user's *locale* writes time on a 24-hour clock, read off the
    /// locale's own short-time format. This is what `auto` resolves to and
    /// nothing else — the shell's actual answer is `is24Hour` below.
    ///
    /// Qt time formats are built from h/H/m/s/z, `t` for the zone and AP/ap for
    /// the meridiem, so the presence of an `a` is exactly the 12-hour signal.
    function use24Hour(localeTimeFormat: string): bool {
        return !localeTimeFormat || localeTimeFormat.toLowerCase().indexOf("a") < 0;
    }

    /// The shell's answer: the key when it names a clock, the locale when it
    /// says `auto`.
    ///
    /// Anything unrecognised falls to the locale rather than to a hardcoded
    /// clock. `Coerce.oneOf` already keeps `Config.values` inside
    /// `schema.clockFormats`, so an unknown string here means a caller that
    /// bypassed the schema — and the locale is a better answer for one of those
    /// than 24-hour is for a user in Chicago.
    function is24Hour(preference: string, localeTimeFormat: string): bool {
        if (preference === "24h")
            return true;
        if (preference === "12h")
            return false;
        return policy.use24Hour(localeTimeFormat);
    }

    /// The clock itself. No seconds at any size: they are a wakeup a minute
    /// times sixty for a glyph nobody is watching (#22 §5, and the argument in
    /// Core/Time.qml).
    function timeFormat(use24Hour: bool): string {
        return use24Hour ? "HH:mm" : "h:mm AP";
    }

    /// The two above, composed — and the only one of the four a surface should
    /// call. The parts are kept apart because they are separate decisions that
    /// `tests/` checks separately; a surface has no business knowing that, and
    /// a nested call at four call sites is four chances to nest it differently,
    /// which is precisely how #93 happened.
    ///
    ///     Qt.formatDateTime(Time.now, ClockFormat.timeFormatFor(
    ///         Config.values.weatherTime.clock.format,
    ///         Qt.locale().timeFormat(Locale.ShortFormat)))
    function timeFormatFor(preference: string, localeTimeFormat: string): string {
        return policy.timeFormat(policy.is24Hour(preference, localeTimeFormat));
    }

    /// The date under a clock that has room for one — the lock's, and the
    /// dashboard header's.
    readonly property string dateFormat: "dddd, d MMMM"

    /// The date *beside* a clock, for a strip with one line to say both things
    /// in. This is the bar's shape (`ddd d MMM   HH:mm`), named here so that the
    /// surface that adopts it is choosing a written-down format rather than a
    /// string in its own file.
    readonly property string dateFormatCompact: "ddd d MMM"
}
