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
// Sections are thin where their ticket has not landed yet; the section list is
// what is settled, and later tickets add lines to it and nothing else.
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
            // Fixed forest / constrained accent (#58) / full dynamic (#59).
            paletteMode: { def: "forest", coerce: c.oneOf(["forest", "accent", "dynamic"]) },
            paletteOverrides: { def: ({}), coerce: c.object, themed: true },
            dynamic: { def: ({}), coerce: c.object, themed: true },
            animations: { def: true, coerce: c.boolean },
            // 0 stops motion without a rebuild — #22 §5 wants that reachable.
            motionScale: { def: 1.0, coerce: c.number(0, 3) }
        },

        bar: {
            position: { def: "top", coerce: c.oneOf(["top", "bottom"]) },
            height: { def: 36, coerce: c.integer(20, 96) },
            surface: { def: ({}), coerce: c.object, themed: true },
            ridgeline: { def: ({}), coerce: c.object, themed: true }
            // Module layout and per-module options land with #35 and #37.
        },

        launcher: {
            maxResults: { def: 8, coerce: c.integer(1, 50) }
            // Provider options land with #39–#41.
        },

        controlCenter: {
            // Sliders, toggle grid and drill-ins land with #44 and #45.
        },

        dashboard: {
            // Card registry and per-card options land with #49 and #50.
        },

        notifications: {
            // DND is not here — it is situational, so it is state (#21).
            timeoutMs: { def: 5000, coerce: c.integer(0, 60000) },
            historyLimit: { def: 100, coerce: c.integer(0, 1000) }
            // Per-app rules land with #43.
        },

        weatherTime: {
            location: { def: "", coerce: c.string },
            units: { def: "metric", coerce: c.oneOf(["metric", "imperial"]) },
            clockFormat: { def: "24h", coerce: c.oneOf(["24h", "12h"]) }
        },

        wallpaper: {
            path: { def: "", coerce: c.path },
            fillMode: { def: "crop", coerce: c.oneOf(["crop", "fit", "stretch", "tile"]) }
        },

        system: {
            // Schedule, not a live toggle: the intent is "warm my screen at
            // night", which is setup and belongs in config (#21).
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
