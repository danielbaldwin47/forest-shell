// How this shell writes the time (#49, and the half of #93 a new surface can
// settle for itself).
//
// Three surfaces show a clock — the bar, the lock and now the dashboard's
// header — and #93 is what happens when each decides for itself: the bar reads
// `19:26` while the lock reads `7:30 PM`, on the same machine, minutes apart.
// The dashboard would have been the third such decision, so the decision moved
// here instead: this file is a home for it that is not any one surface's, and it
// imports nothing but QtQuick, so `tests/` reaches it.
//
// **It does not own a setting, and deliberately does not invent one.** #50 owns
// `weatherTime`'s clock keys, and a key named here would be a key that ticket
// has to migrate away from. What this file holds is the *interim rule* — follow
// the locale — stated once, so that when #50 lands it replaces one function
// rather than three surfaces.
//
// #93 remains open after this, and the remaining work is small and named: the
// bar's Clock.qml and the lock's LockSurface.qml both still answer for
// themselves (`Surfaces/Lock/LockPolicy.qml` holds the lock's copy of the rule,
// which `tests/tst_clockformat.qml` pins to this one so the two cannot drift
// while both exist).
import QtQuick

QtObject {
    id: policy

    /// Whether the user's locale writes time on a 24-hour clock, read off the
    /// locale's own short-time format rather than a config key we would then
    /// have to migrate when #50 adds the real one.
    ///
    /// Qt time formats are built from h/H/m/s/z, `t` for the zone and AP/ap for
    /// the meridiem, so the presence of an `a` is exactly the 12-hour signal.
    function use24Hour(localeTimeFormat: string): bool {
        return !localeTimeFormat || localeTimeFormat.toLowerCase().indexOf("a") < 0;
    }

    /// The clock itself. No seconds at any size: they are a wakeup a minute
    /// times sixty for a glyph nobody is watching (#22 §5, and the argument in
    /// Core/Time.qml).
    function timeFormat(use24Hour: bool): string {
        return use24Hour ? "HH:mm" : "h:mm AP";
    }

    /// The two above, composed — and what every surface actually calls. The
    /// pair is kept apart because they are two decisions and `tests/` checks
    /// them separately (and because LockPolicy holds its own copy of both while
    /// #93 is open); a surface has no business knowing that, and a triple-nested
    /// call at three call sites is three chances to nest it differently.
    ///
    ///     Qt.formatDateTime(Time.now, ClockFormat.timeFormatFor(
    ///         Qt.locale().timeFormat(Locale.ShortFormat)))
    function timeFormatFor(localeTimeFormat: string): string {
        return policy.timeFormat(policy.use24Hour(localeTimeFormat));
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
