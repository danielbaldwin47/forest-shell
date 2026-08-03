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
#   NESTED_ENV=("XDG_CONFIG_HOME=$NESTED_WORK/config")  # optional
#   nested_shell lock-harness.qml 'harness: lock harness ready'
#   nested_ipc some target call
#   nested_hyprctl dispatch workspace 2       # drive the compositor, not the shell
#   nested_await "$NESTED_SHELL_LOG" 'the line that proves it' 15
#   nested_key escape                      # a keystroke, into the focused window
#
# Sourcing installs an EXIT trap that tears the nested session down. See
# tools/lock-harness.sh and tools/settings-harness.sh for the worked examples.
#
# WHAT THIS SEAM CANNOT DO — screenshots and frame counts. Diagnosed in #85:
# both are one bug, and it is upstream.
#
# The nested compositor never presents a frame after its first commit. The
# protocol trace (WAYLAND_DEBUG=client on the nested Hyprland) shows the
# last buffer go out with a wl_surface.frame request, the outer session answer
# wl_callback.done — and then nothing, ever again. aquamarine 0.14.0's frame
# scheduler drops a frame request that arrives while a frame is being run;
# upstream fixed exactly that the day after the 0.14.0 tag (hyprwm/aquamarine
# 5ea27f81, "frame: reschedule one more idle frame if requested"), but the
# stall reproduces with that fix applied, so something deeper in the nested
# present path is still wedged on this stack (Hyprland 0.56.1 + aq 0.14.0).
#
# Everything downstream follows from that one stall:
#   - the nested window on the outer session shows black — nothing was ever
#     composited into it (confirmed visually and by capturing its region from
#     the outer session, which works fine and shows a black rectangle);
#   - every capture protocol on the nested socket waits for a present that
#     never comes: grim blocks (both bare and `-o WAYLAND-1`; the output
#     really is named WAYLAND-1 — `WL-1` is rejected), and so does a raw
#     zwlr-screencopy client, and so does a capture of an added headless
#     output. `hyprctl dispatch forcerendererreload` makes the copy *complete*
#     but the delivered buffer is transparent black — the sentinel test shows
#     the compositor really writes zeros, it is not a stuck buffer;
#   - Qt clients inside stop rendering once their first frame's callback never
#     returns, which is why QSG_RENDER_TIMING measures zero frames per
#     workspace switch. A broken animation and a working one both measure
#     zero, so #75-class acceptance (~14 frames per switch) still needs a
#     real session. What the seam *can* answer is whether the shell was told,
#     which is the half that had no evidence when #75 was diagnosed.
#
# What closes the visual gap instead: tools/capture-harness.sh — the shell's
# real surface components rendered client-side and grabbed with
# Item.grabToImage, which does not involve a compositor at all. #79's contrast
# measurement runs there (tools/measure-contrast.py). It has two modes, and the
# difference between them is MultiEffect: the default renders on
# QT_QPA_PLATFORM=offscreen, needs no session and draws no Lucide glyph at all;
# `--session` renders the same components on the caller's own Wayland session,
# where MultiEffect works, which is how #73's "status strip icons and settings
# chrome visually judged" was finally answered. Neither mode judges compositor
# composition — blur behind the bar, layer stacking, frame pacing. That is the
# compositor's own pixels, and it stays real-session work.

# --- state, all owned by this file ------------------------------------------

NESTED_DISPLAY=""       # the wayland-N socket the nested compositor is on
NESTED_SIGNATURE=""     # the nested Hyprland's instance signature — see nested_up
NESTED_WORK=""          # scratch dir: configs, logs, captures
NESTED_ENV=()           # extra `KEY=value` for the shell — see nested_shell
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

## Hyprland's per-instance directories. One appears per running instance, named
## by its signature — which is the handle `hyprctl` and Quickshell's Hyprland
## module both take from `HYPRLAND_INSTANCE_SIGNATURE`.
nested_instances() {
    find "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" -maxdepth 1 -mindepth 1 \
        -type d -printf '%f\n' 2>/dev/null | sort
}

## Start a nested Hyprland and set NESTED_DISPLAY to the socket it opened, plus
## NESTED_SIGNATURE to the instance it registered.
##
## `env -u HYPRLAND_INSTANCE_SIGNATURE` is load-bearing here: with it inherited,
## Hyprland comes up as a client of the *outer* instance rather than as its own,
## and so does everything launched after it — which for a lock means locking the
## real session, the exact thing this file exists to prevent. Clients are then
## pointed at the new instance explicitly, by `nested_env`.
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
    local before after before_instances
    before=$(nested_sockets)
    before_instances=$(nested_instances)

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
    for _ in $(seq 1 100); do
        NESTED_SIGNATURE=$(comm -13 <(printf '%s\n' "$before_instances") \
                                    <(printf '%s\n' "$(nested_instances)") | head -1)
        [[ -n "$NESTED_SIGNATURE" ]] && break
        sleep 0.1
    done
    [[ -n "$NESTED_SIGNATURE" ]] \
        || nested_note "no instance signature yet — the facade will be inert in there"

    nested_note "nested compositor on $NESTED_DISPLAY"
}

## Run something as a client of the nested session.
##
## Both variables are load-bearing, and the signature is the subtler of the two.
## Inherited from the *outer* session it aims every `hyprctl` and every dispatch
## at the real compositor — which for a lock means locking the session doing the
## testing. Unset, the shell's Hyprland facade reads no session at all and
## degrades to a logged no-op, so anything that goes through the compositor
## (`Compositor.setLayerRule`, #78) is never exercised. Pointed at the nested
## instance, both problems are the same fix: real calls, contained.
nested_env() {
    nested_env_argv
    "${NESTED_ENV_ARGV[@]}" "$@"
}

## The `env` argv nested_env runs things under, left in a global so
## nested_shell can launch its client as a *simple command*. `nested_env cmd &`
## backgrounds a subshell, and killing that subshell pid leaves the client
## alive — measured as a "restarted" shell whose notification daemon kept
## serving, ids continuing where the old run left off. `env … cmd &` is
## fork+exec, so $! is the client itself.
nested_env_argv() {
    if [[ -n "$NESTED_SIGNATURE" ]]; then
        NESTED_ENV_ARGV=(env HYPRLAND_INSTANCE_SIGNATURE="$NESTED_SIGNATURE"
                             WAYLAND_DISPLAY="$NESTED_DISPLAY")
    else
        NESTED_ENV_ARGV=(env -u HYPRLAND_INSTANCE_SIGNATURE
                             WAYLAND_DISPLAY="$NESTED_DISPLAY")
    fi
}

## Drive the nested compositor directly, as a harness does when it needs the
## *compositor* to do something rather than the shell — including keys, which
## are the only way to test a surface the way it is actually used (#77 was a
## window with no keyboard path at all, and nothing about that is checkable by
## calling functions on it). Fails loudly rather than falling back to the outer
## instance: a keystroke aimed at the wrong one lands in the session you are
## working in.
nested_hyprctl() {
    [[ -n "$NESTED_SIGNATURE" ]] || { echo "no nested instance signature" >&2; return 1; }
    nested_env hyprctl "$@" 2>&1
}

## Send one key to the focused window inside the nested session, by its Hyprland
## key name: `nested_key escape`, `nested_key tab`, `nested_key space`.
nested_key() {
    nested_hyprctl dispatch sendshortcut ", $1, activewindow" > /dev/null
}

## The same, for a key aimed at whatever holds keyboard focus rather than at a
## toplevel — which is what you want when the surface under test is a *layer*
## surface (the screenshot picker, #51; a lock; a drawer with an exclusive
## keyboard grab).
##
## The distinction is not cosmetic and fails confusingly: `activewindow`
## resolves only to toplevels, so against a session whose focus is held by a
## layer surface it answers `sendshortcut: window not found` and the keystroke
## is simply dropped — which looks exactly like a surface that ignored the key.
## An empty window target sends to the focused surface instead, and is the only
## form that reaches a layer shell (measured on Hyprland 0.56.1).
nested_key_focused() {
    nested_hyprctl dispatch sendshortcut ", $1, " > /dev/null
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
    # means a test that toggles a setting toggles a scratch one. It is also the
    # door for QSG_RENDER_TIMING, when frames are what is being counted.
    # `setsid` so the whole shell — not just the process this script launched —
    # can be taken down by `nested_kill_shell`. Quickshell forks: the process
    # started here is not the one that owns the Wayland connection and the IPC
    # socket, so killing it by pid leaves an instance behind, orphaned and
    # still answering. Measured (#71): a leaked instance from the previous run
    # answered `ipc call lock lock` on a recycled wayland-N with the lock state
    # of a session that no longer existed, which reads exactly like the feature
    # under test being broken.
    #
    # There is no fork here to lose the pid to: this shell is not interactive,
    # so a background command is not a process-group leader and `setsid` execs
    # in place. $! is the new group leader.
    nested_env_argv
    setsid "${NESTED_ENV_ARGV[@]}" "${NESTED_ENV[@]}" \
        "$NESTED_QS" -p "$entry" > "$NESTED_SHELL_LOG" 2>&1 &
    NESTED_SHELL_PID=$!

    if [[ -n "$ready" ]] && ! nested_await "$NESTED_SHELL_LOG" "$ready" "$timeout"; then
        echo "the shell never came up — see $NESTED_SHELL_LOG" >&2
        return 1
    fi
    nested_note "shell up (pid $NESTED_SHELL_PID) — $entry"
}

## Take the shell under test down — the whole of it, and nothing else.
##
## The negative pid is the point: it signals the process group `nested_shell`
## put it in, which is the only way to reach the forked instance behind it.
## Scoped to a group this file created, so it can never reach the shell running
## the session the harness is being run from.
nested_kill_shell() {
    [[ -n "$NESTED_SHELL_PID" ]] || return 0
    kill -- "-$NESTED_SHELL_PID" 2>/dev/null || kill "$NESTED_SHELL_PID" 2>/dev/null
    wait "$NESTED_SHELL_PID" 2>/dev/null
    NESTED_SHELL_PID=""
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
    nested_env "$NESTED_QS" -p "$NESTED_ENTRY" ipc "$@" 2>&1
}

# --- teardown ----------------------------------------------------------------

nested_down() {
    if (( NESTED_KEEP )); then
        printf '\nnested session left up:\n  WAYLAND_DISPLAY=%s\n  logs: %s\n' \
            "$NESTED_DISPLAY" "$NESTED_WORK"
        printf '  kill it with: kill %s %s\n' "$NESTED_SHELL_PID" "$NESTED_HYPR_PID"
        return
    fi
    nested_kill_shell
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
