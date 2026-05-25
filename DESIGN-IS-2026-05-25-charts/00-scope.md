# 00 — Scope Lock (charts only)

This is a **focused chart audit**, not a whole-page audit. The v1.6 page-level redesign already shipped (`DESIGN-IS-2026-05-25/`). User now wants the chart layer specifically reviewed.

## What is being audited

Three chart surfaces inside `/root/subforme/index.html`:

| Surface | Function | Lines | What it does |
|---|---|---|---|
| **Ring gauge** | `renderRingGauge()` | 2334–2486 | Quota gauge at top-right of hero card. Custom polar series: sector fill + polygon pointer + center text + accent background ring. |
| **Usage line chart** | `_usageOption()` | 2577–2706 | Time-series of data usage per bucket. axisPointer with snap handle + tap-shows-tooltip. |
| **Per-IP sparklines** | `renderDeviceSparklines()` | 2492–2540 | Tiny line chart per device row showing recent connection counts. |

## Common infrastructure

- `loadECharts()` lazy-loads the self-hosted `echarts.min.js` (~1 MB) from the bridge.
- `_chartTheme()` reads CSS custom properties so charts inherit the active theme.
- `_gradient()` / `_withAlpha()` are color helpers for ECharts canvas (since canvas can't render oklch/color-mix directly).

## Live URL for visual inspection
`https://plus.notomarosww.com:2053/sub/djMsNCwxNzc5NjkzNjI50ccc25a80f`

## Primary user
VPN consumer, mobile, Persian-first. Opens the page after using their client for a day or a week and wants to know:
1. **How much quota is left?** (ring gauge)
2. **Where did my usage go this week?** (line chart)
3. **Which IPs are connected right now and how active?** (devices + sparklines)

## Primary chart-level tasks

The three charts collectively must answer those questions **at a glance**. Specifically:

- **Ring gauge**: A 1-second glance tells the user "I've used ~38% — fine" or "I've used 92% — renew now."
- **Line chart**: A 5-second glance tells the user the shape of their usage (steady? one spike? a leak?). On tap, a precise value for a chosen point.
- **Sparklines**: Per-row signal — is *this* device active or quiet right now?

## Constraints

- **ECharts only** — the library is self-hosted via the bridge; don't propose D3 / Chart.js / nivo / Visx.
- **Theme-respecting** — every color used in chart canvas must come from `_chartTheme()` so light/midnight both work. **No hardcoded #0770FF or rgba(58,77,233,…) in chart options** (current code has these — flagged below).
- **PasarGuard data only** — `total_traffic` per bucket (no upload/download split). Don't propose 2-series stacked area.
- **Mobile-first** — 390×844 viewport target; touch-only interaction.
- **No regression on a11y** — `prefers-reduced-motion` already honored at the CSS reset level; chart animations should drop their durations the same way.

## Reference designs

- Apple Health "Activity" rings + step chart — the user has previously expressed liking apple-style.
- iOS Battery usage chart (Settings → Battery) — the canonical small-multiples weekly chart.
- Stripe Dashboard charts — utility-first, no decoration.

## What's explicitly NOT in scope

- The bridge `/api/sub/online/{token}` contract.
- Token validation, JWT refresh, install.sh, uninstall.sh.
- Page-level layout (hero card, devices section, configs, more) — that's v1.6 territory.
- Translations (i18n keyset is frozen).
- Adding a new "upload vs download" series (the data doesn't exist on the backend).

## User framing

The user invoked `/design-is` with "ميخوام نمودارا رو دوباره ديزاين کني" (I want you to redesign the charts again). Honest framing translation: they noticed the v1.6 redesign cleaned up the page chrome, but the charts themselves still carry hardcoded-color stragglers and the visual language is inconsistent with the rest of the cleaned-up page.

## Input materials inspected

- `/root/subforme/index.html` @ commit `46bebcf` (post-v1.6 redesign + modal cleanup).
- The live page response at `/tmp/live.html` (rendered Jinja output).
- ECharts demos: `line-tooltip-touch`, `custom-gauge` (referenced in earlier sessions).
