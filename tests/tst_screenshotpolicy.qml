// The screenshot picker's decisions (#51): a drag in, a rectangle and an argv
// out.
//
// Seam 1 (CLAUDE.md). The surface next door is a layer window, a `Process` and
// a `grabToImage`; everything that could be *wrong* about a screenshot — which
// rectangle a backwards drag means, which window a click landed on, whether an
// edge snapped, what the file is called — is here, where a test can pose a
// three-window desktop that is not this one.
import QtQuick
import QtTest
import "../Services/Screenshot"

TestCase {
    name: "ScreenshotPolicy"

    ScreenshotPolicy { id: policy }

    // A desktop to pose against: the monitor this was measured on (eDP-1,
    // 1920x1080 native at scale 1.5 — so 1280x720 logical), and three windows
    // reported the way Hyprland reports them.
    readonly property var monitor: ({ x: 0, y: 0, width: 1920, height: 1080, scale: 1.5 })

    readonly property var desktop: [
        {
            title: "kitty", class: "kitty", mapped: true, hidden: false, monitor: 0,
            workspace: { id: 1, name: "1" }, at: [14, 58], size: [600, 400]
        },
        {
            title: "firefox", class: "firefox", mapped: true, hidden: false, monitor: 0,
            workspace: { id: 1, name: "1" }, at: [640, 58], size: [626, 648]
        },
        {
            title: "dialog", class: "kitty", mapped: true, hidden: false, monitor: 0,
            workspace: { id: 1, name: "1" }, at: [100, 100], size: [200, 150]
        }
    ]

    // --- normalise ------------------------------------------------------------

    function test_a_drag_is_the_same_rectangle_whichever_way_it_was_drawn() {
        const forward = policy.normalise(100, 100, 300, 250);
        const backward = policy.normalise(300, 250, 100, 100);
        compare(forward.x, 100);
        compare(forward.y, 100);
        compare(forward.width, 200);
        compare(forward.height, 150);
        compare(JSON.stringify(backward), JSON.stringify(forward));
    }

    function test_a_drag_up_and_to_the_left_is_not_a_negative_rectangle() {
        // The case a naive `x1 - x0` gets wrong, and the one people actually do
        // when selecting something in the bottom-right corner.
        const rect = policy.normalise(500, 400, 200, 150);
        compare(rect.x, 200);
        compare(rect.y, 150);
        compare(rect.width, 300);
        compare(rect.height, 250);
    }

    function test_a_boundary_never_lands_on_half_a_pixel() {
        // The pointer arrives as a real. A region edge at x.5 is a row of
        // blended pixels in the saved file.
        const rect = policy.normalise(10.4, 20.6, 110.5, 120.4);
        compare(rect.x, 10);
        compare(rect.y, 21);
        compare(rect.x % 1, 0);
        compare(rect.width % 1, 0);
        compare(rect.height % 1, 0);
    }

    // --- bounds ---------------------------------------------------------------

    function test_the_monitors_size_is_native_and_the_bounds_are_logical() {
        // The one division in the file. Getting it backwards clamps every
        // selection to the top-left 44% of the screen.
        const box = policy.bounds(monitor);
        compare(box.x, 0);
        compare(box.y, 0);
        compare(box.width, 1280);
        compare(box.height, 720);
    }

    function test_a_monitor_reporting_no_scale_is_taken_as_one_not_as_zero() {
        const box = policy.bounds({ x: 0, y: 0, width: 800, height: 600 });
        compare(box.width, 800);
        compare(box.height, 600);
    }

    function test_a_second_monitor_keeps_its_layout_offset() {
        // `x`/`y` are already layout coordinates and must not be divided.
        const box = policy.bounds({ x: 1280, y: 0, width: 2560, height: 1440, scale: 2 });
        compare(box.x, 1280);
        compare(box.width, 1280);
        compare(box.height, 720);
    }

    // --- clamp ----------------------------------------------------------------

    function test_a_drag_off_the_screen_is_trimmed_not_slid() {
        // Clamping only the origin would hand back a region the pointer never
        // covered — same size, wrong place.
        const box = policy.bounds(monitor);
        const rect = policy.clamp({ x: 1200, y: 650, width: 300, height: 200 }, box);
        compare(rect.x, 1200);
        compare(rect.y, 650);
        compare(rect.width, 80);
        compare(rect.height, 70);
    }

    function test_a_drag_off_the_top_left_keeps_what_it_selected_on_the_other_side() {
        const box = policy.bounds(monitor);
        const rect = policy.clamp({ x: -50, y: -30, width: 200, height: 100 }, box);
        compare(rect.x, 0);
        compare(rect.y, 0);
        compare(rect.width, 150);
        compare(rect.height, 70);
    }

    function test_a_rectangle_entirely_off_the_screen_clamps_to_nothing() {
        const box = policy.bounds(monitor);
        const rect = policy.clamp({ x: 4000, y: 4000, width: 100, height: 100 }, box);
        compare(rect.width, 0);
        compare(rect.height, 0);
    }

    // --- a drag, or a click ---------------------------------------------------

    function test_a_click_is_not_a_region() {
        // A press and release at the "same" place still travels a few pixels on
        // a trackpad. Without the floor, every click captures stray pixels and
        // the window snapping looks broken.
        verify(!policy.isRegion(policy.normalise(300, 300, 302, 301)));
        verify(!policy.isRegion({ x: 0, y: 0, width: 40, height: 3 }));
        verify(policy.isRegion({ x: 0, y: 0, width: 40, height: 30 }));
    }

    function test_the_floor_applies_to_both_dimensions() {
        // A 400x2 sliver is as much "not what they meant" as a 2x2 one.
        verify(!policy.isRegion({ x: 0, y: 0, width: 400, height: 2 }));
        verify(!policy.isRegion({ x: 0, y: 0, width: 2, height: 400 }));
    }

    // --- windows --------------------------------------------------------------

    function test_the_desktops_windows_come_back_as_rectangles() {
        const rects = policy.windows(desktop, 1, 0);
        compare(rects.length, 3);
        compare(rects[0].x, 14);
        compare(rects[0].y, 58);
        compare(rects[0].width, 600);
        compare(rects[0].height, 400);
        compare(rects[0].title, "kitty");
    }

    function test_a_window_the_compositor_is_holding_but_not_showing_is_not_a_rectangle() {
        // Its `at`/`size` are stale, so snapping to it highlights empty desktop.
        const hidden = desktop.concat([{
            title: "stashed", class: "kitty", mapped: true, hidden: true, monitor: 0,
            workspace: { id: 1, name: "1" }, at: [0, 0], size: [400, 300]
        }, {
            title: "unmapped", class: "kitty", mapped: false, hidden: false, monitor: 0,
            workspace: { id: 1, name: "1" }, at: [0, 0], size: [400, 300]
        }]);
        compare(policy.windows(hidden, 1, 0).length, 3);
    }

    function test_another_workspaces_windows_are_rectangles_over_content_they_do_not_own() {
        const elsewhere = desktop.concat([{
            title: "other", class: "kitty", mapped: true, hidden: false, monitor: 0,
            workspace: { id: 7, name: "7" }, at: [0, 0], size: [400, 300]
        }]);
        compare(policy.windows(elsewhere, 1, 0).length, 3);
        compare(policy.windows(elsewhere, 7, 0).length, 1);
    }

    function test_the_output_next_door_is_filtered_out() {
        // Its coordinates land inside this monitor's picker.
        const twoScreens = desktop.concat([{
            title: "second screen", class: "kitty", mapped: true, hidden: false, monitor: 1,
            workspace: { id: 1, name: "1" }, at: [1300, 100], size: [400, 300]
        }]);
        compare(policy.windows(twoScreens, 1, 0).length, 3);
        compare(policy.windows(twoScreens, 1, 1).length, 1);
    }

    function test_a_zero_area_window_cannot_be_clicked_so_it_is_dropped() {
        // Left in, `hit()`'s smallest-wins rule would elect something with no
        // pixels in it.
        const degenerate = [{
            title: "nothing", class: "x", mapped: true, hidden: false, monitor: 0,
            workspace: { id: 1, name: "1" }, at: [10, 10], size: [0, 300]
        }];
        compare(policy.windows(degenerate, 1, 0).length, 0);
    }

    function test_an_empty_compositor_is_an_empty_list_not_a_crash() {
        compare(policy.windows([], 1, 0).length, 0);
        compare(policy.windows(null, 1, 0).length, 0);
        compare(policy.windows(undefined, 1, 0).length, 0);
    }

    // --- hit ------------------------------------------------------------------

    function test_a_click_lands_on_the_window_under_it() {
        const rects = policy.windows(desktop, 1, 0);
        const got = policy.hit(rects, 700, 300);
        verify(got !== null);
        compare(got.title, "firefox");
    }

    function test_a_click_where_two_windows_overlap_takes_the_smaller_one() {
        // The dialog sits inside the terminal. "On top" is not answerable from
        // a focus-ordered list, but the smaller rectangle is the front one in
        // every case that matters — a dialog over its parent, a floating window
        // over a tiled one.
        const rects = policy.windows(desktop, 1, 0);
        const got = policy.hit(rects, 150, 150);
        verify(got !== null);
        compare(got.title, "dialog");
    }

    function test_a_click_on_empty_desktop_hits_nothing() {
        const rects = policy.windows(desktop, 1, 0);
        // Below the terminal and left of firefox — the one genuinely bare
        // corner of this desktop.
        compare(policy.hit(rects, 300, 600), null);
        compare(policy.hit([], 100, 100), null);
    }

    function test_a_windows_far_edge_is_outside_it() {
        // Half-open, like every other rectangle here: a window at x=14 of width
        // 600 owns 14..613, and 614 is the next thing along.
        const rects = policy.windows([desktop[0]], 1, 0);
        verify(policy.hit(rects, 14, 58) !== null);
        compare(policy.hit(rects, 614, 58), null);
    }

    // --- snapping -------------------------------------------------------------

    function test_an_edge_drawn_near_a_window_edge_takes_the_windows_edge() {
        const rects = policy.windows(desktop, 1, 0);
        // Drawn 5px inside the terminal's top-left, 4px past its bottom-right.
        const snapped = policy.snap({ x: 19, y: 63, width: 591, height: 391 }, rects, null);
        compare(snapped.x, 14);
        compare(snapped.y, 58);
        compare(snapped.x + snapped.width, 614);
        compare(snapped.y + snapped.height, 458);
    }

    function test_each_edge_snaps_on_its_own_so_a_region_can_span_two_windows() {
        // The common ask: from one window's left edge to another's right. A
        // whole-rectangle snap could only ever offer one window at a time.
        const rects = policy.windows(desktop, 1, 0);
        const snapped = policy.snap({ x: 18, y: 300, width: 1248, height: 100 }, rects, null);
        compare(snapped.x, 14);                       // the terminal's left
        compare(snapped.x + snapped.width, 1266);     // firefox's right
    }

    function test_a_deliberate_margin_around_a_window_survives() {
        // 20px clear of every edge is further than the snap distance, so it is
        // taken as meant rather than swallowed. Note the right edge stops at
        // 580 and not at the terminal's own 634: that would be 6px from
        // firefox's left edge, and snapping to it would be correct.
        const rects = policy.windows(desktop, 1, 0);
        const drawn = { x: -6, y: 38, width: 586, height: 440 };
        const snapped = policy.snap(drawn, rects, null);
        compare(snapped.x, drawn.x);
        compare(snapped.width, drawn.width);
    }

    function test_the_screens_own_edges_are_snap_candidates_too() {
        // "Flush with the top of the screen" is the same gesture.
        const box = policy.bounds(monitor);
        const snapped = policy.snap({ x: 4, y: 5, width: 1270, height: 710 }, [], box);
        compare(snapped.x, 0);
        compare(snapped.y, 0);
        compare(snapped.width, 1280);
        compare(snapped.height, 720);
    }

    function test_a_snap_that_would_collapse_the_region_is_refused() {
        // Both edges of a narrow selection can find the same candidate. A
        // zero-width rectangle is not what the drag asked for.
        const rects = [{ x: 100, y: 100, width: 200, height: 150 }];
        const drawn = { x: 96, y: 300, width: 9, height: 40 };
        const snapped = policy.snap(drawn, rects, null);
        compare(snapped.width, drawn.width);
        compare(snapped.x, drawn.x);
    }

    function test_snapping_nothing_to_nothing_returns_what_it_was_given() {
        const drawn = { x: 40, y: 50, width: 200, height: 100 };
        const snapped = policy.snap(drawn, [], null);
        compare(snapped.x, 40);
        compare(snapped.y, 50);
        compare(snapped.width, 200);
        compare(snapped.height, 100);
    }

    // --- where it lands -------------------------------------------------------

    function test_the_default_directory_is_the_one_the_ticket_names() {
        compare(policy.directory("", "/home/x"), "/home/x/Pictures/Screenshots");
        compare(policy.directory(null, "/home/x"), "/home/x/Pictures/Screenshots");
        compare(policy.directory("   ", "/home/x"), "/home/x/Pictures/Screenshots");
    }

    function test_a_tilde_is_expanded_here_because_nothing_downstream_is_a_shell() {
        // `Process` takes an argv. A literal `~/Pictures` becomes a directory
        // called `~`, and it is only ever found much later.
        compare(policy.directory("~/Shots", "/home/x"), "/home/x/Shots");
        compare(policy.directory("~", "/home/x"), "/home/x");
        // Not a home reference — a real relative-looking name is left alone.
        compare(policy.directory("/mnt/big/shots", "/home/x"), "/mnt/big/shots");
        compare(policy.directory("~notauser/shots", "/home/x"), "~notauser/shots");
    }

    function test_a_file_name_sorts_and_is_free_of_hostile_characters() {
        const name = policy.filename(new Date(2026, 7, 3, 4, 5, 6));
        compare(name, "forest-2026-08-03T04-05-06.png");
        verify(name.indexOf(":") < 0);
        verify(name.indexOf(" ") < 0);
    }

    function test_a_path_joins_with_exactly_one_slash() {
        compare(policy.path("/home/x/Shots", "a.png"), "/home/x/Shots/a.png");
        compare(policy.path("/home/x/Shots/", "a.png"), "/home/x/Shots/a.png");
    }

    function test_the_output_raster_is_native_because_the_freeze_is() {
        // A grab that asked for the logical size would resample a 1.5x
        // screenshot down to 1x — a soft picture of a sharp screen.
        const size = policy.nativeSize({ x: 0, y: 0, width: 400, height: 300 }, 1.5);
        compare(size.width, 600);
        compare(size.height, 450);
    }

    function test_a_region_never_rasterises_to_nothing() {
        const size = policy.nativeSize({ x: 0, y: 0, width: 0, height: 0 }, 1.5);
        compare(size.width, 1);
        compare(size.height, 1);
    }

    // --- the tools ------------------------------------------------------------

    function test_the_freeze_captures_the_whole_output_without_the_cursor() {
        // The cursor is over the picker, not over the thing being photographed.
        const argv = policy.freezeArgv("eDP-1", "/tmp/f.png", "");
        compare(JSON.stringify(argv), JSON.stringify(["grim", "-o", "eDP-1", "/tmp/f.png"]));
        verify(argv.indexOf("-c") < 0);
    }

    function test_the_freeze_can_be_stood_in_for_because_grim_hangs_under_test() {
        // Seam 2 runs in a nested compositor where grim does not fail but
        // *hangs*, waiting for a frame that compositor never presents. The
        // override is how the harness gets past the one step it cannot run.
        const argv = policy.freezeArgv("eDP-1", "/tmp/f.png", "cp /fixtures/a.png");
        compare(argv[0], "sh");
        compare(argv[1], "-c");
        // The destination goes in as an argument, never interpolated into the
        // script — the same rule as the clipboard argv.
        verify(argv[2].indexOf("$1") >= 0);
        verify(argv[2].indexOf("/tmp/f.png") < 0);
        compare(argv[argv.length - 1], "/tmp/f.png");
        verify(argv.indexOf("grim") < 0);
    }

    function test_a_blank_override_is_not_an_override() {
        // Otherwise an env var that is merely *set* would silently disable the
        // real capture.
        compare(policy.freezeArgv("eDP-1", "/tmp/f.png", "   ")[0], "grim");
        compare(policy.freezeArgv("eDP-1", "/tmp/f.png", null)[0], "grim");
        compare(policy.freezeArgv("eDP-1", "/tmp/f.png", undefined)[0], "grim");
    }

    function test_a_freeze_that_never_answers_has_a_deadline() {
        // The failure this exists for is a hang, not an error: without it the
        // picker sits neither open nor closed and every later press answers
        // "already open" with nothing in the log saying why.
        verify(policy.freezeTimeoutMs > 0);
        verify(policy.freezeTimedOut().indexOf(String(policy.freezeTimeoutMs)) >= 0);
        verify(policy.freezeTimedOut().indexOf("giving up") >= 0);
    }

    function test_the_clipboard_argv_passes_the_file_as_an_argument_not_in_the_script() {
        // A path with a space or a quote in it must not be able to become
        // another command. The script names `$1`; the path is argv[2].
        const argv = policy.copyArgv("/home/x/Shots/a b.png");
        compare(argv[0], "sh");
        compare(argv[1], "-c");
        verify(argv[2].indexOf("$1") >= 0);
        verify(argv[2].indexOf("a b.png") < 0);
        compare(argv[argv.length - 1], "/home/x/Shots/a b.png");
    }

    function test_the_editor_handoff_is_the_configured_tool() {
        compare(JSON.stringify(policy.editorArgv("swappy", "/tmp/a.png")),
                JSON.stringify(["swappy", "-f", "/tmp/a.png"]));
    }

    function test_an_empty_editor_is_off_rather_than_missing() {
        // "The user turned it off" and "it is configured and not installed" are
        // different outcomes and get different log lines.
        verify(!policy.wants(""));
        verify(!policy.wants("   "));
        verify(!policy.wants(null));
        verify(policy.wants("swappy"));
    }

    // --- what a harness reads -------------------------------------------------

    function test_every_outcome_says_which_one_it_was() {
        // #81: "the picker did not open" has four causes, and without these
        // they are one picture in the log.
        compare(policy.opened("eDP-1", 3), "picker opened on eDP-1 (3 windows to snap to)");
        compare(policy.opened("eDP-1", 1), "picker opened on eDP-1 (1 window to snap to)");
        compare(policy.alreadyOpen(), "picker already open — ignoring open");
        compare(policy.cancelled("escape"), "picker cancelled (escape)");
        compare(policy.cancelled(""), "picker cancelled (request)");
        compare(policy.freezeMissing(),
                "grim is not installed — the region picker needs it to freeze the screen");
        compare(policy.freezeFailed(1), "grim failed (exit 1) — no freeze, so no picker");
    }

    function test_a_selection_line_carries_the_rectangle_and_how_it_was_made() {
        compare(policy.selected({ x: 14, y: 58, width: 600, height: 400 }, "drag"),
                "selected 600x400 at 14,58 (drag)");
        compare(policy.selected({ x: 14, y: 58, width: 600, height: 400 }, "window: kitty"),
                "selected 600x400 at 14,58 (window: kitty)");
    }

    function test_the_degraded_clipboard_says_so_and_names_the_missing_tool() {
        // Someone who pressed the key and then pressed paste needs to know they
        // have a path and not a picture.
        const line = policy.copiedPathInstead("/home/x/a.png");
        verify(line.indexOf("wl-copy") >= 0);
        verify(line.indexOf("path") >= 0);
        compare(policy.copied("/home/x/a.png"),
                "copied the image to the clipboard (/home/x/a.png)");
    }

    function test_an_absent_editor_and_a_disabled_one_read_differently() {
        compare(policy.editorAbsent("swappy"),
                "swappy is not installed — skipping the edit handoff");
        compare(policy.editorOff(), "no editor configured — skipping the edit handoff");
        compare(policy.handedOff("swappy", "/tmp/a.png"), "handed /tmp/a.png to swappy");
    }

    function test_saving_reports_the_raster_it_wrote() {
        compare(policy.saved("/tmp/a.png", { width: 600, height: 450 }),
                "saved 600x450 to /tmp/a.png");
        compare(policy.saveFailed("/tmp/a.png"), "could not write /tmp/a.png");
    }

    /// #52: a drag handed to another service rather than saved.
    function test_a_handed_region_says_no_file_was_written() {
        const line = policy.handedRegion({ x: 10, y: 20, width: 640, height: 480 });
        verify(line.indexOf("640x480") >= 0);
        verify(line.indexOf("10,20") >= 0);
        verify(line.indexOf("no file written") >= 0);
        verify(line !== policy.saved("/tmp/a.png", { width: 640, height: 480 }));
    }
}
