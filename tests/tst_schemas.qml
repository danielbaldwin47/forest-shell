// The two schemas as data (#21, #33): the section list, the config/state split,
// and the theme-flagged groups later tickets read.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "Schemas"

    SettingsSchema { id: settings }
    StateSchema { id: state }
    SpecStore { id: store }
    Migrations { id: migrations }

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
        compare(bar.surface.adaptiveOpacity, false);
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
        const modules = store.defaults(settings.spec).bar.modules;
        compare(modules.left, ["workspaces"]);
        compare(modules.center, ["clock"]);
        compare(modules.right, []);
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

    function test_empty_sections_are_sections_and_not_leaves() {
        // Several sections are deliberately empty until their ticket lands;
        // they must still be walkable, not read as a whole-sub-object leaf.
        for (const section of ["controlCenter", "dashboard", "weatherTime"]) {
            verify(!store.isLeaf(settings.spec[section]), section + " reads as a leaf");
            compare(store.leafPathsUnder(settings.spec, section).length, 0);
        }
    }

    // --- the keys the settings window is built on (#54) ----------------------

    function test_the_four_built_tabs_have_keys_to_edit() {
        // Appearance, Bar, Launcher and Notifications are implemented in #54, so
        // an empty section there is a tab with nothing in it.
        for (const section of ["appearance", "bar", "launcher", "notifications"])
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

    function test_bar_opacity_cannot_be_set_below_the_contrast_floor() {
        // Not taste: secondary text over the brightest wallpaper measures
        // 4.44:1 at 0.60, under the design system's 4.5:1 body floor (#10).
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

        const seen = {};
        for (const row of rows) {
            compare(row.id, undefined);            // no longer the row's identity
            verify(typeof row.serverId === "number", "lost the daemon id");
            verify(typeof row.seq === "number", "no sequence number");
            verify(seen[row.seq] === undefined, "duplicate seq " + row.seq);
            seen[row.seq] = true;
        }
        // Newest first, so the head holds the highest sequence number — the
        // next arrival counts on from there.
        verify(rows[0].seq > rows[2].seq);
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
