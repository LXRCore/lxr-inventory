# Changelog — lxr-inventory

## 3.0.0 — 2026-09-19
* Tool durability shows on the tile (the same bar as a gun's condition) and in the detail.
* Robbery at gunpoint: someone with their hands up can be searched by an armed player (`searchRequires.targetHandsUp`, `robRequiresGun`), and everyone gets Rob / Search options on people who are cuffed, dead or holding their hands up (the law's own Search stays in lxr-lawman); event `lxr:inventory:robbery`.
* **Trade** — `/trade` (and the wheel) offers a face-to-face trade to the closest player: both offers sit in escrow, a cash offer rides along, both confirm, the swap is checked for weight, slots and money on both sides before anything moves; cancel / ESC / walking away / a disconnect returns everything (an offline owner's goods wait in a return stash swept on the next login). Shift + drag = the whole stack, Alt + drag = half. The item export surface other frameworks' scripts call (`AddItem`, `RemoveItem`, `HasItem`, `GetItemCount`, `CanAddItem`, `GetFreeWeight`, `GetSlots`, `SetItemData`, `ClearInventory`, `UseItem`, `OpenInventoryById`, `CreateInventory`, `DeleteInventory`, …) as thin wrappers over the core.
* Drag and drop: the slot under the cursor at release is found by position when the page did not deliver enter/leave while the button was held (the game's page); grids carry `data-key`.
* Fix: `LXRCore.PlayerData` stays current — the core object comes back as a copy, so cash, job and metadata never changed after login in this resource. It now listens to `lxr:client:data` / `lxr:client:unloaded` and refreshes its copy.
* The satchel opens on **I** (was TAB); players rebind it in the game's settings.
* *What you wear* lists every piece the character actually wears (lxr-clothing's `Wearing()`, labels from its catalogue) — click a piece to take it off / put it back, **Undress** / **Dress** for the whole outfit.
* A rejected move always tells the player why (no session, invalid target, amount) — nothing is dropped silently.
* LXRCore v3 release line: every resource ships as 3.0.0 from here (the entries below are the road to it).

## 3.1.1 — 2026-09-19
* Fix: nothing in the satchel could be clicked, double-clicked or dragged — the slot was a component declared inside the page, so React recreated its type on every state change and remounted every slot under the pointer mid-click and mid-drag. The slot is a plain render function now.
## [2.1.0] — 2026-09-17
- Cleaner slot layout: per-slot weight text removed from grid slots (weight now lives in the tooltip and detail panel only); shop prices remain visible on shop slots via a dedicated `.slot-price` element.
- Shop buy flow: clicking **Buy** on a shop item posts a `buy` NUI callback that triggers an atomic server-side purchase (`lxr-inventory:server:buy`) — validates the shop entry, charges cash, adds the item via Containers, and refreshes.

## [2.0.0] — 2026-09-17
- Rewrite for LXRCore v3: validated container move engine (no remove-then-add), per-player sessions, single-user stashes/drops, atomic shop purchases with refund, distance-checked give and permissioned search.
- Vanilla NUI (drag & drop, hotbar, tooltips, item box) on LXRCore design tokens; Georgian locale.
- Stash table created through the core migration runner; player items persisted by the core.
- Removed crafting/attachments, CDN dependencies, GTA weapon images.
