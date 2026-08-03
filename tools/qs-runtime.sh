#!/usr/bin/env bash
# Which quickshell binary runs forest-shell. Sourced, never executed.
#
#   source "$(dirname "$0")/qs-runtime.sh"
#   QS_BIN=$(qs_runtime_resolve) || exit 1
#
# Until #57 this file did not exist and three harnesses each carried
# `QS_BIN="${QS_BIN:-qs-upstream}"` — a hand-built prefix at
# ~/.local/bin/qs-upstream, needed because /usr/bin/qs was the noctalia fork
# (0.0.12) and could not run this shell. #57 retires that: the runtime is
# pacman `quickshell` at plain `qs`.
#
# The rule here is deliberately one rule rather than a swap-shaped special
# case: *the binary must identify as upstream Quickshell at or above the floor
# below*. That is true of pacman `quickshell` after the swap and of the
# `qs-upstream` prefix before it, so `QS_BIN=qs-upstream tools/foo.sh` keeps
# working for as long as the prefix is on disk without this file knowing
# anything about the transition. It is false of the noctalia fork, which is
# the failure this catches — `command -v qs` succeeds against the fork, so
# without a version check the harnesses would launch it and fail later with a
# QML import error that names nothing useful.
#
# The verdict function is pure and pinned by tests/tst_qs_runtime.sh.

# Upstream release the shell is written against (#14/#15 chose it; the API it
# depends on — IpcHandler function signatures, FileView, Quickshell.Io — is
# 0.3.0-era). Raise this when the shell starts using something newer.
QS_RUNTIME_MIN=0.3.0

# True when $1 is a version at or above $2. Numeric per component, so 0.10.0
# beats 0.9.0 — a string compare would get that backwards.
qs_runtime_version_ge() {
    [[ "$1" == "$2" ]] && return 0
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" == "$1" ]]
}

# Reads the first line of `<binary> --version` and says whether that binary may
# run forest-shell. Echoes one of:
#
#   ok:<version>     upstream, at or above the floor   (exit 0)
#   old:<version>    upstream, below the floor         (exit 1)
#   fork:<name>      some other program entirely       (exit 1)
#   unknown          unparseable — no version found    (exit 1)
#
# Fails closed. A binary that will not say what it is does not get to run the
# shell: mid-swap is exactly when `qs` might be missing, half-replaced, or a
# wrapper that prints nothing, and "assume it's fine" turns that into a
# confusing QML error instead of a clear one.
qs_runtime_verdict() {
    local name version
    read -r name version _ <<<"${1-}"

    [[ -n "$name" ]] || { printf 'unknown\n'; return 1; }
    [[ "$name" == "Quickshell" ]] || { printf 'fork:%s\n' "$name"; return 1; }

    # `quickshell 0.3.0-2.1` is the pacman pkgrel, not part of the release.
    version="${version%%-*}"
    [[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { printf 'unknown\n'; return 1; }

    if qs_runtime_version_ge "$version" "$QS_RUNTIME_MIN"; then
        printf 'ok:%s\n' "$version"
        return 0
    fi
    printf 'old:%s\n' "$version"
    return 1
}

# The resolved path, memoised. This is what callers should use.
#
# Call it at the point the binary is about to run, not at load time: these
# harnesses all have a `--help` that must keep working on a machine whose
# runtime is not ready yet, and resolving during sourcing would fail the script
# before it ever reached argument parsing.
# The failure is memoised too. A caller that asks twice on a machine with the
# wrong runtime should not get the whole diagnostic block printed twice.
_qs_runtime_bin=""
_qs_runtime_failed=0
qs_runtime_bin() {
    (( _qs_runtime_failed )) && return 1
    if [[ -z "$_qs_runtime_bin" ]]; then
        _qs_runtime_bin=$(qs_runtime_resolve) || { _qs_runtime_failed=1; return 1; }
    fi
    printf '%s\n' "$_qs_runtime_bin"
}

# Echoes the resolved binary on stdout, or explains itself on stderr and fails.
# Diagnostics go to stderr so `QS_BIN=$(qs_runtime_resolve)` stays clean.
qs_runtime_resolve() {
    local requested="${QS_BIN:-qs}" resolved
    local -r hint='override with QS_BIN=<binary> if the runtime lives elsewhere'

    if ! resolved=$(command -v "$requested" 2>/dev/null); then
        printf 'qs-runtime: %s not found on PATH.\n' "$requested" >&2
        printf '  forest-shell needs upstream Quickshell >= %s (pacman: quickshell).\n' "$QS_RUNTIME_MIN" >&2
        printf '  %s\n' "$hint" >&2
        return 1
    fi

    # No pipe: a pipeline here would trip `set -o pipefail` in the caller when
    # the binary writes more than one line and takes SIGPIPE.
    # `status` is deliberately not the name here: it is read-only in zsh and
    # fish, and this file gets sourced into interactive shells while debugging.
    local output first verdict rc=0
    output=$("$resolved" --version 2>/dev/null || true)
    first="${output%%$'\n'*}"
    verdict=$(qs_runtime_verdict "$first") || rc=$?

    if (( rc == 0 )); then
        printf '%s\n' "$resolved"
        return 0
    fi

    printf 'qs-runtime: %s cannot run forest-shell.\n' "$resolved" >&2
    case "$verdict" in
        fork:noctalia-qs)
            printf '  It is the noctalia fork (%s), not upstream Quickshell.\n' "$first" >&2
            printf '  This is the pre-#57 runtime. Complete the swap:\n' >&2
            printf '    see integration/README.md, "Swap the runtime"\n' >&2
            printf '  Until then: QS_BIN=qs-upstream <command>\n' >&2
            ;;
        fork:*)
            printf '  It reports itself as %s, not Quickshell.\n' "${verdict#fork:}" >&2
            printf '  %s\n' "$hint" >&2
            ;;
        old:*)
            printf '  It is Quickshell %s; this shell needs >= %s.\n' "${verdict#old:}" "$QS_RUNTIME_MIN" >&2
            printf '  Upgrade the quickshell package.\n' >&2
            ;;
        *)
            printf '  `%s --version` said nothing recognisable: %s\n' "$resolved" "${first:-<no output>}" >&2
            printf '  %s\n' "$hint" >&2
            ;;
    esac
    return 1
}
