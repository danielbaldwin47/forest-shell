pragma Singleton

// What a clock says, resolved for this machine (#93).
//
// `Time.now` is *when*; this is *how it is written*. Four surfaces draw a clock
// — the bar strip, the lock, the dashboard header and the Weather & Time tab —
// and #93 is what happened when each worked that out for itself: the bar
// hardcoded 24 hours while the lock followed the locale, so one shell read
// `Sat 1 Aug   19:26` on one surface and `7:30 PM` on the other.
//
//     text: Qt.formatDateTime(Time.now, TimeFormat.time)
//
// **The rule is not here.** Core/ClockFormat.qml holds it, imports nothing but
// QtQuick and is what `tests/` checks (CLAUDE.md's first seam: Quickshell's
// modules are compiled into the binary, so a file that imports them is
// unreachable from qmltestrunner). This file is the other half of that trade —
// the one place the key and the locale meet the rule, so that a surface asks
// for a format string rather than assembling one. Every call site that
// assembles it is another chance to assemble it differently, and four of those
// is the bug.
//
// `pragma Singleton` leads the file for the reason spelled out in
// Core/Config.qml.
import QtQuick
import Quickshell

Singleton {
    id: root

    /// The rule. Instantiated once here rather than once per surface, which is
    /// the whole point of the file.
    readonly property ClockFormat rule: ClockFormat {}

    /// What the user asked for — `auto`, `12h` or `24h`. Read through a
    /// property rather than inline below so the key path appears once in the
    /// shell instead of once per clock.
    readonly property string preference: Config.values.weatherTime.clock.format

    /// The time, as a Qt format string: the key when it names a clock, this
    /// machine's locale when it says `auto`.
    readonly property string time:
        root.rule.timeFormatFor(root.preference,
                                Qt.locale().timeFormat(Locale.ShortFormat))

    /// The date *under* a clock that has room for one — the lock's, and the
    /// dashboard header's.
    readonly property string date: root.rule.dateFormat

    /// The date *beside* one, for a strip with a single line to say both things
    /// in. This is the bar's shape.
    readonly property string dateCompact: root.rule.dateFormatCompact
}
