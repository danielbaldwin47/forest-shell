#!/usr/bin/env bash
# Which qmltestrunner runs the QML suite (#215).
#
# Two decisions live in tools/qmltestrunner.sh and both are pinned here:
#
#   qmltestrunner_qt_verdict  — given a binary's dynamic linkage, which Qt
#                               major is this runner?
#   qmltestrunner_resolve     — given the candidates on this machine, which
#                               one runs the suite?
#
# The bug that made this a seam-1 unit: on a machine with Plasma installed,
# qt5-declarative owns /usr/bin/qmltestrunner, so the PATH hit is a Qt5 binary.
# It fails every file with "Library import requires a version" and, under
# `set -euo pipefail`, kills the suite before it prints a Totals: line — which
# reads as "the QML phase never ran" rather than "wrong binary". A unit that
# fakes a Qt5 runner on PATH and asserts the Qt6 one is chosen catches it.
#
# It is bash, and qmltestrunner only eats QML, so this rides along in
# tests/run.sh next to tst_qs_runtime.sh — same precedent, same shape.
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../tools/qmltestrunner.sh
source ../tools/qmltestrunner.sh

failures=0

# Asserts the verdict string AND the exit status: callers branch on the status
# and only print the string, so a verdict that says qt5 while exiting 0 would
# select the broken runner anyway.
check_verdict() {
    local desc=$1 input=$2 want=$3 want_rc=$4
    local got rc=0
    got=$(qmltestrunner_qt_verdict "$input") || rc=$?
    if [[ "$got" == "$want" && "$rc" == "$want_rc" ]]; then
        printf 'PASS  %s\n' "$desc"
    else
        printf 'FAIL  %s\n        input:  %q\n        want:   %s (rc %s)\n        got:    %s (rc %s)\n' \
            "$desc" "$input" "$want" "$want_rc" "$got" "$rc"
        failures=$((failures + 1))
    fi
}

check_resolve() {
    local desc=$1 want=$2 want_rc=$3
    local got rc=0
    got=$(qmltestrunner_resolve 2>/dev/null) || rc=$?
    if [[ "$got" == "$want" && "$rc" == "$want_rc" ]]; then
        printf 'PASS  %s\n' "$desc"
    else
        printf 'FAIL  %s\n        want:   %s (rc %s)\n        got:    %s (rc %s)\n' \
            "$desc" "$want" "$want_rc" "$got" "$rc"
        failures=$((failures + 1))
    fi
}

# --- the linkage verdict ----------------------------------------------------
# Real `ldd` output, trimmed to the lines that decide it.
qt6_ldd='	libQt6QuickTest.so.6 => /usr/lib/libQt6QuickTest.so.6 (0x00007f0a)
	libQt6Qml.so.6 => /usr/lib/libQt6Qml.so.6 (0x00007f0b)
	libc.so.6 => /usr/lib/libc.so.6 (0x00007f0c)'
qt5_ldd='	libQt5QuickTest.so.5 => /usr/lib/libQt5QuickTest.so.5 (0x00007f0a)
	libQt5Qml.so.5 => /usr/lib/libQt5Qml.so.5 (0x00007f0b)
	libc.so.6 => /usr/lib/libc.so.6 (0x00007f0c)'

check_verdict 'a Qt6 runner is accepted' "$qt6_ldd" 'qt6' 0
check_verdict 'the qt5-declarative runner is rejected by its linkage' "$qt5_ldd" 'qt5' 1

# libc.so.6 is in every one of these lines. A verdict that matches a bare "6"
# anywhere would call the Qt5 runner a Qt6 one — the exact bug, undetected.
check_verdict 'libc.so.6 does not make a Qt5 runner look like Qt6' \
    '	libQt5Qml.so.5 => /usr/lib/libQt5Qml.so.5 (0x1)
	libc.so.6 => /usr/lib/libc.so.6 (0x2)' 'qt5' 1

# --- linkage that says nothing ----------------------------------------------
# Unknown is not rejection: a machine where the linkage cannot be read (no ldd,
# a static or wrapped binary, a distro that names its libraries differently)
# ran this suite fine before #215, and must keep running it. The resolver
# prefers a known-Qt6 candidate and only falls back to an unknown one.
check_verdict 'no Qt library in the linkage is unknown, not qt6' \
    '	libc.so.6 => /usr/lib/libc.so.6 (0x1)' 'unknown' 1
check_verdict 'empty linkage is unknown' '' 'unknown' 1
check_verdict "ldd's own error is unknown" \
    '	not a dynamic executable' 'unknown' 1

# A future Qt7 runner is not this suite's runner either, and must not read as
# unknown — unknown is the "cannot tell" fallback, and a Qt7 binary is a thing
# we can tell.
check_verdict 'a Qt7 runner is a known mismatch, not unknown' \
    '	libQt7QuickTest.so.7 => /usr/lib/libQt7QuickTest.so.7 (0x1)' 'qt7' 1

# --- resolution -------------------------------------------------------------
# Fakes rather than real runners: the point is which path is chosen, and a
# stub with the right name in the right place is the whole input. Linkage is
# stubbed too, keyed on the path, so the test never needs a Qt5 install.
fake_root=$(mktemp -d)
trap 'rm -rf "$fake_root"' EXIT
mkdir -p "$fake_root/path" "$fake_root/qt6" "$fake_root/elsewhere"
for d in path qt6 elsewhere; do
    printf '#!/bin/sh\nexit 0\n' >"$fake_root/$d/qmltestrunner"
    chmod +x "$fake_root/$d/qmltestrunner"
done

# The linkage each fake reports. Set per-case below; default is unreadable.
declare -A fake_linkage=()
qmltestrunner_linkage() { printf '%s\n' "${fake_linkage[$1]-}"; }

PATH="$fake_root/path:$PATH"

# The bug, as a unit. Qt5 on PATH, Qt6 at the packaged location.
QMLTESTRUNNER_CANDIDATES=("$fake_root/qt6/qmltestrunner")
fake_linkage=(["$fake_root/path/qmltestrunner"]="$qt5_ldd" \
              ["$fake_root/qt6/qmltestrunner"]="$qt6_ldd")
check_resolve 'a Qt5 runner on PATH loses to the Qt6 one off it' \
    "$fake_root/qt6/qmltestrunner" 0

# The T480 case that always worked: nothing at the packaged path, a Qt6 runner
# on PATH. The fix must not break it.
QMLTESTRUNNER_CANDIDATES=("$fake_root/nonexistent/qmltestrunner")
fake_linkage=(["$fake_root/path/qmltestrunner"]="$qt6_ldd")
check_resolve 'a Qt6 runner on PATH is used when there is no other' \
    "$fake_root/path/qmltestrunner" 0

# Nothing readable anywhere: use what there is rather than refusing to run.
QMLTESTRUNNER_CANDIDATES=("$fake_root/nonexistent/qmltestrunner")
fake_linkage=()
check_resolve 'an unreadable linkage is used rather than refused' \
    "$fake_root/path/qmltestrunner" 0

# ...but a *known-wrong* runner is refused even when it is the only one. It
# cannot run a single file, so exiting here with a message beats dying at the
# first import with no Totals: line, which is what #215 looked like.
QMLTESTRUNNER_CANDIDATES=("$fake_root/nonexistent/qmltestrunner")
fake_linkage=(["$fake_root/path/qmltestrunner"]="$qt5_ldd")
check_resolve 'a lone Qt5 runner is refused, not run' '' 1

# The error names every candidate it tried, with what each one was, so the
# reader can see both the wrong binary and the place the right one belongs.
err=$(qmltestrunner_resolve 2>&1 >/dev/null || true)
for want in "$fake_root/path/qmltestrunner" "$fake_root/nonexistent/qmltestrunner" qt5; do
    if [[ "$err" == *"$want"* ]]; then
        printf 'PASS  the refusal names %s\n' "$want"
    else
        printf 'FAIL  the refusal does not name %s\n        got: %s\n' "$want" "$err"
        failures=$((failures + 1))
    fi
done

# An explicit override wins over both, because the human saying which binary
# beats any guess this file makes. It is still verdicted: an override pointing
# at a Qt5 runner is the same broken run, just chosen by hand.
QMLTESTRUNNER_CANDIDATES=("$fake_root/qt6/qmltestrunner")
fake_linkage=(["$fake_root/path/qmltestrunner"]="$qt6_ldd" \
              ["$fake_root/qt6/qmltestrunner"]="$qt6_ldd" \
              ["$fake_root/elsewhere/qmltestrunner"]="$qt6_ldd")
QMLTESTRUNNER="$fake_root/elsewhere/qmltestrunner" \
    check_resolve 'QMLTESTRUNNER overrides both' \
        "$fake_root/elsewhere/qmltestrunner" 0

QMLTESTRUNNER="$fake_root/nonexistent/qmltestrunner" \
    check_resolve 'an override that is not there fails rather than falling back' '' 1

if (( failures )); then
    printf '\n%d qmltestrunner check(s) failed\n' "$failures" >&2
    exit 1
fi
printf '\nqmltestrunner: all checks passed\n'
