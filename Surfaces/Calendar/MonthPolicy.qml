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

    /// Which of the seven header columns are weekend columns, in column order.
    ///
    /// The header has no day behind it — it is above all six rows at once — so
    /// it cannot read `isWeekend` off a cell, and a view that worked it out
    /// inline would be the second place in the shell that decides what a
    /// weekend is. Same `Locale.Sunday === 0` convention as `grid`.
    function weekendColumns(firstDay: int): var {
        const start = isNaN(firstDay) ? 1 : ((Math.floor(firstDay) % 7) + 7) % 7;
        const out = [];
        for (let c = 0; c < policy.columns; c++) {
            const dow = (start + c) % 7;
            out.push(dow === 0 || dow === 6);
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

    /// How many chips fit *once the row's banner lanes have taken their share*.
    ///
    /// This is the join `chipsPerCell` alone cannot make, and getting it wrong
    /// is invisible in a test of either half: `laneCount` counts the bars a row
    /// must reserve room for, `chipsPerCell` counts what fits in a height, and
    /// nothing until now subtracted the first from the second. A view that asks
    /// `chipsPerCell(rowHeight)` and then draws banners on top of the answer
    /// draws one chip too many in every row that has a multi-day event in it —
    /// the last one under the cell's floor, where the grid line cuts it in half.
    ///
    /// Lanes cost `lanes * (laneHeight + gap)`: the gap is *below* each lane,
    /// because the last one still has to be separated from the first chip.
    /// A row with no banners costs nothing, so an ordinary week is exactly
    /// `chipsPerCell`.
    ///
    /// `laneHeight` defaults to `chipHeight` — a banner and a chip are the same
    /// height in the month grid, which is what makes the two stacks read as one
    /// column — and every other argument means what it does in `chipsPerCell`.
    function chipCapacity(cellHeight: real, lanes: int, chipHeight, headerHeight, gap, laneHeight): int {
        const chip = chipHeight === undefined || chipHeight === null ? policy.chipHeight : chipHeight;
        const space = gap === undefined || gap === null ? policy.chipGap : gap;
        const lane = laneHeight === undefined || laneHeight === null ? chip : laneHeight;
        const count = Math.max(0, isNaN(lanes) ? 0 : Math.floor(lanes));
        return policy.chipsPerCell(cellHeight - count * (lane + space),
                                   chip, headerHeight, space);
    }

    /// The two capacities a cell actually has: `{ full, withMore }`.
    ///
    /// **"+N more" is not a chip and charging it as one costs a whole event.**
    /// `chipCapacity` counts chip-sized rows, and `cellChips` gives the last of
    /// them back to the affordance — which is right only while the affordance is
    /// as tall as a chip. It is not: it is one line of 11pt text, `moreHeight`
    /// tall, and at the surface's own numbers (113px row, 26px numeral band,
    /// 21px chips at a 2px gap) charging it 21 is the difference between three
    /// events and two. `full` is what fits when nothing is hidden; `withMore` is
    /// what fits beside the line that says so.
    ///
    /// `moreHeight` defaults to `chipHeight`, which is exactly the old
    /// behaviour, so a caller that has no separate affordance keeps it.
    function cellCapacity(cellHeight: real, lanes: int, chipHeight, headerHeight, gap, laneHeight, moreHeight): var {
        const chip = chipHeight === undefined || chipHeight === null ? policy.chipHeight : chipHeight;
        const space = gap === undefined || gap === null ? policy.chipGap : gap;
        const more = moreHeight === undefined || moreHeight === null ? chip : moreHeight;
        const full = policy.chipCapacity(cellHeight, lanes, chip, headerHeight, space, laneHeight);
        const withMore = policy.chipCapacity(cellHeight - (more + space), lanes,
                                             chip, headerHeight, space, laneHeight);
        return { "full": full, "withMore": Math.min(withMore, full) };
    }

    /// `cellChips` again, asked with both capacities: everything if it fits,
    /// otherwise as many chips as fit *beside* the "+N more" line.
    function cellChipsFor(events: var, iso: string, capacity: var): var {
        const timed = policy.cellEvents(events, iso, -1).timed;
        const caps = capacity || ({ "full": 0, "withMore": 0 });
        const full = isNaN(caps.full) ? 0 : Math.floor(caps.full);
        if (timed.length <= full)
            return { "shown": timed, "moreCount": 0 };
        const room = Math.max(0, isNaN(caps.withMore) ? 0 : Math.floor(caps.withMore));
        const shown = timed.slice(0, room);
        return { "shown": shown, "moreCount": timed.length - shown.length };
    }

    /// What a cell draws when its banners are drawn as **row bars** rather than
    /// as chips inside it: `{ shown, moreCount }` over the timed events alone.
    ///
    /// `cellEvents` answers the other question — what a cell shows when it owns
    /// the whole stack — and a month grid that draws bars across the row would
    /// count each banner twice if it asked that one: once in the bar and once in
    /// the chip list underneath it.
    ///
    /// The overflow rule is the part worth stating. "+N more" is itself a row,
    /// so a cell with room for three rows and four events shows **two** chips
    /// and "+2 more" — never three chips and "+1 more", which needs four rows
    /// and is how a month grid ends up with a line hanging below its own cell.
    /// A capacity of zero has no room even for the affordance, so everything is
    /// hidden and the caller is told how much.
    function cellChips(events: var, iso: string, capacity): var {
        const timed = policy.cellEvents(events, iso, -1).timed;
        const uncapped = capacity === undefined || capacity === null || isNaN(capacity) || capacity < 0;
        const cap = uncapped ? timed.length : Math.floor(capacity);
        if (timed.length <= cap)
            return { "shown": timed, "moreCount": 0 };
        if (cap <= 0)
            return { "shown": [], "moreCount": timed.length };
        const shown = timed.slice(0, cap - 1);
        return { "shown": shown, "moreCount": timed.length - shown.length };
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
    ///
    /// **A bar that crosses a week boundary keeps its lane.** `laneHints` is the
    /// `{ id: lane }` map the *previous* row hands forward (see `laneHintsOf`),
    /// and a segment that continues from it is placed in that lane first, before
    /// the greedy pass runs. Measured without it: Cabin weekend (Sat 22 → Mon
    /// 24) drew in lane 2 on Saturday and lane 1 on Sunday, and the horizontal
    /// thread the eye follows across the wrap was broken by the jump — the two
    /// halves read as two events that happen to share a name. A hint whose lane
    /// is already taken by a longer bar is dropped rather than forced; the
    /// greedy pass then answers as it always did, so a hint can never make a row
    /// deeper than it needs to be.
    function spans(events: var, rowStartIso: string, laneHints): var {
        if (!policy.time.isDay(rowStartIso))
            return [];
        const hints = (laneHints === undefined || laneHints === null) ? ({}) : laneHints;
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
                "lane": -1
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
        const freeIn = function (lane, segment) {
            while (lane >= lanes.length)
                lanes.push(new Array(policy.columns).fill(false));
            for (let column = segment.startCol; column < segment.startCol + segment.span; column++)
                if (lanes[lane][column])
                    return false;
            return true;
        };
        const occupy = function (lane, segment) {
            for (let column = segment.startCol; column < segment.startCol + segment.span; column++)
                lanes[lane][column] = true;
            segment.lane = lane;
        };

        // The continuations first, each into the lane it held last row. A hint
        // that no longer fits is simply not taken.
        for (const carried of segments) {
            if (!carried.continuesLeft)
                continue;
            const hint = hints[carried.id];
            if (hint === undefined || hint === null || isNaN(hint) || hint < 0)
                continue;
            const lane = Math.floor(hint);
            if (freeIn(lane, carried))
                occupy(lane, carried);
        }

        for (const segment of segments) {
            if (segment.lane >= 0)
                continue;
            let lane = 0;
            while (!freeIn(lane, segment))
                lane++;
            occupy(lane, segment);
        }

        segments.sort(function (a, b) {
            if (a.lane !== b.lane)
                return a.lane - b.lane;
            return a.startCol - b.startCol;
        });
        return segments;
    }

    /// What this row hands the next one: `{ id: lane }` for every segment that
    /// runs off its right edge. Only those — a bar that ended here has no claim
    /// on next week's lanes, and hinting it would pin a lane against events that
    /// really are there.
    function laneHintsOf(segments: var): var {
        const out = ({});
        for (const segment of (segments || []))
            if (segment.continuesRight)
                out[segment.id] = segment.lane;
        return out;
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

    /// How many lanes deep the banners are **over one column** — the height that
    /// column's own chips have to clear, which is not the row's.
    ///
    /// The difference is a whole week of events. A row's lane count is the
    /// deepest stack anywhere in it, and charging every cell that height was
    /// measured to empty the three busiest days of a month: at 1180x760 a row is
    /// 113px, two banner lanes cost 46, and the Monday and Tuesday either side
    /// of a Wednesday conference — with no bar over them at all — were left with
    /// 43px, room for one row, which the "+N more" affordance then took. Three
    /// cells showed nothing but "+4 more" while the cell between them showed a
    /// chip.
    ///
    /// Charging each column only for the bars that actually cross it keeps the
    /// alignment where alignment is the point — a cell under a banner starts its
    /// chips below that banner, so a bar never has a chip beside it pretending
    /// to be in the same lane — and gives the pixels back everywhere else. The
    /// stack stays top-aligned in every cell either way, which is the edge the
    /// eye actually reads down.
    ///
    /// Depth, not count: a lane-1 bar over a column with no lane-0 bar still
    /// sits at the lane-1 offset, so the column owes both.
    function laneDepthAt(segments: var, column: int): int {
        const col = Math.floor(column);
        let deepest = -1;
        for (const segment of (segments || [])) {
            const start = segment.startCol;
            if (col >= start && col < start + segment.span)
                deepest = Math.max(deepest, segment.lane);
        }
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
