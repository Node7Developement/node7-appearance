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
local interactionPoints = {}

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
    return (Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped, Citizen.ResultAsInteger()) or 0) ~= 0
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

local CATEGORY_BODIES_UPPER = hash('bodies_upper')

local function getCurrentBodyAssets(ped)
    ped = ped or PlayerPedId()
    if not DoesEntityExist(ped) or not nativeHasPedComponentLoaded(ped) then
        return nil
    end

    local count = Citizen.InvokeNative(0x90403E8107B60E81, ped, Citizen.ResultAsInteger()) or 0
    for index = 0, tonumber(count) - 1 do
        local category = Citizen.InvokeNative(0x9B90842304C938A7, ped, index, 0, Citizen.ResultAsInteger())
        if category == CATEGORY_BODIES_UPPER then
            local drawable, albedo, normal, material = Citizen.InvokeNative(
                0xA9C28516A6DC9D56,
                ped,
                index,
                Citizen.PointerValueInt(),
                Citizen.PointerValueInt(),
                Citizen.PointerValueInt(),
                Citizen.PointerValueInt()
            )

            if albedo and albedo ~= 0 and normal and normal ~= 0 and material and material ~= 0 then
                return {
                    drawable = drawable,
                    albedo = albedo,
                    normal = normal,
                    material = material,
                    sex = IsPedMale(ped) and 'male' or 'female',
                    skin = cloneTable(currentSkin),
                }
            end
        end
    end

    return nil
end

local function emitAppearanceApplied(reason)
    CreateThread(function()
        local ped = PlayerPedId()
        local timeout = GetGameTimer() + 5000
        while DoesEntityExist(ped) and not nativeHasPedComponentLoaded(ped) and GetGameTimer() < timeout do
            Wait(0)
        end

        -- Do not inspect live MetaPed component assets here. The inspection native used
        -- by the tattoo bridge is not safe as part of the normal reload path on every
        -- RedM build and could prevent the completion event from firing. Barber and
        -- clothing integrations only need a reliable completion signal plus skin data.
        Wait(100)
        TriggerEvent('node7-appearance:client:applied', {
            reason = reason or 'appearance',
            ped = ped,
            skin = cloneTable(currentSkin),
            clothes = cloneTable(currentClothes),
            body = {
                sex = IsPedMale(ped) and 'male' or 'female',
                skin = cloneTable(currentSkin),
            },
        })
    end)
end

local function setPedComponent(ped, componentHash, deferVariation)
    ped = ped or PlayerPedId()
    componentHash = tonumber(componentHash)
    if not componentHash or componentHash == 0 then return false end

    local ok, err = pcall(function()
        local categoryHash = Citizen.InvokeNative(0x5FF9A878C3D115B8, componentHash, not IsPedMale(ped), true)
        if categoryHash and categoryHash ~= 0 then
            Citizen.InvokeNative(0x59BD177A1A48600A, ped, categoryHash)
        end
        -- RedM MP shop items use the normal final=true commit path.
        -- Facial hair does not persist reliably when this flag is false.
        Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, false, true, true)
        if not deferVariation then
            updatePedVariation(ped)
        end
    end)

    if not ok then
        debugLog(('component apply failed: %s'):format(tostring(err)))
    end

    return ok
end

local function removePedCategory(ped, category, deferVariation)
    ped = ped or PlayerPedId()
    local ok, err = pcall(function()
        Citizen.InvokeNative(0xD710A5007C2AC539, ped, hash(category), 0)
        if not deferVariation then
            updatePedVariation(ped)
        end
    end)
    if not ok then
        debugLog(('component remove failed: %s'):format(tostring(err)))
    end
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

local CACHEABLE_COMPONENTS = {
    BODIES_LOWER = true,
    BODIES_UPPER = true,
    heads = true,
    hair = true,
    teeth = true,
    eyes = true
}

local function buildComponentCaches()
    componentsMale = {}
    componentsFemale = {}
    headHashTable = {}

    for _, item in pairs(clothesList or {}) do
        if item and item.is_multiplayer and item.hashname and item.hashname ~= '' then
            local category = item.category_hashname
            local componentHash = tonumber(item.hash)
            if CACHEABLE_COMPONENTS[category] and componentHash then
                local target = item.ped_type == 'female' and componentsFemale or componentsMale
                target[category] = target[category] or {}
                target[category][#target[category] + 1] = componentHash
            end
            if category == 'heads' and componentHash then
                headHashTable[item.hashname] = componentHash
            end
        end
    end
    debugLog('component caches ready')
end

local function addInteractionPoint(entry, interactionType)
    if type(entry) ~= 'table' or type(entry.coords) ~= 'table' then return end
    local coords = entry.coords
    local radius = tonumber(entry.radius) or 2.0
    interactionPoints[#interactionPoints + 1] = {
        label = entry.label or (interactionType == 'wardrobe' and 'Wardrobe' or 'Tailor'),
        type = interactionType,
        x = tonumber(coords.x) or 0.0,
        y = tonumber(coords.y) or 0.0,
        z = tonumber(coords.z) or 0.0,
        radiusSquared = radius * radius
    }
end

local function buildInteractionPoints()
    interactionPoints = {}
    for _, shop in ipairs(Config.Shops or {}) do
        addInteractionPoint(shop, 'clothing')
    end
    for _, wardrobe in ipairs(Config.Wardrobes or {}) do
        addInteractionPoint(wardrobe, 'wardrobe')
    end
end

CreateThread(function()
    buildComponentCaches()
    buildInteractionPoints()
end)

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
        setPedComponent(ped, components.BODIES_UPPER[bodyIndex], true)
    end
    if components.BODIES_LOWER and components.BODIES_LOWER[bodyIndex] then
        setPedComponent(ped, components.BODIES_LOWER[bodyIndex], true)
    end
    setPedComponent(ped, getHeadHash(IsPedMale(ped), headNum, skin.skin_tone), true)

    if components.eyes and components.eyes[tonumber(skin.eyes_color) or 1] then
        setPedComponent(ped, components.eyes[tonumber(skin.eyes_color) or 1], true)
    end
    if components.teeth and components.teeth[tonumber(skin.teeth) or 1] then
        setPedComponent(ped, components.teeth[tonumber(skin.teeth) or 1], true)
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

local function applyClothingItem(category, ped, deferVariation)
    local item = currentClothes[category]
    if not item then return false end

    ped = ped or PlayerPedId()
    if item.remove then
        return removePedCategory(ped, category, deferVariation)
    end

    local componentHash = tonumber(item.hash)
    if not componentHash then
        componentHash = getItemHash(getClothingList(category), item.model, item.texture)
        item.hash = componentHash
    end

    return componentHash and setPedComponent(ped, componentHash, deferVariation) or false
end

local function applyHairItem(category, ped, deferVariation)
    local item = currentSkin[category]
    if not item then return false end

    ped = ped or PlayerPedId()
    local categoryHash = category == 'hair' and 0x864B03AE or 0xF8016BCA
    if item.remove or tonumber(item.model) == 0 then
        local ok, err = pcall(function()
            Citizen.InvokeNative(0xD710A5007C2AC539, ped, categoryHash, 0)
            if not deferVariation then
                updatePedVariation(ped)
            end
        end)
        if not ok then
            debugLog(('hair remove failed: %s'):format(tostring(err)))
        end
        return ok
    end

    local componentHash = tonumber(item.hash)
    if not componentHash then
        componentHash = getItemHash(getHairList(category), item.model, item.texture)
        item.hash = componentHash
    end

    return componentHash and setPedComponent(ped, componentHash, deferVariation) or false
end

local function restoreHairAndBeardAfterClothes(ped)
    ped = ped or PlayerPedId()

    -- Clothing rebuilds can remove MetaPed hair categories. Apply hair after the
    -- clothing variation pass, then make beard the absolute final component with
    -- no variation refresh after it. This preserves paid barber beards through
    -- /rc, /loadskin, masks, bandanas, and outfit reloads.
    if currentSkin.hair then
        applyHairItem('hair', ped, false)
    end
    if currentSkin.beard then
        applyHairItem('beard', ped, true)
    end
end

local function applyClothes(clothes, suppressAppliedEvent)
    currentClothes = type(clothes) == 'table' and (cloneTable(clothes) or {}) or {}
    local ped = PlayerPedId()
    local changed = false

    for category in pairs(currentClothes) do
        changed = applyClothingItem(category, ped, true) or changed
        Wait(0)
    end

    if changed then
        updatePedVariation(ped)
    else
        forceVisible()
    end

    restoreHairAndBeardAfterClothes(ped)
    forceVisible()

    if not suppressAppliedEvent then
        emitAppearanceApplied('clothes')
    end
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

    -- Clothing must be applied before hair/beard. The previous order applied the
    -- beard first and then removed it again during the clothing MetaPed rebuild.
    if clothes then
        applyClothes(clothes, true)
    else
        restoreHairAndBeardAfterClothes(ped)
    end

    forceVisible()
    emitAppearanceApplied('skin')
end

local function saveSkin()
    TriggerServerEvent('node7-appearance:server:saveSkin', currentSkin)
end

local function saveClothes()
    TriggerServerEvent('node7-appearance:server:saveClothes', currentClothes)
end

local function requestSavedAppearance()
    TriggerServerEvent('node7-appearance:server:loadSaved')
end

local function repairVisibility()
    forceVisible()
    notify('Visibility repaired.', 'success')
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
    DisplayRadar(false)
    startCamera()
    forceVisible()
end

local function exitEditorCamera()
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
            { title = 'Load Saved Appearance', description = 'Reload saved skin and clothing.', icon = 'rotate-right', onSelect = requestSavedAppearance },
            { title = 'Fix Visibility', description = 'Force visible ped/collision repair.', icon = 'eye', onSelect = repairVisibility }
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

local function normalizeClothingItem(list, model, texture, remove)
    local normalizedModel = normalizeNumber(model, 0, 0, #list)
    local textureMax = normalizedModel > 0 and list[normalizedModel] and #list[normalizedModel] or 1
    local item = {
        model = normalizedModel,
        texture = normalizeNumber(texture, 1, 1, textureMax),
        remove = remove == true
    }
    if not item.remove then
        item.hash = getItemHash(list, item.model, item.texture)
    end
    return item, textureMax
end

local function categoryStatus(category)
    local item = currentClothes[category]
    if type(item) ~= 'table' then return 'Not selected' end
    if item.remove then return 'Removed' end
    return ('Model %s / Texture %s'):format(tostring(item.model or 0), tostring(item.texture or 1))
end

local function promptSaveCurrentOutfit()
    local input = lib.inputDialog('Save Outfit', {
        { type = 'input', label = 'Outfit Name', required = true, min = 1, max = 64 }
    })
    if input and input[1] then
        TriggerServerEvent('node7-appearance:server:saveOutfit', currentClothes, input[1])
    end
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
    options[#options + 1] = { title = 'Save As Outfit', description = 'Name and save current outfit.', icon = 'box-archive', onSelect = promptSaveCurrentOutfit }
    options[#options + 1] = { title = 'Wardrobe / Outfits', icon = 'box-open', onSelect = openWardrobeMenu }
    options[#options + 1] = { title = 'Fix Visibility', icon = 'eye', onSelect = forceVisible }

    lib.registerContext({ id = 'node7_appearance_clothing', title = 'Clothing Store', menu = 'node7_appearance_main', options = options })
    lib.showContext('node7_appearance_clothing')
end

openClothingCategory = function(category)
    local list = getClothingList(category) or {}
    local selected = currentClothes[category]
    if type(selected) ~= 'table' then selected = { model = 0, texture = 1 } end

    local item, textureMax = normalizeClothingItem(list, selected.model, selected.texture, selected.remove)
    local model = item.model
    local texture = item.texture

    local function setAndReopen(newModel, newTexture, remove)
        currentClothes[category] = normalizeClothingItem(list, newModel, newTexture, remove)
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
        options[#options + 1] = { title = 'Save Current Outfit', icon = 'floppy-disk', onSelect = promptSaveCurrentOutfit }
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

local function handleApplyClothes(clothes)
    applyClothes(clothes)
end

RegisterNetEvent('node7-appearance:client:ApplySkin', applySkin)
RegisterNetEvent('node7-appearance:client:ApplyClothes', handleApplyClothes)

RegisterNetEvent('node7-appearance:client:loadSaved', requestSavedAppearance)

local function setBarberState(style, savedSkin)
    if type(savedSkin) == 'table' then
        currentSkin = cloneTable(savedSkin) or currentSkin
    end

    if type(style) == 'table' then
        if type(style.hair) == 'table' then currentSkin.hair = cloneTable(style.hair) end
        if type(style.beard) == 'table' then currentSkin.beard = cloneTable(style.beard) end
    end

    return true
end

RegisterNetEvent('node7-appearance:client:setBarberState', function(style, savedSkin)
    setBarberState(style, savedSkin)
end)

exports('SetBarberState', setBarberState)

-- Compatibility aliases for converted RSG resources.
RegisterNetEvent('rsg-appearance:client:OpenCreator', function(data)
    TriggerEvent('node7-appearance:client:openCreator', data)
end)

RegisterNetEvent('rsg-appearance:client:ApplySkin', applySkin)
RegisterNetEvent('rsg-appearance:client:ApplyClothes', handleApplyClothes)

RegisterNetEvent('rsg-appearance:client:outfits', function()
    openWardrobeMenu()
end)

local function registerCommandAliases(commands, handler)
    for _, command in ipairs(commands) do
        RegisterCommand(command, handler, false)
    end
end

registerCommandAliases({ 'appearance' }, function()
    TriggerEvent('node7-appearance:client:open')
end)
registerCommandAliases({ 'creator', 'charcreator' }, function()
    TriggerEvent('node7-appearance:client:openCreator')
end)
registerCommandAliases({ 'clothing', 'clothes', 'tailor' }, function()
    TriggerEvent('node7-appearance:client:openClothing')
end)
registerCommandAliases({ 'wardrobe', 'outfits' }, function()
    TriggerEvent('node7-appearance:client:openWardrobe')
end)
registerCommandAliases({ 'loadappearance', 'loadskin', 'rc' }, requestSavedAppearance)
registerCommandAliases({ 'fixvisible' }, repairVisibility)

CreateThread(function()
    Wait(1500)
    refreshState(function(state)
        currentSkin = mergeDefaults(state.skin or currentSkin)
        currentClothes = cloneTable(state.clothes or currentClothes) or {}
    end)
end)

local function getNearbyInteraction(coords)
    for _, point in ipairs(interactionPoints) do
        local dx = coords.x - point.x
        local dy = coords.y - point.y
        local dz = coords.z - point.z
        if (dx * dx + dy * dy + dz * dz) <= point.radiusSquared then
            return point
        end
    end
end

local function interactionControlReleased()
    for _, control in ipairs(Config.OpenControls or {}) do
        if IsControlJustReleased(0, control)
            or IsControlJustReleased(1, control)
            or IsControlJustReleased(2, control) then
            return true
        end
    end
    return false
end

CreateThread(function()
    while true do
        local point = getNearbyInteraction(GetEntityCoords(PlayerPedId()))
        local waitTime = point and 0 or 1000

        if point then
            if not textUiShowing then
                lib.showTextUI(('[E] %s'):format(point.label))
                textUiShowing = true
            end

            if interactionControlReleased() then
                TriggerEvent(point.type == 'wardrobe'
                    and 'node7-appearance:client:openWardrobe'
                    or 'node7-appearance:client:openClothing')
                Wait(500)
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
exports('TattooBridgeReady', function() return true end)
exports('GetTattooBodyTextureSet', function()
    local body = getCurrentBodyAssets(PlayerPedId())
    if body then body.source = 'node7-appearance-export' end
    return body
end)
exports('RefreshTattooBodyTextureSet', function()
    updatePedVariation(PlayerPedId())
    emitAppearanceApplied('tattoo_refresh')
    return getCurrentBodyAssets(PlayerPedId())
end)
exports('FixVisibility', forceVisible)
