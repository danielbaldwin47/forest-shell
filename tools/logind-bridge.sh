#!/usr/bin/env bash
# The logind bridge (#48; the design is #30's resolution) — one bare word on
# stdout per logind event the shell has to react to.
#
#   tools/logind-bridge.sh
#   lock          # `loginctl lock-session`, a lid switch, anything else
#   sleep         # PrepareForSleep(true): the machine is about to suspend
#   resume        # PrepareForSleep(false): it came back
#   unlock        # `loginctl unlock-session` — the shell refuses it, see below
#
# Run by Services/System/LogindBridge.qml as a long-lived `Process`, and by
# hand when you want to watch what logind is actually saying.
#
# ## Why the shell needs a helper at all
#
# Quickshell 0.3.0 has no arbitrary-DBus client (#4 §2.8), so the two signals
# that decide when a session locks are unreachable from QML: the session's own
# `Lock`/`Unlock`, and the manager's `PrepareForSleep`. Something outside the
# process has to hear them and say so in a form QML can read, which is this.
#
# ## Why gdbus and not busctl
#
# #30's resolution says `busctl monitor`, and it cannot work here — measured
# while building this: the system bus refuses `BecomeMonitor` to anyone but
# root, so an unprivileged `busctl --system monitor` exits immediately with
#
#     Call to org.freedesktop.DBus.Monitoring.BecomeMonitor failed: Access denied
#
# Monitoring is eavesdropping, and eavesdropping on the system bus is
# privileged. *Subscribing* to broadcast signals is not, and it is all this
# needs: `gdbus monitor` does an ordinary `AddMatch` and receives the signals
# addressed to everyone, as an unprivileged client, which is what logind
# broadcasts these as. It also prints one line per signal instead of a
# nine-line block, so the filter below is four rules rather than a state
# machine. (gdbus ships with glib2, which is already a dependency of everything
# on this desktop.)
#
# ## What it does not do
#
# It does not decide anything. `unlock` is forwarded and the shell refuses it —
# there is no unlock path that does not go through PAM (#30, #47) — and the
# lock-before-sleep guarantee is the *shell's* delay inhibitor, held in
# LogindBridge.qml, because only the shell knows when the compositor has
# confirmed the lock is up.
set -uo pipefail

readonly LOGIN1=org.freedesktop.login1
readonly MANAGER=/org/freedesktop/login1

command -v gdbus > /dev/null || {
    echo "gdbus not found — install glib2" >&2
    exit 127
}

## This session's object path, so another user's session locking does not lock
## this one. `gdbus monitor --dest` hears every object the name owns, and on a
## machine with two people logged in that is two sessions' worth of signals.
session_path() {
    local reply=""
    # The session id first: it is in the environment of anything logind started,
    # and it survives the shell being restarted from a terminal inside the
    # session. GetSessionByPID is the fallback, and it is the weaker of the two —
    # a process outside the session's cgroup (a systemd --user unit, anything
    # run from a scope logind does not own) is not in any session as far as
    # logind is concerned, and it answers with an error.
    if [[ -n "${XDG_SESSION_ID:-}" ]]; then
        reply=$(busctl --system call "$LOGIN1" "$MANAGER" "$LOGIN1.Manager" \
                    GetSession s "$XDG_SESSION_ID" 2>/dev/null)
    fi
    if [[ -z "$reply" ]]; then
        reply=$(busctl --system call "$LOGIN1" "$MANAGER" "$LOGIN1.Manager" \
                    GetSessionByPID u $$ 2>/dev/null)
    fi
    sed -n 's/^o "\(.*\)"$/\1/p' <<< "$reply"
}

SESSION=$(session_path)
if [[ -z "$SESSION" ]]; then
    # Not fatal for sleep — PrepareForSleep is the manager's and needs no session
    # — but `loginctl lock-session` will not be heard, so it is said out loud
    # rather than left as a lock that silently never arrives (#78).
    echo "logind knows no session for this shell — lock-session will not be heard" >&2
fi
echo "watching ${SESSION:-<no session>} and $MANAGER" >&2

# Line buffering on both halves, or the events arrive in 4 KiB batches: glib
# block-buffers stdout when it is a pipe, and so does awk. A sleep event that
# turns up after the machine woke is worse than none at all.
stdbuf -oL gdbus monitor --system --dest "$LOGIN1" 2>&1 \
    | stdbuf -oL awk -v session="$SESSION" '
        # gdbus prints one line per signal:
        #   /org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)
        #   /org/freedesktop/login1/session/_37: org.freedesktop.login1.Session.Lock ()
        # Its first two lines are a banner naming the bus name it attached to,
        # and they match none of these.
        session != "" && $1 == session ":" && $2 ~ /\.Session\.Lock$/ {
            print "lock"; fflush(); next
        }
        session != "" && $1 == session ":" && $2 ~ /\.Session\.Unlock$/ {
            print "unlock"; fflush(); next
        }
        $2 ~ /\.Manager\.PrepareForSleep$/ && $0 ~ /\(true,?\)/ {
            print "sleep"; fflush(); next
        }
        $2 ~ /\.Manager\.PrepareForSleep$/ && $0 ~ /\(false,?\)/ {
            print "resume"; fflush(); next
        }
    '
