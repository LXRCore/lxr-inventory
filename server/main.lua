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

local sessions = {}   -- source → { other, otherId, kind, anchor = vector3|nil, range }
local pendingOpen = {} -- source → { token, kind, id, data, coords }
local stashes = {}    -- id → container (loaded lazily)
local drops = {}      -- id → container + coords + createdAt + owner
local shops = {}      -- id → container (items carry price)
local buckets = {}
local lastUse, lastGive, lastDropCreate = {}, {}, {}
local dropsByOwner = {} -- citizenid → count
local nextDrop = 0
local openToken = 0

local function limited(src)
    local rl = Config.Security.rateLimit
    return not LXRCore.RateLimit(buckets, src, rl.burst, rl.windowMs)
end

local function notify(src, key, kind, vars)
    LXRCore.Notify(src, Lang:t(key, vars), kind or 'error')
end

---Player state checks shared by every action.
local function blocked(src, Player, allowCuffed)
    local md = Player.PlayerData.metadata or {}
    if Config.General.blockWhenDead and md.isdead then notify(src, 'error.dead') return true end
    if Config.General.blockWhenCuffed and md.ishandcuffed and not allowCuffed then notify(src, 'error.cuffed') return true end
    return false
end

local function cooldown(tbl, src, ms)
    local now = GetGameTimer()
    if tbl[src] and now - tbl[src] < ms then return true end
    tbl[src] = now
    return false
end

local function distanceTo(src, coords)
    local ped = GetPlayerPed(src)
    if ped == 0 or not coords then return math.huge end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z))
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

local function createDrop(coords, owner)
    nextDrop = nextDrop + 1
    local id = ('drop-%d'):format(nextDrop)
    drops[id] = Containers.New(id, 'drop', {}, Config.Drops.slots, Config.Drops.weight, Lang:t('ui.ground'),
        { coords = coords, createdAt = GetGameTimer(), owner = owner })
    if owner then dropsByOwner[owner] = (dropsByOwner[owner] or 0) + 1 end
    return drops[id]
end

local function removeDrop(id)
    local d = drops[id]
    if d and d.owner and dropsByOwner[d.owner] then dropsByOwner[d.owner] = math.max(0, dropsByOwner[d.owner] - 1) end
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
                useable = itemDef.useable, image = itemDef.image, slot = slot, price = math.max(0, tonumber(entry.price) or 0),
            }
        end
    end
    local c = Containers.New(id, 'shop', items, math.max(slot, 1), math.huge, def.label or id,
        { account = def.account or Config.Shops.account, coords = def.coords, distance = def.distance or 3.0 })
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
    if r.targetHandsUp and Player(Target.PlayerData.source).state.handsup == true then
        -- a robbery: the robber must be armed when the config says so
        if Config.General.robRequiresGun then
            local ped = GetPlayerPed(Player.PlayerData.source)
            local weapon = ped ~= 0 and GetSelectedPedWeapon(ped) or 0
            if not weapon or weapon == 0 or weapon == joaat('WEAPON_UNARMED') then return false end
        end
        LXRCore.Emit('lxr:inventory:robbery', nil, Player.PlayerData.source, Target.PlayerData.source)
        return true
    end
    return false
end

local function within(src, target, range)
    local a, b = GetPlayerPed(src), GetPlayerPed(target)
    if a == 0 or b == 0 then return false end
    return #(GetEntityCoords(a) - GetEntityCoords(b)) <= range
end

---Resolve (kind, id, data) to a container the requesting player may use.
-- ═══════════════════════════════════════════════════════════════════════════════
-- 🤝 TRADE — two escrows, both confirm, then the swap (or everything goes back)
-- ═══════════════════════════════════════════════════════════════════════════════
local trades = {}        -- id → { id, a, b, esc = { [src] = container }, money = { [src] = n }, ok = { [src] = bool }, at }
local tradeOf = {}       -- src → trade id
local invites = {}       -- target src → { from, at }
local tradeSeq = 0
local refresh, close     -- defined below

local function tradeName(src)
    local P = LXRCore.Functions.GetPlayer(src)
    local c = P and P.PlayerData.charinfo or {}
    local n = ((c.firstname or '') .. ' ' .. (c.lastname or '')):gsub('^%s+', '')
    return n ~= '' and n or (GetPlayerName(src) or tostring(src))
end
local function partnerOf(tr, src) return tr.a == src and tr.b or tr.a end
local function tradeInfo(tr, src)
    local other = partnerOf(tr, src)
    return {
        id = tr.id, partner = tradeName(other),
        theirs = Containers.View(tr.esc[other]).items, theirSlots = tr.esc[other].slots,
        money = { mine = tr.money[src] or 0, theirs = tr.money[other] or 0 },
        confirmed = { mine = tr.ok[src] == true, theirs = tr.ok[other] == true },
    }
end
-- give a side's escrow back to its owner (online: the satchel; offline: a return stash swept on next login)
local function returnEscrow(tr, src)
    local esc = tr.esc[src]
    if not esc or Containers.IsEmpty(esc) then return end
    local P = LXRCore.Functions.GetPlayer(src)
    local target = P and playerContainer(P)
    if not target then
        local cid = tr.cid[src]
        if cid then target = getStash('trade-return-' .. cid, { slots = esc.slots, weight = esc.maxWeight * 4 }) target.dirty = true end
    end
    for slot, it in pairs(esc.items) do
        if it and target then
            local ok = Containers.Add(target, it.name, it.amount, it.info)
            if not ok then LXRCore.Log.error('inventory', ('trade: could not return %dx %s to %s'):format(it.amount, it.name, tostring(src))) end
        end
        esc.items[slot] = nil
    end
    if target and target.kind == 'stash' then saveStash(target) end
    if P then P.Functions.UpdatePlayerData() end
end
local function endTrade(tr, reason)
    if not trades[tr.id] then return end
    trades[tr.id] = nil
    for _, s in ipairs({ tr.a, tr.b }) do
        tradeOf[s] = nil
        returnEscrow(tr, s)
        if sessions[s] and sessions[s].kind == 'trade' then
            sessions[s] = nil
            TriggerClientEvent('lxr-inventory:client:close', s)
        end
        if reason and LXRCore.Functions.GetPlayer(s) then notify(s, 'info.trade_' .. reason) end
    end
    LXRCore.Log.info('inventory', 'trade ended: ' .. tostring(reason), { a = tr.a, b = tr.b })
end
local function tradeRefresh(tr)
    for _, s in ipairs({ tr.a, tr.b }) do if sessions[s] and sessions[s].kind == 'trade' then refresh(s) end end
end
-- the swap: both must be able to carry the other's offer and pay their own sum; nothing moves otherwise
local function settleTrade(tr)
    local A, B = LXRCore.Functions.GetPlayer(tr.a), LXRCore.Functions.GetPlayer(tr.b)
    if not A or not B then return endTrade(tr, 'cancelled') end
    local acct = Config.Trade.account or 'cash'
    for _, s in ipairs({ tr.a, tr.b }) do
        local P = s == tr.a and A or B
        if (tr.money[s] or 0) > (P.PlayerData.money[acct] or 0) then tr.ok = {} notify(s, 'error.not_enough_money') tradeRefresh(tr) return end
    end
    -- a dry run on copies of both satchels
    for _, s in ipairs({ tr.a, tr.b }) do
        local P = s == tr.a and A or B
        local other = partnerOf(tr, s)
        local probe = Containers.New('probe', 'player', Containers.Deserialize(Containers.Serialize(playerContainer(P))), tonumber(P.PlayerData.slots) or LXRCore.Config.Player.maxSlots, tonumber(P.PlayerData.weight) or LXRCore.Config.Player.maxWeight, 'probe')
        for _, it in pairs(tr.esc[other].items) do
            if it and not Containers.Add(probe, it.name, it.amount, it.info) then
                tr.ok = {}
                notify(s, 'error.trade_cannot_carry') notify(other, 'error.trade_partner_full')
                tradeRefresh(tr) return
            end
        end
    end
    -- the swap
    for _, s in ipairs({ tr.a, tr.b }) do
        local P = s == tr.a and A or B
        local other = partnerOf(tr, s)
        local mine = playerContainer(P)
        for slot, it in pairs(tr.esc[other].items) do
            if it then Containers.Add(mine, it.name, it.amount, it.info) tr.esc[other].items[slot] = nil end
        end
        local give = tr.money[s] or 0
        if give > 0 then P.Functions.RemoveMoney(acct, give, 'trade:' .. tr.id) end
        local get = tr.money[other] or 0
        if get > 0 then P.Functions.AddMoney(acct, get, 'trade:' .. tr.id) end
    end
    LXRCore.Log.info('inventory', 'trade settled', { a = tr.a, b = tr.b, moneyA = tr.money[tr.a], moneyB = tr.money[tr.b] })
    LXRCore.Emit('lxr:inventory:traded', nil, tr.a, tr.b)
    trades[tr.id] = nil
    for _, s in ipairs({ tr.a, tr.b }) do
        tradeOf[s] = nil
        if sessions[s] and sessions[s].kind == 'trade' then sessions[s] = nil TriggerClientEvent('lxr-inventory:client:close', s) end
        notify(s, 'info.trade_done', 'success')
        local P = s == tr.a and A or B
        P.Functions.UpdatePlayerData()
    end
end
local function startTrade(a, b)
    tradeSeq = tradeSeq + 1
    local id = tradeSeq
    local A, B = LXRCore.Functions.GetPlayer(a), LXRCore.Functions.GetPlayer(b)
    if not A or not B then return end
    local function esc(s) return Containers.New('trade-' .. id .. '-' .. s, 'trade', {}, Config.Trade.slots, Config.Trade.maxWeight, Lang:t('ui.your_offer'), { owner = s }) end
    local tr = { id = id, a = a, b = b, esc = { [a] = esc(a), [b] = esc(b) }, money = {}, ok = {}, at = os.time(), cid = { [a] = A.PlayerData.citizenid, [b] = B.PlayerData.citizenid } }
    trades[id] = tr
    tradeOf[a], tradeOf[b] = id, id
    for _, s in ipairs({ a, b }) do
        if sessions[s] then close(s) end
        local P = s == a and A or B
        local other = partnerOf(tr, s)
        local anchorPed = GetPlayerPed(other)
        sessions[s] = { other = tr.esc[s], otherId = tr.esc[s].id, kind = 'trade', anchor = anchorPed ~= 0 and GetEntityCoords(anchorPed) or nil, range = Config.Trade.distance + 1.0, moves = 0, trade = id }
        local view = Containers.View(tr.esc[s]); view.trade = tradeInfo(tr, s)
        TriggerClientEvent('lxr-inventory:client:open', s, Containers.View(playerContainer(P)), view, nil)
    end
    LXRCore.Log.info('inventory', 'trade started', { a = a, b = b })
end
local function tradeRequest(src, target)
    if not Config.Trade.enabled then return end
    local P, T = LXRCore.Functions.GetPlayer(src), LXRCore.Functions.GetPlayer(tonumber(target))
    if not P or not T or T == P then return notify(src, 'error.nobody_nearby') end
    if blocked(src, P, false) then return end
    if tradeOf[src] or tradeOf[T.PlayerData.source] then return notify(src, 'error.trade_busy') end
    if not within(src, T.PlayerData.source, Config.Trade.distance) then return notify(src, 'error.too_far') end
    local ts = T.PlayerData.source
    if invites[ts] and os.time() - invites[ts].at < Config.Trade.requestMs / 1000 then return notify(src, 'error.trade_busy') end
    invites[ts] = { from = src, at = os.time() }
    TriggerClientEvent('lxr-inventory:client:tradeRequest', ts, src, tradeName(src), Config.Trade.requestMs)
    notify(src, 'info.trade_sent')
end
RegisterNetEvent('lxr-inventory:server:tradeRequest', function(target) local src = source if limited(src) then return end tradeRequest(src, target) end)
RegisterNetEvent('lxr-inventory:server:tradeAnswer', function(yes)
    local src = source
    if limited(src) then return end
    local inv = invites[src]
    invites[src] = nil
    if not inv then return end
    if os.time() - inv.at > Config.Trade.requestMs / 1000 then return end
    if not yes then return notify(inv.from, 'info.trade_declined') end
    if tradeOf[src] or tradeOf[inv.from] then return end
    if not LXRCore.Functions.GetPlayer(inv.from) or not within(src, inv.from, Config.Trade.distance) then return notify(src, 'error.too_far') end
    startTrade(inv.from, src)
end)
RegisterNetEvent('lxr-inventory:server:tradeMoney', function(amount)
    local src = source
    if limited(src) then return end
    local tr = tradeOf[src] and trades[tradeOf[src]]
    if not tr then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 0 or amount > (Config.Trade.maxMoney or 10000) then return notify(src, 'error.invalid_amount') end
    local P = LXRCore.Functions.GetPlayer(src)
    if not P or amount > (P.PlayerData.money[Config.Trade.account or 'cash'] or 0) then return notify(src, 'error.not_enough_money') end
    tr.money[src] = amount
    tr.ok = {}
    tradeRefresh(tr)
end)
RegisterNetEvent('lxr-inventory:server:tradeConfirm', function()
    local src = source
    if limited(src) then return end
    local tr = tradeOf[src] and trades[tradeOf[src]]
    if not tr then return end
    if not within(tr.a, tr.b, Config.Trade.distance + 1.0) then return endTrade(tr, 'cancelled') end
    tr.ok[src] = not tr.ok[src]
    if tr.ok[tr.a] and tr.ok[tr.b] then return settleTrade(tr) end
    tradeRefresh(tr)
end)
RegisterNetEvent('lxr-inventory:server:tradeCancel', function()
    local src = source
    local tr = tradeOf[src] and trades[tradeOf[src]]
    if tr then endTrade(tr, 'cancelled') end
end)
AddEventHandler('lxr:player:dropped', function(P)
    local src = P and P.PlayerData and P.PlayerData.source
    local tr = src and tradeOf[src] and trades[tradeOf[src]]
    if tr then endTrade(tr, 'cancelled') end
end)
-- a return stash left by a trade that ended while its owner was gone is swept back on login
AddEventHandler('lxr:player:loaded', function(P)
    local cid = P and P.PlayerData and P.PlayerData.citizenid
    if not cid then return end
    local id = 'trade-return-' .. cid
    if not LXRCore.DB.Scalar(('SELECT stash FROM `%s` WHERE stash = ? LIMIT 1'):format(Config.Stash.table), { id }) then return end
    local st = getStash(id)
    local mine = playerContainer(P)
    for slot, it in pairs(st.items) do if it and Containers.Add(mine, it.name, it.amount, it.info) then st.items[slot] = nil end end
    st.dirty = true saveStash(st)
    P.Functions.UpdatePlayerData()
end)
exports('TradeRequest', tradeRequest)
LXRCore.Commands.Add(Config.Trade.command or 'trade', Lang:t('command.trade'), {}, false, function(src)
    TriggerClientEvent('lxr-inventory:client:tradeClosest', src)
end)

local function resolveOther(src, Player, kind, id, data)
    if kind == 'stash' then
        if type(id) ~= 'string' or id == '' or #id > 100 then return nil, 'invalid' end
        -- access rules supplied by the resource that owns the stash
        if type(data) == 'table' then
            local pd = Player.PlayerData
            local function inList(v, wanted)
                if type(wanted) == 'table' then
                    for _, w in ipairs(wanted) do if w == v then return true end end
                    return false
                end
                return wanted == nil or wanted == v
            end
            if data.owner ~= nil and not inList(pd.citizenid, data.owner) then return nil, 'no_permission' end
            if data.job ~= nil and not inList(pd.job.name, data.job) then return nil, 'no_permission' end
            if data.gang ~= nil and not inList(pd.gang.name, data.gang) then return nil, 'no_permission' end
            if data.jobGrade ~= nil and (pd.job.grade.level or 0) < tonumber(data.jobGrade) then return nil, 'no_permission' end
            if data.coords and distanceTo(src, data.coords) > (tonumber(data.distance) or Config.General.sessionRange) then return nil, 'too_far' end
        end
        local c = getStash(id, data)
        if type(data) == 'table' and data.coords then c.coords, c.distance = data.coords, tonumber(data.distance) end
        return c
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
            local cid = Player.PlayerData.citizenid
            if (dropsByOwner[cid] or 0) >= (Config.Drops.maxPerPlayer or 3) then return nil, 'too_many_drops' end
            if cooldown(lastDropCreate, src, Config.Drops.createCooldownMs or 3000) then return nil, 'too_fast' end
            d = createDrop({ x = coords.x, y = coords.y, z = coords.z }, cid)
            broadcastDrops()
        end
        return d
    elseif kind == 'shop' then
        if type(id) ~= 'string' then return nil, 'invalid' end
        local c = shops[id] or buildShop(id, data)
        if not c then return nil, 'invalid' end
        if c.coords and distanceTo(src, c.coords) > (c.distance or 3.0) then return nil, 'too_far' end
        return c
    elseif kind == 'trade' then
        local tr = tradeOf[src] and trades[tradeOf[src]]
        if not tr then return nil, 'invalid' end
        return tr.esc[src]
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

local function anchorFor(other)
    if not other then return nil, nil end
    if other.kind == 'drop' then return other.coords, Config.Drops.pickupRange + 1.0 end
    if other.kind == 'otherplayer' and other.player then
        local ped = GetPlayerPed(other.player.PlayerData.source)
        return ped ~= 0 and GetEntityCoords(ped) or nil, Config.General.searchDistance + 1.0
    end
    if other.coords then return other.coords, (other.distance or Config.General.sessionRange) + 1.0 end
    return nil, nil
end

local function finishOpen(src, Player, kind, id, data)
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
    local anchor, range = anchorFor(other)
    sessions[src] = { other = other, otherId = other and other.id or nil, kind = other and other.kind or nil, anchor = anchor, range = range, moves = 0 }
    TriggerClientEvent('lxr-inventory:client:open', src, Containers.View(playerContainer(Player)), other and Containers.View(other) or nil,
        anchor and { x = anchor.x, y = anchor.y, z = anchor.z, range = range } or nil)
end

local function open(src, kind, id, data)
    local Player = LXRCore.Functions.GetPlayer(src)
    if not Player then return end
    if blocked(src, Player, false) then return end
    if sessions[src] then close(src) end
    local delay = kind and (Config.General.openDelayMs[kind] or 0) or 0
    if delay <= 0 then return finishOpen(src, Player, kind, id, data) end

    -- validate now so the player is not shown a bar for something they cannot open
    local probe, err = resolveOther(src, Player, kind, id, data)
    if not probe then return notify(src, 'error.' .. (err or 'invalid')) end

    openToken = openToken + 1
    local token = openToken
    local startCoords = GetEntityCoords(GetPlayerPed(src))
    pendingOpen[src] = { token = token, kind = kind, id = id, data = data, coords = startCoords }
    TriggerClientEvent('lxr-inventory:client:progress', src, kind, delay)
    SetTimeout(delay, function()
        local p = pendingOpen[src]
        if not p or p.token ~= token then return end
        pendingOpen[src] = nil
        local P = LXRCore.Functions.GetPlayer(src)
        if not P then return end
        if distanceTo(src, startCoords) > (Config.General.cancelMoveDistance or 1.5) + 0.5 then
            TriggerClientEvent('lxr-inventory:client:progressCancel', src)
            return notify(src, 'error.cancelled')
        end
        finishOpen(src, P, kind, id, data)
    end)
end

close = function(src)
    pendingOpen[src] = nil
    local s = sessions[src]
    if not s then return end
    if s.kind == 'trade' then
        sessions[src] = nil
        local tr = tradeOf[src] and trades[tradeOf[src]]
        if tr then endTrade(tr, 'cancelled') end
        return
    end
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

refresh = function(src)
    local Player = LXRCore.Functions.GetPlayer(src)
    local s = sessions[src]
    if not Player then return end
    Player.Functions.UpdatePlayerData()
    local view = s and s.other and Containers.View(s.other) or nil
    if view and s.kind == 'trade' then
        local tr = trades[s.trade]
        if tr then view.trade = tradeInfo(tr, src) end
    end
    TriggerClientEvent('lxr-inventory:client:update', src, Containers.View(playerContainer(Player)), view)
    if s and s.other and s.other.kind == 'otherplayer' then
        local target = s.other.player
        if target then target.Functions.UpdatePlayerData() end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📡 EVENTS
-- ═══════════════════════════════════════════════════════════════════════════════

local function clientOpen(src, kind, id)
    if kind == nil or kind == 'player' then return open(src, nil) end
    if type(kind) ~= 'string' or not Config.Security.clientOpenKinds[kind] then
        return LXRCore.Log.exploit(src, 'client asked to open a restricted container kind', { kind = tostring(kind), id = tostring(id) })
    end
    if kind == 'shop' and not Config.Shops.registered[id] then
        return LXRCore.Log.exploit(src, 'client asked to open an unregistered shop', { id = tostring(id) })
    end
    open(src, kind, id, nil)
end

RegisterNetEvent('lxr-inventory:server:open', function(kind, id)
    local src = source
    if limited(src) then return end
    clientOpen(src, kind, id)
end)

RegisterNetEvent('lxr-inventory:server:cancelOpen', function()
    local src = source
    if pendingOpen[src] then
        pendingOpen[src] = nil
        TriggerClientEvent('lxr-inventory:client:progressCancel', src)
    end
end)

-- Server-side API for other resources: TriggerEvent('inventory:server:OpenInventory', 'stash', id, { label, slots, maxweight })
AddEventHandler('inventory:server:OpenInventory', function(kind, id, data)
    local src = source
    if not LXRCore.Players[src] then return end
    if kind == 'player' or kind == nil then return open(src, nil) end
    open(src, kind, id, data)
end)
-- net variant kept for legacy resources; same whitelist as the native client event
RegisterNetEvent('inventory:server:OpenInventory', function(kind, id)
    local src = source
    if limited(src) then return end
    clientOpen(src, kind, id)
end)

RegisterNetEvent('lxr-inventory:server:close', function()
    close(source)
end)

-- sort the satchel: hotbar slots keep their place, the rest is ordered by type then label
RegisterNetEvent('lxr-inventory:server:sort', function()
    local src = source
    if limited(src) then return end
    local Player = LXRCore.Functions.GetPlayer(src)
    if not Player or not sessions[src] or blocked(src, Player, false) then return end
    local pd = Player.PlayerData
    local hot = Config.Keys.hotbarSlots or 5
    local keep, rest = {}, {}
    for slot, it in pairs(pd.items or {}) do
        slot = tonumber(slot) or (it and it.slot)
        if slot and it then
            if slot <= hot then keep[slot] = it else rest[#rest + 1] = it end
        end
    end
    table.sort(rest, function(a, b)
        if (a.type or '') ~= (b.type or '') then return (a.type or '') < (b.type or '') end
        if (a.label or a.name) ~= (b.label or b.name) then return (a.label or a.name) < (b.label or b.name) end
        return (a.amount or 0) > (b.amount or 0)
    end)
    local items, slot = {}, hot + 1
    for k, it in pairs(keep) do it.slot = k items[k] = it end
    for _, it in ipairs(rest) do it.slot = slot items[slot] = it slot = slot + 1 end
    Player.Functions.SetPlayerData('items', items)
    refresh(src)
end)

RegisterNetEvent('lxr-inventory:server:move', function(fromKind, toKind, fromSlot, toSlot, amount)
    local src = source
    if limited(src) then return end
    local Player = LXRCore.Functions.GetPlayer(src)
    local s = sessions[src]
    if not Player then return end
    if not s then return notify(src, 'error.no_session') end   -- the page is up but the server has no session: reopen
    if blocked(src, Player, false) then return end
    if s.anchor and distanceTo(src, s.anchor) > (s.range or Config.General.sessionRange) then
        close(src)
        TriggerClientEvent('lxr-inventory:client:close', src)
        return notify(src, 'error.too_far')
    end
    if s.other and s.other.kind == 'otherplayer' and s.other.player then
        -- the searched player must still be searchable (not revived / uncuffed meanwhile)
        if not canSearch(Player, s.other.player) or not LXRCore.Players[s.other.player.PlayerData.source] then
            close(src)
            TriggerClientEvent('lxr-inventory:client:close', src)
            return notify(src, 'error.no_permission')
        end
    end
    s.moves = (s.moves or 0) + 1
    local mine = playerContainer(Player)
    local function pick(kind)
        if kind == 'player' then return mine end
        if kind == 'other' then return s.other end
        return nil
    end
    local from, to = pick(fromKind), pick(toKind)
    if not from or not to then return notify(src, 'error.invalid') end
    amount = tonumber(amount)
    if amount and amount > Config.Security.maxMoveAmount then return notify(src, 'error.invalid_amount') end

    -- shops: buying only, player → shop is not allowed
    if to.kind == 'shop' then return notify(src, 'error.cannot_store_here') end
    if from.kind == 'shop' then
        local entry = from.items[tonumber(fromSlot)]
        if not entry then return end
        amount = math.floor(amount or 1)
        if amount <= 0 or amount > entry.amount or amount > (Config.Shops.maxPerPurchase or 100) then return notify(src, 'error.invalid_amount') end
        if from.coords and distanceTo(src, from.coords) > (from.distance or 3.0) then return notify(src, 'error.too_far') end
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
    if s.kind == 'trade' then
        local tr = trades[s.trade]
        if tr then tr.ok = {} tradeRefresh(tr) end
    end
    if from.kind == 'stash' then from.dirty = true end
    if to.kind == 'stash' then to.dirty = true end
    if from ~= to then
        local moved = to.items[tonumber(toSlot)] or from.items[tonumber(fromSlot)]
        if Config.Security.logMoves then
            LXRCore.Log.info('inventory', ('%s %s -> %s'):format(action or 'move', from.kind, to.kind),
                { source = src, item = moved and moved.name, amount = amount, fromId = from.id, toId = to.id, move = s.moves })
        end
        if to.kind == 'otherplayer' and to.player then
            TriggerClientEvent('inventory:client:ItemBox', to.player.PlayerData.source, LXRShared.Items[moved.name], 'add', amount)
        end
        -- weapons leaving the satchel must leave the hands too (weapon resources listen)
        if moved and moved.type == 'weapon' and from.kind == 'player' then
            TriggerClientEvent('lxr-inventory:client:weaponRemoved', src, moved.name)
        end
        if moved and moved.type == 'weapon' and from.kind == 'otherplayer' and from.player then
            TriggerClientEvent('lxr-inventory:client:weaponRemoved', from.player.PlayerData.source, moved.name)
        end
    end
    refresh(src)
end)

-- shop purchase: client → server (NUI 'buy' callback), atomic money-then-item
RegisterNetEvent('lxr-inventory:server:buy', function(slot, amount)
    local src = source
    if limited(src) then return end
    local Player = LXRCore.Functions.GetPlayer(src)
    local s = sessions[src]
    if not Player or not s or not s.other or s.other.kind ~= 'shop' then return end
    slot, amount = tonumber(slot), math.floor(tonumber(amount) or 1)
    if slot <= 0 or amount <= 0 then return notify(src, 'error.invalid_amount') end
    local entry = s.other.items[slot]
    if not entry or entry.price <= 0 then return notify(src, 'error.invalid') end
    if amount > entry.amount or amount > (Config.Shops.maxPerPurchase or 100) then return notify(src, 'error.invalid_amount') end
    if s.anchor and distanceTo(src, s.anchor) > (s.range or Config.General.sessionRange) then
        close(src); TriggerClientEvent('lxr-inventory:client:close', src)
        return notify(src, 'error.too_far')
    end
    local mine = playerContainer(Player)
    local price = entry.price * amount
    local canSlot = Containers.CanPlace(mine, entry.name, amount, entry.info, nil)
    if price > 0 and not Player.Functions.RemoveMoney(nil, price, 'shop:' .. s.other.id) then
        return notify(src, 'error.not_enough_money')
    end
    local ok, why
    if canSlot then
        ok = Containers.PlaceAt(mine, entry.name, amount, entry.info, nil)
    else
        ok, why = Containers.Add(mine, entry.name, amount, entry.info)
    end
    if not ok then
        if price > 0 then Player.Functions.AddMoney(nil, price, 'shop:refund') end
        return notify(src, 'error.' .. (why or 'too_heavy'))
    end
    LXRCore.Log.info('inventory', ('bought %dx %s for %s'):format(amount, entry.name, price), { source = src, shop = s.other.id })
    TriggerClientEvent('inventory:client:ItemBox', src, LXRShared.Items[entry.name], 'add', amount)
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
    local def = LXRShared.Items[item.name] or {}
    local md = Player.PlayerData.metadata or {}
    if md.isdead and not def.useWhileDead then return notify(src, 'error.dead') end
    if md.ishandcuffed and not def.useWhileCuffed then return notify(src, 'error.cuffed') end
    if cooldown(lastUse, src, Config.General.useCooldownMs or 400) then return end
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
    if blocked(src, Player, false) then return end
    if cooldown(lastGive, src, Config.General.giveCooldownMs or 1500) then return notify(src, 'error.too_fast') end
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

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔁 TRANSFER — everything, or only what the other side already holds
-- ═══════════════════════════════════════════════════════════════════════════════
RegisterNetEvent('lxr-inventory:server:transfer', function(direction, mode)
    if sessions[source] and sessions[source].kind == 'trade' then
        local tr = trades[sessions[source].trade]
        if tr then SetTimeout(0, function() tr.ok = {} tradeRefresh(tr) end) end
    end
    local src = source
    if limited(src) then return end
    local Player = LXRCore.Functions.GetPlayer(src)
    local s = sessions[src]
    if not Player or not s or not s.other then return end
    if blocked(src, Player, false) then return end
    if s.other.kind == 'shop' then return notify(src, 'error.cannot_store_here') end
    if s.anchor and distanceTo(src, s.anchor) > (s.range or Config.General.sessionRange) then return notify(src, 'error.too_far') end
    local mine = playerContainer(Player)
    local from, to = mine, s.other
    if direction == 'take' then from, to = s.other, mine end
    if s.other.kind == 'otherplayer' and direction ~= 'take' then return notify(src, 'error.no_permission') end
    local has = {}
    for _, it in pairs(to.items) do if it then has[it.name] = true end end
    local moved, lines = 0, 0
    for slot = from.slots, 1, -1 do
        local it = from.items[slot]
        if it and (mode ~= 'matching' or has[it.name]) and not (it.type == 'weapon' and from.kind == 'player' and Player.PlayerData.metadata and Player.PlayerData.metadata.weaponInHand == it.name) then
            local ok = Containers.Add(to, it.name, it.amount, it.info)
            if ok then from.items[slot] = nil moved = moved + it.amount lines = lines + 1 end
        end
    end
    if lines == 0 then return notify(src, mode == 'matching' and 'error.nothing_matching' or 'error.nothing_to_move') end
    if from.kind == 'stash' then from.dirty = true end
    if to.kind == 'stash' then to.dirty = true end
    LXRCore.Log.info('inventory', ('transfer %s %s: %d items in %d lines'):format(direction, mode or 'all', moved, lines), { source = src, other = s.other.id })
    refresh(src)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🍂 DECAY — the catalog says what spoils into what; this is the clock
-- ═══════════════════════════════════════════════════════════════════════════════
local function sweepDecay(container, now)
    local changed = false
    for slot, it in pairs(container.items) do
        local def = it and LXRShared.Items[it.name]
        if def and def.decay and def.decay.hours then
            it.info = it.info or {}
            if not it.info.made then it.info.made = now changed = true
            elseif now - it.info.made > def.decay.hours * 3600 then
                local into = LXRShared.Items[def.decay.into]
                if into then
                    local amount = it.amount
                    container.items[slot] = nil
                    Containers.Add(container, into.name, amount, {})
                else container.items[slot] = nil end
                changed = true
            end
        end
    end
    return changed
end
if Config.Decay and Config.Decay.enabled then
    CreateThread(function()
        while true do
            Wait((Config.Decay.sweepMinutes or 5) * 60000)
            local now = os.time()
            for src, Player in pairs(LXRCore.Players) do
                local c = playerContainer(Player)
                if sweepDecay(c, now) then Player.Functions.UpdatePlayerData() if sessions[src] then refresh(src) end end
            end
            for _, c in pairs(stashes or {}) do if c and sweepDecay(c, now) then c.dirty = true end end
        end
    end)
end

AddEventHandler('playerDropped', function()
    close(source)
    buckets[source], lastUse[source], lastGive[source], lastDropCreate[source] = nil, nil, nil, nil
end)

AddEventHandler('lxr:player:unloaded', function(src) close(src) end)

-- Items changed by other resources (usable items, jobs, shops of other scripts) while the UI is open
AddEventHandler('lxr:inventory:changed', function(src)
    if sessions[src] then
        TriggerClientEvent('lxr-inventory:client:update', src, Containers.View(playerContainer(LXRCore.Functions.GetPlayer(src))), sessions[src].other and Containers.View(sessions[src].other) or nil)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for _, c in pairs(stashes) do if c.dirty then saveStash(c) end end
end)

-- Send current drops to late joiners
AddEventHandler('lxr:player:loaded', function(Player)
    local list = {}
    for id, d in pairs(drops) do list[#list + 1] = { id = id, coords = d.coords } end
    TriggerClientEvent('lxr-inventory:client:drops', Player.PlayerData.source, list)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🔌 EXPORTS & COMMANDS
-- ═══════════════════════════════════════════════════════════════════════════════

exports('OpenInventory', function(src, kind, id, data) open(src, kind, id, data) end)
exports('CloseInventory', function(src) close(src) TriggerClientEvent('lxr-inventory:client:close', src) end)
-- ── the item surface other scripts expect from an inventory (the names every RedM framework's scripts call);
--    thin wrappers over the core's inventory API, so a third-party script ports with a resource-name change
local Inv = LXRCore.Inventory
local function playerOf(src) return LXRCore.Functions.GetPlayer(tonumber(src)) end
exports('AddItem', function(src, name, amount, slot, info, reason) return Inv.AddItem(tonumber(src), name, amount, slot, info, reason or RES) end)
exports('RemoveItem', function(src, name, amount, slot, reason) return Inv.RemoveItem(tonumber(src), name, amount, slot, reason or RES) end)
exports('HasItem', function(src, items, amount) return Inv.HasItem(tonumber(src), items, amount) end)
exports('GetItemCount', function(src, name) return Inv.GetItemCount(tonumber(src), name) end)
exports('GetItemByName', function(src, name) return Inv.GetItem(tonumber(src), name) end)
exports('GetItemsByName', function(src, name)
    local out = {}
    for _, it in pairs(Inv.GetItems(tonumber(src)) or {}) do if it and it.name == name then out[#out + 1] = it end end
    return out
end)
exports('GetItemBySlot', function(src, slot) local P = playerOf(src) return P and P.PlayerData.items[tonumber(slot)] or nil end)
exports('GetInventory', function(src) return Inv.GetItems(tonumber(src)) end)
exports('CanAddItem', function(src, name, amount) return Inv.CanCarry(tonumber(src), name, amount) end)
exports('GetTotalWeight', function(src) local P = playerOf(src) return P and Inv.GetTotalWeight(P.PlayerData.items) or 0 end)
exports('GetFreeWeight', function(src) local P = playerOf(src) if not P then return 0 end return (tonumber(P.PlayerData.weight) or LXRCore.Config.Player.maxWeight) - Inv.GetTotalWeight(P.PlayerData.items) end)
exports('GetSlots', function(src) local P = playerOf(src) if not P then return 0, 0 end local used = 0 for _, it in pairs(P.PlayerData.items) do if it then used = used + 1 end end return used, (tonumber(P.PlayerData.slots) or LXRCore.Config.Player.maxSlots) - used end)
exports('GetSlotsByItem', function(src, name) local P = playerOf(src) return P and Inv.GetSlotsByItem(P.PlayerData.items, name) or {} end)
exports('GetFirstSlotByItem', function(src, name) local P = playerOf(src) return P and Inv.GetFirstSlotByItem(P.PlayerData.items, name) or nil end)
exports('SetItemData', function(src, slot, info) return Inv.SetMetadata(tonumber(src), tonumber(slot), info) end)
exports('ClearInventory', function(src, keep) return Inv.ClearInventory(tonumber(src), keep) end)
exports('UseItem', function(src, item) return LXRCore.Items.Use(tonumber(src), item) end)
exports('OpenInventoryById', function(src, target) open(tonumber(src), 'otherplayer', tonumber(target)) end)
exports('CreateInventory', function(id, data) return getStash(id, data) ~= nil end)
exports('DeleteInventory', function(id)
    local st = getStash(id)
    for k in pairs(st.items) do st.items[k] = nil end
    st.dirty = true saveStash(st) stashes[id] = nil
    return true
end)
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
