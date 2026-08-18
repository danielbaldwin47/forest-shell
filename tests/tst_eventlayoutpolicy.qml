// How overlapping events share the width of a day.
//
// The assertions are exact fractions rather than "roughly a third", because
// the whole point of the policy is that the arithmetic is decided here and not
// in a layout engine: `xFrac` and `wFrac` are integer ratios, so a third is
// `1 / 3` on both sides of the comparison and either matches exactly or is a
// bug. Nothing in this file renders anything.
//
// The three-way overlap and the ids come from tools/fixtures/calendar-events.json
// (Tuesday 2026-08-18), so the picture the capture harness takes and the
// numbers asserted here are the same day.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "EventLayoutPolicy"

    EventLayoutPolicy { id: layoutPolicy }

    function evt(id, start, end) {
        return { "id": id, "start": start, "end": end };
    }

    function placed(results, id) {
        for (let i = 0; i < results.length; i++)
            if (results[i].id === id)
                return results[i];
        return null;
    }

    function ids(results) {
        return results.map(function (r) {
            return r.id;
        }).join(",");
    }

    // --- nothing, and one thing -----------------------------------------------

    function test_a_day_with_nothing_on_it_lays_out_nothing() {
        compare(layoutPolicy.layout([]).length, 0);
        compare(layoutPolicy.layout(null).length, 0);
        compare(layoutPolicy.layout(undefined).length, 0);
        compare(layoutPolicy.clusters([]).length, 0);
    }

    function test_a_lone_event_takes_the_whole_column() {
        const out = layoutPolicy.layout([testCase.evt("evt-6", "2026-08-18T15:00", "2026-08-18T15:45")]);
        compare(out.length, 1);
        compare(out[0].column, 0);
        compare(out[0].columns, 1);
        compare(out[0].span, 1);
        compare(out[0].xFrac, 0);
        compare(out[0].wFrac, 1);
    }

    // --- touching is not overlapping ------------------------------------------

    function test_back_to_back_meetings_are_one_column_wide_each() {
        const out = layoutPolicy.layout([
            testCase.evt("a", "2026-08-18T09:00", "2026-08-18T10:00"),
            testCase.evt("b", "2026-08-18T10:00", "2026-08-18T11:00")
        ]);
        compare(layoutPolicy.clusters([
            testCase.evt("a", "2026-08-18T09:00", "2026-08-18T10:00"),
            testCase.evt("b", "2026-08-18T10:00", "2026-08-18T11:00")
        ]).length, 2);
        compare(testCase.placed(out, "a").columns, 1);
        compare(testCase.placed(out, "a").wFrac, 1);
        compare(testCase.placed(out, "b").column, 0);
        compare(testCase.placed(out, "b").wFrac, 1);
    }

    // --- the fixture Tuesday --------------------------------------------------

    function fixtureTuesday() {
        return [
            testCase.evt("evt-3", "2026-08-18T10:00", "2026-08-18T11:30"),
            testCase.evt("evt-4", "2026-08-18T10:30", "2026-08-18T12:00"),
            testCase.evt("evt-5", "2026-08-18T11:00", "2026-08-18T12:30"),
            testCase.evt("evt-6", "2026-08-18T15:00", "2026-08-18T15:45")
        ];
    }

    function test_the_fixture_tuesday_packs_its_three_way_overlap_into_three_columns() {
        const out = layoutPolicy.layout(testCase.fixtureTuesday());
        compare(out.length, 4);

        compare(testCase.placed(out, "evt-3").columns, 3);
        compare(testCase.placed(out, "evt-3").column, 0);
        compare(testCase.placed(out, "evt-3").xFrac, 0);
        compare(testCase.placed(out, "evt-3").wFrac, 1 / 3);

        compare(testCase.placed(out, "evt-4").column, 1);
        compare(testCase.placed(out, "evt-4").xFrac, 1 / 3);
        compare(testCase.placed(out, "evt-4").wFrac, 1 / 3);

        compare(testCase.placed(out, "evt-5").column, 2);
        compare(testCase.placed(out, "evt-5").xFrac, 2 / 3);
        compare(testCase.placed(out, "evt-5").wFrac, 1 / 3);
    }

    function test_the_afternoon_is_its_own_cluster_and_full_width() {
        const out = layoutPolicy.layout(testCase.fixtureTuesday());
        compare(testCase.placed(out, "evt-6").columns, 1);
        compare(testCase.placed(out, "evt-6").xFrac, 0);
        compare(testCase.placed(out, "evt-6").wFrac, 1);

        const groups = layoutPolicy.clusters(testCase.fixtureTuesday());
        compare(groups.length, 2);
        compare(groups[0].join(","), "evt-3,evt-4,evt-5");
        compare(groups[1].join(","), "evt-6");
    }

    // --- transitive clustering ------------------------------------------------

    function test_a_chain_of_overlaps_is_one_cluster_even_where_the_ends_do_not_touch() {
        // A and C never overlap; B holds them together.
        const chain = [
            testCase.evt("a", "2026-08-18T09:00", "2026-08-18T10:00"),
            testCase.evt("b", "2026-08-18T09:30", "2026-08-18T11:00"),
            testCase.evt("c", "2026-08-18T10:15", "2026-08-18T12:00")
        ];
        compare(layoutPolicy.clusters(chain).length, 1);

        const out = layoutPolicy.layout(chain);
        compare(testCase.placed(out, "a").columns, 2);
        compare(testCase.placed(out, "a").column, 0);
        compare(testCase.placed(out, "b").column, 1);

        // C reuses the column A freed at 10:00 rather than opening a third.
        compare(testCase.placed(out, "c").column, 0);
        compare(testCase.placed(out, "c").xFrac, 0);

        // And it cannot widen — B is still running at 10:15.
        compare(testCase.placed(out, "a").wFrac, 0.5);
        compare(testCase.placed(out, "b").wFrac, 0.5);
        compare(testCase.placed(out, "c").wFrac, 0.5);
    }

    // --- rightward expansion --------------------------------------------------

    function test_a_chip_widens_into_the_columns_free_for_its_whole_span() {
        // Three deep in the morning; by 09:50 only the first column is still
        // busy, so D widens across the two the cluster no longer needs.
        const day = [
            testCase.evt("a", "2026-08-18T09:00", "2026-08-18T10:00"),
            testCase.evt("b", "2026-08-18T09:00", "2026-08-18T09:30"),
            testCase.evt("c", "2026-08-18T09:15", "2026-08-18T09:45"),
            testCase.evt("d", "2026-08-18T09:50", "2026-08-18T10:30")
        ];
        compare(layoutPolicy.clusters(day).length, 1);
        const out = layoutPolicy.layout(day);

        compare(testCase.placed(out, "a").columns, 3);
        compare(testCase.placed(out, "a").column, 0);
        compare(testCase.placed(out, "b").column, 1);
        compare(testCase.placed(out, "c").column, 2);
        compare(testCase.placed(out, "d").column, 1);

        // D is one column wide by assignment and two by expansion.
        compare(testCase.placed(out, "d").span, 2);
        compare(testCase.placed(out, "d").xFrac, 1 / 3);
        compare(testCase.placed(out, "d").wFrac, 2 / 3);

        // Everything overlapped stays a third.
        compare(testCase.placed(out, "a").wFrac, 1 / 3);
        compare(testCase.placed(out, "b").wFrac, 1 / 3);
        compare(testCase.placed(out, "c").wFrac, 1 / 3);
    }

    function test_expansion_stops_at_the_first_column_that_is_not_free() {
        // A runs all morning in column 0 with B beside it, so neither can
        // widen; C reuses B's column and has nothing to its right.
        const day = [
            testCase.evt("a", "2026-08-18T09:00", "2026-08-18T12:00"),
            testCase.evt("b", "2026-08-18T09:00", "2026-08-18T10:00"),
            testCase.evt("c", "2026-08-18T10:30", "2026-08-18T11:00")
        ];
        const out = layoutPolicy.layout(day);
        compare(testCase.placed(out, "a").columns, 2);
        compare(testCase.placed(out, "a").column, 0);
        compare(testCase.placed(out, "a").wFrac, 0.5);   // B blocks it all morning
        compare(testCase.placed(out, "b").column, 1);
        compare(testCase.placed(out, "b").wFrac, 0.5);
        // C reuses B's column; there is nothing to its right to grow into.
        compare(testCase.placed(out, "c").column, 1);
        compare(testCase.placed(out, "c").xFrac, 0.5);
        compare(testCase.placed(out, "c").wFrac, 0.5);
    }

    // --- the short-event floor ------------------------------------------------

    function test_an_event_shorter_than_the_slot_still_pushes_its_neighbour_aside() {
        const out = layoutPolicy.layout([
            testCase.evt("tiny", "2026-08-18T10:00", "2026-08-18T10:05"),
            testCase.evt("next", "2026-08-18T10:10", "2026-08-18T11:00")
        ]);
        compare(testCase.placed(out, "tiny").columns, 2);
        compare(testCase.placed(out, "tiny").column, 0);
        compare(testCase.placed(out, "next").column, 1);
        compare(testCase.placed(out, "next").wFrac, 0.5);
    }

    function test_the_floor_is_fifteen_minutes_and_not_a_minute_more() {
        compare(layoutPolicy.minSlotMinutes, 15);
        // 10:15 is exactly where the floor ends, and touching is not overlapping.
        const out = layoutPolicy.layout([
            testCase.evt("tiny", "2026-08-18T10:00", "2026-08-18T10:05"),
            testCase.evt("next", "2026-08-18T10:15", "2026-08-18T11:00")
        ]);
        compare(testCase.placed(out, "tiny").columns, 1);
        compare(testCase.placed(out, "next").columns, 1);
        compare(testCase.placed(out, "next").wFrac, 1);
    }

    function test_a_zero_length_event_still_takes_a_slot() {
        // A drag passes through zero on its way somewhere.
        const out = layoutPolicy.layout([
            testCase.evt("drag", "2026-08-18T10:00", "2026-08-18T10:00"),
            testCase.evt("next", "2026-08-18T10:10", "2026-08-18T11:00")
        ]);
        compare(out.length, 2);
        compare(testCase.placed(out, "drag").columns, 2);
    }

    // --- ordering and rubbish -------------------------------------------------

    function test_two_identical_events_lay_out_the_same_way_every_time() {
        const same = [
            testCase.evt("zulu", "2026-08-18T09:00", "2026-08-18T10:00"),
            testCase.evt("alfa", "2026-08-18T09:00", "2026-08-18T10:00")
        ];
        const out = layoutPolicy.layout(same);
        compare(testCase.ids(out), "alfa,zulu");
        compare(testCase.placed(out, "alfa").column, 0);
        compare(testCase.placed(out, "zulu").column, 1);
        // Same input in the other order, same answer.
        compare(testCase.ids(layoutPolicy.layout(same.slice().reverse())), "alfa,zulu");
    }

    function test_the_longer_of_two_events_starting_together_takes_the_left_column() {
        const out = layoutPolicy.layout([
            testCase.evt("short", "2026-08-18T09:00", "2026-08-18T09:30"),
            testCase.evt("long", "2026-08-18T09:00", "2026-08-18T11:00")
        ]);
        compare(testCase.placed(out, "long").column, 0);
        compare(testCase.placed(out, "short").column, 1);
    }

    function test_something_that_is_not_an_event_is_left_out_rather_than_laid_out() {
        const out = layoutPolicy.layout([
            testCase.evt("ok", "2026-08-18T09:00", "2026-08-18T10:00"),
            testCase.evt("", "2026-08-18T09:00", "2026-08-18T10:00"),          // no id
            testCase.evt("backwards", "2026-08-18T11:00", "2026-08-18T10:00"), // ends first
            testCase.evt("dayonly", "2026-08-18", "2026-08-18T10:00"),         // not a stamp
            testCase.evt("junk", "sometime", "later"),
            null
        ]);
        compare(testCase.ids(out), "ok");
        compare(out[0].columns, 1);
    }

    function test_an_event_crossing_midnight_still_collides_with_the_next_day() {
        const out = layoutPolicy.layout([
            testCase.evt("night", "2026-08-18T23:00", "2026-08-19T01:00"),
            testCase.evt("early", "2026-08-19T00:30", "2026-08-19T02:00")
        ]);
        compare(testCase.placed(out, "night").columns, 2);
        compare(testCase.placed(out, "early").column, 1);
    }

    // --- the all-day row ------------------------------------------------------
    //
    // 2026-08-16 is a Sunday, so the week runs 08-16 (column 0) to 08-22
    // (column 6).

    function test_an_all_day_event_ending_at_midnight_covers_one_column() {
        // evt-7 from the fixture: 00:00 to 00:00 the next day is one day.
        const out = layoutPolicy.allDayLanes(
            [testCase.evt("evt-7", "2026-08-19T00:00", "2026-08-20T00:00")],
            "2026-08-16");
        compare(out.length, 1);
        compare(out[0].lane, 0);
        compare(out[0].startCol, 3);
        compare(out[0].span, 1);
        compare(out[0].continuesLeft, false);
        compare(out[0].continuesRight, false);
    }

    function test_a_multi_day_event_covers_every_column_it_touches() {
        // evt-9 from the fixture: Thursday morning to Saturday afternoon.
        const out = layoutPolicy.allDayLanes(
            [testCase.evt("evt-9", "2026-08-20T09:00", "2026-08-22T17:00")],
            "2026-08-16");
        compare(out[0].startCol, 4);
        compare(out[0].span, 3);
        compare(out[0].continuesRight, false);
    }

    function test_spans_that_do_not_share_a_column_share_a_lane() {
        const out = layoutPolicy.allDayLanes([
            testCase.evt("evt-7", "2026-08-19T00:00", "2026-08-20T00:00"),
            testCase.evt("evt-9", "2026-08-20T09:00", "2026-08-22T17:00")
        ], "2026-08-16");
        compare(out.length, 2);
        compare(testCase.placed(out, "evt-7").lane, 0);
        compare(testCase.placed(out, "evt-9").lane, 0);
    }

    function test_spans_that_share_a_column_stack_into_lanes() {
        const out = layoutPolicy.allDayLanes([
            testCase.evt("wide", "2026-08-18T00:00", "2026-08-22T00:00"),
            testCase.evt("late", "2026-08-20T09:00", "2026-08-22T17:00")
        ], "2026-08-16");
        compare(testCase.placed(out, "wide").startCol, 2);
        compare(testCase.placed(out, "wide").span, 4);   // Tue-Fri
        compare(testCase.placed(out, "wide").lane, 0);
        compare(testCase.placed(out, "late").startCol, 4);
        compare(testCase.placed(out, "late").lane, 1);
    }

    function test_a_lane_is_reused_by_the_next_span_that_fits_in_it() {
        const out = layoutPolicy.allDayLanes([
            testCase.evt("a", "2026-08-16T00:00", "2026-08-18T00:00"),  // cols 0-1
            testCase.evt("b", "2026-08-16T00:00", "2026-08-18T00:00"),  // cols 0-1
            testCase.evt("c", "2026-08-19T00:00", "2026-08-21T00:00")   // cols 3-4
        ], "2026-08-16");
        compare(testCase.placed(out, "a").lane, 0);
        compare(testCase.placed(out, "b").lane, 1);
        compare(testCase.placed(out, "c").lane, 0);
    }

    function test_the_longer_of_two_spans_starting_together_takes_the_top_lane() {
        const out = layoutPolicy.allDayLanes([
            testCase.evt("short", "2026-08-17T00:00", "2026-08-18T00:00"),
            testCase.evt("long", "2026-08-17T00:00", "2026-08-20T00:00")
        ], "2026-08-16");
        compare(testCase.placed(out, "long").lane, 0);
        compare(testCase.placed(out, "short").lane, 1);
    }

    function test_a_span_running_off_both_ends_is_clipped_to_the_week_and_flagged() {
        const out = layoutPolicy.allDayLanes(
            [testCase.evt("holiday", "2026-08-13T00:00", "2026-08-25T10:00")],
            "2026-08-16");
        compare(out[0].startCol, 0);
        compare(out[0].span, 7);
        compare(out[0].continuesLeft, true);
        compare(out[0].continuesRight, true);
    }

    function test_a_span_running_off_one_end_is_flagged_on_that_end_only() {
        const left = layoutPolicy.allDayLanes(
            [testCase.evt("in", "2026-08-14T00:00", "2026-08-18T00:00")],
            "2026-08-16");
        compare(left[0].startCol, 0);
        compare(left[0].span, 2);
        compare(left[0].continuesLeft, true);
        compare(left[0].continuesRight, false);

        const right = layoutPolicy.allDayLanes(
            [testCase.evt("out", "2026-08-21T00:00", "2026-08-25T00:00")],
            "2026-08-16");
        compare(right[0].startCol, 5);
        compare(right[0].span, 2);
        compare(right[0].continuesLeft, false);
        compare(right[0].continuesRight, true);
    }

    function test_a_span_that_misses_the_week_is_not_laid_out_at_all() {
        compare(layoutPolicy.allDayLanes(
            [testCase.evt("before", "2026-08-09T00:00", "2026-08-10T00:00")],
            "2026-08-16").length, 0);
        compare(layoutPolicy.allDayLanes(
            [testCase.evt("after", "2026-08-23T00:00", "2026-08-24T00:00")],
            "2026-08-16").length, 0);
        // A span ending exactly at the week's first midnight ends the day before.
        compare(layoutPolicy.allDayLanes(
            [testCase.evt("edge", "2026-08-14T00:00", "2026-08-16T00:00")],
            "2026-08-16").length, 0);
    }

    function test_the_all_day_row_of_a_week_that_is_not_one_is_empty() {
        compare(layoutPolicy.allDayLanes([], "2026-08-16").length, 0);
        compare(layoutPolicy.allDayLanes(null, "2026-08-16").length, 0);
        compare(layoutPolicy.allDayLanes(
            [testCase.evt("a", "2026-08-17T00:00", "2026-08-18T00:00")], "").length, 0);
        compare(layoutPolicy.allDayLanes(
            [testCase.evt("a", "2026-08-17T00:00", "2026-08-18T00:00")], "2026-13-01").length, 0);
    }

    function test_a_span_with_a_broken_stamp_is_left_out() {
        const out = layoutPolicy.allDayLanes([
            testCase.evt("ok", "2026-08-17T00:00", "2026-08-18T00:00"),
            testCase.evt("nostart", "whenever", "2026-08-18T00:00"),
            testCase.evt("noend", "2026-08-17T00:00", ""),
            testCase.evt("backwards", "2026-08-19T00:00", "2026-08-17T00:00"),
            testCase.evt("", "2026-08-17T00:00", "2026-08-18T00:00")
        ], "2026-08-16");
        compare(testCase.ids(out), "ok");
    }

    // --- adversarial probes ---------------------------------------------------
    //
    // Written against the finished policy rather than with it, to see whether
    // the arithmetic survives the cases the happy path never reaches.

    function test_probe_the_same_hour_on_two_days_is_two_clusters_not_one() {
        // absMinutes is absolute, so 10:00 Tuesday must not collide with 10:00
        // Wednesday however the caller hands them over.
        const two = [
            testCase.evt("tue", "2026-08-18T10:00", "2026-08-18T11:00"),
            testCase.evt("wed", "2026-08-19T10:00", "2026-08-19T11:00")
        ];
        compare(layoutPolicy.clusters(two).length, 2);
        const out = layoutPolicy.layout(two);
        compare(testCase.placed(out, "tue").wFrac, 1);
        compare(testCase.placed(out, "wed").wFrac, 1);
        compare(testCase.placed(out, "wed").columns, 1);
    }

    function test_probe_a_chip_widens_over_one_column_and_stops_at_the_next() {
        // Four deep, staggered so a later column is busy while an earlier one
        // has emptied — the arrangement where "stop at the first blocked
        // column" and "stop at the first column with anything in it" differ.
        const day = [
            testCase.evt("a", "2026-08-18T09:00", "2026-08-18T12:00"),
            testCase.evt("b", "2026-08-18T09:10", "2026-08-18T09:40"),
            testCase.evt("c", "2026-08-18T09:20", "2026-08-18T09:45"),
            testCase.evt("d", "2026-08-18T09:30", "2026-08-18T10:30"),
            testCase.evt("e", "2026-08-18T09:50", "2026-08-18T10:00")
        ];
        const out = layoutPolicy.layout(day);
        compare(testCase.placed(out, "a").column, 0);
        compare(testCase.placed(out, "b").column, 1);
        compare(testCase.placed(out, "c").column, 2);
        compare(testCase.placed(out, "d").column, 3);
        compare(testCase.placed(out, "e").columns, 4);
        // E reuses B's column, widens over C's (empty by 09:50) and stops at
        // D's, which is still running.
        compare(testCase.placed(out, "e").column, 1);
        compare(testCase.placed(out, "e").span, 2);
        compare(testCase.placed(out, "e").xFrac, 1 / 4);
        compare(testCase.placed(out, "e").wFrac, 1 / 2);
        // And nothing that widened landed on top of anything: A is still a
        // quarter, D still a quarter.
        compare(testCase.placed(out, "a").wFrac, 1 / 4);
        compare(testCase.placed(out, "d").wFrac, 1 / 4);
    }

    function test_probe_two_clusters_on_one_day_are_sized_independently() {
        const day = [
            testCase.evt("m1", "2026-08-18T09:00", "2026-08-18T10:00"),
            testCase.evt("m2", "2026-08-18T09:15", "2026-08-18T10:00"),
            testCase.evt("m3", "2026-08-18T09:30", "2026-08-18T10:00"),
            testCase.evt("p1", "2026-08-18T14:00", "2026-08-18T15:00"),
            testCase.evt("p2", "2026-08-18T14:30", "2026-08-18T15:30")
        ];
        const out = layoutPolicy.layout(day);
        compare(testCase.placed(out, "m3").columns, 3);
        compare(testCase.placed(out, "m3").xFrac, 2 / 3);
        compare(testCase.placed(out, "p2").columns, 2);
        compare(testCase.placed(out, "p2").xFrac, 1 / 2);
        compare(testCase.placed(out, "p2").wFrac, 1 / 2);
    }

    function test_probe_the_layout_of_a_deep_cluster_does_not_depend_on_input_order() {
        const day = [
            testCase.evt("a", "2026-08-18T09:00", "2026-08-18T12:00"),
            testCase.evt("b", "2026-08-18T09:10", "2026-08-18T09:40"),
            testCase.evt("c", "2026-08-18T09:20", "2026-08-18T09:45"),
            testCase.evt("d", "2026-08-18T09:30", "2026-08-18T10:30"),
            testCase.evt("e", "2026-08-18T09:50", "2026-08-18T10:00")
        ];
        const forwards = JSON.stringify(layoutPolicy.layout(day));
        const backwards = JSON.stringify(layoutPolicy.layout(day.slice().reverse()));
        compare(backwards, forwards);
        // And laying the same day out twice does not accumulate anything.
        compare(JSON.stringify(layoutPolicy.layout(day)), forwards);
    }

    function test_probe_the_spine_functions_answer_on_their_own() {
        compare(layoutPolicy.absMinutes("2026-08-19T00:00")
                - layoutPolicy.absMinutes("2026-08-18T00:00"), 1440);
        verify(isNaN(layoutPolicy.absMinutes("2026-08-18")));
        verify(isNaN(layoutPolicy.absMinutes(null)));

        const slot = layoutPolicy.slotOf(testCase.evt("x", "2026-08-18T10:00", "2026-08-18T10:05"));
        compare(slot.to - slot.from, 5);
        compare(slot.until - slot.from, 15);   // inflated for collisions only
        compare(layoutPolicy.slotOf(testCase.evt("x", "2026-08-18T11:00", "2026-08-18T10:00")), null);
        compare(layoutPolicy.slotOf(null), null);

        const order = layoutPolicy.sortedSlots([
            testCase.evt("late", "2026-08-18T11:00", "2026-08-18T11:30"),
            testCase.evt("short", "2026-08-18T09:00", "2026-08-18T09:30"),
            testCase.evt("long", "2026-08-18T09:00", "2026-08-18T10:30")
        ]);
        compare(order.map(function (s) { return s.id; }).join(","), "long,short,late");
    }

    function test_probe_a_monday_week_is_not_a_sunday_one() {
        // 2026-08-17 is a Monday. The same event lands in a different column
        // depending only on the week handed in — nothing here knows a firstDay.
        const evt = testCase.evt("wed", "2026-08-19T00:00", "2026-08-20T00:00");
        compare(layoutPolicy.allDayLanes([evt], "2026-08-16")[0].startCol, 3);
        compare(layoutPolicy.allDayLanes([evt], "2026-08-17")[0].startCol, 2);
        // And a span reaching back over the Monday boundary is clipped there.
        const back = layoutPolicy.allDayLanes(
            [testCase.evt("weekend", "2026-08-16T00:00", "2026-08-18T00:00")], "2026-08-17");
        compare(back[0].startCol, 0);
        compare(back[0].span, 1);
        compare(back[0].continuesLeft, true);
    }

    function test_probe_an_all_day_span_ending_at_midnight_does_not_steal_the_next_column() {
        // 23:00 to midnight is Tuesday alone, and the Wednesday event beside it
        // keeps its own lane rather than being pushed down.
        const out = layoutPolicy.allDayLanes([
            testCase.evt("tue", "2026-08-18T23:00", "2026-08-19T00:00"),
            testCase.evt("wed", "2026-08-19T00:00", "2026-08-20T00:00")
        ], "2026-08-16");
        compare(testCase.placed(out, "tue").startCol, 2);
        compare(testCase.placed(out, "tue").span, 1);
        compare(testCase.placed(out, "tue").lane, 0);
        compare(testCase.placed(out, "wed").startCol, 3);
        compare(testCase.placed(out, "wed").lane, 0);
    }

    function test_probe_a_third_lane_opens_only_when_two_are_taken() {
        const out = layoutPolicy.allDayLanes([
            testCase.evt("a", "2026-08-16T00:00", "2026-08-23T00:00"),   // all week
            testCase.evt("b", "2026-08-17T00:00", "2026-08-19T00:00"),   // cols 1-2
            testCase.evt("c", "2026-08-18T00:00", "2026-08-20T00:00"),   // cols 2-3
            testCase.evt("d", "2026-08-20T00:00", "2026-08-22T00:00")    // cols 4-5
        ], "2026-08-16");
        compare(testCase.placed(out, "a").lane, 0);
        compare(testCase.placed(out, "a").span, 7);
        compare(testCase.placed(out, "b").lane, 1);
        compare(testCase.placed(out, "c").lane, 2);
        // D clears B, so it drops back to the first lane that has room.
        compare(testCase.placed(out, "d").startCol, 4);
        compare(testCase.placed(out, "d").lane, 1);
    }

    // A deterministic pile of days, checked against the property the whole file
    // exists to guarantee rather than against numbers written down by hand: two
    // chips that share any time must not share any width. The generator is a
    // fixed LCG, so a failure here is reproducible by seed rather than a
    // once-in-a-while flake.
    function generatedDay(seed, count) {
        let state = seed;
        function next(n) {
            state = (state * 1103515245 + 12345) % 2147483648;
            return Math.floor(state / 65536) % n;
        }
        const day = [];
        for (let i = 0; i < count; i++) {
            const start = 6 * 60 + next(14) * 15 + next(4) * 5;
            const length = [0, 5, 15, 30, 45, 60, 90, 180][next(8)];
            day.push(testCase.evt("g" + i,
                                  layoutPolicy.time.formatStamp("2026-08-18", start),
                                  layoutPolicy.time.formatStamp("2026-08-18", start + length)));
        }
        return day;
    }

    function test_probe_chips_that_share_time_never_share_width() {
        for (let seed = 1; seed <= 40; seed++) {
            const day = testCase.generatedDay(seed, 9);
            const out = layoutPolicy.layout(day);
            const slots = {};
            const rects = {};
            const all = layoutPolicy.sortedSlots(day);
            for (let s = 0; s < all.length; s++)
                slots[all[s].id] = all[s];
            compare(out.length, all.length);
            for (let i = 0; i < out.length; i++) {
                const r = out[i];
                verify(r.column >= 0 && r.column < r.columns);
                verify(r.span >= 1 && r.column + r.span <= r.columns);
                fuzzyCompare(r.xFrac, r.column / r.columns, 1e-9);
                fuzzyCompare(r.wFrac, r.span / r.columns, 1e-9);
                verify(r.xFrac + r.wFrac <= 1 + 1e-9);
                verify(rects[r.id] === undefined);
                rects[r.id] = r;
            }
            for (let a = 0; a < out.length; a++) {
                for (let b = a + 1; b < out.length; b++) {
                    const ra = out[a], rb = out[b];
                    const sa = slots[ra.id], sb = slots[rb.id];
                    const sharesTime = sa.from < sb.until && sb.from < sa.until;
                    if (!sharesTime)
                        continue;
                    const sharesWidth = ra.xFrac < rb.xFrac + rb.wFrac - 1e-9
                                     && rb.xFrac < ra.xFrac + ra.wFrac - 1e-9;
                    verify(!sharesWidth);
                }
            }
        }
    }

    function test_probe_every_cluster_is_as_narrow_as_it_can_be() {
        // `columns` must be the depth of the cluster: no column is opened that
        // some moment does not actually need, or every chip on a busy morning
        // renders narrower than it has to.
        for (let seed = 101; seed <= 130; seed++) {
            const day = testCase.generatedDay(seed, 8);
            const groups = layoutPolicy.slotClusters(day);
            const out = layoutPolicy.layout(day);
            for (let g = 0; g < groups.length; g++) {
                const group = groups[g];
                // The fewest columns a cluster can use is the most events
                // covering any one instant — the depth at a point, not the
                // number overlapping some long event, which can be larger.
                let deepest = 0;
                for (let i = 0; i < group.length; i++) {
                    let deep = 0;
                    for (let j = 0; j < group.length; j++)
                        if (group[j].from <= group[i].from && group[i].from < group[j].until)
                            deep++;
                    deepest = Math.max(deepest, deep);
                }
                const width = testCase.placed(out, group[0].id).columns;
                compare(width, deepest);
            }
        }
    }

    function test_probe_no_two_all_day_spans_in_a_lane_share_a_column() {
        for (let seed = 201; seed <= 230; seed++) {
            let state = seed;
            const week = [];
            for (let i = 0; i < 7; i++) {
                state = (state * 1103515245 + 12345) % 2147483648;
                const first = Math.floor(state / 65536) % 9 - 1;   // -1..7
                state = (state * 1103515245 + 12345) % 2147483648;
                const len = Math.floor(state / 65536) % 4 + 1;
                week.push(testCase.evt("w" + i,
                                       layoutPolicy.time.addDays("2026-08-16", first) + "T00:00",
                                       layoutPolicy.time.addDays("2026-08-16", first + len) + "T00:00"));
            }
            const out = layoutPolicy.allDayLanes(week, "2026-08-16");
            for (let a = 0; a < out.length; a++) {
                verify(out[a].startCol >= 0 && out[a].span >= 1);
                verify(out[a].startCol + out[a].span <= 7);
                for (let b = a + 1; b < out.length; b++) {
                    if (out[a].lane !== out[b].lane)
                        continue;
                    verify(!(out[a].startCol < out[b].startCol + out[b].span
                             && out[b].startCol < out[a].startCol + out[a].span));
                }
            }
        }
    }

    // --- which row an event belongs on ----------------------------------------

    function test_isBanded_takes_allday_and_multiday() {
        // A meeting inside one day stays in the grid.
        verify(!layoutPolicy.isBanded(testCase.evt("a", "2026-08-18T10:00", "2026-08-18T11:30")));

        // The flag is enough on its own.
        const flagged = testCase.evt("b", "2026-08-19T00:00", "2026-08-20T00:00");
        flagged.allDay = true;
        verify(layoutPolicy.isBanded(flagged));

        // And so is crossing days without it — the fixture's "Nordic QML Days",
        // 09:00 Thursday to 17:00 Saturday, which the grid would draw as three
        // unrelated blocks.
        verify(layoutPolicy.isBanded(testCase.evt("c", "2026-08-20T09:00", "2026-08-22T17:00")));
    }

    function test_isBanded_leaves_an_evening_in_the_grid() {
        // 23:00–01:00 touches two days and is still one evening. `spansDays`
        // counts calendar days, so this is the case that says the threshold is
        // days-touched and not hours-long.
        compare(layoutPolicy.eventPolicy.spansDays(
                    testCase.evt("d", "2026-08-18T23:00", "2026-08-19T01:00")), 2);
        verify(layoutPolicy.isBanded(testCase.evt("d", "2026-08-18T23:00", "2026-08-19T01:00")));

        // Whereas one ending exactly at midnight belongs to its own day alone.
        verify(!layoutPolicy.isBanded(testCase.evt("e", "2026-08-18T22:00", "2026-08-19T00:00")));
    }

    function test_band_and_grid_partition_the_list() {
        const timed = testCase.evt("a", "2026-08-18T10:00", "2026-08-18T11:30");
        const long = testCase.evt("c", "2026-08-20T09:00", "2026-08-22T17:00");
        const flagged = testCase.evt("b", "2026-08-19T00:00", "2026-08-20T00:00");
        flagged.allDay = true;
        const all = [timed, flagged, long];

        compare(layoutPolicy.bandEvents(all).map(e => e.id), ["b", "c"]);
        compare(layoutPolicy.gridEvents(all).map(e => e.id), ["a"]);

        // The partition is the point: no event may appear on both rows or on
        // neither, whatever the list holds.
        compare(layoutPolicy.bandEvents(all).length + layoutPolicy.gridEvents(all).length,
                all.length);
        compare(layoutPolicy.bandEvents([]).length, 0);
        compare(layoutPolicy.gridEvents(null).length, 0);
    }

    function test_isCompact_threshold() {
        // 30 minutes is 28px at `hourRow: 56`, and two lines need 34.
        compare(layoutPolicy.compactMinutes, 30);
        verify(layoutPolicy.isCompact(15));
        verify(layoutPolicy.isCompact(30));
        verify(!layoutPolicy.isCompact(31));
        verify(!layoutPolicy.isCompact(90));
        // A duration that is not one must not silently collapse every chip.
        verify(!layoutPolicy.isCompact(NaN));
    }

    // --- what fits inside one chip --------------------------------------------

    function test_a_roomy_hour_long_chip_stacks_title_over_a_full_range() {
        const c = layoutPolicy.chipContent(186, 56, 60);
        compare(c.mode, "stacked");
        verify(c.showTime);
        compare(c.timeForm, "range");
        verify(!c.narrow);
        compare(c.titleSize, 12.5);
        compare(c.bar, 4);
        compare(c.padLeft, 12);   // bar + space2
    }

    function test_a_half_hour_chip_sets_its_time_inline_however_wide_it_is() {
        // 28px of chip has one line in it. Wide, that line carries both; the
        // duration decides, not the height, or a taller `hourRow` would let a
        // 15-minute event sprout a second line its 30-minute neighbour lacks.
        const c = layoutPolicy.chipContent(186, 28, 30);
        compare(c.mode, "inline");
        verify(c.showTime);
        compare(c.timeForm, "start");
    }

    function test_the_packed_tuesday_still_prints_a_start_time() {
        // The critic's case, in its own numbers: three concurrent events in a
        // 1180px window with a 248px sidebar and a 56px gutter share one
        // ~125px column, so each is ~41px wide — and at 90 minutes each is
        // 84px tall. That has to be a title *and* a start time, not `D…`.
        const columnW = (1180 - 248 - 56) / 7;
        const c = layoutPolicy.chipContent(columnW / 3 - 2, 84, 90);
        compare(c.mode, "stacked");
        verify(c.showTime);
        compare(c.timeForm, "start");
        verify(c.narrow);
        compare(c.bar, 3);
        compare(c.padLeft, 6);
        compare(c.titleSize, 11);
    }

    function test_a_tall_chip_spends_its_height_on_wrapping_the_title() {
        compare(layoutPolicy.chipContent(90, 84, 90).titleLines, 3);
        compare(layoutPolicy.chipContent(90, 56, 60).titleLines, 2);
        // A chip with only its two lines of room keeps the second for the time
        // rather than giving it to the title.
        compare(layoutPolicy.chipContent(90, 32, 45).titleLines, 1);
        // Never past three: a chip is a label, not a paragraph.
        compare(layoutPolicy.chipContent(90, 400, 480).titleLines, 3);
    }

    function test_a_chip_too_narrow_to_wrap_between_words_does_not_wrap() {
        // The reversal this floor records: wrapping the packed 38px chip broke
        // `Design review` inside its words — `Desig / n / rev…` — which reads
        // worse than the one elided line it replaced, however much height the
        // chip had going spare.
        compare(layoutPolicy.wrapMinWidth, 72);
        compare(layoutPolicy.chipContent(38, 84, 90).titleLines, 1);
        compare(layoutPolicy.chipContent(71, 84, 90).titleLines, 1);
        compare(layoutPolicy.chipContent(72, 84, 90).titleLines, 3);
    }

    function test_one_line_modes_never_wrap() {
        compare(layoutPolicy.chipContent(186, 28, 30).titleLines, 1);   // inline
        compare(layoutPolicy.chipContent(30, 84, 90).titleLines, 1);    // titleOnly
    }

    function test_a_sliver_too_narrow_for_any_time_gives_the_title_the_chip() {
        const c = layoutPolicy.chipContent(30, 84, 90);
        compare(c.mode, "titleOnly");
        verify(!c.showTime);
    }

    function test_the_two_line_floor_is_a_height_and_it_is_32() {
        compare(layoutPolicy.twoLineMinHeight, 32);
        compare(layoutPolicy.chipContent(60, 31, 45).mode, "titleOnly");
        compare(layoutPolicy.chipContent(60, 32, 45).mode, "stacked");
    }

    function test_the_time_form_steps_down_before_it_disappears() {
        // Three bands, in order: range, start, nothing. A width that lost the
        // range straight to nothing is the bug this replaced.
        compare(layoutPolicy.chipContent(104, 56, 60).timeForm, "range");
        compare(layoutPolicy.chipContent(103, 56, 60).timeForm, "start");
        verify(layoutPolicy.chipContent(36, 56, 60).showTime);
        verify(!layoutPolicy.chipContent(35, 56, 60).showTime);
    }

    function test_chip_content_survives_a_delegate_mid_rebuild() {
        // A delegate asks with `NaN` width for one frame. It must get an
        // answer, not `undefined` — which is a chip that paints nothing.
        const c = layoutPolicy.chipContent(NaN, NaN, NaN);
        compare(c.mode, "titleOnly");
        compare(c.textWidth, 0);
        verify(c.narrow);
    }

    function test_a_title_is_clipped_after_a_whole_word() {
        compare(layoutPolicy.clipTitle("Design review", 7), "Design…");
        compare(layoutPolicy.clipTitle("Design review", 20), "Design review");
        compare(layoutPolicy.clipTitle("Design review", 13), "Design review");
        // The boundary itself: 12 glyphs cannot hold all 13, so back to the space.
        compare(layoutPolicy.clipTitle("Design review", 12), "Design…");
    }

    function test_a_first_word_too_long_for_the_box_falls_back_to_a_hard_cut() {
        // Better a fragment than an empty chip.
        compare(layoutPolicy.clipTitle("Retrospective", 5), "Retr…");
        compare(layoutPolicy.clipTitle("Retrospective", 1), "…");
        compare(layoutPolicy.clipTitle("Retrospective", 0), "");
    }

    function test_clip_title_takes_whatever_a_half_built_chip_hands_it() {
        compare(layoutPolicy.clipTitle("", 8), "");
        // `title` is `var` and not `string` for exactly this: a `string`
        // parameter coerces null into the four-glyph title "null", which is
        // what a chip on a half-built model would then print.
        compare(layoutPolicy.clipTitle(null, 8), "");
        compare(layoutPolicy.clipTitle(undefined, 8), "");
        compare(layoutPolicy.clipTitle("Standup", NaN), "");
        // Leading space trimmed first, or the cut lands inside the padding.
        compare(layoutPolicy.clipTitle(" Standup meeting", 3), "St…");
    }
}
