#!/usr/bin/env bash
# The one decision inside the shared real-session runner (#150).
#
# tools/session-run.sh is launch, settle and restore on the caller's own Wayland
# session — none of that is checkable at a seam, and its header says so. But one
# thing in it is arithmetic rather than I/O: how many frames the scenegraph
# logged, optionally from a line onwards. Both budget harnesses branch on that
# number, and it has a trap in it worth pinning — `grep -c` prints 0 *and exits
# 1* when nothing matched, so a naive `|| echo 0` appends a second number and
# every caller then reads "0 0" as a count.
#
# Same precedent as tests/tst_qs_runtime.sh: a seam-1 decision that happens to
# be bash, run from tests/run.sh alongside the other non-QML checks.
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../tools/session-run.sh
source ../tools/session-run.sh

failures=0

check() {
    local desc=$1 want=$2 got=$3
    if [[ "$got" == "$want" ]]; then
        printf 'PASS  %s\n' "$desc"
    else
        printf 'FAIL  %s\n        want:   %q\n        got:    %q\n' "$desc" "$want" "$got"
        failures=$((failures + 1))
    fi
}

fixture=$(mktemp -t forest-session-run.XXXXXX.log)
trap 'rm -f "$fixture"' EXIT

# The scenegraph's own wording, with the startup noise a real log has above it.
cat > "$fixture" <<'LOG'
[forest] +12ms  startup: stage first frame painted
[forest] +48ms  startup: stage interactive
qt.scenegraph.time.renderloop: syncAndRender: frame rendered in 1.2ms
qt.scenegraph.time.renderloop: syncAndRender: frame rendered in 0.9ms
[forest] +900ms compositor: workspace 2 focused
qt.scenegraph.time.renderloop: syncAndRender: frame rendered in 3.4ms
LOG

check 'counts every frame line in the file' \
    3 "$(session_run_frames "$fixture")"

# What the frame harness does with it: everything above the mark is startup, and
# the window is what came after.
check 'counts only the lines after the mark' \
    1 "$(session_run_frames "$fixture" 5)"

check 'a mark past the end of the log is no frames, not an error' \
    0 "$(session_run_frames "$fixture" 99)"

check 'an explicit mark of 0 is the whole file' \
    3 "$(session_run_frames "$fixture" 0)"

# The `grep -c` trap. A log with no frames in it is the ordinary case for a run
# that failed early, and it must read as the number 0 — one field, not two, and
# not the empty string that `(( ))` would then choke on.
empty=$(mktemp -t forest-session-run-empty.XXXXXX.log)
printf '[forest] +12ms  startup: stage interactive\n' > "$empty"
check 'no frames is the number 0' 0 "$(session_run_frames "$empty")"
check 'no frames is one field, not two' 1 "$(session_run_frames "$empty" | wc -w)"
rm -f "$empty"

# A log that is not there at all — the shell died before writing one, or a
# caller passed a path that never got created. Still a number, still silent.
check 'a missing log is no frames' \
    0 "$(session_run_frames /nonexistent/forest/log 2>/dev/null)"
check 'a missing log says nothing on stderr' \
    '' "$(session_run_frames /nonexistent/forest/log 2>&1 >/dev/null)"

if (( failures )); then
    printf '\n%d failure(s)\n' "$failures"
    exit 1
fi
printf '\nsession-run: all checks passed\n'
