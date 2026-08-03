#!/usr/bin/env bash
# Measure the idle budget on a real session (#22 §5, the method fixed by #95).
#
#   tools/idle-budget.sh                  # 195 s window, the real shell
#   tools/idle-budget.sh --seconds 120
#   tools/idle-budget.sh --keep           # leave the shell up afterwards
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

# shellcheck source=qs-runtime.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qs-runtime.sh"
# shellcheck source=load-window.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/load-window.sh"

SECONDS_WINDOW=195
ENTRY="shell.qml"
KEEP=0

while (( $# )); do
    case "$1" in
        --seconds) SECONDS_WINDOW="$2"; shift 2 ;;
        --entry)   ENTRY="$2"; shift 2 ;;
        --keep)    KEEP=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ -n "${WAYLAND_DISPLAY:-}" ]] || { echo "no WAYLAND_DISPLAY — this needs a real session" >&2; exit 2; }

pass_count=0
fail_count=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail_count=$((fail_count + 1)); }
note() { printf '  ....  %s\n' "$1"; }

LOG=$(mktemp -t forest-idle.XXXXXX.log)

# QSG_RENDER_TIMING makes the scenegraph print a line per rendered frame. It is
# the only way to count repaints from outside, and it costs a printf per frame —
# which is why it is here and not in the shell.
QS_RUNTIME=$(qs_runtime_bin) || exit 1

QSG_RENDER_TIMING=1 QT_ASSUME_STDERR_HAS_CONSOLE=1 \
    "$QS_RUNTIME" -p "$ENTRY" > "$LOG" 2>&1 &
SHELL_PID=$!

# When the repaints happened, and not just how many — the gap list is what says
# a count of six is the clock rather than three pairs ten seconds apart, and it
# is what diagnosed #137 (`10.8s, 41.1s, 29.9s, 9.9s …`: a cluster waking the
# shell every ten seconds, hiding inside a count that was only three over).
#
# Stamped here because the scenegraph's own line carries no time. A separate
# reader rather than a filter in the pipeline above, so `$!` stays the shell's
# own pid — /proc/<pid>/stat is where the other two budgets come from.
STAMPS=$(mktemp -t forest-idle-frames.XXXXXX)
tail -n0 -F "$LOG" 2>/dev/null \
    | grep --line-buffered -a 'frame rendered in' \
    | while IFS= read -r _; do printf '%s\n' "$EPOCHREALTIME"; done > "$STAMPS" &
STAMP_PID=$!

cleanup() {
    local exit_status=$?
    load_window_stop
    pkill -P "$STAMP_PID" 2>/dev/null
    kill "$STAMP_PID" 2>/dev/null
    rm -f "$STAMPS"
    if (( KEEP )); then
        printf '\nshell left up (pid %s), log: %s\n' "$SHELL_PID" "$LOG"
        return
    fi
    kill "$SHELL_PID" 2>/dev/null
    wait "$SHELL_PID" 2>/dev/null
    # Kept whenever anything went wrong — including the paths that exit before
    # a check has run, which are the ones where the log is the only evidence
    # there is (a shell that never reached interactive says why in there).
    if (( fail_count )) || (( exit_status )); then
        printf 'log kept: %s\n' "$LOG"
    else
        rm -f "$LOG"
    fi
}
trap cleanup EXIT

for _ in $(seq 1 300); do
    grep -qa 'startup: stage interactive' "$LOG" && break
    sleep 0.1
done
if ! grep -qa 'startup: stage interactive' "$LOG"; then
    echo "the shell never reached interactive — see $LOG" >&2
    exit 1
fi
note "shell up (pid $SHELL_PID) — settling for 10 s before the window opens"

# The first seconds are startup, not idle: wallpaper decode, the deferred stage,
# and each native service's first DBus reply all land in them — the last of
# those is the slowest, at about a second per backend, and each one that changes
# a glyph on the bar costs the repaint that draws it.
sleep 10

ticks_per_second=$(getconf CLK_TCK)
cpu_ticks() { awk '{print $14 + $15}' "/proc/$1/stat" 2>/dev/null; }
switches()  { awk '/ctxt_switches/ {total += $2} END {print total}' "/proc/$1/status" 2>/dev/null; }
# The scenegraph's own wording, which is `syncAndRender: frame rendered in Nms`
# — one line per presented frame, per window. `grep -c` prints its count and
# *exits 1* when that count is zero, so the obvious `|| echo 0` fallback would
# append a second number to the first.
frames()    { local count; count=$(grep -ac 'frame rendered in' "$1" 2>/dev/null); echo "${count:-0}"; }

start_ticks=$(cpu_ticks "$SHELL_PID")
start_switches=$(switches "$SHELL_PID")
start_frames=$(frames "$LOG")
start_lines=$(grep -ac '' "$LOG")
start_time=$(date +%s.%N)
load_window_start

note "measuring for ${SECONDS_WINDOW}s — do not touch the machine"
sleep "$SECONDS_WINDOW"

end_ticks=$(cpu_ticks "$SHELL_PID")
end_switches=$(switches "$SHELL_PID")
end_frames=$(frames "$LOG")
end_time=$(date +%s.%N)
load_window_report

if [[ -z "$end_ticks" ]]; then
    echo "the shell died during the window — see $LOG" >&2
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
compositor_events=$(tail -n +"$((start_lines + 1))" "$LOG" \
    | grep -ac 'compositor: \(workspace .* focused\|focused window\)')
compositor_events=${compositor_events:-0}

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
screens=$(grep -ac 'bar: content ready on' "$LOG")
screens=${screens:-1}
(( screens )) || screens=1
expected_frames=$(python3 -c "import math; print(2 * $screens * (math.ceil($SECONDS_WINDOW / 60) + 1))")

printf '\n'
if (( compositor_events )); then
    note "$compositor_events compositor event(s) inside the window — workspace switches or"
    note "active-window changes, so this session was in use while it was measured"
    printf '\n'
fi

# What a driven window does and does not void. Input only ever *adds* work — a
# workspace switch animates the ridgeline, a hover repaints a module — so a
# reading that passes its budget under input passes it at rest too, and that
# pass is real. A reading that fails one has no such argument: it might be the
# shell, it might be whoever was driving. So the three criteria split by
# direction rather than all going out together, and only the frame count, whose
# budget the driving directly writes, is void either way.
void_count=0
void() { printf '  \033[33m????\033[0m  %s\n' "$1"; void_count=$((void_count + 1)); }
driven=$(( compositor_events > 0 ))

if python3 -c "import sys; sys.exit(0 if $cpu_percent <= 0.5 else 1)"; then
    if (( driven )); then
        pass "idle CPU $(printf '%.3f' "$cpu_percent")% ≤ 0.5% — under input, so an upper bound"
    else
        pass "idle CPU $(printf '%.3f' "$cpu_percent")% ≤ 0.5%"
    fi
elif (( driven )); then
    void "idle CPU $(printf '%.3f' "$cpu_percent")% over budget, but the window was driven"
else
    fail "idle CPU $(printf '%.3f' "$cpu_percent")% over the 0.5% budget"
fi

if python3 -c "import sys; sys.exit(0 if $switch_rate < 5 else 1)"; then
    if (( driven )); then
        pass "$(printf '%.2f' "$switch_rate") context switches/s < 5/s — under input, so an upper bound"
    else
        pass "$(printf '%.2f' "$switch_rate") context switches/s < 5/s"
    fi
elif (( driven )); then
    void "$(printf '%.2f' "$switch_rate") context switches/s over budget, but the window was driven"
else
    fail "$(printf '%.2f' "$switch_rate") context switches/s over the 5/s budget"
fi

# The clock is the one thing that may repaint at rest, once a minute on the
# minute (Surfaces/Bar/Modules/Clock.qml). Anything much past that is an
# animation that did not stop.
if (( driven )); then
    void "$frame_count frames in ${SECONDS_WINDOW}s, but the window was driven — every"
    note "     switch and hover in it is a repaint the criterion never asked about"
elif (( frame_count <= expected_frames )); then
    pass "$frame_count frames in ${SECONDS_WINDOW}s — the clock, and nothing else"
else
    fail "$frame_count frames in ${SECONDS_WINDOW}s, expected at most $expected_frames"
fi

# The count alone cannot say "on the minute", which is what #22 §5 actually
# asks — #73 proved it with the list, `gaps (ms): [59999, 59999, 60000, …]`.
# The threshold drops the sub-second pairs, which are the second window
# rendering the same repaint moment rather than a repaint of their own.
python3 "$(dirname "${BASH_SOURCE[0]}")/measure-frame-timing.py" "$LOG" \
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
gate_ms() { sed 's/\x1b\[[0-9;]*m//g' "$LOG" | grep -a "startup: stage $1" | head -1 \
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

printf '\nthe shell pushed a Hyprland layerrule that outlives it — `hyprctl reload` clears it\n'
# A real failure outranks a void one: something measured and over budget is a
# finding whatever else the window contained. Void alone is exit 2 — nothing
# here is a verdict on the shell, so re-run rather than read it as one.
(( fail_count )) && exit 1
if (( void_count )); then
    printf 'that is %d criterion/criteria this window could not judge — re-run when nothing\nelse is on the compositor\n' "$void_count"
    exit 2
fi
exit 0
