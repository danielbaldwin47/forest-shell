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
#  14. the bottom edge dragged above its own start stops at the 15-minute floor,
#      and Escape sent into the middle of a held drag cancels it without writing
#      an event and without closing the window
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

## nested-session.sh counts failures; this counts passes too, by taking its
## `nested_pass` over — every check in this file goes through the helpers below
## and they all end there, so one shadowed function counts all of them.
##
## The count is what makes a *shrunken* run visible. Several blocks here can only
## run if the ones before them found something to aim at, and a run that skipped
## them printed the same "all calendar checks passed" as a full one. The expected
## total at the bottom is the check on the checks.
calendar_pass_count=0
nested_pass() {
    calendar_pass_count=$((calendar_pass_count + 1))
    printf '  \033[32mPASS\033[0m  %s\n' "$1"
}

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

# The Google sync half (section 11) runs against tools/fixtures/gcal-fake.sh
# rather than the real helper: no network, no account, no token. The mode file is
# how the fake is told to start refusing mid-run — the other two knobs are
# arguments, but a shell that is already up cannot be handed a new environment.
GCAL_PUSHES="$SCRATCH/pushes.jsonl"
GCAL_MODE="$SCRATCH/gcal-mode"
GCAL_RUNS="$SCRATCH/gcal-runs"
GCAL_ARGS="$SCRATCH/gcal-args"
: > "$GCAL_PUSHES"
: > "$GCAL_MODE"
: > "$GCAL_RUNS"
: > "$GCAL_ARGS"

NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state"
            "XDG_DATA_HOME=$SCRATCH/data"
            "FOREST_GCAL_HELPER=$REPO/tools/fixtures/gcal-fake.sh"
            "GCAL_FAKE_PUSHES=$GCAL_PUSHES"
            "GCAL_FAKE_RUNS=$GCAL_RUNS"
            "GCAL_FAKE_ARGS=$GCAL_ARGS"
            "GCAL_FAKE_MODE_FILE=$GCAL_MODE")

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

# --- 6b. the view change is a transition, not a swap --------------------------
#
# Seam 2 cannot see a frame — the nested compositor never presents one
# (`tools/nested-session.sh`'s header) — so "did it animate" is unaskable here
# and "did it decide to animate, and in which direction" is not. `CalendarView`
# logs the crossing, `KeyNavPolicy.viewSign` decides which way it travels
# (`tests/tst_keynavpolicy.qml` pins the sign), and between the two the motion
# is verified without a photograph of it.
#
# The window has to be open for any of this: the view outlives it, the grids
# that cross-fade do not.

mark=$(log_lines)
ipc view month > /dev/null
expect_since "$mark" 'calendar: transition view week->month' \
    'widening the scale is a logged transition and not a swap'

mark=$(log_lines)
ipc view day > /dev/null
expect_since "$mark" 'calendar: transition view month->day' \
    'and narrowing it names both ends the other way round'

# The refutation is the half that matters: a "transition" that fires when
# nothing changed is a transition nobody can trust to mean anything.
mark=$(log_lines)
ipc view day > /dev/null
refute_since "$mark" 'calendar: transition view' \
    'switching to the view already on screen transitions nothing'

mark=$(log_lines)
ipc view week > /dev/null
expect_since "$mark" 'calendar: transition view day->week' \
    'and back to week for everything below'

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
pointer_mark="$mark"
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

        # --- the resize floor -------------------------------------------------
        #
        # The bottom edge dragged *up* past its own start. `EventPolicy.resize`
        # floors at `minMinutes`, so the answer is 15m and not 0m and not a
        # negative one — the floor is the claim, and it is the only one of the
        # four gestures whose result is not where the pointer let go.
        #
        # The chip is on Thursday now, 09:00–11:00, so this aims 3px above the
        # 11:00 edge and lands on 09:00.
        mark=$(log_lines)
        nested_drag "$thu_x" "$(( y_1100 - 3 ))" "$thu_x" "$y_0900"
        expect_since "$mark" "calendar: drag begin resizeBottom $drag_id" \
            'a press on the moved chip'"'"'s bottom edge begins a resize'
        expect_since "$mark" "calendar: resize $drag_id 120m -> 15m" \
            'dragging the bottom edge above the start stops at the 15-minute floor'

        # --- cancel -----------------------------------------------------------
        #
        # Escape *during* a drag, which is the one gesture a single `nested_drag`
        # cannot express: it presses, travels and releases in one call. So the
        # drag is held at its destination (`NESTED_DRAG_HOLD_MS`, which
        # tools/nested-click.c grew for this) and run in the background, and the
        # key is sent into the middle of it. The hold is a second and the key
        # goes at 0.8s, comfortably after the travel ends and long before the
        # release — a wait rather than a race.
        #
        # Exactly one Escape, and this is why: once the drag is cancelled the
        # window's own Escape handler is live again, and a second would close the
        # calendar out from under everything below.
        #
        # Wednesday is empty again — the event moved to Thursday — so this is a
        # create drag, and a cancelled create must leave no event behind at all.
        mark=$(log_lines)
        NESTED_DRAG_HOLD_MS=1000 nested_drag "$wed_x" "$y_0900" "$wed_x" "$y_1030" &
        cancel_pid=$!
        # A bounded poll on the log rather than a fixed sleep: Escape only needs
        # to land once the drag has actually begun, and the travel time is not
        # a promise.
        for _ in $(seq 1 40); do
            since "$mark" | grep -qaE 'calendar: drag begin create' && break
            sleep 0.05
        done
        nested_key escape
        # And a bounded poll on the background drag's own exit, rather than an
        # unbounded `wait` — a drag that never releases would otherwise hang
        # the whole harness instead of failing the one check that noticed.
        released=0
        for _ in $(seq 1 60); do
            kill -0 "$cancel_pid" 2>/dev/null || { released=1; break; }
            sleep 0.05
        done
        if (( released )); then
            wait "$cancel_pid" || nested_note 'the held drag exited non-zero'
        else
            kill -9 "$cancel_pid" 2>/dev/null
            nested_fail 'drag never released'
        fi
        expect_since "$mark" 'calendar: drag cancel' \
            'Escape in the middle of a drag cancels it'
        refute_since "$mark" 'calendar: create ' \
            'and a cancelled create writes no event'
        refute_since "$mark" 'calendar: window closed' \
            'and the drag ate the key rather than closing the whole calendar'
    fi
fi

# --- 10d. the cursor ----------------------------------------------------------
#
# A cursor shape is not something a client draws, it is a request it sends
# (`wp_cursor_shape_device_v1.set_shape`, #185) — and this seam cannot read one,
# because the calendar is a `FloatingWindow` and `tools/cursor-harness.sh`'s
# `WAYLAND_DEBUG` trick needs the whole nested session run under it. What it can
# read is the shell's own word for the shape it asked for: `CursorPolicy` owns
# the mapping from zone to word *and* to protocol number, `tests/tst_cursorpolicy
# .qml` pins the pair, and the surfaces log the word as the pointer crosses.
#
# Nothing new is driven here. The three gestures above already put the pointer
# on empty grid, on a chip's body and on a chip's bottom edge, so this reads the
# lines those crossings left — which is also the point: if the pointer never
# reached the thing, the cursor line is missing and this fails for the same
# reason the drag would have.

if [[ -n "${wed_x:-}" ]]; then
    expect_since "$pointer_mark" 'calendar: cursor crosshair' \
        'the empty grid asks for a crosshair — a press there draws, it does not open'
    expect_since "$pointer_mark" 'calendar: cursor pointing-hand' \
        "a chip's body asks for the hand"
    expect_since "$pointer_mark" 'calendar: cursor ns-resize' \
        "and a chip's bottom edge asks for the resize arrows"
else
    # Said rather than skipped. The pointer checks read the lines the gestures
    # above left, so no gestures means no lines — and a silent skip here is a
    # short run that prints the same "all checks passed" as a full one.
    nested_fail 'no pointer gestures ran, so nothing crossed the grid to read a cursor from'
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

# --- 10e. Google sync ---------------------------------------------------------
#
# Everything about *what* a sync round decides is checked offscreen — the
# mapping in tests/tst_googleeventpolicy.qml, the plan in tests/tst_syncpolicy.qml,
# the HTTP in tests/tst_gcal_sync.py against a faked urlopen. None of that needs
# a compositor and none of it is repeated here.
#
# What only exists once a shell is running is the wiring, and it is the half that
# was silent when it broke: does a trigger reach a process, does that process's
# stdout reach the policy, does a queued op reach its stdin, does an exit code
# reach the log. Six log lines are the contract
# (Services/Calendar/GoogleSync.qml) and this section asserts on all of them.
#
# The helper is tools/fixtures/gcal-fake.sh, wired in through FOREST_GCAL_HELPER
# above. Sync starts *off*, and is switched on by editing settings.json the way a
# person would — which is also the check that the new schema section and its
# hot reload work at all.
#
# Before section 11 and not after it, because section 11 ends by taking the
# shell away: a sync check placed below `nested_kill_shell` asks a dead shell to
# sync and reads "No running instances" as ten failures.

SETTINGS="$SCRATCH/config/forest-shell/settings.json"

## The two files the fake keeps are read the way the log is — what arrived after
## a mark, never the whole thing — because this section runs several rounds and
## every question here is about one of them.
runs_since() { tail -n "+$(($1 + 1))" "$GCAL_RUNS" 2>/dev/null; }
args_lines() { wc -l < "$GCAL_ARGS" 2>/dev/null || echo 0; }
args_since() { tail -n "+$(($1 + 1))" "$GCAL_ARGS" 2>/dev/null; }
runs_lines() { wc -l < "$GCAL_RUNS" 2>/dev/null || echo 0; }
pushes_lines() { wc -l < "$GCAL_PUSHES" 2>/dev/null || echo 0; }

# Held from here to the end of the section for the secret check at the bottom.
gcal_mark=$(log_lines)

# Off is the state the shell starts in, and the check worth making is not that
# it says so — it is that nothing ran. A setting that reached the log line but
# not the process would look exactly like this in the log and be a subprocess
# every five minutes on every machine that never connected an account. The
# window has already been opened and closed several times above, and `show()`
# calls `syncOnOpen`, so this counts those too.
mark=$(log_lines)
ipc sync > /dev/null
expect_since "$mark" 'calendar: sync off' \
    'a sync asked for while the setting is off says so'
if (( $(runs_lines) == 0 )); then
    nested_pass 'and runs no helper at all — not for the verb, and not for the opens above'
else
    nested_fail "sync is off and the helper ran $(runs_lines) time(s): $(tr '\n' ' ' < "$GCAL_RUNS")"
fi

mark=$(log_lines)
python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as handle:
        doc = json.load(handle)
except (OSError, ValueError):
    doc = {}
doc.setdefault("calendar", {}).setdefault("google", {})["enabled"] = True
doc["calendar"]["google"]["calendarId"] = "primary"
with open(path, "w") as handle:
    json.dump(doc, handle, indent=2)
    handle.write("\n")
PY
# The shell's own line and not `config: reloaded`: the reload proves a file was
# re-read, and this proves the service that reads it saw the change. They are
# different claims, and the second is the one this section is about.
expect_since "$mark" 'calendar: sync on' \
    'switching sync on in settings.json is picked up without a restart'

# The first round. No syncToken yet, so the fake answers as a full pull does:
# two events, one timed with a guest and a meeting room, one all-day.
mark=$(log_lines)
args_mark=$(args_lines)
ipc sync > /dev/null
expect_since "$mark" 'calendar: sync pull 2 changes' \
    'a round pulls the fake helper'"'"'s two events'
expect_since "$mark" 'calendar: sync idle [0-9]{4}-[0-9]{2}-[0-9]{2}T' \
    'the round ends by saying when it ended'

# `--window` is a flag only a *full* pull carries, and nothing at the first seam
# can see an argv — `SettingsSchema` states the number and `SyncPolicy` never
# meets it. This is the only place the claim "the process was told" is checkable.
if args_since "$args_mark" | grep -qE '^pull .*--window [0-9]+'; then
    nested_pass 'the first pull — no token yet — carries a --window'
else
    nested_fail "a full pull went out without a --window: $(args_since "$args_mark" | tr '\n' '|')"
fi

# The log is the shell'"'"'s claim; the file is the evidence. The store writes on a
# 250ms debounce, so this polls rather than reads once.
pulled=""
for _ in $(seq 1 40); do
    if grep -qa 'Fake standup' "$EVENTS"; then pulled=yes; break; fi
    sleep 0.1
done
if [[ -n "$pulled" ]]; then
    nested_pass 'a pulled event reaches events.json, not just the log'
else
    nested_fail "the pull logged 2 changes and events.json has no 'Fake standup' in it"
fi

# This round *did* push — the seeded fixture calendar predates sync being
# switched on, and uploading it is what `SyncPolicy.reconcile` is for. What must
# never be in there is one of the two events that just came *down*: an echoed
# pull is the loop the design is arranged around (`applyRemote` deliberately
# emits no `mutated`, and a pulled event's `modifiedAt` is stamped with the
# server's own `updated` so it cannot read as locally-newer), and both halves of
# that are decided elsewhere — here is where the wiring between them is checked.
# A pushed op names the event it is about by `googleId`, so the fake's own ids
# are the tell.
if grep -qaE 'gid-(standup|offsite)' "$GCAL_PUSHES"; then
    nested_fail 'an event that arrived in the pull was pushed straight back up'
else
    nested_pass 'a pulled event is not echoed back as a push'
fi

status=$(ipc syncStatus 2>/dev/null)
if grep -qaw 'idle' <<< "$status"; then
    nested_pass 'syncStatus answers one word, and it is the right one'
else
    nested_fail "syncStatus answered '${status:-nothing}' and not 'idle'"
fi

# The second round carries the token the first one was given, which is the
# difference between an incremental pull and a full one. The fake answers an
# incremental pull with nothing, which is the shape of almost every real round.
pushes_mark=$(pushes_lines)
args_mark=$(args_lines)
mark=$(log_lines)
ipc sync > /dev/null
expect_since "$mark" 'calendar: sync pull 0 changes' \
    'the next round is incremental — the syncToken was kept'
expect_since "$mark" 'calendar: sync idle [0-9]{4}' \
    'and finishes rather than hanging on an empty answer'
# …and carries no window. A token pull asks what changed, and a change that
# moved an event *out* of the window is one the server would then not mention —
# so a window here is worse than a filter, it is a hole.
if args_since "$args_mark" | grep -qE '^pull .*--window'; then
    nested_fail "an incremental pull carried a --window: $(args_since "$args_mark" | tr '\n' '|')"
else
    nested_pass 'and asks for no --window — the token already says what changed'
fi
# The round before it uploaded the whole seeded calendar and was told each
# event's `googleId` and `updated`. If any of that was dropped on the way back
# into the store, every round from here to forever would upload it again — the
# same loop as an echoed pull, arriving by the other door.
if (( $(pushes_lines) == pushes_mark )); then
    nested_pass 'a round with nothing to say sends nothing — what was pushed stayed pushed'
else
    nested_fail "an idle round pushed $(( $(pushes_lines) - pushes_mark )) op(s) again"
fi

# Two triggers inside one round. Ordinary on a real calendar — the interval
# timer and the three-second debounce behind an edit have no reason to miss each
# other — and not survivable by accident: a `Process` handed a command while it
# is running is killed, so the second trigger would take the first round's pull
# away mid-answer. `slow` is what makes the overlap deliberate instead of a race
# the fake usually wins.
printf 'slow\n' > "$GCAL_MODE"
runs_mark=$(runs_lines)
mark=$(log_lines)
ipc sync > /dev/null
ipc sync > /dev/null
expect_since "$mark" 'calendar: sync idle [0-9]{4}' \
    'a round that is slow to answer still ends'
overlapped=$(runs_since "$runs_mark" | grep -c 'pull' || true)
if (( overlapped == 1 )); then
    nested_pass 'the second trigger is dropped — one round, one helper'
else
    nested_fail "two overlapping syncs ran $overlapped pull helper(s), wanted 1"
fi
: > "$GCAL_MODE"

# A local edit, pushed. No `ipc sync` here on purpose: the push has to be the
# 3-second debounce behind a mutation, or the trigger is untested and only the
# verb is.
# The id is read off the file the way section 8 argues it must be, not written
# down: two of the events in there now arrived from the fake helper, so the
# highest id is not the fixture's any more.
push_id="evt-$(python3 -c '
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
made=$(ipc create 2026-08-21 840 30 'Pushed by the harness' 2>/dev/null)
if ! grep -qa "$push_id" <<< "$made"; then
    nested_fail "could not make an event to push (create answered '${made:-nothing}', wanted $push_id)"
    nested_fail "and so could not check that the op left the shell"
else
    expect_since "$mark" "calendar: sync push $push_id ok" \
        'a local edit is pushed by the debounce behind it, not by a verb'
    landed=""
    for _ in $(seq 1 40); do
        if grep -qa "\"$push_id\"" "$GCAL_PUSHES"; then landed=yes; break; fi
        sleep 0.1
    done
    if [[ -n "$landed" ]]; then
        nested_pass 'the op really left the shell — it is in the pushes file'
    else
        nested_fail "the log claimed $push_id was pushed and $GCAL_PUSHES has no such op"
    fi
fi

# Exit 3 is the helper saying no account is connected. A state and not an error:
# the shell says so once and does not spend a subprocess every few seconds
# retrying a consent flow nobody has run.
printf 'auth-needed\n' > "$GCAL_MODE"
mark=$(log_lines)
ipc sync > /dev/null
expect_since "$mark" 'calendar: sync auth needed' \
    'a helper that exits 3 is reported as an account to connect, not a failure'
refute_since "$mark" 'calendar: sync error' \
    'and not also as an error'

# Exit 1 is the other kind of bad news: a failure rather than a state. The shell
# names the code — an error whose code is not in the log is a bug report that
# begins "it stopped syncing" — and then comes back by itself. The backoff is
# the only thing that gets a laptop whose network dropped back in sync without
# somebody opening a window, and nothing else in this file would notice if it
# never fired once.
printf 'broken\n' > "$GCAL_MODE"
mark=$(log_lines)
ipc sync > /dev/null
expect_since "$mark" 'calendar: sync error 1' \
    'a helper that exits 1 is an error, reported with its code'
: > "$GCAL_MODE"
expect_since "$mark" 'calendar: sync idle [0-9]{4}' \
    'and the backoff brings the next round on its own, with no second verb'

mark=$(log_lines)
ipc syncConnect > /dev/null
expect_since "$mark" 'calendar: sync connected fake@example.com' \
    'syncConnect runs the consent flow and logs the address it got'

# The token, and where it did not go. The control comes first for #78's reason:
# a refutation over a log passes just as happily against a helper that never had
# a secret to leak, so the run has to establish there was one. The fake prints a
# bearer token on stderr for every invocation and puts it in the JSON the shell
# parses — including the consent answer `syncConnect` just read one field out of.
# Captured rather than piped into `grep -q`: this script runs under `pipefail`,
# and a `-q` that stops reading hands the fake a SIGPIPE, which is a non-zero
# pipeline and a control that fails for reasons that have nothing to do with
# what it is asking.
control=$(GCAL_FAKE_MODE_FILE= GCAL_FAKE_RUNS= \
          "$REPO/tools/fixtures/gcal-fake.sh" auth 2>&1 || true)
if grep -qaE 'ya29\.' <<< "$control"; then
    nested_pass 'the fake really does hand the shell a token — the control'
else
    nested_fail 'the fake printed no token, so the check below would prove nothing'
fi
refute_since "$gcal_mark" 'ya29\.' \
    'and none of it reaches the log — not a round, not a failure, not the consent flow'

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

## One named event's own field, rather than a string that is somewhere in the
## file. `file_says '"start": "2026-08-20T09:00"'` is the trap this exists to
## avoid: that stamp was already in the fixture, on a different event, so the
## check passed before the drag ever ran and would have kept passing if the
## pointer had done nothing at all.
##
## Polls for the reason `file_says` does — the write is a restarting 250ms
## debounce — and parses the file rather than grepping it, because "this event
## has this start" is a question about one JSON object and not about the text.
event_field_says() {
    local id="$1" field="$2" want="$3" what="$4"
    for _ in $(seq 1 50); do
        if python3 - "$EVENTS" "$id" "$field" "$want" <<'PY'
import json
import sys

path, ident, field, want = sys.argv[1:5]
try:
    with open(path) as handle:
        events = json.load(handle).get("events", [])
except (OSError, ValueError):
    sys.exit(1)
for event in events:
    if isinstance(event, dict) and event.get("id") == ident:
        sys.exit(0 if event.get(field) == want else 1)
sys.exit(1)
PY
        then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — no event $id with a $field of \"$want\" in $EVENTS"
    return 1
}

# The four gestures, in the file rather than in the log. The log says the store
# acted; this says the pointer's work is what a later run would read back — the
# id and the field together, so the fixture cannot answer for the drag.
if [[ -n "${drag_id:-}" ]]; then
    event_field_says "$drag_id" start '2026-08-20T09:00' \
        'the dragged-out event is in events.json, on the day the move put it'
    event_field_says "$drag_id" end '2026-08-20T09:15' \
        'and at the length the floored resize left it'
    event_field_says "$drag_id" title 'New event' \
        'under the default title the dismissed panel kept for it'
else
    # Said rather than skipped, for the reason the cursor block gives: three
    # checks that quietly did not run look exactly like three that passed.
    nested_fail 'no drag ran, so events.json was never asked about one'
fi
file_says '"id": "evt-11"' 'the fixture events it never touched are still there'

# Only now is it safe to take the shell away. A SIGTERM does not run QML
# destruction — measured: killing the shell 200 ms after a delete left the file
# holding the event, with `Component.onDestruction: flush()` in place — so the
# waits above are the harness's own guarantee and the flush is a courtesy to a
# clean quit, not something to assert through.
nested_kill_shell

# Read out of the policy rather than written down here. A hardcoded number goes
# stale the first time the schema moves and then asserts that the migration did
# not happen — which is the shape of a check that passes for a year and then
# fails for the wrong reason.
schema_version=$(sed -n 's/.*readonly property int version: \([0-9]\+\).*/\1/p' \
    "$REPO/Services/Calendar/EventPolicy.qml" | head -1)
if [[ -n "$schema_version" ]] && grep -qa "\"version\": $schema_version" "$EVENTS" 2>/dev/null; then
    nested_pass "the file it wrote is stamped with its schema version (v$schema_version)"
else
    nested_fail "the written events.json is not stamped v${schema_version:-?}"
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

# How many checks a whole run makes. Stated, so a run that quietly made fewer
# fails instead of congratulating itself — several blocks above only run when the
# ones before them found something to aim at, and "all calendar checks passed" is
# a sentence a half-run could print. Bump it deliberately when a check is added.
CALENDAR_EXPECTED=122

printf '\n'
printf 'calendar: %s passed, %s failed, expected %s\n' \
    "$calendar_pass_count" "$nested_fail_count" "$CALENDAR_EXPECTED"
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
if (( calendar_pass_count != CALENDAR_EXPECTED )); then
    printf 'the run made %s checks and not %s — a check was skipped, or added without bumping CALENDAR_EXPECTED\n' \
        "$calendar_pass_count" "$CALENDAR_EXPECTED"
    printf 'shell log: %s\n' "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all calendar checks passed\n'
exit 0
