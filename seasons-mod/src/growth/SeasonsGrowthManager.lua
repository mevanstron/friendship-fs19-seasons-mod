----------------------------------------------------------------------------------------------------
-- SeasonsGrowthManager
----------------------------------------------------------------------------------------------------
-- Purpose:  Growth manager class
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsGrowthManager = {}

local SeasonsGrowthManager_mt = Class(SeasonsGrowthManager)

function SeasonsGrowthManager:new(mission, environment, fruitTypeManager, densityMapScanner, weather, data, pcf)
    local self = setmetatable({}, SeasonsGrowthManager_mt)

    self.mission = mission
    self.environment = environment
    self.fruitTypeManager = fruitTypeManager
    self.densityMapScanner = densityMapScanner
    self.weather = weather
    self.data = data
    self.pcf = pcf

    self.damageFactorMatrix = {}
    self.destroyingPatchesQueue = {}

    self.weedsScale = SeasonsGrowth.DEFAULT_WEEDS_SCALE
    self.damageScale = SeasonsGrowth.DEFAULT_DAMAGE_SCALE
    self.pcfTimer = 0
    self.pcfTimerActive = true
    self.droughtSeverity = 4
    self.frostSeverity = 4

    if g_addCheatCommands then
        addConsoleCommand("rmQuickGrowth", "Growth test rmQuickGrowth(transition)", "commandQuickTest", self)
        addConsoleCommand("rmResetGrowth", "Reset all fields", "commandResetGrowth", self)
        addConsoleCommand("rmPrintGerminationData", "Print germination data", "commandPrintGerminationData", self)
        addConsoleCommand("rmPrintFruitTypesData", "Print fruitypes", "commandPrintFruitTypesData", self)
        addConsoleCommand("rmPrintGrowthData", "Print growth data", "commandPrintGrowthData", self)
        addConsoleCommand("rmMatureWeeds", "Mature weeds", "commandMatureWeeds", self)
        addConsoleCommand("rmSproutWeeds", "Sprout weeds", "commandSproutWeeds", self)
        addConsoleCommand("rmTestPatchyCropFailure", "", "commandTestPatchyCropFailure", self)
        addConsoleCommand("rmGerminationTest", "", "commandGerminationTest", self)
        addConsoleCommand("rmRemoveWeeds", "", "commandRemoveWeeds", self)
        addConsoleCommand("rmWitherWeeds", "", "commandWitherWeeds", self)
    end

    return self
end

function SeasonsGrowthManager:delete()
    self.densityMapScanner:unregisterCallback("Growth")
    self.densityMapScanner:unregisterCallback("Germination")
    self.densityMapScanner:unregisterCallback("Weeds")

    if g_addCheatCommands then
        removeConsoleCommand("rmQuickGrowth")
        removeConsoleCommand("rmResetGrowth")
        removeConsoleCommand("rmPrintGerminationData")
        removeConsoleCommand("rmPrintFruitTypesData")
        removeConsoleCommand("rmPrintGrowthData")
        removeConsoleCommand("rmMatureWeeds")
        removeConsoleCommand("rmSproutWeeds")
        removeConsoleCommand("rmTestPatchyCropFailure")
        removeConsoleCommand("rmGerminationTest")
        removeConsoleCommand("rmRemoveWeeds")
        removeConsoleCommand("rmWitherWeeds")
    end
end

function SeasonsGrowthManager:load()
    self:loadModifiers()
    self:updateWeedsandDamageScales(self.environment.daysPerSeason)
    self.densityMapScanner:registerCallback("Growth", self.dms_handleGrowth, self, self.dms_finishGrowth, false)
    self.densityMapScanner:registerCallback("Germination", self.dms_handleGermination, self, self.dms_finishGermination, false)
    self.densityMapScanner:registerCallback("Weeds", self.dms_growWeeds, self, nil, false)

    self.droughtSeverity = self.weather:getDroughtSeverity()
    self.frostSeverity = self.weather:getFrostSeverity()
end

---Reset the growth if this is the first time Seasons was loaded but the save was also not already created
-- If the save is old, then we need to show a message
function SeasonsGrowthManager:onMissionLoaded()
    local shouldShowMessage = self.mission.missionInfo.isValid and g_dedicatedServerInfo == nil
    if self.data.isNewGame and self.mission:getIsServer() and not shouldShowMessage then
        Logging.info("Resetting all fields. This will only happen once")
        self:resetGrowth()
    end
end

function SeasonsGrowthManager:loadModifiers()
    local terrainDetailId = self.mission.terrainDetailId

    local modifiers = {}

    modifiers.fruitState = {}
    modifiers.fruitState.modifier = DensityMapModifier:new(terrainDetailId, 0, 1) -- overwritten with fruit
    modifiers.fruitState.filter = DensityMapFilter:new(modifiers.fruitState.modifier) -- overwritten with fruit

    modifiers.sprayState = {}
    modifiers.sprayState.modifier = DensityMapModifier:new(terrainDetailId, self.mission.sprayFirstChannel, self.mission.sprayNumChannels)

    modifiers.groundType = {}
    modifiers.groundType.modifier = DensityMapModifier:new(terrainDetailId, self.mission.terrainDetailTypeFirstChannel, self.mission.terrainDetailTypeNumChannels)
    modifiers.groundType.filter = DensityMapFilter:new(modifiers.groundType.modifier)
    modifiers.groundType.filter:setValueCompareParams("greater", 0)

    local weedType = self.fruitTypeManager:getWeedFruitType()
    if weedType ~= nil then
        local ids = self.mission.fruits[weedType.index]

        modifiers.setWeedArea = {}
        modifiers.setWeedArea.modifier = DensityMapModifier:new(ids.id, weedType.startStateChannel, weedType.numStateChannels)
        modifiers.setWeedArea.filter = DensityMapFilter:new(modifiers.setWeedArea.modifier)
    end

    self.modifiers = modifiers
end

function SeasonsGrowthManager:onPeriodChanged()
    if self.mission:getIsServer() then
        self.densityMapScanner:queueJob("Growth", self.environment.period)
    end
end

function SeasonsGrowthManager:onDayChanged()
    --log("Germinating period: ", self.environment.period, " day: ", self.environment.currentDay, "with soil temp: ", self.weather:getYesterdayMaxSoilTemp())
    if self.mission:getIsServer() then
        self.droughtSeverity = self.weather:getDroughtSeverity()
        self.frostSeverity = self.weather:getFrostSeverity()
        self.pcf:resetForNewDay()
        self.pcfTimerActive = true

        local yesterdayMaxSoilTemp = self.weather:getYesterdayMaxSoilTemp()
        self.densityMapScanner:queueJob("Germination", yesterdayMaxSoilTemp)

        local fruitTypeWeed = self.fruitTypeManager:getFruitTypeByIndex(FruitType.WEED)
        if fruitTypeWeed.weedWitherSoilTemp >= yesterdayMaxSoilTemp then
            self.densityMapScanner:queueJob("Weeds", SeasonsGrowth.WEEDS_WITHER)
        elseif fruitTypeWeed.weedMatureSoilTemp >= yesterdayMaxSoilTemp and self.environment.currentDay % 2 == 1 then
            self.densityMapScanner:queueJob("Weeds", SeasonsGrowth.WEEDS_GROW)
        end
    end
end

function SeasonsGrowthManager:onHourChanged()
    if self.mission.getIsServer() and self.mission.missionInfo.weedsEnabled then
        self:sproutWeeds()
    end
end

function SeasonsGrowthManager:onSeasonLengthChanged()
    self:updateWeedsandDamageScales(self.environment.daysPerSeason)
end

--reset growth to first_load_transition for all fields
function SeasonsGrowthManager:resetGrowth()
    if self.mission:getIsServer() then
        self.densityMapScanner:queueJob("Growth", SeasonsGrowth.FIRST_LOAD_TRANSITION)
    end
end

--density scanner functions - must not be called directly

function SeasonsGrowthManager:dms_handleGermination(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, jobParams)
    local soilTempMax = jobParams[1]
    local soilMoistureMax = jobParams[2]
    local germinationData = self.data:buildGerminationData(soilTempMax, soilMoistureMax)

    for fruitName,germinationValue in pairs(germinationData) do
        if germinationValue == true and fruitName ~= "WEED" then
            local fruitType = self.fruitTypeManager:getFruitTypeByName(fruitName)
            local fruit = self.mission.fruits[fruitType.index]

            local currentGrowthData = {}
            currentGrowthData.fruitName = fruitType.name
            currentGrowthData.setFromMin = SeasonsGrowth.PLANTED_STATE
            currentGrowthData.setTo = 1

            self:dms_setGrowthState(fruit, fruitType, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, currentGrowthData)
        end
    end
end

function SeasonsGrowthManager:dms_finishGermination(jobParams)
    -- log("Germination finished")
end

function SeasonsGrowthManager:dms_handleGrowth(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, jobParams)
    local period = jobParams[1]

    for index, fruit in pairs(self.mission.fruits) do
        local fruitType = self.fruitTypeManager:getFruitTypeByIndex(index)
        local fruitName = fruitType.name

        if self.data.growth[period][fruitName] ~= nil then
            local currentGrowthData = self.data.growth[period][fruitName]

            if fruitType.index == FruitType.WEED then
                self:handleWeedGrowth(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, SeasonsGrowth.WEEDS_GROW)
            end
            --increment by 1 for crops between incrementByOneMin and incrementByOneMax or for crops at incrementByOneMin
            if currentGrowthData.incrementByOneMin ~= nil then
                self:dms_incrementGrowthState(fruit, fruitType, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, currentGrowthData.incrementByOneMin, currentGrowthData.incrementByOneMax, 1)
            end
            --incrementBy between incrementByMin and incrementByMax
            if currentGrowthData.incrementByMin ~= nil and currentGrowthData.incrementBy ~= nil then
                self:dms_incrementGrowthState(fruit, fruitType, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, currentGrowthData.incrementByMin, currentGrowthData.incrementByMax, currentGrowthData.incrementBy)
            end
            --set growth state
            if currentGrowthData.setFromMin ~= nil and currentGrowthData.setTo ~= nil then
                self:dms_setGrowthState(fruit, fruitType, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, currentGrowthData)
            end
        end
    end
end

function SeasonsGrowthManager:dms_finishGrowth(jobParams)
    local period = jobParams[1]

    -- Find whether grass was cut back. If so, revalidate bale missions
    local grass = self.data.growth[period]["GRASS"]
    if grass ~= nil and grass.setTo == 2 then
        for _, mission in ipairs(g_missionManager.missions) do
            if mission.type.category == MissionManager.CATEGORY_GRASS_FIELD then
                g_missionManager:validateMissionOnField(mission.field, FieldManager.FIELDEVENT_HARVESTED, true)
            end
        end
    end
end

--Set growth state of fruit to a particular state based on transition
function SeasonsGrowthManager:dms_setGrowthState(fruit, fruitType, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, currentGrowthData)
    local modifiers = self.modifiers.fruitState
    local modifier = modifiers.modifier
    local filter = modifiers.filter

    -- local useMaxState = false

    modifier:resetDensityMapAndChannels(fruit.id, fruitType.startStateChannel, fruitType.numStateChannels)
    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    filter:resetDensityMapAndChannels(fruit.id, fruitType.startStateChannel, fruitType.numStateChannels)

    local minState = currentGrowthData.setFromMin
    if minState == SeasonsGrowth.CUT then
        minState = fruitType.cutState + 1
    end

    local setToState = currentGrowthData.setTo
    if setToState == SeasonsGrowth.WITHERED then
        setToState = fruitType.witheringNumGrowthStates
    elseif setToState == SeasonsGrowth.CUT then
        setToState = fruitType.cutState + 1
    end

    if currentGrowthData.setFromMax ~= nil then --if maxState exists
        local maxState = currentGrowthData.setFromMax

        if maxState == SeasonsGrowth.MAX_STATE then
            maxState = fruitType.numGrowthStates
        end

        filter:setValueCompareParams("between", minState, maxState)
        -- useMaxState = true
    else -- else only use minState
        filter:setValueCompareParams("equals", minState)
    end

    local _, _, delta = modifier:executeSet(setToState, filter)
    if delta ~= 0 then
        if fruitType.resetsSpray then
            modifier = self.modifiers.sprayState.modifier
            modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")

            filter:setValueCompareParams("equals", setToState)
            modifier:executeSet(0, filter)
        end

        if fruitType.index == FruitType.WEED then return end
        if fruitType.groundTypeChanged > 0 then --grass
            modifier = self.modifiers.groundType.modifier
            local filterGround = self.modifiers.groundType.filter

            modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
            filter:setValueCompareParams("greater", 0)

            modifier:executeSet(fruitType.groundTypeChanged, filterGround, filter)
        end
    end
end

---incrementByfor crops between incrementByMin and incrementByMax or for crops at incrementByMin
function SeasonsGrowthManager:dms_incrementGrowthState(fruit, fruitType, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, incrementByMin, incrementByMax, incrementBy)
    local modifiers = self.modifiers.fruitState
    local modifier = modifiers.modifier
    local filter = modifiers.filter

    -- local useMaxState = false
    local minState = incrementByMin

    modifier:resetDensityMapAndChannels(fruit.id, fruitType.startStateChannel, fruitType.numStateChannels)
    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    filter:resetDensityMapAndChannels(fruit.id, fruitType.startStateChannel, fruitType.numStateChannels)

    if incrementByMax ~= nil then
        local maxState = incrementByMax

        if maxState == SeasonsGrowth.MAX_STATE then
            maxState = fruitType.numGrowthStates - 1
        end

        filter:setValueCompareParams("between", minState, maxState)
        -- useMaxState = true
    else
        filter:setValueCompareParams("equals", minState)
    end

    local _, _, delta = modifier:executeAdd(incrementBy, filter)
    if delta ~= 0 then
        local maxFertiliseState = fruitType.maxFertiliseState
        if fruitType.resetsSpray and minState < maxFertiliseState then
            modifier = self.modifiers.sprayState.modifier
            modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")

            filter:setValueCompareParams("between", minState, maxFertiliseState)
            modifier:executeSet(0, filter)
        end
        if fruitType.groundTypeChanged ~= nil then
            if fruitType.groundTypeChanged > 0 then --grass
                modifier = self.modifiers.groundType.modifier
                local filterGround = self.modifiers.groundType.filter

                modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
                filter:setValueCompareParams("greater", 0)

                modifier:executeSet(fruitType.groundTypeChanged, filterGround, filter)
            end
        end
    end
end

---Grow weeds
function SeasonsGrowthManager:dms_growWeeds(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, jobParams)
    local growthCommand = jobParams[1]
    self:handleWeedGrowth(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, growthCommand)
end

function SeasonsGrowthManager:handleWeedGrowth(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, growthCommand)
    local modifiers = self.modifiers.setWeedArea
    if modifiers ~= nil and growthCommand ~= nil then
        local modifier = modifiers.modifier
        local filter = modifiers.filter

        modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")

        if growthCommand == SeasonsGrowth.WEEDS_SPROUT then -- sprout weeds
            filter:setValueCompareParams("equals", 1)
            modifier:executeSet(2, filter)
        elseif growthCommand == SeasonsGrowth.WEEDS_GROW then --small weeds --> big weeds
            filter:setValueCompareParams("equals", 2)
            modifier:executeSet(3, filter)
        elseif growthCommand == SeasonsGrowth.WEEDS_REMOVE then
            filter:setValueCompareParams("greater", 0)
            modifier:executeSet(0, filter)
        elseif growthCommand == SeasonsGrowth.WEEDS_WITHER then
            filter:setValueCompareParams("equals", 2)
            modifier:executeSet(4, filter)
            filter:setValueCompareParams("equals", 3)
            modifier:executeSet(5, filter)
        end
    end
end

---Create a random parallogram of given size or with size randomization
function SeasonsGrowthManager:createRandomParallelogram(size, randomSize)
    local height = size
    local width = size

    if randomSize then
        height = math.abs(2 * math.random() - 1) * size
        size = math.abs(2 * math.random() - 1) * size
    end

    local startWorldX = (2 * math.random() - 1) * self.mission.terrainSize / 2
    local startWorldZ = (2 * math.random() - 1) * self.mission.terrainSize / 2

    local widthWorldX = startWorldX + width +  (2 * math.random() - 1) * size
    local widthWorldZ = startWorldZ + (2 * math.random() - 1) * size

    local heightWorldX = startWorldX + (2 * math.random() - 1) * size
    local heightWorldZ = startWorldZ + height + (2 * math.random() - 1) * size

    return startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ
end

---Sprout weeds using random parallograms
function SeasonsGrowthManager:sproutWeeds()
    local weedGerminationTemp = self.fruitTypeManager:getFruitTypeByIndex(FruitType.WEED).germinateTemp
    --log("weed germ temp: ", weedGerminationTemp, " current soil temp:", self.weather:getCurrentSoilTemperature() )
    if weedGerminationTemp <= self.weather:getCurrentSoilTemperature() then
        for i = 1, self.weedsScale do
            local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = self:createRandomParallelogram(SeasonsGrowth.DEFAULT_WEEDS_SIZE, true)
            self:handleWeedGrowth(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, SeasonsGrowth.WEEDS_SPROUT)
        end
    end
end

function SeasonsGrowthManager:getDamageFactorResult(eventIntensity, plantResistance)
    return (4 - eventIntensity) * (4 - plantResistance) / 2
end

function SeasonsGrowthManager:patchyCropFailure(fruitIndex, eventIntensity, eventType)
    local fruit = self.mission.fruits[fruitIndex]
    local fruitType = self.fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    local currentGrowthData = {}
    currentGrowthData.fruitName = fruitType.name

    local seedDamageFactor = 0
    local youngDamageFactor = 0
    local matureDamageFactor = 0

    if eventType == SeasonsGrowth.CROP_DAMAGE_FROST then
        seedDamageFactor = self:getDamageFactorResult(eventIntensity, fruitType.seedFrostResistanceFactor)
        youngDamageFactor = self:getDamageFactorResult(eventIntensity, fruitType.youngPlantFrostResistanceFactor)
        matureDamageFactor = self:getDamageFactorResult(eventIntensity, fruitType.maturePlantFrostResistanceFactor)
    elseif eventType == SeasonsGrowth.CROP_DAMAGE_DROUGHT then
        seedDamageFactor = self:getDamageFactorResult(eventIntensity, fruitType.seedDroughtResistanceFactor)
        youngDamageFactor = self:getDamageFactorResult(eventIntensity, fruitType.youngPlantDroughtResistanceFactor)
        matureDamageFactor = self:getDamageFactorResult(eventIntensity, fruitType.maturePlantDroughtResistanceFactor)
    end

    --seeded
    currentGrowthData = self:buildGrowthDataForPCF(SeasonsGrowth.PLANTED_STATE, SeasonsGrowth.GERMINATION_FAILED_STATE)
    self:destroyInPatches(fruit, fruitType, currentGrowthData, seedDamageFactor)

    --young plants
    currentGrowthData = self:buildGrowthDataForPCF(1, fruitType.youngPlantDamageState, fruitType.youngPlantMaxState)
    self:destroyInPatches(fruit, fruitType, currentGrowthData, youngDamageFactor)

    --mature plants
    currentGrowthData = self:buildGrowthDataForPCF(fruitType.maturePlantMinState, fruitType.maturePlantDamageState, fruitType.numGrowthStates)
    self:destroyInPatches(fruit, fruitType, currentGrowthData, matureDamageFactor)
end

function SeasonsGrowthManager:buildGrowthDataForPCF(setFromMin, setTo, setFromMax)
    local currentGrowthData = {}
    currentGrowthData.setFromMin = setFromMin
    currentGrowthData.setTo = setTo
    if setFromMax ~= nil then
        currentGrowthData.setFromMax = setFromMax
    end

    return currentGrowthData
end

---Destroy given fruit in random patches, but first add the info to a queue so this can be performed
-- spread across frames.
function SeasonsGrowthManager:destroyInPatches(fruit, fruitType, currentGrowthData, damageFactor)
    -- No need to add event when damage factor is 0 (intensity would be 0)
    -- Do not overload the queue too much as it would hold up the game when fast forwarding, causing drops in FPS,
    -- especially when growth/snow/grass is also running.
    if damageFactor == 0 or #self.destroyingPatchesQueue > 50 then
        return
    end

    local intensity = damageFactor * self.damageScale

    table.insert(self.destroyingPatchesQueue, {
        count = intensity,
        fruit = fruit,
        fruitType = fruitType,
        currentGrowthData = currentGrowthData
    })
end

---Execute patches from the patch queue
function SeasonsGrowthManager:doDestroyInPatchesFromQueue(dt)
    if #self.destroyingPatchesQueue == 0 then
        return
    end

    local info = self.destroyingPatchesQueue[1]

    local modifiers = self.modifiers.fruitState
    local modifier = modifiers.modifier
    local filter = modifiers.filter

    local fruit = info.fruit
    local fruitType = info.fruitType
    local currentGrowthData = info.currentGrowthData

    local useMaxState = false

    modifier:resetDensityMapAndChannels(fruit.id, fruitType.startStateChannel, fruitType.numStateChannels)
    filter:resetDensityMapAndChannels(fruit.id, fruitType.startStateChannel, fruitType.numStateChannels)

    local minState = currentGrowthData.setFromMin
    if minState == SeasonsGrowth.CUT then
        minState = fruitType.cutState + 1
    end

    local setToState = currentGrowthData.setTo
    if setToState == SeasonsGrowth.WITHERED then
        setToState = fruitType.witheringNumGrowthStates
    elseif setToState == SeasonsGrowth.CUT then
        setToState = fruitType.cutState + 1
    end

    if currentGrowthData.setFromMax ~= nil then --if maxState exists
        local maxState = currentGrowthData.setFromMax

        if maxState == SeasonsGrowth.MAX_STATE then
            maxState = fruitType.numGrowthStates
        end

        filter:setValueCompareParams("between", minState, maxState)
    else -- else only use minState
        filter:setValueCompareParams("equals", minState)
    end

    for i = 1, math.min(info.count, 6) do
        local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = self:createRandomParallelogram(SeasonsGrowth.DEFAULT_DAMAGE_SIZE, true)

        modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
        local _, _, delta = modifier:executeSet(setToState, filter)
    end

    info.count = info.count - 6
    if info.count <= 0 then
        table.remove(self.destroyingPatchesQueue, 1)
    end
end

function SeasonsGrowthManager:updateWeedsandDamageScales(daysPerSeason)
    self.weedsScale = SeasonsGrowth.DEFAULT_WEEDS_SCALE * SeasonsGrowth.DEFAULT_SCALE_DAYS / daysPerSeason
    self.damageScale = SeasonsGrowth.DEFAULT_DAMAGE_SCALE *  SeasonsGrowth.DEFAULT_SCALE_DAYS / daysPerSeason
end

function SeasonsGrowthManager:update(dt)
    self:doDestroyInPatchesFromQueue(dt)

    if self.pcfTimerActive == false then
        return
    end

    self.pcfTimer = self.pcfTimer + dt * self.mission.missionInfo.timeScale
    pcfInterval = self.pcf:getTimerIntervalInMS()
    if self.pcfTimer > pcfInterval then
        self.pcfTimer = self.pcfTimer - pcfInterval

        fruitIndex = self.pcf:getNextFruitIndex()
        if fruitIndex == nil then
            self.pcfTimerActive = false
            return
        end

        if self.frostSeverity < 4 then
            self:patchyCropFailure(fruitIndex, self.frostSeverity, SeasonsGrowth.CROP_DAMAGE_FROST)
        end

        if self.droughtSeverity < 4 then
            self:patchyCropFailure(fruitIndex, self.droughtSeverity, SeasonsGrowth.CROP_DAMAGE_DROUGHT)
        end
    end
end

-- debug functions

function SeasonsGrowthManager:commandQuickTest(transition)
    if tonumber(transition) == nil then
        return "Usage: rmQuickGrowth transition"
    end

    self.densityMapScanner:queueJob("Growth", tonumber(transition))
end

function SeasonsGrowthManager:commandResetGrowth()
    self:resetGrowth()
end

function SeasonsGrowthManager:commandPrintGerminationData()
    log("")
    log("Germination Data")
    Logging.table(self.data:buildGerminationData())
end

function SeasonsGrowthManager:commandPrintFruitTypesData()
    log("")
    log("FruitTypes Data")
    for index, fruit in pairs(self.mission.fruits) do
        Logging.table(self.fruitTypeManager:getFruitTypeByIndex(index))
    end
end

function SeasonsGrowthManager:commandGerminationTest(soilTemp)
    if tonumber(soilTemp) == nil then
        return "Usage: rmGerminationTest soilTemperature"
    end

    self.densityMapScanner:queueJob("Germination", tonumber(soilTemp))
end

function SeasonsGrowthManager:commandPrintGrowthData()
    log("")
    log("Growth Data")
    Logging.table(self.data.growth)
    log("")
    log("Plantable Data")
    Logging.table(self.data.plantable)
    log("")
    log("Harvestable Data")
    Logging.table(self.data.harvestable)
end

function SeasonsGrowthManager:commandSproutWeeds()
    self:sproutWeeds()
end

function SeasonsGrowthManager:commandMatureWeeds()
    self.densityMapScanner:queueJob("Weeds", SeasonsGrowth.WEEDS_GROW)
end

function SeasonsGrowthManager:commandRemoveWeeds()
    self.densityMapScanner:queueJob("Weeds", SeasonsGrowth.WEEDS_REMOVE)
end

function SeasonsGrowthManager:commandWitherWeeds()
    log(self.fruitTypeManager:getFruitTypeByIndex(FruitType.WEED).weedWitherSoilTemp)
    self.densityMapScanner:queueJob("Weeds", SeasonsGrowth.WEEDS_WITHER)
end

function SeasonsGrowthManager:commandTestPatchyCropFailure()
    Logging.table(self.pcf.fruits)
    log("current index: ", self.pcf.fruitToProcessIndex)
    log("interval: ", self.pcf.timerInterval)
    log("fruits: ", self.pcf.numberOfFruits)
    log("frost: ", self.frostSeverity)
    log("drought: ", self.droughtSeverity)
end
