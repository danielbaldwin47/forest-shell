#!/usr/bin/env bash
# Engage the lock inside a nested Hyprland and assert it is answerable (#81).
#
# The failure this exists for cost a session every time it was tested: a lock
# that will not authenticate can only be escaped by killing the compositor. So
# nothing here touches the running session. tools/nested-session.sh starts a
# second Hyprland as a window inside it, the shell's lock runs in *that*, and a
# lock that will not open is closed with `kill`.
#
#   tools/lock-harness.sh            # run the checks, print PASS/FAIL, exit 0/1
#   tools/lock-harness.sh --keep     # leave the nested session up afterwards,
#                                    # for typing at it by hand
#   tools/lock-harness.sh --attempt  # also send one wrong password to real PAM
#   tools/lock-harness.sh --latch    # also check the lockout latch (#161) —
#                                    # costs one more wrong password
#
# What it asserts, in the order the lock does them:
#
#   1. Enter with no conversation says so, instead of going quiet
#   2. the compositor confirms every screen is covered (`secure`) — on a
#      session with one screen, which is a screen it cannot fail to cover.
#      tools/multi-monitor-harness.sh is where that claim is made to mean
#      something: two outputs, one buffer behind both, and an output plugged
#      in and out while the session is locked (#98)
#   3. a PAM conversation actually opens, and prompts
#   4. the shell survives opening it
#   5. the field can hear a keyboard
#
# and, opt-in, that a lockout survives being announced badly (`--latch`, #161):
# faillock's own two lines are replayed into the real message path and a real
# wrong password completes the attempt, because producing the two lines for real
# means locking the account of whoever ran this.
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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

readonly WRONG_PASSWORD="definitely-not-the-password-$$"
ATTEMPT=0
LATCH=0
for arg in "$@"; do
    case "$arg" in
        --keep)    NESTED_KEEP=1 ;;
        --attempt) ATTEMPT=1 ;;
        --latch)   LATCH=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call "$@"; }

# `ipc locktest state` returns the surface's whole state as JSON. Anything that
# is not that object is the *client* having failed, not the lock answering — and
# an unparsed error string trivially satisfies "the message is not empty", so
# every assertion on a reply has to establish it is a reply first.
lock_message() {
    local state="$1"
    [[ "$state" == *'"message":'* ]] || return 1
    sed 's/.*"message":"\([^"]*\)".*/\1/' <<< "$state"
}

# The same guard for the flags, which are unquoted: `true`, `false`, nothing at
# all if this was the client failing rather than the lock answering.
lock_flag() {
    local state="$1" key="$2"
    [[ "$state" == *"\"$key\":"* ]] || return 1
    sed "s/.*\"$key\":\([a-z]*\).*/\1/" <<< "$state"
}

nested_up || exit 1
nested_shell lock-harness.qml 'harness: lock harness ready' || exit 1

echo
# 1 — Enter with nothing to answer. Run *before* the lock, where there is
# provably no conversation: this is #81's failure mode in isolation, and it
# costs PAM nothing. Silence here is the bug; a message is the fix.
ipc locktest type "no conversation is open" > /dev/null
ipc locktest enter > /dev/null
state=$(ipc locktest state)
if ! message=$(lock_message "$state"); then
    nested_fail "could not read the lock's state — $state"
elif [[ -z "$message" ]]; then
    nested_fail "Enter with no conversation was silent — the #81 lockout (state: $state)"
else
    nested_pass "Enter with no conversation says so: $message"
fi

echo "engaging the lock"
ipc lock lock > /dev/null

# 2 — the compositor has the screen.
if nested_await "$NESTED_SHELL_LOG" 'lock: compositor confirms all screens covered' 15; then
    nested_pass "compositor confirms all screens covered"
else
    nested_fail "compositor never confirmed the lock (secure never went true)"
fi

# 3 — PAM was actually asked something. This is #81: the conversation never
# opened, so every Enter was a no-op forever.
if nested_await "$NESTED_SHELL_LOG" 'lock: pam conversation open' 15; then
    nested_pass "PAM conversation opened and prompted"
else
    nested_fail "PAM never prompted — every Enter is a silent no-op (#81)"
fi

# 4 — opening it did not take the shell down with it. #81 saw
# `wl_display: error 0: invalid object` 3/3 here once `begin()` ran, and could
# not tell a real bug from an artefact of the nested backend. This is the check
# that answers it, on whatever machine it is run.
if kill -0 "$NESTED_SHELL_PID" 2>/dev/null; then
    nested_pass "shell survived opening the conversation"
else
    nested_fail "shell died while locked — $(grep -aiE 'wayland|fatal' "$NESTED_SHELL_LOG" | tail -2)"
fi

# 4b — opt in to the full round trip. One wrong password, one faillock try.
if (( ATTEMPT )) && kill -0 "$NESTED_SHELL_PID" 2>/dev/null; then
    nested_note "sending one wrong password — this counts against pam_faillock"
    ipc locktest type "$WRONG_PASSWORD" > /dev/null
    ipc locktest enter > /dev/null

    if nested_await "$NESTED_SHELL_LOG" 'lock: password attempt (failed|maxTries)' 20; then
        nested_pass "wrong password was refused by PAM"
    else
        nested_fail "wrong password produced no response at all (#81)"
    fi

    state=$(ipc locktest state)
    if ! message=$(lock_message "$state"); then
        nested_fail "could not read the lock's state — $state"
    elif [[ -z "$message" ]]; then
        nested_fail "nothing was put on screen for the user to read — state: $state"
    else
        nested_pass "the refusal is on screen: $message"
    fi
fi

# 4c — the lockout latch (#161). faillock says two things per refusal and only
# the first one names the lockout; the second ("(10 minutes left to unlock)") is
# what `message` remembers. Producing that for real costs `deny` failed logins
# against the account running this, so the script speaks faillock's two lines
# into the real `noteMessage` and lets a real wrong password complete the
# attempt. What is under test is entirely on this side of PAM: whether the
# completed attempt still knows it was a lockout once the last message it heard
# was not one.
if (( LATCH )) && kill -0 "$NESTED_SHELL_PID" 2>/dev/null; then
    nested_note "replaying faillock's two lines, then one wrong password — this counts against pam_faillock"
    ipc locktest say 'Account locked due to 3 failed logins' > /dev/null
    ipc locktest say '(10 minutes left to unlock)' > /dev/null

    if grep -qa 'lock: faillock lockout recognised in a pam message' "$NESTED_SHELL_LOG"; then
        nested_pass "faillock's refusal was recognised as a lockout"
    else
        nested_fail "faillock's refusal was not recognised — the message patterns missed it (#161)"
    fi

    # Counted rather than awaited: `nested_await` greps the log from the start,
    # so under `--attempt --latch` 4b's own completion would satisfy it instantly
    # and the state below would be read before this attempt had finished — a
    # working latch reported as a broken one.
    before=$(grep -ac 'lock: password attempt ' "$NESTED_SHELL_LOG")
    ipc locktest type "$WRONG_PASSWORD" > /dev/null
    ipc locktest enter > /dev/null
    for _ in $(seq 40); do
        (( $(grep -ac 'lock: password attempt ' "$NESTED_SHELL_LOG") > before )) && break
        sleep 0.5
    done

    state=$(ipc locktest state)
    if ! locked=$(lock_flag "$state" lockedOut); then
        nested_fail "could not read the lock's state — $state"
    elif (( $(grep -ac 'lock: password attempt ' "$NESTED_SHELL_LOG") == before )); then
        nested_fail "the attempt never completed — nothing to latch onto (#81)"
    elif [[ "$locked" == true ]]; then
        nested_pass "the lockout latched: the attempt completed locked out even though the last message was not one"
    else
        nested_fail "the lockout did not latch — the last message overruled it (#161): $state"
    fi

    # …and a latched lockout is a message that stays up. This is the second
    # half of #161: the idle retreat took the lockout off the screen after a
    # couple of seconds, leaving the user typing into a field that cannot win.
    ipc locktest clearmessage > /dev/null
    state=$(ipc locktest state)
    if ! message=$(lock_message "$state"); then
        nested_fail "could not read the lock's state — $state"
    elif [[ -n "$message" ]]; then
        nested_pass "the lockout survived the retreat: $message"
    else
        nested_fail "the retreat cleared a lockout off the screen (#161)"
    fi
fi

# Once, however many wrong passwords the flags above spent.
if (( ATTEMPT || LATCH )); then
    nested_note "clear the tally with: sudo faillock --user $USER --reset"
fi

# 5 — the field can hear a keyboard. The IPC above deliberately bypasses it,
# so this is the only thing standing in for "would a keystroke have landed".
if grep -qa 'lock: field has focus on' "$NESTED_SHELL_LOG"; then
    nested_pass "the field took keyboard focus on its surface"
else
    nested_fail "the field never took focus — typing would go nowhere: $(grep -a 'lock: field' "$NESTED_SHELL_LOG" | tail -1)"
fi

echo
if (( nested_fail_count )); then
    printf '\033[31m%d check(s) failed\033[0m\n' "$nested_fail_count"
    exit 1
fi
printf '\033[32mthe lock is answerable\033[0m\n'
exit 0
