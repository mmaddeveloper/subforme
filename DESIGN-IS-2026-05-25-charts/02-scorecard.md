# 02 — Scorecard (charts-only)

Anchors from Phase 2; tie-break = lower score; score-the-worst-instance applied.

---

**1. Good design is innovative — Score: 2/3**
Evidence: Custom polar gauge (sector + polygon needle + center text) and snap-tooltip line chart (mobile-touch axisPointer with draggable handle). Both refresh existing ECharts demo patterns (`custom-gauge`, `line-tooltip-touch`) with clear theme/touch improvements.
Justification: Refreshes existing patterns with a clear improvement — not a wholly novel pattern, not a wholesale demo copy.

**2. Good design makes a product useful — Score: 3/3**
Evidence: Each chart directly answers its primary question — gauge → "how much quota left?", line → "what's my usage shape?", sparkline → "is this IP active?". Tap-shows-tooltip is the right primary interaction.
Justification: Primary task completes in fewest possible steps; no decoy actions.

**3. Good design is aesthetic — Score: 1/3**
Evidence: Line chart palette is entirely hardcoded blue (`#0770FF` 2579, `rgba(58,77,233,…)` 2580–81, `#7581BD` 2582, `rgba(15,16,22,0.92)` tooltip 2602, white border 2677) — completely ignores `--accent`. Ring gauge uses one stray `rgba(76,107,167,0.35)` shadow 2443 instead of `_withAlpha(t.accent2, 0.35)`. Five distinct color systems on three charts that should be a family.
Justification: 5+ inconsistencies AND one jarring violation (line chart is theme-incoherent across light/midnight). Lowest score worse than 1 would require active visual noise, which isn't quite the case.

**4. Good design makes a product understandable — Score: 2/3**
Evidence: All labels match handlers (post-v1.6); period tabs clear; tooltip on tap is intuitive. But the axisPointer handle is a non-obvious affordance — first-time touch users may not know they can drag it to scrub. The gauge percent has no inline "of quota" label (relies on the hero card title).
Justification: 1 control (axisPointer handle) needs a tooltip / first-use hint.

**5. Good design is unobtrusive — Score: 2/3**
Evidence: Chart chrome is mostly quiet; the visible figure is the data. But the line chart's saturated `#0770FF` line + emphasis glow (`shadowBlur:10` at 2684) and the hardcoded `rgba(58,77,233,0.8)` area are louder than they should be next to the page's softer `--accent` indigo.
Justification: Chrome visible but quiet — 2/3.

**6. Good design is honest — Score: 3/3**
Evidence: Charts represent the underlying data faithfully. No fake smoothing that exaggerates a trend; tooltip shows precise values. Gauge needle position is mathematically correct vs. percentage.
Justification: Every claim, badge, and label maps 1:1 to actual data.

**7. Good design is long-lasting — Score: 1/3**
Evidence: Gradient area fill (dated 2020–2024 dashboard marker, lines 2688–2695), saturated unrelated blue palette ignoring system tokens, white-bordered emphasis circles with glow shadow (line 2677–2686 — Apple-mimicking, currently fashionable), hardcoded dark tooltip that doesn't respect light mode.
Justification: 3+ dated markers anchored to the current "AI-dashboard" aesthetic. 1/3 per anchor.

**8. Good design is thorough — Score: 2/3**
Evidence: Empty: line chart ✓, sparkline ✓, gauge has no "no data" state (shows ∞ for unlimited). Loading: gauge has CSS fallback ✓, sparkline collapses ✓, line chart has nothing — empty axes appear before data lands. Error: silent for gauge + sparkline. Focus-visible on canvas handle: not possible (ECharts is canvas). Disabled: N/A.
Justification: 1 state rough (line chart loading) is the dominant gap; gauge "empty" is ambiguous but ∞ is the unlimited case, not a true empty.

**9. Good design is environmentally friendly — Score: 1/3**
Evidence: Inline JS 14.8 KB ✓, deferred 1.03 MB ✓ (lazy). Polling 60s with `document.hidden` gate ✓. BUT: ECharts canvas animations run unconditionally — `prefers-reduced-motion` is ignored (the CSS `*{}` reset can't reach canvas). Ring gauge animates 1000ms quarticInOut even when user opts out. Line chart uses ECharts default animation. Sparkline already `animation:false` ✓.
Justification: Motion always on for canvas — fails the 3/3 anchor that requires reduced-motion respected. Falls to 1/3 per anchor "motion always on."

**10. Good design is as little design as possible — Score: 2/3**
Evidence: Gauge 5 elements (arc + needle + center plate + percent text + background track) — all earn their place. Sparkline 2 elements — minimal. Line chart **9 elements** (line + symbols + area gradient + axisPointer line + handle + label + 2 axis label series + tooltip). The symbol emphasis effect (`scale:1.6` + shadowBlur:10 at 2679–2686) and the area gradient itself are removable without breaking the task.
Justification: ≤2 removable elements (emphasis glow + area gradient could both go, and the chart would read more honestly).

---

## Total: **19 / 30**

| # | Principle | Score |
|---|---|---|
| 1 | innovative | 2 |
| 2 | useful | 3 |
| 3 | aesthetic | 1 |
| 4 | understandable | 2 |
| 5 | unobtrusive | 2 |
| 6 | honest | 3 |
| 7 | long-lasting | 1 |
| 8 | thorough | 2 |
| 9 | environmentally friendly | 1 |
| 10 | as little design as possible | 2 |
| **Σ** | | **19** |
