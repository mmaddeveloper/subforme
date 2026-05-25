# 00 — Scope Lock

## What is being audited
- **Surface**: subforme subscription page (single-file Jinja template, ~115 KB rendered HTML)
- **Repo**: `/root/subforme/index.html` (3086 lines; CSS + ~64 KB inline JS)
- **Live URL**: https://plus.notomarosww.com:2053/sub/djMsNCwxNzc5NjkzNjI50ccc25a80f (token shown is the user's own, fetched in `/tmp/live.html` for inspection)
- **NOT in scope**: `bridge/bridge.py` (server-side data plane), `install.sh` (installer), `uninstall.sh` — these are infrastructure, not user-facing design.

## Primary user
A VPN subscriber on mobile (Persian-speaking, RTL) — usually arriving from a Telegram message link, opening the page on their phone, glancing for ~30s.

## Primary task
**Configure a VPN client + understand how much data/time is left.**
Concretely the user needs to:
1. See remaining data quota + days at a glance.
2. Copy a `vless://…` URL or scan a QR code into their client (V2RayNG / Streisand / NekoBox / Hiddify).
3. Check which devices/IPs are currently online (for shared accounts).

## Constraints
- **Stack**: single Jinja template; no build step; bundle must load without external CDNs (ECharts is self-hosted from a sibling bridge service).
- **Brand**: Persian-first (`lang="fa"`, `dir="rtl"`), with EN fallback toggle. Existing theme variants: indigo (`--accent:#7c5cff`), gold, mint, rose.
- **Deployment**: served by PasarGuard/Marzban panel via `/sub/{token}`; UA-sniffed (the panel returns base64 to non-browser UAs).
- **Accessibility floor**: WCAG AA contrast; keyboard reachable.
- **Deadline**: none — iterating with the user over multiple sessions.

## Reference designs / competitors
- **Hiddify panel sub page** — utilitarian table + QR
- **Marzban legacy subscription page** — listing of config URLs
- **Apple Wallet pass / iOS Mail receipt-style summaries** — what the user explicitly liked aesthetically in earlier sessions ("apple-style")
- **shadcn/ui Chart docs** — referenced earlier as the visual target

## Input materials inspected during audit
- `/root/subforme/index.html` @ commit `c9a6f4d`
- `/tmp/live.html` — rendered output from the live URL (115559 bytes)
- Git log of recent commits relating to UI: `eafdc22`, `fe9752a`, `c9a6f4d`

## User's framing
The user invoked `/design-is` with the argument "برام ساب باز طراحي کن" (redesign sub for me). The audit must score the evidence honestly — the verdict follows the rule mechanically, not the user's framing.
