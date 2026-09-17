--[[
    ██╗     ██╗  ██╗██████╗        ██╗███╗   ██╗██╗   ██╗███████╗███╗   ██╗████████╗ ██████╗ ██████╗ ██╗   ██╗
    ██║     ╚██╗██╔╝██╔══██╗       ██║████╗  ██║██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔══██╗╚██╗ ██╔╝
    ██║      ╚███╔╝ ██████╔╝█████╗ ██║██╔██╗ ██║██║   ██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║██████╔╝ ╚████╔╝
    ██║      ██╔██╗ ██╔══██╗╚════╝ ██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██╔══██╗  ╚██╔╝
    ███████╗██╔╝ ██╗██║  ██║       ██║██║ ╚████║ ╚████╔╝ ███████╗██║ ╚████║   ██║   ╚██████╔╝██║  ██║   ██║
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝       ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝

    🐺 LXR Core - Inventory Server

    Sessions (who has which container open), stashes (persisted), ground
    drops (in memory, expiring), shops (buy = money then item, atomic),
    giving, searching, using. Every net event is rate limited and re-checks
    the session so a modified client cannot reach a container it did not open.

    Developer:   iBoss21 / LXRCore
    Website:     https://www.lxrcore.com
    © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
]]

local LXRCore = exports['lxr-core']:GetCoreObject()
local RES = GetCurrentResourceName()

local sessions = {}   -- source → { other = container|nil, otherId = string|nil }
local stashes = {}    -- id → container (loaded lazily)
local drops = {}      -- id → container + coords + createdAt
local shops = {}      -- id → container (items carry price)
local buckets = {}
local nextDrop = 0

local function limited(src)
    local rl = Config.Security.rateLimit
    return not LXRCore.RateLimit(buckets, src, rl.burst, rl.windowMs)
end

local function notify(src, key, kind, vars)
    TriggerClientEvent('LXRCore:Notify', src, Lang:t(key, vars), kind or 'error')
end

local function playerContainer(Player)
    local pd = Player.PlayerData
    return Containers.New('player', 'player', pd.items, tonumber(pd.slots) or LXRCore.Config.Player.maxSlots,
        tonumber(pd.weight) or LXRCore.Config.Player.maxWeight, Lang:t('ui.your_satchel'), { player = Player })
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📦 STASHES (persisted in Config.Stash.table)
-- ═══════════════════════════════════════════════════════════════════════════════

local function stashLimits(id, data)
    local slots, weight = Config.Stash.defaultSlots, Config.Stash.defaultWeight
    for prefix, preset in pairs(Config.Stash.presets or {}) do
        if id:sub(1, #prefix) == prefix then slots, weight = preset.slots, preset.weight end
    end
    if type(data) == 'table' then
        slots = tonumber(data.slots) or slots
        weight = tonumber(data.maxweight or data.weight) or weight
    end
    return slots, weight
end

local function getStash(id, data)
    if stashes[id] then
        if type(data) == 'table' then
            local s, w = stashLimits(id, data)
            stashes[id].slots, stashes[id].maxWeight = s, w
            if data.label then stashes[id].label = data.label end
        end
        return stashes[id]
    end
    local raw = LXRCore.DB.Scalar(('SELECT items FROM `%s` WHERE stash = ?'):format(Config.Stash.table), { id })
    local items = Containers.Deserialize(LXRCore.Shared.JsonDecode(raw, {}))
    local slots, weight = stashLimits(id, data)
    stashes[id] = Containers.New(id, 'stash', items, slots, weight, (type(data) == 'table' and data.label) or id, { dirty = false })
    return stashes[id]
end

local function saveStash(c)
    if not c or c.kind ~= 'stash' then return end
    LXRCore.DB.InsertAsync(('INSERT INTO `%s` (stash, items) VALUES (?, ?) ON DUPLICATE KEY UPDATE items = VALUES(items)'):format(Config.Stash.table),
        { c.id, json.encode(Containers.Serialize(c)) })
    c.dirty = false
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🪵 DROPS (in memory)
-- ═══════════════════════════════════════════════════════════════════════════════

local function broadcastDrops()
    local list = {}
    for id, d in pairs(drops) do list[#list + 1] = { id = id, coords = d.coords } end
    TriggerClientEvent('lxr-inventory:client:drops', -1, list)
end

local function createDrop(coords)
    nextDrop = nextDrop + 1
    local id = ('drop-%d'):format(nextDrop)
    drops[id] = Containers.New(id, 'drop', {}, Config.Drops.slots, Config.Drops.weight, Lang:t('ui.ground'),
        { coords = coords, createdAt = GetGameTimer() })
    return drops[id]
end

local function removeDrop(id)
    drops[id] = nil
    for src, s in pairs(sessions) do
        if s.otherId == id then
            s.other, s.otherId = nil, nil
            TriggerClientEvent('lxr-inventory:client:otherClosed', src)
        end
    end
    broadcastDrops()
end

local function nearestDrop(coords, range)
    local best, bestDist
    for id, d in pairs(drops) do
        local dist = #(vector3(d.coords.x, d.coords.y, d.coords.z) - coords)
        if dist <= range and (not bestDist or dist < bestDist) then best, bestDist = d, dist end
    end
    return best
end

CreateThread(function()
    while true do
        Wait(60000)
        local now = GetGameTimer()
        for id, d in pairs(drops) do
            if Containers.IsEmpty(d) or now - d.createdAt > Config.Drops.expireMs then removeDrop(id) end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🛒 SHOPS
-- ═══════════════════════════════════════════════════════════════════════════════

local function buildShop(id, data)
    local def = data or Config.Shops.registered[id]
    if not def or type(def.items) ~= 'table' then return nil end
    local items = {}
    local slot = 0
    for _, entry in ipairs(def.items) do
        local itemDef = LXRShared.Items[tostring(entry.name):lower()]
        if itemDef then
            slot = slot + 1
            items[slot] = {
                name = itemDef.name, amount = tonumber(entry.amount) or 100, info = entry.info or {}, label = itemDef.label,
                description = itemDef.description or '', weight = itemDef.weight, type = itemDef.type, unique = itemDef.unique,
                useable = itemDef.useable, image = itemDef.image, slot = slot, price = tonumber(entry.price) or 0,
            }
        end
    end
    local c = Containers.New(id, 'shop', items, math.max(slot, 1), math.huge, def.label or id, { account = def.account or Config.Shops.account })
    shops[id] = c
    return c
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔓 OPENING
-- ═══════════════════════════════════════════════════════════════════════════════

local function canSearch(Player, Target)
    local r = Config.General.searchRequires
    local job = Player.PlayerData.job
    if r.leoOnDuty and job.type == 'leo' and job.onduty then return true end
    local md = Target.PlayerData.metadata or {}
    if r.targetCuffed and md.ishandcuffed then return true end
    if r.targetDead and md.isdead then return true end
    return false
end

local function within(src, target, range)
    local a, b = GetPlayerPed(src), GetPlayerPed(target)
    if a == 0 or b == 0 then return false end
    return #(GetEntityCoords(a) - GetEntityCoords(b)) <= range
end

---Resolve (kind, id, data) to a container the requesting player may use.
local function resolveOther(src, Player, kind, id, data)
    if kind == 'stash' then
        if type(id) ~= 'string' or id == '' or #id > 100 then return nil, 'invalid' end
        return getStash(id, data)
    elseif kind == 'drop' then
        local d = drops[id]
        if not d then return nil, 'invalid' end
        local ped = GetPlayerPed(src)
        if #(GetEntityCoords(ped) - vector3(d.coords.x, d.coords.y, d.coords.z)) > Config.Drops.pickupRange + 1.0 then return nil, 'too_far' end
        return d
    elseif kind == 'ground' then
        local ped = GetPlayerPed(src)
        local coords = GetEntityCoords(ped)
        local d = nearestDrop(coords, Config.Drops.pickupRange)
        if not d then
            d = createDrop({ x = coords.x, y = coords.y, z = coords.z })
            broadcastDrops()
        end
        return d
    elseif kind == 'shop' then
        if type(id) ~= 'string' then return nil, 'invalid' end
        local c = shops[id] or buildShop(id, data)
        if not c then return nil, 'invalid' end
        return c
    elseif kind == 'otherplayer' then
        local target = LXRCore.Functions.GetPlayer(tonumber(id))
        if not target or target.PlayerData.source == src then return nil, 'invalid' end
        if not within(src, target.PlayerData.source, Config.General.searchDistance) then return nil, 'too_far' end
        if not canSearch(Player, target) then return nil, 'no_permission' end
        local c = playerContainer(target)
        c.id, c.kind, c.label = tostring(target.PlayerData.source), 'otherplayer', Lang:t('ui.other_player')
        return c
    end
    return nil, 'invalid'
end

local function open(src, kind, id, data)
    local Player = LXRCore.Functions.GetPlayer(src)
    if not Player then return end
    local other, err
    if kind then
        other, err = resolveOther(src, Player, kind, id, data)
        if not other then return notify(src, 'error.' .. (err or 'invalid')) end
        -- a stash / drop may only be open by one player at a time (prevents dupes by racing moves)
        if (other.kind == 'stash' or other.kind == 'drop') and other.openBy and other.openBy ~= src and LXRCore.Players[other.openBy] then
            return notify(src, 'error.in_use')
        end
        other.openBy = src
    end
    sessions[src] = { other = other, otherId = other and other.id or nil, kind = other and other.kind or nil }
    TriggerClientEvent('lxr-inventory:client:open', src, Containers.View(playerContainer(Player)), other and Containers.View(other) or nil)
end

local function close(src)
    local s = sessions[src]
    if not s then return end
    if s.other then
        if s.other.openBy == src then s.other.openBy = nil end
        if s.other.kind == 'stash' and s.other.dirty then saveStash(s.other) end
        if s.other.kind == 'drop' and Containers.IsEmpty(s.other) then removeDrop(s.other.id) end
    end
    sessions[src] = nil
    if Config.General.saveOnClose then
        local Player = LXRCore.Functions.GetPlayer(src)
        if Player then LXRCore.Player.Save(src, false) end
    end
end

local function refresh(src)
    local Player = LXRCore.Functions.GetPlayer(src)
    local s = sessions[src]
    if not Player then return end
    Player.Functions.UpdatePlayerData()
    TriggerClientEvent('lxr-inventory:client:update', src, Containers.View(playerContainer(Player)), s and s.other and Containers.View(s.other) or nil)
    if s and s.other and s.other.kind == 'otherplayer' then
        local target = s.other.player
        if target then target.Functions.UpdatePlayerData() end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📡 EVENTS
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('lxr-inventory:server:open', function(kind, id, data)
    local src = source
    if limited(src) then return end
    if kind ~= nil and type(kind) ~= 'string' then return end
    -- data from clients is only honoured for shops registered in config; others resources pass data server-side
    open(src, kind, id, nil)
end)

-- Server-side API for other resources: TriggerEvent('inventory:server:OpenInventory', 'stash', id, { label, slots, maxweight })
AddEventHandler('inventory:server:OpenInventory', function(kind, id, data)
    local src = source
    if not LXRCore.Players[src] then return end
    if kind == 'player' or kind == nil then return open(src, nil) end
    open(src, kind, id, data)
end)
-- net variant kept for legacy resources; client-supplied data is ignored
RegisterNetEvent('inventory:server:OpenInventory', function(kind, id)
    local src = source
    if limited(src) then return end
    if kind == 'player' or kind == nil then return open(src, nil) end
    open(src, kind, id, nil)
end)

RegisterNetEvent('lxr-inventory:server:close', function()
    close(source)
end)

RegisterNetEvent('lxr-inventory:server:move', function(fromKind, toKind, fromSlot, toSlot, amount)
    local src = source
    if limited(src) then return end
    local Player = LXRCore.Functions.GetPlayer(src)
    local s = sessions[src]
    if not Player or not s then return end
    local mine = playerContainer(Player)
    local function pick(kind)
        if kind == 'player' then return mine end
        if kind == 'other' then return s.other end
        return nil
    end
    local from, to = pick(fromKind), pick(toKind)
    if not from or not to then return end
    amount = tonumber(amount)
    if amount and amount > Config.Security.maxMoveAmount then return end

    -- shops: buying only, player → shop is not allowed
    if to.kind == 'shop' then return notify(src, 'error.cannot_store_here') end
    if from.kind == 'shop' then
        local entry = from.items[tonumber(fromSlot)]
        if not entry then return end
        amount = math.floor(amount or 1)
        if amount <= 0 or amount > entry.amount then return notify(src, 'error.invalid_amount') end
        local price = (entry.price or 0) * amount
        local canSlot = Containers.CanPlace(mine, entry.name, amount, entry.info, toSlot)
        if price > 0 and not Player.Functions.RemoveMoney(from.account, price, 'shop:' .. from.id) then
            return notify(src, 'error.not_enough_money')
        end
        local ok, why
        if canSlot then
            ok = Containers.PlaceAt(mine, entry.name, amount, entry.info, toSlot)
        else
            ok, why = Containers.Add(mine, entry.name, amount, entry.info) -- any free slot
        end
        if not ok then
            if price > 0 then Player.Functions.AddMoney(from.account, price, 'shop:refund') end
            return notify(src, 'error.' .. (why or 'too_heavy'))
        end
        LXRCore.Log.info('inventory', ('bought %dx %s for %s'):format(amount, entry.name, price), { source = src, shop = from.id })
        TriggerClientEvent('inventory:client:ItemBox', src, LXRShared.Items[entry.name], 'add', amount)
        return refresh(src)
    end

    local ok, why, action = Containers.Move(from, to, fromSlot, toSlot, amount)
    if not ok then return notify(src, 'error.' .. (why or 'invalid')) end
    if from.kind == 'stash' then from.dirty = true end
    if to.kind == 'stash' then to.dirty = true end
    if from ~= to then
        local moved = to.items[tonumber(toSlot)] or from.items[tonumber(fromSlot)]
        LXRCore.Log.info('inventory', ('%s %s -> %s'):format(action or 'move', from.kind, to.kind),
            { source = src, item = moved and moved.name, amount = amount, fromId = from.id, toId = to.id })
        if to.kind == 'otherplayer' and to.player then
            TriggerClientEvent('inventory:client:ItemBox', to.player.PlayerData.source, LXRShared.Items[moved.name], 'add', amount)
        end
    end
    refresh(src)
end)

RegisterNetEvent('lxr-inventory:server:use', function(slot)
    local src = source
    if limited(src) then return end
    local Player = LXRCore.Functions.GetPlayer(src)
    slot = tonumber(slot)
    if not Player or not slot then return end
    local item = Player.PlayerData.items[slot]
    if not item then return end
    if not LXRCore.Items.CanUse(item.name) then return notify(src, 'error.not_usable') end
    if Config.General.closeOnUse and item.shouldClose then close(src) TriggerClientEvent('lxr-inventory:client:close', src) end
    TriggerClientEvent('lxr-inventory:client:useAnim', src)
    LXRCore.Items.Use(src, item)
    refresh(src)
end)

RegisterNetEvent('lxr-inventory:server:give', function(target, slot, amount)
    local src = source
    if limited(src) then return end
    local Player = LXRCore.Functions.GetPlayer(src)
    local Target = LXRCore.Functions.GetPlayer(tonumber(target))
    slot = tonumber(slot)
    if not Player or not Target or Target == Player or not slot then return end
    if not within(src, Target.PlayerData.source, Config.General.giveDistance) then return notify(src, 'error.too_far') end
    local item = Player.PlayerData.items[slot]
    if not item then return end
    amount = math.floor(tonumber(amount) or item.amount)
    if amount <= 0 or amount > item.amount then return notify(src, 'error.invalid_amount') end
    local mine, theirs = playerContainer(Player), playerContainer(Target)
    local ok, why = Containers.Add(theirs, item.name, amount, item.info)
    if not ok then return notify(src, why == 'too_heavy' and 'error.target_full' or ('error.' .. why)) end
    item.amount = item.amount - amount
    if item.amount <= 0 then mine.items[slot] = nil end
    Target.Functions.UpdatePlayerData()
    TriggerClientEvent('inventory:client:ItemBox', Target.PlayerData.source, LXRShared.Items[item.name], 'add', amount)
    TriggerClientEvent('inventory:client:ItemBox', src, LXRShared.Items[item.name], 'remove', amount)
    TriggerClientEvent('lxr-inventory:client:giveAnim', src)
    LXRCore.Log.info('inventory', ('gave %dx %s'):format(amount, item.name), { source = src, target = Target.PlayerData.source })
    refresh(src)
end)

AddEventHandler('playerDropped', function()
    close(source)
    buckets[source] = nil
end)

AddEventHandler('LXRCore:Server:OnPlayerUnload', function(src) close(src) end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, c in pairs(stashes) do if c.dirty then saveStash(c) end end
end)

-- Send current drops to late joiners
AddEventHandler('LXRCore:Server:PlayerLoaded', function(Player)
    local list = {}
    for id, d in pairs(drops) do list[#list + 1] = { id = id, coords = d.coords } end
    TriggerClientEvent('lxr-inventory:client:drops', Player.PlayerData.source, list)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔌 EXPORTS & COMMANDS
-- ═══════════════════════════════════════════════════════════════════════════════

exports('OpenInventory', function(src, kind, id, data) open(src, kind, id, data) end)
exports('CloseInventory', function(src) close(src) TriggerClientEvent('lxr-inventory:client:close', src) end)
exports('GetStashItems', function(id) return Containers.Serialize(getStash(id)) end)
exports('AddStashItem', function(id, name, amount, info)
    local c = getStash(id)
    local ok, why = Containers.Add(c, name, amount, info)
    if ok then c.dirty = true saveStash(c) end
    return ok, why
end)
exports('RemoveStashItem', function(id, name, amount)
    local c = getStash(id)
    if Containers.Count(c, name) < (tonumber(amount) or 1) then return false, 'not_owned' end
    local remaining = math.floor(tonumber(amount) or 1)
    for slot, it in pairs(c.items) do
        if it.name == name and remaining > 0 then
            local take = math.min(it.amount, remaining)
            it.amount = it.amount - take
            remaining = remaining - take
            if it.amount <= 0 then c.items[slot] = nil end
        end
    end
    c.dirty = true
    saveStash(c)
    return true
end)
exports('ClearStash', function(id)
    local c = getStash(id)
    c.items = {}
    c.dirty = true
    saveStash(c)
    return true
end)
exports('RegisterShop', function(id, data) return buildShop(id, data) ~= nil end)
exports('GetSlotData', function(src, slot)
    local Player = LXRCore.Functions.GetPlayer(src)
    return Player and Player.PlayerData.items[tonumber(slot)] or nil
end)

-- Legacy aliases (QBR-era event names)
RegisterNetEvent('inventory:server:UseItemSlot', function(slot) TriggerEvent('lxr-inventory:server:use', slot) end)
RegisterNetEvent('inventory:server:SaveInventory', function() end)
LXRCore.Functions.CreateCallback('lxr-inventory:server:GetStashItems', function(_, cb, id) cb(Containers.Serialize(getStash(id))) end)

LXRCore.Commands.Add('giveitem', Lang:t('command.giveitem'), { { name = 'id', help = 'Player id' }, { name = 'item', help = 'Item name' }, { name = 'amount', help = 'Amount' } }, true, function(src, args)
    local Target = LXRCore.Functions.GetPlayer(tonumber(args[1]))
    if not Target then return notify(src, 'error.invalid') end
    local ok, why = Target.Functions.AddItem(tostring(args[2]):lower(), tonumber(args[3]) or 1, nil, nil, 'admin:giveitem')
    if src > 0 then notify(src, ok and 'info.item_given' or ('error.' .. (why or 'invalid')), ok and 'success' or 'error') end
end, 'admin')

LXRCore.Commands.Add('clearinv', Lang:t('command.clearinv'), { { name = 'id', help = 'Player id' } }, true, function(src, args)
    local Target = LXRCore.Functions.GetPlayer(tonumber(args[1]))
    if not Target then return notify(src, 'error.invalid') end
    Target.Functions.ClearInventory()
    if src > 0 then notify(src, 'info.cleared', 'success') end
end, 'admin')

LXRCore.Commands.Add('resetstash', Lang:t('command.resetstash'), { { name = 'id', help = 'Stash id' } }, true, function(src, args)
    local c = getStash(tostring(args[1]))
    c.items = {}
    c.dirty = true
    saveStash(c)
    if src > 0 then notify(src, 'info.cleared', 'success') end
end, 'admin')

-- Ensure the stash table exists (idempotent migration through the core runner)
LXRCore.DB.RegisterMigration(RES, '0001_stashitems', ([[
CREATE TABLE IF NOT EXISTS `%s` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `stash` VARCHAR(255) NOT NULL,
  `items` LONGTEXT DEFAULT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`stash`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]]):format(Config.Stash.table))

LXRCore.Log.info('inventory', ('%s v%s ready'):format(RES, GetResourceMetadata(RES, 'version', 0)))
