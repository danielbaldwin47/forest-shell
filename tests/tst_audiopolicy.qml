// What the volume and mic indicators decide (#36): a level is turned into one
// of four glyphs, and a set is clamped before it reaches PipeWire.
//
// The service next door is wiring; everything here is a decision, so it is
// checkable without a sound server.
import QtQuick
import QtTest
import "../Services/Media"

TestCase {
    name: "AudioPolicy"

    AudioPolicy { id: policy }

    function test_a_volume_reads_as_a_whole_percent() {
        compare(policy.percent(0), 0);
        compare(policy.percent(1), 100);
        compare(policy.percent(0.4004058837890625), 40);   // measured, this laptop
        compare(policy.percent(0.005), 1);                 // rounds away from silence
    }

    function test_a_percent_never_reports_a_volume_the_shell_would_refuse() {
        // Overamplification is not offered (PipeWire allows > 1.0), so the
        // readout has to agree with the setter about the ceiling.
        compare(policy.percent(1.5), 100);
        compare(policy.percent(-0.2), 0);
        compare(policy.percent(NaN), 0);
    }

    function test_a_set_is_clamped_into_the_range_the_shell_offers() {
        compare(policy.clamp(0.5), 0.5);
        compare(policy.clamp(1.4), 1);
        compare(policy.clamp(-1), 0);
        compare(policy.clamp(NaN), 0);
    }

    function test_a_step_lands_on_the_step_grid() {
        // Whatever the level was, a step up puts it on a multiple of the step:
        // otherwise a volume nudged from 0.43 spends the rest of the session
        // three percent off every round number.
        compare(policy.stepped(0.43, 1), 0.45);
        compare(policy.stepped(0.45, 1), 0.50);
        compare(policy.stepped(0.45, -1), 0.40);
        compare(policy.stepped(0.02, -1), 0);
        compare(policy.stepped(1, 1), 1);
    }

    function test_the_sink_glyph_follows_the_level() {
        compare(policy.sinkIcon(0.8, false), "volume-2");
        compare(policy.sinkIcon(0.3, false), "volume-1");
        compare(policy.sinkIcon(0, false), "volume");
    }

    function test_a_muted_sink_says_muted_at_any_level() {
        // The level is still there underneath — a mute that looked like a level
        // change would be a mute nobody can find their way back from.
        compare(policy.sinkIcon(0.8, true), "volume-x");
        compare(policy.sinkIcon(0, true), "volume-x");
    }

    function test_the_mic_is_only_on_the_bar_when_it_is_muted() {
        // The cluster is quiet by default (#9): a live mic is the normal state
        // and says nothing, a muted one is the surprise worth a glyph.
        verify(policy.showSource(true));
        verify(!policy.showSource(false));
        compare(policy.sourceIcon(true), "mic-off");
        compare(policy.sourceIcon(false), "mic");
    }

    // --- the drill-in's two lists (#45) --------------------------------------
    //
    // The output picker and the per-application mixer. Switching a real device
    // and hearing it move needs a real sound card and is a manual pass; every
    // decision made before PipeWire is touched is here.

    function sink(id, extra) {
        const node = { id: id, description: "", nickname: "", name: "",
                       isDefault: false };
        for (const key in extra ?? ({}))
            node[key] = extra[key];
        return node;
    }

    function stream(id, appName, extra) {
        const node = { id: id, description: "", name: "",
                       properties: { "application.name": appName } };
        for (const key in extra ?? ({}))
            node[key] = extra[key];
        return node;
    }

    function names(rows) {
        return rows.map(row => row.name);
    }

    function test_the_current_output_is_pinned_to_the_top() {
        // It is the answer to the question the picker was opened with — "what
        // am I playing through" — and a checked row six rows down answers it
        // slowly.
        const rows = policy.sinks([
            sink("1", { description: "Analogue" }),
            sink("2", { description: "HDMI" }),
            sink("3", { description: "USB headset", isDefault: true })
        ]);
        compare(names(rows), ["USB headset", "Analogue", "HDMI"]);
    }

    function test_the_rest_of_the_outputs_are_alphabetical_regardless_of_case() {
        const rows = policy.sinks([
            sink("1", { description: "hdmi" }),
            sink("2", { description: "Analogue" })
        ]);
        compare(names(rows), ["Analogue", "hdmi"]);
    }

    function test_an_output_is_named_by_the_words_a_person_would_recognise() {
        // `description` is the human one, `nickname` is shorter when it exists,
        // and the machine name is the last resort rather than the first.
        compare(policy.deviceName({ description: "Built-in Audio", nickname: "Speakers",
                                    name: "alsa_output.pci-0000_00_1f.3" }),
                "Built-in Audio");
        compare(policy.deviceName({ nickname: "Speakers",
                                    name: "alsa_output.pci-0000_00_1f.3" }),
                "Speakers");
        compare(policy.deviceName({ name: "alsa_output.pci-0000_00_1f.3" }),
                "alsa_output.pci-0000_00_1f.3");
        compare(policy.deviceName({}), "Unknown device");
        compare(policy.deviceName(null), "Unknown device");
    }

    function test_a_node_pipewire_has_not_filled_in_yet_is_not_a_row() {
        compare(policy.sinks([sink(""), sink("4")]).length, 1);
        compare(policy.streams([stream("", "x"), stream("4", "y")]).length, 1);
    }

    function test_the_mixer_is_alphabetical_by_application() {
        const rows = policy.streams([
            stream("3", "mpv"), stream("1", "Firefox"), stream("2", "Discord")
        ]);
        compare(names(rows), ["Discord", "Firefox", "mpv"]);
    }

    function test_two_streams_from_one_application_are_two_rows() {
        // Firefox playing two tabs is two streams to PipeWire and two volumes
        // to set. Merging them gives a slider that moves one of the two.
        const rows = policy.streams([
            stream("9", "Firefox", { properties: { "application.name": "Firefox",
                                                   "media.name": "Tab two" } }),
            stream("4", "Firefox", { properties: { "application.name": "Firefox",
                                                   "media.name": "Tab one" } })
        ]);
        compare(rows.length, 2);
        // PipeWire's own order within an application, which is the order they
        // started in and the only thing left that tells them apart.
        compare(rows.map(row => row.id), ["4", "9"]);
    }

    function test_a_stream_is_named_by_its_application_first() {
        compare(policy.streamName(stream("1", "Firefox")), "Firefox");
        compare(policy.streamName({ id: "1", description: "playback" }), "playback");
        compare(policy.streamName({ id: "1" }), "Unknown application");
    }

    function test_the_subtitle_is_what_is_playing_when_it_says_anything_new() {
        // "Firefox · Firefox" is a row that spent a line saying nothing.
        compare(policy.streamSubtitle({ properties: { "application.name": "mpv",
                                                      "media.name": "track.flac" } }),
                "track.flac");
        compare(policy.streamSubtitle({ properties: { "application.name": "Firefox",
                                                      "media.name": "firefox" } }),
                "");
        compare(policy.streamSubtitle({ properties: {} }), "");
    }

    function test_a_stream_falls_back_to_the_shells_own_glyph() {
        compare(policy.streamIcon({ properties: { "application.icon_name": "firefox" } }),
                "firefox");
        compare(policy.streamIcon({ properties: {} }), "volume-2");
    }

    // --- #75: the signatures -------------------------------------------------

    function test_a_moving_volume_does_not_change_either_signature() {
        // The sharpest case in the shell: a volume moves *while the user is
        // dragging the row it would rebuild*, and a rebuilt delegate is a
        // slider that loses the drag moving it.
        const quiet = policy.sinks([sink("1", { description: "Analogue", volume: 0.2 })]);
        const loud = policy.sinks([sink("1", { description: "Analogue", volume: 0.9 })]);
        compare(policy.sinkSignature(quiet), policy.sinkSignature(loud));

        const before = policy.streams([stream("1", "mpv", { volume: 0.2 })]);
        const after = policy.streams([stream("1", "mpv", { volume: 0.9 })]);
        compare(policy.streamSignature(before), policy.streamSignature(after));
    }

    function test_the_default_output_moving_does_change_the_signature() {
        // It reorders the list and moves the tick, which is structural.
        const before = policy.sinks([sink("1", { description: "A" }),
                                     sink("2", { description: "B", isDefault: true })]);
        const after = policy.sinks([sink("1", { description: "A", isDefault: true }),
                                    sink("2", { description: "B" })]);
        verify(policy.sinkSignature(before) !== policy.sinkSignature(after));
    }

    function test_an_application_starting_playback_changes_the_signature() {
        const before = policy.streams([stream("1", "mpv")]);
        const after = policy.streams([stream("1", "mpv"), stream("2", "Firefox")]);
        verify(policy.streamSignature(before) !== policy.streamSignature(after));
    }
}
