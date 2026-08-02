// The session drawer's actions (#38): what is on it, what each one runs, and
// which one is not a command at all.
//
// Firing them is the surface's job — `Process` and `SessionLock` both import
// Quickshell — so what is checked here is the table and the routing, and
// tools/drawer-harness.sh asserts on the log lines these functions produce.
import QtQuick
import QtTest
import "../Surfaces/Drawers"

TestCase {
    id: testCase
    name: "SessionPolicy"

    SessionPolicy { id: policy }

    readonly property var configured: ({
        logout: "hyprctl dispatch exit",
        suspend: "systemctl suspend",
        reboot: "systemctl reboot",
        shutdown: "systemctl poweroff"
    })

    function test_the_menu_is_the_five_the_ticket_names_in_that_order() {
        const ids = policy.actions.map(action => action.id);
        compare(ids, ["lock", "logout", "suspend", "reboot", "shutdown"]);
    }

    function test_every_action_has_something_to_draw() {
        for (const action of policy.actions) {
            verify(action.label !== undefined && action.label !== "",
                   action.id + " has no label");
            verify(action.icon !== undefined && action.icon !== "",
                   action.id + " has no icon");
        }
    }

    function test_lock_is_the_shell_and_not_a_command() {
        // The lock is a surface this shell owns (#47). Shelling out to
        // `loginctl lock-session` so the shell could ask itself to lock would
        // be the mistake Core/SurfaceBus.qml exists to avoid, one process
        // further out.
        verify(policy.routesToLock("lock"));
        compare(policy.command("lock", testCase.configured), "");

        for (const action of policy.actions)
            if (action.id !== "lock")
                verify(!policy.routesToLock(action.id), action.id + " routed to the lock");
    }

    function test_the_other_four_run_what_the_config_says() {
        compare(policy.command("logout", testCase.configured), "hyprctl dispatch exit");
        compare(policy.command("shutdown", testCase.configured), "systemctl poweroff");
    }

    function test_a_command_emptied_in_the_config_is_refused_rather_than_run() {
        // A blank key is a user saying "not on this machine", not a shell bug.
        // What must not happen is an empty argv reaching `Process`, which is a
        // button that spins and reports nothing.
        compare(policy.command("suspend", { suspend: "   " }), "");
        verify(/suspend/.test(policy.refused("suspend")));
        verify(/system\.session\.commands\.suspend/.test(policy.refused("suspend")),
               policy.refused("suspend"));
    }

    function test_an_action_nobody_declared_runs_nothing() {
        compare(policy.command("hibernate", testCase.configured), "");
        verify(!policy.routesToLock("hibernate"));
    }

    function test_a_command_is_argv_and_not_a_shell_line() {
        // Split here rather than handed to `sh -c`: the config holds a command,
        // and a string that reaches a shell brings the shell's quoting,
        // globbing and word-splitting rules with it for no gain.
        compare(policy.argv("hyprctl dispatch exit"), ["hyprctl", "dispatch", "exit"]);
        compare(policy.argv("  systemctl   poweroff  "), ["systemctl", "poweroff"]);
        compare(policy.argv(""), []);
    }

    function test_firing_an_action_says_what_it_ran() {
        compare(policy.fired("shutdown", "systemctl poweroff"),
                "shutdown → systemctl poweroff");
        compare(policy.fired("lock", ""), "lock → the shell's own lock");
    }
}
