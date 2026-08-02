#!/usr/bin/env bash
# Pop, replace and dismiss the OSD inside a nested Hyprland (#46).
#
#   tools/osd-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/osd-harness.sh --keep   # leave the nested session up to poke at
#
# This is the second seam (CLAUDE.md). Every *rule* the OSD has is a pure
# function in `tests/tst_osdpolicy.qml` — the arming rule, the glyph ladder, the
# anchor table. What only exists once a compositor does is here: a layer surface
# that maps on a change and unmaps itself again, a dismiss timer that really
# fires, an IPC door, and the suppression that has to survive another surface
# opening on top of it.
#
# What it asserts:
#
#   1. the shell comes up with the OSD armed, and *silent* — no channel pops
#      on the way in, which is the arming rule's whole point (a login that
#      greets you with three OSDs is what it exists to prevent)
#   2. `ipc call osd pop volume 45` shows it, with the value in the log line
#   3. it takes itself down again after the configured timeout, and says so
#   4. `ipc call osd hide` takes it down, and says the reason was ipc
#   5. a second pop while it is up replaces the reading in place rather than
#      showing a second pill
#   6. `popMuted` reads as Muted rather than as a level
#   7. an unknown channel is refused by name, and nothing is shown
#   8. `show` is not on the target's surface, because the CLI cannot call it
#      (#77)
#   9. the control centre suppresses a pop while it is open
#  10. the control centre opening *over* a pill takes the pill down
#  11. no binding loops while all of that happened
#
# What it deliberately does not do: drive the real path. The nested session
# shares the host's PipeWire and the host's backlight, so a check that turned
# the volume up to see the OSD would be one that turned the *caller's* volume
# up. Which changes pop and which arm is decided in `observe()` and checked at
# seam 1; this is the surface those verdicts drive.
#
# Two things no seam here can see, both recorded rather than claimed:
#   - "on the focused screen" needs two outputs (#98);
#   - "no idle wakeups" needs frame and wakeup counts over an idle window
#     (#95). Both are real-session work, and the ticket's PR says so.
#
# The shell under test runs against a scratch XDG_CONFIG_HOME: this seeds a
# short timeout so the dismiss check is a second rather than a wait, and a
# harness that edited the settings of the session running it is one nobody
# would run twice.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call osd "$@"; }

# The log is append-only and the pill is shown several times over, so "did this
# call do anything" is always a question about what arrived *after* it. Every
# check marks the log first and reads only the tail.
log_lines() { wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0; }

since() { tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" 2>/dev/null; }

## Wait for a line that arrived after `mark`, and report it as a check.
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

## Assert an IPC reply is exactly what was expected.
expect_reply() {
    local got="$1" want="$2" what="$3"
    if [[ "$got" == "$want" ]]; then
        nested_pass "$what"
    else
        nested_fail "$what — expected '$want', got '$got'"
    fi
}

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

# 400ms is above the schema's floor and short enough that the dismiss check is
# not a wait. `top` because the startup line names the position, which is the
# cheapest possible proof that the geometry key is read at all.
cat > "$SCRATCH/config/forest-shell/settings.json" <<'EOF'
{
  "controlCenter": { "osd": { "timeout": 400, "position": "top", "margin": 24 } }
}
EOF

nested_shell shell.qml 'osd armed' || exit 1

# --- 1. it comes up armed, and silent ----------------------------------------

if grep -qaE 'osd: osd armed \(ipc target: osd, top, 400ms\)' "$NESTED_SHELL_LOG"; then
    nested_pass 'the OSD reads its geometry and timeout from settings.json'
else
    nested_fail "the startup line does not name the configured position and timeout: \
$(grep -a 'osd armed' "$NESTED_SHELL_LOG" | head -1)"
fi

# The arming rule. Whichever of the three channels this machine has, their first
# readings arrive during startup — and none of them may show anything. An
# `armed` line is the evidence the watcher ran at all, so a machine with no
# audio and no backlight is reported rather than passing vacuously.
if grep -qaE 'osd: [a-z]+ [0-9]+% — showing' "$NESTED_SHELL_LOG"; then
    nested_fail "a channel popped during startup: \
$(grep -aE 'osd: .* — showing' "$NESTED_SHELL_LOG" | head -1)"
elif grep -qaE 'osd: [a-z]+ armed at [0-9]+% — not showing' "$NESTED_SHELL_LOG"; then
    nested_pass 'the first reading of each channel arms it rather than popping it'
else
    nested_note 'no channel armed — this machine exposed no sink, source or backlight'
    nested_pass 'nothing popped on the way up'
fi

# --- 2. the door shows it ----------------------------------------------------

mark=$(log_lines)
ipc pop volume 45 > /dev/null
expect_since "$mark" 'osd: volume 45% — showing \(Volume 45%\)' \
    'ipc call osd pop volume 45 shows the pill, with the value in the line'

expect_reply "$(ipc isShown)" 'true' 'the pill reports itself shown'
expect_reply "$(ipc channel)" 'volume' 'the pill reports which channel it is on'
expect_reply "$(ipc level)" '45' 'the pill reports the level it was given'

# --- 3. it takes itself down -------------------------------------------------

expect_since "$mark" 'osd: hidden \(timeout\)' \
    'the pill dismisses itself after the configured timeout'
expect_reply "$(ipc isShown)" 'false' 'it reports itself hidden afterwards'

# --- 4. and it can be taken down ---------------------------------------------

mark=$(log_lines)
ipc pop brightness 70 > /dev/null
ipc hide > /dev/null
expect_since "$mark" 'osd: hidden \(ipc\)' \
    'ipc call osd hide takes the pill down, and says who asked'

# --- 5. a second pop replaces the reading in place ---------------------------
#
# The window stays mapped and the value moves inside it — #27's "in-place value
# update" in lifecycle terms, and what a held volume key does ten times a
# second. What this seam can see of that is the absence of a hide between the
# two showings: a pill that unmapped and remapped would have logged one.

mark=$(log_lines)
ipc pop volume 20 > /dev/null
ipc pop volume 40 > /dev/null
expect_since "$mark" 'osd: volume 40% — showing' 'a second pop replaces the reading'

if since "$mark" | grep -qaE 'osd: hidden'; then
    nested_fail 'the pill was taken down between two pops rather than updated in place'
else
    nested_pass 'the pill was updated in place — no hide between the two pops'
fi
expect_reply "$(ipc level)" '40' 'the second value is the one on screen'

# --- 6. muted reads as muted -------------------------------------------------

mark=$(log_lines)
ipc popMuted mic 60 > /dev/null
expect_since "$mark" 'osd: mic 60% — showing \(Microphone Muted\)' \
    'a muted channel reads as Muted rather than as a level'
expect_reply "$(ipc readout)" 'Muted' 'the readout says Muted while the level is kept'
ipc hide > /dev/null

# --- 7. an unknown channel is refused ----------------------------------------

mark=$(log_lines)
ipc pop nonesuch 50 > /dev/null
expect_since "$mark" 'osd: no such channel: nonesuch' \
    'an unknown channel is refused by name'
expect_reply "$(ipc isShown)" 'false' 'and nothing is shown for it'

# --- 8. `show` is not on the surface -----------------------------------------
#
# The name is unusable from the CLI whatever it does in QML: `qs ipc call osd
# show` is parsed as the `ipc show` subcommand and prints the target listing,
# exit 0, without calling anything (#77).

if nested_ipc show | sed -n '/^target osd$/,/^target /p' | grep -qa 'function show('; then
    nested_fail 'the osd target advertises show(), which the CLI cannot call'
else
    nested_pass 'the osd target does not advertise an uncallable show()'
fi

# --- 9. the control centre suppresses a pop ----------------------------------
#
# The panel holds a live slider for all three channels (#44), so an OSD over it
# is the same number twice — one of them on top of the control being dragged.

mark=$(log_lines)
nested_ipc call controlcenter open > /dev/null
expect_since "$mark" 'drawers: controlcenter opened' 'the control centre opens'

mark=$(log_lines)
ipc pop volume 55 > /dev/null
expect_since "$mark" 'osd: suppressed while controlcenter is open' \
    'a pop under an open control centre is suppressed, and says why'
expect_reply "$(ipc isShown)" 'false' 'and nothing is shown'

nested_ipc call controlcenter close > /dev/null

# --- 10. and takes a pill that is already up down ----------------------------

mark=$(log_lines)
ipc pop volume 65 > /dev/null
expect_since "$mark" 'osd: volume 65% — showing' 'the pill is up again with the drawer closed'

mark=$(log_lines)
nested_ipc call controlcenter open > /dev/null
expect_since "$mark" 'osd: hidden \(suppressed\)' \
    'the control centre opening over a live pill takes the pill down'
nested_ipc call controlcenter close > /dev/null

# --- 11. nothing is fighting itself ------------------------------------------

if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops while the pill was going up and down'
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all OSD checks passed\n'
exit 0
