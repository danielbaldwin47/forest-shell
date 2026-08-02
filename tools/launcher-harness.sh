#!/usr/bin/env bash
# Drive the launcher's apps provider inside a nested Hyprland (#39).
#
#   tools/launcher-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/launcher-harness.sh --keep   # leave the nested session up to poke at
#
# The launcher splits cleanly across the three seams, and this is the middle
# one. Which provider a query is in, what matches it, how frecency weights the
# result and where the list stops are decisions with no compositor in them —
# tests/tst_launcherpolicy.qml checks 38 of them. Whether the *provider* works
# is a different question, and it is the one the prototype got wrong: #11
# recorded `DesktopEntries.applications` as coming back empty on both runtimes
# with 190 desktop files on disk, and shipped a baked fixture instead.
#
# It is not empty. The model is populated asynchronously, one entry at a time,
# and only once something *observes* it — an imperative read at
# `Component.onCompleted`, or from a timer a second later, returns 0 either way.
# That is a trap no unit test can see and the exact class of thing this seam
# exists for, so check 2 below is the one that matters most here.
#
# What it asserts:
#
#   1. the provider comes up and says so
#   2. the desktop-entry scan finds applications, and settles
#   3. one line is logged for the settled count, not one per entry
#   4. a query filters the list down
#   5. a query that matches nothing returns nothing, without erroring
#   6. an empty query is the short recents list, not every app on the machine
#   7. the icon theme resolves a real entry's icon
#   8. a launch is remembered in the running shell
#   9. ...and reaches state.json on disk
#  10. a second launch increments rather than replacing
#  11. frecency reorders the recents list
#  12. nothing is fighting itself (no binding loops)
#
# The shell under test runs against a scratch XDG_CONFIG_HOME and
# XDG_STATE_HOME: this harness writes frecency counts, and one that wrote them
# into the session running it would leave the developer's own launcher ranked by
# the test suite.
#
# **Enter is not pressed here.** There is no key-injection tool this repo may
# assume, and this shell is layer surfaces all the way down, so `sendshortcut`
# has no toplevel to aim at (tools/drawer-harness.sh hits the same wall with
# Escape). The write is driven one seam below the keystroke — see the header of
# launcher-harness.qml — and what stays unchecked is one `Keys` handler.
#
# The drawer *window* half — that the launcher registers its IPC target, that
# Super+Space reaches the compositor, that opening it swaps with the session
# menu rather than stacking — is tools/drawer-harness.sh, because that is the
# window's behaviour rather than the provider's.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call launcher "$@"; }

## The reply with the `qs` client's own chatter stripped, so a check can compare
## against a value rather than grep for one. Every handler answers on one line
## for exactly this reason — see the header of launcher-harness.qml.
reply() { ipc "$@" 2>/dev/null | tr -d '\r' | tail -1; }

## The ranked ids as lines, from the comma-separated reply.
rows() { reply rank "$1" | tr ',' '\n' | grep -c . ; }
row() { reply rank "$1" | tr ',' '\n' | sed -n "$2p"; }

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

nested_shell launcher-harness.qml 'harness: launcher harness ready' || exit 1

echo

# --- 1. the provider is up ----------------------------------------------------

if grep -qa 'startup: stage apps provider armed' "$NESTED_SHELL_LOG"; then
    nested_pass 'the apps provider came up'
else
    nested_fail 'the apps provider never came up'
fi

# --- 2. the scan finds applications -------------------------------------------
#
# The check the prototype's finding demanded. A count of zero here is not "this
# machine has no applications" — it is the model never having been observed
# declaratively, which is the bug that cost #11 a fixture.

if ! nested_await "$NESTED_SHELL_LOG" 'launcher: [0-9]+ applications? indexed' 15; then
    nested_fail 'the desktop-entry scan never settled'
    COUNT=0
else
    COUNT=$(reply count)
    if [[ "$COUNT" =~ ^[0-9]+$ ]] && (( COUNT > 0 )); then
        nested_pass "the scan found $COUNT applications"
    else
        nested_fail "the scan settled at \"$COUNT\" applications — the model was never observed"
    fi
fi

if [[ "$(reply indexed)" == "true" ]]; then
    nested_pass 'the provider knows the scan has finished'
else
    nested_fail 'the provider still thinks it is looking'
fi

# --- 3. one line, not one per entry -------------------------------------------
#
# The model notifies per entry. A count logged on every notification is sixty
# lines of noise in the log this suite reads, so the line is debounced — and a
# debounce that silently stopped working would only ever show up here.

indexed_lines=$(grep -ac 'applications\? indexed' "$NESTED_SHELL_LOG")
if (( indexed_lines == 1 )); then
    nested_pass 'the settled count is logged once'
else
    nested_fail "the count was logged $indexed_lines times — the settle debounce is not working"
fi

# --- 4. a query filters --------------------------------------------------------
#
# Against whatever is actually installed: the desktop files on this machine are
# not the ones on the next, so the harness picks a real entry out of the model
# and searches for it rather than hard-coding a package name.

SAMPLE=$(reply sample "")
if [[ -z "$SAMPLE" ]]; then
    nested_fail 'no entry to search for — the model is empty'
else
    hits=$(reply rank "$(printf '%s' "$SAMPLE" | tr -cd '[:alnum:]' | cut -c1-4)")
    if [[ -n "$hits" ]]; then
        nested_pass 'a query filters the list to matches'
    else
        nested_fail "a query for part of \"$SAMPLE\" matched nothing"
    fi
fi

# --- 5. a query that matches nothing -------------------------------------------

if [[ -z "$(reply rank 'zqxjvwk')" ]]; then
    nested_pass 'a query that matches nothing returns nothing'
else
    nested_fail 'a nonsense query matched something'
fi

# --- 6. the empty state is short -----------------------------------------------
#
# #11 §6: a launcher that opens onto every application on the machine is a menu,
# not a clearing. The cap is `LauncherPolicy.recentsLimit`.

recents=$(rows "")
if (( recents > 0 && recents <= 6 )); then
    nested_pass "the empty state is a short list ($recents rows, of $COUNT apps)"
else
    nested_fail "the empty state is $recents rows — it should be a capped recents list"
fi

# --- 7. the icon theme answers -------------------------------------------------
#
# Separate from the entry model on purpose: #11 found `Quickshell.iconPath`
# working in a process where the model appeared not to, so a launcher can be
# fully populated and completely iconless.

FIRST=$(row "" 1)
icon=$(reply iconFor "$FIRST")
if [[ -n "$icon" ]]; then
    nested_pass "the icon theme resolved an icon ($FIRST → $icon)"
else
    nested_fail "no icon resolved for $FIRST"
fi

# --- 8. a launch is remembered -------------------------------------------------

before=$(reply uses "$FIRST")
ipc remember "$FIRST" > /dev/null
mark_pattern="launcher: remembered ${FIRST//./\\.} \\(1\\)"
if nested_await "$NESTED_SHELL_LOG" "$mark_pattern" 5; then
    nested_pass "the first launch of $FIRST was remembered"
else
    nested_fail "no frecency write logged for $FIRST (was $before before)"
fi

# --- 9. ...and it reaches the file ---------------------------------------------
#
# The in-memory count and the file are two different claims: Core/SpecFile.qml
# debounces the write by 250 ms and writes atomically through a second FileView.
# A count that is right in the shell and absent on disk is a launcher that
# forgets everything on restart, which is the failure worth catching.

state_json=""
for _ in $(seq 1 40); do
    state_json=$(find "$SCRATCH/state" -name 'state.json' -print -quit 2>/dev/null)
    [[ -n "$state_json" ]] && grep -qa '"uses"' "$state_json" && break
    sleep 0.1
done

if [[ -z "$state_json" ]]; then
    nested_fail 'no state.json was ever written'
elif python3 -c '
import json, sys
uses = json.load(open(sys.argv[1])).get("launcher", {}).get("uses", {})
sys.exit(0 if uses.get(sys.argv[2]) == 1 else 1)
' "$state_json" "$FIRST" 2>/dev/null; then
    nested_pass 'the use count reached state.json on disk'
else
    nested_fail "state.json does not hold a count of 1 for $FIRST: $(cat "$state_json" 2>/dev/null | head -c 300)"
fi

# --- 10. a second launch increments --------------------------------------------
#
# The map is replaced wholesale on every write (SpecFile deep-copies what it is
# given), so "the second write forgot the first" is a real shape rather than a
# hypothetical one.

ipc remember "$FIRST" > /dev/null
if nested_await "$NESTED_SHELL_LOG" "launcher: remembered ${FIRST//./\\.} \\(2\\)" 5; then
    nested_pass 'a second launch increments rather than replacing'
else
    nested_fail "the second launch of $FIRST did not reach a count of 2"
fi

# --- 11. frecency reorders the recents list ------------------------------------
#
# The point of remembering. Pick something that is *not* currently first, launch
# it enough times to matter, and it should come to the top of the empty-query
# list — while a typed query still ranks on the match (which is the unit test's
# job, not this one's).

TARGET=$(row "" 3)
if [[ -z "$TARGET" || "$TARGET" == "$FIRST" ]]; then
    nested_note 'too few applications to check reordering'
else
    for _ in $(seq 1 6); do ipc remember "$TARGET" > /dev/null; done
    sleep 0.3
    if [[ "$(row "" 1)" == "$TARGET" ]]; then
        nested_pass "frecency brought $TARGET to the top of the recents list"
    else
        nested_fail "$TARGET was launched 6 times and is still not first"
    fi
fi

# --- 12. nothing is fighting itself --------------------------------------------

if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops in the provider'
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all launcher checks passed\n'
exit 0
