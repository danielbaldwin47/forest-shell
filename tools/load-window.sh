#!/usr/bin/env bash
# What else the machine was doing while a performance window was measured.
# Sourced by tools/idle-budget.sh and tools/frame-budget.sh, never executed.
#
#   load_window_start          # begins sampling /proc/loadavg
#   load_window_report         # "load    start=0.42 peak=0.91 end=0.55"
#
# #95 is the reason this exists. Both budgets are per-process — the shell's own
# CPU, the shell's own frames — but neither is per-process in the way that
# matters: a render thread that wants 0.4 ms of GPU time takes longer to get it
# on a machine running eight other things, and the number lands in the report
# with nothing next to it saying so. The first #95 frame run measured a 16 ms
# render spike at load 9.2 on a four-core laptop, which is a fact about the
# laptop and not about the shell.
#
# It records rather than gates: no budget here, because there is no honest
# threshold for "quiet enough". A reader comparing two runs needs to see it.

LOAD_WINDOW_SAMPLES=""
LOAD_WINDOW_PID=""

load_window_start() {
    LOAD_WINDOW_SAMPLES=$(mktemp -t forest-load.XXXXXX)
    ( while :; do awk '{print $1}' /proc/loadavg >> "$LOAD_WINDOW_SAMPLES"; sleep 5; done ) &
    LOAD_WINDOW_PID=$!
}

# Stops the sampler and drops its file without printing. For the cleanup paths:
# `while :; do … sleep 5; done` in the background outlives a SIGTERM'd script
# and keeps appending to a temp file nobody will read.
load_window_stop() {
    [[ -n "$LOAD_WINDOW_PID" ]] || return 0
    kill "$LOAD_WINDOW_PID" 2>/dev/null
    wait "$LOAD_WINDOW_PID" 2>/dev/null
    rm -f "$LOAD_WINDOW_SAMPLES"
    LOAD_WINDOW_PID=""
}

load_window_report() {
    [[ -n "$LOAD_WINDOW_PID" ]] || return 0
    kill "$LOAD_WINDOW_PID" 2>/dev/null
    wait "$LOAD_WINDOW_PID" 2>/dev/null
    awk 'NR==1 {first=$1; peak=$1} {if ($1 > peak) peak=$1; last=$1}
         END {if (NR) printf "  ....  load    start=%.2f peak=%.2f end=%.2f (1-min average, all processes)\n", first, peak, last}' \
        "$LOAD_WINDOW_SAMPLES"
    rm -f "$LOAD_WINDOW_SAMPLES"
    LOAD_WINDOW_PID=""
}
