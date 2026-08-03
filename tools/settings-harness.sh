#!/usr/bin/env bash
# Open, drive and close the settings window inside a nested Hyprland (#77).
#
#   tools/settings-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/settings-harness.sh --keep   # leave the nested session up to poke at
#
# The window's only door until the control centre (#45) and the launcher (#40)
# land is `qs ipc call settings …`, and #77 was two holes in it: the documented
# invocation did nothing, and once open the window could not be touched from the
# keyboard at all. Neither is checkable from `tests/` — one is an IPC round trip
# and the other needs a compositor to hold focus — so both land here, at the
# second seam.
#
# What it asserts:
#
#   1. `ipc call settings open` opens the window
#   2. `ipc call settings showTab <tab>` opens on that tab, argument intact
#   3. `show` is not on the target's surface, because it cannot be called
#   4. an unknown tab id still opens the window, on the first tab
#   5. a second call raises rather than opening a second window
#   6. `ipc call settings close` closes it, and says why
#   7. Escape inside the window closes it, and says why
#   8. the tab rail answers the arrow keys
#   9. the rail is one tab stop, so Tab reaches the page
#  10. a switch can be toggled with Space, and writes sparsely
#  11. that write keeps keys the schema has never heard of (#64's claim)
#
# The shell under test runs against a scratch XDG_CONFIG_HOME and
# XDG_STATE_HOME: the last two checks press keys at a real settings window, and
# a harness that edits the settings of the session running it is one nobody will
# run twice.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call settings "$@"; }

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

## Send a key until the window answers it, or give up.
##
## A newly mapped toplevel does not have the compositor's keyboard focus for the
## first moment of its life, and `sendshortcut` into a window that does not have
## it is silently a no-op. Polling on the evidence is the same shape as every
## other wait in this seam, and it is what keeps the check from being a sleep
## long enough to be slow and short enough to be flaky.
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

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

# Seeded before the shell has ever read the file: a key no schema knows about,
# next to a hand-set known one. #64 claims a GUI write preserves what it does
# not recognise, and #73 could not test it — an unknown key survived every hand
# edit there, but no GUI write ever landed on top of one, which is the only case
# that can lose it. Check 11 reads both back after the keyboard has written.
#
# `wallpaper.path` is the known key, deliberately not one of the three the
# sparse-write check greps for, and deliberately not in the subtree the switch
# writes to.
cat > "$SCRATCH/config/forest-shell/settings.json" <<'EOF'
{
  "wallpaper": { "path": "/nonexistent/hand-set.png" },
  "somethingTheSchemaHasNeverHeardOf": { "kept": true, "count": 7 }
}
EOF

nested_shell shell.qml 'settings window armed' || exit 1

# --- 1. the door -------------------------------------------------------------

mark=$(log_lines)
ipc open > /dev/null
expect_since "$mark" 'settings: window opened' 'ipc call settings open opens the window'

# --- 2. a tab, as an argument ------------------------------------------------

mark=$(log_lines)
reply=$(ipc showTab notifications)
expect_since "$mark" 'settings: window (opened|raised) \(tab notifications\)' \
    'ipc call settings showTab notifications selects that tab'

if grep -qa 'not expected' <<< "$reply"; then
    nested_fail "the tab argument never reached the shell: $reply"
else
    nested_pass 'the tab argument reaches the shell'
fi

# --- 3. `show` is not on the surface -----------------------------------------
#
# The name is unusable from the CLI whatever it does in QML: `qs ipc call
# settings show` is parsed as the `ipc show` subcommand and prints the target
# listing, exit 0, without calling anything. A `show` on the handler would put
# that name in front of everybody in exactly the listing they read it from.

if nested_ipc show | sed -n '/^target settings$/,/^target /p' | grep -qa 'function show('; then
    nested_fail 'the settings target advertises show(), which the CLI cannot call'
else
    nested_pass 'the settings target does not advertise an uncallable show()'
fi

# Upstream's behaviour, recorded rather than asserted: if a later Quickshell
# stops swallowing the token, this note is where to start putting `show` back.
if ipc show 2>&1 | grep -qa 'function '; then
    nested_note "'ipc call settings show' still prints the target listing (upstream CLI collision)"
fi

# --- 4. an unknown tab still opens the window --------------------------------

mark=$(log_lines)
ipc showTab nonesuch > /dev/null
expect_since "$mark" 'settings: window (opened|raised) \(tab appearance\)' \
    'an unknown tab id opens the first tab rather than nothing'

# --- 5. a second call raises rather than reopening ---------------------------

mark=$(log_lines)
ipc open > /dev/null
expect_since "$mark" 'settings: window raised' 'open on an open window raises it'

# --- 6. close over IPC -------------------------------------------------------

mark=$(log_lines)
ipc close > /dev/null
expect_since "$mark" 'settings: window closed \(ipc\)' \
    'ipc call settings close closes the window'

# --- 7. Escape ---------------------------------------------------------------

mark=$(log_lines)
ipc open > /dev/null
expect_since "$mark" 'settings: window opened' 'the window is open again for the key checks'

mark=$(log_lines)
key_until escape "$mark" 'settings: window closed \(escape\)' \
    'Escape closes the window from the keyboard'

# --- 8. the tab rail answers the arrow keys ----------------------------------
#
# Focus starts on the selected rail item, so one Down is one tab — and
# selection follows focus, which is what the log line records.

mark=$(log_lines)
ipc showTab appearance > /dev/null
expect_since "$mark" 'settings: window opened \(tab appearance\)' \
    'the window reopens on the appearance tab'

mark=$(log_lines)
key_until down "$mark" 'settings: tab selected \(bar\)' \
    'Down on the tab rail moves to the next tab'

mark=$(log_lines)
key_until up "$mark" 'settings: tab selected \(appearance\)' \
    'Up moves back'

# --- 9. the rail is one tab stop, not ten ------------------------------------
#
# Tab once and press Space. The first control on the Appearance tab is the
# theming-mode chip that is already selected, so a Space that reached the page
# writes nothing and says nothing — whereas a Space still on the rail would
# select another tab and log it. Ten stops would put nine keypresses between the
# window opening and the first setting on it.

mark=$(log_lines)
nested_key tab; sleep 0.5
nested_key space; sleep 0.8
if since "$mark" | grep -qa 'settings: tab selected'; then
    nested_fail 'one Tab did not leave the rail — it moved to another rail row'
else
    nested_pass 'one Tab leaves the rail for the page'
fi

# --- 10. a setting can be changed with no pointer at all ---------------------
#
# The end of the keyboard path, and the check the rest of it exists for: Tab off
# the rail into the page, Tab to the Dark mode switch, Space. #73 could not
# verify its own "edits move settings.json sparsely" criterion without a
# synthetic pointer, which is a fair sign of how load-bearing this is for
# testing as well as for use.

SETTINGS_FILE="$SCRATCH/config/forest-shell/settings.json"

# Tab until the switch answers, rather than counting stops to it.
#
# The count is not a constant: an inert chip is not a focus stop
# (Surfaces/Settings/Controls/Chip.qml — `activeFocusOnTab: root.available`), so
# the theming-mode row above this switch is two stops on a machine without
# matugen and three on one with it (#59), where the full-dynamic chip is live.
# A hard-coded Tab count therefore passes on whichever machine it was written on
# and fails on the other, which is a harness reporting the tester's laptop.
#
# Space on a chip is harmless here — it selects a theming mode in a scratch
# config — and the loop stops at the *first* Space that writes `darkMode`, so
# the toggle is never pressed twice and the key is never toggled back (#21).
wrote=0
for _ in 1 2 3 4; do
    nested_key tab; sleep 0.5
    nested_key space; sleep 0.6
    if grep -qa '"darkMode": *false' "$SETTINGS_FILE" 2>/dev/null; then
        wrote=1
        break
    fi
done

if (( wrote )); then
    nested_pass 'Space on a focused switch writes the setting'
else
    nested_fail "Space did not write the setting (file: $(tr -d '\n' < "$SETTINGS_FILE" 2>/dev/null))"
fi

# Sparse, still: the keyboard goes through the same `Config.set` the pointer
# does, so one edit is one key in the file and nothing else.
if grep -qa 'bar\|launcher\|notifications' "$SETTINGS_FILE"; then
    nested_fail "the keyboard edit wrote more than it touched: $(tr -d '\n' < "$SETTINGS_FILE")"
else
    nested_pass 'the keyboard edit wrote one key and nothing else'
fi

# --- 11. a GUI write does not eat what it does not understand ----------------
#
# #64 claims settings.json keeps keys the schema has never heard of. #73 left it
# untested with the exact reason it matters: an unknown key survived every hand
# edit, but no GUI write had ever landed on top of one, and a write is where a
# schema-shaped serializer drops what it cannot name. The keyboard has just
# written `appearance.darkMode` over a file seeded with both an unknown subtree
# and a hand-set `wallpaper.path`.

if grep -qa 'somethingTheSchemaHasNeverHeardOf' "$SETTINGS_FILE"; then
    nested_pass 'the GUI write kept a key no schema knows about'
else
    nested_fail "the GUI write dropped the unknown key: $(tr -d '\n' < "$SETTINGS_FILE")"
fi

if grep -qa 'hand-set.png' "$SETTINGS_FILE"; then
    nested_pass 'the GUI write kept the hand-set key it did not touch'
else
    nested_fail "the GUI write dropped a hand-set key: $(tr -d '\n' < "$SETTINGS_FILE")"
fi

# --- 12. nothing in the window is fighting itself ----------------------------
#
# #80's fix gives the row's control slot a ceiling and lets the control read it,
# which is the shape a binding loop comes from if the control's width is ever
# computed back off the slot's. A loop is a warning, not a failure, so it would
# otherwise pass unnoticed until the row visibly flickered.

if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops while the window was open'
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all settings-window checks passed\n'
exit 0
