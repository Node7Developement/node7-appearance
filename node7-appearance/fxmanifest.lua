fx_version 'cerulean'
game 'rdr3'

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

author 'NODE7 Development Studios'
description 'NODE7 Appearance - ox_lib RedM appearance, creator, clothing, and wardrobe system'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'data/features.lua',
    'data/overlays.lua',
    'data/clothes_list.lua',
    'data/hairs_list.lua',
    'data/clothing.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

files {
    'img/*.png'
}

dependencies {
    'ox_lib',
    'oxmysql',
    'node7-core'
}
