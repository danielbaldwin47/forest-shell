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
#   nested_click 640 400                   # a real button press, hit-tested
#   nested_drag 640 300 640 460            # press, travel, release — one gesture
#   nested_window_rect 'forest-shell — cal' # a toplevel's rect, to aim at
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

# Which quickshell binary is allowed to run the shell, and why plain `qs` is
# not assumed to be it (#57). Sourced rather than inlined so the three harnesses
# that launch a runtime agree on one answer.
# shellcheck source=qs-runtime.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qs-runtime.sh"

# Where this file's own siblings are — nested-click.c and the protocol it is
# built against. Resolved once, at source time, because `nested_click` is
# called from harnesses that have long since `cd`'d somewhere else.
NESTED_TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- state, all owned by this file ------------------------------------------

NESTED_DISPLAY=""       # the wayland-N socket the nested compositor is on
NESTED_SIGNATURE=""     # the nested Hyprland's instance signature — see nested_up
NESTED_WORK=""          # scratch dir: configs, logs, captures
NESTED_ENV=()           # extra `KEY=value` for the shell — see nested_shell
NESTED_CONFIG=()        # extra hyprland.conf lines — see nested_up
NESTED_HYPR_LOG=""
NESTED_HYPR_PID=""
NESTED_CLICK_BIN=""     # the click tool, built on first use — see nested_click
NESTED_SHELL_LOG=""
NESTED_SHELL_PID=""
NESTED_ENTRY=""        # the entry point running in there; `ipc` needs it too
NESTED_KEEP=${NESTED_KEEP:-0}      # 1 = leave it up on exit, to poke at by hand

# The monitor layout, as Hyprland `monitor =` rules and in Hyprland's order:
# the *first* is the nested backend's own output and comes up with the
# compositor; every one after it is created as a headless output once the
# compositor is up (#98). Override the whole array before `nested_up` to run a
# harness on more than one screen, at more than one size and scale:
#
#   NESTED_MONITORS=("WAYLAND-1, 1280x800@60, 0x0, 1"
#                    "FOREST-2, 1920x1080@60, 1280x0, 1.5")
#
# Headless rather than a second nested window on purpose. A second output on
# the wayland backend is a second window on the *host*, so the host's tiling
# decides its size — measured: adding one resized both outputs to ~618x648,
# and the rule for the new one never applied. A headless output has no window
# to be resized, so its geometry is the one written here.
NESTED_MONITORS=("WAYLAND-1, 1280x800@60, 0x0, 1")

# 1 = drop the backend's own output once the headless ones are up, leaving a
# session whose every output has the geometry this file gave it. Only for a
# harness that asserts on geometry — it needs at least one other output, and it
# leaves nothing on screen for `--keep` to poke at.
NESTED_HEADLESS_ONLY=${NESTED_HEADLESS_ONLY:-0}
NESTED_QS=""           # the quickshell binary; resolved in nested_shell (#57)
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
    #
    # Every rule in NESTED_MONITORS is written, including the ones for outputs
    # that do not exist yet: a rule is matched by name when the output appears,
    # which is what makes a headless output come up at a size this file chose
    # rather than at the backend's 1920x1080@2 default.
    {
        local spec
        for spec in "${NESTED_MONITORS[@]}"; do
            printf 'monitor = %s\n' "$spec"
        done
        cat <<'EOF'
animations { enabled = false }
misc { disable_hyprland_logo = true, disable_splash_rendering = true }
bind = SUPER, Q, exit
EOF
        # Anything else the harness needs the *compositor* configured with, one
        # line per entry: `NESTED_CONFIG=('input { kb_layout = us,de }')`. Here
        # because some of what the shell shows is a fact about the session it is
        # in rather than about the shell — the keyboard-layout module is not on
        # the bar at all on a one-layout machine, so a harness that needs to
        # click it has to give the compositor two (#187).
        local line
        for line in "${NESTED_CONFIG[@]}"; do
            printf '%s\n' "$line"
        done
    } > "$NESTED_WORK/hyprland.conf"

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

    # Every output past the backend's own. Done here rather than left to the
    # caller so that a two-screen harness has two screens before its shell
    # starts — a shell that comes up on one output and gets a second later is
    # the hotplug case, not the two-monitor case, and they fail differently.
    local spec
    for spec in "${NESTED_MONITORS[@]:1}"; do
        nested_output_add "$spec" || return 1
    done

    # ...and, if asked, nothing but those. The backend's own output is a window
    # on the host session, so the host's tiling resizes it whenever it feels
    # like it — measured: 1280x800 at bring-up, 1252x648 once a second output
    # existed, 618x648 a moment later. A harness asserting on geometry cannot
    # live with that, and loses nothing by dropping it: the nested compositor
    # never presents a frame anyway (hyprwm/aquamarine#348), so the window it
    # would have drawn into is not something anyone can look at.
    if (( NESTED_HEADLESS_ONLY )); then
        local backend
        backend=$(nested_output_name "${NESTED_MONITORS[0]}")
        nested_output_remove "$backend" || return 1
        nested_note "dropped $backend — headless outputs only"
    fi
}

## The name a `monitor =` rule applies to: the first field, unpadded.
nested_output_name() {
    local name="${1%%,*}"
    printf '%s' "${name// /}"
}

## The outputs the nested compositor currently has, one name per line.
nested_outputs() {
    nested_hyprctl monitors | awk '$1 == "Monitor" { print $2 }'
}

## One output's geometry as the compositor reports it: `1280x800 0x0 1.50`,
## in physical pixels, position, and scale. Empty if there is no such output.
##
## Physical is what `hyprctl` reports and logical is what the shell sees, so a
## caller asserting on a surface's size divides by the scale — the gap between
## the two is the thing #98 exists to exercise.
nested_output_geometry() {
    nested_hyprctl monitors | awk -v want="$1" '
        $1 == "Monitor" { cur = $2 }
        cur == want && $2 == "at" { split($1, mode, "@"); size = mode[1]; pos = $3 }
        cur == want && $1 == "scale:" { print size, pos, $2; exit }
    '
}

## The size the *shell* sees on an output: physical divided by scale, as
## `1280x720` for a 1920x1080 output at scale 1.5. What a surface's own
## geometry has to agree with, and the reason a harness asks rather than
## hard-codes: the nested backend's own output is a window on the host, so the
## host's tiling — not this file — decides how big it is.
nested_output_logical() {
    nested_output_geometry "$1" | awk '
        $3 > 0 {
            split($1, size, "x")
            # Rounded, not truncated: a scale that does not divide the mode
            # exactly (1.25 on 1920 wide) leaves Qt at the nearest logical
            # pixel and `%d` alone a pixel short of it.
            printf "%dx%d\n", int(size[1] / $3 + 0.5), int(size[2] / $3 + 0.5)
        }
    '
}

## Plug an output in, from a `monitor =` rule: `nested_output_add "FOREST-2,
## 1920x1080@60, 1280x0, 1.5"`. Returns once the compositor reports it, so the
## next assertion is about the shell rather than about a race.
##
## The rule is pushed before the output is created because Hyprland applies
## rules by name at the moment an output appears; pushed after, the output has
## already come up at the backend's default and the rule is a resize.
nested_output_add() {
    local spec="$1" name
    name=$(nested_output_name "$spec")

    nested_hyprctl keyword monitor "${spec// /}" > /dev/null || return 1
    nested_hyprctl output create headless "$name" > /dev/null || return 1

    local _
    for _ in $(seq 1 50); do
        nested_outputs | grep -qx "$name" && return 0
        sleep 0.1
    done
    echo "output $name never appeared" >&2
    return 1
}

## Pull an output back out, and wait until it is actually gone. The waiting is
## the point: "the surface went away" is only an assertion if the output did.
nested_output_remove() {
    local name="$1"
    nested_hyprctl output remove "$name" > /dev/null || return 1

    local _
    for _ in $(seq 1 50); do
        nested_outputs | grep -qx "$name" || return 0
        sleep 0.1
    done
    echo "output $name never went away" >&2
    return 1
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

## Click inside the nested session, at a point in the compositor's *global*
## coordinates: `nested_click 24 24`, `nested_click 640 400 right`.
##
## Two halves, because no one instrument does both. `hyprctl dispatch
## movecursor` warps the cursor and re-runs hit testing, which is the only form
## that spans several outputs — and it cannot press a button. `sendshortcut`
## carries mouse buttons and answers `ok`, but resolves its target as a
## *toplevel*, so against the bar, a drawer or the lock it delivers nothing at
## all and says so nowhere (measured on Hyprland 0.56.1, with a drawer open and
## with none: the shell's log stayed silent for every spelling of it). So the
## button goes in through a virtual pointer instead — tools/nested-click.c,
## above libinput and below anything the shell can see, so the click is
## hit-tested, focus-grabbed and delivered exactly as a real one is. That is
## what makes *delivery* assertable, which is the whole of #187.
##
## Aim it with `hyprctl layers`: a layer surface reports the `xywh` this takes.
nested_click() {
    local x="$1" y="$2" button="${3:-left}"
    nested_click_tool || return 1
    nested_hyprctl dispatch movecursor "$x" "$y" > /dev/null || return 1
    # The warp is a compositor-side event the surface under it has to be told
    # about before the button lands on it; without the pause the press arrives
    # in the same breath as the enter and the client has not laid out yet.
    sleep 0.2
    nested_env "$NESTED_CLICK_BIN" "$button" || return 1
}

## Drag inside the nested session, from one point in the compositor's global
## coordinates to another: `nested_drag 100 200 100 400`, with an optional step
## count as a fifth argument.
##
## Why this is not two `nested_click`s. tools/nested-click.c creates its virtual
## pointer, uses it and destroys it inside one process, so a press in one
## invocation and a release in another cannot hold a button down — the device
## dies in between and the compositor drops the grab with it. The whole gesture
## therefore happens inside one run of the tool, which is what `--drag` is.
##
## The motion is **absolute**, against the output's own extents, which is why
## this reads them rather than taking them on trust: relative motion goes
## through pointer acceleration and the landing coordinate stops being
## arithmetic. `motion_absolute` is scoped to one output and the tool binds
## none, so this is a **single-output helper** — under NESTED_MONITORS with more
## than one output it aims at the first, and a harness that needs a drag on the
## second output needs a different instrument.
##
## The extents are the **logical** ones, not the mode `hyprctl` prints. Both
## endpoints are compositor-global coordinates — the same space the opening
## `movecursor` warp is in — and that space is scaled, so dividing a logical x
## by a physical width is a fraction that is wrong by exactly the scale. At
## scale 1 the two agree and nothing shows; at 1.5 the drag lands two thirds of
## the way to where it was aimed and no instrument says so.
##
## The opening warp is `hyprctl dispatch movecursor`, exactly as `nested_click`
## does it and for the same reason: it is a compositor-side event the surface
## under it has to be told about before a button lands on it.
nested_drag() {
    local x1="$1" y1="$2" x2="$3" y2="$4" steps="${5:-12}" button="${6:-left}"
    nested_click_tool || return 1

    local output extents w h
    output=$(nested_outputs | head -n 1)
    [[ -n "$output" ]] || { echo "no output to drag on" >&2; return 1; }
    extents=$(nested_output_logical "$output")
    w="${extents%x*}"; h="${extents#*x}"
    [[ -n "$w" && -n "$h" && "$w" != "$extents" ]] || {
        echo "could not read the logical extents of $output" >&2; return 1; }

    nested_hyprctl dispatch movecursor "$x1" "$y1" > /dev/null || return 1
    sleep 0.2
    nested_env "$NESTED_CLICK_BIN" "$button" --drag "$x1" "$y1" "$x2" "$y2" \
        "$w" "$h" "$steps" || return 1
}

## A toplevel's rect as `<x> <y> <w> <h>`, found by a substring of its title, or
## nothing at all if no window matches.
##
## `hyprctl layers` is the wrong instrument for this and answers nothing: a
## `FloatingWindow` is a toplevel, so it is in `clients` and not in `layers`.
## And its size is read rather than assumed — under a nested Hyprland an
## ordinary window is tiled to the output, so whatever `implicitWidth` the QML
## declared is not what is on screen.
##
## First match wins, in the order Hyprland lists them; a harness that opens two
## windows with the same words in their titles should ask for something more
## specific.
nested_window_rect() {
    local want="$1"
    nested_hyprctl -j clients | python3 -c '
import json, sys
want = sys.argv[1]
try:
    clients = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for client in clients:
    if want in (client.get("title") or ""):
        at = client.get("at") or [0, 0]
        size = client.get("size") or [0, 0]
        print(at[0], at[1], size[0], size[1])
        break
' "$want"
}

## The bar's layer surface as `<monitor> <x> <y> <w> <h>`, or nothing at all if
## it never mapped.
##
## Here rather than in a harness because two of them aim at the bar and both had
## copied the same awk (#185): the rect is read from `hyprctl layers` rather than
## assumed from `NESTED_MONITORS`, and the monitor name comes from the same lines
## as the rect — with the backend's own output dropped (`NESTED_HEADLESS_ONLY`)
## the first declared name is not the one that exists. Coordinates *derived* from
## the rect stay in the harness: what counts as the launcher's x is that
## harness's business, and only the reading is shared.
nested_bar_rect() {
    nested_hyprctl layers | awk '
        /^Monitor / { mon = $2; sub(/:$/, "", mon) }
        /forest-shell:bar/ && !found {
            if (match($0, /xywh: [0-9-]+ [0-9-]+ [0-9-]+ [0-9-]+/)) {
                print mon, substr($0, RSTART + 6, RLENGTH - 6)
                found = 1
            }
        }'
}

## Build tools/nested-click.c against the vendored protocol, once per run.
##
## Built rather than vendored as a binary, and built into the run's own scratch
## dir rather than cached: a stale click tool is the kind of failure that reads
## as the shell being broken, and 0.3s of `cc` per harness run buys never
## having to wonder. Needs `wayland-scanner` and a C compiler — the same class
## of dependency `wtype` already is, and the failure says which one is missing.
nested_click_tool() {
    [[ -n "${NESTED_CLICK_BIN:-}" && -x "${NESTED_CLICK_BIN:-}" ]] && return 0
    [[ -n "$NESTED_WORK" ]] || { echo "no nested session to click in" >&2; return 1; }

    local build="$NESTED_WORK/click"
    local xml="$NESTED_TOOLS/protocols/wlr-virtual-pointer-unstable-v1.xml"
    mkdir -p "$build"

    local missing=()
    command -v wayland-scanner > /dev/null || missing+=(wayland-scanner)
    command -v cc > /dev/null || missing+=(cc)
    pkg-config --exists wayland-client 2> /dev/null || missing+=(wayland-client)
    if (( ${#missing[@]} )); then
        echo "cannot build the click tool — missing: ${missing[*]}" >&2
        return 1
    fi

    {
        wayland-scanner client-header "$xml" \
            "$build/wlr-virtual-pointer-unstable-v1-client-protocol.h" &&
        wayland-scanner private-code "$xml" \
            "$build/wlr-virtual-pointer-unstable-v1-protocol.c" &&
        cc -O1 -o "$build/nested-click" "$NESTED_TOOLS/nested-click.c" \
            "$build/wlr-virtual-pointer-unstable-v1-protocol.c" \
            -I"$build" $(pkg-config --cflags --libs wayland-client)
    } > "$build/build.log" 2>&1 || {
        echo "the click tool did not build — see $build/build.log" >&2
        return 1
    }

    NESTED_CLICK_BIN="$build/nested-click"
}

## Run a shell entry point inside the nested session, and wait for it to say it
## is up. The ready pattern is the caller's, because only the caller knows what
## its entry point logs — shell.qml's staged startup (#32) ends with a line, and
## a purpose-built harness root should log one of its own.
nested_shell() {
    local entry="${1:-shell.qml}" ready="${2:-}" timeout="${3:-20}"
    NESTED_SHELL_LOG="$NESTED_WORK/shell.log"
    NESTED_ENTRY="$entry"

    # Resolved here rather than at load time so `--help` still answers on a
    # machine whose runtime is not swapped yet. Everything downstream that
    # needs the binary — nested_ipc, the closing note — runs after this.
    NESTED_QS=$(qs_runtime_bin) || return 1

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
