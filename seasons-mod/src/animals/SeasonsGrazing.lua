----------------------------------------------------------------------------------------------------
-- SeasonsAnimals
----------------------------------------------------------------------------------------------------
-- Purpose:  Animal changes
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsGrazing = {}

local SeasonsGrazing_mt = Class(SeasonsGrazing)

SeasonsGrazing.MAP_NUM_CHANNELS = 1

function SeasonsGrazing:new(mission, fruitTypeManager, environment)
    local self = setmetatable({}, SeasonsGrazing_mt)

    self.mission = mission
    self.fruitTypeManager = fruitTypeManager
    self.environment = environment
    self.isServer = mission:getIsServer()

    SeasonsModUtil.appendedFunction(AnimalHusbandry, "finalizePlacement", self.inj_animalHusbandry_finalizePlacement)
    SeasonsModUtil.appendedFunction(AnimalHusbandry, "onSell", self.inj_animalHusbandry_onSell)
    SeasonsModUtil.appendedFunction(HusbandryModuleFood, "loadFromXMLFile", self.inj_husbandryModuleFood_loadFromXMLFile)
    SeasonsModUtil.appendedFunction(HusbandryModuleFood, "onHourChanged", self.inj_husbandryModuleFood_onHourChanged)
    SeasonsModUtil.appendedFunction(HusbandryModuleFood, "onIntervalUpdate", self.inj_husbandryModuleFood_onIntervalUpdate)
    SeasonsModUtil.appendedFunction(HusbandryModuleFood, "saveToXMLFile", self.inj_husbandryModuleFood_saveToXMLFile)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleFood, "load", self.inj_husbandryModuleFood_load)

    return self
end

function SeasonsGrazing:delete()
    if self.mask ~= 0 then
        delete(self.mask)
    end
end

function SeasonsGrazing:load()
end

function SeasonsGrazing:onTerrainLoaded()
    self:createMask()

    self.modifiers = {}
    self.modifiers.mask = DensityMapModifier:new(self.mask, 0, 1)
    self.modifiers.maskFilter = DensityMapFilter:new(self.modifiers.mask)
    self.modifiers.maskFilter:setValueCompareParams("equals", 1)

    self.grassFruitDesc = self.fruitTypeManager:getFruitTypeByIndex(FruitType.GRASS)
    self.modifiers.heightModifier = DensityMapModifier:new(self.mission.fruits[FruitType.GRASS].id, self.grassFruitDesc.startStateChannel, self.grassFruitDesc.numStateChannels)
    self.modifiers.heightFilter = DensityMapFilter:new(self.modifiers.heightModifier)
    self.modifiers.heightFilter:setValueCompareParams("between", self.grassFruitDesc.minHarvestingGrowthState + 1, self.grassFruitDesc.maxHarvestingGrowthState + 1)
    self.modifiers.heightFilter2 = DensityMapFilter:new(self.modifiers.heightModifier)
end

function SeasonsGrazing:createMask()
    self.mask = createBitVectorMap("GrazingMap")

    local size = getDensityMapSize(self.mission.terrainDetailId)
    loadBitVectorMapNew(self.mask, size, size, SeasonsGrazing.MAP_NUM_CHANNELS, false)
end

function SeasonsGrazing:setFoliageInMask(placeable, value)
    local terrainSize = self.mission.terrainSize

    for _, area in ipairs(placeable.foliageAreas) do
        if area.fruitType == FruitType.GRASS then
            local dimensions = area.fieldDimensions
            local numDimensions = getNumOfChildren(dimensions)

            for i = 1, numDimensions do
                local dimWidth = getChildAt(dimensions, i - 1)
                if getNumOfChildren(dimWidth) ~= 2 then
                    -- Invalid setup
                    Logging.warning("The configuration of %s is invalid: foliageAreas are not referencing proper nodes", placeable.configFileName)
                    return
                end

                local dimStart = getChildAt(dimWidth, 0)
                local dimHeight = getChildAt(dimWidth, 1)

                local x,_,z = getWorldTranslation(dimStart)
                local x1,_,z1 = getWorldTranslation(dimWidth)
                local x2,_,z2 = getWorldTranslation(dimHeight)

                self.modifiers.mask:setParallelogramUVCoords(x / terrainSize + 0.5, z / terrainSize + 0.5, x1 / terrainSize + 0.5, z1 / terrainSize + 0.5, x2 / terrainSize + 0.5, z2 / terrainSize + 0.5, "ppp")
                local a, b, c = self.modifiers.mask:executeSet(value)
            end
        end
    end
end

---Add a husbandry. Adds it to mask, finds the bounding box
function SeasonsGrazing:addHusbandry(husbandry)
    self:setFoliageInMask(husbandry, 1)
    self:findBoundingBox(husbandry)

    -- Get total available grass
    local foodModule = husbandry:getModuleByName("food")
    foodModule.seasons_grazingAvailable = self:getTotalGrass(husbandry)
end

---Remove a husbandry. Clears it from the mask
function SeasonsGrazing:removeHusbandry(husbandry)
    self:setFoliageInMask(husbandry, 0)
end

---Find a box that contains all the grass so we have a parallogram to focus on.
-- This is axis aligned because that is the simplest to calculate
function SeasonsGrazing:findBoundingBox(husbandry)
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge

    for _, area in ipairs(husbandry.foliageAreas) do
        if area.fruitType == FruitType.GRASS then
            local dimensions = area.fieldDimensions
            local numDimensions = getNumOfChildren(dimensions)

            for i = 1, numDimensions do
                local dimWidth = getChildAt(dimensions, i - 1)
                if getNumOfChildren(dimWidth) ~= 2 then
                    break
                end

                local dimStart = getChildAt(dimWidth, 0)
                local dimHeight = getChildAt(dimWidth, 1)

                local x,_,z = getWorldTranslation(dimStart)
                local x1,_,z1 = getWorldTranslation(dimWidth)
                local x2,_,z2 = getWorldTranslation(dimHeight)

                minX = math.min(minX, x, x1, x2)
                minZ = math.min(minZ, z, z1, z2)
                maxX = math.max(maxX, x, x1, x2)
                maxZ = math.max(maxZ, z, z1, z2)
            end
        end
    end

    if minX > maxX or minZ > maxZ then
        return
    end

    husbandry.seasons_grazingAABB = {minX=minX, minZ=minZ, maxX=maxX, maxZ=maxZ}
end

---Update the buffer for the husbandry, with optionally the total amount of grass already given
function SeasonsGrazing:updateBuffer(husbandry)
    local foodModule = husbandry:getModuleByName("food")

    if husbandry.seasons_grazingAABB == nil then
        return
    end

    -- If we consumed everything, cut grass
    if foodModule.seasons_grazingConsumed ~= 0 and foodModule.seasons_grazingConsumed >= foodModule.seasons_grazingAvailable - 1 then
        self:cutGrass(husbandry)

        foodModule.seasons_grazingConsumed = 0
        foodModule.seasons_grazingAvailable = self:getTotalGrass(husbandry)
    end
end

---Get the total amount of harvestable grass and turn it into a liter amount
function SeasonsGrazing:getTotalGrass(husbandry)
    local modifier = self.modifiers.heightModifier
    local heightFilter = self.modifiers.heightFilter
    local maskFilter = self.modifiers.maskFilter

    local terrainSize = self.mission.terrainSize

    local aabb = husbandry.seasons_grazingAABB
    if aabb == nil then
        return 0
    end

    -- Parallogram from AABB
    local x, z, x1, z1, x2, z2 = aabb.minX, aabb.minZ, aabb.maxX, aabb.minZ, aabb.minX, aabb.maxZ
    modifier:setParallelogramWorldCoords(x, z, x1, z1, x2, z2, "ppp")
    modifier:setReturnValueShift(-1)

    local pixels, area, totalArea = modifier:executeGet(heightFilter, maskFilter)

    return area * self.grassFruitDesc.literPerSqm * self.mission:getFruitPixelsToSqm()
end

---Cut one layer of grass to simulate it being grazed
function SeasonsGrazing:cutGrass(husbandry)
    local modifier = self.modifiers.heightModifier
    local heightFilter = self.modifiers.heightFilter2
    local maskFilter = self.modifiers.maskFilter

    local terrainSize = self.mission.terrainSize

    local aabb = husbandry.seasons_grazingAABB
    if aabb == nil then
        return 0
    end

    local x, z, x1, z1, x2, z2 = aabb.minX, aabb.minZ, aabb.maxX, aabb.minZ, aabb.minX, aabb.maxZ
    modifier:setParallelogramWorldCoords(x, z, x1, z1, x2, z2, "ppp")

    modifier:executeAdd(-1, heightFilter, maskFilter)
end

----------------------
-- Injections
----------------------

---Update mask when a husbandry is placed
function SeasonsGrazing.inj_animalHusbandry_finalizePlacement(placeable)
    g_seasons.animals.grazing:addHusbandry(placeable)
end

---Update mask when a husbandry is sold
function SeasonsGrazing.inj_animalHusbandry_onSell(placeable)
    g_seasons.animals.grazing:removeHusbandry(placeable)
end

function SeasonsGrazing.inj_husbandryModuleFood_load(module, superFunc, ...)
    if not superFunc(module, ...) then
        return false
    end

    module.seasons_grazingAvailable = 0
    module.seasons_grazingConsumed = 0

    return true
end

function SeasonsGrazing.inj_husbandryModuleFood_onIntervalUpdate(module, dayToInterval)
    if module.singleAnimalUsagePerDay > 0.0 then
        local currentAmount = module:getFillLevel(FillType.GRASS_WINDROW)
        local capacity = module:getCapacity()

        -- Remove a small percentage
        local partOfYear = dayToInterval * (1 / (g_seasons.environment.daysPerSeason * 4))
        local rotting = 1.5 * partOfYear * module.seasons_grazingAvailable -- 1.5 times per year
        if rotting > 0 then
            module.seasons_grazingConsumed = math.min(module.seasons_grazingConsumed + rotting, module.seasons_grazingAvailable)
        end

        -- We try to fill it up to at least 80%
        local atLeastContent = 0.8 * capacity
        if atLeastContent > currentAmount then
            -- Try to fill it
            local inBuffer = module.seasons_grazingAvailable - module.seasons_grazingConsumed
            local diff = math.min(atLeastContent - currentAmount, inBuffer)

            -- Add to trough
            diff = module:changeFillLevels(diff, FillType.GRASS_WINDROW)

            -- Add to consumption
            module.seasons_grazingConsumed = module.seasons_grazingConsumed + diff

            if diff > 0 then
                module:updateFillPlane()
            end

            -- Cut the grass when needed
            g_seasons.animals.grazing:updateBuffer(module.owner)
        end
    end
end

function SeasonsGrazing.inj_husbandryModuleFood_onHourChanged(module)
    if g_currentMission.environment.currentHour == 10 then
        local total = g_seasons.animals.grazing:getTotalGrass(module.owner)
        module.seasons_grazingAvailable = total

        if total == 0 then
            module.seasons_grazingConsumed = 0
        elseif total > 0 then
            g_seasons.animals.grazing:updateBuffer(module.owner)
        end
    end
end

---Read the buffer contents
function SeasonsGrazing.inj_husbandryModuleFood_loadFromXMLFile(module, xmlFile, key)
    module.seasons_grazingConsumed = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#seasons_grazingConsumed"), 0)
    module.seasons_grazingAvailable = g_seasons.animals.grazing:getTotalGrass(module.owner)

    g_seasons.animals.grazing:updateBuffer(module.owner)
end

---Write the buffer contents
function SeasonsGrazing.inj_husbandryModuleFood_saveToXMLFile(module, xmlFile, key, usedModNames)
    if module.seasons_grazingConsumed ~= nil then
        setXMLFloat(xmlFile, key .. "#seasons_grazingConsumed", module.seasons_grazingConsumed)
    end
end

