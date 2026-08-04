#!/usr/bin/env bash
# Measure the idle budget on a real session (#22 §5, the method fixed by #95).
#
#   tools/idle-budget.sh                  # 195 s window, the real shell
#   tools/idle-budget.sh --seconds 120
#   tools/idle-budget.sh --keep           # leave the shell up afterwards
#   tools/idle-budget.sh --help           # the window, and the rungs it reaches
#
# **This is not a seam, and it cannot be made into one.** `tests/` cannot import
# Quickshell; the nested compositor never presents a frame (#85), so frames
# measured in there are zero whether the shell is idle or on fire; and a
# client-side capture has no frame pacing at all. So this runs the real shell on
# the caller's own Wayland session, which is exactly what #95 says the
# measurement takes — and it puts a bar on that session for the length of the
# window.
#
# What it reports, and the budgets it checks them against:
#
#   CPU        ≤ 0.5 % of one core over the window (#22 §5; ~0.2 % aspiration)
#   switches   < 5 /s, voluntary + involuntary, from /proc/<pid>/status
#   frames     one repaint a minute and nothing else — the count and the gaps.
#              Needs QSG_RENDER_TIMING, which this exports.
#   startup    first frame ≤ 1.5 s, interactive ≤ 2 s (#22 §4), read off the
#              same run's log. Here rather than at the second seam because a
#              nested compositor never presents a frame (#85), so a first-frame
#              time measured in one is a claim about a frame nobody saw.
#
# Idle means idle: do not touch the machine while it runs. A pointer crossing
# the bar is a hover, a hover is a repaint, and a repaint is the thing being
# counted. That is checked rather than trusted — a window with a workspace
# switch or an active-window change in it **exits 2, inconclusive**, which is a
# third verdict distinct from pass and fail: the shell was driven, so it was
# never measured. The 1-minute load average over the window is reported next to
# the numbers for the same reason (tools/load-window.sh).
#
# The other thing waiting for the machine to be left alone is the shell's own
# idle ladder (#176). `system.idle.dim` fires at 2.5 min on battery and 5 min on
# mains, so the default window straddles a rung on one power source and not on
# the other — and #152 walked into it: 45 frames against a budget of 10, 39 of
# them the screen dimming at 151.7 s and the OSD announcing it (#175). A rung
# firing inside the window is a state change the harness measured rather than a
# repaint regression, so it voids the same way input does. Which rungs were
# armed comes out of the shell's own ladder line, and the power state is
# reported on every run, because #73's 6 frames and #137's 21 are only
# comparable to each other if they were taken on the same one and nothing
# recorded it. `--help` says which rungs the default window can reach.
#
# The one that is not obvious, and cost #95 three windows: **an animated window
# title is input.** The bar tracks the focused window, a terminal running an
# agent puts a spinner in its title, and the title changes about once a second
# — so the shell repaints about once a second, correctly, for as long as that
# window has focus. Measure with the focused window static, or from a workspace
# with nothing on it at all.
#
# The shell pushes a Hyprland layerrule for its own namespace at startup (#78)
# and there is no clearing verb in the 0.5x syntax, so the rule outlives the
# process. `hyprctl reload` clears it; this script says so rather than doing it,
# because reloading the compositor is the caller's session's business.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Launch, settle, conditions and teardown are the same on both budget harnesses
# and live in one place (#150); what stays here is the window, the budgets and
# the three verdicts.
# shellcheck source=session-run.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/session-run.sh"

SECONDS_WINDOW=195
ENTRY="shell.qml"
RUN_START=$(date +%s.%N)

usage() {
    cat <<'USAGE'
tools/idle-budget.sh [--seconds N] [--entry FILE] [--keep]

  --seconds N   the window, in seconds (default 195)
  --entry FILE  the shell entry point (default shell.qml)
  --keep        leave the shell running afterwards
  --help        this

Which idle rungs the window reaches, and why it matters:

  The shell's idle ladder is waiting for the same thing this harness is — a
  machine nobody is touching. On battery the defaults are dim at 2.5 min
  (150 s), lock at 5 min (300 s), dpms at 6 min (360 s) and suspend at 15 min
  (900 s); on mains each is twice that and suspend is off. The window is
  measured on top of the ~12-15 s the harness spends launching and settling, so
  from a cold start the 195 s default reaches **dim and nothing else on
  battery, and no rung at all on mains**. --seconds 300 reaches lock on
  battery, --seconds 360 reaches dpms, and both stay short of any rung on
  mains.

  A rung that fires inside the window is measured by it: #152 read 45 frames
  against a budget of 10, 39 of which were the screen dimming at 151.7 s. So a
  window with a rung in it voids the frame criterion the way input does and
  exits 2, inconclusive — re-run it on mains, or shorter than the first armed
  rung. What is actually armed is read out of the shell's own ladder line
  rather than out of the timeouts above, which are only the defaults.

  Your idle clock may already be running when the harness starts: it counts
  from the last input on the session, not from launch. The prediction assumes
  the last input was you starting this, and the log is the witness either way.
USAGE
}

while (( $# )); do
    case "$1" in
        --seconds) SECONDS_WINDOW="$2"; shift 2 ;;
        --entry)   ENTRY="$2"; shift 2 ;;
        --keep)    SESSION_RUN_KEEP=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# Which power source the machine is on. The shell's own ladder line is the
# better authority once it is up — it is what the ladder was armed against —
# but this is wanted before the window opens and on runs that never get a
# ladder line at all, so it comes from sysfs, which is where UPower reads it
# from too. A machine with neither a mains supply nor a battery is `unknown`
# rather than a guess: the report says what it knows (#176).
# A USB supply is only consulted when the machine has no mains one at all. On
# the T480 the two USB-C port controllers publish `online 1` while the barrel
# charger is what is actually feeding it, so a machine with both would read `ac`
# off a USB port that charges nothing — and on a laptop running from its
# battery with a USB-C dock attached, that is the wrong answer in the direction
# that matters here.
power_state() {
    local type_file supply mains_seen=0 mains_online=0 usb_online=0 battery=0
    for type_file in /sys/class/power_supply/*/type; do
        [[ -r "$type_file" ]] || continue
        supply=${type_file%/type}
        [[ -r "$supply/online" ]] || { [[ "$(<"$type_file")" == Battery ]] && battery=1; continue; }
        case "$(<"$type_file")" in
            Mains)
                mains_seen=1
                [[ "$(<"$supply/online")" == 1 ]] && mains_online=1 ;;
            USB|USB_PD|USB_PD_DRP)
                [[ "$(<"$supply/online")" == 1 ]] && usb_online=1 ;;
            Battery) battery=1 ;;
        esac
    done
    if (( mains_seen )); then
        (( mains_online )) && printf 'ac\n' || { (( battery )) && printf 'battery\n' || printf 'unknown\n'; }
    elif (( usb_online )); then printf 'ac\n'
    elif (( battery )); then printf 'battery\n'
    else printf 'unknown\n'; fi
}

session_run_require_session

session_run_launch forest-idle "$ENTRY" || exit 1

# When the repaints happened, and not just how many — the gap list is what says
# a count of six is the clock rather than three pairs ten seconds apart, and it
# is what diagnosed #137 (`10.8s, 41.1s, 29.9s, 9.9s …`: a cluster waking the
# shell every ten seconds, hiding inside a count that was only three over).
#
# Stamped here because the scenegraph's own line carries no time. A separate
# reader rather than a filter in the pipeline above, so `$!` stays the shell's
# own pid — /proc/<pid>/stat is where the other two budgets come from.
STAMPS=$(mktemp -t forest-idle-frames.XXXXXX)
tail -n0 -F "$SESSION_RUN_LOG" 2>/dev/null \
    | grep --line-buffered -a 'frame rendered in' \
    | while IFS= read -r _; do printf '%s\n' "$EPOCHREALTIME"; done > "$STAMPS" &
STAMP_PID=$!

cleanup() {
    local exit_status=$?
    # The stamp reader is this harness's own; the shell, the conditions sampler
    # and the log are the shared teardown's.
    pkill -P "$STAMP_PID" 2>/dev/null
    kill "$STAMP_PID" 2>/dev/null
    rm -f "$STAMPS"
    session_run_teardown "$exit_status"
}
trap cleanup EXIT

session_run_settle 10 'before the window opens' || exit 1

ticks_per_second=$(getconf CLK_TCK)
cpu_ticks() { awk '{print $14 + $15}' "/proc/$1/stat" 2>/dev/null; }
switches()  { awk '/ctxt_switches/ {total += $2} END {print total}' "/proc/$1/status" 2>/dev/null; }

start_ticks=$(cpu_ticks "$SESSION_RUN_PID")
start_switches=$(switches "$SESSION_RUN_PID")
start_frames=$(session_run_frames "$SESSION_RUN_LOG")
start_lines=$(session_run_mark)
start_time=$(date +%s.%N)
power_at_start=$(power_state)
load_window_start

# Said here as well as in the report, so a run that dies mid-window still leaves
# the one condition that cannot be recovered afterwards in its log (#176).
note "power   $power_at_start — the ladder's ${power_at_start} rungs are the ones in play"
note "measuring for ${SECONDS_WINDOW}s — do not touch the machine"
sleep "$SECONDS_WINDOW"

end_ticks=$(cpu_ticks "$SESSION_RUN_PID")
end_switches=$(switches "$SESSION_RUN_PID")
end_frames=$(session_run_frames "$SESSION_RUN_LOG")
end_time=$(date +%s.%N)
power_at_end=$(power_state)
load_window_report

if [[ -z "$end_ticks" ]]; then
    echo "the shell died during the window — see $SESSION_RUN_LOG" >&2
    exit 1
fi

# Was the machine actually idle? Every number below is worthless if it was not,
# and "do not touch the machine" is an instruction to a human that nothing
# checks — #95 measured 155 frames in a 195 s window and the log said why:
# something else on the session was switching workspaces, and each switch
# animates the ridgeline (#75). That is not the shell failing the criterion,
# it is the window not being an idle window, and the two must not report the
# same way. So the shell's own compositor lines are the witness: a workspace
# focus or an active-window change inside the window means there was input on
# this session, from a human or from another agent driving hyprctl.
compositor_events=$(tail -n +"$((start_lines + 1))" "$SESSION_RUN_LOG" \
    | grep -ac 'compositor: \(workspace .* focused\|focused window\)')
compositor_events=${compositor_events:-0}

# The other thing that was waiting for the machine to be left alone: the shell's
# own idle ladder (#176). Same argument as the paragraph above — a rung firing
# inside the window is a state change the window measured, not a repaint the
# idle shell made, and the two must not report the same way.
#
# The ladder is read off the shell's own startup line rather than out of the
# settings file, so the harness and the shell cannot disagree about what was
# armed; the arithmetic on it is a decision and lives at the first seam
# (tools/idle-rungs.py, tests/tst_idle_rungs.py). `lead` is how much idle time
# was already on the clock when the window opened — launch plus settle — because
# a rung fires on the idle clock and not on the window's.
lead_seconds=$(python3 -c "print(round($start_time - $RUN_START, 1))")
rungs_report=$(python3 "$(dirname "${BASH_SOURCE[0]}")/idle-rungs.py" "$SESSION_RUN_LOG" \
                   --window "$SECONDS_WINDOW" --lead "$lead_seconds" --from-line "$start_lines" 2>/dev/null)
rungs_field() { printf '%s\n' "$rungs_report" | grep -a "^$1=" | cut -d= -f2-; }
ladder_power=$(rungs_field power)
armed_rungs=$(rungs_field armed)
crossed_rungs=$(rungs_field crossed)
fired_rungs=$(rungs_field fired)

# What the shell believed beats what sysfs says, when they disagree: the ladder
# was armed against the shell's own reading. A disagreement is itself worth
# printing rather than resolving silently.
power_line="$power_at_start"
[[ "$power_at_start" != "$power_at_end" ]] && power_line="$power_at_start → $power_at_end during the window"
[[ -n "$ladder_power" && "$ladder_power" != unknown && "$ladder_power" != "$power_at_start" ]] \
    && power_line="$power_line (sysfs), $ladder_power (the shell's ladder)"

printf '  ....  power   %s\n' "$power_line"
if [[ -n "$armed_rungs" ]]; then
    printf '  ....  ladder  armed %s — idle time %ss to %ss was measured\n' \
        "${armed_rungs//,/, }" "$lead_seconds" \
        "$(python3 -c "print(round($lead_seconds + $SECONDS_WINDOW, 1))")"
else
    printf '  ....  ladder  the log never said what was armed — rungs unjudged\n'
fi

printf '\n'
python3 - "$start_ticks" "$end_ticks" "$start_switches" "$end_switches" \
          "$start_frames" "$end_frames" "$start_time" "$end_time" "$ticks_per_second" \
          "$STAMPS" <<'PY'
import sys

start_ticks, end_ticks, start_sw, end_sw, start_fr, end_fr = (int(v) for v in sys.argv[1:7])
start_time, end_time = float(sys.argv[7]), float(sys.argv[8])
hz = int(sys.argv[9])
stamps_path = sys.argv[10]

elapsed = end_time - start_time
cpu_seconds = (end_ticks - start_ticks) / hz
print(f"  window      {elapsed:.1f}s")
print(f"  cpu         {cpu_seconds:.3f}s of core time — {cpu_seconds / elapsed * 100:.3f}% of one core")
print(f"  switches    {end_sw - start_sw} — {(end_sw - start_sw) / elapsed:.2f}/s")
print(f"  frames      {end_fr - start_fr} — one per {elapsed / max(1, end_fr - start_fr):.1f}s")

# One repaint is several frames: the shell has a window per surface per screen
# and Qt renders all of them when any one repaints, within milliseconds. The
# gap list is between repaint *moments*, because that is the thing the budget
# is written in — "one repaint a minute", not one frame.
try:
    with open(stamps_path) as handle:
        times = [float(line) for line in handle if line.strip()]
except OSError:
    times = []

times = [t for t in times if start_time <= t <= end_time]
moments = []
for t in times:
    if not moments or t - moments[-1] > 0.5:
        moments.append(t)

gaps = [moments[i] - moments[i - 1] for i in range(1, len(moments))]
if gaps:
    print(f"  repaints    {len(moments)} — gaps {', '.join(f'{gap:.1f}s' for gap in gaps)}")
elif moments:
    print(f"  repaints    1 — no gap to measure")
else:
    print("  repaints    none in the window")
PY

cpu_percent=$(python3 -c "print((($end_ticks - $start_ticks) / $ticks_per_second) / ($end_time - $start_time) * 100)")
switch_rate=$(python3 -c "print(($end_switches - $start_switches) / ($end_time - $start_time))")
frame_count=$((end_frames - start_frames))
# The budget is "one repaint a minute" (#22 §5), and two things turn that into
# a frame count. The shell has two windows *per screen* — the bar and the
# background — and Qt renders both when either repaints, so one repaint moment
# costs two frames per screen; the screen count is read off the log rather than
# assumed, because a docked laptop has three and would otherwise fail this
# criterion while sitting perfectly still. And a minute's worth of slack covers
# the readings that legitimately change on their own: the battery percentage
# ticks every few minutes while discharging, and that repaint is data rather
# than animation.
#
# Measured on the T480, one screen, 195 s: 7-9 frames. The failure this catches
# is an order of magnitude away from that — an animation that never settles
# measures in the hundreds.
screens=$(grep -ac 'bar: content ready on' "$SESSION_RUN_LOG")
screens=${screens:-1}
(( screens )) || screens=1
expected_frames=$(python3 -c "import math; print(2 * $screens * (math.ceil($SECONDS_WINDOW / 60) + 1))")

power_changed=0
[[ "$power_at_start" != "$power_at_end" ]] && power_changed=1

printf '\n'
if (( compositor_events )); then
    note "$compositor_events compositor event(s) inside the window — workspace switches or"
    note "active-window changes, so this session was in use while it was measured"
fi
if [[ -n "$fired_rungs" ]]; then
    note "the idle ladder fired inside the window: ${fired_rungs//,/, } — that is the shell"
    note "changing state on a schedule, and the repaints it costs are that rung's"
elif [[ -n "$crossed_rungs" ]]; then
    note "the window covered ${crossed_rungs//,/, } on the idle clock, but the log has no rung"
    note "firing in it — the session was already idle before the run, so it fired earlier"
fi
if (( power_changed )); then
    note "the power source changed mid-window ($power_at_start → $power_at_end), which rearms the"
    note "whole ladder at the other source's timeouts"
fi
{ (( compositor_events )) || [[ -n "$fired_rungs" ]] || (( power_changed )); } && printf '\n'

# What a disturbed window does and does not void. Input only ever *adds* work —
# a workspace switch animates the ridgeline, a hover repaints a module — so a
# reading that passes its budget under input passes it at rest too, and that
# pass is real. A reading that fails one has no such argument: it might be the
# shell, it might be whoever was driving. So the three criteria split by
# direction rather than all going out together, and only the frame count, whose
# budget the driving directly writes, is void either way.
#
# A rung firing is the same kind of event with one asymmetry (#176): it does not
# only add. dim writes a backlight and the OSD used to announce it (#175), but
# dpms blanks the screen, and a shell whose frames stop being presented can come
# in *under* a frame budget it would otherwise fail. So a window with a rung in
# it gets no upper-bound claim on any criterion — the numbers are reported, the
# frame count is void, and the run is inconclusive.
void_count=0
void() { printf '  \033[33m????\033[0m  %s\n' "$1"; void_count=$((void_count + 1)); }

disturbance=""
join_reason() { [[ -n "$disturbance" ]] && disturbance="$disturbance and $1" || disturbance="$1"; }
(( compositor_events )) && join_reason "the window was driven"
[[ -n "$fired_rungs" ]] && join_reason "the idle ladder fired (${fired_rungs//,/, })"
(( power_changed )) && join_reason "the power source changed"

driven=0
[[ -n "$disturbance" ]] && driven=1
# Input alone is the one disturbance that argues in a single direction, so it is
# the one that still earns "upper bound" out of a pass.
qualifier="$disturbance"
[[ "$disturbance" == "the window was driven" ]] && qualifier="under input, so an upper bound"

if python3 -c "import sys; sys.exit(0 if $cpu_percent <= 0.5 else 1)"; then
    if (( driven )); then
        pass "idle CPU $(printf '%.3f' "$cpu_percent")% ≤ 0.5% — $qualifier"
    else
        pass "idle CPU $(printf '%.3f' "$cpu_percent")% ≤ 0.5%"
    fi
elif (( driven )); then
    void "idle CPU $(printf '%.3f' "$cpu_percent")% over budget, but $disturbance"
else
    fail "idle CPU $(printf '%.3f' "$cpu_percent")% over the 0.5% budget"
fi

if python3 -c "import sys; sys.exit(0 if $switch_rate < 5 else 1)"; then
    if (( driven )); then
        pass "$(printf '%.2f' "$switch_rate") context switches/s < 5/s — $qualifier"
    else
        pass "$(printf '%.2f' "$switch_rate") context switches/s < 5/s"
    fi
elif (( driven )); then
    void "$(printf '%.2f' "$switch_rate") context switches/s over budget, but $disturbance"
else
    fail "$(printf '%.2f' "$switch_rate") context switches/s over the 5/s budget"
fi

# The clock is the one thing that may repaint at rest, once a minute on the
# minute (Surfaces/Bar/Modules/Clock.qml). Anything much past that is an
# animation that did not stop.
if (( driven )); then
    void "$frame_count frames in ${SECONDS_WINDOW}s, but $disturbance — the repaints"
    note "     that costs are not the ones the criterion asked about"
elif (( frame_count <= expected_frames )); then
    pass "$frame_count frames in ${SECONDS_WINDOW}s — the clock, and nothing else"
else
    fail "$frame_count frames in ${SECONDS_WINDOW}s, expected at most $expected_frames"
fi

# The count alone cannot say "on the minute", which is what #22 §5 actually
# asks — #73 proved it with the list, `gaps (ms): [59999, 59999, 60000, …]`.
# The threshold drops the sub-second pairs, which are the second window
# rendering the same repaint moment rather than a repaint of their own.
python3 "$(dirname "${BASH_SOURCE[0]}")/measure-frame-timing.py" "$SESSION_RUN_LOG" \
    --from-line "$start_lines" --list-gaps 1000 2>/dev/null | grep -a '^gaps' | sed 's/^/  ....  /'

# --- the startup gates, from the same run ------------------------------------
#
# #22 §4 budgets startup from process launch: the first frame — wallpaper *and*
# bar — within 1.5 s, and everything reachable within 2 s. Both are read off the
# log, which is why every line carries the age of the process (Core/Logger.qml).
#
# They live here rather than at the second seam because a nested compositor
# never presents (#85), so "first frame painted" in there is a claim about a
# frame nobody could see. #36's own criterion is that the gates still hold with
# five more services in the deferred stage — which is a question about this
# session, on this machine.
gate_ms() { sed 's/\x1b\[[0-9;]*m//g' "$SESSION_RUN_LOG" | grep -a "startup: stage $1" | head -1 \
                | grep -o '+[0-9]*ms' | head -1 | tr -d '+ms'; }

first_frame_ms=$(gate_ms 'first frame painted')
interactive_ms=$(gate_ms 'interactive')

if [[ -n "$first_frame_ms" ]] && (( first_frame_ms <= 1500 )); then
    pass "first frame at ${first_frame_ms}ms ≤ 1500ms"
elif [[ -n "$first_frame_ms" ]]; then
    fail "first frame at ${first_frame_ms}ms, over the 1500ms gate"
else
    fail 'the log never said a first frame was painted'
fi

if [[ -n "$interactive_ms" ]] && (( interactive_ms <= 2000 )); then
    pass "interactive at ${interactive_ms}ms ≤ 2000ms"
elif [[ -n "$interactive_ms" ]]; then
    fail "interactive at ${interactive_ms}ms, over the 2000ms gate"
else
    fail 'the log never said the shell became interactive'
fi

session_run_layerrule_note
# A real failure outranks a void one: something measured and over budget is a
# finding whatever else the window contained. Void alone is exit 2 — nothing
# here is a verdict on the shell, so re-run rather than read it as one.
(( fail_count )) && exit 1
if (( void_count )); then
    printf 'that is %d criterion/criteria this window could not judge — re-run when nothing\nelse is on the compositor' "$void_count"
    if [[ -n "$fired_rungs" ]]; then
        printf ', and either on mains or with --seconds under the first\narmed rung (see --help)'
    fi
    printf '\n'
    exit 2
fi
exit 0
