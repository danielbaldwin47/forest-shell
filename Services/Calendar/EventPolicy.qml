// Every decision the event list makes, as pure functions over a plain array.
//
// `CalendarStore.qml` holds no arithmetic: it reads the file into `events`, and
// each mutation is `events = EventPolicy.something(events, …)` followed by a log
// line and a debounced write. That split is the whole reason this file exists —
// the store imports Quickshell and is therefore unreachable from `tests/`,
// while this is QtQuick-only and every case below is checkable offscreen
// (`tests/tst_eventpolicy.qml`).
//
// The functions are **non-mutating**. Each returns a fresh array of fresh event
// objects for the ones it touched, which matters twice: QML only notices a
// `var` property changing when it is assigned, and a same-length model that is
// edited in place does not rebuild its delegates (measured, #195).
//
// An event is:
//
//     { id, title, start, end, allDay, colour, guests: [contactId] }
//
// `start` and `end` are local wall-clock stamps (`"2026-08-18T09:15"`), never
// instants — see CalendarTime.qml for the argument. `end` is **exclusive**: an
// event 09:00-10:00 and one 10:00-11:00 do not overlap. An all-day event still
// carries stamps, at 00:00 on its first day and 00:00 on the day *after* its
// last, so one rule covers both kinds and nothing has to special-case `allDay`
// to know which days a thing is on.
import QtQuick

QtObject {
    id: policy

    /// The shortest an event may be made by dragging. Fifteen minutes is the
    /// grid's own snap, so a resize can never land between two lines.
    readonly property int minMinutes: 15

    property CalendarTime time: CalendarTime {}

    // --- identity -------------------------------------------------------------

    /// The next free `evt-N`.
    ///
    /// Deterministic and not a uuid, on purpose: a harness has to be able to
    /// say "the event this call just made is `evt-1`" without reading the file
    /// back first, and a person hand-editing the JSON has to be able to type an
    /// id. Ids that are not `evt-<number>` are ignored rather than rejected —
    /// a hand-written `standup` is a legal id, it just does not participate in
    /// the counter.
    function nextId(events: var): string {
        let highest = 0;
        for (const event of (events || [])) {
            const m = /^evt-(\d+)$/.exec(event && event.id ? event.id : "");
            if (m)
                highest = Math.max(highest, parseInt(m[1], 10));
        }
        return "evt-" + (highest + 1);
    }

    function indexOf(events: var, id: string): int {
        const list = events || [];
        for (let i = 0; i < list.length; i++)
            if (list[i] && list[i].id === id)
                return i;
        return -1;
    }

    function byId(events: var, id: string): var {
        const at = policy.indexOf(events, id);
        return at < 0 ? null : events[at];
    }

    // --- shape ----------------------------------------------------------------

    /// A copy with every field present and of the right type. What the store
    /// runs each entry of a hand-edited file through, so nothing downstream has
    /// to ask whether `guests` exists.
    ///
    /// **This function is the schema.** Everything it does not name is dropped
    /// on the next read, silently, which is why the Google sync fields are here
    /// rather than only in `GoogleEventPolicy`: `googleId`/`etag`/`updated` are
    /// what a pull matches and compares against, `modifiedAt` is the local half
    /// of that comparison, and `recurringEventId`/`originalStartTime` are what
    /// say an event is one instance of a series rather than a thing of its own.
    /// `otherAttendees` is the meeting room: attendees Google sent that the
    /// guest row deliberately does not draw, kept because a push sends the whole
    /// attendee list and an event that forgot its room gets pushed out of it.
    /// A local-only event simply has them all empty.
    function normalize(event: var): var {
        const raw = event || {};
        const guests = [];
        for (const guest of (Array.isArray(raw.guests) ? raw.guests : []))
            if (typeof guest === "string" && guest.length > 0 && guests.indexOf(guest) < 0)
                guests.push(guest);
        const others = [];
        const seenOther = [];
        for (const other of (Array.isArray(raw.otherAttendees) ? raw.otherAttendees : [])) {
            const email = (other && typeof other.email === "string") ? other.email.trim() : "";
            if (email.length === 0 || seenOther.indexOf(email) >= 0)
                continue;
            seenOther.push(email);
            others.push({ "email": email, "resource": other.resource === true });
        }
        return {
            "id": typeof raw.id === "string" ? raw.id : "",
            "title": typeof raw.title === "string" ? raw.title : "",
            "start": typeof raw.start === "string" ? raw.start : "",
            "end": typeof raw.end === "string" ? raw.end : "",
            "allDay": raw.allDay === true,
            "colour": typeof raw.colour === "string" ? raw.colour : "",
            "guests": guests,
            "otherAttendees": others,
            "googleId": typeof raw.googleId === "string" ? raw.googleId : "",
            "etag": typeof raw.etag === "string" ? raw.etag : "",
            "updated": typeof raw.updated === "string" ? raw.updated : "",
            "modifiedAt": typeof raw.modifiedAt === "string" ? raw.modifiedAt : "",
            "recurringEventId": typeof raw.recurringEventId === "string" ? raw.recurringEventId : "",
            "originalStartTime": typeof raw.originalStartTime === "string" ? raw.originalStartTime : ""
        };
    }

    /// `{ok, error}`. The error is a sentence, because it ends up in the log
    /// next to the file that produced it.
    function validate(event: var): var {
        const e = policy.normalize(event);
        if (!e.id)
            return { "ok": false, "error": "no id" };
        if (!policy.time.isStamp(e.start))
            return { "ok": false, "error": "start is not a stamp: " + e.start };
        if (!policy.time.isStamp(e.end))
            return { "ok": false, "error": "end is not a stamp: " + e.end };
        if (policy.time.diffMinutes(e.start, e.end) <= 0)
            return { "ok": false, "error": "ends before it starts" };
        return { "ok": true, "error": "" };
    }

    /// Everything in `raw` that is a usable event, normalized and sorted.
    /// Anything that is not is dropped and named in `rejected`, which is what
    /// the store logs — a silently vanished event is the worst outcome here.
    function sanitize(raw: var): var {
        const kept = [];
        const rejected = [];
        for (const entry of (Array.isArray(raw) ? raw : [])) {
            const check = policy.validate(entry);
            if (check.ok)
                kept.push(policy.normalize(entry));
            else
                rejected.push(((entry && entry.id) || "(no id)") + ": " + check.error);
        }
        return { "events": policy.sort(kept), "rejected": rejected };
    }

    /// Start first, then end, then id — total, so two runs over the same file
    /// draw the same picture.
    function sort(events: var): var {
        return (events || []).slice().sort(function (a, b) {
            if (a.start !== b.start)
                return a.start < b.start ? -1 : 1;
            if (a.end !== b.end)
                return a.end < b.end ? -1 : 1;
            return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
        });
    }

    // --- schema version -------------------------------------------------------

    /// The version this file writes. **v2** adds `modifiedAt`, the local half of
    /// the sync comparison — see `migrate`.
    readonly property int version: 2

    /// One events.json document, brought up to `version`.
    ///
    /// Returns `{version, events, changed}`. `changed` is the whole point: a
    /// migration that rewrites the file on every read is a file that is never
    /// at rest, and `CalendarStore` watches its own writes. It is true exactly
    /// once — on the read that found an older version — and false forever after.
    ///
    /// The v1 → v2 step is `modifiedAt`. Without it every pre-sync event has an
    /// empty local timestamp, and the last-writer-wins comparison reads that as
    /// "older than anything the server has ever said", so the first pull would
    /// quietly overwrite local edits made before sync was ever switched on. The
    /// honest answer is not the epoch and not now-forever: it is *the moment we
    /// noticed*, `nowStamp`, stamped once and then left alone. That makes a
    /// pre-existing event lose to a server change made after the upgrade and win
    /// against one made before it, which is the best a file with no history can
    /// say.
    ///
    /// An event that already carries a `modifiedAt` keeps it — a document
    /// half-written by a newer build is not re-stamped — and a document already
    /// at or past `version` is returned untouched, so a downgrade never
    /// rewrites a newer file into an older shape.
    function migrate(doc: var, nowStamp: string): var {
        const parsed = doc || {};
        const raw = Array.isArray(parsed) ? parsed : parsed.events;
        const events = Array.isArray(raw) ? raw : [];
        const was = typeof parsed.version === "number" ? parsed.version : 0;
        if (was >= policy.version)
            return { "version": was, "events": events, "changed": false };

        const out = [];
        for (const event of events) {
            const copy = {};
            for (const key in (event || {}))
                copy[key] = event[key];
            if (typeof copy.modifiedAt !== "string" || copy.modifiedAt.length === 0)
                copy.modifiedAt = nowStamp;
            out.push(copy);
        }
        return { "version": policy.version, "events": out, "changed": true };
    }

    /// `after`, with `modifiedAt` set to `nowStamp` on every event that is new
    /// or actually different from its counterpart in `before`.
    ///
    /// The store funnels every mutation through one commit, so this is the one
    /// place a local edit gets dated — a per-verb stamp would be six chances to
    /// forget one, and a forgotten stamp is an edit that loses every conflict it
    /// is ever in.
    ///
    /// "Different" ignores `modifiedAt` itself, so re-stamping is not itself a
    /// change and a re-commit of an untouched list dates nothing. It also
    /// ignores `etag`/`updated`: those are the server's answer arriving, not a
    /// local edit, and dating them would make every pull look like a local
    /// change and push it straight back.
    function stampChanged(before: var, after: var, nowStamp: string): var {
        const previous = before || [];
        return (after || []).map(function (event) {
            const old = policy.byId(previous, event && event.id ? event.id : "");
            if (old && policy.sameContent(old, event))
                return event;
            const copy = {};
            for (const key in (event || {}))
                copy[key] = event[key];
            copy.modifiedAt = nowStamp;
            return copy;
        });
    }

    /// Do two events say the same thing, ignoring the bookkeeping fields that
    /// are not a local edit (`modifiedAt`, `etag`, `updated`)?
    function sameContent(a: var, b: var): bool {
        const left = policy.normalize(a);
        const right = policy.normalize(b);
        left.modifiedAt = ""; right.modifiedAt = "";
        left.etag = ""; right.etag = "";
        left.updated = ""; right.updated = "";
        return JSON.stringify(left) === JSON.stringify(right);
    }

    // --- mutations ------------------------------------------------------------

    /// Add an event. `spec` may name its own `id`; without one it gets
    /// `nextId`. Returns the new list — invalid specs come back as the list
    /// unchanged, which the store notices by comparing lengths.
    function create(events: var, spec: var): var {
        const list = events || [];
        const made = policy.normalize(spec);
        if (!made.id)
            made.id = policy.nextId(list);
        if (!policy.validate(made).ok)
            return list;
        if (policy.indexOf(list, made.id) >= 0)
            return list;
        return policy.sort(list.concat([made]));
    }

    /// The list with `id` replaced by `changed(event)`'s answer. The one place
    /// an event object is copied, so no caller can edit one in place by
    /// accident.
    function replace(events: var, id: string, changed: var): var {
        const at = policy.indexOf(events, id);
        if (at < 0)
            return events || [];
        const next = policy.normalize(changed(policy.normalize(events[at])));
        if (!policy.validate(next).ok)
            return events;
        const out = events.slice();
        out[at] = next;
        return policy.sort(out);
    }

    /// Move an event to a new start, **keeping its duration**. That is the
    /// whole claim: dragging a 90-minute meeting to Thursday leaves it 90
    /// minutes long, and a move implemented as "set start" silently makes it
    /// something else.
    function move(events: var, id: string, newStart: string): var {
        if (!policy.time.isStamp(newStart))
            return events || [];
        return policy.replace(events, id, function (event) {
            const minutes = policy.time.diffMinutes(event.start, event.end);
            event.start = newStart;
            event.end = policy.time.addMinutes(newStart, minutes);
            return event;
        });
    }

    /// Move by whole days, which is what a month-grid drag does.
    function moveDays(events: var, id: string, delta: int): var {
        return policy.replace(events, id, function (event) {
            const minutes = policy.time.parseMinutes(event.start);
            const day = policy.time.addDays(policy.time.dayOf(event.start), delta);
            const start = policy.time.formatStamp(day, minutes);
            const length = policy.time.diffMinutes(event.start, event.end);
            event.start = start;
            event.end = policy.time.addMinutes(start, length);
            return event;
        });
    }

    /// Drag one edge. `edge` is `"start"` or `"end"`; `stamp` is where the
    /// pointer let go.
    ///
    /// The floor is enforced by moving the *dragged* edge, never the other one:
    /// pulling the bottom of a 30-minute event up past its top leaves a
    /// 15-minute event that still starts when it started. An event shortened
    /// past its opposite edge would otherwise flip, and a flipped event is one
    /// that fails `validate` and is dropped on the next read.
    function resize(events: var, id: string, edge: string, stamp: string, floor: int): var {
        if (!policy.time.isStamp(stamp))
            return events || [];
        const least = floor === undefined || floor === null || floor <= 0
                    ? policy.minMinutes : Math.round(floor);
        return policy.replace(events, id, function (event) {
            if (edge === "start") {
                const latest = policy.time.addMinutes(event.end, -least);
                event.start = policy.time.compare(stamp, latest) > 0 ? latest : stamp;
            } else {
                const earliest = policy.time.addMinutes(event.start, least);
                event.end = policy.time.compare(stamp, earliest) < 0 ? earliest : stamp;
            }
            return event;
        });
    }

    /// Invite someone. Adding a guest who is already on the event is a no-op
    /// and not a duplicate — the picker can fire the same call twice and the
    /// avatar row still shows one face.
    function addGuest(events: var, id: string, contactId: string): var {
        if (!contactId)
            return events || [];
        return policy.replace(events, id, function (event) {
            if (event.guests.indexOf(contactId) < 0)
                event.guests = event.guests.concat([contactId]);
            return event;
        });
    }

    function removeGuest(events: var, id: string, contactId: string): var {
        return policy.replace(events, id, function (event) {
            event.guests = event.guests.filter(function (guest) {
                return guest !== contactId;
            });
            return event;
        });
    }

    function retitle(events: var, id: string, title: string): var {
        return policy.replace(events, id, function (event) {
            event.title = title;
            return event;
        });
    }

    /// Pin an event's colour, or unpin it with `""`.
    ///
    /// Unpinning is worth having and is why this is not a one-liner in the
    /// store: `colour` empty means *the hash decides*, which is a different
    /// state from any of the eight names and the only way back to it once
    /// somebody has picked one. `HuePolicy.indexFor` reads the same two cases
    /// off the other end.
    function recolour(events: var, id: string, colour: string): var {
        const name = String(colour === undefined || colour === null ? "" : colour)
                     .trim().toLowerCase();
        return policy.replace(events, id, function (event) {
            event.colour = name;
            return event;
        });
    }

    /// Drop an event. Removing an id that is not there returns the list
    /// unchanged rather than failing: the caller may be a keybind pressed
    /// twice.
    function remove(events: var, id: string): var {
        return (events || []).filter(function (event) {
            return event.id !== id;
        });
    }

    // --- reading --------------------------------------------------------------

    /// Do two events share any time at all? Half-open, so back-to-back
    /// meetings do not.
    function overlaps(a: var, b: var): bool {
        if (!a || !b)
            return false;
        return policy.time.compare(a.start, b.end) < 0
            && policy.time.compare(b.start, a.end) < 0;
    }

    /// How many days an event shows on: 1 for the ordinary case, 3 for a
    /// Thursday-to-Saturday span. An event ending exactly at midnight belongs
    /// to the day before it, which is what makes an all-day event one day long
    /// rather than two.
    function spansDays(event: var): int {
        if (!event)
            return 0;
        const first = policy.time.dayOf(event.start);
        const last = policy.lastDay(event);
        if (!first || !last)
            return 0;
        return policy.time.diffDays(first, last) + 1;
    }

    function lastDay(event: var): string {
        const endDay = policy.time.dayOf(event.end);
        if (!endDay)
            return "";
        const endsAtMidnight = policy.time.parseMinutes(event.end) === 0;
        const startDay = policy.time.dayOf(event.start);
        if (endsAtMidnight && policy.time.compare(endDay, startDay) > 0)
            return policy.time.addDays(endDay, -1);
        return endDay;
    }

    /// Everything showing on a day, in order — including the middle day of a
    /// multi-day span, which is the case a naive `start.startsWith(day)` gets
    /// wrong.
    function forDay(events: var, iso: string): var {
        if (!policy.time.isDay(iso))
            return [];
        return policy.sort((events || []).filter(function (event) {
            const first = policy.time.dayOf(event.start);
            const last = policy.lastDay(event);
            return first && last
                && policy.time.compare(first, iso) <= 0
                && policy.time.compare(last, iso) >= 0;
        }));
    }

    /// The same over a run of days — a week view asks once rather than seven
    /// times.
    function forRange(events: var, fromIso: string, toIso: string): var {
        if (!policy.time.isDay(fromIso) || !policy.time.isDay(toIso))
            return [];
        return policy.sort((events || []).filter(function (event) {
            const first = policy.time.dayOf(event.start);
            const last = policy.lastDay(event);
            return first && last
                && policy.time.compare(first, toIso) <= 0
                && policy.time.compare(last, fromIso) >= 0;
        }));
    }

    /// Everything in `events` that shares time with `event`, itself excluded.
    function collisions(events: var, event: var): var {
        return (events || []).filter(function (other) {
            return other.id !== event.id && policy.overlaps(event, other);
        });
    }
}
