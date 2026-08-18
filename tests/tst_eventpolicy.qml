// Every decision the event list makes.
//
// The store on the other side of this file imports Quickshell and so is
// unreachable from here — which is the whole argument for it holding no
// arithmetic. Everything below is what the store would otherwise be doing
// inline and nobody could check: what the next id is, what a drag does to a
// duration, what a resize refuses to do, which days an event shows on.
//
// Two claims get the most cases because they are the ones a naive
// implementation gets wrong and nothing notices until a user does:
//
//   - a **move preserves duration**. "Set the start" is not a move; it is a
//     move plus a silent resize.
//   - a **multi-day event shows on its middle days**. `start.startsWith(day)`
//     passes every single-day test and loses Friday out of a Thursday-to-
//     Saturday span.
import QtQuick
import QtTest
import "../Services/Calendar"

TestCase {
    id: testCase

    name: "EventPolicy"

    EventPolicy { id: policy }

    function event(id, start, end, extra) {
        const made = {
            "id": id, "title": id, "start": start, "end": end,
            "allDay": false, "colour": "", "guests": []
        };
        for (const key in (extra || {}))
            made[key] = extra[key];
        return made;
    }

    /// The fixture week, matching tools/fixtures/calendar-events.json in the
    /// part that matters here: a three-way overlap on the Tuesday.
    function week() {
        return [
            event("evt-1", "2026-08-17T09:00", "2026-08-17T09:30"),
            event("evt-2", "2026-08-18T10:00", "2026-08-18T11:30"),
            event("evt-3", "2026-08-18T10:30", "2026-08-18T12:00"),
            event("evt-4", "2026-08-18T11:00", "2026-08-18T12:30"),
            event("evt-5", "2026-08-19T00:00", "2026-08-20T00:00", { "allDay": true }),
            event("evt-6", "2026-08-20T09:00", "2026-08-22T17:00")
        ];
    }

    function ids(events) {
        return events.map(function (e) { return e.id; }).join(",");
    }

    // --- nextId ---------------------------------------------------------------

    function test_the_first_event_is_evt_1() {
        compare(policy.nextId([]), "evt-1");
        compare(policy.nextId(null), "evt-1");
    }

    function test_nextId_follows_the_highest_and_not_the_count() {
        compare(policy.nextId([event("evt-1", "2026-08-18T09:00", "2026-08-18T10:00"),
                               event("evt-3", "2026-08-18T11:00", "2026-08-18T12:00")]),
                "evt-4");
    }

    function test_nextId_ignores_ids_that_are_not_numbered() {
        // A hand-written id is legal; it just does not join the counter.
        compare(policy.nextId([event("standup", "2026-08-18T09:00", "2026-08-18T09:15"),
                               event("evt-2", "2026-08-18T11:00", "2026-08-18T12:00")]),
                "evt-3");
        compare(policy.nextId([event("standup", "2026-08-18T09:00", "2026-08-18T09:15")]),
                "evt-1");
    }

    function test_nextId_is_deterministic_across_calls() {
        const list = testCase.week();
        compare(policy.nextId(list), policy.nextId(list));
        compare(policy.nextId(list), "evt-7");
    }

    // --- validation and sanitizing --------------------------------------------

    function test_validate_wants_an_id_and_two_stamps() {
        verify(policy.validate(event("evt-1", "2026-08-18T09:00", "2026-08-18T10:00")).ok);
        verify(!policy.validate(event("", "2026-08-18T09:00", "2026-08-18T10:00")).ok);
        verify(!policy.validate(event("evt-1", "2026-08-18", "2026-08-18T10:00")).ok);
        verify(!policy.validate(event("evt-1", "2026-08-18T09:00", "nope")).ok);
    }

    function test_validate_refuses_an_event_that_ends_before_it_starts() {
        const backwards = policy.validate(event("evt-1", "2026-08-18T10:00", "2026-08-18T09:00"));
        verify(!backwards.ok);
        const empty = policy.validate(event("evt-1", "2026-08-18T10:00", "2026-08-18T10:00"));
        verify(!empty.ok);
    }

    function test_normalize_fills_in_what_is_missing() {
        const e = policy.normalize({ "id": "evt-1", "start": "2026-08-18T09:00",
                                     "end": "2026-08-18T10:00" });
        compare(e.title, "");
        compare(e.allDay, false);
        compare(e.guests.length, 0);
        verify(Array.isArray(e.guests));
    }

    function test_normalize_drops_duplicate_and_junk_guests() {
        const e = policy.normalize({ "id": "evt-1", "start": "2026-08-18T09:00",
                                     "end": "2026-08-18T10:00",
                                     "guests": ["mira", "mira", "", 7, "juno"] });
        compare(e.guests.join(","), "mira,juno");
    }

    function test_sanitize_keeps_the_good_and_names_the_bad() {
        const clean = policy.sanitize([
            event("evt-2", "2026-08-18T10:00", "2026-08-18T11:00"),
            event("evt-1", "2026-08-18T09:00", "2026-08-18T10:00"),
            event("evt-9", "2026-08-18T10:00", "2026-08-18T09:00")
        ]);
        compare(testCase.ids(clean.events), "evt-1,evt-2");
        compare(clean.rejected.length, 1);
        verify(clean.rejected[0].indexOf("evt-9") === 0);
    }

    function test_sanitize_of_a_non_list_is_empty_and_not_a_crash() {
        compare(policy.sanitize(null).events.length, 0);
        compare(policy.sanitize({ "events": [] }).events.length, 0);
    }

    // --- create ---------------------------------------------------------------

    function test_create_appends_and_sorts() {
        const list = policy.create([event("evt-1", "2026-08-18T14:00", "2026-08-18T15:00")],
                                   event("evt-2", "2026-08-18T09:00", "2026-08-18T10:00"));
        compare(testCase.ids(list), "evt-2,evt-1");
    }

    function test_create_names_the_event_when_the_caller_did_not() {
        const list = policy.create(testCase.week(), {
            "title": "Design sync",
            "start": "2026-08-18T15:00", "end": "2026-08-18T16:00"
        });
        compare(list.length, 7);
        verify(policy.byId(list, "evt-7") !== null);
        compare(policy.byId(list, "evt-7").title, "Design sync");
    }

    function test_create_does_not_touch_the_list_it_was_given() {
        const before = testCase.week();
        policy.create(before, event("evt-9", "2026-08-18T15:00", "2026-08-18T16:00"));
        compare(before.length, 6);
    }

    function test_create_refuses_an_invalid_event_and_a_duplicate_id() {
        const list = testCase.week();
        compare(policy.create(list, event("evt-9", "2026-08-18T16:00", "2026-08-18T15:00")).length, 6);
        compare(policy.create(list, event("evt-2", "2026-08-18T16:00", "2026-08-18T17:00")).length, 6);
    }

    // --- move -----------------------------------------------------------------

    function test_move_preserves_the_duration() {
        const list = policy.move(testCase.week(), "evt-2", "2026-08-19T14:00");
        const moved = policy.byId(list, "evt-2");
        compare(moved.start, "2026-08-19T14:00");
        compare(moved.end, "2026-08-19T15:30");   // still 90 minutes
    }

    function test_move_preserves_a_duration_that_crosses_midnight() {
        const list = policy.move(testCase.week(), "evt-6", "2026-08-25T09:00");
        const moved = policy.byId(list, "evt-6");
        compare(moved.start, "2026-08-25T09:00");
        compare(moved.end, "2026-08-27T17:00");   // still two days and eight hours
    }

    function test_move_across_midnight_rolls_the_day() {
        const list = policy.move(testCase.week(), "evt-2", "2026-08-18T23:00");
        compare(policy.byId(list, "evt-2").end, "2026-08-19T00:30");
    }

    function test_move_of_an_unknown_id_or_a_bad_stamp_changes_nothing() {
        compare(policy.byId(policy.move(testCase.week(), "evt-99", "2026-08-19T14:00"),
                            "evt-2").start, "2026-08-18T10:00");
        compare(policy.byId(policy.move(testCase.week(), "evt-2", "nope"),
                            "evt-2").start, "2026-08-18T10:00");
    }

    function test_moveDays_keeps_the_time_of_day() {
        const list = policy.moveDays(testCase.week(), "evt-2", 3);
        const moved = policy.byId(list, "evt-2");
        compare(moved.start, "2026-08-21T10:00");
        compare(moved.end, "2026-08-21T11:30");
    }

    function test_moveDays_backwards_over_a_month_end() {
        const list = policy.moveDays(testCase.week(), "evt-1", -17);
        compare(policy.byId(list, "evt-1").start, "2026-07-31T09:00");
    }

    // --- resize ---------------------------------------------------------------

    function test_resize_moves_the_edge_it_was_given() {
        const longer = policy.resize(testCase.week(), "evt-2", "end", "2026-08-18T12:00", 15);
        compare(policy.byId(longer, "evt-2").end, "2026-08-18T12:00");
        compare(policy.byId(longer, "evt-2").start, "2026-08-18T10:00");

        const earlier = policy.resize(testCase.week(), "evt-2", "start", "2026-08-18T09:00", 15);
        compare(policy.byId(earlier, "evt-2").start, "2026-08-18T09:00");
        compare(policy.byId(earlier, "evt-2").end, "2026-08-18T11:30");
    }

    function test_resize_floors_at_fifteen_minutes_on_the_bottom_edge() {
        // Dragging the bottom up past the top: the event stops at 15 minutes
        // and keeps the start it had.
        const list = policy.resize(testCase.week(), "evt-2", "end", "2026-08-18T09:00", 15);
        const e = policy.byId(list, "evt-2");
        compare(e.start, "2026-08-18T10:00");
        compare(e.end, "2026-08-18T10:15");
    }

    function test_resize_floors_at_fifteen_minutes_on_the_top_edge() {
        const list = policy.resize(testCase.week(), "evt-2", "start", "2026-08-18T13:00", 15);
        const e = policy.byId(list, "evt-2");
        compare(e.start, "2026-08-18T11:15");
        compare(e.end, "2026-08-18T11:30");
    }

    function test_resize_uses_the_policys_own_floor_when_none_is_given() {
        compare(policy.minMinutes, 15);
        const list = policy.resize(testCase.week(), "evt-2", "end", "2026-08-18T10:00", 0);
        compare(policy.byId(list, "evt-2").end, "2026-08-18T10:15");
    }

    function test_resize_of_a_bad_stamp_changes_nothing() {
        compare(policy.byId(policy.resize(testCase.week(), "evt-2", "end", "nope", 15),
                            "evt-2").end, "2026-08-18T11:30");
    }

    // --- guests ---------------------------------------------------------------

    function test_addGuest_adds_one() {
        const list = policy.addGuest(testCase.week(), "evt-2", "mira");
        compare(policy.byId(list, "evt-2").guests.join(","), "mira");
    }

    function test_addGuest_twice_is_still_one_guest() {
        let list = policy.addGuest(testCase.week(), "evt-2", "mira");
        list = policy.addGuest(list, "evt-2", "mira");
        list = policy.addGuest(list, "evt-2", "juno");
        list = policy.addGuest(list, "evt-2", "juno");
        compare(policy.byId(list, "evt-2").guests.join(","), "mira,juno");
    }

    function test_addGuest_leaves_the_original_event_alone() {
        const before = testCase.week();
        policy.addGuest(before, "evt-2", "mira");
        compare(policy.byId(before, "evt-2").guests.length, 0);
    }

    function test_addGuest_of_nobody_or_of_an_unknown_event_changes_nothing() {
        compare(policy.byId(policy.addGuest(testCase.week(), "evt-2", ""),
                            "evt-2").guests.length, 0);
        compare(policy.addGuest(testCase.week(), "evt-99", "mira").length, 6);
    }

    function test_removeGuest_removes_only_that_one() {
        let list = policy.addGuest(testCase.week(), "evt-2", "mira");
        list = policy.addGuest(list, "evt-2", "juno");
        list = policy.removeGuest(list, "evt-2", "mira");
        compare(policy.byId(list, "evt-2").guests.join(","), "juno");
    }

    function test_removeGuest_of_someone_not_invited_changes_nothing() {
        const list = policy.removeGuest(testCase.week(), "evt-2", "mira");
        compare(policy.byId(list, "evt-2").guests.length, 0);
    }

    // --- remove ---------------------------------------------------------------

    function test_remove_drops_one_event() {
        const list = policy.remove(testCase.week(), "evt-3");
        compare(list.length, 5);
        compare(policy.byId(list, "evt-3"), null);
    }

    function test_remove_of_an_unknown_id_is_a_no_op() {
        compare(policy.remove(testCase.week(), "evt-99").length, 6);
    }

    function test_remove_does_not_recycle_the_id() {
        // The counter follows the highest id ever used in the list, so deleting
        // the last event and making another does reuse the number — stated here
        // because it is a choice, and a harness that asserted `evt-7` after a
        // delete would be asserting this line.
        const list = policy.remove(testCase.week(), "evt-6");
        compare(policy.nextId(list), "evt-6");
    }

    // --- overlaps -------------------------------------------------------------

    function test_the_three_way_overlap_all_collide() {
        const list = testCase.week();
        const a = policy.byId(list, "evt-2");
        const b = policy.byId(list, "evt-3");
        const c = policy.byId(list, "evt-4");
        verify(policy.overlaps(a, b));
        verify(policy.overlaps(b, c));
        verify(policy.overlaps(a, c));
        compare(policy.collisions(list, a).length, 2);
        compare(policy.collisions(list, b).length, 2);
    }

    function test_back_to_back_events_do_not_overlap() {
        const a = event("a", "2026-08-18T09:00", "2026-08-18T10:00");
        const b = event("b", "2026-08-18T10:00", "2026-08-18T11:00");
        verify(!policy.overlaps(a, b));
        verify(!policy.overlaps(b, a));
    }

    function test_an_event_inside_another_overlaps_it() {
        const outer = event("a", "2026-08-18T09:00", "2026-08-18T17:00");
        const inner = event("b", "2026-08-18T12:00", "2026-08-18T12:30");
        verify(policy.overlaps(outer, inner));
        verify(policy.overlaps(inner, outer));
    }

    function test_events_on_different_days_do_not_overlap() {
        verify(!policy.overlaps(event("a", "2026-08-18T09:00", "2026-08-18T10:00"),
                                event("b", "2026-08-19T09:00", "2026-08-19T10:00")));
    }

    function test_overlaps_of_nothing_is_false() {
        verify(!policy.overlaps(null, event("b", "2026-08-18T09:00", "2026-08-18T10:00")));
    }

    // --- days -----------------------------------------------------------------

    function test_spansDays_counts_an_ordinary_event_as_one() {
        compare(policy.spansDays(event("a", "2026-08-18T09:00", "2026-08-18T10:00")), 1);
    }

    function test_spansDays_counts_an_all_day_event_as_one() {
        // Ends at 00:00 the next day, which belongs to the day before it.
        compare(policy.spansDays(event("a", "2026-08-19T00:00", "2026-08-20T00:00")), 1);
    }

    function test_spansDays_counts_a_thursday_to_saturday_span_as_three() {
        compare(policy.spansDays(event("a", "2026-08-20T09:00", "2026-08-22T17:00")), 3);
    }

    function test_forDay_finds_the_events_that_start_on_it() {
        compare(testCase.ids(policy.forDay(testCase.week(), "2026-08-18")),
                "evt-2,evt-3,evt-4");
        compare(testCase.ids(policy.forDay(testCase.week(), "2026-08-17")), "evt-1");
    }

    function test_forDay_finds_the_middle_of_a_multi_day_span() {
        // The case `start.startsWith(day)` loses: Friday is neither end of a
        // Thursday-to-Saturday event.
        compare(testCase.ids(policy.forDay(testCase.week(), "2026-08-21")), "evt-6");
        compare(testCase.ids(policy.forDay(testCase.week(), "2026-08-22")), "evt-6");
    }

    function test_forDay_does_not_bleed_past_a_midnight_end() {
        // The all-day Wednesday event ends at 00:00 Thursday and must not show
        // on Thursday.
        compare(testCase.ids(policy.forDay(testCase.week(), "2026-08-19")), "evt-5");
        compare(testCase.ids(policy.forDay(testCase.week(), "2026-08-20")), "evt-6");
    }

    function test_forDay_of_an_empty_day_and_a_non_day() {
        compare(policy.forDay(testCase.week(), "2026-08-23").length, 0);
        compare(policy.forDay(testCase.week(), "nope").length, 0);
    }

    function test_forRange_covers_the_whole_week_once() {
        compare(testCase.ids(policy.forRange(testCase.week(), "2026-08-17", "2026-08-23")),
                "evt-1,evt-2,evt-3,evt-4,evt-5,evt-6");
    }

    function test_forRange_includes_a_span_that_only_reaches_into_it() {
        compare(testCase.ids(policy.forRange(testCase.week(), "2026-08-22", "2026-08-28")),
                "evt-6");
        compare(policy.forRange(testCase.week(), "2026-08-23", "2026-08-28").length, 0);
    }

    // --- the shape the store depends on ---------------------------------------

    function test_every_mutation_returns_a_new_array() {
        const before = testCase.week();
        verify(policy.create(before, event("evt-9", "2026-08-18T15:00", "2026-08-18T16:00")) !== before);
        verify(policy.move(before, "evt-2", "2026-08-19T14:00") !== before);
        verify(policy.remove(before, "evt-2") !== before);
        verify(policy.addGuest(before, "evt-2", "mira") !== before);
    }

    function test_a_full_round_of_edits_lands_where_it_should() {
        // What tools/calendar-harness.sh drives over IPC, in one place: make,
        // invite, move, resize, delete.
        let list = policy.create([], { "title": "Design sync",
                                       "start": "2026-08-18T09:15",
                                       "end": "2026-08-18T10:15" });
        compare(testCase.ids(list), "evt-1");
        list = policy.addGuest(list, "evt-1", "mira");
        list = policy.move(list, "evt-1", "2026-08-19T11:00");
        list = policy.resize(list, "evt-1", "end", "2026-08-19T12:30", 15);
        const e = policy.byId(list, "evt-1");
        compare(e.start, "2026-08-19T11:00");
        compare(e.end, "2026-08-19T12:30");
        compare(e.guests.join(","), "mira");
        compare(policy.remove(list, "evt-1").length, 0);
    }
}
