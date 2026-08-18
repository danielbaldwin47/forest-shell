// What the sidebar shows under the calendars list: the next few events, from
// now forward.
//
// ## Why the sidebar needed something here at all
//
// The rail is 248 x 760 and its two lists — the mini-month and the calendars —
// together fill about half of it. The rest was blank, which is not restraint:
// a column that stops halfway down reads as a panel that failed to load, and
// the eye keeps returning to it looking for the thing that is missing. The
// honest options were to space the two existing lists down the rail, which
// makes the gaps look deliberate and says nothing new, or to put something
// there that the grid cannot say. *What is next* is that something: the grid
// answers "what does this week look like", and it takes a scan of seven
// columns to answer "what is next", which is the question you actually have
// while looking at a calendar.
//
// ## Why the arithmetic is here and not in the surface
//
// "The next three" is a decision — which side of *now* an event falls on, what
// an all-day event's "now" even means, how ties break — and decisions live at
// the first seam where a test can hold them. The surface below this file only
// draws rows.
//
// ## What counts as upcoming
//
// A timed event is upcoming while its **start** is at or after now. Not its
// end: an event you are in the middle of has stopped being the thing that is
// next, and a list whose first row is the meeting you are already sitting in
// pushes the one you have to leave for off the bottom.
//
// An all-day event has no start time to compare, so it is upcoming while its
// **date** is today or later — an all-day today stays listed all day, which is
// the whole point of marking a day rather than a moment.
//
// Ties break on title, so two events starting at the same minute list in a
// stable order rather than in whatever order the store happened to hold them.
pragma ComponentBehavior: Bound
import QtQuick
import "../../Services/Calendar"

QtObject {
    id: policy

    /// Where a stamp is taken apart. The day of `"2026-08-18T09:00"` is
    /// `CalendarTime.dayOf`'s answer everywhere in this surface — a policy that
    /// sliced ten characters for itself would be a second definition of what a
    /// day is, and it would be the one nobody updated.
    property CalendarTime time: CalendarTime {}

    /// The default the sidebar asks for. Three rows is what fits between the
    /// calendars list and the footer at the shortest window this surface
    /// allows; a list that scrolls in a rail is a second scroll region beside
    /// the grid's, and two scrollable columns is one more than a calendar
    /// should ever ask a hand to choose between.
    readonly property int defaultLimit: 3

    /// The next `limit` events at or after `nowStamp` (`YYYY-MM-DDTHH:MM`).
    ///
    /// Returns the store's own event objects, untouched — the caller formats
    /// them. A policy that returned display strings would be a policy that had
    /// to know about 24-hour clocks, and the format object already does.
    function next(events: var, nowStamp: string, limit: int): var {
        const capped = limit > 0 ? limit : policy.defaultLimit;
        if (!events || !nowStamp)
            return [];

        const nowDay = policy.time.dayOf(nowStamp);
        const upcoming = events.filter(function (event) {
            if (!event || !event.start)
                return false;
            return event.allDay
                ? policy.time.dayOf(event.start) >= nowDay
                : event.start >= nowStamp;
        });

        upcoming.sort(function (a, b) {
            if (a.start !== b.start)
                return a.start < b.start ? -1 : 1;
            const left = a.title || "";
            const right = b.title || "";
            return left < right ? -1 : (left > right ? 1 : 0);
        });

        return upcoming.slice(0, capped);
    }

    /// Whether an event in that list starts on the same day as `nowStamp`.
    /// The surface uses it to decide whether a row says a weekday at all —
    /// "Today" plus a time is the answer to *when*, and repeating the date on
    /// every row of a three-row list is noise the rail cannot afford.
    function isSameDay(event: var, nowStamp: string): bool {
        if (!event || !event.start || !nowStamp)
            return false;
        return policy.time.dayOf(event.start) === policy.time.dayOf(nowStamp);
    }
}
