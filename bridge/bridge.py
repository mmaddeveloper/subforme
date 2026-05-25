#!/usr/bin/env python3
"""subforme-bridge — token-authenticated public JSON endpoint that exposes
PasarGuard/Marzban's per-user IP+UA history to the subscription template.

Env vars (loaded from systemd EnvironmentFile):
    PANEL_URL       e.g. http://127.0.0.1:8000 or https://panel.example.com:2053
    PG_ADMIN_USER   panel admin username (read-capable is enough)
    PG_ADMIN_PASS   panel admin password
    PORT            bind port (default 8787)
    BIND_HOST       bind address (default 127.0.0.1; use 0.0.0.0 to expose
                    publicly when running without an upstream nginx)
    TLS_CERT_FILE   if set together with TLS_KEY_FILE, the bridge listens
                    with HTTPS — point both at your panel's cert files so
                    the same domain (with a different port) Just Works
    TLS_KEY_FILE    matching private key
    MAX_DEVICES     max IPs returned per query (default 3, sorted by active
                    connection count)
    CACHE_SECONDS   per-token cache TTL (default 30)
    CACHE_MAX       max cached tokens (default 4096, LRU evicts above this)
    ALLOWED_ORIGIN  CORS Origin allow-list (default: echo the request Origin
                    only when it matches the panel's host, else no header)
"""

import json
import os
import ssl
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import OrderedDict
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
    MAX_DEVICES = int(os.environ.get("MAX_DEVICES", "3"))
    CACHE_SECONDS = int(os.environ.get("CACHE_SECONDS", "30"))
    CACHE_MAX = int(os.environ.get("CACHE_MAX", "4096"))
except ValueError as _e:
    sys.stderr.write(f"[bridge] invalid numeric env var: {_e}\n")
    sys.exit(2)
# Clamp MAX_DEVICES — a typo like 1000000 would balloon the response and
# overload the panel. 50 is well above any realistic per-user IP count.
MAX_DEVICES = max(1, min(MAX_DEVICES, 50))
BIND_HOST = os.environ.get("BIND_HOST", "127.0.0.1")
STATIC_DIR = os.environ.get("STATIC_DIR", "/opt/subforme-bridge/static")
# Whitelisted static files the bridge will serve. Keep tight — the bridge
# runs as root and the directory lives in its own data dir, but a
# permissive any-file handler would be the kind of thing that bites later.
STATIC_ALLOW = {
    "echarts.min.js": "application/javascript; charset=utf-8",
    "custom-gauge-panel.png": "image/png",
}
TLS_CERT_FILE = os.environ.get("TLS_CERT_FILE", "").strip() or None
TLS_KEY_FILE = os.environ.get("TLS_KEY_FILE", "").strip() or None
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "").strip() or None

_jwt: str | None = None
_jwt_exp: float = 0.0
_jwt_lock = threading.Lock()

_cache: "OrderedDict[str, tuple[float, list]]" = OrderedDict()
_cache_lock = threading.Lock()


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


def get_admin_jwt(force_refresh: bool = False, stale_jwt: str | None = None) -> str:
    """Single-flight admin JWT refresh. The lock prevents two threads from
    both POSTing to /api/admin/token under contention. When `force_refresh`
    is set, the caller can also pass the JWT it saw as `stale_jwt`; if some
    other thread has already replaced it inside the lock, we skip the POST
    and return the fresh one — that prevents a thundering-herd of /token
    requests when many users hit the bridge after a panel restart.
    """
    global _jwt, _jwt_exp
    with _jwt_lock:
        now = time.monotonic()
        if not force_refresh and _jwt and now < _jwt_exp:
            return _jwt
        # Force-refresh, but another thread already refreshed under us — use that.
        if force_refresh and stale_jwt and _jwt and _jwt != stale_jwt and now < _jwt_exp:
            return _jwt
        body = urllib.parse.urlencode({"username": ADMIN_USER, "password": ADMIN_PASS}).encode()
        status, payload = _http(
            "POST",
            f"{PANEL_URL}/api/admin/token",
            data=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        if status != 200:
            # Don't echo the response body — it may include the form payload
            # (and therefore the password) in some panel error formats.
            raise RuntimeError(f"admin auth failed with status {status}")
        try:
            token = json.loads(payload).get("access_token")
        except Exception:
            raise RuntimeError("admin auth response wasn't valid JSON")
        if not token:
            raise RuntimeError("admin auth response had no access_token")
        _jwt = token
        # Keep a generous safety margin under the panel's 1h default.
        # time.monotonic() so a wall-clock step doesn't keep a stale JWT alive.
        _jwt_exp = time.monotonic() + 50 * 60
        return _jwt


def _cache_get(token: str):
    with _cache_lock:
        hit = _cache.get(token)
        if hit is None:
            return None
        # Use monotonic clock for TTL math so an NTP step (forward OR backward)
        # doesn't leave stale entries cached or expire fresh ones too early.
        if time.monotonic() - hit[0] >= CACHE_SECONDS:
            _cache.pop(token, None)
            return None
        _cache.move_to_end(token)  # LRU bump
        return hit[1]


def _cache_put(token: str, devices: list):
    with _cache_lock:
        _cache[token] = (time.monotonic(), devices)
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
    # Defensive: a misrouted 200 (auth proxy login page, broken nginx) can
    # leave us with a non-dict JSON body. Treat anything else as "no username".
    if not isinstance(info, dict):
        print(f"[bridge] /info response for …{tail} wasn't a JSON object", file=sys.stderr)
        return []
    username = info.get("username")
    if not username or not isinstance(username, str):
        print(f"[bridge] no username in /info response for …{tail}", file=sys.stderr)
        return []

    # Step 2: pull *active* connection IPs from the panel's node aggregator.
    # /api/node/online_stats/{username}/ip returns the IPs xray/sing-box is
    # currently terminating for this user across all nodes — i.e. the real
    # device IPs using the VPN right now, not the IPs that downloaded the
    # subscription URL at some point in the past.
    # Response shape: { "nodes": { <node_id>: { "ips": { <ip>: <count> } } } }
    #
    # Retry once on 401 in case the cached JWT was revoked (admin password
    # rotated, panel restart).
    quoted_user = urllib.parse.quote(username, safe="")
    url = f"{PANEL_URL}/api/node/online_stats/{quoted_user}/ip"
    status, payload = 0, b""
    jwt = None
    for attempt in range(2):
        try:
            # On the second pass, pass the stale JWT so the refresher can
            # short-circuit if some other thread already grabbed a fresh one
            # — keeps a thundering herd from all POSTing /api/admin/token.
            jwt = get_admin_jwt(force_refresh=(attempt == 1), stale_jwt=(jwt if attempt == 1 else None))
        except Exception as e:
            print(f"[bridge] admin auth failed: {e}", file=sys.stderr)
            return []
        status, payload = _http("GET", url, headers={"Authorization": f"Bearer {jwt}"})
        if status == 401 and attempt == 0:
            continue
        break
    if status != 200:
        print(f"[bridge] online_stats for {username} returned {status}", file=sys.stderr)
        return []
    try:
        nodes_obj = (json.loads(payload).get("nodes") or {})
    except Exception as e:
        print(f"[bridge] online_stats JSON parse failed for {username}: {e}", file=sys.stderr)
        return []

    # Step 3: aggregate connection counts per IP across all nodes, then take
    # the top MAX_DEVICES (default 3) by connection count.
    ip_counts: dict = {}
    for node_data in nodes_obj.values():
        if not node_data:
            continue
        for ip, count in (node_data.get("ips") or {}).items():
            if not ip:
                continue
            ip_counts[ip] = ip_counts.get(ip, 0) + int(count or 0)

    now_ts = int(time.time())
    devices = [
        {
            "ip": ip,
            "user_agent": "",          # the node API doesn't expose UA
            "last_seen": now_ts,       # if we see it here, it's online now
            "connections": count,
        }
        for ip, count in sorted(ip_counts.items(), key=lambda kv: -kv[1])
    ][:MAX_DEVICES]

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


def _cors_origin(req_origin: str | None) -> str | None:
    """Return the value to put in Access-Control-Allow-Origin (or None).
    If ALLOWED_ORIGIN is set, only echo origins on that list. Otherwise
    echo whatever the browser sent (the alternative — `*` — would let any
    site read someone's IP history with just the token)."""
    if not req_origin:
        return None
    if ALLOWED_ORIGIN:
        allowed = {o.strip() for o in ALLOWED_ORIGIN.split(",") if o.strip()}
        return req_origin if req_origin in allowed else None
    return req_origin


class Handler(BaseHTTPRequestHandler):
    def _json(self, status: int, body):
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        cors = _cors_origin(self.headers.get("Origin"))
        if cors:
            self.send_header("Access-Control-Allow-Origin", cors)
            self.send_header("Vary", "Origin")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_OPTIONS(self):
        # CORS preflight — required when the template fetch is cross-origin
        cors = _cors_origin(self.headers.get("Origin"))
        self.send_response(204)
        if cors:
            self.send_header("Access-Control-Allow-Origin", cors)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Accept, Content-Type")
            self.send_header("Access-Control-Max-Age", "600")
        self.end_headers()

    def _serve_static(self, name: str):
        """Serve a whitelisted file from STATIC_DIR. Treated as immutable
        (long Cache-Control) because the URL is meant to be content-pinned
        — bump the filename / install version to invalidate."""
        ctype = STATIC_ALLOW.get(name)
        if not ctype:
            return self._json(404, {"error": "not found"})
        # Defense in depth: even though `name` was matched against an
        # alphanumeric whitelist key, normalize the final path and reject
        # anything that ends up outside STATIC_DIR.
        full = os.path.realpath(os.path.join(STATIC_DIR, name))
        if not full.startswith(os.path.realpath(STATIC_DIR) + os.sep) and full != os.path.realpath(os.path.join(STATIC_DIR, name)):
            return self._json(404, {"error": "not found"})
        try:
            with open(full, "rb") as f:
                body = f.read()
        except FileNotFoundError:
            return self._json(404, {"error": "not found"})
        except OSError as e:
            print(f"[bridge] static read {name} failed: {e}", file=sys.stderr)
            return self._json(500, {"error": "read failed"})
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "public, max-age=31536000, immutable")
        cors = _cors_origin(self.headers.get("Origin"))
        if cors:
            self.send_header("Access-Control-Allow-Origin", cors)
            self.send_header("Vary", "Origin")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/healthz":
            return self._json(200, {"ok": True})
        if path.startswith("/static/"):
            return self._serve_static(path[len("/static/"):])
        prefix = "/api/sub/online/"
        if not path.startswith(prefix):
            return self._json(404, {"error": "not found"})
        # Percent-decode any escapes the browser left in the path before
        # validation. Without this, `/api/sub/online/%2F..` slips past the
        # "no slash" check, gets re-encoded to `%252F..` by quote(safe="")
        # in step 1, and the panel sees a token nobody issued.
        token = urllib.parse.unquote(path[len(prefix):]).strip("/")
        if not token:
            return self._json(400, {"error": "missing token"})
        # Reject anything that obviously isn't a panel-issued token: very
        # long strings, slashes (path traversal), backslashes, and ANY ASCII
        # control character (NUL through 0x1F).
        if len(token) > 256 or any(c in token for c in "/\\") or any(ord(c) < 0x20 for c in token):
            return self._json(400, {"error": "invalid token"})
        try:
            return self._json(200, get_devices(token))
        except Exception as e:
            tail = token[-6:] if len(token) > 12 else "***"
            print(f"[bridge] unhandled error for token=…{tail}: {e}", file=sys.stderr)
            return self._json(500, [])

    def do_HEAD(self):
        # Browsers may HEAD a static URL before fetching, and admins use
        # `curl -I` to sanity-check the bridge. Mirror the routing of
        # do_GET but only emit headers, not the body.
        path = urllib.parse.urlparse(self.path).path
        if path == "/healthz" or path.startswith("/api/sub/online/"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path.startswith("/static/"):
            name = path[len("/static/"):]
            ctype = STATIC_ALLOW.get(name)
            if not ctype:
                self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers(); return
            try:
                size = os.path.getsize(os.path.join(STATIC_DIR, name))
            except OSError:
                self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers(); return
            self.send_response(200)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(size))
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
            self.end_headers()
            return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *_):
        pass  # silence default access logs


class _BridgeServer(ThreadingHTTPServer):
    # daemon_threads=True means in-flight request threads don't keep the
    # process alive on shutdown. Without it, Ctrl+C / SIGTERM hangs until
    # every open connection drains — systemctl restart can take 90s and
    # the foreground process ignores Ctrl+C.
    daemon_threads = True
    allow_reuse_address = True


def _install_signal_handlers(server):
    """Shut the server down on Ctrl+C *and* on SIGTERM (which is what
    systemd sends on `systemctl stop|restart`)."""
    import signal
    def _stop(signum, _frame):
        name = signal.Signals(signum).name
        print(f"[bridge] received {name}, shutting down", file=sys.stderr, flush=True)
        # shutdown() blocks until serve_forever returns, so call it from a
        # thread so we don't deadlock the signal handler.
        threading.Thread(target=server.shutdown, daemon=True).start()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            signal.signal(sig, _stop)
        except (ValueError, OSError):
            pass  # not in the main thread / unsupported on this platform


if __name__ == "__main__":
    server = _BridgeServer((BIND_HOST, PORT), Handler)
    scheme = "http"
    if TLS_CERT_FILE and TLS_KEY_FILE:
        ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ctx.load_cert_chain(certfile=TLS_CERT_FILE, keyfile=TLS_KEY_FILE)
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
        scheme = "https"
    elif TLS_CERT_FILE or TLS_KEY_FILE:
        sys.stderr.write("[bridge] TLS_CERT_FILE and TLS_KEY_FILE must both be set; falling back to plain HTTP\n")
    print(f"[bridge] listening on {scheme}://{BIND_HOST}:{PORT} -> {PANEL_URL}", flush=True)
    _install_signal_handlers(server)
    try:
        server.serve_forever()
    finally:
        server.server_close()
