pragma Singleton

// The calendar's events and the people who can be invited to them, on disk.
//
// A raw `FileView` rather than `Core/SpecFile.qml`, and the difference is what
// the file *is*: SpecFile owns a knob tree — a schema, typed defaults,
// per-key `set`, migrations keyed on a version — and a list of events is a
// document. Nothing here has a default, and "the third event" is not a key.
//
// But every idiom SpecFile earned is copied verbatim, because they were all
// bought with a bug:
//
//   - `atomicWrites: true`, so a crash mid-write does not leave half a file;
//   - `printErrors: false`, because a missing file is the normal first run;
//   - `watchChanges: true` with a debounced reload, so a hand edit shows up;
//   - the write is debounced, and the text we last wrote is remembered so our
//     own write arriving back through the watcher is not reprocessed;
//   - `Component.onDestruction: flush()`, so a pending write is not lost to a
//     config reload or a clean quit. It is *not* a SIGTERM safety net —
//     measured in tools/calendar-harness.sh: a shell killed 200 ms after a
//     delete left the file holding the event, because a signal does not run QML
//     destruction. Anything that needs the file to be current waits for the
//     debounce; nothing may assert through the flush.
//
// Two files, two homes, because they are two kinds of thing.
// `Paths.calendarFile` is under XDG_DATA_HOME — the shell wrote it, on the
// user's behalf, and losing it loses something they typed.
// `Paths.contactsFile` is beside settings.json — a contact list is
// hand-editable, hand-copied between machines, and is config in every sense
// that matters. Both follow XDG overrides for free, which is exactly how the
// harnesses point them at a scratch directory.
//
// All arithmetic lives in EventPolicy.qml, which is QtQuick-only and therefore
// testable offscreen. This file reads, writes, logs and nothing else.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Core

Singleton {
    id: root

    /// The events, sanitized and sorted. Assigned whole on every change —
    /// never edited in place, because a `var` property mutated in place tells
    /// no binding anything (#195).
    property var events: []

    /// The people who can be invited. Seeded on first run so the guest picker
    /// has something to search on a machine that has never opened this file.
    property var contacts: []

    /// Both files have been read (or found missing and seeded). Anything that
    /// would rather not draw an empty calendar for a frame waits on this.
    readonly property bool ready: root.eventsSettled && root.contactsSettled

    property bool eventsSettled: false
    property bool contactsSettled: false

    readonly property string eventsPath: Paths.calendarFile
    readonly property string contactsPath: Paths.contactsFile

    /// The schema version stamped into the events file. The number itself lives
    /// in `EventPolicy` beside the migration that reads it, so the file and the
    /// arithmetic that upgrades it can never disagree about which version this
    /// build writes.
    readonly property int version: root.policy.version

    /// The contacts file has its own version and its own (so far empty) history.
    /// Sharing one number would have made a events-only migration silently
    /// restamp contacts.json as something it is not.
    readonly property int contactsVersion: 1

    property EventPolicy policy: EventPolicy {}
    property GuestPolicy guestPolicy: GuestPolicy {}

    /// What we last wrote, and a cooldown around it: `watchChanges` hands our
    /// own write straight back, and re-reading it would re-sort a list that is
    /// already sorted for no reason at all.
    property string lastWrittenText: ""

    // --- reading --------------------------------------------------------------

    /// Now, as an RFC3339 instant in UTC.
    ///
    /// UTC and not a local wall-clock stamp, on purpose: `modifiedAt` is only
    /// ever compared against Google's `updated`, which is an instant. Comparing
    /// an instant against a bare local time would be off by the offset, and
    /// right twice a year in London.
    function nowStamp(): string {
        return new Date().toISOString();
    }

    function readEvents(): void {
        const text = eventsFile.text();
        const parsed = JSON.parse(text.length > 0 ? text : "{}");
        const upgraded = root.policy.migrate(parsed, root.nowStamp());
        const clean = root.policy.sanitize(upgraded.events);
        for (const complaint of clean.rejected)
            Logger.warn("calendar", "dropping an event in " + root.eventsPath
                        + " — " + complaint);
        root.events = clean.events;
        if (!upgraded.changed)
            return;
        // Once, on the read that found the old file. `write()` is what makes it
        // stick, and the cooldown inside it is what stops our own write coming
        // back round as another migration.
        Logger.log("calendar", "migrated " + root.eventsPath + " to v" + root.version
                   + " (" + root.events.length + " event(s) stamped)");
        root.write();
    }

    function readContacts(): void {
        const text = contactsFile.text();
        const parsed = JSON.parse(text.length > 0 ? text : "{}");
        const raw = Array.isArray(parsed) ? parsed : parsed.contacts;
        const kept = [];
        for (const entry of (Array.isArray(raw) ? raw : [])) {
            if (!entry || typeof entry.id !== "string" || entry.id.length === 0)
                continue;
            kept.push({
                "id": entry.id,
                "name": typeof entry.name === "string" ? entry.name : entry.id,
                "email": typeof entry.email === "string" ? entry.email : "",
                "colour": typeof entry.colour === "string" ? entry.colour : ""
            });
        }
        root.contacts = kept;
    }

    /// The contact record behind an id, or null. `GuestPolicy` owns the lookup
    /// — this file holds no arithmetic, and a second search here is a second
    /// answer to what "the same contact" means.
    function contactById(id: string): var {
        return root.guestPolicy.contactFor(id, root.contacts);
    }

    // --- writing --------------------------------------------------------------

    function write(): void {
        writeTimer.stop();
        const out = { "version": root.version, "events": root.events };
        root.lastWrittenText = JSON.stringify(out, null, 2) + "\n";
        cooldownTimer.restart();
        eventsFile.setText(root.lastWrittenText);
    }

    /// Write now if a write is pending. Called on destruction, and by anything
    /// that is about to be measured on the file rather than on the log.
    function flush(): void {
        if (writeTimer.running)
            root.write();
    }

    /// Every verb below ends here, which is why the local edit clock is here and
    /// not in any of them: `stampChanged` dates the events that actually moved,
    /// and a verb added later cannot forget to.
    function commit(next: var): void {
        root.events = root.policy.stampChanged(root.events, next, root.nowStamp());
        writeTimer.restart();
        root.mutated();
    }

    /// A local edit landed. `Services/Calendar/GoogleSync.qml` debounces a push
    /// off this; nothing else listens. Emitted from `commit` and therefore from
    /// every verb, present and future, rather than from each of them.
    ///
    /// Deliberately **not** emitted by `applyRemote` below: a pull that fired a
    /// push would push back what it had just been given, on a loop that only
    /// ends when the debounce and the round trip happen to miss each other.
    signal mutated()

    // --- what the server said ---------------------------------------------------

    /// Apply what a sync round decided: `upserts` are whole events, `removes`
    /// are local ids. Answers how many of each actually landed, as
    /// `{added, updated, removed}`.
    ///
    /// Three things separate this from the verbs above, and each is a bug it
    /// exists to avoid:
    ///
    ///   - **no `stampChanged`.** `modifiedAt` is the local half of the
    ///     last-writer-wins comparison, and `SyncPolicy.applied` has already set
    ///     it to the server's own `updated`. Re-dating it now would make every
    ///     pulled event look newer than the server that sent it, and every pull
    ///     would be chased by a push of what had just arrived.
    ///   - **no `mutated`.** See the signal above.
    ///   - **an empty `id` means "new here".** `SyncPolicy.applied` leaves the id
    ///     blank for a remote event nothing local matched, because which local
    ///     event a `googleId` is belongs to the store. An id that *is* set but
    ///     names nothing is the opposite case — the event was deleted here while
    ///     the round was in flight — and is skipped rather than re-created, or a
    ///     delete the user just made would be undone by its own round trip.
    function applyRemote(upserts: var, removes: var): var {
        const gone = Array.isArray(removes) ? removes : [];
        let next = (root.events || []).filter(function (event) {
            return gone.indexOf(event.id) < 0;
        });
        const removed = root.events.length - next.length;
        let added = 0;
        let changed = 0;

        for (const raw of (Array.isArray(upserts) ? upserts : [])) {
            const event = root.policy.normalize(raw);
            if (event.id.length === 0) {
                event.id = root.policy.nextId(next);
                next = next.concat([event]);
                added += 1;
                continue;
            }
            const at = root.policy.indexOf(next, event.id);
            if (at < 0)
                continue;   // deleted here while the round was in flight
            next = next.slice();
            next[at] = event;
            changed += 1;
        }

        const clean = root.policy.sanitize(next);
        for (const complaint of clean.rejected)
            Logger.warn("calendar", "dropping a synced event — " + complaint);
        root.events = clean.events;
        writeTimer.restart();
        return { "added": added, "updated": changed, "removed": removed };
    }

    /// People a pull mentioned that the address book does not have, kept for as
    /// long as the shell runs and no longer.
    ///
    /// In memory and **not** written to `contacts.json`, which is the one
    /// decision here worth stating: that file is config — hand-written,
    /// hand-copied between machines, owned by the user — and a sync that grew it
    /// by one line per stranger on a meeting invitation would be the shell
    /// editing something the user thinks is theirs. Losing these on restart
    /// costs a display name: the guest id carries the address (`gmail:<email>`),
    /// so `GoogleEventPolicy.emailFor` still finds it and a push still invites
    /// the right person.
    function rememberContacts(people: var): int {
        const fresh = [];
        for (const person of (Array.isArray(people) ? people : [])) {
            if (!person || typeof person.id !== "string" || person.id.length === 0)
                continue;
            if (root.contactById(person.id))
                continue;
            if (fresh.some(function (seen) { return seen.id === person.id; }))
                continue;
            fresh.push({
                "id": person.id,
                "name": typeof person.name === "string" && person.name.length > 0
                        ? person.name : person.id,
                "email": typeof person.email === "string" ? person.email : "",
                "colour": ""
            });
        }
        if (fresh.length > 0)
            root.contacts = root.contacts.concat(fresh);
        return fresh.length;
    }

    // --- the verbs ------------------------------------------------------------
    //
    // Each is: ask the policy, log one line, queue a write. The log line is the
    // assertion seam 2 reads, so its shape is part of the contract and not a
    // debugging aid — tools/calendar-harness.sh greps these exact prefixes.

    /// Make an event on `dayIso`, `startMin` minutes after midnight, running
    /// `minutes` long. Returns its id, or `""` if the request made no sense.
    function createEvent(dayIso: string, startMin: int, minutes: int, title: string): string {
        const start = root.policy.time.formatStamp(dayIso, startMin);
        if (!start) {
            Logger.warn("calendar", "cannot create an event on " + dayIso + " — not a date");
            return "";
        }
        const length = minutes > 0 ? minutes : 60;
        const id = root.policy.nextId(root.events);
        const next = root.policy.create(root.events, {
            "id": id,
            "title": title && title.length > 0 ? title : "New event",
            "start": start,
            "end": root.policy.time.addMinutes(start, length),
            "allDay": false,
            "colour": "",
            "guests": []
        });
        if (next.length === root.events.length) {
            Logger.warn("calendar", "refused to create an event at " + start);
            return "";
        }
        root.commit(next);
        Logger.log("calendar", "create " + id + " " + start + " " + length
                   + "m \"" + (title && title.length > 0 ? title : "New event") + "\"");
        return id;
    }

    function moveEvent(id: string, newStart: string): bool {
        const before = root.policy.byId(root.events, id);
        if (!before)
            return false;
        const next = root.policy.move(root.events, id, newStart);
        const after = root.policy.byId(next, id);
        if (!after || after.start === before.start)
            return false;
        root.commit(next);
        Logger.log("calendar", "move " + id + " " + before.start + " -> " + after.start);
        return true;
    }

    function resizeEvent(id: string, edge: string, stamp: string): bool {
        const before = root.policy.byId(root.events, id);
        if (!before)
            return false;
        const next = root.policy.resize(root.events, id, edge, stamp, root.policy.minMinutes);
        const after = root.policy.byId(next, id);
        if (!after)
            return false;
        const was = root.policy.time.diffMinutes(before.start, before.end);
        const now = root.policy.time.diffMinutes(after.start, after.end);
        if (was === now && after.start === before.start)
            return false;
        root.commit(next);
        Logger.log("calendar", "resize " + id + " " + was + "m -> " + now + "m");
        return true;
    }

    /// Name an event that already exists. The quick-create panel's only verb:
    /// the drag committed the event, so what is left to say is what it is
    /// called. A rename to the title it already has logs nothing, so a panel
    /// dismissed without typing is silent rather than a spurious edit in the
    /// log seam 2 reads.
    function renameEvent(id: string, title: string): bool {
        const before = root.policy.byId(root.events, id);
        if (!before)
            return false;
        const name = title && title.length > 0 ? title : "New event";
        if (before.title === name)
            return false;
        root.commit(root.policy.retitle(root.events, id, name));
        Logger.log("calendar", "rename " + id + " \"" + name + "\"");
        return true;
    }

    /// Pin an event's hue by name, or hand it back to the hash with `""`.
    function recolourEvent(id: string, colour: string): bool {
        const before = root.policy.byId(root.events, id);
        if (!before)
            return false;
        const next = root.policy.recolour(root.events, id, colour);
        const after = root.policy.byId(next, id);
        if (!after || after.colour === before.colour)
            return false;
        root.commit(next);
        Logger.log("calendar", "colour " + id + " " + (after.colour || "auto"));
        return true;
    }

    function addGuest(id: string, contactId: string): bool {
        const before = root.policy.byId(root.events, id);
        if (!before)
            return false;
        // Asked for twice — from the picker and from a script, or from two
        // scripts. Not a failure, and not a second guest either. It gets a line
        // because silence here is indistinguishable from an add that never
        // arrived: a harness driving the same verb twice has to be able to tell
        // "already invited" from "the call did nothing at all".
        if (Array.isArray(before.guests) && before.guests.indexOf(contactId) >= 0) {
            Logger.log("calendar", "guest add " + id + " " + contactId + " (already)");
            return false;
        }
        const next = root.policy.addGuest(root.events, id, contactId);
        const after = root.policy.byId(next, id);
        if (!after || after.guests.length === before.guests.length)
            return false;
        root.commit(next);
        Logger.log("calendar", "guest add " + id + " " + contactId);
        return true;
    }

    function removeGuest(id: string, contactId: string): bool {
        const before = root.policy.byId(root.events, id);
        if (!before)
            return false;
        const next = root.policy.removeGuest(root.events, id, contactId);
        const after = root.policy.byId(next, id);
        if (!after || after.guests.length === before.guests.length)
            return false;
        root.commit(next);
        Logger.log("calendar", "guest remove " + id + " " + contactId);
        return true;
    }

    function deleteEvent(id: string): bool {
        if (!root.policy.byId(root.events, id))
            return false;
        root.commit(root.policy.remove(root.events, id));
        Logger.log("calendar", "delete " + id);
        return true;
    }

    // --- seeding --------------------------------------------------------------

    /// The people the guest picker offers on a machine that has never had a
    /// contacts file. Eight, because that is enough to make the picker's
    /// search worth typing into and few enough to read at a glance — and they
    /// are obviously samples, so nobody mistakes one for a real address.
    readonly property var sampleContacts: [
        { "id": "mira",  "name": "Mira Okonkwo",   "email": "mira@example.org",  "colour": "#7aa2f7" },
        { "id": "juno",  "name": "Juno Alvarez",   "email": "juno@example.org",  "colour": "#9ece6a" },
        { "id": "tabby", "name": "Tabitha Fenn",   "email": "tabby@example.org", "colour": "#e0af68" },
        { "id": "rune",  "name": "Rune Halvorsen", "email": "rune@example.org",  "colour": "#bb9af7" },
        { "id": "opal",  "name": "Opal Nakamura",  "email": "opal@example.org",  "colour": "#7dcfff" },
        { "id": "cass",  "name": "Cass Delacroix", "email": "cass@example.org",  "colour": "#f7768e" },
        { "id": "birch", "name": "Birch Odili",    "email": "birch@example.org", "colour": "#73daca" },
        { "id": "wren",  "name": "Wren Sadiq",     "email": "wren@example.org",  "colour": "#ff9e64" }
    ]

    /// No events file yet. Write an empty one rather than nothing at all: the
    /// file's existence is what tells the next reader the calendar is empty on
    /// purpose, and it gives a person something to hand-edit.
    function seedEvents(): void {
        Logger.log("calendar", "no " + root.eventsPath + " yet — seeding it empty");
        makeEventsDir.running = true;
    }

    function seedContacts(): void {
        Logger.log("calendar", "no " + root.contactsPath + " yet — seeding "
                   + root.sampleContacts.length + " sample contacts");
        root.contacts = root.sampleContacts;
        makeContactsDir.running = true;
    }

    // A debounced write pending when the shell reloads or quits is an event the
    // user just made and will not find again.
    Component.onDestruction: root.flush()

    Component.onCompleted: {
        // `blockLoading` does not read eagerly — asking for the text is what
        // forces the read, and every failure signal fires inside this call. So
        // by the line after it the answer is final either way, and no caller
        // can arrive before the file has had its say.
        eventsFile.text();
        Logger.stage("calendar store armed (" + root.eventsPath + ", "
                     + root.events.length + " event(s))");
    }

    FileView {
        id: eventsFile

        path: root.eventsPath
        // The one blocking read in the file, and it buys a real bug: the store
        // is a singleton, so it is constructed the first time anything touches
        // it — and if that first toucher is an IPC `create`, an asynchronous
        // read has not landed yet, `events` is still empty, and
        // `EventPolicy.nextId` answers `evt-1` on top of a calendar that
        // already has eleven of them. Measured exactly that way in
        // tools/calendar-harness.sh before this line existed. The file is one
        // small JSON and it is read once.
        blockLoading: true
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onFileChanged: reloadTimer.restart()

        onLoaded: {
            if (cooldownTimer.running && eventsFile.text() === root.lastWrittenText) {
                root.eventsSettled = true;
                return;   // our own write, arriving back through the watcher
            }
            try {
                root.readEvents();
            } catch (error) {
                // The last good list stays in place and the file is not
                // touched: a half-typed edit must not cost the user their
                // calendar.
                Logger.warn("calendar", "ignoring " + root.eventsPath + ": "
                            + error + " — keeping the last good events");
            }
            root.eventsSettled = true;
        }

        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.seedEvents();
            else
                Logger.warn("calendar", "could not read " + root.eventsPath + ": "
                            + FileViewError.toString(error));
            root.eventsSettled = true;
        }

        onSaveFailed: error => {
            Logger.warn("calendar", "could not write " + root.eventsPath + ": "
                        + FileViewError.toString(error));
        }
    }

    FileView {
        id: contactsFile

        path: root.contactsPath
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onFileChanged: contactsReloadTimer.restart()

        onLoaded: {
            try {
                root.readContacts();
            } catch (error) {
                Logger.warn("calendar", "ignoring " + root.contactsPath + ": "
                            + error + " — keeping the last good contacts");
            }
            root.contactsSettled = true;
        }

        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.seedContacts();
            else
                Logger.warn("calendar", "could not read " + root.contactsPath + ": "
                            + FileViewError.toString(error));
            root.contactsSettled = true;
        }

        onSaveFailed: error => {
            Logger.warn("calendar", "could not write " + root.contactsPath + ": "
                        + FileViewError.toString(error));
        }
    }

    Timer {
        id: reloadTimer
        interval: 100
        onTriggered: eventsFile.reload()
    }

    Timer {
        id: contactsReloadTimer
        interval: 100
        onTriggered: contactsFile.reload()
    }

    Timer {
        id: writeTimer
        interval: 250
        onTriggered: root.write()
    }

    Timer {
        id: cooldownTimer
        interval: 1000
    }

    // FileView writes the file, not the directory above it — and the calendar's
    // is two levels deep on a machine that has never run the shell.
    Process {
        id: makeEventsDir
        command: ["mkdir", "-p", root.eventsPath.slice(0, root.eventsPath.lastIndexOf("/"))]
        onExited: root.write()
    }

    Process {
        id: makeContactsDir
        command: ["mkdir", "-p", root.contactsPath.slice(0, root.contactsPath.lastIndexOf("/"))]
        onExited: contactsFile.setText(
            JSON.stringify({ "version": root.contactsVersion, "contacts": root.contacts }, null, 2) + "\n")
    }
}
