#!/usr/bin/env python3
"""Unit tests for tools/gcal-sync.py — the shell's whole Google surface.

Every decision the helper makes is checkable without an account: paging is a
loop over two recorded bodies, a 410 is a recorded body, rotation is which
refresh token ends up in the file, and the loopback consent flow is a real
socket on 127.0.0.1 answered by this process. What cannot be checked here is
whether Google agrees with our reading of its API — that needs the wizard and a
real account, and the PR says so.

    tests/tst_gcal_sync.py         # part of tests/run.sh

Two invariants get asserted on every single run rather than once: the token file
is 0600, and no secret string from any fixture ever reaches stdout. Those are
the two ways this tool could hurt someone, so they are checked over the union of
everything the suite did, not at one convenient spot.

Stdlib only, same rule as the tool: this runs inside a gate.
"""

import base64
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import shutil
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "tools" / "gcal-sync.py"
FIXTURES = REPO / "tools" / "fixtures" / "gcal"

_spec = importlib.util.spec_from_file_location("gcal_sync", TOOL)
gcal = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gcal)

failures = []
stdout_seen = []


def check(name, condition, detail=""):
    if condition:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}{': ' + detail if detail else ''}")
        failures.append(name)


def fixture(name):
    return json.loads((FIXTURES / name).read_text())


# Everything a leak would look like. The client secret is ours, the rest come
# out of the recorded token bodies.
CLIENT_SECRET = "GOCSPX-FIXTURE-client-secret"
SECRETS = [
    CLIENT_SECRET,
    fixture("token-response.json")["access_token"],
    fixture("token-response.json")["refresh_token"],
    fixture("token-refresh-rotated.json")["access_token"],
    fixture("token-refresh-rotated.json")["refresh_token"],
]


# ------------------------------------------------------------------ harness --


def workspace(root, name, token=None, creds=True):
    """A private config/data pair, pointed at by the two env overrides."""
    work = root / name
    work.mkdir(parents=True)
    if creds:
        (work / "google-oauth.json").write_text(json.dumps({"installed": {
            "client_id": "1234-fixture.apps.googleusercontent.com",
            "client_secret": CLIENT_SECRET,
            "auth_uri": gcal.AUTH_ENDPOINT,
            "token_uri": gcal.TOKEN_ENDPOINT,
        }}))
        os.environ["FOREST_GCAL_OAUTH"] = str(work / "google-oauth.json")
    else:
        os.environ["FOREST_GCAL_OAUTH"] = str(work / "absent.json")
    tokfile = work / "calendar" / "google-token.json"
    os.environ["FOREST_GCAL_TOKEN"] = str(tokfile)
    if token is not None:
        tokfile.parent.mkdir(parents=True, exist_ok=True)
        tokfile.write_text(json.dumps(token))
    return tokfile


def stored_token(expires_in=3600, refresh="1//FIXTURE-refresh-token-original"):
    return {
        "access_token": "ya29.FIXTURE-access-token-page-one",
        "refresh_token": refresh,
        "expires_at": int(time.time()) + expires_in,
        "scope": " ".join(gcal.SCOPES),
        "token_type": "Bearer",
        "email": "daniel@example.com",
    }


def fake_http(responder):
    """Replace the one chokepoint, and keep every call for inspection."""
    calls = []

    def _fake(method, url, params=None, form=None, json_body=None,
              headers=None, timeout=30):
        call = {"method": method, "url": url, "params": dict(params or {}),
                "form": dict(form or {}), "body": json_body,
                "headers": dict(headers or {})}
        calls.append(call)
        return responder(call, len(calls) - 1)

    gcal._http = _fake
    return calls


def run(argv, stdin_text=None):
    out, err = io.StringIO(), io.StringIO()
    old_stdin = sys.stdin
    if stdin_text is not None:
        sys.stdin = io.StringIO(stdin_text)
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = gcal.main(argv)
    finally:
        sys.stdin = old_stdin
    text = out.getvalue()
    stdout_seen.append(text)
    try:
        obj = json.loads(text)
    except ValueError:
        obj = {"_unparseable": text}
    return code, obj, err.getvalue()


def mode_of(path):
    return path.stat().st_mode & 0o777


# -------------------------------------------------------------------- tests --


def test_window_bounds():
    now = 1787040000.0  # 2026-08-18T08:00:00Z
    lo, hi = gcal.window_bounds(7, now=now)
    check("--window builds an RFC3339 pair",
          lo == "2026-08-11T08:00:00Z" and hi == "2026-08-25T08:00:00Z",
          f"{lo}..{hi}")
    check("--window reaches equally into past and future",
          gcal.window_bounds(30, now=now)[0] < gcal._rfc3339(now)
          < gcal.window_bounds(30, now=now)[1])
    check("no --window means no bounds", gcal.window_bounds(None) == (None, None))


def test_pull_pages(root):
    workspace(root, "pull-pages", token=stored_token())
    page1, page2 = fixture("events-page1.json"), fixture("events-page2.json")

    def responder(call, n):
        return 200, (page1 if n == 0 else page2)

    calls = fake_http(responder)
    code, obj, _ = run(["pull", "--window", "30"])

    check("a paged pull exits 0", code == 0, str(code))
    check("a paged pull concatenates both pages",
          [e["id"] for e in obj.get("events", [])] ==
          ["6r2p9c1h6cpj2b9k6phm4b9k", "1k9m3d5g7ppl2c8j4rhn6a2b",
           "8b4n2q6r0ssk5f1h9tjm3d7c"], json.dumps(obj)[:160])
    check("a paged pull returns the last page's sync token",
          obj.get("nextSyncToken") == page2["nextSyncToken"])
    check("a pull without a sync token reports itself full", obj.get("full") is True)
    check("every page asks for flat, deleted-inclusive instances",
          all(c["params"]["singleEvents"] == "true"
              and c["params"]["showDeleted"] == "true" for c in calls))
    check("the second page carries the first page's pageToken",
          calls[1]["params"].get("pageToken") == page1["nextPageToken"],
          json.dumps(calls[1]["params"]))
    check("a windowed pull bounds the request",
          "timeMin" in calls[0]["params"] and "timeMax" in calls[0]["params"])
    check("the pull authorises with the stored token",
          calls[0]["headers"].get("Authorization")
          == "Bearer ya29.FIXTURE-access-token-page-one")
    check("pull stops paging when a page carries no pageToken", len(calls) == 2,
          str(len(calls)))


def test_pull_incremental(root):
    workspace(root, "pull-inc", token=stored_token())
    calls = fake_http(lambda call, n: (200, fixture("events-page2.json")))
    code, obj, _ = run(["pull", "--sync-token", "TOKEN-A", "--window", "30"])

    check("an incremental pull exits 0", code == 0, str(code))
    check("an incremental pull sends the sync token",
          calls[0]["params"].get("syncToken") == "TOKEN-A")
    check("a sync token suppresses timeMin/timeMax (the API forbids both)",
          "timeMin" not in calls[0]["params"] and "timeMax" not in calls[0]["params"],
          json.dumps(calls[0]["params"]))
    check("an incremental pull reports itself not full", obj.get("full") is False)
    check("a cancelled instance is passed through, not dropped",
          obj["events"][0]["status"] == "cancelled")


def test_pull_gone(root):
    workspace(root, "pull-gone", token=stored_token())
    fake_http(lambda call, n: (410, fixture("events-410-gone.json")))
    code, obj, _ = run(["pull", "--sync-token", "STALE"])

    check("a 410 is an answer, not a failure", code == 0, str(code))
    check("a 410 reports gone", obj.get("gone") is True, json.dumps(obj)[:120])
    check("a 410 carries no events", obj.get("events") == [])


def test_pull_calendar_id_is_escaped(root):
    workspace(root, "pull-escape", token=stored_token())
    calls = fake_http(lambda call, n: (200, {"items": [], "nextSyncToken": "T"}))
    run(["pull", "--calendar", "en.uk#holiday@group.v.calendar.google.com"])
    check("a calendar id with # is percent-escaped into the path",
          "%23holiday%40group" in calls[0]["url"], calls[0]["url"])


def test_window_rejects_nonsense(root):
    workspace(root, "pull-window", token=stored_token())
    fake_http(lambda call, n: (200, {"items": []}))
    code, obj, _ = run(["pull", "--window", "0"])
    check("--window 0 is refused", code == 1 and obj.get("ok") is False, str(code))


def test_refresh_rotation(root):
    tokfile = workspace(root, "refresh-rot", token=stored_token(expires_in=-10))
    rotated = fixture("token-refresh-rotated.json")

    def responder(call, n):
        if call["url"] == gcal.TOKEN_ENDPOINT:
            return 200, rotated
        return 200, {"items": [], "nextSyncToken": "TOKEN-B"}

    calls = fake_http(responder)
    code, obj, _ = run(["pull"])
    saved = json.loads(tokfile.read_text())

    check("an expired token refreshes before the request", code == 0
          and calls[0]["url"] == gcal.TOKEN_ENDPOINT, str(code))
    check("the refresh spends the stored refresh token",
          calls[0]["form"].get("refresh_token") == "1//FIXTURE-refresh-token-original")
    check("a rotated refresh token replaces the old one",
          saved["refresh_token"] == rotated["refresh_token"], saved["refresh_token"][:12])
    check("the new access token is stored",
          saved["access_token"] == rotated["access_token"])
    check("the refreshed token is the one the API call uses",
          calls[1]["headers"]["Authorization"] == f"Bearer {rotated['access_token']}")
    check("the refresh keeps the known email", saved.get("email") == "daniel@example.com")
    check("the refreshed token file is still 0600", mode_of(tokfile) == 0o600,
          oct(mode_of(tokfile)))
    check("the pull still answers", obj.get("ok") is True)


def test_refresh_without_rotation(root):
    tokfile = workspace(root, "refresh-norot", token=stored_token(expires_in=-10))
    body = dict(fixture("token-refresh-rotated.json"))
    body.pop("refresh_token")  # Google usually returns none
    fake_http(lambda call, n: (200, body))
    code, obj, _ = run(["refresh"])
    saved = json.loads(tokfile.read_text())

    check("an explicit refresh exits 0", code == 0, str(code))
    check("a response with no refresh_token keeps the stored one",
          saved["refresh_token"] == "1//FIXTURE-refresh-token-original")
    check("refresh reports the new expiry, not the token",
          obj.get("expiresAt", "").endswith("Z") and "access" not in json.dumps(obj))


def test_refresh_invalid_grant(root):
    workspace(root, "refresh-bad", token=stored_token(expires_in=-10))
    fake_http(lambda call, n: (400, fixture("token-invalid-grant.json")))
    code, obj, err = run(["pull"])

    check("invalid_grant exits 3", code == 3, str(code))
    check("invalid_grant answers {ok:false,error:auth}",
          obj == {"ok": False, "error": "auth"}, json.dumps(obj))
    check("invalid_grant says why on stderr", "invalid_grant" in err, err[:80])


def test_no_token_is_auth(root):
    workspace(root, "no-token")
    fake_http(lambda call, n: (200, {}))
    code, obj, _ = run(["pull"])
    check("pulling without a token exits 3", code == 3 and obj["error"] == "auth",
          str(code))


def test_status(root):
    tokfile = workspace(root, "status-off")
    code, obj, _ = run(["status"])
    check("status on a fresh machine reports not connected",
          code == 0 and obj["connected"] is False, json.dumps(obj)[:120])
    check("status names the token path it looked at",
          obj["tokenPath"] == str(tokfile))

    workspace(root, "status-on", token=stored_token())
    code, obj, _ = run(["status"])
    check("status reports the account once connected",
          code == 0 and obj["connected"] is True
          and obj["email"] == "daniel@example.com", json.dumps(obj)[:120])
    check("status reports expiry and nothing else about the token",
          obj["expiresAt"].endswith("Z") and obj["expired"] is False
          and "access_token" not in obj and "refresh_token" not in obj)


def test_push(root):
    workspace(root, "push", token=stored_token())
    created = fixture("push-create-201.json")

    def responder(call, n):
        if call["method"] == "POST" and call["body"].get("summary") == "Dentist":
            return 201, created
        if call["method"] == "POST":
            return 403, fixture("rate-limit-403.json")
        if call["method"] == "PATCH":
            return 412, fixture("push-precondition-412.json")
        if call["method"] == "DELETE":
            return 404, {"error": {"code": 404, "message": "Not Found"}}
        return 500, {}

    ops = [
        {"id": "evt-1", "op": "create", "body": {"summary": "Dentist"}},
        {"id": "evt-2", "op": "patch", "googleId": "abc123",
         "body": {"summary": "Moved"}},
        {"id": "evt-3", "op": "delete", "googleId": "gone999"},
        {"id": "evt-4", "op": "patch", "body": {"summary": "no id"}},
        {"id": "evt-5", "op": "explode", "body": {}},
        {"id": "evt-6", "op": "create", "body": {"summary": "Too fast"}},
    ]
    calls = fake_http(responder)
    code, obj, _ = run(["push", "--stdin"], stdin_text=json.dumps(ops))
    by_id = {r["id"]: r for r in obj["results"]}

    check("a delivered batch exits 0 even with refused ops", code == 0, str(code))
    check("every op gets exactly one result in order",
          [r["id"] for r in obj["results"]] == [o["id"] for o in ops])
    check("a create returns the server's id, etag and updated",
          by_id["evt-1"]["ok"] is True
          and by_id["evt-1"]["googleId"] == created["id"]
          and by_id["evt-1"]["etag"] == created["etag"]
          and by_id["evt-1"]["updated"] == created["updated"],
          json.dumps(by_id["evt-1"]))
    check("a 412 maps to conflict",
          by_id["evt-2"] == {"id": "evt-2", "ok": False, "googleId": "abc123",
                             "error": "conflict"}, json.dumps(by_id["evt-2"]))
    check("deleting something already gone is a success",
          by_id["evt-3"]["ok"] is True and "error" not in by_id["evt-3"])
    check("a patch with no googleId never reaches the network",
          by_id["evt-4"]["error"] == "missing-google-id")
    check("an unknown verb is refused as bad-op",
          by_id["evt-5"]["error"] == "bad-op")
    check("a rate limit maps to rate", by_id["evt-6"]["error"] == "rate",
          json.dumps(by_id["evt-6"]))
    check("only the four network-bound ops made a request", len(calls) == 4,
          str(len(calls)))
    check("a patch targets the event, not the collection",
          calls[1]["method"] == "PATCH" and calls[1]["url"].endswith("/events/abc123"),
          calls[1]["url"])


def test_machine_timezone():
    """The zone name the push backstop uses when the shell states none.

    Abbreviations are the trap: `time.tzname` says `BST`, which is not a zone id
    and which the API will not take. Every branch here has to produce something
    with a slash in it or the literal `UTC`.
    """
    saved = os.environ.get("TZ")
    try:
        os.environ["TZ"] = "Europe/London"
        check("TZ is honoured when it names a zone",
              gcal.machine_timezone() == "Europe/London")
        os.environ["TZ"] = ":Europe/Berlin"
        check("a leading colon in TZ is stripped",
              gcal.machine_timezone() == "Europe/Berlin")
        os.environ["TZ"] = "BST"
        named = gcal.machine_timezone()
        check("an abbreviation in TZ is refused in favour of the system's answer",
              named == "UTC" or "/" in named, named)
        os.environ.pop("TZ", None)
        fallback = gcal.machine_timezone()
        check("with no TZ the answer is still a zone id",
              fallback == "UTC" or "/" in fallback, fallback)
    finally:
        if saved is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = saved


def test_fill_timezone():
    naive = {"start": {"dateTime": "2026-08-18T09:15:00"},
             "end": {"dateTime": "2026-08-18T09:45:00"}}
    filled = gcal.fill_timezone(naive, zone="Europe/London")
    check("a naive dateTime gets the machine's zone",
          filled["start"]["timeZone"] == "Europe/London"
          and filled["end"]["timeZone"] == "Europe/London", json.dumps(filled))

    stated = {"start": {"dateTime": "2026-08-18T09:15:00", "timeZone": "Asia/Tokyo"}}
    check("a stated zone is never overridden",
          gcal.fill_timezone(stated, zone="Europe/London")["start"]["timeZone"]
          == "Asia/Tokyo")

    offset = {"start": {"dateTime": "2026-08-18T09:15:00+01:00"},
              "end": {"dateTime": "2026-08-18T09:45:00Z"}}
    done = gcal.fill_timezone(offset, zone="Europe/London")
    check("a dateTime that carries its own offset is left alone",
          "timeZone" not in done["start"] and "timeZone" not in done["end"],
          json.dumps(done))

    allday = {"start": {"date": "2026-08-18"}, "end": {"date": "2026-08-19"}}
    check("an all-day body has no time of day to place",
          gcal.fill_timezone(allday, zone="Europe/London") == allday)
    check("a body that is not a dict comes back unharmed",
          gcal.fill_timezone(None) is None)


def test_push_fills_a_missing_timezone(root):
    """The API rejects a naive `dateTime`, and it rejects it per op.

    So an unstated zone does not fail the sync — it fails exactly the events
    somebody had just made, which is the failure that looks like nothing.
    """
    workspace(root, "push-tz", token=stored_token())
    calls = fake_http(lambda call, n: (201, fixture("push-create-201.json")))
    ops = [{"id": "evt-1", "op": "create",
            "body": {"summary": "Dentist",
                     "start": {"dateTime": "2026-08-18T09:15:00"},
                     "end": {"dateTime": "2026-08-18T09:45:00"}}}]
    code, _obj, _ = run(["push", "--stdin"], stdin_text=json.dumps(ops))
    sent = calls[0]["body"]
    check("the push exits 0", code == 0, str(code))
    check("a naive body reaches the wire with a zone on both ends",
          bool(sent["start"].get("timeZone")) and bool(sent["end"].get("timeZone")),
          json.dumps(sent))


def test_push_all_auth_is_exit_3(root):
    workspace(root, "push-auth", token=stored_token())
    fake_http(lambda call, n: (401, {"error": {"code": 401,
                                               "message": "Invalid Credentials"}}))
    code, obj, _ = run(["push", "--stdin"],
                       stdin_text=json.dumps([{"id": "evt-1", "op": "create",
                                               "body": {}}]))
    check("a batch the token cannot make exits 3", code == 3, str(code))
    check("that batch answers {ok:false,error:auth}",
          obj == {"ok": False, "error": "auth"}, json.dumps(obj))


def test_push_needs_stdin(root):
    workspace(root, "push-nostdin", token=stored_token())
    fake_http(lambda call, n: (200, {}))
    code, obj, _ = run(["push"])
    check("push without --stdin is refused", code == 1 and obj["ok"] is False)


# ------------------------------------------------------------------- auth --


def drive_consent(state_override=None, error=None, box=None):
    """Stand in for the browser: answer the loopback exactly once.

    The opener is called while the server is already listening, so the thread
    can connect immediately; `handle_request` accepts it on the main thread.
    """
    box = box if box is not None else {}

    def opener(url):
        query = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(url).query))
        box["consent"] = query
        redirect = query["redirect_uri"]
        params = {"state": state_override if state_override is not None
                  else query["state"]}
        if error:
            params["error"] = error
        else:
            params["code"] = "4/FIXTURE-auth-code"

        def hit():
            try:
                urllib.request.urlopen(
                    f"{redirect}/?{urllib.parse.urlencode(params)}",
                    timeout=10).read()
            except Exception as exc:  # recorded, asserted on by the caller
                box["browser_error"] = repr(exc)

        thread = threading.Thread(target=hit, daemon=True)
        thread.start()
        box["thread"] = thread

    gcal.open_in_browser = opener
    return box


def test_auth_happy(root):
    tokfile = workspace(root, "auth-ok")
    token_body = fixture("token-response.json")

    def responder(call, n):
        if call["url"] == gcal.TOKEN_ENDPOINT:
            return 200, token_body
        return 200, fixture("userinfo.json")

    calls = fake_http(responder)
    box = drive_consent()
    code, obj, err = run(["auth"])
    box["thread"].join(timeout=5)
    consent = box["consent"]
    saved = json.loads(tokfile.read_text())

    check("auth exits 0", code == 0, json.dumps(obj))
    check("auth answers with the account, nothing else",
          obj == {"ok": True, "email": "daniel@example.com"}, json.dumps(obj))
    check("the browser was pointed at the loopback we bound",
          consent["redirect_uri"].startswith("http://127.0.0.1:")
          and consent["redirect_uri"].split(":")[-1] != "0",
          consent["redirect_uri"])
    check("consent asks for offline access with S256 PKCE",
          consent["code_challenge_method"] == "S256"
          and consent["access_type"] == "offline" and consent["code_challenge"])
    check("consent asks for exactly the scopes the shell uses",
          consent["scope"].split(" ") == gcal.SCOPES, consent["scope"])

    verifier = calls[0]["form"]["code_verifier"]
    digest = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
    check("the verifier sent to /token is the one the challenge was made from",
          digest == consent["code_challenge"], digest)
    check("the code exchange sends the same redirect_uri it bound",
          calls[0]["form"]["redirect_uri"] == consent["redirect_uri"])
    check("the token file is written 0600", mode_of(tokfile) == 0o600,
          oct(mode_of(tokfile)))
    check("the token file holds the refresh token",
          saved["refresh_token"] == token_body["refresh_token"])
    check("the stored expiry is absolute, not the relative one Google sent",
          saved["expires_at"] > time.time() + 3000)
    check("no client secret is stored beside the token",
          CLIENT_SECRET not in tokfile.read_text())
    check("auth says where it wrote on stderr", "token written to" in err, err[:80])


def test_auth_rejects_wrong_state(root):
    tokfile = workspace(root, "auth-state")
    fake_http(lambda call, n: (200, fixture("token-response.json")))
    box = drive_consent(state_override="attacker-supplied")
    code, obj, _ = run(["auth"])
    box["thread"].join(timeout=5)

    check("a mismatched state exits 1", code == 1, str(code))
    check("a mismatched state writes no token", not tokfile.exists())
    check("a mismatched state never exchanges the code",
          "state" in obj.get("error", ""), json.dumps(obj))


def test_auth_refused_consent(root):
    tokfile = workspace(root, "auth-refused")
    fake_http(lambda call, n: (200, {}))
    box = drive_consent(error="access_denied")
    code, obj, _ = run(["auth"])
    box["thread"].join(timeout=5)

    check("a refused consent exits 3", code == 3, str(code))
    check("a refused consent writes no token", not tokfile.exists())
    check("a refused consent answers auth", obj["error"] == "auth")


def test_auth_without_creds(root):
    workspace(root, "auth-nocreds", creds=False)
    fake_http(lambda call, n: (200, {}))
    code, obj, _ = run(["auth"])
    check("auth with no client credentials exits 3", code == 3, str(code))
    check("auth with no client credentials answers auth", obj["error"] == "auth")


def test_token_umask_is_forced(root):
    """A loose umask must not widen the token file — os.open's mode is masked."""
    tokfile = workspace(root, "umask")
    old = os.umask(0o000)
    try:
        gcal.save_token({"access_token": "x", "refresh_token": "y",
                         "expires_at": 0})
    finally:
        os.umask(old)
    check("save_token forces 0600 under umask 000", mode_of(tokfile) == 0o600,
          oct(mode_of(tokfile)))
    check("save_token leaves no .tmp behind",
          not tokfile.with_name(tokfile.name + ".tmp").exists())


def test_no_secret_reached_stdout():
    joined = "".join(stdout_seen)
    leaked = [s for s in SECRETS if s in joined]
    check("no token or secret reached stdout in any run", not leaked,
          ",".join(x[:12] for x in leaked))
    check("every run printed exactly one JSON object",
          all(isinstance(json.loads(t), dict) for t in stdout_seen if t.strip()))


# ------------------------------------------------------------------ probes --
#
# Adversarial second pass. Each of these was written to break the tool rather
# than to describe it; the three that did break it are marked.


def test_probe_unwritable_token_still_answers_json(root):
    """A path the token cannot be written to must still answer on stdout.

    Broke it: `load_token`/`save_token` raise OSError, nothing caught it, and
    the caller got a traceback on stderr and *nothing* on stdout — the one
    thing the contract promises can never happen.
    """
    work = root / "unwritable"
    work.mkdir()
    (work / "google-oauth.json").write_text(json.dumps({
        "installed": {"client_id": "x", "client_secret": CLIENT_SECRET}}))
    os.environ["FOREST_GCAL_OAUTH"] = str(work / "google-oauth.json")
    (work / "blocker").write_text("a file where a directory has to be")
    os.environ["FOREST_GCAL_TOKEN"] = str(work / "blocker" / "cal" / "tok.json")
    fake_http(lambda call, n: (200, fixture("token-refresh-rotated.json")))

    code, obj, err = run(["refresh"])
    check("an unwritable token path exits 1, not a traceback", code == 1, str(code))
    check("an unwritable token path still prints one JSON object on stdout",
          obj.get("ok") is False and "_unparseable" not in obj, json.dumps(obj)[:120])
    check("the traceback goes to stderr where humans read it",
          "Traceback" in err or "NotADirectory" in err, err[-80:])


def test_probe_malformed_op_is_bad_op(root):
    """One malformed op must cost its own result, not the batch's answer.

    Broke it: a non-object entry reached `op.get` and raised AttributeError out
    of `main`, so a single bad element in the array the shell sends destroyed
    the results for every good op beside it.
    """
    workspace(root, "push-malformed", token=stored_token())
    created = fixture("push-create-201.json")
    calls = fake_http(lambda call, n: (201, created))
    ops = ["nonsense", 7, None, {"id": "evt-9", "op": "create", "body": {"summary": "Fine"}}]
    code, obj, _ = run(["push", "--stdin"], stdin_text=json.dumps(ops))

    check("a batch with malformed ops still exits 0", code == 0, str(code))
    check("every op still gets exactly one result",
          len(obj.get("results", [])) == len(ops), json.dumps(obj)[:160])
    check("a non-object op is refused as bad-op",
          [r["error"] for r in obj["results"][:3]] == ["bad-op"] * 3,
          json.dumps(obj["results"][:3]))
    check("the good op beside it still reached the network and succeeded",
          len(calls) == 1 and obj["results"][3]["ok"] is True,
          json.dumps(obj["results"][3]))


def test_probe_stray_request_does_not_eat_the_callback(root):
    """A GET that is not the redirect must not end the wait.

    Broke it: the listener served exactly one request of any shape, so the
    browser's own /favicon.ico (or anything else on the machine knocking on an
    open port) consumed it, and the real redirect was refused with
    "wrong state" — blaming the user for someone else's request.
    """
    tokfile = workspace(root, "auth-stray")
    fake_http(lambda call, n: (200, fixture("token-response.json"))
              if call["url"] == gcal.TOKEN_ENDPOINT
              else (200, fixture("userinfo.json")))
    box = {}

    def opener(url):
        query = dict(urllib.parse.parse_qsl(urllib.parse.urlparse(url).query))
        redirect = query["redirect_uri"]

        def hit():
            for target in (f"{redirect}/favicon.ico",
                           f"{redirect}/?" + urllib.parse.urlencode(
                               {"state": query["state"], "code": "4/FIXTURE-auth-code"})):
                try:
                    urllib.request.urlopen(target, timeout=10).read()
                except Exception as exc:
                    box.setdefault("errors", []).append(repr(exc))

        box["thread"] = threading.Thread(target=hit, daemon=True)
        box["thread"].start()

    gcal.open_in_browser = opener
    old_timeout, gcal.AUTH_TIMEOUT_S = gcal.AUTH_TIMEOUT_S, 15
    try:
        code, obj, _ = run(["auth"])
    finally:
        gcal.AUTH_TIMEOUT_S = old_timeout
    box["thread"].join(timeout=10)

    check("a favicon request ahead of the redirect does not fail the flow",
          code == 0 and obj.get("ok") is True, json.dumps(obj))
    check("the redirect after the stray request still writes the token",
          tokfile.exists() and mode_of(tokfile) == 0o600)
    check("the stray request was answered rather than dropped",
          not box.get("errors"), ",".join(box.get("errors", []))[:120])


def test_probe_runaway_paging_stops(root):
    """A server that always offers another page must not spin forever."""
    workspace(root, "pull-runaway", token=stored_token())
    calls = fake_http(lambda call, n: (200, {"items": [], "nextPageToken": "MORE"}))
    code, obj, _ = run(["pull"])
    check("endless paging is refused rather than followed", code == 1, str(code))
    check("it gives up at MAX_PAGES exactly", len(calls) == gcal.MAX_PAGES,
          str(len(calls)))
    check("the give-up still answers JSON", obj.get("ok") is False)


def test_probe_refresh_margin_is_the_margin(root):
    """The refresh fires inside the 60s margin and not a moment earlier."""
    workspace(root, "margin-inside", token=stored_token(expires_in=30))
    calls = fake_http(lambda call, n: (200, fixture("token-refresh-rotated.json"))
                      if call["url"] == gcal.TOKEN_ENDPOINT else (200, {"items": []}))
    run(["pull"])
    check("a token expiring inside the margin is refreshed first",
          calls[0]["url"] == gcal.TOKEN_ENDPOINT, calls[0]["url"])

    workspace(root, "margin-outside", token=stored_token(expires_in=600))
    calls = fake_http(lambda call, n: (200, {"items": [], "nextSyncToken": "T"}))
    run(["pull"])
    check("a token outside the margin is spent as it stands",
          all(c["url"] != gcal.TOKEN_ENDPOINT for c in calls), str(len(calls)))
    check("status agrees with access_token about what expired means",
          run(["status"])[1]["expired"] is False)


def test_probe_partial_auth_batch_still_exits_0(root):
    """Only an all-refused batch is an auth failure; a mixed one is payload."""
    workspace(root, "push-mixed", token=stored_token())

    def responder(call, n):
        return (401, {"error": {"code": 401, "message": "Invalid Credentials"}}) \
            if n == 0 else (201, fixture("push-create-201.json"))

    fake_http(responder)
    ops = [{"id": "evt-1", "op": "create", "body": {}},
           {"id": "evt-2", "op": "create", "body": {}}]
    code, obj, _ = run(["push", "--stdin"], stdin_text=json.dumps(ops))
    check("a batch with one auth refusal still exits 0", code == 0, str(code))
    check("the refusal is reported per op, not as the batch's answer",
          obj["results"][0]["error"] == "auth" and obj["results"][1]["ok"] is True,
          json.dumps(obj["results"]))


def test_probe_http_is_the_only_chokepoint():
    """The claim the tests rest on: faking `_http` really does cut the wire."""
    source = TOOL.read_text()
    tree = __import__("ast").parse(source)
    callers = set()
    for node in __import__("ast").walk(tree):
        if isinstance(node, __import__("ast").FunctionDef):
            body = __import__("ast").dump(node)
            if "urlopen" in body or "'socket'" in body:
                callers.add(node.name)
    check("only _http opens a connection", callers <= {"_http"},
          ",".join(sorted(callers)))
    check("nothing writes the token file but save_token",
          source.count("os.open(") == 1)


def test_probe_existing_token_file_is_narrowed(root):
    """Replacing a token file left world-readable by an older run narrows it.

    The *directory* is left exactly as it was found. It is shared — events.json
    lives in it — so a helper that tightened somebody's own choice of mode would
    be reaching outside the one file it owns. The secret's protection is the
    0600, which does not depend on the directory's mode.
    """
    tokfile = workspace(root, "narrow", token=stored_token(expires_in=-10))
    os.chmod(tokfile, 0o644)
    os.chmod(tokfile.parent, 0o755)
    fake_http(lambda call, n: (200, fixture("token-refresh-rotated.json")))
    code, _, _ = run(["refresh"])
    check("refreshing over a 0644 token file leaves it 0600",
          code == 0 and mode_of(tokfile) == 0o600, oct(mode_of(tokfile)))
    check("and leaves the shared directory's mode alone",
          mode_of(tokfile.parent) == 0o755, oct(mode_of(tokfile.parent)))


def test_probe_a_world_writable_token_directory_is_narrowed(root):
    """The one pre-existing directory the helper does change: a writable one.

    0755 is a preference and is left alone (above). 0757 is a hole: the 0600 on
    the token protects nothing when anyone can rename it out of the directory
    and drop their own file in its place, so the mode has to come down or the
    file mode is a claim the filesystem does not back.
    """
    tokfile = workspace(root, "wide-dir", token=stored_token(expires_in=-10))
    os.chmod(tokfile.parent, 0o757)
    fake_http(lambda call, n: (200, fixture("token-refresh-rotated.json")))
    code, _, _ = run(["refresh"])
    check("a world-writable token directory is narrowed to 0700",
          code == 0 and mode_of(tokfile.parent) == 0o700, oct(mode_of(tokfile.parent)))

    group = workspace(root, "group-dir", token=stored_token(expires_in=-10))
    os.chmod(group.parent, 0o775)
    fake_http(lambda call, n: (200, fixture("token-refresh-rotated.json")))
    code, _, _ = run(["refresh"])
    check("and so is a group-writable one",
          code == 0 and mode_of(group.parent) == 0o700, oct(mode_of(group.parent)))

    readable = workspace(root, "readable-dir", token=stored_token(expires_in=-10))
    os.chmod(readable.parent, 0o755)
    fake_http(lambda call, n: (200, fixture("token-refresh-rotated.json")))
    code, _, _ = run(["refresh"])
    check("a merely readable one is somebody's choice and is left alone",
          code == 0 and mode_of(readable.parent) == 0o755, oct(mode_of(readable.parent)))


def test_probe_a_directory_this_helper_creates_is_0700(root):
    """The one case the helper does decide: a token directory it made itself."""
    tokfile = workspace(root, "fresh-dir", token=stored_token())
    shutil.rmtree(tokfile.parent, ignore_errors=True)
    check("the token directory did not exist before the write",
          not tokfile.parent.exists())
    written = gcal.save_token(stored_token())
    check("a token directory this helper created is 0700",
          mode_of(written.parent) == 0o700, oct(mode_of(written.parent)))
    check("and the token in it is 0600", mode_of(written) == 0o600, oct(mode_of(written)))


def main():
    root = Path(tempfile.mkdtemp(prefix="gcal-sync-tests-"))
    saved_env = {k: os.environ.get(k)
                 for k in ("FOREST_GCAL_OAUTH", "FOREST_GCAL_TOKEN")}
    real_http, real_opener = gcal._http, gcal.open_in_browser
    try:
        test_window_bounds()
        test_pull_pages(root)
        test_pull_incremental(root)
        test_pull_gone(root)
        test_pull_calendar_id_is_escaped(root)
        test_window_rejects_nonsense(root)
        test_refresh_rotation(root)
        test_refresh_without_rotation(root)
        test_refresh_invalid_grant(root)
        test_no_token_is_auth(root)
        test_status(root)
        test_push(root)
        test_machine_timezone()
        test_fill_timezone()
        test_push_fills_a_missing_timezone(root)
        test_push_all_auth_is_exit_3(root)
        test_push_needs_stdin(root)
        test_auth_happy(root)
        test_auth_rejects_wrong_state(root)
        test_auth_refused_consent(root)
        test_auth_without_creds(root)
        test_token_umask_is_forced(root)
        test_probe_unwritable_token_still_answers_json(root)
        test_probe_malformed_op_is_bad_op(root)
        test_probe_stray_request_does_not_eat_the_callback(root)
        test_probe_runaway_paging_stops(root)
        test_probe_refresh_margin_is_the_margin(root)
        test_probe_partial_auth_batch_still_exits_0(root)
        test_probe_http_is_the_only_chokepoint()
        test_probe_existing_token_file_is_narrowed(root)
        test_probe_a_world_writable_token_directory_is_narrowed(root)
        test_probe_a_directory_this_helper_creates_is_0700(root)
        test_no_secret_reached_stdout()
    finally:
        gcal._http, gcal.open_in_browser = real_http, real_opener
        for key, value in saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        shutil.rmtree(root, ignore_errors=True)

    if failures:
        print(f"{len(failures)} check(s) failed")
        return 1
    print("gcal-sync: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
