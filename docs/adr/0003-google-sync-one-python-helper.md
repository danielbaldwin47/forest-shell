# 0003 — All Google HTTP lives in one stdlib Python helper

Status: accepted
Date: 2026-08-18 (decided while building the Google half of the calendar on
`gauntlet-calendar`)

## Context

The calendar had to talk to Google Calendar: an OAuth consent flow, token
storage and refresh rotation, incremental pulls with a `syncToken`, event
pushes, and recovery from the 410 that retires a token. The shell is QML, and
QML is where the rest of the shell's HTTP already lives —
`Services/Weather/Weather.qml` uses `XMLHttpRequest` and argues, correctly for
its case, that spawning `curl` would be a dependency added for nothing.

Three things Google needs are things QML cannot do. The desktop OAuth flow
redirects to `127.0.0.1`, so something has to open a loopback listener. The
refresh token has to land in a file at 0600, and QML can neither `open` with a
mode nor `chmod`. And PKCE, refresh rotation, `syncToken` handling, paging and
410 recovery are a body of logic worth unit-testing against a faked transport —
but a QML file that imports `Quickshell` is unreachable from `tests/`, because
Quickshell's modules are compiled into its binary and `qmltestrunner` cannot
load them.

Splitting the work was the option that looked cheapest: refresh in QML, the
rest in a helper. It puts the refresh token in two places instead of one.

## Decision

Every Google HTTP request the shell makes goes through `tools/gcal-sync.py`,
behind a single `_http` chokepoint, and the shell spawns it and parses one JSON
object. Nothing else in the shell holds a Google URL, a token, or a client
secret.

The helper is stdlib-only, the same rule every tool in a gate follows, and its
contract is fixed so the caller never guesses: exactly one JSON object on
stdout and nothing else ever; human-readable progress on stderr; no access
token, refresh token or client secret on either; exit 0 answered, 1 broke, 3
re-authorise. Credentials read from `google-oauth.json`, tokens write to
`google-token.json` via `os.open(…, 0o600)` and an atomic rename.

What is left on the QML side is deliberately not HTTP. `GoogleEventPolicy` maps
payloads to events and back, `SyncPolicy` decides what to apply and what to
push, and both are pure `QtObject`s that `tests/` reaches directly.
`Services/Calendar/GoogleSync.qml` only decides *when* a round happens, runs the
helper, and does what the policies say.

## Consequences

- The token exists in exactly one process and one file. No token, and no URL
  carrying one, passes through QML or the shell log; the only field of a token
  that ever leaves the helper is the account's address.
- `tests/tst_gcal_sync.py` fakes `urlopen` and covers the flows no QML seam
  could reach — consent, rotation, paging, 410 — including that the token file
  is 0600 and that no secret reaches stdout.
- Seam 2 fakes the *helper* rather than the network: `FOREST_GCAL_HELPER` names
  what `GoogleSync.qml` runs, and `tools/fixtures/gcal-fake.sh` speaks the
  contract above and records pushes. The harness therefore asserts on wiring —
  does a trigger reach a process, does an answer reach the store — and never on
  Google.
- Python 3 becomes a runtime dependency of Google sync. It was already a hard
  dependency of `tests/run.sh`, and sync is off by default, so a machine that
  never connects an account never needs it.
- Connecting an account needs a human at a browser and a Google Cloud console,
  which no seam covers. `tools/gcal-connect-wizard.sh` is that path, and it is a
  wizard rather than a doc because eight of its steps are clicks and two are
  files that have to end up at 0600.
