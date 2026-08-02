// What the bluetooth indicator decides (#36). Three states and a count, which
// is the whole of what the bar shows — pairing, trust and per-device battery
// are the control centre's (#44), not the cluster's.
import QtQuick
import QtTest
import "../Services/Networking"

TestCase {
    name: "BluetoothPolicy"

    BluetoothPolicy { id: policy }

    function test_connected_devices_are_counted_from_plain_data() {
        compare(policy.connectedCount([]), 0);
        compare(policy.connectedCount(null), 0);
        compare(policy.connectedCount([{ connected: false }, { connected: true }]), 1);
        compare(policy.connectedCount([{ connected: true }, { connected: true }]), 2);
    }

    function test_the_glyph_says_off_connected_or_idle() {
        compare(policy.icon(false, 0), "bluetooth-off");
        compare(policy.icon(false, 2), "bluetooth-off");   // a radio that is off has nothing connected
        compare(policy.icon(true, 1), "bluetooth-connected");
        compare(policy.icon(true, 0), "bluetooth");
    }

    function test_a_scan_in_progress_is_visible_while_it_runs() {
        // The shell never starts a scan itself — the control centre will — but
        // blueman or bluetoothctl might, and a discovering adapter is doing
        // something worth showing.
        compare(policy.icon(true, 0, true), "bluetooth-searching");
        compare(policy.icon(true, 1, true), "bluetooth-connected");
        compare(policy.icon(false, 0, true), "bluetooth-off");
    }

    function test_emphasis_matches_the_other_indicators() {
        compare(policy.emphasis(false, 0), "off");
        compare(policy.emphasis(true, 0), "idle");
        compare(policy.emphasis(true, 1), "connected");
    }

    function test_the_label_counts_what_is_connected() {
        compare(policy.label(false, 0), "Bluetooth off");
        compare(policy.label(true, 0), "No devices");
        compare(policy.label(true, 1), "1 device");
        compare(policy.label(true, 3), "3 devices");
    }

    function test_no_adapter_is_not_the_same_as_an_adapter_that_is_off() {
        // A machine with no bluetooth hardware shows nothing at all, rather
        // than a permanently crossed-out glyph nobody can act on.
        verify(!policy.present(null));
        verify(policy.present({ enabled: false }));
    }
}
