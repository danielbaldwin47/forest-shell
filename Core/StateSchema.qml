// The `state.json` spec table — everything that is *not* setup (#21, #33).
//
// Same machinery as the settings file, different schema and a different
// lifetime: this is the ephemera the shell writes on its own, often, without
// asking. Keeping it out of `settings.json` is what lets the config file be
// hand-edited, diffed and carried between machines without a stream of
// shell-authored churn on top of it.
//
// The test for which file a key belongs in is *portability*, not how often it
// changes: dark mode is toggled constantly and is still config, because it is
// part of "my setup". DND is the mirror case — situational, tied to this
// afternoon on this machine — and lives here (#21).
//
// Lives in `Quickshell.stateDir`, so wiping it costs nothing but a re-opened
// tab. Nothing in here may be load-bearing.
//
// Pure data, no Quickshell imports, so tests/ can reach it.
import QtQuick

QtObject {
    id: schema

    readonly property QtObject c: Coerce {}

    readonly property string versionKey: "stateVersion"
    readonly property int version: 2

    /// The calendar's three views, in the order the toolbar draws them. Stated
    /// here so a hand-edited state file naming a fourth one falls back to the
    /// default rather than opening a window onto nothing.
    readonly property var calendarViews: ["day", "week", "month"]

    readonly property var spec: ({
        // Situational, not setup — the one toggle that is state (#21). Owned by
        // the notification service (#42).
        dnd: { def: false, coerce: c.boolean },

        // "Keep this machine awake" is about this afternoon (#44, semantics
        // from #30). Config would restore it on Monday because a film ran on
        // Friday, which is a lock nobody asked for. Owned by
        // Services/Hardware/KeepAwake.qml.
        keepAwake: { def: false, coerce: c.boolean },

        nightLight: {
            // Whether the screen is warmed *now*. The temperature and the
            // command are config (`weatherTime.nightLight`) because they are
            // setup and travel between machines; this is not, for the reason
            // above — a night light left on last night is not a setting, and a
            // shell that restored it at nine in the morning would be wrong in
            // the one way the toggle exists to avoid (#44).
            on: { def: false, coerce: c.boolean }
        },

        dashboard: {
            lastTab: { def: "", coerce: c.string }   // #49
        },

        controlCenter: {
            lastTab: { def: "", coerce: c.string }   // #45
        },

        settings: {
            // The settings window reopens where it was left (#54). Empty means
            // "the first tab" rather than a tab id repeated here — the tab
            // order lives in one place, and it is not this file. An id from a
            // build that had a tab this one does not falls back the same way.
            lastTab: { def: "", coerce: c.string }
        },

        calendar: {
            // The calendar window reopens on the view it was left on. Unlike
            // the `lastTab` keys above this one names its default outright —
            // there is no "first view" to fall back to, and `week` is the view
            // the surface opens on when nothing has chosen yet.
            lastView: { def: "week", coerce: c.oneOf(schema.calendarViews) }
        },

        claude: {
            // Resumes the conversation across a shell restart (#41).
            sessionId: { def: "", coerce: c.string }
        },

        theme: {
            // Which preset was last applied (#56). A breadcrumb and nothing
            // more: applying a theme *copies* its keys into settings.json, so
            // the skin is already in the config and this only names where it
            // came from. Nothing reads it but the list, which ticks that row —
            // and stops ticking it the moment a knob is moved afterwards.
            //
            // State rather than config for the reason the file's header gives:
            // this is shell-authored churn, and the setup it would otherwise
            // travel with is the copied keys, which travel by themselves. A
            // settings.json carried to another machine takes the look with it
            // and leaves the label behind, which is the honest answer — the
            // theme file it names may not exist over there.
            lastApplied: { def: "", coerce: c.string }
        },

        seen: {
            // Suppresses the what's-new notice for a version already read.
            changelogVersion: { def: "", coerce: c.string }
        },

        notifications: {
            history: { def: [], coerce: c.array },   // #43

            // The last sequence number issued to a history row (#76). Beside
            // the list rather than derived from it, because the list is not a
            // reliable high-water mark: the center dismisses single rows (#43),
            // and lowering `historyLimit` truncates it — either can take the
            // highest number away and let the next arrival reissue it.
            seq: { def: 0, coerce: c.integer(0) },

            // When the center was last open, in epoch ms, or 0 for never
            // (#43). What the bar indicator counts from: "unread" here means
            // "arrived since you last looked", because nothing in the shell
            // marks a single row read. Persisted so the badge does not empty
            // itself every time the shell restarts.
            seenAt: { def: 0, coerce: c.integer(0) }
        },

        launcher: {
            // Frecency (#39). Two integer maps rather than one map of
            // `{ count, at }` objects, because the coercer runs per leaf:
            // `mapOf(integer)` drops the one entry a hand-edit corrupted and
            // keeps the rest, where `object` can only take the whole map or
            // refuse the whole map. This file is hand-editable (#21), so that
            // difference is the difference between losing one app's history
            // and losing all of it.
            //
            // Keyed by desktop-entry id. Ids of apps since uninstalled are
            // left in place: they cost a few bytes, they match nothing, and
            // reinstalling something should not forget that you use it.
            uses: { def: ({}), coerce: c.mapOf(c.integer(0)) },

            // Epoch milliseconds of the last launch. Beside the count rather
            // than derived from it for the reason `notifications.seq` is:
            // neither number can be recovered from the other.
            lastUsed: { def: ({}), coerce: c.mapOf(c.integer(0)) }
        },

        weather: {
            cache: { def: ({}), coerce: c.object }   // #50
        }
    })

    // Nothing here ever *has* to be migrated: this file is disposable, so a
    // schema break may simply drop it. The rows below are kept anyway — history
    // is ephemera, but it is the user's ephemera, and dropping it silently on
    // an upgrade is the kind of thing that reads as a bug.
    readonly property var migrations: [
        {
            to: 2,
            describe: "notification history: id → serverId",
            migrate: function (raw) {
                // v1 rows carried the freedesktop daemon's notification id as
                // their identity, under the name `id`. That counter restarts at
                // 1 with every server and history does not, so one shell
                // restart was enough to put two different rows in the list
                // under the same id (#76). The number is still worth keeping —
                // it correlates a row with a popup that is still on screen —
                // but only under a name that says whose it is.
                //
                // The row *key* is not assigned here. `NotificationPolicy`
                // gives one to any row that arrives without a sequence number,
                // so a row hand-added to an already-migrated file is covered by
                // the same code path as these — and there is one implementation
                // of the numbering rather than two that must agree.
                const notifications = raw.notifications;
                if (!notifications || !Array.isArray(notifications.history))
                    return raw;

                for (const row of notifications.history) {
                    // state.json is hand-editable (#21) and a step that throws
                    // stops the whole run — anything that is not a row is left
                    // exactly as it is, for the reader to drop.
                    if (row === null || typeof row !== "object" || Array.isArray(row))
                        continue;
                    if (row.id === undefined)
                        continue;
                    if (row.serverId === undefined)
                        row.serverId = row.id;
                    delete row.id;
                }
                return raw;
            }
        }
    ]
}
