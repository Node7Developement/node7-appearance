local Config = Node7AppearanceConfig or {}
local RESOURCE_NAME = GetCurrentResourceName()

local Data = require 'data.features'
local clothesList = require 'data.clothes_list'
local hairsList = require 'data.hairs_list'
local clothing = require 'data.clothing'

local currentSkin = {}
local currentClothes = {}
local componentsMale = {}
local componentsFemale = {}
local headHashTable = {}
local textUiShowing = false
local editorCam = nil
local inEditor = false

local function debugLog(message)
    if Config.Debug then
        print(('[node7-appearance] %s'):format(message))
    end
end

local function notify(description, notifyType)
    if lib and lib.notify then
        lib.notify({
            title = Config.NotifyTitle or 'NODE7 Appearance',
            description = description,
            type = notifyType or 'inform'
        })
    else
        print(('[node7-appearance] %s'):format(description))
    end
end

local function hash(value)
    if type(value) == 'number' then return value end
    if joaat then return joaat(value) end
    return GetHashKey(value)
end

local function cloneTable(input)
    if type(input) ~= 'table' then return input end
    local out = {}
    for k, v in pairs(input) do
        out[k] = cloneTable(v)
    end
    return out
end

local function mergeDefaults(skin)
    local result = cloneTable(skin or {}) or {}
    for k, v in pairs(Config.DefaultSkin or {}) do
        if result[k] == nil then result[k] = v end
    end
    result.sex = tonumber(result.sex) == 2 and 2 or 1
    result.model = result.sex == 2 and 'mp_female' or 'mp_male'
    return result
end

local function labelFor(key)
    return (Config.Labels and Config.Labels[key]) or tostring(key):gsub('_', ' '):gsub('^%l', string.upper)
end

local function normalizeNumber(value, fallback, minValue, maxValue)
    value = tonumber(value) or fallback
    if minValue and value < minValue then value = minValue end
    if maxValue and value > maxValue then value = maxValue end
    return value
end

local function forceVisible()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true)
    SetEntityAlpha(ped, 255, false)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    pcall(function() NetworkSetEntityInvisibleToNetwork(ped, false) end)
end

local function nativeHasPedComponentLoaded(ped)
    return Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)
end

local function updatePedVariation(ped)
    ped = ped or PlayerPedId()
    Citizen.InvokeNative(0x704C908E9C405136, ped)
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
    Citizen.InvokeNative(0xAAB86462966168CE, ped, true)
    local timeout = GetGameTimer() + 3000
    while not nativeHasPedComponentLoaded(ped) and GetGameTimer() < timeout do
        Wait(0)
    end
    forceVisible()
end

local function setPedComponent(ped, componentHash)
    ped = ped or PlayerPedId()
    componentHash = tonumber(componentHash)
    if not componentHash or componentHash == 0 then return false end

    local ok, err = pcall(function()
        local categoryHash = Citizen.InvokeNative(0x5FF9A878C3D115B8, componentHash, not IsPedMale(ped), true)
        if categoryHash then
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, categoryHash)
        end
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, false, true, true)
        updatePedVariation(ped)
    end)

    if not ok then
        debugLog(('component apply failed: %s'):format(tostring(err)))
    end

    return ok
end

local function removePedCategory(ped, category)
    ped = ped or PlayerPedId()
    local ok = pcall(function()
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, hash(category), 0)
        updatePedVariation(ped)
    end)
    return ok
end

local function setPedModel(modelName)
    local modelHash = hash(modelName)
    RequestModel(modelHash)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
        Wait(0)
    end
    if not HasModelLoaded(modelHash) then
        notify(('Model failed to load: %s'):format(tostring(modelName)), 'error')
        return false
    end

    Citizen.InvokeNative(0xED40380076A31506, PlayerId(), modelHash, false)
    Wait(300)
    local ped = PlayerPedId()
    Citizen.InvokeNative(0x77FF8D35EEC6BBC4, ped, 7, true)
    updatePedVariation(ped)
    SetModelAsNoLongerNeeded(modelHash)
    forceVisible()
    return true
end

local function buildComponentCaches()
    for _, item in pairs(clothesList or {}) do
        if item and item.is_multiplayer and item.hashname and item.hashname ~= '' then
            local category = item.category_hashname
            if category == 'BODIES_LOWER' or category == 'BODIES_UPPER' or category == 'heads' or category == 'hair' or category == 'teeth' or category == 'eyes' then
                local target = item.ped_type == 'female' and componentsFemale or componentsMale
                target[category] = target[category] or {}
                target[category][#target[category] + 1] = tonumber(item.hash)
            end
            if category == 'heads' then
                headHashTable[item.hashname] = tonumber(item.hash)
            end
        end
    end
    debugLog('component caches ready')
end

CreateThread(buildComponentCaches)

local function getSkinColorFromBodySize(body, color)
    body = tonumber(body) or 1
    color = tonumber(color) or 1
    local map = {
        [1] = { 7, 10, 9, 11, 8, 12 },
        [2] = { 1, 4, 3, 5, 2, 6 },
        [3] = { 13, 16, 15, 17, 14, 18 },
        [4] = { 19, 22, 21, 23, 20, 24 },
        [5] = { 25, 28, 27, 29, 26, 30 },
        [6] = { 31, 34, 33, 35, 32, 36 }
    }
    return (map[body] and map[body][color]) or 1
end

local function getHeadHash(isMale, number, color)
    number = tonumber(number) or 1
    color = tonumber(color) or 1
    if color == 2 then color = 4
    elseif color == 3 then color = 3
    elseif color == 4 then color = 5
    elseif color == 5 then color = 2
    elseif color == 6 then color = 6
    else color = 1 end

    if isMale then
        if number == 16 then number = 18
        elseif number == 17 then number = 21
        elseif number == 18 then number = 22
        elseif number == 19 then number = 25
        elseif number == 20 then number = 28 end
    else
        if number == 17 then number = 20
        elseif number == 18 then number = 22
        elseif number == 19 then number = 27
        elseif number == 20 then number = 28 end
    end

    local suffix = ('%03d_V_%03d'):format(number, color)
    local sex = isMale and 'M' or 'F'
    local hashName = ('CLOTHING_ITEM_%s_HEAD_%s'):format(sex, suffix)
    return headHashTable[hashName] or GetHashKey(hashName)
end

local function applyBody(ped, skin)
    ped = ped or PlayerPedId()
    skin = mergeDefaults(skin)

    local components = IsPedMale(ped) and componentsMale or componentsFemale
    local bodyIndex = getSkinColorFromBodySize(skin.body_size, skin.skin_tone)
    local headNum = math.ceil((tonumber(skin.head) or 1) / 6)

    if components.BODIES_UPPER and components.BODIES_UPPER[bodyIndex] then
        setPedComponent(ped, components.BODIES_UPPER[bodyIndex])
    end
    if components.BODIES_LOWER and components.BODIES_LOWER[bodyIndex] then
        setPedComponent(ped, components.BODIES_LOWER[bodyIndex])
    end
    setPedComponent(ped, getHeadHash(IsPedMale(ped), headNum, skin.skin_tone))

    if components.eyes and components.eyes[tonumber(skin.eyes_color) or 1] then
        setPedComponent(ped, components.eyes[tonumber(skin.eyes_color) or 1])
    end
    if components.teeth and components.teeth[tonumber(skin.teeth) or 1] then
        setPedComponent(ped, components.teeth[tonumber(skin.teeth) or 1])
    end

    if Data and Data.Appearance then
        if skin.body_waist and Data.Appearance.body_waist and Data.Appearance.body_waist[tonumber(skin.body_waist)] then
            Citizen.InvokeNative(0x1902C4CFCC5BE57C, ped, Data.Appearance.body_waist[tonumber(skin.body_waist)])
        end
        if skin.chest_size and Data.Appearance.chest_size and Data.Appearance.chest_size[tonumber(skin.chest_size)] then
            Citizen.InvokeNative(0x1902C4CFCC5BE57C, ped, Data.Appearance.chest_size[tonumber(skin.chest_size)])
        end
    end

    if skin.height then
        pcall(function() SetPedScale(ped, (tonumber(skin.height) or 100) * 0.01) end)
    end

    updatePedVariation(ped)
end

local function applyFeatures(ped, skin)
    ped = ped or PlayerPedId()
    if not Data or not Data.features then return end
    for name, featureHash in pairs(Data.features) do
        if skin[name] ~= nil then
            local value = (tonumber(skin[name]) or 0) / 100
            Citizen.InvokeNative(0x5653AB26C82938CF, ped, featureHash, value)
        end
    end
    updatePedVariation(ped)
end

local function getGenderKey()
    return IsPedMale(PlayerPedId()) and 'male' or 'female'
end

local function getClothingList(category)
    local gender = getGenderKey()
    local byGender = clothing[gender] or {}
    return byGender[category]
end

local function getHairList(category)
    local gender = getGenderKey()
    local byGender = hairsList[gender] or {}
    return byGender[category]
end

local function getItemHash(list, model, texture)
    model = tonumber(model) or 0
    texture = tonumber(texture) or 1
    if model <= 0 then return nil end
    if not list or not list[model] or not list[model][texture] then return nil end
    return tonumber(list[model][texture].hash)
end

local function applyClothingItem(category)
    local item = currentClothes[category]
    if not item then return end
    if item.remove then
        removePedCategory(PlayerPedId(), category)
        return
    end
    if item.hash then
        setPedComponent(PlayerPedId(), item.hash)
        return
    end
    local list = getClothingList(category)
    local itemHash = getItemHash(list, item.model, item.texture)
    if itemHash then
        item.hash = itemHash
        setPedComponent(PlayerPedId(), itemHash)
    end
end

local function applyHairItem(category)
    local item = currentSkin[category]
    if not item then return end
    local categoryHash = category == 'hair' and 0x864B03AE or 0xF8016BCA
    if item.remove or tonumber(item.model) == 0 then
        Citizen.InvokeNative(0xD710A5007C2AC539, PlayerPedId(), categoryHash, 0)
        updatePedVariation(PlayerPedId())
        return
    end
    if item.hash then
        setPedComponent(PlayerPedId(), item.hash)
        return
    end
    local list = getHairList(category)
    local itemHash = getItemHash(list, item.model, item.texture)
    if itemHash then
        item.hash = itemHash
        setPedComponent(PlayerPedId(), itemHash)
    end
end

local function applyClothes(clothes)
    if type(clothes) ~= 'table' then clothes = {} end
    currentClothes = cloneTable(clothes) or {}
    if next(currentClothes) == nil then
        forceVisible()
        return
    end
    for category in pairs(currentClothes) do
        applyClothingItem(category)
        Wait(0)
    end
    forceVisible()
end

local function applySkin(skin, clothes)
    skin = mergeDefaults(skin)
    currentSkin = cloneTable(skin)

    if skin.model then
        setPedModel(skin.model)
    end

    local ped = PlayerPedId()
    applyBody(ped, skin)
    applyFeatures(ped, skin)

    if skin.hair then applyHairItem('hair') end
    if skin.beard then applyHairItem('beard') end

    if clothes then
        applyClothes(clothes)
    end

    forceVisible()
end

local function saveSkin()
    TriggerServerEvent('node7-appearance:server:saveSkin', currentSkin)
end

local function saveClothes()
    TriggerServerEvent('node7-appearance:server:saveClothes', currentClothes)
end

local function startCamera()
    if editorCam then return end
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local camCoords = vector3(coords.x + forward.x * 2.0, coords.y + forward.y * 2.0, coords.z + 0.75)
    editorCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(editorCam, camCoords.x, camCoords.y, camCoords.z)
    PointCamAtEntity(editorCam, ped, 0.0, 0.0, 0.5, true)
    SetCamActive(editorCam, true)
    RenderScriptCams(true, true, 300, true, true)
end

local function stopCamera()
    if not editorCam then return end
    RenderScriptCams(false, true, 300, true, true)
    DestroyCam(editorCam, false)
    editorCam = nil
end

local function enterEditorCamera()
    inEditor = true
    DisplayRadar(false)
    startCamera()
    forceVisible()
end

local function exitEditorCamera()
    inEditor = false
    stopCamera()
    DisplayRadar(true)
    forceVisible()
end

local openAppearanceMenu = function() end
local openCreatorMenu = function() end
local openBodyMenu = function() end
local openFaceMenu = function() end
local openHairMenu = function() end
local openClothingMenu = function() end
local openClothingCategory = function(category) end
local openWardrobeMenu = function() end

local function refreshState(callback)
    CreateThread(function()
        local state = lib.callback.await('node7-appearance:server:getState', false) or {}
        currentSkin = mergeDefaults(state.skin or currentSkin)
        currentClothes = cloneTable(state.clothes or currentClothes) or {}
        if callback then callback(state) end
    end)
end

openAppearanceMenu = function()
    lib.registerContext({
        id = 'node7_appearance_main',
        title = 'NODE7 Appearance',
        options = {
            { title = 'Character Creator', description = 'Body, face, hair, and base appearance.', icon = 'user', onSelect = openCreatorMenu },
            { title = 'Clothing Store', description = 'Edit clothing with ox_lib menus.', icon = 'shirt', onSelect = openClothingMenu },
            { title = 'Wardrobe / Outfits', description = 'Use, save, or delete outfits.', icon = 'box-open', onSelect = openWardrobeMenu },
            { title = 'Load Saved Appearance', description = 'Reload saved skin and clothing.', icon = 'rotate-right', onSelect = function() TriggerServerEvent('node7-appearance:server:loadSaved') end },
            { title = 'Fix Visibility', description = 'Force visible ped/collision repair.', icon = 'eye', onSelect = function() forceVisible(); notify('Visibility repaired.', 'success') end }
        }
    })
    lib.showContext('node7_appearance_main')
end

openCreatorMenu = function()
    enterEditorCamera()
    currentSkin = mergeDefaults(currentSkin)
    lib.registerContext({
        id = 'node7_appearance_creator',
        title = 'Character Creator',
        menu = 'node7_appearance_main',
        onExit = exitEditorCamera,
        options = {
            { title = 'Male Model', description = 'Switch to mp_male.', icon = 'person', onSelect = function() currentSkin.sex = 1; currentSkin.model = 'mp_male'; applySkin(currentSkin); openCreatorMenu() end },
            { title = 'Female Model', description = 'Switch to mp_female.', icon = 'person-dress', onSelect = function() currentSkin.sex = 2; currentSkin.model = 'mp_female'; applySkin(currentSkin); openCreatorMenu() end },
            { title = 'Body', description = 'Head, skin tone, height, body size.', icon = 'person', onSelect = openBodyMenu },
            { title = 'Face Features', description = 'Face, eyes, nose, mouth, jaw, chin, ears.', icon = 'face-smile', onSelect = openFaceMenu },
            { title = 'Hair / Beard', description = 'Hair and beard model/texture.', icon = 'scissors', onSelect = openHairMenu },
            { title = 'Save Appearance', description = 'Save skin to citizenid.', icon = 'floppy-disk', onSelect = function() saveSkin(); exitEditorCamera() end },
            { title = 'Exit Editor', icon = 'xmark', onSelect = exitEditorCamera }
        }
    })
    lib.showContext('node7_appearance_creator')
end

openBodyMenu = function()
    local inputs = lib.inputDialog('Body', {
        { type = 'number', label = 'Head', description = '1 - 120', default = tonumber(currentSkin.head) or 1, min = 1, max = 120 },
        { type = 'number', label = 'Skin Tone', description = '1 - 6', default = tonumber(currentSkin.skin_tone) or 1, min = 1, max = 6 },
        { type = 'number', label = 'Body Size', description = '1 - 6', default = tonumber(currentSkin.body_size) or 1, min = 1, max = 6 },
        { type = 'number', label = 'Waist', description = '1 - 21', default = tonumber(currentSkin.body_waist) or 11, min = 1, max = 21 },
        { type = 'number', label = 'Chest', description = '1 - 11', default = tonumber(currentSkin.chest_size) or 6, min = 1, max = 11 },
        { type = 'number', label = 'Height', description = '90 - 110', default = tonumber(currentSkin.height) or 100, min = 90, max = 110 }
    })
    if inputs then
        currentSkin.head = normalizeNumber(inputs[1], 1, 1, 120)
        currentSkin.skin_tone = normalizeNumber(inputs[2], 1, 1, 6)
        currentSkin.body_size = normalizeNumber(inputs[3], 1, 1, 6)
        currentSkin.body_waist = normalizeNumber(inputs[4], 11, 1, 21)
        currentSkin.chest_size = normalizeNumber(inputs[5], 6, 1, 11)
        currentSkin.height = normalizeNumber(inputs[6], 100, 90, 110)
        applySkin(currentSkin, currentClothes)
    end
    openCreatorMenu()
end

openFaceMenu = function()
    local options = {}
    for _, key in ipairs((Config.FeatureGroups and Config.FeatureGroups.face) or {}) do
        options[#options + 1] = {
            title = labelFor(key),
            description = ('Current: %s'):format(tostring(currentSkin[key] or 0)),
            icon = 'sliders',
            onSelect = function()
                local input = lib.inputDialog(labelFor(key), {
                    { type = 'number', label = 'Value', description = '-100 to 100', default = tonumber(currentSkin[key]) or 0, min = -100, max = 100 }
                })
                if input then
                    currentSkin[key] = normalizeNumber(input[1], 0, -100, 100)
                    applyFeatures(PlayerPedId(), currentSkin)
                end
                openFaceMenu()
            end
        }
    end
    options[#options + 1] = { title = 'Back', icon = 'arrow-left', onSelect = openCreatorMenu }
    lib.registerContext({ id = 'node7_appearance_face', title = 'Face Features', menu = 'node7_appearance_creator', options = options })
    lib.showContext('node7_appearance_face')
end

local function editHairCategory(category)
    local list = getHairList(category) or {}
    local item = currentSkin[category]
    if type(item) ~= 'table' then item = { model = 0, texture = 1 } end
    local maxModel = #list
    local maxTexture = 1
    if list[tonumber(item.model) or 1] then maxTexture = #list[tonumber(item.model) or 1] end

    local input = lib.inputDialog(labelFor(category), {
        { type = 'number', label = 'Model', description = ('0 - %s'):format(maxModel), default = tonumber(item.model) or 0, min = 0, max = maxModel },
        { type = 'number', label = 'Texture', description = ('1 - %s'):format(maxTexture), default = tonumber(item.texture) or 1, min = 1, max = maxTexture },
        { type = 'checkbox', label = 'Remove' }
    })

    if input then
        currentSkin[category] = {
            model = normalizeNumber(input[1], 0, 0, maxModel),
            texture = normalizeNumber(input[2], 1, 1, maxTexture),
            remove = input[3] == true
        }
        currentSkin[category].hash = getItemHash(list, currentSkin[category].model, currentSkin[category].texture)
        applyHairItem(category)
    end
    openHairMenu()
end

openHairMenu = function()
    lib.registerContext({
        id = 'node7_appearance_hair',
        title = 'Hair / Beard',
        menu = 'node7_appearance_creator',
        options = {
            { title = 'Hair', description = 'Edit hair model/texture.', icon = 'scissors', onSelect = function() editHairCategory('hair') end },
            { title = 'Beard', description = 'Edit beard model/texture.', icon = 'user', onSelect = function() editHairCategory('beard') end },
            { title = 'Back', icon = 'arrow-left', onSelect = openCreatorMenu }
        }
    })
    lib.showContext('node7_appearance_hair')
end

local function categoryStatus(category)
    local item = currentClothes[category]
    if type(item) ~= 'table' then return 'Not selected' end
    if item.remove then return 'Removed' end
    return ('Model %s / Texture %s'):format(tostring(item.model or 0), tostring(item.texture or 1))
end

openClothingMenu = function()
    forceVisible()
    local options = {}
    for _, category in ipairs(Config.ClothingCategories or {}) do
        if getClothingList(category) then
            options[#options + 1] = {
                title = labelFor(category),
                description = categoryStatus(category),
                icon = 'shirt',
                arrow = true,
                onSelect = function() openClothingCategory(category) end
            }
        end
    end
    options[#options + 1] = { title = 'Save Clothes', description = 'Save current clothing to citizenid.', icon = 'floppy-disk', onSelect = saveClothes }
    options[#options + 1] = { title = 'Save As Outfit', description = 'Name and save current outfit.', icon = 'box-archive', onSelect = function()
        local input = lib.inputDialog('Save Outfit', { { type = 'input', label = 'Outfit Name', required = true, min = 1, max = 64 } })
        if input and input[1] then
            TriggerServerEvent('node7-appearance:server:saveOutfit', currentClothes, input[1])
        end
    end }
    options[#options + 1] = { title = 'Wardrobe / Outfits', icon = 'box-open', onSelect = openWardrobeMenu }
    options[#options + 1] = { title = 'Fix Visibility', icon = 'eye', onSelect = forceVisible }

    lib.registerContext({ id = 'node7_appearance_clothing', title = 'Clothing Store', menu = 'node7_appearance_main', options = options })
    lib.showContext('node7_appearance_clothing')
end

openClothingCategory = function(category)
    local list = getClothingList(category) or {}
    local item = currentClothes[category]
    if type(item) ~= 'table' then item = { model = 0, texture = 1 } end

    local model = normalizeNumber(item.model, 0, 0, #list)
    local texture = normalizeNumber(item.texture, 1, 1, 999)
    local textureMax = 1
    if model > 0 and list[model] then textureMax = #list[model] end
    texture = normalizeNumber(texture, 1, 1, textureMax)

    local function setAndReopen(newModel, newTexture, remove)
        currentClothes[category] = {
            model = normalizeNumber(newModel, 0, 0, #list),
            texture = normalizeNumber(newTexture, 1, 1, textureMax),
            remove = remove == true
        }
        if not currentClothes[category].remove then
            currentClothes[category].hash = getItemHash(list, currentClothes[category].model, currentClothes[category].texture)
        end
        applyClothingItem(category)
        openClothingCategory(category)
    end

    lib.registerContext({
        id = 'node7_appearance_cat_' .. category,
        title = labelFor(category),
        menu = 'node7_appearance_clothing',
        options = {
            { title = 'Current', description = ('Model %s / Texture %s / Max textures %s'):format(model, texture, textureMax), disabled = true },
            { title = 'Previous Model', icon = 'chevron-left', onSelect = function() setAndReopen(model - 1, 1, false) end },
            { title = 'Next Model', icon = 'chevron-right', onSelect = function() setAndReopen(model + 1, 1, false) end },
            { title = 'Previous Texture', icon = 'minus', onSelect = function() setAndReopen(model, texture - 1, false) end },
            { title = 'Next Texture', icon = 'plus', onSelect = function() setAndReopen(model, texture + 1, false) end },
            { title = 'Set Exact Model/Texture', icon = 'keyboard', onSelect = function()
                local input = lib.inputDialog(labelFor(category), {
                    { type = 'number', label = 'Model', description = ('0 - %s'):format(#list), default = model, min = 0, max = #list },
                    { type = 'number', label = 'Texture', description = ('1 - %s'):format(textureMax), default = texture, min = 1, max = textureMax }
                })
                if input then setAndReopen(input[1], input[2], false) else openClothingCategory(category) end
            end },
            { title = 'Remove Item', icon = 'trash', onSelect = function() setAndReopen(0, 1, true) end },
            { title = 'Save Clothes', icon = 'floppy-disk', onSelect = function() saveClothes(); openClothingCategory(category) end },
            { title = 'Back', icon = 'arrow-left', onSelect = openClothingMenu }
        }
    })
    lib.showContext('node7_appearance_cat_' .. category)
end

openWardrobeMenu = function()
    refreshState(function(state)
        local outfits = state.outfits or {}
        local options = {}
        for _, outfit in ipairs(outfits) do
            options[#options + 1] = {
                title = outfit.name,
                description = 'Use or delete this outfit.',
                icon = 'box',
                arrow = true,
                onSelect = function()
                    lib.registerContext({
                        id = 'node7_appearance_outfit_' .. tostring(outfit.id),
                        title = outfit.name,
                        menu = 'node7_appearance_wardrobe',
                        options = {
                            { title = 'Wear Outfit', icon = 'shirt', onSelect = function() applyClothes(outfit.clothing); TriggerServerEvent('node7-appearance:server:saveClothes', outfit.clothing); openWardrobeMenu() end },
                            { title = 'Delete Outfit', icon = 'trash', onSelect = function() TriggerServerEvent('node7-appearance:server:deleteOutfit', outfit.id); SetTimeout(300, openWardrobeMenu) end },
                            { title = 'Back', icon = 'arrow-left', onSelect = openWardrobeMenu }
                        }
                    })
                    lib.showContext('node7_appearance_outfit_' .. tostring(outfit.id))
                end
            }
        end
        options[#options + 1] = { title = 'Save Current Outfit', icon = 'floppy-disk', onSelect = function()
            local input = lib.inputDialog('Save Outfit', { { type = 'input', label = 'Outfit Name', required = true, min = 1, max = 64 } })
            if input and input[1] then
                TriggerServerEvent('node7-appearance:server:saveOutfit', currentClothes, input[1])
            end
        end }
        options[#options + 1] = { title = 'Reload Saved Clothes', icon = 'rotate-right', onSelect = function()
            local clothes = lib.callback.await('node7-appearance:server:getClothes', false) or {}
            applyClothes(clothes)
        end }
        options[#options + 1] = { title = 'Back', icon = 'arrow-left', onSelect = openAppearanceMenu }

        lib.registerContext({ id = 'node7_appearance_wardrobe', title = 'Wardrobe', menu = 'node7_appearance_main', options = options })
        lib.showContext('node7_appearance_wardrobe')
    end)
end

RegisterNetEvent('node7-appearance:client:open', function()
    refreshState(function() openAppearanceMenu() end)
end)

RegisterNetEvent('node7-appearance:client:openCreator', function(data)
    if type(data) == 'table' then currentSkin = mergeDefaults(data) end
    refreshState(function() openCreatorMenu() end)
end)

RegisterNetEvent('node7-appearance:client:openClothing', function()
    refreshState(function() openClothingMenu() end)
end)

RegisterNetEvent('node7-appearance:client:openWardrobe', function()
    refreshState(function() openWardrobeMenu() end)
end)

RegisterNetEvent('node7-appearance:client:ApplySkin', function(skin, clothes)
    applySkin(skin, clothes)
end)

RegisterNetEvent('node7-appearance:client:ApplyClothes', function(clothes)
    applyClothes(clothes)
end)

RegisterNetEvent('node7-appearance:client:loadSaved', function()
    TriggerServerEvent('node7-appearance:server:loadSaved')
end)

-- Compatibility aliases for converted RSG resources.
RegisterNetEvent('rsg-appearance:client:OpenCreator', function(data)
    TriggerEvent('node7-appearance:client:openCreator', data)
end)

RegisterNetEvent('rsg-appearance:client:ApplySkin', function(skin, clothes)
    applySkin(skin, clothes)
end)

RegisterNetEvent('rsg-appearance:client:ApplyClothes', function(clothes, target)
    applyClothes(clothes)
end)

RegisterNetEvent('rsg-appearance:client:outfits', function()
    openWardrobeMenu()
end)

RegisterCommand('appearance', function() TriggerEvent('node7-appearance:client:open') end, false)
RegisterCommand('creator', function() TriggerEvent('node7-appearance:client:openCreator') end, false)
RegisterCommand('charcreator', function() TriggerEvent('node7-appearance:client:openCreator') end, false)
RegisterCommand('clothing', function() TriggerEvent('node7-appearance:client:openClothing') end, false)
RegisterCommand('clothes', function() TriggerEvent('node7-appearance:client:openClothing') end, false)
RegisterCommand('tailor', function() TriggerEvent('node7-appearance:client:openClothing') end, false)
RegisterCommand('wardrobe', function() TriggerEvent('node7-appearance:client:openWardrobe') end, false)
RegisterCommand('outfits', function() TriggerEvent('node7-appearance:client:openWardrobe') end, false)
RegisterCommand('loadappearance', function() TriggerServerEvent('node7-appearance:server:loadSaved') end, false)
RegisterCommand('loadskin', function() TriggerServerEvent('node7-appearance:server:loadSaved') end, false)
RegisterCommand('fixvisible', function() forceVisible(); notify('Visibility repaired.', 'success') end, false)

CreateThread(function()
    Wait(1500)
    refreshState(function(state)
        currentSkin = mergeDefaults(state.skin or currentSkin)
        currentClothes = cloneTable(state.clothes or currentClothes) or {}
    end)
end)

CreateThread(function()
    while true do
        local waitTime = 1000
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local nearLabel = nil
        local nearType = nil

        for _, shop in ipairs(Config.Shops or {}) do
            local c = shop.coords
            local distance = #(coords - vector3(c.x, c.y, c.z))
            if distance <= (shop.radius or 2.0) then
                nearLabel = shop.label or 'Tailor'
                nearType = 'clothing'
                waitTime = 0
                break
            end
        end

        if not nearLabel then
            for _, wardrobe in ipairs(Config.Wardrobes or {}) do
                local c = wardrobe.coords
                local distance = #(coords - vector3(c.x, c.y, c.z))
                if distance <= (wardrobe.radius or 2.0) then
                    nearLabel = wardrobe.label or 'Wardrobe'
                    nearType = 'wardrobe'
                    waitTime = 0
                    break
                end
            end
        end

        if nearLabel then
            if not textUiShowing then
                lib.showTextUI(('[E] %s'):format(nearLabel))
                textUiShowing = true
            end
            for _, control in ipairs(Config.OpenControls or {}) do
                if IsControlJustReleased(0, control) or IsControlJustReleased(1, control) or IsControlJustReleased(2, control) then
                    if nearType == 'wardrobe' then
                        TriggerEvent('node7-appearance:client:openWardrobe')
                    else
                        TriggerEvent('node7-appearance:client:openClothing')
                    end
                    Wait(500)
                    break
                end
            end
        elseif textUiShowing then
            lib.hideTextUI()
            textUiShowing = false
        end

        Wait(waitTime)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE_NAME then return end
    if textUiShowing then lib.hideTextUI() end
    stopCamera()
    forceVisible()
end)

exports('OpenAppearance', openAppearanceMenu)
exports('OpenCreator', openCreatorMenu)
exports('OpenClothing', openClothingMenu)
exports('OpenWardrobe', openWardrobeMenu)
exports('ApplySkin', applySkin)
exports('ApplyClothes', applyClothes)
exports('GetCurrentSkin', function() return currentSkin end)
exports('GetCurrentClothes', function() return currentClothes end)
exports('FixVisibility', forceVisible)
