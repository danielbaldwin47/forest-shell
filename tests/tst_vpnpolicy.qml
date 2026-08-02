// What the VPN tile decides (#44): what `nmcli` is asked, which of its lines is
// a tunnel, and which tunnel one press moves.
//
// `Quickshell.Networking` is a real NetworkManager client but has no VPN
// surface, so this is the one part of the network facade that shells out — and
// the one part with a parser, since `nmcli -t` is the only shape the answer
// comes in.
import QtQuick
import QtTest
import "../Services/Networking"

TestCase {
    name: "VpnPolicy"

    VpnPolicy { id: policy }

    // `nmcli -t -f NAME,TYPE,STATE connection show`, verbatim. Colons inside a
    // name arrive backslash-escaped; the type and state never contain one.
    readonly property string listing:
          'Wired connection 1:802-3-ethernet:activated\n'
        + 'PUMPKINCURRY:802-11-wireless:activated\n'
        + 'work:vpn:activated\n'
        + 'home:wireguard:\n'

    function test_the_commands_are_the_three_nmcli_answers() {
        compare(policy.listCommand(),
                ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show"]);
        compare(policy.upCommand("work"), ["nmcli", "connection", "up", "id", "work"]);
        compare(policy.downCommand("work"), ["nmcli", "connection", "down", "id", "work"]);
    }

    function test_a_tunnel_nobody_named_is_not_asked_for() {
        // An empty argv reaching `Process` is a tile that spins.
        compare(policy.upCommand(""), []);
        compare(policy.downCommand("  "), []);
        compare(policy.upCommand(null), []);
    }

    // --- reading the listing -------------------------------------------------

    function test_only_the_tunnels_are_tunnels() {
        // Wifi and ethernet are connections too, and neither belongs on this
        // tile — Services/Networking/Networking.qml already speaks for them.
        compare(policy.parse(listing),
                [{ name: "work", up: true }, { name: "home", up: false }]);
    }

    function test_wireguard_counts_as_a_vpn() {
        // NetworkManager types a WireGuard profile `wireguard` rather than
        // `vpn`, and a shell that only matched the latter would show no tile on
        // a machine whose only tunnel is one.
        const rows = policy.parse('home:wireguard:activated\n');
        compare(rows.length, 1);
        compare(rows[0].name, "home");
        compare(rows[0].up, true);
    }

    function test_a_name_with_a_colon_in_it_survives_the_parse() {
        // `nmcli -t` escapes a literal colon; splitting naively would cut the
        // name in half and then fail to find it again on the way back up.
        const rows = policy.parse('work\\: eu:vpn:activated\n');
        compare(rows.length, 1);
        compare(rows[0].name, "work: eu");
    }

    function test_a_machine_with_no_networkmanager_lists_nothing() {
        compare(policy.parse(""), []);
        compare(policy.parse(null), []);
        compare(policy.parse("Error: NetworkManager is not running."), []);
    }

    function test_only_activated_counts_as_up() {
        // `activating` is a tunnel that has not come up yet, and lighting the
        // tile for it would light it for one that then fails.
        compare(policy.parse('a:vpn:activating\n')[0].up, false);
        compare(policy.parse('a:vpn:\n')[0].up, false);
        compare(policy.parse('a:vpn:activated\n')[0].up, true);
    }

    // --- which one a press moves ---------------------------------------------

    function test_a_press_takes_down_whichever_is_up() {
        const tunnels = [{ name: "work", up: false }, { name: "home", up: true }];
        compare(policy.active(tunnels), "home");
        compare(policy.target(tunnels), "home");
        compare(policy.wanted(tunnels), false);
    }

    function test_a_press_brings_up_the_first_one_when_none_is() {
        // "First" is nmcli's order, which is NetworkManager's own. A picker for
        // the rest is the drill-in this ticket stubs.
        const tunnels = [{ name: "work", up: false }, { name: "home", up: false }];
        compare(policy.active(tunnels), "");
        compare(policy.target(tunnels), "work");
        compare(policy.wanted(tunnels), true);
    }

    function test_a_machine_with_no_tunnel_has_nothing_to_press() {
        compare(policy.target([]), "");
        compare(policy.target(null), "");
        compare(policy.active([]), "");
    }

    function test_the_tile_is_absent_rather_than_dead_without_a_tunnel() {
        verify(!policy.available([]));
        verify(!policy.available(null));
        verify(policy.available([{ name: "work", up: false }]));
    }

    // --- did it work ---------------------------------------------------------

    function test_an_exit_status_is_the_whole_answer() {
        // nmcli exits non-zero and explains itself on stderr, unlike hyprctl
        // (#78).
        verify(policy.accepted(0));
        verify(!policy.accepted(4));
    }

    function test_both_outcomes_get_a_line_and_both_name_the_tunnel() {
        compare(policy.applied("work", true), "vpn work up");
        compare(policy.applied("work", false), "vpn work down");
        compare(policy.complaint("work", true, 4, "Error: no such connection\n"),
                "vpn work up refused — exit 4: Error: no such connection");
        compare(policy.complaint("work", false, 4, ""),
                "vpn work down refused — exit 4");
    }

    // --- the drill-in's list (#45) -------------------------------------------

    function names(rows) {
        return rows.map(row => row.name);
    }

    function test_the_tunnel_that_is_up_sits_first() {
        compare(names(policy.rows([
            { name: "work", up: false },
            { name: "home", up: true }
        ])), ["home", "work"]);
    }

    function test_the_rest_are_alphabetical_rather_than_in_networkmanagers_order() {
        // NetworkManager lists by last-modified, so its order reshuffles itself
        // every time the user brings a tunnel up — which is exactly the moment
        // they are looking at the list.
        compare(names(policy.rows([
            { name: "zurich", up: false },
            { name: "Amsterdam", up: false },
            { name: "berlin", up: false }
        ])), ["Amsterdam", "berlin", "zurich"]);
    }

    function test_a_nameless_row_is_not_a_row() {
        compare(policy.rows([{ name: "" }, { name: "  " }, { name: "work" }]).length, 1);
    }

    function test_pressing_a_second_tunnel_brings_it_up_rather_than_taking_the_first_down() {
        // The tile acts on the machine's state; a row acts on itself.
        const rows = policy.rows([{ name: "home", up: true }, { name: "work", up: false }]);
        compare(policy.rowAction(rows[0]), "down");
        compare(policy.rowAction(rows[1]), "up");
    }

    function test_a_row_says_whether_it_is_up() {
        compare(policy.rowDetail({ up: true }), "Connected");
        compare(policy.rowDetail({ up: false }), "Not connected");
        compare(policy.rowIcon({ up: true }), "shield");
        compare(policy.rowIcon({ up: false }), "shield-off");
    }

    function test_the_signature_is_the_whole_row() {
        // The one list of the five with no live measurement on it, so nothing
        // has to be left out to keep #75 at bay.
        const before = policy.rows([{ name: "work", up: false }]);
        const after = policy.rows([{ name: "work", up: true }]);
        verify(policy.signature(before) !== policy.signature(after));
        compare(policy.signature(before), policy.signature(policy.rows([{ name: "work" }])));
    }
}
