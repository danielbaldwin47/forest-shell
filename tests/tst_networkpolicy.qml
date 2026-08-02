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
        compare(policy.icon(true, wifi(true, 5), "wifi"), "wifi-zero");
        compare(policy.icon(true, wifi(true, 95), "wifi-zero"), "wifi");
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

    function test_emphasis_is_a_word_rather_than_a_colour() {
        // The policy has no Theme to ask — it names the state and the module
        // maps it to a role, which is also what keeps the three indicators in
        // the cluster tinted by the same rule.
        compare(policy.emphasis(false, wifi(false, 0)), "off");
        compare(policy.emphasis(true, wifi(false, 0)), "idle");
        compare(policy.emphasis(true, wifi(true, 50)), "connected");
        compare(policy.emphasis(true, wired(true)), "connected");
    }

    function test_the_label_names_the_network_it_is_on() {
        compare(policy.label(true, wifi(true, 50)), "moss");
        compare(policy.label(true, wifi(false, 0)), "Not connected");
        compare(policy.label(false, null), "Wi-Fi off");
        compare(policy.label(true, null), "No network");
    }
}
