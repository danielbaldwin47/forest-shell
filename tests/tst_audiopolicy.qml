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

    function test_the_readout_says_muted_rather_than_a_number() {
        compare(policy.readable(0.4, false), "40%");
        compare(policy.readable(0.4, true), "Muted");
    }
}
