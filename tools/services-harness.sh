#!/usr/bin/env bash
# Bring the system services up inside a nested Hyprland, and check they are
# really running (#36, extended by #37).
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
#   2. each service logs that it is up — or that it is inert, on a machine that
#      has no such hardware
#   3. the bar carries #9's whole default inventory
#   4. the state each service reports is the state the machine is actually in,
#      cross-checked against the same fact read from outside the shell
#   5. volume and mic mute round-trip: set it, and the service says so
#   6. the backlight round-trips through `brightnessctl` — and a refusal is
#      logged as a refusal (#78: an exit code nothing reads is a failure
#      reported as success)
#   7. #37's four modules read the compositor they are running under: the
#      keyboard layout and the focused window are cross-checked against
#      `hyprctl` aimed at the nested instance, and the media pill's "nothing
#      playing is no module" rule is checked against the bus
#   8. the launcher and control-centre buttons say in the log that their
#      surfaces do not exist yet (#39, #44) — the graceful-no-op criterion
#   9. nothing logged a binding loop while all of them were live
#
# Two phases, because two things are being tested and only one of them can be
# driven: `shell.qml` is the real staged startup and is what proves 1-3, then
# `services-harness.qml` replaces it to prove 4-8 over IPC.
#
# **Check 6 moves the machine's own backlight.** A nested compositor is nested;
# the panel underneath it is not. The script reads what it finds, nudges one
# step, and puts it back — `--no-backlight` skips it entirely.
#
# What no seam covers, and this one least of all: the idle budget (≤ 0.5 % CPU,
# < 5 wakeups/s with all of them running). Wakeups are a property of a real session
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

## Wait for a log line written *after* a mark, so a check cannot be satisfied by
## a line the startup already wrote. `wc -l` is the mark: the log only grows.
await_since() {
    local mark="$1" pattern="$2" timeout="${3:-10}"
    local deadline=$((SECONDS + timeout))
    while (( SECONDS < deadline )); do
        if tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qaE "$pattern"; then
            return 0
        fi
        sleep 0.25
    done
    return 1
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

# The tray and the media pill are the two modules whose contents belong to other
# applications, and a machine with neither exercises only the shell's half of
# them. `tools/fake-dbus-clients.py` is the other half: one StatusNotifierItem
# and one MPRIS player, on the **session** bus — which is shared with the
# desktop running this, so they briefly appear in whatever else is watching.
#
# Started before the shell, because the ordering is part of what is being
# checked: an application that registered its icon before the tray host did must
# still turn up (Core/ServiceInit.qml's argument for constructing the tray at
# all).
FAKE_CLIENTS_PID=""
if python3 -c 'import dbus, gi' 2>/dev/null; then
    python3 "$(dirname "${BASH_SOURCE[0]}")/fake-dbus-clients.py" both \
        > "$NESTED_WORK/fake-clients.log" 2>&1 &
    FAKE_CLIENTS_PID=$!
    nested_await "$NESTED_WORK/fake-clients.log" 'mpris org.mpris' 5 || true
    nested_note 'a fake tray item and a fake media player are on the session bus'
    # Chained onto the teardown the nested session installed, not over it: a
    # trap that replaced it would leave a nested Hyprland running.
    trap 'kill "$FAKE_CLIENTS_PID" 2>/dev/null; nested_down' EXIT
else
    nested_note 'no python dbus bindings — the tray and media checks read the empty case'
fi

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

# The count is written out rather than derived, so that a service which stops
# being constructed fails this check instead of silently shrinking it. The cost
# is that it has to be updated by the ticket that adds one — and it was not:
# #40 took the list from ten to twelve (Apps, Calculator) and left this at ten,
# so the check has been red on main since it landed. #41 makes it thirteen.
deferred_line=$(grep -a 'services: deferred stage' "$NESTED_SHELL_LOG" | head -1)
# Eighteen since #48: PowerProfiles, NightLight and Vpn joined with #44, and
# LogindBridge and Idle with the idle ladder — each for a reason
# Core/ServiceInit.qml states beside it. The number is asserted rather than a
# lower bound because the whole point of the list is that a service which
# quietly stopped being constructed is invisible otherwise.
#
# Counted against `report("deferred", [...])` rather than taken from the log the
# check is reading, which is the only way round that catches a service going
# missing; #49 found it red and at sixteen, exactly as the note above predicts.
#
# Twenty-five since Weather, Screenshot and Recorder joined it — and it stayed
# at eighteen while they did, so this check has been red on main for exactly the
# reason its own note gives: the number is updated by the ticket that adds a
# service, and it was not. Counted off `report("deferred", [...])` again here.
# It is a bookkeeping fix rather than #141's, but a check that is always red is
# a check nobody reads, which is what #141 is about at the other seam.
if [[ "$deferred_line" == *"25 object(s)"* ]]; then
    nested_pass 'the deferred stage constructs all twenty-five services'
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
# #37's two. The tray line is the one that matters most: the StatusNotifier host
# is registered by the singleton being touched, so a tray that logs nothing is a
# tray no application can ever appear in.
expect_log 'tray: statusnotifier host registered' 'the tray registers a statusnotifier host'
expect_log 'media: mpris facade ready' 'the mpris facade reports its state'

# 3 — the bar carries them. The registry resolves names from config, and a
# module that fails to load drops out with a warning rather than taking the bar
# with it — which means a broken module looks like a bar that is merely quiet.
# 3/2/6 since #43 put the notification indicator in the default right cluster
# (Core/SettingsSchema.qml). The count was left at 3/2/5 by that ticket and this
# harness has been red on it since; corrected here because #44 is the next thing
# to run it.
if grep -qaE 'bar: content ready on .* \(3/2/6 modules\)' "$NESTED_SHELL_LOG"; then
    nested_pass 'the bar carries the whole default inventory (#9, completed by #37)'
else
    nested_fail "the default bar is not 3/2/6 modules: $(grep -a 'bar: content ready' "$NESTED_SHELL_LOG" | head -1)"
fi

# A name the registry does not know is dropped with a warning, and the default
# layout must never be the thing that trips it (tests/tst_barregistry.qml checks
# the same claim against the schema; this checks it against the shell that
# actually resolved it).
if grep -qa 'bar: no such module' "$NESTED_SHELL_LOG"; then
    nested_fail "the default bar names a module the registry does not have: $(grep -a 'bar: no such module' "$NESTED_SHELL_LOG" | head -1)"
else
    nested_pass 'every module in the default bar is one the registry knows'
fi

# The tray delegate is the one piece of #37 that only exists when an application
# has registered an icon: with an empty tray the Repeater builds nothing, and a
# mistyped property inside it would never be evaluated. With the fake item on the
# bus it is built, and a bad binding shows up here as a QML warning naming the
# file.
if [[ -n "$FAKE_CLIENTS_PID" ]]; then
    if grep -qaE '(Tray|Media|ActiveWindow|KeyboardLayout|LauncherButton|ControlCenterButton)\.qml:[0-9]+' \
            "$NESTED_SHELL_LOG"; then
        nested_fail "a #37 module reported a QML error: $(grep -aE '(Tray|Media|ActiveWindow|KeyboardLayout|LauncherButton|ControlCenterButton)\.qml:[0-9]+' "$NESTED_SHELL_LOG" | head -1)"
    else
        nested_pass 'the tray delegate builds against a real item without complaint'
    fi
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

nested_kill_shell

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

# The scan's *result*, not just its start (#141). Switching the scanner on was
# logged and what came back never was, so a scan that saw four access points and
# one that saw none read the same from the log — and the Wi-Fi half of #136's
# manual pass had to be evidenced against `nmcli` from outside the shell.
#
# Held and let go through the same two calls the drill-in makes, so this is the
# real scanner rather than a read of the candidate list.
if [[ "$(snapshot_field "$snapshot" network.wifiEnabled)" == "true" ]]; then
    mark=$(wc -l < "$NESTED_SHELL_LOG")
    ipc wifiScan true > /dev/null
    if await_since "$mark" 'network: scanning' 5; then
        nested_pass 'a scan says it started'
    else
        nested_fail 'the scanner was switched on and said nothing'
    fi

    # Twenty seconds: NetworkManager answers a fresh scan in a few, and a
    # machine whose last scan is still warm answers immediately.
    if await_since "$mark" 'network: (no networks|[0-9]+ networks?) visible' 20; then
        nested_pass "a scan says what it found: $(tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" \
            | grep -aoE '(no networks|[0-9]+ networks?) visible' | tail -1) (#141)"
    else
        nested_fail 'a scan returned and the log cannot say whether it found anything (#141)'
    fi
    ipc wifiScan false > /dev/null
else
    nested_note 'the wifi radio is off — the scan-result check is skipped'
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
    # 5b — the *mixer's* half of it (#141). Per-app volume and per-app mute
    # changed real PipeWire state and logged nothing, so a set that worked and a
    # set that hit the wrong node looked identical from outside — the #81 shape
    # this seam exists to catch.
    #
    # A stream to move is made rather than found: a machine with nothing playing
    # has no mixer rows at all, and one with a real player has rows belonging to
    # the developer's own music. `pw-play` on a few seconds of generated silence
    # is a sink-input like any other, and inaudible either way.
    if command -v pw-play >/dev/null 2>&1; then
        silence="$NESTED_WORK/silence.wav"
        python3 -c '
import struct, sys, wave
with wave.open(sys.argv[1], "wb") as out:
    out.setnchannels(1)
    out.setsampwidth(2)
    out.setframerate(48000)
    out.writeframes(b"\x00\x00" * 48000 * 60)
' "$silence"

        before_ids=$(snapshot_field "$(ipc snapshot)" audio.streams)
        pw-play "$silence" > "$NESTED_WORK/pw-play.log" 2>&1 &
        PW_PLAY_PID=$!

        # The new row, by difference: the id is PipeWire's node id and nothing
        # outside PipeWire can predict it, and a machine that already had
        # streams must not have one of those picked instead.
        stream_id=""
        for _ in $(seq 1 40); do
            stream_id=$(python3 -c '
import json, sys
try:
    before = {row["id"] for row in json.loads(sys.argv[1])}
    now = json.loads(sys.argv[2])
except (ValueError, KeyError, TypeError):
    sys.exit(0)
for row in now:
    if row["id"] not in before:
        print(row["id"])
        break
' "$before_ids" "$(snapshot_field "$(ipc snapshot)" audio.streams)")
            [[ -n "$stream_id" ]] && break
            sleep 0.25
        done

        if [[ -z "$stream_id" ]]; then
            nested_note 'pw-play never became a mixer row — the per-app checks are skipped'
        else
            stream_row() {
                python3 -c '
import json, sys
for row in json.loads(sys.argv[1]):
    if row["id"] == sys.argv[2]:
        print(row[sys.argv[3]] if isinstance(row[sys.argv[3]], str)
              else json.dumps(row[sys.argv[3]]))
        break
' "$(snapshot_field "$(ipc snapshot)" audio.streams)" "$stream_id" "$1"
            }
            stream_name=$(stream_row name)
            nested_note "a generated stream is on the mixer: $stream_name (node $stream_id)"

            mark=$(wc -l < "$NESTED_SHELL_LOG")
            ipc streamVolume "$stream_id" 35 > /dev/null
            sleep 0.4
            moved=$(stream_row percent)
            if [[ "$moved" == "35" ]]; then
                nested_pass 'a per-app volume reaches pipewire and reads back'
            else
                nested_fail "set the stream to 35%, the node reports $moved%"
            fi
            if tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qaE "audio: stream .* 35%"; then
                nested_pass 'the per-app volume says so in the log (#141)'
            else
                nested_fail 'a per-app volume changed pipewire and logged nothing (#141)'
            fi

            mark=$(wc -l < "$NESTED_SHELL_LOG")
            ipc streamMute "$stream_id" > /dev/null
            sleep 0.4
            if [[ "$(stream_row muted)" == "true" ]]; then
                nested_pass 'a per-app mute reaches pipewire and reads back'
            else
                nested_fail 'the stream did not mute'
            fi
            if tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qaE "audio: stream .* muted"; then
                nested_pass 'the per-app mute says so in the log (#141)'
            else
                nested_fail 'a per-app mute changed pipewire and logged nothing (#141)'
            fi

            # And back. The unmute is its own assertion rather than tidying:
            # "muted" and "unmuted" being distinguishable in the log is the
            # whole of what #141 asks for, and a line that said `muted` both
            # times would pass the check above.
            mark=$(wc -l < "$NESTED_SHELL_LOG")
            ipc streamMute "$stream_id" > /dev/null
            sleep 0.4
            if tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qaE "audio: stream .* unmuted"; then
                nested_pass 'the per-app unmute is a different line from the mute (#141)'
            else
                nested_fail 'an unmute logged nothing, or logged the same line as the mute (#141)'
            fi
        fi

        # The refusal, which has always been logged — asserted here so that a
        # success line added on top of it cannot quietly replace it.
        mark=$(wc -l < "$NESTED_SHELL_LOG")
        ipc streamVolume 99999999 50 > /dev/null
        sleep 0.3
        if tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qa 'stream 99999999 unchanged'; then
            nested_pass 'a set on a stream that is not there is refused, in the log'
        else
            nested_fail 'a set on a missing stream logged nothing'
        fi

        [[ -n "${PW_PLAY_PID:-}" ]] && kill "$PW_PLAY_PID" 2>/dev/null
    else
        nested_note 'no pw-play on this machine — the per-app mixer checks are skipped'
    fi
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

# 7 — #37's modules, against the compositor they are reading. The keyboard
# layout and the focused window are the two facts here that the *nested* session
# owns, so both are cross-checked against `hyprctl` aimed at that instance
# rather than at the machine's own session.
snapshot=$(ipc snapshot)

hypr_layout=$(nested_hyprctl -j devices 2>/dev/null | python3 -c '
import json, sys
try:
    keyboards = json.load(sys.stdin).get("keyboards", [])
except ValueError:
    sys.exit(0)
main = next((k for k in keyboards if k.get("main")), keyboards[0] if keyboards else None)
if main:
    layouts = [x.strip() for x in str(main.get("layout", "")).split(",") if x.strip()]
    index = main.get("active_layout_index", 0)
    index = index if isinstance(index, int) and 0 <= index < len(layouts) else 0
    print("%s|%s" % (main.get("name", ""), layouts[index].upper() if layouts else ""))
' || true)
hypr_device="${hypr_layout%%|*}"
hypr_code="${hypr_layout##*|}"
shell_device=$(snapshot_field "$snapshot" keyboard.device)

if [[ -z "$hypr_layout" ]]; then
    nested_note 'the nested compositor reported no keyboards — the layout checks are skipped'
elif [[ "$shell_device" == "$hypr_device" ]]; then
    nested_pass "the shell reads the compositor's main keyboard ($hypr_device)"
    shell_code=$(snapshot_field "$snapshot" keyboard.layout)
    switchable=$(snapshot_field "$snapshot" keyboard.switchable)
    if [[ "$switchable" == "true" && "$shell_code" == "$hypr_code" ]]; then
        nested_pass "the layout module shows the live layout ($shell_code)"
    elif [[ "$switchable" == "false" ]]; then
        # The single-layout machine, which is the acceptance criterion: the
        # module is off the bar, and asking it to cycle says so rather than
        # dispatching a switch that would do nothing.
        nested_pass 'one layout configured — the module is hidden (#37)'
        mark=$(wc -l < "$NESTED_SHELL_LOG")
        ipc cycleLayout > /dev/null
        sleep 0.3
        if tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qa 'one keyboard layout'; then
            nested_pass 'a cycle with nothing to cycle to is refused, in the log'
        else
            nested_fail 'a cycle on a single-layout machine logged nothing'
        fi
    else
        nested_fail "the shell says layout $shell_code, hyprctl says $hypr_code"
    fi
else
    nested_fail "the shell read keyboard '$shell_device', hyprctl says '$hypr_device'"
fi

# The same path with two layouts, which is the case the module exists for and
# the one no single-layout machine can reach. The nested compositor is given a
# second layout live, and switched from *outside* the shell — that is what makes
# this a test of the `activelayout` wiring rather than of the dispatch: nothing
# tells the shell what happened except the event.
if [[ "$(snapshot_field "$snapshot" keyboard.switchable)" == "false" && -n "$hypr_layout" ]]; then
    if nested_hyprctl keyword input:kb_layout "us,de" | grep -qa '^ok'; then
        nested_hyprctl switchxkblayout current next > /dev/null
        two_layouts=""
        for _ in $(seq 1 25); do
            two_layouts=$(ipc snapshot)
            [[ "$(snapshot_field "$two_layouts" keyboard.switchable)" == "true" ]] && break
            sleep 0.2
        done

        if [[ "$(snapshot_field "$two_layouts" keyboard.switchable)" == "true" ]]; then
            nested_pass "a second layout appears without being asked ($(snapshot_field "$two_layouts" keyboard.layout))"

            before=$(snapshot_field "$two_layouts" keyboard.layout)
            ipc cycleLayout > /dev/null
            after="$before"
            for _ in $(seq 1 25); do
                after=$(snapshot_field "$(ipc snapshot)" keyboard.layout)
                [[ "$after" != "$before" ]] && break
                sleep 0.2
            done
            if [[ "$after" != "$before" ]]; then
                nested_pass "the module's click cycles the layout ($before → $after)"
            else
                nested_fail "a cycle left the layout at $before"
            fi
        else
            nested_fail 'a second layout was configured and the shell never noticed'
        fi

        nested_hyprctl keyword input:kb_layout "${hypr_code,,}" > /dev/null
    else
        nested_note 'the nested compositor refused a second layout — the cycle check is skipped'
    fi
fi

# The focused window. A bare nested session has no windows at all, and the
# module is *supposed* to be absent then — so the empty case is the assertion,
# and a session with something focused is checked against its title.
#
# One is spawned where there is a terminal to spawn, because "tracks focus" is
# the criterion and an empty session only proves the other half of it.
terminal=$(command -v kitty || command -v alacritty || command -v foot || true)
if [[ -n "$terminal" ]]; then
    nested_hyprctl dispatch exec "$terminal" > /dev/null
    for _ in $(seq 1 40); do
        [[ -n "$(snapshot_field "$(ipc snapshot)" window.title)" ]] && break
        sleep 0.25
    done
    snapshot=$(ipc snapshot)
else
    nested_note 'no terminal to open in the nested session — the focus check reads the empty case'
fi

## What the nested compositor says is focused, in the shape the module shows it:
## the title, or the window class where the application has not set one.
focused_title() {
    nested_hyprctl -j activewindow 2>/dev/null | python3 -c '
import json, sys
try:
    window = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
print(" ".join(str(window.get("title") or window.get("class") or "").split()))
' || true
}

# Retried, because a window that has just mapped renames itself once or twice as
# its shell starts up — the two readings are taken a moment apart, and a
# disagreement is only interesting if it survives the title settling.
for _ in $(seq 1 10); do
    hypr_title=$(focused_title)
    shell_title=$(snapshot_field "$(ipc snapshot)" window.title)
    [[ "$shell_title" == "$hypr_title" ]] && break
    sleep 0.3
done
if [[ "$shell_title" == "$hypr_title" ]]; then
    if [[ -z "$hypr_title" ]]; then
        nested_pass 'nothing is focused, and the window module has nothing to show'
    else
        nested_pass "the window module tracks the focused window ($shell_title)"
    fi
else
    nested_fail "the window module says '$shell_title', hyprctl says '$hypr_title'"
fi

# The tray, against the item that was put on the bus before the shell started.
tray_count=$(snapshot_field "$snapshot" tray.count)
if [[ -z "$FAKE_CLIENTS_PID" ]]; then
    nested_note "no fake clients — the tray host holds $tray_count item(s)"
elif [[ "$tray_count" -ge 1 ]]; then
    nested_pass "the tray host picked up the item that registered before it ($tray_count item(s))"

    # Activation, which is the other half of the first acceptance criterion.
    # Asserted on the *item's* side: what matters is that the application heard
    # the click, and the shell reporting that it sent one is not that.
    meant=$(ipc trayPress left)
    sleep 0.5
    if [[ "$meant" == *activate* ]] && grep -qa '^activated' "$NESTED_WORK/fake-clients.log"; then
        nested_pass 'a left click on a tray icon reaches the application'
    else
        nested_fail "a left click meant '$meant' and the item never heard it"
    fi

    ipc trayPress middle > /dev/null
    sleep 0.5
    if grep -qa '^secondary-activated' "$NESTED_WORK/fake-clients.log"; then
        nested_pass 'a middle click reaches the application'\''s secondary action'
    else
        nested_fail 'a middle click never reached the item'
    fi

    # The fake item exports no menu, which is the case the policy answers
    # "none" for — and the shell must say so rather than silently doing
    # nothing (#81).
    mark=$(wc -l < "$NESTED_SHELL_LOG")
    right=$(ipc trayPress right)
    sleep 0.3
    if [[ "$right" == *none* ]] \
            && tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qa 'has no menu'; then
        nested_pass 'a right click on an item with no menu is refused, in the log'
    else
        nested_fail "a right click on a menuless item answered '$right' and logged nothing"
    fi
else
    nested_fail 'a tray item was on the bus before the shell started and the tray never saw it'
fi

# The media pill, against the player. Both halves of its rule are checked: what
# it says while something is playing, and that a click reaches the player —
# which is the acceptance criterion, and the one thing about this module that a
# snapshot alone cannot show.
players=$(snapshot_field "$snapshot" media.players)
showing=$(snapshot_field "$snapshot" media.showing)
if [[ -z "$FAKE_CLIENTS_PID" ]]; then
    if [[ "$players" == "0" && "$showing" == "false" ]]; then
        nested_pass 'nothing is playing, and the media pill is off the bar (#37)'
    else
        nested_note "$players player(s) on this machine — showing \"$(snapshot_field "$snapshot" media.label)\""
    fi
elif [[ "$showing" == "true" && "$(snapshot_field "$snapshot" media.label)" == *"Test Track"* ]]; then
    nested_pass "the media pill shows the playing track (\"$(snapshot_field "$snapshot" media.label)\")"

    was_playing=$(snapshot_field "$snapshot" media.playing)
    was_icon=$(snapshot_field "$snapshot" media.icon)
    ipc playPause > /dev/null
    now_playing="$was_playing"
    for _ in $(seq 1 25); do
        now_playing=$(snapshot_field "$(ipc snapshot)" media.playing)
        [[ "$now_playing" != "$was_playing" ]] && break
        sleep 0.2
    done
    now_icon=$(snapshot_field "$(ipc snapshot)" media.icon)
    if [[ "$now_playing" != "$was_playing" && "$now_icon" != "$was_icon" ]]; then
        nested_pass "a click on the pill reaches the player ($was_icon → $now_icon)"
    else
        nested_fail "play/pause left the player at playing=$now_playing icon=$now_icon"
    fi
    ipc playPause > /dev/null

    # "Hidden when nothing plays" (#37), against the case that decides it: a
    # player that stops keeps its name and its metadata on the bus, so a pill
    # that read only the track would stay on the bar forever.
    busctl --user call org.mpris.MediaPlayer2.foresttest /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2.Player Stop > /dev/null 2>&1
    stopped_showing="true"
    for _ in $(seq 1 25); do
        stopped_showing=$(snapshot_field "$(ipc snapshot)" media.showing)
        [[ "$stopped_showing" == "false" ]] && break
        sleep 0.2
    done
    if [[ "$stopped_showing" == "false" ]]; then
        nested_pass 'a player that stops takes the pill off the bar, name still on the bus'
    else
        nested_fail 'the player stopped and the pill stayed on the bar'
    fi
    busctl --user call org.mpris.MediaPlayer2.foresttest /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2.Player Play > /dev/null 2>&1
else
    nested_fail "a player is on the bus and the pill says showing=$showing players=$players"
fi

# 8 — the two buttons whose surfaces do not exist yet (#39, #44). The criterion
# is a *logged* no-op: a button that does nothing quietly is indistinguishable
# from a button that is broken (#81).
for surface in launcher controlcenter; do
    mark=$(wc -l < "$NESTED_SHELL_LOG")
    ipc surface "$surface" > /dev/null
    sleep 0.3
    if tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qa "surfaces: no .* surface yet — ignoring toggle"; then
        nested_pass "the $surface button says in the log that its surface is not built yet"
    else
        nested_fail "pressing the $surface button logged nothing"
    fi
done

# `dashboard` until #49 declared it, and the name has to stay one nobody has:
# an undeclared name that quietly becomes a declared one turns this into "a
# surface that exists reads as a shell bug", which passes for the wrong reason.
mark=$(wc -l < "$NESTED_SHELL_LOG")
ipc surface notepad > /dev/null
sleep 0.3
if tail -n "+$((mark + 1))" "$NESTED_SHELL_LOG" | grep -qa 'no such surface: notepad'; then
    nested_pass 'a surface nobody declared reads as a shell bug rather than a missing one'
else
    nested_fail 'an undeclared surface name was accepted silently'
fi

# 9 — nothing is fighting itself. A binding loop is a warning rather than a
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
