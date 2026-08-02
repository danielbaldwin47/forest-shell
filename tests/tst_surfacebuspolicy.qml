// The bar buttons that reach surfaces which do not exist yet (#37, for #39 and
// #44): what they may ask for, and what the shell says when nothing answers.
import QtQuick
import QtTest
import "../Core"

TestCase {
    name: "SurfaceBusPolicy"

    SurfaceBusPolicy { id: policy }

    function test_the_launcher_answers_the_name_the_shell_switcher_generates() {
        // Fixed by the shell-switch contract, not chosen here: the generated
        // Hyprland bind is `bind = SUPER, Space, exec, qs ipc call launcher
        // toggle` (.wayfinder/research/shell-switch-integration.md §2.2), so a
        // different target or verb would ship a Super+Space that does nothing.
        compare(policy.command("launcher"), "qs ipc call launcher toggle");
    }

    function test_no_surface_advertises_a_name_the_cli_eats() {
        // #77: `qs ipc call <target> show` is parsed as `qs ipc show`, prints
        // the target listing and exits 0. Same for `list` and `call`. An
        // advertised function nobody can call is worse than no function,
        // because it is the one everybody types first.
        for (const name in policy.surfaces) {
            const surface = policy.surfaces[name];
            verify(policy.callable(surface.verb),
                   name + " advertises a verb the CLI eats: " + surface.verb);
            verify(policy.reservedVerbs.indexOf(surface.target) < 0,
                   name + " advertises a target the CLI eats: " + surface.target);
        }
    }

    function test_every_surface_is_named_the_way_settings_was() {
        // Lowercase, matching the surface's own name — the convention
        // Surfaces/Settings/SettingsWindow.qml fixed for `settings`.
        for (const name in policy.surfaces) {
            const surface = policy.surfaces[name];
            compare(surface.target, name);
            compare(surface.target, surface.target.toLowerCase());
            verify(surface.label !== undefined && surface.label !== "",
                   name + " has no label to put in a log line");
        }
    }

    function test_a_missing_surface_says_what_to_try_by_hand() {
        // "Nothing happened" is exactly what a broken button and an unbuilt
        // surface look like from outside, so the line names both the surface
        // and the command that will work once it lands.
        const line = policy.absent("controlcenter");
        verify(/control centre/.test(line), line);
        verify(/qs ipc call controlcenter toggle/.test(line), line);
    }

    function test_a_surface_nobody_declared_is_a_shell_bug_and_reads_like_one() {
        verify(!policy.known("dashboard"));
        compare(policy.absent("dashboard"), "no such surface: dashboard");
        compare(policy.command("dashboard"), "");
        verify(policy.known("launcher"));
        verify(policy.known("controlcenter"));
    }
}
