--[[
    ██╗     ██╗  ██╗██████╗        ██╗███╗   ██╗██╗   ██╗███████╗███╗   ██╗████████╗ ██████╗ ██████╗ ██╗   ██╗
    ██║     ╚██╗██╔╝██╔══██╗       ██║████╗  ██║██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔══██╗╚██╗ ██╔╝
    ██║      ╚███╔╝ ██████╔╝█████╗ ██║██╔██╗ ██║██║   ██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║██████╔╝ ╚████╔╝
    ██║      ██╔██╗ ██╔══██╗╚════╝ ██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██╔══██╗  ╚██╔╝
    ███████╗██╔╝ ██╗██║  ██║       ██║██║ ╚████║ ╚████╔╝ ███████╗██║ ╚████║   ██║   ╚██████╔╝██║  ██║   ██║
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝       ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝

    🐺 LXR Core - Inventory Configuration

    Keys, container limits, drops, shops and security rules. Player weight and
    slot limits come from lxr-core (Config.Player.maxWeight / maxSlots).

    ═══════════════════════════════════════════════════════════════════════════════
    SERVER INFORMATION
    ═══════════════════════════════════════════════════════════════════════════════

    Brand:       LXRCore — Lux Empire eXperience RedM Core
    Product:     wolves.land / The Land of Wolves 🐺
    Developer:   iBoss21 / LXRCore
    Website:     https://www.lxrcore.com
    Discord:     https://discord.gg/ZHMKVYyhBa (development)
    GitHub:      https://github.com/LXRCore

    Version: 2.0.0 · Framework Support: LXR Core v3 (Native)
    © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
]]

Config = Config or {}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ SERVER BRANDING & INFO ████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.ServerInfo = { name = 'The Land of Wolves' }

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ LANGUAGE CONFIGURATION ████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.Lang = 'en'

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ KEYS CONFIGURATION ████████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.Keys = {
    open    = 'TAB',   -- RegisterKeyMapping default (players can rebind in settings)
    hotbar  = { '1', '2', '3', '4', '5' }, -- keys for hotbar slots 1..5
    hotbarSlots = 5,
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ GENERAL SETTINGS ██████████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.General = {
    giveDistance    = 2.5,   -- Max distance to give an item to another player (metres)
    searchDistance  = 2.0,   -- Max distance to search / rob another player
    searchRequires  = { leoOnDuty = true, targetCuffed = true, targetDead = true }, -- any of these unlocks searching
    closeOnUse      = true,  -- Close the UI when a usable item with shouldClose is used
    useAnimation    = { dict = 'mech_inspection@weapons@longarms@shotgun_break', anim = 'base', durationMs = 800 }, -- nil = none
    dropAnimation   = { dict = 'mech_pickup@ground', anim = 'putdown_low', durationMs = 900 },
    saveOnClose     = true,  -- Persist the player's inventory when the UI closes (core saves periodically anyway)
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ CONTAINERS ████████████████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.Stash = {
    defaultSlots  = 40,
    defaultWeight = 400000,  -- grams
    table         = 'stashitems',
    -- Prefix-based defaults so resources can open stashes without registering them first
    presets = {
        ['stash_house_'] = { slots = 60, weight = 600000 },
        ['stash_job_']   = { slots = 80, weight = 1000000 },
    },
}

Config.Drops = {
    slots        = 30,
    weight       = 200000,
    expireMs     = 20 * 60000,  -- Empty drops vanish immediately; non-empty after this
    pickupRange  = 2.0,
    marker       = { r = 196, g = 165, b = 116, a = 140 },
    prop         = 'p_sack01x', -- Prop spawned at the drop (nil = marker only)
}

Config.Shops = {
    -- Shops are opened by other resources through
    --   TriggerEvent('inventory:server:OpenInventory', 'shop', 'valentine_general', { label = 'General Store', items = {...} })
    -- or registered here and opened with the id only.
    registered = {
        general_valentine = {
            label = 'Valentine General Store',
            items = {
                { name = 'bread', price = 1, amount = 50 },
                { name = 'water', price = 1, amount = 50 },
                { name = 'coffee', price = 2, amount = 30 },
                { name = 'bandage', price = 3, amount = 20 },
                { name = 'lantern', price = 8, amount = 5 },
            },
        },
    },
    account = 'cash',
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ SECURITY & ANTI-ABUSE █████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.Security = {
    rateLimit     = { burst = 40, windowMs = 5000 },
    maxMoveAmount = 10000,
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ DEBUG SETTINGS ████████████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.Debug = false

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ END OF CONFIGURATION ██████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████
