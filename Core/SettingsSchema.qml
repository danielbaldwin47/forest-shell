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

    // --- field tables for the whole-sub-object leaves ------------------------
    //
    // A themed group is one leaf so a preset can replace it atomically (#56),
    // which leaves nowhere for per-key defaults and ranges to live — so they
    // live here, and `c.shape` turns the table into both (Core/Coerce.qml).
    //
    // Every number below is a measured decision from the bar prototype (#10),
    // not a taste call made at this keyboard. What is *not* here is as
    // deliberate: no ridgeline shape key (`peaks` and `pills` were built and
    // rejected — shipping them as settings would ship the rejected designs),
    // no horizon rule and no workspace id under the active peak (both measured
    // as not working at a 32px bar).

    readonly property var barSurfaceFields: ({
        // 86% of `surface` over the wallpaper. Measured 7.12:1 for
        // text-secondary under the right-hand cluster — the worst case, since
        // that cluster sits over the brightest part of the sky. The floor is
        // 0.65: 0.60 measured 4.44:1 and fails the body-text rule (#10).
        opacity: { def: 0.86, coerce: c.number(0.65, 1.0) },
        // Blur is the compositor's job — a Hyprland layerrule on this bar's
        // namespace, which costs the shell nothing per frame. #22 §6 forbids
        // QML-side full-screen blur outright, and the shell must look correct
        // with it off.
        blur: { def: true, coerce: c.boolean },
        // The brief's pale mist wash, §6.1.
        mistWash: { def: 0.10, coerce: c.number(0, 0.5) },
        // "Barely-perceptible top-edge lightening" — the vertical luminance
        // gradient every board pin has, compressed into 32px.
        topLight: { def: true, coerce: c.boolean },
        topLightAmount: { def: 0.05, coerce: c.number(0, 0.4) },
        // 1px border-subtle bottom hairline: the bar's bottom edge is a
        // horizon, and the horizon motif wants a line.
        hairline: { def: true, coerce: c.boolean },
        // 2-4% monochrome noise kills gradient banding (brief §3.5).
        grain: { def: 0.03, coerce: c.number(0, 0.1) },
        // Less translucency as the wallpaper brightens. Off by default, and
        // costs nothing while off — the wallpaper is not even quantized.
        adaptiveOpacity: { def: false, coerce: c.boolean }
    })

    readonly property var barRidgelineFields: ({
        // Width is the whole ballgame (#10): at w14/gap4 the units read as
        // receding strata; narrower and it reads as a bar chart, wider and it
        // reads as a row of buttons. Locked taste call.
        unitWidth: { def: 14, coerce: c.integer(4, 40) },
        gap: { def: 4, coerce: c.integer(0, 20) },
        // Heights: active tallest, occupied falling away by distance, empty at
        // the vanishing height regardless.
        activeHeight: { def: 14, coerce: c.integer(2, 48) },
        occupiedHeight: { def: 9, coerce: c.integer(1, 48) },
        emptyHeight: { def: 3, coerce: c.integer(0, 48) },
        falloff: { def: 2, coerce: c.integer(0, 12) },
        minHeight: { def: 4, coerce: c.integer(0, 48) },
        // Haze: the same encoding again, in opacity, so distance reads twice.
        occupiedHaze: { def: 0.62, coerce: c.number(0, 1) },
        emptyHaze: { def: 0.22, coerce: c.number(0, 1) },
        hazeFalloff: { def: 0.10, coerce: c.number(0, 1) },
        minHaze: { def: 0.15, coerce: c.number(0, 1) },
        // Hyprland destroys empty workspaces, so a fixed slot range is unioned
        // with whatever live workspaces exist beyond it — otherwise the row
        // grows and shrinks as you work.
        slots: { def: 5, coerce: c.integer(1, 20) },
        // The single-lamplight rule, resolved (#10): amber is reserved for
        // attention, so the active workspace is teal and the bar at rest
        // carries no warm element at all. This is the escape hatch for the
        // other reading, not the default.
        amberActive: { def: false, coerce: c.boolean }
    })

    // Which modules the bar carries, in which cluster, in what order. Presence
    // *is* enablement: there is no separate `enabled` flag, because a module
    // that is off is a module that is not in a list.
    //
    // Unknown names are dropped by the registry with a warning rather than
    // here: the schema's business is "a list of names", and which names exist
    // is the bar's (Surfaces/Bar/BarRegistry.qml).
    //
    // The consequence of a sparse file: a user who never touched this key picks
    // up modules that later versions ship, and one who reordered the bar does
    // not. That is the same trade the whole config makes, and the visible half
    // is the one worth having.
    readonly property var barModuleFields: ({
        left: { def: ["workspaces"], coerce: c.arrayOf(c.string, "bar.modules.left") },
        center: { def: ["clock"], coerce: c.arrayOf(c.string, "bar.modules.center") },
        right: { def: [], coerce: c.arrayOf(c.string, "bar.modules.right") }
    })

    readonly property var spec: ({
        appearance: {
            // Intent, not ephemera: dark mode is part of the setup, so it is
            // config even though it is a one-click toggle (#21).
            darkMode: { def: true, coerce: c.boolean },
            // The one degrade knob (#22 §7): manual, never auto-detected, and
            // a fully supported look rather than a broken mode. In cost order
            // it turns off the compositor blur, then decorative effects, then
            // collapses every transition to a 140ms opacity fade.
            reducedEffects: { def: false, coerce: c.boolean },
            // Role → colour, read by Core/Theme.qml (#34): an unknown role or
            // an unparseable colour is dropped with a warning rather than
            // painted, because this arrives hand-edited.
            paletteOverrides: { def: ({}), coerce: c.object, themed: true },
            dynamic: { def: ({}), coerce: c.object, themed: true }
            // The palette *mode* — fixed forest / constrained accent / matugen
            // — lands with #58 and #59.
        },

        bar: {
            // Top horizontal is the v1 bar (#9). Left/right are absent rather
            // than accepted-and-ignored: the widgets are built axis-agnostic so
            // a vertical bar can land post-v1 without rewrites, but a position
            // the shell cannot actually lay out is a dead setting.
            position: { def: "top", coerce: c.oneOf(["top", "bottom"]) },
            // 32 logical px — 48 device px at the T480's 1.5 scale. 26 crowds
            // the icons, 36+ reads as a title bar (#10).
            height: { def: 32, coerce: c.integer(20, 64) },
            padding: { def: 12, coerce: c.integer(0, 48) },
            moduleGap: { def: 14, coerce: c.integer(0, 48) },

            // Flush full-width is the default; floating insets the bar into a
            // rounded slab. The margins and radius only apply while floating.
            floating: { def: false, coerce: c.boolean },
            floatMarginH: { def: 12, coerce: c.integer(0, 64) },
            floatMarginV: { def: 8, coerce: c.integer(0, 64) },
            floatRadius: { def: 10, coerce: c.integer(0, 32) },

            // The window is never destroyed to hide it (#12 §2, #22 §5) — it
            // drops its content and keeps a reveal strip.
            autoHide: { def: false, coerce: c.boolean },

            surface: { def: c.shapeDefaults(schema.barSurfaceFields),
                       coerce: c.shape(schema.barSurfaceFields, "bar.surface"), themed: true },
            ridgeline: { def: c.shapeDefaults(schema.barRidgelineFields),
                         coerce: c.shape(schema.barRidgelineFields, "bar.ridgeline"), themed: true },
            modules: { def: c.shapeDefaults(schema.barModuleFields),
                       coerce: c.shape(schema.barModuleFields, "bar.modules") }
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
            // Timeouts, history and per-app rules land with #42 and #43.
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
