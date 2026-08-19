// One sync round's decisions.
//
// The cases that carry their weight are the ones where the wrong answer is
// invisible until somebody loses work:
//
//   - **the tie.** Equal timestamps are what the round *after* a successful
//     pull looks like. Resolving the tie to "local" would push every pulled
//     event straight back, forever, and the calendar would still look right.
//   - **410.** The queue is the only copy of edits made offline. A resync that
//     clears it alongside the token loses them silently, and the next pull
//     makes the calendar look correct — as the server's copy.
//   - **create-then-delete offline.** Collapsing to "the last op" sends a
//     create so it can send a delete, which is two invitations in every guest's
//     inbox for a meeting that never happened.
//   - **a cancelled event with a queued edit.** Both halves have to go: the
//     event locally, and the op that would otherwise resurrect it.
//   - **the empty remove.** `{remove: ""}` matches every local-only event if it
//     is taken at face value.
//   - **the cleared guest list.** The whole path, from a plan's push op to the
//     body the helper sends, because the bug is a field being *absent*, and
//     absent is what a passing one-sided test also looks like.
import QtQuick
import QtTest
import "../Services/Calendar"

TestCase {
    id: testCase

    name: "SyncPolicy"

    SyncPolicy { id: policy }
    GoogleEventPolicy { id: mapping }

    readonly property string early: "2026-08-18T06:00:00.000Z"
    readonly property string late: "2026-08-18T09:00:00.000Z"
    readonly property string now: "2026-08-18T12:00:00.000Z"

    function event(extra) {
        const e = {
            "id": "evt-1", "title": "Standup",
            "start": "2026-08-18T09:15", "end": "2026-08-18T09:45",
            "allDay": false, "colour": "", "guests": [], "otherAttendees": [],
            "googleId": "g-1", "etag": "\"1\"",
            "updated": testCase.early, "modifiedAt": testCase.early
        };
        for (const k in (extra || {}))
            e[k] = extra[k];
        return e;
    }

    function remote(extra) {
        const g = {
            "id": "", "title": "Standup (moved)",
            "start": "2026-08-18T10:15", "end": "2026-08-18T10:45",
            "allDay": false, "colour": "", "guests": [], "otherAttendees": [],
            "googleId": "g-1", "etag": "\"2\"", "updated": testCase.late
        };
        for (const k in (extra || {}))
            g[k] = extra[k];
        return g;
    }

    function delta(extra) {
        const d = { "events": [], "gone": false, "nextSyncToken": "" };
        for (const k in (extra || {}))
            d[k] = extra[k];
        return d;
    }

    function state(extra) {
        const s = { "syncToken": "tok-1", "pendingOps": [] };
        for (const k in (extra || {}))
            s[k] = extra[k];
        return s;
    }

    function pushOf(result, id) {
        for (const op of result.toPush)
            if (op.id === id)
                return op;
        return null;
    }

    // --- the token ------------------------------------------------------------

    function test_a_token_advances() {
        const out = policy.plan([], testCase.delta({ "nextSyncToken": "tok-2" }),
                                testCase.state(), testCase.now);
        compare(out.newState.syncToken, "tok-2");
        compare(out.needsFullSync, false);
    }

    function test_a_token_survives_a_delta_that_names_none() {
        // A page in the middle of a paged pull carries `nextPageToken`, not
        // `nextSyncToken`. Taking the absence as "no token" would throw away a
        // good one and turn the next round into a full download.
        const out = policy.plan([], testCase.delta(), testCase.state(), testCase.now);
        compare(out.newState.syncToken, "tok-1");
    }

    // --- 410 ------------------------------------------------------------------

    function test_gone_asks_for_a_full_resync_and_keeps_the_queue() {
        const local = [testCase.event({ "googleId": "", "modifiedAt": testCase.late })];
        const queue = [{ "id": "evt-1", "op": "create", "googleId": "", "attempt": 0 }];
        const out = policy.plan(local, testCase.delta({ "gone": true, "events": [testCase.remote()] }),
                                testCase.state({ "pendingOps": queue }), testCase.now);
        compare(out.needsFullSync, true);
        compare(out.newState.syncToken, "");
        compare(out.toApplyLocally.length, 0, "a partial delta must not be applied");
        compare(out.newState.pendingOps.length, 1);
        compare(out.toPush.length, 1);
        compare(out.toPush[0].op, "create");
    }

    // --- the queue ------------------------------------------------------------

    function test_dedupe_collapses_repeated_edits() {
        const out = policy.dedupe([
            { "id": "evt-1", "op": "patch", "googleId": "g-1", "attempt": 2 },
            { "id": "evt-1", "op": "patch", "googleId": "g-1", "attempt": 0 },
            { "id": "evt-2", "op": "patch", "googleId": "g-2", "attempt": 0 }
        ]);
        compare(out.length, 2);
        compare(out[0].id, "evt-1");
        compare(out[0].attempt, 2, "a fold must not reset an earned backoff");
        compare(out[1].id, "evt-2");
    }

    function test_dedupe_folds_an_edit_into_an_unsent_create() {
        const out = policy.dedupe([
            { "id": "evt-1", "op": "create", "googleId": "" },
            { "id": "evt-1", "op": "patch", "googleId": "" }
        ]);
        compare(out.length, 1);
        compare(out[0].op, "create", "a PATCH against an id we do not have yet is a 404");
    }

    function test_dedupe_cancels_a_create_that_was_deleted_before_it_went() {
        const out = policy.dedupe([
            { "id": "evt-1", "op": "create", "googleId": "" },
            { "id": "evt-1", "op": "delete", "googleId": "" }
        ]);
        compare(out.length, 0);
    }

    function test_dedupe_drops_nonsense() {
        const out = policy.dedupe([
            { "id": "", "op": "patch" }, { "id": "evt-1", "op": "explode" }, null
        ]);
        compare(out.length, 0);
    }

    // --- last writer wins -----------------------------------------------------

    function test_remote_wins_when_the_server_is_newer() {
        const out = policy.plan([testCase.event()], testCase.delta({ "events": [testCase.remote()] }),
                                testCase.state(), testCase.now);
        compare(out.toApplyLocally.length, 1);
        compare(out.toApplyLocally[0].op, "upsert");
        compare(out.toApplyLocally[0].event.id, "evt-1", "the local id is ours to keep");
        compare(out.toApplyLocally[0].event.start, "2026-08-18T10:15");
        compare(out.toApplyLocally[0].event.modifiedAt, testCase.late,
                "the last writer was the server; saying so is what makes the next round a no-op");
        compare(out.toPush.length, 0, "the copy that lost must not be pushed back");
    }

    function test_remote_wins_a_tie() {
        const local = testCase.event({ "modifiedAt": testCase.late });
        const out = policy.plan([local], testCase.delta({ "events": [testCase.remote()] }),
                                testCase.state(), testCase.now);
        compare(out.toApplyLocally.length, 1);
        compare(out.toApplyLocally[0].op, "upsert");
        compare(out.toPush.length, 0);
    }

    function test_local_wins_when_it_was_edited_after_the_server_said_so() {
        const local = testCase.event({ "title": "Standup (mine)",
                                       "modifiedAt": "2026-08-18T11:00:00.000Z" });
        const out = policy.plan([local], testCase.delta({ "events": [testCase.remote()] }),
                                testCase.state(), testCase.now);
        compare(out.toApplyLocally.length, 0);
        compare(out.toPush.length, 1, "a local copy the server has not got is a push waiting to happen");
        compare(out.toPush[0].op, "patch");
        compare(out.toPush[0].googleId, "g-1");
        compare(out.toPush[0].event.title, "Standup (mine)");
    }

    function test_a_new_remote_event_arrives_without_an_id() {
        const out = policy.plan([], testCase.delta({ "events": [testCase.remote({ "googleId": "g-9" })] }),
                                testCase.state(), testCase.now);
        compare(out.toApplyLocally.length, 1);
        compare(out.toApplyLocally[0].event.id, "", "which local id this becomes is the store's answer");
        compare(out.toApplyLocally[0].event.googleId, "g-9");
    }

    function test_a_remote_event_with_no_updated_is_dated_now() {
        const out = policy.plan([], testCase.delta({ "events": [testCase.remote({ "updated": "" })] }),
                                testCase.state(), testCase.now);
        compare(out.toApplyLocally[0].event.modifiedAt, testCase.now);
    }

    // --- deletions ------------------------------------------------------------

    function test_a_remote_cancellation_wins_over_a_local_edit() {
        // A cancellation is not a field-level edit: the meeting is off for
        // everyone who was invited. Keeping our newer copy would show a meeting
        // nobody else can see, and pushing it would re-invite the room.
        const local = testCase.event({ "modifiedAt": "2026-08-18T11:00:00.000Z" });
        const queue = [{ "id": "evt-1", "op": "patch", "googleId": "g-1", "attempt": 0 }];
        const out = policy.plan([local], testCase.delta({ "events": [{ "remove": "g-1" }] }),
                                testCase.state({ "pendingOps": queue }), testCase.now);
        compare(out.toApplyLocally.length, 1);
        compare(out.toApplyLocally[0].op, "remove");
        compare(out.toApplyLocally[0].id, "evt-1");
        compare(out.toApplyLocally[0].googleId, "g-1");
        compare(out.toPush.length, 0, "the queued edit went with it");
        compare(out.newState.pendingOps.length, 0);
    }

    function test_an_empty_remove_is_ignored() {
        // The helper can produce `{remove: ""}` from a cancelled payload whose
        // id never arrived. Taken at face value it matches every local-only
        // event on the calendar.
        const local = [testCase.event({ "googleId": "" })];
        const out = policy.plan(local, testCase.delta({ "events": [{ "remove": "" }] }),
                                testCase.state(), testCase.now);
        compare(out.toApplyLocally.length, 0);
    }

    function test_a_cancellation_we_never_had_asks_for_nothing() {
        const out = policy.plan([testCase.event()],
                                testCase.delta({ "events": [{ "remove": "g-404" }] }),
                                testCase.state(), testCase.now);
        compare(out.toApplyLocally.length, 0);
    }

    function test_a_local_delete_is_pushed() {
        // The store has already dropped the event, so the queue is the only
        // record that it ever existed.
        const queue = [{ "id": "evt-9", "op": "delete", "googleId": "g-9", "attempt": 0 }];
        const out = policy.plan([], testCase.delta(), testCase.state({ "pendingOps": queue }),
                                testCase.now);
        compare(out.toPush.length, 1);
        compare(out.toPush[0].op, "delete");
        compare(out.toPush[0].googleId, "g-9");
        compare(out.toPush[0].event, null);
    }

    function test_a_local_delete_of_something_never_uploaded_is_dropped() {
        const queue = [{ "id": "evt-9", "op": "delete", "googleId": "", "attempt": 0 }];
        const out = policy.plan([], testCase.delta(), testCase.state({ "pendingOps": queue }),
                                testCase.now);
        compare(out.toPush.length, 0);
    }

    // --- the queue is a cache -------------------------------------------------

    function test_an_event_the_server_never_saw_is_pushed_without_being_queued() {
        // The calendar that existed before sync was switched on, and the op
        // lost to a crash between the edit and the write.
        const out = policy.plan([testCase.event({ "googleId": "", "updated": "" })],
                                testCase.delta(), testCase.state(), testCase.now);
        compare(out.toPush.length, 1);
        compare(out.toPush[0].op, "create");
        compare(out.newState.pendingOps[0].op, "create");
    }

    function test_a_synced_event_nobody_touched_is_not_pushed() {
        const out = policy.plan([testCase.event()], testCase.delta(), testCase.state(), testCase.now);
        compare(out.toPush.length, 0);
        compare(out.newState.pendingOps.length, 0);
    }

    // --- offline, then back ---------------------------------------------------

    function test_a_queue_built_offline_drains_on_reconnect() {
        const local = [
            testCase.event({ "id": "evt-1", "googleId": "", "updated": "", "modifiedAt": testCase.late }),
            testCase.event({ "id": "evt-2", "googleId": "g-2", "title": "Retro",
                             "modifiedAt": testCase.late })
        ];
        const queue = [
            { "id": "evt-1", "op": "create", "googleId": "", "attempt": 3 },
            { "id": "evt-2", "op": "patch", "googleId": "g-2", "attempt": 3 }
        ];
        const out = policy.plan(local, testCase.delta({ "nextSyncToken": "tok-2" }),
                                testCase.state({ "pendingOps": queue }), testCase.now);
        compare(out.toPush.length, 2);
        compare(out.toPush[0].op, "create");
        compare(out.toPush[1].op, "patch");

        const done = policy.markPushed(local, out.newState, [
            { "id": "evt-1", "ok": true, "googleId": "g-1new", "etag": "\"9\"", "updated": testCase.now },
            { "id": "evt-2", "ok": true, "googleId": "g-2", "etag": "\"9\"", "updated": testCase.now }
        ]);
        compare(done.newState.pendingOps.length, 0, "an accepted op leaves the queue");
        compare(done.newState.syncToken, "tok-2", "the token is not a push's business");
        compare(done.events[0].googleId, "g-1new",
                "a create's id is the only record that the two are the same thing");
        compare(done.events[0].etag, "\"9\"");
        compare(done.events[0].updated, testCase.now);
        compare(done.events[0].modifiedAt, testCase.late,
                "the server answering is not a local edit");
    }

    function test_a_refused_push_stays_queued_and_earns_a_backoff() {
        const local = [testCase.event()];
        const queue = [{ "id": "evt-1", "op": "patch", "googleId": "g-1", "attempt": 1 }];
        const done = policy.markPushed(local, testCase.state({ "pendingOps": queue }),
                                       [{ "id": "evt-1", "ok": false, "error": "rate" }]);
        compare(done.newState.pendingOps.length, 1);
        compare(done.newState.pendingOps[0].attempt, 2);
        compare(done.events[0].googleId, "g-1", "a refusal changes nothing about the event");
    }

    function test_a_result_for_an_op_nobody_queued_is_ignored() {
        const local = [testCase.event()];
        const done = policy.markPushed(local, testCase.state(),
                                       [{ "id": "evt-1", "ok": true, "googleId": "g-hijack" }]);
        compare(done.events[0].googleId, "g-1");
        compare(done.newState.pendingOps.length, 0);
    }

    function test_an_unanswered_op_stays_queued_untouched() {
        const queue = [{ "id": "evt-1", "op": "patch", "googleId": "g-1", "attempt": 1 }];
        const done = policy.markPushed([testCase.event()],
                                       testCase.state({ "pendingOps": queue }), []);
        compare(done.newState.pendingOps.length, 1);
        compare(done.newState.pendingOps[0].attempt, 1, "no answer is not a failure");
    }

    // --- backoff --------------------------------------------------------------

    function test_backoff_doubles_from_a_second_and_stops_at_fifteen_minutes() {
        compare(policy.backoffMs(0), 0, "nothing has failed yet");
        compare(policy.backoffMs(1), 1000);
        compare(policy.backoffMs(2), 2000);
        compare(policy.backoffMs(3), 4000);
        compare(policy.backoffMs(10), 512000);
        compare(policy.backoffMs(11), 900000);
        compare(policy.backoffMs(500), 900000, "a laptop shut for a weekend comes back to a ceiling");
    }

    // --- instants -------------------------------------------------------------

    function test_instants_are_parsed_not_compared_as_text() {
        // The same moment, spelled three ways. A string comparison gets the
        // first pair wrong the day a payload drops its milliseconds.
        compare(policy.instantMs("2026-08-18T06:00:00Z"),
                policy.instantMs("2026-08-18T06:00:00.000Z"));
        compare(policy.instantMs("2026-08-18T07:00:00+01:00"),
                policy.instantMs("2026-08-18T06:00:00Z"));
        compare(policy.instantMs("not a date"), -1);
        compare(policy.instantMs(""), -1);
    }

    function test_an_event_with_no_local_stamp_loses() {
        // A hand-edited file, or one the migration never reached. We cannot
        // claim it is newer than a server change we can read the date of.
        verify(policy.remoteWins({ "modifiedAt": "" }, { "updated": testCase.early }));
    }

    // --- the whole path -------------------------------------------------------

    function test_a_cleared_guest_list_is_pushed_as_an_empty_list() {
        // The bug this guards is a field being *absent* from a PATCH body,
        // which is how "leave the guests alone" is spelled — so removing the
        // last guest would silently keep every one of them over there.
        const local = [testCase.event({ "guests": [], "modifiedAt": "2026-08-18T11:00:00.000Z" })];
        const out = policy.plan(local, testCase.delta(), testCase.state(), testCase.now);
        compare(out.toPush.length, 1);
        const body = mapping.toGoogle(out.toPush[0].event, "Europe/London", null);
        verify(body.hasOwnProperty("attendees"), "an absent list means unchanged, not cleared");
        compare(body.attendees.length, 0);
    }

    function test_a_pushed_event_keeps_the_meeting_room_it_was_pulled_with() {
        const local = [testCase.event({
            "guests": ["gmail:mira@example.com"],
            "otherAttendees": [{ "email": "room-4@resource.calendar.google.com", "resource": true }],
            "modifiedAt": "2026-08-18T11:00:00.000Z"
        })];
        const out = policy.plan(local, testCase.delta(), testCase.state(), testCase.now);
        const body = mapping.toGoogle(out.toPush[0].event, "Europe/London", null);
        compare(body.attendees.length, 2);
        compare(body.attendees[0].email, "room-4@resource.calendar.google.com");
        compare(body.attendees[0].resource, true);
        compare(body.attendees[1].email, "mira@example.com");
    }

    // --- a round has to settle ------------------------------------------------

    function test_an_edit_that_lost_the_conflict_is_not_pushed_anyway() {
        // Edited here, edited later over there. The server's copy is applied,
        // so the queued edit is now a push of the body this round just decided
        // against — the local edit would be discarded here and land there.
        const local = [testCase.event({ "modifiedAt": testCase.early })];
        const queue = [{ "id": "evt-1", "op": "patch", "googleId": "g-1", "attempt": 0 }];
        const out = policy.plan(local, testCase.delta({ "events": [testCase.remote()] }),
                                testCase.state({ "pendingOps": queue }), testCase.now);
        compare(out.toApplyLocally[0].op, "upsert");
        compare(out.toPush.length, 0, "the copy that lost does not go up");
        compare(out.newState.pendingOps.length, 0);
    }

    function test_a_pull_does_not_resurrect_an_event_a_queued_delete_is_about() {
        // The store dropped the event, so nothing local carries its googleId
        // and an upsert would arrive as a brand-new event with no id to land on.
        const queue = [{ "id": "evt-1", "op": "delete", "googleId": "g-1", "attempt": 0 }];
        const out = policy.plan([], testCase.delta({ "events": [testCase.remote()] }),
                                testCase.state({ "pendingOps": queue }), testCase.now);
        compare(out.toApplyLocally.length, 0, "a stale update must not bring it back");
        compare(out.toPush.length, 1);
        compare(out.toPush[0].op, "delete");
    }

    function test_a_create_accepted_after_the_event_was_deleted_becomes_a_delete() {
        // Deleted while the create was in flight. The googleId in the answer is
        // the only handle on that meeting; dropped, the invitation stands in
        // every guest's calendar and no later round can reach it.
        const queue = [{ "id": "evt-2", "op": "create", "googleId": "", "attempt": 0 }];
        const done = policy.markPushed([], testCase.state({ "pendingOps": queue }),
                                       [{ "id": "evt-2", "ok": true, "googleId": "g-9",
                                          "etag": "\"1\"", "updated": testCase.now }]);
        compare(done.newState.pendingOps.length, 1);
        compare(done.newState.pendingOps[0].op, "delete");
        compare(done.newState.pendingOps[0].googleId, "g-9");
    }

    function test_a_pull_applied_and_replanned_asks_for_nothing() {
        // The convergence check the whole design rests on: apply what a round
        // says, plan again on the same clock, and the second round is silent.
        const first = policy.plan([testCase.event()],
                                  testCase.delta({ "events": [testCase.remote()],
                                                   "nextSyncToken": "tok-2" }),
                                  testCase.state(), testCase.now);
        const second = policy.plan([first.toApplyLocally[0].event], testCase.delta(),
                                   first.newState, testCase.now);
        compare(second.toPush.length, 0, "a pull must not become a push next round");
        compare(second.newState.pendingOps.length, 0);
        compare(second.newState.syncToken, "tok-2");
    }
}
