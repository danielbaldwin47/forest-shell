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
                Object.keys(settings.barRidgelineFields).length);
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
        for (const section of ["launcher", "controlCenter", "dashboard",
                               "weatherTime"]) {
            verify(!store.isLeaf(settings.spec[section]), section + " reads as a leaf");
            compare(store.leafPathsUnder(settings.spec, section).length, 0);
        }
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
}
