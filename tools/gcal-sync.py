#!/usr/bin/env python3
"""Google Calendar helper — every Google HTTP request the shell makes.

QML cannot open a loopback listener, cannot chmod a file to 0600, and cannot be
unit-tested against a faked `urlopen`; OAuth needs all three. So the whole
Google surface — PKCE consent, token storage and rotation, incremental pulls,
event pushes — lives here, behind one `_http` chokepoint, and the shell spawns
this and parses one JSON object.

    tools/gcal-sync.py auth
    tools/gcal-sync.py status
    tools/gcal-sync.py calendars
    tools/gcal-sync.py pull [--calendar ID] [--sync-token T] [--window DAYS]
    tools/gcal-sync.py push --stdin < ops.json
    tools/gcal-sync.py refresh

Contract, so the caller never has to guess:
  * exactly one JSON object on **stdout**, nothing else, ever;
  * human-readable progress and diagnostics on **stderr**;
  * no access token, refresh token or client secret is ever written to either;
  * exit 0 the request was answered, 1 something broke, 3 the user must
    re-authorise (`{"ok":false,"error":"auth"}` — the shell logs
    `calendar: sync auth needed`).

Per-op push outcomes are payload, not process state: a batch that was delivered
exits 0 even when an op inside it was refused, because the caller has to read
the results either way, and an exit code cannot carry three of them.

Credentials: `$XDG_CONFIG_HOME/forest-shell/google-oauth.json` (or
`FOREST_GCAL_OAUTH`), the file Google Cloud Console hands you for a **Desktop
app** client. Tokens: `$XDG_DATA_HOME/forest-shell/calendar/google-token.json`
(or `FOREST_GCAL_TOKEN`), written 0600 by `os.open` + atomic rename.

Google's device flow does not permit Calendar scopes, so a loopback redirect on
127.0.0.1 with PKCE S256 is the only supported desktop path.

Stdlib only, same rule as every other tool in a gate: it must run anywhere.
"""

import argparse
import base64
import hashlib
import http.server
import json
import os
import secrets
import subprocess
import sys
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
USERINFO_ENDPOINT = "https://www.googleapis.com/oauth2/v3/userinfo"
API_ROOT = "https://www.googleapis.com/calendar/v3"

SCOPES = [
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
    "https://www.googleapis.com/auth/userinfo.email",
]

# Refresh this far before the server's own expiry, so a request never races the
# clock it was authorised against.
REFRESH_MARGIN_S = 60
PAGE_SIZE = 250
MAX_PAGES = 40
AUTH_TIMEOUT_S = 300


class ToolError(Exception):
    """Something broke. Exit 1."""


class AuthError(ToolError):
    """The user must re-authorise. Exit 3."""


# ---------------------------------------------------------------- transport --


def _http(method, url, params=None, form=None, json_body=None, headers=None,
          timeout=30):
    """The one place this tool talks to the network.

    Returns `(status, obj)`; a non-2xx status is returned, not raised, because
    410 and 412 are answers the caller acts on rather than failures. `obj` is
    the parsed JSON body, `{}` for an empty one, `{"_raw": text}` for a body
    that is not JSON. Only a transport failure raises.
    """
    if params:
        url = url + "?" + urllib.parse.urlencode(params)
    body = None
    head = dict(headers or {})
    if form is not None:
        body = urllib.parse.urlencode(form).encode()
        head["Content-Type"] = "application/x-www-form-urlencoded"
    elif json_body is not None:
        body = json.dumps(json_body).encode()
        head["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, method=method, headers=head)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, _parse_body(resp.read())
    except urllib.error.HTTPError as exc:
        return exc.code, _parse_body(exc.read())
    except urllib.error.URLError as exc:
        raise ToolError(f"network: {exc.reason}") from exc


def _parse_body(raw):
    text = (raw or b"").decode("utf-8", "replace").strip()
    if not text:
        return {}
    try:
        obj = json.loads(text)
    except ValueError:
        return {"_raw": text[:400]}
    return obj if isinstance(obj, dict) else {"_list": obj}


# ------------------------------------------------------------------- files --


def creds_path():
    override = os.environ.get("FOREST_GCAL_OAUTH")
    if override:
        return Path(override)
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "forest-shell" / "google-oauth.json"


def token_path():
    override = os.environ.get("FOREST_GCAL_TOKEN")
    if override:
        return Path(override)
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    return Path(base) / "forest-shell" / "calendar" / "google-token.json"


def load_creds():
    path = creds_path()
    try:
        obj = json.loads(path.read_text())
    except FileNotFoundError:
        raise AuthError(f"no client credentials at {path}") from None
    except ValueError as exc:
        raise ToolError(f"{path}: not JSON ({exc})") from None
    # Console hands out {"installed": {...}}; accept it and the flat form.
    if isinstance(obj.get("installed"), dict):
        obj = obj["installed"]
    elif isinstance(obj.get("web"), dict):
        obj = obj["web"]
    if not obj.get("client_id"):
        raise ToolError(f"{path}: no client_id")
    return obj


def load_token():
    path = token_path()
    try:
        obj = json.loads(path.read_text())
    except FileNotFoundError:
        return None
    except ValueError as exc:
        raise ToolError(f"{path}: not JSON ({exc})") from None
    return obj if isinstance(obj, dict) else None


def save_token(tok):
    """Write the token file 0600 and atomically.

    `os.open` sets the mode at creation so the secret is never briefly world
    readable; umask can only take bits away, so chmod restates it. The rename
    is what makes a half-written file impossible.
    """
    path = token_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(path.parent, 0o700)
    except OSError:
        pass
    tmp = path.with_name(path.name + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(tok, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    return path


# -------------------------------------------------------------------- time --


def _now():
    return time.time()


def _rfc3339(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")


def machine_timezone():
    """This machine's IANA zone name, e.g. `Europe/London`. `UTC` if unknowable.

    Wanted because a timed `dateTime` with no offset and no `timeZone` is a
    naive local time the API refuses outright, and the shell can reach this
    machine's zone name only awkwardly. The caller normally states the zone; this
    is the backstop that keeps a missing one from turning into a failed push.

    `time.tzname` is deliberately not used: it yields abbreviations (`BST`,
    `CEST`) which are ambiguous across regions and not what the API accepts. The
    zoneinfo symlink is the only spelling on a systemd machine that is a real
    zone id, and `TZ` is honoured first because a caller who set it means it.
    """
    tz = os.environ.get("TZ", "").strip().lstrip(":")
    if tz and (tz == "UTC" or "/" in tz):
        return tz
    try:
        link = os.path.realpath("/etc/localtime")
        marker = "/zoneinfo/"
        if marker in link:
            return link.split(marker, 1)[1]
    except OSError:
        pass
    try:
        with open("/etc/timezone", encoding="utf-8") as handle:
            named = handle.read().strip()
        if named:
            return named
    except OSError:
        pass
    return "UTC"


def fill_timezone(body, zone=None):
    """A push body with a zone on every naive `dateTime`.

    Only naive ones. A `dateTime` that already carries an offset states its own
    instant, and an all-day `date` has no time of day to place, so both are left
    exactly as the shell wrote them — this adds the one piece of information
    that has no other source, and never overrides an answer already given.
    """
    if not isinstance(body, dict):
        return body
    named = zone or machine_timezone()
    for end in ("start", "end"):
        slot = body.get(end)
        if not isinstance(slot, dict):
            continue
        stamp = slot.get("dateTime", "")
        if not isinstance(stamp, str) or not stamp:
            continue
        if slot.get("timeZone"):
            continue
        # A sign after the date part is an offset. The date's own hyphens are
        # skipped by starting at the `T`, which is why this is a slice and not
        # an `in`.
        after_date = stamp[10:]
        if stamp.endswith("Z") or "+" in after_date or "-" in after_date:
            continue
        slot["timeZone"] = named
    return body


def window_bounds(days, now=None):
    """`--window DAYS` means DAYS in *each* direction around now.

    A calendar surface shows what just happened as well as what is coming, so a
    one-sided window would make yesterday's events vanish on the first full
    pull. Returned as the RFC3339 pair the API wants.
    """
    if days is None:
        return None, None
    if days <= 0:
        raise ToolError("--window needs a positive number of days")
    base = _now() if now is None else now
    span = timedelta(days=days).total_seconds()
    return _rfc3339(base - span), _rfc3339(base + span)


# ---------------------------------------------------------------- oauth --


def _pkce():
    verifier = base64.urlsafe_b64encode(secrets.token_bytes(48)).decode().rstrip("=")
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).decode().rstrip("=")
    return verifier, challenge


def consent_url(client_id, redirect_uri, state, challenge):
    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "state": state,
        "code_challenge": challenge,
        "code_challenge_method": "S256",
        "access_type": "offline",
        "prompt": "consent",
    }
    return AUTH_ENDPOINT + "?" + urllib.parse.urlencode(params)


def open_in_browser(url):
    """Hand the URL to the desktop, and fall back to the human.

    A headless run, a missing xdg-open and a broken handler all look the same
    from here, so all three end the same way: the URL on stderr, where the
    contract already says human text goes.
    """
    try:
        proc = subprocess.run(["xdg-open", url], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=10)
        if proc.returncode == 0:
            _say("opened the consent page in your browser")
            return
    except (OSError, subprocess.SubprocessError):
        pass
    _say("open this URL to authorise forest-shell:")
    _say(url)


_PAGE = (b"<!doctype html><meta charset=utf-8><title>forest-shell</title>"
         b"<body style='font:16px system-ui;padding:3rem'>"
         b"<p>forest-shell is connected. You can close this tab.</p>")


class _CallbackHandler(http.server.BaseHTTPRequestHandler):
    query = None

    def do_GET(self):  # noqa: N802 — BaseHTTPRequestHandler's spelling
        parsed = urllib.parse.urlparse(self.path)
        query = dict(urllib.parse.parse_qsl(parsed.query))
        # Only a request carrying `code` or `error` is the redirect. A browser
        # asks the same origin for /favicon.ico, and anything else on the
        # machine can knock on an open port; treating a stray GET as the
        # callback ends the wait with an empty query, which reads as a state
        # mismatch and blames the user for someone else's request.
        if "code" in query or "error" in query:
            type(self).query = query
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(_PAGE)))
        self.end_headers()
        self.wfile.write(_PAGE)

    def log_message(self, *_args):
        pass  # the access log is not our stderr contract


def exchange_code(creds, code, verifier, redirect_uri):
    form = {
        "client_id": creds["client_id"],
        "code": code,
        "code_verifier": verifier,
        "grant_type": "authorization_code",
        "redirect_uri": redirect_uri,
    }
    if creds.get("client_secret"):
        form["client_secret"] = creds["client_secret"]
    status, obj = _http("POST", TOKEN_ENDPOINT, form=form)
    if status != 200:
        raise AuthError(f"token exchange refused: {_api_error(obj, status)}")
    return _token_record(obj, None)


def refresh_access(creds, tok):
    """Spend the refresh token, and take the new one if Google rotates it."""
    refresh = (tok or {}).get("refresh_token")
    if not refresh:
        raise AuthError("no refresh token stored — run `auth`")
    form = {
        "client_id": creds["client_id"],
        "refresh_token": refresh,
        "grant_type": "refresh_token",
    }
    if creds.get("client_secret"):
        form["client_secret"] = creds["client_secret"]
    status, obj = _http("POST", TOKEN_ENDPOINT, form=form)
    if status != 200:
        if obj.get("error") == "invalid_grant":
            raise AuthError("refresh token rejected (invalid_grant)")
        raise ToolError(f"refresh failed: {_api_error(obj, status)}")
    fresh = _token_record(obj, tok)
    save_token(fresh)
    return fresh


def _token_record(obj, previous):
    prev = previous or {}
    record = {
        "access_token": obj.get("access_token", ""),
        # Rotation: a response carrying a new refresh token replaces the old
        # one, and a response without one leaves it standing.
        "refresh_token": obj.get("refresh_token") or prev.get("refresh_token", ""),
        "expires_at": int(_now() + int(obj.get("expires_in", 3600))),
        "scope": obj.get("scope", prev.get("scope", " ".join(SCOPES))),
        "token_type": obj.get("token_type", "Bearer"),
    }
    if prev.get("email"):
        record["email"] = prev["email"]
    if not record["access_token"]:
        raise AuthError("token response carried no access_token")
    return record


def access_token(force=False):
    """The token every API call goes out with, refreshed when it is due."""
    tok = load_token()
    if not tok:
        raise AuthError(f"not connected — no token at {token_path()}")
    if force or tok.get("expires_at", 0) - REFRESH_MARGIN_S <= _now():
        tok = refresh_access(load_creds(), tok)
    return tok


def _auth_header(tok):
    return {"Authorization": f"Bearer {tok['access_token']}"}


def fetch_email(tok):
    status, obj = _http("GET", USERINFO_ENDPOINT, headers=_auth_header(tok))
    if status != 200:
        return ""
    return obj.get("email", "")


# ------------------------------------------------------------------ errors --


def _api_error(obj, status):
    err = obj.get("error")
    if isinstance(err, dict):
        return err.get("message") or err.get("status") or f"http {status}"
    if isinstance(err, str):
        detail = obj.get("error_description")
        return f"{err}: {detail}" if detail else err
    return f"http {status}"


def _op_error(status, obj):
    """Map an HTTP answer onto the short code the shell logs and retries on."""
    if status in (401,):
        return "auth"
    if status == 403:
        reason = ""
        err = obj.get("error")
        if isinstance(err, dict):
            errors = err.get("errors") or []
            if errors and isinstance(errors[0], dict):
                reason = errors[0].get("reason", "")
        throttled = ("rateLimitExceeded", "userRateLimitExceeded",
                     "quotaExceeded")
        return "rate" if reason in throttled else "forbidden"
    if status == 404:
        return "notfound"
    if status in (409, 412):
        return "conflict"
    if status == 410:
        return "gone"
    if status == 429:
        return "rate"
    if 500 <= status < 600:
        return "server"
    return f"http:{status}"


# ------------------------------------------------------------- subcommands --


def cmd_auth(args, opener=None):
    creds = load_creds()
    verifier, challenge = _pkce()
    state = secrets.token_urlsafe(24)

    _CallbackHandler.query = None
    server = http.server.HTTPServer(("127.0.0.1", 0), _CallbackHandler)
    redirect_uri = f"http://127.0.0.1:{server.server_port}"
    try:
        (opener or open_in_browser)(
            consent_url(creds["client_id"], redirect_uri, state, challenge))
        # Serve until the redirect arrives, then stop listening. Stray requests
        # are answered and ignored, so the whole flow still has one deadline
        # rather than one request.
        deadline = _now() + AUTH_TIMEOUT_S
        while _CallbackHandler.query is None:
            remaining = deadline - _now()
            if remaining <= 0:
                break
            server.timeout = remaining
            server.handle_request()
    finally:
        server.server_close()

    query = _CallbackHandler.query
    if query is None:
        raise ToolError("timed out waiting for the browser redirect")
    if query.get("error"):
        raise AuthError(f"consent refused: {query['error']}")
    if not secrets.compare_digest(query.get("state", ""), state):
        raise ToolError("redirect carried the wrong state — refusing the code")
    code = query.get("code")
    if not code:
        raise ToolError("redirect carried no authorisation code")

    tok = exchange_code(creds, code, verifier, redirect_uri)
    tok["email"] = fetch_email(tok)
    path = save_token(tok)
    _say(f"token written to {path}")
    return {"ok": True, "email": tok["email"]}, 0


def cmd_status(args):
    tok = load_token()
    if not tok:
        return {"ok": True, "connected": False, "tokenPath": str(token_path())}, 0
    return {
        "ok": True,
        "connected": True,
        "email": tok.get("email", ""),
        "expiresAt": _rfc3339(tok.get("expires_at", 0)),
        "expired": tok.get("expires_at", 0) - REFRESH_MARGIN_S <= _now(),
        "scope": tok.get("scope", ""),
        "tokenPath": str(token_path()),
    }, 0


def cmd_refresh(args):
    tok = refresh_access(load_creds(), load_token() or {})
    return {"ok": True, "expiresAt": _rfc3339(tok["expires_at"])}, 0


def cmd_calendars(args):
    tok = access_token()
    status, obj = _http("GET", f"{API_ROOT}/users/me/calendarList",
                        params={"minAccessRole": "reader", "maxResults": 250},
                        headers=_auth_header(tok))
    if status == 401:
        raise AuthError("calendarList refused the token")
    if status != 200:
        raise ToolError(f"calendarList: {_api_error(obj, status)}")
    calendars = [{
        "id": item.get("id", ""),
        "summary": item.get("summary", ""),
        "primary": bool(item.get("primary")),
        "accessRole": item.get("accessRole", ""),
        "timeZone": item.get("timeZone", ""),
        "backgroundColor": item.get("backgroundColor", ""),
    } for item in obj.get("items", [])]
    return {"ok": True, "calendars": calendars}, 0


def cmd_pull(args):
    tok = access_token()
    cal = urllib.parse.quote(args.calendar, safe="")
    url = f"{API_ROOT}/calendars/{cal}/events"
    base = {
        # Instances, not masters: the shell stores flat events, and a deleted
        # one only arrives at all because showDeleted asks for it.
        "singleEvents": "true",
        "showDeleted": "true",
        "maxResults": PAGE_SIZE,
    }
    full = not args.sync_token
    if args.sync_token:
        base["syncToken"] = args.sync_token
    else:
        # timeMin/timeMax are illegal alongside a syncToken, and meaningless:
        # the token already carries the window the last full pull established.
        lo, hi = window_bounds(args.window)
        if lo:
            base["timeMin"], base["timeMax"] = lo, hi

    events, sync_token, page_token, pages = [], "", None, 0
    while True:
        params = dict(base)
        if page_token:
            params["pageToken"] = page_token
        status, obj = _http("GET", url, params=params, headers=_auth_header(tok))
        if status == 410:
            # The token aged out. Not a failure: the shell answers by asking
            # for a full pull, so this exits 0 with the fact it needs.
            _say("sync token expired — a full pull is needed")
            return {"ok": True, "gone": True, "events": [], "full": False}, 0
        if status == 401:
            raise AuthError("events.list refused the token")
        if status != 200:
            raise ToolError(f"events.list: {_api_error(obj, status)}")
        events.extend(obj.get("items", []))
        sync_token = obj.get("nextSyncToken", sync_token)
        page_token = obj.get("nextPageToken")
        pages += 1
        if not page_token:
            break
        if pages >= MAX_PAGES:
            raise ToolError(f"events.list did not finish in {MAX_PAGES} pages")
    _say(f"pulled {len(events)} event(s) over {pages} page(s)")
    return {"ok": True, "events": events, "nextSyncToken": sync_token,
            "full": full}, 0


def _read_ops(args):
    if not args.stdin:
        raise ToolError("push reads its ops from stdin — pass --stdin")
    try:
        obj = json.loads(sys.stdin.read() or "[]")
    except ValueError as exc:
        raise ToolError(f"stdin is not JSON ({exc})") from None
    if isinstance(obj, dict):
        obj = obj.get("ops", [])
    if not isinstance(obj, list):
        raise ToolError("expected a JSON array of ops")
    return obj


def _push_one(op, tok, url_base):
    """One op, one result. Never raises for an outcome the caller can read."""
    if not isinstance(op, dict):
        # The op array comes from the shell over stdin; one malformed entry
        # must cost its own result, not the whole batch's answer.
        return {"id": "", "ok": False, "googleId": "", "error": "bad-op"}
    op_id = str(op.get("id", ""))
    kind = op.get("op", "")
    google_id = op.get("googleId", "")
    result = {"id": op_id, "ok": False, "googleId": google_id}

    if kind not in ("create", "patch", "delete"):
        result["error"] = "bad-op"
        return result
    if kind in ("patch", "delete") and not google_id:
        result["error"] = "missing-google-id"
        return result

    # The shell states the zone; this is the backstop. A naive `dateTime` with
    # no `timeZone` beside it is rejected by the API, and it is rejected per op,
    # so one unstated zone would fail exactly the events people had just made.
    body = fill_timezone(op.get("body") or {})

    headers = _auth_header(tok)
    if kind == "create":
        status, obj = _http("POST", url_base, params={"sendUpdates": "none"},
                            json_body=body, headers=headers)
    else:
        target = f"{url_base}/{urllib.parse.quote(google_id, safe='')}"
        if kind == "patch":
            status, obj = _http("PATCH", target, params={"sendUpdates": "none"},
                                json_body=body, headers=headers)
        else:
            status, obj = _http("DELETE", target,
                                params={"sendUpdates": "none"}, headers=headers)

    if kind == "delete" and status in (200, 204, 404, 410):
        # Deleting something already gone is the outcome we wanted, not a
        # failure to retry forever.
        result["ok"] = True
        return result
    if 200 <= status < 300:
        result.update(ok=True,
                      googleId=obj.get("id", google_id),
                      etag=obj.get("etag", ""),
                      updated=obj.get("updated", ""))
        return result
    result["error"] = _op_error(status, obj)
    return result


def cmd_push(args):
    ops = _read_ops(args)
    tok = access_token()
    cal = urllib.parse.quote(args.calendar, safe="")
    url_base = f"{API_ROOT}/calendars/{cal}/events"
    results = [_push_one(op, tok, url_base) for op in ops]
    if results and all(r.get("error") == "auth" for r in results):
        raise AuthError("every push was refused by the token")
    failed = sum(1 for r in results if not r["ok"])
    _say(f"pushed {len(results)} op(s), {failed} refused")
    return {"ok": True, "results": results}, 0


# --------------------------------------------------------------------- cli --


def _say(text):
    print(text, file=sys.stderr)


def build_parser():
    parser = argparse.ArgumentParser(
        prog="gcal-sync.py", description=__doc__.split("\n\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter)
    subs = parser.add_subparsers(dest="cmd", required=True)

    subs.add_parser("auth", help="run the loopback PKCE consent flow")
    subs.add_parser("status", help="report the stored token, never its value")
    subs.add_parser("refresh", help="spend the refresh token now")
    subs.add_parser("calendars", help="list the calendars this account reads")

    pull = subs.add_parser("pull", help="list events, incrementally when able")
    pull.add_argument("--calendar", default="primary")
    pull.add_argument("--sync-token", default="")
    pull.add_argument("--window", type=int, default=None,
                      help="days either side of now, full pulls only")

    push = subs.add_parser("push", help="apply create/patch/delete ops")
    push.add_argument("--calendar", default="primary")
    push.add_argument("--stdin", action="store_true",
                      help="read the op array from stdin")
    return parser


HANDLERS = {
    "auth": cmd_auth,
    "status": cmd_status,
    "refresh": cmd_refresh,
    "calendars": cmd_calendars,
    "pull": cmd_pull,
    "push": cmd_push,
}


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        obj, code = HANDLERS[args.cmd](args)
    except AuthError as exc:
        _say(f"auth: {exc}")
        obj, code = {"ok": False, "error": "auth"}, 3
    except ToolError as exc:
        _say(f"error: {exc}")
        obj, code = {"ok": False, "error": str(exc)}, 1
    except Exception:  # noqa: BLE001 — the stdout contract outranks the trace
        # "Exactly one JSON object on stdout, ever" has to survive the things
        # nobody enumerated: a token path whose parent is a file, a full disk, a
        # body shaped unlike anything recorded. The caller parses stdout, so a
        # bare traceback is an unparseable answer *and* a lost error. The trace
        # still goes to stderr, where the contract already puts human text.
        traceback.print_exc(file=sys.stderr)
        obj, code = {"ok": False, "error": "internal error — see stderr"}, 1
    print(json.dumps(obj))
    return code


if __name__ == "__main__":
    sys.exit(main())
