// What a theme preset is (#56): which keys travel, what save captures, what
// apply writes, and what "Forest (default)" and the undo slot mean.
//
// Every acceptance criterion on the ticket is a decision rather than a picture,
// which is why they are all here. The two halves that are not: the directory
// listing and the files themselves (Core/Themes.qml, driven at seam 2 by
// tools/theme-harness.sh), and what a theme *looks* like once applied, which is
// seam 3's.
//
// The coercion check below is the ticket's #79 criterion and is deliberately
// written as a composition: the policy plans a write, the schema's own coercer
// takes it, and the floor holds. That is the real path — `Config.set` runs that
// coercer — and it is why the policy does no clamping of its own.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "ThemePolicy"

    ThemePolicy { id: policy }
    SettingsSchema { id: schema }
    SpecStore { id: store }

    function opFor(ops, path) {
        return ops.find(op => op.path === path) ?? null;
    }

    function paths(ops) {
        return ops.map(op => op.path);
    }

    /// A settings file as it would be on disk: sparse, stamped, and carrying a
    /// key from a newer shell that this build has never heard of.
    function sampleRaw() {
        return {
            settingsVersion: 2,
            appearance: {
                mode: "dynamic",
                darkMode: false,
                paletteOverrides: { accentPrimary: "#8fbf9f" },
                dynamic: { sampledFrom: "/w/dawn.jpg" }
            },
            bar: {
                height: 40,
                surface: { opacity: 0.72, blur: false, futureKnob: 3 },
                modules: { left: ["launcher"] }
            }
        };
    }

    // --- which keys travel ----------------------------------------------------

    function test_a_theme_carries_the_skin() {
        const carried = policy.carriedPaths(schema.spec);
        verify(carried.indexOf("appearance.mode") >= 0);
        verify(carried.indexOf("appearance.paletteOverrides") >= 0);
        verify(carried.indexOf("bar.surface") >= 0);
        verify(carried.indexOf("bar.ridgeline") >= 0);
    }

    function test_a_theme_carries_no_layout() {
        // Skin, not layout: the ticket's line, and the one that decides whether
        // applying a theme is safe on a machine with a different screen.
        const carried = policy.carriedPaths(schema.spec);
        for (const path of ["bar.height", "bar.position", "bar.padding",
                            "bar.modules.left", "bar.modules.right",
                            "wallpaper.path", "appearance.darkMode",
                            "controlCenter.tiles", "notifications.apps"])
            verify(carried.indexOf(path) < 0, path + " must not travel with a theme");
    }

    function test_a_theme_never_carries_a_modes_own_output() {
        // Wallpaper-derived palettes are output, not a theme — the mode choice
        // travels, the sample it produced does not.
        verify(policy.carriedPaths(schema.spec).indexOf("appearance.dynamic") < 0);
    }

    function test_every_carried_path_is_a_leaf_of_the_settings_spec() {
        for (const path of policy.carriedPaths(schema.spec))
            verify(store.leafAt(schema.spec, path) !== null, path + " is not a leaf");
    }

    // --- saving ---------------------------------------------------------------

    function test_save_captures_only_what_the_file_actually_holds() {
        const theme = policy.fragment(schema.spec, sampleRaw());
        compare(theme.appearance.mode, "dynamic");
        compare(theme.appearance.paletteOverrides, ({ accentPrimary: "#8fbf9f" }));
        compare(theme.bar.surface, ({ opacity: 0.72, blur: false, futureKnob: 3 }));
        // Never touched, so never in the file, so never in the theme — the
        // ridgeline goes on following the shipped default.
        compare(theme.bar.ridgeline, undefined);
        compare(theme.appearance.dynamic, undefined);
        compare(theme.appearance.darkMode, undefined);
        compare(theme.bar.height, undefined);
    }

    function test_save_copies_rather_than_aliases_the_settings_file() {
        const raw = sampleRaw();
        const theme = policy.fragment(schema.spec, raw);
        theme.bar.surface.opacity = 0.99;
        compare(raw.bar.surface.opacity, 0.72);
    }

    function test_a_theme_file_stamps_its_own_version_first() {
        const file = policy.themeFile(schema, sampleRaw());
        compare(Object.keys(file)[0], schema.versionKey);
        compare(file[schema.versionKey], schema.version);
        compare(file.bar.surface.opacity, 0.72);
    }

    function test_saving_an_untouched_shell_gives_a_theme_with_no_body() {
        const file = policy.themeFile(schema, { settingsVersion: 2 });
        compare(Object.keys(file), [schema.versionKey]);
    }

    function test_a_snapshot_captures_a_write_the_engine_has_not_made_yet() {
        // The config engine debounces its writes, so the file lags the live
        // values by up to a quarter of a second — and "save the look I am
        // looking at" is pressed exactly then. A snapshot serializes the values
        // against the file rather than reading the file.
        const raw = sampleRaw();
        const values = store.resolve(schema.spec, raw).values;
        values.bar.surface.opacity = 0.9;

        const file = policy.snapshot(schema, values, raw);
        compare(file.bar.surface.opacity, 0.9);
        // Sparse all the same: a knob still at its default does not enter the
        // theme just because the group did.
        compare(file.bar.surface.grain, undefined);
        // And a key from a newer shell survives the round trip.
        compare(file.bar.surface.futureKnob, 3);
        compare(file.bar.height, undefined);
    }

    function test_a_snapshot_of_an_untouched_shell_is_the_default_theme() {
        const values = store.resolve(schema.spec, {}).values;
        compare(policy.snapshot(schema, values, {}), policy.defaultFile(schema));
    }

    // --- applying -------------------------------------------------------------

    function test_apply_writes_what_the_theme_carries() {
        const planned = policy.plan(schema, policy.themeFile(schema, sampleRaw()));
        verify(planned.ok);
        compare(opFor(planned.ops, "bar.surface").value,
                ({ opacity: 0.72, blur: false, futureKnob: 3 }));
        compare(opFor(planned.ops, "appearance.mode").value, "dynamic");
    }

    function test_apply_resets_the_keys_the_theme_does_not_carry() {
        // Not a skip: a theme is the whole skin, so a key it is silent about is
        // a key the shipped default owns again. Deletion rather than writing
        // today's default, which is the config engine's rule (#21).
        const planned = policy.plan(schema, policy.themeFile(schema, sampleRaw()));
        compare(opFor(planned.ops, "bar.ridgeline").reset, true);
        compare(opFor(planned.ops, "bar.ridgeline").value, undefined);
    }

    function test_apply_touches_nothing_but_the_carried_paths() {
        const planned = policy.plan(schema, policy.themeFile(schema, sampleRaw()));
        compare(paths(planned.ops), policy.carriedPaths(schema.spec));
    }

    function test_forest_default_is_the_deletion_of_every_carried_key() {
        const planned = policy.plan(schema, policy.defaultFile(schema));
        verify(planned.ok);
        verify(planned.ops.length > 0);
        for (const op of planned.ops)
            compare(op.reset, true, op.path + " should be reset by the default theme");
    }

    function test_a_group_is_replaced_whole_and_never_half_merged() {
        // One op for `bar.surface`, carrying the whole group — so a knob the
        // user moved and the theme is silent about does not survive underneath.
        const planned = policy.plan(schema, policy.themeFile(schema, sampleRaw()));
        const surface = planned.ops.filter(op => op.path.startsWith("bar.surface"));
        compare(surface.length, 1);
        compare(surface[0].value.opacity, 0.72);
    }

    // --- migration on apply ---------------------------------------------------

    function test_a_theme_from_an_older_shell_migrates_on_apply() {
        // v1 kept the wallpaper under `background`. A theme is a fragment of the
        // settings file, so it meets the settings file's own migration chain on
        // the way in — this one has nothing of its own to move, which is the
        // point: the version is what is being checked, not the step.
        const old = { settingsVersion: 1, appearance: { mode: "forest" } };
        const planned = policy.plan(schema, old);
        verify(planned.ok);
        compare(planned.from, 1);
        compare(planned.to, schema.version);
        compare(opFor(planned.ops, "appearance.mode").value, "forest");
    }

    function test_a_theme_with_no_stamp_at_all_is_the_oldest_version() {
        const planned = policy.plan(schema, { bar: { surface: { opacity: 0.9 } } });
        verify(planned.ok);
        compare(planned.from, 1);
        compare(planned.to, schema.version);
    }

    function test_a_theme_from_a_newer_shell_is_applied_as_it_stands() {
        // Never downgraded and never pruned: the keys this build does not know
        // are inside a themed group, and the group travels whole.
        const planned = policy.plan(schema, {
            settingsVersion: schema.version + 5,
            bar: { surface: { opacity: 0.8, futureKnob: 7 } }
        });
        verify(planned.ok);
        compare(planned.to, schema.version + 5);
        compare(opFor(planned.ops, "bar.surface").value.futureKnob, 7);
    }

    function test_a_migration_that_throws_applies_nothing() {
        // Half a theme is the one outcome with no way back.
        const broken = {
            spec: schema.spec, versionKey: schema.versionKey, version: 3,
            migrations: [{ to: 3, describe: "boom",
                           migrate: function () { throw new Error("boom"); } }]
        };
        const planned = policy.plan(broken, { settingsVersion: 1 });
        verify(!planned.ok);
        compare(planned.ops.length, 0);
        verify(planned.error.indexOf("boom") >= 0);
    }

    // --- the floor a theme cannot get under (#79) -----------------------------

    function test_a_theme_below_the_opacity_floor_is_coerced_not_applied_raw() {
        // The policy plans the raw value and the schema's coercer — the one
        // `Config.set` runs — is what clamps it. Two halves of the real path,
        // composed here.
        const planned = policy.plan(schema, {
            settingsVersion: schema.version,
            bar: { surface: { opacity: 0.2 } }
        });
        const op = opFor(planned.ops, "bar.surface");
        compare(op.value.opacity, 0.2);

        const leaf = store.leafAt(schema.spec, "bar.surface");
        const coerced = leaf.coerce(op.value);
        compare(coerced.opacity, 0.65);
    }

    function test_a_theme_carrying_nonsense_costs_that_knob_and_not_the_group() {
        const leaf = store.leafAt(schema.spec, "bar.surface");
        ignoreWarning(/ignoring bar\.surface\.opacity/);
        const coerced = leaf.coerce({ opacity: "loud", blur: false });
        compare(coerced.opacity, leaf.def.opacity);
        compare(coerced.blur, false);
    }

    function test_a_theme_that_is_not_an_object_at_that_key_is_refused_outright() {
        const leaf = store.leafAt(schema.spec, "bar.surface");
        compare(leaf.coerce("nord"), undefined);
    }

    // --- the undo slot --------------------------------------------------------

    function test_the_undo_slot_restores_the_pre_apply_state() {
        // The snapshot is the same shape as a theme, so undo is apply. What it
        // has to get right is the key the *applied* theme introduced: restoring
        // has to take it away again, not leave it behind.
        const before = sampleRaw();
        const snapshot = policy.themeFile(schema, before);

        // ...a theme is applied that carries a ridgeline and no palette.
        const applied = policy.plan(schema, {
            settingsVersion: schema.version,
            bar: { ridgeline: { unitWidth: 20 } }
        });
        const after = { settingsVersion: schema.version };
        for (const op of applied.ops)
            if (!op.reset)
                store.setPath(after, op.path, op.value);

        const undone = policy.plan(schema, snapshot);
        compare(opFor(undone.ops, "bar.ridgeline").reset, true);
        compare(opFor(undone.ops, "appearance.paletteOverrides").value,
                ({ accentPrimary: "#8fbf9f" }));
        compare(opFor(undone.ops, "bar.surface").value.opacity, 0.72);

        // And what the ops leave behind is the file that was there before,
        // key for key.
        const restored = { settingsVersion: schema.version };
        for (const op of undone.ops)
            if (!op.reset)
                store.setPath(restored, op.path, op.value);
        compare(policy.fragment(schema.spec, restored),
                policy.fragment(schema.spec, before));
        verify(store.getPath(after, "bar.ridgeline") !== undefined);
    }

    // --- the breadcrumb -------------------------------------------------------

    /// What the shell holds after a theme has been applied: the plan run through
    /// the config engine's own coercers, over resolved defaults. The same thing
    /// `Config.set` does, which is what makes the drift answers below true of a
    /// running shell rather than of an idealised one.
    function applied(file) {
        const values = store.resolve(schema.spec, {}).values;
        for (const op of policy.plan(schema, file).ops) {
            const leaf = store.leafAt(schema.spec, op.path);
            store.setPath(values, op.path,
                          op.reset ? leaf.def : leaf.coerce(op.value));
        }
        return values;
    }

    function test_a_shell_still_wears_the_theme_it_applied() {
        const theme = policy.themeFile(schema, sampleRaw());
        verify(policy.matches(schema, applied(theme), theme));
    }

    function test_a_knob_moved_afterwards_is_a_drift() {
        const theme = policy.themeFile(schema, sampleRaw());
        const values = applied(theme);
        values.bar.surface.opacity = 0.9;
        verify(!policy.matches(schema, values, theme));
    }

    function test_a_layout_change_afterwards_is_not_a_drift() {
        // Layout is not part of the skin, so moving the bar does not stop the
        // theme from being the theme.
        const theme = policy.themeFile(schema, sampleRaw());
        const values = applied(theme);
        values.bar.height = 28;
        values.bar.modules.left = ["workspaces"];
        verify(policy.matches(schema, values, theme));
    }

    function test_a_theme_that_was_coerced_on_the_way_in_is_not_instantly_drifted() {
        // The regression this reading exists for: a theme carrying an opacity
        // under #79's floor is applied *at* the floor, so a drift check that
        // compared the file byte for byte would flag the row it had just ticked.
        const theme = {
            settingsVersion: schema.version,
            bar: { surface: { opacity: 0.2 } }
        };
        verify(policy.matches(schema, applied(theme), theme));
    }

    function test_a_theme_that_spells_out_a_default_is_not_instantly_drifted() {
        // The same bug from the other side: the config engine writes sparsely,
        // so a knob a theme spells out at its shipped value never reaches the
        // file at all.
        const leaf = store.leafAt(schema.spec, "bar.ridgeline");
        const theme = {
            settingsVersion: schema.version,
            bar: { ridgeline: { gap: leaf.def.gap } }
        };
        verify(policy.matches(schema, applied(theme), theme));
    }

    function test_an_untouched_shell_wears_forest_default() {
        const shipped = policy.defaultFile(schema);
        verify(policy.matches(schema, store.resolve(schema.spec, {}).values, shipped));
        verify(!policy.matches(schema, store.resolve(schema.spec, sampleRaw()).values, shipped));
    }

    function test_a_theme_the_config_would_refuse_outright_is_never_worn() {
        // `bar.surface` as a string is refused by the group's coercer, so
        // nothing was applied and nothing can be wearing it.
        const theme = { settingsVersion: schema.version, bar: { surface: "nord" } };
        verify(!policy.matches(schema, store.resolve(schema.spec, {}).values, theme));
    }

    function test_the_key_count_in_the_log_counts_keys_and_not_sections() {
        // Two carried keys in two sections, plus the version stamp.
        const file = policy.themeFile(schema, sampleRaw());
        compare(policy.carriedCount(schema, file), 3);
        compare(policy.carriedCount(schema, policy.defaultFile(schema)), 0);
    }

    // --- names ----------------------------------------------------------------

    function test_a_name_is_a_file_name() {
        compare(policy.refusal("Nord"), "");
        compare(policy.fileName("Nord"), "Nord.json");
        compare(policy.fileName("  Nord  "), "Nord.json");
        compare(policy.nameOf("/c/themes/Nord.json"), "Nord");
    }

    function test_a_name_is_never_silently_rewritten() {
        // A theme saved as `Deep Woods` is listed as `Deep Woods`, not
        // `deep-woods`: identity is the file name, and a slug is a rename.
        compare(policy.fileName("Deep Woods"), "Deep Woods.json");
    }

    function test_the_names_a_save_refuses() {
        verify(policy.refusal("") !== "");
        verify(policy.refusal("   ") !== "");
        verify(policy.refusal("../escape") !== "");
        verify(policy.refusal("a/b") !== "");
        verify(policy.refusal(".hidden") !== "");
        verify(policy.refusal("x".repeat(65)) !== "");
        compare(policy.fileName("a/b"), "");
    }

    function test_the_two_built_in_entries_are_not_names_to_save_under() {
        verify(policy.refusal(policy.defaultName) !== "");
        verify(policy.refusal(policy.undoName) !== "");
        verify(policy.refusal("forest (DEFAULT)") !== "");
    }

    function test_a_file_that_is_not_a_theme_has_no_name() {
        compare(policy.nameOf("/c/themes/notes.txt"), "");
        compare(policy.nameOf(""), "");
    }

    // --- the list -------------------------------------------------------------

    function test_the_list_is_alphabetical_and_ignores_everything_else() {
        const rows = policy.entries([
            { path: "/t/zinc.json" }, { path: "/t/README.md" },
            { path: "/t/Alder.json" }, { path: "/t/moss.json" }
        ], "", false);
        compare(rows.map(row => row.name), ["Alder", "moss", "zinc"]);
    }

    function test_the_applied_theme_is_marked_and_can_be_marked_drifted() {
        const files = [{ path: "/t/moss.json" }, { path: "/t/zinc.json" }];
        const clean = policy.entries(files, "moss", false);
        compare(clean[0].applied, true);
        compare(clean[0].drifted, false);
        compare(clean[1].applied, false);

        const drifted = policy.entries(files, "moss", true);
        compare(drifted[0].drifted, true);
        // Drift is a property of the applied row and nothing else.
        compare(drifted[1].drifted, false);
    }

    function test_a_breadcrumb_naming_a_theme_that_is_gone_marks_nothing() {
        const rows = policy.entries([{ path: "/t/moss.json" }], "nord", true);
        compare(rows.length, 1);
        compare(rows[0].applied, false);
    }
}
