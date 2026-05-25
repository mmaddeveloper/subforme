# 01 — Evidence (consolidated)

Subagents: Structural, Visual, Copy & Honesty, Weight & Friction. Accessibility subagent merged into Visual.

## Structural

| Metric | Value | Cite |
|---|---|---|
| Static interactive elements | 14 (13 btn + 1 link) | 1213, 1219, 1277, 1283, 1316, 1339, 1336–1338, 1392–1394, 1415, 1272 |
| Dynamic interactive elements | ~50+ (device rows × 2, configs × 2, apps × 4–5 per OS, 4 themes, 24 avatars, 5 OS rail, 3 support) | 1335, 1913, 1926, 1941, 1959, 1987 |
| Max DOM nesting (primary card) | **6** levels: body → shell → hero-card → usage-grid → ring-wrap → ring → ring-content → ring-pct → span | 1250 |
| Repeated affordances (copy/QR) | **4 places**: header copy (1277), header QR (1283), modal copy/base64 (1393–1394), per-config (1335), per-device (1335) | — |
| Dead code | `fmtPrice()` defined ~1704, never called | 1704 |
| Unused CSS classes | 0 (all classes referenced) | — |
| Sections + chrome | 9 sections + 2 modals + aurora + toasts | 1207, 1223, 1259, 1266, 1292, 1330, 1358, 1368, 1377, 1388, 1411 |
| Module-scope state | **18** top-level `let`/`const` declarations | 1441–1700 |
| i18n keys fa / en | 63 / 63 (perfectly balanced) | 1483–1582 |

## Visual

| Metric | Value | Cite |
|---|---|---|
| Spacing scale | 2,3,4,5,6,8,10,12,14,16,20,**22**,24,32,**40** (22 and 40 are outliers) | 171, 190, 136 |
| Type scale | 8/9/10/10.5/11/12/13/14/17/20/22/24/28/32 + clamp(28,6.5vw,40) + clamp(46,11vw,72) | 254, 303, others |
| Distinct colors | ~55 across 4 themes (19 neutrals + 12 brand + 6 semantic + 12 gradient + 4 markup) | 18–110 |
| **Lowest text contrast** | **2.2:1** for `--ink-3 #6a6a78` on `--surface rgba(255,255,255,0.04)` on `#0a0a0f` — **FAILS WCAG AA** (req 4.5:1) | 20, 24 |
| State coverage | empty✓ loading-partial error✗(CSS) success✓ focus-visible✓ disabled✗ hover✓ active✓ | 677, 558, 891, 1179, 277 |
| CSS tokens declared / referenced | 22 declared; ~8 appear unused | 18–110 |
| Idle infinite animations | **8**: drift1/2/3 (3 aurora blobs, 22/26/30s), shimmer, blink, ping ×2, usage shimmer | 123–125, 184, 264, 278, 674, 961 |
| Inline SVG icons | 12 unique | — |
| Idle ornaments | **10+**: 3 aurora blobs w/ blur(80px), noise overlay, hero shimmer border, button shine sweep, conic-gradient ring, modal backdrop-filter, theme-swatch glow, accent side bars | 120–134, 179, 469, 325, 934, 577, 1047 |
| RTL handling | Partial: `dir="rtl"` + 6 `[dir="rtl"]` selectors + 5 `margin-inline-*` + some physical sides for edit-pencil | 2, 230–231, 263, 394, 702, 714, 925 |

## Copy & Honesty

| Finding | Status | Cite |
|---|---|---|
| Marketing superlatives | 0 found | — |
| Dark patterns | 0 found (no fake scarcity, no forced continuity, no confirmshaming) | — |
| Jargon | 0 — all labels in plain language | — |
| Label→behavior mismatches | 0 — every "Copy"/"QR"/"Refresh"/"Period" label matches its handler | 2936, 2957, 2960, 2941, 2846, 2893, 2912, 2981, 2858, 3008 |
| i18n parity | ✓ all fa keys mirrored in en (Copy subagent counted 72/72 incl. tier+app strings) | 1485–1583 |
| Honesty about limitations | `devicesNote` explicitly says page only shows last fetcher's IP | 1532 |
| Tone consistency | Consistent (one outlier: `toast('ERROR')` hardcoded English, not i18n'd) | **2965** |

## Weight & Friction

| Metric | Value | Cite |
|---|---|---|
| Inline JS bytes | 65,933 | 1441–3083 |
| Blocking external | qrcode-generator (~20KB) + Google Fonts (~30KB gz) | 10, 11 |
| Total blocking | ~96 KB | — |
| Deferred bytes | ECharts 1.03 MB (loaded on chart-render demand) | 2354 |
| Initial network requests | **5** blocking (HTML + 2 preconnects + fonts + qrcode-generator); 0 async on first paint | 8–11 |
| TTI estimate | 1.2–2.5s (font CSS is critical path) | — |
| Idle infinite animations | **8** (3 aurora 22/26/30s, shimmer 4s, blink 1s, ping ×2 1.6s, usage-shimmer 3s) | 123–125, 184, 264, 278, 674, 961 |
| Attention requesters on idle | 5–6 (ring, status pip, 4 section accent headers) | 1240, 1230, 1280, 1295, 1355, 1362 |
| `prefers-reduced-motion` | **NOT respected** anywhere | — |
| `prefers-color-scheme` | **NOT respected** — hardcoded `data-theme="midnight"` on `<html>` | 2 |
| Auto-poll | 60s; pauses on `document.hidden`✓; no error backoff | 2118–2129 |

## Known gaps / not inspected
- No live screenshot (no agent-browser); visual inferences come from CSS source.
- Did not run Lighthouse or a real-device perf trace — TTI is an estimate.
- Did not test the actual QR rendering visually.
- Did not audit `preview.html` separately — assumed JS-identical (verified earlier).
