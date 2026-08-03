// The two schemas as data (#21, #33): the section list, the config/state split,
// and the theme-flagged groups later tickets read.
import QtQuick
import QtTest
import "../Core"
import "../Surfaces/Drawers"

TestCase {
    name: "Schemas"

    SettingsSchema { id: settings }
    StateSchema { id: state }
    SpecStore { id: store }
    Migrations { id: migrations }

    // Only for the one check that the control centre's factory grid and the
    // schema's default grid are the same list (#55). Both files are pure
    // QtQuick, which is the whole reason that check can live at this seam.
    ControlCenterPolicy { id: control }

    // --- settings.json -------------------------------------------------------

    function test_sections_mirror_the_settings_gui_tabs() {
        // 1:1 with the GUI tabs (#54, #55), so hand-editing and the settings
        // window are the same mental model.
        const expected = ["appearance", "bar", "launcher", "controlCenter", "dashboard",
                          "notifications", "weatherTime", "wallpaper", "system"];
        compare(Object.keys(settings.spec).length, expected.length);
        for (const section of expected)
            verify(settings.spec[section] !== undefined, "missing section " + section);
    }

    function test_every_leaf_has_a_default_and_a_coercer() {
        for (const path of store.leafPaths(settings.spec)) {
            const leaf = store.leafAt(settings.spec, path);
            verify(leaf.def !== undefined, path + " has no default");
            verify(typeof leaf.coerce === "function", path + " has no coercer");
        }
    }

    function test_every_default_survives_its_own_coercer() {
        // A default the coercer would reject is a schema bug that only shows up
        // once a user writes that key by hand.
        for (const path of store.leafPaths(settings.spec)) {
            const leaf = store.leafAt(settings.spec, path);
            verify(store.equals(leaf.coerce(leaf.def), leaf.def), path + " default is not coercible");
        }
    }

    function test_theme_flagged_groups_are_whole_sub_objects() {
        // #56 swaps these atomically, so each must be one leaf and not a
        // section of individually-defaulted keys.
        for (const path of ["bar.surface", "bar.ridgeline",
                            "appearance.paletteOverrides", "appearance.dynamic"]) {
            const leaf = store.leafAt(settings.spec, path);
            verify(leaf !== null, path + " is not a leaf");
            verify(leaf.themed === true, path + " is not marked themed");
        }
    }

    function test_the_mode_choice_travels_and_its_output_does_not() {
        // #56 draws this line: a preset carries the *choice* of theming mode,
        // and never what a wallpaper-coupled mode sampled on the machine it was
        // saved on. Both flags are read by Core/ThemePolicy.qml and by nothing
        // else, so losing one would be silent everywhere but here.
        compare(store.leafAt(settings.spec, "appearance.mode").themed, true);
        compare(store.leafAt(settings.spec, "appearance.mode").derived, undefined);
        compare(store.leafAt(settings.spec, "appearance.dynamic").derived, true);
    }

    function test_intent_lives_in_settings() {
        // Toggled often, but still setup: these travel with the config (#21).
        verify(store.leafAt(settings.spec, "appearance.darkMode") !== null);
        verify(store.leafAt(settings.spec, "wallpaper.path") !== null);
        verify(store.leafAt(settings.spec, "system.nightLight.enabled") !== null);
    }

    function test_notification_timeouts_are_settings_exposed_per_urgency() {
        // #42 asks for urgency-aware timeouts with authored defaults, reachable
        // from settings.json. Critical's 0 is the load-bearing one: it means
        // "until acknowledged", not "no timeout configured".
        compare(store.leafAt(settings.spec, "notifications.timeouts.low").def, 5000);
        compare(store.leafAt(settings.spec, "notifications.timeouts.normal").def, 8000);
        compare(store.leafAt(settings.spec, "notifications.timeouts.critical").def, 0);
    }

    function test_per_app_rules_are_a_free_form_map() {
        // The keys are the user's apps, so the spec table cannot name them:
        // this is one leaf holding an object, not a section (#42, #43).
        const leaf = store.leafAt(settings.spec, "notifications.apps");
        verify(leaf !== null, "notifications.apps is not a leaf");
        compare(leaf.def, ({}));
        // Not theme-flagged: a preset has no business silencing an app (#56).
        compare(leaf.themed, undefined);
    }

    function test_a_fresh_config_is_only_a_version_stamp() {
        // Sparse: defaults are never written out, so a first-run file is one
        // line and every later default change reaches the user.
        const out = store.serialize(settings.spec, store.defaults(settings.spec), {});
        compare(Object.keys(out).length, 0);
    }

    function test_a_hand_edited_file_resolves_and_writes_back_sparse() {
        const raw = {
            settingsVersion: 2,
            system: { nightLight: { enabled: "true", temperature: "3200" } },
            keptByANewerShell: 1
        };
        const values = store.resolve(settings.spec, raw).values;
        compare(values.system.nightLight.enabled, true);
        compare(values.system.nightLight.temperature, 3200);

        const out = store.serialize(settings.spec, values, raw);
        compare(out.system.nightLight.enabled, true);
        compare(out.system.nightLight.temperature, 3200);
        // Untouched keys stay out of the file, and so does the whole section
        // that has none.
        compare(out.system.nightLight.from, undefined);
        compare(out.appearance, undefined);
        compare(out.keptByANewerShell, 1);
        compare(out.settingsVersion, 2);
    }

    // --- the bar section (#35) ----------------------------------------------

    function test_the_bar_defaults_are_the_decided_ones() {
        // #10's resolution table. If one of these changes, the decision
        // changed — this is not a formatting preference.
        const bar = store.defaults(settings.spec).bar;
        compare(bar.position, "top");
        compare(bar.height, 32);
        compare(bar.padding, 12);
        compare(bar.moduleGap, 14);
        compare(bar.floating, false);
        compare(bar.surface.opacity, 0.86);
        compare(bar.surface.hairline, true);
        compare(bar.surface.grain, 0.03);
        // No `adaptiveOpacity`: the legibility floor is always on and is not a
        // setting (#79). A build that still offered the knob would be offering
        // a switch that changes nothing.
        compare(bar.surface.adaptiveOpacity, undefined);
        compare(bar.ridgeline.unitWidth, 14);
        compare(bar.ridgeline.gap, 4);
        compare(bar.ridgeline.activeHeight, 14);
        compare(bar.ridgeline.occupiedHeight, 9);
        compare(bar.ridgeline.emptyHeight, 3);
        compare(bar.ridgeline.falloff, 2);
        compare(bar.ridgeline.occupiedHaze, 0.62);
        compare(bar.ridgeline.emptyHaze, 0.22);
        // Amber is reserved for attention; the active workspace is teal, so
        // the bar at rest carries no warm element (#10).
        compare(bar.ridgeline.amberActive, false);
    }

    function test_a_hand_edited_bar_opacity_cannot_go_illegible() {
        // The one number in the file that can make the bar unreadable rather
        // than merely ugly: 20% fill measured 1.25:1 (#10).
        const values = store.resolve(settings.spec, { bar: { surface: { opacity: 0.2 } } }).values;
        compare(values.bar.surface.opacity, 0.65);
    }

    function test_a_partly_written_themed_group_still_resolves_whole() {
        // A preset or a hand edit may name one key; every consumer still reads
        // a complete group.
        const values = store.resolve(settings.spec, { bar: { ridgeline: { slots: 9 } } }).values;
        compare(values.bar.ridgeline.slots, 9);
        compare(values.bar.ridgeline.unitWidth, 14);
        compare(Object.keys(values.bar.ridgeline).length,
                Object.keys(store.leafAt(settings.spec, "bar.ridgeline").knobs).length);
    }

    function test_module_order_is_three_lists_of_names() {
        // #9's default inventory, in #9's order: #37 brought all of it but the
        // notification indicator, which lands with the centre it opens (#43).
        const modules = store.defaults(settings.spec).bar.modules;
        compare(modules.left, ["launcher", "workspaces", "activeWindow"]);
        compare(modules.center, ["clock", "media"]);
        // The machine's condition, with the one door on that side outermost.
        compare(modules.right, ["tray", "status", "battery", "keyboard", "notifications",
                                "controlCenter"]);
    }

    function test_a_reordered_bar_writes_back_only_the_module_key() {
        // Sparse: changing the bar layout must not freeze every other bar
        // default into the user's file.
        const values = store.defaults(settings.spec);
        values.bar.modules.left = ["clock", "workspaces"];
        const out = store.serialize(settings.spec, values, {});
        compare(out.bar.modules.left, ["clock", "workspaces"]);
        compare(out.bar.height, undefined);
        compare(out.bar.surface, undefined);
    }

    function test_every_section_is_a_section_and_not_a_leaf() {
        // A section with one sub-object in it must still be walkable rather
        // than read as a whole-sub-object leaf. `dashboard` was the last empty
        // one and filled in with #49; the check outlives it because the
        // distinction is what `themed: true` turns off deliberately, and a
        // section that acquired it by accident would half-merge under a preset.
        for (const section of ["dashboard", "controlCenter", "weatherTime"]) {
            verify(!store.isLeaf(settings.spec[section]), section + " reads as a leaf");
            verify(store.leafPathsUnder(settings.spec, section).length > 0,
                   section + " has no keys under it");
        }
    }

    function test_the_dashboard_carries_its_cards_and_its_header() {
        // #49. The card list is one key and not one per card, because the order
        // is the whole of what it decides (Surfaces/Drawers/DashboardRegistry.qml).
        //
        // #50's two sampler knobs are here rather than under `system` because
        // they are the *card's*: the sampler exists for it and runs only while
        // something is watching it (Services/System/SystemStats.qml).
        compare(store.leafPathsUnder(settings.spec, "dashboard").sort(),
                ["dashboard.cards", "dashboard.profile.avatar", "dashboard.profile.name",
                 "dashboard.systemMonitor.diskPath", "dashboard.systemMonitor.intervalSeconds"]);
        compare(store.defaults(settings.spec).dashboard.cards,
                ["calendar", "weather", "systemMonitor", "media"]);
    }

    function test_the_osd_keys_live_under_the_control_centre() {
        // #46's geometry and timeout. Here rather than in a tenth section
        // because #21 fixes the section list at nine and the tabs at ten
        // (tests/tst_settingstabs.qml), and because the OSD reports exactly the
        // three channels the control centre puts sliders on — Core/
        // SettingsSchema.qml argues it where the keys are.
        compare(store.leafPathsUnder(settings.spec, "controlCenter").sort(),
                ["controlCenter.columns",
                 "controlCenter.osd.margin",
                 "controlCenter.osd.position",
                 "controlCenter.osd.timeout",
                 "controlCenter.sliders",
                 "controlCenter.step",
                 "controlCenter.tiles"]);
    }

    function test_the_grid_and_the_sliders_are_two_lists_of_names() {
        // #55's Control Center tab. The same shape as `dashboard.cards` and the
        // bar's module lists, and for the same reason: presence *is*
        // enablement, so a tile that is off is a tile that is not in the list
        // and there is no second flag to disagree with it.
        //
        // Names rather than a closed enum, so a file written by a newer shell
        // keeps a tile this one cannot draw —
        // Surfaces/Drawers/ControlCenterPolicy.qml drops an unknown id when it
        // builds the grid, which is the same rule the dashboard registry
        // follows.
        const values = store.defaults(settings.spec);
        compare(values.controlCenter.tiles,
                ["wifi", "bluetooth", "dnd", "nightlight", "keepawake",
                 "mode", "powerprofile", "vpn", "wallpaper", "recording"]);
        compare(values.controlCenter.sliders, ["volume", "mic", "brightness"]);
        compare(values.controlCenter.columns, 3);
        compare(values.controlCenter.step, 5);
    }

    function test_the_grid_defaults_are_the_grid_the_panel_draws() {
        // The schema cannot import the policy — Core/ does not reach up into
        // Surfaces/ — so the order and the two numbers are written twice, and
        // this is what holds them together. A disagreement would otherwise only
        // be visible as a panel whose factory settings differ from the file's,
        // which is the kind of thing nobody goes looking for.
        //
        // Same arrangement as the night-light temperature range, which
        // Services/Hardware/NightLightPolicy.qml and the schema both state.
        compare(settings.controlCenterTiles, control.tileOrder);
        compare(settings.controlCenterSliders, control.sliderOrder);
        compare(store.defaults(settings.spec).controlCenter.tiles, control.tileOrder);
        compare(store.defaults(settings.spec).controlCenter.sliders, control.sliderOrder);
        compare(store.defaults(settings.spec).controlCenter.columns, control.columns);
        compare(store.defaults(settings.spec).controlCenter.step, control.step);
    }

    function test_the_night_light_keys_live_under_weather_time() {
        // #44 puts them here rather than under `appearance` because this is the
        // section that will own sunset (#50) — the schedule needs a location,
        // and a warmth key three sections away from the times that drive it is
        // a key nobody finds. #50 brought that location: the weather card's
        // four keys are its neighbours here.
        compare(store.leafPathsUnder(settings.spec, "weatherTime").sort(),
                ["weatherTime.clock.format",
                 "weatherTime.nightLight.command",
                 "weatherTime.nightLight.offCommand",
                 "weatherTime.nightLight.temperature",
                 "weatherTime.weather.days",
                 "weatherTime.weather.place",
                 "weatherTime.weather.refreshMinutes",
                 "weatherTime.weather.units"]);
    }

    function test_one_clock_key_for_every_surface_that_draws_a_clock() {
        // #93: the bar hardcoded 24-hour and the lock followed the locale, so
        // one shell showed `19:26` and `7:30 PM` minutes apart. There is one
        // key now, and `auto` is its default — a shell nobody has told anything
        // reads the time the way the rest of the machine does.
        compare(store.defaults(settings.spec).weatherTime.clock.format, "auto");
        // The three words are the whole of the choice, and the list here is the
        // one Core/ClockFormat.qml reads (tst_clockformat.qml checks that end).
        compare(settings.clockFormats, ["auto", "12h", "24h"]);
        // A hand-edited clock this shell cannot write falls back rather than
        // reaching Qt.formatDateTime as a format string.
        const clock = settings.spec.weatherTime.clock;
        compare(clock.format.coerce("12"), undefined);
        compare(clock.format.coerce("24h"), "24h");
    }

    function test_the_weather_card_is_not_configured_into_a_location_lookup() {
        // The auto mode is opt-in: an empty place means "nowhere configured"
        // and makes no request at all, rather than being read as permission to
        // ask a geolocation service about this address
        // (Services/Weather/WeatherPolicy.qml, `mode`).
        compare(store.defaults(settings.spec).weatherTime.weather.place, "");
    }

    function test_a_hand_edited_refresh_cannot_hammer_the_forecast_service() {
        // Clamped rather than refused, which is what `c.integer` does with a
        // range: a hand-edited 1 becomes the floor rather than falling back to
        // the default, so the file still says roughly what its author meant.
        const weather = settings.spec.weatherTime.weather;
        compare(weather.refreshMinutes.coerce(1), 5);
        compare(weather.refreshMinutes.coerce(9999), 720);
        compare(weather.refreshMinutes.coerce(5), 5);
        // And a unit system this shell does not have falls back rather than
        // being passed through to the API as a query parameter.
        compare(weather.units.coerce("kelvin"), undefined);
        compare(weather.units.coerce("imperial"), "imperial");
    }

    function test_a_hand_edited_sample_interval_cannot_become_a_busy_loop() {
        // A zero-interval timer is four file reads in a tight loop; the floor
        // is what a hand-edit lands on instead.
        const monitor = settings.spec.dashboard.systemMonitor;
        compare(monitor.intervalSeconds.coerce(0), 1);
        compare(monitor.intervalSeconds.coerce(1), 1);
        compare(monitor.intervalSeconds.coerce(11), 10);
    }

    function test_the_idle_ladder_lives_under_system() {
        // #48's four rungs, under the section that already owns the lock and the
        // session commands — the ladder's last rung *runs* one of those commands,
        // and a timeout three sections away from what it triggers is a key
        // nobody finds. Settings › System is the tab (#55).
        const leaves = store.leafPathsUnder(settings.spec, "system")
            .filter(path => path.startsWith("system.idle."));

        compare(leaves.sort(), [
            "system.idle.dim.ac", "system.idle.dim.battery",
            "system.idle.dim.enabled", "system.idle.dim.level",
            "system.idle.dpms.ac", "system.idle.dpms.battery",
            "system.idle.dpms.enabled", "system.idle.dpms.lockedSeconds",
            "system.idle.dpms.offCommand", "system.idle.dpms.onCommand",
            "system.idle.lock.ac", "system.idle.lock.battery",
            "system.idle.lock.enabled",
            "system.idle.suspend.ac", "system.idle.suspend.battery",
            "system.idle.suspend.enabled"
        ]);
    }

    function test_the_ladder_has_no_key_for_what_it_may_not_offer() {
        // Two rules from #30 that are deliberately not settings: inhibitors are
        // respected on every rung, and the audio gate is on suspend alone. A key
        // for either would be a key that makes a film stop halfway, or one that
        // suspends the machine under the music it is playing.
        compare(store.leafAt(settings.spec, "system.idle.respectInhibitors"), null);
        compare(store.leafAt(settings.spec, "system.idle.suspend.audioGate"), null);
        // And there is no second suspend command: the ladder's last rung runs
        // the session menu's, so the two cannot disagree.
        compare(store.leafAt(settings.spec, "system.idle.suspend.command"), null);
        verify(store.leafAt(settings.spec, "system.session.commands.suspend") !== null);
    }

    function test_a_hand_edited_ladder_cannot_be_armed_at_zero_seconds() {
        // The worst thing this file can express: a rung that fires the moment
        // the shell starts. The coercer floors at 0, and 0 is read as "off on
        // this power source" by Services/System/IdlePolicy.qml rather than as
        // "immediately".
        const raw = { system: { idle: { lock: { battery: -3, ac: "soon" } } } };
        const idle = store.resolve(settings.spec, raw).values.system.idle;
        compare(idle.lock.battery, 0);
        // An unreadable value falls back to its default rather than to zero,
        // which is the ordinary coercion rule and is safe here for the same
        // reason.
        compare(idle.lock.ac, 10);
    }

    // --- the keys the settings window is built on (#54, #55) -----------------

    function test_every_tab_has_keys_to_edit() {
        // #54 built four tabs and #55 the other six, so every section now has a
        // tab in front of it and an empty one is a tab with nothing in it.
        // About is the tenth tab and has no section, which
        // tests/tst_settingstabs.qml pins from the other side.
        for (const section in settings.spec)
            verify(store.leafPathsUnder(settings.spec, section).length > 0,
                   section + " has no keys");
    }

    function test_a_themed_group_knows_what_its_knobs_are() {
        // The knob table is what the GUI renders its controls from, and what the
        // coercer was derived from — one declaration, so a range cannot drift
        // away from the control that offers it.
        for (const path of ["bar.surface", "bar.ridgeline"]) {
            const leaf = store.leafAt(settings.spec, path);
            const knobs = Object.keys(leaf.knobs);
            verify(knobs.length > 0, path + " has no knob table");
            for (const knob of knobs)
                verify(store.equals(leaf.def[knob], leaf.knobs[knob].def),
                       path + "." + knob + " is not the default the group carries");
        }
    }

    function test_a_hand_edited_group_keeps_the_knobs_it_did_not_name() {
        // The whole reason `themed: true` groups are safe to hand-edit.
        const raw = { bar: { surface: { opacity: 0.7 } } };
        const surface = store.resolve(settings.spec, raw).values.bar.surface;

        compare(surface.opacity, 0.7);
        compare(surface.grain, 0.03);
        compare(surface.hairline, true);
    }

    function test_moving_one_knob_writes_only_that_knob() {
        // A themed group is one key, so the resolved value is always the whole
        // group — and writing all of it back would freeze every knob the user
        // never touched at whatever the default was that day. Only what differs
        // goes in the file; the coercer merges the rest back on read (#21).
        const values = store.resolve(settings.spec, {}).values;
        values.bar.surface.opacity = 0.7;

        const out = store.serialize(settings.spec, values, {});
        compare(Object.keys(out.bar.surface).length, 1);
        compare(out.bar.surface.opacity, 0.7);

        // And it round-trips: the knobs that were left out come back.
        const again = store.resolve(settings.spec, out).values.bar.surface;
        compare(again.opacity, 0.7);
        compare(again.grain, 0.03);
    }

    function test_a_group_back_at_its_defaults_leaves_the_file() {
        const raw = { bar: { surface: { opacity: 0.7 } } };
        const values = store.resolve(settings.spec, raw).values;
        values.bar.surface.opacity = 0.86;

        compare(store.serialize(settings.spec, values, raw).bar, undefined);
    }

    function test_a_group_keeps_keys_written_by_a_newer_shell() {
        const raw = { bar: { surface: { sheen: 3 } } };
        const values = store.resolve(settings.spec, raw).values;

        const out = store.serialize(settings.spec, values, raw);
        compare(out.bar.surface.sheen, 3);
        compare(out.bar.surface.opacity, undefined);
    }

    function test_bar_opacity_stays_inside_its_range() {
        // Taste, since #79: the 4.5:1 floor is enforced on the rendered band
        // (Surfaces/Bar/BarLegibility.qml), not here. The range is still a
        // range — a fill at 0.2 is a bar that has stopped being a bar — but it
        // is no longer load-bearing for legibility, and the old rationale
        // ("0.60 measures 4.44:1") was measured against an averaged wallpaper
        // and does not survive a capture.
        const raw = { bar: { surface: { opacity: 0.2 } } };
        compare(store.resolve(settings.spec, raw).values.bar.surface.opacity, 0.65);
    }

    function test_module_lists_pass_unknown_names_to_the_registry() {
        // The schema's business is "a list of names"; which names exist is the
        // bar's, and the registry drops unknowns with a warning
        // (tests/tst_barregistry.qml). Validating against a closed list here
        // would let an older shell prune the modules a newer one shipped.
        const raw = { bar: { modules: { left: ["launcher", "aquarium", "clock"] } } };
        const left = store.resolve(settings.spec, raw).values.bar.modules.left;

        compare(left.length, 3);
        compare(left[1], "aquarium");
    }

    function test_every_default_bar_module_is_one_the_registry_knows() {
        const modules = store.leafAt(settings.spec, "bar.modules.left").def
            .concat(store.leafAt(settings.spec, "bar.modules.center").def)
            .concat(store.leafAt(settings.spec, "bar.modules.right").def);

        for (const id of modules)
            verify(settings.barModules.indexOf(id) >= 0, id + " is not in the registry");
        // A module in two clusters at once is a layout bug the file can express
        // and the GUI cannot, so the defaults must not model it.
        compare(modules.filter((id, i) => modules.indexOf(id) !== i).length, 0);
    }

    function test_ask_claude_ships_read_only_plus_web() {
        // #9's decision, and the reason the default is safe to widen from rather
        // than to: nothing here can write, run or install anything.
        const tools = store.leafAt(settings.spec, "launcher.claude.tools").def;
        compare(tools.join(","), "WebSearch,WebFetch,Read,Grep,Glob");
        compare(store.leafAt(settings.spec, "launcher.claude.permissionMode").def, "default");
    }

    function test_a_notification_rule_the_shell_cannot_read_costs_one_app() {
        const raw = { notifications: { apps: {
            firefox: "silent", slack: "screaming", mail: "blocked" } } };
        const rules = store.resolve(settings.spec, raw).values.notifications.apps;

        compare(rules.firefox, "silent");
        compare(rules.mail, "blocked");
        compare(rules.slack, undefined);
    }

    // --- state.json ----------------------------------------------------------

    function test_ephemera_live_in_state_not_settings() {
        // DND is the deliberate exception to "intent lives in config": it is
        // situational, so it never touches settings.json (#21).
        verify(store.leafAt(state.spec, "dnd") !== null);
        compare(store.leafAt(settings.spec, "dnd"), null);
        compare(store.leafAt(settings.spec, "notifications.dnd"), null);

        verify(store.leafAt(state.spec, "claude.sessionId") !== null);
        verify(store.leafAt(state.spec, "dashboard.lastTab") !== null);
        verify(store.leafAt(state.spec, "seen.changelogVersion") !== null);

        // Which settings tab you had open is not part of your setup (#54).
        verify(store.leafAt(state.spec, "settings.lastTab") !== null);
        compare(store.leafAt(settings.spec, "settings"), null);
    }

    function test_state_leaves_are_specified_like_settings_leaves() {
        for (const path of store.leafPaths(state.spec)) {
            const leaf = store.leafAt(state.spec, path);
            verify(leaf.def !== undefined, path + " has no default");
            verify(typeof leaf.coerce === "function", path + " has no coercer");
            verify(store.equals(leaf.coerce(leaf.def), leaf.def), path + " default is not coercible");
        }
    }

    function test_the_two_files_use_different_version_keys() {
        verify(settings.versionKey !== state.versionKey);
    }

    // --- settings v3: the legibility floor stops being a setting (#79) -------

    function test_adaptive_opacity_is_dropped_from_a_file_that_has_it() {
        const raw = {
            settingsVersion: 2,
            bar: { height: 40, surface: { opacity: 0.7, adaptiveOpacity: true } }
        };
        const result = migrations.run(raw, settings.migrations,
                                      settings.versionKey, settings.version);
        verify(result.ok, result.error);
        compare(result.raw.bar.surface.adaptiveOpacity, undefined);
        // Everything the user did set is still theirs.
        compare(result.raw.bar.surface.opacity, 0.7);
        compare(result.raw.bar.height, 40);
        compare(result.raw.settingsVersion, settings.version);
    }

    function test_dropping_it_takes_an_emptied_surface_section_with_it() {
        // A file whose only bar.surface key was the knob should not be left
        // carrying an empty object — the sparse write would never have made one.
        const result = migrations.run({
            settingsVersion: 2, bar: { surface: { adaptiveOpacity: false } }
        }, settings.migrations, settings.versionKey, settings.version);
        verify(result.ok, result.error);
        compare(result.raw.bar.surface, undefined);
    }

    function test_a_file_without_the_knob_is_left_alone() {
        for (const raw of [{ settingsVersion: 2 },
                           { settingsVersion: 2, bar: {} },
                           { settingsVersion: 2, bar: { surface: { opacity: 0.9 } } },
                           // Shapes a hand-edited file can be in: the migration
                           // must not throw on any of them (#21 — never blocks
                           // startup).
                           { settingsVersion: 2, bar: "nonsense" },
                           { settingsVersion: 2, bar: { surface: [1, 2] } }]) {
            const result = migrations.run(raw, settings.migrations,
                                          settings.versionKey, settings.version);
            verify(result.ok, JSON.stringify(raw) + ": " + result.error);
        }
    }

    function test_history_written_before_row_keys_is_migrated_rather_than_dropped() {
        // v1 rows carried the freedesktop daemon's id as their identity, and
        // that counter restarts at 1 with every server (#76). History is
        // ephemera, but it is the user's ephemera — the rows are kept and given
        // keys rather than thrown away.
        const raw = {
            stateVersion: 1,
            notifications: {
                history: [
                    { id: 1, time: 3000, appKey: "telegram", summary: "after the restart" },
                    { id: 2, time: 2000, appKey: "telegram", summary: "before it" },
                    { id: 1, time: 1000, appKey: "telegram", summary: "the first one" }
                ]
            }
        };

        const result = migrations.run(raw, state.migrations, state.versionKey, state.version);
        verify(result.ok, result.error);
        const rows = result.raw.notifications.history;
        compare(rows.length, 3);

        for (const row of rows) {
            compare(row.id, undefined);            // no longer the row's identity
            verify(typeof row.serverId === "number", "lost the daemon id");
        }
        compare(rows[0].serverId, 1);
        compare(rows[2].serverId, 1);
        // The key is not assigned here: NotificationPolicy gives one to any row
        // that arrives without a sequence number, which covers a row hand-added
        // to an already-migrated file as well as these.
    }

    function test_migrating_leaves_a_serverId_that_is_already_there_alone() {
        // A file half-written by a newer build, or hand-edited. Whatever wrote
        // `serverId` knew more than this step does.
        const result = migrations.run({
            stateVersion: 1,
            notifications: { history: [{ id: 9, serverId: 4, time: 1 }] }
        }, state.migrations, state.versionKey, state.version);
        verify(result.ok, result.error);
        compare(result.raw.notifications.history[0].serverId, 4);
        compare(result.raw.notifications.history[0].id, undefined);
    }

    function test_migrating_a_state_file_with_no_history_changes_nothing() {
        const result = migrations.run({ stateVersion: 1, dnd: true }, state.migrations,
                                      state.versionKey, state.version);
        verify(result.ok, result.error);
        compare(result.raw.dnd, true);
        compare(result.raw.notifications, undefined);
    }

    function test_a_wrecked_history_row_does_not_take_the_migration_down() {
        // state.json is hand-editable (#21), and a migration that throws stops
        // the whole run — so this one has to survive nonsense in the list.
        const result = migrations.run({
            stateVersion: 1,
            notifications: { history: ["nonsense", null, 42, { time: 1 }] }
        }, state.migrations, state.versionKey, state.version);
        verify(result.ok, result.error);
        compare(result.raw.notifications.history.length, 4);
    }
}
