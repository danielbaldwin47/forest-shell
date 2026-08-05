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

    function test_a_scan_this_shell_is_holding_is_visible_while_it_runs() {
        compare(policy.icon(true, 0, true, true), "bluetooth-searching");
        compare(policy.icon(true, 1, true, true), "bluetooth-connected");
        compare(policy.icon(false, 0, true, true), "bluetooth-off");
    }

    function test_somebody_else_s_scan_does_not_move_the_glyph() {
        // #36 drew every discovering adapter, whoever started it, and that is a
        // bar repainting on somebody else's schedule — the measurement is in
        // BluetoothPolicy.qml's `icon` (#137). A scan the user started from the
        // control centre still shows; one blueman started in the background is
        // not news the bar can act on.
        compare(policy.icon(true, 0, true, false), "bluetooth");
        compare(policy.icon(true, 0, false, false), "bluetooth");
        // And the holder alone is not enough: the glyph says what the radio is
        // doing, not what was asked of it.
        compare(policy.icon(true, 0, false, true), "bluetooth");
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

    // --- #189: a handle BlueZ re-created ------------------------------------
    //
    // The signature is what decides whether the panel is rebuilt, and until #189
    // it was made only of facts about the *device*: address, name, and the three
    // flags. A BlueZ device object that goes away and comes back — the adapter
    // cycling, the device leaving and re-entering range — carries every one of
    // those unchanged, so the gate held the list still and the rows went on
    // pointing at a destroyed handle. A press then threw to the QML console
    // instead of connecting anything, which is one of the three ways #189's
    // dead button looks identical from the outside.
    //
    // Identity cannot be read off a single reading, so it is counted: the
    // generation for an address goes up when the handle behind it is not the
    // handle that was there before, and the signature carries the number.

    function test_a_handle_that_has_not_moved_keeps_its_generation() {
        const handle = { marker: 1 };
        const rows = [device("00:01", { live: handle })];
        const first = policy.handleGenerations(rows, ({}));
        compare(first["00:01"].generation, 0);
        compare(policy.handleGenerations(rows, first)["00:01"].generation, 0);
    }

    function test_a_re_created_handle_bumps_the_generation() {
        const before = policy.handleGenerations(
            [device("00:01", { live: { marker: 1 } })], ({}));
        const after = policy.handleGenerations(
            [device("00:01", { live: { marker: 2 } })], before);
        compare(after["00:01"].generation, 1);
    }

    function test_a_re_created_handle_republishes_behind_an_unchanged_signature() {
        // Every field the old signature was made of is identical here: same
        // address, same name, same flags. Only the object differs.
        const facts = { name: "Zen Zone", paired: true, bonded: true };
        const oldHandle = { marker: 1 };
        const newHandle = { marker: 2 };

        const first = [device("00:01", Object.assign({ live: oldHandle }, facts))];
        const firstGen = policy.handleGenerations(first, ({}));
        const before = policy.deviceRows(first, firstGen);

        const second = [device("00:01", Object.assign({ live: newHandle }, facts))];
        const after = policy.deviceRows(second, policy.handleGenerations(second, firstGen));

        compare(before[0].name, after[0].name);
        verify(policy.deviceSignature(before) !== policy.deviceSignature(after));
        // And the row the panel gets points at the new object, not the dead one.
        compare(after[0].live.marker, 2);
    }

    function test_generations_are_absent_by_default_and_that_is_not_a_change() {
        // The bar builds rows without a generation map at all — the gate is the
        // panel's business. A missing map must not read as "everything moved".
        const rows = [device("00:01", { live: { marker: 1 } })];
        compare(policy.deviceSignature(policy.deviceRows(rows)),
                policy.deviceSignature(policy.deviceRows(rows)));
    }

    function test_a_device_bluez_has_forgotten_leaves_the_map() {
        const first = policy.handleGenerations(
            [device("00:01", { live: { marker: 1 } }),
             device("00:02", { live: { marker: 2 } })], ({}));
        const after = policy.handleGenerations(
            [device("00:01", { live: { marker: 1 } })], first);
        compare(after["00:02"], undefined);
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

    // --- #189: the words while a connect is in flight ------------------------
    //
    // "Paired" before the press and "Paired" after it is the whole of what the
    // ticket describes: a row that cannot be told apart from a dead button. The
    // press needs an acknowledgement and the attempt needs an ending, and both
    // of them are words on this line.

    function test_a_connect_in_flight_says_so() {
        compare(policy.deviceDetail(device("00:01", { paired: true, connecting: true })),
                "Connecting…");
    }

    function test_a_connect_that_failed_says_so_before_it_goes_back_to_resting() {
        compare(policy.deviceDetail(device("00:01", { paired: true, failed: true })),
                "Connect failed");
        // And with the marker gone the row is a paired device again, not a
        // permanent failure.
        compare(policy.deviceDetail(device("00:01", { paired: true })), "Paired");
    }

    function test_pairing_outranks_connecting_and_connected_outranks_both() {
        // A device BlueZ is bonding is not also connecting, and a device that
        // arrived is not still trying. Ordered so that a stale marker on either
        // side cannot outrank the fact that the headset is now audible.
        compare(policy.deviceDetail(device("00:01", { pairing: true, connecting: true })),
                "Pairing…");
        compare(policy.deviceDetail(
            device("00:01", { connected: true, connecting: true })), "Connected");
        compare(policy.deviceDetail(
            device("00:01", { connected: true, failed: true })), "Connected");
    }

    function test_a_failed_connect_does_not_outrank_a_second_attempt() {
        // Press again while the failure is still on screen: the row has to read
        // as trying, or the second press looks as dead as the first.
        compare(policy.deviceDetail(
            device("00:01", { paired: true, failed: true, connecting: true })),
            "Connecting…");
    }

    function test_an_unpaired_row_still_reads_as_unpaired_while_it_pairs() {
        // The distinguishing affordance the ticket asks for: the two gestures
        // are one press, and which one it was is legible from the words — an
        // unpaired row says "Not paired" and reads "Pairing…" once pressed,
        // where a paired one says "Paired" and reads "Connecting…".
        compare(policy.deviceDetail(device("00:01")), "Not paired");
        compare(policy.deviceDetail(device("00:01", { pairing: true })), "Pairing…");
    }

    // --- #189: how long an attempt gets --------------------------------------

    function test_a_connect_is_given_less_than_a_pairing() {
        // A pairing waits on a human — reading a code off a screen, holding a
        // button. A connect waits on a radio that is either there or is not, so
        // it is the shorter of the two. Both are bounded: an attempt with no
        // ending is the row stuck on "Connecting…" until the shell restarts.
        compare(policy.connectTimeoutMs, 15000);
        verify(policy.connectTimeoutMs < policy.pairTimeoutMs);
    }

    function test_a_failure_is_shown_for_long_enough_to_read_and_no_longer() {
        compare(policy.failedShownMs, 4000);
        verify(policy.failedShownMs < policy.connectTimeoutMs);
    }

    // --- #189: what the log says about a connect -----------------------------

    // --- #189: a press on the LE transport -----------------------------------

    function test_a_press_on_a_bonded_le_shadow_is_reported() {
        // The row `foldTransports` keeps on purpose: bonded, so it holds the verb
        // for what is happening, and useless for audio. #153's silent no-sound
        // bond is this row being pressed with nothing said about it.
        const rows = [device("00:01", { name: "Zen Zone", paired: true }),
                      device("00:02", { name: "LE-Zen Zone", paired: true })];
        verify(policy.leShadow(rows[1], rows));
        verify(!policy.leShadow(rows[0], rows));
        verify(policy.leWarning("LE-Zen Zone").indexOf("LE-Zen Zone") === 0);
    }

    function test_an_le_device_with_no_classic_twin_is_not_a_shadow() {
        // Half the mice, the tags, the watches: LE is the only transport it has,
        // and a warning here would be a warning on every press.
        const rows = [device("00:02", { name: "LE-Tile", paired: true })];
        verify(!policy.leShadow(rows[0], rows));
    }

    // --- #189: what the panel says about the scan ----------------------------

    function test_the_activity_line_follows_the_radio_and_not_the_request() {
        // A panel holding a scan the adapter is not running had no words at all
        // before this, which reads as a panel that never asked.
        compare(policy.activity(true, true), "scanning…");
        compare(policy.activity(true, false), "not scanning");
        // Closed panels make no claim about the radio, whatever it is doing —
        // somebody else's scan is not this panel's news.
        compare(policy.activity(false, true), "");
        compare(policy.activity(false, false), "");
    }

    function test_a_scan_that_was_already_running_is_still_a_log_line() {
        verify(policy.discoveryShared() !== "");
        verify(policy.discoveryShared() !== policy.discovery(true));
    }

    function test_a_connect_that_worked_says_so() {
        compare(policy.connectOutcome("Zen Zone", ""), "connected Zen Zone");
    }

    function test_a_connect_that_did_not_says_why() {
        compare(policy.connectOutcome("Zen Zone", "timed out"),
                "Zen Zone not connected — timed out");
        compare(policy.connectOutcome("Zen Zone", "refused by bluez"),
                "Zen Zone not connected — refused by bluez");
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

    // --- what BlueZ actually did (#141) --------------------------------------

    function state(extra) {
        const facts = { paired: false, connected: false, pairing: false };
        for (const key in extra ?? ({}))
            facts[key] = extra[key];
        return facts;
    }

    function test_nothing_changing_says_nothing() {
        // The common case by far: this runs every time a headset reports one
        // percent less battery, and a line each time would be a log nobody
        // reads — which is the failure mode on the other side of #141.
        const now = state({ paired: true, connected: true });
        compare(policy.settled("Zen Zone", now, now).length, 0);
    }

    function test_a_pair_that_worked_says_so() {
        compare(policy.settled("Zen Zone", state({}), state({ paired: true })),
                ["Zen Zone paired"]);
    }

    function test_a_pair_that_failed_says_so() {
        // The case that filed the ticket: `bluetooth: pair Zen Zone` was the
        // only line, and BlueZ then reported Paired: no. There is no error to
        // read — the flag going back down with the device still unpaired is
        // the whole of the evidence.
        compare(policy.settled("Zen Zone", state({ pairing: true }), state({})),
                ["Zen Zone pairing failed"]);
    }

    function test_a_pairing_that_finished_is_not_a_failure() {
        compare(policy.settled("Zen Zone", state({ pairing: true }),
                               state({ paired: true })),
                ["Zen Zone paired"]);
    }

    function test_connecting_and_disconnecting_are_different_lines() {
        compare(policy.settled("Zen Zone", state({ paired: true }),
                               state({ paired: true, connected: true })),
                ["Zen Zone connected"]);
        compare(policy.settled("Zen Zone", state({ paired: true, connected: true }),
                               state({ paired: true })),
                ["Zen Zone disconnected"]);
    }

    function test_a_device_that_pairs_and_connects_at_once_says_both() {
        // One round trip can carry both, and the facade's own press does ask
        // for both — `deviceAction` pairs and connects as one gesture.
        compare(policy.settled("Zen Zone", state({}),
                               state({ paired: true, connected: true })),
                ["Zen Zone paired", "Zen Zone connected"]);
    }

    function test_a_forgotten_device_says_it_is_no_longer_paired() {
        compare(policy.settled("Zen Zone", state({ paired: true, connected: true }),
                               state({})),
                ["Zen Zone no longer paired", "Zen Zone disconnected"]);
    }

    function test_a_device_with_no_previous_reading_is_not_a_transition() {
        // An adapter coming up with three paired headsets on it must not
        // announce all three as having just paired.
        compare(policy.settled("Zen Zone", null, state({ paired: true })).length, 0);
        compare(policy.settled("Zen Zone", undefined, state({ paired: true })).length, 0);
        compare(policy.settled("Zen Zone", state({}), null).length, 0);
    }

    // --- trust, and the transport a press lands on (#153) --------------------

    function test_a_device_that_has_just_paired_wants_trusting() {
        // The bond survived the pass that filed #153; it was untrusted, so
        // BlueZ refused the headset's own reconnect afterwards.
        compare(policy.trustNeeded(state({}), state({ paired: true })), true);
    }

    function test_a_device_that_is_already_trusted_is_left_alone() {
        compare(policy.trustNeeded(state({}),
                                   state({ paired: true, trusted: true })), false);
    }

    function test_trust_follows_the_bond_and_not_the_reading() {
        // Only the transition into paired. A device that was already paired
        // and untrusted when the shell started was trusted or not by somebody
        // else's decision, and starting up is not the moment to overrule it.
        compare(policy.trustNeeded(state({ paired: true }),
                                   state({ paired: true })), false);
        compare(policy.trustNeeded(state({}), state({})), false);
        compare(policy.trustNeeded(null, state({ paired: true })), false);
        compare(policy.trustNeeded(state({}), null), false);
    }

    function test_trusting_says_so() {
        compare(policy.trustGranted("Zen Zone"), "Zen Zone trusted");
    }

    function test_an_le_advertisement_names_the_device_it_shadows() {
        compare(policy.classicName("LE-Zen Zone"), "Zen Zone");
        compare(policy.classicName("le_Zen Zone"), "Zen Zone");
        // Not an LE advertisement at all, and not a device that merely starts
        // with those two letters.
        compare(policy.classicName("Zen Zone"), "");
        compare(policy.classicName("LEGO Boost"), "");
        compare(policy.classicName("LE-"), "");
        compare(policy.classicName(null), "");
    }

    function test_a_press_lands_on_the_classic_device_and_not_its_le_shadow() {
        // #153: the press pairing "LE-Zen Zone" bonded over LE, which carries
        // no A2DP — no card in PipeWire, no sink, no sound. When both are on
        // the air the classic one is the row.
        const rows = policy.deviceRows([
            device("BC:87:FA:BC:D5:94", { name: "Zen Zone" }),
            device("7C:11:22:33:44:55", { name: "LE-Zen Zone" })
        ]);
        compare(names(rows), ["Zen Zone"]);
        compare(rows[0].address, "BC:87:FA:BC:D5:94");
    }

    function test_an_le_device_with_no_classic_twin_is_still_a_row() {
        // Plenty of devices are LE and nothing else — a tag, a watch, a
        // mouse. Folding those away would hide the only row they have.
        const rows = policy.deviceRows([
            device("7C:11:22:33:44:55", { name: "LE-Tile Tracker" })
        ]);
        compare(names(rows), ["LE-Tile Tracker"]);
    }

    function test_an_le_row_that_is_doing_something_is_never_folded_away() {
        // Only a bare scan result is shadow enough to drop. A bond or a live
        // connection over LE is the row that holds the disconnect.
        const connected = policy.deviceRows([
            device("BC:87:FA:BC:D5:94", { name: "Zen Zone" }),
            device("7C:11:22:33:44:55", { name: "LE-Zen Zone", connected: true })
        ]);
        compare(names(connected), ["LE-Zen Zone", "Zen Zone"]);

        const paired = policy.deviceRows([
            device("BC:87:FA:BC:D5:94", { name: "Zen Zone" }),
            device("7C:11:22:33:44:55", { name: "LE-Zen Zone", paired: true })
        ]);
        compare(names(paired), ["LE-Zen Zone", "Zen Zone"]);
    }

    function test_a_row_with_nothing_happening_to_it_is_a_scan_result() {
        verify(policy.nothingHappeningTo(device("00:01")));
        verify(!policy.nothingHappeningTo(device("00:01", { connected: true })));
        verify(!policy.nothingHappeningTo(device("00:01", { paired: true })));
        verify(!policy.nothingHappeningTo(device("00:01", { pairing: true })));
    }

    // --- the pairing agent (#153) --------------------------------------------

    function test_an_attempt_is_given_a_minute() {
        // Long enough for a headset held in a hand and a BlueZ window that is
        // about this wide; short enough that a device that walked away does not
        // leave a row reading "Pairing…" until the shell restarts.
        compare(policy.pairTimeoutMs, 60000);
    }

    function test_the_pairing_script_registers_an_agent_before_it_pairs() {
        // The whole of #153's first cause: an outgoing Pair() with nothing to
        // answer the authentication request. Order is the point — an agent,
        // made default, then trust, then pair.
        compare(policy.pairScript("BC:87:FA:BC:D5:94"), [
            "agent NoInputNoOutput",
            "default-agent",
            "trust BC:87:FA:BC:D5:94",
            "pair BC:87:FA:BC:D5:94"
        ]);
    }

    function test_a_pairing_with_no_address_is_no_script() {
        compare(policy.pairScript("").length, 0);
        compare(policy.pairScript(null).length, 0);
    }

    function test_the_agent_reports_a_pairing_that_worked() {
        const outcome = policy.pairOutcome("Pairing successful");
        compare(outcome.done, true);
        compare(outcome.ok, true);
    }

    function test_the_agent_reports_why_a_pairing_failed() {
        const outcome = policy.pairOutcome(
            "Failed to pair: org.bluez.Error.AuthenticationCanceled");
        compare(outcome.done, true);
        compare(outcome.ok, false);
        compare(outcome.reason, "org.bluez.Error.AuthenticationCanceled");
    }

    function test_the_colours_bluetoothctl_writes_are_not_part_of_the_answer() {
        // bluetoothctl paints its own output even with no terminal on the far
        // end, and an escape sequence in the middle of the line is what makes
        // a match that works by hand fail in a pipe.
        const outcome = policy.pairOutcome("\x1b[0;92m[CHG]\x1b[0m Pairing successful");
        compare(outcome.done, true);
        compare(outcome.ok, true);
    }

    function test_a_device_bluetoothctl_cannot_see_ends_the_attempt() {
        // Measured against bluetoothctl 5.87: an address it does not hold an
        // object for is refused in a sentence of its own, with no "Failed to
        // pair" anywhere in it. Read as narration, that is an attempt that
        // hangs until the timeout — a row stuck on "Pairing…" for a minute
        // after the device it names walked out of range mid-scan.
        const outcome = policy.pairOutcome("Device 00:11:22:33:44:55 not available");
        compare(outcome.done, true);
        compare(outcome.ok, false);
        compare(outcome.reason, "not available");
    }

    function test_everything_else_bluetoothctl_says_is_not_an_outcome() {
        // It narrates the whole scan while it waits. None of that ends the
        // attempt, and ending it early is what unregisters the agent.
        compare(policy.pairOutcome("Attempting to pair with BC:87:FA:BC:D5:94").done, false);
        compare(policy.pairOutcome("[NEW] Device 7C:11:22:33:44:55 LE-Zen Zone").done, false);
        // The agent's own registration, which is the *start* of the attempt.
        compare(policy.pairOutcome("Agent registered").done, false);
        compare(policy.pairOutcome("Default agent request successful").done, false);
        compare(policy.pairOutcome("[Zen Zone]> pair BC:87:FA:BC:D5:94").done, false);
        compare(policy.pairOutcome("").done, false);
        compare(policy.pairOutcome(null).done, false);
    }

    function test_a_pairing_result_says_so_in_the_log() {
        compare(policy.paired("Zen Zone", { done: true, ok: true, reason: "" }),
                "Zen Zone paired");
        compare(policy.paired("Zen Zone",
                              { done: true, ok: false,
                                reason: "org.bluez.Error.AuthenticationCanceled" }),
                "Zen Zone pairing failed — org.bluez.Error.AuthenticationCanceled");
        compare(policy.paired("Zen Zone", { done: true, ok: false, reason: "" }),
                "Zen Zone pairing failed");
    }
}
