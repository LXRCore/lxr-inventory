<!--
    lxr-inventory — LXRCore inventory UI, stashes, drops, shops
    Developer: iBoss21 / LXRCore · https://www.lxrcore.com
    © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
-->

<img src="https://raw.githubusercontent.com/LXRCore/.github/main/profile/lxrcore-logo.png" alt="LXRCore" width="72" align="left" style="margin-right:12px">

# lxr-inventory — Inventory for LXRCore v3

![Version](https://img.shields.io/badge/version-2.0.0-c4a574)
![Core](https://img.shields.io/badge/requires-lxr--core_v3-1a1512)
![NUI](https://img.shields.io/badge/NUI-vanilla_%C2%B7_no_CDN-brightgreen)
![Tests](https://img.shields.io/badge/move_engine_tests-7_passing-brightgreen)

Item logic (weight, slots, stacking, persistence of the player's satchel) is
owned by **lxr-core**. This resource adds what players see and touch: the
drag-and-drop interface, hotbar keys, stashes, ground drops, shops, giving
items and searching other players.

## Why v2

| v1 (qb-inventory clone) | v2 |
|---|---|
| Bootstrap, jQuery, jQuery-UI, FontAwesome and Google Fonts from CDNs | vanilla HTML/CSS/JS, LXRCore design tokens, works offline |
| "remove then add" moves — items vanished or duplicated when the add failed | one move engine (`server/containers.lua`): validate everything, then mutate; swap only when both sides fit |
| any client could open any stash / player and push moves into it | per-player **session**: moves are only accepted into the container the server opened for you; stashes/drops are single-user while open |
| crafting, attachments, GTA weapon images | removed (crafting belongs to its own resource) |
| direct SQL in the resource | stash table created through the core migration runner; player items saved by the core |

## Features

* Player satchel + secondary panel (stash · ground · shop · other player), drag & drop, split by amount, double-click to move/use.
* Hotbar: slots 1–5 on keys 1–5 (`RegisterKeyMapping`, rebindable). Open with TAB.
* Stashes: `Config.Stash.presets` by id prefix; other resources open them with `TriggerEvent('inventory:server:OpenInventory', 'stash', id, { label, slots, maxweight })`.
* Ground drops: created where the player stands, prop + marker, expire when empty or after `Config.Drops.expireMs`.
* Shops: `Config.Shops.registered` or `exports['lxr-inventory']:RegisterShop(id, { label, items })`; buying charges the account first and refunds on failure.
* Give to nearest player (server checks distance) · search / rob when you are on-duty law or the target is cuffed / dead.
* Item box toasts (`inventory:client:ItemBox`), use / drop animations.
* English + Georgian locales.

## Install

```cfg
ensure lxr-core
ensure lxr-inventory
```
No SQL to import: `stashitems` is created on first start by the core migration runner.

## API

| | |
|---|---|
| `exports['lxr-inventory']:OpenInventory(src, kind, id, data)` | `kind` ∈ `stash`, `drop`, `ground`, `shop`, `otherplayer` |
| `exports['lxr-inventory']:CloseInventory(src)` | |
| `exports['lxr-inventory']:GetStashItems(id)` / `AddStashItem(id, name, amount, info)` / `RemoveStashItem(id, name, amount)` / `ClearStash(id)` | |
| `exports['lxr-inventory']:RegisterShop(id, def)` | |
| `exports['lxr-inventory']:GetSlotData(src, slot)` | |
| events kept for legacy resources | `inventory:server:OpenInventory`, `inventory:client:ItemBox`, `inventory:server:UseItemSlot`, `lxr-inventory:client:giveAnim`, `inventory:client:DropItemAnim`, `lxr-inventory:server:GetStashItems` (callback) |
| commands | `/giveitem id item amount` (admin), `/clearinv id` (admin), `/resetstash id` (admin) |

Item images: put `html/images/<item>.png` files in place (see the folder README); the UI shows a lettered tile when an image is missing.

## Tests

```bash
lua tests/run.lua      # needs ../lxr-core for the runtime shim
```
Covers stacking, splitting, swapping, weight/slot limits, metadata separation and serialisation.

## Verification

| Check | Result |
|---|---|
| Lua / JS syntax | ✅ |
| Move engine offline tests | ✅ 7/7 |
| NUI rendered with mock data (grid, hotbar keys, tooltip, weight bar, shop prices) | ✅ |
| In-game: drag & drop, stashes, drops, shops, give/search | **NOT TESTED** yet |

> © 2026 iBoss21 / LXRCore | [lxrcore.com](https://www.lxrcore.com) | All Rights Reserved
