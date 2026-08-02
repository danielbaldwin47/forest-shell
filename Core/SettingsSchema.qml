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
    function group(label, knobs) {
        const fields = {};
        for (const key in knobs) {
            const knob = knobs[key];
            fields[key] = { def: knob.def, coerce: knob.coerce ?? coercerFor(knob) };
        }

        return { def: c.shapeDefaults(fields), coerce: c.shape(fields, label),
                 themed: true, knobs: knobs };
    }

    /// What kind of knob this is: `choice`, `range` or `toggle`. One answer,
    /// read by both things that need it — the coercer below, and the control
    /// the settings GUI renders (Surfaces/Settings/Controls/KnobRow.qml). Asking
    /// the same three questions in two places is how a knob ends up validated
    /// as one thing and edited as another.
    ///
    /// Integer or real is not part of the kind: it follows from the default,
    /// since a knob whose default is `14` is not one anybody wants at `14.3`.
    function knobKind(knob): string {
        if (knob.values !== undefined)
            return "choice";
        if (knob.min !== undefined || knob.max !== undefined)
            return "range";
        if (typeof knob.def === "boolean")
            return "toggle";
        // Reached only by a knob line that declares nothing this understands —
        // a schema bug, and one worth failing loudly on rather than admitting
        // an uncoerced value into a hand-edited file.
        throw new Error("SettingsSchema: cannot tell what kind of knob this is: "
                        + JSON.stringify(knob));
    }

    function coercerFor(knob) {
        switch (knobKind(knob)) {
        case "choice":
            return c.oneOf(knob.values);
        case "range":
            return Number.isInteger(knob.def) ? c.integer(knob.min, knob.max)
                                              : c.number(knob.min, knob.max);
        default:
            return c.boolean;
        }
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
        },

        // Geometry and inventory are plain keys; the two styling groups are
        // theme-flagged, because a preset (#56) swaps how the bar *looks*
        // without moving modules around or resizing it.
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

            // Which modules the bar carries, in which cluster, in what order.
            // Presence *is* enablement: there is no separate `enabled` flag,
            // because a module that is off is a module that is not in a list.
            //
            // A list of names, not a closed enum: unknown names are dropped by
            // the registry with a warning rather than here
            // (Surfaces/Bar/BarRegistry.qml), so a file written by a newer
            // shell keeps its modules under an older one. Three leaves rather
            // than one leaf holding all three, so reordering one cluster
            // writes back only that cluster.
            //
            // The default inventory is #9's, in #9's order (#37 completed it,
            // bar the notification indicator, which lands with the
            // notification centre). Left is where you are — the workspaces and
            // the window in front of you, behind the door into the launcher.
            // Centre is the clock and what is playing. Right is the machine's
            // condition, tray first and the control-centre door outermost: the
            // right cluster is all readings except that last one, and a door at
            // the screen edge is the easiest target on the bar.
            //
            // Three of these hide themselves — media with nothing playing, the
            // keyboard layout on a single-layout machine, the window title on
            // an empty workspace — so the shipped bar is shorter than this list
            // most of the time.
            modules: {
                left: { def: ["launcher", "workspaces", "activeWindow"],
                        coerce: c.arrayOf(c.string, "bar.modules.left") },
                center: { def: ["clock", "media"],
                          coerce: c.arrayOf(c.string, "bar.modules.center") },
                right: { def: ["tray", "status", "battery", "keyboard", "controlCenter"],
                         coerce: c.arrayOf(c.string, "bar.modules.right") }
            },

            // The two ceilings #37 needed and #36 did not: a track title and a
            // window title are arbitrary text from another application, and an
            // uncapped one walks across the bar and pushes the clock off centre
            // (the #80 class of overflow). Both elide from the right.
            //
            // JSON-only for now, which #9 allows for the long tail: they are
            // two numbers in px that depend on a screen width the Bar tab has
            // no preview of.
            mediaMaxWidth: { def: 180, coerce: c.integer(60, 600) },
            windowMaxWidth: { def: 220, coerce: c.integer(60, 800) },

            // The two styling groups, declared knob by knob (`group()` above):
            // the group's default object, its knob-by-knob coercer and the
            // controls the Bar tab renders are all derived from each line, so
            // a slider cannot offer a value the file would then clamp.
            //
            // Every number below is a measured decision from the bar prototype
            // (#10), not a taste call made at this keyboard. What is *not*
            // here is as deliberate: no ridgeline shape key (`peaks` and
            // `pills` were built and rejected — shipping them as settings
            // would ship the rejected designs), no horizon rule and no
            // workspace id under the active peak (both measured as not working
            // at a 32px bar).
            surface: schema.group("bar.surface", {
                // 86% of `surface` over the wallpaper. Measured 7.12:1 for
                // text-secondary under the right-hand cluster — the worst
                // case, since that cluster sits over the brightest part of the
                // sky. The floor is 0.65: 0.60 measured 4.44:1 and fails the
                // body-text rule (#10).
                opacity: { def: 0.86, min: 0.65, max: 1.0, label: "Fill opacity" },
                // Blur is the compositor's job — a Hyprland layerrule on this
                // bar's namespace, which costs the shell nothing per frame.
                blur: { def: true, label: "Blur the wallpaper behind" },
                // The brief's pale mist wash, §6.1.
                mistWash: { def: 0.10, min: 0, max: 0.5, label: "Mist wash" },
                // "Barely-perceptible top-edge lightening" — the vertical
                // luminance gradient every board pin has, compressed into 32px.
                topLight: { def: true, label: "Top-edge lightening" },
                topLightAmount: { def: 0.05, min: 0, max: 0.4, label: "Top light amount" },
                // 1px border-subtle bottom hairline: the bar's bottom edge is
                // a horizon, and the horizon motif wants a line.
                hairline: { def: true, label: "Bottom hairline" },
                // 2-4% monochrome noise kills gradient banding (brief §3.5).
                grain: { def: 0.03, min: 0, max: 0.1, label: "Grain" },
                // Less translucency as the wallpaper brightens. Off by
                // default, and costs nothing while off.
                adaptiveOpacity: { def: false, label: "Adapt opacity to the wallpaper" }
            }),

            ridgeline: schema.group("bar.ridgeline", {
                // Width is the whole ballgame (#10): at w14/gap4 the units
                // read as receding strata; narrower and it reads as a bar
                // chart, wider and it reads as a row of buttons. Locked taste
                // call.
                unitWidth: { def: 14, min: 4, max: 40, label: "Unit width" },
                gap: { def: 4, min: 0, max: 20, label: "Gap" },
                // Heights: active tallest, occupied falling away by distance,
                // empty at the vanishing height regardless.
                activeHeight: { def: 14, min: 2, max: 48, label: "Active height" },
                occupiedHeight: { def: 9, min: 1, max: 48, label: "Occupied height" },
                emptyHeight: { def: 3, min: 0, max: 48, label: "Empty height" },
                falloff: { def: 2, min: 0, max: 12, label: "Height falloff" },
                minHeight: { def: 4, min: 0, max: 48, label: "Minimum height" },
                // Haze: the same encoding again, in opacity, so distance reads
                // twice.
                occupiedHaze: { def: 0.62, min: 0, max: 1, label: "Occupied haze" },
                emptyHaze: { def: 0.22, min: 0, max: 1, label: "Empty haze" },
                hazeFalloff: { def: 0.10, min: 0, max: 1, label: "Haze falloff" },
                minHaze: { def: 0.15, min: 0, max: 1, label: "Minimum haze" },
                // Hyprland destroys empty workspaces, so a fixed slot range is
                // unioned with whatever live workspaces exist beyond it —
                // otherwise the row grows and shrinks as you work.
                slots: { def: 5, min: 1, max: 20, label: "Workspace slots" },
                // The single-lamplight rule, resolved (#10): amber is reserved
                // for attention, so the active workspace is teal and the bar
                // at rest carries no warm element at all. This is the escape
                // hatch for the other reading, not the default.
                amberActive: { def: false, label: "Amber active workspace" }
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
                         coerce: c.arrayOf(c.oneOf(schema.claudeTools), "launcher.claude.tools") },
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
            // dead settings. On, a client's own expire-timeout hint wins — in
            // milliseconds, like the table, and bounded the same way (#74).
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
            // A map rather than a section because the keys are the user's
            // apps, not ours: the spec table cannot name them ahead of time.
            // One unparseable rule drops that app's entry rather than every
            // other app's (Core/Coerce.qml, `mapOf`) — an absent entry is what
            // `normal` already means, so this file only ever carries the apps
            // the user actually silenced or blocked. Enforced by
            // Services/Notifications (#42); the three-way UI that writes it is
            // the Notifications tab (#43, #54).
            apps: { def: ({}), coerce: c.mapOf(c.oneOf(schema.notificationRules)) }
        },

        weatherTime: {
            // Location, units and clock format land with #50.
        },

        wallpaper: {
            path: { def: "", coerce: c.path }
            // Fill mode and any transition land with the wallpaper work.
        },

        system: {
            // The session drawer's four system actions (#38), next to the lock
            // below because they are the same menu: lock, log out, suspend,
            // restart, shut down.
            //
            // Strings rather than a toggle each, because what ends a session
            // differs by init system and by machine and the shell has no
            // business guessing — these are the systemd and Hyprland answers,
            // and a machine that wants `loginctl terminate-session` says so
            // here. Locking is deliberately not among them: it is a surface
            // this shell owns (#47), reached in-process, and
            // Surfaces/Drawers/SessionPolicy.qml says why.
            //
            // A key blanked here is "not on this machine": the row stays on the
            // menu and refuses with a line naming the key, which is a better
            // answer than a button that quietly is not there.
            session: {
                commands: {
                    logout: { def: "hyprctl dispatch exit", coerce: c.string },
                    suspend: { def: "systemctl suspend", coerce: c.string },
                    reboot: { def: "systemctl reboot", coerce: c.string },
                    shutdown: { def: "systemctl poweroff", coerce: c.string }
                }
            },

            // Schedule, not a live toggle: the intent is "warm my screen at
            // night", which is setup and belongs in config (#21, #33).
            nightLight: {
                enabled: { def: false, coerce: c.boolean },
                from: { def: "20:00", coerce: c.string },
                to: { def: "07:00", coerce: c.string },
                temperature: { def: 4000, coerce: c.integer(1000, 6500) }
            },

            // The lock screen (#30, #47). Four keys, and deliberately no fifth:
            // there is no retry limit, no lockout duration and no failed-attempt
            // count here, because faillock owns all three and the shell keeps no
            // counts of its own. The idle timeouts that *reach* the lock are the
            // idle ladder's (#48), not the lock's.
            lock: {
                // Count only, never contents (#9). Off is for a machine that
                // locks in front of other people.
                notificationCount: { def: true, coerce: c.boolean },
                // The system stack, so the lock inherits faillock and whatever
                // else the distro already trusts, and the shell writes nothing
                // to /etc. "login" is an Arch/Debian assumption rather than a
                // law, which is the only reason this is a key at all.
                pamConfig: { def: "login", coerce: c.string },
                // Fingerprint is latent: this permits it, fprintd decides. Off
                // means do not even probe.
                fingerprint: { def: true, coerce: c.boolean },
                fingerprintPamConfig: { def: "fprintd", coerce: c.string }
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
