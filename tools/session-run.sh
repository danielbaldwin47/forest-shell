#!/usr/bin/env bash
# Running the real shell on the caller's own Wayland session, and giving the
# session back. Sourced by tools/idle-budget.sh and tools/frame-budget.sh,
# never executed.
#
#   source "$(dirname "$0")/session-run.sh"    # brings qs-runtime + load-window
#   session_run_require_session                # WAYLAND_DISPLAY or exit 2
#   session_run_launch forest-idle shell.qml   # sets SESSION_RUN_LOG / _PID
#   session_run_settle 10 'before the window opens'
#
# The teardown is the caller's EXIT trap, and the status has to be caught in its
# first line — anything before it overwrites `$?`, and a trap body of
# `my_extras; session_run_teardown $?` would hand over the status of my_extras
# instead of the script's. That is what decides whether the log is kept, so both
# harnesses spell it out:
#
#   cleanup() {
#       local exit_status=$?
#       my_extras
#       session_run_teardown "$exit_status"
#   }
#   trap cleanup EXIT
#
# **Not a seam, and not on the way to being one.** The two harnesses that source
# this are real-session tools for the reasons their own headers give — the
# nested compositor never presents a frame (#85), and a client-side capture has
# no frame pacing at all — and pulling their launch into one file does not
# change that. What is checkable is the one piece of arithmetic in here,
# `session_run_frames`, which is pinned by tests/tst_session_run.sh.
#
# Why it exists (#150): frame-budget.sh restated about sixty lines of
# idle-budget.sh — same launch, same wait for interactive, same settle, same
# conditions recording, same teardown — so the next fix to one silently missed
# the other. What stays in each script is its own measurement and its own
# verdict; three verdicts each, pass / fail / **exit 2 inconclusive**, and that
# contract is the caller's to keep. Nothing here decides it.
#
# The shell pushes a Hyprland layerrule for its own namespace at startup (#78)
# and there is no clearing verb in the 0.5x syntax, so the rule outlives the
# process: session_run_layerrule_note prints the one line that says so, which
# each harness does rather than reloading the caller's compositor for them.

_session_run_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=qs-runtime.sh
source "$_session_run_dir/qs-runtime.sh"
# shellcheck source=load-window.sh
source "$_session_run_dir/load-window.sh"

# Set by session_run_launch, read by everything downstream of it.
SESSION_RUN_LOG=""
SESSION_RUN_PID=""
# The harness's own --keep flag assigns this before teardown runs.
SESSION_RUN_KEEP=0

# The verdict vocabulary, kept unprefixed because it is what every harness in
# tools/ calls it — the ones that do not source this file still declare their
# own copy, and matching them is what lets one of those adopt this without
# rewriting its report. session_run_teardown reads fail_count to decide whether
# the log is evidence or litter, which is why the counter lives here with the
# functions that move it rather than in the harness.
pass_count=0
fail_count=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail_count=$((fail_count + 1)); }
note() { printf '  ....  %s\n' "$1"; }

# There is no fallback for this one: the whole point of these harnesses is that
# they run where a compositor will actually present what the shell draws.
session_run_require_session() {
    [[ -n "${WAYLAND_DISPLAY:-}" ]] && return 0
    echo "no WAYLAND_DISPLAY — this needs a real session" >&2
    exit 2
}

# For the harnesses that drive the session as well as watch it.
#
# A stale HYPRLAND_INSTANCE_SIGNATURE is the failure mode worth naming: it is
# inherited by anything that outlives a compositor restart, hyprctl then talks
# to a socket that is not there, and every dispatch would silently do nothing
# while the run still reported its numbers.
session_run_require_hyprctl() {
    command -v hyprctl >/dev/null || {
        echo "no hyprctl — the interaction is driven over Hyprland's IPC" >&2
        exit 2
    }
    hyprctl version >/dev/null 2>&1 || {
        echo "hyprctl cannot reach the compositor — HYPRLAND_INSTANCE_SIGNATURE is unset or stale" >&2
        exit 2
    }
}

# Launches the shell into a fresh log. $1 names the log (mktemp prefix), $2 is
# the QML entry point.
#
# QSG_RENDER_TIMING makes the scenegraph print a line per rendered frame. It is
# the only way to count repaints from outside, and it costs a printf per frame —
# which is why it is here and not in the shell.
session_run_launch() {
    local prefix=$1 entry=$2 runtime
    runtime=$(qs_runtime_bin) || return 1
    SESSION_RUN_LOG=$(mktemp -t "$prefix.XXXXXX.log")
    QSG_RENDER_TIMING=1 QT_ASSUME_STDERR_HAS_CONSOLE=1 \
        "$runtime" -p "$entry" > "$SESSION_RUN_LOG" 2>&1 &
    SESSION_RUN_PID=$!
}

# Waits for the shell to say it is interactive, then sits out the startup.
# $1 is the settle in seconds, $2 the tail of the line that announces it.
#
# The first seconds are startup, not measurement: wallpaper decode, the deferred
# stage, and each native service's first DBus reply all land in them — the last
# of those is the slowest, at about a second per backend, and each one that
# changes a glyph on the bar costs the repaint that draws it.
#
# Returns 1 rather than exiting, so the caller's trap still runs and keeps the
# log: a shell that never reached interactive says why in there.
session_run_settle() {
    local seconds=${1:-10} what=${2:-before the run}
    for _ in $(seq 1 300); do
        grep -qa 'startup: stage interactive' "$SESSION_RUN_LOG" && break
        sleep 0.1
    done
    if ! grep -qa 'startup: stage interactive' "$SESSION_RUN_LOG"; then
        echo "the shell never reached interactive — see $SESSION_RUN_LOG" >&2
        return 1
    fi
    note "shell up (pid $SESSION_RUN_PID) — settling for ${seconds} s $what"
    sleep "$seconds"
}

# The line count a measured window starts at. The parsers are told to ignore
# everything above it rather than the log being truncated, so a failed run still
# has its startup in the file that gets kept.
session_run_mark() {
    grep -ac '' "$SESSION_RUN_LOG"
}

# How many frames the scenegraph logged in $1, counting from line $2 onwards
# (default: the whole file). The wording is the scenegraph's own,
# `syncAndRender: frame rendered in Nms` — one line per presented frame, per
# window.
#
# `grep -c` prints its count and *exits 1* when that count is zero, so the
# obvious `|| echo 0` fallback would append a second number to the first. The
# substitution default below is the fix, and tests/tst_session_run.sh pins it.
session_run_frames() {
    local log=$1 from=${2:-0} count
    count=$(tail -n +"$((from + 1))" "$log" 2>/dev/null | grep -ac 'frame rendered in')
    echo "${count:-0}"
}

# Stops the conditions sampler, puts the shell down, and decides what happens to
# the log. Call it last from the caller's EXIT trap, passing the trap's own
# status: `trap 'session_run_teardown $?' EXIT`.
#
# The log is kept whenever anything went wrong — including the paths that exit
# before a check has run, which are the ones where it is the only evidence
# there is.
session_run_teardown() {
    local exit_status=${1:-0}
    load_window_stop
    [[ -n "$SESSION_RUN_PID" ]] || return 0
    if (( SESSION_RUN_KEEP )); then
        printf '\nshell left up (pid %s), log: %s\n' "$SESSION_RUN_PID" "$SESSION_RUN_LOG"
        return 0
    fi
    kill "$SESSION_RUN_PID" 2>/dev/null
    wait "$SESSION_RUN_PID" 2>/dev/null
    if (( fail_count )) || (( exit_status )); then
        printf 'log kept: %s\n' "$SESSION_RUN_LOG"
    else
        rm -f "$SESSION_RUN_LOG"
    fi
}

# What the caller's session is left holding, and how to get rid of it (#78).
session_run_layerrule_note() {
    printf '\nthe shell pushed a Hyprland layerrule that outlives it — `hyprctl reload` clears it\n'
}
