#!/usr/bin/env bash
# Run this shell inside a nested Hyprland, so a surface can be driven and looked
# at without risking the session doing the looking.
#
# This is the shell's second test seam. The first is `tests/` — pure QML modules
# that import nothing but QtQuick, run offscreen by qmltestrunner, and cover
# everything that is a decision rather than a picture. Nothing that *renders*
# can be reached from there: Quickshell's own QML modules are compiled into the
# binary and qmltestrunner cannot load them, and `MultiEffect` draws nothing
# offscreen anyway. Everything on that side of the line lands here.
#
# The argument for it is #73's acceptance pass: seven surfaces merged green
# against `tests/`, then the first run under a real compositor produced eight
# bugs at once (#74–#81), one of which — a lock that could not be unlocked —
# cost the session that found it. A nested compositor turns that class of
# failure back into a window that can be closed.
#
#   tools/nested-session.sh                # the real shell, nested, held open
#   tools/nested-session.sh gallery.qml    # some other entry point
#
# Or, from a harness script, as a library:
#
#   source "$(dirname "${BASH_SOURCE[0]}")/nested-session.sh"
#   nested_up
#   nested_shell lock-harness.qml 'harness: lock harness ready'
#   nested_ipc some target call
#   nested_await "$NESTED_SHELL_LOG" 'the line that proves it' 15
#   nested_key escape                      # a keystroke, into the focused window
#
# Sourcing installs an EXIT trap that tears the nested session down. See
# tools/lock-harness.sh and tools/settings-harness.sh for the worked examples.
#
# WHAT THIS SEAM CANNOT DO YET — screenshots.
#
# `grim` does not complete against Hyprland's nested Wayland backend: measured
# here, it blocks indefinitely and is killed by the timeout, both bare and as
# `grim -o WAYLAND-1` (the nested output is named `WAYLAND-1` — `WL-1` is
# rejected as unknown). wlr-screencopy appears never to deliver a frame for a
# nested output. So this seam can *drive* a surface and *read its logs*, but it
# cannot yet look at one.
#
# That gap matters more than it sounds: #79 (bar contrast at the opacity floor)
# and #80 (a settings row pushing its control off-screen) were both found by
# measuring pixels out of a capture, and #73's "MultiEffect surfaces visually
# judged" is still unchecked because nothing has ever rendered them anywhere.
# Until it is closed, those checks still need a real session.
#
# The promising route, untried: the nested compositor paints into an ordinary
# window on the *outer* session, so capturing that window's region from outside
# (`grim -g` over its geometry from `hyprctl clients`) should get the pixels
# without screencopy being involved at all.

# --- state, all owned by this file ------------------------------------------

NESTED_DISPLAY=""       # the wayland-N socket the nested compositor is on
NESTED_SIGNATURE=""     # the nested Hyprland's instance signature, for hyprctl
NESTED_WORK=""          # scratch dir: configs, logs, captures
NESTED_ENV=()           # extra `env` assignments for the shell under test
NESTED_HYPR_LOG=""
NESTED_HYPR_PID=""
NESTED_SHELL_LOG=""
NESTED_SHELL_PID=""
NESTED_ENTRY=""        # the entry point running in there; `ipc` needs it too
NESTED_KEEP=${NESTED_KEEP:-0}      # 1 = leave it up on exit, to poke at by hand
NESTED_QS="${QS_BIN:-qs-upstream}" # #14/#15: upstream prefix until the swap (#57)
nested_fail_count=0

nested_pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
nested_note() { printf '  ....  %s\n' "$1"; }
nested_fail() {
    printf '  \033[31mFAIL\033[0m  %s\n' "$1"
    nested_fail_count=$((nested_fail_count + 1))
}

# --- waiting -----------------------------------------------------------------

## Wait for a line to appear in a log, or give up. Every wait here is a poll on
## evidence rather than a sleep, so a run is as fast as the shell is and does
## not go flaky on a loaded machine.
nested_await() {
    local file="$1" pattern="$2" timeout="${3:-10}"
    local ticks=$(( timeout * 10 ))
    for _ in $(seq 1 "$ticks"); do
        [[ -e "$file" ]] && grep -qaE "$pattern" "$file" && return 0
        sleep 0.1
    done
    return 1
}

# --- bring-up ----------------------------------------------------------------

nested_sockets() {
    find "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" -maxdepth 1 \
        -name 'wayland-[0-9]*' ! -name '*.lock' -printf '%f\n' 2>/dev/null | sort
}

nested_signatures() {
    find "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" -mindepth 1 -maxdepth 1 -type d \
        -printf '%f\n' 2>/dev/null | sort
}

## Start a nested Hyprland and set NESTED_DISPLAY to the socket it opened.
##
## `env -u HYPRLAND_INSTANCE_SIGNATURE` is load-bearing in every launch below:
## with it inherited, Hyprland and every client attach to the *outer* instance
## instead — which for a lock means locking the real session, the exact thing
## this file exists to prevent.
nested_up() {
    NESTED_WORK="${TMPDIR:-/tmp}/forest-nested.$$"
    mkdir -p "$NESTED_WORK"
    NESTED_HYPR_LOG="$NESTED_WORK/hyprland.log"

    # `WAYLAND-1` is what the nested backend actually calls its output — the
    # `WL-1` this started life as matched nothing, so the size was never applied
    # and the window came up at whatever the backend defaulted to.
    cat > "$NESTED_WORK/hyprland.conf" <<'EOF'
monitor = WAYLAND-1, 1280x800@60, 0x0, 1
animations { enabled = false }
misc { disable_hyprland_logo = true, disable_splash_rendering = true }
bind = SUPER, Q, exit
EOF

    # Which socket is ours, by set difference rather than "the newest one" —
    # two of these run in parallel often enough (one per worktree) that picking
    # by mtime eventually attaches a harness to somebody else's compositor.
    local before after sig_before sig_after
    before=$(nested_sockets)
    sig_before=$(nested_signatures)

    env -u HYPRLAND_INSTANCE_SIGNATURE Hyprland -c "$NESTED_WORK/hyprland.conf" \
        > "$NESTED_HYPR_LOG" 2>&1 &
    NESTED_HYPR_PID=$!

    for _ in $(seq 1 100); do
        after=$(nested_sockets)
        NESTED_DISPLAY=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)
        [[ -n "$NESTED_DISPLAY" ]] && break
        kill -0 "$NESTED_HYPR_PID" 2>/dev/null || break
        sleep 0.1
    done

    if [[ -z "$NESTED_DISPLAY" ]] || ! kill -0 "$NESTED_HYPR_PID" 2>/dev/null; then
        echo "could not start a nested Hyprland — see $NESTED_HYPR_LOG" >&2
        return 1
    fi

    # The instance signature, by the same set difference and for the same
    # reason: `hyprctl` talks to whichever instance the environment names, and
    # the environment names the *outer* one. Getting this wrong is not a failed
    # assertion — it is a keystroke delivered to the session you are working in.
    sig_after=$(nested_signatures)
    NESTED_SIGNATURE=$(comm -13 <(printf '%s\n' "$sig_before") <(printf '%s\n' "$sig_after") \
        | head -1)

    nested_note "nested compositor on $NESTED_DISPLAY"
}

## Drive the nested compositor: `nested_hyprctl dispatch sendshortcut ", escape, activewindow"`.
##
## Keys are the only way to test a surface the way it is actually used — #77 was
## a window with no keyboard path at all, and nothing about that is checkable by
## calling functions on it. Fails loudly rather than falling back to the outer
## instance.
nested_hyprctl() {
    [[ -n "$NESTED_SIGNATURE" ]] || { echo "no nested instance signature" >&2; return 1; }
    HYPRLAND_INSTANCE_SIGNATURE="$NESTED_SIGNATURE" hyprctl "$@" 2>&1
}

## Send one key to the focused window inside the nested session, by its Hyprland
## key name: `nested_key escape`, `nested_key tab`, `nested_key space`.
nested_key() {
    nested_hyprctl dispatch sendshortcut ", $1, activewindow" > /dev/null
}

## Run a shell entry point inside the nested session, and wait for it to say it
## is up. The ready pattern is the caller's, because only the caller knows what
## its entry point logs — shell.qml's staged startup (#32) ends with a line, and
## a purpose-built harness root should log one of its own.
nested_shell() {
    local entry="${1:-shell.qml}" ready="${2:-}" timeout="${3:-20}"
    NESTED_SHELL_LOG="$NESTED_WORK/shell.log"
    NESTED_ENTRY="$entry"

    # NESTED_ENV is how a harness keeps the shell under test off the user's own
    # files: `NESTED_ENV=(XDG_CONFIG_HOME=… XDG_STATE_HOME=…)` before this call
    # means a test that toggles a setting toggles a scratch one.
    env -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY="$NESTED_DISPLAY" \
        "${NESTED_ENV[@]}" "$NESTED_QS" -p "$entry" > "$NESTED_SHELL_LOG" 2>&1 &
    NESTED_SHELL_PID=$!

    if [[ -n "$ready" ]] && ! nested_await "$NESTED_SHELL_LOG" "$ready" "$timeout"; then
        echo "the shell never came up — see $NESTED_SHELL_LOG" >&2
        return 1
    fi
    nested_note "shell up (pid $NESTED_SHELL_PID) — $entry"
}

## Talk to the nested shell.
##
## Two things the client needs and neither is optional. Quickshell's IPC is
## scoped to the display, so `WAYLAND_DISPLAY` must be set for the *client* too
## — without it, `ipc call` reports "no running instances on the current
## display" while listing the instance it is declining to talk to. And `-p` must
## name the same entry point the shell was started with, or the client looks for
## a `default` config it will not find and fails with a message about
## `shell.qml` that has nothing to do with what went wrong.
nested_ipc() {
    env -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY="$NESTED_DISPLAY" \
        "$NESTED_QS" -p "$NESTED_ENTRY" ipc "$@" 2>&1
}

# --- teardown ----------------------------------------------------------------

nested_down() {
    if (( NESTED_KEEP )); then
        printf '\nnested session left up:\n  WAYLAND_DISPLAY=%s\n  logs: %s\n' \
            "$NESTED_DISPLAY" "$NESTED_WORK"
        printf '  kill it with: kill %s %s\n' "$NESTED_SHELL_PID" "$NESTED_HYPR_PID"
        return
    fi
    [[ -n "$NESTED_SHELL_PID" ]] && kill "$NESTED_SHELL_PID" 2>/dev/null
    [[ -n "$NESTED_HYPR_PID"  ]] && kill "$NESTED_HYPR_PID"  2>/dev/null
    wait 2>/dev/null
    # Logs are evidence when something failed and litter when nothing did.
    if (( nested_fail_count == 0 )) && [[ -n "$NESTED_WORK" ]]; then
        rm -rf "$NESTED_WORK"
    elif [[ -n "$NESTED_WORK" ]]; then
        printf 'logs kept in %s\n' "$NESTED_WORK"
    fi
}

# --- sourced, or run? --------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    trap nested_down EXIT
    return 0
fi

set -uo pipefail

ENTRY="shell.qml"
while (( $# )); do
    case "$1" in
        --help|-h) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *)  ENTRY="$1"; shift ;;
    esac
done

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ENTRY" ]] || { echo "no such entry point: $ENTRY" >&2; exit 1; }

trap nested_down EXIT
nested_up || exit 1
nested_shell "$ENTRY" '' || exit 1

nested_note "talk to it with:  WAYLAND_DISPLAY=$NESTED_DISPLAY $NESTED_QS -p $ENTRY ipc call <target> <fn>"
nested_note "SUPER+Q inside the window closes it; Ctrl-C here does too"
wait "$NESTED_HYPR_PID"
