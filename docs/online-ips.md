# Online IPs endpoint

The subscription page can list **all** connected devices instead of just the
last one. To enable this, expose a small JSON endpoint on your panel and point
the template at it via the `ONLINE_IPS_ENDPOINT` constant in `index.html`.

This document describes the contract, then shows two sample implementations
(Node/Express and Python/FastAPI).

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
