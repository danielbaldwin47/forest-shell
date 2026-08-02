// The media pill's decisions (#37): what it says, and which of several players
// it is about.
import QtQuick
import QtTest
import "../Services/Media"

TestCase {
    name: "MprisPolicy"

    MprisPolicy { id: policy }

    function test_the_label_leads_with_the_track() {
        // Title first, because the pill elides from the right and the title is
        // what is being read at a glance.
        compare(policy.label("Reckoner", "Radiohead", "Spotify"), "Reckoner · Radiohead");
        compare(policy.label("Reckoner", "", "Spotify"), "Reckoner");
    }

    function test_a_player_with_no_track_says_who_it_is() {
        // A browser that has registered an MPRIS name and loaded nothing still
        // answers its own name, and that is honest — "Firefox" beats a blank
        // pill that looks broken.
        compare(policy.label("", "", "Firefox"), "Firefox");
        compare(policy.label("", "Radiohead", "Firefox"), "Firefox");
        compare(policy.label("", "", ""), "");
    }

    function test_tags_arrive_however_they_were_written() {
        // Titles come from whatever wrote the file's tags. A newline in a bar
        // label is a row that grows to two lines.
        compare(policy.label("  Reckoner\n", " Radiohead ", ""), "Reckoner · Radiohead");
        compare(policy.label(undefined, undefined, undefined), "");
    }

    function test_the_glyph_says_what_a_click_does() {
        // Not what is happening: the text beside it already says that, and a
        // play triangle next to an audibly playing track reads as broken.
        compare(policy.icon(true), "pause");
        compare(policy.icon(false), "play");
    }

    function test_the_pill_is_about_whatever_is_playing() {
        const players = [
            { id: "a", playing: false, title: "", artist: "", identity: "Firefox" },
            { id: "b", playing: true, title: "Reckoner", artist: "Radiohead", identity: "Spotify" }
        ];
        compare(policy.pick(players, undefined), 1);
    }

    function test_a_playing_pill_is_not_stolen() {
        // The failure this argument exists for: a second player waking up must
        // not take the pill from the one you are listening to.
        const players = [
            { id: "a", playing: true, title: "Podcast", artist: "", identity: "mpv" },
            { id: "b", playing: true, title: "Reckoner", artist: "Radiohead", identity: "Spotify" }
        ];
        compare(policy.pick(players, "b"), 1);
        compare(policy.pick(players, "a"), 0);
        // A previous id nothing answers to any more falls back to the first
        // playing player rather than to nothing.
        compare(policy.pick(players, "gone"), 0);
    }

    function test_pausing_does_not_move_the_pill() {
        // Pause and resume is one gesture on this module; a pill that jumped to
        // another player in between would resume the wrong thing.
        const players = [
            { id: "a", playing: false, title: "Podcast", artist: "", identity: "mpv" },
            { id: "b", playing: false, title: "Reckoner", artist: "Radiohead", identity: "Spotify" }
        ];
        compare(policy.pick(players, "b"), 1);
        // Nothing was showing and nothing is playing: the first player with
        // anything to say.
        compare(policy.pick(players, undefined), 0);
    }

    function test_a_player_with_nothing_to_say_is_not_the_pill() {
        const players = [
            { id: "a", playing: true, title: "", artist: "", identity: "" },
            { id: "b", playing: false, title: "Reckoner", artist: "", identity: "Spotify" }
        ];
        compare(policy.pick(players, undefined), 1);
        // Even while it is the one playing — an entry that answers nothing is
        // not something the bar can show.
        compare(policy.pick(players, "a"), 1);
    }

    function test_no_players_is_no_module() {
        compare(policy.pick([], undefined), -1);
        compare(policy.pick(null, undefined), -1);
        verify(!policy.showing(""));
        verify(!policy.showing("   "));
        verify(policy.showing("Reckoner"));
    }
}
