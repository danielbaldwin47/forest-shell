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

runner=$(command -v qmltestrunner || true)
[[ -n "$runner" ]] || runner=/usr/lib/qt6/bin/qmltestrunner   # not on PATH on Arch
[[ -x "$runner" ]] || { echo "qmltestrunner not found (tried PATH and $runner)" >&2; exit 1; }

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

# The blur measurement's arithmetic (#97). The harness that takes the two
# captures needs a real compositor, but "does this pair show a blur" is a
# decision, and a box blur applied here is the picture the compositor is
# supposed to produce — so the tool that reads it is checkable without one.
"$python" tst_measure_blur.py

# Same reason, different language: which quickshell binary may run the shell is
# a decision (parse a version, compare against a floor), but it is bash, and
# qmltestrunner only loads QML. It rides along here (#57).
bash tst_qs_runtime.sh

exec "$runner" -input .
