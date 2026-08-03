#!/usr/bin/env bash
# Which quickshell binary is allowed to run forest-shell (#57).
#
# The decision under test is `qs_runtime_verdict`: given the first line of
# `<binary> --version`, is this upstream Quickshell at or above the floor the
# shell is written against? It is a decision rather than a picture, so it wants
# seam 1 — but it is bash, and qmltestrunner only eats QML. It runs from
# tests/run.sh alongside the other non-QML invariant checks (the vendored icons
# and the grain texture), which is the precedent for a seam-1 check that is not
# a .qml file.
#
# Resolution itself — PATH lookup, exec, the error text — is not tested here.
# That part is I/O; the part worth pinning is the verdict.
set -euo pipefail
cd "$(dirname "$0")"

# shellcheck source=../tools/qs-runtime.sh
source ../tools/qs-runtime.sh

failures=0

# Asserts the verdict string AND the exit status, because callers branch on the
# status and only ever print the string. A verdict that says "old:0.2.0" while
# exiting 0 would let a too-old runtime through silently.
check() {
    local desc=$1 input=$2 want=$3 want_rc=$4
    local got rc=0
    got=$(qs_runtime_verdict "$input") || rc=$?
    if [[ "$got" == "$want" && "$rc" == "$want_rc" ]]; then
        printf 'PASS  %s\n' "$desc"
    else
        printf 'FAIL  %s\n        input:  %q\n        want:   %s (rc %s)\n        got:    %s (rc %s)\n' \
            "$desc" "$input" "$want" "$want_rc" "$got" "$rc"
        failures=$((failures + 1))
    fi
}

# --- the two runtimes that actually exist on the build machine ---------------
# Upstream, as the pacman package prints it. Note the empty revision field: the
# Arch package builds without git metadata, so the parse must not depend on it.
check 'upstream at the floor is accepted' \
    'Quickshell 0.3.0 (revision , distributed by Arch Linux)' 'ok:0.3.0' 0

# The fork this ticket retires. It is /usr/bin/qs until the swap, it satisfies
# `command -v qs`, and it cannot run this shell — so the check exists mostly to
# catch this exact string.
check 'the noctalia fork is rejected by name' \
    'noctalia-qs 0.0.12 (revision 76c13298a1a3daf54f5e63db3aad3e71228e5d2c, distributed by Arch Linux)' \
    'fork:noctalia-qs' 1

# --- the floor --------------------------------------------------------------
check 'below the floor is rejected' 'Quickshell 0.2.9 (revision x)' 'old:0.2.9' 1
check 'above the floor is accepted' 'Quickshell 0.4.0 (revision x)' 'ok:0.4.0' 0
check 'a major bump is accepted, not string-compared' 'Quickshell 1.0.0' 'ok:1.0.0' 0
check 'two-digit minor sorts numerically, not lexically' 'Quickshell 0.10.0' 'ok:0.10.0' 0

# A pacman pkgrel suffix is not part of upstream's version. `0.3.0-2.1` is the
# same release as `0.3.0` and must not read as newer or as garbage.
check 'a pkgrel suffix is trimmed, not parsed' 'Quickshell 0.3.0-2.1 (revision x)' 'ok:0.3.0' 0

# --- degenerate input -------------------------------------------------------
# Every one of these must fail closed. A binary that cannot be identified is
# not assumed good: the swap is exactly the window where `qs` might be missing,
# half-installed, or a wrapper that prints nothing.
check 'empty output is unknown, not ok' '' 'unknown' 1
check 'a version-less name is unknown' 'Quickshell' 'unknown' 1
check 'a non-numeric version is unknown' 'Quickshell git-abcdef' 'unknown' 1
check 'an unrelated binary is a fork, not unknown' 'qmlscene 6.8.1' 'fork:qmlscene' 1

if (( failures )); then
    printf '\n%d qs-runtime check(s) failed\n' "$failures" >&2
    exit 1
fi
printf '\nqs-runtime: all checks passed\n'
