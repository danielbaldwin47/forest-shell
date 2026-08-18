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

    // --- how tall a chip may be -----------------------------------------------

    /// At or under this many minutes a chip has no room for two lines.
    ///
    /// 30 and not 20: at `hourRow` 56 a half-hour chip is 28px tall, and two
    /// lines of pt(12.5) and pt(11) with `space1` of top padding need 34. The
    /// number is here rather than in the chip because it is the same question
    /// the layout is already answering — how much room does this event get —
    /// and because a threshold with no test is a threshold that drifts.
    readonly property int compactMinutes: 30

    /// Whether a chip of this many minutes collapses to one line, with its time
    /// set inline after its title instead of under it.
    function isCompact(minutes: real): bool {
        return isFinite(minutes) && minutes <= policy.compactMinutes;
    }

    /// Under this many pixels of chip width, the time line is dropped and the
    /// title gets the chip to itself.
    ///
    /// The number comes off the picture rather than out of the air. A
    /// three-way overlap on a 1180px window gives each chip 41px, of which 19
    /// is padding and the accent bar — and `"10 – 11:30a"` in 22px is `"1…"`,
    /// which is not a time, is not a title, and is the only thing on the
    /// second line. 92px is where `"10 – 11:30a"` stops eliding at pt(11).
    readonly property int timeLineMinWidth: 92

    /// Whether a chip this wide has room to say when it is as well as what it
    /// is. A chip that cannot is not wrong — it is a chip in a busy hour, and
    /// its neighbours' edges already say where it starts and stops.
    function showsTimeLine(width: real): bool {
        return isFinite(width) && width >= policy.timeLineMinWidth;
    }
}
