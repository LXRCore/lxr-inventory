--[[ ═══════════════════════════════════════════════════════════════════════════
     🐺 LXR-INVENTORY — Offline tests for the container move engine
     Requires a sibling checkout of lxr-core (../lxr-core) for the runtime shim.
     Usage (from the lxr-inventory folder):  lua tests/run.lua
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

local CORE = os.getenv('LXR_CORE_PATH') or '../lxr-core'
package.path = CORE .. '/?.lua;' .. package.path
local cwd = io.popen('cd'):read('l') or '.'
local ok = pcall(function() require('tests.lib.fxshim') end)
if not ok then
    print('lxr-core shim not found at ' .. CORE .. ' (set LXR_CORE_PATH)')
    os.exit(2)
end
local Shim = require('tests.lib.fxshim')

-- load core shared data for item definitions
for _, f in ipairs({ 'shared/main.lua', 'shared/locale.lua', 'locales/en.lua', 'config.lua', 'shared/catalog.lua', 'shared/items.lua', 'shared/prices.lua' }) do
    Shim.load(CORE .. '/' .. f)
end
Shim.load('server/containers.lua')

local passed, failed = 0, 0
local function test(name, fn)
    local okT, err = xpcall(fn, debug.traceback)
    if okT then passed = passed + 1 print('  ^ ok   ' .. name) else failed = failed + 1 print('  x FAIL ' .. name .. '\n' .. err) end
end
local function eq(a, b, msg) if a ~= b then error((msg or 'eq') .. ': expected ' .. tostring(b) .. ' got ' .. tostring(a), 2) end end

local function container(slots, weight) return Containers.New('c', 'stash', {}, slots or 5, weight or 5000) end

test('Add stacks, respects weight and slots', function()
    local c = container(2, 1000)
    eq(Containers.Add(c, 'bread', 2), true)
    eq(Containers.Add(c, 'bread', 2), true)
    eq(Containers.Count(c, 'bread'), 4)
    eq(select(2, Containers.Add(c, 'pickaxe', 1)), 'too_heavy')
    eq(Containers.Add(c, 'water', 1), true)
    eq(select(2, Containers.Add(c, 'apple', 1)), 'too_heavy', 'no free slot reported as too_heavy')
end)

test('Move within a container: move, stack, split, swap', function()
    local c = container(4, 100000)
    Containers.Add(c, 'bread', 5)      -- slot 1
    Containers.Add(c, 'water', 3)      -- slot 2
    eq(Containers.Move(c, c, 1, 3, 2), true, 'split')
    eq(c.items[1].amount, 3)
    eq(c.items[3].amount, 2)
    eq(Containers.Move(c, c, 3, 1), true, 'stack back')
    eq(c.items[1].amount, 5)
    eq(c.items[3], nil)
    local okS, _, action = Containers.Move(c, c, 1, 2)
    eq(okS, true, 'swap')
    eq(action, 'swap')
    eq(c.items[1].name, 'water')
    eq(c.items[2].name, 'bread')
    eq(c.items[1].slot, 1)
    eq(select(2, Containers.Move(c, c, 1, 2, 1)), 'slot_occupied', 'partial onto different item')
end)

test('Move between containers validates destination weight and never loses items', function()
    local a, b = container(5, 100000), container(5, 250)
    Containers.Add(a, 'bread', 3) -- 200 g each
    local okM, why = Containers.Move(a, b, 1, 1, 2)
    eq(okM, false)
    eq(why, 'too_heavy')
    eq(a.items[1].amount, 3, 'source untouched on failure')
    eq(Containers.Move(a, b, 1, 1, 1), true)
    eq(a.items[1].amount, 2)
    eq(b.items[1].amount, 1)
end)

test('unique items never stack; metadata mismatch blocks stacking', function()
    local c = container(5, 100000)
    Containers.Add(c, 'id_card', 1)
    Containers.Add(c, 'id_card', 1)
    eq(c.items[1].amount, 1)
    eq(c.items[2].amount, 1)
    eq(select(2, Containers.Move(c, c, 1, 2)), nil, 'swap of two uniques allowed')
    local d = container(5, 100000)
    Containers.Add(d, 'water', 2, { quality = 50 })
    Containers.Add(d, 'water', 1, { quality = 90 })
    eq(d.items[2] ~= nil, true, 'different metadata → separate slots')
    eq(select(2, Containers.Move(d, d, 1, 2, 1)), 'slot_occupied', 'partial move onto different metadata blocked')
    local okSwap, _, act = Containers.Move(d, d, 1, 2)
    eq(okSwap, true, 'whole stacks swap')
    eq(act, 'swap')
end)

test('swap refused when it would overweight the source side', function()
    local a, b = container(3, 300), container(3, 100000)
    Containers.Add(a, 'bread', 1)   -- 200 g
    Containers.Add(b, 'pickaxe', 1) -- 2000 g
    local okS, why = Containers.Move(b, a, 1, 1)
    eq(okS, false)
    eq(why, 'too_heavy')
    eq(a.items[1].name, 'bread')
    eq(b.items[1].name, 'pickaxe')
end)

test('Serialize / Deserialize round trip', function()
    local c = container(5, 100000)
    Containers.Add(c, 'bread', 2)
    Containers.Add(c, 'water', 1, { quality = 40 })
    local rows = Containers.Serialize(c)
    local back = Containers.Deserialize(rows)
    eq(back[1].amount, 2)
    eq(back[2].info.quality, 40)
    eq(#Containers.View(c).items, 2)
end)

test('invalid slots and amounts are rejected', function()
    local c = container(3, 100000)
    Containers.Add(c, 'bread', 2)
    eq(select(2, Containers.Move(c, c, 1, 9)), 'invalid_slot')
    eq(select(2, Containers.Move(c, c, 1, 2, 0)), 'invalid_amount')
    eq(select(2, Containers.Move(c, c, 1, 2, 5)), 'invalid_amount')
    eq(select(2, Containers.Move(c, c, 2, 1)), 'not_owned')
    eq(select(2, Containers.CanPlace(c, 'bread', 1, nil, 1.5)), 'invalid_slot')
end)

print(('\n%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
