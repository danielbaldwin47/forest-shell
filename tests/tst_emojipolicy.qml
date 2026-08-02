// The emoji provider's decisions (#40) — the search over the bundled table, and
// the table's own invariants.
import QtQuick
import QtTest
import "../Services/Launcher"

TestCase {
    id: testCase
    name: "EmojiPolicy"

    EmojiPolicy { id: policy }
    EmojiTable { id: table }

    function charsOf(rows) {
        return rows.map(row => row.copy);
    }

    function firstChar(query) {
        const rows = policy.rows(query);
        return rows.length > 0 ? rows[0].copy : "";
    }

    // --- the table -----------------------------------------------------------

    function test_the_table_is_not_empty_and_every_entry_is_complete() {
        verify(table.emoji.length > 100);
        for (const entry of table.emoji) {
            verify(entry.char.length > 0);
            verify(entry.name.length > 0);
            verify(Array.isArray(entry.keywords));
        }
    }

    function test_no_two_entries_claim_the_same_glyph() {
        // A duplicate is invisible on screen — two rows, same picture — and it
        // makes the row id ambiguous, since the id is built from the character.
        const seen = ({});
        for (const entry of table.emoji) {
            verify(seen[entry.char] === undefined);
            seen[entry.char] = true;
        }
    }

    // --- searching -----------------------------------------------------------

    function test_a_name_match_wins() {
        compare(firstChar("rocket"), "🚀");
        compare(firstChar("thumbs up"), "👍");
    }

    function test_a_keyword_reaches_a_glyph_whose_name_you_do_not_know() {
        // Nobody searches for "face with tears of joy".
        compare(firstChar("lol"), "😂");
        compare(firstChar("shrug"), "🤷");
        compare(firstChar("tux"), "🐧");
    }

    function test_a_name_hit_outranks_a_keyword_hit() {
        // "fire" is the name of 🔥 and a keyword of 🦊 (firefox). The name wins,
        // which is the same weighting the apps provider gives a desktop entry.
        compare(firstChar("fire"), "🔥");
    }

    function test_an_empty_query_browses_rather_than_listing_everything() {
        const rows = policy.rows("");
        compare(rows.length, policy.browseLimit);
        verify(policy.browseLimit < table.emoji.length);
    }

    function test_a_query_that_matches_nothing_returns_nothing() {
        compare(policy.rows("zzzzqqq").length, 0);
    }

    function test_keywords_are_scored_one_at_a_time() {
        // Joined into one string, "sadcry" would match `["sad", "cry"]` across
        // the seam between two words — a match no one meant. 😢 carries both.
        compare(policy.rows("sadcry").length, 0);
    }

    // --- the rows ------------------------------------------------------------

    function test_a_row_carries_the_glyph_in_the_icon_slot_and_copies_only_it() {
        const row = policy.rows("rocket")[0];
        compare(row.provider, "emoji");
        compare(row.glyph, "🚀");
        compare(row.icon, "");
        compare(row.title, "rocket");
        compare(row.category, "Emoji");
        // No name, no codepoint — Enter here means "put this in the message I
        // am writing".
        compare(row.copy, "🚀");
        compare(row.run, null);
    }

    function test_row_ids_are_unique_across_a_result_set() {
        const seen = ({});
        for (const row of policy.rows("face")) {
            verify(seen[row.id] === undefined);
            seen[row.id] = true;
        }
    }

    // --- the silence ---------------------------------------------------------

    function test_only_a_failed_search_is_silent() {
        // No scan to be waiting on, so there is no state in which "nothing yet"
        // differs from "nothing matched" — unlike the apps provider.
        compare(policy.silence(""), null);
        verify(policy.silence("zzzzqqq").text.indexOf("zzzzqqq") >= 0);
    }

    function test_the_copy_log_names_the_glyph_and_the_name() {
        const line = policy.copied({ char: "🚀", name: "rocket" });
        verify(line.indexOf("🚀") >= 0);
        verify(line.indexOf("rocket") >= 0);
    }
}
