// Where a new event lands when it is asked for from the chrome rather than
// dragged onto the grid.
//
// ## Why this is a decision and not a constant
//
// A `+` in the sidebar has no y coordinate to read a time off, so something has
// to choose one, and "09:00" is only right on a day that is not today. On today
// the useful answer is *next*, not *morning*: the reason to press a create
// button at 13:40 is almost never to schedule something that already started.
//
// So: the next snap boundary after now when the day in view is today, and the
// start of the working day on any other day. Both are guesses, and both are
// guesses the user immediately corrects by dragging the chip — the point is
// that the chip lands somewhere they can see it, which a 09:00 event on a grid
// scrolled to the afternoon does not.
//
// ## Why it clamps
//
// An event created at 23:55 would run past midnight, and this store has no
// concept of an event that spans days. The last start that fits a whole hour is
// what a late press gets, which is visibly wrong in the right direction — the
// chip is on screen at the bottom of today rather than absent.
pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: policy

    /// Minutes after midnight for a new event on `anchorIso`.
    ///
    /// `nowMin` is minutes after midnight *now*, and `snapMin` the grid's own
    /// snap (15), so a chip made from the button lands on the same rules a chip
    /// dragged out by hand does — two create paths that disagreed about where
    /// 13:47 rounds to would be two calendars.
    function startMinute(anchorIso: string, todayIso: string, nowMin: int,
                         snapMin: int, minutes: int): int {
        const snap = snapMin > 0 ? snapMin : 15;
        const length = minutes > 0 ? minutes : 60;
        const latest = 24 * 60 - length;
        if (anchorIso !== todayIso || !todayIso)
            return Math.max(0, Math.min(policy.dayStart, latest));
        const next = Math.ceil((Math.max(0, nowMin) + 1) / snap) * snap;
        return Math.max(0, Math.min(next, latest));
    }

    /// 09:00 — the top of the working day, and the row the week view scrolls to
    /// when it opens, so a chip created on another day is inside the first
    /// screenful rather than above it.
    readonly property int dayStart: 9 * 60
}
