// How overlapping events share the width of a day, as arithmetic.
//
// This decides one thing: given the events on a day, what fraction of the
// column each chip starts at and how wide it is. Nothing here knows a pixel —
// `xFrac`/`wFrac` are 0..1 of whatever width the day column turns out to be,
// so the same numbers are right at any scale, on any monitor, and can be
// asserted without rendering anything. Vertical geometry is the grid's job
// (TimeGridPolicy); this file only ever divides the horizontal.
//
// The algorithm is the one Google Calendar and Notion both use, and each step
// exists because the obvious cheaper version looks wrong:
//
//   - **transitive clustering, not pairwise.** A overlaps B and B overlaps C
//     while A and C do not touch; if A and C are each sized against their own
//     partner they come out half-width and *different* half-widths, and the
//     row reads as three unrelated ideas. One cluster, one width.
//   - **greedy leftmost free column.** Chips settle left as space frees up, so
//     a morning that empties out does not leave a staircase of gaps.
//   - **rightward expansion.** A chip widens into the columns to its right
//     that are free *for its whole span* — this is the Notion move, and it is
//     what stops a lone 2 pm meeting from rendering one-third wide just
//     because 10 am was busy.
//
// Two rules that are easy to get backwards:
//
//   - **touching is not overlapping.** `end` is exclusive (see
//     EventPolicy.qml), so 09:00-10:00 and 10:00-11:00 are one column, not
//     two. Anything else makes back-to-back meetings — the commonest calendar
//     there is — render as a permanently split day.
//   - **a very short event still occupies `minSlotMinutes`** for collision
//     purposes. A five-minute event is drawn a few pixels tall; if it also
//     claimed only five minutes of *width* the meeting starting ten minutes
//     later would sit on top of it and hide it entirely. It is inflated for
//     the collision test only — its drawn height stays its real duration.
//
// `allDayLanes` is the same greedy packing one dimension coarser: the all-day
// row is laid out in whole day columns rather than minutes, and an event
// running past either end of the week is clipped to the week and flagged so
// the surface can draw the arrow rather than a rounded end.
import QtQuick
import "../../Services/Calendar"

QtObject {
    id: policy

    /// The shortest stretch an event can occupy *for collision purposes*.
    readonly property int minSlotMinutes: 15

    property EventPolicy eventPolicy: EventPolicy {}
    readonly property CalendarTime time: policy.eventPolicy.time

    // --- the shared spine -----------------------------------------------------

    /// Minutes since 1970-01-01T00:00 in local wall clock, or `NaN`. Absolute
    /// rather than minutes-since-midnight so an event crossing midnight
    /// compares against its neighbours instead of wrapping under them.
    function absMinutes(stamp: string): real {
        const s = policy.time.parseStamp(stamp);
        if (!s)
            return NaN;
        return policy.time.ordinalOf(s.year, s.month, s.day) * 1440 + s.minutes;
    }

    /// The collision rectangle of one event, or `null` if it is not one:
    /// `from`/`to` are its real minutes and `until` is `to` floored to
    /// `minSlotMinutes` past `from`. An event whose end precedes its start is
    /// not laid out at all — a zero-length one is, because a drag in progress
    /// passes through zero on its way somewhere.
    function slotOf(event: var): var {
        if (!event || !event.id)
            return null;
        const from = policy.absMinutes(event.start);
        const to = policy.absMinutes(event.end);
        if (isNaN(from) || isNaN(to) || to < from)
            return null;
        return {
            "id": event.id,
            "from": from,
            "to": to,
            "until": Math.max(to, from + policy.minSlotMinutes),
            "column": 0
        };
    }

    /// Slots in painting order: earliest first, and where two start together
    /// the longer one first so it takes the leftmost column and the short one
    /// tucks in beside it. Ties break on id so the same day always lays out
    /// the same way.
    function sortedSlots(events: var): var {
        const slots = [];
        const list = events || [];
        for (let i = 0; i < list.length; i++) {
            const slot = policy.slotOf(list[i]);
            if (slot)
                slots.push(slot);
        }
        slots.sort(function (a, b) {
            if (a.from !== b.from)
                return a.from - b.from;
            if (a.until !== b.until)
                return b.until - a.until;
            return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
        });
        return slots;
    }

    /// Slots grouped by transitive overlap. A group closes the moment an event
    /// starts at or after everything before it has ended — at, because
    /// touching is not overlapping.
    function slotClusters(events: var): var {
        const slots = policy.sortedSlots(events);
        const out = [];
        let current = [];
        let reach = 0;
        for (let i = 0; i < slots.length; i++) {
            if (current.length > 0 && slots[i].from >= reach) {
                out.push(current);
                current = [];
                reach = 0;
            }
            current.push(slots[i]);
            reach = current.length === 1 ? slots[i].until : Math.max(reach, slots[i].until);
        }
        if (current.length > 0)
            out.push(current);
        return out;
    }

    /// The same grouping as ids, which is the shape worth asserting on.
    function clusters(events: var): var {
        return policy.slotClusters(events).map(function (group) {
            return group.map(function (slot) {
                return slot.id;
            });
        });
    }

    // --- the day layout -------------------------------------------------------

    /// True when nothing already assigned to `column` overlaps `slot`. Both
    /// sides use the inflated `until`, so the floor that decides collisions
    /// also decides expansion.
    function columnIsFree(group: var, column: int, slot: var): bool {
        for (let i = 0; i < group.length; i++) {
            const other = group[i];
            if (other === slot || other.column !== column)
                continue;
            if (other.from < slot.until && slot.from < other.until)
                return false;
        }
        return true;
    }

    /// Where every event on a day sits across the width of it:
    /// `[{id, column, columns, span, xFrac, wFrac}]`, cluster by cluster and
    /// in painting order within each. `columns` is the width of the *cluster*,
    /// not of the day, so two clusters on one day are sized independently.
    /// Events that are not events are dropped rather than laid out.
    function layout(events: var): var {
        const groups = policy.slotClusters(events);
        const out = [];
        for (let g = 0; g < groups.length; g++) {
            const group = groups[g];

            // Greedy leftmost free column.
            const colEnd = [];
            for (let i = 0; i < group.length; i++) {
                let column = 0;
                while (column < colEnd.length && colEnd[column] > group[i].from)
                    column++;
                group[i].column = column;
                colEnd[column] = group[i].until;
            }
            const columns = colEnd.length;

            // Then widen rightwards, stopping at the first column that is not
            // free for the whole of this event.
            for (let j = 0; j < group.length; j++) {
                const slot = group[j];
                let span = 1;
                while (slot.column + span < columns
                       && policy.columnIsFree(group, slot.column + span, slot))
                    span++;
                out.push({
                    "id": slot.id,
                    "column": slot.column,
                    "columns": columns,
                    "span": span,
                    "xFrac": slot.column / columns,
                    "wFrac": span / columns
                });
            }
        }
        return out;
    }

    // --- the all-day row ------------------------------------------------------

    /// Where one event sits on a week's all-day row, or `null` if it misses
    /// the week entirely. `startCol`/`span` are already clipped to the seven
    /// columns; `continuesLeft`/`continuesRight` say the clip happened, which
    /// is the surface's cue to draw an arrow instead of a rounded end.
    function weekSpan(event: var, weekStartIso: string): var {
        if (!event || !event.id || !policy.time.isDay(weekStartIso))
            return null;
        const first = policy.time.dayOf(event.start);
        if (!first)
            return null;
        const last = policy.eventPolicy.lastDay(event);
        if (!last || policy.time.compare(last, first) < 0)
            return null;

        const rawStart = policy.time.diffDays(weekStartIso, first);
        const rawEnd = policy.time.diffDays(weekStartIso, last);
        if (rawEnd < 0 || rawStart > 6)
            return null;

        const startCol = Math.max(0, rawStart);
        const endCol = Math.min(6, rawEnd);
        return {
            "id": event.id,
            "startCol": startCol,
            "span": endCol - startCol + 1,
            "continuesLeft": rawStart < 0,
            "continuesRight": rawEnd > 6
        };
    }

    /// True when nothing already in `lane` shares a column with `span`.
    /// Columns are whole days and `span` counts them inclusively, so an event
    /// ending on Tuesday and one starting on Wednesday share a lane.
    function laneIsFree(lane: var, span: var): bool {
        for (let i = 0; i < lane.length; i++) {
            const other = lane[i];
            if (other.startCol < span.startCol + span.span
                && span.startCol < other.startCol + other.span)
                return false;
        }
        return true;
    }

    /// The all-day row for one week:
    /// `[{id, lane, startCol, span, continuesLeft, continuesRight}]`, packed
    /// into the fewest lanes greedily — leftmost-starting first, and where two
    /// start together the longer bar takes the higher lane so the row reads
    /// top-heavy rather than ragged.
    ///
    /// It lays out whatever it is handed; deciding which events belong in the
    /// all-day row rather than the grid is the caller's job.
    function allDayLanes(events: var, weekStartIso: string): var {
        const spans = [];
        const list = events || [];
        for (let i = 0; i < list.length; i++) {
            const span = policy.weekSpan(list[i], weekStartIso);
            if (span)
                spans.push(span);
        }
        spans.sort(function (a, b) {
            if (a.startCol !== b.startCol)
                return a.startCol - b.startCol;
            if (a.span !== b.span)
                return b.span - a.span;
            return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
        });

        const lanes = [];
        const out = [];
        for (let s = 0; s < spans.length; s++) {
            const span = spans[s];
            let lane = 0;
            while (lane < lanes.length && !policy.laneIsFree(lanes[lane], span))
                lane++;
            if (lane === lanes.length)
                lanes.push([]);
            lanes[lane].push(span);
            out.push({
                "id": span.id,
                "lane": lane,
                "startCol": span.startCol,
                "span": span.span,
                "continuesLeft": span.continuesLeft,
                "continuesRight": span.continuesRight
            });
        }
        return out;
    }

    // --- which row an event belongs on ----------------------------------------

    /// True for an event that belongs in the all-day band rather than in the
    /// time grid.
    ///
    /// Two kinds qualify and the second is the one that is easy to miss. An
    /// event flagged `allDay` obviously has no place on a 24-hour column. But
    /// so does a *timed* event that runs across days — the fixture's
    /// "Nordic QML Days", 09:00 Thursday to 17:00 Saturday, is drawn in the
    /// grid as three disconnected blocks that say nothing about it being one
    /// conference. A bar across three columns says exactly that.
    ///
    /// The threshold is "touches more than one day", not "lasts more than 24
    /// hours": a 23:00–01:00 event touches two days and is still an evening,
    /// so `spansDays` — which counts calendar days and treats an exclusive
    /// midnight end as the day before — is the function asked, not a duration.
    function isBanded(event: var): bool {
        if (!event)
            return false;
        if (event.allDay === true)
            return true;
        return policy.eventPolicy.spansDays(event) > 1;
    }

    /// The all-day band's events, in the order they were given.
    function bandEvents(events: var): var {
        return (events || []).filter(function (event) {
            return policy.isBanded(event);
        });
    }

    /// The time grid's events — everything the band did not take. Stated as its
    /// own function rather than left to each caller's `!isBanded`, so the two
    /// rows can never both claim an event or both drop it.
    function gridEvents(events: var): var {
        return (events || []).filter(function (event) {
            return event && !policy.isBanded(event);
        });
    }

    // --- what fits inside one chip --------------------------------------------
    //
    // A chip is a box of a size the *grid* chose — its height is its duration
    // and its width is however many neighbours it is sharing the hour with —
    // and what may be printed inside it is arithmetic on those two numbers.
    // Getting it wrong is not a subtle failure: the three-way Tuesday overlap
    // rendered `D…`, `V…`, `P…` and no times at all, which is three chips that
    // have given up saying anything.
    //
    // The decision is one function, `chipContent(width, height, minutes)`, and
    // it answers in one object so a chip can never take the title rule from one
    // branch and the padding from another.

    /// Below this many pixels of chip *height* there is no second line.
    ///
    /// 32 and not 34: at `hourRow` 56 a half-hour chip is 28px, a 45-minute one
    /// is 42. Two lines of pt(12.5) and pt(11) at the tight metrics below
    /// measure 31, so 32 is the first height that fits them with a pixel over —
    /// and it is the height the critic named, which matters more than the
    /// arithmetic agreeing to the pixel: a 45-minute meeting showing no start
    /// time is the complaint.
    readonly property int twoLineMinHeight: 32

    /// At or under this many minutes a chip is *never* given two lines, however
    /// tall the grid happens to draw it. `chipMinH` floors a 15-minute event at
    /// 20px, and a taller `hourRow` would otherwise let a 15-minute event
    /// sprout a second line while the 30-minute one beside it did not.
    readonly property int compactMinutes: 30

    /// Whether a chip of this many minutes collapses to one line, with its time
    /// set inline after its title instead of under it.
    function isCompact(minutes: real): bool {
        return isFinite(minutes) && minutes <= policy.compactMinutes;
    }

    /// Under this many pixels a chip is *narrow*: the accent bar loses a pixel,
    /// the padding halves, and the type steps down one notch. This is the
    /// packed-overlap case — three chips in one column of a 1180px window — and
    /// the alternative measured worse than ugly: 11px of padding out of 40px of
    /// chip left 22px for a title, which is one glyph and an ellipsis.
    ///
    /// 100 and not 125: a chip that has a whole week column to itself is not
    /// narrow, and stepping its type down would shrink the common case to fix
    /// the rare one.
    readonly property int narrowWidth: 100

    /// The floor for printing a time at all, and the floor for printing it as a
    /// *range*. Between them the time is the start alone (`10:30a`), which is
    /// the half of it a neighbouring chip's edges cannot already tell you.
    ///
    /// 36 is the measured packed case and not a round number: a 1180px window
    /// with a 248px sidebar and a 56px gutter gives a week column 125px, a
    /// three-way overlap takes a third of that, and 2px of gap leaves ~40 —
    /// so any floor above 40 means the case this whole section exists for
    /// never prints a time. `"10:30a"` at pt(10) is 30px and the narrow
    /// padding is 8, which is where 36 stops being arbitrary. 104 is
    /// `"10:30 – 11:45 AM"` at pt(11) — 90px — plus the roomy padding, measured
    /// against the same capture: a floor of 128 silently demoted every chip in
    /// a 125px week column to a bare start time.
    readonly property int timeMinWidth: 36
    readonly property int timeRangeMinWidth: 104

    /// The floor for setting a one-line chip's time *inline* after its title.
    /// Lower than `timeRangeMinWidth` because the inline time is only ever the
    /// *start* — `9a`, not a range — so it costs the title about 20px rather
    /// than 90. Under this, the title is squeezed to nothing to make room for a
    /// time it would have been better off without.
    readonly property int inlineTimeMinWidth: 96

    /// Everything a chip needs to know about its own contents:
    ///
    ///   - `mode` — `"stacked"` (title over time), `"inline"` (title then time
    ///     on one line) or `"titleOnly"`.
    ///   - `showTime` / `timeForm` — whether a time is printed, and whether it
    ///     is the `"range"` or just the `"start"`.
    ///   - `titleSize` / `timeSize` — point sizes, to hand to `Theme.pt`.
    ///   - `titleLines` — how many lines the title may wrap over. **This is
    ///     what makes a packed column readable.** A 38px chip has room for
    ///     four glyphs on a line, so a one-line rule prints `Des…` whatever
    ///     else is done to it; the same chip is 84px tall, and `Design` /
    ///     `review` over `10a` uses the space the event's own duration already
    ///     bought. Notion wraps narrow chips for exactly this reason.
    ///   - `bar`, `padLeft`, `padRight`, `padTop` — the chip's own metrics, so
    ///     the narrow case tightens every one of them together or none.
    ///
    /// `width` and `height` are the drawn box; `minutes` is the event's real
    /// duration, which is not recoverable from the height once `chipMinH` has
    /// floored it.
    function chipContent(width: real, height: real, minutes: real): var {
        const w = isFinite(width) ? width : 0;
        const h = isFinite(height) ? height : 0;
        const narrow = w < policy.narrowWidth;

        const bar = narrow ? 3 : 4;
        const gap = narrow ? 3 : policy.roomyGap;
        const padRight = narrow ? 2 : gap;
        const padTop = narrow ? 1 : 3;
        const textW = Math.max(0, w - bar - gap - padRight);

        const showTime = w >= policy.timeMinWidth;
        const timeForm = w >= policy.timeRangeMinWidth ? "range" : "start";

        let mode = "titleOnly";
        if (!policy.isCompact(minutes) && h >= policy.twoLineMinHeight && showTime)
            mode = "stacked";
        else if (showTime && w >= policy.inlineTimeMinWidth)
            mode = "inline";

        const titleSize = narrow ? 11 : 12.5;
        const timeSize = narrow ? 10 : 11;

        // A line box is its point size and a bit; the exact metric belongs to
        // the font and the surface measures it, but the *count* is a decision
        // and has to be the same on every screen, so it is taken from the sizes
        // this function chose rather than from anything rendered.
        const titleLine = Math.round(titleSize * policy.lineFactor);
        const timeLine = mode === "stacked" ? Math.round(timeSize * policy.lineFactor) : 0;
        const room = h - padTop - timeLine - 2;
        const titleLines = (mode === "stacked" && w >= policy.wrapMinWidth)
            ? Math.max(1, Math.min(policy.maxTitleLines, Math.floor(room / titleLine)))
            : 1;

        return {
            "mode": mode,
            "showTime": mode !== "titleOnly",
            "timeForm": mode === "inline" ? "start" : timeForm,
            "narrow": narrow,
            "titleSize": titleSize,
            "timeSize": timeSize,
            "titleLines": titleLines,
            "bar": bar,
            "padLeft": bar + gap,
            "padRight": padRight,
            "padTop": padTop,
            "textWidth": textW
        };
    }

    /// Line box over point size, and the ceiling on wrapping. Three lines is
    /// where a chip stops being a label and starts being a paragraph — past
    /// that the title is long enough that the editor is the place to read it.
    readonly property real lineFactor: 1.35
    readonly property int maxTitleLines: 3

    /// Under this width a chip does **not** wrap, whatever height it has.
    ///
    /// Measured, and the measurement reversed a decision. Wrapping a 38px chip
    /// looked like the answer — Notion wraps narrow chips — until it was
    /// captured: a line that cannot hold one whole word breaks inside words,
    /// and `Design review` came out `Desig / n / rev…`, which is worse to read
    /// than the single elided line it replaced. 72 is about two short words at
    /// pt(11) less the narrow padding, i.e. the narrowest chip on which a wrap
    /// lands between words rather than through one.
    readonly property int wrapMinWidth: 72

    /// The padding a chip that is not narrow gets on each side of its text —
    /// `Theme.space2`, written out because this file is loaded by
    /// `qmltestrunner`, which cannot import `qs.Core`.
    readonly property int roomyGap: 8

    /// A title cut to fit, **at a word boundary wherever one exists**.
    ///
    /// `Text.ElideRight` cuts mid-glyph: `"Design review"` in a packed column
    /// becomes `"D…"`, which names nothing. Cutting at the last whole word that
    /// fits gives `"Design…"` in the same pixels — the same information the eye
    /// wanted, and the reason a packed Tuesday is still readable.
    ///
    /// `maxChars` is how many glyphs fit, which only the surface can measure;
    /// this decides what to do with the number. A first word already too long
    /// for the box falls back to a hard cut, because a chip that printed
    /// nothing would be worse than one that printed a fragment.
    function clipTitle(title: var, maxChars: int): string {
        const t = (title === undefined || title === null) ? "" : String(title).trim();
        const n = Math.floor(maxChars);
        if (!isFinite(n) || n < 1)
            return "";
        if (t.length <= n)
            return t;

        const cut = t.slice(0, n);
        const space = cut.lastIndexOf(" ");
        if (space > 0)
            return cut.slice(0, space) + "…";
        return (n > 1 ? t.slice(0, n - 1) : "") + "…";
    }
}
