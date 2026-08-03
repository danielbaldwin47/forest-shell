// What decides whether the bar is on screen (#70).
//
// Three hide reasons converge on one property — the `bar.autoHide` pointer
// reveal that #35 shipped, a fullscreen window on the focused screen, and an
// explicit hide over IPC or the global shortcut. The tests below are mostly
// about the order they resolve in, and about the two traps that order has:
// a fullscreen on one monitor must not clear the bar off the others, and an
// override must never be a state the user cannot get back out of.
import QtQuick
import QtTest
import "../Core"
import "../Surfaces/Bar"

TestCase {
    name: "BarVisibilityPolicy"

    BarVisibilityPolicy { id: policy }
    SurfaceBusPolicy { id: bus }

    // `{ autoHide, hovering, lingering, override, fullscreen, focusedScreen }`,
    // with the shipped defaults — pinned bar, pointer elsewhere, nobody has
    // pressed anything, no fullscreen.
    function ctx(over) {
        const c = policy.context(false, false, false, "auto", false, true);
        for (const key in (over || {}))
            c[key] = over[key];
        return c;
    }

    function test_the_default_bar_is_shown_and_reserves_its_strip() {
        // The shipped default is `autoHide: false`: a pinned bar that the
        // compositor tiles under.
        verify(policy.revealed(ctx()));
        verify(policy.reservesSpace(ctx()));
        compare(policy.reason(ctx()), "pinned");
        // Nothing to reveal, so the edge strip is not armed.
        verify(!policy.hoverArms(ctx()));
    }

    // --- the #68 behaviour, unchanged ----------------------------------------

    function test_autohide_still_hides_and_the_pointer_still_reveals() {
        // The regression fence around the refactor: #35's auto-hide is a
        // hidden bar, a hover that reveals it, and a linger that keeps it a
        // beat after the pointer leaves so crossing it does not make it flap.
        verify(!policy.revealed(ctx({ autoHide: true })));
        verify(policy.revealed(ctx({ autoHide: true, hovering: true })));
        verify(policy.revealed(ctx({ autoHide: true, lingering: true })));
        verify(policy.hoverArms(ctx({ autoHide: true })));
    }

    function test_an_autohiding_bar_never_reserves_space() {
        // That is the point of it — and it stays true while the pointer has
        // it revealed, because a reserved zone that appeared and vanished
        // under the pointer would reflow every tiled window on hover.
        verify(!policy.reservesSpace(ctx({ autoHide: true })));
        verify(!policy.reservesSpace(ctx({ autoHide: true, hovering: true })));
    }

    // --- fullscreen (#70's decision) -----------------------------------------

    function test_a_fullscreen_window_hides_the_bar() {
        // Decided in #70 and implemented without a knob: the bar is
        // WlrLayer.Top, which Hyprland draws above a fullscreen window, and a
        // fullscreen surface ignores exclusive zones — so a pinned bar takes
        // its strip out of a fullscreen video and gives nothing back.
        verify(!policy.revealed(ctx({ fullscreen: true })));
        compare(policy.reason(ctx({ fullscreen: true })), "fullscreen");
    }

    function test_the_pointer_reveals_a_fullscreen_hidden_bar() {
        // Same edge strip as auto-hide, which is how every video player
        // behaves and part of why the knob was not needed.
        verify(policy.hoverArms(ctx({ fullscreen: true })));
        verify(policy.revealed(ctx({ fullscreen: true, hovering: true })));
    }

    function test_fullscreen_on_another_monitor_leaves_this_bar_alone() {
        // The multi-monitor trap. `Compositor.focusedFullscreen` is one global
        // read off the focused workspace, so ungated it would clear the bar
        // off every screen when one goes fullscreen (#22 §1).
        verify(policy.revealed(ctx({ fullscreen: true, focusedScreen: false })));
        compare(policy.reason(ctx({ fullscreen: true, focusedScreen: false })),
                "pinned");
    }

    function test_fullscreen_gives_back_the_exclusive_zone() {
        // For the mode that is not true fullscreen. `focusedFullscreen` reads
        // the workspace's `hasfullscreen`, which Hyprland also sets for
        // maximize — and a maximized window *does* honour exclusive zones, so
        // keeping the band would leave the window stopping short of a strip
        // with nothing drawn in it.
        verify(!policy.reservesSpace(ctx({ fullscreen: true })));
        // And not on the monitors that are not showing it.
        verify(policy.reservesSpace(ctx({ fullscreen: true,
                                          focusedScreen: false })));
    }

    // --- the override, which is the IPC door and the keybind -----------------

    function test_an_explicit_hide_hides_a_pinned_bar_and_frees_its_space() {
        const hidden = ctx({ override: "hidden" });
        verify(!policy.revealed(hidden));
        // Unlike fullscreen: the user asked for the bar to be gone, so the
        // band it was reserving goes back to the windows.
        verify(!policy.reservesSpace(hidden));
        compare(policy.reason(hidden), "override");
    }

    function test_an_explicit_hide_is_not_undone_by_the_pointer() {
        // An explicit hide is intent. Reaching for something at the top of the
        // screen must not put the bar back, or the keybind reads as broken
        // exactly when it was used.
        verify(!policy.hoverArms(ctx({ override: "hidden" })));
        verify(!policy.revealed(ctx({ override: "hidden", hovering: true })));
    }

    function test_an_explicit_show_beats_both_hide_reasons() {
        // The escape hatch that let #70 reject the fullscreen knob: a user who
        // wants the bar over a fullscreen window has a keybind for it.
        verify(policy.revealed(ctx({ override: "shown", autoHide: true })));
        verify(policy.revealed(ctx({ override: "shown", fullscreen: true })));
    }

    // --- toggle --------------------------------------------------------------

    function test_toggle_flips_what_is_on_screen_on_the_first_press() {
        // Not a cycle through the three override values: the first press does
        // the visible thing, whatever put the bar where it is.
        const cases = [
            ctx(),
            ctx({ autoHide: true }),
            ctx({ autoHide: true, hovering: true }),
            ctx({ fullscreen: true }),
            ctx({ override: "hidden" }),
            ctx({ override: "shown", autoHide: true })
        ];
        for (const before of cases) {
            const after = ctx(before);
            after.override = policy.next(before);
            compare(policy.revealed(after), !policy.revealed(before),
                    "toggle did not flip: " + JSON.stringify(before));
        }
    }

    function test_two_toggles_restore_the_bar_and_release_the_override() {
        // The trap this avoids: a bar hidden by keybind while fullscreen, then
        // toggled back, must not be left pinned to `shown` — or leaving
        // fullscreen would find the bar stuck on top of nothing, held there by
        // a press the user has forgotten making.
        const start = ctx({ fullscreen: true });
        const once = ctx(start);
        once.override = policy.next(start);
        compare(once.override, "shown");

        const twice = ctx(once);
        twice.override = policy.next(once);
        compare(twice.override, "auto");
        compare(policy.revealed(twice), policy.revealed(start));
    }

    function test_toggling_a_pinned_bar_twice_returns_it_to_auto() {
        const start = ctx();
        const once = ctx(start);
        once.override = policy.next(start);
        compare(once.override, "hidden");

        const twice = ctx(once);
        twice.override = policy.next(once);
        compare(twice.override, "auto");
        verify(policy.revealed(twice));
    }

    function test_every_override_the_policy_produces_is_one_it_declares() {
        // `override` is a string on the surface and arrives from IPC, so the
        // set is worth pinning: a typo'd value would read as `auto` and the
        // bar would silently ignore the keybind.
        const seen = ["auto", "shown", "hidden"];
        compare(policy.overrides, seen);
        for (const over of seen)
            verify(policy.overrides.indexOf(policy.next(ctx({ override: over })))
                   >= 0);
    }

    function test_an_override_off_the_wire_is_normalised_before_it_is_believed() {
        // `override` arrives as a string over IPC. Without this a typo'd value
        // would read as `auto` everywhere downstream, so the door would answer
        // 0 and the bar would not move — the worst of both.
        for (const over of policy.overrides)
            compare(policy.normalize(over), over);
        compare(policy.normalize("Shown"), "auto");
        compare(policy.normalize(""), "auto");
        compare(policy.normalize("toggle"), "auto");
    }

    // --- the door itself -----------------------------------------------------

    function test_no_ipc_verb_on_the_bar_is_a_name_the_cli_eats() {
        // The bug closed PR #67 would have shipped: it declared
        // `function show()`, and `qs ipc call bar show` is parsed as
        // `qs ipc show` — the target listing, exit 0, nothing called (#77).
        // #70 asked for `show` in as many words, so this is the one check that
        // stops the acceptance criterion being met on paper and not in a
        // terminal.
        for (const verb of policy.verbs)
            verify(bus.callable(verb), "bar advertises a verb the CLI eats: "
                   + verb);
        verify(policy.verbs.indexOf("show") < 0);
        verify(policy.verbs.indexOf("reveal") >= 0);
    }

    function test_the_bar_target_is_not_a_name_the_cli_eats_either() {
        verify(bus.reservedVerbs.indexOf("bar") < 0);
        // And it is not one of the surfaces on the bus, which would be two
        // IpcHandlers on one target and one of them silently never answering.
        verify(!bus.known("bar"));
    }

    function test_the_log_line_names_the_reason() {
        // #81: a lifecycle with no log line gave one bug two candidate causes
        // for a week. With three hide reasons on one property, "the bar is not
        // there" has to say which one did it.
        compare(policy.describe(ctx()), "shown (pinned)");
        compare(policy.describe(ctx({ autoHide: true })), "hidden (autohide)");
        compare(policy.describe(ctx({ fullscreen: true })), "hidden (fullscreen)");
        compare(policy.describe(ctx({ autoHide: true, hovering: true })),
                "shown (hover)");
        compare(policy.describe(ctx({ autoHide: true, lingering: true })),
                "shown (linger)");
        compare(policy.describe(ctx({ override: "hidden" })), "hidden (override)");
    }
}
