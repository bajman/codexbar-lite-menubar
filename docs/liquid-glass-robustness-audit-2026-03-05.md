# CodexBar Menu Bar Audit

Date: 2026-03-05
Workspace: `/Users/yaleleber/Code/codexbar-lite-menubar`

## Scope

This pass focused on the menu bar panel, SwiftUI/AppKit bridging, Liquid Glass treatment, and the refresh paths that directly affect panel responsiveness.

## Implemented in this pass

### Liquid Glass and visual hierarchy

- Kept true glass on the outer panel shell and action controls, while restoring separate content surfaces for usage cards, info rows, and expanded chart sections.
- Removed the unsupported macOS `.interactive()` glass variant from the shared glass modifier.
- Normalized panel spacing to a 4/8/12/16 rhythm across cards, action rows, account chips, and chart sections.
- Improved card header layout so provider title, subtitle, email, and plan metadata no longer crowd each other as aggressively.
- Increased panel attachment and screen inset spacing so the floating panel reads as an intentional overlay instead of hugging surrounding chrome.

### Performance and robustness

- Split settings observation into data-affecting vs presentation-only buckets so menu-only interactions do not trigger full provider refreshes.
- Avoided status fetch work for disabled providers and clear their cached status when they are no longer active.
- Fixed token-cost refresh throttling so failures do not suppress the next automatic retry for the full TTL window.
- Precomputed chart models so hover updates no longer rebuild chart data on every mouse move.
- Detached the panel hosting tree on dismiss so hidden views do not keep observing store changes offscreen.
- Narrowed the menu-render observation token to fields that actually affect the panel/icon rendering path.

## Remaining follow-up recommendations

### Refresh semantics

- Manual refresh requests are still dropped when a refresh is already in flight. Add a queued rerun flag so user-initiated refreshes are coalesced instead of ignored.
- Status checks are still tied to the main usage cadence. A dedicated TTL/backoff layer would reduce network work further.

### Visual refinement

- The action area can go one step further by giving provider status metadata its own dedicated info component rather than reusing generic text rows.
- If the app later adopts more glass controls inside the panel, keep them grouped in small `GlassEffectContainer` clusters instead of reintroducing glass on content cards.

### Validation

- Capture before/after screenshots for the panel on both light and dark appearances.
- Recheck with Reduce Transparency enabled to confirm the content-surface fallback stays readable.
- Profile panel open and hover interactions on lower-end Apple Silicon hardware after any future chart or animation changes.
