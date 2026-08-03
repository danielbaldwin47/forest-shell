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
# counted.
#
# The shell pushes a Hyprland layerrule for its own namespace at startup (#78)
# and there is no clearing verb in the 0.5x syntax, so the rule outlives the
# process. `hyprctl reload` clears it; this script says so rather than doing it,
# because reloading the compositor is the caller's session's business.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=qs-runtime.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qs-runtime.sh"

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

cleanup() {
    local exit_status=$?
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
start_time=$(date +%s.%N)

note "measuring for ${SECONDS_WINDOW}s — do not touch the machine"
sleep "$SECONDS_WINDOW"

end_ticks=$(cpu_ticks "$SHELL_PID")
end_switches=$(switches "$SHELL_PID")
end_frames=$(frames "$LOG")
end_time=$(date +%s.%N)

if [[ -z "$end_ticks" ]]; then
    echo "the shell died during the window — see $LOG" >&2
    exit 1
fi

printf '\n'
python3 - "$start_ticks" "$end_ticks" "$start_switches" "$end_switches" \
          "$start_frames" "$end_frames" "$start_time" "$end_time" "$ticks_per_second" <<'PY'
import sys

start_ticks, end_ticks, start_sw, end_sw, start_fr, end_fr = (int(v) for v in sys.argv[1:7])
start_time, end_time = float(sys.argv[7]), float(sys.argv[8])
hz = int(sys.argv[9])

elapsed = end_time - start_time
cpu_seconds = (end_ticks - start_ticks) / hz
print(f"  window      {elapsed:.1f}s")
print(f"  cpu         {cpu_seconds:.3f}s of core time — {cpu_seconds / elapsed * 100:.3f}% of one core")
print(f"  switches    {end_sw - start_sw} — {(end_sw - start_sw) / elapsed:.2f}/s")
print(f"  frames      {end_fr - start_fr} — one per {elapsed / max(1, end_fr - start_fr):.1f}s")
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
if python3 -c "import sys; sys.exit(0 if $cpu_percent <= 0.5 else 1)"; then
    pass "idle CPU $(printf '%.3f' "$cpu_percent")% ≤ 0.5%"
else
    fail "idle CPU $(printf '%.3f' "$cpu_percent")% over the 0.5% budget"
fi

if python3 -c "import sys; sys.exit(0 if $switch_rate < 5 else 1)"; then
    pass "$(printf '%.2f' "$switch_rate") context switches/s < 5/s"
else
    fail "$(printf '%.2f' "$switch_rate") context switches/s over the 5/s budget"
fi

# The clock is the one thing that may repaint at rest, once a minute on the
# minute (Surfaces/Bar/Modules/Clock.qml). Anything much past that is an
# animation that did not stop.
if (( frame_count <= expected_frames )); then
    pass "$frame_count frames in ${SECONDS_WINDOW}s — the clock, and nothing else"
else
    fail "$frame_count frames in ${SECONDS_WINDOW}s, expected at most $expected_frames"
fi

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
(( fail_count )) && exit 1
exit 0
