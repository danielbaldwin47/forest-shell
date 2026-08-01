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
    readonly property int version: 1

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

    // Nothing to migrate yet, and nothing ever has to be: this file is
    // disposable, so a future schema break may simply drop it. The registry is
    // here so the runner is wired identically for both files from day one.
    readonly property var migrations: []
}
