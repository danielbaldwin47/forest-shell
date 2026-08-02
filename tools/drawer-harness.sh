#!/usr/bin/env bash
# Open, drive and dismiss the shared drawer window inside a nested Hyprland (#38).
#
#   tools/drawer-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/drawer-harness.sh --keep   # leave the nested session up to poke at
#
# The drawer is a lifecycle, which is the class of thing `tests/` cannot see at
# all: whether the window actually maps, whether the focus grab dismisses it,
# whether the state resets, whether the IPC door is callable at all. The
# decisions behind it — which drawer is open, which screen, what a hotplug does
# — are unit-checked in tests/tst_drawerpolicy.qml; this is the half that needs
# a compositor.
#
# What it asserts:
#
#   1. the drawer registers on the surface bus and on IPC as `session`
#   2. `ipc call session toggle` opens it, naming the screen
#   3. the fog is laid out *below* the bar, so the bar is above it
#   4. `ipc call session isOpen` agrees while it is open
#   5. a second toggle closes it, and says why
#   6. `ipc call session close` closes an open drawer, and says why
#   7. `show` is not on the target, because the CLI cannot call it (#77)
#   8. a toggle for a drawer nobody has built leaves the open one alone
#   9. the compositor took the fog's blur layerrule
#  10. reducedEffects still opens and closes the drawer — the ladder collapses
#      the motion, it does not remove the surface
#  11. nothing is fighting itself (no binding loops)
#
# The shell under test runs against a scratch XDG_CONFIG_HOME and
# XDG_STATE_HOME: check 10 rewrites `appearance.reducedEffects`, and a harness
# that edits the settings of the session running it is one nobody will run twice.
#
# **Escape is driven by hand, not here.** Hyprland's `sendshortcut` takes a
# *toplevel* — `, escape, activewindow`, and inside this session `hyprctl
# activewindow` answers `Invalid` because the shell is layer surfaces all the
# way down. There is no key-injection tool this repo may assume (no wtype, no
# ydotool), so the keyboard path is a `--keep` step:
#
#   tools/drawer-harness.sh --keep
#   qs-upstream -p shell.qml ipc call session open   # in the nested session
#   ...press Escape in it, and look for `drawers: session closed (escape)`
#
# tools/settings-harness.sh can press keys only because the settings window is
# an ordinary toplevel; tools/lock-harness.sh works around the same wall with a
# harness-only IPC that types for it, which tests the handler and not the key.
#
# What this seam also cannot answer, and #38's acceptance says so: whether the
# transitions hold 60 Hz. That is frame pacing — the nested session never
# presents (see the header of nested-session.sh) and a client-side grab never
# counts frames.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call session "$@"; }

# The log is append-only and the drawer is opened several times over, so "did
# this call do anything" is always a question about what arrived *after* it.
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
    nested_fail "$what — nothing matching /$pattern/ since the call"
    return 1
}

## Nothing matching arrived, and waiting longer would not change that. Used for
## the checks whose evidence is an absence.
expect_quiet_since() {
    local mark="$1" pattern="$2" what="$3"
    sleep 0.5
    if since "$mark" | grep -qaE "$pattern"; then
        nested_fail "$what — /$pattern/ arrived and should not have"
        return 1
    fi
    nested_pass "$what"
}

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
SETTINGS_FILE="$SCRATCH/config/forest-shell/settings.json"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

nested_shell shell.qml 'drawers armed' || exit 1

echo

# --- 1. the doors are open ---------------------------------------------------
#
# Two of them, and they are announced together on purpose: the surface bus
# registration is what makes a bar button reach this, and the IPC target is what
# makes a keybind reach it. A drawer that registers neither is #81 — a surface
# that does nothing, quietly.

if grep -qa 'surfaces: session registered (qs ipc call session toggle)' "$NESTED_SHELL_LOG"; then
    nested_pass 'the session drawer registered on the surface bus'
else
    nested_fail 'the session drawer never registered on the surface bus'
fi

if nested_ipc show | grep -qa '^target session$'; then
    nested_pass 'the session drawer owns the `session` ipc target'
else
    nested_fail 'there is no `session` ipc target'
fi

# The launcher's door is named by the shell-switch contract (#7) rather than
# chosen here: lowercase `launcher`, verb `toggle`. A rename is a broken
# integration in somebody else's repo, so it is asserted literally.

if grep -qa 'surfaces: launcher registered (qs ipc call launcher toggle)' "$NESTED_SHELL_LOG"; then
    nested_pass 'the launcher registered on the surface bus'
else
    nested_fail 'the launcher never registered on the surface bus'
fi

if nested_ipc show | grep -qa '^target launcher$'; then
    nested_pass 'the launcher owns the `launcher` ipc target'
else
    nested_fail 'there is no `launcher` ipc target'
fi

if nested_ipc show | sed -n '/^target launcher$/,/^target /p' | grep -qa 'function show('; then
    nested_fail 'the launcher target advertises show(), which the CLI cannot call'
else
    nested_pass 'the launcher target does not advertise an uncallable show()'
fi

# Super+Space (#39). The shell registers the shortcut over
# hyprland-global-shortcuts-v1 rather than shelling out per keypress, so the
# evidence is the compositor's own list — the binding in hyprland.conf is the
# user's half and is not something this seam can write for them.

if nested_hyprctl globalshortcuts | grep -qa 'forest-shell:launcher'; then
    nested_pass 'the compositor has the launcher global shortcut'
else
    nested_fail 'hyprland was never offered a launcher global shortcut'
fi

# --- 2. it opens, on a named screen ------------------------------------------

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'drawers: session opened on ' 'ipc call session toggle opens the drawer'

# --- 3. the fog is laid out below the bar ------------------------------------
#
# #38's "the bar renders above the fog and stays clickable", measured rather
# than asserted. The drawer window reserves nothing and respects what does
# (`ExclusionMode.Normal`, zero zone), so the compositor lays it out *under* the
# bar's exclusive strip — the fog never covers the bar and stacking order within
# `WlrLayer.Top` never has to be argued with. `hyprctl layers` reports the
# geometry the compositor actually gave each surface, which is the evidence.
#
# Clickability has a second half — a focus grab eats clicks outside the windows
# it names — and that is Core/FocusGrabWindows.qml, which this seam cannot see.

layers=$(nested_hyprctl layers)
bar_height=$(sed -n 's/.*xywh: [0-9-]* [0-9-]* [0-9-]* \([0-9]*\),.*forest-shell:bar.*/\1/p' <<< "$layers" | head -1)
fog_top=$(sed -n 's/.*xywh: [0-9-]* \([0-9-]*\) [0-9-]* [0-9]*,.*forest-shell:drawers.*/\1/p' <<< "$layers" | head -1)

if [[ -z "$fog_top" ]]; then
    nested_fail 'the drawer window never mapped a layer surface'
elif [[ -z "$bar_height" ]]; then
    nested_fail 'the bar has no layer surface to be above'
elif [[ "$fog_top" == "$bar_height" ]]; then
    nested_pass "the fog starts below the bar (bar ${bar_height}px, fog top ${fog_top}px)"
else
    nested_fail "the fog starts at ${fog_top}px under a ${bar_height}px bar — it is covering it"
fi

# --- 4. ...and says so ---------------------------------------------------------

reply=$(ipc isOpen)
if grep -qa 'true' <<< "$reply"; then
    nested_pass 'isOpen agrees while the drawer is open'
else
    nested_fail "isOpen said \"$reply\" with the drawer open"
fi

# --- 5. a second toggle closes it, and the reason travels --------------------
#
# A drawer that was dismissed and one that was toggled shut look identical
# afterwards. The reason in the line is what tells them apart, here and in a bug
# report.

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'drawers: session closed \(toggle\)' 'a second toggle closes it, saying toggle'

reply=$(ipc isOpen)
if grep -qa 'false' <<< "$reply"; then
    nested_pass 'isOpen agrees once it is closed'
else
    nested_fail "isOpen said \"$reply\" with the drawer closed"
fi

# --- 6. the explicit close ---------------------------------------------------

ipc open > /dev/null
mark=$(log_lines)
ipc close > /dev/null
expect_since "$mark" 'drawers: session closed \(ipc\)' 'ipc call session close closes it, saying ipc'

# --- 7. `show` is not on the surface -----------------------------------------
#
# `qs ipc call session show` is parsed as the `ipc show` subcommand and prints
# the target listing, exit 0, without calling anything (#77). A `show` on the
# handler would put that name in front of everybody in the listing they read it
# from.

if nested_ipc show | sed -n '/^target session$/,/^target /p' | grep -qa 'function show('; then
    nested_fail 'the session target advertises show(), which the CLI cannot call'
else
    nested_pass 'the session target does not advertise an uncallable show()'
fi

# --- 8. a drawer nobody built leaves the open one alone ----------------------
#
# The control centre is declared on the bus and unbuilt (#44). Pressing that
# button has to be a logged no-op — what must not happen is the open drawer
# closing because someone reached for a surface that is not there.
#
# This was `launcher` until #39 landed and made it a real drawer, which is the
# hazard the check has to be written against: the unbuilt name has to be one
# that is still unbuilt, or the assertion quietly becomes "a toggle for a
# drawer that exists does nothing", which is the opposite claim and passes for
# the wrong reason.

ipc open > /dev/null
mark=$(log_lines)
nested_ipc call controlcenter toggle > /dev/null 2>&1
expect_quiet_since "$mark" 'drawers: session closed' \
    'a toggle for an unbuilt drawer leaves the open one alone'
ipc close > /dev/null

# --- 8b. the launcher is a drawer, and swapping does not close the fog -------
#
# #39's tenant, checked here rather than in tools/launcher-harness.sh because
# what is being asserted is the *window's* behaviour: one drawer replacing
# another is a transition inside one surface, and the evidence that it was not
# two windows fighting is that no `closed` line appears between them.

ipc open > /dev/null
mark=$(log_lines)
nested_ipc call launcher toggle > /dev/null
expect_since "$mark" 'drawers: session → launcher' \
    'the launcher swaps with the session menu rather than stacking'
expect_quiet_since "$mark" 'drawers: session closed' \
    'the swap does not take the fog down on its way'

mark=$(log_lines)
nested_ipc call launcher toggle > /dev/null
expect_since "$mark" 'drawers: launcher closed \(toggle\)' 'the launcher toggles shut'

# --- 8c. the notification centre is the third tenant -------------------------
#
# #43. The door is `notificationcenter` and not `notifications`, and that is the
# part worth asserting literally: the notification *service* already owns the
# `notifications` IPC target for DND, and two IpcHandlers on one name is one of
# them silently not answering. A rename here is a keybind that stops working.

if grep -qa 'surfaces: notificationcenter registered (qs ipc call notificationcenter toggle)' \
        "$NESTED_SHELL_LOG"; then
    nested_pass 'the notification centre registered on the surface bus'
else
    nested_fail 'the notification centre never registered on the surface bus'
fi

if nested_ipc show | grep -qa '^target notificationcenter$'; then
    nested_pass 'the notification centre owns the `notificationcenter` ipc target'
else
    nested_fail 'there is no `notificationcenter` ipc target'
fi

# Both targets exist, separately — the evidence that the two names did not
# collide into one handler.
if nested_ipc show | grep -qa '^target notifications$'; then
    nested_pass 'the notification service still owns its own `notifications` target'
else
    nested_fail 'the `notifications` ipc target went away when the centre took a name'
fi

mark=$(log_lines)
nested_ipc call notificationcenter toggle > /dev/null
expect_since "$mark" 'drawers: notificationcenter opened on ' \
    'ipc call notificationcenter toggle opens the centre'

reply=$(nested_ipc call notificationcenter isOpen)
if grep -qa 'true' <<< "$reply"; then
    nested_pass 'the centre agrees it is open'
else
    nested_fail "notificationcenter isOpen said \"$reply\" with the centre open"
fi

# Opening the centre is what "read" means in this shell (#43): the surface sets
# `centerOpen`, the service stamps `seenAt` and the bar's count empties. The
# stamp is the log line; the count is asked for over IPC below.
expect_since "$mark" 'notifications: seen \(unread ' \
    'opening the centre marks history seen'

mark=$(log_lines)
nested_ipc call notificationcenter toggle > /dev/null
expect_since "$mark" 'drawers: notificationcenter closed \(toggle\)' 'the centre toggles shut'

if nested_ipc show | sed -n '/^target notificationcenter$/,/^target /p' \
        | grep -qa 'function show('; then
    nested_fail 'the notificationcenter target advertises show(), which the CLI cannot call'
else
    nested_pass 'the notificationcenter target does not advertise an uncallable show()'
fi

# --- 9. the fog asked the compositor for its blur ----------------------------
#
# The 10% wash does nothing on its own — what makes it fog is the compositor
# blurring what is behind it. #78: hyprctl exits 0 when it *refuses* a rule, so
# the reply text is the only evidence there is, and the shell logs the two cases
# differently for exactly that reason.

if grep -qa 'layerrule blur 1 → forest-shell:drawers' "$NESTED_SHELL_LOG"; then
    nested_pass 'hyprland took the fog blur layerrule'
elif grep -qa 'refused layerrule .* forest-shell:drawers' "$NESTED_SHELL_LOG"; then
    nested_fail "hyprland refused the fog blur: $(grep -a 'refused layerrule' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_fail 'the fog blur layerrule was never pushed'
fi

# --- 10. reduced effects still has a drawer -----------------------------------
#
# #22 §7 asks for "a fully supported look, not a broken mode". Rung 3 collapses
# every transition to a 140 ms fade; what it must not do is leave the surface
# unopenable. The durations themselves are unit-checked
# (tests/tst_effectspolicy.qml) — what is checked here is that the lifecycle
# still runs with the knob on.

reduced_mark=$(log_lines)
printf '{ "appearance": { "reducedEffects": true } }\n' > "$SETTINGS_FILE"
expect_since "$reduced_mark" 'config: reloaded ' 'the knob reaches the running shell'

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'drawers: session opened on ' 'the drawer still opens with reducedEffects on'

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'drawers: session closed \(toggle\)' 'the drawer still closes with reducedEffects on'

# Rung 1 of the ladder, and the one rung with a subprocess in it — so this is a
# wait rather than a look: `hyprctl` is a `Process` the shell queues, and the
# reply lands some frames after the key that asked for it.
expect_since "$reduced_mark" 'layerrule blur 0 → forest-shell:drawers' \
    'reducedEffects took the fog blur away (rung 1)'

# --- 11. nothing is fighting itself ------------------------------------------
#
# A binding loop is a warning, not a failure, so it would otherwise pass
# unnoticed until the drawer visibly flickered. The window's `visible` is bound
# to an animated opacity and its slot list is rewritten from a signal on it,
# which is exactly the shape one comes from.

if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops while the drawer was open'
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all drawer checks passed\n'
exit 0
