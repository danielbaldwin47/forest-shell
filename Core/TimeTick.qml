// When the shell clock should next wake up.
//
// The idle budget (#22 §5) is `< 5 wakeups/s` with the shell doing nothing, and
// a clock is the one thing on an idle bar that has to wake at all. A repeating
// one-second timer that reformats a string 59 times out of 60 for no visible
// change is the single easiest way to lose that budget, so the tick is **one
// per minute, aligned to the minute** — the display changes on the same edge
// the user's watch does, and the shell sleeps in between.
//
// Alignment is arithmetic rather than calendar work because epoch milliseconds
// and local minutes share their boundaries: every real UTC offset is a whole
// number of minutes, including the half- and quarter-hour ones. That stops
// being true at hour precision, which is why this function does not offer it.
//
// Pure functions, no Quickshell imports, so tests/ can reach them.
import QtQuick

QtObject {
    /// Milliseconds from `nowMs` to the next `periodMs` boundary.
    ///
    /// Always in `(0, periodMs]` — never zero, because a timer asked to fire in
    /// no time at all is a busy loop, and a clock that is exactly on the minute
    /// wants the *next* one.
    ///
    /// Re-derived from the wall clock on every tick rather than accumulated, so
    /// a timer that fires late — a suspended laptop, a busy compositor — costs
    /// one late minute instead of a drift that grows all day.
    function msUntilNext(nowMs: real, periodMs: real): real {
        const period = periodMs > 0 ? periodMs : 1;
        if (!isFinite(nowMs))
            return period;
        // Double modulo so a negative instant cannot produce a negative wait.
        const remainder = ((nowMs % period) + period) % period;
        return period - remainder;
    }
}
