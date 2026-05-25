# 04 — /make-plan handoff prompt

Copy-paste the fenced block below into the next session.

````
/make-plan Redesign the subforme subscription page (single Jinja template at /root/subforme/index.html). Current design failed audit at 17/30 with critical gaps in principles #5 unobtrusive, #7 long-lasting, #8 thorough, #9 environmentally friendly (all scored 1/3).

Verdict paragraph (quoted from 03-verdict.md):
> Total 17/30 falls below the REFINE threshold (≥20), and four principles — #5 unobtrusive, #7 long-lasting, #8 thorough, #9 environmentally friendly — score 1 on dimensions that are load-bearing for a single-purpose page used in a 30-second mobile glance, so the visual layer needs to be redone from the principle of restraint rather than patched in place.

Why redesign and not refine: The fixable signals (spacing outliers, missing error/disabled CSS, ERROR i18n gap) are individually small, but the structural pattern of the page is "celebratory dashboard for a 30-second utility task." You can't refine 8 idle animations and 10+ ornaments into "unobtrusive" — restraint requires removal, not iteration. Honesty (#6=3) and Understandability (#4=3) are intact and become the preserve list, which is why NEW is not warranted.

Preserve from current design (do not lose these):
- Information architecture order: identity → quota → copy → devices → usage → apps → support — proven by the 3/3 score on #4 understandable.
- Honesty pattern: `devicesNote` at index.html:1532 ("this page shows only the last fetcher's IP") — exemplary, keep verbatim and apply the same disclosure pattern to any new explainer copy.
- The i18n keyset: 63 fa / 63 en keys in I18N at index.html:1483–1582. Copy text inside keys may be rewritten; key names must stay so Jinja/JS references don't break.
- Label↔handler correctness: every interactive label maps 1:1 to its handler (Copy → clipboard.writeText, period tabs → refetch, theme/avatar/lang persist) — preserve this discipline in every new control.
- All bridge.py contracts: /api/sub/online/{token} and /static/<file> are out of scope. The redesign is template-only.
- The token validation + path-traversal defense in bridge.py:_resolve_static (out of scope, but listed so the planner doesn't propose changes that depend on bridge edits).
- Auto-poll cadence: 60s with `document.hidden` gate (index.html:2118–2129) — correctly tuned, do not change.
- Brand color tokens (--accent #7c5cff indigo, plus gold / mint / rose alternates at lines 28, 50, 72, 94). The accent values are good; their *deployment* (aurora blobs, gradient text, shine sweeps) is what needs to go.

Discard (these are causing the failing scores):
- The three `.aurora-*` blur(80px) radial-gradient blobs at index.html:120–125 with their drift1/drift2/drift3 22/26/30s loops. Caused failure on #5 unobtrusive, #7 long-lasting, #9 environmentally friendly.
- The hero shimmer-border animation at index.html:179–186 (`animation: shimmer 4s`). Caused failure on #5 unobtrusive, #7 long-lasting.
- The button shine sweep `::after` at index.html:469–475. Caused failure on #7 long-lasting.
- The blink cursor on the hero name at index.html:264. Caused failure on #5 unobtrusive.
- The conic-gradient ring background at index.html:325 (replaced by the ECharts gauge already, but the residual CSS conic ring should be flat). Caused failure on #7 long-lasting.
- The noise overlay at index.html:130–134. Caused failure on #5 unobtrusive.
- Hardcoded `data-theme="midnight"` at index.html:2 — forces dark mode regardless of OS preference. Caused failure on #9 environmentally friendly.
- The 4-way duplicated copy/QR affordance (header @1277/1283, modal @1393–1394, per-config @1335, per-device @1335). Caused failure on #10 as little design.
- Avatar picker (24 emojis at index.html:1941) and the metallic tier pill (Bronze/Silver/Gold/Platinum at index.html:1508/1557). Caused failure on #10 as little design — they don't serve the primary task.

Top 5 moves from the audit (verbatim):
1. **#5 unobtrusive + #9 environmentally friendly — Strip the aurora/shimmer/glow layer.** Remove the 3 `.aurora-*` blur blobs (index.html:120–125), hero shimmer border (179–186), button shine sweep (469–475), blink cursor (264). Replace conic-gradient ring + noise overlay with a flat panel. Gate any remaining motion on `@media (prefers-reduced-motion: no-preference)`. Evidence: 01-evidence.md → Visual → "Idle ornaments 10+".
2. **#9 environmentally friendly — Honor `prefers-color-scheme`.** Add a light theme as default for `prefers-color-scheme: light`, keep midnight as the user's optional persisted override. Drop the hardcoded `data-theme="midnight"` from `<html>` (index.html:2). Evidence: 01-evidence.md → Weight & Friction → "hardcoded dark only".
3. **#10 as little design as possible — Cut copy/QR redundancy to one canonical surface.** Pick a single per-config-row pattern (long-press action sheet OR a visible "Copy" + ⋯ menu for "QR / Base64"). Remove the duplicated modal "Copy / Base64" pair and the header copy button when the canonical surface is reachable. Evidence: 01-evidence.md → Structural → "Repeated affordances: 4 places".
4. **#10 + #2 useful — Demote secondary surface area.** Move "Get the App" + "Support" below a collapsed section or a separate sheet. Collapse the tier pill / avatar picker / hero name flourish behind a "Profile" toggle. The page's job is "copy a config + see what's left." Evidence: 01-evidence.md → Structural → "9 sections + 2 modals".
5. **#8 thorough — Add the missing states.** Author `.error` CSS for failed network calls (toast is a stopgap, not the state), `[aria-disabled]` for buttons that briefly disable during async, and a real skeleton for the device list + usage chart while data loads. Localize the hardcoded `'ERROR'` toast at index.html:2965. Evidence: 01-evidence.md → Visual → "State coverage" + Copy & Honesty → "one outlier".

Redesign principles in priority order:
1. **#10 As little design as possible** — every element on the new page must earn its place by serving the 30-second user. If removing it doesn't break "copy a config + see what's left", remove it.
2. **#5 Unobtrusive** — chrome recedes; content is the figure. No idle animation, no decorative blurs, no gradient text on functional labels. The ring gauge can stay (it's content, not chrome) but its frame must be quiet.
3. **#9 Environmentally friendly** — honor `prefers-reduced-motion` and `prefers-color-scheme`. Light mode by default for daylight users. No infinite animations on idle. Stay under 100 KB blocking JS.
4. **#8 Thorough** — empty, loading, error, success, focus-visible, disabled all present and intentional (not just "default browser").
5. **#7 Long-lasting** — avoid 2024-coded markers (aurora, glassmorphism, gradient text, shine sweeps). The new design should still read as current in 2029.

Deliverables for the plan:
- New information architecture (preserve the section order, but propose which sections collapse / move below the fold). One screen map for mobile + one for desktop.
- New primary flow wireframe (low-fi, labeled) compared side-by-side to the current 9-section layout. Mark which sections are above-the-fold on a 390×844 viewport.
- Token decisions: type scale (cap at 6 sizes), spacing scale (cap at 6 steps), color count (cap at 12 functional + 1 accent per theme variant), max nesting depth (cap at 5).
- States checklist for every interactive control: empty / loading / error / success / focus / disabled — each with a target screenshot or CSS spec.
- Migration path: the redesign ships behind a `?v=2` query flag for one week; old design served at root; cut over once user confirms parity. Old CSS deleted from the same commit that flips the default.
- Cutover criteria: (a) all I18N keys still resolve, (b) every label still maps to its handler (re-run the Copy & Honesty audit), (c) Lighthouse perf ≥ 90 on mobile, (d) WCAG AA contrast on all primary text (`--ink-3` on `--surface` currently fails at 2.2:1 — fix in the redesign).

Anti-patterns to guard against (specific to REDESIGN):
- **Porting old structure under new styling** — if the new design still has 9 sections + 2 modals + 4 copy buttons, the redesign hasn't happened.
- **Keeping both designs behind a flag indefinitely** — set a cutover date in the plan.
- **Redesigning to follow a 2026 trend** — no glassmorphism, no aurora, no gradient mesh, no AI-dashboard glow. Aim for "boring is beautiful."
- **Treating the Preserve list as optional** — honesty + understandability + the bridge contract are why the verdict was REDESIGN-not-NEW. Lose them and the next audit will demand starting over again.
- **Sneaking the discarded items back in under new names** — if the planner proposes a "subtle backdrop glow" or a "tasteful shimmer", that is the aurora layer with a new label.
````
