// The bar as data (#35): the module layout config orders, and the surface
// knobs behind the atomic `bar.surface` group.
//
// The live QML next to this file imports Quickshell and so cannot be loaded
// here; what it adds is the painting, which the shell verifies by running (see
// the ticket's acceptance criteria).
import QtQuick
import QtTest
import "../Surfaces/Bar"

TestCase {
    name: "BarSpec"

    BarSpec { id: spec }

    // --- the surface ---------------------------------------------------------

    function test_the_shipped_surface_is_the_measured_one() {
        // 86% fill over compositor-blurred wallpaper, measured at 7.12:1 for
        // text-secondary on the brightest pin (#10).
        const surface = spec.surface({});
        compare(surface.fillOpacity, 0.86);
        compare(surface.topLight, true);
        compare(surface.wash, true);
        compare(surface.hairline, true);
        compare(surface.grain, true);
    }

    function test_adaptive_opacity_is_off_by_default() {
        compare(spec.surface({}).adaptiveOpacity, false);
    }

    function test_fill_opacity_cannot_be_thinned_past_legibility() {
        // Not taste: below this the bar stops clearing 4.5:1 over a bright sky,
        // and the failure only shows up on some wallpapers (#10 §2).
        compare(spec.minFillOpacity, 0.65);
        compare(spec.surface({ fillOpacity: 0.2 }).fillOpacity, 0.65);
        compare(spec.surface({ fillOpacity: 0.0 }).fillOpacity, 0.65);
        compare(spec.surface({ fillOpacity: 1.4 }).fillOpacity, 1.0);
        compare(spec.surface({ fillOpacity: 0.7 }).fillOpacity, 0.7);
    }

    function test_a_hand_edited_surface_is_salvaged_not_rejected() {
        compare(spec.surface({ fillOpacity: "0.9" }).fillOpacity, 0.9);
        compare(spec.surface({ grain: "false" }).grain, false);
        // One unreadable key costs that key, never the surface.
        compare(spec.surface({ fillOpacity: "solid" }).fillOpacity, 0.86);
        compare(spec.surface({ grain: 3 }).grain, true);
        // A group that is not a group at all still leaves a painted bar.
        compare(spec.surface(null).fillOpacity, 0.86);
        compare(spec.surface("nope").topLight, true);
        compare(spec.surface(undefined).grain, true);
    }

    // --- the module layout ---------------------------------------------------

    function test_every_registry_id_can_be_placed() {
        // The id list is the registry as far as config is concerned.
        const layout = spec.modules({ left: spec.moduleIds, center: [], right: [] });
        compare(layout.left.join(","), spec.moduleIds.join(","));
    }

    function test_the_layout_is_ordered_by_the_config() {
        const layout = spec.modules({ left: ["clock"], center: [], right: ["workspaces"] });
        compare(layout.left.join(","), "clock");
        compare(layout.center.length, 0);
        compare(layout.right.join(","), "workspaces");
    }

    function test_naming_one_slot_replaces_the_whole_layout() {
        // The group is atomic, like every themed group: per-slot merging would
        // make "take the clock off my bar" impossible to write down.
        const layout = spec.modules({ left: ["clock"] });
        compare(layout.left.join(","), "clock");
        compare(layout.center.length, 0);
        compare(layout.right.length, 0);
    }

    function test_an_unknown_module_is_dropped_not_drawn() {
        ignoreWarning(/unknown module in bar\.modules\.left: teapot/);
        const layout = spec.modules({ left: ["workspaces", "teapot"] });
        compare(layout.left.join(","), "workspaces");
    }

    function test_a_module_is_placed_once() {
        // One module, one place on the bar — two clocks is a typo, not a wish.
        ignoreWarning(/module placed twice, keeping the first: clock/);
        const layout = spec.modules({ left: ["clock"], right: ["clock"] });
        compare(layout.left.join(","), "clock");
        compare(layout.right.length, 0);
    }

    function test_a_slot_that_is_not_a_list_is_empty() {
        const layout = spec.modules({ left: "clock", center: 7, right: null });
        compare(layout.left.length, 0);
        compare(layout.center.length, 0);
        compare(layout.right.length, 0);
    }

    function test_every_slot_is_always_present() {
        // Consumers iterate the three clusters unconditionally.
        for (const value of [null, undefined, {}, "x", []])
            for (const slot of spec.slotNames)
                verify(Array.isArray(spec.modules(value)[slot]), slot + " missing");
    }
}
