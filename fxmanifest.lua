fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'lxr-Inventory - A system so advanced, it might just invent itself.'
version '1.0.1'

-- Shared scripts to keep things nice and tidy, because who likes clutter?
shared_scripts {
	'@lxr-core/shared/locale.lua',  -- LXRCore language support for multilingual mastery
   	'locales/en.lua',               -- English translation because the code understands you
	'config.lua',                   -- Configuring like a boss (iBoss, actually)
}

-- The mystical server scripts. Here lies the MySQL and server logic, brewing in the background.
server_scripts {
	'@oxmysql/lib/MySQL.lua',       -- Making sure your items don't vanish into thin air
	'server/main.lua'               -- All the server-side magic happens here
}

-- Client-side wonders unfold right here.
client_script 'client/main.lua'     -- Where the magic hits the player-side experience

-- NUI interface – fancy stuff happens here with HTML, CSS, and JS, like it’s a website but cooler.
ui_page {
	'html/ui.html'                  -- Where your inventory comes to life (visually)
}

-- File section – a collection of styles, images, and other goodies
files {
	'html/ui.html',                 -- The heart of the UI
	'html/css/main.css',            -- Style it up! Making the inventory look slick
	'html/js/app.js',               -- The real wizardry happens here
	'html/images/*.png',            -- Pretty pictures for items, because visuals matter
	'html/images/*.jpg',            -- Some more pretty pictures, just in case
	'html/ammo_images/*.png',       -- Ammo images for when you need to load up with style
	'html/attachment_images/*.png', -- Attachments looking sharp, like a well-dressed weapon
	'html/*.ttf'                    -- Fancy fonts to keep things stylish
}

-- This Lua version is so modern, it can practically time-travel.
lua54 'yes'
