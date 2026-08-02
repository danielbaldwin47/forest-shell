#!/usr/bin/env bash
# Run the idle ladder and the logind bridge inside a nested Hyprland (#48).
#
#   tools/idle-harness.sh          # run the checks, print PASS/FAIL, exit 0/1
#   tools/idle-harness.sh --keep   # leave the nested session up to poke at
#
# This is the second seam (CLAUDE.md). Every *rule* the ladder has is a pure
# function in `tests/tst_idlepolicy.qml` — the stage table, the AC/battery
# split, what freezes it, what blocks suspend. What only exists once a
# compositor does is here: an `IdleMonitor` that really fires against
# `ext-idle-notify-v1`, a `WlSessionLock` that really comes up, a logind delay
# inhibitor that is really held, and the ordering between the last two — which
# is the ticket's fourth acceptance criterion, and the only one that cannot be
# checked by reading the code.
#
# Two runs, because the two interesting states are mutually exclusive: once the
# ladder has locked the session there is no way back out of it without a
# password, and the sleep hook's whole point is what it does to an *unlocked*
# one.
#
#   run 1 — the ladder. It blanks the screen on its own timeout and puts it back
#           on the first keypress; an un-corked PipeWire stream holds the suspend
#           rung and nothing else; Keep Awake freezes every rung and releases
#           them again; editing settings.json re-arms it under the running
#           shell; and the lock rung really locks.
#   run 2 — the bridge, on a session run 1 is not around to have locked. The
#           delay inhibitor is held from startup, a sleep raises the lock first,
#           and the inhibitor is released only after the compositor confirms.
#
# ## What is deliberately not driven, and why
#
#   - **the dim rung.** The nested shell reads the host's `/sys`, so a real dim
#     in here would dim the screen of the session running the harness — the same
#     argument tools/osd-harness.sh makes about the host's PipeWire. The rung is
#     turned off in the scratch config and the check is that it says so.
#   - **`loginctl lock-session`.** The nested shell inherits `XDG_SESSION_ID`,
#     so that command would lock the *real* session, which is what this whole
#     seam exists to avoid. What routes through it is the session menu's Lock
#     (Services/System/LogindBridge.qml), and it is real-session work.
#   - **a real suspend.** `system.session.commands.suspend` is `true` in the
#     scratch config, so the last rung runs a no-op binary. What is checked is
#     the order of the steps before it, not that systemd works.
#
# What no seam covers, recorded rather than claimed: an actual DPMS blank, an
# actual suspend and a lid switch are real-session work, and so is "two outputs,
# neither of them left unlocked" (#98).
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

idle() { nested_ipc call idle "$@"; }
logind() { nested_ipc call logind "$@"; }
keepawake() { nested_ipc call keepawake "$@"; }

# The log is append-only and the shell is restarted once, so "did this call do
# anything" is always a question about what arrived *after* it.
log_lines() { wc -l < "$NESTED_SHELL_LOG" 2>/dev/null || echo 0; }
since() { tail -n "+$(($1 + 1))" "$NESTED_SHELL_LOG" 2>/dev/null; }

expect_since() {
    local mark="$1" pattern="$2" what="$3" ticks="${4:-60}"
    for _ in $(seq 1 "$ticks"); do
        if since "$mark" | grep -qaE "$pattern"; then
            nested_pass "$what"
            return 0
        fi
        sleep 0.1
    done
    nested_fail "$what — nothing matching /$pattern/ since the call"
    return 1
}

expect_reply() {
    local got="$1" want="$2" what="$3"
    if [[ "$got" == "$want" ]]; then
        nested_pass "$what"
    else
        nested_fail "$what — expected '$want', got '$got'"
    fi
}

## Assert two lines arrived in this order. The whole point of the sleep hook: a
## log holding both lines in the wrong order is a machine that slept and then
## locked.
expect_order() {
    local mark="$1" first="$2" second="$3" what="$4"
    local tail_lines first_at second_at
    tail_lines=$(since "$mark")
    first_at=$(grep -naE "$first" <<< "$tail_lines" | head -1 | cut -d: -f1)
    second_at=$(grep -naE "$second" <<< "$tail_lines" | head -1 | cut -d: -f1)

    if [[ -z "$first_at" ]]; then
        nested_fail "$what — /$first/ never appeared"
    elif [[ -z "$second_at" ]]; then
        nested_fail "$what — /$second/ never appeared"
    elif (( first_at < second_at )); then
        nested_pass "$what"
    else
        nested_fail "$what — /$second/ came first (lines $second_at then $first_at)"
    fi
}

## A fresh compositor, not just a fresh shell.
##
## `ext-session-lock-v1` keeps the screen locked when the client dies without
## unlocking — that is the protocol's whole point, and it is what the lock
## surface's `secure` reports (#47). So a nested Hyprland whose shell locked and
## was then killed stays locked forever, and the next shell to ask for a lock in
## there gets `wl_display error 0: invalid object` and dies with it. Run 1 ends
## locked; run 2 therefore starts a compositor of its own.
restart_session() {
    nested_kill_shell
    [[ -n "$NESTED_HYPR_PID" ]] && kill "$NESTED_HYPR_PID" 2>/dev/null
    wait "$NESTED_HYPR_PID" 2>/dev/null
    nested_up || return 1
}

nested_up || exit 1

SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")
SETTINGS="$SCRATCH/config/forest-shell/settings.json"

## Timeouts in minutes, as the schema takes them: 0.05 is three seconds. The dim
## rung is off — it would dim the host's panel — and both commands that would
## touch the machine are `true`. `$1` is whether the lock rung is armed, which
## run 1 turns on halfway through and run 2 leaves off.
write_settings() {
    cat > "$SETTINGS" <<EOF
{
  "system": {
    "session": { "commands": { "suspend": "true" } },
    "idle": {
      "dim": { "enabled": false },
      "lock": { "enabled": $1, "battery": 0.02, "ac": 0.02 },
      "dpms": { "enabled": true, "battery": 0.05, "ac": 0.05,
                "offCommand": "true", "onCommand": "true" },
      "suspend": { "enabled": false, "battery": 0, "ac": 0 }
    }
  }
}
EOF
}

write_settings false
nested_shell shell.qml 'idle: ladder armed' || exit 1

# --- 1. the ladder is the configured one -------------------------------------

if grep -qaE 'idle: ladder armed \(ipc target: idle\) — ladder on (ac|battery): dim off \(turned off\), lock off \(turned off\), dpms 3s, suspend off' \
        "$NESTED_SHELL_LOG"; then
    nested_pass 'the ladder is read from settings.json rung by rung, with the reason each off one is off'
else
    nested_fail "the startup line is not the configured ladder: \
$(grep -a 'ladder armed' "$NESTED_SHELL_LOG" | head -1)"
fi

# Which column of #30's table this machine is on. Reported rather than asserted:
# a desktop is always on the AC ladder, and that is the correct reading of "no
# battery" rather than a failure.
nested_note "power source: $([[ "$(idle onBattery)" == 'true' ]] && echo battery || echo ac)"

# --- 2. a rung really fires, and activity really undoes it -------------------
#
# Nothing sends the nested session any input until this script does, so it is
# idle from the moment it comes up: what fires here is the real
# `ext-idle-notify-v1` path on its real three-second timeout, not an IPC call
# standing in for one.

expect_since 0 'idle: idle: dpms — screen off' \
    'the dpms rung fires on its own timeout, against the real idle protocol' 120
expect_reply "$(idle isBlanked)" 'true' 'and the shell knows the screen is off'

# The *undo* is checked here; what cannot be checked here is real input driving
# it. Measured while building this: nothing a script can send resets
# `ext-idle-notify-v1` in a nested session — `dispatch sendshortcut` is
# synthesised straight into the focused client's keyboard, and `dispatch
# movecursor` warps the pointer, so both bypass the input path that feeds the
# idle notifier. A real keypress on a real session is what the protocol is for,
# and it is the one part of this rung that stays real-session work. It is also
# why the order of the checks below is what it is: the monitor stays idle for
# the rest of the run, so each rung fires once on its own and is driven through
# the door after that.
mark=$(log_lines)
idle wake > /dev/null
expect_since "$mark" 'idle: activity: dpms — screen on \(ipc\)' \
    'the screen comes back, and the line says what brought it back'
expect_reply "$(idle isBlanked)" 'false' 'and the shell knows the screen is on'

# --- 3. the audio gate, on the suspend rung and nothing else -----------------
#
# The nested session shares the host's PipeWire, so this plays *silence* into
# the host's default sink for as long as pw-cat runs: audible to nobody, and an
# un-corked output stream to PipeWire, which is what #30's gate is written
# against.

PW_PID=""
if command -v pw-cat > /dev/null && [[ "$(idle isPlaying)" == 'false' ]]; then
    pw-cat --playback --rate 48000 --channels 2 --format s16 --raw /dev/zero \
        > /dev/null 2>&1 &
    PW_PID=$!
    for _ in $(seq 1 40); do
        [[ "$(idle isPlaying)" == 'true' ]] && break
        sleep 0.1
    done
fi

if [[ -n "$PW_PID" ]] && [[ "$(idle isPlaying)" == 'true' ]]; then
    nested_pass 'an un-corked output stream reads as audio playing'

    mark=$(log_lines)
    idle fire suspend > /dev/null
    expect_since "$mark" 'idle: suspend held off — audio is playing' \
        'the suspend rung is held off while something is playing, and says why'

    # The gate is on that rung alone: the screen still blanks under the music.
    mark=$(log_lines)
    idle fire dpms > /dev/null
    expect_since "$mark" 'idle: idle: dpms — screen off' \
        'the screen still blanks while audio plays — the gate is on suspend only'

    kill "$PW_PID" 2>/dev/null
    wait "$PW_PID" 2>/dev/null
    PW_PID=""
    for _ in $(seq 1 40); do
        [[ "$(idle isPlaying)" == 'false' ]] && break
        sleep 0.1
    done
    expect_reply "$(idle isPlaying)" 'false' 'and the gate clears when it stops'
else
    nested_note 'no pw-cat, or the host was already playing — the audio gate is not driven here'
    idle fire dpms > /dev/null
fi

# --- 4. Keep Awake freezes the whole ladder ----------------------------------
#
# Pressed at a blanked screen — the rung above left it that way — so this also
# checks the other half: freezing the ladder undoes what the ladder has already
# done, because a Keep Awake pressed at a dark screen is somebody asking for
# their screen back.

expect_reply "$(idle isBlanked)" 'true' 'the screen is off going into this'
mark=$(log_lines)
keepawake set true > /dev/null
expect_since "$mark" 'idle: activity: dpms — screen on \(keep awake\)' \
    'freezing the ladder puts the screen back on'
expect_since "$mark" 'idle: ladder frozen — keep awake is on' 'Keep Awake freezes the ladder'
expect_since "$mark" 'idle: ladder on (ac|battery): dim off \(keep awake\), lock off \(keep awake\), dpms off \(keep awake\), suspend off \(keep awake\)' \
    'every rung says it was keep awake that turned it off'
expect_reply "$(idle isFrozen)" 'true' 'the shell reports the ladder frozen'

# Nothing fires while it is frozen — the dpms rung is three seconds and this
# waits longer than that.
mark=$(log_lines)
sleep 5
if since "$mark" | grep -qa 'idle: idle:'; then
    nested_fail "a rung fired under a frozen ladder: $(since "$mark" | grep -a 'idle: idle:' | head -1)"
else
    nested_pass 'no rung fires while the ladder is frozen'
fi

mark=$(log_lines)
keepawake set false > /dev/null
expect_since "$mark" 'idle: ladder released — keep awake is off' 'and turning it off releases the ladder'
expect_since "$mark" 'idle: idle: dpms — screen off' \
    'the ladder starts counting again the moment it is released' 120
idle wake > /dev/null

# --- 5. editing settings.json re-arms the ladder under the running shell -----
#
# "Timeout configurable" is only true if it is configurable *now*: a ladder that
# had to be restarted into is one nobody would tune.

mark=$(log_lines)
write_settings true
expect_since "$mark" 'idle: ladder on (ac|battery): dim off \(turned off\), lock 1s, dpms 3s' \
    'editing settings.json re-arms the ladder without a restart' 120

# --- 6. and the lock rung really locks ---------------------------------------

expect_since "$mark" 'idle: idle: lock' 'the lock rung fires on its own timeout' 120
expect_since "$mark" 'lock: locking \(idle\)' 'and the reason recorded on the lock is the ladder'
expect_since "$mark" 'lock: compositor confirms all screens covered' \
    'the compositor confirms every screen is covered' 150

# --- 7. run 2: the sleep hook, on a session nothing has locked ---------------
#
# The delay inhibitor is real — `systemd-inhibit --mode=delay` against the
# caller's own logind — and so is the lock. What is simulated is only logind's
# `PrepareForSleep`, driven through the same `sleep()` the helper's `sleep` line
# calls, because the alternative is suspending the machine running the tests.

restart_session || exit 1
SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")
SETTINGS="$SCRATCH/config/forest-shell/settings.json"
write_settings false
nested_shell shell.qml 'idle: ladder armed' || exit 1

# Settled first, and not for tidiness: a lock raised while the shell is still
# building its surfaces takes the whole shell down in here — `wl_display error
# 0: invalid object`, the nested-backend artefact #81 could not rule out. On a
# real session the lock is raised minutes into a session, never milliseconds.
nested_await "$NESTED_SHELL_LOG" 'startup: stage interactive' 20 \
    || nested_note 'the shell never said it was interactive'
sleep 2

expect_since 0 'logind: bridge listening' 'the logind bridge helper is running' 100
expect_since 0 'logind: helper: watching /org/freedesktop/login1' \
    'and it says which session it is watching'
expect_reply "$(logind isInhibiting)" 'true' \
    'the sleep delay inhibitor is held — and reported held only because it took'

mark=$(log_lines)
logind sleep > /dev/null

expect_since "$mark" 'logind: sleep requested — locking first' \
    'a sleep on an unlocked session locks first, and says so'
expect_since "$mark" 'lock: locking \(sleep\)' 'the lock records that a sleep asked for it'
expect_since "$mark" 'logind: sleep inhibitor released' \
    'the delay inhibitor is let go, one way or the other' 100

# Which way it went, and both are correct answers. The fast path is the one a
# real session takes; the ceiling is the one this seam usually takes, because
# the nested compositor's `secure` arrives about five seconds after the lock —
# it never presents a frame (#85), and that is the delay showing through. The
# failure this is looking for is neither: an inhibitor let go before the lock
# was even raised.
if since "$mark" | grep -qaE 'logind: lock confirmed after [0-9]+ms — releasing'; then
    nested_pass 'the inhibitor was released on the compositor confirming the lock'
    expect_order "$mark" 'lock: compositor confirms all screens covered' \
        'logind: sleep inhibitor released' \
        'the screens were covered before the sleep lock was let go — a suspend cannot land unlocked'
elif since "$mark" | grep -qa 'the compositor did not confirm the lock within'; then
    nested_note 'the nested compositor took longer than the ceiling to confirm `secure` (#85)'
    nested_pass 'the ceiling expired and the shell said so, rather than being overruled in silence'
    expect_order "$mark" 'lock: locking \(sleep\)' 'logind: sleep inhibitor released' \
        'the lock was raised before the sleep lock was let go'
else
    nested_fail 'the inhibitor was released without either confirming the lock or giving up on it'
fi

for _ in $(seq 1 50); do
    [[ "$(logind isInhibiting)" == 'false' ]] && break
    sleep 0.1
done
expect_reply "$(logind isInhibiting)" 'false' 'and the shell knows it let go'

# The lock is up and PAM is open; if that took the shell down, everything after
# this is a client error rather than a failed assertion (#81, tools/lock-harness.sh).
if kill -0 "$NESTED_SHELL_PID" 2>/dev/null; then
    nested_pass 'the shell survived locking on the way to sleep'
else
    nested_fail "the shell died while locking for sleep — \
$(grep -aiE 'wayland|fatal' "$NESTED_SHELL_LOG" | tail -2)"
fi

# --- 8. and it takes the lock again on the way back --------------------------

mark=$(log_lines)
logind resume > /dev/null
expect_since "$mark" 'logind: logind resumed the session' 'the resume is heard'
expect_since "$mark" 'logind: sleep inhibitor held \(delay, what=sleep\)' \
    'resuming takes the delay inhibitor again — the second suspend of a session waits too'
expect_reply "$(logind isInhibiting)" 'true' 'and it reports itself holding one again'

# --- 8b. and the second sleep takes the fast path ----------------------------
#
# The same hook with the lock already up and already confirmed: this is the
# branch a real session takes on every suspend after the first, and it is the
# one that shows the release is gated on the confirmation rather than on a
# timer.

mark=$(log_lines)
logind sleep > /dev/null
expect_since "$mark" 'logind: sleep requested — already locked' \
    'a sleep on a locked session does not lock twice'
expect_since "$mark" 'logind: lock confirmed after [0-9]+ms — releasing the sleep inhibitor' \
    'and lets the inhibitor go on the confirmation it already has'
logind resume > /dev/null

# --- 9. nothing is fighting itself -------------------------------------------

if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops while the ladder ran'
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all idle ladder checks passed\n'
exit 0
