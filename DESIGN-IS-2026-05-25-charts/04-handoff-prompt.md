# 04 — /make-plan handoff prompt (charts)

Copy-paste the fenced block below into the next session.

````
/make-plan Redesign the chart layer of the subforme subscription page — three ECharts surfaces inside /root/subforme/index.html: `renderRingGauge` (lines 2334–2486), `_usageOption` (lines 2577–2706), `renderDeviceSparklines` (lines 2492–2540). Current chart layer failed a Dieter Rams audit at 19/30 with critical gaps in principles #3 aesthetic, #7 long-lasting, #9 environmentally friendly (all scored 1/3). The page-level v1.6 redesign (commit 46bebcf) is OUT of scope and must not be touched.

Verdict paragraph (quoted from 03-verdict.md):
> Total 19/30 sits one point below the REFINE threshold (≥20) with three principles scoring 1/3 (#3 aesthetic, #7 long-lasting, #9 environmentally friendly) all driven by the same root cause — the line chart was authored before the v1.6 token system existed and still ships a hardcoded blue palette + dated visual language that doesn't read as a family with the ring gauge and sparklines.

Why redesign and not refine: The three failing principles converge on the same chart (`_usageOption`), and its visual vocabulary (gradient area fill, white-bordered Apple-style symbols with glow, dark-only tooltip, off-token type sizes) has to be re-decided, not re-tinted. A refine would tweak colors; a redesign re-derives the chart's visual language from the same `_chartTheme()` tokens the gauge and sparklines already use. The canvas-vs-CSS-reset motion gap is also a fix-it-once-systemically issue: ECharts canvas animations ignore the page-level `@media (prefers-reduced-motion)` block and need a JS `matchMedia` gate.

Preserve from current design (MUST stay intact):
- `renderRingGauge` polar geometry (sector + polygon needle + center plate + animated text) — index.html:2334–2486. Only the one stray `rgba(76, 107, 167, 0.35)` shadow at line 2443 needs replacing with `_withAlpha(t.accent2, 0.35)`. Everything else in this function is already theme-aware and stays.
- `renderDeviceSparklines` — index.html:2492–2540. Already minimal: smooth line + area fade, `animation: false`, fallback `.ready` class toggle. Only the animation-gate move applies (it's already off, so this is a no-op for sparklines).
- `loadECharts()` lazy loader (index.html:2264) — keep verbatim.
- `_chartTheme()` helper (around index.html:2288–2300) — keep the existing keys; this redesign ADDS keys, doesn't rewrite the function. New keys to add: `tooltipBg`, `tooltipBorder`, `tooltipInk`, `axisInk`, `axisTick`, `gridLine`.
- Tap-shows-tooltip + snap axisPointer + draggable handle interaction model. Only the VISUAL treatment of these elements changes.
- Period tabs above the line chart (HTML at index.html:1269–1271 + handler `initUsageStatsTabs` lines ~2761). Labels and refetch behavior preserved.
- All i18n keys — no renames.

Discard (these are causing the failing scores):
- `#0770FF` line color literal at index.html:2579. Caused failure on #3 aesthetic, #7 long-lasting.
- `rgba(58, 77, 233, 0.8)` + `rgba(58, 77, 233, 0.3)` area gradient at index.html:2580–2581. Caused failure on #7 long-lasting (dated dashboard fill) + #3 aesthetic.
- `#7581BD` axisPointer color at index.html:2582. Caused failure on #3 aesthetic.
- `rgba(15, 16, 22, 0.92)` tooltip background at index.html:2602 — invisible on midnight theme (1.04:1 contrast). Caused failure on #3 aesthetic + #8 thorough.
- `rgba(255, 255, 255, ...)` axis label + tooltip text literals at index.html:2607, 2615, 2617, 2646, 2660 — break on light mode. Caused failure on #3 aesthetic.
- Emphasis effect with `scale:1.6` + `shadowBlur:10 shadowColor:'rgba(7,112,255,0.6)'` + `borderColor:'#fff'` at index.html:2677–2686. Caused failure on #5 unobtrusive + #7 long-lasting + #10 as little design (it's borrowed Apple-iconography for status, not earned).
- The 9/10/11/16/20 px inline `fontSize` literals at index.html:2456, 2607, 2615, 2616, 2632, 2648, 2662. Caused failure on #3 aesthetic.
- The `padding:[8,12]` / `[4,8]` and `grid:{top:24 left:8 right:8 bottom:42}` off-scale spacing at index.html:2605, 2633, 2667. Caused failure on #3 aesthetic.
- Unconditional `animation: true / animationDuration: 1000` on the ring gauge at index.html:2474–2477 — ignored `prefers-reduced-motion`. Same for the line chart's implicit ECharts default. Caused failure on #9 environmentally friendly.

Top 5 moves from the audit (verbatim):
1. **#3 aesthetic + #7 long-lasting — Replace the line chart palette with `_chartTheme()` derivatives.** Drop `#0770FF`, `rgba(58,77,233,…)`, `#7581BD`. Use `t.accent` for the line stroke, `_withAlpha(t.accent, 0.18)` for a quiet single-color area fill (or `null` for no fill), `t.ink-3` for axis labels, `t.line` for axis ticks. Tooltip: `t.surface` background + `t.line` border + `t.ink` text — that inverts naturally per theme. Evidence: 01-evidence.md Visual → "Line chart palette".
2. **#9 environmentally friendly — Gate canvas animations on `prefers-reduced-motion`.** At chart-init time read `const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;` and pass `animation: !reduceMotion` + `animationDuration: reduceMotion ? 0 : 600` to every `setOption()`. The ring gauge's 1000ms quarticInOut becomes 0ms when the user opts out. Evidence: 01-evidence.md Friction → "`prefers-reduced-motion` honored: NO".
3. **#5 unobtrusive + #10 as little design — Remove the emphasis glow and white-bordered symbols.** Drop the `emphasis: { scale: 1.6, itemStyle: { shadowBlur: 10, ... } }` block (lines 2679–2686). Symbol size 7 → 4 (smaller, less Apple-ish). Border drops to none. Less furniture, more data. Evidence: 01-evidence.md Friction → "Visual elements per chart: line 9".
4. **#3 aesthetic — Add a `--t-xxs: 11px` token (or commit to `--t-xs: 12px`) and replace every 9/10/11 inline literal in chart code.** Same for spacing: chart `grid` and tooltip `padding` come from `--s-1..6`. After this pass, no chart option should contain a raw font size or pixel padding. Evidence: 01-evidence.md Visual → "Type literals not on token scale".
5. **#8 thorough — Add a real loading state for the line chart.** While the period tab fetch is in flight, paint a `.skeleton` row inside `#usageChartWrap` (matching the chart's height) instead of leaving the box empty. Reuse the existing `.skeleton` CSS from the v1.6 redesign (already authored at index.html:1071). Evidence: 01-evidence.md Visual → "Loading state: line chart ✗".

Redesign principles in priority order:
1. **#3 Aesthetic** — three charts must read as one family. One accent color (theme-driven), one stroke weight, one tooltip surface that inverts on light/dark. Zero chart-internal hardcoded colors.
2. **#9 Environmentally friendly** — every chart's `setOption` honors `prefers-reduced-motion` via a JS gate. No idle canvas animation when the user opts out.
3. **#7 Long-lasting** — drop the 2020-era gradient-area + glow-emphasis vocabulary. Aim for the visual restraint of an iOS Settings chart: line, light fill, axis, tooltip on tap. Nothing else.
4. **#10 As little design as possible** — line chart drops from 9 visual elements to 5 (line, light area, axis, axisPointer, tooltip on tap). The emphasis glow + symbol border + extra accent layers are removed.
5. **#8 Thorough** — every chart has empty, loading, error states. Line chart specifically gets a skeleton while data is in flight.

Deliverables for the plan:
- New `_chartTheme()` definition: add `tooltipBg`, `tooltipBorder`, `tooltipInk`, `axisInk`, `axisTick`, `gridLine` keys mapped to existing CSS variables.
- New `_usageOption()` body — full diff against the current 2577–2706 block, every color and font-size sourced from `t` or new chart tokens.
- New shared helper `_chartAnim()` returning `{ animation, animationDuration, animationDurationUpdate, animationEasing, animationEasingUpdate }` keyed off `matchMedia('(prefers-reduced-motion: reduce)').matches`. Use in all three charts.
- `--t-xxs: 11px` and any new chart-specific spacing tokens added near :root in the style block (lines 13–95) — or a documented decision to consolidate to existing `--t-xs: 12px` and `--s-2: 8px`.
- States checklist verified: every chart has empty / loading / error / focus / disabled covered (most already do; line chart gets the new skeleton).
- Migration: this is template-only, no bridge changes. Ship as v1.7. User reinstalls.
- Cutover criteria: (a) `grep -nE "#[0-9a-fA-F]{6}|rgba?\(" index.html | grep -E "2577,|2578,|...2706" returns ZERO chart-internal hex/rgba literals — every color is `t.<key>`; (b) with OS reduced-motion enabled, ring gauge does not animate; (c) light + dark mode tooltips both legible (contrast ≥ 4.5:1 via a manual check on each theme); (d) `node --check` passes on both index.html and preview.html main script blocks; (e) re-run `/design-is` charts-only audit and confirm total ≥ 24/30 with no principle below 2.

Anti-patterns to guard against (specific to REDESIGN of charts):
- **Porting old palette under new variable names** — if `t.lineChartBlue` resolves to `#0770FF`, the redesign hasn't happened. Use the SAME `t.accent` the gauge already uses.
- **Inventing chart-specific tokens unnecessarily** — only add `tooltipBg` etc. because the chart's tooltip surface is genuinely distinct from a page surface. Don't create `--chart-line-1-color` when `t.accent` works.
- **Bringing back the gradient area "subtly"** — flat fill at `_withAlpha(t.accent, 0.15)` is OK. A linear-gradient with two stops is not.
- **Adding new visual elements to compensate for removed ones** — if the emphasis glow goes, don't replace it with a "subtle halo" on hover. Touch UI doesn't need either.
- **Skipping `preview.html` mirror** — every chart edit must land in both files; verify with `diff -q /tmp/index.main.js /tmp/preview.main.js`.
- **Touching the bridge or i18n** — out of scope.
````
