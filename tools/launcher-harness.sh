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
#  12. `=` evaluates through qalc, and the answer reaches a row
#  13. a leading digit reaches the calculator with no prefix typed
#  14. a sum qalc refuses says so, rather than showing nothing
#  15. `:` searches the emoji table, and Enter copies the glyph
#  16. `=` Enter copies the result
#  17. `/` lists actions, and one of them changes the shell
#  18. ...and the change reaches settings.json on disk
#  19. nothing is fighting itself (no binding loops)
#  20. a machine with no qalc says so, immediately and only about the calculator
#
# ## The three #40 providers, and why they are here
#
# Checks 12-18 are the ones the unit tests cannot make. The calculator spawns a
# process, the emoji and calculator rows write the Wayland clipboard, and the
# actions rows reach four other singletons and one file on disk — none of which
# exists on the `tests/` side of the line.
#
# Check 20 is the sharpest of them and the reason the provider is built the way
# it is. Measured against Quickshell 0.3.0, a `Process` whose binary is missing
# emits *no* `exited` signal — only `running` going false — so there is no exit
# code to key a "not installed" message off, and keying it off empty output
# instead is the #78 shape the ticket's maintenance pass named in advance. The
# check restarts the shell with a PATH that has everything on it except `qalc`,
# which is the only way to ask the question honestly.
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

## The dispatcher's rows for a whole query, prefix and all (#40).
prow() { reply rows "$1" | tr ',' '\n' | sed -n "$2p"; }

## Poll until a query has rows, or give up.
##
## The calculator is the one provider that answers asynchronously — it has to
## start a process, wait for it to exit, and read what it printed — so a single
## call returning nothing is the correct *first* answer rather than a failure.
## Everything else here is synchronous and settles on the first ask; this loop
## costs them one iteration.
settle() {
    local query="$1" tries="${2:-40}"
    while (( tries-- > 0 )); do
        [[ -n "$(reply rows "$query")" ]] && return 0
        sleep 0.1
    done
    return 1
}

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

# --- 12. the calculator evaluates ----------------------------------------------
#
# The whole of what the unit tests cannot reach: a real `qalc` on this machine,
# spawned by a real `Process`, printing something the policy then reads.

if ! grep -qa 'startup: stage calculator provider armed' "$NESTED_SHELL_LOG"; then
    nested_fail 'the calculator provider never came up'
elif [[ "$(reply calculatorReady)" != "true" ]]; then
    nested_note 'no qalc on this machine — checks 12-14 and 16 skipped'
    NO_QALC=1
else
    nested_pass 'the calculator provider found qalc'
fi

if [[ -z "${NO_QALC:-}" ]]; then
    if settle '=12 * 60 * 24' && [[ "$(reply title '=12 * 60 * 24' 0)" == "17280" ]]; then
        nested_pass 'a sum typed behind = comes back evaluated'
    else
        nested_fail "= 12 * 60 * 24 came back as \"$(reply title '=12 * 60 * 24' 0)\""
    fi

    # --- 13. a leading digit needs no prefix -----------------------------------
    #
    # The implicit route (LauncherPolicy.impliedId). Nothing about it is visible
    # to the apps provider, so a regression here looks like a launcher that has
    # simply stopped finding anything for `2+2`.

    if settle '2+2' && [[ "$(prow '2+2' 1)" == calculator:* ]]; then
        nested_pass 'a bare sum routes to the calculator with no prefix typed'
    else
        nested_fail "2+2 routed to \"$(prow '2+2' 1)\" rather than the calculator"
    fi

    # --- 14. a refused sum says so ----------------------------------------------
    #
    # Measured: `qalc -t "frobnicate(2)"` exits 1 and *still prints* `0 B·t·m⁴`.
    # Output cannot be the test, which is why the policy reads the exit code —
    # and why "no rows" must not be the whole of what the user is told.

    reply rows '=frobnicate(2)' > /dev/null
    sleep 0.5
    said=$(reply silence '=frobnicate(2)')
    if [[ "$said" == *"not a sum"* ]]; then
        nested_pass 'a sum qalc refuses is reported as a refusal'
    else
        nested_fail "a refused sum said \"$said\""
    fi
fi

# --- 15. the emoji provider copies ---------------------------------------------

if [[ "$(reply title ':rocket' 0)" == "rocket" ]]; then
    nested_pass 'the emoji table is searchable'
else
    nested_fail "\":rocket\" found \"$(reply title ':rocket' 0)\""
fi

if [[ "$(reply activate ':rocket' 0)" == "true" && "$(reply clipboard)" == "🚀" ]]; then
    nested_pass 'Enter on an emoji row puts the glyph on the clipboard'
else
    nested_fail "the clipboard holds \"$(reply clipboard)\" after copying 🚀"
fi

# --- 16. ...and so does the calculator ------------------------------------------

if [[ -z "${NO_QALC:-}" ]]; then
    if settle '=2+2' && [[ "$(reply activate '=2+2' 0)" == "true" \
                        && "$(reply clipboard)" == "4" ]]; then
        nested_pass 'Enter on a result puts the number on the clipboard'
    else
        nested_fail "the clipboard holds \"$(reply clipboard)\" after copying a result"
    fi
fi

# --- 17. the actions provider runs something ------------------------------------
#
# The dark/light row. It is a *caller* — Core/Theme.qml owns the mode and #44's
# tile and #58's switch call the same function — so what is checked here is that
# the call lands, not that the launcher has its own idea of the mode.

before=$(reply dark)
if [[ "$(reply runAction theme.toggle)" == "true" && "$(reply dark)" != "$before" ]]; then
    nested_pass "the dark mode action flipped the shell from $before"
else
    nested_fail "the dark mode action left the shell at $before"
fi

# The lock action is the one the harness refuses to run, for the reason it
# refuses to launch applications — see the header of launcher-harness.qml.
if [[ "$(reply runAction session.lock)" == "false" ]]; then
    nested_pass 'the harness refuses to run the lock action'
else
    nested_fail 'the harness ran the lock action — the nested session is now locked'
fi

# --- 18. ...and it reaches the file ---------------------------------------------
#
# Through Core/SpecFile.qml's 250 ms debounce, which is the half of a config
# write that no unit test sees.

SETTINGS="$SCRATCH/config/forest-shell/settings.json"
tries=30
while (( tries-- > 0 )); do
    grep -qa "\"darkMode\": $(reply dark)" "$SETTINGS" 2>/dev/null && break
    sleep 0.1
done
if grep -qa "\"darkMode\": $(reply dark)" "$SETTINGS" 2>/dev/null; then
    nested_pass 'the action reached settings.json on disk'
else
    nested_fail "settings.json does not agree with the shell: $(grep -ao '"darkMode":[^,]*' "$SETTINGS" 2>/dev/null)"
fi

# --- 19. nothing is fighting itself --------------------------------------------

if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops in the provider'
fi

# --- 20. a machine with no qalc -------------------------------------------------
#
# Last, because it restarts the shell and the restart truncates the log every
# check above reads.
#
# The PATH is a directory of symlinks to everything in /usr/bin except `qalc` —
# rather than an empty one — so that the only thing missing is the calculator's
# tool. A shell that lost every binary would fail this check for reasons that
# have nothing to do with #40.

kill "$NESTED_SHELL_PID" 2>/dev/null
wait "$NESTED_SHELL_PID" 2>/dev/null

NOQALC="$SCRATCH/nopath"
mkdir -p "$NOQALC"
for binary in /usr/bin/*; do
    ln -sf "$binary" "$NOQALC/$(basename "$binary")" 2>/dev/null
done
# `NESTED_QS` is a name looked up on PATH, and this is the PATH — so the shell
# under test has to be able to find the thing that starts it. Resolved against
# the *outer* PATH before it is replaced.
QS_PATH=$(command -v "$NESTED_QS" 2>/dev/null || printf '%s' "$NESTED_QS")
ln -sf "$QS_PATH" "$NOQALC/$(basename "$QS_PATH")"
rm -f "$NOQALC/qalc"

NESTED_ENV+=("PATH=$NOQALC")
if ! nested_shell launcher-harness.qml 'harness: launcher harness ready'; then
    nested_fail 'the shell did not come up without qalc on PATH'
else
    if nested_await "$NESTED_SHELL_LOG" 'launcher: no qalc on PATH' 10; then
        nested_pass 'a missing qalc is noticed at startup, not at the first sum'
    else
        nested_fail 'the shell never noticed that qalc is missing'
    fi

    said=$(reply silence '=2+2')
    if [[ "$said" == *"not installed"* ]]; then
        nested_pass "a sum with no qalc says: $said"
    else
        nested_fail "a sum with no qalc said \"$said\""
    fi

    # The failure must stay inside the provider that owns it.
    if [[ "$(reply title ':fire' 0)" == "fire" ]]; then
        nested_pass 'the other providers are unaffected by a missing qalc'
    else
        nested_fail 'a missing qalc took the emoji provider down with it'
    fi
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all launcher checks passed\n'
exit 0
