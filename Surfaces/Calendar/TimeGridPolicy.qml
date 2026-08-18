// Where a minute sits on the week grid, and which day a pixel belongs to.
//
// The week and day views are one component with a different column count, and
// almost everything they draw is arithmetic over two numbers: how tall an hour
// is, and how wide a column is. That arithmetic is the whole of this file, so
// the view stays a picture — a `Repeater` of columns, a `Repeater` of hour
// lines, a `Rectangle` per event — and every off-by-one it could have is
// checkable offscreen (`tests/tst_timegridpolicy.qml`).
//
// Two currencies, matching CalendarTime.qml: a *day* is `"2026-08-18"` and a
// *stamp* is `"2026-08-18T09:15"`, both local wall clock, neither an instant.
// Day and minute arithmetic is delegated to `CalendarTime` rather than redone
// here — `Date` appears nowhere in the calendar, for the reasons its header
// gives.
//
// The conventions the rest of the grid is built on:
//
//   - **Minutes run 0..1440 within a day**, midnight to midnight. 1440 is a
//     real value, not an overflow: it is where an event ending at midnight
//     stops, and it is the bottom edge of the grid.
//   - **y is measured from the top of the day**, not from the top of the
//     viewport. Scrolling is the view's job (`visibleScrollY` only says where
//     to start), so nothing here has to know it happened.
//   - **x is measured from the left of the grid, gutter included.** `gridWidth`
//     is the full width of the grid surface and the hour gutter is the first
//     `gutterWidth` of it, so a view can hand over its own `width` and the
//     `x` a `MouseArea` reports without adjusting either. A point inside the
//     gutter belongs to no column, which is what makes `-1` meaningful.
//   - **Weekend is Saturday and Sunday** — a shading rule, not a locale one, so
//     it does not move when `firstDay` does.
//   - **A non-positive `hourHeight` is a caller bug and yields `NaN`**, not a
//     collapsed grid: a zero-height hour would map every minute of the day to
//     y=0 and every drag would silently land at midnight.
import QtQuick
import "../../Services/Calendar"

QtObject {
    id: grid

    /// Pixels per hour. The view sets it — a zoom control is a change to this
    /// one number — and every function below takes it as an optional argument
    /// so a test can state its own without touching the object.
    property real hourHeight: 60

    /// The minute the grid opens on. Seven is early enough to have the working
    /// day below it and late enough that the night is scrolled away.
    readonly property int defaultStartHour: 7

    /// The drag snap, in minutes. Shared with `EventPolicy.minMinutes` by
    /// coincidence of value, not by dependency: this one is about where a
    /// pointer lands, that one about how short an event may be.
    readonly property int defaultStep: 15

    property CalendarTime time: CalendarTime {}

    // --- the vertical axis ----------------------------------------------------

    /// The hour height a call should use: its own argument when it was given
    /// one, the property otherwise. Non-positive is `NaN` — see the header.
    function hourPixels(hourHeight) {
        const h = (hourHeight === undefined || hourHeight === null) ? grid.hourHeight : hourHeight;
        return (typeof h === "number" && isFinite(h) && h > 0) ? h : NaN;
    }

    /// The full height of one day's column.
    function dayHeight(hourHeight) {
        return 24 * grid.hourPixels(hourHeight);
    }

    /// Minutes since midnight -> y from the top of the day.
    function minutesToY(minutes, hourHeight) {
        return minutes / 60 * grid.hourPixels(hourHeight);
    }

    /// y from the top of the day -> minutes since midnight. Neither snapped nor
    /// clamped: a raw pointer position is all three of those things separately,
    /// and a drag that wants the unsnapped value (a ghost following the cursor)
    /// would have to undo the rounding otherwise.
    function yToMinutes(y, hourHeight) {
        return y / grid.hourPixels(hourHeight) * 60;
    }

    /// To the nearest `step` minutes, a half rounding forward to the later
    /// line. A non-positive step is a no-op rather than a division by zero.
    function snap(minutes, step) {
        const s = (step === undefined || step === null) ? grid.defaultStep : step;
        if (!(s > 0) || !isFinite(minutes))
            return minutes;
        return Math.round(minutes / s) * s;
    }

    /// Into the day, 0..1440 inclusive at both ends.
    function clampMinutes(minutes: real): real {
        if (!isFinite(minutes))
            return NaN;
        return Math.max(0, Math.min(1440, minutes));
    }

    // --- the hour gutter ------------------------------------------------------

    /// One gutter label. `"01:00"` in 24-hour form; `"1 AM"` in 12-hour, with
    /// no minutes on it — the gutter marks whole hours, and ":00" on every line
    /// is thirteen characters of noise in a column that has to stay narrow.
    function hourLabel(hour: int, use24: bool): string {
        const h = ((Math.round(hour) % 24) + 24) % 24;
        if (use24)
            return grid.time.pad2(h) + ":00";
        return (h % 12 === 0 ? 12 : h % 12) + (h < 12 ? " AM" : " PM");
    }

    /// The gutter, top to bottom: `[{hour, label, y}]` for **1..23**.
    ///
    /// Midnight and 24:00 are deliberately absent. Both sit exactly on an edge
    /// of the grid, where half the glyph would be clipped away, and the day
    /// they belong to is already named by the column header.
    function hourLabels(use24, hourHeight) {
        const h = grid.hourPixels(hourHeight);
        const out = [];
        for (let hour = 1; hour <= 23; hour++) {
            out.push({
                "hour": hour,
                "label": grid.hourLabel(hour, use24 === true),
                "y": grid.minutesToY(hour * 60, h)
            });
        }
        return out;
    }

    /// Where the now-line goes for a wall-clock stamp, or **-1 for "no line"**.
    ///
    /// Only the minutes of the stamp are read; which column it belongs on is
    /// the view's question, and it already knows its own days. -1 is
    /// unambiguous because a real answer is never negative.
    function nowLineY(stamp: string, hourHeight): real {
        const minutes = grid.time.parseMinutes(stamp);
        if (minutes < 0)
            return -1;
        return grid.minutesToY(minutes, hourHeight);
    }

    /// How close an hour label may come to the live-time label before one of
    /// them has to go. Two labels at pt(11) are ~15px tall, so 20 is one gap
    /// between them plus a little air.
    readonly property int labelGap: 20

    /// Whether an hour label is suppressed because the live time is sitting on
    /// top of it.
    ///
    /// **This is not "hide the current hour", which is what it looks like it
    /// should be.** At 13:40 with `hourRow: 56` the now-line is 37px below the
    /// 13:00 rule and 19px above the 14:00 one — so hiding *the current hour*
    /// would blank a label nothing is near and leave the one actually being
    /// overprinted in place. The question is a distance, so the rule is a
    /// distance. `nowY < 0` — the clock is not in this view — hides nothing.
    function hourLabelHidden(labelY: real, nowY: real, gap): bool {
        if (!(nowY >= 0) || !isFinite(labelY))
            return false;
        const g = (gap === undefined || gap === null) ? grid.labelGap : gap;
        return Math.abs(labelY - nowY) < g;
    }

    // --- the horizontal axis --------------------------------------------------

    /// Saturday or Sunday. `false` for anything that is not a day.
    function isWeekend(iso: string): bool {
        const dow = grid.time.dayOfWeek(iso);
        return dow === 0 || dow === 6;
    }

    /// The columns of a view, left to right:
    /// `[{iso, weekday, dayNumber, isToday, isWeekend}]`.
    ///
    /// **Seven columns is a week** and is aligned to `firstDay`, so the anchor
    /// can be any day in it and the view does not jump when you move within
    /// one. **Any other count is a run of days beginning at the anchor**, which
    /// is what makes `count: 1` the day view with no second code path.
    ///
    /// `todayIso` is passed in rather than read from a clock: this file has no
    /// clock, and the harness that poses a picture needs to say what "today" is
    /// or no two runs match. Omitting it means no column is today.
    function dayColumns(anchorIso, firstDay, count, todayIso) {
        const n = Math.round(count);
        if (!(n > 0) || !grid.time.isDay(anchorIso))
            return [];
        const start = n === 7 ? grid.time.weekStart(anchorIso, firstDay) : anchorIso;
        if (!start)
            return [];
        const out = [];
        for (let i = 0; i < n; i++) {
            const iso = grid.time.addDays(start, i);
            const parsed = grid.time.parseDay(iso);
            const dow = grid.time.dayOfWeek(iso);
            out.push({
                "iso": iso,
                "weekday": dow,
                "dayNumber": parsed ? parsed.day : -1,
                "isToday": iso === todayIso,
                "isWeekend": dow === 0 || dow === 6
            });
        }
        return out;
    }

    /// The width of one column. `NaN` if the gutter leaves nothing over.
    function columnWidth(gutterWidth: real, gridWidth: real, count: int): real {
        const n = Math.round(count);
        const w = (gridWidth - gutterWidth) / n;
        return (n > 0 && isFinite(w) && w > 0) ? w : NaN;
    }

    /// Which column a point is in, or **-1**: in the gutter, off either edge,
    /// or a grid too narrow to have columns at all. A view uses the -1 to
    /// refuse a drag rather than to start one at column 0.
    ///
    /// The index is reconciled against `xForColumn`'s own edges rather than
    /// trusted from the division. `(x - gutter) / w` and `gutter + i * w` are
    /// two different roundings of the same number, and on a column width that
    /// does not divide evenly — which is every real window, since a week is
    /// seven columns of whatever is left over — they disagree by an ulp. That
    /// puts a click on a column's own left edge in the column *before* it: an
    /// event created one day out, from a grid that looks correct. Stepping to
    /// the edge makes the two functions exact inverses at every width (measured
    /// over ~34k width/count/index combinations: 3284 disagreed before, none
    /// after). The loops run at most one step each.
    function columnForX(x: real, gutterWidth: real, gridWidth: real, count: int): int {
        const n = Math.round(count);
        const w = grid.columnWidth(gutterWidth, gridWidth, count);
        if (isNaN(w) || !isFinite(x) || x < gutterWidth || x >= gridWidth)
            return -1;
        let i = Math.max(0, Math.min(n - 1, Math.floor((x - gutterWidth) / w)));
        while (i > 0 && x < gutterWidth + i * w)
            i--;
        while (i < n - 1 && x >= gutterWidth + (i + 1) * w)
            i++;
        return i;
    }

    /// The left edge of a column. `NaN` for an index outside the view, so a bad
    /// index parks nothing at x=0 where it would look deliberate.
    function xForColumn(index: int, gutterWidth: real, gridWidth: real, count: int): real {
        const w = grid.columnWidth(gutterWidth, gridWidth, count);
        if (isNaN(w) || index < 0 || index >= Math.round(count))
            return NaN;
        return gutterWidth + index * w;
    }

    /// A point on the grid -> `{iso, minutes}`, snapped, or `null` if the point
    /// is not on a column.
    ///
    /// `columns` is the array `dayColumns` returned, which is what the view
    /// already has bound to its `Repeater`; passing it rather than re-deriving
    /// the days here means a drag can never disagree with the columns it is
    /// being dragged across.
    ///
    /// Snap first, then clamp: snapping runs to the nearest line and clamping
    /// keeps the result inside the day, so a drag near midnight lands on 1440
    /// rather than being rounded past it and then wrapped into tomorrow.
    function gridPointToStamp(x, y, columns, gutterWidth, gridWidth, hourHeight, step) {
        if (!columns || columns.length === undefined || columns.length === 0)
            return null;
        const col = grid.columnForX(x, gutterWidth, gridWidth, columns.length);
        if (col < 0)
            return null;
        const minutes = grid.clampMinutes(grid.snap(grid.yToMinutes(y, hourHeight), step));
        if (isNaN(minutes))
            return null;
        return { "iso": columns[col].iso, "minutes": minutes };
    }

    /// Where the view scrolls to on open: the top of `startHour`, so the
    /// working day is on screen and the night is above it.
    ///
    /// With a `viewportHeight` the answer is clamped so the last hour of the
    /// day still sits at the bottom of the view; without one it is unclamped,
    /// because a `Flickable` that does not yet know its own height would
    /// otherwise be told to scroll to zero.
    function visibleScrollY(startHour, hourHeight, viewportHeight) {
        const h = grid.hourPixels(hourHeight);
        const hour = (startHour === undefined || startHour === null) ? grid.defaultStartHour : startHour;
        const y = grid.minutesToY(Math.max(0, Math.min(24, hour)) * 60, h);
        if (viewportHeight === undefined || viewportHeight === null || !isFinite(viewportHeight))
            return y;
        return Math.max(0, Math.min(y, grid.dayHeight(h) - viewportHeight));
    }

    // --- events ---------------------------------------------------------------

    /// Where an event sits in one day's column: `{y, h, continuesAbove,
    /// continuesBelow}`, or `null` if it does not appear on that day at all.
    ///
    /// An event that crosses midnight is **clipped to the day**, not moved and
    /// not dropped: a 22:00-02:00 event is drawn twice, as the last two hours
    /// of one column and the first two of the next, which is what a week view
    /// shows. The two flags say which end was cut, so the view can mark the
    /// edge rather than pretending the event began at 00:00.
    ///
    /// `end` is exclusive (EventPolicy's rule), so an event ending at midnight
    /// fills its own day to the bottom and does not put a zero-height sliver on
    /// the next one.
    function eventRect(start: string, end: string, dayIso: string, hourHeight) {
        if (!grid.time.isDay(dayIso) || !grid.time.isStamp(start) || !grid.time.isStamp(end))
            return null;
        const midnight = grid.time.formatStamp(dayIso, 0);
        const from = grid.time.diffMinutes(midnight, start);
        const to = grid.time.diffMinutes(midnight, end);
        if (!(to > from) || to <= 0 || from >= 1440)
            return null;
        const top = Math.max(0, from);
        const bottom = Math.min(1440, to);
        const h = grid.hourPixels(hourHeight);
        return {
            "y": grid.minutesToY(top, h),
            "h": grid.minutesToY(bottom - top, h),
            "continuesAbove": from < 0,
            "continuesBelow": to > 1440
        };
    }
}
