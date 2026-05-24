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
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PANEL_URL = os.environ["PANEL_URL"].rstrip("/")
ADMIN_USER = os.environ["PG_ADMIN_USER"]
ADMIN_PASS = os.environ["PG_ADMIN_PASS"]
PORT = int(os.environ.get("PORT", "8787"))
LIMIT = int(os.environ.get("LIMIT", "50"))
CACHE_SECONDS = int(os.environ.get("CACHE_SECONDS", "30"))

_jwt = None
_jwt_exp = 0.0
_cache: dict = {}


def _http(method, url, data=None, headers=None, timeout=10):
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def get_admin_jwt():
    global _jwt, _jwt_exp
    if _jwt and time.time() < _jwt_exp:
        return _jwt
    body = urllib.parse.urlencode({"username": ADMIN_USER, "password": ADMIN_PASS}).encode()
    status, payload = _http(
        "POST",
        f"{PANEL_URL}/api/admin/token",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    if status != 200:
        raise RuntimeError(f"admin auth failed: {status}")
    _jwt = json.loads(payload)["access_token"]
    _jwt_exp = time.time() + 50 * 60
    return _jwt


def _to_unix(iso: str) -> int:
    """Parse PasarGuard's `created_at`. Treats naive timestamps as UTC —
    .timestamp() on a naive datetime defaults to local time, which would
    skew "last seen" by the host's tz offset on non-UTC servers."""
    if not iso:
        return 0
    try:
        from datetime import datetime, timezone
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    except Exception:
        return 0


def get_devices(token: str):
    now = time.time()
    hit = _cache.get(token)
    if hit and now - hit[0] < CACHE_SECONDS:
        return hit[1]

    tail = token[-6:] if len(token) >= 6 else token  # for logs, never the full token

    # Step 1: token -> username (no admin auth needed)
    try:
        _, payload = _http("GET", f"{PANEL_URL}/sub/{urllib.parse.quote(token)}/info")
        info = json.loads(payload)
    except Exception as e:
        print(f"[bridge] info lookup failed for …{tail}: {e}", file=sys.stderr)
        return []
    username = info.get("username")
    if not username:
        print(f"[bridge] no username in /info response for …{tail}", file=sys.stderr)
        return []

    # Step 2: pull IP + UA history with admin auth
    try:
        jwt = get_admin_jwt()
        status, payload = _http(
            "GET",
            f"{PANEL_URL}/api/users/{urllib.parse.quote(username)}/sub_update?limit={LIMIT}",
            headers={"Authorization": f"Bearer {jwt}"},
        )
        if status != 200:
            print(f"[bridge] sub_update for {username} returned {status}", file=sys.stderr)
            return []
        updates = json.loads(payload).get("updates", []) or []
    except Exception as e:
        print(f"[bridge] sub_update lookup failed for {username}: {e}", file=sys.stderr)
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

    # If every IP we got back is loopback, the panel is almost certainly
    # behind a proxy with UVICORN_PROXY_HEADERS=False. Log a one-shot hint
    # so the admin can fix it instead of wondering why everyone is the same.
    _maybe_warn_loopback(devices)

    _cache[token] = (now, devices)
    return devices


_warned_loopback = False
def _maybe_warn_loopback(devices):
    global _warned_loopback
    if _warned_loopback or not devices:
        return
    loopback = {"127.0.0.1", "::1"}
    ips = [d.get("ip") for d in devices if d.get("ip")]
    if ips and all(ip in loopback for ip in ips):
        print(
            "[bridge] all client IPs returned by the panel are loopback — "
            "this almost always means UVICORN_PROXY_HEADERS=False on the "
            "panel (nginx forwards from 127.0.0.1, uvicorn ignores "
            "X-Forwarded-For). Add UVICORN_PROXY_HEADERS=true to the "
            "panel's .env and restart it.",
            file=sys.stderr,
        )
        _warned_loopback = True


class Handler(BaseHTTPRequestHandler):
    def _json(self, status, body):
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
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
        try:
            return self._json(200, get_devices(token))
        except Exception as e:
            print(f"[bridge] error for token={token[:6]}…: {e}", file=sys.stderr)
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
