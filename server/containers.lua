--[[
    ██╗     ██╗  ██╗██████╗        ██╗███╗   ██╗██╗   ██╗███████╗███╗   ██╗████████╗ ██████╗ ██████╗ ██╗   ██╗
    ██║     ╚██╗██╔╝██╔══██╗       ██║████╗  ██║██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔══██╗╚██╗ ██╔╝
    ██║      ╚███╔╝ ██████╔╝█████╗ ██║██╔██╗ ██║██║   ██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║██████╔╝ ╚████╔╝
    ██║      ██╔██╗ ██╔══██╗╚════╝ ██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██╔══██╗  ╚██╔╝
    ███████╗██╔╝ ██╗██║  ██║       ██║██║ ╚████║ ╚████╔╝ ███████╗██║ ╚████║   ██║   ╚██████╔╝██║  ██║   ██║
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝       ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝

    🐺 LXR Core - Inventory Containers & Move Engine (server)

    A container is { id, kind, items, slots, maxWeight, label }. Player
    containers point at the live PlayerData.items table from lxr-core, so the
    core's save pipeline persists them. Stashes and drops are owned here.

    Containers.Move(from, to, fromSlot, toSlot, amount) validates the whole
    operation first (ownership of the slot, amount, weight and slot limits on
    the destination, swap feasibility) and only then mutates both tables.
    Nothing is ever removed without its destination guaranteed.

    Developer:   iBoss21 / LXRCore
    Website:     https://www.lxrcore.com
    © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
]]

Containers = {}

local function itemDef(name)
    return LXRShared and LXRShared.Items and LXRShared.Items[tostring(name):lower()]
end

local function weightOf(items)
    local w = 0
    for _, it in pairs(items) do
        if it then w = w + (tonumber(it.weight) or 0) * (tonumber(it.amount) or 0) end
    end
    return w
end
Containers.Weight = weightOf

local function slotItem(def, amount, slot, info)
    return {
        name = def.name, amount = amount, info = info or {}, label = def.label,
        description = def.description or '', weight = def.weight, type = def.type,
        unique = def.unique, useable = def.useable, image = def.image,
        shouldClose = def.shouldClose, slot = slot, combinable = def.combinable,
    }
end

---Build a container view over an items table.
function Containers.New(id, kind, items, slots, maxWeight, label, extra)
    local c = { id = id, kind = kind, items = items, slots = slots, maxWeight = maxWeight, label = label or id }
    if extra then for k, v in pairs(extra) do c[k] = v end end
    return c
end

---Can `amount` of `name` (with `info`) be placed into `container` at `slot`?
---Returns ok, reason. Ignores the item currently at `ignoreSlot` (used for swaps).
function Containers.CanPlace(container, name, amount, info, slot, ignoreSlot, ignoreAmount)
    local def = itemDef(name)
    if not def then return false, 'item_not_exist' end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end
    slot = tonumber(slot)
    if not slot or slot < 1 or slot > container.slots or slot % 1 ~= 0 then return false, 'invalid_slot' end

    local current = weightOf(container.items)
    if ignoreSlot and container.items[ignoreSlot] then
        local ig = container.items[ignoreSlot]
        current = current - (tonumber(ig.weight) or 0) * (ignoreAmount or ig.amount)
    end
    if current + (def.weight or 0) * amount > container.maxWeight then return false, 'too_heavy' end

    local existing = container.items[slot]
    if existing and slot ~= ignoreSlot then
        if existing.name ~= def.name or def.unique then return false, 'slot_occupied' end
        -- stacking: metadata must match for stackable items with info
        if json.encode(existing.info or {}) ~= json.encode(info or {}) then return false, 'slot_occupied' end
    end
    return true
end

---Place items into a slot (caller must have called CanPlace).
local function place(container, name, amount, info, slot)
    local def = itemDef(name)
    local existing = container.items[slot]
    if existing and existing.name == def.name then
        existing.amount = existing.amount + amount
    else
        container.items[slot] = slotItem(def, amount, slot, info)
    end
end

local function take(container, slot, amount)
    local it = container.items[slot]
    it.amount = it.amount - amount
    if it.amount <= 0 then container.items[slot] = nil end
end

---Place directly into a slot after a successful CanPlace (used for shop purchases).
function Containers.PlaceAt(container, name, amount, info, slot)
    place(container, name, amount, info, tonumber(slot))
    return true
end

---Move `amount` from `from[fromSlot]` to `to[toSlot]`. Same container allowed.
---When the destination holds a different item and the full stack is moved,
---the two stacks are swapped (only if the swap fits on both sides).
---@return boolean ok, string|nil reason, string|nil action ('move'|'stack'|'swap')
function Containers.Move(from, to, fromSlot, toSlot, amount)
    fromSlot, toSlot = tonumber(fromSlot), tonumber(toSlot)
    if not fromSlot or not toSlot then return false, 'invalid_slot' end
    local src = from.items[fromSlot]
    if not src then return false, 'not_owned' end
    amount = math.floor(tonumber(amount) or src.amount)
    if amount <= 0 or amount > src.amount then return false, 'invalid_amount' end
    if from == to and fromSlot == toSlot then return true, nil, 'noop' end

    local dst = to.items[toSlot]
    local sameContainer = from == to

    -- 1. plain move / stack
    if not dst or (dst.name == src.name and not src.unique and json.encode(dst.info or {}) == json.encode(src.info or {})) then
        local ok, why = Containers.CanPlace(to, src.name, amount, src.info, toSlot, sameContainer and fromSlot or nil, sameContainer and amount or nil)
        if not ok then return false, why end
        take(from, fromSlot, amount)
        place(to, src.name, amount, src.info, toSlot)
        return true, nil, dst and 'stack' or 'move'
    end

    -- 2. swap: only whole stacks
    if amount ~= src.amount then return false, 'slot_occupied' end
    local dstAmount = dst.amount
    -- destination must fit src (ignoring dst), source must fit dst (ignoring src)
    local okA, whyA = Containers.CanPlace(to, src.name, amount, src.info, toSlot, toSlot, dstAmount)
    if not okA then return false, whyA end
    local okB, whyB = Containers.CanPlace(from, dst.name, dstAmount, dst.info, fromSlot, fromSlot, amount)
    if not okB then return false, whyB end
    local srcCopy, dstCopy = from.items[fromSlot], to.items[toSlot]
    from.items[fromSlot], to.items[toSlot] = nil, nil
    dstCopy.slot, srcCopy.slot = fromSlot, toSlot
    from.items[fromSlot] = dstCopy
    to.items[toSlot] = srcCopy
    return true, nil, 'swap'
end

---Add `amount` of `name` anywhere in the container (stack first, then free slot).
function Containers.Add(container, name, amount, info)
    local def = itemDef(name)
    if not def then return false, 'item_not_exist' end
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'invalid_amount' end
    if weightOf(container.items) + (def.weight or 0) * amount > container.maxWeight then return false, 'too_heavy' end
    if not def.unique then
        for slot, it in pairs(container.items) do
            if it.name == def.name and json.encode(it.info or {}) == json.encode(info or {}) then
                it.amount = it.amount + amount
                return true, nil, slot
            end
        end
    end
    for slot = 1, container.slots do
        if not container.items[slot] then
            container.items[slot] = slotItem(def, amount, slot, info)
            return true, nil, slot
        end
    end
    return false, 'too_heavy'
end

function Containers.Count(container, name)
    local n = 0
    for _, it in pairs(container.items) do if it.name == name then n = n + it.amount end end
    return n
end

function Containers.IsEmpty(container)
    return next(container.items) == nil
end

---Serialise for storage / NUI (array of slot items).
function Containers.Serialize(container)
    local out = {}
    for slot, it in pairs(container.items) do
        if it and it.amount > 0 then
            out[#out + 1] = { name = it.name, amount = it.amount, info = it.info or {}, type = it.type, slot = slot }
        end
    end
    return out
end

---Rebuild slot items from stored rows (unknown items dropped).
function Containers.Deserialize(rows)
    local items = {}
    for _, r in ipairs(rows or {}) do
        local def = r and r.name and itemDef(r.name)
        local slot = tonumber(r.slot)
        if def and slot then
            items[slot] = slotItem(def, tonumber(r.amount) or 1, slot, type(r.info) == 'table' and r.info or {})
        end
    end
    return items
end

---Payload for the NUI: full item rows with labels, plus limits.
function Containers.View(container)
    local items = {}
    for slot, it in pairs(container.items) do
        if it then
            local def = itemDef(it.name)
            local fresh = nil
            if def and def.decay and def.decay.hours and it.info and it.info.made then
                fresh = math.max(0, math.min(1, 1 - (os.time() - it.info.made) / (def.decay.hours * 3600)))
            end
            items[#items + 1] = {
                slot = slot, name = it.name, label = it.label, amount = it.amount, weight = it.weight,
                info = it.info or {}, type = it.type, useable = it.useable, unique = it.unique,
                image = it.image, description = it.description, price = it.price,
                rarity = def and def.rarity or 'common', category = def and def.category or 'misc', legal = not (def and def.legal == false), fresh = fresh,
            }
        end
    end
    return {
        id = container.id, kind = container.kind, label = container.label,
        slots = container.slots, maxWeight = container.maxWeight, weight = weightOf(container.items),
        items = items,
    }
end
