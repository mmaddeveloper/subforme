# Online IPs endpoint

The subscription page can list **all** connected devices instead of just the
last one. To enable this, expose a small JSON endpoint on your panel and point
the template at it via the `ONLINE_IPS_ENDPOINT` constant in `index.html`.

> **PasarGuard / Marzban users:** the panels already record every IP that
> fetches a subscription (in the `user_subscription_updates` table), but
> they expose this list **only via the admin API** — the subscription token
> alone can't reach it. Jump to the [PasarGuard proxy section](#pasarguard--marzban-bridge)
> for a complete, ready-to-deploy bridge that turns the admin endpoint into
> the public JSON the template needs.

This document describes the contract, then shows three implementations:
the generic Node/Express and FastAPI templates, and a PasarGuard-specific
bridge that hooks into the panel's existing IP-tracking.

---

## Contract

**Request**

```
GET  {ONLINE_IPS_ENDPOINT with {token} replaced by the subscription token}
Accept: application/json
```

The token is the **last path segment** of `user.subscription_url`. For example,
if the subscription URL is `https://panel.example.com/sub/abc123`, then `{token}`
becomes `abc123`.

**Response — `200 OK`**

A JSON **array** of device objects:

```json
[
  {
    "ip": "1.2.3.4",
    "user_agent": "v2rayNG/1.8.5 (Android 13)",
    "last_seen": 1716300000
  },
  {
    "ip": "5.6.7.8",
    "user_agent": "Streisand/2.4 (iOS 17.4)",
    "last_seen": 1716300120
  }
]
```

| Field        | Type            | Notes                                                                 |
|--------------|-----------------|-----------------------------------------------------------------------|
| `ip`         | string \| null  | Optional. Shown next to the device name.                              |
| `user_agent` | string          | Parsed by the template to detect app / OS / icon.                     |
| `last_seen`  | number \| string| Unix seconds (preferred) or any string `Date()` can parse.            |

A device is rendered as **online** when `last_seen` is within the last
**5 minutes** (see `isRecentlyOnline` in `index.html`).

**Anything else** — non-array body, non-2xx status, CORS failure, network error,
or an exception — is treated as "no data" and the template silently falls back
to the single last-known device from `sub_last_user_agent`. So a broken endpoint
never breaks the page.

---

## CORS

The page is served from your panel's subscription URL and fetches the endpoint
with `fetch()`. If the endpoint lives on the same origin you don't need to
configure anything; otherwise add:

```
Access-Control-Allow-Origin: https://panel.example.com
```

(or `*` if you're comfortable with that).

---

## Sample — Node.js / Express

```js
import express from "express";
const app = express();

// In production, replace this stub with a query against your panel's
// IP/session log table.
async function lookupDevices(token) {
  // Example placeholder data:
  return [
    { ip: "1.2.3.4", user_agent: "v2rayNG/1.8.5 (Android 13)", last_seen: Math.floor(Date.now() / 1000) - 30 },
    { ip: "5.6.7.8", user_agent: "Streisand/2.4 (iOS 17.4)",   last_seen: Math.floor(Date.now() / 1000) - 600 },
  ];
}

app.get("/api/sub/online/:token", async (req, res) => {
  try {
    const devices = await lookupDevices(req.params.token);
    res.set("Cache-Control", "no-store");
    res.json(devices);
  } catch (e) {
    res.status(500).json([]);
  }
});

app.listen(8080);
```

---

## Sample — Python / FastAPI

```python
import time
from fastapi import FastAPI

app = FastAPI()

async def lookup_devices(token: str):
    # Replace with a real query against your panel's IP/session log.
    now = int(time.time())
    return [
        {"ip": "1.2.3.4", "user_agent": "v2rayNG/1.8.5 (Android 13)", "last_seen": now - 30},
        {"ip": "5.6.7.8", "user_agent": "Streisand/2.4 (iOS 17.4)",   "last_seen": now - 600},
    ]

@app.get("/api/sub/online/{token}")
async def online(token: str):
    return await lookup_devices(token)
```

---

## PasarGuard / Marzban bridge

PasarGuard (and its predecessor Marzban) already log every subscription
fetch with `ip`, `user_agent`, and `created_at` in the
`user_subscription_updates` table. The data is reachable only through the
admin-authenticated endpoint:

```
GET /api/users/{username}/sub_update
Authorization: Bearer <admin JWT>
```

The bridge below resolves the sub token to a username via the **public**
`/sub/{token}/info` endpoint, then calls the admin endpoint with credentials
held server-side. The browser never sees the admin token.

### Node.js (Express) bridge

`server.js`:

```js
import express from "express";

const PANEL_URL    = process.env.PANEL_URL;        // e.g. https://panel.example.com
const ADMIN_USER   = process.env.PG_ADMIN_USER;    // a sudo or read-capable admin
const ADMIN_PASS   = process.env.PG_ADMIN_PASS;
const LIMIT        = parseInt(process.env.LIMIT || "50", 10);
const CACHE_MS     = 30_000;                       // serve cached results for 30s

const app = express();
app.use((req, res, next) => {
  res.set("Access-Control-Allow-Origin", "*");      // tighten to your panel host in production
  res.set("Cache-Control", "no-store");
  next();
});

let adminJwt = null;
let adminJwtExp = 0;

async function getAdminToken() {
  if (adminJwt && Date.now() < adminJwtExp) return adminJwt;
  const body = new URLSearchParams({ username: ADMIN_USER, password: ADMIN_PASS });
  const res = await fetch(`${PANEL_URL}/api/admin/token`, { method: "POST", body });
  if (!res.ok) throw new Error(`admin auth failed: ${res.status}`);
  const json = await res.json();
  adminJwt = json.access_token;
  adminJwtExp = Date.now() + 50 * 60 * 1000; // refresh well before 1h expiry
  return adminJwt;
}

const cache = new Map();
app.get("/api/sub/online/:token", async (req, res) => {
  const { token } = req.params;
  const hit = cache.get(token);
  if (hit && Date.now() - hit.t < CACHE_MS) return res.json(hit.devices);

  try {
    // 1) Token -> username (no admin auth needed for this endpoint)
    const info = await fetch(`${PANEL_URL}/sub/${encodeURIComponent(token)}/info`).then(r => r.ok ? r.json() : null);
    if (!info?.username) return res.json([]);

    // 2) Pull IP + UA history with admin auth
    const jwt = await getAdminToken();
    const list = await fetch(
      `${PANEL_URL}/api/users/${encodeURIComponent(info.username)}/sub_update?limit=${LIMIT}`,
      { headers: { Authorization: `Bearer ${jwt}` } }
    ).then(r => r.ok ? r.json() : { updates: [] });

    // 3) Reshape into the JSON the template expects, dedupe by ip+UA, sort newest first
    const seen = new Map();
    for (const u of list.updates || []) {
      const key = `${u.ip || ""}|${u.user_agent || ""}`;
      const ts = Math.floor(new Date(u.created_at).getTime() / 1000);
      const prev = seen.get(key);
      if (!prev || prev.last_seen < ts) {
        seen.set(key, { ip: u.ip, user_agent: u.user_agent, last_seen: ts });
      }
    }
    const devices = [...seen.values()].sort((a, b) => b.last_seen - a.last_seen);

    cache.set(token, { t: Date.now(), devices });
    res.json(devices);
  } catch (e) {
    console.error(e);
    res.status(500).json([]);
  }
});

app.listen(process.env.PORT || 8787);
```

`package.json`:

```json
{
  "name": "subforme-ip-bridge",
  "version": "1.0.0",
  "type": "module",
  "dependencies": { "express": "^4.19.0" }
}
```

`.env`:

```
PANEL_URL=https://panel.example.com
PG_ADMIN_USER=youradmin
PG_ADMIN_PASS=yourpassword
PORT=8787
LIMIT=50
```

### Deployment (systemd, same host as the panel)

`/etc/systemd/system/subforme-bridge.service`:

```ini
[Unit]
Description=Subforme online-IPs bridge
After=network.target

[Service]
WorkingDirectory=/opt/subforme-bridge
EnvironmentFile=/opt/subforme-bridge/.env
ExecStart=/usr/bin/node server.js
Restart=on-failure
User=www-data

[Install]
WantedBy=multi-user.target
```

```sh
sudo mkdir -p /opt/subforme-bridge && cd /opt/subforme-bridge
# copy server.js, package.json, .env in
npm install --omit=dev
sudo systemctl enable --now subforme-bridge
```

### Expose via the same domain

If your panel is on `panel.example.com`, reverse-proxy the bridge under
`/sub-online/` so the template can use a same-origin URL (avoids CORS):

```nginx
location /sub-online/ {
    proxy_pass http://127.0.0.1:8787/api/sub/online/;
    proxy_set_header Host $host;
}
```

Then in `index.html`:

```js
const ONLINE_IPS_ENDPOINT = 'https://panel.example.com/sub-online/{token}';
```

### Security notes

- The bridge keeps the admin JWT in memory; it's never exposed to the
  browser. Rotate `PG_ADMIN_PASS` if the server is compromised.
- Use a **read-capable** admin if your panel supports it (PasarGuard's
  permission system). Don't use the sudo account if you can avoid it.
- Limit the upstream `/api/sub/online/:token` to your panel's domain via
  the `Access-Control-Allow-Origin` header (replace `*` above).
- A 30-second cache is included to absorb refresh spam.

---

## Wiring it up in `index.html`

```js
const ONLINE_IPS_ENDPOINT = 'https://panel.example.com/api/sub/online/{token}';
```

Leave it as an empty string (`''`) to disable the feature and show only the
last-known device.

---

<div dir="rtl" lang="fa">

## فارسی

این endpoint اختیاریه. اگر فعالش کنی، صفحه‌ی اشتراک به‌جای نمایش فقط آخرین دستگاه،
**همه‌ی دستگاه‌های متصل** کاربر رو لیست می‌کنه.

**نکات کوتاه:**

- درخواست `GET` می‌فرسته به آدرسی که توی `ONLINE_IPS_ENDPOINT` گذاشتی؛
  هرجا `{token}` باشه، با توکن اشتراک کاربر جایگزین می‌شه.
- جواب باید یه **آرایه‌ی JSON** باشه با فیلدهای `ip`, `user_agent`, `last_seen`.
- مقدار `last_seen` رو ترجیحاً به‌صورت Unix-seconds برگردون.
- اگر `last_seen` در ۵ دقیقه‌ی اخیر باشه، دستگاه «آنلاین» نمایش داده می‌شه.
- اگه endpoint کار نکنه (خطای شبکه / CORS / فرمت غلط)، صفحه ساکت برمی‌گرده به
  نمایش آخرین دستگاه — یعنی هیچ‌وقت صفحه نمی‌شکنه.

نمونه‌های Node.js و FastAPI بالا هستن — کافیه تابع `lookupDevices` رو با
یه کوئری واقعی به دیتابیس پنلت جایگزین کنی.

</div>
