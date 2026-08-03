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
    # Guarded: `${call#*ipc call }` on a command that has no `ipc call` in it is
    # a no-op, and would silently hand the whole command line on as a target and
    # function name — a bind for a plain dispatcher would then fail four checks
    # with unreadable text instead of one with a clear reason.
    if [[ "$call" != *"ipc call "* ]]; then
        echo "$CONF: ${mods}+${key} is not an 'ipc call' bind — this harness only knows those" >&2
        exit 1
    fi
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
# the replacement. Sourced from the same data file the registration script uses,
# so the check and the registered value cannot drift apart.

# The value of FOREST_REPO does not matter to the sed-safety check — no path can
# introduce a `|` — but registration.env refuses to be sourced without one, so
# that a caller who does care cannot get an unresolved command by accident.
FOREST_REPO=$(pwd)
# shellcheck source=../integration/shell-switch/registration.env
source integration/shell-switch/registration.env
if [[ "$FOREST_LAUNCHER_CMD" == *"|"* || "$FOREST_LAUNCHER_CMD" == *"&"* ]]; then
    nested_fail "the registered launcher_cmd contains | or &, which shell-switch's sed cannot carry: $FOREST_LAUNCHER_CMD"
else
    nested_pass "the registered launcher_cmd is sed-safe (no | or &), so SUPER+Space needs no fallback"
fi

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

# Marked before the first call so the handler check below reads only what the
# binds produced — but not until startup has actually finished talking. The
# ready line nested_shell waits for is stage 2's, and stages keep logging after
# it: measured 37 ms and 29 lines between "settings window armed" and the last
# startup line, including a Wallpaper warning that has nothing to do with any
# bind. Marking at the ready line would attribute all of that to the first key.
settle() {
    local last=-1 now
    for _ in $(seq 1 40); do
        now=$(wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0)
        [[ "$now" == "$last" ]] && return 0
        last="$now"
        sleep 0.25
    done
}
settle
mark=$(wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0)

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

# Handlers that threw rather than returned. Exit status only proves the call was
# routed — a QML error inside the handler still unwinds to a 0 from the CLI, so
# the log is the only place it shows up. Read from the mark, so this is about
# the binds and not about anything startup already said.
raised=$(tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" 2>/dev/null \
    | grep -aE 'TypeError|ReferenceError|is not a function|Binding loop' | head -1)
if [[ -n "$raised" ]]; then
    nested_fail "a bind's handler raised: $raised"
else
    nested_pass 'no handler raised while every bind was exercised'
fi

# --- 7. the bar's other door: the global shortcut ----------------------------
#
# The bar (#70) is reachable two ways, and only one of them is a line in the
# file this harness parses. `bind = …, global, forest-shell:bar-toggle` costs no
# `qs` subprocess per press, and is offered over
# hyprland-global-shortcuts-v1 — so the compositor's own list is the evidence,
# the same way tools/drawer-harness.sh checks the launcher's. The binding in the
# user's hyprland.conf is their half and is not something this seam can write.

if nested_hyprctl globalshortcuts | grep -qa 'forest-shell:bar-toggle'; then
    nested_pass 'the compositor has the bar-toggle global shortcut'
else
    nested_fail 'hyprland was never offered a bar-toggle global shortcut'
fi

# And that a toggle says which of the three hide reasons decided the bar. #81
# was a lifecycle with no log line, and one bug then had two candidate causes
# for a week; with auto-hide, fullscreen and an explicit override all landing on
# one property, "the bar is not there" has to name the one that did it.

bar_line=$(tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" 2>/dev/null \
    | grep -aE 'bar: (toggle|shown|hidden|auto) ' | head -1)
if [[ "$bar_line" =~ (pinned|hover|linger|ipc|autohide|fullscreen) ]]; then
    nested_pass "the bar toggle named its reason: ${bar_line##* }"
else
    nested_fail 'the bar toggled without logging which reason decided it'
fi

# --- 4. and the fallback path, with the shell gone ---------------------------
#
# Deliberately the *same* nested session with its shell killed, rather than a
# call made before bring-up. An earlier draft ran this first, against
# `qs -c forest` — which resolves through the caller's own XDG_CONFIG_HOME, so
# the moment forest-shell became the daily driver this harness would have fired
# `lock lock` and `recorder toggle` at the real session. Seam 2's rule is that a
# harness never touches the session running it; killing the nested shell keeps
# the down-case contained and makes it a true "config present, nothing running"
# rather than "config not found".

nested_kill_shell
nested_note 'shell killed — checking the binds fall through'

for i in "${!CALLS[@]}"; do
    read -r target fn _ <<< "${CALLS[$i]}"
    # shellcheck disable=SC2086
    if nested_ipc call $target $fn > /dev/null 2>&1; then
        nested_fail "${CHORDS[$i]}: 'ipc call $target $fn' exited 0 with the shell dead — the fallback would never fire"
    else
        nested_pass "${CHORDS[$i]}: falls through to its fallback with the shell down"
    fi
done

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all bind checks passed\n'
exit 0
