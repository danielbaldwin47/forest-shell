#!/usr/bin/env bash
# What a click on a bar *status indicator* opens, driven with a real pointer
# inside a nested Hyprland (#184).
#
#   tools/bar-indicator-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/bar-indicator-harness.sh --keep   # leave the nested session up to poke at
#
# Its own harness rather than four more cases in tools/bar-click-harness.sh, for
# a reason that is layout and not taste: that one aims at three targets — the
# left edge, the middle, the right edge — because each of its clusters holds
# exactly one module, and a fourth aimable thing does not exist on a bar with
# three clusters. This one gives the whole right cluster to the status group and
# takes the other two for the drawer it swaps from and the readout it must not
# open.
#
# Seam 1 holds the tables (tests/tst_drillinpolicy.qml `panelForIndicator`,
# tests/tst_drawerpolicy.qml `barIndicatorClick`) and passes whether or not a
# glyph is clickable at all. What is checked here is that the click lands on the
# glyph, reaches the routing, and moves the control centre — which is the same
# argument #187's harness makes and the same reason this cannot be IPC.
#
# What it asserts:
#
#   1. every glyph in the cluster opens a panel, and they are the panels the
#      table names, in the order the cluster draws them
#   2. with nothing open, a click on a glyph opens the control centre *already
#      drilled* — one gesture, not the two it took before
#   3. the same glyph again closes the control centre
#   4. with the control centre open on another panel, the glyph swaps the panel
#      and the drawer never leaves the screen
#   5. with another drawer open, the glyph swaps to the control centre, drilled
#   6. a readout with no panel behind it is still not a door: it dismisses like
#      the dead space it is, and opens nothing when nothing is open
#
# ## How the targets are aimed
#
# `bar.padding` is configuration, so the harness sets it to 0 and the cluster
# ends flush with the bar's right edge. Inside Surfaces/Bar/Modules/Status.qml
# the glyphs are 16px icons at `Theme.space2` (8px) apart, so they sit on a 24px
# pitch counting leftwards from `bar_x + bar_w - 8`.
#
# How *many* of them are there is not the harness's to decide: the cluster shows
# a wifi glyph only where NetworkManager answers, a bluetooth glyph only on a
# machine with an adapter, and the mic only while it is muted — all three read
# from the host's own services through the nested session. So check 1 discovers
# the cluster instead of assuming it: it clicks each of the four slots with
# nothing open, asks `controlcenter panel` what that did, and builds the map the
# rest of the run aims with. A slot past the end of the cluster is dead bar and
# opens nothing, which with no drawer open is a click that does nothing at all —
# the safe direction to be wrong in.
#
# The run needs at least two distinct panels to make check 4 a swap rather than
# a reopen. Where the cluster only ever shows one — a desktop with no radios and
# no mic — check 4 drills the second panel over IPC instead and says so.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

## A click, and then long enough for what it did to have finished happening —
## the same 0.6s tools/bar-click-harness.sh settles for, and for the same
## reason: a drawer's entrance is 240ms (#27) and its window's map is a
## compositor round trip after that.
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

## What the control centre is drilled into, or "" for its root. The one question
## the whole harness turns on, and it is a query rather than a log scrape
## because `drill` is idempotent-looking in the log: a panel that opened and one
## that was already open read the same afterwards.
drilled() { nested_ipc call controlcenter panel; }

expect_drilled() {
    local want="$1" what="$2"
    local got
    got=$(drilled)
    if [[ "$got" == "$want" ]]; then
        nested_pass "$what"
    else
        nested_fail "$what — drilled into '$got', wanted '$want'"
    fi
}

# One screen, and it has to be the headless one: `NESTED_HEADLESS_ONLY` drops
# the backend's own window, so a monitor list naming only `WAYLAND-1` leaves the
# session with no output at all and the bar with nothing to map onto (measured —
# the first run of this harness failed exactly there).
NESTED_MONITORS=("WAYLAND-1, 1280x800@60, 0x0, 1"
                 "HEADLESS-2, 1280x800@60, 0x0, 1")
NESTED_HEADLESS_ONLY=1

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
cat > "$SCRATCH/config/forest-shell/settings.json" <<'EOF'
{
  "bar": {
    "floating": false,
    "padding": 0,
    "modules": {
      "left": ["launcher"],
      "center": ["systemMonitor"],
      "right": ["status"]
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
monitor_x=$(( bar_x + bar_w / 2 ))
dead_x=$(( bar_x + bar_w / 4 ))

# A 16px icon on an 8px gap, counting leftwards from the flush right edge.
slot_x() { echo $(( bar_x + bar_w - 8 - $1 * 24 )); }

# --- 1. what the cluster is --------------------------------------------------
#
# Discovery *and* an assertion: the panels found have to be panels, and they
# have to arrive in the order Status.qml draws its glyphs — wifi, bluetooth,
# volume, mic — read backwards from the right edge. A cluster that answered
# `wifi` from the rightmost slot would mean the aim is off by a glyph, and every
# check below it would then be testing whichever glyph it happened to hit.

declare -a SLOT_PANEL=()
for slot in 0 1 2 3; do
    x=$(slot_x "$slot")
    click "$x" "$mid_y"
    panel=$(drilled)
    SLOT_PANEL+=("$panel")
    if [[ -n "$panel" ]]; then
        # Put it back the way it was found: the next slot's click has to start
        # from nothing open or it is measuring a swap.
        nested_ipc call controlcenter toggle > /dev/null
        sleep 0.4
    fi
done

found="${SLOT_PANEL[*]}"
nested_note "slots right-to-left opened: [${found// /] [}]"

# Trailing empties are slots past the end of the cluster; what is left is the
# cluster itself, and it must be a suffix of the glyph order reversed.
cluster=()
for panel in "${SLOT_PANEL[@]}"; do
    [[ -z "$panel" ]] && break
    cluster+=("$panel")
done

if [[ ${#cluster[@]} -eq 0 ]]; then
    nested_fail 'no status glyph opened anything — the aim is wrong, or nothing is wired'
    nested_down
    exit 1
fi
nested_pass "${#cluster[@]} status glyph(s) open a panel"

# `audio` twice in a row is the volume and the mic, which share a panel by
# design (DrillInPolicy.panelForSlider, and now panelForIndicator).
expected_order=("audio" "audio" "bluetooth" "wifi")
order_ok=1
for i in "${!cluster[@]}"; do
    case "${cluster[$i]}" in
        wifi|bluetooth|audio) ;;
        *) order_ok=0 ;;
    esac
done
# The panels the cluster showed, in right-to-left order, have to be a
# subsequence of the order above — same relative order, gaps allowed for the
# glyphs this machine does not show.
j=0
for panel in "${cluster[@]}"; do
    while [[ $j -lt ${#expected_order[@]} && "${expected_order[$j]}" != "$panel" ]]; do
        j=$(( j + 1 ))
    done
    if [[ $j -ge ${#expected_order[@]} ]]; then
        order_ok=0
        break
    fi
    j=$(( j + 1 ))
done

if [[ $order_ok -eq 1 ]]; then
    nested_pass "the glyphs open their own panels, in the cluster's own order (${cluster[*]})"
else
    nested_fail "the cluster opened [${cluster[*]}] — not the order Status.qml draws"
fi

# The glyph the rest of the run clicks, and the panel it must open.
target_x=$(slot_x 0)
target_panel="${cluster[0]}"

# A second, different panel for the swap in check 4. The cluster's own, where it
# has one — otherwise the control centre gets drilled over IPC and the check
# says so.
other_panel=""
for panel in "${cluster[@]}"; do
    if [[ "$panel" != "$target_panel" ]]; then
        other_panel="$panel"
        break
    fi
done
if [[ -z "$other_panel" ]]; then
    other_panel=$([[ "$target_panel" == "wifi" ]] && echo bluetooth || echo wifi)
    nested_note "only one panel in this cluster; check 4 drills '$other_panel' over IPC"
fi

# --- 2. a glyph opens the control centre already drilled ---------------------

expect_open controlcenter false 'the control centre starts closed'

mark=$(log_lines)
click "$target_x" "$mid_y"
expect_since "$mark" "drawers: controlcenter opened on " \
    'a status glyph opens the control centre'
expect_since "$mark" "control-centre: $target_panel panel opened" \
    "and it arrives drilled into $target_panel"
expect_drilled "$target_panel" 'the drilled panel is the glyph’s own'

# --- 3. the same glyph closes it ---------------------------------------------
#
# `DrillInPolicy.next` and `DrawerPolicy.next` both say the control that opened
# a thing closes it; from the bar that is one table further out, and this is the
# row.

mark=$(log_lines)
click "$target_x" "$mid_y"
expect_since "$mark" 'drawers: controlcenter closed \(toggle\)' \
    'the same glyph again closes the control centre'
expect_open controlcenter false 'and it really is closed'

# --- 4. another glyph swaps the panel without reopening the drawer -----------
#
# The acceptance criterion with the most ways to look right and be wrong: a
# close followed by an open lands on the same screen as a swap. The evidence is
# what is *absent* — no `drawers: controlcenter closed` between the two panel
# lines — plus `isOpen` never having gone false, which is what the drawer
# closing would have logged.

nested_ipc call controlcenter toggle > /dev/null
sleep 0.4
nested_ipc call controlcenter drill "$other_panel" > /dev/null
sleep 0.4
expect_drilled "$other_panel" "the control centre is open on $other_panel to swap away from"

mark=$(log_lines)
click "$target_x" "$mid_y"
expect_since "$mark" "control-centre: $target_panel panel opened" \
    "the glyph swaps the panel to $target_panel"
expect_quiet_since "$mark" 'drawers: controlcenter closed' \
    'and the drawer never left the screen'
expect_open controlcenter true 'the control centre is still open'
expect_drilled "$target_panel" 'showing the glyph’s panel'

nested_ipc call controlcenter toggle > /dev/null
sleep 0.4

# --- 5. from another drawer, one gesture -------------------------------------
#
# #187's row 2 with a destination: a door swaps in one gesture, and a glyph is a
# door that also names which room.

nested_ipc call launcher toggle > /dev/null
sleep 0.4
expect_open launcher true 'the launcher is open to swap away from'

mark=$(log_lines)
click "$target_x" "$mid_y"
expect_since "$mark" 'drawers: launcher → controlcenter' \
    'a status glyph swaps the launcher out in one gesture'
expect_drilled "$target_panel" 'and the control centre arrives drilled'
expect_open launcher false 'the launcher is not what is open afterwards'

# --- 6. a readout is still not a door ----------------------------------------
#
# The system monitor has no panel and must gain none: #184 makes four glyphs
# interactive and the rest have to stay exactly as they were — which on a bar
# with a drawer open means dismissing, because a readout claims no click and the
# bar behind it is dead space (#187's row 3).

mark=$(log_lines)
click "$monitor_x" "$mid_y"
expect_since "$mark" 'drawers: controlcenter closed \(bar\)' \
    'the system monitor dismisses rather than opening anything'
expect_drilled "" 'and nothing is drilled behind it'

mark=$(log_lines)
click "$monitor_x" "$mid_y"
expect_quiet_since "$mark" 'drawers: controlcenter opened' \
    'with nothing open, the system monitor opens nothing'
expect_open controlcenter false 'the control centre stayed closed'

# Dead bar with nothing open is the same non-event, and it is the control for
# the check above: if this one *did* something, check 6 proved nothing about the
# system monitor in particular.
mark=$(log_lines)
click "$dead_x" "$mid_y"
expect_quiet_since "$mark" 'drawers: controlcenter opened' \
    'and neither does empty bar space'

nested_down
exit $(( nested_fail_count > 0 ))
