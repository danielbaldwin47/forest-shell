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
    if (( NESTED_KEEP )); then
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

# Every `remembered` line the running shell has written, as its key alone.
remembered_keys() {
    grep -a 'notifications: remembered ' "$1" \
        | sed 's/.*notifications: remembered \([^ ]*\) .*/\1/'
}

## Post one notification and wait for the shell to say it saw it. Every wait in
## here is on evidence rather than a sleep: a notification that never arrives
## has to fail the assertion below, not the timeout above it.
post() {
    local summary="$1"
    shift
    notify-send -a harness "$@" "$summary" >/dev/null 2>&1
    nested_await "$NESTED_SHELL_LOG" "remembered .*$summary" 10
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

post "first-server-a" >/dev/null
post "first-server-b" >/dev/null

first_run_keys=$(remembered_keys "$NESTED_SHELL_LOG")
cp "$NESTED_SHELL_LOG" "$NESTED_WORK/shell.first.log"

# The write is debounced by a second (Notifications.qml), and the flush on
# destruction only runs if the engine tears down cleanly — so wait for the file
# to actually carry the rows before taking the shell away.
if ! nested_await "$(state_file)" 'first-server-b' 10; then
    nested_fail "history never reached the state file"
fi

kill "$NESTED_SHELL_PID" 2>/dev/null
wait "$NESTED_SHELL_PID" 2>/dev/null

# A second server. Its notification id counter starts again at 1; the history it
# is writing into does not.
nested_shell shell.qml "$READY" 25 || exit 1
post "second-server" >/dev/null

second_run_keys=$(remembered_keys "$NESTED_SHELL_LOG")
all_keys=$(printf '%s\n%s\n' "$first_run_keys" "$second_run_keys" | grep -v '^$')
duplicate=$(sort <<< "$all_keys" | uniq -d)

if [[ -n "$all_keys" && -z "$duplicate" ]]; then
    nested_pass "row keys stay unique across a restart ($(wc -l <<< "$all_keys") rows)"
else
    nested_fail "row keys collided across a restart: ${duplicate:-no rows were remembered}"
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

kill "$NESTED_SHELL_PID" 2>/dev/null
wait "$NESTED_SHELL_PID" 2>/dev/null

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
    if grep -qa 'state: migrated .* v1 to v2' "$NESTED_SHELL_LOG"; then
        nested_pass "a v1 state file is migrated on load"
    else
        nested_fail "the v1 → v2 state migration did not run"
        grep -a 'state:' "$NESTED_SHELL_LOG" | tail -3
    fi

    # Both rows are still there, and the two that shared daemon id 1 no longer
    # share anything the center would key on.
    post "after-migration" >/dev/null
    if ! nested_await "$(state_file)" 'after-migration' 10; then
        nested_note "the post-migration write had not settled"
    fi
    migrated=$(cat "$(state_file)")
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
fi

# --- report ------------------------------------------------------------------

if (( nested_fail_count == 0 )); then
    printf '\n\033[32mall notification checks passed\033[0m\n'
    exit 0
fi
printf '\n\033[31m%d notification check(s) failed\033[0m\n' "$nested_fail_count"
exit 1
