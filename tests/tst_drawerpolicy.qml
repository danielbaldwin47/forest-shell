// The shared drawer window's decisions (#38): which drawer is open, on which
// screen, what a hotplug does to that, and the timings the cross-drawer swap
// needs that are not already a design-system step.
//
// The window itself is a `PanelWindow` with a `HyprlandFocusGrab` in it and so
// cannot be loaded here; that half is driven over IPC in a nested compositor by
// tools/drawer-harness.sh, and photographed by tools/capture-harness.sh
// --surface drawer.
import QtQuick
import QtTest
import "../Surfaces/Drawers"

TestCase {
    name: "DrawerPolicy"

    DrawerPolicy { id: policy }

    /// The shell as it will be once the launcher lands (#39). The swap is the
    /// one rule the shared-window topology exists to enforce, and it is not
    /// reachable in a world with a single drawer in it.
    DrawerPolicy {
        id: twoDrawers
        tenants: ["session", "launcher"]
    }

    // --- which drawer is open ------------------------------------------------

    function test_a_toggle_opens_what_is_closed_and_closes_what_is_open() {
        compare(policy.next("", "session"), "session");
        compare(policy.next("session", "session"), "");
    }

    function test_asking_for_a_second_drawer_swaps_rather_than_stacking() {
        // One window, one focus grab: two drawers open at once is the state
        // this topology exists to make unrepresentable (#12).
        compare(twoDrawers.next("session", "launcher"), "launcher");
        compare(twoDrawers.next("launcher", "session"), "session");
    }

    function test_a_toggle_for_a_drawer_nobody_built_changes_nothing() {
        // The bus already logs the miss (Core/SurfaceBusPolicy.qml). What must
        // not happen is the open drawer closing because someone pressed a
        // button for a surface that has not landed.
        compare(policy.next("session", "dashboard"), "session");
        compare(policy.next("", "dashboard"), "");
    }

    function test_the_transition_names_what_the_motion_has_to_do() {
        compare(policy.transition("", "session"), "open");
        compare(policy.transition("session", ""), "close");
        compare(policy.transition("session", "launcher"), "switch");
        compare(policy.transition("session", "session"), "none");
        compare(policy.transition("", ""), "none");
    }

    // --- which screen --------------------------------------------------------

    function test_a_drawer_opens_on_the_focused_screen() {
        compare(policy.openOn("DP-2", ["eDP-1", "DP-2"]), "DP-2");
    }

    function test_a_focused_screen_the_shell_cannot_see_falls_back_to_the_first() {
        // Compositor.focusedScreenName is empty when Hyprland is not there at
        // all, and can name a screen that has just been unplugged. Neither is a
        // reason to open nothing: a drawer that silently refuses to appear is
        // #81 again.
        compare(policy.openOn("", ["eDP-1", "DP-2"]), "eDP-1");
        compare(policy.openOn("HDMI-A-1", ["eDP-1", "DP-2"]), "eDP-1");
    }

    function test_no_screens_is_no_drawer() {
        compare(policy.openOn("eDP-1", []), "");
    }

    // --- hotplug -------------------------------------------------------------

    function test_an_open_drawer_does_not_survive_losing_its_screen() {
        verify(!policy.survivesScreenChange("DP-2", ["eDP-1", "DP-2"], ["eDP-1"]));
    }

    function test_an_open_drawer_does_not_survive_a_hotplug_it_was_not_on_either() {
        // #22 §3: hotplug destroys and recreates every per-screen surface, and
        // the drawer's anchor moves with the geometry underneath it. Closing is
        // the reset the ticket asks for — a drawer left open across a monitor
        // change is anchored to a layout that no longer exists.
        verify(!policy.survivesScreenChange("eDP-1", ["eDP-1"], ["eDP-1", "DP-2"]));
    }

    function test_a_screen_list_that_only_reordered_is_not_a_hotplug() {
        // Quickshell re-emits the list for reasons that are not a plug being
        // moved. Closing the drawer under the user's hand for one of those
        // would be the bug the reset is meant to prevent.
        verify(policy.survivesScreenChange("DP-2", ["eDP-1", "DP-2"], ["DP-2", "eDP-1"]));
    }

    // --- motion --------------------------------------------------------------

    function test_the_cross_drawer_swap_starts_the_entrance_late() {
        // #27 variant A: out 140, in 240 starting at +100ms — about 40ms of
        // overlap, which is what keeps the fog from reading as empty between
        // two drawers.
        compare(policy.crossfadeDelay(false), 100);
    }

    function test_reduced_effects_takes_the_overlap_out() {
        // "All motion collapses to opacity-only 140 crossfades" (#27) — a
        // delay is a stagger, and the ladder's rung 3 has none of those. The
        // durations either side of this are Theme's (Core/EffectsPolicy.qml);
        // the delay is the one timing this file owns.
        compare(policy.crossfadeDelay(true), 0);
    }

    function test_the_entrance_settles_one_percent_and_only_when_transforms_run() {
        compare(policy.entryScale(true), 0.99);
        compare(policy.entryScale(false), 1.0);
    }

    // --- what the log says ---------------------------------------------------

    function test_every_state_change_says_which_drawer_and_why() {
        // tools/drawer-harness.sh greps for exactly these, so the wording is
        // the contract rather than a nicety (#81).
        compare(policy.opened("session", "DP-2"), "session opened on DP-2");
        compare(policy.closed("session", "toggle"), "session closed (toggle)");
        compare(policy.closed("session", ""), "session closed (request)");
        compare(policy.switched("session", "launcher"), "session → launcher");
    }
}
