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
#  12. a real drag on an empty column creates the event it drew, and opens the
#      quick-create panel on it; Escape dismisses the panel without closing the
#      window
#  13. a real drag on a chip's bottom edge resizes it; one on its body moves it
#      into the next day, keeping the minute — and both survive into events.json
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
# name it: the next id is one past the fixture's highest. That is also why the
# assertion is worth making twice — once on the log, which says the store acted,
# and once on the file, which says the act survived.
#
# **The number is read off the fixture, not written down here.** It was written
# down once (`evt-12`, when the fixture held eleven events) and the fixture grew
# to thirty-seven a commit later; the check then failed for a reason that had
# nothing to do with the calendar, and the *file* half of it went on passing
# because `evt-12` was by then a fixture event. A harness that hard-codes a
# number its own input decides is a harness that goes red on somebody else's
# commit.
NEXT_ID="evt-$(python3 -c '
import json, re, sys
events = json.load(open(sys.argv[1]))
events = events["events"] if isinstance(events, dict) else events
highest = 0
for event in events:
    match = re.fullmatch(r"evt-(\d+)", str(event.get("id", "")))
    if match:
        highest = max(highest, int(match.group(1)))
print(highest + 1)
' "$EVENTS")"

mark=$(log_lines)
made=$(ipc create 2026-08-18 555 60 'Design sync')
expect_since "$mark" "calendar: create $NEXT_ID 2026-08-18T09:15 60m \"Design sync\"" \
    'create makes an event at the minute it was given'

if grep -qa "$NEXT_ID" <<< "$made"; then
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
ipc guestAdd "$NEXT_ID" mira > /dev/null
expect_since "$mark" "calendar: guest add $NEXT_ID mira" \
    'guestAdd invites someone to an event that exists'

# Twice is not twice. The store says so out loud rather than going quiet: a
# silent second call is indistinguishable from a call that never arrived, and
# the `(already)` suffix is what lets this check assert the party did not grow
# *and* that the verb was heard.
mark=$(log_lines)
ipc guestAdd "$NEXT_ID" mira > /dev/null
expect_since "$mark" "calendar: guest add $NEXT_ID mira \\(already\\)" \
    'inviting the same person twice says so and adds nobody'
refute_since "$mark" "calendar: guest add $NEXT_ID mira$" \
    'and does not log a second plain add'

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

# --- 10b. the pointer, on the grid itself ------------------------------------
#
# Everything above this line is driven over IPC, and IPC is deliberately not the
# seam a pointer claim lives at — #187 is the whole argument: every IPC-driven
# check passed against a bar whose buttons could not be clicked, because the
# verb was never the broken part. So the three gestures the week grid exists for
# are driven with `nested_drag`, through the compositor, onto the real surface.
#
# **Nothing here is aimed at a guessed pixel.** A `FloatingWindow` under a
# nested Hyprland is tiled to the output, so its rect is read
# (`nested_window_rect`), and the grid's own geometry — where the scrolling area
# starts, how far it is scrolled, which column is which day and how wide it is —
# is read off the line `WeekView` prints for exactly this purpose. Between them
# every coordinate below is arithmetic, and a layout change moves the aim rather
# than breaking it.
#
# The order is create, resize, move, which is not the order they were written
# in. A chip moved into Thursday lands in the fixture's busiest column, packed
# beside a three-day span, so its width and its bottom edge are no longer where
# this could aim; resizing first is done while the new chip still owns a whole
# empty Wednesday column.

## The last geometry line the grid printed, or nothing.
grid_geometry() {
    local line
    for _ in $(seq 1 60); do
        line=$(grep -a 'calendar: geometry ' "$NESTED_SHELL_LOG" | tail -n 1)
        if [[ -n "$line" ]]; then
            printf '%s\n' "$line"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

## One `key=value` off that line.
geom_field() {
    sed -n "s/.* $2=\([^ ]*\).*/\1/p" <<< "$1"
}

mark=$(log_lines)
ipc open > /dev/null
ipc view week > /dev/null
ipc goto 2026-08-18 > /dev/null
expect_since "$mark" 'calendar: window (opened|raised)' \
    'the window is open again for the pointer checks'

geometry=$(grid_geometry)
win_rect=$(nested_window_rect 'forest-shell — calendar')
read -r win_x win_y _win_w _win_h <<< "${win_rect:-}"

if [[ -z "$geometry" ]]; then
    nested_fail 'the week grid never printed its geometry — nothing to aim at'
elif [[ -z "${win_x:-}" ]]; then
    nested_fail 'no toplevel titled "forest-shell — calendar" in hyprctl clients'
else
    nested_pass 'the grid printed its geometry and the window rect could be read'

    hour_h=$(geom_field "$geometry" hourHeight)
    grid_top=$(geom_field "$geometry" gridTop)
    view_h=$(geom_field "$geometry" viewH)
    content_y=$(geom_field "$geometry" contentY)
    cols=$(geom_field "$geometry" cols)

    ## The centre x of the column for a day, in compositor-global coordinates.
    column_x() {
        local iso="$1" field
        for field in ${cols//,/ }; do
            if [[ "${field%%:*}" == "$iso" ]]; then
                local rest="${field#*:}"
                echo $(( win_x + ${rest%%:*} + ${rest##*:} / 2 ))
                return 0
            fi
        done
        return 1
    }

    ## The y of a minute-after-midnight, same space. The grid scrolls, so
    ## `contentY` is part of the sum and not a constant.
    minute_y() {
        echo $(( win_y + grid_top + ($1 * hour_h) / 60 - content_y ))
    }

    wed_x=$(column_x 2026-08-19) || wed_x=""
    thu_x=$(column_x 2026-08-20) || thu_x=""
    y_0900=$(minute_y 540)
    y_1030=$(minute_y 630)
    y_1100=$(minute_y 660)
    top_limit=$(( win_y + grid_top ))
    bottom_limit=$(( win_y + grid_top + view_h ))

    if [[ -z "$wed_x" || -z "$thu_x" ]]; then
        nested_fail "the week on screen has no 2026-08-19/20 column: $cols"
    elif (( y_0900 < top_limit || y_1100 > bottom_limit )); then
        # Said out loud rather than aimed anyway: a press outside the viewport
        # lands on the toolbar or on nothing, and "the drag did not create an
        # event" would be the diagnosis for a window that is simply too short.
        nested_fail "09:00–11:00 is not inside the viewport ($geometry) — nothing to aim at"
    else
        nested_pass "the aim is inside the viewport (Wed x=$wed_x, 09:00 y=$y_0900)"

        # --- drag-create ----------------------------------------------------
        drag_id="evt-$(( ${NEXT_ID#evt-} + 1 ))"

        mark=$(log_lines)
        nested_drag "$wed_x" "$y_0900" "$wed_x" "$y_1030"
        expect_since "$mark" 'calendar: drag begin create 2026-08-19T09:00' \
            'a press on empty grid begins a create drag at the minute it landed on'
        expect_since "$mark" \
            "calendar: create $drag_id 2026-08-19T09:00 90m \"New event\"" \
            'letting go writes the event the drag drew, snapped to the quarter hour'
        expect_since "$mark" "calendar: quick-create open $drag_id" \
            'and the quick-create panel opens on the chip it just made'

        # Escape keeps the event under its default title — see the header of
        # Surfaces/Calendar/QuickCreatePopover.qml for why that, and not a
        # discard. It must also *not* reach the window, which is what the
        # refutation next to it is for.
        mark=$(log_lines)
        key_until escape "$mark" 'calendar: quick-create dismissed \(escape\)' \
            'Escape dismisses the quick-create panel'
        refute_since "$mark" 'calendar: window closed' \
            'and the panel ate the key rather than closing the whole calendar'

        # --- resize ----------------------------------------------------------
        #
        # 3px above the chip's own bottom edge, which is inside the 6px strip
        # `DragPolicy.edgeDepth` gives a chip this tall.
        mark=$(log_lines)
        nested_drag "$wed_x" "$(( y_1030 - 3 ))" "$wed_x" "$y_1100"
        expect_since "$mark" "calendar: drag begin resizeBottom $drag_id" \
            'a press on the bottom edge begins a resize and not a move'
        expect_since "$mark" "calendar: resize $drag_id 90m -> 120m" \
            'dragging the bottom edge down half an hour lengthens the event by it'

        # --- move -------------------------------------------------------------
        #
        # Aimed at 09:45, which is the chip's body: clear of the 6px strip at
        # 09:00 and of the one at 11:00, so this is the gesture the edge check
        # above is not.
        mark=$(log_lines)
        y_0945=$(minute_y 585)
        nested_drag "$wed_x" "$y_0945" "$thu_x" "$y_0945"
        expect_since "$mark" "calendar: drag begin move $drag_id" \
            'a press on a chip body begins a move'
        expect_since "$mark" \
            "calendar: move $drag_id 2026-08-19T09:00 -> 2026-08-20T09:00" \
            'dragging it one column right moves the day and keeps the minute'
    fi
fi

# --- 10c. the keyboard, key by key -------------------------------------------
#
# Every binding in `Surfaces/Calendar/KeyNavPolicy.qml`, delivered as a real key
# through the compositor rather than called as a function. The table itself is
# checked at the first seam — `tests/tst_keynavpolicy.qml` holds the whole keymap
# to account offscreen — so what is left for this seam is the half a unit test
# cannot see: that the window has the keyboard at all, that the key reaches the
# focus chain the surface actually builds, and that the one handler at the root
# of it dispatches what the policy decided.
#
# That gap is not theoretical. A keymap can be perfect and unreachable: #187 was
# a surface every IPC-driven check passed against and no pointer could touch,
# and a focus scope that swallows keys fails exactly the same way — silently,
# with the policy still green.
#
# Two things about the delivery. `nested_key` sends a bare key, so `Ctrl+K` and
# `?` need `sendshortcut`'s modifier field, which `key_mod_until` below supplies;
# and `?` is sent both ways it can arrive, because X11 and Wayland layouts
# disagree about whether Shift+/ is `question` or `slash` with Shift held, and
# `KeyNavPolicy` accepts both precisely because neither is safe to assume. A
# harness that picked one would be testing this machine's layout.

## Send each `MOD:key` spelling in turn until one of them lands.
##
## Doubles as the focus wait `key_until` is, for the same reason: a newly raised
## toplevel does not have the keyboard for the first moment of its life.
key_mod_until() {
    local mark="$1" pattern="$2" what="$3"
    shift 3
    local spec
    for _ in $(seq 1 8); do
        for spec in "$@"; do
            nested_hyprctl dispatch sendshortcut \
                "${spec%%:*}, ${spec#*:}, activewindow" > /dev/null
            for _ in $(seq 1 5); do
                if since "$mark" | grep -qaE "$pattern"; then
                    nested_pass "$what"
                    return 0
                fi
                sleep 0.1
            done
        done
    done
    nested_fail "$what — none of $* produced anything matching /$pattern/"
    return 1
}

mark=$(log_lines)
ipc open > /dev/null
ipc view week > /dev/null
ipc goto 2026-08-18 > /dev/null
expect_since "$mark" 'calendar: window (opened|raised)' \
    'the window is open again for the key checks'

# The first key is also the focus wait, which is why it is the only one here
# sent with `key_until`: once one key has been answered the window has the
# keyboard, and every check after it can be a single press.
mark=$(log_lines)
key_until d "$mark" 'calendar: view day' 'D switches to the day view'

mark=$(log_lines)
nested_key m
expect_since "$mark" 'calendar: view month' 'M switches to the month view'

mark=$(log_lines)
nested_key w
expect_since "$mark" 'calendar: view week' 'W switches back to the week view'

# Stepping. The expected day is arithmetic, not a wildcard: a `goto` that fired
# with the wrong argument is the failure worth catching, and `goto .*` would
# pass for every one of them.
mark=$(log_lines)
nested_key j
expect_since "$mark" 'calendar: goto 2026-08-11' 'J steps back one whole week'

mark=$(log_lines)
nested_key k
expect_since "$mark" 'calendar: goto 2026-08-18' 'K steps forward one whole week'

mark=$(log_lines)
nested_key left
expect_since "$mark" 'calendar: goto 2026-08-11' 'Left is J by another name'

mark=$(log_lines)
nested_key right
expect_since "$mark" 'calendar: goto 2026-08-18' 'Right is K by another name'

mark=$(log_lines)
nested_key t
expect_since "$mark" "calendar: today $(date +%Y-%m-%d)" \
    "T anchors on the machine's own today"

# `C` on a day that is *not* today, on purpose: `CreatePolicy` puts a new event
# at the next quarter-hour when the anchor is today and at 09:00 when it is not,
# so anchoring anywhere else makes the minute arithmetic instead of a clock — and
# a check whose expected value depends on when it ran is a check that will be
# deleted the first time it flakes.
mark=$(log_lines)
ipc goto 2027-03-15 > /dev/null
expect_since "$mark" 'calendar: goto 2027-03-15' \
    'the anchor is parked on a day that cannot be today'

mark=$(log_lines)
nested_key c
expect_since "$mark" 'calendar: create evt-[0-9]+ 2027-03-15T09:00 60m' \
    'C creates an hour at 09:00, the slot CreatePolicy picks'

# Selection needs something to select, so back to the fixture's busiest week.
mark=$(log_lines)
ipc goto 2026-08-18 > /dev/null
expect_since "$mark" 'calendar: goto 2026-08-18' 'back on the fixture week'

mark=$(log_lines)
nested_key down
expect_since "$mark" 'calendar: select evt-[0-9]+' \
    'Down selects an event of the visible week'

mark=$(log_lines)
nested_key up
expect_since "$mark" 'calendar: select evt-[0-9]+' 'Up selects one too'

mark=$(log_lines)
nested_key return
expect_since "$mark" 'calendar: open evt-[0-9]+' 'Enter opens what is selected'

# --- the command menu ---------------------------------------------------------

mark=$(log_lines)
key_mod_until "$mark" 'calendar: command menu open' \
    'Ctrl+K opens the command menu' 'CTRL:k'

mark=$(log_lines)
nested_key escape
expect_since "$mark" 'calendar: command menu closed' 'Escape closes the menu'
refute_since "$mark" 'calendar: window closed' \
    'and closes only the menu — the window under it stays up'

mark=$(log_lines)
key_mod_until "$mark" 'calendar: command menu open' \
    'Ctrl+K opens it again' 'CTRL:k'

# Typed into the field, not dispatched as shortcuts: with the caret in the menu
# `KeyNavPolicy` drops every bare letter, which is the rule that stops `m` from
# flipping the calendar to the month view behind the menu. That it flips it here
# is the *filter* answering — `mon` narrows the list to one row and Enter runs
# it — which is a different claim, and the only one that proves both halves.
mark=$(log_lines)
for letter in m o n; do
    nested_key "$letter"
    sleep 0.15
done
nested_key return
expect_since "$mark" 'calendar: view month' \
    'typing "mon" and pressing Enter runs the Month view command'
expect_since "$mark" 'calendar: command menu closed' 'and the menu closes behind it'

# --- the shortcuts sheet ------------------------------------------------------

mark=$(log_lines)
key_mod_until "$mark" 'calendar: shortcuts open' \
    '? opens the shortcuts sheet' ':question' 'SHIFT:slash'

mark=$(log_lines)
nested_key escape
expect_since "$mark" 'calendar: shortcuts closed' 'Escape closes the sheet'
refute_since "$mark" 'calendar: window closed' 'and leaves the window standing'

# One Escape per layer, which is the whole of the rule: with no overlay left the
# next one reaches the window.
mark=$(log_lines)
key_until escape "$mark" 'calendar: window closed \(escape\)' \
    'a second Escape, with nothing over the grid, closes the window'

# --- 10c. the guest picker ----------------------------------------------------
#
# The one claim here that no other seam can make: that a *keystroke* reaches the
# picker's field, that the field searches, and that Enter turns the highlighted
# row into a guest on the event. The ranking itself is arithmetic and is tested
# at the first seam (`tests/tst_guestpolicy.qml`); the picture is seam 3's
# (`--cal-state guests`). What is left is the wiring between a key and a store.
#
# `evt-11` and not one of the busy Tuesday's events, for one reason: it has no
# guests. The picker excludes people who are already invited, so an event that
# already had Mira on it would answer the query below with one row fewer and the
# count in the log line would be measuring the fixture rather than the search.
#
# The window was closed by the Escape check above, so `openEvent` reopens it —
# which is a claim worth having anyway: the panel is owned by the singleton and
# not by the view, so naming an event is enough to get a window *and* a panel.
mark=$(log_lines)
ipc open > /dev/null
expect_since "$mark" 'calendar: window opened' 'the window comes back for the picker'

# The keyboard is warmed up *before* the panel exists, not after. A newly mapped
# toplevel does not hold the compositor's keyboard focus for the first moment of
# its life, and the one key this section cannot poll on is Tab — it moves a
# caret and logs nothing, so a Tab that arrived early is indistinguishable from
# one that never arrived. `Ctrl+K` is the same keyboard and does log, so it is
# what establishes that keys are landing; the panel is opened afterwards and
# takes the caret itself.
mark=$(log_lines)
key_mod_until "$mark" 'calendar: command menu open' \
    'the reopened window is taking keys at all' 'CTRL:k'
mark=$(log_lines)
nested_key escape
expect_since "$mark" 'calendar: command menu closed' 'and the menu goes away again'

mark=$(log_lines)
ipc goto 2026-08-23 > /dev/null
ipc openEvent evt-11 > /dev/null
expect_since "$mark" 'calendar: open evt-11' 'openEvent selects and opens the event'
expect_since "$mark" 'calendar: editor open evt-11' 'and the editor panel comes up on it'

# Tab and not a letter. The editor spells its focus order out
# (`KeyNavigation.tab: guestPicker.fieldItem`) precisely so that "focus the
# guests field" is one key with one answer rather than whatever the scene
# graph's own traversal happens to be — and so this harness does not need a
# shortcut invented for it. A bare `g` was the alternative and was rejected:
# with a caret in the title field it is a letter, not a command.
#
# "mi" finds two people and *ranks* them: Mira by the front of her name, Amina
# by the middle of hers. Two results is the whole point of the query — one would
# not tell a search apart from a list that ignores what is typed into it.
#
# Typed inside a retry loop, and the retry starts by rebuilding the panel rather
# than by clearing the field. The first keystroke after a focus change is the
# one the compositor drops (measured here: `m` went missing and the field
# searched for `i`), and a half-typed query cannot be corrected blind — a second
# `m` on a field holding `i` is `im`, not `mi`. `goto` closes the panel and
# `openEvent` opens a fresh one, so every attempt starts from an empty field and
# the assertion below is on the query, not on the typing.
guest_search='calendar: guest search "mi" 2 results'
guest_typed=1
for _ in $(seq 1 6); do
    mark=$(log_lines)
    ipc goto 2026-08-23 > /dev/null
    ipc openEvent evt-11 > /dev/null
    sleep 0.4
    nested_key tab
    sleep 0.3
    for letter in m i; do
        nested_key "$letter"
        sleep 0.25
    done
    sleep 0.3
    if since "$mark" | grep -qaE "$guest_search"; then
        guest_typed=0
        break
    fi
done
if (( guest_typed == 0 )); then
    nested_pass 'typing in the guests field searches the contacts as it goes'
else
    nested_fail "typing in the guests field never logged /$guest_search/"
fi

mark=$(log_lines)
nested_key return
expect_since "$mark" 'calendar: guest add evt-11 mira' \
    'Enter invites the highlighted row — the prefix match, not the substring one'

# And the same person again, over IPC this time, which is the path the picker
# itself cannot take (it hides everybody already invited). One line, no second
# guest.
mark=$(log_lines)
ipc guestAdd evt-11 mira > /dev/null
expect_since "$mark" 'calendar: guest add evt-11 mira \(already\)' \
    'a duplicate arriving over IPC is refused out loud'

# The store said it happened; this says a later run would read it back. Polled,
# because the write is debounced by 250 ms and restarts on every edit — the same
# argument section 11 makes below, made here because the shell is still up.
guest_landed=1
for _ in $(seq 1 50); do
    if python3 - "$EVENTS" <<'PYEOF'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
event = next((e for e in data.get("events", []) if e.get("id") == "evt-11"), None)
sys.exit(0 if event and "mira" in event.get("guests", []) else 1)
PYEOF
    then
        guest_landed=0
        break
    fi
    sleep 0.1
done
if (( guest_landed == 0 )); then
    nested_pass 'the guest the keyboard added reaches events.json'
else
    nested_fail "evt-11 in $EVENTS never gained the guest the picker added"
fi

# Put the panel away, so the window is back to a bare grid for the checks that
# follow — an editor left open would hold the caret and eat the next Escape.
mark=$(log_lines)
nested_key escape
expect_since "$mark" 'calendar: editor closed' 'Escape closes the panel'
refute_since "$mark" 'calendar: window closed' 'and leaves the window under it standing'

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

file_says "\"id\": \"$NEXT_ID\"" 'the created event reaches events.json'
file_says 'Design sync' 'the title it was given goes to the file too'
file_says '"mira"' 'the guest it was given goes to the file too'
file_stops_saying '"id": "evt-1",' 'the deleted event is gone from events.json'

# The three gestures, in the file rather than in the log. The log says the store
# acted; this says the pointer's work is what a later run would read back.
if [[ -n "${drag_id:-}" ]]; then
    file_says "\"id\": \"$drag_id\"" 'the dragged-out event reaches events.json'
    file_says '"start": "2026-08-20T09:00"' 'holding the day the move put it on'
    file_says '"end": "2026-08-20T11:00"' 'and the length the resize gave it'
fi
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
# Create, move and resize are driven for real in section 10b above. What is
# still IPC-only:
#
#   TODO (guests, the pointer half): section 10c drives the picker from the
#       keyboard, which is the half that proves the field searches. A *click*
#       on a result row is still unexercised — and per #187 a click is not the
#       same seam as a key, so it is worth its own check once the panel's
#       geometry is readable from outside the way `WeekView.geometryLine`
#       makes the grid's.
#
# It is a `nested_click` plus one `expect_since`. It cannot be a screenshot:
# this seam never presents.

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all calendar checks passed\n'
exit 0
