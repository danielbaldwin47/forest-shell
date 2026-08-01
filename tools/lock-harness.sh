#!/usr/bin/env bash
# Engage the lock inside a nested Hyprland and assert it is answerable (#81).
#
# The failure this exists for cost a session every time it was tested: a lock
# that will not authenticate can only be escaped by killing the compositor. So
# nothing here touches the running session. A second Hyprland is started as a
# window inside it, the shell's lock runs in *that*, and a lock that will not
# open is closed with `kill`.
#
#   tools/lock-harness.sh            # run the checks, print PASS/FAIL, exit 0/1
#   tools/lock-harness.sh --keep     # leave the nested session up afterwards,
#                                    # for typing at it by hand
#   tools/lock-harness.sh --attempt  # also send one wrong password to real PAM
#
# What it asserts, in the order the lock does them:
#
#   1. Enter with no conversation says so, instead of going quiet
#   2. the compositor confirms every screen is covered (`secure`)
#   3. a PAM conversation actually opens, and prompts
#   4. the shell survives opening it
#   5. the field can hear a keyboard
#
# None of that answers a prompt, and that is deliberate. The lock authenticates
# against the system `login` stack, so a wrong password sent from here is a
# wrong password against your real account: three of them and pam_faillock locks
# you out for `unlock_time`, on the very machine you are debugging a lock screen
# on. `--attempt` sends exactly one, for when the full round trip is what you
# need — it costs a faillock try and says so.
#
# A successful unlock is the one thing a script cannot check, because it needs
# the password. `--keep` leaves the nested session up to type into by hand.
set -uo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly HARNESS_QML="$ROOT/lock-harness.qml"
readonly WORK="${TMPDIR:-/tmp}/forest-lock-harness.$$"
readonly QS="${QS_BIN:-qs-upstream}"
readonly WRONG_PASSWORD="definitely-not-the-password-$$"

KEEP=0
ATTEMPT=0
for arg in "$@"; do
    case "$arg" in
        --keep)    KEEP=1 ;;
        --attempt) ATTEMPT=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

mkdir -p "$WORK"
HYPR_LOG="$WORK/hyprland.log"
SHELL_LOG="$WORK/shell.log"
NESTED_DISPLAY=""
HYPR_PID=""
SHELL_PID=""

fail_count=0
pass()  { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail_count=$((fail_count + 1)); }
note()  { printf '  ....  %s\n' "$1"; }

cleanup() {
    if (( KEEP )); then
        printf '\nnested session left up:\n  WAYLAND_DISPLAY=%s\n  logs: %s\n' \
            "$NESTED_DISPLAY" "$WORK"
        printf '  kill it with: kill %s %s\n' "$SHELL_PID" "$HYPR_PID"
        return
    fi
    [[ -n "$SHELL_PID" ]] && kill "$SHELL_PID" 2>/dev/null
    [[ -n "$HYPR_PID"  ]] && kill "$HYPR_PID"  2>/dev/null
    wait 2>/dev/null
}
trap cleanup EXIT

# Wait for a line to appear in a log, or give up. Every wait in this script is
# a poll on evidence rather than a sleep, so the run is as fast as the lock is
# and does not go flaky on a slow machine.
await_log() {
    local file="$1" pattern="$2" timeout="${3:-10}"
    local ticks=$(( timeout * 10 ))
    for _ in $(seq 1 "$ticks"); do
        grep -qaE "$pattern" "$file" && return 0
        sleep 0.1
    done
    return 1
}

qs_nested() {
    env -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY="$NESTED_DISPLAY" \
        "$QS" -p "$HARNESS_QML" "$@"
}

ipc() { qs_nested ipc call "$@" 2>&1; }

# --- bring up the nested compositor ---------------------------------------

cat > "$WORK/hyprland.conf" <<'EOF'
monitor = WL-1, 1280x800@60, 1
animations { enabled = false }
misc { disable_hyprland_logo = true, disable_splash_rendering = true }
bind = SUPER, Q, exit
EOF

before=$(ls /run/user/"$(id -u)"/ | grep -c '^wayland-[0-9]*$')
env -u HYPRLAND_INSTANCE_SIGNATURE Hyprland -c "$WORK/hyprland.conf" \
    > "$HYPR_LOG" 2>&1 &
HYPR_PID=$!

for _ in $(seq 1 100); do
    after=$(ls /run/user/"$(id -u)"/ | grep -c '^wayland-[0-9]*$')
    (( after > before )) && break
    sleep 0.1
done
NESTED_DISPLAY=$(ls -t /run/user/"$(id -u)"/ | grep -m1 '^wayland-[0-9]*$')
if [[ -z "$NESTED_DISPLAY" ]] || ! kill -0 "$HYPR_PID" 2>/dev/null; then
    echo "could not start a nested Hyprland — see $HYPR_LOG" >&2
    exit 1
fi
note "nested compositor on $NESTED_DISPLAY"

# --- run the lock in it ----------------------------------------------------

env -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY="$NESTED_DISPLAY" \
    "$QS" -p "$HARNESS_QML" > "$SHELL_LOG" 2>&1 &
SHELL_PID=$!

if ! await_log "$SHELL_LOG" 'harness: lock harness ready' 20; then
    echo "the harness shell never came up — see $SHELL_LOG" >&2
    exit 1
fi
note "shell up (pid $SHELL_PID)"

echo
# 1 — Enter with nothing to answer. Run *before* the lock, where there is
# provably no conversation: this is #81's failure mode in isolation, and it
# costs PAM nothing. Silence here is the bug; a message is the fix.
ipc locktest type "no conversation is open" > /dev/null
ipc locktest enter > /dev/null
state=$(ipc locktest state)
if [[ "$state" == *'"message":""'* ]]; then
    fail "Enter with no conversation was silent — the #81 lockout (state: $state)"
else
    pass "Enter with no conversation says so: $(sed 's/.*"message":"\([^"]*\)".*/\1/' <<< "$state")"
fi

echo "engaging the lock"
ipc lock lock > /dev/null

# 2 — the compositor has the screen.
if await_log "$SHELL_LOG" 'lock: compositor confirms all screens covered' 15; then
    pass "compositor confirms all screens covered"
else
    fail "compositor never confirmed the lock (secure never went true)"
fi

# 2 — PAM was actually asked something. This is #81: the conversation never
# opened, so every Enter was a no-op forever.
if await_log "$SHELL_LOG" 'lock: pam conversation open' 15; then
    pass "PAM conversation opened and prompted"
else
    fail "PAM never prompted — every Enter is a silent no-op (#81)"
fi

# 3 — opening it did not take the shell down with it.
if kill -0 "$SHELL_PID" 2>/dev/null; then
    pass "shell survived opening the conversation"
else
    fail "shell died while locked — $(grep -aiE 'wayland|fatal' "$SHELL_LOG" | tail -2)"
fi

# 4b — opt in to the full round trip. One wrong password, one faillock try.
if (( ATTEMPT )) && kill -0 "$SHELL_PID" 2>/dev/null; then
    note "sending one wrong password — this counts against pam_faillock"
    ipc locktest type "$WRONG_PASSWORD" > /dev/null
    ipc locktest enter > /dev/null

    if await_log "$SHELL_LOG" 'lock: password attempt (failed|maxTries)' 20; then
        pass "wrong password was refused by PAM"
    else
        fail "wrong password produced no response at all (#81)"
    fi

    state=$(ipc locktest state)
    if [[ "$state" == *'"message":""'* ]]; then
        fail "nothing was put on screen for the user to read — state: $state"
    else
        pass "the refusal is on screen: $(sed 's/.*"message":"\([^"]*\)".*/\1/' <<< "$state")"
    fi
    note "clear the tally with: sudo faillock --user $USER --reset"
fi

# 5 — the field can hear a keyboard. The IPC above deliberately bypasses it,
# so this is the only thing standing in for "would a keystroke have landed".
if grep -qa 'lock: field has focus on' "$SHELL_LOG"; then
    pass "the field took keyboard focus on its surface"
else
    fail "the field never took focus — typing would go nowhere: $(grep -a 'lock: field' "$SHELL_LOG" | tail -1)"
fi

echo
if (( fail_count )); then
    printf '\033[31m%d check(s) failed\033[0m — logs in %s\n' "$fail_count" "$WORK"
    KEEP=$KEEP  # logs survive under --keep
    exit 1
fi
printf '\033[32mthe lock is answerable\033[0m\n'
exit 0
