// The month view, as arithmetic (#49 continued).
//
// The month grid itself is already decided: Surfaces/Drawers/CalendarPolicy.qml
// answers "which six rows of seven days is this month" for the dashboard card,
// and this file imports and reuses it rather than growing a second copy that
// can disagree with the first. A calendar shell with two month grids in it is a
// calendar shell with one of them wrong.
//
// What is here is everything the *event-bearing* month needs on top of that
// grid, and all of it is a decision rather than a picture:
//
//   - **grid()** re-expresses `CalendarPolicy.weeks()` in this surface's own
//     currency — the `"2026-08-18"` day string every other calendar policy
//     speaks (Services/Calendar/CalendarTime.qml) — and stamps each cell with
//     the three facts a delegate would otherwise re-derive per frame;
//   - **cellEvents()** decides what a cell shows and what it hides behind
//     "+N more", which is the whole of the month view's information design;
//   - **spans()** turns multi-day events into per-row bars with lanes, which is
//     the only genuinely hard shape in the view — an event running Thursday to
//     the following Tuesday is *two* bars, one clipped at each end;
//   - **chipsPerCell()** is the arithmetic that connects the two: how many
//     chips fit is a function of the cell's measured height, so the cap that
//     `cellEvents` applies is a number the layout computes rather than a
//     constant somebody guessed.
//
// ## Conventions
//
// Days are local wall-clock strings and never `Date`s, for the reasons
// CalendarTime's header sets out. Weekdays are 0-6 Sunday-first, matching
// CalendarPolicy and QML's own `Locale.Sunday`. Columns are 0-6 left to right
// *as drawn*, so column 0 is whatever `firstDay` says it is — but a weekend is
// still Saturday and Sunday, because that is a fact about the days and not
// about where they were printed.
//
// ## Why the anchor month arithmetic is here and not in CalendarTime
//
// `nextMonth`/`prevMonth` clamp the day: the month after the 31st of January is
// the 28th of February, not the 3rd of March. That clamp is a *view* decision —
// it exists so paging forward and back six times returns you to a month you
// recognise — and CalendarTime has no `addMonths` for the same reason it has no
// `Date`: an unclamped one would be a trap. If a second surface ever needs the
// same clamp, that is the moment to promote it; one caller is not yet a spine.
import QtQuick
import "../Drawers"
import "../../Services/Calendar"

QtObject {
    id: policy

    /// Six rows of seven, whatever the month — CalendarPolicy's shape, restated
    /// here so a caller sizing a grid does not have to reach through.
    readonly property int rows: 6
    readonly property int columns: 7

    /// Defaults for `chipsPerCell`, named rather than inlined so a surface that
    /// draws chips a different size can say so in one place.
    readonly property int chipHeight: 20
    readonly property int cellHeaderHeight: 22
    readonly property int chipGap: 2

    property CalendarPolicy month: CalendarPolicy {}
    property CalendarTime time: CalendarTime {}
    property EventPolicy events: EventPolicy {}

    // --- the grid -------------------------------------------------------------

    /// The month containing `anchorIso`, as six rows of seven cells:
    /// `{ iso, day, inMonth, isToday, isWeekend }`.
    ///
    /// `todayIso` is optional and there is no clock behind it — a policy that
    /// asked the machine what day it is would draw a different picture on every
    /// run, and the capture harness could never take the same photograph twice.
    /// Omit it and no cell claims to be today, which is the honest answer.
    ///
    /// `iso` is the real date of every cell including the corners, so the 1st of
    /// September in August's last row is `"2026-09-01"` and not a bare `1` that
    /// could be mistaken for this month's.
    function grid(anchorIso: string, firstDay: int, todayIso): var {
        const anchor = policy.time.parseDay(anchorIso);
        if (!anchor)
            return [];
        const first = ((Math.round(firstDay) % 7) + 7) % 7;
        const today = policy.time.isDay(todayIso) ? todayIso : "";
        const weeks = policy.month.weeks(anchor.year, anchor.month, first);

        const out = [];
        for (const week of weeks) {
            const row = [];
            for (const cell of week) {
                const iso = policy.time.dayIso(cell.year, cell.month, cell.day);
                const dow = policy.time.dayOfWeek(iso);
                row.push({
                    "iso": iso,
                    "day": cell.day,
                    "inMonth": cell.current,
                    "isToday": today !== "" && iso === today,
                    "isWeekend": dow === 0 || dow === 6
                });
            }
            out.push(row);
        }
        return out;
    }

    // --- what a cell shows ----------------------------------------------------

    /// Whether an event is drawn as a *banner* — a bar across the top of its
    /// cells — rather than as a chip inside one.
    ///
    /// Two kinds qualify and they are not the same kind: an all-day event, and
    /// a timed event that outlives its own day. Both want a bar because both
    /// are false as a chip: "09:00 Nordic QML Days" in Thursday's cell says
    /// nothing about the two days after it.
    function isBanner(event: var): bool {
        if (!event)
            return false;
        return event.allDay === true || policy.events.spansDays(event) > 1;
    }

    /// What the cell for `iso` shows: `{ timed, allDay, shown, moreCount }`.
    ///
    /// `allDay` is the banner set of that day and `timed` everything else, both
    /// in EventPolicy's total order. `shown` is the first `maxChips` of the two
    /// concatenated — **banners first**, because a banner is the thing that is
    /// true all day and a 15:00 coffee is not what you hide it behind — and
    /// `moreCount` is what a "+N more" affordance says.
    ///
    /// A `maxChips` below zero (or absent) means no cap, which is what the day
    /// and week views want when they ask the same question. Zero means the cell
    /// is too short for even one chip, and then `moreCount` is everything: a
    /// cell that can only afford "+3 more" is still telling the truth.
    function cellEvents(events: var, iso: string, maxChips): var {
        const empty = { "timed": [], "allDay": [], "shown": [], "moreCount": 0 };
        if (!policy.time.isDay(iso))
            return empty;

        const all = policy.events.forDay(events, iso);
        const banners = [];
        const timed = [];
        for (const event of all)
            (policy.isBanner(event) ? banners : timed).push(event);

        const ordered = banners.concat(timed);
        const uncapped = maxChips === undefined || maxChips === null
                      || isNaN(maxChips) || maxChips < 0;
        const cap = uncapped ? ordered.length : Math.floor(maxChips);
        const shown = ordered.slice(0, cap);
        return {
            "timed": timed,
            "allDay": banners,
            "shown": shown,
            "moreCount": ordered.length - shown.length
        };
    }

    /// How many chips fit in a cell of `cellHeight`, given the day-number header
    /// above them.
    ///
    /// `n` chips occupy `n * chipHeight + (n - 1) * gap` — gaps go *between*
    /// chips, so one chip needs no gap and the common short-cell case does not
    /// lose a row to a spacer that is not drawn. Never negative: a cell too
    /// short for its own header shows no chips rather than minus one.
    ///
    /// The arguments after the first are optional and default to the properties
    /// above; they are spelled out so a test can vary one without a surface.
    function chipsPerCell(cellHeight: real, chipHeight, headerHeight, gap): int {
        const chip = chipHeight === undefined || chipHeight === null ? policy.chipHeight : chipHeight;
        const header = headerHeight === undefined || headerHeight === null ? policy.cellHeaderHeight : headerHeight;
        const space = gap === undefined || gap === null ? policy.chipGap : gap;
        const pitch = chip + space;
        if (!(pitch > 0) || isNaN(cellHeight))
            return 0;
        return Math.max(0, Math.floor((cellHeight - header + space) / pitch));
    }

    // --- multi-day bars -------------------------------------------------------

    /// The banner segments of the row that opens on `rowStartIso`, each
    /// `{ id, startCol, span, continuesLeft, continuesRight, lane }`.
    ///
    /// One segment per event *per row*: an event crossing a row boundary is two
    /// segments with `continuesRight` on the first and `continuesLeft` on the
    /// second, which is what lets the view draw an arrow at the cut instead of
    /// pretending the event ended there.
    ///
    /// Lanes are assigned greedily into the lowest free one, over segments taken
    /// left to right and longest first. Greedy is not optimal — a cleverer
    /// packing could sometimes use one lane fewer — but it is *stable*: adding
    /// an event late in the week cannot reshuffle the bars above it, and a
    /// month grid whose rows jump when you create an event reads as a bug. The
    /// longest-first tiebreak is what keeps the long bar on top, where the eye
    /// expects the thing that lasts longest.
    function spans(events: var, rowStartIso: string): var {
        if (!policy.time.isDay(rowStartIso))
            return [];
        const rowEnd = policy.time.addDays(rowStartIso, policy.columns - 1);

        const segments = [];
        for (const event of policy.events.forRange(events, rowStartIso, rowEnd)) {
            if (!policy.isBanner(event))
                continue;
            const first = policy.time.dayOf(event.start);
            const last = policy.events.lastDay(event);
            if (!first || !last)
                continue;
            const startCol = Math.max(0, policy.time.diffDays(rowStartIso, first));
            const endCol = Math.min(policy.columns - 1, policy.time.diffDays(rowStartIso, last));
            if (endCol < startCol)
                continue;
            segments.push({
                "id": event.id,
                "startCol": startCol,
                "span": endCol - startCol + 1,
                "continuesLeft": policy.time.compare(first, rowStartIso) < 0,
                "continuesRight": policy.time.compare(last, rowEnd) > 0,
                "lane": 0
            });
        }

        segments.sort(function (a, b) {
            if (a.startCol !== b.startCol)
                return a.startCol - b.startCol;
            if (a.span !== b.span)
                return b.span - a.span;
            return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
        });

        const lanes = [];
        for (const segment of segments) {
            let lane = 0;
            for (;; lane++) {
                if (lane === lanes.length)
                    lanes.push(new Array(policy.columns).fill(false));
                let free = true;
                for (let column = segment.startCol; column < segment.startCol + segment.span; column++) {
                    if (lanes[lane][column]) {
                        free = false;
                        break;
                    }
                }
                if (free)
                    break;
            }
            for (let column = segment.startCol; column < segment.startCol + segment.span; column++)
                lanes[lane][column] = true;
            segment.lane = lane;
        }

        segments.sort(function (a, b) {
            if (a.lane !== b.lane)
                return a.lane - b.lane;
            return a.startCol - b.startCol;
        });
        return segments;
    }

    /// How many lanes deep a row's banners go — the height the view has to
    /// reserve above the chips. Zero for a row with no banners in it, so an
    /// ordinary week costs nothing.
    function laneCount(segments: var): int {
        let deepest = -1;
        for (const segment of (segments || []))
            deepest = Math.max(deepest, segment.lane);
        return deepest + 1;
    }

    // --- paging ---------------------------------------------------------------

    /// The anchor `delta` months away, with the day **clamped** into the month
    /// it lands in: a month after the 31st of January is the 28th of February.
    ///
    /// Clamping rather than rolling over is what makes paging reversible in the
    /// cases people actually page through — the alternative puts you in March
    /// on the way out of January and never brings you back.
    function shiftMonths(anchorIso: string, delta: int): string {
        const anchor = policy.time.parseDay(anchorIso);
        if (!anchor)
            return "";
        const target = policy.month.shift(anchor.year, anchor.month, Math.round(delta));
        const length = policy.time.daysInMonth(target.year, target.month);
        return policy.time.dayIso(target.year, target.month, Math.min(anchor.day, length));
    }

    function nextMonth(anchorIso: string): string {
        return policy.shiftMonths(anchorIso, 1);
    }

    function prevMonth(anchorIso: string): string {
        return policy.shiftMonths(anchorIso, -1);
    }
}
