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

    /// The narrowest a lane is ever divided to, **in pixels of column**.
    ///
    /// This is the floor equal division does not have on its own, and its
    /// absence is what a packed column dies of. Five concurrent events in the
    /// 124px column a 1180px window leaves is a 22px chip; 22px prints one
    /// glyph at any type size that is not a joke, so a fifth equal lane does
    /// not divide the information, it destroys it — and it destroys the four
    /// beside it at the same time, which is the part that matters. The split
    /// therefore stops at `minLaneWidth`, and everything past it **cascades**:
    /// indented into the last lane, widened to the column's right edge, drawn
    /// over its predecessors. Notion's week view makes the same move, and for
    /// the same reason.
    ///
    /// **64, and it used to be 34.** The 34 was arrived at by asking how narrow
    /// a chip could get and still print one word; the answer was "it can", and
    /// the picture that came back was three 39px slivers reading
    /// `Pairing: / grid / packing` down three lines with the time jammed against
    /// the fill. A lane that prints one word per line is not a chip, it is a
    /// column of syllables — the measurement was right and the question was
    /// wrong.
    ///
    /// The question the cascade actually answers is *when is a title readable*,
    /// and a cascaded chip's title is readable for a reason nothing here had
    /// used: **a cascade is staggered in time as well as in x.** Chips are
    /// painted in start order, so the chip that covers one starts later, and its
    /// top edge sits below the covered chip's title line. Every title in a
    /// staggered cascade therefore prints at the chip's *full* width and none of
    /// them is occluded — which is exactly what Notion's week view does with an
    /// overlapping cluster, and why its packed columns stay legible where an
    /// equal division of the same pixels does not.
    ///
    /// So the floor is set at the width a chip needs to be a chip — 64px leaves
    /// a ~50px text box at the narrow tier, which is a short word and a half —
    /// and anything past it cascades rather than divides. `cascadeIsLegible`
    /// guards the other side: where the starts are *not* staggered the cascade
    /// would hide a title outright, and there the division is taken back.
    readonly property int minLaneWidth: 64

    /// How far apart two starts must be for the later chip to clear the earlier
    /// one's title line. A title line is ~17px at the roomy tier and `hourRow`
    /// is 56, so 20 minutes is 18.7px — one line box with a pixel over. Under
    /// it the cascade stops being staggered and starts being occlusion.
    readonly property int cascadeClearMinutes: 20

    /// The width under which an equal division prints nothing at all, so a
    /// cluster that cannot be cascaded legibly is still cascaded rather than
    /// divided into slivers. 40px is the three-way split of a 123px week column
    /// — the picture that started this section.
    readonly property int minSplitWidth: 40

    /// Whether a cluster's starts are staggered enough for a cascade to keep
    /// every title visible. Sorted starts, adjacent gaps, all of them wide
    /// enough — one pair too close is enough to lose a title, so one pair too
    /// close is enough to refuse.
    function cascadeIsLegible(group: var, clear): bool {
        const need = (clear === undefined || clear === null)
            ? policy.cascadeClearMinutes : clear;
        const starts = (group || []).map(function (slot) {
            return slot.from;
        }).sort(function (a, b) {
            return a - b;
        });
        for (let i = 1; i < starts.length; i++)
            if (starts[i] - starts[i - 1] < need)
                return false;
        return true;
    }

    /// How many lanes a column this wide may be divided into. `0` means "no
    /// opinion": the caller passed no width, so the division is uncapped and
    /// `layout` behaves exactly as it did before there was a cap.
    function laneCap(width: real): int {
        if (!isFinite(width) || width <= 0)
            return 0;
        return Math.max(1, Math.floor(width / policy.minLaneWidth));
    }

    /// The widest one cascade step may be, as a fraction of the column.
    ///
    /// 0.12, down from 0.18, and the reason is the stagger. The indent used to
    /// be asked to reveal the covered chip's *title*, which takes real pixels;
    /// once `cascadeIsLegible` guarantees the covering chip starts a title line
    /// lower, the title below is already whole and the indent only has to say
    /// "there is a card under this one". 0.12 of a 121px track is 14px — the
    /// accent bar and a sliver of its fill, which reads as a stack — and the
    /// 7px it hands back goes to the last chip in the cascade, the one with the
    /// least room and the most to lose.
    /// 0.20 now, and the number that moved it is what the picture *reads as*
    /// rather than what it contains. At 0.12 a 121px column steps 15px, which is
    /// the accent bar and a sliver — three chips that look like one chip with two
    /// scratches down it, and the note off the capture was "cascaded, not side by
    /// side". At 0.20 the step is 24px: bar, fill and a clear left margin, so the
    /// three read as three staggered lanes. The width it costs the last chip is
    /// affordable because `banner` below bought the covered ones their times
    /// back — the pixels the cascade was hoarding were being spent on a title
    /// nobody could date.
    readonly property real cascadeFrac: 0.20

    /// And the narrowest. A cascade whose steps are two pixels apart is not a
    /// cascade, it is five chips drawn on top of each other — the picture the
    /// clamp produced the first time this was written, and it reads as a
    /// rendering fault rather than as five overlapping meetings. Where the
    /// indent cannot reach this, the cluster gives up a *lane* instead: fewer,
    /// wider lanes leave room for the cascade to be visible, which is the whole
    /// point of cascading rather than dividing.
    readonly property real minCascadeFrac: 0.06

    /// How many lanes a cluster of `wanted` columns actually takes in a column
    /// `cap` lanes wide, given that the overflow has to have somewhere visible
    /// to indent into. Never more than `cap`, never fewer than one, and never
    /// so many that the cascade collapses onto itself.
    function cascadeLanes(wanted: int, cap: int, minFrac: real): int {
        let columns = (cap > 0) ? Math.min(wanted, cap) : wanted;
        while (columns > 1 && wanted > columns) {
            const baseX = (columns - 1) / columns;
            if ((1 - minFrac - baseX) / (wanted - columns) >= policy.minCascadeFrac)
                break;
            columns--;
        }
        return Math.max(1, columns);
    }

    /// Where every event on a day sits across the width of it:
    /// `[{id, column, columns, span, depth, xFrac, wFrac}]`, cluster by cluster
    /// and in painting order within each. `columns` is the width of the
    /// *cluster*, not of the day, so two clusters on one day are sized
    /// independently. Events that are not events are dropped rather than laid
    /// out.
    ///
    /// `width` is the column's pixel width and is optional. Given one, the
    /// division is capped by `minLaneWidth` and the overflow cascades;
    /// `depth` is how many cascade steps in a chip is, and it is also the
    /// order to paint them in — a chip must be drawn over the one it indents
    /// from or the indent says nothing.
    function layout(events: var, width: real): var {
        const groups = policy.slotClusters(events);
        const cap = policy.laneCap(width);
        const minFrac = (cap > 0) ? Math.min(1, policy.minLaneWidth / width) : 0;
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
            const wanted = colEnd.length;
            // The cascade is only reached for; where the starts are not
            // staggered it would hide a title outright, and an equal division
            // is taken back — but only while a lane is still wide enough to
            // print something. Under `minSplitWidth` neither arrangement works
            // and the cascade is the least-bad of the two.
            let columns = policy.cascadeLanes(wanted, cap, minFrac);
            if (columns < wanted
                && !policy.cascadeIsLegible(group)
                && (cap <= 0 || width / wanted >= policy.minSplitWidth))
                columns = wanted;
            const overflow = wanted - columns;
            const step = overflow > 0
                ? Math.min(policy.cascadeFrac,
                           Math.max(0, (1 - minFrac - (columns - 1) / columns) / overflow))
                : 0;

            // Then widen rightwards, stopping at the first column that is not
            // free for the whole of this event.
            for (let j = 0; j < group.length; j++) {
                const slot = group[j];
                let span = 1;
                while (slot.column + span < wanted
                       && policy.columnIsFree(group, slot.column + span, slot))
                    span++;

                const lane = Math.min(slot.column, columns - 1);
                const depth = slot.column - lane;
                let xFrac = lane / columns;
                let wFrac = Math.min(span, columns - lane) / columns;
                if (depth > 0) {
                    // Cascaded: indent from the last lane and run to the right
                    // edge, never past `minLaneWidth` of remaining room.
                    xFrac = Math.min(xFrac + depth * step, Math.max(0, 1 - minFrac));
                    wFrac = 1 - xFrac;
                }
                // How long this chip has before something is drawn over it.
                //
                // The cascade's legibility comes from the stagger, and the
                // stagger is a budget rather than a guarantee: a chip covered
                // 30 minutes in has 30 minutes of clear box, which is one line
                // and not two. Reporting it here is what lets `chipContent`
                // spend the box it actually has — the alternative was measured,
                // and it was a title that cleared the chip above and a time
                // sliced in half by its top edge.
                //
                // `Infinity` for a chip nothing covers, so a caller that
                // forwards it straight into a `Math.min` gets the chip's own
                // height back.
                let clear = Infinity;
                for (let k = 0; k < group.length; k++) {
                    const over = group[k];
                    if (over === slot || over.column <= slot.column)
                        continue;
                    if (Math.min(over.column, columns - 1) !== lane)
                        continue;
                    clear = Math.min(clear, Math.max(0, over.from - slot.from));
                }

                out.push({
                    "id": slot.id,
                    "column": slot.column,
                    "columns": columns,
                    "span": span,
                    "depth": depth,
                    "clearMinutes": clear,
                    "xFrac": xFrac,
                    "wFrac": wFrac
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

    /// The floor a band bar is never cut below, whatever its title measures.
    /// Under about this much a bar stops reading as a span at all and reads as
    /// a swatch someone dropped on the band.
    readonly property int bandBarMinWidth: 72

    /// How wide an all-day bar is actually drawn, given the track its columns
    /// give it and what its own contents measure.
    ///
    /// **A bar that ends inside the run takes its natural width; one that runs
    /// off an edge fills the track.** In a week column the two are the same
    /// number — a 123px column and a title that elides — so this rule is
    /// invisible there and decisive on a day view, where one all-day event was
    /// drawn as an 870px slab of tint with four words at the left end of it.
    /// The band's job is to say *which days*, and on a single-column day the
    /// answer is "this one" however wide the bar is; stretching therefore buys
    /// nothing and costs the row its shape.
    ///
    /// A continuing span is the exception and must stay flush: the cut edge
    /// against the frame is what says it carries on, and a natural-width bar
    /// floating clear of the edge would say the opposite.
    ///
    /// **And so is a span that covers more than one column, which is the second
    /// exception and was missing.** Read back off the week capture: "Nordic QML
    /// Days" runs Thursday 09:00 to Saturday 17:00, and the natural-width rule
    /// drew it as a 130px bar sitting in Thursday — a three-day conference
    /// rendered as a Thursday appointment, with Friday and Saturday reading
    /// empty. The rule above says the band's job is to say *which days*; on a
    /// multi-column span the width **is** that answer, so the argument that
    /// retires a stretched bar on a single day is exactly the argument that
    /// requires one across three. `columns` defaults to 1, so the day view's
    /// 870px slab stays retired.
    ///
    /// `contentWidth` is a measurement — the surface takes it off `TextMetrics`
    /// — and everything done with it is here.
    ///
    /// `columns` is **how many day columns the span covers, and it is untyped on
    /// purpose**, the same way `cascadeIsLegible`'s `clear` and `showsGrip`'s
    /// `clearHeight` are: an `int` annotation would coerce an omitted argument to
    /// 0, and this has to be able to tell "not given" from a real count so an
    /// older caller passing three arguments still means one column. Anything
    /// absent, null or non-finite is 1; anything else is rounded to a whole
    /// number of columns.
    function bandBarWidth(track: real, contentWidth: real, continues: bool,
                          columns): real {
        const t = isFinite(track) ? Math.max(0, track) : 0;
        if (continues === true)
            return t;
        const cols = (columns === undefined || columns === null
                      || !isFinite(columns)) ? 1 : Math.round(columns);
        if (cols > 1)
            return t;
        const natural = isFinite(contentWidth) ? Math.max(0, contentWidth) : 0;
        return Math.min(t, Math.max(policy.bandBarMinWidth, natural));
    }

    /// Where a band bar's trailing edge sits, given the right edge of the column
    /// its span ends in (`spanRight`), the right edge of the **last** column in
    /// the view (`viewRight`), and whether the span runs on past this week.
    ///
    /// **The trailing gap is the continuation cue.** Two bars ended on the same
    /// pixel and only one carried an arrow, which read as a forgotten arrow
    /// rather than as one bar stopping and another running on. So a span that
    /// ends inside the week stops `gap` short of its column edge with both right
    /// corners rounded, and one that continues runs hard into that edge and is
    /// cut by it.
    ///
    /// **Except against the frame**, which is the clamp. For a span reaching the
    /// last column that edge is the window's own: a bar and its arrow flush
    /// against the frame photograph as a chip clipped by the viewport rather than
    /// as one carrying on into next week, and there is nothing out there to
    /// disambiguate it — no eighth column can follow. So the last column keeps
    /// the ordinary inset (`viewRight` is passed already less it) and the arrow
    /// gets air to sit in.
    ///
    /// Both edges are pixel positions from the surface, which is why they are
    /// arguments and not something derived here; the rule about what to do with
    /// them is the only thing this owns.
    function bandBarTrailX(spanRight: real, viewRight: real, continues: bool,
                           gap: real): real {
        const right = isFinite(spanRight) ? spanRight : 0;
        const inset = (continues === true || !isFinite(gap)) ? 0 : gap;
        if (!isFinite(viewRight))
            return right - inset;
        return Math.min(right - inset, viewRight);
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

    /// The **banner** tier: two lines in a box too short for two lines at the
    /// ordinary type.
    ///
    /// This is the cascade's own case and it is the one the whole surface was
    /// judged on. A chip covered 30 minutes in has 28px of clear band, which is
    /// under `twoLineMinHeight`, so the rule above collapsed it to one line — and
    /// the one line it kept was the title, because `inlineTimeFits` will not buy
    /// a time with an ellipsis. Two chips of a three-way overlap therefore stated
    /// no time at all, and "a 28px title strip that never says when it is" is
    /// exactly what a packed column must not be.
    ///
    /// The band cannot grow — it is the stagger, in minutes — so the type shrinks
    /// instead, once, to the only tier where two whole lines fit 28px:
    /// `bannerTitleSize` over `bannerTimeSize` is 14 + 12 = 26px of line box with
    /// the top pad at zero. Both lines print whole; neither elides. Under 26 there
    /// is no honest second line and the chip goes back to one.
    readonly property int bannerMinHeight: 26
    readonly property real bannerTitleSize: 10.5
    readonly property real bannerTimeSize: 9

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
    /// two-way overlap — half a week column — and the alternative measured worse
    /// than ugly: 11px of padding out of 40px of chip left 22px for a title,
    /// which is one glyph and an ellipsis.
    ///
    /// 100 and not 125: a chip that has a whole week column to itself is not
    /// narrow, and stepping its type down would shrink the common case to fix
    /// the rare one.
    readonly property int narrowWidth: 100

    /// Under *this* many pixels a chip is **tight**, which is a second step and
    /// not more of the first. This is the three-way overlap, and it is the case
    /// the whole packed column exists for: a 1180px window with a 248px sidebar
    /// and a 56px gutter gives a week column 123px, three equal columns of 41
    /// less a 2px gap is a 39px chip, and 39px is not a small version of 59px —
    /// it is a different problem.
    ///
    /// The numbers behind the tight tier are measured against IBM Plex Sans
    /// Medium, which is what actually decides whether a packed chip says
    /// anything. In a ~34px text box (39 less a 2px bar, 2 of left pad and 1 of
    /// right), `packing` — the longest word on the fixture week — is 43.0px at
    /// 12.5, 37.8 at 11, 34.0 at 9.5, 32.2 at 9 and **30.4 at 8.5**.
    ///
    /// 8.5 and not 9, and the extra step is the *measured* one: 9.5 and 9 were
    /// both captured and both came out `packin / g`, because a laid-out line is
    /// wider than the sum of its advances — Qt rounds per glyph at these sizes
    /// and a seven-glyph word collects the rounding seven times. So the size is
    /// chosen with a margin over the arithmetic rather than against it, which
    /// is what the two captures cost to learn. At 11 the same chip can only ever
    /// print `Des…`, so the step down is buying the whole title, not polish.
    ///
    /// 56 is where the two-way case stops: half a 123px column less the gap is
    /// 59, which must stay in the roomier tier.
    readonly property int tightWidth: 56

    /// The type the tight tier sets, title and time alike.
    ///
    /// It was 8.5, chosen as the largest size at which `packing` — the longest
    /// word on the fixture week — fit a 34px text box without breaking inside
    /// itself. It read, at a magnifier. It did not read on the picture, and
    /// "functionally unreadable" is the note that came back, so the box grew
    /// instead of the type shrinking further: the tight tier's gap dropped from
    /// 2px to 1, which is a pixel nobody can see and 36px of text box rather
    /// than 34. `packing` is 34.0 at 9.5 against a 36px box, which is the same
    /// one-pixel margin 8.5 had against 34 — the arithmetic is unchanged and
    /// the glyphs are 12% taller.
    ///
    /// One size for both lines, and that is the second change. Title and time
    /// at 8.5/9 put two different type sizes inside a 40px box, which reads as
    /// a rendering accident rather than a hierarchy; weight carries the
    /// hierarchy here, as it does everywhere else on this surface.
    readonly property real tightTitleSize: 9.5

    /// The floor for printing a time at all, and the floor for printing it as a
    /// *range*. Between them the time is the start alone — and it is the range's
    /// own first token, `10:30`, never a second grammar like `10:30a`. One
    /// surface prints times one way; a chip that shrank into a different clock
    /// notation would make the eye re-learn the format per column width.
    ///
    /// 36 is the measured packed case and not a round number: a 1180px window
    /// with a 248px sidebar and a 56px gutter gives a week column 125px, a
    /// three-way overlap takes a third of that, and 2px of gap leaves ~40 —
    /// so any floor above 40 means the case this whole section exists for
    /// never prints a time. `"10:30"` at 9 is 24px and the tight padding is 6,
    /// which is where 36 stops being arbitrary. 104 is
    /// `"10:30 – 11:45 AM"` at pt(11) — 90px — plus the roomy padding, measured
    /// against the same capture: a floor of 128 silently demoted every chip in
    /// a 125px week column to a bare start time.
    /// 112 and no longer 104: the symmetric inset above costs a narrow chip
    /// three pixels of text box, and 104 was measured against the old one. A
    /// 106px cascade step printing `10:30 – 12:00 PM` into an 86px box elides
    /// the meridiem off the end of a range, which is the one form that must
    /// never lose its tail; 112 demotes it to its own first token instead.
    readonly property int timeMinWidth: 36
    readonly property int timeRangeMinWidth: 112

    /// The floor, **in text-box pixels rather than chip pixels**, for hanging a
    /// meridiem off a start-only time. `"10:30 AM"` is 48px at 11 and 44 at 10;
    /// `"10:30"` is 30 and 27. A two-way split leaves a 51px text box and takes
    /// the meridiem; the three-way split leaves 33 and does not, and printing it
    /// anyway would elide to `"10:30 A…"`, which is worse than the unambiguous
    /// half of the same token — the chip's own row in the grid already says
    /// which half of the day it is in.
    /// 30 and no longer 50, because the tier it silenced was the one that could
    /// least afford a second grammar. A grid printing `1:00 – 2:00 PM` on one
    /// chip, `9:00 AM` on the next and a bare `10:00` on the packed ones is
    /// three clock notations a centimetre apart, and the eye re-learns which is
    /// which per column width. Two forms are the floor — the whole range, or
    /// **its own first token**, `10:00 AM` — and the packed chip is held to the
    /// second rather than allowed a third. Where the last pixel is missing the
    /// time shrinks to fit (`Text.HorizontalFit` in the chip), which costs a
    /// point of size and keeps the notation.
    readonly property int meridiemMinTextWidth: 30

    /// The floor for setting a one-line chip's time *inline* after its title.
    /// Lower than `timeRangeMinWidth` because the inline time is only ever the
    /// *start* — `9:00 AM`, not a range — so it costs the title about 45px
    /// rather than 90. Under this, the title is squeezed to make room for a
    /// time it would have been better off without.
    readonly property int inlineTimeMinWidth: 96

    /// Where a one-line chip stops printing its start alone and prints **the
    /// whole range** after the title, on the same line.
    ///
    /// This is the day view earning its width. `inlineTimeMinWidth` is the
    /// floor for any inline time at all and buys `9:00 AM`, which is all a
    /// 123px week column can carry; a single column is seven times that, and a
    /// half-hour meeting there printed `3:00 PM` beside 700px of empty fill —
    /// the one chip on the surface with room to spare saying the least. 240 is
    /// `"10:00 – 11:30 AM"` at pt(11) — 90px measured — plus the roomy padding
    /// and a title worth eliding, so the range never crowds the thing it
    /// follows.
    readonly property int inlineRangeMinWidth: 240

    /// The guest line: **the third thing a chip says, and only where the box
    /// has room for it without taking anything from the first two.**
    ///
    /// Height first. 48 is the brief's number and it is also the arithmetic: a
    /// roomy chip's title line is 17px, its time line 15, its top pad 3 — 35 —
    /// so 48 is the first height with a whole third line spare. A 45-minute
    /// meeting (42px) therefore keeps title over time and gains nothing it
    /// cannot afford.
    ///
    /// Width second, and it is the harder gate: initials in a row of avatars
    /// plus a `+N` is about 70px, and a chip that spent its width on three
    /// packed lanes has none of it. 190 keeps guests out of every week column
    /// (123px, and 59 or 39 once shared) and lets them into a day column, which
    /// is exactly the split the brief asks for — the day view shows more
    /// because it has more, not because it is a different chip.
    readonly property int guestLineMinHeight: 48
    readonly property int guestsMinWidth: 190

    /// --- the column's own margins ---------------------------------------------

    /// Where a column stops being a slot in a week and starts being a page.
    ///
    /// A 123px week column cannot spend eight pixels a side on air: that is 13%
    /// of the track, and the chips are the thing the reader came for. A single
    /// 1300px day column spending the same eight is spending 1%, and the picture
    /// it buys is the one the capture asked for — chips sitting *in* a track
    /// rather than bleeding into the window frame at one end and the day rule at
    /// the other. 320 is roughly two week columns: past it the column is wide
    /// enough that no chip loses a word to the margin.
    readonly property int wideColumnWidth: 320
    readonly property int wideColumnInset: 8

    /// The leading — and, symmetrically, the trailing — margin inside a column.
    ///
    /// `base` is the narrow answer (`CalendarTokens.chipInset`), passed in so
    /// this file still knows no pixels of its own. **Symmetric on purpose.** The
    /// day view's own header sat at 10px while its chips sat at 2, so the date
    /// and the events it names were on two different left edges, and the last
    /// chip in a packed row ran into the frame with nothing under the header's
    /// margin at all. One inset, used by both, and the track is the difference.
    function columnInset(columnWidth: real, base): real {
        const b = (typeof base === "number" && base >= 0) ? base : 2;
        if (!isFinite(columnWidth))
            return b;
        return columnWidth >= policy.wideColumnWidth
            ? Math.max(b, policy.wideColumnInset) : b;
    }

    /// The width the chips divide between them, given a column and its inset.
    /// The `gap` comes back because every chip pays it off its own right edge —
    /// so adding it here once is what makes the *last* chip's right margin come
    /// out equal to the first chip's left one instead of `inset - gap`.
    function columnTrack(columnWidth: real, inset: real, gap: real): real {
        const w = isFinite(columnWidth) ? columnWidth : 0;
        const i = isFinite(inset) ? inset : 0;
        const g = isFinite(gap) ? gap : 0;
        return Math.max(0, w - 2 * i + g);
    }

    /// The air between two chips that sit side by side in one column — and the
    /// single number that decides whether packed lanes read as *packed* or as
    /// one chip drawn over another.
    ///
    /// **It has to scale with the lane, because the eye reads the ratio.** Two
    /// pixels between two 39px week lanes is 5% of a lane: a seam, and it reads
    /// as one. The same two pixels between two 433px day lanes is 0.5%, and the
    /// picture that came back off the day capture was exactly that — three
    /// concurrent meetings that had been divided into three equal lanes by this
    /// file and looked, on the page, like a cascade of one chip occluding the
    /// next, right rounded corner and all. Nothing was covering anything; there
    /// was simply no gutter to see. A fixed gap cannot fix both columns at once,
    /// so the gap is a fraction of the lane it separates.
    ///
    /// 3% keeps a 40px week lane at the 2px it already had (rounding down to
    /// the floor) and opens a 433px day lane to the cap. The cap is 12: past
    /// that the gutter starts competing with the chips for the reader's
    /// attention, and it is air, not information.
    ///
    /// `base` is the narrow answer (`CalendarTokens.chipGap`) and is also the
    /// floor — no arrangement is ever tighter than the one the week column
    /// already ships.
    readonly property int maxLaneGap: 12
    readonly property real laneGapFrac: 0.03

    function laneGap(laneWidth: real, base): int {
        const b = (typeof base === "number" && base >= 0) ? Math.floor(base) : 2;
        if (!isFinite(laneWidth) || laneWidth <= 0)
            return b;
        return Math.max(b, Math.min(policy.maxLaneGap,
                                    Math.round(laneWidth * policy.laneGapFrac)));
    }

    /// --- what a day comes to --------------------------------------------------

    /// The count and the total booked minutes of one day's timed events.
    ///
    /// The day view's header row is the one row in the surface that can be
    /// accused of saying nothing new — the toolbar above it already prints the
    /// whole date, so a header that prints the date again has spent 48px
    /// repeating itself. This is what it spends them on instead: the two facts
    /// about the day that neither the toolbar nor the grid states outright, and
    /// that a reader scanning for "how booked am I" is actually after.
    ///
    /// Overlaps are counted twice on purpose. Three concurrent meetings *are*
    /// four and a half hours of obligation, and a figure that quietly merged
    /// them would be a different, softer claim than the grid beneath it makes.
    ///
    /// `allDayCount` is the band above the grid, and it counts but contributes
    /// no minutes — an all-day event is not eight hours of anything, and a
    /// total that swallowed one would put a day's real load out by a working
    /// week. It is a count and not a list because the band has already been
    /// clipped to this day by the time anybody can count it. Leaving it out
    /// entirely was the first version, and it printed "4 events" under a header
    /// with five chips visible beneath it.
    function dayLoad(events: var, allDayCount: var): var {
        const list = Array.isArray(events) ? events : [];
        let minutes = 0;
        let count = 0;
        for (let i = 0; i < list.length; i++) {
            const slot = policy.slotOf(list[i]);
            if (!slot)
                continue;
            count++;
            minutes += Math.max(0, slot.to - slot.from);
        }
        const banded = (typeof allDayCount === "number" && allDayCount > 0)
            ? Math.floor(allDayCount) : 0;
        return { "count": count + banded, "minutes": minutes };
    }

    /// `dayLoad` as the string the header prints. The duration arrives already
    /// formatted (`CalendarFormat.duration`) so this file still speaks no
    /// language of its own; what it decides is the plural and the separator,
    /// and that an empty day says nothing at all rather than "0 events".
    function dayLoadLabel(load: var, durationText: var): string {
        if (!load || !(load.count > 0))
            return "";
        const head = load.count === 1 ? "1 event" : String(load.count) + " events";
        return (typeof durationText === "string" && durationText !== "")
            ? head + " · " + durationText : head;
    }

    /// --- the resize affordance ------------------------------------------------

    /// The shortest chip that carries a visible resize grip.
    ///
    /// Notion draws none at all, and the note off the first capture was that our
    /// grid "looks readable but not operable" — a wall of blocks with nothing
    /// saying they can be taken hold of. A grip that appears only on hover says
    /// nothing to a reader who has not already guessed; this one is drawn faint
    /// and always, and brightens under the pointer.
    ///
    /// 44 is where it stops costing more than it says: the pill is 3px tall and
    /// sits 3px off the bottom edge, so under about 44px it is inside the type
    /// it is supposed to sit clear of. A half-hour chip (28px) therefore keeps
    /// its one clean line and is resized by grabbing its edge, unlabelled.
    /// `clearHeight` is the same guard the content rule uses — a chip mostly
    /// covered by a cascaded neighbour has no bottom edge to offer.
    readonly property int gripMinHeight: 44

    function showsGrip(height: real, clearHeight): bool {
        const full = isFinite(height) ? height : 0;
        const clear = (clearHeight === undefined || clearHeight === null
                       || !isFinite(clearHeight)) ? full : Math.max(0, clearHeight);
        return Math.min(full, clear) >= policy.gripMinHeight;
    }

    /// Everything a chip needs to know about its own contents:
    ///
    ///   - `mode` — `"stacked"` (title over time), `"inline"` (title then time
    ///     on one line) or `"titleOnly"`.
    ///   - `showTime` / `timeForm` — whether a time is printed, and whether it
    ///     is the `"range"` or just the `"start"`.
    ///   - `titleSize` / `timeSize` — point sizes, to hand to `Theme.pt`.
    ///   - `titleLines` — how many lines the title may wrap over. **This is
    ///     what makes a packed column readable.** A 39px chip has room for
    ///     four glyphs of pt(12.5) on a line, so a one-line rule prints `Des…`
    ///     whatever else is done to it; the same chip is 84px tall, and
    ///     `Design` / `review` over `10:00` at the tight tier's type uses the
    ///     space the event's own duration already bought. Notion wraps narrow
    ///     chips for exactly this reason.
    ///   - `timeMeridiem` — whether the start-only time carries its `AM`/`PM`.
    ///   - `bar`, `padLeft`, `padRight`, `padTop` — the chip's own metrics, so
    ///     the narrow case tightens every one of them together or none.
    ///
    /// `width` and `height` are the drawn box; `minutes` is the event's real
    /// duration, which is not recoverable from the height once `chipMinH` has
    /// floored it.
    /// `clearHeight` is the fourth number and the newest: how much of the box
    /// is still *visible* once a cascaded neighbour is drawn over it. It
    /// defaults to the whole height, which is every chip that shares its column
    /// side by side or has the column to itself. Where it is smaller, it is
    /// what the content rule spends — a chip with 28px of clear box prints one
    /// line whatever its 84px of height would otherwise buy, because the other
    /// 56px are behind another card.
    function chipContent(width: real, height: real, minutes: real, clearHeight): var {
        const w = isFinite(width) ? width : 0;
        const full = isFinite(height) ? height : 0;
        const clear = (clearHeight === undefined || clearHeight === null
                       || !isFinite(clearHeight)) ? full : Math.max(0, clearHeight);
        const h = Math.min(full, clear);
        const tight = w < policy.tightWidth;
        const narrow = w < policy.narrowWidth;

        // A box short enough to have lost its second line, but not so short that
        // shrinking the type cannot buy it back. The tight tier is excluded: its
        // type is already at the floor and there is nothing left to give.
        const banner = !tight
            && h >= policy.bannerMinHeight && h < policy.twoLineMinHeight;

        const bar = tight ? 2 : (narrow ? 3 : 4);
        const gap = tight ? 3 : (narrow ? 6 : policy.roomyGap);
        // **The inset is symmetric, and it was not.** The right pad used to be
        // cut to 1px where the left kept 3, on the argument that the right side
        // buys nothing — which is true of a title that elides and false of the
        // time, which ends where it ends. The picture that came back was
        // `10:00 AM` finishing exactly on the fill boundary and abutting the
        // next chip's rail: two chips reading as one smear. Text sits the same
        // distance from both edges now, and the pixels come out of the lane
        // rather than out of one side of it.
        const padRight = gap;
        const textW = Math.max(0, w - bar - gap - padRight);

        const showTime = w >= policy.timeMinWidth;
        const timeForm = w >= policy.timeRangeMinWidth ? "range" : "start";

        let mode = "titleOnly";
        if (!policy.isCompact(minutes) && showTime
            && (h >= policy.twoLineMinHeight || banner))
            mode = "stacked";
        else if (showTime && w >= policy.inlineTimeMinWidth)
            mode = "inline";

        const bannerSet = banner && mode === "stacked";
        const titleSize = bannerSet ? policy.bannerTitleSize
            : (tight ? policy.tightTitleSize : (narrow ? 11 : 12.5));
        const timeSize = bannerSet ? policy.bannerTimeSize
            : (tight ? policy.tightTitleSize : (narrow ? 10 : 11));
        // The banner spends its top pad on the second line; every other tier
        // keeps it. Decided here rather than above because it follows the mode,
        // and a chip that wanted a banner but got `titleOnly` keeps its pad.
        const padTop = bannerSet ? 0 : (tight ? 2 : 3);

        // The guest line, on the two gates above. `mode === "stacked"` is part
        // of it and not an accident: an inline chip has one line by definition,
        // and a `titleOnly` chip could not afford a time, let alone a guest.
        const showGuests = mode === "stacked"
            && w >= policy.guestsMinWidth && h >= policy.guestLineMinHeight;

        // A line box is its point size and a bit; the exact metric belongs to
        // the font and the surface measures it, but the *count* is a decision
        // and has to be the same on every screen, so it is taken from the sizes
        // this function chose rather than from anything rendered.
        const titleLine = Math.round(titleSize * policy.lineFactor);
        const timeLine = mode === "stacked" ? Math.round(timeSize * policy.lineFactor) : 0;
        // The guest line is charged against the title's wrapping allowance the
        // same way the time line is, so a chip never wraps into a row it has
        // already promised to something else.
        const guestLine = showGuests ? Math.round(timeSize * policy.lineFactor) : 0;
        const room = h - padTop - timeLine - guestLine - 2;
        const lineCap = tight ? policy.maxTightTitleLines : policy.maxTitleLines;
        const titleLines = (mode === "stacked" && textW >= policy.wrapMinTextWidth)
            ? Math.max(1, Math.min(lineCap, Math.floor(room / titleLine)))
            : 1;

        // An inline time is the start alone, *until the chip is wide enough for
        // the range* — see `inlineRangeMinWidth`. Above it the one-line chip
        // says exactly what the two-line one says, which is the point of giving
        // the day view its width.
        const form = (mode === "inline" && w < policy.inlineRangeMinWidth)
            ? "start" : timeForm;

        return {
            "mode": mode,
            "showTime": mode !== "titleOnly",
            "showGuests": showGuests,
            "guestSize": timeSize,
            "timeForm": form,
            "timeMeridiem": form === "range" || textW >= policy.meridiemMinTextWidth,
            "narrow": narrow,
            "tight": tight,
            "banner": bannerSet,
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
    ///
    /// The tight tier gets a fourth, because there a line is about *one word*:
    /// three lines of `Pairing: / grid / pack…` spends its whole allowance on a
    /// three-word title and still elides, where four prints the title. The rule
    /// is words, not lines; four narrow lines and three roomy ones are the same
    /// rule measured against the type each tier sets.
    readonly property real lineFactor: 1.35
    readonly property int maxTitleLines: 3
    readonly property int maxTightTitleLines: 4

    /// Under this many pixels **of text box** a chip does not wrap, whatever
    /// height it has.
    ///
    /// This measurement reversed a decision, and then the decision reversed
    /// back. Wrapping a 39px chip at pt(11) came out `Desig / n / rev…`,
    /// because a line that cannot hold one whole word breaks inside one — so
    /// wrapping was ruled out on chip width. But the thing that was too small
    /// was the *type*, not the chip: the tight tier's 9.5 puts every word in the
    /// fixture inside the same 33px box, and the wrap lands between words. So
    /// the gate is the text box against the type that will be set in it, and
    /// 28 is a short word at 9.5 — below that a chip has no wrap worth making.
    readonly property int wrapMinTextWidth: 28

    /// The padding a chip that is not narrow gets on each side of its text —
    /// `Theme.space2`, written out because this file is loaded by
    /// `qmltestrunner`, which cannot import `qs.Core`.
    readonly property int roomyGap: 8

    /// Whether a one-line chip may carry its time on the same line as its
    /// title — and the rule is **all or nothing**.
    ///
    /// The inline time costs a title about 50px, and on a covered cascade step
    /// that is the difference between `Design review` and `Desig… 10:00 AM`.
    /// One of those names a meeting and the other names nothing while printing
    /// a fact the chip's own row in the grid already states: the top edge sits
    /// on 10:00 and the hour is labelled a centimetre to the left. So a
    /// one-line chip either says both things whole or says the title, and it
    /// never buys the time with an ellipsis.
    ///
    /// The two widths are font metrics, which no policy can measure — the chip
    /// measures them and hands the numbers back, exactly as it does for
    /// `clipTitle`. The decision stays here.
    function inlineTimeFits(textWidth: real, titleWidth: real,
                            timeWidth: real, gap: real): bool {
        const box = isFinite(textWidth) ? textWidth : 0;
        const title = isFinite(titleWidth) ? titleWidth : 0;
        const time = isFinite(timeWidth) ? timeWidth : 0;
        const air = isFinite(gap) ? gap : 0;
        if (time <= 0)
            return false;
        return title + air + time <= box;
    }

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
    /// How many glyphs a word boundary may throw away before the cut is not
    /// worth making.
    ///
    /// `"Coffee with Opal"` in a box that holds fifteen glyphs cuts to
    /// `"Coffee with Opa"`, whose last space is at eleven — so the word rule
    /// printed `"Coffee with…"` and left a quarter of a full-width chip empty
    /// to the right of it. That is the rule firing in reverse: it exists to stop
    /// a *packed* chip printing `"D…"`, and on a chip with room it was spending
    /// pixels to say less. Past this budget the title is handed back whole and
    /// the surface's own `ElideRight` cuts it, which is pixel-exact where this
    /// is an estimate and therefore always fills the box.
    ///
    /// Three, because the cases the word rule is for are one or two glyphs over
    /// a boundary — `"Design r"` → `"Design…"` — and a boundary four or more
    /// glyphs back is a whole short word being dropped for nothing.
    readonly property int wordCutBudget: 3

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
            return (n - space <= policy.wordCutBudget)
                ? cut.slice(0, space) + "…"
                : t;
        return (n > 1 ? t.slice(0, n - 1) : "") + "…";
    }
}
