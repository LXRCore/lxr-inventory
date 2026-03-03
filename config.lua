--[[
    ██╗     ██╗  ██╗██████╗        ██╗███╗   ██╗██╗   ██╗███████╗███╗   ██╗████████╗ ██████╗ ██████╗ ██╗   ██╗
    ██║     ╚██╗██╔╝██╔══██╗       ██║████╗  ██║██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔═══██╗██╔══██╗╚██╗ ██╔╝
    ██║      ╚███╔╝ ██████╔╝█████╗ ██║██╔██╗ ██║██║   ██║█████╗  ██╔██╗ ██║   ██║   ██║   ██║██████╔╝ ╚████╔╝ 
    ██║      ██╔██╗ ██╔══██╗╚════╝ ██║██║╚██╗██║╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ██║   ██║██╔══██╗  ╚██╔╝  
    ███████╗██╔╝ ██╗██║  ██║       ██║██║ ╚████║ ╚████╔╝ ███████╗██║ ╚████║   ██║   ╚██████╔╝██║  ██║   ██║   
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝       ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝   ╚═╝   

    🐺 LXR Inventory System
    Advanced Inventory, Crafting, Shops & Drops for RedM

    ═══════════════════════════════════════════════════════════════════════════════
    SERVER INFORMATION
    ═══════════════════════════════════════════════════════════════════════════════

    Server:    The Land of Wolves 🐺
    Developer: iBoss21 / The Lux Empire
    Website:   https://www.wolves.land
    Discord:   https://discord.gg/CrKcWdfd3A
    Store:     https://theluxempire.tebex.io

    ═══════════════════════════════════════════════════════════════════════════════

    Framework Support:
    - LXR Core  (Primary)
    - RSG Core  (Primary)
    - VORP Core (Supported / Legacy)

    © 2026 iBoss21 / The Lux Empire | wolves.land | All Rights Reserved
]]

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🐺 RESOURCE NAME PROTECTION - RUNTIME CHECK
-- ═══════════════════════════════════════════════════════════════════════════════

local REQUIRED_RESOURCE_NAME = "lxr-inventory"
local currentResourceName = GetCurrentResourceName()

if currentResourceName ~= REQUIRED_RESOURCE_NAME then
    error(string.format([[

        ═══════════════════════════════════════════════════════════════════════════════
        ❌ CRITICAL ERROR: RESOURCE NAME MISMATCH ❌
        ═══════════════════════════════════════════════════════════════════════════════

        Expected: %s
        Got: %s

        This resource is branded and must maintain the correct name.
        Rename the folder to "%s" to continue.

        🐺 wolves.land - The Land of Wolves

        ═══════════════════════════════════════════════════════════════════════════════

    ]], REQUIRED_RESOURCE_NAME, currentResourceName, REQUIRED_RESOURCE_NAME))
end

Config = {}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ SERVER BRANDING & INFO ████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.ServerInfo = {
    name      = 'The Land of Wolves 🐺',
    developer = 'iBoss21 / The Lux Empire',
    website   = 'https://www.wolves.land',
    discord   = 'https://discord.gg/CrKcWdfd3A',
    github    = 'https://github.com/iBoss21',
    store     = 'https://theluxempire.tebex.io',
    tags      = {'RedM', 'SeriousRP', 'Inventory', 'Crafting', 'LXRCore', 'Economy'},
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ FRAMEWORK CONFIGURATION ███████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

--[[
    Framework Priority (in order):
    1. LXR-Core (Primary)
    2. RSG-Core (Primary)
    3. VORP Core (Supported / Legacy)
    4. Standalone (Fallback)
]]

Config.Framework = 'auto' -- 'auto' or manual: 'lxr-core', 'rsg-core', 'vorp_core', 'standalone'

Config.FrameworkSettings = {
    ['lxr-core'] = {
        resource      = 'lxr-core',
        notifications = 'lxr-core',
        inventory     = 'lxr-inventory',
        events = {
            server   = 'LXRCore:Server:%s',
            client   = 'LXRCore:Client:%s',
            callback = 'LXRCore:Callback:%s',
        },
    },
    ['rsg-core'] = {
        resource      = 'rsg-core',
        notifications = 'ox_lib',
        inventory     = 'rsg-inventory',
        events = {
            server   = 'RSGCore:Server:%s',
            client   = 'RSGCore:Client:%s',
            callback = 'RSGCore:Callback:%s',
        },
    },
    ['vorp_core'] = {
        resource      = 'vorp_core',
        notifications = 'vorp',
        inventory     = 'vorp_inventory',
        events = {
            server = 'vorp:server:%s',
            client = 'vorp:client:%s',
        },
    },
    ['standalone'] = {
        notifications = 'print',
        inventory     = 'none',
    },
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ INVENTORY CONFIGURATION ███████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

MaxInventorySlots = 41

Config.MaximumAmmoValues = {
    ["pistol"] = 250,
    ["rifle"]  = 250,
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ CRAFTING CONFIGURATION ████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.CraftingObject = `prop_toolchest_05`

Config.CraftingItems = {
    [1] = {
        name      = "lockpick",
        amount    = 20,
        info      = {},
        costs     = {
            ["metalscrap"] = 20,
            ["plastic"]    = 20,
        },
        type      = "item",
        threshold = 0,
        points    = 1,
    },
    [2] = {
        name      = "coffee",
        amount    = 20,
        info      = {},
        costs     = {
            ["coffeeseeds"] = 20,
            ["water"]       = 20,
        },
        type      = "item",
        threshold = 0,
        points    = 2,
    },
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ ATTACHMENT CRAFTING ███████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████

Config.AttachmentCraftingLocation = vector3(-277.2096, 779.3605, 119.504)

Config.AttachmentCrafting = {
    [1] = {
        name      = "weapon_revolver_cattleman",
        amount    = 50,
        info      = {},
        costs     = {
            ["metalscrap"] = 140,
        },
        type      = "item",
        threshold = 0,
        points    = 1,
    },
}

