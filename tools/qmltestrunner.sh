#!/usr/bin/env bash
# Which qmltestrunner runs the QML suite. Sourced, never executed.
#
#   source "$(dirname "$0")/../tools/qmltestrunner.sh"
#   runner=$(qmltestrunner_resolve) || exit 1
#
# Until #215 tests/run.sh took the PATH hit and only fell back to
# /usr/lib/qt6/bin/qmltestrunner when PATH had none. That is backwards on any
# machine with Plasma installed: qt5-declarative owns /usr/bin/qmltestrunner,
# so the PATH hit wins and it is a Qt5 binary. The suite's imports are Qt6
# style, so a Qt5 runner fails every file with "Library import requires a
# version" and — under `set -euo pipefail` — dies at the first one with no
# Totals: line at all. The failure reads as "the QML phase never ran", which
# sends the reader looking at the environment instead of at the binary.
#
# So the rule here is not an ordering, it is a property: *the runner must be
# the Qt6 one*. PATH is a place to look, not evidence. What decides is the
# binary's own dynamic linkage — a qmltestrunner links libQt<major>QuickTest,
# which is the thing the ticket's "linked Qt major" means and the one signal
# that cannot lie about which Qt it will hand the QML engine.
#
# Two verdicts, not one, because "wrong" and "cannot tell" earn different
# treatment. A known mismatch (Qt5) is refused: it provably cannot run a
# single file, and refusing with a message beats dying at the first import.
# An unreadable linkage (no ldd, a static or wrapped binary, a distro naming
# its libraries some other way) is *used*, because those machines ran this
# suite fine before #215 and a check that breaks them has cost more than the
# bug it fixes. Preference still goes to a candidate that proves itself Qt6.
#
# Both decisions are pinned by tests/tst_qmltestrunner.sh.

# Where a Qt6 runner lives when it is not on PATH. Arch keeps the Qt6 tools out
# of PATH so they cannot shadow the Qt5 ones; other distros ship the same
# layout under lib64.
QMLTESTRUNNER_CANDIDATES=(
    /usr/lib/qt6/bin/qmltestrunner
    /usr/lib64/qt6/bin/qmltestrunner
)

# The dynamic libraries $1 links against, one per line, or nothing when that
# cannot be read. Split out from the verdict so the decision above it stays
# pure — and so the tests can hand it a Qt5 linkage without a Qt5 install.
qmltestrunner_linkage() {
    ldd "$1" 2>/dev/null || true
}

# Reads a binary's linkage and says which Qt it is built against. Echoes one of:
#
#   qt6        links Qt 6 — this is the runner   (exit 0)
#   qt<major>  links some other Qt               (exit 1)
#   unknown    no Qt library named in the input  (exit 1)
#
# The library name carries the major (libQt5QuickTest.so.5), so the match is
# anchored to the `libQt` prefix rather than to a digit: `libc.so.6` sits in
# every one of these listings, and a looser pattern would read the Qt5 runner
# as Qt6 — the #215 bug, now silent.
qmltestrunner_qt_verdict() {
    local linkage="${1-}"

    if [[ "$linkage" =~ libQt([0-9]+)(QuickTest|Qml|Quick|Core) ]]; then
        local major="${BASH_REMATCH[1]}"
        if [[ "$major" == 6 ]]; then
            printf 'qt6\n'
            return 0
        fi
        printf 'qt%s\n' "$major"
        return 1
    fi

    printf 'unknown\n'
    return 1
}

# Echoes the runner to use on stdout, or explains itself on stderr and fails.
# Diagnostics go to stderr so `runner=$(qmltestrunner_resolve)` stays clean.
#
# QMLTESTRUNNER=<path> overrides the search: a human naming the binary beats
# any guess this file makes. It is still verdicted, because an override
# pointing at a Qt5 runner is the same broken run — only chosen by hand.
qmltestrunner_resolve() {
    local -r hint='override with QMLTESTRUNNER=<path> if the Qt6 runner lives elsewhere'
    local override="${QMLTESTRUNNER-}"

    if [[ -n "$override" ]]; then
        if [[ ! -x "$override" ]]; then
            printf 'qmltestrunner: QMLTESTRUNNER=%s is not an executable.\n' "$override" >&2
            return 1
        fi
        local override_verdict
        override_verdict=$(qmltestrunner_qt_verdict "$(qmltestrunner_linkage "$override")") || true
        if [[ "$override_verdict" == qt6 || "$override_verdict" == unknown ]]; then
            printf '%s\n' "$override"
            return 0
        fi
        printf 'qmltestrunner: QMLTESTRUNNER=%s links %s, not Qt6.\n' "$override" "$override_verdict" >&2
        printf '  A Qt5 runner fails every file with "Library import requires a version".\n' >&2
        return 1
    fi

    # The packaged locations first and PATH last — not because PATH is wrong,
    # but because on the machine where the two disagree PATH is the Qt5 one.
    # The verdict decides; this order only settles ties between two Qt6 runners.
    local -a candidates=("${QMLTESTRUNNER_CANDIDATES[@]}")
    local on_path
    on_path=$(command -v qmltestrunner 2>/dev/null) || on_path=""
    if [[ -n "$on_path" ]]; then
        local seen=0 c
        for c in "${candidates[@]}"; do
            [[ "$c" == "$on_path" ]] && seen=1
        done
        (( seen )) || candidates+=("$on_path")
    fi

    # Two passes over one candidate list: a proven Qt6 runner anywhere beats an
    # unreadable one, wherever each was found.
    local candidate verdict
    local -a tried=() fallbacks=()
    for candidate in "${candidates[@]}"; do
        if [[ ! -x "$candidate" ]]; then
            tried+=("$candidate (not found)")
            continue
        fi
        verdict=$(qmltestrunner_qt_verdict "$(qmltestrunner_linkage "$candidate")") || true
        case "$verdict" in
            qt6)
                printf '%s\n' "$candidate"
                return 0
                ;;
            unknown)
                tried+=("$candidate (cannot read its Qt version)")
                fallbacks+=("$candidate")
                ;;
            *)
                tried+=("$candidate (links $verdict)")
                ;;
        esac
    done

    if (( ${#fallbacks[@]} )); then
        printf '%s\n' "${fallbacks[0]}"
        return 0
    fi

    printf 'qmltestrunner: no Qt6 qmltestrunner found. Tried:\n' >&2
    local entry
    for entry in "${tried[@]}"; do
        printf '  %s\n' "$entry" >&2
    done
    printf '  A Qt5 runner cannot run this suite: it fails every file with\n' >&2
    printf '  "Library import requires a version" and prints no Totals: line.\n' >&2
    printf '  On Arch the Qt6 one is in qt6-declarative, off PATH by design.\n' >&2
    printf '  %s\n' "$hint" >&2
    return 1
}
