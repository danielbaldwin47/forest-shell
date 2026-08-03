#!/usr/bin/env bash
# Drive the launcher's apps provider inside a nested Hyprland (#39).
#
#   tools/launcher-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/launcher-harness.sh --keep   # leave the nested session up to poke at
#   tools/launcher-harness.sh --live   # ...and spend one real Ask Claude turn
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
#  19. the Ask Claude provider comes up
#  20. its preflight answers at startup rather than at the first `?`
#  21. the argv the *resolved* config builds is contained, and cannot say --bare
#  22. `?` produces a conversation rather than rows
#  23. a real question streams, resumes and cancels        (--live only)
#  24. `;` lists the clipboard, filters it, and Enter puts an entry back —
#      text through the compositor's selection, an image through `wl-copy`,
#      with a thumbnail decoded to disk       (needs cliphist + wl-clipboard)
#      — including that the watcher lines in the *shipped* autostart config
#      start, stay up, and fill the history from a plain copy (#140)
#  25. nothing is fighting itself (no binding loops)
#  26. a machine with no qalc and no cliphist says so about each, immediately,
#      and only about the provider that owns the tool
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

LIVE=0
for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        # Spends one real turn on the user's subscription. Off by default for
        # that reason and not because the check is weak — it is the only one
        # here that watches an answer actually stream.
        --live) LIVE=1 ;;
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
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state" "$SCRATCH/cache"
# The cache is scratch for #53's sake and it is not tidiness: cliphist keeps its
# store under `XDG_CACHE_HOME`, so a harness without this line would read — and
# print — the developer's own clipboard history.
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state"
            "XDG_CACHE_HOME=$SCRATCH/cache")

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

# --- 19. Ask Claude comes up ----------------------------------------------------

if grep -qa 'startup: stage claude provider armed' "$NESTED_SHELL_LOG"; then
    nested_pass 'the Ask Claude provider came up'
else
    nested_fail 'the Ask Claude provider never came up'
fi

# --- 20. the preflight answered -------------------------------------------------
#
# Either answer is a pass. What is being checked is that the question was asked
# at startup rather than left for the first `?` to discover — the calculator's
# argument, and the difference between a panel that says "not logged in" the
# moment you type `?` and one that takes a question and then says it.

if nested_await "$NESTED_SHELL_LOG" 'launcher: (claude ready|Not logged in)' 15; then
    nested_pass "the preflight answered: $(grep -aoE 'launcher: (claude ready|Not logged in.*)' "$NESTED_SHELL_LOG" | tail -1)"
else
    nested_fail 'the preflight never ran — a `?` would discover the auth state itself'
fi

# --- 21. the argv the *resolved* config produces ---------------------------------
#
# tests/tst_claudepolicy.qml asserts this shape against a hand-written settings
# object. What it cannot see is whether Core/SettingsSchema.qml still resolves
# to something that produces it: a coercer that quietly dropped
# `launcher.claude.tools` would pass every unit test and ship a run with no
# restriction on it at all. This is the same argv, built from the config the
# shell actually loaded.

ARGV=$(reply claudeArgv 'hello')

argv_has() {
    if [[ "$ARGV" == *"$1"* ]]; then
        nested_pass "the argv carries $2"
    else
        nested_fail "the argv is missing $2 — got: ${ARGV:0:200}"
    fi
}

argv_has '--tools WebSearch,WebFetch,Read,Grep,Glob' 'the restricted tool set'
argv_has '--allowedTools WebSearch,WebFetch,Read,Grep,Glob' 'the matching grant'
argv_has '--safe-mode' 'a hermetic run'
argv_has '--permission-mode dontAsk' 'the deny gate'
argv_has '--verbose' 'the flag stream-json requires'

# The one that is about money rather than behaviour: `--bare` hard-disables
# OAuth, so a run carrying it works perfectly and bills an API account instead
# of the subscription the user is paying for.
if [[ "$ARGV" != *"--bare"* ]]; then
    nested_pass 'the argv cannot reach --bare'
else
    nested_fail 'the argv carries --bare — this run would not be on the subscription'
fi

# --- 22. `?` is a conversation, not a list ---------------------------------------

if [[ -z "$(reply rows '?why is the sky blue')" ]]; then
    nested_pass 'a question produces no rows — the panel is a transcript'
else
    nested_fail "a question produced rows: $(reply rows '?why is the sky blue')"
fi

said=$(reply silence '?')
if [[ -n "$said" ]]; then
    nested_pass "an empty question says: $said"
else
    nested_fail 'an empty question says nothing at all'
fi

# --- 23. a real question --------------------------------------------------------
#
# Off by default, and that is the honest default rather than a timid one: this
# check spends real money on the user's own subscription and needs a network.
# `--live` asks for it.
#
# What it cannot check either way is the ticket's last acceptance criterion —
# that the run is on subscription auth rather than an API key. The nested
# session inherits the environment it was started from, so an absent
# `ANTHROPIC_API_KEY` here says nothing about a real session's. That one is a
# real-session check and the PR says so.

if (( LIVE )); then
    if [[ "$(reply claudeReady)" != "true" ]]; then
        nested_fail 'asked for --live but the CLI is not logged in'
    else
        reply claudeReset >/dev/null
        reply askClaude 'Reply with exactly the word: pineapple' >/dev/null

        # The question is in the transcript on the same call, before any
        # answer: the panel must never look like it dropped what was typed.
        if [[ "$(reply claudeTurns)" == "1" ]]; then
            nested_pass 'the question is in the transcript before the answer'
        else
            nested_fail "the question did not reach the transcript: $(reply claudeTurns) turn(s)"
        fi

        if nested_await "$NESTED_SHELL_LOG" 'launcher: session .* (opened|resumed)' 10; then
            nested_pass "a session was opened: $(reply claudeSession)"
        else
            nested_fail 'no session was opened'
        fi

        if nested_await "$NESTED_SHELL_LOG" 'launcher: answered in [0-9]+ms' 60; then
            nested_pass "the answer landed: $(reply claudeTurn 1)"
        else
            nested_fail "the answer never landed — failure: $(reply claudeFailure)"
        fi

        # The follow-up resumes rather than opening a second conversation.
        SID=$(reply claudeSession)
        reply askClaude 'What word did you just say? One word.' >/dev/null
        if nested_await "$NESTED_SHELL_LOG" "launcher: session $SID resumed" 10; then
            nested_pass 'the follow-up resumed the same session'
        else
            nested_fail 'the follow-up did not resume the session'
        fi

        # And it can be stopped mid-answer.
        if [[ "$(reply claudeCancel)" == "true" ]]; then
            nested_await "$NESTED_SHELL_LOG" 'launcher: cancelled by the user' 5 \
                && nested_pass 'a turn in flight can be cancelled' \
                || nested_fail 'the cancel was accepted but never logged'
        else
            nested_pass 'nothing was in flight to cancel'
        fi
    fi
else
    printf '  ..  skipped the live question (pass --live to spend a real turn)\n'
fi

# --- 24. the clipboard (#53) ----------------------------------------------------
#
# The provider whose every failure looks like success. `cliphist list` prints
# nothing on an empty history, nothing when the watcher was never started, and
# nothing when the binary is absent — three different pieces of news, one of
# which is fine and two of which need a sentence. Only the exit status and the
# probe tell them apart, which is the ticket's own instruction and #78's shape.
#
# The history is seeded through `cliphist store` directly, on stdin, which is
# exactly what `wl-paste --watch cliphist store` does to it — so this is the
# real store rather than a fixture, without needing a watcher running inside a
# nested compositor that cannot present a frame.
#
# `XDG_CACHE_HOME` is scratch for the whole run, and that is not tidiness: the
# store is a file under it, so a harness without it would list the developer's
# own clipboard history — every password manager paste of the day — into a log
# this suite prints.

if grep -qa 'startup: stage clipboard provider armed' "$NESTED_SHELL_LOG"; then
    nested_pass 'the clipboard provider came up'
else
    nested_fail 'the clipboard provider never came up'
fi

## Seed the store the way the watcher does.
clip_store() { env XDG_CACHE_HOME="$SCRATCH/cache" cliphist store; }

## Leave the provider and come back to it, which is what re-reads the history.
## The list is read on *entering* the room rather than per keystroke (the
## history changes outside this shell), so this is the user's own gesture and
## not a back door: type something else, then type `;` again.
clip_reenter() {
    reply rows '' >/dev/null
    reply rows ';' >/dev/null
}

## Poll until the listing has at least N entries.
clip_settle() {
    local want="$1" tries="${2:-40}"
    while (( tries-- > 0 )); do
        [[ "$(reply clipboardCount)" =~ ^[0-9]+$ ]] \
            && (( $(reply clipboardCount) >= want )) && return 0
        sleep 0.1
    done
    return 1
}

if ! command -v cliphist >/dev/null 2>&1 || ! command -v wl-copy >/dev/null 2>&1; then
    # The round trip needs both binaries and there is nothing honest to fake.
    # What still runs is check 26 below, which removes `cliphist` from PATH on
    # purpose — so the degradation half is covered on every machine, and only
    # the success half is skipped here.
    nested_note 'skipped the clipboard round trip — cliphist and wl-clipboard are not installed'
else
    # An empty history, before anything is stored. The state a machine with
    # cliphist installed and no watcher running sits in forever, so "empty" on
    # its own would be true and useless.
    said=$(reply silence ';')
    if [[ "$said" == *"wl-paste"* && "$said" == *"--watch"* ]]; then
        nested_pass "an empty history names the watcher: $said"
    else
        nested_fail "an empty history said \"$said\""
    fi

    # The watchers, from the file a user actually installs (#140). Everything
    # below this block seeds the store by hand, which proves the provider reads
    # a history but never that anything fills one — the bug was a shell whose
    # `;` was empty on every machine but the author's, with the two lines held
    # as data and prose and shipped in no installable config.
    #
    # So: parse them out of the shipped conf and start them exactly as
    # Hyprland's `exec-once` would, rather than writing the argv again here — a
    # copy of the line cannot catch the line being wrong. Then stop them again
    # before the rest of check 24 runs. A watcher left up would re-store every
    # entry the checks below put on the selection and turn a deterministic
    # history into a racing one.
    CLIP_CONF="integration/hyprland/forest-autostart.conf"
    CLIP_WATCHERS=()
    nested_env_argv
    while IFS= read -r clip_line; do
        # Word-split deliberately: the line is an argv, not a shell command.
        # `env … cmd &` is fork+exec, so $! is the watcher itself and not a
        # subshell around it — killing a subshell would leave it running.
        # shellcheck disable=SC2086
        "${NESTED_ENV_ARGV[@]}" XDG_CACHE_HOME="$SCRATCH/cache" \
            ${clip_line#exec-once = } >/dev/null 2>&1 &
        CLIP_WATCHERS+=("$!")
    done < <(grep '^exec-once = ' "$CLIP_CONF")

    if (( ${#CLIP_WATCHERS[@]} == 2 )); then
        nested_pass "$CLIP_CONF ships 2 watcher lines"
    else
        nested_fail "$CLIP_CONF ships ${#CLIP_WATCHERS[@]} watcher lines, not 2"
    fi

    # A wrong flag makes `wl-paste` exit at once, so "still alive" is the check
    # that the shipped argv is one this wl-clipboard accepts.
    sleep 0.5
    clip_alive=0
    for clip_pid in ${CLIP_WATCHERS[@]+"${CLIP_WATCHERS[@]}"}; do
        kill -0 "$clip_pid" 2>/dev/null && (( clip_alive++ ))
    done
    # `clip_alive == count` is vacuously true at zero, which is exactly the
    # state this check exists to catch — a conf that ships no lines at all.
    if (( ${#CLIP_WATCHERS[@]} > 0 && clip_alive == ${#CLIP_WATCHERS[@]} )); then
        nested_pass 'both watchers are still running after starting'
    else
        nested_fail "$clip_alive of ${#CLIP_WATCHERS[@]} watchers survived starting"
    fi

    # A fresh value per attempt rather than one copy and a long poll: `cliphist`
    # stores selection *changes*, so a copy that lands before the watcher has
    # registered is never stored and re-copying the same bytes would not be a
    # change. Each attempt is a new selection, so the first one after the
    # watcher is up gets stored — no sleep-and-hope.
    MARKER=''
    tries=40
    while (( tries-- > 0 )); do
        printf 'forest-shell watcher-marker-140 %s' "$tries" | nested_env wl-copy
        if env XDG_CACHE_HOME="$SCRATCH/cache" cliphist list 2>/dev/null \
                | grep -qa 'watcher-marker-140'; then
            MARKER=1
            break
        fi
        sleep 0.1
    done
    if [[ -n "$MARKER" ]]; then
        nested_pass 'a copy reaches the history with no manual store — the watchers fill it'
    else
        nested_fail 'nothing the watchers should have stored reached the history'
    fi

    # The half the user sees: the provider lists what the watchers stored.
    clip_reenter
    if [[ "$(reply title ';watcher-marker-140' 0)" == *watcher-marker-140* ]]; then
        nested_pass 'the launcher lists the entry the watchers stored'
    else
        nested_fail "the launcher listed \"$(reply title ';watcher-marker-140' 0)\" for the stored entry"
    fi

    # Guarded on non-empty, and not for tidiness: bare `wait` waits for *every*
    # background job, which here is the nested compositor and the shell under
    # test — so an empty array turns a failing run into a hanging one. Measured:
    # the run that proved these checks go red hung until its timeout killed it.
    if (( ${#CLIP_WATCHERS[@]} > 0 )); then
        kill "${CLIP_WATCHERS[@]}" 2>/dev/null
        wait "${CLIP_WATCHERS[@]}" 2>/dev/null
    fi

    TEXT='forest-shell harness — git push --force-with-lease'
    printf '%s' "$TEXT" | clip_store
    clip_store < assets/noise.png
    clip_reenter

    if clip_settle 2; then
        nested_pass "the history was read: $(reply clipboardCount) entries"
    else
        nested_fail "the history never came back — count: $(reply clipboardCount)"
    fi

    if grep -qaE 'launcher: [0-9]+ clipboard entr(y|ies) listed' "$NESTED_SHELL_LOG"; then
        nested_pass 'the listing logs what it found'
    else
        nested_fail 'the listing was never logged'
    fi

    # The text entry, found by searching for part of it.
    if [[ "$(reply title ';force-with-lease' 0)" == "$TEXT" ]]; then
        nested_pass 'a query filters the history down to the entry'
    else
        nested_fail "a query for part of the entry found \"$(reply title ';force-with-lease' 0)\""
    fi

    if [[ -z "$(reply rows ';zzzzznothing')" ]]; then
        nested_pass 'a query that matches nothing returns nothing'
    else
        nested_fail 'a query that should match nothing returned rows'
    fi

    said=$(reply silence ';zzzzznothing')
    if [[ "$said" == *"zzzzznothing"* ]]; then
        nested_pass "a miss over a full history says: $said"
    else
        nested_fail "a miss over a full history said \"$said\" — that is the empty-history sentence"
    fi

    # The text round trip. Enter decodes the *entry*, never the preview — the
    # preview is truncated, and copying it would paste a mangled prefix while
    # reporting success.
    Quickshell_before=$(reply clipboard)
    if [[ "$(reply activate ';force-with-lease' 0)" == "true" ]]; then
        tries=40
        while (( tries-- > 0 )); do
            [[ "$(reply clipboard)" == "$TEXT" ]] && break
            sleep 0.1
        done
        if [[ "$(reply clipboard)" == "$TEXT" ]]; then
            nested_pass 'Enter puts the whole text entry back on the selection'
        else
            nested_fail "the clipboard holds \"$(reply clipboard)\", not the entry (was: $Quickshell_before)"
        fi
    else
        nested_fail 'Enter on a clipboard row was refused'
    fi

    # The image half. A row that says what it is, a thumbnail that decodes to a
    # real file, and an offer the compositor will hand out as image/png.
    IMAGE_ROW=$(reply title ';image' 0)
    if [[ "$IMAGE_ROW" == Image* ]]; then
        nested_pass "the stored PNG is listed as an image: $IMAGE_ROW"
    else
        nested_fail "the stored PNG listed as \"$IMAGE_ROW\""
    fi

    IMAGE_ID=$(prow ';image' 1 | sed 's/^clipboard://')
    if [[ -n "$IMAGE_ID" ]]; then
        tries=40
        THUMB=""
        while (( tries-- > 0 )); do
            THUMB=$(reply clipboardThumbnail "$IMAGE_ID")
            [[ -n "$THUMB" ]] && break
            sleep 0.1
        done
        THUMB_PATH="${THUMB#file://}"
        if [[ -s "$THUMB_PATH" ]]; then
            nested_pass "the thumbnail decoded to $THUMB_PATH"
        else
            nested_fail "no thumbnail decoded for entry $IMAGE_ID (got \"$THUMB\")"
        fi
    else
        nested_fail 'the image entry has no id to decode'
    fi

    if [[ "$(reply activate ';image' 0)" == "true" ]]; then
        tries=40
        while (( tries-- > 0 )); do
            nested_env wl-paste --list-types 2>/dev/null | grep -qa 'image/png' && break
            sleep 0.1
        done
        if nested_env wl-paste --list-types 2>/dev/null | grep -qa 'image/png'; then
            nested_pass 'Enter on an image offers it back as image/png'
        else
            nested_fail "the selection offers: $(nested_env wl-paste --list-types 2>/dev/null | tr '\n' ' ')"
        fi
    else
        nested_fail 'Enter on an image row was refused'
    fi
fi

# --- 25. nothing is fighting itself --------------------------------------------

if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops in the provider'
fi

# --- 26. a machine with no qalc and no cliphist ----------------------------------
#
# Last, because it restarts the shell and the restart truncates the log every
# check above reads.
#
# The PATH is a directory of symlinks to everything in /usr/bin except `qalc`
# and `cliphist` — rather than an empty one — so that the only things missing
# are the two providers' tools. A shell that lost every binary would fail this
# check for reasons that have nothing to do with #40 or #53.
#
# The clipboard half runs on every machine, including one where check 24 skipped
# the round trip for want of the binaries: the failure this asserts is produced
# on purpose rather than found. It is the ticket's second acceptance criterion —
# "the service degrades gracefully without cliphist" — and the shape it is
# guarding against is a history that reads as empty because the binary is not
# there, which is #78 with no error anywhere in it.

nested_kill_shell

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
rm -f "$NOQALC/qalc" "$NOQALC/cliphist"

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

    # And the same three questions for the clipboard.
    if nested_await "$NESTED_SHELL_LOG" 'launcher: no cliphist on PATH' 10; then
        nested_pass 'a missing cliphist is noticed at startup, not at the first `;`'
    else
        nested_fail 'the shell never noticed that cliphist is missing'
    fi

    if [[ "$(reply clipboardReady)" == "false" && "$(reply clipboardProbed)" == "true" ]]; then
        nested_pass 'the provider knows it is inert rather than merely empty'
    else
        nested_fail "the provider says ready=$(reply clipboardReady) probed=$(reply clipboardProbed)"
    fi

    said=$(reply silence ';')
    if [[ "$said" == *"not installed"* ]]; then
        nested_pass "a \`;\` with no cliphist says: $said"
    else
        nested_fail "a \`;\` with no cliphist said \"$said\" — an empty list is the #78 shape"
    fi

    if [[ -z "$(reply rows ';')" ]]; then
        nested_pass 'and shows no rows rather than inventing any'
    else
        nested_fail 'a missing cliphist produced rows'
    fi
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all launcher checks passed\n'
exit 0
