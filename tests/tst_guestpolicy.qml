// Who the guest picker offers, in what order, and what a guest looks like.
//
// Two kinds of case here. The ordering ones are about a person's expectation
// rather than a boundary: typing the first letters of a name must put that name
// first, and must keep putting it first — a picker whose order wobbles is
// unusable even when every candidate it returns is correct. The folding ones
// are the boundary kind, and they are all about characters that look like a
// letter but are not the letter: é, ø, ß, and the whole-name-versus-word seam
// where "Casimir" contains what "Mira" starts with.
//
// The unknown-guest cases are the ones worth keeping honest. A guest with no
// contact record still has to render, and an address nobody has met still has
// to be invitable, because both are states a real events file reaches.
import QtQuick
import QtTest
import "../Services/Calendar"

TestCase {
    id: testCase

    name: "GuestPolicy"

    GuestPolicy { id: guests }

    // The fixture list, in fixture order — tools/fixtures/calendar-contacts.json.
    readonly property var contacts: [
        { id: "mira",  name: "Mira Okonkwo",   email: "mira@example.org",  colour: "#7aa2f7" },
        { id: "juno",  name: "Juno Alvarez",   email: "juno@example.org",  colour: "#9ece6a" },
        { id: "tabby", name: "Tabitha Fenn",   email: "tabby@example.org", colour: "#e0af68" },
        { id: "rune",  name: "Rune Halvorsen", email: "rune@example.org",  colour: "#bb9af7" },
        { id: "opal",  name: "Opal Nakamura",  email: "opal@example.org",  colour: "#7dcfff" },
        { id: "cass",  name: "Cass Delacroix", email: "cass@example.org",  colour: "#f7768e" },
        { id: "birch", name: "Birch Odili",    email: "birch@example.org", colour: "#73daca" },
        { id: "wren",  name: "Wren Sadiq",     email: "wren@example.org",  colour: "#ff9e64" }
    ]

    function ids(list) {
        return list.map(c => c.id).join(",");
    }

    // --- folding --------------------------------------------------------------

    function test_folding_removes_case_and_accents() {
        compare(guests.fold("José"), "jose");
        compare(guests.fold("MIRA"), "mira");
        compare(guests.fold("Ångström"), "angstrom");
        compare(guests.fold("Łukasz"), "lukasz");
        compare(guests.fold("Straße"), "strasse");
        compare(guests.fold("Æon"), "aeon");
    }

    function test_folding_handles_the_letters_nfd_leaves_alone() {
        // ø is not o plus a mark, so NFD alone would leave it — the table must.
        compare(guests.fold("Halvørsen"), "halvorsen");
        compare(guests.fold("Đorđe"), "dorde");
    }

    function test_folding_survives_junk() {
        compare(guests.fold(""), "");
        compare(guests.fold(null), "");
        compare(guests.fold(17), "");
        compare(guests.fold(undefined), "");
    }

    function test_folding_leaves_non_latin_alone() {
        compare(guests.fold("李雷"), "李雷");
    }

    // --- ranking --------------------------------------------------------------

    function test_a_whole_name_prefix_outranks_a_word_prefix() {
        const mira = { id: "a", name: "Mira Okonkwo", email: "mira@example.org" };
        const tamir = { id: "b", name: "Ines Tamira", email: "ines@example.org" };
        compare(guests.rank(mira, "mir"), 3);
        compare(guests.rank(tamir, "tamir"), 2);
    }

    function test_a_word_prefix_outranks_a_substring() {
        const okonkwo = { id: "a", name: "Mira Okonkwo", email: "mira@example.org" };
        const casimir = { id: "b", name: "Casimir Vale", email: "cas@example.org" };
        compare(guests.rank(okonkwo, "okon"), 2);
        compare(guests.rank(casimir, "mir"), 1);
    }

    function test_an_address_prefix_ranks_like_a_word_prefix() {
        const c = { id: "a", name: "Mira Okonkwo", email: "mo@example.org" };
        compare(guests.rank(c, "mo@"), 2);
        compare(guests.rank(c, "example"), 1);
    }

    function test_no_match_is_zero_and_an_empty_query_matches_everything() {
        const c = { id: "a", name: "Mira Okonkwo", email: "mira@example.org" };
        compare(guests.rank(c, "zzz"), 0);
        compare(guests.rank(c, ""), 1);
        compare(guests.rank(null, "mira"), 0);
    }

    function test_a_hyphenated_or_apostrophed_name_is_reachable_by_either_part() {
        const c = { id: "a", name: "Ana-María O'Brien", email: "ana@example.org" };
        compare(guests.rank(c, "maria"), 2);
        compare(guests.rank(c, "brien"), 2);
    }

    // --- search ---------------------------------------------------------------

    function test_search_puts_the_prefix_match_first() {
        compare(ids(guests.search(contacts, "mira", [])), "mira");
        compare(ids(guests.search(contacts, "ru", [])), "rune");
    }

    function test_search_ranks_prefixes_above_substrings() {
        // "a" starts Alvarez and Ada-less nobody; it appears inside many names.
        const list = guests.search(contacts, "al", []);
        compare(list[0].id, "juno");   // Alvarez, a word prefix
        verify(list.length > 1);       // Opal, Delacroix — substrings, below it
    }

    function test_search_folds_the_query_and_the_contacts() {
        const accented = [{ id: "jose", name: "José Márquez", email: "jose@example.org" }];
        compare(ids(guests.search(accented, "jose", [])), "jose");
        compare(ids(guests.search(accented, "JOSÉ", [])), "jose");
        compare(ids(guests.search(accented, "marq", [])), "jose");
    }

    function test_search_with_an_empty_query_returns_everyone_it_can_show() {
        const all = guests.search(contacts, "", []);
        compare(all.length, 8);
        compare(all[0].id, "mira");   // fixture order, untouched
    }

    function test_search_caps_at_eight() {
        const many = [];
        for (let i = 0; i < 20; i++)
            many.push({ id: "c" + i, name: "Person " + i, email: "p" + i + "@example.org" });
        compare(guests.search(many, "", []).length, 8);
        compare(guests.search(many, "person", []).length, 8);
    }

    function test_search_drops_the_already_invited() {
        const list = guests.search(contacts, "", ["mira", "juno"]);
        compare(list.length, 6);
        compare(list[0].id, "tabby");
        compare(ids(guests.search(contacts, "mira", ["mira"])), "");
    }

    function test_search_is_stable_across_repeats() {
        const first = ids(guests.search(contacts, "a", []));
        for (let i = 0; i < 5; i++)
            compare(ids(guests.search(contacts, "a", [])), first);
    }

    function test_search_survives_junk() {
        compare(guests.search(null, "mira", []).length, 0);
        compare(guests.search(contacts, "mira", null).length, 1);
        compare(guests.search([null, 3, { name: "no id" }], "", []).length, 0);
    }

    function test_search_takes_the_exclude_list_as_optional() {
        compare(guests.search(contacts, "mira").length, 1);
    }

    // --- initials -------------------------------------------------------------

    function test_two_words_give_two_glyphs() {
        compare(guests.initials("Mira Okonkwo"), "MO");
        compare(guests.initials("Rune Halvorsen"), "RH");
    }

    function test_one_word_gives_one_glyph() {
        compare(guests.initials("Prince"), "P");
        compare(guests.initials("prince"), "P");
    }

    function test_three_words_take_the_first_and_the_last() {
        compare(guests.initials("Ada Byron Lovelace"), "AL");
        compare(guests.initials("Jan van der Berg"), "JB");
    }

    function test_a_non_latin_name_keeps_its_own_glyph() {
        compare(guests.initials("李雷"), "李");
        compare(guests.initials("李 雷"), "李雷");
    }

    function test_initials_keep_the_accent_because_they_are_displayed() {
        compare(guests.initials("Émile Zola"), "ÉZ");
    }

    function test_initials_survive_junk() {
        compare(guests.initials(""), "");
        compare(guests.initials("   "), "");
        compare(guests.initials(null), "");
        compare(guests.initials("someone@example.org"), "S");
    }

    // --- colour ---------------------------------------------------------------

    function test_a_colour_is_a_palette_hue_and_never_changes() {
        const first = guests.colourFor("mira", guests.palette);
        verify(guests.palette.indexOf(first) >= 0);
        for (let i = 0; i < 5; i++)
            compare(guests.colourFor("mira", guests.palette), first);
    }

    function test_different_keys_spread_across_the_palette() {
        const seen = {};
        for (let i = 0; i < contacts.length; i++)
            seen[guests.colourFor(contacts[i].id, guests.palette)] = true;
        verify(Object.keys(seen).length >= 4);   // a hash that collides eight ways is broken
    }

    function test_colour_falls_back_to_the_default_palette() {
        compare(guests.colourFor("mira", null), guests.colourFor("mira", guests.palette));
        compare(guests.colourFor("mira", []), guests.colourFor("mira", guests.palette));
        compare(guests.colourFor("", guests.palette), guests.palette[0]);
        compare(guests.colourFor(null, guests.palette), guests.palette[0]);
    }

    function test_colour_honours_a_custom_palette() {
        const two = ["ink", "moss"];
        verify(two.indexOf(guests.colourFor("mira", two)) >= 0);
    }

    // --- dedupe ---------------------------------------------------------------

    function test_dedupe_keeps_the_first_mention() {
        compare(guests.dedupe(["mira", "juno", "mira"]).join(","), "mira,juno");
        compare(guests.dedupe([]).length, 0);
    }

    function test_dedupe_drops_the_junk() {
        compare(guests.dedupe(["mira", "", null, 3, "mira"]).join(","), "mira");
        compare(guests.dedupe(null).length, 0);
    }

    // --- displayList ----------------------------------------------------------

    function test_a_known_guest_carries_its_contact_record() {
        const list = guests.displayList(["mira"], contacts, guests.palette);
        compare(list.length, 1);
        compare(list[0].id, "mira");
        compare(list[0].name, "Mira Okonkwo");
        compare(list[0].email, "mira@example.org");
        compare(list[0].initials, "MO");
        compare(list[0].colour, "#7aa2f7");   // the record's own colour wins
        verify(list[0].known);
    }

    function test_an_unknown_id_renders_as_itself() {
        const list = guests.displayList(["ghost"], contacts, guests.palette);
        compare(list.length, 1);
        compare(list[0].name, "ghost");
        compare(list[0].email, "");
        compare(list[0].initials, "G");
        verify(guests.palette.indexOf(list[0].colour) >= 0);
        verify(!list[0].known);
    }

    function test_display_list_dedupes_and_holds_its_order() {
        const list = guests.displayList(["juno", "mira", "juno"], contacts, guests.palette);
        compare(list.length, 2);
        compare(list[0].id, "juno");
        compare(list[1].id, "mira");
    }

    function test_display_list_survives_junk() {
        compare(guests.displayList(null, contacts, guests.palette).length, 0);
        compare(guests.displayList(["mira"], null, guests.palette)[0].name, "mira");
    }

    // --- free text ------------------------------------------------------------

    function test_an_unknown_address_becomes_a_guest() {
        const c = guests.parseFreeText("someone@x.com", contacts);
        verify(c !== null);
        compare(c.id, "someone@x.com");
        compare(c.name, "someone@x.com");
        compare(c.email, "someone@x.com");
        verify(c.synthetic);
        verify(guests.palette.indexOf(c.colour) >= 0);
    }

    function test_a_known_address_does_not_become_a_second_guest() {
        compare(guests.parseFreeText("mira@example.org", contacts), null);
        compare(guests.parseFreeText("MIRA@Example.org", contacts), null);
    }

    function test_only_an_address_becomes_a_guest() {
        compare(guests.parseFreeText("mira", contacts), null);
        compare(guests.parseFreeText("mira@", contacts), null);
        compare(guests.parseFreeText("@example.org", contacts), null);
        compare(guests.parseFreeText("mira@example", contacts), null);
        compare(guests.parseFreeText("two words@example.org", contacts), null);
        compare(guests.parseFreeText("", contacts), null);
        compare(guests.parseFreeText(null, contacts), null);
    }

    function test_an_address_is_trimmed_and_folded_into_one_id() {
        const a = guests.parseFreeText("  Someone@X.com  ", contacts);
        const b = guests.parseFreeText("someone@x.com", contacts);
        compare(a.id, b.id);
        compare(a.name, "Someone@X.com");   // shown as typed
    }

    function test_a_free_text_guest_renders_from_its_id_alone() {
        const c = guests.parseFreeText("someone@x.com", contacts);
        const list = guests.displayList([c.id], contacts, guests.palette);
        compare(list[0].name, "someone@x.com");
        compare(list[0].initials, "S");
    }

    // --- adversarial ----------------------------------------------------------
    //
    // The cases above check each function against its own claim. These check the
    // claims against each other: that the *ranking* really outranks the list
    // order rather than merely reordering neighbours, that the cap counts what a
    // person can actually pick, that folding is one rule applied everywhere
    // rather than three, and that a field a person types into tolerates what
    // typing and pasting actually produce.

    function test_a_query_with_stray_whitespace_still_finds_the_name() {
        // A pasted address or a name typed after a space is the same query. A
        // picker that goes empty on a leading space reads as a broken search.
        const mira = { id: "mira", name: "Mira Okonkwo", email: "mira@example.org" };
        compare(guests.rank(mira, "mira "), 3);
        compare(guests.rank(mira, " mira"), 3);
        compare(ids(guests.search(contacts, "  mira  ", [])), "mira");
        compare(guests.search(contacts, "   ", []).length, 8);   // blank is empty
    }

    function test_a_later_whole_name_prefix_beats_an_earlier_word_prefix() {
        // Opal is fifth; Okonkwo and Odili are words of names above it. Rank has
        // to win, or the tiers are decoration on the fixture's own order.
        const list = guests.search(contacts, "o", []);
        compare(list[0].id, "opal");
        compare(ids(list), "opal,mira,birch,juno,tabby,rune,cass,wren");
    }

    function test_the_cap_counts_what_is_left_after_the_exclusions() {
        // Eight is how many a person can pick from, not how many matched.
        const many = [];
        for (let i = 0; i < 20; i++)
            many.push({ id: "c" + i, name: "Person " + i, email: "p" + i + "@example.org" });
        const list = guests.search(many, "person", ["c0", "c1"]);
        compare(list.length, 8);
        compare(list[0].id, "c2");
        compare(ids(list).indexOf("c0"), -1);
    }

    function test_a_glyph_outside_the_basic_plane_survives_whole() {
        // Half a surrogate pair is a replacement box in an avatar.
        const g = guests.firstGlyph("𝔄da");
        compare(g.length, 2);
        compare(guests.initials("𝔄da Lovelace"), g + "L");
    }

    function test_a_colour_key_is_folded_like_every_other_comparison() {
        // The same person keyed from an id, a display name or a pasted address
        // must land on one hue, or an avatar changes colour as text is retyped.
        for (let i = 0; i < contacts.length; i++)
            compare(guests.colourFor(contacts[i].id.toUpperCase(), guests.palette),
                    guests.colourFor(contacts[i].id, guests.palette));
        compare(guests.colourFor("José", guests.palette), guests.colourFor("jose", guests.palette));
    }

    function test_display_list_holds_its_order_when_a_guest_is_unknown() {
        const list = guests.displayList(["ghost", "mira", "ghost", ""], contacts, guests.palette);
        compare(list.length, 2);
        compare(list[0].id, "ghost");
        verify(!list[0].known);
        compare(list[1].name, "Mira Okonkwo");
        verify(list[1].known);
    }

    function test_an_address_already_known_in_another_spelling_is_not_minted() {
        const accented = [{ id: "jose", name: "José Márquez", email: "José@Example.ORG" }];
        compare(guests.parseFreeText("jose@example.org", accented), null);
        verify(guests.parseFreeText("jose@example.com", accented) !== null);
    }
}
