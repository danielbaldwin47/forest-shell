// Registry-driven dashboard layout (#49): the config names cards, the registry
// decides which names exist, and a bad name costs one card rather than the
// dashboard.
//
// The bar's registry is the prior art (tests/tst_barregistry.qml) and the rules
// are the same three: presence is enablement, order is the config's, a name
// nobody built is dropped with a warning.
import QtQuick
import QtTest
import "../Surfaces/Drawers"
import "../Core"

TestCase {
    name: "DashboardRegistry"

    DashboardRegistry { id: registry }
    SettingsSchema { id: settings }
    SpecStore { id: store }

    function test_the_default_card_list_only_names_cards_that_exist() {
        const cards = store.defaults(settings.spec).dashboard.cards;
        for (const name of cards)
            verify(registry.known(name), name + " is in the default dashboard but not the registry");
    }

    function test_the_default_card_list_survives_resolution_unchanged() {
        const cards = store.defaults(settings.spec).dashboard.cards;
        compare(registry.resolve(cards), cards);
    }

    function test_order_is_the_config_order() {
        // The whole point of the key: the cards stack in the order the file
        // lists, not in registry order.
        compare(registry.resolve(["media", "calendar"]), ["media", "calendar"]);
        compare(registry.resolve(["calendar", "media"]), ["calendar", "media"]);
    }

    function test_a_card_left_out_of_the_list_is_a_card_that_is_off() {
        // Presence is enablement — there is no `enabled` flag, for the reason
        // the bar's registry gives: two ways to say the same thing is one too
        // many for a file people hand-edit.
        compare(registry.resolve(["calendar"]), ["calendar"]);
        compare(registry.resolve([]), []);
    }

    function test_an_unknown_name_costs_one_card() {
        ignoreWarning(/no such card: horoscope/);
        compare(registry.resolve(["calendar", "horoscope", "media"]), ["calendar", "media"]);
    }

    function test_a_card_cannot_appear_twice() {
        // A card is a thing on the dashboard rather than a template: two
        // calendars would be two things claiming to be the month.
        ignoreWarning(/card listed twice: calendar/);
        compare(registry.resolve(["calendar", "media", "calendar"]), ["calendar", "media"]);
    }

    function test_a_list_that_is_not_a_list_answers_with_an_empty_dashboard() {
        // The consumer iterates the result, so `undefined` here would be a
        // `.length` of nothing at dashboard-construction time.
        compare(registry.resolve(null), []);
        compare(registry.resolve(undefined), []);
        compare(registry.resolve("calendar"), []);
    }

    function test_the_registry_and_the_settings_pool_agree() {
        // The vocabulary is what a settings GUI would offer as the pool to drag
        // from, and the registry is what resolves the result. A card in the
        // registry the vocabulary does not list is one the GUI could remove and
        // never put back.
        //
        // Only one way round: the vocabulary deliberately names the two cards
        // #50 adds, which is how a config written for a newer shell keeps them.
        for (const name in registry.cards)
            verify(settings.dashboardCards.indexOf(name) >= 0,
                   name + " is in the registry but not in the settings vocabulary");
    }

    function test_every_registered_card_names_a_file_and_a_label() {
        for (const name in registry.cards) {
            const entry = registry.cards[name];
            verify(/\.qml$/.test(entry.file), name + " does not name a QML file");
            verify(entry.label !== undefined && entry.label !== "", name + " has no label");
        }
    }

    // --- what counts as a change (#75) ---------------------------------------

    function test_the_same_cards_in_the_same_order_are_the_same_dashboard() {
        // The check that keeps a `Repeater` from rebuilding every card when an
        // unrelated key is written: a config reload replaces `Config.values`
        // whole, so the resolved list arrives as a new array with the same names
        // in it on every save of anything.
        verify(registry.same(["calendar", "media"], ["calendar", "media"]));
        verify(registry.same([], []));
    }

    function test_reordering_is_a_change_and_so_is_adding_or_removing() {
        verify(!registry.same(["calendar", "media"], ["media", "calendar"]));
        verify(!registry.same(["calendar"], ["calendar", "media"]));
        verify(!registry.same(["calendar", "media"], ["calendar"]));
    }

    function test_a_missing_list_compares_as_an_empty_dashboard() {
        // `same` is asked before the first resolution has happened, so it has to
        // answer about a list that is not there yet rather than throwing.
        verify(registry.same(null, []));
        verify(registry.same(undefined, null));
        verify(!registry.same(null, ["calendar"]));
    }

    function test_the_two_cards_this_ticket_ships_are_both_here() {
        verify(registry.known("calendar"));
        verify(registry.known("media"));
        // #50's two are vocabulary and not registry: a name the shell can keep
        // in a config file, and cannot yet draw.
        verify(!registry.known("weather"));
        verify(!registry.known("systemMonitor"));
    }
}
