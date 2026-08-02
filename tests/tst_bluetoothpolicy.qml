// What the bluetooth indicator decides (#36) — three states and a count, which
// is the whole of what the bar shows — and what the drill-in's device list
// decides (#45): the order, what a press means, and the words on each row.
//
// Pairing a real device needs a real radio and a real device to pair with, so
// that half is a manual pass. Everything decided before the radio is touched is
// here.
import QtQuick
import QtTest
import "../Services/Networking"

TestCase {
    name: "BluetoothPolicy"

    BluetoothPolicy { id: policy }

    function device(address, extra) {
        const row = { address: address, name: "", connected: false,
                      paired: false, pairing: false, bonded: false };
        for (const key in extra ?? ({}))
            row[key] = extra[key];
        return row;
    }

    function names(rows) {
        return rows.map(row => row.name);
    }

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

    // --- the drill-in's list (#45) -------------------------------------------

    function test_connected_first_then_pairing_then_paired_then_the_rest() {
        const rows = policy.deviceRows([
            device("00:04", { name: "unknown speaker" }),
            device("00:03", { name: "keyboard", paired: true }),
            device("00:02", { name: "headset", pairing: true }),
            device("00:01", { name: "mouse", connected: true })
        ]);
        compare(names(rows), ["mouse", "headset", "keyboard", "unknown speaker"]);
    }

    function test_the_order_is_alphabetical_within_a_band_regardless_of_case() {
        const rows = policy.deviceRows([
            device("00:01", { name: "Zen mouse", paired: true }),
            device("00:02", { name: "airpods", paired: true }),
            device("00:03", { name: "Keyboard", paired: true })
        ]);
        compare(names(rows), ["airpods", "Keyboard", "Zen mouse"]);
    }

    function test_a_bonded_device_counts_as_paired() {
        // BlueZ reports both, and a device that is bonded but not "paired" is
        // one this list would otherwise offer to pair again.
        compare(policy.deviceRows([device("00:01", { bonded: true })])[0].paired, true);
    }

    function test_a_nameless_device_is_still_a_row_under_its_address() {
        // A discovery view that hides what the scan found is shorter than what
        // is on the air. The address is what the user matches against the label
        // on the back of the thing they are holding.
        const rows = policy.deviceRows([device("A0:B1:C2:D3:E4:F5")]);
        compare(rows.length, 1);
        compare(rows[0].name, "A0:B1:C2:D3:E4:F5");
    }

    function test_a_device_bluez_has_not_filled_in_yet_is_not_a_row() {
        compare(policy.deviceRows([device(""), device("  "), device("00:01")]).length, 1);
    }

    function test_the_live_handle_travels_with_the_row_untouched() {
        const handle = { marker: 7 };
        compare(policy.deviceRows([{ address: "00:01", live: handle }])[0].live.marker, 7);
    }

    // --- #75: the signature --------------------------------------------------

    function test_a_drifting_battery_does_not_change_the_signature() {
        // The same rule the wifi list follows: a live measurement must not
        // rebuild a delegate, or the row loses its hover every few seconds.
        const before = policy.deviceRows([
            device("00:01", { connected: true, batteryAvailable: true, battery: 81 })]);
        const after = policy.deviceRows([
            device("00:01", { connected: true, batteryAvailable: true, battery: 80 })]);
        compare(policy.deviceSignature(before), policy.deviceSignature(after));
    }

    function test_a_device_connecting_does_change_the_signature() {
        const before = policy.deviceRows([device("00:01", { paired: true })]);
        const after = policy.deviceRows([device("00:01", { paired: true, connected: true })]);
        verify(policy.deviceSignature(before) !== policy.deviceSignature(after));
    }

    function test_a_device_appearing_in_a_scan_changes_the_signature() {
        const before = policy.deviceRows([device("00:01")]);
        const after = policy.deviceRows([device("00:01"), device("00:02")]);
        verify(policy.deviceSignature(before) !== policy.deviceSignature(after));
    }

    // --- what a press means --------------------------------------------------

    function test_an_unpaired_device_pairs() {
        // Pairing and connecting are one gesture: nobody who presses an
        // unpaired headset wants to be paired to it and then press it again.
        compare(policy.deviceAction(device("00:01")), "pair");
    }

    function test_a_paired_device_connects_and_a_connected_one_disconnects() {
        compare(policy.deviceAction(device("00:01", { paired: true })), "connect");
        compare(policy.deviceAction(device("00:01", { paired: true, connected: true })),
                "disconnect");
    }

    function test_a_pairing_in_flight_cancels() {
        compare(policy.deviceAction(device("00:01", { pairing: true })), "cancel");
    }

    // --- the words -----------------------------------------------------------

    function test_the_detail_line_names_the_state() {
        compare(policy.deviceDetail(device("00:01", { pairing: true })), "Pairing…");
        compare(policy.deviceDetail(device("00:01", { connected: true })), "Connected");
        compare(policy.deviceDetail(device("00:01", { paired: true })), "Paired");
        compare(policy.deviceDetail(device("00:01")), "Not paired");
    }

    function test_a_battery_shows_only_when_bluez_reports_one() {
        // A headset that does not publish its level must not read as flat.
        compare(policy.deviceDetail(device("00:01",
            { connected: true, batteryAvailable: true, battery: 80 })), "Connected · 80%");
        compare(policy.deviceDetail(device("00:01",
            { connected: true, batteryAvailable: false, battery: 0 })), "Connected");
    }

    function test_the_glyph_follows_the_bluez_device_class() {
        compare(policy.deviceIcon("audio-headset"), "headphones");
        compare(policy.deviceIcon("input-mouse"), "mouse");
        compare(policy.deviceIcon("phone"), "smartphone");
    }

    function test_a_device_class_bluez_does_not_name_still_gets_a_glyph() {
        // A row with a hole where an icon goes reads as broken rather than as
        // unrecognised.
        compare(policy.deviceIcon("something-new"), "bluetooth");
        compare(policy.deviceIcon(""), "bluetooth");
        compare(policy.deviceIcon(null), "bluetooth");
    }
}
