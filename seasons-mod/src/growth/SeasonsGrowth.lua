----------------------------------------------------------------------------------------------------
-- SeasonsGrowth
----------------------------------------------------------------------------------------------------
-- Purpose:  Growth main class
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsGrowth = {}

local SeasonsGrowth_mt = Class(SeasonsGrowth)

SeasonsGrowth.MAX_STATE = 99
SeasonsGrowth.CUT = 200
SeasonsGrowth.WITHERED = 300
SeasonsGrowth.FIRST_LOAD_TRANSITION = 999
SeasonsGrowth.UNKNOWN_FRUIT_COPY_SOURCE = "BARLEY"
SeasonsGrowth.MAX_ALLOWABLE_GROWTH_PERIOD = 12 * 2 -- max growth for any fruit = 2 years

SeasonsGrowth.EXCEPTIONAL_EVENT_DROUGHT = 800
SeasonsGrowth.EXCEPTIONAL_EVENT_FROST = 801
SeasonsGrowth.EXCEPTIONAL_EVENT_OPTIMAL_GROWTH = 802

SeasonsGrowth.DEFAULT_WEEDS_SCALE = 30
SeasonsGrowth.DEFAULT_WEEDS_SIZE = 6
SeasonsGrowth.DEFAULT_DAMAGE_SCALE = 50
SeasonsGrowth.DEFAULT_DAMAGE_SIZE = 8
SeasonsGrowth.DEFAULT_SCALE_DAYS = 9

SeasonsGrowth.WEEDS_SPROUT = 1
SeasonsGrowth.WEEDS_GROW = 2
SeasonsGrowth.WEEDS_REMOVE = 3
SeasonsGrowth.WEEDS_WITHER = 4

SeasonsGrowth.PLANTED_STATE = 11
SeasonsGrowth.GERMINATION_FAILED_STATE = 12

SeasonsGrowth.CROP_DAMAGE_FROST = "frost"
SeasonsGrowth.CROP_DAMAGE_DROUGHT = "drought"

function SeasonsGrowth:new(mission, environment, messageCenter,i18n, fruitTypeManager, densityMapScanner, weather, sprayTypeManager, fieldManager)
    local self = setmetatable({}, SeasonsGrowth_mt)

    self.mission = mission
    self.environment = environment
    self.messageCenter = messageCenter
    self.i18n = i18n
    self.fruitTypeManager = fruitTypeManager
    self.densityMapScanner = densityMapScanner
    self.weather = weather
    self.sprayTypeManager = sprayTypeManager

    self.fruitTypes = SeasonsGrowthFruitTypes:new(mission, messageCenter, fruitTypeManager)
    self.data = SeasonsGrowthData:new(mission, environment, weather, fruitTypeManager)
    self.pcf = SeasonsGrowthPatchyCropFailure:new(mission, self.data)

    self.manager = SeasonsGrowthManager:new(mission, environment, fruitTypeManager, densityMapScanner, weather, self.data, self.pcf)
    self.cropRotation = SeasonsCropRotation:new(mission, environment, messageCenter, fruitTypeManager, densityMapScanner, i18n, self.data, environment)
    self.npcs = SeasonsGrowthNPCMissions:new(fruitTypeManager, messageCenter, fieldManager, self.data, self.cropRotation, environment)


    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "cutFruitArea", SeasonsGrowth.inj_densityMapUtil_cutFruitArea)
    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "updateCultivatorArea", SeasonsGrowth.inj_densityMapUtil_updateCultivatorArea)
    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "updateDirectSowingArea", SeasonsGrowth.inj_densityMapUtil_updateDirectSowingArea)
    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "updateHerbicideArea", SeasonsGrowth.inj_fsDensityMapUtil_updateHerbicideArea)
    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "updateSowingArea", SeasonsGrowth.inj_densityMapUtil_updateSowingArea)
    SeasonsModUtil.overwrittenStaticFunction(FSDensityMapUtil, "updateWeederArea", SeasonsGrowth.inj_fsDensityMapUtil_updateWeederArea)
    SeasonsModUtil.appendedFunction(SowingMachine, "updateAiParameters", SeasonsGrowth.inj_sowingMachine_updateAiParameters)

    -- These functions load growth state from XML files. As the growth system is not used we prevent them
    -- from running to save a bit of performance
    local noop = function(...) end
    SeasonsModUtil.overwrittenConstant(getfenv(0), "loadCropsGrowthStateFromFile", noop)
    SeasonsModUtil.overwrittenConstant(getfenv(0), "loadTerrainDetailUpdaterStateFromFile", noop)
    SeasonsModUtil.overwrittenConstant(getfenv(0), "saveTerrainDetailUpdaterStateToFile", noop)
    SeasonsModUtil.overwrittenConstant(getfenv(0), "saveCropsGrowthStateToFile", noop)

    return self
end

function SeasonsGrowth:delete()
    self.messageCenter:unsubscribeAll(self)

    self.data:delete()
    self.fruitTypes:delete()
    self.manager:delete()
    self.npcs:delete()
    self.cropRotation:delete()
    self.pcf:delete()
end

function SeasonsGrowth:load()
    self.fruitTypes:load()
    self.data:load()

    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.HOUR_CHANGED_FIX, self.onHourChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)

    self.manager:load()
    self.pcf:load()
    self.npcs:load()
    self.cropRotation:load()

    -- Add visual sprayed ground to herbicide for preventive spraying
    self.sprayTypeManager:getSprayTypeByName("HERBICIDE").groundType = 1

    -- Turn 2-level fertilization into 3-level again
    self.mission.sprayLevelMaxValue = (2 ^ self.mission.sprayLevelNumChannels) - 1
    self.mission.densityMapModifiers.resetSprayArea.filter2:setValueCompareParams("between", 0, self.mission.sprayLevelMaxValue)
end

function SeasonsGrowth:setDataPaths(dataPaths)
    self.fruitTypes:setDataPaths(dataPaths)
    self.data:setDataPaths(dataPaths)
end

function SeasonsGrowth:loadFromSavegame(xmlFile)
    self.data:loadFromSavegame(xmlFile)
    self.cropRotation:loadFromSavegame(xmlFile)
    self.npcs:loadFromSavegame(xmlFile)
    self.pcf:loadFromSavegame(xmlFile)
end

function SeasonsGrowth:saveToSavegame(xmlFile)
    self.cropRotation:saveToSavegame(xmlFile)
    self.npcs:saveToSavegame(xmlFile)
    self.pcf:saveToSavegame(xmlFile)
end

function SeasonsGrowth:onMissionLoaded()
    self.manager:onMissionLoaded()
    self.npcs:onMissionLoaded()
end

---Reset all growth to a state for a new game
function SeasonsGrowth:resetGrowth()
    self.manager:resetGrowth()
end

function SeasonsGrowth:onTerrainLoaded()
    self.cropRotation:onTerrainLoaded()
end

-----------------------------------
-- Events
-----------------------------------

function SeasonsGrowth:onDayChanged()
    self.manager:onDayChanged()
end

function SeasonsGrowth:onHourChanged()
    self.manager:onHourChanged()
end

function SeasonsGrowth:onPeriodChanged()
    self.manager:onPeriodChanged()
end

function SeasonsGrowth:onSeasonLengthChanged()
    self.manager:onSeasonLengthChanged()
end

function SeasonsGrowth:update(dt)
    self.manager:update(dt)
end

-----------------------------------
-- Injections
-----------------------------------

---Default the planting state to 11 (planted). In vanilla it would default to 1, which is the first growth state
function SeasonsGrowth.inj_densityMapUtil_updateSowingArea(superFunc, fruitId, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, angle, growthState, blockedSprayTypeIndex)
    return superFunc(fruitId, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, angle, growthState or SeasonsGrowth.PLANTED_STATE, blockedSprayTypeIndex)
end

function SeasonsGrowth.inj_densityMapUtil_updateDirectSowingArea(superFunc, fruitId, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, angle, growthState, blockedSprayTypeIndex)
    local changedArea, totalArea = superFunc(fruitId, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, angle, growthState, blockedSprayTypeIndex)

    -- Update with planted state
    if growthState == nil then
        local ids = g_currentMission.fruits[fruitId]
        if ids == nil or ids.id == 0 then
            return 0, 0
        end

        local detailId = g_currentMission.terrainDetailId

        local modifiers = g_currentMission.densityMapModifiers.updateDirectSowingArea
        local modifier = modifiers.modifier
        local filter2 = modifiers.filter2

        local desc = g_fruitTypeManager:getFruitTypeByIndex(fruitId)

        -- Anywhere we set the growth state to 1 (basegame planted state)
        filter2:resetDensityMapAndChannels(ids.id, desc.startStateChannel, desc.numStateChannels)
        filter2:setValueCompareParams("equal", 1)

        modifier:resetDensityMapAndChannels(ids.id, desc.startStateChannel, desc.numStateChannels)

        -- Set it to our planted state
        modifier:executeSet(SeasonsGrowth.PLANTED_STATE, filter2)
    end

    return changedArea, totalArea
end

---Do set weeds after treshing
function SeasonsGrowth.inj_densityMapUtil_cutFruitArea(superFunc, fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, destroySeedingWidth, useMinForageState, excludedSprayType, setsWeeds)
    return superFunc(fruitIndex, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, destroySpray, destroySeedingWidth, useMinForageState, excludedSprayType, true)
end

function SeasonsGrowth.inj_densityMapUtil_updateCultivatorArea(superFunc, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, createField, commonForced, angle, blockedSprayTypeIndex, setsWeeds)
    return superFunc(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, createField, commonForced, angle, blockedSprayTypeIndex, true)
end

---Update AI to recognize the planted state
function SeasonsGrowth.inj_sowingMachine_updateAiParameters(vehicle)
    if vehicle.addAITerrainDetailRequiredRange ~= nil then
        if vehicle:getUseSowingMachineAIRquirements() then
            local spec = vehicle.spec_sowingMachine
            local fruitTypeIndex = spec.seeds[spec.currentSeed]
            vehicle:addAIFruitProhibitions(fruitTypeIndex, SeasonsGrowth.PLANTED_STATE - 1, SeasonsGrowth.PLANTED_STATE - 1) -- -1 for unknown reason
        end
    end
end

---Add weeding of planted fields
function SeasonsGrowth.inj_fsDensityMapUtil_updateWeederArea(superFunc, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, maxGrowthState)
    local numPixels, totalNumPixels = superFunc(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, maxGrowthState)

    local weedType = g_fruitTypeManager:getWeedFruitType()
    if weedType ~= nil then
        local modifiers = g_currentMission.densityMapModifiers.updateWeederArea
        local modifier = modifiers.modifier
        local filter1 = modifiers.filter1
        local filter2 = modifiers.filter2

        for index, entry in pairs(g_currentMission.fruits) do
            local desc = g_fruitTypeManager:getFruitTypeByIndex(index)
            if desc.weed == nil then
                -- only do weeding if fruit is in first and second visible growth state
                filter2:resetDensityMapAndChannels(entry.id, desc.startStateChannel, desc.numStateChannels)
                filter2:setValueCompareParams("equal", SeasonsGrowth.PLANTED_STATE)

                local _, numP, totalNumP = modifier:executeSet(0, filter1, filter2)
                numPixels = numPixels + numP
                totalNumPixels = totalNumPixels + totalNumP
            end
        end
    end

    return numPixels, totalNumPixels
end

---Add spraying of planted state
function SeasonsGrowth.inj_fsDensityMapUtil_updateHerbicideArea(superFunc, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, groundType)
    local numPixels, totalNumPixels = superFunc(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, groundType)
    local weedType = g_fruitTypeManager:getWeedFruitType()

    if weedType ~= nil then
        local modifiers = g_currentMission.densityMapModifiers.updateHerbicideArea
        local modifier = modifiers.modifier
        local weedFilter = modifiers.weedFilter
        local maskFilter = modifiers.maskFilter

        local weedFruitId = g_currentMission.fruits[weedType.index]
        local weed = weedType.weed
        local detailId = g_currentMission.terrainDetailId

        for index, entry in pairs(g_currentMission.fruits) do
            local desc = g_fruitTypeManager:getFruitTypeByIndex(index)
            if desc.weed == nil then
                -- planted
                maskFilter:resetDensityMapAndChannels(entry.id, desc.startStateChannel, desc.numStateChannels)
                maskFilter:setValueCompareParams("equal", SeasonsGrowth.PLANTED_STATE)

                -- Set the ground to wet
                weedFilter:setValueCompareParams("between", 0, 1)

                modifier:resetDensityMapAndChannels(detailId, g_currentMission.sprayFirstChannel, g_currentMission.sprayNumChannels)
                modifier:executeSet(groundType, maskFilter, weedFilter)

                -- Now update the grond for state 1, and update the actual weed
                weedFilter:setValueCompareParams("equal", 1)

                modifier:resetDensityMapAndChannels(weedFruitId.id, weedType.startStateChannel, weedType.numStateChannels)
                local _, numP, totalNumP = modifier:executeSet(0, weedFilter, maskFilter)

                numPixels = numPixels + numP
                totalNumPixels = totalNumPixels + totalNumP
            end
        end
    end

    return numPixels, totalNumPixels
end
