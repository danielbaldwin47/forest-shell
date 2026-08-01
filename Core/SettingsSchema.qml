// The `settings.json` spec table — the whole definition of what a forest-shell
// config *is* (#21, #33).
//
// Nine top-level sections, mirroring the settings GUI tabs 1:1 (#54, #55 — the
// About tab has no config), plus the `settingsVersion` stamp the migration
// runner owns. Keys are camelCase. The point of the 1:1 mapping is that
// hand-editing this file and using the GUI are the same mental model.
//
// Rules this table is read under (Core/SpecStore.qml enforces them):
//
//   - a node with `def` is a leaf; anything else is a section;
//   - `coerce` salvages hand-edited values and returns `undefined` to fall back
//     to `def` for that one key;
//   - `onChange(value, previous, path)` is optional and runs on reload and on
//     `set()`. It is for effects that can be expressed *here*, in a file with no
//     Quickshell imports; anything needing a service connects to
//     `Config.keyChanged` instead;
//   - `themed: true` marks a whole sub-object that a theme preset replaces
//     atomically (#56). Those are leaves, not sections, so a preset never
//     half-merges into keys a user left behind.
//
// What is deliberately *not* here: DND, last-open tab, session ids, caches.
// Intent lives in config even when it is toggled often — dark mode, the current
// wallpaper, the night-light schedule are all part of "my setup" and travel
// between the laptop and the desktop — while situational ephemera live in
// Core/StateSchema.qml and never churn this file (#21).
//
// Sections are thin, several of them empty, and that is the point: what #21
// settled is the *section list*, and a key's name, default and range belong to
// the ticket that builds the thing it configures. Guessing them here would
// commit names those tickets would then have to migrate away from. The keys
// present are the ones #33 names outright — dark mode, the wallpaper, the
// night-light schedule — plus the four theme-flagged groups it asks for.
//
// Pure data, no Quickshell imports, so tests/ can reach it.
import QtQuick

QtObject {
    id: schema

    readonly property QtObject c: Coerce {}

    readonly property string versionKey: "settingsVersion"
    readonly property int version: 2

    readonly property var spec: ({
        appearance: {
            // Intent, not ephemera: dark mode is part of the setup, so it is
            // config even though it is a one-click toggle (#21).
            darkMode: { def: true, coerce: c.boolean },
            // Role → colour, read by Core/Theme.qml (#34): an unknown role or
            // an unparseable colour is dropped with a warning rather than
            // painted, because this arrives hand-edited.
            paletteOverrides: { def: ({}), coerce: c.object, themed: true },
            dynamic: { def: ({}), coerce: c.object, themed: true }
            // The palette *mode* — fixed forest / constrained accent / matugen
            // — lands with #58 and #59.
        },

        bar: {
            surface: { def: ({}), coerce: c.object, themed: true },
            ridgeline: { def: ({}), coerce: c.object, themed: true }
            // Position, height, module layout land with #35 and #37.
        },

        launcher: {
            // Providers and their options land with #39–#41.
        },

        controlCenter: {
            // Sliders, toggle grid and drill-ins land with #44 and #45.
        },

        dashboard: {
            // Card registry and per-card options land with #49 and #50.
        },

        notifications: {
            // DND is not here — it is situational, so it is state (#21).

            // How long a popup stays up, per urgency, in ms. 0 means "until it
            // is dismissed", which is why critical is 0: an urgent notification
            // that times out unseen is the one failure the level exists to
            // prevent (#42).
            timeouts: {
                low: { def: 5000, coerce: c.integer(0, 300000) },
                normal: { def: 8000, coerce: c.integer(0, 300000) },
                critical: { def: 0, coerce: c.integer(0, 300000) }
            },

            // Off by default: nearly every client passes a hardcoded 5000 it
            // never thought about, so honouring it would make the table above
            // dead settings. On, a client's own expire-timeout hint wins.
            honorClientTimeout: { def: false, coerce: c.boolean },

            // Popups on screen at once. Past this the oldest leaves early to
            // make room — it is already in history, and an uncapped stack is a
            // screen a notification storm can fill top to bottom.
            maxVisible: { def: 3, coerce: c.integer(1, 10) },

            // Rows kept in the history the center renders (#43). 0 turns
            // history off, which is also "do not write my notifications to
            // disk".
            historyLimit: { def: 100, coerce: c.integer(0, 1000) },

            // App key → "normal" | "silent" (history only) | "blocked"
            // (nothing at all). The app key is the desktop entry where a client
            // supplies one and the app name otherwise, lower-cased.
            //
            // A free-form object rather than a section because the keys are the
            // user's apps, not ours: the spec table cannot name them ahead of
            // time. Enforced by Services/Notifications (#42); the three-way UI
            // that writes it arrives with the settings window (#43, #55).
            apps: { def: ({}), coerce: c.object }
        },

        weatherTime: {
            // Location, units and clock format land with #50.
        },

        wallpaper: {
            path: { def: "", coerce: c.path }
            // Fill mode and any transition land with the wallpaper work.
        },

        system: {
            // Schedule, not a live toggle: the intent is "warm my screen at
            // night", which is setup and belongs in config (#21, #33).
            nightLight: {
                enabled: { def: false, coerce: c.boolean },
                from: { def: "20:00", coerce: c.string },
                to: { def: "07:00", coerce: c.string },
                temperature: { def: 4000, coerce: c.integer(1000, 6500) }
            }
        }
    })

    // Ordered by `to`. Each step takes the raw parsed file and returns it.
    readonly property var migrations: [
        {
            to: 2,
            describe: "background.wallpaper → wallpaper.path",
            migrate: function (raw) {
                // The skeleton (#32) shipped the wallpaper under `background`,
                // before the section list was resolved (#21).
                const background = raw.background;
                if (!background || typeof background.wallpaper !== "string")
                    return raw;

                if (raw.wallpaper === undefined || raw.wallpaper === null
                        || typeof raw.wallpaper !== "object" || Array.isArray(raw.wallpaper))
                    raw.wallpaper = {};
                if (raw.wallpaper.path === undefined)
                    raw.wallpaper.path = background.wallpaper;

                delete background.wallpaper;
                if (Object.keys(background).length === 0)
                    delete raw.background;
                return raw;
            }
        }
    ]
}
