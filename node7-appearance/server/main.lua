local Config = Node7AppearanceConfig or {}

local function log(message)
    print(('[node7-appearance] %s'):format(message))
end

local function cloneTable(input)
    if type(input) ~= 'table' then return input end
    local output = {}
    for key, value in pairs(input) do
        output[key] = cloneTable(value)
    end
    return output
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
    local normalized = type(skin) == 'table' and (cloneTable(skin) or {}) or {}
    for key, value in pairs(Config.DefaultSkin or {}) do
        if normalized[key] == nil or normalized[key] == '' then
            normalized[key] = value
        end
    end
    normalized.sex = tonumber(normalized.sex) == 2 and 2 or 1
    normalized.model = normalized.sex == 2 and 'mp_female' or 'mp_male'
    return normalized
end

local function normalizeClothes(clothes)
    return type(clothes) == 'table' and (cloneTable(clothes) or {}) or {}
end

local function normalizeOutfitName(value)
    local name = tostring(value or ''):gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return name:sub(1, 64)
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

    -- Backward compatibility for older rsg-appearance rows without retrying a failing ALTER every restart.
    local legacyColumn = MySQL.query.await("SHOW COLUMNS FROM `player_skins` LIKE 'clothes'") or {}
    if not legacyColumn[1] then
        MySQL.query.await('ALTER TABLE `player_skins` ADD COLUMN `clothes` LONGTEXT NULL AFTER `skin`')
    end
end

CreateThread(function()
    Wait(1000)
    local ok, err = pcall(ensureTables)
    if not ok then
        log(('table setup failed: %s'):format(tostring(err)))
    end
    log('started v1.1.0')
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
    local encodedClothes = json.encode(clothes)
    MySQL.query.await([[
        INSERT INTO `player_clothing` (citizenid, clothing)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE
            clothing = VALUES(clothing),
            updated_at = CURRENT_TIMESTAMP
    ]], { citizenid, encodedClothes })
    pcall(function()
        MySQL.query.await('UPDATE `player_skins` SET clothes = ? WHERE citizenid = ?', { encodedClothes, citizenid })
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

local function requireCitizenId(src)
    local citizenid = getCitizenId(src)
    if citizenid then return citizenid end
    notify(src, 'No active NODE7 character found.', 'error')
    return nil
end

local function saveOutfit(citizenid, clothes, outfitName)
    if not citizenid then return false, 'missing citizenid' end

    local name = normalizeOutfitName(outfitName)
    if name == '' then return false, 'Outfit name missing.' end

    local normalizedClothes = normalizeClothes(clothes)
    MySQL.query.await([[
        INSERT INTO `player_clothing_outfits` (citizenid, name, clothing)
        VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE
            clothing = VALUES(clothing),
            updated_at = CURRENT_TIMESTAMP
    ]], { citizenid, name, json.encode(normalizedClothes) })

    return true, name
end

local function deleteOutfit(citizenid, idOrName)
    if not citizenid then return false end

    local id = tonumber(idOrName)
    if id then
        MySQL.query.await('DELETE FROM `player_clothing_outfits` WHERE citizenid = ? AND id = ?', { citizenid, id })
    else
        local name = normalizeOutfitName(idOrName)
        if name == '' then return false end
        MySQL.query.await('DELETE FROM `player_clothing_outfits` WHERE citizenid = ? AND name = ?', { citizenid, name })
    end
    return true
end

local function sendSavedAppearance(src, openCreatorWhenMissing)
    local citizenid = getCitizenId(src)
    if not citizenid then
        if openCreatorWhenMissing then
            TriggerClientEvent('node7-appearance:client:openCreator', src)
        else
            notify(src, 'No active NODE7 character found.', 'error')
        end
        return false
    end

    local skin = getSkin(citizenid)
    local clothes = getClothes(citizenid)
    if skin then
        TriggerClientEvent('node7-appearance:client:ApplySkin', src, skin, clothes)
        return true
    end

    if openCreatorWhenMissing then
        TriggerClientEvent('node7-appearance:client:openCreator', src)
    else
        notify(src, 'No saved appearance found.', 'error')
    end
    return false
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
    local citizenid = requireCitizenId(src)
    if not citizenid then return end

    local ok, result = saveSkin(citizenid, skin)
    if not ok then
        notify(src, result or 'Skin save failed.', 'error')
        return
    end
    notify(src, 'Appearance saved.', 'success')
end)

RegisterNetEvent('node7-appearance:server:saveClothes', function(clothes)
    local src = source
    local citizenid = requireCitizenId(src)
    if not citizenid then return end

    local ok, result = saveClothes(citizenid, clothes)
    if not ok then
        notify(src, result or 'Clothing save failed.', 'error')
        return
    end
    notify(src, 'Clothing saved.', 'success')
end)

RegisterNetEvent('node7-appearance:server:saveOutfit', function(clothes, outfitName)
    local src = source
    local citizenid = requireCitizenId(src)
    if not citizenid then return end

    local ok, result = saveOutfit(citizenid, clothes, outfitName)
    if not ok then
        notify(src, result or 'Outfit save failed.', 'error')
        return
    end
    notify(src, ('Outfit saved: %s'):format(result), 'success')
end)

RegisterNetEvent('node7-appearance:server:deleteOutfit', function(idOrName)
    local src = source
    local citizenid = requireCitizenId(src)
    if not citizenid then return end

    if deleteOutfit(citizenid, idOrName) then
        notify(src, 'Outfit deleted.', 'success')
    else
        notify(src, 'Outfit could not be deleted.', 'error')
    end
end)

RegisterNetEvent('node7-appearance:server:loadSaved', function()
    sendSavedAppearance(source, false)
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
    local citizenid = getCitizenId(source)
    if not citizenid then return end
    saveSkin(citizenid, skin)
    if clothes then saveClothes(citizenid, clothes) end
end)

RegisterNetEvent('rsg-appearance:server:LoadSkin', function()
    sendSavedAppearance(source, true)
end)

RegisterNetEvent('rsg-appearance:server:saveOutfit', function(newClothes, _isMale, outfitName)
    local citizenid = getCitizenId(source)
    if not citizenid then return end

    saveClothes(citizenid, newClothes)
    if outfitName then
        saveOutfit(citizenid, newClothes, outfitName)
    end
end)

RegisterNetEvent('rsg-appearance:server:saveUseOutfit', function(clothes)
    local citizenid = getCitizenId(source)
    if citizenid then saveClothes(citizenid, clothes) end
end)

RegisterNetEvent('rsg-appearance:server:DeleteOutfit', function(name)
    local citizenid = getCitizenId(source)
    if citizenid then deleteOutfit(citizenid, name) end
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
