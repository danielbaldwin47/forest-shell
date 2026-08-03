// Seam 1 (CLAUDE.md) for screen recording (#52).
//
// Every decision the recorder makes is in RecorderPolicy.qml, which imports
// nothing but QtQuick — so the two argvs, the engine choice, the fallback rule
// and the state machine are all poseable here without a compositor, a GPU, or
// either encoder being installed on the machine running the tests.
//
// The two argvs are the reason this file is long. `-f` is the framerate to one
// tool and the output file to the other, and nothing at any other seam would
// notice them being swapped: a wrong argv produces a tool that exits non-zero,
// which is indistinguishable from a machine without VAAPI.
import QtQuick
import QtTest
import "../Services/Recorder"

TestCase {
    id: suite
    name: "RecorderPolicy"

    RecorderPolicy { id: policy }

    readonly property var region: ({ x: 100, y: 50, width: 640, height: 480 })
    readonly property var bothPresent: ({ "gpu-screen-recorder": true, "wf-recorder": true })
    readonly property var onlyWf: ({ "gpu-screen-recorder": false, "wf-recorder": true })
    readonly property var onlyGsr: ({ "gpu-screen-recorder": true, "wf-recorder": false })
    readonly property var neither: ({ "gpu-screen-recorder": false, "wf-recorder": false })

    /// The index of a flag's argument, so a test can assert on pairs without
    /// pinning the order of the whole command line.
    function valueAfter(argv, flag) {
        const at = argv.indexOf(flag);
        return at < 0 || at + 1 >= argv.length ? null : argv[at + 1];
    }

    // --- engineFor -----------------------------------------------------------

    function test_auto_prefers_the_gpu_encoder_when_it_is_installed() {
        compare(policy.engineFor("auto", suite.bothPresent), "gpu-screen-recorder");
    }

    function test_auto_falls_to_wf_recorder_when_the_gpu_encoder_is_absent() {
        compare(policy.engineFor("auto", suite.onlyWf), "wf-recorder");
    }

    function test_an_unset_engine_behaves_as_auto() {
        compare(policy.engineFor("", suite.bothPresent), "gpu-screen-recorder");
        compare(policy.engineFor(undefined, suite.onlyWf), "wf-recorder");
    }

    function test_an_explicit_engine_wins_over_the_preference_order() {
        compare(policy.engineFor("wf-recorder", suite.bothPresent), "wf-recorder");
    }

    /// The setting is a preference about how to record, not a demand to fail:
    /// a machine configured for an encoder it does not have still records.
    function test_an_explicit_engine_that_is_missing_falls_through() {
        compare(policy.engineFor("gpu-screen-recorder", suite.onlyWf), "wf-recorder");
        compare(policy.engineFor("wf-recorder", suite.onlyGsr), "gpu-screen-recorder");
    }

    function test_no_encoder_installed_is_the_empty_string() {
        compare(policy.engineFor("auto", suite.neither), "");
        compare(policy.engineFor("gpu-screen-recorder", suite.neither), "");
    }

    function test_an_engine_name_nobody_has_heard_of_still_picks_something() {
        compare(policy.engineFor("ffmpeg", suite.bothPresent), "gpu-screen-recorder");
    }

    // --- shouldFallback ------------------------------------------------------

    function test_an_engine_that_never_started_falls_back() {
        // No `exited` signal at all in Quickshell 0.3.0 when the binary is
        // missing, so `started` false is the whole signal (#40).
        verify(policy.shouldFallback("gpu-screen-recorder", false, 0, 0));
    }

    function test_a_fast_non_zero_exit_is_a_failed_init_and_falls_back() {
        // The VAAPI case: installed, driver missing, gone in ~200ms.
        verify(policy.shouldFallback("gpu-screen-recorder", true, 1, 200));
    }

    function test_a_non_zero_exit_after_the_grace_window_does_not_fall_back() {
        // A recording that ran and broke. Retrying it would start a second
        // file minutes into the first one.
        verify(!policy.shouldFallback("gpu-screen-recorder", true, 1, 60000));
    }

    function test_a_clean_exit_inside_the_grace_window_does_not_fall_back() {
        // A recording stopped almost immediately is still a recording.
        verify(!policy.shouldFallback("gpu-screen-recorder", true, 0, 400));
    }

    function test_the_last_engine_has_nothing_to_fall_back_to() {
        verify(!policy.shouldFallback("wf-recorder", false, 0, 0));
        verify(!policy.shouldFallback("wf-recorder", true, 1, 100));
    }

    function test_fallbackFor_is_one_hop_and_then_stops() {
        compare(policy.fallbackFor("gpu-screen-recorder"), "wf-recorder");
        compare(policy.fallbackFor("wf-recorder"), "");
        compare(policy.fallbackFor("nonsense"), "");
    }

    // --- gsrArgv -------------------------------------------------------------

    function test_the_gpu_encoder_takes_the_output_file_with_dash_o() {
        const argv = policy.gsrArgv({ file: "/tmp/a.mp4", output: "eDP-1" });
        compare(suite.valueAfter(argv, "-o"), "/tmp/a.mp4");
    }

    function test_the_gpu_encoder_takes_the_framerate_with_dash_f() {
        const argv = policy.gsrArgv({ file: "/tmp/a.mp4", output: "eDP-1", framerate: 30 });
        compare(suite.valueAfter(argv, "-f"), "30");
    }

    function test_a_whole_screen_capture_names_the_monitor_after_dash_w() {
        const argv = policy.gsrArgv({ file: "/tmp/a.mp4", output: "eDP-1" });
        compare(suite.valueAfter(argv, "-w"), "eDP-1");
        compare(argv.indexOf("-region"), -1);
    }

    /// `-w region` is a literal, not a placeholder — see gsrArgv's comment.
    function test_a_region_capture_says_the_word_region_after_dash_w() {
        const argv = policy.gsrArgv({ file: "/tmp/a.mp4", output: "eDP-1",
                                      region: suite.region });
        compare(suite.valueAfter(argv, "-w"), "region");
        compare(suite.valueAfter(argv, "-region"), "640x480+100+50");
    }

    function test_the_gpu_encoder_gets_the_quality_preset_and_the_container() {
        const argv = policy.gsrArgv({ file: "/tmp/a.mkv", output: "eDP-1",
                                      quality: "ultra", container: "mkv" });
        compare(suite.valueAfter(argv, "-q"), "ultra");
        compare(suite.valueAfter(argv, "-c"), "mkv");
    }

    function test_desktop_audio_is_one_device_and_both_is_two() {
        const desktop = policy.gsrArgv({ file: "/tmp/a.mp4", audio: "desktop" });
        compare(desktop.filter(a => a === "-a").length, 1);
        compare(suite.valueAfter(desktop, "-a"), "default_output");

        const both = policy.gsrArgv({ file: "/tmp/a.mp4", audio: "both" });
        compare(both.filter(a => a === "-a").length, 2);
        verify(both.indexOf("default_output") > 0);
        verify(both.indexOf("default_input") > 0);
    }

    function test_no_audio_means_no_audio_flag_at_all() {
        const argv = policy.gsrArgv({ file: "/tmp/a.mp4", audio: "none" });
        compare(argv.indexOf("-a"), -1);
    }

    function test_the_gpu_encoder_is_the_first_word() {
        compare(policy.gsrArgv({ file: "/tmp/a.mp4" })[0], "gpu-screen-recorder");
    }

    // --- wfArgv --------------------------------------------------------------

    /// The one that would silently swap: `-f` is the *file* here and the
    /// framerate to the other tool.
    function test_wf_recorder_takes_the_output_file_with_dash_f() {
        const argv = policy.wfArgv({ file: "/tmp/a.mp4", output: "eDP-1" });
        compare(suite.valueAfter(argv, "-f"), "/tmp/a.mp4");
    }

    function test_wf_recorder_takes_the_monitor_with_dash_o() {
        const argv = policy.wfArgv({ file: "/tmp/a.mp4", output: "eDP-1" });
        compare(suite.valueAfter(argv, "-o"), "eDP-1");
    }

    function test_wf_recorder_takes_the_framerate_with_dash_r() {
        const argv = policy.wfArgv({ file: "/tmp/a.mp4", output: "eDP-1", framerate: 24 });
        compare(suite.valueAfter(argv, "-r"), "24");
    }

    function test_wf_recorder_geometry_is_grims_form() {
        const argv = policy.wfArgv({ file: "/tmp/a.mp4", output: "eDP-1",
                                     region: suite.region });
        compare(suite.valueAfter(argv, "-g"), "100,50 640x480");
    }

    function test_a_whole_screen_capture_passes_no_geometry() {
        const argv = policy.wfArgv({ file: "/tmp/a.mp4", output: "eDP-1" });
        compare(argv.indexOf("-g"), -1);
    }

    /// Four audio sources collapse to one switch, because the tool has one.
    function test_wf_recorder_audio_is_a_boolean() {
        verify(policy.wfArgv({ file: "/tmp/a.mp4", audio: "desktop" }).indexOf("--audio") > 0);
        verify(policy.wfArgv({ file: "/tmp/a.mp4", audio: "mic" }).indexOf("--audio") > 0);
        verify(policy.wfArgv({ file: "/tmp/a.mp4", audio: "both" }).indexOf("--audio") > 0);
        compare(policy.wfArgv({ file: "/tmp/a.mp4", audio: "none" }).indexOf("--audio"), -1);
    }

    /// The setting the fallback cannot honour, which is inaudible until
    /// playback — so it is said out loud rather than silently approximated.
    function test_only_wf_recorder_narrows_the_audio_setting() {
        verify(policy.audioIsNarrowed("wf-recorder", "mic"));
        verify(policy.audioIsNarrowed("wf-recorder", "both"));
        verify(!policy.audioIsNarrowed("wf-recorder", "desktop"));
        verify(!policy.audioIsNarrowed("wf-recorder", "none"));
        verify(!policy.audioIsNarrowed("gpu-screen-recorder", "both"));
    }

    function test_wf_recorder_gets_no_quality_flag() {
        const argv = policy.wfArgv({ file: "/tmp/a.mp4", quality: "ultra" });
        compare(argv.indexOf("-q"), -1);
    }

    // --- argv dispatch -------------------------------------------------------

    function test_argv_routes_by_engine_name() {
        compare(policy.argv("gpu-screen-recorder", { file: "/tmp/a.mp4" })[0],
                "gpu-screen-recorder");
        compare(policy.argv("wf-recorder", { file: "/tmp/a.mp4" })[0], "wf-recorder");
    }

    function test_argv_for_no_engine_is_empty_rather_than_a_bare_command() {
        compare(policy.argv("", { file: "/tmp/a.mp4" }).length, 0);
        compare(policy.argv("ffmpeg", { file: "/tmp/a.mp4" }).length, 0);
    }

    // --- launchArgv ----------------------------------------------------------
    //
    // Quickshell spawns children with SIGINT ignored, and an ignored-on-entry
    // signal cannot be trapped — so a bare encoder cannot be stopped at all.
    // See RecorderPolicy.signalReset. Measured by tools/recorder-harness.sh as
    // a stop that logged and did nothing.

    function test_the_encoder_is_launched_behind_a_signal_reset() {
        const argv = policy.launchArgv("gpu-screen-recorder", { file: "/tmp/a.mp4" }, true);
        compare(argv[0], "env");
        compare(argv[1], "--default-signal=INT");
        compare(argv[2], "gpu-screen-recorder");
    }

    /// `env` execs in place, so the pid the shell holds is still the encoder's
    /// and `signal()` reaches the right process — the prefix must therefore not
    /// disturb anything after it.
    function test_the_prefix_leaves_the_command_line_untouched() {
        const opts = { file: "/tmp/a.mp4", output: "eDP-1", framerate: 30 };
        const bare = policy.argv("gpu-screen-recorder", opts);
        const wrapped = policy.launchArgv("gpu-screen-recorder", opts, true);
        compare(wrapped.slice(2).join(" "), bare.join(" "));
    }

    /// A machine whose `env` is older than coreutils 9.2 still records; it just
    /// cannot stop cleanly, which the service warns about rather than hiding.
    function test_a_machine_without_the_reset_launches_the_encoder_bare() {
        const argv = policy.launchArgv("wf-recorder", { file: "/tmp/a.mp4" }, false);
        compare(argv[0], "wf-recorder");
    }

    function test_no_engine_is_still_an_empty_command_with_the_prefix_on() {
        compare(policy.launchArgv("", { file: "/tmp/a.mp4" }, true).length, 0);
    }

    function test_the_missing_reset_warning_says_what_breaks() {
        const line = policy.signalResetMissing();
        verify(line.indexOf("coreutils 9.2") >= 0);
        verify(line.indexOf("missing its index") >= 0);
    }

    // --- the region ----------------------------------------------------------

    function test_a_fractional_rectangle_becomes_integers() {
        const argv = policy.gsrArgv({ file: "/tmp/a.mp4",
                                      region: { x: 10.4, y: 20.6, width: 100.5, height: 200.2 } });
        // A literal "100.5" on a command line is a tool that refuses to parse.
        // Each number rounds on its own: the rectangle arrives from the picker
        // already integral (ScreenshotPolicy.normalise), so this is coercion
        // rather than geometry and there is no origin/extent pair to keep in
        // step.
        compare(suite.valueAfter(argv, "-region"), "101x200+10+21");
    }

    function test_odd_sides_are_trimmed_down_to_even() {
        const trimmed = policy.evenSides({ x: 3, y: 5, width: 641, height: 481 });
        compare(trimmed.width, 640);
        compare(trimmed.height, 480);
        // The origin is untouched: only the sides have to be even.
        compare(trimmed.x, 3);
        compare(trimmed.y, 5);
    }

    function test_even_sides_are_left_alone() {
        const same = policy.evenSides(suite.region);
        compare(same.width, 640);
        compare(same.height, 480);
    }

    function test_a_click_sized_region_is_not_a_region() {
        verify(!policy.isRegion({ x: 0, y: 0, width: 3, height: 200 }));
        verify(!policy.isRegion({ x: 0, y: 0, width: 200, height: 2 }));
        verify(policy.isRegion(suite.region));
    }

    // --- settings coercion ---------------------------------------------------

    function test_a_nonsense_framerate_becomes_the_default() {
        compare(policy.framerate(0), 60);
        compare(policy.framerate(-5), 60);
        compare(policy.framerate("banana"), 60);
        compare(policy.framerate(undefined), 60);
    }

    function test_an_absurd_framerate_is_capped_rather_than_refused() {
        compare(policy.framerate(100000), 240);
    }

    function test_a_framerate_is_rounded_because_argv_is_text() {
        compare(policy.framerate(29.97), 30);
    }

    function test_unknown_quality_container_and_audio_fall_to_defaults() {
        compare(policy.quality("cinematic"), "very_high");
        compare(policy.container("webm"), "mp4");
        compare(policy.audio("stereo"), "desktop");
    }

    function test_known_values_survive() {
        compare(policy.quality("medium"), "medium");
        compare(policy.container("mkv"), "mkv");
        compare(policy.audio("none"), "none");
    }

    // --- where it lands ------------------------------------------------------

    function test_an_unset_directory_is_videos_recordings_under_home() {
        compare(policy.directory("", "/home/x"), "/home/x/Videos/Recordings");
    }

    function test_a_tilde_is_expanded_here_because_nothing_runs_a_shell() {
        compare(policy.directory("~/Clips", "/home/x"), "/home/x/Clips");
        compare(policy.directory("~", "/home/x"), "/home/x");
    }

    function test_an_absolute_directory_is_left_alone() {
        compare(policy.directory("/mnt/video", "/home/x"), "/mnt/video");
    }

    function test_the_filename_carries_the_container_extension() {
        const when = new Date(2026, 7, 3, 4, 5, 6);
        compare(policy.filename(when, "mkv"), "forest-2026-08-03T04-05-06.mkv");
        compare(policy.filename(when, "mp4"), "forest-2026-08-03T04-05-06.mp4");
    }

    function test_path_does_not_double_the_separator() {
        compare(policy.path("/a/b", "c.mp4"), "/a/b/c.mp4");
        compare(policy.path("/a/b/", "c.mp4"), "/a/b/c.mp4");
    }

    // --- the readouts --------------------------------------------------------

    function test_duration_is_short_under_an_hour_and_long_over_it() {
        compare(policy.formatDuration(7000), "0:07");
        compare(policy.formatDuration(62000), "1:02");
        compare(policy.formatDuration(3723000), "1:02:03");
    }

    function test_duration_never_goes_backwards_past_zero() {
        compare(policy.formatDuration(-1), "0:00");
        compare(policy.formatDuration(undefined), "0:00");
    }

    function test_the_bar_says_nothing_while_idle() {
        compare(policy.barLabel(false, 9000), "");
        compare(policy.barLabel(true, 9000), "0:09");
    }

    function test_the_tile_names_the_engine_until_it_is_running() {
        compare(policy.tileDetail(false, 0, "gpu-screen-recorder", true), "GPU");
        compare(policy.tileDetail(false, 0, "wf-recorder", true), "Software");
        compare(policy.tileDetail(false, 0, "", false), "No recorder");
        compare(policy.tileDetail(true, 65000, "wf-recorder", true), "1:05");
    }

    // --- the state machine ---------------------------------------------------

    function test_a_press_only_starts_from_idle() {
        verify(policy.canStart("idle"));
        verify(!policy.canStart("starting"));
        verify(!policy.canStart("recording"));
        verify(!policy.canStart("stopping"));
    }

    /// Stopping something that is still starting has to work: the encoder has
    /// a subprocess by then, and a press in that gap must not be swallowed.
    function test_a_press_stops_from_starting_as_well_as_recording() {
        verify(policy.canStop("starting"));
        verify(policy.canStop("recording"));
        verify(!policy.canStop("idle"));
        verify(!policy.canStop("stopping"));
    }

    function test_the_shell_shows_itself_recording_from_the_first_press() {
        verify(policy.isActive("starting"));
        verify(policy.isActive("recording"));
        verify(!policy.isActive("stopping"));
        verify(!policy.isActive("idle"));
    }

    function test_the_happy_path_walks_all_four_states() {
        let at = "idle";
        compare(at = policy.nextState(at, "start"), "starting");
        compare(at = policy.nextState(at, "started"), "recording");
        compare(at = policy.nextState(at, "stop"), "stopping");
        compare(at = policy.nextState(at, "exited"), "idle");
    }

    function test_a_second_start_does_not_move_the_machine() {
        compare(policy.nextState("recording", "start"), "recording");
        compare(policy.nextState("starting", "start"), "starting");
    }

    /// An exit arriving in `idle` is a process that was already given up on —
    /// it must not push the machine backwards.
    function test_an_unexpected_event_leaves_the_state_alone() {
        compare(policy.nextState("idle", "stop"), "idle");
        compare(policy.nextState("idle", "started"), "idle");
        compare(policy.nextState("recording", "nonsense"), "recording");
    }

    function test_an_exit_from_any_state_lands_in_idle() {
        compare(policy.nextState("starting", "exited"), "idle");
        compare(policy.nextState("recording", "exited"), "idle");
        compare(policy.nextState("stopping", "exited"), "idle");
    }

    // --- the log lines a harness greps for -----------------------------------

    function test_the_fallback_line_names_both_engines_and_the_reason() {
        const missing = policy.fellBack("gpu-screen-recorder", "wf-recorder",
                                        policy.fallbackReason(false, 0));
        verify(missing.indexOf("gpu-screen-recorder") >= 0);
        verify(missing.indexOf("wf-recorder") >= 0);
        verify(missing.indexOf("not installed") >= 0);

        const broken = policy.fellBack("gpu-screen-recorder", "wf-recorder",
                                       policy.fallbackReason(true, 1));
        verify(broken.indexOf("failed to initialise") >= 0);
        verify(broken.indexOf("exit 1") >= 0);
    }

    function test_the_start_line_says_which_rectangle_and_which_engine() {
        const whole = policy.startingWith("wf-recorder", "/tmp/a.mp4", null);
        verify(whole.indexOf("the whole screen") >= 0);
        verify(whole.indexOf("wf-recorder") >= 0);
        verify(whole.indexOf("/tmp/a.mp4") >= 0);

        const part = policy.startingWith("gpu-screen-recorder", "/tmp/a.mp4", suite.region);
        verify(part.indexOf("640x480 region") >= 0);
    }

    function test_the_stop_line_carries_the_duration_and_the_file() {
        const line = policy.stopped("/tmp/a.mp4", 65000);
        verify(line.indexOf("1:05") >= 0);
        verify(line.indexOf("/tmp/a.mp4") >= 0);
    }

    function test_the_refusals_are_distinguishable_from_each_other() {
        const lines = [policy.noEngine(), policy.alreadyRecording(),
                       policy.notRecording(), policy.directoryFailed(1),
                       policy.tooSmall({ x: 0, y: 0, width: 3, height: 3 }),
                       policy.pickCancelled(), policy.noMonitor(),
                       policy.stillStopping()];
        for (let i = 0; i < lines.length; i++) {
            verify(lines[i].length > 0);
            for (let j = i + 1; j < lines.length; j++)
                verify(lines[i] !== lines[j]);
        }
    }

    /// Two refusals that look the same from outside and resolve differently:
    /// one waits for the user, the other for the muxer.
    function test_a_start_during_the_flush_is_a_different_refusal() {
        verify(policy.stillStopping() !== policy.alreadyRecording());
        verify(policy.stillStopping().indexOf("still being written") >= 0);
        // The state machine is what tells them apart at the call site.
        verify(!policy.canStart("stopping"));
        verify(!policy.canStart("recording"));
    }

    function test_the_probe_line_says_which_way_round_it_went() {
        verify(policy.probed("wf-recorder", true).indexOf("is available") >= 0);
        verify(policy.probed("wf-recorder", false).indexOf("not installed") >= 0);
    }

    function test_stopping_says_it_used_sigint() {
        verify(policy.signalledStop().indexOf("SIGINT") >= 0);
        compare(policy.stopSignal, 2);
    }
}
