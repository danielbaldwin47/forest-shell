// What the network indicator decides (#36): which device the cluster speaks
// for, and which glyph says so.
//
// The devices are passed in as plain data, so this file never meets
// NetworkManager — which is the point: "wired beats wifi" and "two bars" are
// decisions, and decisions live where tests can reach them.
import QtQuick
import QtTest
import "../Services/Networking"

TestCase {
    name: "NetworkPolicy"

    NetworkPolicy { id: policy }

    function wifi(connected, strength) {
        return { kind: "wifi", connected: connected, name: "moss", strength: strength };
    }

    function wired(connected) {
        return { kind: "wired", connected: connected, name: "enp0s31f6", strength: 100 };
    }

    function test_signal_strength_is_a_percent_whichever_scale_it_arrives_in() {
        // NetworkManager reports 0-100 and the binding types it as a double, so
        // a fraction is the plausible other reading. Both normalize here rather
        // than at four call sites that would have to agree.
        compare(policy.strength(72), 72);
        compare(policy.strength(0.72), 72);
        compare(policy.strength(1), 100);
        compare(policy.strength(0), 0);
        compare(policy.strength(140), 100);
        compare(policy.strength(-3), 0);
        compare(policy.strength(NaN), 0);
    }

    function test_a_connected_wire_speaks_for_the_machine() {
        // Wired is the honest answer when both are up: it is the one carrying
        // the traffic, and a wifi glyph over a docked laptop is a lie.
        const device = policy.primary([wifi(true, 80), wired(true)]);
        compare(device.kind, "wired");
    }

    function test_an_unplugged_wire_does_not_speak_over_live_wifi() {
        const device = policy.primary([wired(false), wifi(true, 80)]);
        compare(device.kind, "wifi");
    }

    function test_with_nothing_connected_the_wifi_radio_still_speaks() {
        // Something has to be on the bar, and "wifi, not connected" is more
        // useful than an empty slot — the alternative reads as a bar that lost
        // a module.
        const device = policy.primary([wired(false), wifi(false, 0)]);
        compare(device.kind, "wifi");
        compare(device.connected, false);
    }

    function test_a_machine_with_no_network_device_at_all_answers_null() {
        compare(policy.primary([]), null);
        compare(policy.primary(null), null);
    }

    function test_the_glyph_follows_the_bars() {
        compare(policy.icon(true, wifi(true, 90)), "wifi");
        compare(policy.icon(true, wifi(true, 60)), "wifi-high");
        compare(policy.icon(true, wifi(true, 30)), "wifi-low");
        compare(policy.icon(true, wifi(true, 5)), "wifi-zero");
    }

    function test_the_glyph_holds_still_while_the_signal_wanders() {
        // The idle-budget bug (#22 §5, measured with tools/idle-budget.sh): an
        // access point at 0.72-0.78 — an ordinary desk — sat astride the 75
        // threshold and flipped the glyph every few seconds all day, one bar
        // repaint each time. Staying put is the whole feature.
        compare(policy.icon(true, wifi(true, 78), "wifi"), "wifi");
        compare(policy.icon(true, wifi(true, 72), "wifi"), "wifi");
        compare(policy.icon(true, wifi(true, 68), "wifi"), "wifi");
        // Past the deadband, it does move — a signal that really has fallen
        // must still be readable as one.
        compare(policy.icon(true, wifi(true, 66), "wifi"), "wifi-high");
    }

    function test_climbing_back_takes_the_same_margin() {
        // Symmetrical, or the deadband would only be a delay: 75 alone would
        // put it straight back and the flapping would resume one notch down.
        compare(policy.icon(true, wifi(true, 76), "wifi-high"), "wifi-high");
        compare(policy.icon(true, wifi(true, 83), "wifi-high"), "wifi");
    }

    function test_a_reading_with_no_history_takes_the_plain_answer() {
        // Startup, and any glyph that is not one of the four bars — the wired
        // one, the radio being off — has no bucket to hold on to.
        compare(policy.icon(true, wifi(true, 74), ""), "wifi-high");
        compare(policy.icon(true, wifi(true, 74), "wifi-off"), "wifi-high");
        compare(policy.icon(true, wifi(true, 74), "ethernet-port"), "wifi-high");
    }

    function test_a_signal_that_collapses_skips_the_buckets_between() {
        // Walking out of range is not a boundary wobble: three buckets in one
        // step is a real change, and the deadband must not hold the glyph at
        // full bars because the drop was too large to be a nudge.
        //
        // The middle two are the ones that caught the first version, which
        // measured the deadband from the bucket being *arrived at* rather than
        // the one being left: a 20% signal then drew full bars, and needed to
        // fall below 17 before the glyph would admit anything had happened.
        compare(policy.icon(true, wifi(true, 40), "wifi"), "wifi-low");
        compare(policy.icon(true, wifi(true, 20), "wifi"), "wifi-zero");
        compare(policy.icon(true, wifi(true, 5), "wifi"), "wifi-zero");
        compare(policy.icon(true, wifi(true, 95), "wifi-zero"), "wifi");
        compare(policy.icon(true, wifi(true, 60), "wifi-zero"), "wifi-high");
    }

    // --- the reading the deadband is taken on (#137) -------------------------
    //
    // The deadband above holds a glyph against a signal that *wanders* past a
    // threshold; it does nothing about one that jumps clean over it, which is
    // what this laptop's radio does. The measurement, and why the answer is an
    // average, are in NetworkPolicy.qml's `barSmoothing`. What is pinned here
    // is both ends of it: a swing that must not move the glyph, and a move that
    // must.

    /// The sequence measured off the bar on an idle desk (#137), long enough to
    /// settle. Nothing in it is a real change: the mean sits around 70, which
    /// is `wifi-high`.
    readonly property var swinging: [63, 84, 63, 66, 67, 74, 84, 63, 79, 63, 84, 66]

    /// Winds a reading and its glyph forward over a run of samples, the way
    /// Services/Networking/Networking.qml's `refreshIcon` does.
    function wind(state, samples, ssid) {
        let carried = state ?? ({ reading: null, glyph: "" });
        for (const sample of samples) {
            const device = { kind: "wifi", connected: true,
                             name: ssid ?? "moss", strength: sample };
            const reading = policy.track(carried.reading, true, device);
            carried = { reading: reading,
                        glyph: policy.icon(true, device, carried.glyph, reading.strength) };
        }
        return carried;
    }

    function test_a_swinging_signal_never_moves_the_glyph() {
        compare(wind(null, swinging).glyph, "wifi-high");
    }

    function test_a_signal_that_really_climbed_still_gets_there() {
        // Smoothing is a delay, not a wall — a laptop carried towards the
        // access point must read as full bars soon after it settles, or the
        // glyph is decoration.
        //
        // Wound over the swinging sequence first, so the climb starts from a
        // settled average rather than from nothing: a reading with no history
        // takes its first sample whole, and a test that climbed from there
        // would pass with no smoothing at all.
        const settled = wind(null, swinging);
        compare(settled.glyph, "wifi-high");
        compare(wind(settled, [95, 95]).glyph, "wifi-high");   // still climbing
        compare(wind(settled, [95, 95, 95]).glyph, "wifi");    // three samples
    }

    function test_a_signal_that_really_fell_gets_there_too() {
        const settled = wind(null, [95, 95, 95, 95]);
        compare(settled.glyph, "wifi");
        // Walking out of range, one sample at a time. The average is what falls,
        // so the glyph steps down through the buckets rather than jumping — and
        // it arrives: full bars to none in eight samples.
        compare(wind(settled, [5, 5, 5, 5, 5, 5, 5, 5]).glyph, "wifi-zero");
    }

    function test_a_swing_whose_mean_really_is_higher_settles_there_once() {
        // The other half of the rule: an average that is genuinely in the next
        // bucket is not noise. A signal swinging 63-100 means 81, and the glyph
        // is supposed to move — once, and then hold, which is one repaint and
        // not a flip every few seconds. Half the samples being below the
        // deadband's lower gate must not drag it back.
        const swung = wind(null, [63, 100, 63, 100, 63, 100, 63, 100, 63, 100]);
        compare(swung.glyph, "wifi");
        compare(wind(swung, [63, 100, 63, 100]).glyph, "wifi");
    }

    function test_the_first_reading_on_a_network_is_taken_whole() {
        // Startup has no history to average against, and a bar that fades in
        // from zero bars over ten seconds is a bar that looks broken.
        const first = policy.track(null, true, wifi(true, 90));
        compare(first.strength, 90);
        compare(policy.icon(true, wifi(true, 90), "", first.strength), "wifi");
    }

    function test_a_reading_belongs_to_the_network_it_was_taken_on() {
        // Joining a weak access point from a strong one must not draw the
        // strong one's bars while the average catches up — and a switch between
        // two networks does not reliably show a disconnected sample in between,
        // so the name is what says the reading is stale, not the link state.
        const strong = wind(null, [95, 95, 95, 95], "moss");
        compare(strong.glyph, "wifi");
        const joined = policy.track(strong.reading,
                                    true, { kind: "wifi", connected: true,
                                            name: "pine", strength: 30 });
        compare(joined.network, "pine");
        compare(joined.strength, 30);
        compare(policy.icon(true, wifi(true, 30), strong.glyph, joined.strength), "wifi-low");
    }

    function test_the_reading_is_forgotten_when_there_is_nothing_to_read() {
        // A link that drops, a radio switched off, a wire: none of them has a
        // strength to average.
        const held = { network: "moss", strength: 70 };
        compare(policy.track(held, true, wifi(false, 0)).strength, 0);
        compare(policy.track(held, false, wifi(true, 90)).strength, 0);
        compare(policy.track(held, true, wired(true)).strength, 0);
        compare(policy.track(held, true, null).strength, 0);
        compare(policy.track(held, true, null).network, "");
    }

    function test_a_glyph_asked_without_a_reading_answers_on_the_sample() {
        // The reading is the caller's to carry, and a caller that has none —
        // the tests above, and anything asking a one-off question — still gets
        // the plain answer rather than no bars.
        compare(policy.icon(true, wifi(true, 90), ""), "wifi");
        compare(policy.icon(true, wifi(true, 30), "", 0), "wifi-low");
    }

    function test_a_connected_wire_has_its_own_glyph() {
        compare(policy.icon(true, wired(true)), "ethernet-port");
    }

    function test_the_radio_being_off_outranks_everything_else() {
        // Airplane mode is the one network state the user did on purpose, so it
        // is the one the glyph must not hide behind "no signal".
        compare(policy.icon(false, wifi(false, 0)), "wifi-off");
        compare(policy.icon(false, null), "wifi-off");
    }

    function test_wifi_that_is_on_but_unconnected_reads_as_no_bars() {
        compare(policy.icon(true, wifi(false, 0)), "wifi-zero");
        compare(policy.icon(true, null), "wifi-zero");
    }

    function test_the_label_names_the_network_it_is_on() {
        compare(policy.label(true, wifi(true, 50)), "moss");
        compare(policy.label(true, wifi(false, 0)), "Not connected");
        compare(policy.label(false, null), "Wi-Fi off");
        compare(policy.label(true, null), "No network");
    }
}
