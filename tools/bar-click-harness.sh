#!/usr/bin/env bash
# What a click on the bar does while a drawer is open, driven with a real
# pointer inside a nested Hyprland (#187, #199).
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
#   7. the control centre's own button opens *and* closes it, and Escape still
#      closes a drawer that a bar click opened
#   8. the launcher global — what super+space runs — still toggles
#   9. with a second screen plugged in, a click on it dismisses too
#
# ## Twice, because there are two mechanisms (#199)
#
# The whole table runs once with `bar.autoHide` off and once with it on, and
# they are not the same test. A pinned bar reserves an exclusive zone, so the
# compositor lays the drawer's fog out *below* it and the bar is the only
# surface over its own strip — that is #187's fix, and it is geometry alone. An
# auto-hiding bar reserves nothing by definition, so there is nothing for the
# fog to stop at: the fog covers the strip, both surfaces are `WlrLayer.Top`,
# and the drawer maps second and therefore wins. Every row above failed again
# in that configuration, on `main` and on #187's own branch.
#
# What covers it there is a hole cut in the drawer's input mask over the bar's
# current rect (Core/BarStripsPolicy.qml). So the run also asserts the *hole*,
# before it asserts anything a click did through it: a pinned bar must produce
# no cutout at all — it does not need one and a hole would be punched through
# fog that is somewhere else — and an auto-hidden one must produce a cutout the
# size of its whole band while it is out, and none at all once it goes away.
# #187's own lesson is why that check exists: a click check can pass for the
# wrong reason, and the verb was never the broken part.
#
# The auto-hide pass pins the bar out with `ipc call bar reveal` rather than by
# hovering the screen edge. It is the same state — an override of `shown` still
# reserves no space while `autoHide` is on, which is the whole of what breaks
# the geometry — and it is the *stable* one. Hovering is not: the bar's own mask
# follows `content`, which slides in over ~240 ms from outside the window, so
# the pointer that just triggered the reveal is left outside the input region
# with no motion to re-enter on, and the 400 ms linger expires before it gets
# one. That flap is the bar's own behaviour and predates #199; a harness that
# drove the reveal by hover would be measuring it rather than the routing.
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
# The rect is read again for each pass. An auto-hidden bar keeps its window and
# its geometry while it is away — only the mask shrinks to the one-pixel reveal
# strip — so the numbers come out the same, and reading them again is what says
# so rather than assumes it.
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

## Which pass is running, printed into every check name. Two identical-looking
## failures in one run are otherwise indistinguishable in the output.
pass_label=""
say() { printf '%s%s' "$pass_label" "$1"; }

expect_since() {
    local mark="$1" pattern="$2" what
    what=$(say "$3")
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
    local mark="$1" pattern="$2" what
    what=$(say "$3")
    sleep 0.5
    if since "$mark" | grep -qaE "$pattern"; then
        nested_fail "$what — /$pattern/ arrived and should not have"
        return 1
    fi
    nested_pass "$what"
}

expect_open() {
    local target="$1" want="$2" what
    what=$(say "$3")
    local got
    got=$(nested_ipc call "$target" isOpen)
    if [[ "$got" == "$want" ]]; then
        nested_pass "$what"
    else
        nested_fail "$what — $target isOpen said '$got', wanted '$want'"
    fi
}

## The hole in the drawer's mask, right now (#199).
##
## The drawer logs the cutout when it *changes*, so the current state is the
## last such line rather than any line since a mark — most of the time the right
## hole is already cut and nothing new is said.
##
## The window has to be mapped for this to mean anything: an unmapped
## `PanelWindow` has no size, and a cutout is refused whenever the window is not
## the size of its screen. So every caller opens a drawer first.
expect_cutout() {
    local want="$1" what
    what=$(say "$2")
    local got=""
    for _ in $(seq 1 40); do
        got=$(grep -a "cutout on $bar_screen" "$NESTED_SHELL_LOG" 2>/dev/null | tail -1)
        if [[ "$got" == *"$want"* ]]; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — wanted a cutout line containing '$want', last was '${got:-none at all}'"
    return 1
}

# --- the session -------------------------------------------------------------

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
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

## The scratch config, with `bar.autoHide` as the one thing that differs between
## the two passes.
write_settings() {
    cat > "$SCRATCH/config/forest-shell/settings.json" <<EOF
{
  "bar": {
    "floating": false,
    "autoHide": $1,
    "modules": {
      "left": ["launcher"],
      "center": ["keyboard"],
      "right": ["controlCenter"]
    }
  }
}
EOF
}

## Restarted rather than reloaded between passes. `bar.autoHide` changes what
## the bar reserves, which changes how the compositor lays the drawer's window
## out; a restart is the one way to be sure the run is looking at the new
## arrangement and not at a surface that has not been reconfigured yet.
start_shell() {
    nested_shell shell.qml 'drawers armed' 25 || return 1
    # The bar's own window logs when it maps; the modules land a frame or two
    # later.
    nested_await "$NESTED_SHELL_LOG" 'bar: window up on' 15 > /dev/null
    sleep 2
}

## Where the bar is, and which screen it is on. The screen name is what the
## cutout lines are keyed by, so it is read from the same place as the rect
## rather than assumed from `NESTED_MONITORS` — the backend's own output is
## dropped here (`NESTED_HEADLESS_ONLY`), so the first declared name is not the
## one that exists.
measure_bar() {
    local info
    info=$(nested_hyprctl layers | awk '
        /^Monitor / { mon = $2; sub(/:$/, "", mon) }
        /forest-shell:bar/ && !found {
            if (match($0, /xywh: [0-9-]+ [0-9-]+ [0-9-]+ [0-9-]+/)) {
                print mon, substr($0, RSTART + 6, RLENGTH - 6)
                found = 1
            }
        }')
    read -r bar_screen bar_x bar_y bar_w bar_h <<< "$info"

    if [[ -z "${bar_h:-}" ]]; then
        nested_fail "$(say 'the bar never mapped a layer surface — nothing to click')"
        return 1
    fi
    nested_note "$(say "bar at ${bar_x},${bar_y} ${bar_w}×${bar_h} on $bar_screen")"

    mid_y=$(( bar_y + bar_h / 2 ))
    launcher_x=$(( bar_x + 20 ))
    control_x=$(( bar_x + bar_w - 20 ))
    keyboard_x=$(( bar_x + bar_w / 2 ))
    dead_x=$(( bar_x + bar_w / 4 ))
    # Well clear of the bar and of the one-pixel reveal strip, so parking here
    # cannot hold an auto-hiding bar out.
    away_y=$(( bar_y + bar_h + 300 ))
}

# --- the table ---------------------------------------------------------------

## #187's nine checks, run once per pass.
##
## Deliberately not parameterised: it reads the target coordinates `measure_bar`
## sets — `mid_y`, `launcher_x`, `control_x`, `keyboard_x`, `dead_x`, `away_y`,
## `bar_screen` — and the pass it is running is `pass_label`, which every
## assertion carries into its own name. They are globals because they were
## globals when this was a straight-line script, and passing seven coordinates
## through a positional interface would be less legible rather than more.
run_table() {

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
    nested_pass "$(say "the keyboard module acted ($layout_before → $layout_after)")"
else
    nested_fail "$(say "the keyboard module did nothing (keymap stayed '$layout_before')")"
fi
expect_quiet_since "$mark" 'drawers: controlcenter closed' \
    'and the control centre stayed open under it'
expect_open controlcenter true 'the control centre is still open'

# --- 6. the desktop still dismisses ------------------------------------------

mark=$(log_lines)
click "$keyboard_x" "$away_y"
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

# The ticket's first acceptance criterion, in its own words and with its own
# surface: check 2 makes the same claim about the launcher, and the launcher is
# at the other end of the bar in the other cluster, so both are worth having.
mark=$(log_lines)
click "$control_x" "$mid_y"
expect_since "$mark" 'drawers: controlcenter closed \(toggle\)' \
    "the control centre's own button closes it"

click "$control_x" "$mid_y"
expect_open controlcenter true 'and opens it again, to press Escape at'

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

# --- 9. a click on a screen the drawer is not on still dismisses -------------
#
# The grab's last job, inherited by geometry. The drawer window now maps on
# every screen while one is open — fog on the drawer's own screen, an empty
# input mask everywhere else — because dismissing from a second monitor used to
# be the grab consuming clicks everywhere it did not name. That is a new claim
# and this is the only seam that can hold more than one screen (#98), so it is
# asserted rather than asserted-in-a-comment.
#
# The output is plugged in *before* the drawer opens, deliberately: a screen set
# that changes under an open drawer is the hotplug reset (`survivesScreenChange`)
# and would close it for an entirely different reason.

SECOND="HEADLESS-9"
if nested_output_add "$SECOND, 1280x800@60, 1280x0, 1"; then
    sleep 1.5
    nested_ipc call controlcenter toggle > /dev/null
    expect_open controlcenter true 'the control centre is open on the first screen'

    mark=$(log_lines)
    click 1920 400
    expect_since "$mark" 'drawers: controlcenter closed \(clicked away\)' \
        'a click on the other screen dismisses the drawer'

    nested_output_remove "$SECOND" > /dev/null
    sleep 1
else
    nested_fail "$(say "could not plug in $SECOND — the second-screen claim is untested")"
fi

}

# --- what the drawer cut out of its own fog (#199) ---------------------------

## A pinned bar needs no hole, and must not be given one: the fog is laid out
## below its reserved strip, so a hole cut at the bar's screen coordinates would
## land in the middle of a window whose origin is 32 px further down.
check_no_cutout() {
    nested_ipc call controlcenter toggle > /dev/null
    expect_open controlcenter true 'a drawer is open for the fog to be measured'
    expect_cutout "no bar cutout on $bar_screen" \
        'a reserving bar gets no hole cut for it — geometry already covers it'
    nested_ipc call controlcenter toggle > /dev/null
    sleep 0.5
}

## An auto-hidden bar gets one while it is out, and none at all once it goes
## away. Not a smaller one: while the bar is away there is nothing behind the
## fog to reach — its dismiss handler is parked outside the window with the rest
## of `content` — so a hole over the reveal strip would be a row of the band
## that neither acts nor dismisses. The whole band stays fog instead, which is
## #199's second acceptance criterion in as many words.
check_cutout_tracks_the_bar() {
    nested_ipc call bar reveal > /dev/null
    nested_ipc call controlcenter toggle > /dev/null
    expect_open controlcenter true 'a drawer is open for the fog to be measured'
    expect_cutout "cutout on $bar_screen: ${bar_w}×${bar_h}+" \
        'an auto-hidden bar that is out gets a hole the size of its whole band'

    # Away, and the pointer parked well clear so nothing holds it out.
    nested_hyprctl dispatch movecursor "$keyboard_x" "$away_y" > /dev/null
    nested_ipc call bar auto > /dev/null
    expect_cutout "no bar cutout on $bar_screen" \
        'and the hole closes entirely when the bar goes away'

    # The cutout line says the *shell* has decided, not that the compositor has
    # applied the new input region — those are two surfaces committing
    # separately, and for a frame or two after the bar goes away the old
    # full-band hole can still be live over a bar that has already shrunk to its
    # reveal strip. A click in that window reaches neither and does nothing.
    # Measured: clicking 0.3 s after the line fails, 1.2 s after it passes. It
    # is the same argument `click` makes for its own settle — the check is what
    # a click reaches, not how many frames the region took.
    sleep 1

    # #199's second acceptance criterion. The discriminator is *which* reason the
    # drawer closes for: a click that reached the bar's dead space closes it as
    # `bar`, and one that reached the fog closes it as `clicked away`. With the
    # bar gone this band belongs to the fog, and saying so needs the reason.
    mark=$(log_lines)
    click "$dead_x" "$mid_y"
    expect_since "$mark" 'drawers: controlcenter closed \(clicked away\)' \
        'with the bar away, a click where it would be reaches the fog and dismisses'

    nested_ipc call bar reveal > /dev/null
    sleep 0.5
}

# --- both passes -------------------------------------------------------------

for pass in pinned autohide; do
    if [[ "$pass" == pinned ]]; then
        pass_label=""
        auto=false
    else
        pass_label="[auto-hide] "
        auto=true
        nested_kill_shell
    fi

    write_settings "$auto"
    start_shell || { nested_down; exit 1; }
    measure_bar || { nested_down; exit 1; }

    if [[ "$pass" == pinned ]]; then
        check_no_cutout
    else
        # Pinned out for the table, and pinned by the override rather than by
        # the pointer — see the header on why hovering is not a stable way to
        # hold an auto-hiding bar in place.
        check_cutout_tracks_the_bar
        nested_ipc call bar reveal > /dev/null
    fi

    run_table
done

nested_down
exit $(( nested_fail_count > 0 ))
