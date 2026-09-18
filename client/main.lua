--[[
    ██╗     ██╗  ██╗██████╗        ██╗███╗   ██╗██╗   ██╗███████╗███╗   ██╗████████╗ ██████╗ ██████╗ ██╗   ██╗
    ██║     ╚██╗██╔╝██╔══██╗       ██║████╗  ██║██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔══██╗╚██╗ ██╔╝
    ██║      ╚███╔╝ ██████╔╝█████╗ ██║██╔██╗ ██║██║   ██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║██████╔╝ ╚████╔╝
    ██║      ██╔██╗ ██╔══██╗╚════╝ ██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██╔══██╗  ╚██╔╝
    ███████╗██╔╝ ██╗██║  ██║       ██║██║ ╚████║ ╚████╔╝ ███████╗██║ ╚████║   ██║   ╚██████╔╝██║  ██║   ██║
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝       ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝

    🐺 LXR Core - Inventory Client

    Key bindings, NUI relay, item-box toasts, ground-drop markers and the
    animations. Every action is sent to the server as an intent; the UI is
    refreshed from the server's answer, never from a local guess.

    Developer:   iBoss21 / LXRCore
    Website:     https://www.lxrcore.com
    © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
]]

local LXRCore = exports['lxr-core']:GetCoreObject()

local isOpen = false
local dropList = {}      -- { { id, coords } }
local dropProps = {}     -- id → entity
local nearDrop = nil
local sessionAnchor = nil  -- { x, y, z, range } while another container is open
local progressActive = false

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🪟 OPEN / CLOSE
-- ═══════════════════════════════════════════════════════════════════════════════

local function setOpen(state)
    isOpen = state
    SetNuiFocus(state, state)
    if not state then
        sessionAnchor = nil
        SendNUIMessage({ action = 'close' })
    end
end

local function requestOpen()
    if isOpen or not LocalPlayer.state.isLoggedIn then return end
    if IsPauseMenuActive() then return end
    local pd = LXRCore.PlayerData or {}
    if pd.metadata and (pd.metadata.isdead or pd.metadata.ishandcuffed) then return end
    if nearDrop then
        TriggerServerEvent('lxr-inventory:server:open', 'drop', nearDrop)
    else
        TriggerServerEvent('lxr-inventory:server:open')
    end
end

-- what the character wears, for the centre panel (from the appearance engine when it runs)
local function wearing()
    if GetResourceState('lxr-clothing') ~= 'started' then return nil end
    local ok, w = pcall(function() return exports['lxr-clothing']:Wearing() end)
    return ok and w or nil
end

RegisterNetEvent('lxr-inventory:client:open', function(player, other, anchor)
    isOpen = true
    progressActive = false
    sessionAnchor = anchor
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', player = player, other = other, locale = Lang.bundle(), lang = Config.Lang, hotbar = Config.Keys.hotbarSlots, brand = LXRCore.Brand, wearing = wearing() })
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- ⏳ OPENING PROGRESS (server-timed; the bar here is cosmetic, the server decides)
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNetEvent('lxr-inventory:client:progress', function(kind, duration)
    progressActive = true
    local label = Lang:t('progress.' .. kind) or Lang:t('progress.default')
    local anim = Config.Progress.animations[kind] or Config.Progress.animations.default
    LXRCore.Functions.Progressbar('lxr_inventory_open', label, duration, false, true,
        Config.Progress.disableControls, anim, {}, {},
        function() end,
        function()
            if progressActive then
                progressActive = false
                TriggerServerEvent('lxr-inventory:server:cancelOpen')
            end
        end)
    -- moving away cancels locally as well (the server checks distance independently)
    local start = GetEntityCoords(PlayerPedId())
    CreateThread(function()
        while progressActive do
            Wait(150)
            if #(GetEntityCoords(PlayerPedId()) - start) > Config.General.cancelMoveDistance then
                progressActive = false
                TriggerServerEvent('lxr-inventory:server:cancelOpen')
                if GetResourceState('progressbar') == 'started' then exports['progressbar']:Cancel() end
                break
            end
        end
    end)
end)

RegisterNetEvent('lxr-inventory:client:progressCancel', function()
    progressActive = false
    if GetResourceState('progressbar') == 'started' then pcall(function() exports['progressbar']:Cancel() end) end
end)

-- walk-away closes the UI (the server closes the session on its side on the next move anyway)
CreateThread(function()
    while true do
        Wait(500)
        if isOpen and sessionAnchor then
            local d = #(GetEntityCoords(PlayerPedId()) - vector3(sessionAnchor.x, sessionAnchor.y, sessionAnchor.z))
            if d > (sessionAnchor.range or Config.General.sessionRange) then
                setOpen(false)
                TriggerServerEvent('lxr-inventory:server:close')
            end
        end
    end
end)

-- weapon removed from the satchel while equipped → drop it from the hands too
RegisterNetEvent('lxr-inventory:client:weaponRemoved', function(name)
    local ped = PlayerPedId()
    local hash = joaat(name)
    if HasPedGotWeapon(ped, hash, 0, false) then RemoveWeaponFromPed(ped, hash, true, 0) end
    TriggerEvent('lxr-weapons:client:removed', name)
end)

RegisterNetEvent('lxr-inventory:client:update', function(player, other)
    if not isOpen then return end
    SendNUIMessage({ action = 'update', player = player, other = other })
end)

RegisterNetEvent('lxr-inventory:client:otherClosed', function()
    if isOpen then SendNUIMessage({ action = 'update', other = false }) end
end)

RegisterNetEvent('lxr-inventory:client:close', function()
    if isOpen then setOpen(false) end
end)

-- Legacy names other resources use
RegisterNetEvent('inventory:client:closeinv', function() if isOpen then setOpen(false) TriggerServerEvent('lxr-inventory:server:close') end end)
RegisterNetEvent('lxr-inventory:client:UpdateItems', function() end) -- core fires this; the NUI refreshes from server views

RegisterKeyMapping('inventory', 'Open inventory', 'keyboard', Config.Keys.open)
RegisterCommand('inventory', requestOpen, false)

for i = 1, Config.Keys.hotbarSlots do
    RegisterKeyMapping('inventory_slot' .. i, ('Use hotbar slot %d'):format(i), 'keyboard', Config.Keys.hotbar[i] or tostring(i))
    RegisterCommand('inventory_slot' .. i, function()
        if isOpen or not LocalPlayer.state.isLoggedIn then return end
        TriggerServerEvent('lxr-inventory:server:use', i)
    end, false)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🖱 NUI CALLBACKS — relay only
-- ═══════════════════════════════════════════════════════════════════════════════

RegisterNUICallback('close', function(_, cb)
    cb({})
    setOpen(false)
    TriggerServerEvent('lxr-inventory:server:close')
end)

RegisterNUICallback('move', function(data, cb)
    cb({})
    if not isOpen or type(data) ~= 'table' then return end
    TriggerServerEvent('lxr-inventory:server:move', data.from, data.to, tonumber(data.fromSlot), tonumber(data.toSlot), tonumber(data.amount))
end)

RegisterNUICallback('use', function(data, cb)
    cb({})
    if not isOpen or type(data) ~= 'table' then return end
    TriggerServerEvent('lxr-inventory:server:use', tonumber(data.slot))
end)

RegisterNUICallback('drop', function(data, cb)
    cb({})
    if not isOpen or type(data) ~= 'table' then return end
    -- opens (or creates) the ground container next to the player, then the NUI moves into it
    TriggerServerEvent('lxr-inventory:server:open', 'ground')
end)

RegisterNUICallback('sort', function(_, cb)
    cb({})
    if isOpen then TriggerServerEvent('lxr-inventory:server:sort') end
end)

-- put on / take off a worn category (visual only; the record stays as bought)
RegisterNUICallback('wear', function(data, cb)
    cb({})
    if not isOpen or type(data) ~= 'table' or GetResourceState('lxr-clothing') ~= 'started' then return end
    pcall(function() exports['lxr-clothing']:ToggleCategory(data.cat, data.hidden and true or false) end)
    SendNUIMessage({ action = 'update', wearing = wearing() })
end)

RegisterNUICallback('give', function(data, cb)
    cb({})
    if not isOpen or type(data) ~= 'table' then return end
    local player, dist = LXRCore.Functions.GetClosestPlayer()
    if player == -1 or dist > Config.General.giveDistance then
        return LXRCore.Functions.Notify(Lang:t('error.nobody_nearby'), 'error')
    end
    TriggerServerEvent('lxr-inventory:server:give', GetPlayerServerId(player), tonumber(data.slot), tonumber(data.amount))
end)

RegisterNUICallback('buy', function(data, cb)
    cb({})
    if not isOpen or type(data) ~= 'table' then return end
    TriggerServerEvent('lxr-inventory:server:buy', tonumber(data.slot), tonumber(data.amount))
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎞 ANIMATIONS & TOASTS
-- ═══════════════════════════════════════════════════════════════════════════════

local function playAnim(def)
    if not def or not def.dict then return end
    if not LXRCore.Functions.RequestAnimDict(def.dict) then return end
    TaskPlayAnim(PlayerPedId(), def.dict, def.anim, 8.0, -8.0, def.durationMs or 800, 48, 0, false, false, false)
end

RegisterNetEvent('lxr-inventory:client:useAnim', function() playAnim(Config.General.useAnimation) end)
RegisterNetEvent('lxr-inventory:client:giveAnim', function() playAnim(Config.General.dropAnimation) end)
RegisterNetEvent('inventory:client:DropItemAnim', function() playAnim(Config.General.dropAnimation) end)

RegisterNetEvent('inventory:client:ItemBox', function(item, kind, amount)
    if type(item) ~= 'table' then return end
    SendNUIMessage({ action = 'itembox', item = { name = item.name, label = item.label, image = item.image }, kind = kind, amount = amount or 1 })
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🪵 GROUND DROPS — cheap proximity check, per-frame only when close
-- ═══════════════════════════════════════════════════════════════════════════════

local function clearProps()
    for _, ent in pairs(dropProps) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
    dropProps = {}
end

RegisterNetEvent('lxr-inventory:client:drops', function(list)
    dropList = type(list) == 'table' and list or {}
    local keep = {}
    for _, d in ipairs(dropList) do
        keep[d.id] = true
        if Config.Drops.prop and not dropProps[d.id] then
            local hash = joaat(Config.Drops.prop)
            if LXRCore.Functions.LoadModel(hash) then
                local ent = CreateObject(hash, d.coords.x, d.coords.y, d.coords.z - 0.9, false, false, false)
                PlaceObjectOnGroundProperly(ent)
                FreezeEntityPosition(ent, true)
                SetModelAsNoLongerNeeded(hash)
                dropProps[d.id] = ent
            end
        end
    end
    for id, ent in pairs(dropProps) do
        if not keep[id] then
            if DoesEntityExist(ent) then DeleteEntity(ent) end
            dropProps[id] = nil
        end
    end
end)

CreateThread(function()
    while true do
        if #dropList == 0 then
            nearDrop = nil
            Wait(1000)
        else
            local pos = GetEntityCoords(PlayerPedId())
            local best, bestDist
            for _, d in ipairs(dropList) do
                local dist = #(pos - vector3(d.coords.x, d.coords.y, d.coords.z))
                if dist <= Config.Drops.pickupRange and (not bestDist or dist < bestDist) then best, bestDist = d, dist end
            end
            nearDrop = best and best.id or nil
            if best then
                local m = Config.Drops.marker
                local until_ = GetGameTimer() + 500
                while GetGameTimer() < until_ do
                    DrawMarker(0x94FDAE17, best.coords.x, best.coords.y, best.coords.z - 0.6, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5, m.r, m.g, m.b, m.a, false, false, 2, false, nil, nil, false)
                    Wait(0)
                end
            else
                Wait(500)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isOpen then setOpen(false) end
    clearProps()
end)

AddEventHandler('LXRCore:Client:OnPlayerUnload', function()
    if isOpen then setOpen(false) end
end)
