#!/usr/bin/env bash
# Run the shell on two outputs, and on three, and on one again (#98).
#
# Everything #22 §1 says about per-screen behaviour has been theory: both
# machines the shell runs on have one output, so "one bar per screen" and "the
# lock covers every output" have never been anything but code that compiles.
# `tools/lock-harness.sh` asserts "all screens covered" against a nested session
# with exactly one screen, which is an assertion that cannot fail.
#
# A nested compositor can be given a second output as easily as a first, which
# is the argument for seam 2 existing. The second one here is *headless*: a
# second wayland-backend output is a second window on the host, so the host's
# tiling decides its size (measured — both outputs ended up ~618x648 and the
# rule for the new one never applied). Headless has no window to be resized, so
# the size and scale asserted on below are the ones this file chose.
#
#   tools/multi-monitor-harness.sh            # the checks, PASS/FAIL, exit 0/1
#   tools/multi-monitor-harness.sh --attempt  # submit to the real login stack
#                                             # instead, at one faillock try
#   tools/multi-monitor-harness.sh --keep     # leave the session up afterwards,
#                                             # for `hyprctl -i` to poke at.
#                                             # There is nothing to *look* at:
#                                             # the outputs are all headless
#
# What it asserts:
#
#   1. two outputs, at different sizes and scales, before the shell starts
#   2. one bar window per output, each with its own output's geometry
#   3. an output plugged in and out while unlocked: a bar arrives, a bar goes
#      away with it, and no other bar is disturbed
#   4. the lock puts a surface on both outputs, and the compositor calls it
#      secure
#   5. one buffer behind both: keys typed on one screen and keys typed on the
#      other land in the same password, and Enter on the far screen submits it
#      as one attempt
#   6. an output plugged in and out *while locked*: a surface arrives for it,
#      and leaves with it, without taking the lock or the shell down
#
# 5 submits, which lock-harness.sh will not do without being asked, and the
# difference is the stack: the shell under test is pointed at one whose auth is
# a bare `pam_unix.so` (`vlock`, `cups`), which prompts and refuses exactly as
# the login stack does with pam_faillock nowhere in it, so the refusal costs the
# account nothing. What that skips is the login stack itself, which `--attempt`
# puts back at the cost lock-harness.sh's `--attempt` charges. The claim being
# tested is about two surfaces and one conversation, and it is the same claim
# either way.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

ATTEMPT=0
for arg in "$@"; do
    case "$arg" in
        --keep)    NESTED_KEEP=1 ;;
        --attempt) ATTEMPT=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# The layout under test. Different sizes *and* different scales, because a
# uniform pair would pass on code that assumes one geometry for every screen —
# which is the assumption #98 exists to break.
#
# Only the headless outputs' geometry is this file's to choose. The nested
# backend's own output is a window on the host session, and the host resizes it
# to whatever it tiles into — measured: 1280x800 at bring-up, 618x616 the
# moment a second output appeared. So every geometry assertion below is against
# what the compositor reports for that output, not against a number written
# here: the claim being tested is "the bar on this screen is this screen's
# size", which is exactly the claim a hard-coded number stops making.
PRIMARY="FOREST-1"
SECOND="FOREST-2"
HOTPLUG="FOREST-3"
NESTED_MONITORS=("WAYLAND-1, 1280x800@60, 0x0, 1"
                 "$PRIMARY, 1280x800@60, 0x0, 1"
                 "$SECOND, 1920x1080@60, 1280x0, 1.5")
NESTED_HEADLESS_ONLY=1
HOTPLUG_SPEC="$HOTPLUG, 1024x768@60, 3200x0, 1"

ipc() { nested_ipc call "$@"; }

## What `hyprctl` will report for a `monitor =` rule, so that the rule stays the
## one place the layout is written down. `1280x800@60, 0x0, 1` reads back as
## `1280x800 0x0 1.00`.
rule_geometry() {
    awk -F, '{ gsub(/ /, ""); split($2, mode, "@"); printf "%s %s %.2f\n", mode[1], $3, $4 }' \
        <<< "$1"
}

## How many times a line appears in the shell log. Explicitly zero when there
## is nothing to count: `grep -c` prints `0` and returns 1 when the pattern is
## absent, but prints *nothing* and returns 2 when the log is not there yet,
## and an empty string reaches the arithmetic below as a syntax error.
log_count() {
    local count
    count=$(grep -ac "$1" "$NESTED_SHELL_LOG" 2>/dev/null)
    printf '%s' "${count:-0}"
}

## How many of a surface are live: every one announced, less every one that
## announced it was going. The subtraction is the leak check — a surface that
## outlives its output never logs the second line.
live_surfaces() { echo $(( $(log_count "$1") - $(log_count "$2") )); }

nested_up || exit 1

# 1 — the session really has two outputs, and they really are different: a
# two-screen run where both screens are the same size and scale proves nothing
# a one-screen run did not.
outputs=$(nested_outputs | sort | tr '\n' ' ')
if [[ "$outputs" == "$PRIMARY $SECOND " ]]; then
    nested_pass "two outputs, and only the two: $outputs"
else
    nested_fail "the session came up with outputs [$outputs], wanted [$PRIMARY $SECOND]"
fi

for rule in "${NESTED_MONITORS[@]:1}"; do
    name=$(nested_output_name "$rule")
    wanted=$(rule_geometry "$rule")
    got=$(nested_output_geometry "$name")
    if [[ "$got" == "$wanted" ]]; then
        nested_pass "$name is $wanted (logical $(nested_output_logical "$name"))"
    else
        nested_fail "$name came up as '$got', wanted '$wanted'"
    fi
done

# The scale gap, quoted rather than asserted, because it is a *measurement* and
# the number is Qt's: `devicePixelRatio` reports 2 on a 1.5-scale output (#73's
# footnote, and the reason Surfaces/Background/Wallpaper.qml clamps it to an
# oversample bound instead of treating it as a raster size). With two outputs it
# stops being a footnote — the lines below say what each screen reported, and
# what the surfaces on it did with that.

# The shell under test gets a scratch config, for settings-harness's reason:
# a harness that runs the real shell must not read or write the files of the
# session it is being run from.
SCRATCH="$NESTED_WORK/xdg"
mkdir -p "$SCRATCH/config/forest-shell" "$SCRATCH/state"
NESTED_ENV=("XDG_CONFIG_HOME=$SCRATCH/config" "XDG_STATE_HOME=$SCRATCH/state")

# A wallpaper, because the wallpaper is decoded per screen at that screen's
# size and the adaptive-opacity read samples what was decoded — two screens
# sharing one decode would be one screen's wallpaper deciding the other's
# contrast, and with one screen there is nothing to tell the two apart. Written
# the way tools/drawer-harness.sh writes its fixtures.
python3 - "$SCRATCH/pine.png" <<'PYEOF'
import struct
import sys
import zlib


def chunk(tag, payload):
    return (struct.pack(">I", len(payload)) + tag + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))


raw = bytearray()
for _ in range(8):
    raw.append(0)
    raw += bytes((36, 58, 44)) * 8

with open(sys.argv[1], "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n")
    f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0)))
    f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
    f.write(chunk(b"IEND", b""))
PYEOF

# The PAM stack the lock talks to, and the reason this harness can afford to
# press Enter at all. The check needs a stack that *prompts* and then refuses:
# `other` is pam_deny, which refuses without ever prompting, so the lock re-arms
# on every keystroke and logs an attempt per key — measured, and useless to
# count. A stack whose auth is a bare `pam_unix.so` prompts like the login stack
# does and refuses a wrong password the same way, and pam_faillock is not in it,
# so the account this is being run on never hears about it.
#
# Chosen by reading the stacks rather than by name, because the name that has
# this shape is a packaging detail: `vlock` here, `cups` on a machine without
# it, and on a machine with neither the check says so and `--attempt` is the
# way to run it.
PAM_STACK=""
for candidate in vlock cups chsh; do
    [[ -r "/etc/pam.d/$candidate" ]] || continue
    grep -qE '^auth.*pam_unix\.so' "/etc/pam.d/$candidate" || continue
    grep -qE 'faillock|system-auth|system-login' "/etc/pam.d/$candidate" && continue
    PAM_STACK="$candidate"
    break
done
(( ATTEMPT )) && PAM_STACK="login"

if [[ -n "$PAM_STACK" ]]; then
    printf '{ "wallpaper": { "path": "%s" }, "system": { "lock": { "pamConfig": "%s" } } }\n' \
        "$SCRATCH/pine.png" "$PAM_STACK" > "$SCRATCH/config/forest-shell/settings.json"
else
    printf '{ "wallpaper": { "path": "%s" } }\n' \
        "$SCRATCH/pine.png" > "$SCRATCH/config/forest-shell/settings.json"
fi

echo
echo "the bar, per output"
nested_shell shell.qml 'startup: stage interactive' 25 || exit 1

# 2 — one window per output, each with its *own* geometry. The whole failure
# mode this catches is a bar that is built once and stretched, or built per
# screen off the wrong screen's size: both produce a window on each output, and
# only the geometry in the line tells them apart.
for name in "$PRIMARY" "$SECOND"; do
    logical=$(nested_output_logical "$name")
    if nested_await "$NESTED_SHELL_LOG" "bar: window up on $name \(${logical/x/×} " 15; then
        nested_pass "bar on $name at ${logical/x/×} — $(grep -a "bar: window up on $name" "$NESTED_SHELL_LOG" | tail -1 | sed 's/.*(\(.*\)).*/\1/')"
    else
        nested_fail "no bar on $name at ${logical/x/×}: $(grep -a 'bar: window up on' "$NESTED_SHELL_LOG" | tr '\n' ' ')"
    fi
done

bars=$(log_count 'bar: window up on')
if [[ "$bars" == "2" ]]; then
    nested_pass "exactly two bar windows, one per output"
else
    nested_fail "$bars bar windows for 2 outputs"
fi

# The wallpaper, decoded per screen at that screen's size. Two decodes and two
# *different* sizes is the assertion: one decode shared, or two at the same
# size, is the smaller screen sampling the larger one's pixels.
for name in "$PRIMARY" "$SECOND"; do
    nested_await "$NESTED_SHELL_LOG" "background: wallpaper .* on $name" 15 \
        || nested_fail "the wallpaper never decoded for $name"
done

decodes=$(grep -a 'background: wallpaper' "$NESTED_SHELL_LOG" | sed 's/.*(\(.*\)).*/\1/' | sort -u | wc -l)
if [[ "$decodes" == "2" ]]; then
    nested_pass "wallpaper decoded per output, at each output's size — $(grep -a 'background: wallpaper' "$NESTED_SHELL_LOG" | sed 's/.* on /on /' | tr '\n' ' ')"
else
    nested_fail "$decodes distinct wallpaper decode sizes across two differently-sized outputs"
fi

echo
echo "hotplug, unlocked"

# 3 — an output arrives. The bar for it is a *new* window; the two already up
# must not be touched, because rebuilding a layer surface for an unrelated
# screen is the compositor-crash class the window discipline exists to avoid.
before_gone=$(log_count 'bar: window gone from')
nested_output_add "$HOTPLUG_SPEC" \
    || { nested_fail "could not plug $HOTPLUG in — the checks below have nothing to assert on"; exit 1; }

hotplug_logical=$(nested_output_logical "$HOTPLUG")
if nested_await "$NESTED_SHELL_LOG" "bar: window up on $HOTPLUG \(${hotplug_logical/x/×} " 15; then
    nested_pass "a bar arrived on the new output, at ${hotplug_logical/x/×}"
else
    nested_fail "no bar on $HOTPLUG after hotplug: $(grep -a 'bar: window up on' "$NESTED_SHELL_LOG" | tr '\n' ' ')"
fi

if [[ "$(log_count 'bar: window gone from')" == "$before_gone" ]]; then
    nested_pass "the other bars were left alone"
else
    nested_fail "plugging an output in disturbed another screen's bar: $(grep -a 'bar: window gone' "$NESTED_SHELL_LOG" | tr '\n' ' ')"
fi

# ...and leaves. A window that outlives its screen is the leak half: it is not
# visible anywhere, and it is still holding a layer surface and a focus-grab
# registration.
nested_output_remove "$HOTPLUG" \
    || { nested_fail "could not pull $HOTPLUG out — the checks below have nothing to assert on"; exit 1; }

if nested_await "$NESTED_SHELL_LOG" "bar: window gone from $HOTPLUG" 15; then
    nested_pass "the bar went away with its output"
else
    nested_fail "the bar for $HOTPLUG outlived the output — a leaked layer surface"
fi

live=$(live_surfaces 'bar: window up on' 'bar: window gone from')
if [[ "$live" == "2" ]]; then
    nested_pass "back to two bars, one per remaining output"
else
    nested_fail "$live bar windows live after the hotplug, wanted 2"
fi

if kill -0 "$NESTED_SHELL_PID" 2>/dev/null; then
    nested_pass "the shell survived an output arriving and leaving"
else
    nested_fail "the shell died on hotplug — $(grep -aiE 'wayland|fatal' "$NESTED_SHELL_LOG" | tail -2)"
fi

echo
echo "the lock, on both outputs"

# The lock runs under lock-harness.qml rather than the real shell, for its own
# reason: only that root exposes the conversation, and the shared buffer is the
# thing being asserted on. Everything under test — Lock.qml, LockAuth, the
# surface — is the real code either way.
#
# And it runs last, which is not an ordering preference. `ext-session-lock`
# keeps the session locked when its client dies — that is the guarantee the
# protocol exists for — so the nested compositor stays locked after the shell
# under test is killed, and the next shell to ask for a lock is refused and
# taken down with a protocol error (measured, by trying to run this phase in
# the middle). Nothing can follow a lock inside one nested session.
nested_kill_shell
mv "$NESTED_SHELL_LOG" "$NESTED_WORK/shell-bar.log" 2>/dev/null
nested_shell lock-harness.qml 'harness: lock harness ready' || exit 1

ipc lock lock > /dev/null

# 4 — covered, and covered *per output*. `secure` is the compositor's word for
# "every output is covered"; the two surface lines are what makes that word
# mean something on a session with more than one output to cover.
if nested_await "$NESTED_SHELL_LOG" 'lock: compositor confirms all screens covered' 15; then
    nested_pass "the compositor confirms every screen is covered — on two of them"
else
    nested_fail "the compositor never confirmed the lock (secure never went true)"
fi

for name in "$PRIMARY" "$SECOND"; do
    if nested_await "$NESTED_SHELL_LOG" "lock: surface up on $name" 15; then
        nested_pass "a lock surface came up on $name"
    else
        nested_fail "no lock surface on $name: $(grep -a 'lock: surface' "$NESTED_SHELL_LOG" | tr '\n' ' ')"
    fi
done

echo
echo "one buffer, two screens"

# 5 — the shared-state design, exercised for the first time. Keys are sent as
# real keystrokes into whichever surface holds keyboard focus, and focus is
# moved between outputs with `focusmonitor`, so what is being tested is two
# *surfaces* writing one buffer — not the IPC that lock-harness.sh uses, which
# writes the buffer directly and would pass on a design that gave every screen
# its own.
## What the lock currently has in the shared buffer, whichever surface put it
## there.
lock_buffer() { ipc locktest state | sed 's/.*"buffer":"\([^"]*\)".*/\1/'; }

typed=""
for want in "$PRIMARY:f:o:r" "$SECOND:e:s:t"; do
    IFS=: read -r name k1 k2 k3 <<< "$want"
    nested_hyprctl dispatch focusmonitor "$name" > /dev/null
    for key in "$k1" "$k2" "$k3"; do
        nested_key_focused "$key" > /dev/null
        typed+="$key"
    done

    # Polled rather than slept on, like every other wait here: a keystroke is
    # a compositor round trip and a shell round trip, and the fixed delay that
    # covers both on an idle machine is the one that goes flaky on a loaded
    # one.
    for _ in $(seq 1 50); do
        buffer=$(lock_buffer)
        [[ "$buffer" == "$typed" ]] && break
        sleep 0.1
    done

    if [[ "$buffer" == "$typed" ]]; then
        nested_pass "typing on $name reached the shared buffer: '$buffer'"
    else
        nested_fail "typed '$typed' across the screens, the buffer holds '$buffer'"
        break
    fi
done

# 6 — Enter on the *far* screen, submitting what was typed on the near one.
# One attempt, from two surfaces, which is the whole of what the shared state
# is for. The refusal comes from a faillock-free stack, so the count is the
# assertion and the account is untouched; `--attempt` runs the same check
# against the login stack.
#
# A machine with no such stack fails rather than notes: this is the ticket's
# headline claim, and a run that skips it while printing that the shell holds
# up on more than one screen is the empty assertion this harness exists to
# stop being.
if [[ -z "$PAM_STACK" ]]; then
    nested_fail "no faillock-free PAM stack here to submit against — run with --attempt to use the login stack"
else
    (( ATTEMPT )) && nested_note "submitting to the login stack — this counts against pam_faillock"
    before_attempts=$(log_count 'lock: password attempt')
    nested_hyprctl dispatch focusmonitor "$SECOND" > /dev/null
    nested_key_focused "Return" > /dev/null

    if nested_await "$NESTED_SHELL_LOG" 'lock: password attempt' 20; then
        attempts=$(( $(log_count 'lock: password attempt') - before_attempts ))
        if [[ "$attempts" == "1" ]]; then
            nested_pass "typed on $PRIMARY, submitted from $SECOND, one attempt: $(grep -a 'lock: password attempt' "$NESTED_SHELL_LOG" | tail -1 | sed 's/.*lock: //')"
        else
            nested_fail "one Enter produced $attempts attempts — the surfaces are not sharing one conversation"
        fi
    else
        nested_fail "Enter on $SECOND submitted nothing: $(grep -a 'lock: ' "$NESTED_SHELL_LOG" | tail -2 | tr '\n' ' ')"
    fi

    (( ATTEMPT )) && nested_note "clear the tally with: sudo faillock --user $USER --reset"
fi

echo
echo "hotplug, locked"

# 7 — an output arriving mid-lock. This is the case the code makes a claim
# about and no test has ever put under load: `WlSessionLockSurface` paints
# `Theme.bgBase` before its content loads so a new output is never a flash of
# white. Seam 2 cannot see the colour — that is seam 3's job — but it can see
# whether a surface is built for the new output at all, which is the difference
# between a flash and an uncovered screen.
nested_output_add "$HOTPLUG_SPEC" \
    || { nested_fail "could not plug $HOTPLUG in while locked"; exit 1; }

if nested_await "$NESTED_SHELL_LOG" "lock: surface up on $HOTPLUG" 15; then
    nested_pass "an output that arrived mid-lock was covered"
else
    nested_fail "$HOTPLUG came up uncovered while the session was locked"
fi

state=$(ipc locktest state)
if [[ "$state" == *'"secure":true'* ]]; then
    nested_pass "the lock stayed secure across the new output"
else
    nested_fail "the lock lost 'secure' when an output arrived — state: $state"
fi

nested_output_remove "$HOTPLUG" \
    || { nested_fail "could not pull $HOTPLUG out while locked"; exit 1; }

if nested_await "$NESTED_SHELL_LOG" "lock: surface gone from $HOTPLUG" 15; then
    nested_pass "the surface went away with its output"
else
    nested_fail "the lock surface for $HOTPLUG outlived the output"
fi

live=$(live_surfaces 'lock: surface up on' 'lock: surface gone from')
if [[ "$live" == "2" ]]; then
    nested_pass "two lock surfaces left, one per remaining output"
else
    nested_fail "$live lock surfaces live after the hotplug, wanted 2"
fi

state=$(ipc locktest state)
if [[ "$state" == *'"locked":true'* ]] && kill -0 "$NESTED_SHELL_PID" 2>/dev/null; then
    nested_pass "still locked, and the shell is still up"
else
    nested_fail "the lock or the shell did not survive hotplug while locked — state: $state"
fi

echo
if (( nested_fail_count )); then
    printf '\033[31m%d check(s) failed\033[0m\n' "$nested_fail_count"
    exit 1
fi
printf '\033[32mthe shell holds up on more than one screen\033[0m\n'
exit 0
