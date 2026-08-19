// Google Calendar's JSON <-> our event, both directions, and nothing else.
//
// Every byte of HTTP lives in `tools/gcal-sync.py`; every byte of storage lives
// in `CalendarStore.qml`. What is left between them is arithmetic and a lookup
// table, which is exactly the shape that survives at seam 1 — so it lives here
// and `tests/tst_googleeventpolicy.qml` owns it.
//
// Four decisions are worth stating, because each is a place a naive mapping is
// wrong and nothing notices for months:
//
//   - **The offset comes from the payload, and the machine's comes from the
//     caller.** Google answers each instance with the offset that was in force
//     *at that instant* (`…T09:15:00+01:00`), and our stamps are bare local
//     wall clock. Converting therefore needs two offsets, and the machine's is
//     the one this file must not go and read: `Date` here would make every case
//     below depend on the tester's `TZ`. It is an argument — a number, or a
//     function of the instant when one event straddles a DST change.
//
//   - **Google's all-day end is exclusive; ours is inclusive.** A one-day event
//     is `date: 2026-08-18` to `date: 2026-08-19` there and `2026-08-18` to
//     `2026-08-18` here. Off by one in either direction is a whole extra day on
//     screen, so both ends go through `CalendarTime.addDays`.
//
//   - **Eleven colours into eight hues does not come back.** `HuePolicy` owns
//     the table (it owns the wheel); Tomato, Flamingo and Tangerine are all
//     `ember`, and `ember` pushes back as Tangerine. The pull direction is the
//     lossy one and it is lossy on purpose — the alternative is a ninth and
//     tenth hue nobody designed.
//
//   - **A cancelled event is not an event.** With `singleEvents=true&
//     showDeleted=true`, a deletion arrives as a normal-looking object with
//     `status: "cancelled"`. Returning it as an event with a flag would put the
//     deletion one `if` away from being drawn; `{remove: googleId}` cannot be.
//
// This is a Services file that imports one Surfaces one, which is the wrong
// direction on paper. `HuePolicy` is a pure `QtObject` with no import but
// QtQuick — it is a policy that happens to live next to the surface that reads
// it — and the hue table belongs with the wheel it names. Duplicating the table
// here would be the real cost.
pragma ComponentBehavior: Bound
import QtQuick
import "../../Surfaces/Calendar"

QtObject {
    id: policy

    property CalendarTime time: CalendarTime {}
    property HuePolicy hues: HuePolicy {}

    /// The prefix a contact gets when Google names somebody the shell has never
    /// heard of. Namespaced rather than bare so a synthetic guest is visibly
    /// not a real address book entry; duplicates are avoided a step earlier, by
    /// `fromGoogle` asking the lookup by **email** before minting one.
    readonly property string syntheticPrefix: "gmail:"

    // --- instants ------------------------------------------------------------

    /// `"2026-08-18T09:15:00+01:00"` -> `{stamp: "2026-08-18T09:15",
    /// offsetMinutes: 60}`, or `null`.
    ///
    /// Seconds and fractional seconds are parsed and dropped: our grid's unit is
    /// a minute, and an event at `:15:30` is an event at `:15`. A payload with
    /// no zone at all (`Z` absent, offset absent) reports `offsetMinutes: null`,
    /// which the callers read as "already local" — that is what our own
    /// `toGoogle` emits, so it is the thing a round trip hands back.
    function parseInstant(value: var): var {
        if (typeof value !== "string")
            return null;
        const m = /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?(Z|z|[+-]\d{2}:?\d{2})?$/.exec(value.trim());
        if (!m)
            return null;
        const stamp = m[1] + "T" + m[2] + ":" + m[3];
        if (!policy.time.isStamp(stamp))
            return null;
        return { "stamp": stamp, "offsetMinutes": policy.parseOffset(m[4]) };
    }

    /// `"+01:00"` / `"-0530"` / `"Z"` -> minutes east of UTC. `null` for a
    /// missing zone, which is not the same claim as `0`.
    function parseOffset(text: var): var {
        if (typeof text !== "string" || text.length === 0)
            return null;
        if (text === "Z" || text === "z")
            return 0;
        const m = /^([+-])(\d{2}):?(\d{2})$/.exec(text);
        if (!m)
            return null;
        return (m[1] === "-" ? -1 : 1) * (parseInt(m[2], 10) * 60 + parseInt(m[3], 10));
    }

    /// The machine's offset for one instant, from whatever the caller passed:
    /// a number, or a function of the UTC stamp of that instant.
    ///
    /// The function form is the one that survives an event straddling a DST
    /// change — start and end then get different answers, which is the only
    /// correct one. `NaN` when the caller gave neither, and every conversion
    /// reads that as "leave the wall clock alone".
    ///
    /// Which is why nothing here goes through bare `Number`: `Number(null)`,
    /// `Number("")` and `Number([])` are all **0**, so an absent offset would
    /// arrive as the claim "this machine is on UTC" and quietly move every
    /// timed event by the payload's offset. Only an actual number, or a string
    /// that is one, counts — and `isFinite` rather than `isNaN` because an
    /// infinity would otherwise reach `addMinutes` as arithmetic.
    function machineOffset(local: var, utcStamp: string): real {
        const raw = (typeof local === "function") ? local(utcStamp) : local;
        const n = (typeof raw === "number") ? raw
                : ((typeof raw === "string" && raw.trim().length > 0) ? Number(raw) : NaN);
        return isFinite(n) ? Math.round(n) : NaN;
    }

    /// One Google instant as our local wall clock. `""` for anything unparseable
    /// — never a guess, the way `CalendarTime` refuses.
    ///
    /// The shift is `machine - payload`, and the machine's offset is asked for
    /// at the instant itself: `09:15+01:00` is `08:15` UTC, so a machine on
    /// `+02:00` that day shows `10:15`.
    function localStamp(dateTime: var, localOffset: var): string {
        const parsed = policy.parseInstant(dateTime);
        if (!parsed)
            return "";
        if (parsed.offsetMinutes === null)
            return parsed.stamp;
        const utc = policy.time.addMinutes(parsed.stamp, -parsed.offsetMinutes);
        const machine = policy.machineOffset(localOffset, utc);
        if (isNaN(machine))
            return parsed.stamp;
        return policy.time.addMinutes(parsed.stamp, machine - parsed.offsetMinutes);
    }

    // --- guests --------------------------------------------------------------

    /// Everybody on the event, as `{email, name}`, in payload order.
    ///
    /// Two kinds are dropped. A **resource** is a room or a projector, not a
    /// person, and our guest row draws faces. The account **itself** is dropped
    /// because Google puts the signed-in user in its own attendee list and our
    /// list means "who else" — pushing it back would also be pointless, since
    /// the API re-adds the organiser whatever we send.
    function attendeesOf(gevent: var): var {
        const raw = (gevent && Array.isArray(gevent.attendees)) ? gevent.attendees : [];
        const out = [];
        for (let i = 0; i < raw.length; i++) {
            const a = raw[i];
            if (!a || typeof a !== "object" || a.resource === true || a.self === true)
                continue;
            const email = typeof a.email === "string" ? a.email.trim() : "";
            if (email.length === 0)
                continue;
            const name = typeof a.displayName === "string" && a.displayName.length > 0
                ? a.displayName : email;
            out.push({ "email": email, "name": name });
        }
        return out;
    }

    /// The attendees `attendeesOf` threw away, in the shape a write accepts.
    ///
    /// This exists because dropping them from the guest row and dropping them
    /// from the *event* are different things. A pulled meeting carries its room
    /// as `{email: "…@resource.calendar.google.com", resource: true}`; our row
    /// draws faces and must not show it, but a later PATCH sends the full
    /// attendee list, so an event pushed back without it books a meeting out of
    /// its room. They ride along on the local event as `otherAttendees` and go
    /// back up untouched.
    ///
    /// `self` is not carried: Google puts the signed-in account in its own
    /// attendee list and re-adds it on every write, so echoing it back is at
    /// best a no-op — and `self` is output-only, so it is stripped here rather
    /// than sent. `resource` is kept, because it is what makes a room a room.
    function otherAttendeesOf(gevent: var): var {
        const raw = (gevent && Array.isArray(gevent.attendees)) ? gevent.attendees : [];
        const out = [];
        for (let i = 0; i < raw.length; i++) {
            const a = raw[i];
            if (!a || typeof a !== "object")
                continue;
            if (a.resource !== true && a.self !== true)
                continue;
            if (a.self === true && a.resource !== true)
                continue;
            const email = typeof a.email === "string" ? a.email.trim() : "";
            if (email.length === 0)
                continue;
            out.push({ "email": email, "resource": true });
        }
        return out;
    }

    /// The guest id for one address: the id of the contact that already owns it,
    /// or a synthetic one. `byEmail` is the caller's address book — a function
    /// from an address to a contact (or null), passed in so this file needs no
    /// store.
    function guestIdFor(email: string, byEmail: var): string {
        const found = typeof byEmail === "function" ? byEmail(email) : null;
        if (found && typeof found === "object" && typeof found.id === "string" && found.id.length > 0)
            return found.id;
        return policy.syntheticPrefix + email;
    }

    /// The contacts an event mentions that the address book does not have yet,
    /// for the store to append. Kept apart from `fromGoogle` so that function
    /// can return the event the plan says it returns and nothing else.
    function newContacts(gevent: var, byEmail: var): var {
        const out = [];
        const seen = [];
        const people = policy.attendeesOf(gevent);
        for (let i = 0; i < people.length; i++) {
            const person = people[i];
            const found = typeof byEmail === "function" ? byEmail(person.email) : null;
            if (found && typeof found === "object")
                continue;
            const id = policy.syntheticPrefix + person.email;
            if (seen.indexOf(id) >= 0)
                continue;
            seen.push(id);
            out.push({ "id": id, "name": person.name, "email": person.email, "synthetic": true });
        }
        return out;
    }

    /// The address to invite for one of our guest ids: the contact's, or the
    /// address inside a synthetic id, or `""`. `byId` is the address book the
    /// other way round.
    function emailFor(guestId: string, byId: var): string {
        const found = typeof byId === "function" ? byId(guestId) : null;
        if (found && typeof found === "object" && typeof found.email === "string" && found.email.length > 0)
            return found.email;
        const id = typeof guestId === "string" ? guestId : "";
        if (id.indexOf(policy.syntheticPrefix) === 0)
            return id.substring(policy.syntheticPrefix.length);
        return "";
    }

    // --- pull ----------------------------------------------------------------

    /// One item out of a `singleEvents=true&showDeleted=true` list, as either an
    /// event of ours or `{remove: googleId}`.
    ///
    /// `id` is left empty: which local event this is — an existing one matched
    /// by `googleId`, or the next id — is the store's answer, not this file's.
    /// `recurringEventId` and `originalStartTime` ride along **raw**, exactly as
    /// Google spelled them. They are identity, not a time we draw, and a
    /// converted identity would change the day the machine's offset changed.
    function fromGoogle(gevent: var, localOffset: var, byEmail: var): var {
        const g = gevent || {};
        const googleId = typeof g.id === "string" ? g.id : "";
        if (g.status === "cancelled")
            return { "remove": googleId };

        const start = g.start || {};
        const end = g.end || {};
        const allDay = typeof start.date === "string" && start.date.length > 0;

        let ourStart = "";
        let ourEnd = "";
        if (allDay) {
            ourStart = policy.time.isDay(start.date) ? start.date + "T00:00" : "";
            // Exclusive over there, inclusive here.
            const lastDay = typeof end.date === "string" && policy.time.isDay(end.date)
                ? policy.time.addDays(end.date, -1) : "";
            ourEnd = lastDay.length > 0 ? lastDay + "T00:00" : ourStart;
        } else {
            ourStart = policy.localStamp(start.dateTime, localOffset);
            ourEnd = policy.localStamp(end.dateTime, localOffset);
            if (ourEnd.length === 0)
                ourEnd = ourStart;
        }

        const guests = [];
        const people = policy.attendeesOf(g);
        for (let i = 0; i < people.length; i++) {
            const id = policy.guestIdFor(people[i].email, byEmail);
            if (id.length > 0 && guests.indexOf(id) < 0)
                guests.push(id);
        }

        const original = g.originalStartTime || {};
        const originalStamp = typeof original.dateTime === "string" ? original.dateTime
                            : (typeof original.date === "string" ? original.date : "");

        return {
            "id": "",
            "title": typeof g.summary === "string" ? g.summary : "",
            "start": ourStart,
            "end": ourEnd,
            "allDay": allDay,
            "colour": policy.hues.hueForGoogleColor(g.colorId),
            "guests": guests,
            "otherAttendees": policy.otherAttendeesOf(g),
            "googleId": googleId,
            "etag": typeof g.etag === "string" ? g.etag : "",
            "updated": typeof g.updated === "string" ? g.updated : "",
            "recurringEventId": typeof g.recurringEventId === "string" ? g.recurringEventId : "",
            "originalStartTime": originalStamp
        };
    }

    // --- push ----------------------------------------------------------------

    /// The request body for one of our events.
    ///
    /// Timed instants go up **naive plus `timeZone`** — `2026-08-18T09:15:00`
    /// with `Europe/Berlin` — rather than with an offset. That is a supported
    /// spelling, and it is the only one this file can write without being told
    /// the machine's offset a second time; the zone is the honest statement of
    /// what our bare stamp meant anyway.
    ///
    /// `recurringEventId` and `originalStartTime` are deliberately absent: they
    /// are read-only on the API, and an instance edit is a PATCH *at the
    /// instance's own id*, which is transport, not body.
    ///
    /// `attendees` is **always** present and always the whole list — our guests
    /// plus whatever `otherAttendees` carried through from the pull. See the
    /// note at the assignment: an omitted list is unchanged, not cleared.
    ///
    /// `tz` must be a real zone. An empty one leaves a naive `dateTime` the API
    /// rejects outright, so the caller states the machine's zone; the helper
    /// (`tools/gcal-sync.py`) fills one in as a backstop.
    function toGoogle(event: var, tz: var, byId: var): var {
        const e = event || {};
        const zone = typeof tz === "string" ? tz : "";
        const body = { "summary": typeof e.title === "string" ? e.title : "" };

        if (e.allDay === true) {
            const startDay = policy.time.dayOf(e.start);
            const lastDay = policy.time.dayOf(e.end);
            body.start = { "date": startDay };
            // Inclusive here, exclusive over there.
            body.end = { "date": lastDay.length > 0 ? policy.time.addDays(lastDay, 1)
                                                    : policy.time.addDays(startDay, 1) };
        } else {
            body.start = policy.instantBody(e.start, zone);
            body.end = policy.instantBody(e.end, zone);
        }

        const colorId = policy.hues.googleColorForHue(e.colour);
        if (colorId.length > 0)
            body.colorId = colorId;

        const attendees = [];
        const seen = [];
        const carried = Array.isArray(e.otherAttendees) ? e.otherAttendees : [];
        for (let i = 0; i < carried.length; i++) {
            const other = carried[i] || {};
            const email = typeof other.email === "string" ? other.email.trim() : "";
            if (email.length === 0 || seen.indexOf(email) >= 0)
                continue;
            seen.push(email);
            const entry = { "email": email };
            if (other.resource === true)
                entry.resource = true;
            attendees.push(entry);
        }
        const guests = Array.isArray(e.guests) ? e.guests : [];
        for (let i = 0; i < guests.length; i++) {
            const email = policy.emailFor(guests[i], byId);
            if (email.length === 0 || seen.indexOf(email) >= 0)
                continue;
            seen.push(email);
            attendees.push({ "email": email });
        }
        // Always spelled out, empty included. `attendees` absent from a PATCH
        // means "leave the guest list alone", so an event whose last guest was
        // removed here would keep every one of them over there — the one shape
        // of edit that cannot be expressed by omission.
        body.attendees = attendees;

        return body;
    }

    /// One end of a timed event, as Google's `{dateTime, timeZone}`.
    function instantBody(stamp: var, tz: string): var {
        const out = { "dateTime": policy.time.isStamp(stamp) ? stamp + ":00" : "" };
        if (tz.length > 0)
            out.timeZone = tz;
        return out;
    }
}
