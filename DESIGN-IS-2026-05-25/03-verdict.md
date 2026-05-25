# 03 — Verdict

## Verdict: **REDESIGN**

**One-sentence verdict**: Total 17/30 falls below the REFINE threshold (≥20), and four principles — #5 unobtrusive, #7 long-lasting, #8 thorough, #9 environmentally friendly — score 1 on dimensions that are load-bearing for a single-purpose page used in a 30-second mobile glance, so the visual layer needs to be redone from the principle of restraint rather than patched in place.

## Why redesign and not refine

The fixable signals (spacing outliers, ERROR i18n gap, missing error/disabled CSS) are individually small. But the structural pattern of the page — **a celebratory dashboard for a 30-second utility task** — is the actual problem. You can't refine 8 idle animations and 10+ ornaments into "unobtrusive"; you have to choose to remove them.

What's working (and must be preserved):
- Information architecture order is sane: identity → quota → copy → devices → usage → apps → support
- Honesty is intact (#6 = 3/3) — no dark patterns, no inflation, `devicesNote` is exemplary
- Understandability is intact (#4 = 3/3) — labels match handlers, perfect i18n parity, no jargon
- The bridge contract / data flow / token model — server-side data plane is unchanged in scope

What's failing structurally:
- The visual layer (aurora + glassmorphism + gradient text + shimmer + blink) is a 2024-coded "AI dashboard" aesthetic that competes with content and ages fast
- Copy/QR affordance duplicated across 4 places (header / modal / per-config / per-device) — one canonical place would do
- Avatar picker (24 emojis) + tier pill + theme picker are surface area that doesn't serve the primary task
- No light mode, no reduced-motion respect — the page assumes a stable "dark aesthetic preference" that the user never asked for

## Top 5 highest-leverage moves (handed off to /make-plan)

1. **#5 unobtrusive + #9 environmentally friendly — Strip the aurora/shimmer/glow layer.** Remove the 3 `.aurora-*` blur blobs (index.html:120–125), the hero shimmer border (179–186), the button shine sweep (469–475), and the blink cursor (264). Replace the conic-gradient ring background and noise overlay with a flat panel. Gate any remaining motion on `@media (prefers-reduced-motion: no-preference)`. Evidence: `01-evidence.md` Visual → "Idle ornaments 10+".

2. **#9 environmentally friendly — Honor `prefers-color-scheme`.** Add a light theme as the default for `prefers-color-scheme: light`, keep midnight as the user's optional override (persisted). Drop the hardcoded `data-theme="midnight"` from the `<html>` element (index.html:2). Evidence: `01-evidence.md` Weight & Friction → "hardcoded dark only".

3. **#10 as little design as possible — Cut the copy/QR redundancy to one canonical surface.** Pick a single per-config-row pattern (long-press → action sheet OR a single visible "Copy" + ⋯ menu for "QR / Base64"). Remove the modal's separate "Copy / Base64" buttons and the duplicated header copy button when the canonical surface is reachable. Evidence: `01-evidence.md` Structural → "Repeated affordances: 4 places".

4. **#10 + #2 useful — Demote secondary surface area.** Move "Get the App" + "Support" below a collapsed section or to a separate sheet; collapse the tier pill / avatar picker / hero name flourish behind a "Profile" toggle. The page's job is "copy a config + see what's left" — surface that, hide the rest. Evidence: `01-evidence.md` Structural → "9 sections + 2 modals" and Weight & Friction → "5–6 attention requesters".

5. **#8 thorough — Add the missing states.** Author `.error` CSS for failed network calls (toast is a stopgap, not the state), `[aria-disabled]` styling for buttons that briefly disable during async actions, and a real skeleton for the device list + usage chart while data is loading. Localize the hardcoded `'ERROR'` toast at index.html:2965. Evidence: `01-evidence.md` Visual → "State coverage" + Copy & Honesty → "one outlier".

## What NOT to touch in the redesign

- The bridge `/api/sub/online/{token}` contract and the JWT auth/refresh flow (bridge.py is out of scope).
- The i18n keyset names (rewriting copy is in scope; renaming keys breaks every Jinja/JS reference).
- The token validation + path-traversal defenses in `_resolve_static`.
- The auto-poll cadence (60s + `document.hidden` gate is correctly tuned).

## Honest cross-check

- User wrote "redesign". Evidence agrees: 17/30 = REDESIGN by the Phase 3 rule. No conflict between user framing and evidence-derived verdict.
- Rejected the temptation to call this REFINE just because copy/honesty/understandability are strong (3/3). Those become the *preserve list* for the redesign — they are why we don't need NEW.
