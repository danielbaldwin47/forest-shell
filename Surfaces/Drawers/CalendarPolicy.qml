// The month grid, as arithmetic (#49).
//
// A calendar is the one card on the dashboard that is entirely a *decision*:
// there is no service behind it, no hardware to be absent and nothing to
// subscribe to. Which weekday a month opens on, what fills the corners of the
// grid around it and which cell is today are all answerable from three integers
// — so all of it is here, on the QtQuick-only side of the line where `tests/`
// can reach it (`tests/tst_calendarpolicy.qml`, 15 cases), and what is left in
// Surfaces/Drawers/Cards/CalendarCard.qml is a `Repeater` over the result.
//
// ## Why the arithmetic and not `Date`
//
// `new Date(year, month - 1, 1).getDay()` would answer the same question in one
// line, and it has two traps this file exists to avoid:
//
//   - **a year under 100 is silently 1900-based**: `new Date(26, 0, 1)` is
//     1926, and the wrong answer is a plausible weekday rather than an error;
//   - **a `Date` is a local-time instant**, so a grid built out of them shifts
//     under a timezone whose offset is not a whole number of days from UTC,
//     and "which day is today" becomes a question about the machine's clock
//     rather than about the calendar.
//
// Sakamoto's method below is the whole of the replacement: it is exact in the
// proleptic Gregorian calendar for any year, and it needs no `Date` at all.
//
// ## Conventions
//
// Months are **1-12**, because every other number in this file is one-based and
// a lone zero-based one is the off-by-one that produces a January labelled
// February. Weekdays are **0-6, Sunday first**, which is QML's own numbering
// (`Locale.Sunday` is 0) — so the locale's `firstDayOfWeek` can be handed
// straight to `weeks()` without translation.
import QtQuick

QtObject {
    id: policy

    /// The grid is a fixed six rows of seven, whatever the month.
    ///
    /// Six because five is not always enough — a 31-day month opening on the
    /// last column spills into a sixth — and a card that changed height as you
    /// paged would move every card under it. The cost is that short months
    /// carry a whole extra week of their neighbours, which is what `current`
    /// below is for.
    readonly property int rows: 6
    readonly property int columns: 7

    readonly property var monthLengths: [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    /// Whether a year has a 29th of February: every fourth, except centuries,
    /// except every fourth century. All three clauses, because the shell will
    /// outlive 2100 and the two-clause version is right until it is not.
    function leapYear(year: int): bool {
        return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
    }

    function daysInMonth(year: int, month: int): int {
        return month === 2 && policy.leapYear(year) ? 29 : policy.monthLengths[month - 1];
    }

    /// The weekday the 1st of a month falls on, 0-6 with Sunday at 0.
    ///
    /// Sakamoto's method. `t` is the accumulated day-of-week offset of each
    /// month's first day within a common year; January and February are counted
    /// against the previous year so that the leap day lands at the end of it and
    /// the century corrections need no special case.
    function firstWeekday(year: int, month: int): int {
        const t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
        const y = month < 3 ? year - 1 : year;
        return (y + Math.floor(y / 4) - Math.floor(y / 100) + Math.floor(y / 400)
                + t[month - 1] + 1) % 7;
    }

    /// The seven weekday numbers of the header row, in the order this locale
    /// writes them. Numbers and not names: the names are `Qt.locale().dayName`,
    /// which is a formatting job and belongs to the card.
    function weekdays(firstDay: int): var {
        const out = [];
        for (let i = 0; i < policy.columns; i++)
            out.push((firstDay + i) % 7);
        return out;
    }

    /// The grid: six rows of seven cells, each
    /// `{ year, month, day, current }`.
    ///
    /// The cells outside the month are the neighbouring months' real dates
    /// rather than blanks, and they carry their own year and month — a blank
    /// corner reads as a missing day, and a cell that knew only its number
    /// could not say whether the 1st in the last row is next month's or a
    /// second copy of this one's (which is the bug `isToday` below is written
    /// against).
    function weeks(year: int, month: int, firstDay: int): var {
        const leading = (policy.firstWeekday(year, month) - firstDay + 7) % 7;
        const previous = policy.shift(year, month, -1);
        const next = policy.shift(year, month, 1);
        const inPrevious = policy.daysInMonth(previous.year, previous.month);
        const inThis = policy.daysInMonth(year, month);

        const out = [];
        for (let row = 0; row < policy.rows; row++) {
            const week = [];
            for (let column = 0; column < policy.columns; column++) {
                // Day of the month, one-based, allowed to run off either end.
                const day = row * policy.columns + column - leading + 1;
                if (day < 1)
                    week.push({ year: previous.year, month: previous.month,
                                day: inPrevious + day, current: false });
                else if (day > inThis)
                    week.push({ year: next.year, month: next.month,
                                day: day - inThis, current: false });
                else
                    week.push({ year: year, month: month, day: day, current: true });
            }
            out.push(week);
        }
        return out;
    }

    /// Whether a cell is today — all three of year, month and day, and that is
    /// the whole point of asking. The 1st of September sits in August's last
    /// row, and a day-number match alone would draw two todays in one grid on
    /// the 1st of August.
    function isToday(cell: var, year: int, month: int, day: int): bool {
        return cell !== undefined && cell !== null
            && cell.year === year && cell.month === month && cell.day === day;
    }

    /// The month `delta` months away, as `{ year, month }`. Rolls the year over
    /// at both ends, and takes any delta rather than ±1 so that "a year back"
    /// is one call and not twelve.
    function shift(year: int, month: int, delta: int): var {
        const zeroBased = (month - 1) + delta;
        return {
            year: year + Math.floor(zeroBased / 12),
            month: ((zeroBased % 12) + 12) % 12 + 1
        };
    }
}
