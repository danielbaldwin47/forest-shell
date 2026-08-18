#!/usr/bin/env bash
# Open, drive and close the calendar window inside a nested Hyprland.
#
#   tools/calendar-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/calendar-harness.sh --keep   # leave the nested session up to poke at
#
# The calendar's lifecycle, its IPC surface and its store all live on the far
# side of `tests/`: opening a window is a Wayland event, Escape is a compositor
# focus question, and `CalendarStore` imports Quickshell, so nothing below is
# reachable from the first seam. The arithmetic underneath it is
# (`tests/tst_calendartime.qml`, `tests/tst_eventpolicy.qml`) — what is left
# here is exactly the part a compositor has to be present for.
#
# What it asserts:
#
#   1. `ipc call calendar open` opens the window, on a known view and day
#   2. `isOpen` answers true while it is up and false once it is not
#   3. `close` closes it, and says why
#   4. `toggle` opens a closed window and closes an open one
#   5. `view day|week|month` switches, and an unknown view is refused out loud
#   6. `goto <day>` anchors on it, and a non-date is refused out loud
#   7. `today` anchors on the machine's own today
#   8. `create` makes an event, logs it, and it is in events.json afterwards
#   9. Escape inside the window closes it, from the keyboard
#  10. nothing in the window is fighting itself (no binding loops)
#  11. `nested_drag` — which landed with this file — puts the cursor where it
#      was aimed, so the instrument the pointer claims will need is exercised
#      before anything depends on it
#
# The shell under test runs against a scratch XDG_CONFIG_HOME *and*
# XDG_DATA_HOME, seeded from tools/fixtures/calendar-*.json. Both, because the
# calendar's two files live in two places on purpose — events are data the shell
# wrote, contacts are hand-editable config — and a harness that wrote events
# into the calendar of the session running it is one nobody will run twice.
#
# The fixture week is 2026-08-18's: eleven events including a three-way overlap
# on the Tuesday, an all-day Wednesday and a Thursday-to-Saturday span. Nothing
# below asserts on the *drawing* of any of that — this seam takes no
# screenshots, because the nested compositor never presents (see the header of
# tools/nested-session.sh). Pictures are tools/capture-harness.sh's job.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call calendar "$@"; }

# The log is append-only and the window is opened several times over, so "did
# this call do anything" is always a question about what arrived *after* it.
# Every check marks the log first and reads only the tail.
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

## Assert a line did *not* arrive. Only meaningful next to a positive check on
## the same call, or it passes for a shell that logged nothing at all.
refute_since() {
    local mark="$1" pattern="$2" what="$3"
    sleep 0.6
    if since "$mark" | grep -qaE "$pattern"; then
        nested_fail "$what — /$pattern/ arrived and should not have"
        return 1
    fi
    nested_pass "$what"
}

## Send a key until the window answers it, or give up.
##
## A newly mapped toplevel does not have the compositor's keyboard focus for the
## first moment of its life, and a key aimed at a window that does not have it
## is silently a no-op. Polling on the evidence is what keeps the check from
## being a sleep long enough to be slow and short enough to be flaky.
key_until() {
    local key="$1" mark="$2" pattern="$3" what="$4"
    for _ in $(seq 1 20); do
        nested_key "$key"
        for _ in $(seq 1 5); do
            if since "$mark" | grep -qaE "$pattern"; then
                nested_pass "$what"
                return 0
            fi
            sleep 0.1
        done
    done
    nested_fail "$what — $key produced nothing matching /$pattern/"
    return 1
}

nested_up || exit 1

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH="$NESTED_WORK/xdg"
EVENTS="$SCRATCH/data/forest-shell/calendar/events.json"
CONTACTS="$SCRATCH/config/forest-shell/contacts.json"

mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state" \
         "$SCRATCH/data/forest-shell/calendar"
cp "$REPO/tools/fixtures/calendar-events.json" "$EVENTS"
cp "$REPO/tools/fixtures/calendar-contacts.json" "$CONTACTS"

NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state"
            "XDG_DATA_HOME=$SCRATCH/data")

nested_shell shell.qml 'calendar window armed' || exit 1

# The fixtures have to be what the shell actually read, or every store check
# below is measuring an empty calendar that happens to behave.
if grep -qa 'calendar: no .* yet — seeding' "$NESTED_SHELL_LOG"; then
    nested_fail 'the shell seeded its own calendar — XDG_DATA_HOME did not reach it'
else
    nested_pass 'the shell read the seeded fixtures rather than seeding its own'
fi

# --- 1. the door -------------------------------------------------------------

mark=$(log_lines)
ipc open > /dev/null
expect_since "$mark" 'calendar: window opened \(view week, [0-9]{4}-[0-9]{2}-[0-9]{2}\)' \
    'ipc call calendar open opens the window, on a named view and day'

# --- 2. isOpen is a question, not a command ----------------------------------

reply=$(ipc isOpen)
if grep -qa 'true' <<< "$reply"; then
    nested_pass 'isOpen answers true while the window is up'
else
    nested_fail "isOpen did not answer true with the window open: $reply"
fi

# --- 3. `show` is not on the surface -----------------------------------------
#
# The name is unusable from the CLI whatever it does in QML: `qs ipc call
# calendar show` is parsed as the `ipc show` subcommand and prints the target
# listing, exit 0, without calling anything (#77). A `show` on the handler would
# put that name in front of everybody in exactly the listing they read it from.

if nested_ipc show | sed -n '/^target calendar$/,/^target /p' | grep -qa 'function show('; then
    nested_fail 'the calendar target advertises show(), which the CLI cannot call'
else
    nested_pass 'the calendar target does not advertise an uncallable show()'
fi

# --- 4. close over IPC -------------------------------------------------------

mark=$(log_lines)
ipc close > /dev/null
expect_since "$mark" 'calendar: window closed \(ipc\)' \
    'ipc call calendar close closes the window'

reply=$(ipc isOpen)
if grep -qa 'false' <<< "$reply"; then
    nested_pass 'isOpen answers false once it is closed'
else
    nested_fail "isOpen did not answer false with the window closed: $reply"
fi

# --- 5. toggle, both ways ----------------------------------------------------

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'calendar: window opened' 'toggle opens a closed window'

mark=$(log_lines)
ipc toggle > /dev/null
expect_since "$mark" 'calendar: window closed \(toggle\)' 'toggle closes an open one'

# --- 6. views ----------------------------------------------------------------
#
# Driven with the window shut on purpose: which view the calendar is on outlives
# the window, and a `view` that only worked while something was on screen would
# lose the user's place on every close.

for name in day month week; do
    mark=$(log_lines)
    ipc view "$name" > /dev/null
    expect_since "$mark" "calendar: view $name" "view $name switches to it"
done

mark=$(log_lines)
ipc view fortnight > /dev/null
expect_since "$mark" 'calendar: unknown view: fortnight' \
    'an unknown view is refused out loud rather than ignored'
refute_since "$mark" 'calendar: view fortnight' 'an unknown view does not switch to itself'

# The view survived being set while closed, which is the claim above.
mark=$(log_lines)
ipc open > /dev/null
expect_since "$mark" 'calendar: window opened \(view week,' \
    'the window opens on the view it was left on'

# --- 7. goto and today -------------------------------------------------------

mark=$(log_lines)
ipc goto 2026-08-18 > /dev/null
expect_since "$mark" 'calendar: goto 2026-08-18' 'goto anchors the view on a day'

mark=$(log_lines)
ipc goto 18-08-2026 > /dev/null
expect_since "$mark" 'calendar: not a date: 18-08-2026' \
    'a date in the wrong shape is refused out loud'
refute_since "$mark" 'calendar: goto 18-08-2026' 'a bad date does not move the view'

mark=$(log_lines)
ipc today > /dev/null
expect_since "$mark" "calendar: today $(date +%Y-%m-%d)" \
    "today anchors on the machine's own today"

# --- 8. create, and the file underneath it -----------------------------------
#
# The id is deterministic (`EventPolicy.nextId`) precisely so this check can
# name it: the fixture's highest is evt-11, so the next one is evt-12. That is
# also why the assertion is worth making twice — once on the log, which says the
# store acted, and once on the file, which says the act survived.

mark=$(log_lines)
made=$(ipc create 2026-08-18 555 60 'Design sync')
expect_since "$mark" 'calendar: create evt-12 2026-08-18T09:15 60m "Design sync"' \
    'create makes an event at the minute it was given'

if grep -qa 'evt-12' <<< "$made"; then
    nested_pass 'create answers with the id it made'
else
    nested_fail "create did not answer with an id: $made"
fi

mark=$(log_lines)
ipc create 2026-13-40 555 60 'Nowhere' > /dev/null
expect_since "$mark" 'calendar: cannot create an event on 2026-13-40' \
    'create refuses a day that does not exist'

# The write is debounced by 250 ms and flushed on destruction, so the file is
# only guaranteed once the shell has gone. Closing the window is not enough —
# the store outlives it.
mark=$(log_lines)
ipc guestAdd evt-12 mira > /dev/null
expect_since "$mark" 'calendar: guest add evt-12 mira' \
    'guestAdd invites someone to an event that exists'

mark=$(log_lines)
ipc guestAdd evt-12 mira > /dev/null
refute_since "$mark" 'calendar: guest add' 'inviting the same person twice logs nothing'

mark=$(log_lines)
ipc deleteEvent evt-1 > /dev/null
expect_since "$mark" 'calendar: delete evt-1' 'deleteEvent drops an event'

# --- 9. Escape ---------------------------------------------------------------

mark=$(log_lines)
ipc open > /dev/null
expect_since "$mark" 'calendar: window (opened|raised)' \
    'the window is open again for the key check'

mark=$(log_lines)
key_until escape "$mark" 'calendar: window closed \(escape\)' \
    'Escape closes the window from the keyboard'

# --- 10. nothing is fighting itself ------------------------------------------

if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops while the window was open'
fi

# --- 11. the file, after the shell has gone ----------------------------------
#
# Last, and every one of them waits rather than looks: the write is debounced by
# 250 ms and the timer restarts on every edit, so a check that read the file
# once would pass or fail depending on how fast the machine is. Waiting is also
# what makes the teardown below safe — see the note there.

## Wait until the file says what it is supposed to, then report it.
##
## Polling and not a sleep, for the usual reason — but also because the thing
## being waited on is a 250 ms debounce that restarts on every edit, so "how
## long" is not a constant a harness can know.
file_says() {
    local pattern="$1" what="$2"
    for _ in $(seq 1 50); do
        if grep -qa "$pattern" "$EVENTS" 2>/dev/null; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — /$pattern/ never appeared in $EVENTS"
    return 1
}

file_stops_saying() {
    local pattern="$1" what="$2"
    for _ in $(seq 1 50); do
        if ! grep -qa "$pattern" "$EVENTS" 2>/dev/null; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — /$pattern/ is still in $EVENTS"
    return 1
}

file_says '"id": "evt-12"' 'the created event reaches events.json'
file_says 'Design sync' 'the title it was given goes to the file too'
file_says '"mira"' 'the guest it was given goes to the file too'
file_stops_saying '"id": "evt-1",' 'the deleted event is gone from events.json'
file_says '"id": "evt-11"' 'the fixture events it never touched are still there'

# Only now is it safe to take the shell away. A SIGTERM does not run QML
# destruction — measured: killing the shell 200 ms after a delete left the file
# holding the event, with `Component.onDestruction: flush()` in place — so the
# waits above are the harness's own guarantee and the flush is a courtesy to a
# clean quit, not something to assert through.
nested_kill_shell

if grep -qa '"version": 1' "$EVENTS" 2>/dev/null; then
    nested_pass 'the file it wrote is stamped with its schema version'
else
    nested_fail 'the written events.json carries no version stamp'
fi

# --- the pointer instrument itself -------------------------------------------
#
# `nested_drag` landed with this file and the grid it is for did not, so without
# this it would ship unexercised — and an instrument nobody has run is a
# candidate cause for every failure of the first check that uses it. What is
# assertable now, with no calendar target and no shell at all, is the half that
# is arithmetic: the gesture's *landing point*. The tool maps each endpoint onto
# the output's extents as a fraction, so a drag that ends where it was aimed is
# a drag whose coordinate space agrees with the compositor's. It is also the
# only reading that separates the two spaces: `movecursor` puts the cursor on
# the start point regardless, so a tool that delivered nothing at all would
# still be sitting at (x1, y1) here.
#
# The points are quarters of the output rather than round numbers, because the
# output is not the size NESTED_MONITORS asks for: the nested backend's own
# window is tiled by the *host*, so a 1280x800 rule came up 618x652 here. Aiming
# at 760 on that output is a drag the compositor clamps to 617, which reads
# exactly like an instrument that lost the last third of its travel.
#
# Within a pixel or two, because a fraction of an integer extent rounds.
drag_extents=$(nested_output_logical "$(nested_outputs | head -n 1)")
drag_w="${drag_extents%x*}" drag_h="${drag_extents#*x}"
if [[ ! "$drag_w" =~ ^[0-9]+$ || ! "$drag_h" =~ ^[0-9]+$ ]]; then
    nested_fail "could not read the output's logical extents (got '$drag_extents')"
else
    drag_x1=$(( drag_w / 4 ))
    drag_y1=$(( drag_h / 4 ))
    drag_x2=$(( drag_w * 3 / 4 ))
    drag_y2=$(( drag_h * 3 / 4 ))
    if ! nested_drag "$drag_x1" "$drag_y1" "$drag_x2" "$drag_y2"; then
        nested_fail 'nested_drag could not run at all'
    else
        cursor=$(nested_hyprctl cursorpos 2>/dev/null | tr -d ' ')
        landed_x="${cursor%%,*}" landed_y="${cursor##*,}"
        if [[ "$landed_x" =~ ^-?[0-9]+$ && "$landed_y" =~ ^-?[0-9]+$ ]] &&
           (( landed_x >= drag_x2 - 2 && landed_x <= drag_x2 + 2 )) &&
           (( landed_y >= drag_y2 - 2 && landed_y <= drag_y2 + 2 )); then
            nested_pass 'nested_drag lands the cursor where it was aimed'
        else
            nested_fail "nested_drag aimed at $drag_x2,$drag_y2 on a ${drag_w}x${drag_h} output and landed at ${cursor:-nothing}"
        fi
    fi
fi

# --- TODO: the rest of the pointer half ---------------------------------------
#
# Everything above is driven over IPC, and IPC is deliberately not the seam the
# pointer claims live at — #187 is the whole argument: every IPC-driven check
# passed against a bar whose buttons could not be clicked, because the verb was
# never the broken part. The four claims below need the grid `nested_drag` drags
# on, which has not landed yet:
#
#   TODO (piece f, drag-create): drag on an empty column of the week grid and
#       assert `calendar: create evt-N <stamp> 60m` — the point being that the
#       *pointer* made it, not that `create` works, which check 8 already says.
#       Aim with `nested_window_rect 'forest-shell — calendar'`: the window is a
#       toplevel and is tiled to the output under a nested Hyprland, so its rect
#       is read and never assumed.
#
#   TODO (piece g, drag-move): press on a chip, drag it into the next column,
#       assert `calendar: move evt-N <from> -> <to>` and that the duration in
#       the file is unchanged — a move that silently resizes is the failure
#       `tests/tst_eventpolicy.qml` guards in the arithmetic and this would
#       guard in the delivery.
#
#   TODO (piece h, resize): press on a chip's bottom edge handle, drag up past
#       its own top, assert `calendar: resize evt-N 90m -> 15m` — the floor,
#       delivered.
#
#   TODO (piece i, guests): open an event, type into the guest picker, click a
#       result, assert `calendar: guest add evt-N <contact>`. The contacts
#       fixture is already seeded above for exactly this.
#
# Each of them is a `nested_drag`/`nested_click` plus one `expect_since`. None
# of them can be a screenshot: this seam never presents.

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all calendar checks passed\n'
exit 0
