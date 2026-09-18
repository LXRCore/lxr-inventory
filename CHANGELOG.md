# Changelog — lxr-inventory

## [2.1.0] — 2026-09-17
- Cleaner slot layout: per-slot weight text removed from grid slots (weight now lives in the tooltip and detail panel only); shop prices remain visible on shop slots via a dedicated `.slot-price` element.
- Shop buy flow: clicking **Buy** on a shop item posts a `buy` NUI callback that triggers an atomic server-side purchase (`lxr-inventory:server:buy`) — validates the shop entry, charges cash, adds the item via Containers, and refreshes.

## [2.0.0] — 2026-09-17
- Rewrite for LXRCore v3: validated container move engine (no remove-then-add), per-player sessions, single-user stashes/drops, atomic shop purchases with refund, distance-checked give and permissioned search.
- Vanilla NUI (drag & drop, hotbar, tooltips, item box) on LXRCore design tokens; Georgian locale.
- Stash table created through the core migration runner; player items persisted by the core.
- Removed crafting/attachments, CDN dependencies, GTA weapon images.
