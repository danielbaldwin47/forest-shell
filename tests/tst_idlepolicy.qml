// The idle ladder's decisions (#48; the ladder is #30's resolution).
//
// Everything here is a *policy* question — which stages are armed, at how many
// seconds, on which power source, and what may stop each one. What only exists
// once a compositor does — an `IdleMonitor` that really fires, a lock that
// really comes up, a delay inhibitor that is really held — is
// `tools/idle-harness.sh`, and the two halves meet at the log lines this file
// also pins.
import QtQuick
import QtTest
import "../Core"
import "../Services/System"

TestCase {
    name: "IdlePolicy"

    IdlePolicy { id: policy }
    SettingsSchema { id: schema }
    SpecStore { id: store }

    readonly property var defaults: store.defaults(schema.spec).system.idle

    // --- #30's table ---------------------------------------------------------

    function test_the_shipped_ladder_is_the_decided_one() {
        // #30's resolution, measured against this machine rather than picked. If
        // one of these changes, the decision changed.
        compare(defaults.dim.battery, 2.5);
        compare(defaults.dim.ac, 5);
        compare(defaults.lock.battery, 5);
        compare(defaults.lock.ac, 10);
        compare(defaults.dpms.battery, 6);
        compare(defaults.dpms.ac, 12);
        compare(defaults.suspend.battery, 15);
        // Off on mains: a plugged-in machine that suspends itself drops the
        // sessions running on it.
        compare(defaults.suspend.ac, 0);
        // The dim is a level, not a command — the backlight facade does it.
        compare(defaults.dim.level, 10);
        // A locked screen blanks fast, and this stage alone is tightened.
        compare(defaults.dpms.lockedSeconds, 30);
    }

    function test_every_stage_ships_on() {
        for (const id of policy.stages)
            compare(defaults[id].enabled, true, id + " ships off");
    }

    function test_the_battery_ladder_is_in_order() {
        // Not enforced by the code — a hand-edited file may lock before it dims,
        // and the right answer there is to lock before dimming rather than to
        // argue with the file. But the *shipped* one has to make sense: dim,
        // lock, blank, sleep.
        const rows = policy.ladder(defaults, true, false);
        compare(rows.map(row => row.id), ["dim", "lock", "dpms", "suspend"]);
        for (let i = 1; i < rows.length; i++)
            verify(rows[i].seconds > rows[i - 1].seconds,
                   rows[i].id + " is not after " + rows[i - 1].id);
    }

    function test_minutes_become_seconds_once() {
        compare(policy.seconds(defaults, "dim", true), 150);
        compare(policy.seconds(defaults, "lock", true), 300);
        compare(policy.seconds(defaults, "dpms", true), 360);
        compare(policy.seconds(defaults, "suspend", true), 900);

        compare(policy.seconds(defaults, "dim", false), 300);
        compare(policy.seconds(defaults, "lock", false), 600);
        compare(policy.seconds(defaults, "dpms", false), 720);
    }

    // --- the AC / battery split ----------------------------------------------

    function test_ac_skips_suspend_and_battery_does_not() {
        const onAc = policy.row(defaults, "suspend", false, false);
        compare(onAc.enabled, false);
        compare(onAc.off, "no timeout on ac");

        const onBattery = policy.row(defaults, "suspend", true, false);
        compare(onBattery.enabled, true);
        compare(onBattery.seconds, 900);
    }

    function test_every_other_stage_is_armed_on_both_sources() {
        for (const id of ["dim", "lock", "dpms"]) {
            verify(policy.row(defaults, id, true, false).enabled, id + " is off on battery");
            verify(policy.row(defaults, id, false, false).enabled, id + " is off on ac");
        }
    }

    function test_a_zero_is_off_on_that_source_only() {
        // The shape that makes AC-suspend-off expressible without a second
        // toggle: one column at zero, the other still armed.
        const settings = { lock: { enabled: true, battery: 0, ac: 10 } };
        compare(policy.row(settings, "lock", true, false).enabled, false);
        compare(policy.row(settings, "lock", true, false).off, "no timeout on battery");
        compare(policy.row(settings, "lock", false, false).enabled, true);
    }

    // --- what turns the ladder off -------------------------------------------

    function test_keep_awake_freezes_every_stage() {
        // #30: the caffeine toggle suppresses the entire ladder. Not one stage,
        // and not "everything but the lock".
        for (const row of policy.ladder(defaults, true, true)) {
            compare(row.enabled, false, row.id + " survived keep awake");
            compare(row.off, "keep awake");
        }
    }

    function test_a_stage_the_user_turned_off_says_so() {
        const settings = { dpms: { enabled: false, battery: 6, ac: 12 } };
        const row = policy.row(settings, "dpms", true, false);
        compare(row.enabled, false);
        compare(row.off, "turned off");
        // The timeout is still reported: the row is what the log line is written
        // from, and "off at 360s" is a more useful line than "off".
        compare(row.seconds, 360);
    }

    function test_a_missing_or_wrecked_section_reads_as_off_rather_than_throwing() {
        // settings.json is hand-edited (#21), and every reader here is inside a
        // binding — a section that arrived as a string must not take the ladder
        // down with it.
        for (const settings of [undefined, null, {}, { dim: "soon" }, { dim: null }]) {
            const row = policy.row(settings, "dim", true, false);
            compare(row.enabled, false);
            compare(row.seconds, 0);
        }
    }

    function test_a_negative_or_unreadable_timeout_is_off_and_not_immediate() {
        // The failure this prevents is the worst one the file can express: a
        // monitor armed at zero seconds locks the session the moment the shell
        // starts.
        for (const value of [-5, "soon", NaN, null]) {
            const settings = { lock: { enabled: true, battery: value, ac: value } };
            compare(policy.row(settings, "lock", true, false).enabled, false);
            compare(policy.seconds(settings, "lock", true), 0);
        }
    }

    // --- DPMS, the one stage with two timeouts -------------------------------

    function test_a_locked_screen_blanks_in_thirty_seconds() {
        // #30 tightens this stage and only this stage while locked: there is
        // nothing on a locked screen worth keeping lit.
        compare(policy.dpmsSeconds(defaults, true, false), 360);
        compare(policy.dpmsSeconds(defaults, true, true), 30);
        compare(policy.dpmsSeconds(defaults, false, true), 30);
    }

    function test_locking_never_makes_the_screen_blank_slower() {
        // A floor, not a replacement. A machine set to blank after 20 s unlocked
        // does not get slower the moment it locks.
        const settings = { dpms: { enabled: true, battery: 20 / 60, ac: 1, lockedSeconds: 30 } };
        compare(policy.dpmsSeconds(settings, true, false), 20);
        compare(policy.dpmsSeconds(settings, true, true), 20);
    }

    function test_a_blanked_lockedSeconds_leaves_the_configured_timeout_alone() {
        const settings = { dpms: { enabled: true, battery: 6, ac: 12, lockedSeconds: 0 } };
        compare(policy.dpmsSeconds(settings, true, true), 360);
    }

    // --- suspend: the gate, and the guarantee --------------------------------

    function test_audio_blocks_suspend_and_nothing_else() {
        // #30: the PipeWire gate is on this stage alone. Music through
        // headphones keeps playing; the screen still dims, locks and blanks.
        verify(policy.suspendBlocked(true));
        verify(!policy.suspendBlocked(false));
        // The other three stages have no such input at all — there is nowhere
        // for a caller to pass one, which is the strongest form of "suspend
        // only" this seam can state.
        for (const id of ["dim", "lock", "dpms"])
            compare(policy.row(defaults, id, true, false).enabled, true,
                    id + " should not care what is playing");
    }

    function test_a_sleep_always_goes_through_the_lock() {
        // The ticket's fourth acceptance criterion, as a decision: there is no
        // path to suspend that skips the lock, so the only question left is
        // whether it is up already.
        verify(policy.mustLockFirst(false));
        verify(!policy.mustLockFirst(true));
    }

    function test_inhibitors_are_respected_on_every_stage() {
        // #30 puts `respectInhibitors` on all four, and there is deliberately no
        // key for it: a config that could turn it off is a config that makes a
        // film stop halfway.
        compare(policy.respectInhibitors, true);
        compare(store.leafAt(schema.spec, "system.idle.respectInhibitors"), null);
    }

    function test_the_delay_lock_gives_up_before_logind_does() {
        // logind's `InhibitDelayMaxSec` defaults to 5 s and it does not ask
        // twice. The shell has to give up first and say so, or it is overruled
        // in silence.
        verify(policy.lockConfirmTimeoutMs < 5000);
    }

    // --- the helper's protocol ------------------------------------------------

    function test_the_bridge_speaks_four_words_and_ignores_the_rest() {
        compare(policy.event("lock"), "lock");
        compare(policy.event("unlock"), "unlock");
        compare(policy.event(" sleep \n"), "sleep");
        compare(policy.event("resume"), "resume");

        // A line from `busctl monitor` that the helper did not filter out, a
        // blank line at EOF, an error the helper printed: none of them are
        // events, and none of them may be guessed at.
        for (const line of ["", "  ", "Member=Lock", "lock-session", null, undefined])
            compare(policy.event(line), "");
    }

    function test_every_event_has_a_line_to_log() {
        for (const event of ["lock", "unlock", "sleep", "resume"])
            verify(policy.bridgeLine(event) !== "", event + " logs nothing");
        compare(policy.bridgeLine("nonsense"), "");
    }

    // --- what the log says ----------------------------------------------------
    //
    // The lines are pinned here because tools/idle-harness.sh asserts on them:
    // "suspend never lands on an unlocked session" is only checkable if the log
    // says when the lock went up and when the sleep lock was let go (#81).

    function test_the_startup_line_carries_the_whole_ladder() {
        const line = policy.ladderLine(policy.ladder(defaults, true, false), true);
        compare(line, "ladder on battery: dim 150s, lock 300s, dpms 360s, suspend 900s");

        const onAc = policy.ladderLine(policy.ladder(defaults, false, false), false);
        compare(onAc, "ladder on ac: dim 300s, lock 600s, dpms 720s, "
                    + "suspend off (no timeout on ac)");
    }

    /// The line a rung logs when its timeout moved under the running shell
    /// (#139). Pinned to the second, because a re-arm that reported the *old*
    /// number would read exactly like the bug it exists to rule out — and
    /// tools/idle-harness.sh greps it verbatim.
    function test_a_rung_that_re_armed_says_at_what() {
        compare(policy.armed("dpms", 6), "dpms armed at 6s");
        compare(policy.armed("lock", policy.seconds(defaults, "lock", true)),
                "lock armed at 300s");
    }

    function test_a_frozen_ladder_says_which_stages_it_froze() {
        const line = policy.ladderLine(policy.ladder(defaults, true, true), true);
        compare(line.indexOf("dim off (keep awake)") >= 0, true, line);
        compare(line.indexOf("suspend off (keep awake)") >= 0, true, line);
    }

    function test_the_sleep_path_logs_which_of_the_two_cases_it_was() {
        verify(policy.sleeping(false).indexOf("locking first") >= 0);
        verify(policy.sleeping(true).indexOf("already locked") >= 0);
        verify(policy.lockConfirmed(120).indexOf("releasing") >= 0);
        verify(policy.lockUnconfirmed(4000).indexOf("sleeping anyway") >= 0);
    }

    function test_a_lock_that_failed_to_take_does_not_read_as_held() {
        // #78's lesson, one subprocess along: a delay inhibitor that never
        // started must not log the line that says it is holding one.
        const refused = policy.inhibitorRefused("systemd-inhibit: not found");
        verify(refused.indexOf("no sleep inhibitor") >= 0);
        verify(refused.indexOf("held") < 0, refused);
    }
}
