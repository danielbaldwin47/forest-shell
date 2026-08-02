#!/usr/bin/env bash
# Post real notifications at the real daemon inside a nested Hyprland, and
# assert on what the shell did with them (#74, #76).
#
#   tools/notification-harness.sh          # run the checks, print PASS/FAIL
#   tools/notification-harness.sh --keep   # leave the nested session up
#
# This is the second test seam, for the half of the notification service that
# `tests/tst_notificationpolicy.qml` cannot reach. Every *rule* is a pure
# function over there. What is only true once a daemon exists is here:
#
#   1. `Notification.expireTimeout` is milliseconds (#74). The policy takes the
#      client's hint on trust — nothing at the pure seam can prove what unit
#      Quickshell actually hands over, and the 1000× that assumption cost is
#      the whole reason this file exists.
#   2. A history row's id is the shell's and not the daemon's (#76). The daemon
#      restarts its counter at 1 with every server, so this needs two servers
#      and the state file that outlives the first one.
#   3. History written by a build that predated the row key is migrated rather
#      than dropped (StateSchema v1 → v2).
#   4. An app that has notified is a row in the settings rules tab without
#      being typed (#71) — a live service read through an open window.
#   5. The lock's count is the notifications that arrived while it was up (#71).
#      Both halves of that only exist here: a real `WlSessionLock` and a real
#      daemon posting at it while it is up.
#
# NOTHING HERE TOUCHES YOUR SESSION. Two isolations, both load-bearing:
#
#   the bus     — a private session bus is started for the run, so the nested
#                 shell owns `org.freedesktop.Notifications` on it. Without one
#                 the name is already held by whatever daemon your real session
#                 runs, the nested shell silently loses the race, and every
#                 `notify-send` below lands on your desktop.
#   the files   — XDG_CONFIG_HOME and XDG_STATE_HOME point at a scratch dir, so
#                 the settings this turns on and the state file it migrates are
#                 not yours.
set -uo pipefail

command -v dbus-daemon  >/dev/null || { echo "dbus-daemon not found" >&2; exit 2; }
command -v notify-send  >/dev/null || { echo "notify-send not found" >&2; exit 2; }

HARNESS_ROOT="${TMPDIR:-/tmp}/forest-notify.$$"
mkdir -p "$HARNESS_ROOT/config" "$HARNESS_ROOT/state" "$HARNESS_ROOT/cache"
export XDG_CONFIG_HOME="$HARNESS_ROOT/config"
export XDG_STATE_HOME="$HARNESS_ROOT/state"
export XDG_CACHE_HOME="$HARNESS_ROOT/cache"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nested-session.sh"

for arg in "$@"; do
    case "$arg" in
        --keep) NESTED_KEEP=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# `dbus-run-session` would do this in one line, but it hands the daemon this
# script's stderr — and a session bus activates portals, gvfs and an
# accessibility bus on the way up, all of which then log over the PASS lines.
# Own the daemon and its log instead.
dbus-daemon --session --fork --print-address=3 --print-pid=4 \
    3> "$HARNESS_ROOT/bus.address" 4> "$HARNESS_ROOT/bus.pid" \
    2> "$HARNESS_ROOT/bus.log" || { echo "could not start a private session bus" >&2; exit 1; }
export DBUS_SESSION_BUS_ADDRESS
DBUS_SESSION_BUS_ADDRESS=$(< "$HARNESS_ROOT/bus.address")
HARNESS_BUS_PID=$(< "$HARNESS_ROOT/bus.pid")

# Sourcing nested-session.sh installed `trap nested_down EXIT`; replacing that
# trap is what this has to call itself, or the nested compositor outlives the
# run.
cleanup_harness() {
    nested_down
    # After nested_down, so the shell is gone before the bus it is on.
    [[ -n "${HARNESS_BUS_PID:-}" ]] && kill "$HARNESS_BUS_PID" 2>/dev/null
    # The same rule nested_down keeps for its logs: this is where the state file
    # a migration check failed on lives, so a failed run keeps it and a clean
    # one does not litter.
    if (( NESTED_KEEP )) || (( nested_fail_count > 0 )); then
        printf '  scratch config/state kept in %s\n' "$HARNESS_ROOT"
        return
    fi
    rm -rf "$HARNESS_ROOT"
}
trap cleanup_harness EXIT

# --- what the shell is told ---------------------------------------------------
#
# `honorClientTimeout` is off by default and #66 argues well for that, so the
# unit bug it hides has to be turned on to be seen — which is exactly how it
# survived to #73.
mkdir -p "$XDG_CONFIG_HOME/forest-shell"
cat > "$XDG_CONFIG_HOME/forest-shell/settings.json" <<'EOF'
{
  "notifications": {
    "honorClientTimeout": true,
    "maxVisible": 5
  }
}
EOF

READY='notifications: server up'

# The state file's directory is Quickshell's to choose, so it is found rather
# than constructed — the layout under stateDir has changed upstream before.
state_file() {
    find "$XDG_STATE_HOME" -name state.json -print -quit 2>/dev/null
}

## Wait for the state file to carry something, and print its contents.
##
## The path has to be resolved on every tick and not once up front: the file
## does not exist until the shell's first write, so a `nested_await "$(state_file)"`
## would poll the empty string for the whole timeout and then report the write
## as the thing that failed.
state_await() {
    local pattern="$1" timeout="${2:-10}" file
    for _ in $(seq 1 $(( timeout * 10 ))); do
        file=$(state_file)
        if [[ -n "$file" ]] && grep -qa "$pattern" "$file"; then
            cat "$file"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# Every `remembered` line the running shell has written, as its key alone.
remembered_keys() {
    grep -a 'notifications: remembered ' "$1" \
        | sed 's/.*notifications: remembered \([^ ]*\) .*/\1/'
}

## Post one notification and wait for the shell to say it saw it. Every wait in
## here is on evidence rather than a sleep: a notification that never arrives
## has to fail the assertion below, not the timeout above it.
##
## The result is checked at every call site, including the ones whose assertion
## is about something else — a notification that silently never arrived turns a
## uniqueness check into a check over nothing, which passes.
post() {
    local summary="$1"
    shift
    notify-send -a harness "$@" "$summary" >/dev/null 2>&1
    nested_await "$NESTED_SHELL_LOG" "remembered .*$summary" 10 && return 0
    nested_fail "the shell never remembered '$summary'"
    return 1
}

## Take the shell down and bring a second one up in the same compositor — a new
## notification server, whose id counter starts again at 1.
restart_shell() {
    nested_kill_shell
    nested_shell shell.qml "$READY" 25
}

## Call the running shell over IPC until it answers with the line that proves
## it did something, and say what it replied if it never does.
##
## Retried rather than called once because this file kills and restarts the
## shell twice: the socket of a shell that is gone outlives it by a moment, and
## a call that lands on that one is silently a no-op — a flake that reads
## exactly like the feature being broken.
ipc_until() {
    local pattern="$1" reply
    shift
    for _ in 1 2 3 4 5; do
        reply=$(nested_ipc call "$@")
        nested_await "$NESTED_SHELL_LOG" "$pattern" 3 && return 0
    done
    nested_note "last ipc reply: ${reply:-nothing}"
    return 1
}

nested_up || exit 1
nested_shell shell.qml "$READY" 25 || exit 1

# --- 1. the client's timeout is milliseconds (#74) ----------------------------

# `-t 4000` is four seconds. Read as seconds it becomes 4 000 000 ms, which the
# policy clamps to its five-minute ceiling — the shape #73 measured.
if post "four-seconds" -t 4000 \
        && grep -qa 'popup (timeout 4000ms, client 4000)' "$NESTED_SHELL_LOG"; then
    nested_pass "a client asking for 4000 gets a 4000 ms popup"
else
    nested_fail "a 4000 ms client timeout was not honoured as 4000 ms"
    grep -a 'notifications: popup' "$NESTED_SHELL_LOG" | tail -3
fi

# The decisive case. Three milliseconds is under the floor; under the seconds
# reading it would have been three seconds, comfortably over it.
if post "three-millis" -t 3 \
        && grep -qa 'popup (timeout 1000ms, client 3)' "$NESTED_SHELL_LOG"; then
    nested_pass "a 3 ms client timeout is floored, not read as 3 s"
else
    nested_fail "a 3 ms client timeout did not land on the floor"
    grep -a 'notifications: popup' "$NESTED_SHELL_LOG" | tail -3
fi

# --- 2. row ids survive a restart (#76) ---------------------------------------

post "first-server-a"
post "first-server-b"

first_run_keys=$(remembered_keys "$NESTED_SHELL_LOG")
cp "$NESTED_SHELL_LOG" "$NESTED_WORK/shell.first.log"

# The write is debounced by a second (Notifications.qml), and the flush on
# destruction only runs if the engine tears down cleanly — so wait for the file
# to actually carry the rows before taking the shell away.
state_await 'first-server-b' 10 > /dev/null || nested_fail "history never reached the state file"

restart_shell || exit 1
post "second-server"

second_run_keys=$(remembered_keys "$NESTED_SHELL_LOG")
all_keys=$(printf '%s\n%s\n' "$first_run_keys" "$second_run_keys" | grep -v '^$')
duplicate=$(sort <<< "$all_keys" | uniq -d)

if [[ -n "$all_keys" && -z "$duplicate" ]]; then
    nested_pass "row keys stay unique across a restart ($(wc -l <<< "$all_keys") rows)"
else
    nested_fail "row keys collided across a restart: ${duplicate:-no rows were remembered}"
fi

# The counter goes to disk with the list it numbers. Without it a history the
# center has emptied — or a lowered `historyLimit` — takes the high-water mark
# with it, and the next start reissues numbers already used (#76).
persisted=$(state_await '"seq"' 10) || persisted=""
if [[ -n "$persisted" ]] && grep -qE '"seq": *[1-9]' <<< "$persisted"; then
    nested_pass "the sequence counter is persisted beside the list"
else
    nested_fail "no sequence counter in the state file"
fi

# Both servers have to have reissued the same notification id, or the check
# above proves nothing: there was never a collision available to make.
if grep -qa 'remembered .* (server id 1):' "$NESTED_WORK/shell.first.log" \
        && grep -qa 'remembered .* (server id 1):' "$NESTED_SHELL_LOG"; then
    nested_pass "both servers reissued notification id 1, so the check above had teeth"
else
    nested_fail "neither server reissued id 1 — nothing above tested a collision"
fi

# --- 3. a v1 history file is migrated, not dropped ----------------------------

nested_kill_shell

file=$(state_file)
if [[ -z "$file" ]]; then
    nested_fail "no state file to migrate"
else
    # A file as the shipped build wrote it: v1, rows keyed on the daemon's id.
    cat > "$file" <<'EOF'
{
  "stateVersion": 1,
  "notifications": {
    "history": [
      { "id": 1, "time": 1000000000002, "appKey": "harness", "summary": "after-restart" },
      { "id": 1, "time": 1000000000001, "appKey": "harness", "summary": "before-restart" }
    ]
  }
}
EOF

    nested_shell shell.qml "$READY" 25 || exit 1
    # Awaited rather than grepped once: the shell is ready when the server has
    # the bus name, and the state file is read lazily a beat after that — so a
    # single grep here is a race that fails on a loaded machine.
    if nested_await "$NESTED_SHELL_LOG" 'state: migrated .* v1 to v2' 10; then
        nested_pass "a v1 state file is migrated on load"
    else
        nested_fail "the v1 → v2 state migration did not run"
        grep -a 'state:' "$NESTED_SHELL_LOG" | tail -3
    fi

    # Both rows are still there, and the two that shared daemon id 1 no longer
    # share anything the center would key on.
    post "after-migration"
    migrated=$(state_await 'after-migration' 10) \
        || nested_fail "the migrated history was never written back"
    if grep -q 'before-restart' <<< "$migrated" && grep -q 'after-restart' <<< "$migrated"; then
        nested_pass "the rows that predate the key are kept, not dropped"
    else
        nested_fail "migrating dropped history rows"
    fi
    if grep -q '"serverId"' <<< "$migrated" && ! grep -q '"id"' <<< "$migrated"; then
        nested_pass "the daemon id is kept as serverId and is no longer the row id"
    else
        nested_fail "migrated rows still carry the daemon id as their identity"
    fi

    # The rows arrived with no sequence number of their own, so the keys they
    # come back with are the ones `readHistory` issued — the case a hand-added
    # row hits too.
    keys=$(grep -o '"key": *"[^"]*"' <<< "$migrated" | sort)
    if [[ -n "$keys" ]] && [[ -z "$(uniq -d <<< "$keys")" ]]; then
        nested_pass "every migrated row came back with a key of its own"
    else
        nested_fail "migrated rows share a key: ${keys:-none were written}"
    fi
fi

# --- 4. history lists apps in the settings tab (#71) --------------------------
#
# The rules tab lists every app that has notified without one being typed. The
# binding is one line, but what it reads is a service that only exists with a
# daemon behind it, and the tab is only constructed once the window is open —
# so both ends are here rather than at the pure seam.

if [[ -z "$NESTED_SHELL_PID" ]]; then
    nested_fail "no shell left running to open settings in"
else
    if ipc_until 'notifications tab: [0-9]+ app row' settings showTab notifications; then
        listed=$(grep -a 'settings: notifications tab:' "$NESTED_SHELL_LOG" \
                 | sed 's/.*, \([0-9]*\) from history/\1/' | tail -1)
        # Everything posted above came from `notify-send -a harness`, and no
        # rule has been written, so every row the tab draws is one history put
        # there.
        if [[ "${listed:-0}" -ge 1 ]]; then
            nested_pass "the app that notified is a row in the tab without being typed"
        else
            nested_fail "the tab listed no apps from history"
            grep -a 'settings: notifications tab:' "$NESTED_SHELL_LOG" | tail -3
        fi

        # Live, which is the half a tab built from a snapshot would still pass:
        # a *new* app notifies with the window already open, and the list it is
        # drawing has to grow by that one row without the window being reopened.
        notify-send -a lateapp "tab-live" > /dev/null 2>&1
        if nested_await "$NESTED_SHELL_LOG" \
                "notifications tab: [0-9]+ app row.*, $(( listed + 1 )) from history" 10; then
            nested_pass "an app that notifies while the tab is open grows a row under it"
        else
            nested_fail "the open tab did not pick up an app that notified under it"
            grep -a 'settings: notifications tab:' "$NESTED_SHELL_LOG" | tail -3
        fi
    else
        nested_fail "the notifications tab never reported what it is listing"
    fi
    nested_ipc call settings close > /dev/null
fi

# --- 5. the lock counts what arrived while it was up (#71) --------------------
#
# `SessionLock.notificationCount` is the seam the lock's status strip renders
# (#47), and it is written from here — so what it holds is only checkable with
# a real lock up and a real daemon posting at it, which is this seam.
#
# The number has teeth because of everything above it: history is already
# several notifications deep by now, so a count that meant "everything
# remembered" would not read 2.

if [[ -z "$NESTED_SHELL_PID" ]]; then
    nested_fail "no shell left running to lock"
else
    if ipc_until 'lock: locking \(ipc\)' lock lock; then
        # Locked, and nothing has arrived since: the strip renders nothing at
        # all for a zero (LockPolicy.notificationSummary), so a "lock count 0"
        # line here would mean the count had already gone wrong.
        post "locked-a" && post "locked-b"
        if nested_await "$NESTED_SHELL_LOG" 'notifications: lock count 2' 10; then
            nested_pass "the lock counts the two notifications that arrived while it was up"
        else
            nested_fail "the lock did not count what arrived while it was up"
            grep -a 'notifications: lock count' "$NESTED_SHELL_LOG" | tail -3
        fi

        # The count is a window, not a total. Anything logged above 2 is
        # history leaking into a lock that has only seen two notifications.
        highest=$(grep -a 'notifications: lock count' "$NESTED_SHELL_LOG" \
                  | sed 's/.*lock count //' | sort -n | tail -1)
        if [[ "${highest:-0}" == 2 ]]; then
            nested_pass "the count is what arrived since the lock, not the whole history"
        else
            nested_fail "the lock counted ${highest:-nothing}, not the 2 that arrived under it"
        fi
    else
        nested_fail "the session never locked over IPC"
    fi
fi

# --- report ------------------------------------------------------------------

if (( nested_fail_count == 0 )); then
    printf '\n\033[32mall notification checks passed\033[0m\n'
    exit 0
fi
printf '\n\033[31m%d notification check(s) failed\033[0m\n' "$nested_fail_count"
exit 1
