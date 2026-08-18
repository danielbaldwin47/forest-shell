// Google's JSON <-> our event.
//
// The cases that carry their weight are the ones where a plausible mapping is
// wrong and the surface still looks fine:
//
//   - **the offset is the payload's, not the machine's.** Google states the
//     offset that was in force at that instant; we store bare local wall clock.
//     A mapping that keeps the digits is right exactly when the two agree, and
//     the day they stop agreeing every event moves by an hour. The crossing
//     case here gives one event two different machine offsets — that is what
//     the function form of the argument is for.
//   - **all-day ends are exclusive there and inclusive here.** Both directions
//     are asserted, and the round trip is asserted on top, because an off-by-one
//     that is symmetric survives a one-way test.
//   - **eleven colours into eight hues.** Both directions, the unknown id, and
//     the fold: Tomato comes back as `ember` and `ember` goes up as Tangerine.
//   - **a cancelled event is a deletion**, and must not be able to be drawn.
import QtQuick
import QtTest
import "../Services/Calendar"
import "../Surfaces/Calendar"

TestCase {
    id: testCase

    name: "GoogleEventPolicy"

    GoogleEventPolicy { id: policy }
    HuePolicy { id: hues }

    readonly property var book: [
        { "id": "mira", "name": "Mira Solberg", "email": "mira@example.com" }
    ]

    function byEmail(email) {
        for (const c of testCase.book)
            if (c.email.toLowerCase() === String(email).toLowerCase())
                return c;
        return null;
    }

    function byId(id) {
        for (const c of testCase.book)
            if (c.id === id)
                return c;
        return null;
    }

    function timed(extra) {
        const g = {
            "id": "g-1", "etag": "\"42\"", "summary": "Standup",
            "updated": "2026-08-18T06:00:00.000Z",
            "start": { "dateTime": "2026-08-18T09:15:00+01:00" },
            "end": { "dateTime": "2026-08-18T09:45:00+01:00" }
        };
        for (const k in (extra || {}))
            g[k] = extra[k];
        return g;
    }

    // --- instants ------------------------------------------------------------

    function test_parse_instant_reads_the_offset_and_drops_the_seconds() {
        const p = policy.parseInstant("2026-08-18T09:15:30+01:00");
        compare(p.stamp, "2026-08-18T09:15");
        compare(p.offsetMinutes, 60);
        compare(policy.parseInstant("2026-08-18T09:15:00Z").offsetMinutes, 0);
        compare(policy.parseInstant("2026-08-18T09:15:00-0530").offsetMinutes, -330);
        // No zone is not the same claim as UTC.
        compare(policy.parseInstant("2026-08-18T09:15:00").offsetMinutes, null);
        compare(policy.parseInstant("2026-08-18"), null);
        compare(policy.parseInstant(null), null);
    }

    // The payload says +01:00, the machine is on +02:00 that day: the wall clock
    // we draw is an hour later than the digits Google sent.
    function test_timed_pull_shifts_by_the_difference_of_the_two_offsets() {
        const e = policy.fromGoogle(testCase.timed({}), 120, testCase.byEmail);
        compare(e.start, "2026-08-18T10:15");
        compare(e.end, "2026-08-18T10:45");
        compare(e.allDay, false);
    }

    // And the other way, including across midnight, which is where a naive
    // "add the minutes to the time" loses the day.
    function test_timed_pull_shifts_backwards_and_rolls_the_day() {
        const g = testCase.timed({});
        g.start.dateTime = "2026-08-18T00:30:00+02:00";
        g.end.dateTime = "2026-08-18T01:30:00+02:00";
        const e = policy.fromGoogle(g, 60, testCase.byEmail);
        compare(e.start, "2026-08-17T23:30");
        compare(e.end, "2026-08-18T00:30");
    }

    function test_utc_payload_lands_on_the_machines_wall_clock() {
        const g = testCase.timed({});
        g.start.dateTime = "2026-08-18T07:15:00Z";
        g.end.dateTime = "2026-08-18T07:45:00Z";
        const e = policy.fromGoogle(g, 120, testCase.byEmail);
        compare(e.start, "2026-08-18T09:15");
        compare(e.end, "2026-08-18T09:45");
    }

    // One event, two machine offsets. Europe's clocks go back at 01:00 UTC on
    // 2026-10-25: Google answers each end with the offset in force there, and
    // the machine — somewhere else, and also shifting — is asked per instant.
    // A single number for the whole event gets one of these two ends wrong.
    function test_an_event_across_a_dst_change_gets_an_offset_per_end() {
        const machine = utc => utc < "2026-10-25T01:00" ? 180 : 120;
        const g = testCase.timed({});
        g.start.dateTime = "2026-10-25T02:30:00+02:00";   // 00:30 UTC, machine +180
        g.end.dateTime = "2026-10-25T04:30:00+01:00";     // 03:30 UTC, machine +120
        const e = policy.fromGoogle(g, machine, testCase.byEmail);
        compare(e.start, "2026-10-25T03:30");
        compare(e.end, "2026-10-25T05:30");
        // The number form is the same call with a constant answer.
        const flat = policy.fromGoogle(g, 120, testCase.byEmail);
        compare(flat.start, "2026-10-25T02:30");
        compare(flat.end, "2026-10-25T05:30");
    }

    function test_an_unparseable_instant_is_empty_never_a_guess() {
        compare(policy.localStamp("tomorrow-ish", 60), "");
        compare(policy.localStamp("2026-08-18T09:15:00", 120), "2026-08-18T09:15");
    }

    // --- all day -------------------------------------------------------------

    function test_all_day_end_is_exclusive_over_there_and_inclusive_here() {
        const e = policy.fromGoogle({
            "id": "g-2", "summary": "Leave", "start": { "date": "2026-08-18" },
            "end": { "date": "2026-08-20" }
        }, 120, testCase.byEmail);
        compare(e.allDay, true);
        compare(e.start, "2026-08-18T00:00");
        compare(e.end, "2026-08-19T00:00");
    }

    function test_a_one_day_google_event_starts_and_ends_on_the_same_day() {
        const e = policy.fromGoogle({
            "id": "g-3", "start": { "date": "2026-08-18" }, "end": { "date": "2026-08-19" }
        }, 120, testCase.byEmail);
        compare(e.start, "2026-08-18T00:00");
        compare(e.end, "2026-08-18T00:00");
    }

    function test_all_day_round_trips_through_both_off_by_ones() {
        const original = {
            "id": "g-2", "summary": "Leave", "start": { "date": "2026-08-18" },
            "end": { "date": "2026-08-20" }
        };
        const body = policy.toGoogle(policy.fromGoogle(original, 120, testCase.byEmail),
                                     "Europe/Berlin", testCase.byId);
        compare(body.start.date, "2026-08-18");
        compare(body.end.date, "2026-08-20");
        verify(body.start.dateTime === undefined);
    }

    // --- cancellations -------------------------------------------------------

    function test_a_cancelled_event_is_a_removal_not_an_event() {
        const out = policy.fromGoogle({
            "id": "g-9", "status": "cancelled",
            "start": { "dateTime": "2026-08-18T09:15:00+01:00" }
        }, 120, testCase.byEmail);
        compare(out.remove, "g-9");
        // Nothing on it can be mistaken for something to draw.
        verify(out.start === undefined);
        verify(out.title === undefined);
    }

    // --- colour --------------------------------------------------------------

    function test_google_colour_ids_become_hue_names() {
        compare(hues.hueForGoogleColor("7"), "glacier");
        compare(hues.hueForGoogleColor(5), "lamplight");
        compare(hues.hueForGoogleColor("11"), "ember");
        compare(hues.hueForGoogleColor("4"), "ember");
        compare(hues.hueForGoogleColor("2"), "lichen");
        compare(hues.hueForGoogleColor("1"), "heather");
        // Grey is a status, and Graphite is the only thing that may become it.
        compare(hues.hueForGoogleColor("8"), "stone");
        // An id we do not know leaves the colour unset, which is an event the
        // hash colours — not hue 0, which would be a silent all-glacier calendar.
        compare(hues.hueForGoogleColor("99"), "");
        compare(hues.hueForGoogleColor(""), "");
        compare(hues.hueForGoogleColor(null), "");
    }

    function test_hue_names_become_google_colour_ids() {
        compare(hues.googleColorForHue("glacier"), "7");
        compare(hues.googleColorForHue("EMBER"), "6");
        compare(hues.googleColorForHue("stone"), "8");
        compare(hues.googleColorForHue("chartreuse"), "");
        compare(hues.googleColorForHue(""), "");
        compare(hues.googleColorForHue(undefined), "");
    }

    // Every hue we can store must survive the trip out and back, or an event
    // edited here changes colour for having been synced.
    function test_every_hue_survives_the_round_trip_out_and_back() {
        for (const name of hues.names) {
            const id = hues.googleColorForHue(name);
            verify(id.length > 0, name + " has no Google colour");
            compare(hues.hueForGoogleColor(id), name);
        }
    }

    // The other direction folds, and that is the deliberate half: three warm
    // reds are one chip colour, so Tomato comes home as Tangerine.
    function test_the_extra_google_reds_fold_onto_ember() {
        const e = policy.fromGoogle(testCase.timed({ "colorId": "11" }), 120, testCase.byEmail);
        compare(e.colour, "ember");
        compare(policy.toGoogle(e, "Europe/Berlin", testCase.byId).colorId, "6");
    }

    function test_an_uncoloured_event_pushes_without_a_colour() {
        const e = policy.fromGoogle(testCase.timed({}), 120, testCase.byEmail);
        compare(e.colour, "");
        verify(policy.toGoogle(e, "Europe/Berlin", testCase.byId).colorId === undefined);
    }

    // --- guests --------------------------------------------------------------

    function test_a_known_address_becomes_the_contact_we_already_have() {
        const e = policy.fromGoogle(testCase.timed({
            "attendees": [{ "email": "MIRA@example.com", "displayName": "Mira S" }]
        }), 120, testCase.byEmail);
        compare(e.guests.join(","), "mira");
        compare(policy.newContacts(testCase.timed({
            "attendees": [{ "email": "MIRA@example.com" }]
        }), testCase.byEmail).length, 0);
    }

    function test_an_unknown_address_becomes_a_synthetic_contact() {
        const g = testCase.timed({
            "attendees": [{ "email": "juno@example.com", "displayName": "Juno Park" }]
        });
        const e = policy.fromGoogle(g, 120, testCase.byEmail);
        compare(e.guests.join(","), "gmail:juno@example.com");
        const made = policy.newContacts(g, testCase.byEmail);
        compare(made.length, 1);
        compare(made[0].id, "gmail:juno@example.com");
        compare(made[0].name, "Juno Park");
        compare(made[0].email, "juno@example.com");
        verify(made[0].synthetic);
        // A synthetic id carries its own address, so the push needs no store.
        compare(policy.emailFor("gmail:juno@example.com", testCase.byId), "juno@example.com");
    }

    function test_a_nameless_attendee_is_called_by_its_address() {
        const made = policy.newContacts(testCase.timed({
            "attendees": [{ "email": "juno@example.com" }]
        }), testCase.byEmail);
        compare(made[0].name, "juno@example.com");
    }

    // A room is not a person and the account is not a guest: Google puts the
    // signed-in user in its own attendee list, and re-adds the organiser to
    // anything we push, so carrying it would only ever draw our own face.
    function test_rooms_and_the_account_itself_are_not_guests() {
        const e = policy.fromGoogle(testCase.timed({
            "attendees": [
                { "email": "room-3@example.com", "resource": true },
                { "email": "me@example.com", "self": true },
                { "email": "juno@example.com" }
            ]
        }), 120, testCase.byEmail);
        compare(e.guests.join(","), "gmail:juno@example.com");
    }

    function test_guests_push_back_as_attendee_addresses() {
        const body = policy.toGoogle({
            "title": "Standup", "start": "2026-08-18T09:15", "end": "2026-08-18T09:45",
            "guests": ["mira", "gmail:juno@example.com", "ghost"]
        }, "Europe/Berlin", testCase.byId);
        compare(body.attendees.length, 2);
        compare(body.attendees[0].email, "mira@example.com");
        compare(body.attendees[1].email, "juno@example.com");
        // A guest we can put no address to is dropped rather than invented.
        compare(body.attendees.map(a => a.email).indexOf("ghost"), -1);
    }

    function test_an_event_with_no_guests_sends_no_attendee_list() {
        const body = policy.toGoogle({
            "title": "Solo", "start": "2026-08-18T09:15", "end": "2026-08-18T09:45", "guests": []
        }, "Europe/Berlin", testCase.byId);
        verify(body.attendees === undefined);
    }

    // --- identity ------------------------------------------------------------

    function test_the_sync_identity_comes_across() {
        const e = policy.fromGoogle(testCase.timed({}), 120, testCase.byEmail);
        compare(e.googleId, "g-1");
        compare(e.etag, "\"42\"");
        compare(e.updated, "2026-08-18T06:00:00.000Z");
        // The local id is the store's to answer, not this file's.
        compare(e.id, "");
    }

    // An instance of a recurring series keeps its series id and its original
    // start **raw**. Converted, the identity would move the day the machine's
    // offset moved, and the instance would stop matching itself.
    function test_a_recurring_instance_keeps_its_identity_verbatim() {
        const e = policy.fromGoogle(testCase.timed({
            "id": "g-1_20260818T081500Z",
            "recurringEventId": "g-series",
            "originalStartTime": { "dateTime": "2026-08-18T09:15:00+01:00" }
        }), 120, testCase.byEmail);
        compare(e.googleId, "g-1_20260818T081500Z");
        compare(e.recurringEventId, "g-series");
        compare(e.originalStartTime, "2026-08-18T09:15:00+01:00");
        compare(e.start, "2026-08-18T10:15");
        // Read-only over there: an instance edit is a PATCH at the instance's
        // own id, which is transport rather than body.
        const body = policy.toGoogle(e, "Europe/Berlin", testCase.byId);
        verify(body.recurringEventId === undefined);
        verify(body.originalStartTime === undefined);
    }

    function test_an_all_day_instance_keeps_its_original_date() {
        const e = policy.fromGoogle({
            "id": "g-4_20260818", "recurringEventId": "g-4",
            "start": { "date": "2026-08-18" }, "end": { "date": "2026-08-19" },
            "originalStartTime": { "date": "2026-08-18" }
        }, 120, testCase.byEmail);
        compare(e.originalStartTime, "2026-08-18");
    }

    // --- push shape ----------------------------------------------------------

    // Naive local time plus the zone, not an offset: it is the honest statement
    // of what our bare stamp meant, and it needs no second offset argument.
    function test_a_timed_push_states_the_zone_rather_than_an_offset() {
        const body = policy.toGoogle({
            "title": "Standup", "start": "2026-08-18T09:15", "end": "2026-08-18T09:45"
        }, "Europe/Berlin", testCase.byId);
        compare(body.summary, "Standup");
        compare(body.start.dateTime, "2026-08-18T09:15:00");
        compare(body.start.timeZone, "Europe/Berlin");
        compare(body.end.dateTime, "2026-08-18T09:45:00");
        verify(body.start.date === undefined);
    }

    // --- stability -----------------------------------------------------------

    // Out and back changes nothing we own. The body carries no offset, so the
    // second pull leaves the wall clock alone whatever the machine is doing —
    // which is the same rule as `parseInstant` reporting a null offset.
    function test_out_and_back_is_stable_on_the_fields_we_own() {
        const first = policy.fromGoogle(testCase.timed({
            "colorId": "7",
            "attendees": [{ "email": "mira@example.com" }, { "email": "juno@example.com" }]
        }), 120, testCase.byEmail);
        const again = policy.fromGoogle(policy.toGoogle(first, "Europe/Berlin", testCase.byId),
                                        480, testCase.byEmail);
        compare(again.title, first.title);
        compare(again.start, first.start);
        compare(again.end, first.end);
        compare(again.allDay, first.allDay);
        compare(again.colour, first.colour);
        compare(again.guests.join(","), first.guests.join(","));
    }

    function test_out_and_back_is_stable_for_an_all_day_event() {
        const first = policy.fromGoogle({
            "id": "g-2", "summary": "Leave", "colorId": "8",
            "start": { "date": "2026-08-18" }, "end": { "date": "2026-08-20" }
        }, 120, testCase.byEmail);
        const again = policy.fromGoogle(policy.toGoogle(first, "Europe/Berlin", testCase.byId),
                                        -300, testCase.byEmail);
        compare(again.allDay, true);
        compare(again.start, first.start);
        compare(again.end, first.end);
        compare(again.colour, "stone");
    }

    // --- junk ----------------------------------------------------------------

    function test_an_empty_payload_is_an_empty_event_not_an_exception() {
        const e = policy.fromGoogle({}, 120, null);
        compare(e.title, "");
        compare(e.start, "");
        compare(e.googleId, "");
        compare(e.guests.length, 0);
        compare(e.colour, "");
    }

    function test_a_push_of_nothing_is_a_body_of_empties() {
        const body = policy.toGoogle(null, "", null);
        compare(body.summary, "");
        compare(body.start.dateTime, "");
        verify(body.start.timeZone === undefined);
    }

    // --- probes (adversarial pass) -------------------------------------------

    // `Number(null)` is 0 and `Number("")` is 0, so an *absent* machine offset
    // is one coercion away from claiming the machine is on UTC — which converts
    // every timed event by the payload's offset instead of leaving it alone.
    // The doc above `machineOffset` promises NaN here; only `undefined` used to
    // deliver it.
    function test_an_absent_machine_offset_leaves_the_wall_clock_alone() {
        const g = testCase.timed({});
        const absent = [null, undefined, "", {}, []];
        for (const nothing of absent) {
            verify(isNaN(policy.machineOffset(nothing, "2026-08-18T08:15")),
                   "offset " + JSON.stringify(nothing) + " is not an offset");
            compare(policy.localStamp(g.start.dateTime, nothing), "2026-08-18T09:15");
        }
        // An offset that is a number in a string is still a number.
        compare(policy.machineOffset("120", "2026-08-18T08:15"), 120);
        // And an infinity is not one: it would reach `addMinutes` as arithmetic.
        verify(isNaN(policy.machineOffset(Infinity, "2026-08-18T08:15")));
    }

    // The function form is the one a real caller passes, and a lookup that
    // cannot answer for an instant returns null rather than throwing. That must
    // read as "leave it alone" too, not as "UTC".
    function test_a_lookup_that_cannot_answer_leaves_the_wall_clock_alone() {
        const e = policy.fromGoogle(testCase.timed({}), () => null, testCase.byEmail);
        compare(e.start, "2026-08-18T09:15");
        compare(e.end, "2026-08-18T09:45");
    }

    // The table is the whole mapping, so its shape is the check: every one of
    // Google's eleven event colours must land somewhere, no id twice, and no
    // key that is not a hue — a key typo would make one hue unpullable and
    // unpushable at once, and only the round-trip test would notice the second.
    function test_every_google_event_colour_is_claimed_exactly_once() {
        const claimed = [];
        for (const key in hues.googleColorTable) {
            verify(hues.names.indexOf(key) >= 0, key + " is not a hue");
            for (const id of hues.googleColorTable[key]) {
                verify(claimed.indexOf(id) < 0, "colorId " + id + " is claimed twice");
                claimed.push(id);
            }
        }
        for (let id = 1; id <= 11; id++)
            verify(claimed.indexOf(String(id)) >= 0, "colorId " + id + " maps to no hue");
        compare(claimed.length, 11);
    }

    // Google can hold one offset for both ends while *we* cross a change: a
    // fixed-offset zone (+05:30) against a machine going back an hour mid-event.
    // The wall clock we draw then has to stretch or shrink, and a single offset
    // for the whole event is the mapping that silently cannot.
    function test_a_fixed_offset_payload_still_gets_an_offset_per_end() {
        const machine = utc => utc < "2026-10-24T22:00" ? 180 : 120;
        const g = testCase.timed({});
        g.start.dateTime = "2026-10-25T02:30:00+05:30";   // 2026-10-24T21:00 UTC
        g.end.dateTime = "2026-10-25T04:30:00+05:30";     // 2026-10-24T23:00 UTC
        const e = policy.fromGoogle(g, machine, testCase.byEmail);
        compare(e.start, "2026-10-25T00:00");
        compare(e.end, "2026-10-25T01:00");
        // Two hours of real time, one hour of wall clock. The flat form cannot
        // say that, which is the whole reason the argument may be a function.
        compare(policy.fromGoogle(g, 120, testCase.byEmail).start, "2026-10-24T23:00");
    }

    // Sub-hour zones are where a sign error hides: an hours-only conversion is
    // right to within 45 minutes, which looks like a rounding bug rather than a
    // sign one.
    function test_a_three_quarter_hour_zone_converts_and_rolls_backwards() {
        compare(policy.parseOffset("+0545"), 345);
        compare(policy.parseOffset("-05:45"), -345);
        compare(policy.localStamp("2026-08-18T09:15:00+05:45", -330), "2026-08-17T22:00");
    }

    // What we push comes back with an offset Google chose, and the wall clock
    // has to survive that: naive-plus-zone out, offset in, same digits — on the
    // machine the zone describes, and honestly different on one it does not.
    function test_what_we_push_comes_back_as_the_same_wall_clock() {
        const ours = { "id": "evt-1", "title": "Standup", "start": "2026-08-18T09:15",
                       "end": "2026-08-18T09:45", "allDay": false, "colour": "lake",
                       "guests": [] };
        const body = policy.toGoogle(ours, "Europe/Berlin", testCase.byId);
        const echo = {
            "id": "g-7", "status": "confirmed", "summary": body.summary,
            "colorId": body.colorId,
            "start": { "dateTime": body.start.dateTime + "+02:00", "timeZone": "Europe/Berlin" },
            "end": { "dateTime": body.end.dateTime + "+02:00", "timeZone": "Europe/Berlin" }
        };
        const back = policy.fromGoogle(echo, 120, testCase.byEmail);
        compare(back.start, ours.start);
        compare(back.end, ours.end);
        compare(back.colour, ours.colour);
        // Read on a machine an hour west, the same event is an hour earlier —
        // that is the conversion working, not failing.
        compare(policy.fromGoogle(echo, 60, testCase.byEmail).start, "2026-08-18T08:15");
    }

    // A cancellation names the event it cancels. Google always sends an id, but
    // an empty one would be a removal that matches every *local-only* event —
    // they all carry `googleId: ""` — so the contract is pinned here: callers
    // must ignore a removal that names nothing.
    function test_a_cancellation_that_names_nothing_is_still_shaped_like_one() {
        const out = policy.fromGoogle({ "status": "cancelled" }, 120, testCase.byEmail);
        compare(out.remove, "");
        verify(out.start === undefined);
    }
}
