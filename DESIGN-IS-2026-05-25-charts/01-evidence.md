# 01 — Evidence (charts-only)

Three subagents: Structural, Visual, Friction. Scope limited to `renderRingGauge`, `_usageOption`, `renderDeviceSparklines` + shared infra (`loadECharts`, `_chartTheme`, `_gradient`, `_withAlpha`).

## Structural

| Metric | Value | Cite |
|---|---|---|
| Chart-layer JS as % of inline script | **31.8%** (511 lines of 1602) | 2263–2773 |
| Interactive surfaces | axisPointer handle ✓; tap-to-tooltip ✓; 3 period tabs; inside dataZoom; sparkline NOT tappable; ring gauge NOT tappable | 2636, 2600, 1269–1271, 2668 |
| Max nesting in option object | 6 levels (`_usageOption`); 5 (`renderRingGauge.renderItem`) | 2577–2706, 2334–2486 |
| Repeated literals across charts | `tooltip:{show:false}` ×2, `fontFamily:'var(--mono)'` ×4 (line chart only), `color:'rgba(255,255,255,0.55)'` ×4 | 2480/2534; 2607,2631,2647,2661; 2615,2617,2646,2660 |
| Dead code | None (post-v1.6 cleanup) | — |
| Module-level chart state | `_ringGauge`, `_usageChart`, `IP_HISTORY` (≤30/IP), `_echartsPromise` | 2303, 2302, 2308, 2263 |
| Hardcoded HEX | `#0770FF` (line color), `#7581BD` (axisPointer) | 2579, 2582 |
| Hardcoded rgba | 9 distinct rgba literals in `_usageOption` (tooltip, axis labels, area gradient, symbol shadow); 1 in ring gauge shadow | 2580–2684, 2443 |
| Off-token font sizes | 9, 10, 11, 16, 20 px inline literals — no `--t-xxs` exists for 9/10/11 | 2456, 2615, 2616, 2632, 2648, 2662 |
| Off-token spacing | `padding:[8,12]`, `[4,8]`; `grid:{top:24,left:8,right:8,bottom:42}`; sparkline `grid:{0,0,2,2}` | 2605, 2633, 2667, 2514 |
| Animation gated on reduced-motion | **NO** — canvas not reached by CSS reset | — |

## Visual

| Metric | Value | Cite |
|---|---|---|
| Ring gauge palette | `t.accent`, `t.accent2`, `_withAlpha(t.ink, 0.08)`, `t.surface` ✓ theme-aware | 2378, 2417, 2434, 2441 |
| Ring gauge hardcoded shadow | `rgba(76, 107, 167, 0.35)` — unrelated blue | 2443 |
| Line chart palette | `#0770FF`, `rgba(58,77,233,…)` area, `#7581BD` pointer, `rgba(15,16,22,0.92)` tooltip, `rgba(255,255,255,...)` axis labels, `#fff` borders — **all hardcoded** | 2579–2684 |
| Sparkline palette | `t.accent2` + alpha — ✓ theme-aware | 2512, 2528 |
| **Tooltip contrast in dark mode** | `rgba(15,16,22,0.92)` tooltip on `--bg #0a0a0f` → **invisible** (1.04:1 vs midnight ink) | 2602 |
| Tooltip contrast in light mode | OK (19.5:1 — dark tooltip on light bg) | 2602 |
| Type literals not on token scale | 9, 10, 11, 20 (no `--t-xxs`) | 2456, 2607, 2632, 2648, 2662 |
| Spacing literals not on 4-base | 2 (sparkline grid), 42 (chart bottom), 24 (chart top) | 2514, 2667 |
| Empty state | line ✓ (`_usageEmpty`); gauge shows `∞` for unlimited (not "no data"); sparkline ✓ (collapse) | 2702, 2372, 2502 |
| Loading state | gauge ✓ (CSS `.ring` fallback); line chart ✗ (no skeleton); sparkline ✓ (collapse) | 2486, none, 2509 |
| Error state | gauge silent return; line `_usageEmpty`; sparkline silent skip | 2339, 2716, 2502 |
| Focus-visible on axisPointer handle | ✗ (ECharts canvas not keyboard-focusable) | 2636–2640 |
| RTL | no `direction:'rtl'` passed to any chart option | none |
| Visual coherence | Ring + sparkline = theme-coherent; line chart = theme-incoherent (hardcoded blue family) | — |

## Friction

| Metric | Value | Cite |
|---|---|---|
| Inline JS bytes (chart layer) | ~14.8 KB | 2263–2773 |
| Deferred bundle | 1.03 MB ECharts | — |
| First paint blocked by ECharts? | No — page paints; charts lazy-load | 2715 |
| Idle animations | Ring gauge 1000ms quarticInOut, line chart ECharts-default, sparkline `animation:false` | 2474–2477, none, 2514 |
| `prefers-reduced-motion` honored | **NO** — canvas ignores CSS reset; no JS `matchMedia` check anywhere in chart code | — |
| Polling cost (60s) | ~600 B response + sparkline setOption (reuses instance, no dispose) | 2028–2040, 2510, 2535 |
| Visual elements per chart | gauge: 5; line: 9 (high); sparkline: 2 | — |
| Touch target — axisPointer handle | **30 px** (WCAG mobile guidance ≥ 44 px) | 2638 |
| Memory: `_ringGauge` disposed on theme change | **NO** — only `data-theme` attr toggles; potential stale instance | 2822–2831 |
| Memory: `_usageChart` disposed | ✓ in `_usageEmpty` | 2704 |
| Memory: sparkline instances | ✓ disposed when history < 2 | 2502 |
| `IP_HISTORY` bounded | ✓ 30/IP, GC'd on each poll | 2309, 2319, 2324 |

## Known gaps
- No real-browser screenshot — Visual inferred from source.
- Did not measure actual TTI under real network — Friction TTI estimated.
- Did not test the live tooltip on a midnight-mode device (the contrast finding is computed).
