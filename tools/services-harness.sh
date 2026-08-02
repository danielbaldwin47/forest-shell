#!/usr/bin/env bash
# Bring the five system services up inside a nested Hyprland, and check they
# are really running (#36).
#
#   tools/services-harness.sh                 # run the checks, print PASS/FAIL
#   tools/services-harness.sh --keep          # leave the session up to poke at
#   tools/services-harness.sh --no-backlight  # skip the one check that moves hardware
#
# This is the second seam. Everything here needs something `tests/` cannot have:
# a PipeWire socket, a NetworkManager on DBus, a BlueZ adapter, UPower, and a
# subprocess that writes to /sys. What *can* be decided without any of that —
# which glyph, what a step is, how a `brightnessctl` reply parses — is in the
# `*Policy.qml` file beside each service and is checked in `tests/`.
#
# What it asserts:
#
#   1. the services construct in the **deferred** stage, not the sync one
#   2. each of the five logs that it is up — or that it is inert, on a machine
#      that has no such hardware
#   3. the bar carries the status cluster and the battery by default
#   4. the state each service reports is the state the machine is actually in,
#      cross-checked against the same fact read from outside the shell
#   5. volume and mic mute round-trip: set it, and the service says so
#   6. the backlight round-trips through `brightnessctl` — and a refusal is
#      logged as a refusal (#78: an exit code nothing reads is a failure
#      reported as success)
#   7. nothing logged a binding loop while all five were live
#
# Two phases, because two things are being tested and only one of them can be
# driven: `shell.qml` is the real staged startup and is what proves 1-3, then
# `services-harness.qml` replaces it to prove 4-6 over IPC.
#
# **Check 6 moves the machine's own backlight.** A nested compositor is nested;
# the panel underneath it is not. The script reads what it finds, nudges one
# step, and puts it back — `--no-backlight` skips it entirely.
#
# What no seam covers, and this one least of all: the idle budget (≤ 0.5 % CPU,
# < 5 wakeups/s with all five running). Wakeups are a property of a real session
# over minutes, measured the way #95 measures them, and a nested compositor that
# never presents a frame (see tools/nested-session.sh) cannot stand in for one.
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

CHECK_BACKLIGHT=1
for arg in "$@"; do
    case "$arg" in
        --keep)          NESTED_KEEP=1 ;;
        --no-backlight)  CHECK_BACKLIGHT=0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

ipc() { nested_ipc call servicetest "$@"; }

## One field out of the snapshot JSON. Every assertion goes through this rather
## than grepping the raw reply, so a *client* failure — an error string where
## JSON was expected — fails the check instead of trivially satisfying it.
snapshot_field() {
    local snapshot="$1" path="$2"
    python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
except ValueError:
    sys.exit(1)
for key in sys.argv[2].split("."):
    if not isinstance(data, dict) or key not in data:
        sys.exit(1)
    data = data[key]
# json.dumps rather than str: a Python bool prints as "True", and every
# comparison below is against the JSON spelling the shell itself uses.
print(data if isinstance(data, str) else json.dumps(data))
' "$snapshot" "$path"
}

## Assert a log line arrived, and say what it was about.
expect_log() {
    local pattern="$1" what="$2" timeout="${3:-15}"
    if nested_await "$NESTED_SHELL_LOG" "$pattern" "$timeout"; then
        nested_pass "$what"
    else
        nested_fail "$what — no line matching /$pattern/"
    fi
}

nested_up || exit 1

# --- phase one: the real shell, staged the way it really starts --------------

nested_shell shell.qml 'startup: stage interactive' || exit 1

echo
# 1 — staging. The sync stage is on the critical path to the wallpaper (#22 §4);
# a service that constructed there would be a service delaying the first frame.
sync_line=$(grep -a 'services: sync stage' "$NESTED_SHELL_LOG" | head -1)
if [[ "$sync_line" == *"0 object(s)"* ]]; then
    nested_pass 'the sync stage constructs no services'
else
    nested_fail "a service constructed in the sync stage: ${sync_line:-<no line>}"
fi

deferred_line=$(grep -a 'services: deferred stage' "$NESTED_SHELL_LOG" | head -1)
if [[ "$deferred_line" == *"8 object(s)"* ]]; then
    nested_pass 'the deferred stage constructs all eight services'
else
    nested_fail "the deferred stage is not what it should be: ${deferred_line:-<no line>}"
fi

# Ordering, not just membership: "deferred" is a claim about *when*, and the
# only evidence for it is that the first frame was already painted.
if grep -a -n -E 'startup: stage (first frame painted|deferred begin)|services: deferred stage' \
        "$NESTED_SHELL_LOG" | head -3 | tail -1 | grep -qa 'services: deferred stage'; then
    nested_pass 'the services construct after the first frame'
else
    nested_fail 'the deferred stage did not follow the first painted frame'
fi

# 2 — each service says it is up, or says it is inert. Both are a line: a
# service that logs nothing is one whose failure has two candidate causes (#81).
expect_log 'audio: (pipewire facade ready|waiting for pipewire)' 'the audio facade reports its state'
expect_log 'network: (networkmanager facade ready|no networkmanager)' 'the network facade reports its state'
expect_log 'bluetooth: (bluez facade ready|no bluetooth adapter)' 'the bluetooth facade reports its state'
expect_log 'power: upower facade ready' 'the power facade reports its state'
expect_log 'backlight: (panel |no backlight device)' 'the backlight facade reports its state'

# 3 — the bar carries them. The registry resolves names from config, and a
# module that fails to load drops out with a warning rather than taking the bar
# with it — which means a broken module looks like a bar that is merely quiet.
if grep -qaE 'bar: content ready on .* \(1/1/2 modules\)' "$NESTED_SHELL_LOG"; then
    nested_pass 'the bar carries the status cluster and the battery by default'
else
    nested_fail "the default bar is not 1/1/2 modules: $(grep -a 'bar: content ready' "$NESTED_SHELL_LOG" | head -1)"
fi

if grep -qa 'module failed to load' "$NESTED_SHELL_LOG"; then
    nested_fail "a bar module failed to load: $(grep -a 'module failed to load' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'every module named in the default bar loaded'
fi

# --- phase two: the same services, driven ------------------------------------
#
# The real shell has no IPC door onto a volume or a backlight — the control
# centre (#44) is what will — so the drive checks run against the harness root,
# which constructs the same singletons through the same ServiceInit call.

kill "$NESTED_SHELL_PID" 2>/dev/null
wait "$NESTED_SHELL_PID" 2>/dev/null

nested_shell services-harness.qml 'harness: services harness ready' || exit 1

# The native backends answer about a second after they are first touched
# (measured: UPower, NetworkManager and BlueZ all populate ~1s in), so the first
# snapshot is polled for rather than taken.
snapshot=""
for _ in $(seq 1 50); do
    snapshot=$(ipc snapshot)
    [[ "$(snapshot_field "$snapshot" power.hasBattery)" == "true" ]] && break
    [[ "$(snapshot_field "$snapshot" network.available)" == "true" ]] && break
    sleep 0.2
done

echo
if ! snapshot_field "$snapshot" audio.ready > /dev/null; then
    nested_fail "the harness did not answer with a snapshot — $snapshot"
    printf '\n%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
nested_pass 'the services answer with a state snapshot'

# 4 — the state is the machine's, not a plausible-looking default. Each of these
# reads the same fact from outside the shell: a service that reported 0% for
# everything would otherwise pass every check above.
battery_present=$([[ -d /sys/class/power_supply/BAT0 ]] && echo true || echo false)
if [[ "$(snapshot_field "$snapshot" power.hasBattery)" == "$battery_present" ]]; then
    nested_pass "the power service agrees with /sys about whether there is a battery ($battery_present)"
else
    nested_fail "power.hasBattery is $(snapshot_field "$snapshot" power.hasBattery), /sys says $battery_present"
fi

if [[ "$battery_present" == "true" ]]; then
    sys_percent=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "")
    shell_percent=$(snapshot_field "$snapshot" power.percent)
    # Not equality: `displayDevice` is UPower's aggregate and this laptop has
    # two batteries, so the shell's number is the pair's and BAT0's is one of
    # them. What is being checked is that it is a real reading rather than a
    # zero — anything in range, from a machine reporting the same order.
    if [[ -n "$shell_percent" && "$shell_percent" -gt 0 && "$shell_percent" -le 100 ]]; then
        nested_pass "the power service reports a live charge ($shell_percent%, BAT0 at ${sys_percent:-?}%)"
    else
        nested_fail "the power service reports $shell_percent% with a battery present"
    fi
fi

wifi_expected=$(nmcli radio wifi 2>/dev/null)
wifi_reported=$(snapshot_field "$snapshot" network.wifiEnabled)
if [[ -z "$wifi_expected" ]]; then
    nested_note "no nmcli to cross-check the wifi radio against — the shell says $wifi_reported"
else
    wifi_state=$([[ "$wifi_expected" == "enabled" ]] && echo true || echo false)
    if [[ "$wifi_state" == "$wifi_reported" ]]; then
        nested_pass "the network service agrees with nmcli about the wifi radio ($wifi_expected)"
    else
        nested_fail "the shell says wifiEnabled=$wifi_reported, nmcli says $wifi_expected"
    fi
fi

bt_expected=$([[ -n "$(ls /sys/class/bluetooth 2>/dev/null)" ]] && echo true || echo false)
if [[ "$(snapshot_field "$snapshot" bluetooth.present)" == "$bt_expected" ]]; then
    nested_pass "the bluetooth service agrees with /sys about the adapter ($bt_expected)"
else
    nested_fail "bluetooth.present is $(snapshot_field "$snapshot" bluetooth.present), /sys says $bt_expected"
fi

# 5 — volume and mic round-trip. A set that did not reach PipeWire is the whole
# failure mode here: the tracker is what makes those properties live, and
# without it every read is a plausible zero (#4 §2.5).
if [[ "$(snapshot_field "$snapshot" audio.hasSink)" == "true" ]]; then
    was_volume=$(snapshot_field "$snapshot" audio.percent)
    ipc volume 42 > /dev/null
    sleep 0.4
    now_volume=$(snapshot_field "$(ipc snapshot)" audio.percent)
    if [[ "$now_volume" == "42" ]]; then
        nested_pass 'a volume set reaches pipewire and reads back'
    else
        nested_fail "set the volume to 42%, the service reports $now_volume%"
    fi

    ipc micMute true > /dev/null
    sleep 0.4
    if [[ "$(snapshot_field "$(ipc snapshot)" audio.sourceMuted)" == "true" ]]; then
        nested_pass 'a mic mute reaches pipewire and reads back'
    else
        nested_fail 'the mic did not mute'
    fi
    ipc micMute false > /dev/null
    ipc volume "$was_volume" > /dev/null
    nested_note "volume put back to $was_volume%"
else
    nested_note 'no default sink on this machine — the audio checks are skipped'
fi

# 6 — the backlight, through the subprocess. This is the one check that moves
# hardware, and the one that would have caught #78's class of bug: a
# `brightnessctl` that refused must log a refusal.
if (( CHECK_BACKLIGHT )) && [[ "$(snapshot_field "$snapshot" backlight.available)" == "true" ]]; then
    device=$(snapshot_field "$snapshot" backlight.device)
    was_raw=$(cat "/sys/class/backlight/$device/brightness" 2>/dev/null)
    was_percent=$(snapshot_field "$snapshot" backlight.percent)

    sysfs_percent=$(python3 -c "
import sys
raw, mx = int(sys.argv[1]), int(sys.argv[2])
print(round(raw / mx * 100))
" "$(cat "/sys/class/backlight/$device/actual_brightness")" "$(cat "/sys/class/backlight/$device/max_brightness")")
    if [[ "$was_percent" == "$sysfs_percent" ]]; then
        nested_pass "the backlight service reads the panel ($device at $was_percent%)"
    else
        nested_fail "the service says $was_percent%, /sys says $sysfs_percent%"
    fi

    mark=$(wc -l < "$NESTED_SHELL_LOG")
    ipc nudgeBrightness 1 > /dev/null
    sleep 0.6
    stepped=$(snapshot_field "$(ipc snapshot)" backlight.percent)
    if [[ "$stepped" != "$was_percent" ]] \
            && tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qa "backlight $device set to"; then
        nested_pass "a step up moved the panel and logged it ($was_percent% → $stepped%)"
    else
        nested_fail "a step up left the panel at $stepped% (was $was_percent%)"
    fi

    ipc brightness "$was_percent" > /dev/null
    sleep 0.6
    # Back to the raw value rather than the percent, because a percent is a
    # rounding of it and the machine should be left exactly as it was found.
    brightnessctl -q -d "$device" set "$was_raw" 2>/dev/null
    nested_note "panel put back to raw $was_raw"
elif (( CHECK_BACKLIGHT )); then
    nested_note 'no backlight on this machine — the brightness checks are skipped'
else
    nested_note 'brightness checks skipped by request'
fi

# 7 — nothing is fighting itself. A binding loop is a warning rather than a
# failure, so it would otherwise pass unnoticed until the bar visibly flickered.
if grep -qa 'Binding loop' "$NESTED_SHELL_LOG"; then
    nested_fail "a binding loop was reported: $(grep -a 'Binding loop' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'no binding loops while the services were live'
fi

printf '\n'
if (( nested_fail_count )); then
    printf '%s check(s) failed — shell log: %s\n' "$nested_fail_count" "$NESTED_SHELL_LOG"
    exit 1
fi
printf 'all service checks passed\n'
exit 0
