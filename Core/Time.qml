pragma Singleton

// The shell clock (#12 §3).
//
// One timer for the whole shell rather than one per surface: the bar clock, and
// later the dashboard header and the notification timestamps, all read the same
// `now`, so the idle cost of displaying the time does not scale with how many
// places display it.
//
//     text: Qt.formatDateTime(Time.now, TimeFormat.dateCompact + "   "
//                                        + TimeFormat.time)
//
// The format is deliberately not a literal in that example. It used to be, and
// the literal got copied — the bar hardcoded 24 hours while the lock followed
// the locale, which is #93. Core/TimeFormat.qml is where a clock's shape comes
// from; this singleton only owns *when* it changes.
//
// It ticks **once a minute, on the minute** (Core/TimeTick.qml). #22 §5 allows a
// faster tick only when seconds are actually visible; nothing in v1 shows them,
// and the ticket that first does is the one that adds the opt-in — a writable
// period here would be a knob every consumer could turn and none could turn
// back.
//
// Nothing constructs this singleton but a consumer reading `now`, so a bar with
// no clock module costs no wakeups at all. That is why it is deliberately *not*
// named in Core/ServiceInit.qml.
//
// `pragma Singleton` leads the file for the reason spelled out in
// Core/Config.qml.
import QtQuick
import Quickshell

Singleton {
    id: root

    /// The current time, to the minute.
    property date now: new Date()

    readonly property int periodMs: 60000

    TimeTick { id: tick }

    Timer {
        id: ticker
        repeat: false
        onTriggered: root.advance()
    }

    // Each tick schedules the next one off the wall clock, so a timer that
    // fires late does not push every later minute late with it.
    function advance() {
        root.now = new Date();
        ticker.interval = tick.msUntilNext(Date.now(), root.periodMs);
        ticker.restart();
    }

    Component.onCompleted: root.advance()
}
