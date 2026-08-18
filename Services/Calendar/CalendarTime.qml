// Day and minute arithmetic for the calendar, with no `Date` anywhere in it.
//
// Every other calendar policy leans on this one rather than re-deriving day
// math, and the reason it exists at all is the argument
// Surfaces/Drawers/CalendarPolicy.qml already makes for the month grid:
//
//   - **a year under 100 is silently 1900-based** in a `Date` constructor, so
//     `new Date(26, 7, 18)` is 1926 and the wrong answer is a plausible date
//     rather than an error;
//   - **a `Date` is a local-time instant**, so "which day is this" becomes a
//     question about the machine's clock and its timezone rather than about
//     the calendar, and an event dragged across a DST boundary moves by an
//     hour nobody asked for.
//
// So the two currencies here are strings, and they are both **local wall
// clock**: a *day* is `"2026-08-18"` and a *stamp* is `"2026-08-18T09:15"`.
// Neither is an instant and neither carries a zone. An event at 09:00 is at
// 09:00 wherever the laptop is opened, which is what a person means when they
// write 09:00 in a calendar.
//
// The conversion underneath is Howard Hinnant's days-from-civil / civil-from-
// days pair: exact in the proleptic Gregorian calendar for any year, and pure
// integer arithmetic. Day 0 is 1970-01-01, which was a Thursday — the one
// constant `dayOfWeek` needs.
//
// Weekdays are **0-6, Sunday first**, matching QML's own numbering
// (`Locale.Sunday` is 0) and `CalendarPolicy`'s, so a locale's `firstDayOfWeek`
// can be handed straight to `weekStart` without translation.
import QtQuick

QtObject {
    id: time

    /// Two digits, zero-padded — the only formatting rule in the file.
    function pad2(n: int): string {
        return (n < 10 ? "0" : "") + n;
    }

    function leapYear(year: int): bool {
        return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    }

    function daysInMonth(year: int, month: int): int {
        if (month === 2)
            return time.leapYear(year) ? 29 : 28;
        return [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
    }

    /// Four digits, zero-padded. Years are padded too, and it is not cosmetic:
    /// `parseDay` wants exactly four digits, so an unpadded year 26 would come
    /// back out of `fromOrdinal` as a string this file's own parser rejects.
    function pad4(n: int): string {
        return (n < 10 ? "000" : n < 100 ? "00" : n < 1000 ? "0" : "") + n;
    }

    /// `2026, 8, 18` -> `"2026-08-18"`. Months are 1-12 throughout.
    function dayIso(year: int, month: int, day: int): string {
        return time.pad4(year) + "-" + time.pad2(month) + "-" + time.pad2(day);
    }

    /// `"2026-08-18"` -> `{year, month, day}`, or `null` if it is not one.
    ///
    /// Strict on shape and on range: a store reading a hand-edited file gets a
    /// null it can drop, not a silently rolled-over date. `"2026-02-30"` is not
    /// a day, and answering "2026-03-02" for it would move an event.
    function parseDay(iso: string): var {
        if (typeof iso !== "string")
            return null;
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
        if (!m)
            return null;
        const year = parseInt(m[1], 10);
        const month = parseInt(m[2], 10);
        const day = parseInt(m[3], 10);
        if (month < 1 || month > 12)
            return null;
        if (day < 1 || day > time.daysInMonth(year, month))
            return null;
        return { "year": year, "month": month, "day": day };
    }

    /// `"2026-08-18T09:15"` -> `{year, month, day, hour, minute, minutes}`, or
    /// `null`. `minutes` is minutes since midnight, which is what the grid
    /// wants.
    function parseStamp(stamp: string): var {
        if (typeof stamp !== "string")
            return null;
        const m = /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})$/.exec(stamp);
        if (!m)
            return null;
        const day = time.parseDay(m[1]);
        if (!day)
            return null;
        const hour = parseInt(m[2], 10);
        const minute = parseInt(m[3], 10);
        if (hour > 23 || minute > 59)
            return null;
        return {
            "year": day.year, "month": day.month, "day": day.day,
            "hour": hour, "minute": minute, "minutes": hour * 60 + minute
        };
    }

    function isDay(iso: string): bool {
        return time.parseDay(iso) !== null;
    }

    function isStamp(stamp: string): bool {
        return time.parseStamp(stamp) !== null;
    }

    /// Days since 1970-01-01, for a valid day string. `NaN` for anything else,
    /// so arithmetic on a bad day is loudly bad rather than quietly zero.
    function toOrdinal(iso: string): real {
        const d = time.parseDay(iso);
        if (!d)
            return NaN;
        return time.ordinalOf(d.year, d.month, d.day);
    }

    function ordinalOf(year: int, month: int, day: int): int {
        const y = year - (month <= 2 ? 1 : 0);
        const era = Math.floor(y / 400);
        const yoe = y - era * 400;
        const doy = Math.floor((153 * (month + (month > 2 ? -3 : 9)) + 2) / 5) + day - 1;
        const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
        return era * 146097 + doe - 719468;
    }

    /// The inverse: a day number back to `"YYYY-MM-DD"`.
    function fromOrdinal(ordinal: int): string {
        const z = ordinal + 719468;
        const era = Math.floor(z / 146097);
        const doe = z - era * 146097;
        const yoe = Math.floor((doe - Math.floor(doe / 1460) + Math.floor(doe / 36524)
                                - Math.floor(doe / 146096)) / 365);
        const y = yoe + era * 400;
        const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
        const mp = Math.floor((5 * doy + 2) / 153);
        const day = doy - Math.floor((153 * mp + 2) / 5) + 1;
        const month = mp + (mp < 10 ? 3 : -9);
        return time.dayIso(y + (month <= 2 ? 1 : 0), month, day);
    }

    /// The weekday of a day: 0 Sunday .. 6 Saturday. `-1` for a bad day.
    function dayOfWeek(iso: string): int {
        const ord = time.toOrdinal(iso);
        if (isNaN(ord))
            return -1;
        // 1970-01-01 was a Thursday, which is 4 in Sunday-first numbering.
        return ((ord + 4) % 7 + 7) % 7;
    }

    /// `delta` days later (or earlier). `""` for a bad day, never a guess.
    function addDays(iso: string, delta: int): string {
        const ord = time.toOrdinal(iso);
        if (isNaN(ord))
            return "";
        return time.fromOrdinal(ord + Math.round(delta));
    }

    /// Whole days from `a` to `b`, signed. `NaN` if either is not a day.
    function diffDays(a: string, b: string): real {
        return time.toOrdinal(b) - time.toOrdinal(a);
    }

    /// The first day of the week `iso` falls in, where the week opens on
    /// `firstDay` (0 Sunday, 1 Monday — the locale's own numbering).
    function weekStart(iso: string, firstDay: int): string {
        const dow = time.dayOfWeek(iso);
        if (dow < 0)
            return "";
        const first = ((Math.round(firstDay) % 7) + 7) % 7;
        return time.addDays(iso, -(((dow - first) % 7 + 7) % 7));
    }

    /// The seven days of that week, in order.
    function weekDays(iso: string, firstDay: int): var {
        const start = time.weekStart(iso, firstDay);
        if (!start)
            return [];
        const out = [];
        for (let i = 0; i < 7; i++)
            out.push(time.addDays(start, i));
        return out;
    }

    /// The day half of a stamp: `"2026-08-18T09:15"` -> `"2026-08-18"`.
    function dayOf(stamp: string): string {
        const s = time.parseStamp(stamp);
        return s ? time.dayIso(s.year, s.month, s.day) : "";
    }

    /// Minutes since midnight, or `-1`.
    function parseMinutes(stamp: string): int {
        const s = time.parseStamp(stamp);
        return s ? s.minutes : -1;
    }

    /// A day and a minute-of-day back into a stamp. Minutes outside 0..1439
    /// roll the day, which is what makes "start plus 90 minutes" safe to write
    /// without every caller checking for midnight.
    function formatStamp(iso: string, minutes: int): string {
        if (!time.isDay(iso))
            return "";
        const total = Math.round(minutes);
        const dayShift = Math.floor(total / 1440);
        const within = total - dayShift * 1440;
        const day = dayShift === 0 ? iso : time.addDays(iso, dayShift);
        if (!day)
            return "";
        return day + "T" + time.pad2(Math.floor(within / 60)) + ":" + time.pad2(within % 60);
    }

    /// `delta` minutes later (or earlier), crossing midnight as it must.
    function addMinutes(stamp: string, delta: int): string {
        const s = time.parseStamp(stamp);
        if (!s)
            return "";
        return time.formatStamp(time.dayIso(s.year, s.month, s.day),
                                s.minutes + Math.round(delta));
    }

    /// Signed minutes from `a` to `b`, across any number of days. `NaN` if
    /// either is not a stamp.
    function diffMinutes(a: string, b: string): real {
        const sa = time.parseStamp(a);
        const sb = time.parseStamp(b);
        if (!sa || !sb)
            return NaN;
        return (time.ordinalOf(sb.year, sb.month, sb.day)
                - time.ordinalOf(sa.year, sa.month, sa.day)) * 1440
               + sb.minutes - sa.minutes;
    }

    /// -1, 0 or 1. Works on days and on stamps — both sort lexically by
    /// construction, which is the other reason for this spelling of them — but
    /// stated as a function so callers do not have to know that.
    function compare(a: string, b: string): int {
        if (a === b)
            return 0;
        return a < b ? -1 : 1;
    }
}
