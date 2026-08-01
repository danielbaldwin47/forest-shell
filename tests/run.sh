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

# The vendored icon set is a checked-in invariant, not a build artifact: it is
# normalized in place, so "did someone drop a pristine upstream SVG in there"
# is a thing the test run should catch. Not a QML test, so it runs first and
# separately.
python=$(command -v python3 || true)
[[ -n "$python" ]] || { echo "python3 not found (needed for the icon set check)" >&2; exit 1; }
"$python" ../tools/normalize-lucide.py --check

exec "$runner" -input .
