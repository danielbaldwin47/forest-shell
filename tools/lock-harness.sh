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
#   tools/lock-harness.sh --latch    # also check the lockout latch (#161) and
#                                    # that it is acted on the moment it is
#                                    # heard (#164) — costs one more wrong
#                                    # password
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
# and, opt-in, that a lockout survives being announced badly (`--latch`, #161)
# and is dressed as a lockout from the moment it is announced rather than from
# the end of the attempt it interrupted (#164): faillock's own two lines are
# replayed into the real message path and a real wrong password completes the
# attempt, because producing the two lines for real means locking the account of
# whoever ran this.
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

# The fingerprint line is its own field, because it is its own line on screen:
# what fprintd says is about a device, not about the password attempt above it.
fingerprint_message() {
    local state="$1"
    [[ "$state" == *'"fingerprintMessage":'* ]] || return 1
    sed 's/.*"fingerprintMessage":"\([^"]*\)".*/\1/' <<< "$state"
}

# The same guard for the flags, which are unquoted: `true`, `false`, nothing at
# all if this was the client failing rather than the lock answering.
lock_flag() {
    local state="$1" key="$2"
    [[ "$state" == *"\"$key\":"* ]] || return 1
    sed "s/.*\"$key\":\([a-z]*\).*/\1/" <<< "$state"
}

# And the same again for a count (#188). `lock_flag`'s `[a-z]*` matches nothing
# against a number, and "nothing" compares equal to plenty of things — the touch
# count is the whole claim of §6, so it needs a reader that can fail.
lock_number() {
    local state="$1" key="$2"
    [[ "$state" == *"\"$key\":"* ]] || return 1
    sed "s/.*\"$key\":\([0-9]*\).*/\1/" <<< "$state"
}

# The sleep and resume verbs the bridge already exposes (#188). Driven here for
# the same reason tools/idle-harness.sh drives them: this seam has no suspend
# and needs none — what is being tested is what the shell does when logind says
# the machine is going and when it says the machine is back.
logind() { nested_ipc call logind "$@"; }

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

    # …and it is acted on *now*, not at the end of the attempt the user is
    # still typing (#164). faillock speaks in preauth, before pam_unix prompts,
    # so everything between here and the completion below is real time with a
    # live field in it. Read the state before anything is submitted: `lockedOut`
    # is what buys the message ember instead of `quiet`, and what stops the
    # retreat.
    state=$(ipc locktest state)
    if ! locked=$(lock_flag "$state" lockedOut); then
        nested_fail "could not read the lock's state — $state"
    elif [[ "$locked" == true ]]; then
        nested_pass "the lockout is on screen as one before the attempt completes"
    else
        nested_fail "the lockout is dressed as an ordinary message until the attempt completes (#164): $state"
    fi

    # And it is `lockedOut` alone that bought that, which is the whole of #164:
    # faillock speaks in `pam_info`, so there is no error flag under this
    # message to fall back on. Asserted because without it the check above
    # passes on a lockout said as an error too — `messageTone` answers
    # "lockout" either way — and the seam would stop modelling the bug.
    if ! errored=$(lock_flag "$state" messageIsError); then
        nested_fail "could not read the lock's state — $state"
    elif [[ "$errored" == false ]]; then
        nested_pass "and it is not riding on an error flag — faillock's is a pam_info"
    else
        nested_fail "the harness said faillock's line as an error — the #164 window is unreachable from here: $state"
    fi

    ipc locktest clearmessage > /dev/null
    state=$(ipc locktest state)
    if ! message=$(lock_message "$state"); then
        nested_fail "could not read the lock's state — $state"
    elif [[ -n "$message" ]]; then
        nested_pass "the retreat cannot take it off screen mid-attempt: $message"
    else
        nested_fail "the retreat cleared a lockout the attempt had not completed yet (#164)"
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

# 4d — a failed finger stays readable (#168). The conversation itself needs a
# reader and a finger, so it cannot happen here; but which of two messages ends
# up on screen is decided in `noteFingerprintMessage`, which hears text. So the
# two lines the hardware trace recorded are replayed back to back — pam_fprintd
# re-prompts 9.7ms after it reports a failed match, less than a frame — and the
# real arbitration answers them. Costs no PAM attempt and no faillock try.
fp_fail='Failed to match fingerprint'
fp_prompt='Place your finger on the fingerprint reader'
ipc locktest fingersay "$fp_fail" true > /dev/null
ipc locktest fingersay "$fp_prompt" false > /dev/null
state=$(ipc locktest state)
if ! message=$(fingerprint_message "$state"); then
    nested_fail "could not read the lock's state — $state"
elif [[ "$message" == "$fp_fail" ]]; then
    nested_pass "the failed match survived the re-prompt: $message"
else
    nested_fail "the re-prompt wiped the failure before it could be drawn (#168): $state"
fi

# …and it is held, not dropped: the reader's own prompt has to come back once
# the failure has had its dwell, or the line goes stale on a device that is
# still waiting for a finger.
# Longer than `LockPolicy.fingerprintErrorDwellMs` (1500ms) and no longer than
# it has to be. Coupled to that number on purpose: raise the dwell past this
# and the check below asserts the opposite of what it says, so they move
# together.
sleep 2
state=$(ipc locktest state)
if ! message=$(fingerprint_message "$state"); then
    nested_fail "could not read the lock's state — $state"
elif [[ "$message" == "$fp_prompt" ]]; then
    nested_pass "the prompt returned once the failure had been read: $message"
else
    nested_fail "the held prompt never went up — the fingerprint line is stuck (#168): $state"
fi

# …and the hold said so in the log. On hardware this is the only way to tell a
# line stuck on a stale failure from a line nothing ever sent to — #81's
# argument, and the state above cannot make it after the flush has happened.
if grep -qa 'lock: fingerprint message held' "$NESTED_SHELL_LOG"; then
    nested_pass "the hold is in the log: $(grep -a -m1 'lock: fingerprint message held' "$NESTED_SHELL_LOG")"
else
    nested_fail "the hold left no trace in the log — a stuck fingerprint line would be undiagnosable (#81)"
fi

# 4e — the offer does not withdraw in silence (#169). Three wrong touches are
# all pam_fprintd allows, and they all happen inside one conversation, so its
# close is the end of fingerprint for this lock. It used to take the line down
# with it: the reader's light going out was the only word on the subject, and
# that light is the hardware's. Posed open, because the probe needs a reader —
# but the withdrawal itself is the real one the close calls.
ipc locktest fingeroffer > /dev/null
for _ in 1 2 3; do
    ipc locktest fingersay "$fp_fail" true > /dev/null
    ipc locktest fingersay "$fp_prompt" false > /dev/null
done
ipc locktest fingerwithdraw true > /dev/null

# The last touch is a failure like any other and keeps its dwell (#168), so the
# closing line queues behind it rather than wiping it — otherwise the fix for
# #169 re-creates the bug #168 fixed, on the one touch that matters most.
state=$(ipc locktest state)
if ! message=$(fingerprint_message "$state"); then
    nested_fail "could not read the lock's state — $state"
elif [[ "$message" == "$fp_fail" ]]; then
    nested_pass "the last failure survived the withdrawal: $message"
else
    nested_fail "the withdrawal wiped the failure that caused it (#168 again): $state"
fi

# Same 2s as above, and coupled to `fingerprintErrorDwellMs` for the same
# reason: the closing line goes up once the failure has had its spell.
sleep 2
state=$(ipc locktest state)
if ! message=$(fingerprint_message "$state"); then
    nested_fail "could not read the lock's state — $state"
elif [[ -z "$message" ]]; then
    nested_fail "the fingerprint offer withdrew in silence (#169): $state"
elif [[ "$message" == *[Pp]assword* ]]; then
    nested_pass "the withdrawn offer points at the password: $message"
else
    nested_fail "the offer said it was over but not what to do instead (#169): $message"
fi

# …and it says so in the log, with the count it spent. Three, because three
# failures were replayed above and the count is read out of the messages — on
# hardware that number is pam_fprintd's `max-tries` and not ours, so a budget
# that quietly changes under us shows up in this line first (#81's argument
# again, and `LockPolicy.fingerprintTouchBudget` is the number it is checked
# against there).
if grep -qa 'lock: fingerprint offer withdrawn after 3 touch(es)' "$NESTED_SHELL_LOG"; then
    nested_pass "the close is in the log, with its count: $(grep -a -m1 'lock: fingerprint offer withdrawn after' "$NESTED_SHELL_LOG")"
elif grep -qa 'lock: fingerprint offer withdrawn after' "$NESTED_SHELL_LOG"; then
    nested_fail "the close logged a count no conversation spent: $(grep -a -m1 'lock: fingerprint offer withdrawn after' "$NESTED_SHELL_LOG")"
else
    nested_fail "the close left no trace in the log — a withdrawn offer would be undiagnosable (#81)"
fi

# 5 — the field can hear a keyboard. The IPC above deliberately bypasses it,
# so this is the only thing standing in for "would a keystroke have landed".
if grep -qa 'lock: field has focus on' "$NESTED_SHELL_LOG"; then
    nested_pass "the field took keyboard focus on its surface"
else
    nested_fail "the field never took focus — typing would go nowhere: $(grep -a 'lock: field' "$NESTED_SHELL_LOG" | tail -1)"
fi

echo
# 6 — a suspend and a resume, with no suspend (#188).
#
# The reported bug is that waking the machine produces "failed to match" three
# times over a sensor that never lights up, then "Out of fingerprint tries". The
# cause has nothing to do with the reader: the shell locks *inside* logind's
# delay inhibitor, which opens the PAM conversations, and then the machine
# suspends on top of them. On this hardware
# `python3-validity-suspend-hotfix.service` restarts open-fprintd on every
# resume, so what the conversation is holding on the other side is a bus name
# nothing owns any more.
#
# None of that needs a real suspend to drive. The bridge already exposes `sleep`
# and `resume` over IPC, and those two calls are the entire lifecycle — the
# suspend in between is the one part the shell never sees.

# An offer mid-flight, with touches already on it, which is the state a lid
# close finds. Posed, because the probe needs a reader (§4's argument).
ipc locktest fingeroffer > /dev/null
ipc locktest fingersay "$fp_fail" true > /dev/null
ipc locktest fingersay "$fp_prompt" false > /dev/null
state=$(ipc locktest state)
if ! touches=$(lock_number "$state" fingerprintTouches); then
    nested_fail "could not read the touch count — $state"
elif [[ "$touches" == "1" ]]; then
    nested_pass "a live offer charges a missed touch: $touches"
else
    nested_fail "a live offer did not charge the touch it was given: $state"
fi

logind sleep > /dev/null
sleep 1

# The teardown is the acceptance: nothing fingerprint-shaped may be carried
# into a suspend, and the touches that were on it do not survive either.
if grep -qa 'lock: sleep announced' "$NESTED_SHELL_LOG"; then
    nested_pass "the lock heard the sleep: $(grep -a -m1 'lock: sleep announced' "$NESTED_SHELL_LOG")"
else
    nested_fail "the lock never heard the sleep — its conversations go into the suspend live (#188)"
fi
if grep -qa 'lock: fingerprint offer torn down' "$NESTED_SHELL_LOG"; then
    nested_pass "the offer stood down: $(grep -a -m1 'lock: fingerprint offer torn down' "$NESTED_SHELL_LOG")"
else
    nested_fail "the offer was carried into the suspend (#188)"
fi

state=$(ipc locktest state)
if ! touches=$(lock_number "$state" fingerprintTouches); then
    nested_fail "could not read the touch count — $state"
elif [[ "$touches" == "0" ]]; then
    nested_pass "the suspend discarded the touches it found: $touches"
else
    nested_fail "touches were carried across the suspend and will be charged (#188): $state"
fi

# Anything the stranded conversation says now is the machine talking to itself.
# It arrives in the wrong finger's exact words, so the only thing that can
# refuse it is the offer not being live.
ipc locktest fingersay "$fp_fail" true > /dev/null
ipc locktest fingersay "$fp_fail" true > /dev/null
ipc locktest fingersay "$fp_fail" true > /dev/null
state=$(ipc locktest state)
if ! touches=$(lock_number "$state" fingerprintTouches); then
    nested_fail "could not read the touch count — $state"
elif [[ "$touches" == "0" ]]; then
    nested_pass "three failures across the suspend cost the user nothing: $touches"
else
    nested_fail "the suspend charged the user $touches touch(es) they never made (#188): $state"
fi

# And they are not on screen either. Costing nothing is only half of it: a
# phantom failure pinned for its dwell is the "fake failure first" the ticket
# rules out, and on hardware where the reader does not come back it is what the
# user reads before the unavailable line.
if ! message=$(fingerprint_message "$state"); then
    nested_fail "could not read the lock's state — $state"
elif [[ "$message" == *"$fp_fail"* ]]; then
    nested_fail "a failure nobody caused is on the lock screen (#188): $message"
else
    nested_pass "the phantom failures never reached the screen: ${message:-<no fingerprint line>}"
fi
if grep -qa 'lock: fingerprint failure dropped' "$NESTED_SHELL_LOG"; then
    nested_pass "and the drop is in the log: $(grep -a -m1 'lock: fingerprint failure dropped' "$NESTED_SHELL_LOG")"
else
    nested_fail "the drop left no trace — a fingerprint line that says nothing would be undiagnosable (#81)"
fi

logind resume > /dev/null
# The rebuild re-runs the enrolment probe, and that probe has a settle window
# for the driver restart above — four asks, 750ms apart. Waiting it out here is
# the difference between reading the answer and reading the question.
sleep 5

if grep -qa 'lock: resume observed' "$NESTED_SHELL_LOG"; then
    nested_pass "the lock heard the resume: $(grep -a -m1 'lock: resume observed' "$NESTED_SHELL_LOG")"
else
    nested_fail "the lock never heard the resume — the already-begun guard still holds it shut (#188)"
fi
if grep -qa 'lock: rebuilding pam conversations' "$NESTED_SHELL_LOG"; then
    nested_pass "both conversations were rebuilt: $(grep -a -m1 'lock: rebuilding pam conversations' "$NESTED_SHELL_LOG")"
else
    nested_fail "the conversations were not rebuilt — the password field is stranded too (#188)"
fi

# The password half, asserted by outcome rather than by intent (#188 acceptance
# 8). "We decided to rebuild" is not the claim — the claim is that PAM is
# prompting again on the other side, and a lock screen that will not take a
# password after a resume is the more serious version of this bug. Both facts
# are read: the far-side log line, and `conversing`, which only goes true when a
# real PAM message arrives.
if [[ $(grep -ca 'lock: pam conversation open' "$NESTED_SHELL_LOG") -ge 2 ]]; then
    nested_pass "pam is prompting again after the resume ($(grep -ca 'lock: pam conversation open' "$NESTED_SHELL_LOG") conversations opened)"
else
    nested_fail "pam never prompted after the resume — the password field is dead (#188)"
fi
state=$(ipc locktest state)
if ! conversing=$(lock_flag "$state" conversing); then
    nested_fail "could not read the lock's state — $state"
elif [[ "$conversing" == "true" ]]; then
    nested_pass "the rebuilt password conversation is answering: conversing=$conversing"
else
    nested_fail "the password conversation is not answering after the resume (#188): $state"
fi

state=$(ipc locktest state)
if ! touches=$(lock_number "$state" fingerprintTouches); then
    nested_fail "could not read the touch count — $state"
elif [[ "$touches" == "0" ]]; then
    nested_pass "the rebuilt offer starts unspent: $touches touch(es)"
else
    nested_fail "the offer was rebuilt with touches already on it (#188): $state"
fi

# Whatever the probe found on the other side, the one thing the screen may not
# say is that the user ran out of tries: they touched nothing.
if ! message=$(fingerprint_message "$state"); then
    nested_fail "could not read the lock's state — $state"
elif [[ "$message" == *"Out of fingerprint tries"* ]]; then
    nested_fail "the resume produced the out-of-tries line over an untouched reader (#188): $message"
else
    nested_pass "the resume did not claim the user was out of tries: ${message:-<no fingerprint line>}"
fi

echo
if (( nested_fail_count )); then
    printf '\033[31m%d check(s) failed\033[0m\n' "$nested_fail_count"
    exit 1
fi
printf '\033[32mthe lock is answerable\033[0m\n'
exit 0
