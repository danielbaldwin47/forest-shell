// What a pointer drag on the week grid is proposing, as arithmetic.
//
// Dragging is the one interaction in the calendar that a picture cannot judge
// and a click cannot either: "drag from here to there" is a *decision* about
// minutes — where the press anchors, which way the drag went, what snaps to
// what, when a duration hits its floor, which day the pointer crossed into —
// wrapped in a surface whose only job is to hand over two numbers. So all of
// it is here, on the QtQuick-only side of the line, and what is left in the
// view is a `MouseArea` calling `begin`/`update`/`end` and a ghost bound to
// `proposal`.
//
// The payoff is that a drag can be *posed* with no pointer at all: the capture
// harness (seam 3) renders a mid-drag ghost by calling `begin` and `update`
// with coordinates, and seam 2 only has to prove that a real pointer reaches
// this object — not that the arithmetic inside it is right, which is this
// file's tests' job.
//
// ## What it is, and is not
//
// A state machine with **no timers, no clock and no store**. `begin` latches
// the press, `update` recomputes a whole proposal from scratch each call (so
// no drift accumulates over a hundred motion events), `end` says whether the
// proposal is worth committing and `cancel` throws it away. Nothing here
// writes an event; the caller does that with the returned stamps.
//
// ## Conventions
//
//   - **Times are local wall-clock stamps** — `"2026-08-18T09:15"` — never a
//     `Date` and never an instant. See Services/Calendar/CalendarTime.qml for
//     the argument; every piece of day and minute arithmetic below is that
//     file's.
//   - **`y` is measured from the top of the day area**, where `y === 0` is
//     00:00, and one hour is `ctx.hourHeight` pixels. The all-day row and any
//     header are the view's business and are not in this coordinate space.
//   - **`x` is measured from the left of the whole grid**, gutter included:
//     `ctx.gutterWidth` is the hour-label gutter and `ctx.gridWidth` is the
//     full width, so the day columns share `gridWidth - gutterWidth` between
//     them. A press in the gutter lands in column 0 rather than nowhere,
//     because a drag that begins one pixel left of the first column is a drag
//     in the first column and not an error.
//   - **Minutes are clamped to a day** (0..1440) at the point they are read
//     off `y`, so a pointer dragged off the bottom of the grid proposes
//     midnight rather than tomorrow lunchtime.
//   - **Every proposal is at least `minMinutes` long.** There is no such thing
//     as a zero-length proposal, mid-drag or at the end of one, so a view can
//     bind a ghost to `proposal` without checking.
//
// ## Committing
//
// `end()` answers `{committed, kind, proposal}` rather than mutating anything.
// It refuses in two distinct ways, and the distinction is the whole point:
//
//   - the drag never passed `ctx.threshold` pixels — that is a **click**, and
//     a click on empty grid opens a quick-create popover while a click on a
//     chip selects it, so the caller needs to know it was one (`kind:
//     "click"`);
//   - the drag moved but landed exactly where it started — a **noop**, which
//     must not be written, because a store write is a file write and a log
//     line and an undo entry for nothing at all.
import QtQuick
import "../../Services/Calendar"

QtObject {
    id: policy

    property CalendarTime time: CalendarTime {}

    /// The live proposal. Idle between drags rather than null, so a view can
    /// bind `visible: dragPolicy.proposal.active` without a guard.
    readonly property var idle: ({
        "active": false, "mode": "", "dayIso": "", "start": "", "end": "",
        "moved": false, "column": -1, "y": 0, "h": 0
    })

    property var proposal: policy.idle

    readonly property bool active: policy.proposal.active

    // --- internals ------------------------------------------------------------

    property var _ctx: null
    property string _mode: ""
    property real _pressX: 0
    property real _pressY: 0
    property bool _moved: false
    property real _anchor: 0        // create: the snapped minute the press anchored
    property real _grab: 0          // move: press minute minus event-start minute
    property real _duration: 0      // move: the duration being preserved
    property string _baseDay: ""    // resize/move: the day the original event starts on
    property real _origStart: 0     // resize: original start, minutes from _baseDay
    property real _origEnd: 0       // resize: original end, minutes from _baseDay
    property string _origStartStamp: ""
    property string _origEndStamp: ""

    /// Fills in the four knobs a caller may leave out. A context without
    /// `hourHeight` would divide by zero and answer `NaN` minutes, which is a
    /// proposal that renders as nothing and commits as garbage — so it falls
    /// back to 60 rather than propagating.
    function _norm(ctx: var): var {
        const c = ctx || {};
        const cols = Array.isArray(c.columns) ? c.columns : [];
        return {
            "hourHeight": c.hourHeight > 0 ? c.hourHeight : 60,
            "gutterWidth": c.gutterWidth > 0 ? c.gutterWidth : 0,
            "gridWidth": c.gridWidth > 0 ? c.gridWidth : 0,
            "columns": cols,
            "event": c.event || null,
            "snap": c.snap > 0 ? c.snap : 15,
            "minMinutes": c.minMinutes > 0 ? c.minMinutes : 15,
            "threshold": c.threshold >= 0 ? c.threshold : 4
        };
    }

    /// Minutes since midnight at `y`, unsnapped and unclamped. The offset a
    /// `move` grabs with is computed from this, not from the snapped value:
    /// snapping the *grab* as well as the result would quantise the pointer
    /// twice and make the chip jump under the finger.
    function rawMinutes(y: real, ctx: var): real {
        const c = policy._norm(ctx);
        return y * 60 / c.hourHeight;
    }

    /// To the nearest `snap` minutes. Nearest, not floor: a drag of 100
    /// minutes is 105 rather than 90, because the pointer is the thing being
    /// rounded and a person aiming at 105 undershoots as often as they
    /// overshoot.
    function snapMinutes(minutes: real, ctx: var): real {
        const c = policy._norm(ctx);
        return Math.round(minutes / c.snap) * c.snap;
    }

    function _clampDay(minutes: real): real {
        return Math.max(0, Math.min(1440, minutes));
    }

    /// Snapped, clamped into the day. What every mode reads off a pointer `y`.
    function minutesAt(y: real, ctx: var): real {
        return policy._clampDay(policy.snapMinutes(policy.rawMinutes(y, ctx), ctx));
    }

    /// Which day column `x` falls in, clamped to the ends. `-1` only when
    /// there are no columns at all.
    function columnForX(x: real, ctx: var): int {
        const c = policy._norm(ctx);
        const n = c.columns.length;
        if (n === 0)
            return -1;
        const span = c.gridWidth - c.gutterWidth;
        if (!(span > 0))
            return 0;
        const idx = Math.floor((x - c.gutterWidth) / (span / n));
        return Math.max(0, Math.min(n - 1, idx));
    }

    function _dayAt(x: real, ctx: var): string {
        const c = policy._norm(ctx);
        const col = policy.columnForX(x, ctx);
        return col < 0 ? "" : c.columns[col];
    }

    /// A proposal from a day and two minute offsets from that day's midnight.
    /// The offsets may sit outside 0..1440 — a resize can push an end past
    /// midnight — so the day, the `y` and the `h` are all re-derived from the
    /// formatted stamps rather than assumed.
    function _make(mode: string, day: string, startMin: real, endMin: real, ctx: var, moved: bool): var {
        const c = policy._norm(ctx);
        const start = policy.time.formatStamp(day, startMin);
        const end = policy.time.formatStamp(day, endMin);
        if (start === "" || end === "")
            return policy.idle;
        const dayIso = policy.time.dayOf(start);
        const px = c.hourHeight / 60;
        return {
            "active": true,
            "mode": mode,
            "dayIso": dayIso,
            "start": start,
            "end": end,
            "moved": moved,
            "column": c.columns.indexOf(dayIso),
            "y": policy.time.parseMinutes(start) * px,
            "h": policy.time.diffMinutes(start, end) * px
        };
    }

    // --- the state machine ----------------------------------------------------

    /// Latch a press. `mode` is `create|move|resizeTop|resizeBottom`; the
    /// three that are not `create` need `ctx.event` — `{id, start, end}` — and
    /// refuse without it rather than proposing an event out of nothing.
    ///
    /// Returns the opening proposal, which for `move` and `resize` is the
    /// event exactly as it already is: the ghost appears where the chip is and
    /// then follows, instead of jumping on the first motion event.
    function begin(mode: string, x: real, y: real, ctx: var): var {
        const c = policy._norm(ctx);
        const known = mode === "create" || mode === "move"
                   || mode === "resizeTop" || mode === "resizeBottom";
        if (!known) {
            policy.cancel();
            return policy.proposal;
        }
        policy._ctx = c;
        policy._mode = mode;
        policy._pressX = x;
        policy._pressY = y;
        policy._moved = false;

        if (mode === "create") {
            const day = policy._dayAt(x, c);
            if (day === "") {
                policy.cancel();
                return policy.proposal;
            }
            policy._baseDay = day;
            policy._anchor = policy.minutesAt(y, c);
            policy._origStartStamp = "";
            policy._origEndStamp = "";
            // The opening ghost is floored the same way `update` floors one, so
            // a press in the last few pixels of a column opens as that day's
            // last quarter rather than as a 00:00 chip that has already jumped
            // into the next column — and then jumps back the moment the pointer
            // moves. The *anchor* keeps the unfloored press minute: a drag
            // upward from the bottom edge is a drag from midnight.
            let openEnd = policy._anchor + c.minMinutes;
            let openStart = policy._anchor;
            if (openEnd > 1440) {
                openEnd = 1440;
                openStart = openEnd - c.minMinutes;
            }
            policy.proposal = policy._make(mode, day, openStart, openEnd, c, false);
            return policy.proposal;
        }

        const ev = c.event;
        const day = ev ? policy.time.dayOf(ev.start) : "";
        if (!ev || day === "" || !policy.time.isStamp(ev.end)) {
            policy.cancel();
            return policy.proposal;
        }
        policy._baseDay = day;
        policy._origStartStamp = ev.start;
        policy._origEndStamp = ev.end;
        policy._origStart = policy.time.parseMinutes(ev.start);
        policy._origEnd = policy._origStart + policy.time.diffMinutes(ev.start, ev.end);
        policy._duration = policy._origEnd - policy._origStart;
        policy._grab = policy.rawMinutes(y, c) - policy._origStart;
        policy.proposal = policy._make(mode, day, policy._origStart, policy._origEnd, c, false);
        return policy.proposal;
    }

    /// Recompute the whole proposal for a pointer at `x, y`. Idle if no drag
    /// is in flight, so a stray motion event after `end()` proposes nothing.
    function update(x: real, y: real): var {
        if (!policy._mode)
            return policy.idle;
        const c = policy._ctx;
        const dx = x - policy._pressX;
        const dy = y - policy._pressY;
        // Latched: a drag that passes the threshold and comes back to the
        // press point has still moved, and must be judged on where it landed
        // rather than being downgraded to a click.
        if (!policy._moved && Math.sqrt(dx * dx + dy * dy) > c.threshold)
            policy._moved = true;

        const cur = policy.minutesAt(y, c);

        if (policy._mode === "create") {
            // The column is the *press* column: a create drag is vertical by
            // nature, and letting a few pixels of horizontal wander change the
            // day is how an event lands on Tuesday when it was drawn on
            // Monday.
            let start = Math.min(policy._anchor, cur);
            let end = Math.max(policy._anchor, cur);
            if (end - start < c.minMinutes) {
                // Grow in the direction of travel, then fall back the other
                // way when that would leave the day.
                if (cur >= policy._anchor)
                    end = start + c.minMinutes;
                else
                    start = end - c.minMinutes;
                if (end > 1440) {
                    end = 1440;
                    start = end - c.minMinutes;
                }
                if (start < 0) {
                    start = 0;
                    end = c.minMinutes;
                }
            }
            policy.proposal = policy._make("create", policy._baseDay, start, end, c, policy._moved);
            return policy.proposal;
        }

        if (policy._mode === "move") {
            const day = policy._dayAt(x, c) || policy._baseDay;
            const raw = policy.rawMinutes(y, c) - policy._grab;
            // Clamped so the whole event stays inside the day it landed on —
            // a move is a translation, so the duration is never the thing that
            // gives.
            const maxStart = Math.max(0, 1440 - policy._duration);
            const start = Math.max(0, Math.min(maxStart, policy.snapMinutes(raw, c)));
            policy.proposal = policy._make("move", day, start, start + policy._duration, c, policy._moved);
            return policy.proposal;
        }

        // Both resizes work in minutes from `_baseDay` midnight, so a bottom
        // edge dragged into the next column extends past midnight instead of
        // folding back to the small hours of the same day.
        const col = policy.columnForX(x, c);
        const dayShift = col < 0 || policy._baseDay === "" ? 0
                       : policy.time.diffDays(policy._baseDay, c.columns[col]);
        const pointer = dayShift * 1440 + cur;

        if (policy._mode === "resizeTop") {
            const start = Math.min(pointer, policy._origEnd - c.minMinutes);
            policy.proposal = policy._make("resizeTop", policy._baseDay, start, policy._origEnd, c, policy._moved);
            return policy.proposal;
        }

        const end = Math.max(pointer, policy._origStart + c.minMinutes);
        policy.proposal = policy._make("resizeBottom", policy._baseDay, policy._origStart, end, c, policy._moved);
        return policy.proposal;
    }

    /// Finish. `committed` is the caller's permission to write; `kind` says
    /// what happened when it is false — `"click"` for a press that never
    /// passed the threshold, `"noop"` for a drag that landed where it started.
    /// The proposal is returned either way, and the machine goes idle.
    function end(): var {
        if (!policy._mode)
            return { "committed": false, "kind": "idle", "proposal": policy.idle };
        const p = policy.proposal;
        const moved = policy._moved;
        const unchanged = policy._mode !== "create"
                       && p.start === policy._origStartStamp
                       && p.end === policy._origEndStamp;
        const committed = moved && !unchanged;
        const kind = committed ? policy._mode : (moved ? "noop" : "click");
        policy._reset();
        return { "committed": committed, "kind": kind, "proposal": p };
    }

    /// Abandon the drag — Escape, or a pointer that left the window. Answers
    /// the same shape as `end()` so a caller can route both through one
    /// handler.
    function cancel(): var {
        const p = policy.proposal;
        policy._reset();
        return { "committed": false, "kind": "cancel", "proposal": p };
    }

    function _reset() {
        policy._mode = "";
        policy._ctx = null;
        policy._moved = false;
        policy._origStartStamp = "";
        policy._origEndStamp = "";
        policy.proposal = policy.idle;
    }

    // --- hit zones ------------------------------------------------------------

    /// How deep a resize strip really is on a chip this tall.
    ///
    /// `edge` defaults to 6px, but never eats more than a third of the chip at
    /// each end: a 15-minute chip is ~15px tall, and two 6px handles on it
    /// would leave 3px of body — so the event could be resized and never
    /// moved, which is the bug a fixed handle size always ships with. Zero on a
    /// chip with no height, which is a delegate mid-rebuild.
    ///
    /// It is a function of its own rather than a line inside `hitEdge` because
    /// the surface needs the same number for a second purpose: the strips it
    /// hangs a resize cursor on have to be exactly as deep as the zones this
    /// answers, or the cursor promises a handle where the press finds a body.
    function edgeDepth(chipHeight: real, edge: real): real {
        const want = edge > 0 ? edge : 6;
        const e = Math.min(want, chipHeight / 3);
        return e > 0 ? e : 0;
    }

    /// Which part of a chip `yInChip` is in: `"top"`, `"bottom"` or `"body"`.
    function hitEdge(yInChip: real, chipHeight: real, edge: real): string {
        const e = policy.edgeDepth(chipHeight, edge);
        if (!(e > 0))
            return "body";
        const y = Math.max(0, Math.min(chipHeight, yInChip));
        if (y < e)
            return "top";
        if (y > chipHeight - e)
            return "bottom";
        return "body";
    }
}
