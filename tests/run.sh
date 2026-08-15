#!/usr/bin/env bash
# Unit tests for the Quickshell-free parts of forest-shell.
#
#   tests/run.sh            all tests
#   tests/run.sh tst_x.qml  one file
#
# Quickshell's QML modules are compiled into the quickshell binary rather than
# shipped as a loadable plugin, so qmltestrunner can only see files that import
# nothing but QtQuick. Anything touching FileView/PanelWindow is verified by
# launching the shell instead (see the ticket's acceptance criteria).
set -euo pipefail
cd "$(dirname "$0")"

# Without this Qt swallows console output when stderr is not a TTY.
export QT_ASSUME_STDERR_HAS_CONSOLE=1
export QT_QPA_PLATFORM=offscreen

# A handful of checks read a checked-in config file rather than a QML object —
# "does the file the integration guide tells you to source still contain the
# lines the shell documents" is a decision, and it belongs at this seam (#140).
# Qt refuses file:// XHR unless this is set.
export QML_XHR_ALLOW_FILE_READ=1

# Which qmltestrunner, and why it is not just the PATH hit: #215. A machine
# with Plasma has a Qt5 one there, and it cannot run a single file.
# shellcheck source=../tools/qmltestrunner.sh
source ../tools/qmltestrunner.sh
runner=$(qmltestrunner_resolve) || exit 1

if [[ $# -gt 0 ]]; then
  exec "$runner" -input "$1"
fi

# The vendored icon set and the grain texture are checked-in invariants, not
# build artifacts: both are generated in place from a script, so "did someone
# drop a pristine upstream SVG in there" and "is this still the texture the
# recipe makes" are things the test run should catch. Not QML tests, so they
# run first and separately.
python=$(command -v python3 || true)
[[ -n "$python" ]] || { echo "python3 not found (needed for the asset checks)" >&2; exit 1; }
"$python" ../tools/normalize-lucide.py --check
"$python" ../tools/make-noise.py --check

# No .qml file may carry a raw control byte (#149): a NUL makes git call the
# file binary, which makes every later diff of it unreviewable and hides it from
# grep. Not a QML test because it walks the tree, and not a grep because grep -P
# is the one tool that provably cannot match a NUL.
"$python" tst_control_bytes.py

# Every click target the shell draws shows a pointer (#185). Also a tree walk
# rather than a QML test: these widgets pull in
# Theme and Config, which qmltestrunner cannot load, so nothing here can be
# instantiated. It is the breadth half of the check — every target, every run —
# and tools/cursor-harness.sh is the half that reads what the shell actually
# asks the compositor for.
"$python" tst_pointer_affordance.py

# The blur measurement's arithmetic (#97). The harness that takes the two
# captures needs a real compositor, but "does this pair show a blur" is a
# decision, and a box blur applied here is the picture the compositor is
# supposed to produce — so the tool that reads it is checkable without one.
"$python" tst_measure_blur.py

# And the same shape for the idle budget's conditions (#176): "did that window
# measure the idle shell or the idle ladder" is a decision over a log and two
# numbers, even though only the window itself needs a real session.
"$python" tst_idle_rungs.py

# Same reason, different language: which quickshell binary may run the shell is
# a decision (parse a version, compare against a floor), but it is bash, and
# qmltestrunner only loads QML. It rides along here (#57).
bash tst_qs_runtime.sh

# And the decision this script itself made wrong until #215: which
# qmltestrunner. Same argument — a resolution rule in bash, verified where the
# QML runner cannot reach.
bash tst_qmltestrunner.sh

# Same shape again (#95): the frame budget's arithmetic — parse, percentile,
# gate — is a decision, but its input is a Qt log and its runner is bash.
bash tst_frame_timing.sh

# And the one decision inside the runner both budget harnesses now share (#150):
# how many frames a log holds, from a line onwards. The launch and the teardown
# around it need a real session; counting does not.
bash tst_session_run.sh

exec "$runner" -input .
