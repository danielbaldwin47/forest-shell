// The OSD's decisions (#46): what pops it, what it says, where it sits and how
// long it stays.
//
// Seam 1 (CLAUDE.md) is the whole of "which change is worth a surface" — the
// arming rule that keeps a login quiet, the suppression rule that keeps it out
// from under the control centre, the glyph ladder, the anchor table. What is
// *not* here is the surface itself: mapping a layer-shell window on the focused
// screen and unmapping it again is seam 2's (tools/osd-harness.sh), and the
// picture is seam 3's (`tools/capture-harness.sh --surface osd --session`).
//
// The one test in here that reaches outside its own directory is
// `test_the_volume_glyph_agrees_with_the_audio_facade`. The OSD draws the same
// speaker the bar does, from a second table, and two tables that must agree are
// two tables that drift — so they are compared rather than described.
import QtQuick
import QtTest
import "../Core"
import "../Surfaces/Osd"
import "../Services/Media"

TestCase {
    name: "OsdPolicy"

    OsdPolicy { id: policy }
    AudioPolicy { id: audio }
    SettingsSchema { id: settings }

    // A new reading of one channel, the shape the facades hand over.
    function snap(available, percent, muted) {
        return { available: available, percent: percent, muted: muted === true };
    }

    // A stored reading — a snapshot plus the moment its channel was armed.
    // `armedAt: 0` with a `now` of 10000 below is "long settled", which is the
    // state every test that is not about settling wants.
    function stored(available, percent, muted, armedAt) {
        const state = snap(available, percent, muted);
        state.armedAt = armedAt === undefined ? 0 : armedAt;
        return state;
    }

    // Well past `policy.settleMs` from `armedAt: 0`.
    readonly property int later: 10000

    // --- what pops it ---------------------------------------------------------

    function test_the_first_reading_of_a_channel_only_arms_it() {
        // PipeWire answers a frame or two after the shell starts, and the panel
        // is probed after that: every channel's first value is a jump from
        // nothing to whatever the machine was already at. Popping on those is a
        // shell that greets every login with three OSDs.
        compare(policy.observe(null, snap(true, 45, false), later), "arm");
        compare(policy.observe(undefined, snap(true, 45, false), later), "arm");
    }

    function test_a_channel_that_is_still_settling_arms_rather_than_pops() {
        // The bug this rule exists for, from the first run of
        // tools/osd-harness.sh: the backlight facade knows it *has* a panel a
        // beat before it has read what the panel is doing, so the channel armed
        // at 0% and then "changed" to the machine's real 1% sixteen
        // milliseconds later — an OSD on the way into every login. A channel is
        // therefore silent for its first `settleMs`, whatever it does.
        compare(policy.observe(stored(true, 0, false, 1000), snap(true, 1, false),
                               1000 + policy.settleMs - 1), "arm");
        compare(policy.observe(stored(true, 0, false, 1000), snap(true, 1, false),
                               1000 + policy.settleMs + 1), "pop");
    }

    function test_a_change_on_an_armed_channel_pops() {
        compare(policy.observe(stored(true, 45, false), snap(true, 50, false), later), "pop");
        compare(policy.observe(stored(true, 45, false), snap(true, 45, true), later), "pop");
        compare(policy.observe(stored(true, 45, true), snap(true, 45, false), later), "pop");
    }

    function test_the_same_value_again_is_not_a_change() {
        // PipeWire recalculates a volume in fractions of a percent, and the
        // facade rounds: the same reading arriving twice is a frame of work,
        // not a state change (Services/Media/Audio.qml says the same thing
        // about its log line).
        compare(policy.observe(stored(true, 45, false), snap(true, 45, false), later), "ignore");
    }

    function test_a_channel_the_machine_does_not_have_is_ignored() {
        // No sink, no mic, no backlight — a desktop has two of these three.
        compare(policy.observe(null, snap(false, 0, false), later), "ignore");
        compare(policy.observe(stored(true, 45, false), snap(false, 0, false), later), "ignore");
    }

    function test_a_device_coming_back_arms_rather_than_pops() {
        // Unplugging headphones takes the default sink away and plugging them
        // in brings a different one back at its own volume. That is not the
        // user asking for anything, so it re-arms — the same rule as the first
        // reading, for the same reason, and the same settle window after it.
        compare(policy.observe(stored(false, 0, false), snap(true, 80, false), later), "arm");
    }

    function test_muted_is_read_strictly() {
        // The snapshots arrive from three different facades; an absent `muted`
        // is not a mute, and must not read as one change on the way in and
        // another on the way out.
        compare(policy.observe(stored(true, 45, undefined), snap(true, 45, false), later),
                "ignore");
    }

    function test_what_is_stored_carries_the_moment_the_channel_was_armed() {
        // The settle window is measured from when the channel appeared, not
        // from the last thing it did — otherwise a value that keeps moving
        // while a service settles keeps pushing the window forward, and a
        // channel that is genuinely being used stays silent.
        const armed = policy.record(null, snap(true, 0, false), "arm", 1000);
        compare(armed.armedAt, 1000);
        compare(armed.percent, 0);

        const settling = policy.record(armed, snap(true, 1, false), "arm", 1200);
        compare(settling.armedAt, 1000, "re-arming while settling moved the window");
        compare(settling.percent, 1, "the reading itself is always stored");

        const popped = policy.record(settling, snap(true, 40, false), "pop", 5000);
        compare(popped.armedAt, 1000);
        compare(popped.percent, 40);

        // A device going away and coming back is a new life, so it gets a new
        // window: the value it comes back at is not something the user asked
        // for either.
        const gone = policy.record(popped, snap(false, 0, false), "ignore", 6000);
        const back = policy.record(gone, snap(true, 80, false), "arm", 7000);
        compare(back.armedAt, 7000);
    }

    // --- when it stays out of the way ----------------------------------------

    function test_the_control_centre_suppresses_it() {
        // The panel holds live sliders for all three channels (#44). An OSD on
        // top of it is the same number twice, one of them over the control the
        // user is dragging.
        verify(policy.suppressed("controlcenter", false));
        verify(!policy.suppressed("launcher", false));
        verify(!policy.suppressed("", false));
    }

    function test_the_lock_suppresses_it() {
        // The lock is a session-lock surface above every layer, so an OSD under
        // it is frames nobody sees. Volume keys still work; they are just
        // silent.
        verify(policy.suppressed("", true));
    }

    // --- what it says ---------------------------------------------------------

    function test_the_volume_glyph_agrees_with_the_audio_facade() {
        // Two tables for one speaker is two tables that drift. The bar's is
        // Services/Media/AudioPolicy.qml and takes 0-1; this one takes percent,
        // because the OSD is fed by three services and only one of them thinks
        // in fractions.
        for (const percent of [0, 1, 20, 49, 50, 51, 100]) {
            compare(policy.icon("volume", percent, false),
                    audio.sinkIcon(percent / 100, false),
                    "unmuted glyph at " + percent + "%");
            compare(policy.icon("volume", percent, true),
                    audio.sinkIcon(percent / 100, true),
                    "muted glyph at " + percent + "%");
        }
    }

    function test_the_other_two_glyphs() {
        compare(policy.icon("mic", 60, false), "mic");
        compare(policy.icon("mic", 60, true), "mic-off");
        // One sun at every level: the control centre's brightness slider has no
        // second glyph either, and a dimming icon would be a decision no ticket
        // has made.
        compare(policy.icon("brightness", 5, false), "sun");
        compare(policy.icon("brightness", 100, false), "sun");
    }

    function test_an_unknown_channel_has_no_glyph_and_no_name() {
        // Reachable: the IPC door takes a channel name typed by a human.
        compare(policy.icon("nonesuch", 50, false), "");
        compare(policy.known("nonesuch"), false);
        compare(policy.known("volume"), true);
    }

    function test_the_readout_is_the_level_until_it_is_muted() {
        compare(policy.readout("volume", 45, false), "45%");
        compare(policy.readout("volume", 45, true), "Muted");
        compare(policy.readout("brightness", 45, false), "45%");
        // Brightness cannot mute — there is nothing to restore it to, which is
        // the same argument ControlSlider.qml makes about its glyph.
        compare(policy.readout("brightness", 45, true), "45%");
    }

    function test_the_name_is_what_the_log_line_and_the_label_share() {
        compare(policy.name("volume"), "Volume");
        compare(policy.name("mic"), "Microphone");
        compare(policy.name("brightness"), "Brightness");
        compare(policy.name("nonesuch"), "");
    }

    function test_the_track_is_a_fraction_of_one() {
        compare(policy.fraction(0), 0);
        compare(policy.fraction(50), 0.5);
        compare(policy.fraction(100), 1);
        // Over-unity volume is representable in PipeWire and is not drawable.
        compare(policy.fraction(140), 1);
        compare(policy.fraction(-5), 0);
        compare(policy.fraction("nonesuch"), 0);
    }

    function test_a_level_from_outside_is_clamped_and_whole() {
        // The IPC door (`qs ipc call osd pop volume 45`) is a string typed by a
        // human, and the harness is the first thing to type into it.
        compare(policy.clampPercent(45.4), 45);
        compare(policy.clampPercent(-10), 0);
        compare(policy.clampPercent(180), 100);
        compare(policy.clampPercent("nonesuch"), 0);
    }

    // --- where it sits and how long it stays ---------------------------------

    function test_the_five_positions_anchor_one_edge_each() {
        // Layer-shell centres on the axis it is not anchored to, so one flag is
        // a centred pill against that edge and no flags is the middle of the
        // screen.
        compare(JSON.stringify(policy.anchorsFor("bottom")),
                JSON.stringify({ top: false, bottom: true, left: false, right: false }));
        compare(JSON.stringify(policy.anchorsFor("top")),
                JSON.stringify({ top: true, bottom: false, left: false, right: false }));
        compare(JSON.stringify(policy.anchorsFor("left")),
                JSON.stringify({ top: false, bottom: false, left: true, right: false }));
        compare(JSON.stringify(policy.anchorsFor("right")),
                JSON.stringify({ top: false, bottom: false, left: false, right: true }));
        compare(JSON.stringify(policy.anchorsFor("center")),
                JSON.stringify({ top: false, bottom: false, left: false, right: false }));
    }

    function test_an_unknown_position_falls_back_to_the_default() {
        // A hand-edited settings.json is coerced before it gets here, but the
        // fallback is stated once rather than trusted to happen upstream.
        compare(JSON.stringify(policy.anchorsFor("nonesuch")),
                JSON.stringify(policy.anchorsFor(policy.defaultPosition)));
        compare(policy.defaultPosition, "bottom");
        verify(policy.positions.indexOf(policy.defaultPosition) >= 0);
    }

    function test_the_margin_is_applied_to_the_anchored_edge_only() {
        // A margin on an unanchored edge is a pill shoved off its own centre.
        compare(JSON.stringify(policy.marginsFor("bottom", 64)),
                JSON.stringify({ top: 0, bottom: 64, left: 0, right: 0 }));
        compare(JSON.stringify(policy.marginsFor("right", 24)),
                JSON.stringify({ top: 0, bottom: 0, left: 0, right: 24 }));
        compare(JSON.stringify(policy.marginsFor("center", 64)),
                JSON.stringify({ top: 0, bottom: 0, left: 0, right: 0 }));
    }

    function test_the_timeout_is_bounded() {
        compare(policy.timeoutMs(2000), 2000);
        // Nothing instant and nothing that outstays the screen: a 0 here would
        // be a surface that maps and unmaps in one frame, and the settings
        // schema clamps to the same pair.
        compare(policy.timeoutMs(0), policy.minTimeoutMs);
        compare(policy.timeoutMs(99999), policy.maxTimeoutMs);
        compare(policy.timeoutMs("nonesuch"), policy.defaultTimeoutMs);
    }

    function test_the_motion_is_the_two_steps_the_spec_grants_it() {
        // #27's OSD row: 240 in, 140 out, and value updates in place at 140.
        // Read off the ladder rather than typed here — Theme.duration() is what
        // collapses both under reducedEffects (#69), and it can only do that to
        // a number that was on the ladder to begin with.
        compare(policy.enterMs, 240);
        compare(policy.inPlaceMs, 140);
    }

    function test_the_settings_keys_and_the_policy_agree() {
        // Two clamps on one number is two clamps that drift: `settings.json` is
        // coerced on the way in (Core/Coerce.qml) and an IPC-supplied timeout is
        // clamped by the policy, and a value the file accepts but the surface
        // refuses would be a setting that silently does nothing.
        const osd = settings.spec.controlCenter.osd;
        compare(osd.timeout.def, policy.defaultTimeoutMs);
        compare(osd.timeout.coerce(policy.minTimeoutMs - 1), policy.minTimeoutMs);
        compare(osd.timeout.coerce(policy.maxTimeoutMs + 1), policy.maxTimeoutMs);
        compare(osd.position.def, policy.defaultPosition);
        for (const position of policy.positions)
            compare(osd.position.coerce(position), position,
                    position + " is a position the schema refuses");
        compare(osd.position.coerce("nonesuch"), undefined);
    }

    // --- what a harness reads -------------------------------------------------

    function test_every_state_change_names_itself() {
        // #81: a lifecycle with no log line is one seam 2 cannot assert on, and
        // the maintenance pass on #46 asks for the *reason* as well as the
        // fact — which key, which channel, which value.
        compare(policy.shown("volume", 45, false),
                "volume 45% — showing (Volume 45%)");
        compare(policy.shown("mic", 60, true),
                "mic 60% — showing (Microphone Muted)");
        compare(policy.hidden("timeout"), "hidden (timeout)");
        compare(policy.hidden("ipc"), "hidden (ipc)");
        compare(policy.suppressedBy("controlcenter"),
                "suppressed while controlcenter is open");
        compare(policy.suppressedBy("lock"), "suppressed while lock is open");
        compare(policy.armed("brightness", 60), "brightness armed at 60% — not showing");
        compare(policy.refused("nonesuch"), "no such channel: nonesuch");
    }
}
