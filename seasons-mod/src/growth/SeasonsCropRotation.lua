----------------------------------------------------------------------------------------------------
-- SeasonsCropRotation
----------------------------------------------------------------------------------------------------
-- Purpose:  Crop rotation
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsCropRotation = {}
local SeasonsCropRotation_mt = Class(SeasonsCropRotation)

SeasonsCropRotation.MAP_NUM_CHANNELS = 2 * 3 + 1 + 1 -- [n-2][n-1][f][h]

SeasonsCropRotation.CATEGORIES = {
    FALLOW = 0,
    OILSEED = 1,
    CEREAL = 2,
    LEGUME = 3,
    ROOT = 4,
    NIGHTSHADE = 5,
    GRASS = 6
}
SeasonsCropRotation.CATEGORIES_MAX = 6

function SeasonsCropRotation:new(mission, environment, messageCenter, fruitTypeManager, densityMapScanner, i18n, data)
    local self = setmetatable({}, SeasonsCropRotation_mt)

    self.mission = mission
    self.environment = environment
    self.messageCenter = messageCenter
    self.fruitTypeManager = fruitTypeManager
    self.densityMapScanner = densityMapScanner
    self.data = data
    self.i18n = i18n

    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "updateSowingArea", SeasonsCropRotation.inj_densityMapUtil_updateSowingArea)
    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "updateDirectSowingArea", SeasonsCropRotation.inj_densityMapUtil_updateSowingArea)
    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "cutFruitArea", SeasonsCropRotation.inj_densityMapUtil_cutFruitArea)

    if g_addCheatCommands then
        addConsoleCommand("rmRunFallow", "Run the yearly fallow", "commandRunFallow", self)
    end
    addConsoleCommand("rmGetRotationInfo", "Get crop rotation info", "commandGetInfo", self)

    return self
end

function SeasonsCropRotation:delete()
    if self.map ~= 0 then
        delete(self.map)
    end

    self.densityMapScanner:unregisterCallback("UpdateFallow")

    if g_addCheatCommands then
        removeConsoleCommand("rmRunFallow")
    end
    removeConsoleCommand("rmGetRotationInfo")

    self.messageCenter:unsubscribeAll(self)
end

----------------------
-- Loading
----------------------

function SeasonsCropRotation:load()
    self:loadModifiers()

    self.densityMapScanner:registerCallback("UpdateFallow", self.dms_updateFallow, self, nil, false)

    self.messageCenter:subscribe(SeasonsMessageType.YEAR_CHANGED, self.onYearChanged, self)
end

function SeasonsCropRotation:onTerrainLoaded()
    self.terrainSize = self.mission.terrainSize

    self:loadMap()
    self:loadModifiers()
end

function SeasonsCropRotation:loadMap()
    self.map = createBitVectorMap("CropRotation")
    local success = false

    if self.mission.missionInfo.isValid then
        local path = self.mission.missionInfo.savegameDirectory .. "/seasons_cropRotation.grle"

        if fileExists(path) then
            success = loadBitVectorMapFromFile(self.map, path, SeasonsCropRotation.MAP_NUM_CHANNELS)
        end
    end

    if not success then
        local size = getDensityMapSize(self.mission.terrainDetailId)
        loadBitVectorMapNew(self.map, size, size, SeasonsCropRotation.MAP_NUM_CHANNELS, false)
    end

    self.mapSize = getBitVectorMapSize(self.map)
end

function SeasonsCropRotation:onMissionLoaded()
end

function SeasonsCropRotation:loadModifiers()
    local terrainDetailId = self.mission.terrainDetailId

    local modifiers = {}

    modifiers.sprayModifier = DensityMapModifier:new(terrainDetailId, self.mission.sprayLevelFirstChannel, self.mission.sprayLevelNumChannels)
    modifiers.filter = DensityMapFilter:new(modifiers.sprayModifier)

    modifiers.terrainSowingFilter = DensityMapFilter:new(terrainDetailId, self.mission.terrainDetailTypeFirstChannel, self.mission.terrainDetailTypeNumChannels)
    modifiers.terrainSowingFilter:setValueCompareParams("between", self.mission.firstSowableValue, self.mission.lastSowableValue)

    modifiers.map = {}
    modifiers.map.modifier = DensityMapModifier:new(self.map, 0, SeasonsCropRotation.MAP_NUM_CHANNELS)
    modifiers.map.modifier:setPolygonRoundingMode("inclusive")
    modifiers.map.filter = DensityMapFilter:new(modifiers.map.modifier)

    modifiers.map.harvestModifier = DensityMapModifier:new(self.map, 0, 1)
    modifiers.map.harvestFilter = DensityMapFilter:new(modifiers.map.harvestModifier)
    modifiers.map.harvestFilter:setValueCompareParams("equals", 0)

    modifiers.map.modifierN2 = DensityMapModifier:new(self.map, 5, 3)
    modifiers.map.filterN2 = DensityMapFilter:new(modifiers.map.modifierN2)

    modifiers.map.modifierN1 = DensityMapModifier:new(self.map, 2, 3)
    modifiers.map.filterN1 = DensityMapFilter:new(modifiers.map.modifierN1)

    modifiers.map.modifierF = DensityMapModifier:new(self.map, 1, 1)
    modifiers.map.filterF = DensityMapFilter:new(modifiers.map.modifierF)
    modifiers.map.filterF:setValueCompareParams("equal", 0)

    modifiers.map.modifierH = DensityMapModifier:new(self.map, 0, 1)

    self.modifiers = modifiers
end

function SeasonsCropRotation:loadFromSavegame(xmlFile)
end

function SeasonsCropRotation:saveToSavegame(xmlFile)
    if self.map ~= 0 then
        saveBitVectorMapToFile(self.map, self.mission.missionInfo.savegameDirectory .. "/seasons_cropRotation.grle")
    end
end

----------------------
-- Reading and writing
----------------------

function SeasonsCropRotation:extractValues(bits)
    -- [n2:3][n1:3][f:1][h:1]

    local n2 = bitShiftRight(bitAND(bits, 224), 5)
    local n1 = bitShiftRight(bitAND(bits, 28), 2)
    local f = bitShiftRight(bitAND(bits, 2), 1)
    local h = bitAND(bits, 1)

    return n2, n1, f, h
end

function SeasonsCropRotation:composeValues(n2, n1, f, h)
    return bitShiftLeft(n2, 5) + bitShiftLeft(n1, 2) + bitShiftLeft(f, 1) + h
end

---Read the n1 and n2 from the map.
function SeasonsCropRotation:readFromMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, filter, skipWhenHarvested, n1Only)
    local terrainSize = self.terrainSize
    local n2, n1 = -1, -1

    local mapModifiers = self.modifiers.map

    -- Read value from CR map
    local mapModifier = mapModifiers.modifier
    mapModifier:setParallelogramUVCoords(startWorldX / terrainSize + 0.5, startWorldZ / terrainSize + 0.5, widthWorldX / terrainSize + 0.5, widthWorldZ / terrainSize + 0.5, heightWorldX / terrainSize + 0.5, heightWorldZ / terrainSize + 0.5, "ppp")
    local mapHarvestFilter = mapModifiers.harvestFilter

    if not n1Only then
        mapModifiers.modifierN2:setParallelogramUVCoords(startWorldX / terrainSize + 0.5, startWorldZ / terrainSize + 0.5, widthWorldX / terrainSize + 0.5, widthWorldZ / terrainSize + 0.5, heightWorldX / terrainSize + 0.5, heightWorldZ / terrainSize + 0.5, "ppp")
        local maxArea = 0
        for i = 0, 6 do
            mapModifiers.filterN2:setValueCompareParams("equal", i)

            local area, totalArea
            if skipWhenHarvested then
                _, area, totalArea = mapModifiers.modifierN2:executeGet(filter, mapHarvestFilter, mapModifiers.filterN2)
            else
                _, area, totalArea = mapModifiers.modifierN2:executeGet(filter, mapModifiers.filterN2)
            end

            if area > maxArea then
                maxArea = area
                n2 = i
            end

            -- Can't find anything larger if we are already at majority
            if area >= totalArea * 0.5 then
                break
            end
        end
    end

    mapModifiers.modifierN1:setParallelogramUVCoords(startWorldX / terrainSize + 0.5, startWorldZ / terrainSize + 0.5, widthWorldX / terrainSize + 0.5, widthWorldZ / terrainSize + 0.5, heightWorldX / terrainSize + 0.5, heightWorldZ / terrainSize + 0.5, "ppp")
    local maxArea = 0
    for i = 0, 6 do
        mapModifiers.filterN1:setValueCompareParams("equal", i)

        local area, totalArea
        if skipWhenHarvested then
            _, area, totalArea = mapModifiers.modifierN1:executeGet(filter, mapHarvestFilter, mapModifiers.filterN1)
        else
            _, area, totalArea = mapModifiers.modifierN1:executeGet(filter, mapModifiers.filterN1)
        end

        if area > maxArea then
            maxArea = area
            n1 = i
        end

        -- Can't find anything larger if we are already at majority
        if area >= totalArea * 0.5 then
            break
        end
    end

    return n2, n1, mapModifier
end

---Write to the rotation map. (Try to prevent using this method as it is not very optimized in complex usage)
function SeasonsCropRotation:writeToMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, bits, filter)
    local modifier = self.modifiers.map.modifier

    self:setParallelogramUVCoords(modifier, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)

    modifier:executeSet(bits, filter)
end

function SeasonsCropRotation:setParallelogramUVCoords(modifier, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local terrainSize = self.terrainSize
    modifier:setParallelogramUVCoords(startWorldX / terrainSize + 0.5, startWorldZ / terrainSize + 0.5, widthWorldX / terrainSize + 0.5, widthWorldZ / terrainSize + 0.5, heightWorldX / terrainSize + 0.5, heightWorldZ / terrainSize + 0.5, "ppp")
end

----------------------
-- Density map scanner functions
----------------------

function SeasonsCropRotation:dms_updateFallow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local terrainSize = self.terrainSize
    local mapModifiers = self.modifiers.map

    mapModifiers.modifierN1:setParallelogramUVCoords(startWorldX / terrainSize + 0.5, startWorldZ / terrainSize + 0.5, widthWorldX / terrainSize + 0.5, widthWorldZ / terrainSize + 0.5, heightWorldX / terrainSize + 0.5, heightWorldZ / terrainSize + 0.5, "ppp")
    mapModifiers.modifierN2:setParallelogramUVCoords(startWorldX / terrainSize + 0.5, startWorldZ / terrainSize + 0.5, widthWorldX / terrainSize + 0.5, widthWorldZ / terrainSize + 0.5, heightWorldX / terrainSize + 0.5, heightWorldZ / terrainSize + 0.5, "ppp")

    local maxArea = 0
    for i = 0, 6 do
        mapModifiers.filterN1:setValueCompareParams("equal", i)

        -- Set [n2]=[n1]
        mapModifiers.modifierN2:executeSet(i, mapModifiers.filterF, mapModifiers.filterN1)

        -- Set [n1]=fallow
        mapModifiers.modifierN1:executeSet(SeasonsCropRotation.CATEGORIES.FALLOW, mapModifiers.filterF, mapModifiers.filterN1)
    end

    -- Reset fallow map
    mapModifiers.modifierF:setParallelogramUVCoords(startWorldX / terrainSize + 0.5, startWorldZ / terrainSize + 0.5, widthWorldX / terrainSize + 0.5, widthWorldZ / terrainSize + 0.5, heightWorldX / terrainSize + 0.5, heightWorldZ / terrainSize + 0.5, "ppp")
    mapModifiers.modifierF:executeSet(0)
end

-----------------------------------
-- Algorithms
-----------------------------------

---Calculate the yield multiplier based on the crop history, fallow state, and harvested fruit type
function SeasonsCropRotation:getRotationYieldMultiplier(n2, n1, fruitType)
    local fruitDesc = self.fruitTypeManager:getFruitTypeByIndex(fruitType)
    local current = fruitDesc.rotation.category

    local returnPeriod = self:getRotationReturnPeriodMultiplier(n2, n1, current, fruitDesc)
    local rotationCategory = self:getRotationCategoryMultiplier(n2, n1, current)

    return returnPeriod * rotationCategory
end

function SeasonsCropRotation:getRotationReturnPeriodMultiplier(n2, n1, current, fruitDesc)
    if fruitDesc.rotation.returnPeriod == 2 then
        -- monoculture
        if n2 == n1 and n2 == current and n1 == current then
            return 0.9
        -- same as last
        elseif n1 == current then
            return 0.95
        end
    elseif fruitDesc.rotation.returnPeriod == 3 then
        -- monoculture
        if n2 == n1 and n2 == current and n1 == current then
            return 0.85
        -- same as last
        elseif n1 == current then
            return 0.9
        -- 1 year between
        elseif n2 == current and n1 ~= current then
            return 0.95
        end
    end

    return 1
end

---Calculate the rotation multiplier based on the previous 2 categories and the current one
function SeasonsCropRotation:getRotationCategoryMultiplier(n2, n1, current)
    local n2Value = self.data:getRotationCategoryValue(n2, current)
    local n1Value = self.data:getRotationCategoryValue(n1, current)

    local n2Factor = -0.05 * n2Value ^ 2 + 0.2 * n2Value + 0.8
    local n1Factor = -0.025 * n1Value ^ 2 + 0.275 * n1Value + 0.75

    return n2Factor * n1Factor
end

----------------------
-- Getting info
----------------------

---Get the categories for given position
function SeasonsCropRotation:getInfoAtWorldCoords(x, z)
    local worldToDensityMap = self.mapSize / self.mission.terrainSize

    local xi = math.floor((x + self.mission.terrainSize * 0.5) * worldToDensityMap)
    local zi = math.floor((z + self.mission.terrainSize * 0.5) * worldToDensityMap)

    local v = getBitVectorMapPoint(self.map, xi, zi, 0, SeasonsCropRotation.MAP_NUM_CHANNELS)
    local n2, n1, f, h = self:extractValues(v)

    return n2, n1, f, h
end

---Get the translated name of the given category
function SeasonsCropRotation:getCategoryName(category)
    return self.i18n:getText(string.format("seasons_rotationCategory_%d", category))
end

---Get a recommended fruit type index based on given data. Returns nil for 'any'
function SeasonsCropRotation:getRecommendation(n2, n1)
    if n2 == SeasonsCropRotation.CATEGORIES.FALLOW and n1 == SeasonsCropRotation.CATEGORIES.FALLOW then
        return nil
    end

    local bestCrop = nil
    local bestYield = 0

    for index, fruitDesc in pairs(g_fruitTypeManager:getFruitTypes()) do
        if fruitDesc.rotation ~= nil then
            local currentYield = self:getRotationYieldMultiplier(n2, n1, index)
            if bestYield < currentYield then
                bestYield = currentYield
                bestCrop = index
            end
        end
    end

    return bestCrop
end

function SeasonsCropRotation:getRandomRecommendation(n2, n1)
    if n2 == SeasonsCropRotation.CATEGORIES.FALLOW and n1 == SeasonsCropRotation.CATEGORIES.FALLOW then
        return nil
    end

    local ordered = {}

    for index, fruitDesc in pairs(g_fruitTypeManager:getFruitTypes()) do
        if fruitDesc.rotation ~= nil then
            local yield = self:getRotationYieldMultiplier(n2, n1, index)
            table.insert(ordered, {index, yield})
        end
    end

    table.sort(ordered, function (a, b)
        return a[2] > b[2]
    end)

    -- Get an item from the top 3
    local i = math.min(math.ceil(math.random() * 3), #ordered)

    return ordered[i].index
end

----------------------
-- Events
----------------------

---The year changed, update fallow state
function SeasonsCropRotation:onYearChanged()
    self.densityMapScanner:queueJob("UpdateFallow")
end

----------------------
-- Injections
----------------------

---Reset harvest bit
function SeasonsCropRotation.inj_densityMapUtil_updateSowingArea(superFunc, fruitId, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, angle, growthState, blockedSprayTypeIndex)
    -- Oilseed ignores crop rotation
    if fruitId ~= FruitType.OILSEEDRADISH then
        local cropRotation = g_seasons.growth.cropRotation
        local modifiers = cropRotation.modifiers

        -- Set harvest bit to 0
        local terrainSize = cropRotation.terrainSize
        modifiers.map.harvestModifier:setParallelogramUVCoords(startWorldX / terrainSize + 0.5, startWorldZ / terrainSize + 0.5, widthWorldX / terrainSize + 0.5, widthWorldZ / terrainSize + 0.5, heightWorldX / terrainSize + 0.5, heightWorldZ / terrainSize + 0.5, "ppp")
        modifiers.map.harvestModifier:executeSet(0)
    end

    -- Do the actual sowing
    return superFunc(fruitId, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, angle, growthState, blockedSprayTypeIndex)
end

---Update the rotation map
function SeasonsCropRotation.inj_densityMapUtil_cutFruitArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, destroySeedingWidth, useMinForageState, excludedSprayType, setsWeeds)
    -- Oilseed ignores crop rotation
    if fruitIndex == FruitType.OILSEEDRADISH then
        return superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, destroySeedingWidth, useMinForageState, excludedSprayType, setsWeeds)
    end

    local cropRotation = g_seasons.growth.cropRotation

    -- Get fruit info
    local desc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    local ids = g_currentMission.fruits[fruitIndex]
    if ids == nil or ids.id == 0 then
        return 0
    end

    -- Filter on fruit to limit bad hits like grass borders
    local fruitFilter = cropRotation.modifiers.filter
    local minState = useMinForageState and desc.minForageGrowthState or desc.minHarvestingGrowthState
    fruitFilter:resetDensityMapAndChannels(ids.id, desc.startStateChannel, desc.numStateChannels)
    fruitFilter:setValueCompareParams("between", minState + 1, desc.maxHarvestingGrowthState + 1)

    -- Read CR data
    local n2, n1, mapModifier = cropRotation:readFromMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, fruitFilter, true, false)
    local yieldMultiplier = 1

    -- When there is nothing read, don't do anything. It will be wrong.
    if n2 ~= -1 or n1 ~= -1 then
        -- Calculate the multiplier
        yieldMultiplier = cropRotation:getRotationYieldMultiplier(n2, n1, fruitIndex)

        -- Then update the values. Set [n-2] = [n-1], [n-1] = current, [f] = 1
        n2 = n1
        n1 = desc.rotation.category
        f = 1
        h = 1

        local bits = cropRotation:composeValues(n2, n1, f, h)

        -- Modifications have to be done sparsely, so when the harvester covers the next area the old values are still available (including h=0)
        mapModifier:executeSet(bits, fruitFilter, cropRotation.modifiers.map.harvestFilter)
    end

    local numPixels, totalNumPixels, sprayFactor, plowFactor, limeFactor, weedFactor, growthState, maxArea, terrainDetailPixelsSum = superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, destroySeedingWidth, useMinForageState, excludedSprayType, setsWeeds)

    -- Update yield
    return numPixels * yieldMultiplier, totalNumPixels, sprayFactor, plowFactor, limeFactor, weedFactor, growthState, maxArea, terrainDetailPixelsSum
end

----------------------
-- Console commands
----------------------

function SeasonsCropRotation:commandRunFallow()
    self.densityMapScanner:queueJob("UpdateFallow")
end

function SeasonsCropRotation:commandGetInfo()
    local x, _, z = getWorldTranslation(getCamera(0))

    local n2, n1 = self:getInfoAtWorldCoords(x, z)

    log(self:getCategoryName(n2), self:getCategoryName(n1))
end

----------------------
-- Debugging
----------------------

function SeasonsCropRotation:visualize()
    if true then
        return
    end

    local mapSize = getBitVectorMapSize(self.map)
    local terrainSize = self.mission.terrainSize

    local worldToDensityMap = mapSize / terrainSize
    local densityToWorldMap = terrainSize / mapSize

    if self.map ~= 0 then
        local x,y,z = getWorldTranslation(getCamera(0))

        if self.mission.controlledVehicle ~= nil then
            local object = self.mission.controlledVehicle

            if self.mission.controlledVehicle.selectedImplement ~= nil then
                object = self.mission.controlledVehicle.selectedImplement.object
            end

            x, y, z = getWorldTranslation(object.components[1].node)
        end

        local terrainHalfSize = terrainSize * 0.5
        local xi = math.floor((x + terrainHalfSize) * worldToDensityMap)
        local zi = math.floor((z + terrainHalfSize) * worldToDensityMap)

        local minXi = math.max(xi - 20, 0)
        local minZi = math.max(zi - 20, 0)
        local maxXi = math.min(xi + 20, mapSize - 1)
        local maxZi = math.min(zi + 20, mapSize - 1)

        for zi = minZi, maxZi do
            for xi = minXi, maxXi do
                local v = getBitVectorMapPoint(self.map, xi, zi, 0, SeasonsCropRotation.MAP_NUM_CHANNELS)

                local x = (xi * densityToWorldMap) - terrainHalfSize
                local z = (zi * densityToWorldMap) - terrainHalfSize
                local y = getTerrainHeightAtWorldPos(self.mission.terrainRootNode, x,0,z) + 0.05

                local n2, n1, f, h = self:extractValues(v)

                local r,g,b = 1, 0, h

                local text = string.format("%d,%d,%d,%d", n2, n1, f, h)
                Utils.renderTextAtWorldPosition(x, y, z, text, getCorrectTextSize(0.015), 0, {r, g, b, 1})
            end
        end
    end
end
