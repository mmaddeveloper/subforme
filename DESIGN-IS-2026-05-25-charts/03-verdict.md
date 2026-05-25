# 03 — Verdict (charts-only)

## Verdict: **REDESIGN**

**One-sentence verdict**: Total 19/30 sits one point below the REFINE threshold (≥20) with three principles scoring 1/3 (#3 aesthetic, #7 long-lasting, #9 environmentally friendly) all driven by the same root cause — the line chart was authored before the v1.6 token system existed and still ships a hardcoded blue palette + dated visual language that doesn't read as a family with the ring gauge and sparklines.

## Why redesign and not refine

The three failing principles converge on **one chart** (`_usageOption`). On paper that looks like a refine ("just swap the colors"), but the deeper issue is the chart's **visual vocabulary**:

- Gradient area fill (2020-era dashboard aesthetic) — needs to be re-decided, not re-tinted.
- Hardcoded dark tooltip — needs to invert based on theme, not be hex-swapped.
- Emphasis glow + white-bordered symbols — borrowed from Apple Health iconography; needs an honest mobile-touch rationale.
- Off-token type sizes (9/10/11/16/20 px) and spacing (`[8,12]`, `top:24 bottom:42`) — needs a new chart-specific token plan that ties into the page tokens (`--t-xs..xxl`, `--s-1..6`).

You can't refine that into honest by tweaking colors; you have to choose a new visual language for the chart and rebuild from it. The gauge and sparklines stay (they already use `_chartTheme()` correctly).

## What's working (preserved into the redesign)

- **Ring gauge** (`renderRingGauge`, lines 2334–2486) — already theme-aware via `_chartTheme()`. Custom polar series with sector + polygon needle + center text. Keep verbatim; only fix the one stray `rgba(76,107,167,0.35)` shadow.
- **Sparklines** (`renderDeviceSparklines`, lines 2492–2540) — minimal, theme-aware (`t.accent2`), already has `animation:false`, fallback collapse pattern works. Keep verbatim.
- **`loadECharts()` lazy loader** — 1.03 MB stays deferred. Keep.
- **`_chartTheme()` helper** — already reads CSS variables; needs ~4 new color keys added (see moves).
- **Tap-shows-tooltip + snap axisPointer + handle pattern** — the interaction model is good; only the visual treatment of the handle needs work.
- **Period tabs** (3 buttons above line chart) — clear labels, refetch on click. Keep.

## What's failing (must be redone, not patched)

- **Line chart palette** (lines 2579–2582, 2602–2607, 2615–2617, 2646, 2655, 2660, 2677, 2682, 2684) — all the hardcoded blue/white/dark literals.
- **Tooltip styling** (line 2602–2607) — dark-only background that becomes invisible on midnight theme.
- **Emphasis effect on data points** (lines 2679–2686) — `scale:1.6` + shadow glow is borrowed style, not function.
- **Area gradient fill** (lines 2688–2695) — a dated 2020s "fancy chart" marker. Decide: keep as a flat fill at low opacity, or remove entirely.
- **Out-of-scale font sizes** (9/10/11/16/20 inline) — adopt a chart-specific micro-scale OR consolidate to existing tokens.
- **Off-scale spacing** (sparkline `grid:{0,0,2,2}`, line chart `grid:{top:24 left:8 right:8 bottom:42}`) — re-derive from `--s-1..6`.
- **Missing `prefers-reduced-motion` respect in canvas** — ECharts animation flag must be JS-gated since CSS reset doesn't reach canvas.

## Top 5 highest-leverage moves (handed off to /make-plan)

1. **#3 aesthetic + #7 long-lasting — Replace the line chart palette with `_chartTheme()` derivatives.** Drop `#0770FF`, `rgba(58,77,233,…)`, `#7581BD`. Use `t.accent` for the line stroke, `_withAlpha(t.accent, 0.18)` for a quiet single-color area fill (or `null` for no fill), `t.ink-3` for axis labels, `t.line` for axis ticks. Tooltip: `t.surface` background + `t.line` border + `t.ink` text — that inverts naturally per theme. Evidence: `01-evidence.md` Visual → "Line chart palette".

2. **#9 environmentally friendly — Gate canvas animations on `prefers-reduced-motion`.** At chart-init time read `const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;` and pass `animation: !reduceMotion` + `animationDuration: reduceMotion ? 0 : 600` to every `setOption()`. The ring gauge's 1000ms quarticInOut becomes 0ms when the user opts out. Evidence: `01-evidence.md` Friction → "`prefers-reduced-motion` honored: NO".

3. **#5 unobtrusive + #10 as little design — Remove the emphasis glow and white-bordered symbols.** Drop the `emphasis: { scale: 1.6, itemStyle: { shadowBlur: 10, ... } }` block (lines 2679–2686). Symbol size 7 → 4 (smaller, less Apple-ish). Border drops to none. Less furniture, more data. Evidence: `01-evidence.md` Friction → "Visual elements per chart: line 9".

4. **#3 aesthetic — Add a `--t-xxs: 11px` token (or commit to `--t-xs: 12px`) and replace every 9/10/11 inline literal in chart code.** Same for spacing: chart `grid` and tooltip `padding` come from `--s-1..6`. After this pass, no chart option should contain a raw font size or pixel padding. Evidence: `01-evidence.md` Visual → "Type literals not on token scale".

5. **#8 thorough — Add a real loading state for the line chart.** While the period tab fetch is in flight, paint a `.skeleton` row inside `#usageChartWrap` (matching the chart's height) instead of leaving the box empty. Reuse the existing `.skeleton` CSS from the v1.6 redesign (already authored at index.html:1071). Evidence: `01-evidence.md` Visual → "Loading state: line chart ✗".

## What NOT to touch

- The bridge contract.
- `renderRingGauge` polar geometry — only the one stray shadow color and the animation gate.
- `renderDeviceSparklines` — already minimal; only the animation gate.
- The tap-shows-tooltip behavior — that's the right interaction.
- The axisPointer handle's existence (only its visual treatment).
- The i18n keys.

## Honest cross-check

- User asked for chart redesign. Evidence agrees: 19/30 with three principles at 1/3 = REDESIGN by the Phase 3 rule.
- Rejected the temptation to call this REFINE just because the failures concentrate on one chart. The line chart's visual vocabulary has to be re-decided, not re-tinted, and the canvas-vs-CSS-reset motion gap is a fix-it-once-systemically issue, not a one-line patch.
- Honest scope-narrow: the gauge and sparklines stay almost untouched. This is a 200-line edit, not a 500-line rebuild.
