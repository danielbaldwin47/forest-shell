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
    /// `clientSeconds` is the client's own expire-timeout hint as Quickshell
    /// hands it over — **seconds**, with -1 for "the server decides". It is
    /// ignored unless the user asks for it, because nearly every client passes
    /// a hardcoded 5000 it never thought about, and honouring that would make
    /// the urgency table dead settings.
    function timeoutMs(urgency: var, clientSeconds: var, settings: var): int {
        const table = (settings && settings.timeouts) || {};

        if (settings && settings.honorClientTimeout && typeof clientSeconds === "number"
                && clientSeconds >= 0) {
            // 0 is the freedesktop spec's "never expire", not "expire now".
            if (clientSeconds === 0)
                return 0;
            return Math.round(Math.min(maxTimeoutMs, Math.max(minTimeoutMs, clientSeconds * 1000)));
        }

        const authored = table[urgencyName(urgency)];
        // Config resolves every leaf, so this fallback is unreachable through
        // the shell — but an undefined interval is a Timer that never fires,
        // and a notification that never leaves the screen is the worst failure
        // this file has available.
        return typeof authored === "number" ? Math.max(0, Math.round(authored)) : 8000;
    }

    // --- the delivery decision -----------------------------------------------

    /// `{ popup, history, reason }` for one notification.
    ///
    /// `context` is `{ rule, urgency, transient, dnd, fullscreen, centerOpen }`.
    /// `reason` is the empty string when the popup shows, and otherwise names
    /// the rule that stopped it — it is what the log line says, so "why did I
    /// not see that" has an answer that does not need a debugger.
    function decide(context: var): var {
        const critical = context.urgency === urgencyCritical;

        // Blocked is the only outcome that leaves no trace at all (#43).
        if (context.rule === "blocked")
            return { popup: false, history: false, reason: "blocked" };

        // The `transient` hint is a client saying "this is a progress blip, not
        // news". It decides remembering, never showing — which is what keeps
        // history from filling up with volume steps.
        const history = !context.transient;

        if (context.rule === "silent")
            return { popup: false, history: history, reason: "silent" };
        if (context.dnd && !critical)
            return { popup: false, history: history, reason: "dnd" };
        if (context.fullscreen)
            return { popup: false, history: history, reason: "fullscreen" };
        if (context.centerOpen)
            return { popup: false, history: history, reason: "center" };

        return { popup: true, history: history, reason: "" };
    }

    // --- history records -----------------------------------------------------

    /// One history row, normalized. Every field is present and of the declared
    /// type whatever the client sent, because these rows are bound to directly
    /// by the center (#43) and an `undefined` in a `Text` is a warning per
    /// frame — for a row that may have been written by an older build.
    function record(fields: var): var {
        const source = fields || {};
        return {
            id: typeof source.id === "number" ? source.id : 0,
            time: typeof source.time === "number" ? source.time : Date.now(),
            appKey: text(source.appKey),
            appName: text(source.appName),
            appIcon: text(source.appIcon),
            image: persistableImage(source.image),
            summary: text(source.summary),
            body: text(source.body),
            urgency: urgencyName(urgencyValue(source.urgency))
        };
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

    /// History without one app's rows — or, for the empty key, without any of
    /// them. Clear-one and clear-all are the same operation at a different
    /// scope, which is what makes them one line each in the center (#43).
    function forget(history: var, key: string): var {
        const list = Array.isArray(history) ? history : [];
        if (!key)
            return [];
        return list.filter(entry => entry.appKey !== key);
    }

    /// `[{ key, name }]` for every app in history, newest first, once each.
    /// This is where #43's "every app that has ever notified" list comes from —
    /// history is the record of who has, so there is no second list to keep in
    /// step with it.
    function appsIn(history: var): var {
        const list = Array.isArray(history) ? history : [];
        const seen = {};
        const out = [];
        for (const entry of list) {
            if (!entry || !entry.appKey || seen[entry.appKey])
                continue;
            seen[entry.appKey] = true;
            out.push({ key: entry.appKey, name: entry.appName || entry.appKey });
        }
        return out;
    }

    /// History as read back from state.json, which is disposable and
    /// hand-editable (#21): anything that is not a record is dropped and the
    /// rest of the list still loads. One wrecked row costs one row.
    ///
    /// The limit is applied on the way in as well as on the way out, because it
    /// may have been lowered since the file was written.
    function readHistory(raw: var, limit: int): var {
        if (!Array.isArray(raw) || limit <= 0)
            return [];
        return raw
            .filter(entry => entry !== null && typeof entry === "object" && !Array.isArray(entry)
                    && typeof entry.time === "number")
            .slice(0, limit)
            .map(entry => record(entry));
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
