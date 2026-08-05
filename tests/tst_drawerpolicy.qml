// The shared drawer window's decisions (#38): which drawer is open, on which
// screen, what a hotplug does to that, and the timings the cross-drawer swap
// needs that are not already a design-system step.
//
// The window itself is a `PanelWindow` and so cannot be loaded here. That half
// is driven over IPC in a nested compositor by tools/drawer-harness.sh, clicked
// at by tools/bar-click-harness.sh, and photographed by
// tools/capture-harness.sh --surface drawer.
import QtQuick
import QtTest
import "../Surfaces/Drawers"

TestCase {
    name: "DrawerPolicy"

    DrawerPolicy { id: policy }

    /// A shell with one drawer in it, which is what this was before the
    /// launcher landed (#39) and what it is again for anyone who builds a
    /// tenant list by hand. Kept so the single-drawer edges — a toggle that
    /// closes rather than swaps — stay reachable once more tenants land.
    DrawerPolicy {
        id: oneDrawer
        tenants: ["session"]
    }

    // --- which drawer is open ------------------------------------------------

    function test_a_toggle_opens_what_is_closed_and_closes_what_is_open() {
        compare(policy.next("", "session"), "session");
        compare(policy.next("session", "session"), "");
        compare(policy.next("", "launcher"), "launcher");
        compare(policy.next("launcher", "launcher"), "");
        compare(oneDrawer.next("session", "session"), "");
    }

    function test_asking_for_a_second_drawer_swaps_rather_than_stacking() {
        // One window, one name: two drawers open at once is the state this
        // topology exists to make unrepresentable (#12).
        compare(policy.next("session", "launcher"), "launcher");
        compare(policy.next("launcher", "session"), "session");
    }

    function test_the_launcher_is_a_drawer() {
        // #39 lands in the shared window rather than in a surface of its own,
        // which is what makes the swap above a transition instead of two
        // windows racing for focus.
        compare(policy.known("launcher"), true);
        compare(oneDrawer.known("launcher"), false);
    }

    function test_the_notification_centre_is_a_drawer() {
        // #43 is the fifth tenant of the shared window — popups keep their own
        // (Surfaces/Notifications/Popups.qml), because a toast has to appear
        // over a fullscreen window and a drawer never does.
        compare(policy.known("notificationcenter"), true);
        compare(policy.next("", "notificationcenter"), "notificationcenter");
        compare(policy.next("notificationcenter", "notificationcenter"), "");
        // The swap, in the direction the bar makes easy: the indicator is two
        // modules from the control-centre button.
        compare(policy.next("launcher", "notificationcenter"), "notificationcenter");
        compare(policy.next("notificationcenter", "session"), "session");
    }

    function test_a_toggle_for_a_drawer_nobody_built_changes_nothing() {
        // The bus already logs the miss (Core/SurfaceBusPolicy.qml). What must
        // not happen is the open drawer closing because someone pressed a
        // button for a surface that has not landed.
        //
        // The name was `dashboard` until #49 landed it, which is the hazard
        // this check has to be written against: an unbuilt name that quietly
        // becomes a built one turns this into "a toggle for a drawer that
        // exists does nothing", which is the opposite claim and passes for the
        // wrong reason. `notepad` is not on any build plan; move it again if it
        // ever is.
        compare(policy.next("session", "notepad"), "session");
        compare(policy.next("", "notepad"), "");
    }

    function test_the_dashboard_is_the_fifth_tenant() {
        // #49, and the reason the check above had to move: the clock opens it,
        // so a toggle for it now has to *change* something.
        verify(policy.known("dashboard"));
        compare(policy.next("", "dashboard"), "dashboard");
        compare(policy.next("dashboard", "dashboard"), "");
        // And it swaps with its neighbours rather than stacking under them.
        compare(policy.next("controlcenter", "dashboard"), "dashboard");
        compare(policy.next("dashboard", "launcher"), "launcher");
    }

    // --- a click on the bar --------------------------------------------------
    //
    // #187's table. Worth saying once, here, what these can and cannot show:
    // the defect #187 reported was a click that never arrived, and no test on
    // this side of the line can see that — the state machine above was already
    // correct and passed while the shell was broken. What is checked here is
    // the routing the fix adds. That the click arrives at all is
    // tools/bar-click-harness.sh, at seam 2.

    function test_a_bar_click_with_nothing_open_routes_nowhere() {
        // With no drawer open the bar is just a bar: dead space does nothing,
        // and neither does a control.
        compare(policy.barClick("", ""), "none");
        compare(policy.barClick("", "mute"), "none");
    }

    function test_a_door_opens_its_drawer_with_nothing_open() {
        // The everyday case, and the one this table broke on its way in: every
        // bar click routes through here now, doors included, so a door has to
        // answer "toggle" whether or not something is already open. Answering
        // "none" made the launcher button dead on an idle bar — caught at
        // seam 2, by tools/bar-click-harness.sh check 1, which exists to make
        // exactly this falsifiable.
        compare(policy.barClick("", "launcher"), "toggle");
        compare(policy.next("", "launcher"), "launcher");
    }

    function test_a_drawers_own_door_closes_it() {
        // Row 1: the button that opened it closes it. Through `next()`, which
        // is what makes this the same gesture as the keybind rather than a
        // second spelling of it.
        compare(policy.barClick("controlcenter", "controlcenter"), "toggle");
        compare(policy.next("controlcenter", "controlcenter"), "");
    }

    function test_another_drawers_door_swaps() {
        // Row 2, and the reporter's own case: control centre open, launcher
        // button clicked, one gesture.
        compare(policy.barClick("controlcenter", "launcher"), "toggle");
        compare(policy.next("controlcenter", "launcher"), "launcher");
    }

    function test_dead_space_dismisses() {
        // Row 3. `""` is what the bar sends when nothing claimed the click —
        // the gaps, and the indicators that are readouts rather than buttons.
        compare(policy.barClick("controlcenter", ""), "dismiss");
        compare(policy.barClick("launcher", ""), "dismiss");
    }

    function test_an_interactive_control_leaves_the_drawer_alone() {
        // Row 4, and the row worth being explicit about: mute, the media
        // transport, the keyboard layout and the recorder are reached for
        // *while* a panel is open. Closing the panel under the user for using
        // one would be a worse bug than the one this ticket fixes.
        compare(policy.barClick("controlcenter", "mute"), "none");
        compare(policy.barClick("controlcenter", "media"), "none");
        compare(policy.barClick("dashboard", "recorder"), "none");
    }

    function test_a_door_for_a_drawer_nobody_built_is_not_a_dismissal() {
        // The hazard the toggle test above is written against, on this table
        // too: an unbuilt name must not fall through to "dismiss", or a bar
        // button for a surface that has not landed would close the drawer that
        // is open — which is exactly what #37 says a missing surface must not
        // do. `notepad` is not on any build plan.
        compare(policy.barClick("session", "notepad"), "none");
    }

    // --- a click on a bar indicator ------------------------------------------
    //
    // #184's table, which is #187's one column wider. The extra column is what
    // is *drilled*, and it is why this is a second function rather than a fifth
    // row above: "the wifi glyph was clicked" has three different answers
    // depending on the inside of a drawer that `barClick` is deliberately blind
    // to. That the click reaches the glyph at all is seam 2 again — this
    // ticket's own harness, tools/bar-indicator-harness.sh.

    function test_an_indicator_opens_the_control_centre_already_drilled() {
        // Nothing open: one gesture instead of the two it takes today (open
        // the control centre, then expand the tile).
        compare(policy.barIndicatorClick("", "", "wifi"), "open");
        compare(policy.barIndicatorClick("", "", "bluetooth"), "open");
    }

    function test_an_indicator_swaps_from_another_drawer_in_one_gesture() {
        // The launcher is open and the wifi glyph is clicked. Row 2 of #187's
        // table said a door swaps rather than closing and reopening; a glyph
        // with a panel behind it is a door, so it swaps too — and arrives
        // drilled, which is the whole point of it being this glyph and not the
        // control centre button.
        compare(policy.barIndicatorClick("launcher", "", "wifi"), "open");
        compare(policy.barIndicatorClick("dashboard", "", "audio"), "open");
    }

    function test_the_same_indicator_twice_closes_the_control_centre() {
        // The rule `next()` applies to drawers and `DrillInPolicy.next()`
        // applies to panels, applied here: the control that opened a thing
        // closes it, so no click is ever a no-op the user has to find another
        // way out of.
        compare(policy.barIndicatorClick("controlcenter", "wifi", "wifi"), "close");
        compare(policy.barIndicatorClick("controlcenter", "audio", "audio"), "close");
    }

    function test_a_different_indicator_swaps_the_panel_without_reopening() {
        // The control centre stays up and only its contents change — #27's
        // in-place step, at 140ms, rather than a 320ms drawer close followed by
        // a 320ms open. "drill" and not "open" is the whole difference.
        compare(policy.barIndicatorClick("controlcenter", "bluetooth", "wifi"), "drill");
        compare(policy.barIndicatorClick("controlcenter", "audio", "wifi"), "drill");
    }

    function test_an_indicator_clicked_at_the_control_centres_root_drills_in() {
        // Open but not drilled: `""` is the root and not a panel name, so it
        // can never equal what was asked for, and this lands on "drill"
        // without a special case.
        compare(policy.barIndicatorClick("controlcenter", "", "wifi"), "drill");
    }

    function test_an_indicator_with_no_panel_does_nothing_at_all() {
        // What the battery, brightness and system-monitor readouts resolve to
        // — `DrillInPolicy.panelForIndicator` answers `""` for all three. Not
        // "dismiss": they are not dead space, they are readouts the user did
        // not mean to press, and nothing about them should move a drawer.
        compare(policy.barIndicatorClick("", "", ""), "none");
        compare(policy.barIndicatorClick("controlcenter", "wifi", ""), "none");
        compare(policy.barIndicatorClick("launcher", "", ""), "none");
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
        // two drawers. What `reducedEffects` does to it is the ladder's
        // (`Theme.stagger`, checked in tests/tst_effectspolicy.qml); the value
        // is the one timing this file owns.
        compare(policy.crossfadeDelayMs, 100);
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
