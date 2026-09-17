--[[ ═══════════════════════════════════════════════════════════════════════════
     🐺 LXR-INVENTORY — Locale: English (canonical)
     Developer   : iBoss21 | Brand : LXRCore | https://www.lxrcore.com
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

Locale.Register('en', {
    error = {
        invalid           = 'That is not possible',
        invalid_amount    = 'Invalid amount',
        invalid_slot      = 'Invalid slot',
        not_owned         = 'You do not have that item',
        too_heavy         = 'Too heavy to carry',
        slot_occupied     = 'That slot is taken',
        item_not_exist    = 'Unknown item',
        not_usable        = 'You cannot use that',
        not_enough_money  = 'Not enough money',
        cannot_store_here = 'You cannot put items there',
        too_far           = 'Too far away',
        no_permission     = 'You cannot search this person',
        in_use            = 'Someone else is using this',
        target_full       = 'They cannot carry that',
        nobody_nearby     = 'Nobody nearby',
        cancelled         = 'Cancelled',
        dead              = 'You cannot do that right now',
        cuffed            = 'Your hands are bound',
        too_fast          = 'Slow down',
        too_many_drops    = 'You have left too many things on the ground',
    },
    progress = {
        default     = 'Searching...',
        stash       = 'Opening the chest...',
        drop        = 'Rummaging...',
        otherplayer = 'Searching pockets...',
    },
    info = {
        item_given = 'Item given',
        cleared    = 'Inventory cleared',
    },
    command = {
        giveitem   = 'Give an item to a player (admin)',
        clearinv   = 'Clear a player inventory (admin)',
        resetstash = 'Empty a stash (admin)',
    },
    ui = {
        your_satchel = 'Your satchel',
        ground       = 'Ground',
        other_player = 'Their satchel',
        weight       = 'Weight',
        use          = 'Use',
        give         = 'Give',
        drop         = 'Drop',
        close        = 'Close',
        amount       = 'Amount',
        buy          = 'Buy',
        price        = 'Price',
        received     = 'Received',
        removed      = 'Removed',
        empty        = 'Empty',
        hotbar       = 'Hotbar',
    },
})
