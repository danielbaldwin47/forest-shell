// What the Wi-Fi drill-in decides (#45): the order of the list, which rows
// prompt for a passphrase, which cannot be joined from here at all, and the
// words on each.
//
// The picture is Surfaces/Drawers/DrillIn/WifiPanel.qml and needs a compositor.
// Joining a real access point needs a real radio and is a manual pass — what is
// here is every decision made before the radio is touched, which is all of them
// except the touching.
import QtQuick
import QtTest
import "../Services/Networking"

TestCase {
    name: "WifiPolicy"

    WifiPolicy { id: policy }

    function network(ssid, extra) {
        const row = { ssid: ssid, security: "psk", known: false,
                      connected: false, connecting: false, strength: 60 };
        for (const key in extra ?? ({}))
            row[key] = extra[key];
        return row;
    }

    function names(rows) {
        return rows.map(row => row.ssid);
    }

    // --- the order -----------------------------------------------------------

    function test_connected_first_then_saved_then_the_rest() {
        const rows = policy.rows([
            network("zebra"),
            network("apple", { known: true }),
            network("HOME", { connected: true }),
            network("banana")
        ]);
        compare(names(rows), ["HOME", "apple", "banana", "zebra"]);
    }

    function test_a_join_in_flight_sits_under_the_connected_row() {
        // Above saved, because it is the row the user just pressed and the one
        // whose outcome they are waiting for.
        const rows = policy.rows([
            network("saved", { known: true }),
            network("joining", { connecting: true })
        ]);
        compare(names(rows), ["joining", "saved"]);
    }

    function test_the_order_is_alphabetical_regardless_of_case() {
        // "iPhone" sorts after "Internet" in ASCII, which is a list that looks
        // unsorted to the person reading it.
        const rows = policy.rows([
            network("iPhone"), network("Internet"), network("apple")
        ]);
        compare(names(rows), ["apple", "Internet", "iPhone"]);
    }

    function test_strength_never_decides_where_a_row_sits() {
        // The whole argument of the file: strength drifts on a still machine,
        // and a list ordered by it reorders under the pointer.
        const weakFirst = policy.rows([
            network("aaa", { strength: 5 }), network("bbb", { strength: 95 })
        ]);
        compare(names(weakFirst), ["aaa", "bbb"]);
    }

    // --- what is a row at all ------------------------------------------------

    function test_a_hidden_network_is_not_a_row() {
        // An empty SSID is a network with nothing to press and nothing to name
        // it by. Joining one means typing its name, which is a different act.
        compare(policy.rows([network(""), network("  "), network("real")]).length, 1);
    }

    function test_one_ssid_on_three_access_points_is_one_row() {
        const rows = policy.rows([
            network("EDUROAM", { strength: 30 }),
            network("EDUROAM", { strength: 80 }),
            network("EDUROAM", { strength: 55 })
        ]);
        compare(rows.length, 1);
    }

    function test_the_connected_copy_of_a_duplicate_wins() {
        // It is the one carrying the traffic, and the one whose handle can be
        // disconnected.
        const rows = policy.rows([
            network("EDUROAM", { strength: 80 }),
            network("EDUROAM", { connected: true, strength: 20 })
        ]);
        compare(rows.length, 1);
        compare(rows[0].connected, true);
    }

    function test_the_live_handle_travels_with_the_row_untouched() {
        // The policy never reads it; the surface binds a live signal strength
        // to it and the facade calls connect() on it.
        const handle = { marker: 42 };
        const rows = policy.rows([{ ssid: "HOME", live: handle }]);
        compare(rows[0].live.marker, 42);
    }

    // --- #75: the signature --------------------------------------------------

    function test_a_drifting_signal_does_not_change_the_signature() {
        // The reason the list survives #75: the service republishes only when
        // this string moves, so a strength that wanders rebuilds no delegates.
        const before = policy.rows([network("HOME", { strength: 72 })]);
        const after = policy.rows([network("HOME", { strength: 78 })]);
        compare(policy.signature(before), policy.signature(after));
    }

    function test_a_network_appearing_does_change_the_signature() {
        const before = policy.rows([network("HOME")]);
        const after = policy.rows([network("HOME"), network("CAFE")]);
        verify(policy.signature(before) !== policy.signature(after));
    }

    function test_connecting_and_connected_are_different_signatures() {
        // Both are structural: the row moves band, and the words on it change.
        const idle = policy.rows([network("HOME")]);
        const joining = policy.rows([network("HOME", { connecting: true })]);
        const done = policy.rows([network("HOME", { connected: true })]);
        verify(policy.signature(idle) !== policy.signature(joining));
        verify(policy.signature(joining) !== policy.signature(done));
    }

    function test_a_network_becoming_saved_changes_the_signature() {
        // It moves band and stops prompting — both visible.
        const before = policy.rows([network("HOME")]);
        const after = policy.rows([network("HOME", { known: true })]);
        verify(policy.signature(before) !== policy.signature(after));
    }

    // --- the passphrase prompt -----------------------------------------------

    function test_a_secured_network_prompts() {
        verify(policy.needsPassword(network("HOME")));
    }

    function test_an_open_network_never_prompts() {
        verify(!policy.needsPassword(network("CAFE", { security: "open" })));
        verify(!policy.needsPassword(network("CAFE", { security: "owe" })));
    }

    function test_a_saved_network_never_prompts() {
        // NetworkManager already holds the secret. Asking again for something
        // the machine knows is how a user comes to believe the shell forgot it.
        verify(!policy.needsPassword(network("HOME", { known: true })));
    }

    function test_the_network_already_connected_never_prompts() {
        verify(!policy.needsPassword(network("HOME", { connected: true })));
    }

    // --- what a press means --------------------------------------------------

    function test_pressing_the_connected_row_disconnects() {
        compare(policy.action(network("HOME", { connected: true })), "disconnect");
    }

    function test_pressing_a_join_in_flight_cancels_it() {
        compare(policy.action(network("HOME", { connecting: true })), "cancel");
    }

    function test_pressing_an_open_network_connects_without_a_prompt() {
        compare(policy.action(network("CAFE", { security: "open" })), "connect");
    }

    function test_pressing_a_saved_network_connects_without_a_prompt() {
        compare(policy.action(network("HOME", { known: true })), "connect");
    }

    function test_pressing_a_secured_network_raises_the_prompt() {
        compare(policy.action(network("HOME")), "prompt");
    }

    function test_an_enterprise_network_is_unsupported_rather_than_silent() {
        // It wants an identity, a certificate and often a CA chain. A field
        // asking for a "password" is a prompt that fails after the typing, so
        // the row says so instead (#81: a press that does nothing and says
        // nothing is the bug).
        const eap = network("CAMPUS", { security: "eap" });
        compare(policy.action(eap), "unsupported");
        verify(!policy.joinable(eap));
        compare(policy.detail(eap),
                "Enterprise — configure it in NetworkManager");
    }

    function test_a_saved_enterprise_network_can_still_be_rejoined() {
        // The certificate is already in NetworkManager; this is the one case
        // where the shell has nothing left to ask for.
        const saved = network("CAMPUS", { security: "eap", known: true });
        verify(policy.joinable(saved));
        compare(policy.action(saved), "connect");
        compare(policy.detail(saved), "Saved · Enterprise");
    }

    // --- the words -----------------------------------------------------------

    function test_the_detail_line_names_the_state_before_the_security() {
        compare(policy.detail(network("HOME", { connected: true })), "Connected");
        compare(policy.detail(network("HOME", { connecting: true })), "Connecting…");
        compare(policy.detail(network("HOME", { known: true })), "Saved");
        compare(policy.detail(network("HOME")), "Secured");
        compare(policy.detail(network("CAFE", { security: "open" })), "Open");
    }

    function test_only_a_secured_row_carries_a_lock() {
        compare(policy.lockIcon(network("HOME")), "lock");
        compare(policy.lockIcon(network("CAFE", { security: "open" })), "");
    }

    function test_the_glyph_is_the_bars_the_bar_draws() {
        // One ladder for the shell: the same four glyphs the indicator uses.
        compare(policy.icon(0), "wifi-zero");
        compare(policy.icon(30), "wifi-low");
        compare(policy.icon(60), "wifi-high");
        compare(policy.icon(90), "wifi");
    }

    function test_the_glyph_normalises_a_fraction_like_the_bar_does() {
        // NetworkManager reports 0-100 and Quickshell types it as a double, so
        // both readings arrive and both have to work.
        compare(policy.icon(0.9), "wifi");
    }

    // --- the passphrase itself -----------------------------------------------

    function test_a_short_wpa_passphrase_is_refused_before_the_radio_sees_it() {
        // WPA-PSK is 8-63 characters. A shorter one is rejected by the
        // supplicant several seconds later, and a prompt that accepts it and
        // then fails blames the user's password rather than its own button.
        verify(!policy.passphraseAccepted(network("HOME"), "short"));
        verify(policy.passphraseAccepted(network("HOME"), "longenough"));
    }

    function test_wep_has_its_own_shorter_floor() {
        const wep = network("OLD", { security: "wep" });
        verify(policy.passphraseAccepted(wep, "abcde"));
        verify(!policy.passphraseAccepted(wep, "abcd"));
    }

    // --- the log -------------------------------------------------------------

    function test_a_failure_names_the_network_and_the_reason() {
        // The two answers a user can act on are separated from the rest: a
        // wrong passphrase is a thing to retype, everything else to retry.
        compare(policy.failure("HOME", "NoSecrets"),
                "wifi HOME failed — wrong passphrase");
        compare(policy.failure("HOME", "WifiAuthTimeout"),
                "wifi HOME failed — authentication timed out");
        compare(policy.failure("HOME", "Nonsense"),
                "wifi HOME failed — unknown reason");
    }

    function test_a_refusal_names_the_network_and_why() {
        compare(policy.refused("CAMPUS", "enterprise networks need NetworkManager"),
                "wifi CAMPUS unchanged — enterprise networks need NetworkManager");
    }

    // --- what a scan found (#141) --------------------------------------------

    function test_a_scan_says_how_many_it_saw() {
        compare(policy.visible(4), "4 networks visible");
    }

    function test_one_network_is_not_one_networks() {
        compare(policy.visible(1), "1 network visible");
    }

    function test_a_scan_that_found_nothing_says_so_in_words() {
        // The whole point of the line: a scan that saw nothing and a scan whose
        // result was never logged used to read the same, which is what made the
        // Wi-Fi step of #136's manual pass unevidenceable from the log.
        compare(policy.visible(0), "no networks visible");
    }

    function test_a_count_that_is_not_a_count_reads_as_nothing() {
        // `wifiCandidates` is a JS array on a service that may have no device,
        // and a length read off nothing must not print "undefined networks".
        for (const bad of [-1, undefined, null, NaN])
            compare(policy.visible(bad), "no networks visible", "count " + bad);
    }
}
