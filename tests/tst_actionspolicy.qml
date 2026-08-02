// The actions provider's decisions (#40) — the table, the matching, and the
// three rules the ticket's maintenance pass set before it was built.
//
// Two of the checks below reach *out* of Services/Launcher, into
// Core/SurfaceBusPolicy.qml and Surfaces/Settings/SettingsTabs.qml. That is
// deliberate and it is where the coupling belongs: ActionsPolicy must not
// import either at runtime — one is a dependency in the wrong direction and the
// other is on the far side of the Quickshell line — so the agreement between
// them is enforced here instead of being left as a comment.
import QtQuick
import QtTest
import "../Services/Launcher"
import "../Core"
import "../Surfaces/Settings"

TestCase {
    id: testCase
    name: "ActionsPolicy"

    ActionsPolicy { id: policy }
    SurfaceBusPolicy { id: bus }
    SettingsTabs { id: tabs }

    /// The context the shell hands in: the mode it is in, and the settings
    /// window's own tab list.
    readonly property var dark: ({ dark: true, settingsTabs: tabs.tabs })
    readonly property var light: ({ dark: false, settingsTabs: tabs.tabs })

    function ids(rows) {
        return rows.map(row => row.run.id);
    }

    function find(id) {
        return policy.catalogue(testCase.dark).find(action => action.id === id) ?? null;
    }

    // --- the rules the maintenance pass set ----------------------------------

    function test_no_action_names_a_verb_the_cli_eats() {
        // #77: `qs ipc call settings show` is parsed as `qs ipc show`, prints
        // the target listing and exits 0. An action naming it is an action
        // nobody can bind a key to.
        for (const action of policy.catalogue(testCase.dark))
            verify(policy.callable(action.verb));
    }

    function test_the_reserved_list_still_agrees_with_the_bus() {
        // Stated in two files because neither may import the other; this is
        // the check that keeps them the same list.
        compare(policy.reservedVerbs.length, bus.reservedVerbs.length);
        for (const verb of bus.reservedVerbs)
            verify(policy.reservedVerbs.indexOf(verb) >= 0);
    }

    function test_the_settings_actions_dispatch_open_and_showtab() {
        compare(testCase.find("settings.open").verb, "open");
        compare(testCase.find("settings.appearance").verb, "showTab");
        compare(testCase.find("settings.appearance").arg, "appearance");
    }

    function test_every_settings_tab_has_an_action_and_every_action_a_tab() {
        const catalogue = policy.catalogue(testCase.dark);
        for (const tab of tabs.tabs)
            verify(testCase.find("settings." + tab.id) !== null);

        // ...and nothing invents a tab. `settings.open` is the one settings
        // action with no tab, which is what its empty `arg` says.
        for (const action of catalogue) {
            if (action.kind !== "settings" || action.arg === "")
                continue;
            verify(tabs.find(action.arg) !== null);
        }
    }

    function test_the_theme_row_is_a_caller_and_says_what_will_happen() {
        // The overlap #44 and #58 were asked to resolve resolves to "Core/
        // Theme.qml already owns it". This table holds no mode of its own —
        // the title is a function of the mode it was handed.
        compare(policy.catalogue(testCase.dark)[0].title, "Switch to light mode");
        compare(policy.catalogue(testCase.light)[0].title, "Switch to dark mode");
        compare(policy.catalogue(testCase.dark)[0].icon, "sun");
        compare(policy.catalogue(testCase.light)[0].icon, "moon");
    }

    // --- what is and is not in the table -------------------------------------

    function test_the_destructive_session_verbs_are_behind_the_menu() {
        // #40's acceptance criterion says "session menu", and the menu orders
        // its own rows least-destructive-first precisely because a mis-aimed
        // press should not end the session. A fuzzy-matched row that shuts the
        // machine down on one Enter throws that away.
        verify(testCase.find("session.menu") !== null);
        compare(testCase.find("session.menu").kind, "surface");
        compare(testCase.find("session.menu").arg, "session");

        for (const id of ["session.logout", "session.suspend",
                          "session.reboot", "session.shutdown"])
            compare(testCase.find(id), null);
    }

    function test_locking_is_the_exception_and_is_direct() {
        // The one session action that cannot lose work.
        compare(testCase.find("session.lock").kind, "lock");
    }

    function test_the_session_row_is_reachable_by_the_verbs_it_hides() {
        // Typing what you want must reach the menu that offers it, or hiding
        // them behind it costs the user the search instead of a keystroke.
        for (const word of ["logout", "suspend", "restart", "shutdown", "reboot"])
            compare(policy.rows(word, testCase.dark)[0].run.id, "session.menu");
    }

    function test_the_bus_name_the_session_row_uses_is_one_the_bus_knows() {
        verify(bus.known(testCase.find("session.menu").arg));
    }

    // --- matching ------------------------------------------------------------

    function test_an_empty_query_is_the_whole_table_in_table_order() {
        const rows = policy.rows("", testCase.dark);
        compare(rows.length, policy.catalogue(testCase.dark).length);
        // The four hand-written rows first: an empty `/` should open on the
        // things you meant, not on the eleventh settings tab.
        compare(rows[0].run.id, "theme.toggle");
        compare(rows[1].run.id, "session.lock");
    }

    function test_a_title_hit_outranks_a_keyword_hit() {
        compare(policy.rows("dark", testCase.light)[0].run.id, "theme.toggle");
        compare(policy.rows("lock", testCase.dark)[0].run.id, "session.lock");
    }

    function test_naming_the_window_offers_the_window_not_its_third_tab() {
        // Eleven rows begin with "Settings", and the fuzzy scorer pays a bonus
        // for a hit at position zero — so without the exact rungs `/settings`
        // ranked "Settings — Bar" above "Open settings".
        compare(policy.rows("settings", testCase.dark)[0].run.id, "settings.open");
    }

    function test_a_keyword_reaches_a_tab_its_name_does_not_contain() {
        compare(policy.rows("wallpaper", testCase.dark)[0].run.id, "settings.wallpaper");
        compare(policy.rows("dnd", testCase.dark)[0].run.id, "settings.notifications");
    }

    function test_a_query_that_matches_nothing_returns_nothing() {
        compare(policy.rows("zzzzqqq", testCase.dark).length, 0);
        verify(policy.silence("zzzzqqq").text.indexOf("zzzzqqq") >= 0);
        compare(policy.silence(""), null);
    }

    // --- the rows ------------------------------------------------------------

    function test_a_row_carries_its_descriptor_whole() {
        // Not an id to look up again: the table is rebuilt per keystroke, and
        // an id resolved a second time is resolved against a different list.
        const row = policy.rows("dark", testCase.light)[0];
        compare(row.provider, "actions");
        compare(row.category, "Action");
        compare(row.copy, "");
        compare(row.run.kind, "theme");
        compare(row.run.id, "theme.toggle");
    }

    function test_an_unbuilt_tab_says_so_before_you_open_it() {
        const built = policy.rows("appearance", testCase.dark)[0];
        compare(built.subtitle, "Settings");
        verify(testCase.find("settings.dashboard") !== null);
        verify(policy.tabHint({ id: "dashboard", built: false })
                     .indexOf("not built yet") >= 0);
    }

    function test_row_ids_are_unique_across_the_table() {
        const seen = ({});
        for (const row of policy.rows("", testCase.dark)) {
            verify(seen[row.id] === undefined);
            seen[row.id] = true;
        }
    }
}
