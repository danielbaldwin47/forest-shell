// What a sync round decides, as one pure function over plain objects.
//
// `GoogleSync.qml` runs `tools/gcal-sync.py`, hands what came back to `plan`,
// and does what it says: apply these to the store, push those to the helper.
// It holds no arithmetic, for the usual reason — it imports Quickshell and is
// therefore unreachable from `tests/`, while this file is QtQuick-only and
// every case below is checkable offscreen (`tests/tst_syncpolicy.qml`).
//
// The three shapes it moves between:
//
//   remoteDelta  { events: [ourEvent | {remove: googleId}], gone: bool,
//                  nextSyncToken: string }   ← GoogleEventPolicy.fromGoogle
//   state        { syncToken: string, pendingOps: [{id, op, googleId, attempt}] }
//   plan(...)    { toApplyLocally: [{op:"upsert", event} | {op:"remove", id, googleId}],
//                  toPush: [{id, op, googleId, event}],
//                  newState: state, needsFullSync: bool }
//
// A pending op names a **local id**, never a body. The body is built at push
// time from the event as it stands then (`GoogleEventPolicy.toGoogle`), which
// is what makes "collapse three edits into one push" true rather than merely
// intended: there is only ever one version of an event to send, the current
// one. It is also why `pendingOps` survives a restart cheaply — three strings
// per queued event, no event payloads duplicated into a second file.
//
// Two clocks meet here, and only one of them is trusted. `updated` is the
// server's, `modifiedAt` is ours, and every comparison is server-against-ours
// on the same event — never ours-against-now. A machine whose clock is an hour
// fast would otherwise win every conflict it took part in, permanently.
import QtQuick

QtObject {
    id: policy

    /// The first retry waits this long; each one after doubles.
    readonly property int backoffFirstMs: 1000

    /// …up to fifteen minutes. A ceiling and not an endless doubling because a
    /// laptop shut for a weekend would otherwise come back with a two-day wait
    /// queued, and the thing it is backing off from — a rate limit, a flaky
    /// link — is measured in minutes.
    readonly property int backoffCapMs: 900000

    // --- time -----------------------------------------------------------------

    /// An RFC3339 instant as epoch milliseconds, or `-1` for anything that is
    /// not one.
    ///
    /// Parsed rather than compared as text on purpose: Google writes
    /// `2026-08-18T06:00:00.000Z` and we write `2026-08-18T06:00:00.000Z` today,
    /// but a stamp with no fractional part, or one with an offset instead of a
    /// `Z`, is the same instant and sorts differently as a string. String
    /// comparison would be right until the first payload spelled differently.
    function instantMs(value: var): real {
        if (typeof value !== "string" || value.length === 0)
            return -1;
        const ms = Date.parse(value);
        return isNaN(ms) ? -1 : ms;
    }

    /// A UTC stamp as epoch milliseconds, or `-1` for anything that is not one.
    ///
    /// The difference from `instantMs` is the naked form. ECMAScript reads a
    /// date-time with no zone — `2026-10-25T00:30` — as **local** time, and the
    /// stamps the Google mapping asks about are UTC by construction, so parsing
    /// one naked is wrong by the local offset. That is invisible for most of the
    /// year and wrong for exactly the hour a DST change moves: the offset looked
    /// up for `00:30Z` on a European autumn Sunday decides whether an event sits
    /// at 01:30 or 02:30 locally, and the naked read asks about the wrong
    /// instant. A stamp that already names a zone (`Z`, `+02:00`) is left alone.
    function utcMs(stamp: var): real {
        if (typeof stamp !== "string" || stamp.length === 0)
            return -1;
        const zoned = /(?:Z|[+-]\d{2}:?\d{2})$/.test(stamp) ? stamp : stamp + "Z";
        const ms = Date.parse(zoned);
        return isNaN(ms) ? -1 : ms;
    }

    /// Does the server's copy win?
    ///
    /// **Equal means the server wins.** Not a coin toss: equal timestamps are
    /// what a freshly applied pull looks like on the very next round, so the
    /// tie has to resolve to "apply it again", which is a no-op, rather than
    /// "push it back", which is a write per sync forever.
    ///
    /// An unreadable or absent `modifiedAt` also loses. A local event with no
    /// local timestamp is one the migration never reached or a hand-edited
    /// file's — either way we cannot claim it is newer than a server change we
    /// can read the date of.
    function remoteWins(localEvent: var, remoteEvent: var): bool {
        const remote = policy.instantMs(remoteEvent ? remoteEvent.updated : "");
        const local = policy.instantMs(localEvent ? localEvent.modifiedAt : "");
        if (remote < 0)
            return local < 0;
        return local < 0 || remote >= local;
    }

    /// How long to wait before retry number `attempt`: 1s, 2s, 4s, … capped.
    ///
    /// Deterministic, with no jitter mixed in here. Jitter is a property of a
    /// fleet of clients hitting one server at the same second; we are one
    /// client, and a schedule a test can state exactly is worth more than a
    /// spread nobody can assert on. `attempt` 0 (nothing has failed) is `0`.
    function backoffMs(attempt: int): int {
        if (attempt <= 0)
            return 0;
        let wait = policy.backoffFirstMs;
        for (let i = 1; i < attempt && wait < policy.backoffCapMs; i++)
            wait = wait * 2;
        return Math.min(wait, policy.backoffCapMs);
    }

    /// What a finished helper run means: `{kind, lastError}`, where `kind` is
    /// `"ok"`, `"auth"` or `"error"`.
    ///
    /// `3` is the helper's "this account is not connected", which is a state and
    /// not an error: it is what a shell says when nobody has run the consent
    /// flow yet, and retrying it on a backoff would be a subprocess every few
    /// seconds forever. Everything else is an error, and its message is the
    /// **last** line the helper complained on — the helper narrates progress on
    /// stderr, so the earlier lines are what it was doing and the last one is
    /// what went wrong. A run that said nothing at all is named by its code, so
    /// the status line is never blank.
    ///
    /// `code` is a `var` because not every failure has an exit code: a run that
    /// exits 0 with something that is not JSON is classified here too, under a
    /// name (`"bad-json"`) rather than a number.
    function classifyExit(code: var, stderrTail: var): var {
        const spelled = String(code);
        if (spelled === "0")
            return { "kind": "ok", "lastError": "" };
        if (spelled === "3")
            return { "kind": "auth", "lastError": "not connected" };
        return { "kind": "error",
                 "lastError": policy.lastLine(stderrTail) || ("exit " + spelled) };
    }

    /// The last non-empty line of a stderr capture, trimmed. `""` for nothing.
    function lastLine(text: var): string {
        if (typeof text !== "string")
            return "";
        const lines = text.split("\n");
        for (let i = lines.length - 1; i >= 0; i--) {
            const line = lines[i].trim();
            if (line.length > 0)
                return line;
        }
        return "";
    }

    // --- the queue ------------------------------------------------------------

    function opIndex(ops: var, id: string): int {
        const list = ops || [];
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].id === id)
                return i;
        return -1;
    }

    /// One op per local event, in the order each event first appeared.
    ///
    /// Not simply "the last one wins", because two of the pairs mean something
    /// the last op alone does not say:
    ///
    ///   - **create then patch is still a create.** The event does not exist
    ///     over there yet, so a PATCH would be a 404 against an id we do not
    ///     have. The create carries the current state anyway — bodies are built
    ///     at push time — so nothing is lost by folding the edit into it.
    ///   - **create then delete is nothing at all.** An event made and dropped
    ///     while offline was never on the server; sending a create so we can
    ///     send a delete would put a meeting in every guest's inbox and then
    ///     take it out again.
    ///
    /// `attempt` carries across a fold as the highest of the two, so collapsing
    /// a queue does not reset a backoff that a failing event has earned.
    function dedupe(ops: var): var {
        const out = [];
        for (const raw of (ops || [])) {
            const op = raw || {};
            const id = typeof op.id === "string" ? op.id : "";
            const kind = op.op;
            if (id.length === 0 || ["create", "patch", "delete"].indexOf(kind) < 0)
                continue;
            const attempt = typeof op.attempt === "number" ? op.attempt : 0;
            const at = policy.opIndex(out, id);
            if (at < 0) {
                out.push({ "id": id, "op": kind,
                           "googleId": typeof op.googleId === "string" ? op.googleId : "",
                           "attempt": attempt });
                continue;
            }
            const held = out[at];
            const merged = {
                "id": id,
                "op": kind,
                "googleId": (typeof op.googleId === "string" && op.googleId.length > 0)
                            ? op.googleId : held.googleId,
                "attempt": Math.max(held.attempt, attempt)
            };
            if (held.op === "create" && kind === "delete") {
                out.splice(at, 1);
                continue;
            }
            if (held.op === "create" && kind === "patch")
                merged.op = "create";
            out[at] = merged;
        }
        return out;
    }

    // --- the round ------------------------------------------------------------

    /// Everything one sync round decides.
    ///
    /// The order inside is the order the reasoning has to happen in: what the
    /// server deleted is settled first, because it decides which local events
    /// still exist and therefore which queued ops are still about anything;
    /// then the surviving remote changes are weighed against local ones; then
    /// the queue is rebuilt from what is left.
    function plan(localEvents: var, remoteDelta: var, state: var, nowStamp: string): var {
        const local = localEvents || [];
        const delta = remoteDelta || {};
        const held = state || {};
        const heldToken = typeof held.syncToken === "string" ? held.syncToken : "";
        const queued = policy.dedupe(held.pendingOps);

        // A 410 is the server saying our token names a point in history it no
        // longer keeps. Nothing about the *local* half is invalid, so the
        // queue survives untouched and still goes up; only the token is
        // dropped, and an empty token is what makes the next pull a full one.
        // Applying a delta we know is incomplete is the one thing that would
        // lose data here, so this returns before any of it is read.
        if (delta.gone === true) {
            return {
                "toApplyLocally": [],
                "toPush": policy.pushable(local, queued),
                "newState": { "syncToken": "", "pendingOps": queued },
                "needsFullSync": true
            };
        }

        const toApply = [];
        const removedIds = [];
        const remoteEvents = Array.isArray(delta.events) ? delta.events : [];

        for (const item of remoteEvents) {
            if (!item || typeof item !== "object")
                continue;
            if (typeof item.remove !== "string")
                continue;
            // A cancellation with no id names nothing. The helper can produce
            // one from a payload whose `id` never arrived, and "remove the
            // event whose googleId is the empty string" would match every
            // local-only event on the calendar.
            if (item.remove.length === 0)
                continue;
            const victim = policy.byGoogleId(local, item.remove);
            removedIds.push(item.remove);
            if (!victim)
                continue;
            toApply.push({ "op": "remove", "id": victim.id, "googleId": item.remove });
        }

        // The googleIds a queued deletion is about. The event is already gone
        // from the store, so nothing else in this round knows they are on their
        // way out.
        const doomed = [];
        for (const op of queued) {
            if (op.op !== "delete")
                continue;
            const going = op.googleId.length > 0
                          ? op.googleId : policy.googleIdOf(policy.byId(local, op.id));
            if (going.length > 0)
                doomed.push(going);
        }

        for (const item of remoteEvents) {
            if (!item || typeof item !== "object" || typeof item.remove === "string")
                continue;
            const googleId = typeof item.googleId === "string" ? item.googleId : "";
            if (googleId.length === 0)
                continue;
            // An update to an event we are in the middle of deleting. Applying
            // it puts the event back on the calendar the user just cleared it
            // from — and it comes back as a *new* event, because the local one
            // is gone and there is no id left to land on. The delete goes up in
            // this same round, so skipping the upsert is also the answer that
            // agrees with where the server is about to be. This is not the
            // last-writer-wins comparison and cannot be: a deletion leaves no
            // `modifiedAt` behind to weigh, only an op in the queue.
            if (doomed.indexOf(googleId) >= 0)
                continue;
            const mine = policy.byGoogleId(local, googleId);
            if (mine && !policy.remoteWins(mine, item))
                continue;
            const event = policy.applied(item, mine, nowStamp);
            toApply.push({ "op": "upsert", "event": event });
        }

        // Ops for an event the server just cancelled are ops about nothing —
        // a PATCH would 404 and a create would resurrect a meeting that was
        // called off for everyone on it.
        // Local events this round is about to overwrite with the server's copy.
        const overwritten = [];
        for (const step of toApply)
            if (step.op === "upsert" && step.event && step.event.id)
                overwritten.push(step.event.id);

        const kept = queued.filter(function (op) {
            const googleId = op.googleId.length > 0
                             ? op.googleId : policy.googleIdOf(policy.byId(local, op.id));
            if (googleId.length > 0 && removedIds.indexOf(googleId) >= 0)
                return false;
            // An edit that lost the conflict. `reconcile` already declines to
            // *derive* an op for an event that lost, but a queued one is the
            // same body by another route: the push is built from the local copy
            // as it stands, and the copy as it stands is the one we are one
            // line away from replacing. Left in, it hands the server the
            // version the round just decided against — the local edit is
            // discarded here and applied over there, which is the one outcome
            // neither writer asked for. A queued *delete* is not an edit and
            // keeps its place.
            return op.op === "delete" || overwritten.indexOf(op.id) < 0;
        });

        const next = policy.reconcile(local, kept, toApply);
        return {
            "toApplyLocally": toApply,
            "toPush": policy.pushable(local, next),
            "newState": {
                "syncToken": typeof delta.nextSyncToken === "string" && delta.nextSyncToken.length > 0
                             ? delta.nextSyncToken : heldToken,
                "pendingOps": next
            },
            "needsFullSync": false
        };
    }

    /// The queue plus the ops nothing put in it.
    ///
    /// Two local states mean "the server has not heard this yet" all by
    /// themselves, whatever the queue remembers: an event with no `googleId`
    /// has never been uploaded, and an event that just won a conflict against
    /// the server holds a version the server does not. Deriving those from the
    /// events rather than trusting the queue is what makes the queue a cache —
    /// a write lost to a crash, or a calendar that existed before sync was
    /// switched on, is picked up on the next round instead of never.
    ///
    /// Events this round is about to overwrite or delete locally are excluded.
    /// They lost, and deriving a push from the copy that lost would undo the
    /// pull one line later — or, for a cancelled event, re-invite everyone to
    /// it.
    function reconcile(local: var, ops: var, toApply: var): var {
        const out = policy.dedupe(ops);
        const settled = [];
        for (const step of (toApply || [])) {
            if (step.op === "upsert" && step.event && step.event.id)
                settled.push(step.event.id);
            else if (step.op === "remove" && step.id)
                settled.push(step.id);
        }
        for (const event of (local || [])) {
            if (!event || typeof event.id !== "string" || event.id.length === 0)
                continue;
            if (settled.indexOf(event.id) >= 0)
                continue;
            if (policy.opIndex(out, event.id) >= 0)
                continue;
            const googleId = typeof event.googleId === "string" ? event.googleId : "";
            if (googleId.length === 0) {
                out.push({ "id": event.id, "op": "create", "googleId": "", "attempt": 0 });
                continue;
            }
            if (policy.instantMs(event.modifiedAt) > policy.instantMs(event.updated))
                out.push({ "id": event.id, "op": "patch", "googleId": googleId, "attempt": 0 });
        }
        // An op about an event that is gone locally and was never uploaded is
        // about nothing at all, and would otherwise sit in the queue file being
        // retried against nowhere for the life of the calendar.
        return out.filter(function (op) {
            return policy.byId(local, op.id) !== null || op.googleId.length > 0;
        });
    }

    /// The queue as push instructions, each carrying the event as it stands now.
    ///
    /// An op whose event has vanished locally is a delete if the server knows
    /// the event and nothing at all if it does not. An op that says `create`
    /// about an event that already has a `googleId` is a `patch` — that pair
    /// happens whenever a create was queued, pushed, and queued again before
    /// its result came back.
    function pushable(local: var, ops: var): var {
        const out = [];
        for (const op of (ops || [])) {
            const event = policy.byId(local, op.id);
            const googleId = (op.googleId && op.googleId.length > 0)
                             ? op.googleId : policy.googleIdOf(event);
            if (!event) {
                if (googleId.length > 0)
                    out.push({ "id": op.id, "op": "delete", "googleId": googleId, "event": null });
                continue;
            }
            if (op.op === "delete") {
                if (googleId.length > 0)
                    out.push({ "id": op.id, "op": "delete", "googleId": googleId, "event": null });
                continue;
            }
            const kind = googleId.length > 0 ? "patch" : "create";
            out.push({ "id": op.id, "op": kind, "googleId": googleId, "event": event });
        }
        return out;
    }

    /// What a losing local event becomes: the server's copy, wearing our id.
    ///
    /// `modifiedAt` is set to the server's `updated` rather than to now. The
    /// event's last writer *was* the server, and saying so is what makes the
    /// next round's comparison come out equal — remote wins, the upsert is
    /// applied again, nothing changes. Stamping it `now` would make our copy
    /// look newer than the server's every single time we pulled it, and every
    /// pull would be followed by a push of what we had just been given.
    function applied(remoteEvent: var, localEvent: var, nowStamp: string): var {
        const out = {};
        for (const key in (remoteEvent || {}))
            out[key] = remoteEvent[key];
        out.id = (localEvent && localEvent.id) ? localEvent.id : "";
        const updated = typeof out.updated === "string" ? out.updated : "";
        out.modifiedAt = updated.length > 0 ? updated : nowStamp;
        return out;
    }

    // --- results --------------------------------------------------------------

    /// The push's answers folded back in: `{events, newState}`.
    ///
    /// Takes the events as well as the state, because half of what a push
    /// returns is about an event — a create's `googleId` is the only record
    /// that the thing over there and the thing here are the same thing, and it
    /// arrives exactly once. Dropping it would make the next round create a
    /// second copy.
    ///
    /// `modifiedAt` is deliberately **not** touched. `googleId`/`etag`/`updated`
    /// are the server's answer arriving, not a local edit, and dating them as
    /// one would leave every pushed event looking newer than the server that
    /// just accepted it.
    ///
    /// A refused op keeps its place in the queue with `attempt` raised by one,
    /// which is what `backoffMs` reads. An answer about an op nobody queued is
    /// ignored rather than trusted.
    function markPushed(localEvents: var, state: var, results: var): var {
        const held = state || {};
        const queued = policy.dedupe(held.pendingOps);
        const kept = [];
        const stamped = {};

        for (const op of queued) {
            const answer = policy.resultFor(results, op.id);
            if (!answer) {
                kept.push(op);
                continue;
            }
            if (answer.ok !== true) {
                kept.push({ "id": op.id, "op": op.op,
                            "googleId": op.googleId, "attempt": op.attempt + 1 });
                continue;
            }
            if (op.op === "delete")
                continue;
            // The event went up and was deleted here while it was in flight.
            // There is nowhere to write the `googleId` back to, and it is the
            // only handle anyone will ever have on that meeting — dropped, the
            // invitation stands in every guest's calendar forever and no later
            // round can reach it, because nothing local remembers it exists.
            // So the answer turns straight back into a deletion. (An event
            // missing from `localEvents` already means "deleted" throughout
            // this file — see `pushable` — so the caller must pass the whole
            // calendar, not a window of it.)
            const answeredId = typeof answer.googleId === "string" ? answer.googleId : op.googleId;
            if (policy.byId(localEvents, op.id) === null) {
                if (answeredId.length > 0)
                    kept.push({ "id": op.id, "op": "delete",
                                "googleId": answeredId, "attempt": 0 });
                continue;
            }
            stamped[op.id] = {
                "googleId": answeredId,
                "etag": typeof answer.etag === "string" ? answer.etag : "",
                "updated": typeof answer.updated === "string" ? answer.updated : ""
            };
        }

        const events = (localEvents || []).map(function (event) {
            const mark = (event && event.id) ? stamped[event.id] : undefined;
            if (!mark)
                return event;
            const copy = {};
            for (const key in event)
                copy[key] = event[key];
            copy.googleId = mark.googleId;
            if (mark.etag.length > 0)
                copy.etag = mark.etag;
            if (mark.updated.length > 0)
                copy.updated = mark.updated;
            return copy;
        });

        return {
            "events": events,
            "newState": {
                "syncToken": typeof held.syncToken === "string" ? held.syncToken : "",
                "pendingOps": kept
            }
        };
    }

    function resultFor(results: var, id: string): var {
        for (const result of (results || []))
            if (result && result.id === id)
                return result;
        return null;
    }

    // --- lookups --------------------------------------------------------------

    function byId(events: var, id: string): var {
        for (const event of (events || []))
            if (event && event.id === id)
                return event;
        return null;
    }

    /// An event's `googleId` as a string, whatever shape the event is in. Not
    /// paranoia: a hand-edited events.json reaches here through `sanitize`, but
    /// a remote event straight out of `fromGoogle` and a test's literal do not.
    function googleIdOf(event: var): string {
        return (event && typeof event.googleId === "string") ? event.googleId : "";
    }

    function byGoogleId(events: var, googleId: string): var {
        if (typeof googleId !== "string" || googleId.length === 0)
            return null;
        for (const event of (events || []))
            if (event && event.googleId === googleId)
                return event;
        return null;
    }
}
