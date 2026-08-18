// What a drag on the week grid proposes.
//
// The grid in every case below is deliberately 60px per hour, so a pixel is a
// minute and every expected time can be read straight off the coordinate — a
// test whose arithmetic needs its own arithmetic proves nothing when it fails.
// Columns are the week of 2026-08-16 (a Sunday), the gutter is 60px wide and
// the grid is 760px, so each day column is exactly 100px: column 0 is Sunday
// the 16th, column 1 Monday the 17th, column 2 Tuesday the 18th.
//
// The cases are the four modes and their floors: the snap that rounds to the
// *nearest* quarter rather than down, a drag that runs upward from its anchor,
// a move that keeps its duration across a day boundary and gives up position
// rather than length at midnight, both resizes hitting the 15-minute floor,
// and the two ways a drag declines to commit — the click that never moved and
// the drag that came back to where it started.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "DragPolicy"

    DragPolicy { id: drag }

    readonly property var week: [
        "2026-08-16", "2026-08-17", "2026-08-18", "2026-08-19",
        "2026-08-20", "2026-08-21", "2026-08-22"
    ]

    readonly property var ctx: ({
        "hourHeight": 60, "gutterWidth": 60, "gridWidth": 760,
        "columns": testCase.week, "snap": 15, "minMinutes": 15, "threshold": 4
    })

    /// The same context with an event attached — move and resize need one.
    function withEvent(start: string, end: string): var {
        return {
            "hourHeight": 60, "gutterWidth": 60, "gridWidth": 760,
            "columns": testCase.week, "snap": 15, "minMinutes": 15, "threshold": 4,
            "event": { "id": "evt-1", "start": start, "end": end }
        };
    }

    function cleanup() {
        drag.cancel();
    }

    // --- the grid's own arithmetic --------------------------------------------

    function test_snapping_goes_to_the_nearest_quarter_not_down() {
        compare(drag.snapMinutes(100, testCase.ctx), 105);
        compare(drag.snapMinutes(97, testCase.ctx), 90);
        compare(drag.snapMinutes(0, testCase.ctx), 0);
    }

    function test_a_pointer_below_the_grid_proposes_midnight_not_tomorrow() {
        compare(drag.minutesAt(2000, testCase.ctx), 1440);
        compare(drag.minutesAt(-40, testCase.ctx), 0);
    }

    function test_the_gutter_and_the_far_edge_both_land_in_a_real_column() {
        compare(drag.columnForX(59, testCase.ctx), 0);    // the hour labels
        compare(drag.columnForX(60, testCase.ctx), 0);
        compare(drag.columnForX(210, testCase.ctx), 1);
        compare(drag.columnForX(310, testCase.ctx), 2);
        compare(drag.columnForX(2000, testCase.ctx), 6);  // dragged off the right
    }

    /// A press exactly on a column's drawn left edge belongs to that column.
    ///
    /// 800px of grid behind an 80px gutter is 720 / 7 = 102.857px a column,
    /// which is the ordinary case rather than a contrived one: the edges are
    /// rounded to whole pixels, so dividing the raw width again disagrees with
    /// where the column was actually drawn. x = 491 is column 4's own left
    /// edge and floor division answers 3 there — an event created a day early
    /// from a grid that looks right.
    function test_a_press_on_a_column_edge_lands_in_that_column() {
        const ctx = {
            "hourHeight": 60, "gutterWidth": 80, "gridWidth": 800,
            "columns": testCase.week, "snap": 15, "minMinutes": 15, "threshold": 4
        };
        compare(drag.columnForX(491, ctx), 4);
        const edges = [80, 183, 286, 389, 491, 594, 697];
        for (let i = 0; i < edges.length; i++)
            compare(drag.columnForX(edges[i], ctx), i, "edge x=" + edges[i]);
    }

    // --- create ---------------------------------------------------------------

    function test_a_create_drag_of_100px_is_105_minutes() {
        drag.begin("create", 210, 540, testCase.ctx);   // 09:00, Monday column
        const p = drag.update(212, 640);
        compare(p.mode, "create");
        compare(p.dayIso, "2026-08-17");
        compare(p.start, "2026-08-17T09:00");
        compare(p.end, "2026-08-17T10:45");
        compare(p.h, 105);
        compare(p.y, 540);
        compare(p.column, 1);
        verify(p.moved);
        const r = drag.end();
        verify(r.committed);
        compare(r.kind, "create");
    }

    function test_a_create_drag_runs_upward_from_its_anchor_too() {
        drag.begin("create", 210, 600, testCase.ctx);   // 10:00
        const p = drag.update(210, 500);
        compare(p.start, "2026-08-17T08:15");           // 500 snaps up to 495
        compare(p.end, "2026-08-17T10:00");
    }

    function test_a_create_drag_is_never_shorter_than_the_floor() {
        drag.begin("create", 210, 540, testCase.ctx);
        const p = drag.update(210, 545);
        compare(p.start, "2026-08-17T09:00");
        compare(p.end, "2026-08-17T09:15");
    }

    function test_a_create_drag_stays_in_the_column_it_started_in() {
        drag.begin("create", 210, 540, testCase.ctx);
        const p = drag.update(690, 600);               // four columns to the right
        compare(p.dayIso, "2026-08-17");
    }

    function test_a_create_drag_off_the_bottom_ends_at_midnight() {
        drag.begin("create", 210, 1430, testCase.ctx);  // 23:45 after snapping
        const p = drag.update(210, 1600);
        compare(p.start, "2026-08-17T23:45");
        compare(p.end, "2026-08-18T00:00");             // end is exclusive
    }

    // --- move -----------------------------------------------------------------

    function test_a_move_across_a_column_keeps_its_duration() {
        const c = testCase.withEvent("2026-08-17T09:00", "2026-08-17T10:30");
        drag.begin("move", 210, 570, c);                // pressed 30 min into the chip
        const p = drag.update(310, 600);               // Tuesday, 10:00
        compare(p.mode, "move");
        compare(p.dayIso, "2026-08-18");
        compare(p.start, "2026-08-18T09:30");           // the grab offset is preserved
        compare(p.end, "2026-08-18T11:00");
        compare(p.h, 90);
        compare(p.column, 2);
    }

    function test_a_move_at_the_bottom_of_the_day_gives_up_position_not_length() {
        const c = testCase.withEvent("2026-08-17T09:00", "2026-08-17T10:30");
        drag.begin("move", 210, 570, c);
        const p = drag.update(310, 1500);
        compare(p.start, "2026-08-18T22:30");
        compare(p.end, "2026-08-19T00:00");
        compare(p.h, 90);
    }

    function test_a_move_without_an_event_proposes_nothing() {
        const p = drag.begin("move", 210, 540, testCase.ctx);
        compare(p.active, false);
        compare(drag.active, false);
    }

    // --- resize ---------------------------------------------------------------

    function test_resize_bottom_floors_at_the_minimum() {
        const c = testCase.withEvent("2026-08-17T09:00", "2026-08-17T10:00");
        drag.begin("resizeBottom", 210, 600, c);
        const p = drag.update(210, 480);                // dragged up past the start
        compare(p.start, "2026-08-17T09:00");
        compare(p.end, "2026-08-17T09:15");
        compare(p.h, 15);
    }

    function test_resize_top_floors_at_the_minimum_from_the_other_side() {
        const c = testCase.withEvent("2026-08-17T09:00", "2026-08-17T10:00");
        drag.begin("resizeTop", 210, 540, c);
        const p = drag.update(210, 620);                // dragged down past the end
        compare(p.start, "2026-08-17T09:45");
        compare(p.end, "2026-08-17T10:00");
    }

    function test_resize_bottom_moves_only_the_end() {
        const c = testCase.withEvent("2026-08-17T09:00", "2026-08-17T10:00");
        drag.begin("resizeBottom", 210, 600, c);
        const p = drag.update(210, 700);
        compare(p.start, "2026-08-17T09:00");
        compare(p.end, "2026-08-17T11:45");             // 700 snaps to 705
        compare(p.mode, "resizeBottom");
    }

    // --- committing -----------------------------------------------------------

    function test_a_press_that_never_moved_is_a_click_and_commits_nothing() {
        drag.begin("create", 210, 540, testCase.ctx);
        const p = drag.update(211, 543);                // inside the 4px threshold
        compare(p.moved, false);
        const r = drag.end();
        compare(r.committed, false);
        compare(r.kind, "click");
    }

    function test_a_drag_that_landed_where_it_started_is_a_noop() {
        const c = testCase.withEvent("2026-08-17T09:00", "2026-08-17T10:30");
        drag.begin("move", 210, 570, c);
        drag.update(310, 700);                          // away
        const p = drag.update(210, 570);               // and back
        compare(p.start, "2026-08-17T09:00");
        verify(p.moved);                                // it did move, so not a click
        const r = drag.end();
        compare(r.committed, false);
        compare(r.kind, "noop");
    }

    function test_ending_a_drag_leaves_the_machine_idle() {
        drag.begin("create", 210, 540, testCase.ctx);
        drag.update(210, 640);
        drag.end();
        compare(drag.active, false);
        compare(drag.update(210, 700).active, false);   // a stray motion proposes nothing
        compare(drag.end().kind, "idle");
    }

    function test_cancelling_throws_the_proposal_away() {
        drag.begin("create", 210, 540, testCase.ctx);
        drag.update(210, 640);
        const r = drag.cancel();
        compare(r.committed, false);
        compare(r.kind, "cancel");
        compare(drag.active, false);
    }

    function test_a_mode_nobody_defined_starts_no_drag() {
        const p = drag.begin("stretch", 210, 540, testCase.ctx);
        compare(p.active, false);
    }

    // --- hit zones ------------------------------------------------------------

    function test_a_chip_has_three_zones() {
        compare(drag.hitEdge(2, 60, 6), "top");
        compare(drag.hitEdge(30, 60, 6), "body");
        compare(drag.hitEdge(58, 60, 6), "bottom");
    }

    function test_a_short_chip_keeps_a_body_to_grab() {
        // 15 minutes is ~15px: 6px handles at both ends would leave 3px of
        // body, so the handles give way instead.
        compare(drag.hitEdge(2, 15, 6), "top");
        compare(drag.hitEdge(7, 15, 6), "body");
        compare(drag.hitEdge(13, 15, 6), "bottom");
    }

    function test_a_chip_with_no_height_is_all_body() {
        // A delegate mid-rebuild has height 0, and a zone read off it decides
        // which gesture a press starts. "top" there would turn every press on a
        // settling column into a resize.
        compare(drag.hitEdge(0, 0, 6), "body");
        compare(drag.hitEdge(4, -10, 6), "body");
    }

    // --- adversarial probes ----------------------------------------------------

    function test_a_press_at_the_bottom_of_the_grid_opens_in_the_day_it_pressed() {
        // 1438px snaps to 1440 — midnight — so the opening ghost of a press in
        // the last few pixels of Monday must be Monday's last quarter, not a
        // 00:00 chip that has already jumped into Tuesday's column. `begin` has
        // to floor the same way `update` does, or the ghost moves backwards the
        // instant the pointer does.
        const p = drag.begin("create", 210, 1438, testCase.ctx);
        compare(p.dayIso, "2026-08-17");
        compare(p.start, "2026-08-17T23:45");
        compare(p.end, "2026-08-18T00:00");
        compare(p.column, 1);
        const q = drag.update(210, 1438);   // the press point again, unmoved
        compare(q.start, p.start);
        compare(q.end, p.end);
    }

    function test_a_bottom_resize_dragged_into_the_next_column_crosses_midnight() {
        // The column under the pointer is a *day offset* for a resize, not a
        // new day: an event whose bottom edge is dragged into Tuesday morning
        // still starts on Monday and now runs past midnight.
        const c = testCase.withEvent("2026-08-17T09:00", "2026-08-17T10:00");
        drag.begin("resizeBottom", 210, 600, c);
        const p = drag.update(310, 120);                // Tuesday, 02:00
        compare(p.dayIso, "2026-08-17");
        compare(p.start, "2026-08-17T09:00");
        compare(p.end, "2026-08-18T02:00");
        compare(p.h, 1020);
    }

    function test_a_grid_with_no_columns_proposes_nothing_at_all() {
        compare(drag.columnForX(210, { "columns": [] }), -1);
        compare(drag.begin("create", 210, 540, null).active, false);
        compare(drag.update(210, 600).active, false);   // nothing was latched
        const c = {
            "hourHeight": 60, "gutterWidth": 60, "gridWidth": 760, "columns": []
        };
        compare(drag.begin("create", 210, 540, c).active, false);
        compare(drag.end().kind, "idle");
    }

    function test_an_overnight_event_moves_without_losing_its_length() {
        // 23:00-01:00 is 120 minutes that do not fit after the clamp's own
        // start ceiling; the position gives way, never the duration.
        const c = testCase.withEvent("2026-08-17T23:00", "2026-08-18T01:00");
        drag.begin("move", 210, 1410, c);               // grabbed 30 min in
        const p = drag.update(310, 600);
        compare(p.start, "2026-08-18T09:30");
        compare(p.end, "2026-08-18T11:30");
        compare(p.h, 120);
        const q = drag.update(310, 1440);               // shoved at the bottom
        compare(q.start, "2026-08-18T22:00");
        compare(q.end, "2026-08-19T00:00");
        compare(q.h, 120);
    }

    function test_a_context_may_set_its_own_snap_and_floor() {
        const c = {
            "hourHeight": 60, "gutterWidth": 60, "gridWidth": 760,
            "columns": testCase.week, "snap": 5, "minMinutes": 30, "threshold": 4
        };
        compare(drag.snapMinutes(548, c), 550);
        drag.begin("create", 210, 540, c);
        const p = drag.update(210, 548);
        compare(p.start, "2026-08-17T09:00");
        compare(p.end, "2026-08-17T09:30");             // the floor is 30, not 15
    }

    function test_a_create_drag_that_comes_back_still_creates() {
        // `noop` is a move/resize verdict: a create that never had an original
        // to equal commits its floor-length event, the way a press-and-wobble
        // on empty grid does everywhere else.
        drag.begin("create", 210, 540, testCase.ctx);
        drag.update(210, 700);
        const p = drag.update(210, 540);
        compare(p.start, "2026-08-17T09:00");
        compare(p.end, "2026-08-17T09:15");
        const r = drag.end();
        verify(r.committed);
        compare(r.kind, "create");
    }

    function test_the_handle_size_may_be_left_out() {
        compare(drag.hitEdge(2, 60), "top");            // edge falls back to 6
        compare(drag.hitEdge(30, 60), "body");
        compare(drag.hitEdge(5, 0, 6), "body");         // a chip with no height
    }
}
