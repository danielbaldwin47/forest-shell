// The spec-table store (#33): one nested `{ def, coerce, onChange }` table
// drives defaults, parsing, sparse serialization and change dispatch for both
// settings.json and state.json. Everything the config engine does to a file is
// decided here; Core/SpecFile.qml only does the IO.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "SpecStore"

    SpecStore { id: store }
    Coerce { id: c }

    readonly property var spec: ({
        bar: {
            position: { def: "top", coerce: c.oneOf(["top", "bottom"]) },
            height: { def: 36, coerce: c.integer(20, 96) },
            // A theme-flagged group: a whole sub-object, atomic by design.
            surface: { def: ({}), coerce: c.object, themed: true }
        },
        wallpaper: {
            path: { def: "", coerce: c.path }
        }
    })

    // --- shape ---------------------------------------------------------------

    function test_a_node_with_def_is_a_leaf() {
        verify(store.isLeaf({ def: 1 }));
        verify(store.isLeaf({ def: ({}) }));   // whole sub-object leaf
        verify(!store.isLeaf({ height: { def: 1 } }));
        verify(!store.isLeaf("top"));
    }

    function test_leaf_paths_are_dotted_and_complete() {
        const paths = store.leafPaths(spec);
        compare(paths.length, 4);
        verify(paths.indexOf("bar.height") >= 0);
        verify(paths.indexOf("wallpaper.path") >= 0);
        // The themed group is one path, not a path per key inside it.
        verify(paths.indexOf("bar.surface") >= 0);
    }

    function test_leaf_at_finds_leaves_and_nothing_else() {
        compare(store.leafAt(spec, "bar.height").def, 36);
        compare(store.leafAt(spec, "bar"), null);
        compare(store.leafAt(spec, "bar.nope"), null);
        // Inside a whole-sub-object leaf there are no addressable keys.
        compare(store.leafAt(spec, "bar.surface.color"), null);
    }

    function test_defaults_mirror_the_spec_shape() {
        const defaults = store.defaults(spec);
        compare(defaults.bar.position, "top");
        compare(defaults.bar.height, 36);
        compare(defaults.wallpaper.path, "");
    }

    function test_defaults_do_not_share_state_with_the_spec() {
        // A consumer mutating its copy must not rewrite the default for every
        // later reload.
        const defaults = store.defaults(spec);
        defaults.bar.surface.color = "#fff";
        compare(Object.keys(store.defaults(spec).bar.surface).length, 0);
    }

    // --- dotted access -------------------------------------------------------

    function test_get_path_reads_nested_and_missing() {
        compare(store.getPath({ bar: { height: 40 } }, "bar.height"), 40);
        compare(store.getPath({ bar: {} }, "bar.height"), undefined);
        compare(store.getPath({}, "bar.height.deep"), undefined);
    }

    function test_set_path_creates_missing_sections() {
        const out = {};
        store.setPath(out, "bar.height", 40);
        compare(out.bar.height, 40);
    }

    function test_unset_path_prunes_the_sections_it_empties() {
        // A sparse file should not accumulate `"bar": {}` husks after a
        // reset-to-defaults.
        const out = { bar: { height: 40 }, wallpaper: { path: "/a.jpg" } };
        store.unsetPath(out, "bar.height");
        compare(out.bar, undefined);
        compare(out.wallpaper.path, "/a.jpg");
    }

    function test_unset_path_keeps_sections_that_still_hold_keys() {
        const out = { bar: { height: 40, custom: 1 } };
        store.unsetPath(out, "bar.height");
        compare(out.bar.custom, 1);
    }

    // --- resolve -------------------------------------------------------------

    function test_resolve_fills_every_leaf() {
        const resolved = store.resolve(spec, { bar: { height: 44 } });
        compare(resolved.values.bar.height, 44);
        compare(resolved.values.bar.position, "top");
        compare(resolved.values.wallpaper.path, "");
        compare(resolved.issues.length, 0);
    }

    function test_resolve_coerces_hand_edited_values() {
        const resolved = store.resolve(spec, { bar: { height: "44" } });
        compare(resolved.values.bar.height, 44);
        compare(resolved.issues.length, 0);
    }

    function test_resolve_falls_back_per_key_and_reports_it() {
        const resolved = store.resolve(spec, { bar: { position: "sideways", height: 44 } });
        compare(resolved.values.bar.position, "top");
        compare(resolved.values.bar.height, 44);   // the neighbour is untouched
        compare(resolved.issues.length, 1);
        compare(resolved.issues[0].path, "bar.position");
        compare(resolved.issues[0].value, "sideways");
    }

    function test_resolve_ignores_keys_the_spec_does_not_know() {
        const resolved = store.resolve(spec, { futureSection: { key: 1 } });
        compare(resolved.values.futureSection, undefined);
        compare(resolved.issues.length, 0);
    }

    // --- serialize -----------------------------------------------------------

    function test_serialize_writes_only_changed_keys() {
        const values = store.defaults(spec);
        values.bar.height = 44;
        const out = store.serialize(spec, values, {});
        compare(out.bar.height, 44);
        compare(out.bar.position, undefined);
        compare(out.wallpaper, undefined);
    }

    function test_serialize_deletes_keys_returned_to_default() {
        // Reset-to-default is key deletion, so a later change to the shipped
        // default flows through instead of being pinned by a stale write.
        const out = store.serialize(spec, store.defaults(spec), { bar: { height: 44 } });
        compare(out.bar, undefined);
    }

    function test_serialize_preserves_unknown_keys() {
        // A file written by a newer forest-shell must survive a save by an
        // older one.
        const values = store.defaults(spec);
        values.bar.height = 44;
        const out = store.serialize(spec, values, {
            settingsVersion: 2,
            bar: { futureKey: "keep me" },
            futureSection: { deep: true }
        });
        compare(out.settingsVersion, 2);
        compare(out.bar.futureKey, "keep me");
        compare(out.bar.height, 44);
        compare(out.futureSection.deep, true);
    }

    function test_serialize_does_not_mutate_the_file_it_was_given() {
        const raw = { bar: { height: 44 } };
        store.serialize(spec, store.defaults(spec), raw);
        compare(raw.bar.height, 44);
    }

    function test_serialize_round_trips_through_resolve() {
        const raw = { bar: { height: 44, futureKey: 1 } };
        const out = store.serialize(spec, store.resolve(spec, raw).values, raw);
        compare(JSON.stringify(out), JSON.stringify(raw));
    }

    function test_serialize_keeps_whole_sub_object_leaves_whole() {
        const values = store.defaults(spec);
        values.bar.surface = { tint: "#123" };
        const out = store.serialize(spec, values, { bar: { surface: { blur: 2 } } });
        // A preset replaces the group; it does not merge into leftover keys.
        compare(out.bar.surface.blur, undefined);
        compare(out.bar.surface.tint, "#123");
    }

    // --- change dispatch -----------------------------------------------------

    function test_changed_paths_lists_only_what_moved() {
        const before = store.defaults(spec);
        const after = store.defaults(spec);
        after.bar.height = 44;
        after.wallpaper.path = "/a.jpg";
        const changed = store.changedPaths(spec, before, after);
        compare(changed.length, 2);
        verify(changed.indexOf("bar.height") >= 0);
        verify(changed.indexOf("wallpaper.path") >= 0);
    }

    function test_changed_paths_compares_structures_by_value() {
        // Reload builds a fresh values object every time, so identity
        // comparison would report every key as changed on every reload.
        const before = store.defaults(spec);
        const after = store.defaults(spec);
        compare(store.changedPaths(spec, before, after).length, 0);
    }

    function test_equals_is_deep() {
        verify(store.equals({ a: [1, { b: 2 }] }, { a: [1, { b: 2 }] }));
        verify(!store.equals({ a: [1] }, { a: [1, 2] }));
        verify(!store.equals({ a: 1 }, { a: 1, b: 2 }));
        verify(!store.equals(0, false));
    }
}
