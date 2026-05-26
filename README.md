<div align="center">

# Plus Collection — PasarGuard Subscription Template

A modern, single-file subscription page template for [PasarGuard](https://github.com/PasarGuard/panel) panel.
Light and dark themes, connected-device tracking, multi-language support — no build step required.

[![License: MIT](https://img.shields.io/badge/License-MIT-c6ff3d.svg)](LICENSE)
[![PasarGuard](https://img.shields.io/badge/PasarGuard-compatible-7c5cff.svg)](https://github.com/PasarGuard/panel)
[![Single File](https://img.shields.io/badge/single--file-no%20build-success.svg)](#)

[Installation](#installation) · [Customization](#customization) · [فارسی](#فارسی)

</div>

---

## Features

- **Light & dark, system-aware** — a daylight Stone theme and a Midnight dark theme; follows the OS by default and remembers a manual choice in `localStorage`
- **Connected devices** — shows the client app, OS, online status, and last-seen time (parsed from the User-Agent). Optional live-IP endpoint for full device listing.
- **Smart alerts** — warns the user when their subscription is expiring or data is running low
- **Bilingual** — Persian (RTL) and English (LTR) with instant switching
- **OS auto-detection** — recommends the right apps for the visitor's platform
- **One-tap import** for Hiddify, v2rayNG, Streisand, and more
- **QR codes** for the subscription link and every config
- **Protocol badges** — VLESS, VMess, Trojan, Shadowsocks, Hysteria2, WireGuard, TUIC
- **Single HTML file** — no Node.js, no build, no dependencies to install

## Screenshots

> Fresh screenshots for the v2.0 (Pine & Stone) redesign are pending. Open any subscription link, or `preview.html` locally, and capture a light and a dark view into `screenshots/`.

## Installation

### One-line install (template + live IP tracking)

```sh
curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/install.sh | sudo bash
```

The installer downloads the template, configures the panel, and sets up a tiny
local Python service that exposes per-user IP+UA history (so the **Connected
Devices** section shows real devices, not just the last fetch). Defaults to
PasarGuard — pass `--panel marzban` or `--panel marzneshin` for the others.

Skip the IP bridge with `--no-bridge` if you only want the template (the
section then falls back to the last-known device from `sub_last_user_agent`).

After it finishes, the installer prints a small nginx snippet to add inside
your panel's existing `server { }` block — that's the only manual step.

### Manual install

If you prefer to do it by hand, the steps for each panel are below.

### PasarGuard

1. **Download the template:**
   ```sh
   sudo wget -N -P /var/lib/pasarguard/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
   ```

2. **Point PasarGuard at it:**
   ```sh
   echo 'CUSTOM_TEMPLATES_DIRECTORY="/var/lib/pasarguard/templates/"' | sudo tee -a /opt/pasarguard/.env
   echo 'SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"'        | sudo tee -a /opt/pasarguard/.env
   ```
   Or uncomment the matching lines in `/opt/pasarguard/.env` by removing the leading `#`.

3. **Restart:**
   ```sh
   pasarguard restart
   ```

### Marzban

1. **Download:**
   ```sh
   sudo wget -N -P /var/lib/marzban/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
   ```
2. **Configure `.env`:**
   ```sh
   echo 'CUSTOM_TEMPLATES_DIRECTORY="/var/lib/marzban/templates/"' | sudo tee -a /opt/marzban/.env
   echo 'SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"'    | sudo tee -a /opt/marzban/.env
   ```
3. **Restart:** `marzban restart`

### Marzneshin

1. **Download:**
   ```sh
   sudo wget -N -P /var/lib/marzneshin/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
   ```
2. **Configure `.env`:**
   ```sh
   echo 'CUSTOM_TEMPLATES_DIRECTORY="/var/lib/marzneshin/templates/"' | sudo tee -a /etc/opt/marzneshin/.env
   echo 'SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"'        | sudo tee -a /etc/opt/marzneshin/.env
   ```
3. **Restart:** `marzneshin restart`

Open any user's subscription link in a browser and the new page appears.

### Updating

**If you installed with the one-line installer**, re-run the same command — it's idempotent, reuses your saved bridge credentials, picks up any new template & bridge code, and restarts the service:

```sh
curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/install.sh | sudo bash
```

**If you installed manually (template only)**, re-run the same `wget` command, then restart your panel. The `-N` flag only re-downloads if the file on GitHub is newer than what you have, so it's safe to run any time.

**PasarGuard:**
```sh
sudo wget -N -P /var/lib/pasarguard/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
pasarguard restart
```

**Marzban:**
```sh
sudo wget -N -P /var/lib/marzban/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
marzban restart
```

**Marzneshin:**
```sh
sudo wget -N -P /var/lib/marzneshin/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
marzneshin restart
```

After updating, open any subscription link with **Ctrl+F5** (or clear your browser cache) so the browser picks up the new file instead of serving the old one from cache.

### Uninstall

To fully revert the install — stop and remove the bridge service, delete `/opt/subforme-bridge`, remove the installed `index.html`, and strip the three lines we added to the panel's `.env`:

```sh
curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/uninstall.sh | sudo bash
```

Add `--yes` to skip the confirm prompt, `--keep-template` / `--keep-env` for a partial cleanup, or `--panel marzban` / `--panel marzneshin` for the other panels. The uninstaller is idempotent — re-running it on an already-clean system is safe.

You'll still need to remove the `location /sub-online/` block from your nginx config manually (the uninstaller prints it as a reminder).

## Customization

Everything is configured at the top of the `<script>` block in `index.html`.

### Support links

```js
const SUPPORT = [
  { name: { fa: "تلگرام", en: "Telegram" }, handle: "@YourChannel", url: "https://t.me/YourChannel", icon: "TG" },
  { name: { fa: "پشتیبانی", en: "Support" }, handle: "24/7 Live",   url: "https://t.me/YourSupport", icon: "24" },
  { name: { fa: "وب‌سایت", en: "Website" },  handle: "yoursite.com", url: "https://yoursite.com",     icon: "WB" },
];
```

### Default theme

Change the `data-theme` attribute on the very first line:

```html
<html lang="fa" dir="rtl" data-theme="midnight">  <!-- midnight | gold | emerald | crimson -->
```

### Live device/IP listing (optional, advanced)

By default the page shows the **last device** that fetched the subscription (from `sub_last_user_agent`).
To list **all** connected IPs, build a custom endpoint on your panel that returns JSON:

```json
[
  { "ip": "1.2.3.4", "user_agent": "v2rayNG/1.8.5", "last_seen": 1716300000 }
]
```

then set its URL in `index.html`:

```js
const ONLINE_IPS_ENDPOINT = 'https://panel.example.com/api/sub/online/{token}';
```

See [`docs/online-ips.md`](docs/online-ips.md) for a sample endpoint.

## Template variables

| Variable | Description |
|----------|-------------|
| `user.username` | Username |
| `user.status.value` | `active` / `limited` / `expired` / `disabled` / `on_hold` |
| `user.data_limit` | Total data in bytes (0 = unlimited) |
| `user.used_traffic` | Used data in bytes |
| `user.expire` | Expiry timestamp (0 = never) |
| `user.subscription_url` | Subscription URL |
| `user.links` | Array of config links |
| `user.sub_last_user_agent` | Last device User-Agent |
| `user.sub_updated_at` | Last subscription update time |
| `user.online_at` | Last online activity |

The template degrades gracefully when a variable is missing.

## Local preview

Open [`preview.html`](preview.html) in your browser — it is the same template filled with sample data.

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you'd like to change.

## License

[MIT](LICENSE) — free to use, modify, and distribute.

## Credits

Built for the [PasarGuard](https://github.com/PasarGuard/panel) panel.

---

<div align="center" id="فارسی">

## فارسی

</div>

یک قالب صفحه اشتراک مدرن و تک‌فایل برای پنل **PasarGuard**.

### ویژگی‌ها
- **تمِ روشن و تیره** هماهنگ با سیستم (تمِ روزِ Stone و تمِ شبِ Midnight)، با ذخیره‌ی انتخابِ دستی
- **دستگاه‌های متصل** با تشخیص اپ و سیستم‌عامل از روی User-Agent
- **اعلان هوشمند** برای انقضای نزدیک یا اتمام حجم
- **دو زبانه** فارسی و انگلیسی با سوییچ لحظه‌ای
- **تک فایل HTML** بدون نیاز به build

### نصب

#### PasarGuard

۱. **دانلود قالب با یک دستور:**
   ```sh
   sudo wget -N -P /var/lib/pasarguard/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
   ```

۲. **تنظیم پنل (به `.env` اضافه کن):**
   ```sh
   echo 'CUSTOM_TEMPLATES_DIRECTORY="/var/lib/pasarguard/templates/"' | sudo tee -a /opt/pasarguard/.env
   echo 'SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"'        | sudo tee -a /opt/pasarguard/.env
   ```
   یا اگر این خط‌ها در فایل `/opt/pasarguard/.env` با `#` کامنت شده‌اند، فقط `#` اول‌شان را پاک کن.

۳. **ریستارت:**
   ```sh
   pasarguard restart
   ```

#### Marzban

۱. **دانلود:**
   ```sh
   sudo wget -N -P /var/lib/marzban/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
   ```
۲. **تنظیم `.env`:**
   ```sh
   echo 'CUSTOM_TEMPLATES_DIRECTORY="/var/lib/marzban/templates/"' | sudo tee -a /opt/marzban/.env
   echo 'SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"'    | sudo tee -a /opt/marzban/.env
   ```
۳. **ریستارت:** `marzban restart`

#### Marzneshin

۱. **دانلود:**
   ```sh
   sudo wget -N -P /var/lib/marzneshin/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
   ```
۲. **تنظیم `.env`:**
   ```sh
   echo 'CUSTOM_TEMPLATES_DIRECTORY="/var/lib/marzneshin/templates/"' | sudo tee -a /etc/opt/marzneshin/.env
   echo 'SUBSCRIPTION_PAGE_TEMPLATE="subscription/index.html"'        | sudo tee -a /etc/opt/marzneshin/.env
   ```
۳. **ریستارت:** `marzneshin restart`

### بروزرسانی

**اگه با اسکریپت یک‌خطی نصب کردی**، فقط همون دستور رو دوباره بزن — اسکریپت idempotent‌ـه و:

- کاربر و پسورد ادمین رو از نصب قبلی می‌خونه (پس دوباره نمی‌پرسه)
- آخرین نسخه‌ی قالب و سرویس پل رو می‌گیره
- سرویس `subforme-bridge` رو ری‌استارت می‌کنه تا تغییرات اعمال بشن

```sh
curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/install.sh | sudo bash
```

**اگه دستی نصب کرده بودی (فقط قالب، بدون پل)**، همون دستور `wget` که اول زدی رو دوباره اجرا کن و پنل رو ری‌استارت کن. به‌خاطر فلگ `-N`، فقط در صورتی فایل دانلود می‌شه که نسخه‌ی روی گیت‌هاب جدیدتر باشه — یعنی هر وقت بخوای می‌تونی این دستور رو اجرا کنی، بدون نگرانی.

**PasarGuard:**
```sh
sudo wget -N -P /var/lib/pasarguard/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
pasarguard restart
```

**Marzban:**
```sh
sudo wget -N -P /var/lib/marzban/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
marzban restart
```

**Marzneshin:**
```sh
sudo wget -N -P /var/lib/marzneshin/templates/subscription/ https://github.com/mmaddeveloper/subforme/releases/latest/download/index.html
marzneshin restart
```

بعد از آپدیت، یکی از صفحه‌های اشتراک رو با **Ctrl+F5** (یا با پاک کردن کش مرورگر) باز کن تا مرورگر نسخه‌ی جدید رو بگیره و نسخه‌ی قدیمی توی کش رو نشون نده.

### حذف کامل (Uninstall)

برای حذف کامل و برگردوندن سرور به حالت اول — توقف سرویس پل، حذف `/opt/subforme-bridge`، پاک کردن `index.html` نصب‌شده، و برداشتن ۳ خطی که توی `.env` پنل اضافه شده بود:

```sh
curl -fsSL https://raw.githubusercontent.com/mmaddeveloper/subforme/main/uninstall.sh | sudo bash
```

فلگ‌های اختیاری:
- `--yes` — بدون پرسیدن «تأیید می‌کنی؟»
- `--keep-template` — `index.html` دست نخوره
- `--keep-env` — `.env` پنل دست نخوره
- `--panel marzban` یا `--panel marzneshin` — برای پنل‌های دیگه

اسکریپت idempotent‌ـه — اگه دوباره روی سرور تمیز اجراش کنی، خطایی نمی‌ده.

تنها قدم دستی: بلوک `location /sub-online/` رو از کانفیگ nginx پاکش کنی (خود uninstaller متنش رو یادآوری می‌کنه).

### شخصی‌سازی
لینک‌های پشتیبانی، تم پیش‌فرض و سایر تنظیمات در ابتدای بخش `<script>` فایل `index.html` قابل تغییرند. برای جزئیات بیشتر بخش انگلیسی بالا را ببینید.

### مجوز
[MIT](LICENSE) — استفاده، تغییر و انتشار آزاد است.
