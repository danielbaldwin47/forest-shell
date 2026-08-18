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

    function test_the_packed_tuesday_is_a_cascade_and_not_three_slivers() {
        // The critic's case, in its own numbers and with the answer it got the
        // second time. Three concurrent events in a 1180px window with a 248px
        // sidebar and a 56px gutter share one ~123px column. Divided equally
        // that is a 39px chip; the picture came back as three slivers reading
        // one word per line. Divided by `minLaneWidth` it is a cascade, and the
        // widths below are what the surface actually draws.
        const columnW = (1180 - 248 - 56) / 7;
        const day = [
            evt("a", "2026-08-18T10:00", "2026-08-18T11:30"),
            evt("b", "2026-08-18T10:30", "2026-08-18T12:00"),
            evt("c", "2026-08-18T11:00", "2026-08-18T12:30")
        ];
        const placed = layoutPolicy.layout(day, columnW - 4);
        const byId = {};
        for (let i = 0; i < placed.length; i++)
            byId[placed[i].id] = placed[i];

        // One lane, three depths: painted in start order, each over the last.
        compare(byId.a.columns, 1);
        compare(byId.a.depth, 0);
        compare(byId.b.depth, 1);
        compare(byId.c.depth, 2);

        // Every chip is wide enough to be a chip. 64px is the floor and the
        // narrowest of the three clears it with the wider `cascadeFrac` step
        // still in hand — the step buys the picture its three visible lanes and
        // the last chip pays about ten pixels for them.
        const track = columnW - 2;
        for (const id of ["a", "b", "c"])
            verify(byId[id].wFrac * track >= layoutPolicy.minLaneWidth - 0.001);
        verify(byId.c.wFrac * track >= 72);
        // And the steps are far enough apart to read as lanes rather than as one
        // chip with two scratches down it: 0.20 of a 123px track is 24px, which
        // is a bar, its fill and a margin.
        verify((byId.b.xFrac - byId.a.xFrac) * track >= 20);
        verify((byId.c.xFrac - byId.b.xFrac) * track >= 20);

        // And what each of them prints. The last and narrowest is the test:
        // at 90px it is `narrow`, never `tight`, and it stacks a wrapped title
        // over a start time with the same inset on both sides.
        const c = layoutPolicy.chipContent(byId.c.wFrac * track, 84, 90);
        compare(c.mode, "stacked");
        verify(c.showTime);
        compare(c.timeForm, "start");
        verify(c.narrow);
        verify(!c.tight);
        compare(c.bar, 3);
        compare(c.padLeft, 9);
        compare(c.padRight, 6);
        compare(c.titleSize, 11);
        // ~59px of box at pt(11) holds `Pairing:` / `grid` / `packing` over
        // three lines, where the 39px sliver broke inside `packing` and still
        // elided.
        verify(c.textWidth >= 56);
        verify(c.titleLines > 1);
    }

    function test_a_covered_chip_is_told_how_much_box_it_still_has() {
        // The stagger buys a title line, not a chip. `Design review` is 90
        // minutes tall and covered 30 minutes in, so 60 of its 84 pixels are
        // behind another card — and the capture showed its `10:00 – 11:30 AM`
        // sliced in half by that card's top edge. The layout reports the clear
        // band; the content rule spends it.
        const day = [
            evt("a", "2026-08-18T10:00", "2026-08-18T11:30"),
            evt("b", "2026-08-18T10:30", "2026-08-18T12:00"),
            evt("c", "2026-08-18T11:00", "2026-08-18T12:30")
        ];
        const placed = layoutPolicy.layout(day, 119);
        const byId = {};
        for (let i = 0; i < placed.length; i++)
            byId[placed[i].id] = placed[i];
        compare(byId.a.clearMinutes, 30);
        compare(byId.b.clearMinutes, 30);
        // Nothing is drawn over the last one, so it keeps its whole height.
        verify(!isFinite(byId.c.clearMinutes));

        // 30 minutes at `hourRow: 56` is 28px, which is under the two-line
        // floor at the ordinary type — so the banner tier shrinks the type until
        // two whole lines fit it, and the covered chip states its title *and*
        // its time above the card that covers it. This is the case the picture
        // was lost on: one line meant the title alone, and two of three chips in
        // a cascade said nothing about when they were.
        const covered = layoutPolicy.chipContent(119, 84, 90, 28);
        compare(covered.mode, "stacked");
        verify(covered.banner);
        verify(covered.showTime);
        compare(covered.titleLines, 1);
        compare(covered.titleSize, layoutPolicy.bannerTitleSize);
        compare(covered.timeSize, layoutPolicy.bannerTimeSize);
        // And the two lines it promises actually fit the band it was given.
        verify(covered.padTop
               + Math.round(covered.titleSize * layoutPolicy.lineFactor)
               + Math.round(covered.timeSize * layoutPolicy.lineFactor) <= 28);
        // One pixel under the banner floor there is no honest second line.
        compare(layoutPolicy.chipContent(119, 84, 90, 25).mode, "inline");
        verify(!layoutPolicy.chipContent(119, 84, 90, 25).banner);
        // Same chip, nothing over it — two lines, as before.
        compare(layoutPolicy.chipContent(119, 84, 90).mode, "stacked");
        compare(layoutPolicy.chipContent(119, 84, 90, Infinity).mode, "stacked");
        // A clear band larger than the chip cannot invent height.
        compare(layoutPolicy.chipContent(119, 32, 45, 400).mode,
                layoutPolicy.chipContent(119, 32, 45).mode);
    }

    function test_an_inline_time_is_never_bought_with_an_ellipsis() {
        // `Standup` beside `9:00 AM` in a 99px box: 46 + 4 + 46 = 96, and both
        // print whole.
        verify(layoutPolicy.inlineTimeFits(99, 46, 46, 4));
        // `Design review` beside `10:00 AM` in the same box: 85 + 4 + 52 = 141,
        // so the time goes and the title keeps all 99 — `Design review` rather
        // than `Desig… 10:00 AM`.
        verify(!layoutPolicy.inlineTimeFits(99, 85, 52, 4));
        // Exactly filling the box is fitting.
        verify(layoutPolicy.inlineTimeFits(100, 50, 46, 4));
        verify(!layoutPolicy.inlineTimeFits(99, 50, 46, 4));
        // A time with no width is not a time.
        verify(!layoutPolicy.inlineTimeFits(99, 10, 0, 4));
        // And a delegate mid-rebuild hands NaN rather than a number.
        verify(!layoutPolicy.inlineTimeFits(NaN, NaN, NaN, NaN));
    }

    function test_the_text_inset_is_the_same_on_both_sides_at_every_tier() {
        // `10:00 AM` finishing exactly on the fill boundary, hard against the
        // next chip's rail, was the second thing the capture came back with.
        // The right pad is the left gap now — at every tier, so no width can
        // reintroduce the asymmetry.
        for (const w of [39, 59, 90, 119, 186, 400]) {
            const c = layoutPolicy.chipContent(w, 84, 90);
            compare(c.padRight, c.padLeft - c.bar);
            verify(c.padRight >= 3);
        }
    }

    function test_the_two_way_split_stays_in_the_roomier_tier() {
        // Half a 123px column is ~59, which must *not* take the tight tier's
        // type: the step exists for the three-way case, and applying it to the
        // two-way one would shrink the common overlap to fix the rare one.
        const c = layoutPolicy.chipContent(59, 84, 90);
        verify(c.narrow);
        verify(!c.tight);
        compare(c.titleSize, 11);
        compare(c.bar, 3);
        compare(c.padLeft, 9);
        // 56 is the boundary and it is inclusive on the roomier side.
        verify(!layoutPolicy.chipContent(56, 84, 90).tight);
        verify(layoutPolicy.chipContent(55, 84, 90).tight);
    }

    function test_a_start_time_keeps_its_meridiem_wherever_it_fits() {
        // One clock grammar per surface. The start-only time is the range's own
        // first token; the only thing width may take off it is the meridiem,
        // and only where `10:30 AM` (48px at 11) would not fit the text box.
        compare(layoutPolicy.meridiemMinTextWidth, 30);
        // Two-way split: 59px of chip, 44px of text box — meridiem stays.
        verify(layoutPolicy.chipContent(59, 84, 90).timeMeridiem);
        // Three-way split: 39px of chip, 31px of text box — and the meridiem
        // stays here too, which is the change. A grid that printed
        // `1:00 – 2:00 PM`, `9:00 AM` and a bare `10:00` within a centimetre of
        // each other was running three clock notations at once; two is the
        // floor, and the packed chip is held to the second rather than given a
        // third of its own.
        verify(layoutPolicy.chipContent(39, 84, 90).timeMeridiem);
        // The floor still bites somewhere, or it is not a floor: a 33px chip is
        // under the time rule entirely and prints no time to hang one off.
        verify(!layoutPolicy.chipContent(33, 84, 90).showTime);
        // A range already carries its own meridiem, whatever the box measures.
        const wide = layoutPolicy.chipContent(186, 56, 60);
        compare(wide.timeForm, "range");
        verify(wide.timeMeridiem);
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

    function test_a_tight_chip_gets_a_fourth_line_because_a_line_is_a_word() {
        // At 33px of box a line holds one word, so three lines is a three-word
        // budget: `Pairing: grid packing` came out `Pairing: / grid / pack…` on
        // the capture with height to spare. Four lines prints the title.
        compare(layoutPolicy.maxTightTitleLines, 4);
        compare(layoutPolicy.chipContent(39, 84, 90).titleLines, 4);
        // The roomy tier keeps its three: there a line is a phrase.
        compare(layoutPolicy.chipContent(186, 400, 480).titleLines, 3);
        // Height still decides first — a fourth line is only offered where one
        // fits, never taken out of the time's row.
        compare(layoutPolicy.chipContent(39, 56, 60).titleLines, 3);
    }

    function test_the_wrap_floor_is_a_text_box_and_not_a_chip() {
        // The reversal, and the reversal of the reversal. Wrapping the packed
        // chip at pt(11) broke `Design review` inside its words — `Desig / n /
        // rev…` — so wrapping was first gated on chip width. But what was too
        // small was the type, not the chip: at the tight tier's 9.5 the same
        // 33px box holds whole words, so the gate belongs on the box measured
        // against the type that will be set in it.
        compare(layoutPolicy.wrapMinTextWidth, 28);
        // 31px of box at the tight tier — wraps. (35 before the inset became
        // symmetric; the two pixels came off the right, where they were the
        // difference between a time and a smear.)
        compare(layoutPolicy.chipContent(39, 84, 90).textWidth, 31);
        verify(layoutPolicy.chipContent(39, 84, 90).titleLines > 1);
        // And the narrowest chip that still prints a time — 36px, a 28px box —
        // wraps too, which is what says the floor is not silently disabling the
        // packed case it was written for.
        compare(layoutPolicy.chipContent(36, 84, 90).textWidth, 28);
        verify(layoutPolicy.chipContent(36, 84, 90).titleLines > 1);
        // One pixel narrower is under the time floor entirely — title only, one
        // line, and no wrap to argue about.
        compare(layoutPolicy.chipContent(35, 84, 90).titleLines, 1);
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
        compare(layoutPolicy.chipContent(60, 32, 45).mode, "stacked");
        // Between the banner floor and the two-line floor a second line is still
        // reachable, at the banner's smaller type.
        verify(layoutPolicy.chipContent(60, 31, 45).banner);
        compare(layoutPolicy.chipContent(60, 31, 45).mode, "stacked");
        // Under the banner floor there is no second line to be had, and a 60px
        // chip is too narrow to set the time inline either.
        compare(layoutPolicy.chipContent(60, 25, 45).mode, "titleOnly");
    }

    function test_the_time_form_steps_down_before_it_disappears() {
        // Three bands, in order: range, start, nothing. A width that lost the
        // range straight to nothing is the bug this replaced.
        compare(layoutPolicy.timeRangeMinWidth, 112);
        compare(layoutPolicy.chipContent(112, 56, 60).timeForm, "range");
        compare(layoutPolicy.chipContent(111, 56, 60).timeForm, "start");
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
        // The boundary itself: 12 glyphs cannot hold all 13, and the space is
        // six glyphs back — past `wordCutBudget`, so the title is handed back
        // whole for the surface to elide pixel-exactly rather than cut here and
        // leave half the box empty.
        compare(layoutPolicy.clipTitle("Design review", 12), "Design review");
        // 8 glyphs: the space is two back, which is the cut this rule exists for.
        compare(layoutPolicy.clipTitle("Design review", 8), "Design…");
    }

    function test_a_word_cut_that_wastes_the_box_is_not_made() {
        compare(layoutPolicy.wordCutBudget, 3);
        // `Coffee with Opal` in a fifteen-glyph box cut to `Coffee with…` and
        // left a quarter of a full-width chip blank — the packed-column rule
        // firing on a chip that was not packed. Four glyphs back is past the
        // budget, so the surface elides instead and fills the box.
        compare(layoutPolicy.clipTitle("Coffee with Opal", 15), "Coffee with Opal");
        // Inside the budget it still cuts at the word, which is what keeps a
        // genuinely packed chip from printing `D…`.
        compare(layoutPolicy.clipTitle("Coffee with Opal", 14), "Coffee with…");
        compare(layoutPolicy.clipTitle("Coffee with Opal", 13), "Coffee with…");
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

    // --- the minimum lane width ----------------------------------------------

    function test_a_column_wide_enough_divides_equally_and_nothing_cascades() {
        // The rule is a floor, not a mode: wherever the lanes clear it, the
        // layout is exactly the side-by-side one it has always been.
        const day = [
            evt("a", "2026-08-18T10:00", "2026-08-18T11:30"),
            evt("b", "2026-08-18T10:30", "2026-08-18T12:00"),
            evt("c", "2026-08-18T11:00", "2026-08-18T12:30")
        ];
        // 210px is a day view's column, and three lanes of 70 clear the floor.
        const placed = layoutPolicy.layout(day, 210);
        compare(placed.length, 3);
        for (let i = 0; i < placed.length; i++) {
            compare(placed[i].columns, 3);
            compare(placed[i].depth, 0);
            fuzzyCompare(placed[i].wFrac, 1 / 3, 0.0001);
            fuzzyCompare(placed[i].xFrac, i / 3, 0.0001);
        }
    }

    function test_a_cascade_needs_its_starts_staggered_or_it_is_occlusion() {
        // The cascade's whole claim is that the chip covering another starts
        // lower than that other one's title line. Where the starts are on top
        // of each other the claim is false and the division comes back, even
        // though the lanes are under the floor — a narrow chip you can read is
        // worth more than a wide one hidden under a neighbour.
        compare(layoutPolicy.cascadeClearMinutes, 20);
        const together = [
            evt("a", "2026-08-18T10:00", "2026-08-18T11:30"),
            evt("b", "2026-08-18T10:10", "2026-08-18T12:00")
        ];
        verify(!layoutPolicy.cascadeIsLegible(layoutPolicy.sortedSlots(together)));
        const split = layoutPolicy.layout(together, 119);
        compare(split[0].columns, 2);
        compare(split[0].depth, 0);
        compare(split[1].depth, 0);

        // Twenty minutes apart is the boundary, and it cascades.
        const staggered = [
            evt("a", "2026-08-18T10:00", "2026-08-18T11:30"),
            evt("b", "2026-08-18T10:20", "2026-08-18T12:00")
        ];
        verify(layoutPolicy.cascadeIsLegible(layoutPolicy.sortedSlots(staggered)));
        compare(layoutPolicy.layout(staggered, 119)[1].depth, 1);

        // But only while a lane is still worth having. Three simultaneous
        // events in a week column divide to 39px, which prints nothing, so the
        // cascade is taken anyway — the least-bad of two bad arrangements.
        compare(layoutPolicy.minSplitWidth, 40);
        const crowd = [
            evt("a", "2026-08-18T10:00", "2026-08-18T12:00"),
            evt("b", "2026-08-18T10:00", "2026-08-18T12:00"),
            evt("c", "2026-08-18T10:00", "2026-08-18T12:00")
        ];
        compare(layoutPolicy.layout(crowd, 119)[2].depth, 2);
    }

    function test_laneCap_is_the_column_over_the_floor() {
        compare(layoutPolicy.minLaneWidth, 64);
        compare(layoutPolicy.laneCap(210), 3);
        compare(layoutPolicy.laneCap(191), 2);
        compare(layoutPolicy.laneCap(127), 1);
        // A cap of zero is "the caller did not measure", not "no lanes".
        compare(layoutPolicy.laneCap(0), 0);
        compare(layoutPolicy.laneCap(NaN), 0);
        // Never zero lanes for a column that exists, however thin.
        compare(layoutPolicy.laneCap(4), 1);
    }

    function test_a_fifth_concurrent_event_cascades_instead_of_shrinking() {
        // Five at once in a 122px column is a 24px equal lane, which prints one
        // glyph — and it prints one glyph on the four beside it too, which is
        // the part that makes the floor worth having. Three lanes stay, and the
        // overflow indents into the last one and runs to the right edge.
        const day = [
            evt("a", "2026-08-18T10:00", "2026-08-18T12:00"),
            evt("b", "2026-08-18T10:05", "2026-08-18T12:00"),
            evt("c", "2026-08-18T10:10", "2026-08-18T12:00"),
            evt("d", "2026-08-18T10:15", "2026-08-18T12:00"),
            evt("e", "2026-08-18T10:20", "2026-08-18T12:00")
        ];
        const placed = layoutPolicy.layout(day, 122);
        const byId = {};
        for (let i = 0; i < placed.length; i++)
            byId[placed[i].id] = placed[i];

        // One lane and a four-step cascade: 122px does not hold two lanes over
        // `minLaneWidth`, and five minutes apart is under `cascadeClearMinutes`
        // — but a 24px equal lane is under `minSplitWidth` too, so the cascade
        // is still the arrangement taken.
        compare(byId.a.columns, 1);
        compare(byId.a.depth, 0);
        compare(byId.b.depth, 1);
        compare(byId.c.depth, 2);
        compare(byId.d.depth, 3);
        compare(byId.e.depth, 4);
        // Every cascaded chip still clears the floor it was cascaded to keep.
        verify(byId.c.wFrac * 122 >= layoutPolicy.minLaneWidth - 0.001);
        verify(byId.d.wFrac * 122 >= layoutPolicy.minLaneWidth - 0.001);
        verify(byId.e.wFrac * 122 >= layoutPolicy.minLaneWidth - 0.001);
        // Indented, in order, by a step nobody can mistake for a seam, and each
        // runs to the column's right edge.
        verify(byId.d.xFrac - byId.c.xFrac >= layoutPolicy.minCascadeFrac);
        verify(byId.e.xFrac - byId.d.xFrac >= layoutPolicy.minCascadeFrac);
        fuzzyCompare(byId.d.xFrac + byId.d.wFrac, 1, 0.0001);
        fuzzyCompare(byId.e.xFrac + byId.e.wFrac, 1, 0.0001);
    }

    function test_the_cascade_never_indents_past_the_floor() {
        // Eight at once: the indent would run off the right edge long before
        // the eighth, so it clamps and the last chips stack at the same x
        // rather than collapsing to nothing.
        const day = [];
        for (let i = 0; i < 8; i++)
            day.push(evt("e" + i, "2026-08-18T10:00", "2026-08-18T12:00"));
        const placed = layoutPolicy.layout(day, 122);
        // One lane and a seven-step cascade: two lanes would have left the
        // steps 4px apart, which is a seam rather than a stack.
        compare(placed[0].columns, 1);
        for (let p = 0; p < placed.length; p++) {
            verify(placed[p].wFrac * 122 >= layoutPolicy.minLaneWidth - 0.001);
            verify(placed[p].xFrac >= 0);
            verify(placed[p].xFrac + placed[p].wFrac <= 1.0001);
            if (p > 0)
                verify(placed[p].xFrac - placed[p - 1].xFrac
                       >= layoutPolicy.minCascadeFrac);
        }
    }

    function test_no_width_means_no_cap_and_the_old_behaviour() {
        // Every caller that never measured a column keeps the layout it had.
        const day = [];
        for (let i = 0; i < 5; i++)
            day.push(evt("e" + i, "2026-08-18T10:00", "2026-08-18T12:00"));
        const placed = layoutPolicy.layout(day);
        for (let p = 0; p < placed.length; p++) {
            compare(placed[p].columns, 5);
            compare(placed[p].depth, 0);
            fuzzyCompare(placed[p].wFrac, 0.2, 0.0001);
        }
    }

    // --- the width a day column buys ------------------------------------------

    function test_a_wide_one_line_chip_prints_the_whole_range_inline() {
        // A half-hour meeting is one line whatever its width. In a week column
        // that line can only afford the start; in a day column it prints the
        // range, which is the day view earning its width.
        const packed = layoutPolicy.chipContent(186, 28, 30);
        compare(packed.mode, "inline");
        compare(packed.timeForm, "start");

        const wide = layoutPolicy.chipContent(560, 28, 30);
        compare(wide.mode, "inline");
        compare(wide.timeForm, "range");

        // The boundary is the boundary, and nothing either side of it moves.
        compare(layoutPolicy.chipContent(239, 28, 30).timeForm, "start");
        compare(layoutPolicy.chipContent(240, 28, 30).timeForm, "range");
    }

    function test_the_guest_line_needs_both_width_and_height() {
        // Wide and tall: guests.
        verify(layoutPolicy.chipContent(560, 84, 90).showGuests);
        // Wide and short: a 45-minute chip keeps title over time and nothing
        // else, because a third line would come out of the second.
        verify(!layoutPolicy.chipContent(560, 42, 45).showGuests);
        verify(!layoutPolicy.chipContent(560, 47, 90).showGuests);
        verify(layoutPolicy.chipContent(560, 48, 90).showGuests);
        // Tall but narrow: every week column, at every packing.
        verify(!layoutPolicy.chipContent(123, 84, 90).showGuests);
        verify(!layoutPolicy.chipContent(189, 84, 90).showGuests);
        verify(layoutPolicy.chipContent(190, 84, 90).showGuests);
        // A one-line chip has no line to spare however wide it is.
        verify(!layoutPolicy.chipContent(560, 28, 30).showGuests);
    }

    function test_the_guest_line_is_charged_against_the_title_wrap() {
        // The same box, with and without a guest line: the title may not wrap
        // into a row already promised to somebody else.
        const withGuests = layoutPolicy.chipContent(560, 84, 90);
        const without = layoutPolicy.chipContent(189, 84, 90);
        verify(withGuests.showGuests);
        verify(!without.showGuests);
        verify(withGuests.titleLines < without.titleLines);
        compare(withGuests.guestSize, withGuests.timeSize);
    }

    // --- how wide an all-day bar is actually drawn -----------------------------

    function test_a_band_bar_that_ends_inside_the_run_takes_its_natural_width() {
        // The day view: one column of 870px, one all-day event, and a bar the
        // width of its own title rather than a slab of tint.
        compare(layoutPolicy.bandBarWidth(870, 160, false), 160);
        // A week column is narrower than the title, so the track still wins and
        // the rule is invisible where it always was.
        compare(layoutPolicy.bandBarWidth(123, 160, false), 123);
    }

    function test_a_band_bar_that_runs_off_an_edge_stays_flush() {
        // The cut edge against the frame is what says it carries on; a natural
        // width floating clear of that edge would say the opposite.
        compare(layoutPolicy.bandBarWidth(870, 160, true), 870);
    }

    function test_a_band_bar_never_shrinks_below_a_swatch() {
        compare(layoutPolicy.bandBarWidth(870, 10, false), layoutPolicy.bandBarMinWidth);
        // Unless the track itself is that small, in which case the track wins.
        compare(layoutPolicy.bandBarWidth(40, 10, false), 40);
        // Nonsense in, zero out rather than NaN through to a width binding.
        compare(layoutPolicy.bandBarWidth(NaN, 160, false), 0);
    }

    /// A span across more than one column fills its track whatever it measures.
    /// "Nordic QML Days" — Thursday to Saturday — was drawn 130px wide inside
    /// Thursday, so a three-day conference read as a Thursday appointment and
    /// the two days it covered read as empty. The width *is* the answer to
    /// which days, so on a multi-column span it stops being negotiable.
    function test_band_bar_spanning_days_fills_its_track() {
        compare(layoutPolicy.bandBarWidth(540, 130, false, 3), 540);
        compare(layoutPolicy.bandBarWidth(540, 130, false, 2), 540);
        // One column keeps the natural-width rule that retired the day view's
        // 870px slab, and so does an absent or nonsense column count.
        compare(layoutPolicy.bandBarWidth(870, 160, false, 1), 160);
        compare(layoutPolicy.bandBarWidth(870, 160, false), 160);
        compare(layoutPolicy.bandBarWidth(870, 160, false, NaN), 160);
        compare(layoutPolicy.bandBarWidth(870, 160, false, undefined), 160);
    }

    // --- the column's own margins ----------------------------------------------

    function test_a_week_column_keeps_its_hairline_inset() {
        // Nothing about the week view moves: 123px is under `wideColumnWidth`,
        // so the inset is the base the surface passes in.
        compare(layoutPolicy.columnInset(123, 2), 2);
        compare(layoutPolicy.columnInset(319, 2), 2);
        // And the track is what it always was — width less the inset, plus the
        // gap every chip pays back off its right edge.
        compare(layoutPolicy.columnTrack(123, 2, 2), 121);
    }

    function test_a_day_column_pays_for_a_real_margin() {
        compare(layoutPolicy.columnInset(320, 2), layoutPolicy.wideColumnInset);
        compare(layoutPolicy.columnInset(1300, 2), 8);
        // Symmetry is the whole point: the last chip's right edge lands the
        // same distance from the column's right as the first chip's left edge
        // does from its left.
        const inset = layoutPolicy.columnInset(1300, 2);
        const track = layoutPolicy.columnTrack(1300, inset, 2);
        const rightEdge = inset + track - 2;
        compare(1300 - rightEdge, inset);
    }

    function test_column_metrics_survive_nonsense() {
        compare(layoutPolicy.columnInset(NaN, 2), 2);
        compare(layoutPolicy.columnInset(1300, NaN), 8);
        compare(layoutPolicy.columnTrack(NaN, 2, 2), 0);
        compare(layoutPolicy.columnTrack(4, 8, 2), 0);
    }

    // --- the gutter between packed lanes ---------------------------------------

    function test_a_week_lane_keeps_the_two_pixels_it_had() {
        // A 121px track split three ways is a 40px lane; 3% of it rounds to
        // one, and the floor takes it back to the gap the week already ships.
        compare(layoutPolicy.laneGap(121 / 3, 2), 2);
        compare(layoutPolicy.laneGap(121, 2), 4);
    }

    function test_a_day_lane_opens_a_gutter_wide_enough_to_see() {
        // The day capture: a 1300px track, three concurrent meetings, 433px
        // each. Two pixels there is half a percent of a lane and reads as an
        // occlusion; the cap is what makes three chips read as three.
        const lane = 1300 / 3;
        compare(layoutPolicy.laneGap(lane, 2), layoutPolicy.maxLaneGap);
        verify(layoutPolicy.laneGap(lane, 2) > layoutPolicy.laneGap(40, 2));
    }

    function test_the_gutter_is_never_tighter_than_the_base() {
        compare(layoutPolicy.laneGap(10, 4), 4);
        compare(layoutPolicy.laneGap(0, 2), 2);
        compare(layoutPolicy.laneGap(NaN, 2), 2);
        compare(layoutPolicy.laneGap(-40, 2), 2);
        compare(layoutPolicy.laneGap(400, NaN), 12);
    }

    // --- what a day comes to ---------------------------------------------------

    function test_a_day_load_counts_events_and_minutes() {
        const load = layoutPolicy.dayLoad([
            { id: "a", start: "2026-08-18T10:00", end: "2026-08-18T11:30" },
            { id: "b", start: "2026-08-18T10:30", end: "2026-08-18T12:00" },
            { id: "c", start: "2026-08-18T15:00", end: "2026-08-18T15:45" }
        ]);
        compare(load.count, 3);
        // Overlaps count twice: three concurrent meetings are three
        // obligations, and merging them would be a softer claim than the grid
        // beneath the header makes.
        compare(load.minutes, 90 + 90 + 45);
    }

    function test_the_all_day_band_counts_but_books_no_time() {
        const timed = [
            { id: "a", start: "2026-08-18T10:00", end: "2026-08-18T11:30" }
        ];
        const load = layoutPolicy.dayLoad(timed, 2);
        // Both chips in the band are on the page, so both are in the count.
        compare(load.count, 3);
        // And neither is eight hours of anything.
        compare(load.minutes, 90);
        compare(layoutPolicy.dayLoad(timed, 0).count, 1);
        compare(layoutPolicy.dayLoad(timed, null).count, 1);
        compare(layoutPolicy.dayLoad(timed, -4).count, 1);
    }

    function test_a_day_load_ignores_what_is_not_an_event() {
        const load = layoutPolicy.dayLoad([
            null,
            { id: "a", start: "2026-08-18T09:00", end: "2026-08-18T09:30" },
            { id: "bad", start: "nonsense", end: "2026-08-18T10:00" }
        ]);
        compare(load.count, 1);
        compare(load.minutes, 30);
        compare(layoutPolicy.dayLoad(null).count, 0);
        compare(layoutPolicy.dayLoad(null).minutes, 0);
    }

    function test_a_day_load_label_says_it_once() {
        compare(layoutPolicy.dayLoadLabel({ count: 4, minutes: 300 }, "5h"),
                "4 events · 5h");
        compare(layoutPolicy.dayLoadLabel({ count: 1, minutes: 45 }, "45m"),
                "1 event · 45m");
        // No duration to print is a count on its own, not a dangling separator.
        compare(layoutPolicy.dayLoadLabel({ count: 2, minutes: 0 }, ""), "2 events");
        // An empty day says nothing rather than "0 events".
        compare(layoutPolicy.dayLoadLabel({ count: 0, minutes: 0 }, "0m"), "");
        compare(layoutPolicy.dayLoadLabel(null, "5h"), "");
    }

    // --- the resize grip --------------------------------------------------------

    function test_only_a_chip_with_a_clear_bottom_edge_offers_a_grip() {
        verify(layoutPolicy.showsGrip(84));
        verify(layoutPolicy.showsGrip(layoutPolicy.gripMinHeight));
        // A half-hour chip is 28px: its one line of type is the whole box.
        verify(!layoutPolicy.showsGrip(28));
        // And a tall chip mostly hidden under a cascaded neighbour has no
        // bottom edge to hand anybody, whatever its own height says.
        verify(!layoutPolicy.showsGrip(84, 28));
        verify(layoutPolicy.showsGrip(84, 60));
        verify(!layoutPolicy.showsGrip(NaN));
    }

}
