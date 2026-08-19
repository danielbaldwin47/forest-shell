// The settings window's tab list (#54, #55), and the invariant that gives the
// config file its shape: the tabs and the sections of `settings.json` are the
// same list.
//
// That mapping is why hand-editing the file and using the window are the same
// mental model (#21). It is easy to break by accident — a section added without
// a tab is a setting the GUI cannot reach, and a tab without a section is a tab
// with nothing in it — and neither shows up until someone goes looking, so it is
// checked here rather than described in a comment.
import QtQuick
import QtTest
import "../Core"
import "../Surfaces/Settings"

TestCase {
    name: "SettingsTabs"

    SettingsTabs { id: registry }
    SettingsSchema { id: settings }

    function test_there_are_eleven_tabs() {
        // The number is a decision (#9), not an accident of the list below. It
        // moved from ten to eleven when the calendar gained a Google account to
        // configure: a section without a tab is a setting the GUI cannot reach,
        // so the count follows the sections rather than holding them back.
        compare(registry.tabs.length, 11);
    }

    function test_every_tab_maps_to_a_config_section() {
        for (const tab of registry.tabs) {
            if (tab.section === "")
                continue;
            verify(settings.spec[tab.section] !== undefined,
                   tab.id + " names a section the schema does not have");
        }
    }

    function test_every_config_section_has_a_tab() {
        const sections = registry.tabs.map(tab => tab.section);
        for (const section in settings.spec)
            verify(sections.indexOf(section) >= 0, section + " has no settings tab");
    }

    function test_exactly_one_tab_configures_nothing() {
        // About: a version number, credits and the changelog-seen flag, which is
        // state. Any other sectionless tab is a tab that forgot its section.
        const sectionless = registry.tabs.filter(tab => tab.section === "");
        compare(sectionless.length, 1);
        compare(sectionless[0].id, "about");
    }

    function test_ids_and_titles_are_unique() {
        const ids = registry.tabs.map(tab => tab.id);
        const titles = registry.tabs.map(tab => tab.title);
        compare(ids.filter((id, i) => ids.indexOf(id) !== i).length, 0);
        compare(titles.filter((title, i) => titles.indexOf(title) !== i).length, 0);
    }

    function test_every_tab_names_an_icon() {
        for (const tab of registry.tabs)
            verify(tab.icon !== undefined && tab.icon !== "", tab.id + " has no icon");
    }

    function test_every_tab_is_built() {
        // #54 shipped the frame and the first four; #55 shipped the other six,
        // so `built` is now true everywhere and the rail marks nothing. The
        // flag stays because it is what the rail and `pageFor` read: a
        // half-landed eleventh tab should show a placeholder rather than an
        // empty page, and this check is what says the list is complete today.
        const unbuilt = registry.tabs.filter(tab => !tab.built).map(tab => tab.id);
        compare(unbuilt.join(","), "");
    }

    function test_an_unknown_tab_id_opens_the_first_tab() {
        // Every way into the window goes through `resolve`: a stale id in the
        // state file, and whatever someone types into `qs ipc call settings
        // show`. An empty window would be a worse answer than the wrong one.
        compare(registry.resolve("bar"), "bar");
        compare(registry.resolve(""), registry.firstTab);
        compare(registry.resolve("nonesuch"), registry.firstTab);
        compare(registry.firstTab, "appearance");
    }

    function test_arrow_keys_walk_the_rail_in_order() {
        // #77: the rail was pointer-only. Up and Down move one tab, in the
        // order the list above states, and stop at the ends — walking off the
        // bottom staying on About is a better answer than jumping back to the
        // top of a list the user can see.
        compare(registry.neighbour("appearance", 1), "bar");
        compare(registry.neighbour("bar", -1), "appearance");
        compare(registry.neighbour("appearance", -1), "appearance");
        compare(registry.neighbour("about", 1), "about");
    }

    function test_arrow_keys_walk_the_whole_rail() {
        // The keyboard walks the same rail the pointer does, and it never
        // skips: the rail's order is the registry's order, including the six
        // tabs #55 added in the middle of it rather than at the end.
        compare(registry.neighbour("launcher", 1), "controlCenter");
        compare(registry.neighbour("controlCenter", 1), "dashboard");
        compare(registry.neighbour("notifications", 1), "weatherTime");
        compare(registry.neighbour("weatherTime", 1), "calendar");
        compare(registry.neighbour("calendar", 1), "wallpaper");
        compare(registry.neighbour("wallpaper", 1), "system");
        compare(registry.neighbour("system", 1), "about");
    }

    function test_arrow_keys_from_an_id_that_is_not_a_tab() {
        // Same fallback as every other entry point: a stale id in the state
        // file behaves as the first tab rather than throwing.
        compare(registry.neighbour("nonesuch", 1), "bar");
        compare(registry.neighbour("", -1), registry.firstTab);
    }

    function test_find_returns_null_for_an_unknown_id() {
        compare(registry.find("nonesuch"), null);
        compare(registry.find("about").title, "About");
    }
}
