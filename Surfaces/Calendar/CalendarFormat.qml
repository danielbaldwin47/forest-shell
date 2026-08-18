// The calendar's words: every string the surface prints that is derived from a
// date rather than typed by a person.
//
// A header, a column heading, an hour label, an event's time range, its
// duration and the compact stamp on a month chip are all the same kind of
// decision — which parts of a date survive into this much space — and they are
// all here rather than in the views, for the reason CLAUDE.md's first seam
// gives: a decision written inside a `Text` element is a decision no test can
// reach. `tests/tst_calendarformat.qml` reaches all of it.
//
// ## What it does not decide
//
// **Whether the clock is 12- or 24-hour.** That is already decided, once, for
// the whole shell (`Core/ClockFormat.qml`, #93 — four surfaces once disagreed
// about the same minute). Every function here that could care takes `use24` as
// an argument and asks nobody; `Core/TimeFormat.qml` is the singleton that
// resolves the `weatherTime.clock.format` key against the locale, and the
// calendar view passes the answer down. A second reading of that key in this
// file would be a second chance to read it differently.
//
// **Day and minute arithmetic.** `Services/Calendar/CalendarTime.qml` owns it,
// and this file parses nothing itself — no `Date`, no regex, no month lengths.
// Days are `"2026-08-18"` and stamps are local wall-clock minutes
// `"2026-08-18T09:15"`, exactly as that file's header sets out.
//
// ## Conventions
//
// Months are **1-12** and weekdays are **0-6 Sunday-first**, matching
// `Surfaces/Drawers/CalendarPolicy.qml` and `CalendarTime`. The month-name
// arrays are indexed by that same 1-12 month number — index 0 is an empty
// string that is never rendered — because a zero-based names array beside
// one-based month numbers everywhere else is exactly the off-by-one that
// labels January "February". A picker that wants the twelve names takes
// `monthLong.slice(1)`.
//
// The range dash is an **en dash with spaces** (` – `, U+2013), which is what a
// span of dates or times takes in English typography; a hyphen is for
// compounds and reads as one when it lands between two numbers.
//
// Anything malformed returns `""` (or `null` where the caller is asked to
// branch), never a plausible-looking guess. A header that is briefly empty is a
// bug someone reports; a header confidently naming the wrong week is one nobody
// notices.
import QtQuick
import "../../Services/Calendar"

QtObject {
    id: format

    /// The arithmetic this file leans on rather than repeating. See the header:
    /// no `Date`, and no second parser.
    property CalendarTime time: CalendarTime {}

    // --- names ----------------------------------------------------------------

    /// Month names, indexed 1-12. Index 0 is a placeholder, never a month.
    readonly property var monthLong: ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    /// The same twelve, abbreviated the way a range header abbreviates them
    /// (`"Aug 18 – 24, 2026"`). Title case, not caps: these appear inside a
    /// sentence-shaped title, and caps in the middle of one shout.
    readonly property var monthShort: ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// Weekday names, 0-6 Sunday-first — the unrotated data behind the two
    /// rotating functions below.
    readonly property var weekdayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    readonly property var weekdayAbbrevs: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// The seven long weekday names in the order this locale writes them,
    /// starting at `firstDay` (0 Sunday, 1 Monday — `CalendarTime`'s numbering).
    function weekdayLong(firstDay: int): var {
        return format.rotate(format.weekdayNames, firstDay);
    }

    /// The seven short ones, same rotation.
    function weekdayShort(firstDay: int): var {
        return format.rotate(format.weekdayAbbrevs, firstDay);
    }

    /// The heading row above a grid of days — the month grid's and the week
    /// view's, which must agree or the two views look like two products.
    ///
    /// Caps live here and not in `weekdayShort`, because caps are a property of
    /// *headings* rather than of the names: the same "Tue" appears in prose
    /// elsewhere, and a surface that uppercased it for itself would be the
    /// place the two headers drift apart.
    function weekdayHeadings(firstDay: int): var {
        return format.weekdayShort(firstDay).map(name => name.toUpperCase());
    }

    /// Rotate a seven-element week so it opens on `firstDay`. Out-of-range or
    /// non-integer values fold back into 0-6 rather than truncating the week —
    /// a header with six columns is worse than a header that starts on Sunday.
    function rotate(names: var, firstDay: int): var {
        const start = ((firstDay % 7) + 7) % 7;
        const out = [];
        for (let i = 0; i < 7; i++)
            out.push(names[(start + i) % 7]);
        return out;
    }

    // --- titles ---------------------------------------------------------------

    /// The header over a view: what the user would say they are looking at.
    ///
    /// `anchorIso` is any day inside the period — the week title is derived
    /// from the week `anchorIso` falls in rather than from the day itself, so
    /// callers may pass the selected day and never the week's own first day.
    ///
    /// An unrecognised view returns `""`. The alternative is picking a form on
    /// the caller's behalf, and a month header over a week grid is a bug that
    /// reads as a design choice.
    function title(view: string, anchorIso: string, firstDay: int): string {
        if (view === "month")
            return format.monthTitle(anchorIso);
        if (view === "day")
            return format.dayTitle(anchorIso);
        if (view === "week") {
            const start = format.time.weekStart(anchorIso, firstDay);
            if (!start)
                return "";
            return format.dayRange(start, format.time.addDays(start, 6));
        }
        return "";
    }

    /// `title` split for the toolbar, which sets the two halves differently:
    /// `{lead, year}` — `"August"` + `"2026"`, `"Aug 17 – 23"` + `"2026"`,
    /// `"Tuesday, 18 August"` + `"2026"`.
    ///
    /// The toolbar sets `lead` in Newsreader and `year` in the UI face at
    /// `textMuted`, which is the one place in the shell the display font is
    /// used twice. Splitting here rather than there is the same argument
    /// `dayHeader` makes: the view would otherwise have to take a string this
    /// file just built and pull it apart again with a regex of its own, and two
    /// regexes over one format is how a header ends up reading `"August 20"`.
    ///
    /// Only a *trailing* year is taken, and only when it is the last word. The
    /// cross-year range `"Dec 29, 2025 – Jan 4, 2026"` therefore leaves its
    /// first year where it is and lifts only the second — the lead reads
    /// `"Dec 29, 2025 – Jan 4"`, which is exactly the week it names.
    ///
    /// An unrecognised view gives `{lead: "", year: ""}` rather than `null`, so
    /// a toolbar binding onto `.lead` renders an empty title instead of
    /// throwing on every frame.
    function titleParts(view: string, anchorIso: string, firstDay: int): var {
        const full = format.title(view, anchorIso, firstDay);
        const match = /^(.*?)[,\s]*\s(\d{4})$/.exec(full);
        if (!match)
            return { "lead": full, "year": "" };
        return { "lead": match[1], "year": match[2] };
    }

    /// `"August 2026"`.
    function monthTitle(iso: string): string {
        const d = format.time.parseDay(iso);
        return d ? format.monthLong[d.month] + " " + d.year : "";
    }

    /// The sidebar's mini month. The same words as `monthTitle` today, named
    /// separately so the sidebar is not calling `title("month", …)` while
    /// showing a week — and so a sidebar that narrows can shorten this without
    /// touching the header that names the view.
    function miniMonthTitle(iso: string): string {
        return format.monthTitle(iso);
    }

    /// `"Tuesday, August 18, 2026"` — the day view's header, which has the room
    /// to spell the weekday out and is the one place the shell says which day of
    /// the week you are actually looking at.
    function dayTitle(iso: string): string {
        const d = format.time.parseDay(iso);
        if (!d)
            return "";
        return format.weekdayNames[format.time.dayOfWeek(iso)] + ", " + format.monthLong[d.month] + " " + d.day + ", " + d.year;
    }

    /// A span of days, dropping whatever both ends share.
    ///
    ///   same month   `"Aug 18 – 24, 2026"`
    ///   same year    `"Aug 31 – Sep 6, 2026"`
    ///   neither      `"Dec 29, 2025 – Jan 4, 2026"`
    ///   one day      `"Aug 18, 2026"`
    ///
    /// The year is repeated only when the two ends disagree about it, and that
    /// is the whole rule: a repeated year in `"Aug 18, 2026 – Aug 24, 2026"` is
    /// the reader's eye doing work the header should have done. Multi-day event
    /// labels use this too, which is why it is public rather than folded into
    /// `title`.
    ///
    /// A range whose end precedes its start returns `""`, for the reason
    /// `duration` refuses a negative one: `"Aug 24 – 18, 2026"` is a span no
    /// calendar contains, but it is shaped exactly like one that is, so it
    /// reads as a real week rather than as the store bug it is. A zero-length
    /// range is not that — the two ends are the same day, and that is the
    /// one-day form above.
    function dayRange(startIso: string, endIso: string): string {
        const a = format.time.parseDay(startIso);
        const b = format.time.parseDay(endIso);
        if (!a || !b)
            return "";
        if (format.time.compare(startIso, endIso) > 0)
            return "";
        if (startIso === endIso)
            return format.monthShort[a.month] + " " + a.day + ", " + a.year;
        if (a.year !== b.year)
            return format.monthShort[a.month] + " " + a.day + ", " + a.year + " – " + format.monthShort[b.month] + " " + b.day + ", " + b.year;
        if (a.month !== b.month)
            return format.monthShort[a.month] + " " + a.day + " – " + format.monthShort[b.month] + " " + b.day + ", " + a.year;
        return format.monthShort[a.month] + " " + a.day + " – " + b.day + ", " + a.year;
    }

    /// The two lines over a week column: `{ weekday: "TUE", day: "18" }`.
    ///
    /// The day number is unpadded — it is set large and on its own, where a
    /// leading zero reads as a typo rather than as alignment. The pieces are
    /// returned apart because the column sets them in two sizes; joining them
    /// here would hand the view a string it has to split again.
    ///
    /// `null` for a day that is not one, so the column can render nothing
    /// rather than a header reading "undefined".
    function dayHeader(iso: string): var {
        const d = format.time.parseDay(iso);
        if (!d)
            return null;
        return {
            weekday: format.weekdayAbbrevs[format.time.dayOfWeek(iso)].toUpperCase(),
            day: String(d.day)
        };
    }

    // --- clock ----------------------------------------------------------------

    /// The label down the time gutter, on the hour: `"1 PM"` / `"13:00"`.
    ///
    /// No `:00` on the 12-hour side — the gutter is a column of hours, the
    /// minutes are always zero, and printing them is sixty pixels of noise
    /// repeated twenty-four times. The 24-hour side keeps them because `"13"`
    /// alone reads as a day number in a calendar of all places.
    function hourLabel(hour: int, use24: bool): string {
        if (hour < 0 || hour > 23)
            return "";
        if (use24)
            return format.time.pad2(hour) + ":00";
        return (hour % 12 || 12) + (hour < 12 ? " AM" : " PM");
    }

    /// One stamp as a clock time: `"9:15 AM"` / `"09:15"`. The long form, for
    /// an editor field or a tooltip; `chipTime` is the short one.
    function stampTime(stamp: string, use24: bool): string {
        const s = format.time.parseStamp(stamp);
        if (!s)
            return "";
        if (use24)
            return format.time.pad2(s.hour) + ":" + format.time.pad2(s.minute);
        return (s.hour % 12 || 12) + ":" + format.time.pad2(s.minute) + (s.hour < 12 ? " AM" : " PM");
    }

    /// An event's time range.
    ///
    ///   24-hour        `"09:15 – 10:00"`
    ///   shared half    `"9:15 – 10:00 AM"`
    ///   crossing noon  `"11:30 AM – 1:00 PM"`
    ///
    /// The meridiem is written once when both ends are in the same half of the
    /// same day. **The same day matters as much as the same half**: 9:00 today
    /// to 9:30 tomorrow are both AM, and `"9:00 – 9:30 AM"` would describe a
    /// half-hour meeting instead of a day-long one. A range that crosses a
    /// midnight prints both meridiems, and the day it crosses into is the
    /// caller's to say — `dayRange` is next door.
    ///
    /// An end before its start returns `""`, the same refusal `dayRange` and
    /// `duration` make: an event that ends before it begins is a store bug, and
    /// `"10:00 – 9:15 AM"` is that bug printed as if it were a meeting.
    function timeRange(startStamp: string, endStamp: string, use24: bool): string {
        const a = format.time.parseStamp(startStamp);
        const b = format.time.parseStamp(endStamp);
        if (!a || !b)
            return "";
        if (format.time.compare(startStamp, endStamp) > 0)
            return "";
        if (use24)
            return format.stampTime(startStamp, use24) + " – " + format.stampTime(endStamp, use24);
        const sameDay = format.time.dayOf(startStamp) === format.time.dayOf(endStamp);
        const sameHalf = (a.hour < 12) === (b.hour < 12);
        if (sameDay && sameHalf)
            return (a.hour % 12 || 12) + ":" + format.time.pad2(a.minute) + " – " + format.stampTime(endStamp, use24);
        return format.stampTime(startStamp, use24) + " – " + format.stampTime(endStamp, use24);
    }

    /// A week chip's start-only time — **the first token of `timeRange`, and
    /// nothing else**.
    ///
    ///   with meridiem     `"10:30 AM"` / `"10:30"` on a 24-hour clock
    ///   without           `"10:30"`
    ///
    /// One surface, one clock grammar. A chip too narrow for a range prints the
    /// half of the range it can carry, in the notation the wide chip beside it
    /// already used; it does **not** switch to `chipTime`'s `"10:30a"`, which is
    /// the month grid's notation and exists there because a month cell has one
    /// line for a title and a time together. Two notations a column apart make
    /// the eye re-learn the clock per chip width, and the reader who mistakes
    /// `10a` for a duration has been failed by the calendar, not by their eyes.
    ///
    /// `withMeridiem` is the caller's, because only the caller knows how many
    /// pixels the token has — `EventLayoutPolicy.chipContent` decides it, and
    /// the 24-hour clock has no meridiem to decide about.
    function startTime(stamp: string, use24: bool, withMeridiem: bool): string {
        const s = format.time.parseStamp(stamp);
        if (!s)
            return "";
        if (use24)
            return format.time.pad2(s.hour) + ":" + format.time.pad2(s.minute);
        const clock = (s.hour % 12 || 12) + ":" + format.time.pad2(s.minute);
        return withMeridiem ? clock + (s.hour < 12 ? " AM" : " PM") : clock;
    }

    /// How long something lasts, at most two units: `"45m"`, `"1h"`,
    /// `"1h 30m"`, `"2d"`, `"1d 4h"`.
    ///
    /// Two units and not three, and they are the two largest non-zero ones —
    /// `"1d 1h"` for a day and an hour and a half. This label sits inside an
    /// event chip beside a title, where a third unit is what pushes the title
    /// out; and at day scale the odd thirty minutes is below the precision
    /// anyone reads the label for.
    ///
    /// A negative duration returns `""`. An event that ends before it starts is
    /// a store bug, and `"-15m"` printed in a chip is that bug wearing a label.
    function duration(minutes: real): string {
        if (!Number.isFinite(minutes) || minutes < 0)
            return "";
        const whole = Math.round(minutes);
        if (whole === 0)
            return "0m";
        const parts = [];
        const days = Math.floor(whole / 1440);
        const hours = Math.floor((whole % 1440) / 60);
        const mins = whole % 60;
        if (days > 0)
            parts.push(days + "d");
        if (hours > 0)
            parts.push(hours + "h");
        if (mins > 0)
            parts.push(mins + "m");
        return parts.slice(0, 2).join(" ");
    }

    /// The stamp on a month-view chip, where the time shares one line with the
    /// event's title in a cell about a hundred and twenty pixels wide:
    /// `"9a"`, `"9:15a"`, `"12p"`, `"1:05p"` — and `"09:15"` on a 24-hour clock.
    ///
    /// Two compressions on the 12-hour side, both paying for title characters.
    /// The meridiem is one lowercase letter rather than three uppercase ones,
    /// which is the long-standing calendar convention for exactly this slot.
    /// And `:00` is dropped, because a whole hour is the common case for a
    /// meeting and the colon is what tips the line into eliding the title.
    ///
    /// The 24-hour side keeps both digits and the colon. There is no letter to
    /// drop there, `"9"` alone reads as a date, and the padding is what lets a
    /// stack of chips line their titles up.
    function chipTime(stamp: string, use24: bool): string {
        const s = format.time.parseStamp(stamp);
        if (!s)
            return "";
        if (use24)
            return format.time.pad2(s.hour) + ":" + format.time.pad2(s.minute);
        return (s.hour % 12 || 12) + (s.minute ? ":" + format.time.pad2(s.minute) : "") + (s.hour < 12 ? "a" : "p");
    }

    // --- relative -------------------------------------------------------------

    /// `"Today"`, `"Tomorrow"`, `"Yesterday"` — or `null` for every other day,
    /// including a malformed one.
    ///
    /// `null` rather than the formatted date, because the caller's question is
    /// "is there a friendlier name for this day", and answering it with a date
    /// makes every caller compare the result against the date it already had.
    /// `today` is passed in for the same reason `use24` is: a policy that read
    /// the clock could not be tested, and `Core/Time.qml` already owns the tick.
    function relativeDay(iso: string, todayIso: string): var {
        const delta = format.time.diffDays(todayIso, iso);
        if (delta === 0)
            return "Today";
        if (delta === 1)
            return "Tomorrow";
        if (delta === -1)
            return "Yesterday";
        return null;
    }
}
