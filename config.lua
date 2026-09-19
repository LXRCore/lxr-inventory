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
    Discord:     https://discord.gg/GAhk8cgXe9
    GitHub:      https://github.com/LXRCore

    Version: 2.0.0 · Framework Support: LXR Core v3 (Native)
    © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
]]

Config = Config or {}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ SERVER BRANDING & INFO ████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████


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

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ DECAY ═════════════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
-- The core catalog marks what spoils (`decay = { hours, into }`); this is the clock that runs it.
-- An item is stamped when first seen (`info.made`); past its hours it becomes `into` (spoiled food, ruined pelt).
Config.Decay = { enabled = true, sweepMinutes = 5 }

Config.General = {
    giveDistance    = 2.5,   -- Max distance to give an item to another player (metres)
    searchDistance  = 2.0,   -- Max distance to search / rob another player
    searchRequires  = { leoOnDuty = true, targetCuffed = true, targetDead = true }, -- any of these unlocks searching
    closeOnUse      = true,  -- Close the UI when a usable item with shouldClose is used
    useAnimation    = nil,   -- nil = none: each usable plays its own (consumables through lxr-hud with the item in hand)
    dropAnimation   = { dict = 'mech_pickup@ground', anim = 'putdown_low', durationMs = 900 },
    saveOnClose     = true,  -- Persist the player's inventory when the UI closes (core saves periodically anyway)
    -- Opening another container takes time (progress bar). The server re-checks distance when the
    -- timer ends and cancels if the player walked away. 0 = instant.
    openDelayMs     = { stash = 1200, drop = 700, ground = 0, shop = 0, otherplayer = 2500 },
    cancelMoveDistance = 1.5,  -- Moving further than this during the progress bar cancels the open
    sessionRange    = 3.0,     -- Max distance from the container (drop / other player / stash coords) while it is open; checked on every move
    useCooldownMs   = 400,     -- Minimum time between item uses per player
    giveCooldownMs  = 1500,    -- Minimum time between gifts per player
    blockWhenDead   = true,    -- No open / move / use / give while metadata.isdead
    blockWhenCuffed = true,    -- Same for metadata.ishandcuffed (searching a cuffed player is still allowed)
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
    maxPerPlayer = 3,           -- Open drops one player may have created at once
    createCooldownMs = 3000,    -- Minimum time between creating drops per player
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
    maxPerPurchase = 100,   -- Units of one item per transaction
    -- Optional per-shop `coords = vector3(...)` + `distance = 3.0` on a registered shop: the server
    -- refuses to open it (and to sell) when the player is not there.
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ SECURITY & ANTI-ABUSE █████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

-- ██████████████████████████████████████████████████████████████████████████████
-- ⏳ PROGRESS (shown while another container is being opened)
-- ██████████████████████████████████████████████████████████████████████████████
Config.Progress = {
    disableControls = { disableMovement = false, disableCarMovement = false, disableMouse = false, disableCombat = true },
    animations = {
        default     = { animDict = 'amb_work@world_human_crouch_inspect@male_a@idle_a', anim = 'idle_a', flags = 1 },
        stash       = { animDict = 'amb_work@world_human_crouch_inspect@male_a@idle_a', anim = 'idle_a', flags = 1 },
        drop        = { animDict = 'amb_work@world_human_crouch_inspect@male_a@idle_a', anim = 'idle_a', flags = 1 },
        otherplayer = { animDict = 'mech_inspection@stand@idle_a@base', anim = 'base', flags = 1 },
    },
}

Config.Security = {
    rateLimit     = { burst = 40, windowMs = 5000 },
    maxMoveAmount = 10000,
    -- Kinds a CLIENT may ask to open. Stashes are never in this list: the resource that owns a
    -- stash opens it server-side with owner / job / gang rules (see README → Stash access).
    clientOpenKinds = { player = true, ground = true, drop = true, shop = true, otherplayer = true },
    logMoves      = true,   -- Log every cross-container move through lxr-core (ledger-style)
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ DEBUG SETTINGS ████████████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.Debug = false

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ END OF CONFIGURATION ██████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████
