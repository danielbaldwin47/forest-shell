#!/usr/bin/env bash
# Measure the frame budget on a real session (#22 §6, re-measured by #95).
#
#   tools/frame-budget.sh                 # ~120 bar-interaction frames
#   tools/frame-budget.sh --frames 200
#   tools/frame-budget.sh --keep          # leave the shell up afterwards
#
# The sibling of tools/idle-budget.sh, and not a seam for the same reasons: the
# nested compositor never presents a frame (#85), so a frame time measured in
# there is a claim about a frame nobody saw, and a client-side capture has no
# frame pacing at all. This runs the real shell on the caller's own Wayland
# session and drives the bar from the compositor's IPC — which means it takes
# the pointer and the active workspace for the length of the run, and puts them
# back afterwards.
#
# What "bar interaction" means here is what #75 made true: a workspace switch
# animates the ridgeline, so switching drives the bar's own animation rather
# than the compositor's. A pointer sweep across the bar is added on top for the
# hover repaints. Both are frames the shell renders because the user did
# something, which is what §6 is about.
#
# The number §6 means is `render` — see tools/measure-frame-timing.py, which
# owns that ruling and the arithmetic. This file owns getting a log that is
# worth arithmetic.
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=qs-runtime.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qs-runtime.sh"
# shellcheck source=load-window.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/load-window.sh"

TARGET_FRAMES=120
BUDGET_MS=8
ENTRY="shell.qml"
KEEP=0
DRIVE_CAP_SECONDS=90

while (( $# )); do
    case "$1" in
        --frames)    TARGET_FRAMES="$2"; shift 2 ;;
        --budget-ms) BUDGET_MS="$2"; shift 2 ;;
        --entry)     ENTRY="$2"; shift 2 ;;
        --keep)      KEEP=1; shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ -n "${WAYLAND_DISPLAY:-}" ]] || { echo "no WAYLAND_DISPLAY — this needs a real session" >&2; exit 2; }
command -v hyprctl >/dev/null || { echo "no hyprctl — the interaction is driven over Hyprland's IPC" >&2; exit 2; }
# A stale HYPRLAND_INSTANCE_SIGNATURE is the failure mode worth naming: it is
# inherited by anything that outlives a compositor restart, hyprctl then talks
# to a socket that is not there, and every dispatch below would silently do
# nothing while the run still reported a frame count.
hyprctl version >/dev/null 2>&1 || {
    echo "hyprctl cannot reach the compositor — HYPRLAND_INSTANCE_SIGNATURE is unset or stale" >&2
    exit 2
}

pass_count=0
fail_count=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail_count=$((fail_count + 1)); }
note() { printf '  ....  %s\n' "$1"; }

LOG=$(mktemp -t forest-frame.XXXXXX.log)

QS_RUNTIME=$(qs_runtime_bin) || exit 1

QSG_RENDER_TIMING=1 QT_ASSUME_STDERR_HAS_CONSOLE=1 \
    "$QS_RUNTIME" -p "$ENTRY" > "$LOG" 2>&1 &
SHELL_PID=$!

HOME_WORKSPACE=$(hyprctl activeworkspace -j 2>/dev/null | grep -o '"id": *[0-9-]*' | head -1 | grep -o '[0-9-]*$')
HOME_CURSOR=$(hyprctl cursorpos 2>/dev/null | tr -d ' ')

restore_session() {
    # The caller was looking at a workspace and had a pointer somewhere. Put
    # both back before anything else, including on the failure paths.
    [[ -n "$HOME_WORKSPACE" ]] && hyprctl dispatch workspace "$HOME_WORKSPACE" >/dev/null 2>&1
    [[ -n "$HOME_CURSOR" ]] && hyprctl dispatch movecursor "${HOME_CURSOR%,*}" "${HOME_CURSOR#*,}" >/dev/null 2>&1
}

cleanup() {
    local exit_status=$?
    restore_session
    load_window_stop
    if (( KEEP )); then
        printf '\nshell left up (pid %s), log: %s\n' "$SHELL_PID" "$LOG"
        return
    fi
    kill "$SHELL_PID" 2>/dev/null
    wait "$SHELL_PID" 2>/dev/null
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
note "shell up (pid $SHELL_PID) — settling for 10 s before the run"

# Same reason as the idle harness: the first seconds are startup, not
# interaction. Every native service's first DBus reply lands in them, and each
# one that changes a glyph on the bar costs the repaint that draws it — frames
# that belong to no interaction at all.
sleep 10

# Everything from here is the measured window. The parser is told to ignore
# everything above it rather than the log being truncated, so a failed run
# still has its startup in the file that gets kept.
start_lines=$(grep -ac '' "$LOG")
load_window_start

frames_so_far() {
    local counted
    counted=$(tail -n +"$((start_lines + 1))" "$LOG" | grep -ac 'frame rendered in')
    echo "${counted:-0}"
}

# The workspaces to cycle. Hyprland destroys an empty workspace as soon as it
# is left, so a session sitting on one workspace would have this create and
# destroy a scratch one on every switch — which is a fine way to animate the
# ridgeline, but noisier than reusing what is already there.
mapfile -t WORKSPACES < <(hyprctl workspaces -j 2>/dev/null | grep -o '"id": *[0-9]*' | grep -o '[0-9]*$' | sort -n | head -4)
(( ${#WORKSPACES[@]} >= 2 )) || WORKSPACES=("${HOME_WORKSPACE:-1}" "$(( ${HOME_WORKSPACE:-1} + 1 ))")

# The bar is 40 px tall in layout units and sits at the top of the output; a
# sweep at y=20 crosses every module on it. Widths come off the compositor so
# this does not assume the machine it ran on last.
BAR_WIDTH=$(hyprctl monitors -j 2>/dev/null | grep -o '"width": *[0-9]*' | head -1 | grep -o '[0-9]*$')
BAR_WIDTH=${BAR_WIDTH:-1280}
MONITOR_SCALE=$(hyprctl monitors -j 2>/dev/null | grep -o '"scale": *[0-9.]*' | head -1 | grep -o '[0-9.]*$')
# `movecursor` speaks logical coordinates; the reported width is physical.
BAR_WIDTH=$(python3 -c "print(int($BAR_WIDTH / max(0.1, ${MONITOR_SCALE:-1})))")

note "driving the bar until ${TARGET_FRAMES} frames (workspace switches + pointer sweeps)"

drive_started=$(date +%s)
round=0
while (( $(frames_so_far) < TARGET_FRAMES )); do
    if (( $(date +%s) - drive_started > DRIVE_CAP_SECONDS )); then
        note "gave up driving after ${DRIVE_CAP_SECONDS}s"
        break
    fi
    round=$((round + 1))

    # A switch each way, with a beat between them: the ridgeline's animation is
    # the thing being measured, and starting the next one on top of it would
    # measure a shell that never finished the first.
    for workspace in "${WORKSPACES[@]}"; do
        hyprctl dispatch workspace "$workspace" >/dev/null 2>&1
        sleep 0.45
    done

    # A hover sweep across the bar, left to right, in eight steps.
    for step in 1 2 3 4 5 6 7 8; do
        hyprctl dispatch movecursor "$(( BAR_WIDTH * step / 9 ))" 20 >/dev/null 2>&1
        sleep 0.12
    done
done

restore_session
sleep 0.5

collected=$(frames_so_far)
note "$collected frames over $round round(s) of interaction"
load_window_report
printf '\n'

python3 tools/measure-frame-timing.py "$LOG" \
    --from-line "$start_lines" \
    --budget-ms "$BUDGET_MS" \
    --min-frames "$TARGET_FRAMES"
measured=$?

# Three verdicts, the same three the idle harness has: met, blown, and never
# measured. A run that hit DRIVE_CAP_SECONDS short of its frame target is the
# third — the interaction failed to drive the shell, so the frames it did
# collect are not a sample of anything, and reporting that as a blown budget is
# the exact misreading #95 was filed to undo.
printf '\n'
case "$measured" in
    0) pass "render stayed inside the ${BUDGET_MS}ms budget over $collected interaction frames" ;;
    2) printf '  \033[33m????\033[0m  the run never collected its frames — nothing here judges the budget\n'
       printf '\nthe shell pushed a Hyprland layerrule that outlives it — `hyprctl reload` clears it\n'
       exit 2 ;;
    *) fail "render went over the ${BUDGET_MS}ms budget — see the report above" ;;
esac

printf '\nthe shell pushed a Hyprland layerrule that outlives it — `hyprctl reload` clears it\n'
(( fail_count )) && exit 1
exit 0
