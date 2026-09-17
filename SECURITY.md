<img src="https://raw.githubusercontent.com/LXRCore/.github/main/profile/lxrcore-logo.png" alt="LXRCore" width="72" align="left" style="margin-right:12px">

# lxr-inventory — Security model

Every client message is an *intent*; the server decides. This file lists the
attacks the resource is built against and where each defence lives.

| Attack | Defence | Where |
|---|---|---|
| Open any stash by id from the client | clients may only open kinds in `Config.Security.clientOpenKinds` (never `stash`); stashes are opened server-side by the owning resource with `owner / job / gang / jobGrade / coords` rules | `server/main.lua` `clientOpen`, `resolveOther` |
| Open an unregistered shop with client-supplied prices | client `data` is ignored; only `Config.Shops.registered` ids; prices clamped ≥ 0; `maxPerPurchase`; shop distance check on open and on every buy | `clientOpen`, `buildShop`, move handler |
| Teleport-open / open through walls | timed open with progress bar (`Config.General.openDelayMs`), start position remembered, distance re-checked when the timer ends; cancelled on move | `open`, `finishOpen`, `lxr-inventory:server:cancelOpen` |
| Walk away with a container open and keep moving items | session anchor (drop coords, other player, stash coords) re-checked on **every** move (`sessionRange`); walk-away closes both sides | move handler, client anchor thread |
| Search a player who is no longer searchable | `canSearch` re-evaluated on every move | move handler |
| Remove-then-add dupes | `Containers.Move` validates both sides (weight, slots, swap) before mutating; stash/drop single-opener lock | `server/containers.lua` |
| Give/use spam, dead or cuffed actions | `useCooldownMs`, `giveCooldownMs`, `blockWhenDead`, `blockWhenCuffed`; core adds per-item cooldown + `use.whileDead/whileCuffed` | `blocked`, `cooldown`, lxr-core `Items.Use` |
| Drop flooding | `Config.Drops.maxPerPlayer`, `createCooldownMs` | `resolveOther('ground')` |
| Weapon kept in hand after it left the satchel | `lxr-inventory:client:weaponRemoved` fired to the loser (and the searched player) | move handler |
| Event flooding | token bucket per source (`Config.Security.rateLimit`); all net events ignore unloaded players | `limited` |
| Forged item box / UI state | UI only renders server views; no client state is trusted | client |
| Silent money/item creation | every cross-container move logged through lxr-core with move counter (`Config.Security.logMoves`); money goes through the core ledger | move handler |

Reporting: open an issue with `[security]` or write to the dev Discord.
