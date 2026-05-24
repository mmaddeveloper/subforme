#!/usr/bin/env python3
"""subforme-bridge — token-authenticated public JSON endpoint that exposes
PasarGuard/Marzban's per-user IP+UA history to the subscription template.

Env vars (loaded from systemd EnvironmentFile):
    PANEL_URL       e.g. http://127.0.0.1:8000
    PG_ADMIN_USER   panel admin username (read-capable is enough)
    PG_ADMIN_PASS   panel admin password
    PORT            local bind port (default 8787)
    LIMIT           max history rows to request (default 50)
    CACHE_SECONDS   per-token cache TTL (default 30)
    CACHE_MAX       max cached tokens (default 4096, LRU evicts above this)
"""

import json
import os
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import OrderedDict
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def _require_env(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        sys.stderr.write(f"[bridge] missing required env var {name} — set it in /opt/subforme-bridge/.env\n")
        sys.exit(2)
    return v


PANEL_URL = _require_env("PANEL_URL").rstrip("/")
ADMIN_USER = _require_env("PG_ADMIN_USER")
ADMIN_PASS = _require_env("PG_ADMIN_PASS")
try:
    PORT = int(os.environ.get("PORT", "8787"))
    LIMIT = int(os.environ.get("LIMIT", "50"))
    CACHE_SECONDS = int(os.environ.get("CACHE_SECONDS", "30"))
    CACHE_MAX = int(os.environ.get("CACHE_MAX", "4096"))
except ValueError as _e:
    sys.stderr.write(f"[bridge] invalid numeric env var: {_e}\n")
    sys.exit(2)

_jwt: str | None = None
_jwt_exp: float = 0.0
_jwt_lock = threading.Lock()

_cache: "OrderedDict[str, tuple[float, list]]" = OrderedDict()
_cache_lock = threading.Lock()

# Discovered-at-runtime sub_update URL template. Once a candidate returns
# 200 for the first user, we pin it so every subsequent lookup is one HTTP
# call instead of probing.
_sub_update_path_tmpl: str | None = None
_sub_update_lock = threading.Lock()


def _api_user_paths(quoted_user: str) -> list[str]:
    """Candidate paths for the user's sub_update history, in preference
    order. PasarGuard 4.0.x uses singular `/api/user/`; later builds also
    expose `/api/users/`. If we've already locked one in, return just it."""
    with _sub_update_lock:
        if _sub_update_path_tmpl is not None:
            return [_sub_update_path_tmpl.format(user=quoted_user, limit=LIMIT)]
    return [
        f"/api/user/{quoted_user}/sub_update?limit={LIMIT}",
        f"/api/users/{quoted_user}/sub_update?limit={LIMIT}",
    ]


def _remember_sub_update_path(path: str) -> None:
    """Convert a concrete path back into a template so we hit the same
    endpoint shape next time without re-probing."""
    global _sub_update_path_tmpl
    if "/api/user/" in path:
        tmpl = "/api/user/{user}/sub_update?limit={limit}"
    elif "/api/users/" in path:
        tmpl = "/api/users/{user}/sub_update?limit={limit}"
    else:
        return
    with _sub_update_lock:
        if _sub_update_path_tmpl != tmpl:
            _sub_update_path_tmpl = tmpl
            print(f"[bridge] pinned sub_update path template: {tmpl}", file=sys.stderr)


def _http(method: str, url: str, data=None, headers=None, timeout: int = 10):
    """Wrapper that swallows non-2xx into a (status, body) pair instead of
    raising HTTPError — so callers can branch on status rather than guess
    which exceptions to catch."""
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    req.add_header("User-Agent", "subforme-bridge/1.0")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        # body still readable for diagnostics; status is the error code
        try:
            body = e.read()
        except Exception:
            body = b""
        return e.code, body


def get_admin_jwt(force_refresh: bool = False) -> str:
    """Single-flight admin JWT refresh. The lock prevents two threads from
    both POSTing to /api/admin/token under contention."""
    global _jwt, _jwt_exp
    with _jwt_lock:
        if not force_refresh and _jwt and time.time() < _jwt_exp:
            return _jwt
        body = urllib.parse.urlencode({"username": ADMIN_USER, "password": ADMIN_PASS}).encode()
        status, payload = _http(
            "POST",
            f"{PANEL_URL}/api/admin/token",
            data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        if status != 200:
            raise RuntimeError(f"admin auth failed: {status} {payload[:200]!r}")
        token = json.loads(payload).get("access_token")
        if not token:
            raise RuntimeError("admin auth response had no access_token")
        _jwt = token
        # Keep a generous safety margin under the panel's 1h default
        _jwt_exp = time.time() + 50 * 60
        return _jwt


def _to_unix(iso: str) -> int:
    """Parse PasarGuard's `created_at`. Treats naive timestamps as UTC —
    .timestamp() on a naive datetime defaults to local time, which would
    skew "last seen" by the host's tz offset on non-UTC servers."""
    if not iso:
        return 0
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    except Exception:
        return 0


def _cache_get(token: str):
    with _cache_lock:
        hit = _cache.get(token)
        if hit is None:
            return None
        if time.time() - hit[0] >= CACHE_SECONDS:
            _cache.pop(token, None)
            return None
        _cache.move_to_end(token)  # LRU bump
        return hit[1]


def _cache_put(token: str, devices: list):
    with _cache_lock:
        _cache[token] = (time.time(), devices)
        _cache.move_to_end(token)
        while len(_cache) > CACHE_MAX:
            _cache.popitem(last=False)  # evict oldest


def get_devices(token: str):
    cached = _cache_get(token)
    if cached is not None:
        return cached

    tail = token[-6:] if len(token) > 12 else "***"  # never echo short tokens

    # Step 1: token -> username (public endpoint, no admin auth).
    # safe="" makes quote() escape slashes too — otherwise a token containing
    # "/" would let a caller traverse to other endpoints.
    quoted_token = urllib.parse.quote(token, safe="")
    status, payload = _http("GET", f"{PANEL_URL}/sub/{quoted_token}/info")
    if status != 200:
        print(f"[bridge] info lookup for …{tail} returned {status}", file=sys.stderr)
        return []
    try:
        info = json.loads(payload)
    except Exception as e:
        print(f"[bridge] info JSON parse failed for …{tail}: {e}", file=sys.stderr)
        return []
    username = info.get("username")
    if not username:
        print(f"[bridge] no username in /info response for …{tail}", file=sys.stderr)
        return []

    # Step 2: pull IP + UA history with admin auth.
    # (a) Different PasarGuard versions expose the endpoint at different
    #     paths. 4.0.x uses /api/user/{username}/sub_update (singular);
    #     newer builds also have /api/users/{username}/sub_update (plural).
    #     Try the candidates and cache the one that worked.
    # (b) Retry once on 401 in case the cached JWT was revoked (admin
    #     password rotated, panel restart).
    quoted_user = urllib.parse.quote(username, safe="")
    candidate_paths = _api_user_paths(quoted_user)
    status, payload = 0, b""
    for attempt in range(2):
        try:
            jwt = get_admin_jwt(force_refresh=(attempt == 1))
        except Exception as e:
            print(f"[bridge] admin auth failed: {e}", file=sys.stderr)
            return []
        chosen = None
        for path in candidate_paths:
            status, payload = _http(
                "GET",
                f"{PANEL_URL}{path}",
                headers={"Authorization": f"Bearer {jwt}"},
            )
            if status == 200:
                chosen = path
                break
            if status == 401:
                break  # JWT issue — bail to retry logic below
        if chosen:
            _remember_sub_update_path(chosen)
            break
        if status == 401 and attempt == 0:
            continue
        break
    if status != 200:
        print(f"[bridge] sub_update for {username} returned {status} on all candidates", file=sys.stderr)
        return []
    try:
        updates = json.loads(payload).get("updates", []) or []
    except Exception as e:
        print(f"[bridge] sub_update JSON parse failed for {username}: {e}", file=sys.stderr)
        return []

    # Step 3: dedupe by ip+UA, newest-first
    seen: dict = {}
    for u in updates:
        ip = u.get("ip") or None
        ua = u.get("user_agent") or ""
        ts = _to_unix(u.get("created_at") or "")
        key = f"{ip or ''}|{ua}"
        prev = seen.get(key)
        if not prev or prev["last_seen"] < ts:
            seen[key] = {"ip": ip, "user_agent": ua, "last_seen": ts}

    devices = sorted(seen.values(), key=lambda d: d["last_seen"], reverse=True)

    _maybe_warn_loopback(devices)
    _cache_put(token, devices)
    return devices


_warned_loopback = False
_warn_lock = threading.Lock()


def _maybe_warn_loopback(devices):
    """If every IP we got back is loopback, the panel is almost certainly
    behind a proxy with UVICORN_PROXY_HEADERS=False. One-shot stderr hint."""
    global _warned_loopback
    if not devices:
        return
    loopback = {"127.0.0.1", "::1"}
    ips = [d.get("ip") for d in devices if d.get("ip")]
    if not ips or not all(ip in loopback for ip in ips):
        return
    with _warn_lock:
        if _warned_loopback:
            return
        _warned_loopback = True
    print(
        "[bridge] all client IPs returned by the panel are loopback — this "
        "almost always means UVICORN_PROXY_HEADERS=False on the panel "
        "(nginx forwards from 127.0.0.1, uvicorn ignores X-Forwarded-For). "
        "Add UVICORN_PROXY_HEADERS=true to the panel's .env and restart it.",
        file=sys.stderr,
    )


class Handler(BaseHTTPRequestHandler):
    def _json(self, status: int, body):
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        # The bridge sits behind same-origin nginx by default; allow only the
        # request's own origin so other sites can't read someone's IP history
        # if they happen to obtain a sub token.
        origin = self.headers.get("Origin")
        if origin:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/healthz":
            return self._json(200, {"ok": True})
        prefix = "/api/sub/online/"
        if not path.startswith(prefix):
            return self._json(404, {"error": "not found"})
        token = path[len(prefix):].strip("/")
        if not token:
            return self._json(400, {"error": "missing token"})
        # The token comes from the URL path; reject anything that obviously
        # isn't a token (control chars, slashes, very long strings).
        if len(token) > 256 or any(c in token for c in "/\\\x00"):
            return self._json(400, {"error": "invalid token"})
        try:
            return self._json(200, get_devices(token))
        except Exception as e:
            tail = token[-6:] if len(token) > 12 else "***"
            print(f"[bridge] unhandled error for token=…{tail}: {e}", file=sys.stderr)
            return self._json(500, [])

    def log_message(self, *_):
        pass  # silence default access logs


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[bridge] listening on 127.0.0.1:{PORT} -> {PANEL_URL}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
