// Registry-driven bar layout (#9, #35): the config names modules, the registry
// decides which names exist, and a bad name costs one module rather than the
// bar.
import QtQuick
import QtTest
import "../Surfaces/Bar"
import "../Surfaces/Settings/Controls"
import "../Core"

TestCase {
    name: "BarRegistry"

    BarRegistry { id: registry }
    SettingsSchema { id: settings }
    SpecStore { id: store }
    FieldPolicy { id: fields }

    function test_the_default_layout_only_names_modules_that_exist() {
        // The shipped default has to survive its own registry — a default
        // naming a module nobody wrote would warn on every clean install.
        const layout = store.defaults(settings.spec).bar.modules;
        for (const cluster of registry.clusters)
            for (const name of layout[cluster])
                verify(registry.known(name), name + " is in the default bar but not the registry");
    }

    function test_the_default_layout_survives_resolution_unchanged() {
        const layout = store.defaults(settings.spec).bar.modules;
        const resolved = registry.resolve(layout);
        compare(resolved.left, layout.left);
        compare(resolved.center, layout.center);
        compare(resolved.right, layout.right);
    }

    function test_order_is_the_config_order() {
        // The whole point of the key: the bar is laid out in the order the
        // file lists, not in registry order.
        const resolved = registry.resolve({ left: ["clock", "workspaces"] });
        compare(resolved.left, ["clock", "workspaces"]);
    }

    function test_an_unknown_name_costs_one_module() {
        ignoreWarning(/no such module: waybar/);
        const resolved = registry.resolve({ left: ["workspaces", "waybar", "clock"] });
        compare(resolved.left, ["workspaces", "clock"]);
    }

    function test_a_module_cannot_appear_twice() {
        // Not even in two different clusters: a module is a thing on the bar,
        // not a template.
        ignoreWarning(/module listed twice: clock/);
        ignoreWarning(/module listed twice: clock/);
        const resolved = registry.resolve({
            left: ["clock", "clock"],
            center: ["clock"],
            right: ["workspaces"]
        });
        compare(resolved.left, ["clock"]);
        compare(resolved.center, []);
        compare(resolved.right, ["workspaces"]);
    }

    function test_every_cluster_is_answered() {
        // Consumers iterate the result, so a missing cluster would be a
        // `undefined.length` at bar-construction time.
        const resolved = registry.resolve({});
        for (const cluster of registry.clusters)
            compare(resolved[cluster], []);
        for (const cluster of registry.clusters)
            compare(registry.resolve(null)[cluster], []);
    }

    function test_the_registry_and_the_settings_pool_agree() {
        // The Bar tab offers `Config.schema.barModules` as the pool you drag
        // from (Surfaces/Settings/Tabs/BarTab.qml), and the registry is what
        // resolves the result. A module in the registry that the vocabulary
        // does not list is one the GUI can never add — and one the GUI removes
        // and cannot put back.
        //
        // Only one way round: the vocabulary deliberately names modules that
        // are not built yet (the notification indicator, the three optional
        // readouts), which is how a config written for a newer shell keeps
        // them.
        for (const name in registry.modules)
            verify(settings.barModules.indexOf(name) >= 0,
                   name + " is in the registry but not in the settings vocabulary");
    }

    function test_the_pool_greys_exactly_what_the_registry_cannot_draw() {
        // The other way round, and the reason the Bar tab can offer the whole
        // vocabulary without lying about it (#72): what the pool greys is
        // computed from `registry.modules` at the point of use, so a module
        // landing in the registry un-greys its chip with no second list to
        // edit. This asserts the wiring, not a count — the set will shrink to
        // empty as #36, #37 and #52 register their modules, and that is the
        // shape of it working.
        const greyed = fields.unsupported(settings.barModules, registry.modules);

        for (const name of greyed)
            verify(!registry.known(name), name + " is greyed but the registry can draw it");
        for (const name in registry.modules)
            verify(greyed.indexOf(name) < 0, name + " is drawable but greyed");
    }

    function test_every_registered_module_names_a_file_and_a_label() {
        for (const name in registry.modules) {
            const entry = registry.modules[name];
            verify(/\.qml$/.test(entry.file), name + " does not name a QML file");
            verify(entry.label !== undefined && entry.label !== "", name + " has no label");
        }
    }
}
