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

    function test_a_stopped_player_is_not_playing_anything() {
        // The ticket's criterion, and the case that decides it: a browser that
        // has registered an MPRIS name and never played is *stopped*, and it
        // reports an identity and often a title. Reading only the label would
        // put a permanent "Firefox" on the bar of every machine with a browser
        // open — the furniture #9 keeps off it.
        const stopped = [
            { id: "a", playing: false, stopped: true,
              title: "", artist: "", identity: "Firefox" }
        ];
        compare(policy.pick(stopped, undefined), -1);
        compare(policy.pick(stopped, "a"), -1);
        verify(!policy.eligible(stopped[0]));

        // Paused is not stopped: it is the thing you were listening to, one
        // click from playing again.
        const paused = { id: "b", playing: false, stopped: false,
                         title: "Reckoner", artist: "", identity: "Spotify" };
        verify(policy.eligible(paused));
        compare(policy.pick([stopped[0], paused], undefined), 1);
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

    // --- the dashboard's card (#49) ------------------------------------------

    function test_a_position_reads_as_a_clock() {
        compare(policy.clock(0), "0:00");
        compare(policy.clock(7), "0:07");
        compare(policy.clock(67), "1:07");
        compare(policy.clock(599), "9:59");
        // Seconds are padded and minutes are not: `3:7` is not a time, and
        // `03:07` is not how a track length is written.
        compare(policy.clock(187), "3:07");
    }

    function test_an_hour_long_track_grows_a_third_field() {
        compare(policy.clock(3600), "1:00:00");
        compare(policy.clock(3671), "1:01:11");
        // A podcast, which is the case this exists for.
        compare(policy.clock(7384), "2:03:04");
    }

    function test_a_position_the_player_did_not_give_is_zero_and_not_blank() {
        // The label sits under the bar, so a disappearing one re-lays the card
        // out on every track change.
        compare(policy.clock(undefined), "0:00");
        compare(policy.clock(null), "0:00");
        compare(policy.clock(NaN), "0:00");
        compare(policy.clock(-12), "0:00");
        compare(policy.clock("not a number"), "0:00");
    }

    function test_a_fractional_second_is_not_shown_as_one() {
        // MPRIS counts in microseconds and upstream hands back a double, so a
        // position is almost never whole.
        compare(policy.clock(66.9), "1:06");
        compare(policy.clock(0.4), "0:00");
    }

    function test_the_progress_is_a_fraction_of_the_track() {
        compare(policy.progress(0, 200), 0);
        compare(policy.progress(50, 200), 0.25);
        compare(policy.progress(200, 200), 1);
    }

    function test_a_position_outside_the_track_does_not_draw_outside_the_bar() {
        // Both happen: a player reports past its own length on the last second
        // of a track, and negative between two of them.
        compare(policy.progress(260, 200), 1);
        compare(policy.progress(-4, 200), 0);
    }

    function test_a_track_with_no_length_has_no_progress() {
        // A live stream is not a fraction of anything, and neither is a
        // division by zero.
        compare(policy.progress(90, 0), 0);
        compare(policy.progress(90, undefined), 0);
        compare(policy.progress(undefined, 200), 0);
        compare(policy.progress(90, -1), 0);
    }

    function test_dragging_the_bar_needs_all_three_answers() {
        verify(policy.scrubbable(true, true, 200));
        verify(!policy.scrubbable(false, true, 200));   // the player refuses seeks
        verify(!policy.scrubbable(true, false, 200));   // it will not say where it is
        verify(!policy.scrubbable(true, true, 0));      // there is no end to seek within
    }

    function test_a_player_that_answers_nothing_is_not_scrubbable() {
        verify(!policy.scrubbable(undefined, undefined, undefined));
        verify(!policy.scrubbable(true, true, "unknown"));
    }

    function test_a_click_across_the_bar_lands_inside_the_track() {
        compare(policy.seekTarget(0, 200), 0);
        compare(policy.seekTarget(0.5, 200), 100);
        compare(policy.seekTarget(1, 200), 200);
        // A pointer dragged off either end of the bar it started in.
        compare(policy.seekTarget(-0.3, 200), 0);
        compare(policy.seekTarget(1.4, 200), 200);
    }

    function test_a_seek_target_is_rounded_to_something_a_player_can_act_on() {
        compare(policy.seekTarget(1 / 3, 200), 66.667);
        compare(policy.seekTarget(0.5, 0), 0);
        compare(policy.seekTarget(NaN, 200), 0);
    }
}
