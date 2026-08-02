// What the power-profile tile decides (#44): what `powerprofilesctl` is asked,
// what its answer means, and which profile one press moves to.
//
// The daemon is the authority on which profiles exist — a machine may offer two
// or four, and one of them may be a vendor name this shell has never heard of —
// so nothing here has a hardcoded list to cycle through.
import QtQuick
import QtTest
import "../Services/Hardware"

TestCase {
    name: "PowerProfilePolicy"

    PowerProfilePolicy { id: policy }

    // `powerprofilesctl list`, verbatim from a machine with amd_pstate. The
    // active profile carries the asterisk; the rest are indented by two.
    readonly property string listing: '* balanced:\n'
        + '    CpuDriver:\tamd_pstate_epp\n'
        + '    PlatformDriver:\tamd-pmf\n'
        + '    Degraded:\tno\n'
        + '\n'
        + '  performance:\n'
        + '    CpuDriver:\tamd_pstate_epp\n'
        + '    PlatformDriver:\tamd-pmf\n'
        + '\n'
        + '  power-saver:\n'
        + '    CpuDriver:\tamd_pstate_epp\n'
        + '    PlatformDriver:\tamd-pmf\n'

    function test_the_commands_are_the_three_the_daemon_answers() {
        compare(policy.listCommand(), ["powerprofilesctl", "list"]);
        compare(policy.setCommand("performance"),
                ["powerprofilesctl", "set", "performance"]);
    }

    function test_a_profile_the_daemon_never_offered_is_not_asked_for() {
        // The name reaches this from a cycle over the daemon's own list, so an
        // empty argv here means a bug upstream of it rather than a user typo —
        // and an empty argv reaching `Process` is a tile that spins.
        compare(policy.setCommand(""), []);
        compare(policy.setCommand("   "), []);
    }

    function test_the_listing_gives_the_profiles_in_the_daemons_order() {
        compare(policy.parseList(listing),
                ["balanced", "performance", "power-saver"]);
    }

    function test_the_asterisk_is_which_one_is_running() {
        compare(policy.parseActive(listing), "balanced");
    }

    function test_a_machine_with_no_daemon_lists_nothing() {
        // `powerprofilesctl` prints its own prose when power-profiles-daemon is
        // not on the bus, and none of it is a profile.
        compare(policy.parseList(""), []);
        compare(policy.parseList(null), []);
        compare(policy.parseList("Error: could not connect to power-profiles-daemon"), []);
        compare(policy.parseActive("Error: could not connect"), "");
    }

    function test_a_vendor_profile_is_listed_under_its_own_name() {
        const listing = '  balanced:\n    CpuDriver:\tintel_pstate\n'
                      + '\n* vendor-turbo:\n    CpuDriver:\tintel_pstate\n';
        compare(policy.parseList(listing), ["balanced", "vendor-turbo"]);
        compare(policy.parseActive(listing), "vendor-turbo");
    }

    function test_a_press_moves_to_the_next_profile_the_daemon_offers() {
        const all = ["balanced", "performance", "power-saver"];
        compare(policy.next("balanced", all), "performance");
        compare(policy.next("performance", all), "power-saver");
        compare(policy.next("power-saver", all), "balanced");
    }

    function test_cycling_from_a_profile_that_left_the_list_starts_over() {
        // The daemon can drop a profile — `performance` disappears on a machine
        // that has been unplugged, and the tile must not become a dead press.
        compare(policy.next("performance", ["balanced", "power-saver"]), "balanced");
        compare(policy.next("", ["balanced", "power-saver"]), "balanced");
    }

    function test_cycling_with_nothing_to_cycle_through_changes_nothing() {
        compare(policy.next("balanced", []), "");
        compare(policy.next("balanced", null), "");
        compare(policy.next("balanced", ["balanced"]), "");
    }

    function test_an_exit_status_is_the_whole_answer() {
        // Unlike hyprctl (#78, which answers `ok` to rules it refuses),
        // powerprofilesctl exits non-zero and says so on stderr.
        verify(policy.accepted(0));
        verify(!policy.accepted(1));
    }

    function test_both_outcomes_get_a_line_and_both_name_the_profile() {
        compare(policy.applied("performance"), "profile performance");
        compare(policy.complaint("performance", 1, "Error: no such profile\n"),
                "profile performance refused — exit 1: Error: no such profile");
        compare(policy.complaint("performance", 1, ""),
                "profile performance refused — exit 1");
    }
}
