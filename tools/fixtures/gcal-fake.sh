#!/usr/bin/env bash
#
# A stand-in for tools/gcal-sync.py, for tools/calendar-harness.sh.
#
# `Services/Calendar/GoogleSync.qml` runs whatever `FOREST_GCAL_HELPER` names,
# and treats a path that does not end in `.py` as an executable rather than
# something to hand to python3 — which is what lets this be a shell script. It
# speaks the real helper's contract and nothing else: one JSON object on stdout,
# human text on stderr, exit 0 for an answer, 1 for a failure, 3 for "no account
# is connected".
#
# What it is *not*: a fake Google. It never sees an HTTP request, and every
# question about pagination, 410 recovery, PKCE or refresh rotation is answered
# at seam 1 by tests/tst_gcal_sync.py against a faked `urlopen`. What only exists
# once a shell is running is the wiring — does a trigger reach a process, does
# its stdout reach `SyncPolicy`, does a queued op reach stdin, does exit 3 reach
# the log — and that is all this file exists to let the harness ask.
#
# State is the arguments, not a file, wherever it can be: `pull` answers with two
# events when it is asked without a syncToken and with none when it is asked with
# one, which is exactly how the real one distinguishes a full pull from an
# incremental one. The one thing that cannot be an argument is the mode, because
# the harness has to change it *between* rounds of a shell it already launched:
#
#   GCAL_FAKE_MODE_FILE   a file whose contents are a mode, read per run.
#                         `auth-needed` makes every subcommand exit 3;
#                         `broken` makes it exit 1, which is the other half of
#                         that distinction — a state the shell reports once
#                         against a failure it backs off from and retries;
#                         `slow` makes it dawdle before answering, which is the
#                         only way to have two triggers overlap on purpose.
#   GCAL_FAKE_PUSHES      append the ops of every push here, one JSON array per
#                         line. The harness reads it to check that an op the log
#                         claimed really left the shell — and, just as much, that
#                         a round nobody edited anything in left it empty.
#   GCAL_FAKE_RUNS        append one line per invocation, `<mode> <subcommand>`.
#                         The pushes file says what left the shell; this says
#                         whether a *process* did — which is how "sync is off, so
#                         nothing ran" and "two triggers, one helper" are asked.
#
# It also prints a bearer token nobody should ever see again. That is a control,
# not decoration: `refute_since 'ya29\.'` over a log is a check that passes just
# as happily against a helper that never had a secret to leak, so the fake makes
# sure there was one, in both of the places a real one would be — the stdout the
# shell parses and the stderr it collects into `lastError`.
set -uo pipefail

# Shaped like a real Google access token and deliberately loud. If this string
# is ever in the shell log, something between here and there is printing what it
# was handed instead of what it decided.
FAKE_TOKEN='ya29.FAKE-SECRET-NEVER-LOG-ME'

mode=""
if [[ -n "${GCAL_FAKE_MODE_FILE:-}" && -r "${GCAL_FAKE_MODE_FILE:-}" ]]; then
    mode=$(tr -d '[:space:]' < "$GCAL_FAKE_MODE_FILE")
fi

cmd="${1:-}"
shift || true

sync_token=""
while (( $# )); do
    case "$1" in
        --sync-token) sync_token="${2:-}"; shift 2 ;;
        --calendar) shift 2 ;;
        --stdin) shift ;;
        *) shift ;;
    esac
done

if [[ -n "${GCAL_FAKE_RUNS:-}" ]]; then
    printf '%s %s\n' "${mode:-none}" "${cmd:-none}" >> "$GCAL_FAKE_RUNS"
fi

# Before the mode gate, because "the token was there to leak" has to be true of
# the refused runs too.
echo "fake: authorising with bearer $FAKE_TOKEN" >&2

if [[ "$mode" == "auth-needed" ]]; then
    echo "fake: no account is connected" >&2
    echo '{"ok":false,"error":"auth"}'
    exit 3
fi

if [[ "$mode" == "broken" ]]; then
    # Exit 1 is "the run failed" — a network that went away, a 500, a quota. The
    # shell is supposed to say `sync error 1` and come back on a backoff, which
    # is the difference between this and the exit 3 above.
    echo "fake: the network went away" >&2
    echo '{"ok":false,"error":"http 503"}'
    exit 1
fi

if [[ "$mode" == "slow" ]]; then
    # Long enough that a second trigger lands inside the first round, and short
    # enough that the harness is not waiting on it.
    sleep 1.5
fi

case "$cmd" in
status)
    echo '{"ok":true,"connected":true,"email":"fake@example.com","expired":false}'
    ;;

auth)
    # The consent answer carries the token, the way the real one's does before
    # the helper writes it to a 0600 file. The shell is expected to read exactly
    # one field out of this object and log exactly that.
    echo '{"ok":true,"email":"fake@example.com","accessToken":"'"$FAKE_TOKEN"'"}'
    ;;

calendars)
    echo '{"ok":true,"calendars":[{"id":"primary","summary":"Fake","primary":true}]}'
    ;;

pull)
    if [[ -n "$sync_token" ]]; then
        # An incremental pull with nothing to report — the shape of almost every
        # round on a calendar nobody is editing.
        echo "fake: incremental pull, nothing new" >&2
        echo '{"ok":true,"events":[],"nextSyncToken":"fake-token-2","full":false,"accessToken":"'"$FAKE_TOKEN"'"}'
    else
        # A full pull. Two events, deliberately unalike: one timed with an
        # attendee and a meeting room, one all-day — the two shapes whose
        # mapping differs most.
        echo "fake: full pull, 2 events" >&2
        cat <<'JSON'
{"ok":true,"full":true,"nextSyncToken":"fake-token-1","events":[
  {"id":"gid-standup","status":"confirmed","summary":"Fake standup",
   "etag":"\"etag-standup\"","updated":"2026-08-18T06:00:00.000Z",
   "start":{"dateTime":"2026-08-18T09:00:00+00:00","timeZone":"UTC"},
   "end":{"dateTime":"2026-08-18T09:30:00+00:00","timeZone":"UTC"},
   "attendees":[{"email":"mira@example.com","displayName":"Mira"},
                {"email":"room-1@resource.calendar.google.com","resource":true}]},
  {"id":"gid-offsite","status":"confirmed","summary":"Fake offsite",
   "etag":"\"etag-offsite\"","updated":"2026-08-18T06:00:00.000Z",
   "start":{"date":"2026-08-20"},"end":{"date":"2026-08-21"}}
]}
JSON
    fi
    ;;

push)
    # The ops arrive on stdin as a JSON array. Recording them is the point: a
    # log line saying a push succeeded is the shell's claim, and the file is the
    # evidence that something actually left it.
    ops=$(cat)
    if [[ -n "${GCAL_FAKE_PUSHES:-}" ]]; then
        printf '%s\n' "$ops" >> "$GCAL_FAKE_PUSHES"
    fi
    # One result per op, ids echoed back — `SyncPolicy.markPushed` matches on
    # them and ignores an answer about an op nobody queued, so a fake that
    # invented ids would look exactly like a fake that answered nothing.
    printf '%s' "$ops" | python3 -c '
import datetime, json, sys
try:
    ops = json.loads(sys.stdin.read() or "[]")
except ValueError:
    ops = []
# `updated` is stamped *now*, as the API stamps it: the server dates an event
# when it accepts it, which is always after the local edit that sent it. A fixed
# timestamp in the past would be a fixture that lies in a specific direction —
# every pushed event would read as locally-newer than the server forever, and
# `SyncPolicy.reconcile` would derive a fresh patch for it on every round. The
# harness asserts that does not happen, so the fake has to be honest about this.
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
results = []
for op in ops if isinstance(ops, list) else []:
    op_id = str(op.get("id", ""))
    kind = op.get("op", "")
    google_id = op.get("googleId", "") or ("gid-" + op_id)
    results.append({"id": op_id, "ok": True, "googleId": google_id,
                    "etag": "\"etag-" + op_id + "\"",
                    "updated": now})
    print("fake: " + kind + " " + op_id, file=sys.stderr)
print(json.dumps({"ok": True, "results": results}))
'
    ;;

*)
    echo "fake: no such subcommand: $cmd" >&2
    echo '{"ok":false,"error":"unknown subcommand"}'
    exit 1
    ;;
esac
exit 0
