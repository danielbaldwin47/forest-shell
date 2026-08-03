#!/usr/bin/env bash
# The frame-budget arithmetic (#95, #22 §6).
#
# `tools/measure-frame-timing.py` turns a QSG_RENDER_TIMING log into the four
# numbers §6 is judged on. That is a decision — a parse, a percentile and a
# gate — so it wants seam 1, even though the log it eats can only be produced
# by a real session (`tools/frame-budget.sh`, seam 3's third cousin). Same
# precedent as tst_qs_runtime.sh: a seam-1 check that is not a .qml file,
# because qmltestrunner only eats QML.
#
# The one ruling worth pinning here rather than in prose: **the gate is on
# `render`, not on `total`**. #73 measured 40 of 59 toast frames apparently
# blowing an 8 ms budget, all of it `swap` blocking on the Wayland frame
# callback at 16.7 ms. Gating on total would condemn a shell doing 0.5 ms of
# work, so the gate reads render and the report prints all three.
set -euo pipefail
cd "$(dirname "$0")"

MEASURE=../tools/measure-frame-timing.py

failures=0

# Asserts one output line matches, so a test names the number it cares about
# rather than the whole report.
check_line() {
    local desc=$1 log=$2 want=$3
    local got rc=0
    got=$(printf '%s\n' "$log" | python3 "$MEASURE" 2>&1) || rc=$?
    if grep -qxF "$want" <<<"$got"; then
        printf 'PASS  %s\n' "$desc"
    else
        printf 'FAIL  %s\n        want line: %s\n        got:\n%s\n' "$desc" "$want" "$got"
        failures=$((failures + 1))
    fi
}

check_rc() {
    local desc=$1 log=$2 want_rc=$3
    shift 3
    local rc=0
    printf '%s\n' "$log" | python3 "$MEASURE" "$@" >/dev/null 2>&1 || rc=$?
    if [[ "$rc" == "$want_rc" ]]; then
        printf 'PASS  %s\n' "$desc"
    else
        printf 'FAIL  %s\n        want rc %s, got rc %s\n' "$desc" "$want_rc" "$rc"
        failures=$((failures + 1))
    fi
}

frame() { printf 'qt.scenegraph.time.renderloop: [window 0x1][render thread 0x2] syncAndRender: frame rendered in %sms, sync=%s, render=%s, swap=%s\n' "$1" "0" "$2" "$3"; }
gap()   { printf 'qt.scenegraph.time.renderloop: [window 0x1][render thread 0x2] syncAndRender: start, elapsed since last call: %s ms\n' "$1"; }

# --- the parse --------------------------------------------------------------
# The real log is ANSI-coloured (QT_ASSUME_STDERR_HAS_CONSOLE=1, which the
# harnesses set because Qt otherwise says nothing at all into a pipe), and the
# window and thread pointers differ per line. Neither may reach the numbers.
ansi=$'\x1b[34m DEBUG\x1b[97m qt.scenegraph.time.renderloop\x1b[0m: [window 0x7f13][render thread 0x7f1a] syncAndRender: frame rendered in 4ms, sync=1, render=2, swap=1'
check_line 'an ANSI-coloured line still parses' "$ansi" 'frames  1'
check_line 'and its render is read, not its total' "$ansi" 'render  max=2 mean=2.00 p95=2 over=0/1'

# A line that is not a rendered frame — the scenegraph prints several per frame
# — must not become a sample.
check_line 'polishAndSync lines are not frames' \
    "$(frame 4 2 1; printf 'qt.scenegraph.time.renderloop: [window 0x1][gui thread] polishAndSync: start, elapsed since last call: 15 ms\n')" \
    'frames  1'

# --- the three series -------------------------------------------------------
# #73's own shape: one outlier that is all swap, the rest at zero.
three=$(frame 15 7 13; frame 0 0 0; frame 1 0 1; frame 0 0 0)
check_line 'total is reported'  "$three" 'total   max=15 mean=4.00 p95=15 over=1/4'
check_line 'render is reported' "$three" 'render  max=7 mean=1.75 p95=7 over=0/4'
check_line 'swap is reported'   "$three" 'swap    max=13 mean=3.50 p95=13 over=1/4'

# p95 is nearest-rank on the sorted samples: with 20 frames the 19th is p95.
# The mean would hide exactly the frame this criterion is about, which is why
# the report carries both.
twenty=$(for i in $(seq 1 19); do frame 0 0 0; done; frame 12 12 0)
check_line 'p95 is nearest-rank, not interpolated' "$twenty" 'render  max=12 mean=0.60 p95=0 over=1/20'

# --- pacing -----------------------------------------------------------------
# Gaps come off the `elapsed since last call` lines, which is the only wall
# clock the scenegraph prints. fps is derived from the median rather than the
# mean because a run that drives an interaction, waits, and drives another has
# idle stretches between the animations: they are not dropped frames and must
# not read as a frame rate collapse.
paced=$(gap 16; gap 17; gap 16; gap 500; gap 16)
check_line 'fps comes off the median gap' "$paced" 'pacing  fps=62.5 median-gap=16ms max-gap=500ms over-20ms=1/5'

# --- the gate ---------------------------------------------------------------
check_rc 'a clean run passes'                  "$(frame 4 2 1)"   0 --budget-ms 8
check_rc 'render over the budget fails'        "$(frame 9 9 0)"   1 --budget-ms 8
check_rc 'swap over the budget alone passes'   "$(frame 17 0 17)" 0 --budget-ms 8
check_rc 'a log with no frames fails'          "nothing here"     1 --budget-ms 8

# A run that did not collect enough frames has not measured the criterion,
# whatever its numbers say — the interaction failed to drive anything.
check_rc 'too few frames fails'                "$(frame 0 0 0)"   1 --budget-ms 8 --min-frames 100
check_rc 'enough frames passes'                "$(frame 0 0 0)"   0 --budget-ms 8 --min-frames 1

if (( failures )); then
    printf '\n%d frame-timing check(s) failed\n' "$failures" >&2
    exit 1
fi
printf '\nframe-timing: all checks passed\n'
