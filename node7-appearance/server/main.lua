local Config = Node7AppearanceConfig or {}
local RESOURCE_NAME = GetCurrentResourceName()

local function log(message)
    print(('[node7-appearance] %s'):format(message))
end

local function debugLog(message)
    if Config.Debug then
        log(message)
    end
end

local function notify(src, description, notifyType)
    TriggerClientEvent('ox_lib:notify', src, {
        title = Config.NotifyTitle or 'NODE7 Appearance',
        description = description,
        type = notifyType or 'inform'
    })
end

local function safeExport(resource, exportName, ...)
    local args = { ... }
    local exportTable = exports[resource]
    if not exportTable then
        return false, ('missing resource exports: %s'):format(resource)
    end

    local ok, result = pcall(function()
        local fn = exportTable[exportName]
        if type(fn) ~= 'function' then return nil end
        return fn(table.unpack(args))
    end)
    if ok and result ~= nil then return true, result end

    local okSelf, resultSelf = pcall(function()
        local fn = exportTable[exportName]
        if type(fn) ~= 'function' then return nil end
        return fn(exportTable, table.unpack(args))
    end)
    if okSelf and resultSelf ~= nil then return true, resultSelf end

    return false, result or resultSelf or ('export failed: %s:%s'):format(resource, exportName)
end

local function valueToCitizenId(value)
    if type(value) ~= 'table' then return nil end

    if value.citizenid then return tostring(value.citizenid) end
    if value.citizenId then return tostring(value.citizenId) end
    if value.CitizenId then return tostring(value.CitizenId) end

    if type(value.PlayerData) == 'table' then
        return valueToCitizenId(value.PlayerData)
    end

    if type(value.data) == 'table' then
        return valueToCitizenId(value.data)
    end

    return nil
end

local function getCoreObject()
    if GetResourceState('node7-core') ~= 'started' then return nil end

    local ok, core = pcall(function()
        return exports['node7-core']:GetCoreObject()
    end)

    if ok and type(core) == 'table' then return core end
    return nil
end

local function getCitizenId(src)
    src = tonumber(src)
    if not src or src <= 0 then return nil end

    local state = Player(src) and Player(src).state or nil
    if state then
        local fromState = valueToCitizenId({
            citizenid = state.citizenid or state.node7CitizenId or state.node7_citizenid,
            PlayerData = state.PlayerData or state.playerData
        })
        if fromState then return fromState end
    end

    local core = getCoreObject()
    if core then
        if core.Functions and type(core.Functions.GetPlayer) == 'function' then
            local ok, player = pcall(core.Functions.GetPlayer, src)
            local citizenid = ok and valueToCitizenId(player) or nil
            if citizenid then return citizenid end
        end

        if type(core.Players) == 'table' then
            local citizenid = valueToCitizenId(core.Players[src] or core.Players[tostring(src)])
            if citizenid then return citizenid end
        end
    end

    local okDirect, directPlayer = safeExport('node7-core', 'GetPlayer', src)
    local directCitizenid = okDirect and valueToCitizenId(directPlayer) or nil
    if directCitizenid then return directCitizenid end

    local okPlayers, players = safeExport('node7-players', 'GetPlayersObject')
    if okPlayers and type(players) == 'table' then
        local citizenid = valueToCitizenId(players[src] or players[tostring(src)])
        if citizenid then return citizenid end
    end

    local license = GetPlayerIdentifierByType(src, 'license')
    if license then
        local rows = MySQL.query.await('SELECT citizenid FROM `players` WHERE license = ? LIMIT 2', { license }) or {}
        if #rows == 1 and rows[1].citizenid then
            return tostring(rows[1].citizenid)
        end
    end

    return nil
end

AddEventHandler('Node7Core:Server:PlayerLoaded', function(player)
    local source = player and player.PlayerData and tonumber(player.PlayerData.source) or nil
    local citizenid = valueToCitizenId(player)
    if source and citizenid and Player(source) and Player(source).state then
        Player(source).state:set('citizenid', citizenid, true)
        Player(source).state:set('node7CitizenId', citizenid, true)
    end
end)

local function normalizeSkin(skin)
    if type(skin) ~= 'table' then skin = {} end
    local defaults = Config.DefaultSkin or {}
    for key, value in pairs(defaults) do
        if skin[key] == nil or skin[key] == '' then
            skin[key] = value
        end
    end
    skin.sex = tonumber(skin.sex) == 2 and 2 or 1
    skin.model = skin.sex == 2 and 'mp_female' or 'mp_male'
    return skin
end

local function normalizeClothes(clothes)
    if type(clothes) ~= 'table' then return {} end
    return clothes
end

local function ensureTables()
    if not Config.AutoCreateTables then return end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `player_skins` (
            `citizenid` VARCHAR(64) NOT NULL,
            `model` VARCHAR(64) NOT NULL DEFAULT 'mp_male',
            `skin` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `player_clothing` (
            `citizenid` VARCHAR(64) NOT NULL,
            `clothing` LONGTEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `player_clothing_outfits` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `citizenid` VARCHAR(64) NOT NULL,
            `name` VARCHAR(64) NOT NULL,
            `clothing` LONGTEXT NOT NULL,
            `is_default` TINYINT(1) NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_citizenid_name` (`citizenid`, `name`),
            KEY `idx_citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]])

    -- Backward compatibility for older rsg-appearance style rows if a clothes column already exists/gets added.
    pcall(function()
        MySQL.query.await('ALTER TABLE `player_skins` ADD COLUMN `clothes` LONGTEXT NULL AFTER `skin`')
    end)
end

CreateThread(function()
    Wait(1000)
    local ok, err = pcall(ensureTables)
    if not ok then
        log(('table setup failed: %s'):format(tostring(err)))
    end
    log('started v1.0.0')
end)

local function getSkin(citizenid)
    if not citizenid then return nil end
    local rows = MySQL.query.await('SELECT citizenid, model, skin FROM `player_skins` WHERE citizenid = ? LIMIT 1', { citizenid })
    if rows and rows[1] then
        local decoded = json.decode(rows[1].skin or '{}') or {}
        decoded.model = rows[1].model or decoded.model
        decoded.citizenid = rows[1].citizenid
        return normalizeSkin(decoded)
    end
    return nil
end

local function getClothes(citizenid)
    if not citizenid then return {} end
    local rows = MySQL.query.await('SELECT clothing FROM `player_clothing` WHERE citizenid = ? LIMIT 1', { citizenid })
    if rows and rows[1] and rows[1].clothing then
        return normalizeClothes(json.decode(rows[1].clothing or '{}') or {})
    end

    local legacy = MySQL.query.await('SELECT clothes FROM `player_skins` WHERE citizenid = ? LIMIT 1', { citizenid })
    if legacy and legacy[1] and legacy[1].clothes then
        return normalizeClothes(json.decode(legacy[1].clothes or '{}') or {})
    end

    return {}
end

local function saveSkin(citizenid, skin)
    if not citizenid then return false, 'missing citizenid' end
    skin = normalizeSkin(skin)
    MySQL.query.await([[
        INSERT INTO `player_skins` (citizenid, model, skin)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            model = VALUES(model),
            skin = VALUES(skin),
            updated_at = CURRENT_TIMESTAMP
    ]], { citizenid, skin.model, json.encode(skin) })
    return true, skin
end

local function saveClothes(citizenid, clothes)
    if not citizenid then return false, 'missing citizenid' end
    clothes = normalizeClothes(clothes)
    MySQL.query.await([[
        INSERT INTO `player_clothing` (citizenid, clothing)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE
            clothing = VALUES(clothing),
            updated_at = CURRENT_TIMESTAMP
    ]], { citizenid, json.encode(clothes) })
    pcall(function()
        MySQL.query.await('UPDATE `player_skins` SET clothes = ? WHERE citizenid = ?', { json.encode(clothes), citizenid })
    end)
    return true, clothes
end

local function getOutfits(citizenid)
    if not citizenid then return {} end
    local rows = MySQL.query.await('SELECT id, name, clothing, is_default FROM `player_clothing_outfits` WHERE citizenid = ? ORDER BY name ASC', { citizenid }) or {}
    local outfits = {}
    for _, row in ipairs(rows) do
        outfits[#outfits + 1] = {
            id = row.id,
            name = row.name,
            clothing = json.decode(row.clothing or '{}') or {},
            is_default = row.is_default == 1
        }
    end
    return outfits
end

lib.callback.register('node7-appearance:server:getState', function(source)
    local citizenid = getCitizenId(source)
    if not citizenid then
        return { citizenid = nil, skin = nil, clothes = {}, outfits = {} }
    end
    return {
        citizenid = citizenid,
        skin = getSkin(citizenid),
        clothes = getClothes(citizenid),
        outfits = getOutfits(citizenid)
    }
end)

lib.callback.register('node7-appearance:server:getSkin', function(source)
    local citizenid = getCitizenId(source)
    return citizenid and getSkin(citizenid) or nil
end)

lib.callback.register('node7-appearance:server:getClothes', function(source)
    local citizenid = getCitizenId(source)
    return citizenid and getClothes(citizenid) or {}
end)

lib.callback.register('node7-appearance:server:getOutfits', function(source)
    local citizenid = getCitizenId(source)
    return citizenid and getOutfits(citizenid) or {}
end)

RegisterNetEvent('node7-appearance:server:saveSkin', function(skin)
    local src = source
    local citizenid = getCitizenId(src)
    local ok, result = saveSkin(citizenid, skin)
    if not ok then
        notify(src, result or 'Skin save failed.', 'error')
        return
    end
    notify(src, 'Appearance saved.', 'success')
end)

RegisterNetEvent('node7-appearance:server:saveClothes', function(clothes)
    local src = source
    local citizenid = getCitizenId(src)
    local ok, result = saveClothes(citizenid, clothes)
    if not ok then
        notify(src, result or 'Clothing save failed.', 'error')
        return
    end
    notify(src, 'Clothing saved.', 'success')
end)

RegisterNetEvent('node7-appearance:server:saveOutfit', function(clothes, outfitName)
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then
        notify(src, 'No active NODE7 character found.', 'error')
        return
    end

    outfitName = tostring(outfitName or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if outfitName == '' then
        notify(src, 'Outfit name missing.', 'error')
        return
    end

    clothes = normalizeClothes(clothes)
    MySQL.query.await([[
        INSERT INTO `player_clothing_outfits` (citizenid, name, clothing)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            clothing = VALUES(clothing),
            updated_at = CURRENT_TIMESTAMP
    ]], { citizenid, outfitName, json.encode(clothes) })
    notify(src, ('Outfit saved: %s'):format(outfitName), 'success')
end)

RegisterNetEvent('node7-appearance:server:deleteOutfit', function(idOrName)
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then return end

    local id = tonumber(idOrName)
    if id then
        MySQL.query.await('DELETE FROM `player_clothing_outfits` WHERE citizenid = ? AND id = ?', { citizenid, id })
    else
        MySQL.query.await('DELETE FROM `player_clothing_outfits` WHERE citizenid = ? AND name = ?', { citizenid, tostring(idOrName or '') })
    end
    notify(src, 'Outfit deleted.', 'success')
end)

RegisterNetEvent('node7-appearance:server:loadSaved', function()
    local src = source
    local citizenid = getCitizenId(src)
    if not citizenid then
        notify(src, 'No active NODE7 character found.', 'error')
        return
    end
    TriggerClientEvent('node7-appearance:client:ApplySkin', src, getSkin(citizenid), getClothes(citizenid))
end)

RegisterNetEvent('node7-appearance:server:setBucket', function(bucket, random)
    local src = source
    if random then
        bucket = math.random(1000, 9999)
        SetRoutingBucketPopulationEnabled(bucket, false)
    end
    SetPlayerRoutingBucket(src, tonumber(bucket) or 0)
end)

-- Compatibility aliases for converted resources expecting rsg-appearance names.
RegisterNetEvent('rsg-appearance:server:SaveSkin', function(skin, clothes)
    local src = source
    local citizenid = getCitizenId(src)
    saveSkin(citizenid, skin)
    if clothes then saveClothes(citizenid, clothes) end
end)

RegisterNetEvent('rsg-appearance:server:LoadSkin', function()
    local src = source
    local citizenid = getCitizenId(src)
    if citizenid and getSkin(citizenid) then
        TriggerClientEvent('node7-appearance:client:ApplySkin', src, getSkin(citizenid), getClothes(citizenid))
    else
        TriggerClientEvent('node7-appearance:client:openCreator', src)
    end
end)

RegisterNetEvent('rsg-appearance:server:saveOutfit', function(newClothes, isMale, outfitName)
    local src = source
    local citizenid = getCitizenId(src)
    if citizenid then
        saveClothes(citizenid, newClothes)
        if outfitName then
            MySQL.query.await([[
                INSERT INTO `player_clothing_outfits` (citizenid, name, clothing)
                VALUES (?, ?, ?)
                ON DUPLICATE KEY UPDATE clothing = VALUES(clothing), updated_at = CURRENT_TIMESTAMP
            ]], { citizenid, tostring(outfitName), json.encode(normalizeClothes(newClothes)) })
        end
    end
end)

RegisterNetEvent('rsg-appearance:server:saveUseOutfit', function(clothes)
    local src = source
    local citizenid = getCitizenId(src)
    if citizenid then saveClothes(citizenid, clothes) end
end)

RegisterNetEvent('rsg-appearance:server:DeleteOutfit', function(name)
    local src = source
    local citizenid = getCitizenId(src)
    if citizenid then
        MySQL.query.await('DELETE FROM `player_clothing_outfits` WHERE citizenid = ? AND name = ?', { citizenid, tostring(name or '') })
    end
end)

lib.callback.register('rsg-appearance:server:LoadClothes', function(source)
    local citizenid = getCitizenId(source)
    return citizenid and getClothes(citizenid) or {}
end)

lib.callback.register('rsg-appearance:server:getOutfits', function(source)
    local citizenid = getCitizenId(source)
    return citizenid and getOutfits(citizenid) or {}
end)

RegisterCommand('openappearance', function(source, args)
    if source ~= 0 and not IsPlayerAceAllowed(source, 'node7.appearance.admin') then
        notify(source, 'Missing ACE: node7.appearance.admin', 'error')
        return
    end
    local target = tonumber(args[1]) or source
    if target <= 0 then
        log('Usage from console: openappearance [playerId]')
        return
    end
    TriggerClientEvent('node7-appearance:client:open', target)
end, true)

exports('GetSkin', getSkin)
exports('SaveSkin', saveSkin)
exports('GetClothes', getClothes)
exports('SaveClothes', saveClothes)
exports('GetOutfits', getOutfits)
exports('GetAppearance', function(citizenid)
    return {
        skin = getSkin(citizenid),
        clothes = getClothes(citizenid),
        outfits = getOutfits(citizenid)
    }
end)
