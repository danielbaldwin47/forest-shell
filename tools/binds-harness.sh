#!/usr/bin/env bash
# Every Hyprland bind forest-shell ships, driven against a real shell (#57).
#
#   tools/binds-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/binds-harness.sh --keep   # leave the nested session up to poke at
#
# #57's third acceptance criterion is "binds degrade to fallbacks with the shell
# down; compositor stays usable". That is two claims, and only one of them is
# the obvious one:
#
#   1. with the shell down, `qs … ipc call` must fail, so `||` reaches the
#      fallback. Cheap to check, and true by inspection.
#   2. with the shell *up*, the same call must succeed — because `||` runs the
#      fallback on *any* non-zero exit. A call that returns non-zero from a live
#      shell fires the fallback on top of it: press lock and you get the shell's
#      lock surface *and* `loginctl lock-session`. That failure is invisible in
#      the down case and impossible to see without a compositor, so it lands
#      here rather than in `tests/`.
#
# The bind file is the input, not a copy of it. Every check below is generated
# by parsing integration/hyprland/forest-binds.conf, so a bind added there
# without a fallback, or pointing at an IPC function that does not exist, fails
# this harness instead of failing silently under someone's fingers.
#
# What it asserts, per bind:
#
#   1. the command has a `|| <fallback>` at all
#   2. the target and function it names are really on the shell's IPC surface
#   3. the call exits 0 against a live shell, so the fallback does not double-fire
#   4. the call exits non-zero once the shell is gone, so the fallback does
#
# and once, for the file as a whole:
#
#   5. no bind here is SUPER+Space — that one belongs to shell-switch
#   6. the launcher command shell-switch is registered with contains no `|`,
#      which is why SUPER+Space is the one bind that cannot have a fallback
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

CONF="integration/hyprland/forest-binds.conf"
[[ -f "$CONF" ]] || { echo "no bind file at $CONF" >&2; exit 1; }

# --- parse the shipped bind file --------------------------------------------
#
# Hyprland's grammar is `bind = MODS, key, dispatcher, args…`, and only the
# first three commas are structural — everything after them is the command,
# commas and all. So the split is exactly three times, never on the rest.

CHORDS=()   # "SUPER SHIFT+L", for naming checks
CALLS=()    # "lock lock", the target and function
CMDS=()     # the whole command, for the fallback checks

while IFS= read -r line; do
    [[ "$line" == bind\ =\ * ]] || continue
    rest="${line#bind = }"

    mods="${rest%%,*}";  rest="${rest#*,}"
    key="${rest%%,*}";   rest="${rest#*,}"
    _disp="${rest%%,*}"; cmd="${rest#*,}"

    # Trim the space Hyprland conventionally puts after each comma.
    key="${key# }"; cmd="${cmd# }"

    CHORDS+=("${mods}+${key}")
    CMDS+=("$cmd")

    call="${cmd%%||*}"                  # drop the fallback
    call="${call#*ipc call }"            # drop `qs -c forest ipc call`
    call="${call%"${call##*[![:space:]]}"}"   # rstrip
    CALLS+=("$call")
done < "$CONF"

(( ${#CALLS[@]} )) || { echo "parsed no binds out of $CONF" >&2; exit 1; }

# --- 5. SUPER+Space is not ours ----------------------------------------------
#
# shell-switch regenerates its own binds file wholesale on every switch and owns
# SUPER+Space there. A duplicate here would either be overridden or fight it,
# depending on source order, which is the kind of thing that is only ever
# noticed by someone whose launcher stopped opening.

space_bind=""
for i in "${!CHORDS[@]}"; do
    [[ "${CHORDS[$i]}" == *"+Space" || "${CHORDS[$i]}" == *"+space" ]] && space_bind="${CHORDS[$i]}"
done
if [[ -n "$space_bind" ]]; then
    nested_fail "$CONF binds $space_bind — SUPER+Space belongs to shell-switch"
else
    nested_pass "the bind file leaves SUPER+Space to shell-switch"
fi

# --- 1. every bind here has a fallback ---------------------------------------

for i in "${!CMDS[@]}"; do
    if [[ "${CMDS[$i]}" == *"||"* ]]; then
        nested_pass "${CHORDS[$i]} has a fallback"
    else
        nested_fail "${CHORDS[$i]} has no '|| fallback' — it goes silent with the shell down"
    fi
done

# --- 6. the launcher command stays sed-safe ----------------------------------
#
# shell-switch interpolates it with `sed -e "s|{{LAUNCHER_CMD}}|${cmd}|g"`, so a
# `|` in the value breaks the expression and an `&` means "the whole match" in
# the replacement. Read out of the registration script rather than restated, so
# the two cannot drift.

LAUNCHER_CMD=$(sed -n 's/^FOREST_LAUNCHER_CMD=//p' tools/register-shell-switch.sh | tr -d '"' | head -1)
if [[ -z "$LAUNCHER_CMD" ]]; then
    nested_fail "could not read FOREST_LAUNCHER_CMD out of tools/register-shell-switch.sh"
elif [[ "$LAUNCHER_CMD" == *"|"* || "$LAUNCHER_CMD" == *"&"* ]]; then
    nested_fail "the registered launcher_cmd contains | or &, which shell-switch's sed cannot carry: $LAUNCHER_CMD"
else
    nested_pass "the registered launcher_cmd is sed-safe (no | or &), so SUPER+Space needs no fallback"
fi

# --- 4. down first: the fallback path ----------------------------------------
#
# Run before the shell exists rather than after killing it, so this is the real
# "nothing is running" case and not a race with a dying process. `-c forest`
# is the form the binds actually use.

QS=$(qs_runtime_bin) || exit 1
for i in "${!CALLS[@]}"; do
    read -r target fn _ <<< "${CALLS[$i]}"
    # shellcheck disable=SC2086
    if "$QS" -c forest ipc call $target $fn > /dev/null 2>&1; then
        nested_fail "${CHORDS[$i]}: 'ipc call $target $fn' exited 0 with no shell running — the fallback would never fire"
    else
        nested_pass "${CHORDS[$i]}: falls through to its fallback with the shell down"
    fi
done

# --- bring one up ------------------------------------------------------------

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

nested_shell shell.qml 'settings window armed' || exit 1

# --- 2. every bind names something the shell actually exposes ----------------

SURFACE=$(nested_ipc show 2>&1)
for i in "${!CALLS[@]}"; do
    read -r target fn _ <<< "${CALLS[$i]}"
    if sed -n "/^target $target\$/,/^target /p" <<< "$SURFACE" | grep -qa "function $fn("; then
        nested_pass "${CHORDS[$i]}: $target.$fn() is on the IPC surface"
    else
        nested_fail "${CHORDS[$i]}: the shell exposes no $target.$fn() — this bind can only ever run its fallback"
    fi
done

# --- 3. and succeeds against a live shell ------------------------------------
#
# The check the whole harness exists for. A non-zero exit here means `||` runs
# the fallback *as well as* the shell's own handler.

for i in "${!CALLS[@]}"; do
    read -r target fn _ <<< "${CALLS[$i]}"
    # shellcheck disable=SC2086
    reply=$(nested_ipc call $target $fn 2>&1); rc=$?
    if (( rc == 0 )); then
        nested_pass "${CHORDS[$i]}: $target.$fn() exits 0 on a live shell — no double fire"
    else
        nested_fail "${CHORDS[$i]}: $target.$fn() exited $rc on a live shell, so the fallback fires too: $reply"
    fi
done

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all bind checks passed\n'
exit 0
