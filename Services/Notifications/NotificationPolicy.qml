// What happens to one arriving notification, as pure functions (#42).
//
// Split out of Services/Notifications/Notifications.qml for the same reason
// Core/Tokens.qml is split out of Core/Theme.qml: this file imports nothing but
// QtQuick, so tests/ can reach it (Quickshell's QML modules are compiled into
// the quickshell binary, and qmltestrunner cannot load them). The singleton
// next door owns the server, the popup list and the state write; every *rule*
// is here.
//
// The rules, in the order they are applied:
//
//   1. the per-app rule the user set — normal / silent (history only) /
//      blocked (nothing at all);
//   2. the freedesktop `transient` hint, which decides history, not the popup;
//   3. suppression — DND, a fullscreen focus, an open notification center —
//      which decides the popup, never the history.
//
// Critical urgency has exactly one exemption, and #9 names it: DND. It does not
// break through a fullscreen focus or an open center, because both of those are
// cases where the user is already looking at something the popup would cover.
import QtQuick

QtObject {
    id: policy

    // --- urgency -------------------------------------------------------------

    // The freedesktop levels, which are also `NotificationUrgency`'s values.
    // Named here rather than imported because this file may not import
    // Quickshell; the numbers are the wire protocol's and cannot drift.
    readonly property int urgencyLow: 0
    readonly property int urgencyNormal: 1
    readonly property int urgencyCritical: 2

    /// Urgency as a name. Everything user-facing and everything persisted uses
    /// the name: a record outlives the build that wrote it, and a name survives
    /// a renumbering that a `2` would not.
    ///
    /// An unrecognised level reads as normal — a client must not be able to
    /// promote itself to critical by sending something off the table.
    function urgencyName(urgency: var): string {
        if (urgency === urgencyLow)
            return "low";
        if (urgency === urgencyCritical)
            return "critical";
        return "normal";
    }

    // --- app identity --------------------------------------------------------

    /// The key a per-app rule is stored under, and the key history groups by.
    ///
    /// The desktop entry wins over the app name because it is the stable id:
    /// `appName` is a display string, localized by whatever the client felt
    /// like, and a rule set on one machine's locale has to keep matching on
    /// another's. Case-folded once, here, so no lookup ever has to think about
    /// casing.
    ///
    /// An app that supplies neither has no key. That is not the same as being
    /// blocked — it simply cannot be ruled on, and notifies as normal.
    function appKey(desktopEntry: var, appName: var): string {
        const entry = typeof desktopEntry === "string" ? desktopEntry.trim() : "";
        if (entry !== "")
            return entry.toLowerCase();
        const name = typeof appName === "string" ? appName.trim() : "";
        return name.toLowerCase();
    }

    // --- per-app rules -------------------------------------------------------

    /// The whole vocabulary. A three-way state, not two booleans, because
    /// "silent" and "blocked" differ in whether the notification is remembered
    /// — and that is the distinction #43's rules UI is built on.
    readonly property var rules: ["normal", "silent", "blocked"]

    /// The rule for an app, from `notifications.apps` in settings.json.
    ///
    /// That object arrives hand-editable and unvalidated, so both halves are
    /// forgiving: the key is matched case-insensitively, and a value that is
    /// not a rule falls back to "normal" with a warning. The safe reading of
    /// nonsense is "notify" — silently swallowing someone's notifications
    /// because they typed "mute" is the one outcome that must not happen.
    function ruleFor(apps: var, key: string): string {
        if (!key || apps === null || typeof apps !== "object" || Array.isArray(apps))
            return "normal";

        let raw;
        for (const candidate in apps)
            if (candidate.trim().toLowerCase() === key) {
                raw = apps[candidate];
                break;
            }
        if (raw === undefined)
            return "normal";

        const rule = typeof raw === "string" ? raw.trim().toLowerCase() : raw;
        if (rules.indexOf(rule) >= 0)
            return rule;

        console.warn("notifications: " + JSON.stringify(raw) + " is not a notification rule for "
                     + key + " — using normal");
        return "normal";
    }

    // --- timeouts ------------------------------------------------------------

    /// Bounds on any timeout the shell will honour. The floor stops a client
    /// from posting a toast that is gone before it is read; the ceiling stops
    /// one from pinning a card to the screen for an hour. Critical's authored
    /// default of 0 is not a timeout and is not bounded by these — it means
    /// "until acknowledged".
    readonly property int minTimeoutMs: 1000
    readonly property int maxTimeoutMs: 300000

    /// How long this notification stays on screen, in ms, or 0 for "until it is
    /// dismissed".
    ///
    /// `clientMs` is the client's own expire-timeout hint as Quickshell hands
    /// it over — **milliseconds**, with -1 for "the server decides". It is
    /// ignored unless the user asks for it, because nearly every client passes
    /// a hardcoded 5000 it never thought about, and honouring that would make
    /// the urgency table dead settings.
    ///
    /// Milliseconds is measured, not read: the capability survey (#4) recorded
    /// `Notification.expireTimeout` as seconds, this file multiplied by 1000 on
    /// that reading, and a live session showed every honoured timeout pinned to
    /// the five-minute ceiling (#74). The property is typed `double` in the
    /// qmltypes, which is what made the wrong reading plausible — so the unit
    /// is not recoverable from the type, only from the test below it.
    function timeoutMs(urgency: var, clientMs: var, settings: var): int {
        const table = (settings && settings.timeouts) || {};

        if (settings && settings.honorClientTimeout && typeof clientMs === "number"
                && clientMs >= 0) {
            // 0 is the freedesktop spec's "never expire", not "expire now".
            if (clientMs === 0)
                return 0;
            return Math.round(Math.min(maxTimeoutMs, Math.max(minTimeoutMs, clientMs)));
        }

        const authored = table[urgencyName(urgency)];
        // Config resolves every leaf, so this fallback is unreachable through
        // the shell — but an undefined interval is a Timer that never fires,
        // and a notification that never leaves the screen is the worst failure
        // this file has available.
        return typeof authored === "number" ? Math.max(0, Math.round(authored)) : 8000;
    }

    // --- the delivery decision -----------------------------------------------

    /// What is currently stopping popups from showing, or "" if nothing is.
    ///
    /// Only the three *situational* reasons — the ones that are true of the
    /// moment rather than of the notification. `context` is
    /// `{ urgency, dnd, fullscreen, centerOpen }`, and the urgency is here for
    /// critical's one exemption.
    ///
    /// Split out of `decide()` so the shell has one place that knows this
    /// cascade: the service reports it live for the bar indicator to explain
    /// itself with, and a fourth reason should not mean editing two files.
    function suppressionOf(context: var): string {
        if (context.dnd && context.urgency !== urgencyCritical)
            return "dnd";
        if (context.fullscreen)
            return "fullscreen";
        if (context.centerOpen)
            return "center";
        return "";
    }

    /// `{ popup, history, reason }` for one notification.
    ///
    /// `context` is `{ rule, urgency, transient, dnd, fullscreen, centerOpen }`.
    /// `reason` is the empty string when the popup shows, and otherwise names
    /// the rule that stopped it — it is what the log line says, so "why did I
    /// not see that" has an answer that does not need a debugger.
    function decide(context: var): var {
        // Blocked is the only outcome that leaves no trace at all (#43).
        if (context.rule === "blocked")
            return { popup: false, history: false, reason: "blocked" };

        // The `transient` hint is a client saying "this is a progress blip, not
        // news". It decides remembering, never showing — which is what keeps
        // history from filling up with volume steps.
        const history = !context.transient;

        if (context.rule === "silent")
            return { popup: false, history: history, reason: "silent" };

        const suppressed = suppressionOf(context);
        return { popup: suppressed === "", history: history, reason: suppressed };
    }

    // --- history records -----------------------------------------------------

    /// One history row, normalized. Every field is present and of the declared
    /// type whatever the client sent, because these rows are bound to directly
    /// by the center (#43) and an `undefined` in a `Text` is a warning per
    /// frame — for a row that may have been written by an older build.
    ///
    /// `serverId` is the freedesktop daemon's notification id, kept only for
    /// correlating a row with a popup that is still on screen. It is **not** an
    /// identity: that counter restarts at 1 with every server and history does
    /// not, so one restart is enough to put two different rows in the list
    /// under the same number (#76). `key` is the identity.
    function record(fields: var): var {
        const source = fields || {};
        const time = typeof source.time === "number" ? source.time : Date.now();
        const seq = typeof source.seq === "number" ? source.seq : 0;
        const appKey = text(source.appKey);
        return {
            key: keyFor(time, seq, appKey),
            seq: seq,
            serverId: typeof source.serverId === "number" ? source.serverId : 0,
            time: time,
            appKey: appKey,
            appName: text(source.appName),
            appIcon: text(source.appIcon),
            image: persistableImage(source.image),
            summary: text(source.summary),
            body: text(source.body),
            urgency: urgencyName(urgencyValue(source.urgency))
        };
    }

    /// A history row's identity (#76) — what the center (#43) will key its
    /// delegates on, and what "dismiss this row" will name.
    ///
    /// Recomputed on every `record()` rather than carried through one, so it is
    /// the same value before a write and after a read and a row that predates
    /// it gets one for free. It does still land in state.json, because a record
    /// is persisted whole; that copy is never read back as the key.
    ///
    /// All three parts earn their place: `seq` is what cannot repeat within a
    /// run of history, `time` is what keeps a row remembered before the state
    /// file has loaded from landing on a stored seq, and `appKey` goes last so
    /// its contents cannot be confused for a separator.
    function keyFor(time: var, seq: var, appKey: var): string {
        return String(time) + ":" + String(seq) + ":" + text(appKey);
    }

    /// The sequence number for the next row: one above everything in the
    /// history in hand, and one above `floor`.
    ///
    /// Both halves are needed. The list alone is not a high-water mark — the
    /// center dismisses single rows (#43) and lowering `historyLimit` truncates
    /// it, so the highest number issued can leave — which is why `floor` is the
    /// counter persisted beside the list in state.json. And the counter alone
    /// is not enough either: the state file is read lazily, so a notification
    /// can be remembered before the floor has arrived, and the rows already in
    /// hand are the only thing that number must not land on.
    function nextSeq(history: var, floor: var): int {
        const list = Array.isArray(history) ? history : [];
        let highest = typeof floor === "number" && floor > 0 ? Math.floor(floor) : 0;
        for (const entry of list)
            highest = Math.max(highest, seqOf(entry));
        return highest + 1;
    }

    /// A row's sequence number, or 0 for a row that has none — hand-written, or
    /// from a build that predates the key. Zero holds nothing back and is not
    /// an identity; `readHistory` is what issues one.
    function seqOf(entry: var): int {
        return entry !== null && typeof entry === "object" && typeof entry.seq === "number"
             ? entry.seq : 0;
    }

    /// An image worth writing to disk. Inline image data lives in Quickshell's
    /// own image provider, keyed by a notification that will not exist after a
    /// restart — persisting that URL would hand the center a permanently broken
    /// image. A path is still a path tomorrow.
    function persistableImage(image: var): string {
        const value = text(image);
        return value.startsWith("image://") ? "" : value;
    }

    /// Newest first, bounded. Returns a new list: the service binds to its
    /// history, and an in-place push would change the value under a binding
    /// that then never re-evaluates.
    function remember(history: var, entry: var, limit: int): var {
        const list = Array.isArray(history) ? history : [];
        if (limit <= 0)
            return [];
        return [entry].concat(list).slice(0, limit);
    }

    /// History as read back from state.json, which is disposable and
    /// hand-editable (#21): anything that is not a record is dropped and the
    /// rest of the list still loads. One wrecked row costs one row.
    ///
    /// The limit is applied on the way in as well as on the way out, because it
    /// may have been lowered since the file was written.
    /// A row that arrives without a sequence number is given one here, above
    /// every number the file already carries — a row hand-added to state.json,
    /// or written by the build that predates the key (#76), still comes back
    /// with an identity nothing else in the list shares. Newest first, so the
    /// head gets the highest and the next arrival counts on from there.
    function readHistory(raw: var, limit: int): var {
        if (!Array.isArray(raw) || limit <= 0)
            return [];
        const rows = raw
            .filter(entry => entry !== null && typeof entry === "object" && !Array.isArray(entry)
                    && typeof entry.time === "number")
            .slice(0, limit);

        let highest = 0;
        for (const entry of rows)
            highest = Math.max(highest, seqOf(entry));

        return rows.map((entry, index) => record(seqOf(entry) > 0
            ? entry
            : Object.assign({}, entry, { seq: highest + rows.length - index })));
    }

    // --- what history says (#71) ---------------------------------------------

    /// Every app history remembers, as the key a rule is stored under — the
    /// settings tab's "every app that has ever notified" (#54), which is really
    /// "every app inside `historyLimit`". An app that falls off the end of
    /// history loses its row unless it has a rule, and a rule is exactly what
    /// keeps it listed, so nothing the user has said anything about can vanish.
    ///
    /// Sorted and unique because the tab draws one row per app and merges this
    /// with two other lists: an order that depended on when an app last
    /// notified would move rows under the pointer while the window is open.
    ///
    /// An app with no key is dropped — it cannot be ruled on (see `appKey`), so
    /// a row for it would be a three-way control that writes nothing.
    function knownApps(history: var): var {
        const apps = [];
        for (const entry of rowsOf(history)) {
            const key = text(entry.appKey);
            if (key !== "" && apps.indexOf(key) < 0)
                apps.push(key);
        }
        return apps.sort();
    }

    /// How many rows arrived at or after `since` — the number the lock screen
    /// shows, and only ever as a number (#9, #30).
    ///
    /// "Since the lock went up" and not "unread", because nothing in the shell
    /// marks a notification read: the center (#43) dismisses rows, which is a
    /// different act, and a count of everything in history would put a hundred
    /// on the strip of a lock nobody had been away from.
    ///
    /// Counted over history rather than tallied as notifications arrive so that
    /// the count is a function of state and not of events — it comes back right
    /// after a hot reload, and it cannot drift from the list it describes.
    /// Silent apps are in it: the strip answers "what is waiting", not "what
    /// interrupted you", and silent asked for no popup, not for no record.
    ///
    /// A `since` of zero or less is "the lock is not up", and counts nothing —
    /// a floor of 0 would put the whole of history on the strip.
    function countSince(history: var, since: var): int {
        if (typeof since !== "number" || since <= 0)
            return 0;
        let count = 0;
        for (const entry of rowsOf(history))
            if (typeof entry.time === "number" && entry.time >= since)
                count++;
        return count;
    }

    // --- what the center shows (#43) -----------------------------------------

    /// History as the center draws it: one entry per app, newest app first,
    /// rows inside a group still newest first.
    ///
    /// `{ appKey, appName, appIcon, count, latest, rows }`. The order is the
    /// order the apps appear in history, which — history being newest first —
    /// is "the app that notified most recently is at the top", and it is stable
    /// while nothing arrives. Sorting by name instead would put a burst from
    /// one app under a group the user has to go looking for.
    ///
    /// `appName` and `appIcon` come off the newest row of the group rather than
    /// the oldest: an app that has changed either since is displayed as it
    /// describes itself now.
    ///
    /// Rows whose app has no key (see `appKey`) are kept, in a group of their
    /// own keyed `""`. They cannot be *ruled* on, but they are in history and
    /// history has to be clearable — a row that cannot be grouped and so is
    /// never drawn is a row nothing can dismiss.
    function groups(history: var): var {
        const out = [];
        const byKey = ({});
        for (const entry of rowsOf(history)) {
            const key = text(entry.appKey);
            let group = byKey[key];
            if (group === undefined) {
                group = {
                    appKey: key,
                    // The name is what a person reads, and a keyless row has
                    // only ever had one of these. Falling back to the key keeps
                    // a group from drawing a blank header.
                    appName: text(entry.appName) || key,
                    appIcon: text(entry.appIcon),
                    count: 0,
                    latest: 0,
                    rows: []
                };
                byKey[key] = group;
                out.push(group);
            }
            group.rows.push(entry);
            group.count++;
            if (typeof entry.time === "number")
                group.latest = Math.max(group.latest, entry.time);
        }
        return out;
    }

    /// History without one app's rows — the center's per-app clear.
    ///
    /// Matched on the folded key both sides, so clearing `firefox` takes the
    /// row a client sent as `Firefox` with it. A new list, for the reason
    /// `remember` returns one.
    function withoutApp(history: var, appKey: var): var {
        const key = text(appKey).trim().toLowerCase();
        return rowsOf(history).filter(entry => text(entry.appKey).trim().toLowerCase() !== key);
    }

    /// History without one row — the center's per-row dismiss.
    ///
    /// Keyed on the row identity (#76) and not on the daemon's id, which is not
    /// unique across a restart: dismissing one row must never take a second,
    /// unrelated one with it.
    ///
    /// A key that matches nothing returns the list unchanged rather than
    /// complaining. The row may have fallen off the end of `historyLimit`
    /// between the click and here, and the user's intent — "that row is gone" —
    /// is satisfied either way.
    function withoutRow(history: var, key: var): var {
        const wanted = text(key);
        return rowsOf(history).filter(entry => keyOf(entry) !== wanted);
    }

    /// A row's identity as stored, recomputed rather than read: `record()` is
    /// the one place a key is made, and a row that came off a hand-edited
    /// state.json may carry a `key` that does not describe it.
    function keyOf(entry: var): string {
        return keyFor(entry.time, seqOf(entry), entry.appKey);
    }

    // --- the bar's unread count (#43) ----------------------------------------

    /// How many notifications have arrived since the center was last looked at
    /// — the number on the bar indicator.
    ///
    /// "Unread" in this shell means "arrived since the center was last open",
    /// for the same reason the lock's count means "since the lock went up":
    /// nothing marks a single notification read, and there is no seam at which
    /// one could honestly be marked so. Opening the center is the one act that
    /// says "I have looked at these".
    ///
    /// A `seenAt` of zero is "never opened", and then everything remembered is
    /// unread — not nothing. The opposite reading would hide a first day's
    /// notifications behind a badge that never lit.
    function unreadSince(history: var, seenAt: var): int {
        if (typeof seenAt !== "number" || seenAt <= 0)
            return rowsOf(history).length;
        return countSince(history, seenAt);
    }

    /// The count as the bar draws it: "" for nothing waiting, and a ceiling
    /// past which the exact number stops being information and starts being a
    /// module wide enough to push the clock off centre (the #80 class).
    function countLabel(count: var): string {
        const value = typeof count === "number" ? Math.floor(count) : 0;
        if (value <= 0)
            return "";
        return value > 99 ? "99+" : String(value);
    }

    /// How long ago a row arrived, short enough to sit at the end of its line.
    ///
    /// Coarse on purpose — a notification from Tuesday does not become more
    /// useful for saying 3d 4h. Anything inside a minute is "now", because a
    /// row that ticks 1s → 2s under the pointer is movement the shell has not
    /// earned (#22 §5: an idle shell does not animate).
    ///
    /// `now` is passed in rather than read from the clock so this is a
    /// function, and so a test can ask about a fixed moment.
    function relativeTime(then: var, now: var): string {
        if (typeof then !== "number" || typeof now !== "number" || then <= 0)
            return "";
        const seconds = Math.floor((now - then) / 1000);
        // A row from the future is a clock that moved, not a row to argue
        // with: it reads as having just arrived.
        if (seconds < 60)
            return "now";
        if (seconds < 3600)
            return Math.floor(seconds / 60) + "m";
        if (seconds < 86400)
            return Math.floor(seconds / 3600) + "h";
        return Math.floor(seconds / 86400) + "d";
    }

    /// The rows of a history that are objects at all. Every reader above takes
    /// history as it comes off state.json, which is hand-editable (#21) — one
    /// wrecked row must cost one row and not the answer.
    function rowsOf(history: var): var {
        const list = Array.isArray(history) ? history : [];
        return list.filter(entry => entry !== null && typeof entry === "object"
                           && !Array.isArray(entry));
    }

    // --- helpers -------------------------------------------------------------

    function text(value: var): string {
        if (typeof value === "string")
            return value;
        if (typeof value === "number" || typeof value === "boolean")
            return String(value);
        return "";
    }

    // A record stores its urgency by name; a live notification carries the
    // number. Both have to land in the same place.
    function urgencyValue(urgency: var): int {
        if (urgency === "low" || urgency === urgencyLow)
            return urgencyLow;
        if (urgency === "critical" || urgency === urgencyCritical)
            return urgencyCritical;
        return urgencyNormal;
    }
}
