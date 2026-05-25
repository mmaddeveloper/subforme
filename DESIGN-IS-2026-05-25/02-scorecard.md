# 02 — Scorecard

Per-principle scores follow the Phase 2 anchors. Tie-break: pick the lower score. Score-the-worst-instance rule applied. Evidence anchors point to `01-evidence.md`.

---

**1. Good design is innovative — Score: 2/3**
Evidence: Ring gauge + per-IP sparkline + auto-poll + theme/avatar pickers exceed the Marzban/Hiddify baseline, but the pattern (dashboard-style sub page with quota gauge + device list) is now common in panels like Hiddify Panel and Sanaei x-ui forks.
Justification: Refreshes an existing pattern with clear improvements — not a wholly novel pattern, not a wholesale copy.

**2. Good design makes a product useful — Score: 2/3**
Evidence: Primary task (copy a config + see quota) completes in ≤1 tap thanks to the prominent header copy button (1277) and the ring gauge at the top (1240). Adjacent surface adds steps: period tabs (1336–1338), avatars (24), theme picker (4), tier pill, OS rail (5), apps list, support links.
Justification: Primary task completes but the adjacent surface adds steps for tasks that aren't the user's job-to-be-done in a 30s glance.

**3. Good design is aesthetic — Score: 2/3**
Evidence: Spacing scale 4/8/12/16 is mostly coherent with two outliers (22px at 171/190, 40px at 136); type scale 8–24px + responsive clamps; ~55 distinct colors are bounded per theme. No orphan styles detected.
Justification: ≤2 minor inconsistencies (22/40 spacing outliers) across audited surface = 2/3 per anchor.

**4. Good design makes a product understandable — Score: 3/3**
Evidence: Every label maps 1:1 to handler behavior (Copy → `navigator.clipboard.writeText`; QR → modal toggle; period tabs → refetch + re-render; theme/avatar/lang → persist + apply). Perfect i18n parity. No jargon (`devicesNote` explicitly explains the IP-history limitation at 1532). Plain language throughout.
Justification: First-time user can name every primary control correctly — meets the 3/3 anchor.

**5. Good design is unobtrusive — Score: 1/3**
Evidence: 3 aurora blobs with `filter: blur(80px)` running 22/26/30-second loops (123–125), shimmer animation on hero border (184), blink cursor on hero name (264), ping animations on status pips (278, 674), conic-gradient ring (325), button shine sweep (469), noise overlay (130–134), 10+ idle ornaments total. Modal backdrop-filter, theme-swatch glow.
Justification: Decoration competes with content. The aurora layer and shimmer/blink loops draw the eye away from the primary affordances. Matches the 1/3 anchor ("decoration competes with content").

**6. Good design is honest — Score: 3/3**
Evidence: Zero marketing inflations, zero dark patterns. All button labels match handlers (verified by Copy & Honesty subagent across 10+ controls). `devicesNote` (1532) explicitly discloses the data limitation: the page shows only the last fetcher's IP. No fake scarcity, no hidden cost, no roach motel.
Justification: Every claim, badge, and label maps 1:1 to actual behavior. The one minor flaw (hardcoded `'ERROR'` toast at 2965 not i18n'd) is a polish gap, not a honesty failure.

**7. Good design is long-lasting — Score: 1/3**
Evidence: Aurora blob backgrounds (`radial-gradient` + `blur(80px)`, lines 120–125) are a 2020–2024 marker (Stripe/Linear/Vercel landing-page genre). Conic-gradient progress ring (325). Glassmorphism via `backdrop-filter: blur` (934). Linear-gradient accent text (multiple). Tier pills with metallic gradient (Bronze/Silver/Gold/Platinum). Button shine sweep (469).
Justification: 4+ dated markers tied to the current "dashboard-glow" aesthetic. In 3 years this will read as dated as Material 2018 or skeuomorphic chrome. Matches the 1/3 anchor (2–3 dated markers; we have more).

**8. Good design is thorough down to the last detail — Score: 1/3**
Evidence: error CSS missing (no `.error`/`.fail`; only JS toast); disabled state missing (no `:disabled`/`[aria-disabled]`/`.disabled`); loading state is partial (`.ready` toggle but no skeleton/spinner UI). Empty/success/focus-visible/hover/active are present.
Justification: 2–3 states missing or rough (error, disabled, loading-partial) = 1/3 per anchor.

**9. Good design is environmentally friendly — Score: 1/3**
Evidence: Initial blocking JS ~96 KB (under 500 KB ✓). BUT: 8 idle infinite animations including 3 large `blur(80px)` radial gradients that continuously force compositor paint. `prefers-reduced-motion` ignored everywhere. `prefers-color-scheme` ignored — hardcoded `data-theme="midnight"`. No light mode.
Justification: Motion always on, reduced-motion ignored → falls to 1/3 even though bundle weight is OK.

**10. Good design is as little design as possible — Score: 1/3**
Evidence: Removable without breaking the primary task: 3 aurora blobs, shimmer hero border, blink cursor, hero name field, tier pill, avatar picker (24 emojis), 4-variant theme picker, "Get the App" section (could be a single link), Support section (could be a footer link), button shine sweeps. Plus the copy/QR affordance is duplicated across 4 locations (header, modal, per-config, per-device).
Justification: 5+ removable elements, primary affordance duplicated 4× → 1/3 per anchor (3–5 removable elements is 1/3; we exceed that but the page does still function, so not 0).

---

## Total: **17 / 30**

| # | Principle | Score |
|---|---|---|
| 1 | innovative | 2 |
| 2 | useful | 2 |
| 3 | aesthetic | 2 |
| 4 | understandable | 3 |
| 5 | unobtrusive | 1 |
| 6 | honest | 3 |
| 7 | long-lasting | 1 |
| 8 | thorough | 1 |
| 9 | environmentally friendly | 1 |
| 10 | as little design as possible | 1 |
| **Σ** | | **17** |
