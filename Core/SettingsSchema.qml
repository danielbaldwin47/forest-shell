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
//
// A section that has outgrown this file lives in a sibling
// `SettingsSchema<Section>.qml` and is composed back into `spec` below, so
// consumers keep one aggregate: `bar` is the first (Core/SettingsSchemaBar.qml),
// and a section earns its own file when its settings tab lands. The knob-group
// machinery those files share is Core/SchemaKnobs.qml.
import QtQuick

QtObject {
    id: schema

    readonly property SchemaKnobs knobs: SchemaKnobs {}
    readonly property QtObject c: knobs.c
    readonly property SettingsSchemaBar barSchema: SettingsSchemaBar {}

    /// The GUI's knob-kind question, answered by the machinery
    /// (Surfaces/Settings/Controls/KnobRow.qml reads this off the aggregate).
    function knobKind(knob): string {
        return knobs.knobKind(knob);
    }

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

    /// The bar's module inventory, owned by the bar's section file — exposed
    /// here so the Bar tab and the registry keep one address for it.
    readonly property var barModules: barSchema.modules

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

        // The fattest section, owned by Core/SettingsSchemaBar.qml and
        // composed back in whole — same keys, same groups, same defaults.
        bar: barSchema.section,

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
