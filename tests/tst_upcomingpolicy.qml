// The sidebar's "what is next" list.
//
// The clock is passed in, never read: the same reason `CalendarFormat` takes a
// `todayIso` — a policy that read the wall clock could only be tested for one
// minute of one day.
import QtQuick
import QtTest
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "UpcomingPolicy"

    UpcomingPolicy { id: policy }

    readonly property string now: "2026-08-18T13:40"

    readonly property var events: [
        { id: "a", title: "Standup", start: "2026-08-18T09:00", allDay: false },
        { id: "b", title: "Retro", start: "2026-08-19T14:00", allDay: false },
        { id: "c", title: "Coffee", start: "2026-08-18T15:00", allDay: false },
        { id: "d", title: "Release cut", start: "2026-08-18T16:30", allDay: false },
        { id: "e", title: "Roadmap sync", start: "2026-08-20T14:00", allDay: false },
        { id: "f", title: "Sprint demo day", start: "2026-08-18T00:00", allDay: true }
    ]

    function ids(list: var): string {
        return (list || []).map(event => event.id).join(",");
    }

    // --- which side of now ----------------------------------------------------

    function test_past_events_are_dropped() {
        // 09:00 is behind 13:40, so the standup is not what is next.
        const list = policy.next(testCase.events, testCase.now, 3);
        verify(testCase.ids(list).indexOf("a") === -1, testCase.ids(list));
    }

    function test_an_event_starting_exactly_now_still_counts() {
        const list = policy.next([{ id: "x", title: "Now", start: testCase.now, allDay: false }],
                                 testCase.now, 3);
        compare(testCase.ids(list), "x");
    }

    function test_all_day_today_stays_listed_after_its_midnight() {
        // Its start stamp is 00:00, thirteen hours behind now, and it is still
        // today's event — the date is what an all-day event is about.
        const list = policy.next(testCase.events, testCase.now, 6);
        verify(testCase.ids(list).indexOf("f") !== -1, testCase.ids(list));
    }

    function test_all_day_yesterday_is_gone() {
        const list = policy.next([{ id: "y", title: "Cabin", start: "2026-08-17T00:00", allDay: true }],
                                 testCase.now, 3);
        compare(testCase.ids(list), "");
    }

    // --- order and length -----------------------------------------------------

    function test_soonest_first_and_capped_at_the_limit() {
        compare(testCase.ids(policy.next(testCase.events, testCase.now, 3)), "f,c,d");
    }

    function test_a_zero_limit_falls_back_to_the_default() {
        compare(policy.next(testCase.events, testCase.now, 0).length, policy.defaultLimit);
    }

    function test_ties_break_on_title_rather_than_store_order() {
        const tied = [
            { id: "z", title: "Zebra", start: "2026-08-18T14:00", allDay: false },
            { id: "m", title: "Apple", start: "2026-08-18T14:00", allDay: false }
        ];
        compare(testCase.ids(policy.next(tied, testCase.now, 2)), "m,z");
    }

    // --- the empty answers ----------------------------------------------------

    function test_nothing_ahead_returns_an_empty_list() {
        compare(policy.next(testCase.events, "2026-12-31T23:00", 3).length, 0);
    }

    function test_missing_input_is_answered_rather_than_thrown() {
        compare(policy.next(null, testCase.now, 3).length, 0);
        compare(policy.next(testCase.events, "", 3).length, 0);
        compare(policy.next([{ id: "n", title: "No start" }], testCase.now, 3).length, 0);
    }

    // --- the day label --------------------------------------------------------

    function test_same_day_is_the_day_the_row_hides_its_date() {
        verify(policy.isSameDay(testCase.events[2], testCase.now));
        verify(!policy.isSameDay(testCase.events[1], testCase.now));
        verify(!policy.isSameDay(null, testCase.now));
    }
}
