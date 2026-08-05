#!/usr/bin/env bash
# Which cursor the bar asks for, read off the Wayland wire (#185).
#
#   tools/cursor-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/cursor-harness.sh --keep   # leave the nested session up to poke at
#
# #185 was filed as "no seam covers this": the pointer is not in the client's
# own scene, so a seam-3 capture never holds it, and the nested compositor
# cannot screenshot. Both are still true — and neither matters, because a cursor
# is not a picture the client draws. It is a *request* the client sends, and a
# request is a line in the log:
#
#     wp_cursor_shape_device_v1#30.set_shape(15, 4)
#
# `4` is `pointer` in that protocol's enum and `1` is `default` — the hand and
# the arrow. So the shell is run with `WAYLAND_DEBUG=1` in `NESTED_ENV`, the
# pointer is put over each target, and the shape it asks for is asserted. That
# is seam 2 doing exactly what seam 2 is for: a thing that only exists once a
# compositor is involved, driven over the protocol and asserted on a log.
#
# What it does not cover, and what still wants a real session: the system tray
# (needs a tray application to have anything to hover) and the notification
# surfaces (the host session already owns `org.freedesktop.Notifications`).
#
# ## Three things this took to work at all, none of them obvious
#
# **A headless seat has no pointer.** `hyprctl dispatch movecursor` moves a
# cursor that no client can see: with no pointer device on the seat, `wl_seat`
# advertises no pointer capability and not one `wl_pointer.enter` is ever sent.
# The virtual pointer `tools/nested-click.c` creates is what puts the pointer on
# the wire — so a *hover* here is a warp plus a click, and the click uses the
# **middle** button, which every target below ignores (`BarIndicator` takes the
# left alone). The button is the price of the pointer existing, not the gesture
# under test.
#
# **The debug log is colourised even into a file.** libwayland writes escape
# sequences between the object name, its id and the method, so `wl_pointer@`
# matches nothing and `set_shape(` matches nothing. Every read here strips them
# first. A pattern that silently never matches reads exactly like a shell that
# never asked for a cursor, which cost a run to tell apart.
#
# **The last shape wins.** Entering a surface can produce two requests in a row —
# the window's cursor and then the item's — so a hover is judged on the last
# shape it produced, not the first or the count.
#
# ## How the targets are aimed
#
# The same way `tools/bar-click-harness.sh` aims its clicks, and for the same
# reason: one module per cluster in a scratch config, so every coordinate is
# arithmetic on the bar's own rect out of `hyprctl layers` rather than a guess
# about icon widths.
#
#   pass 1, the controls    launcher / keyboard / controlCenter  → pointer
#                           bar dead space                       → arrow
#   pass 2, the readouts    systemMonitor / clock / battery      → arrow except
#                                                                  the clock
#
# The pointer assertions are the strong half: only an interactive module asks
# for shape 4, so they cannot pass for the wrong reason. An arrow assertion is
# weaker by construction — a module that hid itself (no battery on a desktop)
# leaves bare bar strip under the pointer, which is also an arrow. `clock` is in
# pass 2 as its own control: it rolls its own hover handling, it is supposed to
# be the pointer, and it is the one target in that pass that proves the pass is
# aimed at modules at all.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

POINTER=4   # wp_cursor_shape_device_v1.shape.pointer — the hand
ARROW=1     # .shape.default — the arrow

# --- the session -------------------------------------------------------------

# Two layouts, so the keyboard module is on the bar at all (it hides itself on a
# one-layout machine), the same reason bar-click-harness declares them.
NESTED_MONITORS=("WAYLAND-1, 1280x800@60, 0x0, 1"
                 "HEADLESS-2, 1280x800@60, 0x0, 1")
NESTED_HEADLESS_ONLY=1
NESTED_CONFIG=($'input {\n    kb_layout = us,de\n}')

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state"
            "WAYLAND_DEBUG=1")

pass_label=""
say() { printf '%s%s' "$pass_label" "$1"; }

## The scratch config: one module per cluster, bar flush rather than floating.
write_settings() {
    cat > "$SCRATCH/config/forest-shell/settings.json" <<EOF
{
  "bar": {
    "floating": false,
    "autoHide": false,
    "modules": {
      "left": ["$1"],
      "center": ["$2"],
      "right": ["$3"]
    }
  }
}
EOF
}

start_shell() {
    nested_shell shell.qml 'drawers armed' 40 || return 1
    nested_await "$NESTED_SHELL_LOG" 'bar: window up on' 20 > /dev/null
    # The window maps before its modules land; a hover during that gap reads the
    # strip rather than the module that is about to fill it.
    sleep 2
}

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
        nested_fail "$(say 'the bar never mapped a layer surface — nothing to hover')"
        return 1
    fi
    nested_note "$(say "bar at ${bar_x},${bar_y} ${bar_w}×${bar_h} on $bar_screen")"

    mid_y=$(( bar_y + bar_h / 2 ))
    left_x=$(( bar_x + 20 ))
    centre_x=$(( bar_x + bar_w / 2 ))
    right_x=$(( bar_x + bar_w - 20 ))
    dead_x=$(( bar_x + bar_w / 4 ))
    # Well clear of the bar, and where the fog would be if a drawer were open.
    away_y=$(( bar_y + bar_h + 300 ))
}

# --- the wire ----------------------------------------------------------------

## Every shape the shell asked for since line `$1`, oldest first.
shapes_since() {
    tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | grep -ao 'set_shape([0-9]*, [0-9]*)' \
        | sed 's/.*, //; s/)//'
}

## Hover `$2,$3` and assert the shell settles on shape `$4`.
hover_is() {
    local what="$1" x="$2" y="$3" want="$4"
    local mark got
    mark=$(wc -l < "$NESTED_SHELL_LOG")

    # Park off the bar first, so the reading is a change *onto* the target
    # rather than whatever the last hover left the cursor showing.
    nested_hyprctl dispatch movecursor "$centre_x" "$away_y" > /dev/null
    sleep 0.4
    nested_click "$x" "$y" middle > /dev/null || {
        nested_fail "$(say "$what — could not put the pointer on $x,$y")"
        return 1
    }
    sleep 0.8

    got=$(shapes_since "$mark" | tail -1)
    if [[ "$got" == "$want" ]]; then
        nested_pass "$(say "$what asks for $(shape_name "$want")")"
        return 0
    fi
    nested_fail "$(say "$what asked for $(shape_name "${got:-none}") at $x,$y, wanted $(shape_name "$want")")"
    return 1
}

shape_name() {
    case "$1" in
        "$POINTER") echo "the pointer ($POINTER)" ;;
        "$ARROW")   echo "the arrow ($ARROW)" ;;
        none)       echo "no cursor at all" ;;
        *)          echo "shape $1" ;;
    esac
}

# --- the table ---------------------------------------------------------------

pass_label="[controls] "
write_settings launcher keyboard controlCenter
start_shell || { nested_down; exit 1; }
measure_bar || { nested_down; exit 1; }

# The three the reporter named, and the fourth thing on that strip that is not a
# control at all — which is the check that says the bar did not simply grow a
# hand everywhere.
hover_is "the launcher button"      "$left_x"   "$mid_y" "$POINTER"
hover_is "the keyboard layout"      "$centre_x" "$mid_y" "$POINTER"
hover_is "the control-centre button" "$right_x"  "$mid_y" "$POINTER"
hover_is "bar dead space"           "$dead_x"   "$mid_y" "$ARROW"

pass_label="[readouts] "
nested_kill_shell
write_settings systemMonitor clock battery
start_shell || { nested_down; exit 1; }
measure_bar || { nested_down; exit 1; }

hover_is "the system monitor" "$left_x"   "$mid_y" "$ARROW"
hover_is "the clock"          "$centre_x" "$mid_y" "$POINTER"
hover_is "the battery"        "$right_x"  "$mid_y" "$ARROW"

nested_down
exit $(( nested_fail_count > 0 ))
