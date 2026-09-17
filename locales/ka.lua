--[[ ═══════════════════════════════════════════════════════════════════════════
     🐺 LXR-INVENTORY — Locale: Georgian (ქართული) — 1:1 mirror of en.lua
     Developer   : iBoss21 | Brand : LXRCore | https://www.lxrcore.com
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

Locale.Register('ka', {
    error = {
        invalid           = 'ეს შეუძლებელია',
        invalid_amount    = 'არასწორი რაოდენობა',
        invalid_slot      = 'არასწორი უჯრა',
        not_owned         = 'ეს ნივთი არ გაქვთ',
        too_heavy         = 'ძალიან მძიმეა',
        slot_occupied     = 'ეს უჯრა დაკავებულია',
        item_not_exist    = 'უცნობი ნივთი',
        not_usable        = 'ამის გამოყენება არ შეიძლება',
        not_enough_money  = 'საკმარისი ფული არ გაქვთ',
        cannot_store_here = 'აქ ნივთების დადება არ შეიძლება',
        too_far           = 'ძალიან შორს ხართ',
        no_permission     = 'ამ ადამიანის გაჩხრეკა არ შეგიძლიათ',
        in_use            = 'ამას სხვა იყენებს',
        target_full       = 'მას ამის ტარება არ შეუძლია',
        nobody_nearby     = 'ახლოს არავინ არის',
    },
    info = {
        item_given = 'ნივთი გადაეცა',
        cleared    = 'ინვენტარი გასუფთავდა',
    },
    command = {
        giveitem   = 'ნივთის მიცემა მოთამაშისთვის (ადმინი)',
        clearinv   = 'მოთამაშის ინვენტარის გასუფთავება (ადმინი)',
        resetstash = 'საცავის დაცარიელება (ადმინი)',
    },
    ui = {
        your_satchel = 'თქვენი ჩანთა',
        ground       = 'მიწა',
        other_player = 'მისი ჩანთა',
        weight       = 'წონა',
        use          = 'გამოყენება',
        give         = 'მიცემა',
        drop         = 'დაგდება',
        close        = 'დახურვა',
        amount       = 'რაოდენობა',
        buy          = 'ყიდვა',
        price        = 'ფასი',
        received     = 'მიღებულია',
        removed      = 'წაღებულია',
        empty        = 'ცარიელი',
        hotbar       = 'სწრაფი უჯრები',
    },
})
