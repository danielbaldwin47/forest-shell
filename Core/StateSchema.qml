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

    readonly property var spec: ({
        // Situational, not setup — the one toggle that is state (#21). Owned by
        // the notification service (#42).
        dnd: { def: false, coerce: c.boolean },

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

        claude: {
            // Resumes the conversation across a shell restart (#41).
            sessionId: { def: "", coerce: c.string }
        },

        seen: {
            // Suppresses the what's-new notice for a version already read.
            changelogVersion: { def: "", coerce: c.string }
        },

        notifications: {
            history: { def: [], coerce: c.array }    // #43
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
            describe: "notification history rows get their own id",
            migrate: function (raw) {
                // v1 rows carried the freedesktop daemon's notification id as
                // their identity. That counter restarts at 1 with every server
                // and history does not, so one shell restart was enough to put
                // two different rows in the list under the same id (#76).
                const notifications = raw.notifications;
                if (!notifications || !Array.isArray(notifications.history))
                    return raw;

                // Newest first, so the head gets the highest number and the
                // next arrival counts on from there.
                const rows = notifications.history;
                for (let i = 0; i < rows.length; i++) {
                    const row = rows[i];
                    // state.json is hand-editable (#21) and a step that throws
                    // stops the whole run — anything that is not a row is left
                    // exactly as it is, for the reader to drop.
                    if (row === null || typeof row !== "object" || Array.isArray(row))
                        continue;
                    if (typeof row.seq !== "number")
                        row.seq = rows.length - i;
                    if (row.serverId === undefined && typeof row.id === "number")
                        row.serverId = row.id;
                    delete row.id;
                }
                return raw;
            }
        }
    ]
}
