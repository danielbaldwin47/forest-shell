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

    /// The dashboard's card inventory (#49), the same kind of pool as
    /// `barModules`: what a settings GUI offers to add, and what
    /// Surfaces/Drawers/DashboardRegistry.qml resolves the result against.
    ///
    /// The same four the registry has since #50 built the data cards. It was
    /// longer than the registry for one ticket, on purpose and only in that
    /// direction: `weather` and `systemMonitor` were named here before either
    /// could be drawn, so a config written against a newer shell kept them
    /// rather than having them stripped on the first save — which is what the
    /// bar's vocabulary still does for the optional modules nobody has built.
    readonly property var dashboardCards: ["calendar", "media", "weather", "systemMonitor"]

    /// What a temperature and a wind speed are measured in (#50). Two systems
    /// and not four keys: nobody wants their temperature in Celsius and their
    /// wind in miles per hour, and Open-Meteo takes the pair as two parameters
    /// Services/Weather/WeatherPolicy.qml derives from this one word.
    readonly property var weatherUnits: ["metric", "imperial"]

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

    /// Where the OSD pill sits (#46). One edge with the pill centred against
    /// it, or the middle of the screen — layer-shell centres a surface on
    /// whichever axis it is not anchored to, so this list is the anchor table.
    /// Surfaces/Osd/OsdPolicy.qml holds the same five and turns them into
    /// flags.
    readonly property var osdPositions: ["top", "bottom", "left", "right", "center"]

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

            // The OSD (#46) — the pill that pops on a volume, mic or
            // brightness change.
            //
            // **Here, and not in a tenth section**, which is the one thing
            // about this ticket the resolutions do not settle: #21 fixes the
            // section list at nine and `tests/tst_settingstabs.qml` holds the
            // tabs to ten, so an `osd` section would be a tab #9 never listed.
            // The OSD reports exactly the three channels the control centre
            // puts sliders on — volume out, mic, brightness (#9) — so it sits
            // under the section that owns those controls, and reads as "what
            // the control centre does when it is not open".
            //
            // JSON-only for now, which #9 permits in as many words ("long-tail
            // options may stay JSON-only until they earn a control"): the
            // Control Center tab is #55's, and these three rows land with it.
            osd: {
                // How long it stays up, in ms. Bounded either side rather than
                // at zero: a 0 here would be a surface that maps and unmaps in
                // one frame. Surfaces/Osd/OsdPolicy.qml clamps an IPC-supplied
                // value to the same pair, and tst_osdpolicy.qml pins the two
                // together.
                timeout: { def: 2000, coerce: c.integer(300, 10000) },

                // Which edge it sits against, centred on the other axis;
                // `center` is the middle of the screen. Bottom by default
                // because the bar is at the top and the notification stack owns
                // the top-right corner (#42).
                position: { def: "bottom", coerce: c.oneOf(schema.osdPositions) },

                // Its gap from that edge, in px. Applied to the anchored edge
                // only, and ignored by `center`.
                margin: { def: 64, coerce: c.integer(0, 400) }
            }
        },

        dashboard: {
            // Which cards the dashboard carries, top to bottom (#49).
            //
            // Presence *is* enablement, exactly as it is for the bar's modules:
            // a card that is off is a card that is not in the list, and there is
            // no second `enabled` flag to disagree with it.
            //
            // A list of names and not a closed enum: an unknown name is dropped
            // by the registry with a warning rather than refused here
            // (Surfaces/Drawers/DashboardRegistry.qml), so a file written by a
            // newer shell keeps the cards this one cannot draw — which is how
            // #50's weather and system-monitor cards survived a round trip
            // through the version before they existed.
            //
            // The default is #9's four-card dashboard: the month, the weather,
            // the machine and what is playing. The header is not in the list —
            // it is what the panel *is*, not a card.
            cards: { def: ["calendar", "weather", "systemMonitor", "media"],
                     coerce: c.arrayOf(c.string, "dashboard.cards") },

            // What the system-monitor card samples, and how often (#50).
            //
            // Here rather than under `system` because these are the *card's*
            // knobs: the sampler exists for it, runs only while something is
            // watching it (Services/System/SystemStats.qml), and a machine with
            // the card off never reads a value at either of these settings.
            systemMonitor: {
                // Seconds between samples. One is the readable maximum — a
                // sparkline updating faster than that is a shimmer rather than
                // a reading — and ten is a monitor that has become a summary.
                // The floor is not zero for the obvious reason: a zero-interval
                // timer is a busy loop reading four files.
                intervalSeconds: { def: 1, coerce: c.integer(1, 10),
                                   label: "Seconds between system samples" },

                // Which filesystem the disk row is about. One and not all of
                // them: a machine with fifteen mounts would need the card to
                // choose anyway, and the one that matters is where the user's
                // files are. A path that is not a mount point drops the row
                // with a warning rather than showing a wrong number.
                diskPath: { def: "/", coerce: c.path,
                            label: "The filesystem the disk row is about" }
            },

            // The header, which is a person rather than a card: a name and a
            // face beside the date (#9).
            //
            // Both default to empty and mean "work it out" rather than "leave it
            // blank" — the shell knows the user's login name and where a
            // desktop keeps a face, and a header that said nothing until it was
            // configured would be a header nobody configures. They are keys at
            // all because neither guess is always right: a login name is not a
            // name, and an account picture is a per-machine file that
            // settings.json travels away from.
            profile: {
                name: { def: "", coerce: c.string,
                        label: "What the dashboard calls you" },
                avatar: { def: "", coerce: c.path,
                          label: "A picture for the dashboard header" }
            }
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
            // The weather card (#50). Open-Meteo, keyless, and asked about one
            // place — Services/Weather/WeatherPolicy.qml builds every URL these
            // keys turn into.
            weather: {
                // A place name, geocoded once and then cached in `state.json`
                // with the reading. `auto` is #9's optional IP-based mode.
                //
                // Empty is the default and it means **neither**: the card says
                // it has not been told where it is, and no request is made.
                // That is deliberately not the pattern `dashboard.profile.name`
                // and `wallpaper.folder` use, where empty means "work it out" —
                // working this one out means asking a geolocation service what
                // this IP looks like, which is the one request this shell makes
                // that tells a third party something rather than only asking it
                // something. A shell does not make that request because nobody
                // filled a field in; `auto` is how it is asked for.
                place: { def: "", coerce: c.string,
                         label: "The place the weather card is about" },

                units: { def: "metric", coerce: c.oneOf(schema.weatherUnits),
                         label: "Temperature and wind units" },

                // How often a card left on screen re-fetches. Nothing polls
                // behind a closed drawer at all (Services/Weather/Weather.qml),
                // so this is the interval of an *open* dashboard — and the
                // staleness threshold that decides whether opening one fetches.
                // Thirty minutes is roughly how often the upstream model
                // updates; the floor is five because a card refreshing faster
                // than the forecast changes is a request that answers with the
                // same numbers.
                refreshMinutes: { def: 30, coerce: c.integer(5, 720),
                                  label: "Minutes between weather refreshes" },

                // Rows in the forecast strip, including today. Seven is the
                // API's free ceiling; four is a strip that fits the 380px panel
                // without the rows becoming columns of two characters.
                days: { def: 4, coerce: c.integer(1, 7),
                        label: "Days in the forecast strip" }
            },

            // Night light (#44). Here rather than under `appearance` because
            // this is the section that will own sunset — the schedule #50
            // lands needs a location, and a warmth key three sections away
            // from the times that drive it is a key nobody finds.
            nightLight: {
                // How warm, in K. 4000 is a warm evening that is still legible
                // for text; the range is what the tools themselves accept
                // (Services/Hardware/NightLightPolicy.qml holds the same two
                // numbers, and this is the file that clamps a hand-edit).
                temperature: { def: 4000, coerce: c.integer(1000, 6500) },

                // What warms the screen, and what stops. Strings rather than a
                // toggle, for the reason `system.session.commands` are: what
                // does this differs by compositor — hyprsunset on Hyprland,
                // wlsunset or gammastep elsewhere — and the shell has no
                // business guessing. The defaults are Hyprland's, since that is
                // the compositor this shell targets (#12).
                //
                // `{temp}` is substituted with the temperature above. Emptying
                // either key removes the control centre's tile rather than
                // leaving one that fails on every press.
                command: { def: "hyprctl hyprsunset temperature {temp}",
                           coerce: c.string },
                offCommand: { def: "hyprctl hyprsunset identity", coerce: c.string }
            }
        },

        wallpaper: {
            path: { def: "", coerce: c.path },

            // Where the control centre's picker looks for candidates (#45), and
            // nothing else reads it — the wallpaper itself is `path` above and
            // may live anywhere. `~/` and not an absolute path because
            // settings.json travels between machines and a home directory does
            // not; Surfaces/Background/Wallpapers.qml expands it.
            //
            // A folder that does not exist is not an error: the picker says
            // where it looked and shows nothing, which is the correct answer on
            // a machine that keeps its wallpapers somewhere else.
            folder: { def: "~/Pictures/Wallpapers", coerce: c.path,
                      label: "Where the wallpaper picker looks" }
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
            },

            // The idle ladder (#48). Four stages, each with its own toggle and
            // its own pair of timeouts in **minutes** — #30's table, which was
            // measured against this machine rather than picked: the T480 ran no
            // idle daemon at all before this, and its effective behaviour was
            // DPMS-off at 5.5 minutes and nothing else.
            //
            //   stage      battery    ac
            //   dim        2.5 min    5 min
            //   lock       5 min      10 min
            //   dpms       6 min      12 min
            //   suspend    15 min     off
            //
            // Minutes and not seconds because that is the unit the decision was
            // made in and the unit the GUI will offer; the ladder converts once
            // (Services/System/IdlePolicy.qml).
            //
            // **Zero means "not on this power source"**, which is what makes AC
            // suspend off while battery suspend is on without a second toggle to
            // keep in agreement with the first. `enabled` is the other kind of
            // off — the one the user flips — and it turns the stage off on both
            // sources at once.
            //
            // What is deliberately not here: `respectInhibitors`. #30 puts it on
            // all four stages, and a key that could turn it off would be a key
            // that makes a film stop halfway. It is a constant in the policy.
            // Nor is the audio gate: it is on suspend only, and which stage a
            // rule applies to is not a setting.
            //
            // JSON-only for now, which #9 permits for the long tail: the System
            // tab is #55's, and these rows land with it.
            idle: {
                // Screen down to `level`, restored on the first activity. The
                // backlight facade does it (#36), so this is one number rather
                // than a command — unlike the two below, dimming is not
                // compositor business.
                dim: {
                    enabled: { def: true, coerce: c.boolean },
                    battery: { def: 2.5, coerce: c.number(0, 600) },
                    ac: { def: 5, coerce: c.number(0, 600) },
                    level: { def: 10, coerce: c.integer(1, 100) }
                },

                lock: {
                    enabled: { def: true, coerce: c.boolean },
                    battery: { def: 5, coerce: c.number(0, 600) },
                    ac: { def: 10, coerce: c.number(0, 600) }
                },

                dpms: {
                    enabled: { def: true, coerce: c.boolean },
                    battery: { def: 6, coerce: c.number(0, 600) },
                    ac: { def: 12, coerce: c.number(0, 600) },

                    // While locked the screen is showing a clock nobody is
                    // reading, so #30 tightens this stage and only this stage.
                    // Seconds, because a number under a minute written as a
                    // fraction of one is a number nobody can check.
                    lockedSeconds: { def: 30, coerce: c.integer(5, 600) },

                    // Strings for the reason `system.session.commands` are: what
                    // blanks a screen differs by compositor and the shell has no
                    // business guessing. These are Hyprland's, since that is the
                    // compositor this shell targets (#12). Blanking either one
                    // turns the stage into a logged refusal rather than a silent
                    // no-op (#78).
                    offCommand: { def: "hyprctl dispatch dpms off", coerce: c.string },
                    onCommand: { def: "hyprctl dispatch dpms on", coerce: c.string }
                },

                // What suspends is `system.session.commands.suspend`, one
                // section up: the session menu's Suspend and the ladder's last
                // rung are the same act on the same machine, and two keys for it
                // would be two keys to keep in agreement.
                suspend: {
                    enabled: { def: true, coerce: c.boolean },
                    battery: { def: 15, coerce: c.number(0, 600) },
                    // Off on mains: a plugged-in machine that suspends itself is
                    // one that drops your ssh sessions while you read (#30).
                    ac: { def: 0, coerce: c.number(0, 600) }
                }
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
