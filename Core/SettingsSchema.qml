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
// A key's name, default and range belong to the ticket that builds the thing it
// configures — guessing them here would commit names those tickets would then
// have to migrate away from. So the sections whose control has not been
// designed yet stay empty, and a section fills in when either the feature or
// **its settings tab** lands. The settings window (#54) is the second of those:
// Appearance, Bar, Launcher and Notifications are built there, so their keys are
// here, taken from the resolutions that already fixed them — #9 for the launcher
// providers and the Claude surface, #10 for the bar geometry, surface and
// ridgeline (which resolved *"all of it is settings, not constants"*), #41 for
// the Claude flags. The bar itself (#35) reads these; it does not get to rename
// them.
//
// Pure data, no Quickshell imports, so tests/ can reach it.
import QtQuick

QtObject {
    id: schema

    readonly property QtObject c: Coerce {}

    readonly property string versionKey: "settingsVersion"
    readonly property int version: 2

    // --- vocabularies ---------------------------------------------------------
    //
    // The closed lists a control renders and a coercer checks against, held as
    // properties rather than inlined so the settings GUI reads the same list the
    // file is validated with. A value that is not on one of these is refused and
    // falls back to the default, which is the whole reason they are closed: an
    // unknown enum name has no obvious reading, so guessing is worse than
    // ignoring (Core/Coerce.qml).

    /// Fixed forest, the constrained wallpaper-coupled accent (#58), or the full
    /// matugen palette (#59). Consumers stay mode-blind and read tokens; this is
    /// only ever read by `Services/Theming/`.
    readonly property var themingModes: ["forest", "accent", "dynamic"]

    /// Every bar module the registry knows, in no particular order — the order
    /// that matters is the user's, and it is the cluster arrays below. Ids not
    /// listed in any cluster are simply off; there is no separate enable flag.
    /// `status` is one module and not four: #9 groups network, bluetooth, volume
    /// and mic into a single quiet icon cluster.
    readonly property var barModules: [
        "launcher", "workspaces", "activeWindow",
        "clock", "media",
        "tray", "status", "battery", "keyboard", "notifications", "controlCenter",
        // Shipped in the registry, off by default (#9).
        "systemMonitor", "brightness", "nightLight", "recorder"
    ]

    /// Rounded-top strata (locked in #10); `peaks` and `pills` were built and
    /// rejected, so they are not offered.
    readonly property var ridgeShapes: ["strata"]

    /// #10 resolved the active workspace to teal, reserving amber for
    /// attention — and resolved the choice itself to be a setting.
    readonly property var ridgeAccents: ["teal", "amber"]

    /// Model aliases, not ids: the launcher passes these through to `--model`
    /// (#41). `opusplan` is a plan-mode alias and resolves to sonnet under
    /// `-p`, so it is deliberately not offered.
    readonly property var claudeModels: ["haiku", "sonnet", "opus"]

    /// The CLI's own list, from its warning text. There is no "off" — an
    /// unrecognised value silently falls back to the default effort, which is
    /// exactly the failure a closed list exists to prevent.
    readonly property var claudeEfforts: ["low", "medium", "high", "xhigh", "max"]

    /// `default` is the shipped mode; the two wider ones are the opt-in "auto"
    /// the user may choose (#9, #41). Interactive approval is post-v1.
    readonly property var claudePermissionModes: ["default", "acceptEdits", "bypassPermissions"]

    /// Read-only plus web (#9): what Ask Claude may load at all. Passed to
    /// `--tools` to restrict *and* `--allowedTools` to permit — the contract
    /// research found either one alone is not a restriction.
    readonly property var claudeTools: [
        "WebSearch", "WebFetch", "Read", "Grep", "Glob"
    ]

    /// Per-app notification handling (#9, #43): silent means history only.
    readonly property var notificationRules: ["normal", "silent", "blocked"]

    /// Builds one theme-flagged group leaf (#56) from a table of knobs.
    ///
    /// A themed group is a *single* leaf carrying a whole sub-object, so that a
    /// preset replaces it atomically. That shape has nowhere to write down what
    /// each knob is, which the settings GUI needs — so the knobs are declared
    /// here, one line each, and this derives the three things that follow from
    /// them: the group's default object, the coercer that repairs a hand-edited
    /// group knob by knob, and the table the Bar tab renders its controls from.
    /// Nothing is written twice, so a range cannot drift away from the control
    /// that offers it.
    ///
    /// A knob is `{ def, label }` plus at most one of:
    ///
    ///   - `min`/`max` — a number. Integer or real is taken from the default,
    ///     since a knob whose default is `14` is not one you want at `14.3`;
    ///   - `values` — one of a closed list;
    ///   - nothing — a bool, from a bool default.
    ///
    /// `coerce` may still be given outright for a knob none of that fits, and
    /// is what a future knob type lands as before it earns a shorthand here.
    function group(knobs) {
        const defaults = {};
        const coercers = {};

        for (const key in knobs) {
            const knob = knobs[key];
            defaults[key] = knob.def;
            coercers[key] = knob.coerce ?? coercerFor(knob);
        }

        return { def: defaults, coerce: c.shape(defaults, coercers),
                 themed: true, knobs: knobs };
    }

    function coercerFor(knob) {
        if (knob.values !== undefined)
            return c.oneOf(knob.values);
        if (knob.min !== undefined || knob.max !== undefined)
            return Number.isInteger(knob.def) ? c.integer(knob.min, knob.max)
                                              : c.number(knob.min, knob.max);
        if (typeof knob.def === "boolean")
            return c.boolean;
        if (typeof knob.def === "string")
            return c.string;
        // Reached only by a knob line that declares nothing this understands —
        // a schema bug, and one worth failing loudly on rather than admitting
        // an uncoerced value into a hand-edited file.
        throw new Error("SettingsSchema: cannot derive a coercer for knob "
                        + JSON.stringify(knob));
    }

    readonly property var spec: ({
        appearance: {
            // Fixed forest until #58/#59 land the other two; the key exists now
            // because the control does (#54), and a mode the shell cannot serve
            // yet is disabled in the GUI rather than missing from the file.
            mode: { def: "forest", coerce: c.oneOf(schema.themingModes) },
            // Intent, not ephemera: dark mode is part of the setup, so it is
            // config even though it is a one-click toggle (#21).
            darkMode: { def: true, coerce: c.boolean },
            // Role → colour, read by Core/Theme.qml (#34): an unknown role or
            // an unparseable colour is dropped with a warning rather than
            // painted, because this arrives hand-edited.
            paletteOverrides: { def: ({}), coerce: c.object, themed: true },
            dynamic: { def: ({}), coerce: c.object, themed: true }
        },

        // Geometry and inventory are plain keys; the two styling groups are
        // theme-flagged, because a preset (#56) swaps how the bar *looks*
        // without moving modules around or resizing it.
        bar: {
            // Flush full-width is the shipped answer (#10): flushness turned out
            // to be a property of the wallpaper, not of the bar, and the opaque
            // band is the failure mode worth designing for.
            floating: { def: false, coerce: c.boolean },
            height: { def: 32, coerce: c.integer(24, 48) },
            paddingH: { def: 12, coerce: c.integer(0, 32) },
            moduleGap: { def: 14, coerce: c.integer(0, 32) },

            modules: {
                left: { def: ["launcher", "workspaces", "activeWindow"],
                        coerce: c.listOf(c.oneOf(schema.barModules)) },
                center: { def: ["clock", "media"],
                          coerce: c.listOf(c.oneOf(schema.barModules)) },
                right: { def: ["tray", "status", "battery", "keyboard",
                               "notifications", "controlCenter"],
                         coerce: c.listOf(c.oneOf(schema.barModules)) }
            },

            surface: schema.group({
                // 86% measured 7.12:1 for secondary text over the brightest pin
                // wallpaper — statistically indistinguishable from opaque, while
                // still moving with the wallpaper. The floor is not taste: at
                // 60% the same text measured 4.44:1 and fails the design
                // system's 4.5:1 body floor, so the range starts at 0.65 (#10).
                opacity: { def: 0.86, min: 0.65, max: 1, label: "Fill opacity" },
                // Delegated to a Hyprland layerrule in the shipping shell, so
                // this is "ask the compositor for it", not a per-frame effect.
                // Desaturation was dropped in #35 — unreachable from a
                // layerrule and not load-bearing.
                blur: { def: true, label: "Blur the wallpaper behind" },
                mist: { def: 0.10, min: 0, max: 0.3, label: "Mist wash" },
                topLight: { def: true, label: "Top-edge lightening" },
                bottomHairline: { def: true, label: "Bottom hairline" },
                grain: { def: 0.03, min: 0, max: 0.08, label: "Grain" },
                // Less translucency as the wallpaper brightens. Off by default:
                // it is a second opinion about a number the user just set.
                adaptiveOpacity: { def: false, label: "Adapt opacity to the wallpaper" }
            }),

            ridgeline: schema.group({
                shape: { def: "strata", values: schema.ridgeShapes, label: "Shape" },
                // Width is the whole ballgame: at 14 with a gap of 4 the
                // horizontal rhythm outruns the vertical and the range appears;
                // wider and the units read as buttons (#10).
                unitWidth: { def: 14, min: 4, max: 24, label: "Unit width" },
                gap: { def: 4, min: 0, max: 12, label: "Gap" },
                // Height and haze both fall away by distance from the active
                // workspace; that double encoding is what reads as a receding
                // range rather than a progress bar.
                activeHeight: { def: 14, min: 4, max: 24, label: "Active height" },
                occupiedHeight: { def: 9, min: 2, max: 24, label: "Occupied height" },
                emptyHeight: { def: 3, min: 0, max: 24, label: "Empty height" },
                heightFalloff: { def: 2, min: 0, max: 8, label: "Height falloff" },
                occupiedHaze: { def: 0.62, min: 0, max: 1, label: "Occupied haze" },
                emptyHaze: { def: 0.22, min: 0, max: 1, label: "Empty haze" },
                hazeFalloff: { def: 0.10, min: 0, max: 1, label: "Haze falloff" },
                // Teal, resolved: amber is the one warm element and it is
                // reserved for attention, so the bar at rest carries none.
                activeAccent: { def: "teal", values: schema.ridgeAccents,
                                label: "Active workspace accent" }
            })
        },

        launcher: {
            // One flag per provider rather than a list, because the set is
            // closed and the prefixes are fixed (#9): turning `?` off is a
            // decision about a feature, not about ordering.
            providers: {
                apps: { def: true, coerce: c.boolean },
                calculator: { def: true, coerce: c.boolean },
                clipboard: { def: true, coerce: c.boolean },
                emoji: { def: true, coerce: c.boolean },
                actions: { def: true, coerce: c.boolean },
                claude: { def: true, coerce: c.boolean }
            },

            // Ask Claude (#41). Subscription auth, so there is no key or
            // endpoint here — only what the run is allowed to be.
            claude: {
                // Haiku for launcher-sized questions; the research measured no
                // latency or quality advantage from Opus at this prompt size,
                // and `?sonnet …` is the inline think-harder affordance.
                model: { def: "haiku", coerce: c.oneOf(schema.claudeModels) },
                effort: { def: "medium", coerce: c.oneOf(schema.claudeEfforts) },
                // A subset of `claudeTools`, not free text: this is passed to
                // `--tools`, and a name the CLI does not know is a silently
                // weaker restriction rather than an error.
                tools: { def: schema.claudeTools.slice(),
                         coerce: c.listOf(c.oneOf(schema.claudeTools)) },
                permissionMode: { def: "default",
                                  coerce: c.oneOf(schema.claudePermissionModes) }
            }
        },

        controlCenter: {
            // Sliders, toggle grid and drill-ins land with #44 and #45.
        },

        dashboard: {
            // Card registry and per-card options land with #49 and #50.
        },

        notifications: {
            // DND is not here — it is situational, so it is state (#21).
            // Timeouts and history land with #42 and #43.
            //
            // App id → rule, for every app that has ever notified (#43). A map
            // and not a list because the shell writes into it by app id, and
            // one unparseable rule drops that app's entry rather than every
            // other app's (Core/Coerce.qml, `mapOf`). Apps at `normal` are
            // absent: the default is the absence of a rule, so this file only
            // ever carries the apps the user actually silenced or blocked.
            appRules: { def: ({}), coerce: c.mapOf(c.oneOf(schema.notificationRules)) }
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
