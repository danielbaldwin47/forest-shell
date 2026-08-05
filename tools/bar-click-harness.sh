#!/usr/bin/env bash
# What a click on the bar does while a drawer is open, driven with a real
# pointer inside a nested Hyprland (#187).
#
#   tools/bar-click-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/bar-click-harness.sh --keep   # leave the nested session up to poke at
#
# Why this is its own harness and not four more cases in drawer-harness.sh: that
# one drives the drawer over IPC, and #187 is the one defect IPC cannot see. The
# reporter's own observation was the discriminator — super+space worked and the
# bar button did not, calling the same verb — so anything that reaches the verb
# without going through the compositor's pointer routing passes while the shell
# is broken. It has to be a click, hit-tested by a compositor, or it proves
# nothing.
#
# **Seam 1 cannot catch this and its tests are not the evidence.** The state
# machine (Surfaces/Drawers/DrawerPolicy.qml) was already correct;
# tests/tst_drawerpolicy.qml passed green through the whole of the bug. What it
# checks now is the routing table the fix adds. The delivery is here.
#
# What it asserts:
#
#   1. with nothing open, the launcher button opens the launcher
#   2. with the launcher open, its own button closes it — `closed (toggle)`
#   3. with the control centre open, the launcher button swaps to it in one
#      gesture — `controlcenter → launcher`, and no `clicked away` in between
#   4. with a drawer open, a click on bar dead space dismisses it — `closed (bar)`
#   5. with a drawer open, a click on an interactive control that is not a door
#      runs the control and leaves the drawer alone
#   6. a click on the desktop still dismisses, still as `clicked away`
#   7. the control centre's own button opens it, and Escape still closes a
#      drawer that a bar click opened
#   8. the launcher global — what super+space runs — still toggles
#
# ## How the targets are aimed
#
# The bar's layout is configuration, so the harness writes it: one module in
# each cluster, at a scratch `XDG_CONFIG_HOME`, with the bar flush rather than
# floating. That makes every target arithmetic on the bar's own layer geometry
# — `hyprctl layers` reports the rect the compositor actually gave it — instead
# of a guess about icon widths:
#
#   launcher      left cluster, one module     just inside the left edge
#   keyboard      centre cluster, one module   the middle of the bar
#   controlCenter right cluster, one module    just inside the right edge
#   dead space    a quarter of the way across  between two clusters, empty
#
# Check 1 exists to make that aim falsifiable: if the left-edge coordinate is
# wrong, the run fails on the first assertion rather than passing checks 2 and 3
# for the wrong reason.
#
# The interactive non-door control is the keyboard layout, chosen for having no
# side effects outside the session under test. Volume would be the ticket's own
# example and is the wrong choice here: the nested shell talks to the *host's*
# PipeWire, so a harness clicking mute mutes the speakers of the person running
# it. Cycling a layout changes a setting of the nested compositor and nothing
# else — and it needs two layouts to be on the bar at all, which is what
# `NESTED_CONFIG` is for.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

## A click, and then long enough for what it did to have finished happening.
##
## A drawer's entrance is 240 ms and its exit 140 (#27), and the window's own
## map is a compositor round trip on top of that. Every assertion here is about
## what happens when a person clicks the bar *next*, and a person is not inside
## that window — so the harness is not either. Without the settle the checks
## measure the gap between two frames rather than the routing they are for.
click() {
    nested_click "$1" "$2" || return 1
    sleep 0.6
}

log_lines() { wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0; }
since() { tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" 2>/dev/null; }

expect_since() {
    local mark="$1" pattern="$2" what="$3"
    for _ in $(seq 1 50); do
        if since "$mark" | grep -qaE "$pattern"; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — nothing matching /$pattern/ since the click"
    return 1
}

## Nothing matching arrived, and waiting longer would not change that.
expect_quiet_since() {
    local mark="$1" pattern="$2" what="$3"
    sleep 0.5
    if since "$mark" | grep -qaE "$pattern"; then
        nested_fail "$what — /$pattern/ arrived and should not have"
        return 1
    fi
    nested_pass "$what"
}

expect_open() {
    local target="$1" want="$2" what="$3"
    local got
    got=$(nested_ipc call "$target" isOpen)
    if [[ "$got" == "$want" ]]; then
        nested_pass "$what"
    else
        nested_fail "$what — $target isOpen said '$got', wanted '$want'"
    fi
}

# Two layouts, so the keyboard module is on the bar at all — it hides itself on
# a one-layout machine, which is most of them (Surfaces/Bar/Modules/
# KeyboardLayout.qml).
NESTED_MONITORS=("WAYLAND-1, 1280x800@60, 0x0, 1"
                 "HEADLESS-2, 1280x800@60, 0x0, 1")
NESTED_HEADLESS_ONLY=1
NESTED_CONFIG=($'input {\n    kb_layout = us,de\n}')

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
cat > "$SCRATCH/config/forest-shell/settings.json" <<'EOF'
{
  "bar": {
    "floating": false,
    "modules": {
      "left": ["launcher"],
      "center": ["keyboard"],
      "right": ["controlCenter"]
    }
  }
}
EOF
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

nested_shell shell.qml 'drawers armed' 25 || exit 1
# The bar's own window logs when it maps; the modules land a frame or two later.
nested_await "$NESTED_SHELL_LOG" 'bar: window up on' 15 > /dev/null
sleep 2

# --- where the bar is --------------------------------------------------------

bar_rect=$(nested_hyprctl layers \
           | sed -n 's/.*xywh: \([0-9-]*\) \([0-9-]*\) \([0-9-]*\) \([0-9-]*\),.*forest-shell:bar.*/\1 \2 \3 \4/p' \
           | head -1)
read -r bar_x bar_y bar_w bar_h <<< "$bar_rect"

if [[ -z "${bar_h:-}" ]]; then
    nested_fail 'the bar never mapped a layer surface — nothing to click'
    nested_down
    exit 1
fi
nested_note "bar at ${bar_x},${bar_y} ${bar_w}×${bar_h}"

mid_y=$(( bar_y + bar_h / 2 ))
launcher_x=$(( bar_x + 20 ))
control_x=$(( bar_x + bar_w - 20 ))
keyboard_x=$(( bar_x + bar_w / 2 ))
dead_x=$(( bar_x + bar_w / 4 ))

# --- 1. the aim is right, and the bar works with nothing open -----------------

mark=$(log_lines)
click "$launcher_x" "$mid_y"
expect_since "$mark" 'drawers: launcher opened on ' \
    'with nothing open, the launcher button opens the launcher'

# --- 2. the open drawer's own door closes it ---------------------------------
#
# The reporter's second case: "you have to dismiss it entirely first". A click
# on the button that opened it has to be the thing that closes it.

mark=$(log_lines)
click "$launcher_x" "$mid_y"
expect_since "$mark" 'drawers: launcher closed \(toggle\)' \
    "the launcher's own button closes it"
expect_open launcher false 'and it really is closed'

# --- 3. another door swaps, in one gesture -----------------------------------
#
# The ticket's headline. The evidence that it is *one* gesture is the switch
# line — #27's cross-drawer transition is a single assignment, so a swap that
# had become a close and then an open would log `closed` and `opened` instead —
# and the absence of `clicked away`, which is what a dismissal on the way
# through would leave behind.

nested_ipc call controlcenter toggle > /dev/null
expect_open controlcenter true 'the control centre is open to swap away from'

mark=$(log_lines)
click "$launcher_x" "$mid_y"
expect_since "$mark" 'drawers: controlcenter → launcher' \
    'the launcher button swaps the control centre out in one gesture'
expect_quiet_since "$mark" 'clicked away' \
    'and nothing was dismissed on the way through'
expect_open launcher true 'the launcher is what is open afterwards'
expect_open controlcenter false 'and the control centre is not'

# --- 4. dead space dismisses -------------------------------------------------

mark=$(log_lines)
click "$dead_x" "$mid_y"
expect_since "$mark" 'drawers: launcher closed \(bar\)' \
    'a click on empty bar space dismisses the drawer'

# --- 5. an interactive control acts, and the drawer stays --------------------
#
# The row that is easy to get backwards. `Compositor.keyboardLayout` is read
# from the compositor's own `activelayout` event rather than set optimistically,
# so the bar's label changing is the compositor confirming the click arrived.

layout_before=$(nested_hyprctl devices | sed -n 's/^\s*active keymap:\s*\(.*\)$/\1/p' | head -1)
nested_ipc call controlcenter toggle > /dev/null
expect_open controlcenter true 'the control centre is open to click past'

mark=$(log_lines)
click "$keyboard_x" "$mid_y"
sleep 1
layout_after=$(nested_hyprctl devices | sed -n 's/^\s*active keymap:\s*\(.*\)$/\1/p' | head -1)

if [[ -n "$layout_before" && "$layout_before" != "$layout_after" ]]; then
    nested_pass "the keyboard module acted ($layout_before → $layout_after)"
else
    nested_fail "the keyboard module did nothing (keymap stayed '$layout_before')"
fi
expect_quiet_since "$mark" 'drawers: controlcenter closed' \
    'and the control centre stayed open under it'
expect_open controlcenter true 'the control centre is still open'

# --- 6. the desktop still dismisses ------------------------------------------

mark=$(log_lines)
click $(( bar_x + bar_w / 2 )) $(( bar_y + bar_h + 300 ))
expect_since "$mark" 'drawers: controlcenter closed \(clicked away\)' \
    'a click on the desktop still dismisses, still as `clicked away`'

# --- 7. the keyboard still works, after a drawer opened from the bar ---------
#
# Opened by *clicking* its own button rather than over IPC, which is the case
# that matters: the drawer takes the keyboard as it maps, and the thing that
# used to be able to take it away instead was the focus grab — it hands keyboard
# focus to whichever of its windows the pointer is over, and the pointer is over
# the bar exactly when a bar button opened the drawer. This is what says the
# grab is gone (see the header of Surfaces/Drawers/Drawers.qml).
#
# It is also the right-edge target's one appearance, so a bad `control_x` fails
# here rather than never being noticed.

mark=$(log_lines)
click "$control_x" "$mid_y"
expect_since "$mark" 'drawers: controlcenter opened on ' \
    'the control centre button opens it'

mark=$(log_lines)
nested_key_focused escape
expect_since "$mark" 'drawers: controlcenter closed \(escape\)' \
    'Escape still closes a drawer that a bar click opened'

# --- 8. super+space still toggles the launcher -------------------------------
#
# The one binding with no `qs ipc call` behind it — a `global` dispatch straight
# into the shell (Surfaces/Drawers/Drawers.qml). It is in this run because it is
# the *control*: it worked throughout the bug, which is what told the reporter
# the state machine was fine and the click was being lost.
#
# Dispatched rather than typed. `sendshortcut` delivers a keystroke to a
# surface; it does not run the compositor's own binds, so pressing SUPER+SPACE
# through it would prove nothing about a bind. What the user's
# `bind = SUPER, SPACE, global, forest-shell:launcher` actually does is this
# dispatch, so this is the whole of the path the shell owns.

mark=$(log_lines)
nested_hyprctl dispatch global forest-shell:launcher > /dev/null
expect_since "$mark" 'drawers: launcher opened on ' \
    'the launcher global still opens the launcher'

mark=$(log_lines)
nested_hyprctl dispatch global forest-shell:launcher > /dev/null
expect_since "$mark" 'drawers: launcher closed \(toggle\)' \
    'and still closes it'

nested_down
exit $(( nested_fail_count > 0 ))
