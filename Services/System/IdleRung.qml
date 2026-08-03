// One rung of the idle ladder: an `IdleMonitor` that re-arms when its timeout
// changes (#139).
//
// `IdleMonitor` re-registers with the compositor when `enabled` goes false and
// back to true, and does *not* when only `timeout` changes — measured against
// `ext-idle-notify-v1` on a nested Hyprland: a monitor armed at 3600 s and then
// shortened to 2 s never fired, while the same monitor toggled off and on fired
// at once. Nothing in the protocol makes that surprising — a notification is
// created with its timeout baked in, so a new timeout needs a new notification
// — but the property is settable, so the shell's own ladder read as if it
// rebound, and #139 is what that cost: every rung on the System tab (#55)
// silently kept its old timeout until the shell was restarted.
//
// Filed upstream as quickshell-mirror/quickshell#938 (#151), with a standalone
// probe verified on Quickshell 0.3.0 — whose idle_notify sources are identical
// to master at filing time. If upstream makes a `timeout` write re-register,
// this wrapper can shed the pulse and become a plain `IdleMonitor` alias; the
// `rearmed()` signal and its log line are the only other thing callers use.
//
// The fix is one pulse. A timeout change disables the monitor for a tick, which
// is the one thing that does re-register it, and the binding brings it back
// with the new value already in place. A rung that is off does not pulse: it
// has no notification to replace, and `armed` going true arms it correctly on
// its own.
//
// What a caller sees is `isIdle`, and it moves the way the underlying monitor's
// does — with one extra edge on a re-arm, false while the pulse is out. That
// edge is the correct reading rather than an artefact: a rung whose timeout
// just changed has not been idle for the new duration, and the stage undoing
// itself and counting again is what a user lengthening a timeout is asking for.
import QtQuick
import Quickshell.Wayland

QtObject {
    id: rung

    /// Whether this rung is armed at all — `row.enabled` from IdlePolicy.
    property bool armed: false
    /// The rung's timeout in seconds.
    property real seconds: 0
    property bool respectInhibitors: true

    /// True once the compositor says the session has been idle for `seconds`.
    readonly property bool isIdle: rung.monitor.isIdle

    /// Emitted once the replacement notification is up, so the ladder can say
    /// so — a rung that silently kept its old timeout is exactly the shape of
    /// #139, and of #81 before it.
    signal rearmed()

    readonly property IdleMonitor monitor: IdleMonitor {
        enabled: rung.armed && !rung.rearm.running
        timeout: rung.seconds
        respectInhibitors: rung.respectInhibitors
    }

    /// One tick, which is all it takes: the monitor is torn down when this
    /// starts and rebuilt when it stops, by then reading the new timeout.
    readonly property Timer rearm: Timer {
        interval: 1
        repeat: false

        onTriggered: rung.rearmed()
    }

    onSecondsChanged: if (rung.armed) rung.rearm.restart()
}
