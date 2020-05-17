----------------------------------------------------------------------------------------------------
-- SeasonsGrowthNPCMissions
----------------------------------------------------------------------------------------------------
-- Purpose:  NPC and mission updates
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsGrowthNPCMissions = {}

local SeasonsGrowthNPCMissions_mt = Class(SeasonsGrowthNPCMissions)

function SeasonsGrowthNPCMissions:new(fruitTypeManager, messageCenter, fieldManager, data, cropRotation, environment)
    local self = setmetatable({}, SeasonsGrowthNPCMissions_mt)

    self.fruitTypeManager = fruitTypeManager
    self.messageCenter = messageCenter
    self.fieldManager = fieldManager
    self.data = data
    self.cropRotation = cropRotation
    self.environment = environment

    SeasonsModUtil.appendedFunction(AbstractFieldMission,       "loadNextVehicleCallback",              SeasonsGrowthNPCMissions.inj_abstractFieldMission_loadNextVehicleCallback)
    SeasonsModUtil.appendedFunction(FieldManager,               "setFieldPartitionStatus",              SeasonsGrowthNPCMissions.inj_fieldManager_setFieldPartitionStatus)
    SeasonsModUtil.appendedFunction(FieldManager,               "update",                               SeasonsGrowthNPCMissions.inj_fieldManager_update)
    SeasonsModUtil.appendedFunction(SowMission,                 "createModifier",                       SeasonsGrowthNPCMissions.inj_sowMission_createModifier)
    SeasonsModUtil.overwrittenConstant(BaleMission,             "FILL_SUCCESS_FACTOR",                  0.7) -- 0.8
    SeasonsModUtil.overwrittenConstant(BaleMission,             "REWARD_PER_HA_HAY",                    5000) -- 3000
    SeasonsModUtil.overwrittenConstant(BaleMission,             "REWARD_PER_HA_SILAGE",                 6000) -- 3300
    SeasonsModUtil.overwrittenConstant(BaleMission,             "SILAGE_VARIANT_CHANCE",                0.6) -- 0.5
    SeasonsModUtil.overwrittenConstant(MissionManager,          "MISSION_GENERATION_INTERVAL",          25 * 60 * 60 * 1000) -- 25 ingame hours
    SeasonsModUtil.overwrittenFunction(AbstractFieldMission,    "getMaxCutLiters",                      SeasonsGrowthNPCMissions.inj_abstractFieldMission_getMaxCutLiters)
    SeasonsModUtil.overwrittenFunction(FSBaseMission,           "getFoliageGrowthStateTimeMultiplier",  SeasonsGrowthNPCMissions.inj_fsBaseMission_getFoliageGrowthStateTimeMultiplier)
    SeasonsModUtil.overwrittenFunction(FSBaseMission,           "updateFoliageGrowthStateTime",         SeasonsGrowthNPCMissions.inj_fsBaseMission_updateFoliageGrowthStateTime)
    SeasonsModUtil.overwrittenFunction(Field,                   "getIsAIActive",                        SeasonsGrowthNPCMissions.inj_field_getIsAIActive)
    SeasonsModUtil.overwrittenFunction(FieldManager,            "getFruitIndexForField",                SeasonsGrowthNPCMissions.inj_fieldManager_getFruitIndexForField)
    SeasonsModUtil.overwrittenFunction(FieldManager,            "update",                               SeasonsGrowthNPCMissions.inj_fieldManager_update)
    SeasonsModUtil.overwrittenFunction(Mission00,               "getIsTourSupported",                   SeasonsGrowthNPCMissions.inj_mission00_getIsTourSupported)
    SeasonsModUtil.overwrittenFunction(SowMission,              "completeField",                        SeasonsGrowthNPCMissions.inj_sowMission_completeField)
    SeasonsModUtil.overwrittenFunction(SowMission,              "decideFruitType",                      SeasonsGrowthNPCMissions.inj_sowMission_decideFruitType)
    SeasonsModUtil.overwrittenFunction(SowMission,              "init",                                 SeasonsGrowthNPCMissions.inj_sowMission_init)
    SeasonsModUtil.overwrittenFunction(SowMission,              "partitionCompletion",                  SeasonsGrowthNPCMissions.inj_sowMission_partitionCompletion)
    SeasonsModUtil.overwrittenStaticFunction(CultivateMission,  "canRunOnField",                        SeasonsGrowthNPCMissions.inj_cultivateMission_canRunOnField)
    SeasonsModUtil.overwrittenStaticFunction(FertilizeMission,  "canRunOnField",                        SeasonsGrowthNPCMissions.inj_fertilizeMission_canRunOnField)
    SeasonsModUtil.overwrittenStaticFunction(FieldUtil,         "getMaxWeedState",                      SeasonsGrowthNPCMissions.inj_fieldUtil_getMaxWeedState)
    SeasonsModUtil.prependedFunction(BaleMission,               "completeField",                        SeasonsGrowthNPCMissions.inj_baleMission_completeField)
    SeasonsModUtil.prependedFunction(HarvestMission,            "completeField",                        SeasonsGrowthNPCMissions.inj_harvestMission_completeField)

    return self
end

function SeasonsGrowthNPCMissions:delete()
    self.messageCenter:unsubscribeAll(self)
end

function SeasonsGrowthNPCMissions:load()
    self.messageCenter:subscribe(SeasonsMessageType.YEAR_CHANGED, self.onYearChanged, self)
end

function SeasonsGrowthNPCMissions:loadFromSavegame(xmlFile)
    local i = 0
    while true do
        local key = string.format("seasons.growth.fields.field(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local fieldId = getXMLInt(xmlFile, key .. "#id")
        local fruitIndex = getXMLInt(xmlFile, key .. "#fruitIndex")

        local field = self.fieldManager:getFieldByIndex(fieldId)
        if fruitIndex ~= nil and field ~= nil then
            field.seasons_selectedFruit = fruitIndex
        end

        i = i + 1
    end
end

function SeasonsGrowthNPCMissions:saveToSavegame(xmlFile)
    local i = 0
    for _, field in pairs(self.fieldManager:getFields()) do
        local key = string.format("seasons.growth.fields.field(%d)", i)

        setXMLInt(xmlFile, key .. "#id", field.fieldId)

        if field.seasons_selectedFruit ~= nil then
            setXMLInt(xmlFile, key .. "#fruitIndex", field.seasons_selectedFruit)
        end

        i = i + 1
    end
end

function SeasonsGrowthNPCMissions:onMissionLoaded()
    self:generateFieldContents()
end

---Decide for each field what fruit it should have in the current year. It is used for sowing missions and by NPCs
function SeasonsGrowthNPCMissions:generateFieldContents()
    for _, field in pairs(self.fieldManager:getFields()) do
        -- State is currently unknown, so this game just loaded
        if field.seasons_n2 == nil then
            -- For new savegames, generate some history, otherwise load data from map
            if self.data.isNewGame and field:getIsAIActive() then
                field.seasons_n2 = math.random(0, SeasonsCropRotation.CATEGORIES_MAX)
                field.seasons_n1 = math.random(0, SeasonsCropRotation.CATEGORIES_MAX)
                field.seasons_f = 0
                field.seasons_h = 0

                self:writeFieldRotationToMap(field)
            else
                local x, z = field:getCenterOfFieldWorldPosition()
                field.seasons_n2, field.seasons_n1, field.seasons_f, field.seasons_h = self.cropRotation:getInfoAtWorldCoords(x, z)
            end
        end

        if field.fieldGrassMission then
            field.seasons_selectedFruit = FruitType.GRASS
        else
            local fruitIndex = self.cropRotation:getRandomRecommendation(field.seasons_n2, field.seasons_n1)
            if fruitIndex == nil then
                fruitIndex = self.fieldManager.availableFruitTypeIndices[math.random(1, self.fieldManager.fruitTypesCount)]
            end

            field.seasons_selectedFruit = fruitIndex
        end
    end
end

---Get whether given field can start planting in current period
function SeasonsGrowthNPCMissions:canPlantNow(field)
    local fruitIndex = field.seasons_selectedFruit
    if fruitIndex == nil or fruitIndex == 0 then
        return false
    end

    local fruitDesc = self.fruitTypeManager:getFruitTypeByIndex(fruitIndex)

    return self.data:canFruitBePlanted(fruitDesc.name, self.environment.period)
end

---Update given field partition with its own values, applying it all to the map directly
function SeasonsGrowthNPCMissions:writeFieldPartitionRotationToMap(field, partition)
    local bits = self.cropRotation:composeValues(field.seasons_n2, field.seasons_n1, field.seasons_f, field.seasons_h)

    local startWorldX, startWorldZ = partition.x0, partition.z0
    local widthWorldX, widthWorldZ = partition.widthX + partition.x0, partition.widthZ + partition.z0
    local heightWorldX, heightWorldZ = partition.heightX + partition.x0, partition.heightZ + partition.z0

    self.cropRotation:writeToMap(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, bits)
end

function SeasonsGrowthNPCMissions:writeFieldRotationToMap(field)
    for i = 1, table.getn(field.maxFieldStatusPartitions) do
        self:writeFieldPartitionRotationToMap(field, field.maxFieldStatusPartitions[i])
    end
end

------------------------------------------------
--- Events
------------------------------------------------

function SeasonsGrowthNPCMissions:onYearChanged()
    for _, field in pairs(self.fieldManager:getFields()) do
        -- Update variables for fallow state as well. This is cheaper than reading the data again
        if field.seasons_f == 0 then
            field.seasons_n2 = field.seasons_n1
            field.seasons_n1 = SeasonsCropRotation.CATEGORIES.FALLOW
        end

        field.seasons_f = 0
    end

    -- Generate new fruits to plant based on previous
    self:generateFieldContents()
end

------------------------------------------------
--- Injections
------------------------------------------------

---Switch completion detection of sowing from 1 to PLANTED
function SeasonsGrowthNPCMissions.inj_sowMission_createModifier(mission)
    if mission.completionFilter ~= nil then
        local ids = g_currentMission.fruits[mission.fruitType]
        local id = ids.id
        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(mission.fruitType)

        if fruitDesc ~= nil then
            mission.completionModifier2 = DensityMapModifier:new(id, fruitDesc.startStateChannel, fruitDesc.numStateChannels)
            mission.completionFilter2 = DensityMapFilter:new(mission.completionModifier2)
            mission.completionFilter2:setValueCompareParams("equal", SeasonsGrowth.PLANTED_STATE)
        end
    end
end

function SeasonsGrowthNPCMissions.inj_sowMission_partitionCompletion(mission, superFunc, x, z, widthX, widthZ, heightX, heightZ)
    mission.completionModifier:setParallelogramWorldCoords(x,z, widthX,widthZ, heightX,heightZ, "pvv")
    mission.completionModifier2:setParallelogramWorldCoords(x,z, widthX,widthZ, heightX,heightZ, "pvv")

    local _, area1, totalArea1 = mission.completionModifier:executeGet(mission.completionFilter)
    local _, area2, totalArea2 = mission.completionModifier2:executeGet(mission.completionFilter2)

    return area1 + area2, totalArea1
end

---When a field is complete, set the PLANTED value instead of 1, and also update the rotation map
function SeasonsGrowthNPCMissions.inj_sowMission_completeField(mission, superFunc)
    local fieldManager = g_fieldManager
    local oldFunc = fieldManager.setFieldPartitionStatus

    -- Override to always use the PLANTED state instead of 1
    fieldManager.setFieldPartitionStatus = function (fieldManager, field, partitions, i, fruitType, state, growthState, ...)
        oldFunc(fieldManager, field, partitions, i, fruitType, state, SeasonsGrowth.PLANTED_STATE, ...)
    end

    mission.field.seasons_h = 0

    superFunc(mission)

    fieldManager.setFieldPartitionStatus = oldFunc
end

---A field that has lapsed germination can be cultivated
function SeasonsGrowthNPCMissions.inj_cultivateMission_canRunOnField(superFunc, field, ...)
    local result = {superFunc(field, ...)}
    if result[1] then
        return unpack(result)
    end

    local x,z = field:getCenterOfFieldWorldPosition()
    local state = SeasonsGrowth.GERMINATION_FAILED_STATE - 1

    if field.fruitType == nil then
        return false
    end

    local area, totalArea = FieldUtil.getFruitArea(x-1,z-1, x+1,z-1, x-1,z+1, {},{}, field.fruitType, state, state, 0, 0, 0, false)
    if area > 0 then
        return true, FieldManager.FIELDSTATE_HARVESTED
    end

    return false
end

---A field with the PLANTED state can be fertilized
function SeasonsGrowthNPCMissions.inj_fertilizeMission_canRunOnField(superFunc, field, sprayFactor, fieldSpraySet, fieldPlowFactor, limeFactor, maxWeedState)
    local result = {superFunc(field, sprayFactor, fieldSpraySet, fieldPlowFactor, limeFactor, maxWeedState)}
    if result[1] then
        return unpack(result)
    end

    -- Can't be planted with no fruit
    if field.fruitType == nil then
        return false
    end

    if fieldSpraySet then
        return false
    end

    local sprayLevel = sprayFactor * g_currentMission.sprayLevelMaxValue
    if sprayLevel >= g_currentMission.sprayLevelMaxValue then
        return false
    end

    local x,z = field:getCenterOfFieldWorldPosition()
    local state = SeasonsGrowth.PLANTED_STATE - 1
    local area, totalArea = FieldUtil.getFruitArea(x-1,z-1, x+1,z-1, x-1,z+1, {},{}, field.fruitType, state, state, 0, 0, 0, false)

    if area > 0 then
        return true, FieldManager.FIELDSTATE_GROWING, SeasonsGrowth.PLANTED_STATE
    end

    return false
end

---Change sowing state from 1 too PLANTED
function SeasonsGrowthNPCMissions.inj_fieldManager_update(fieldManager, dt)
    if fieldManager.fieldStatusParametersToSet ~= nil and fieldManager.fieldStatusParametersToSet[5] == FieldManager.FIELDSTATE_GROWING and fieldManager.fieldStatusParametersToSet[6] == 1 then
        fieldManager.fieldStatusParametersToSet[6] = SeasonsGrowth.PLANTED_STATE
    end
end

---The multiplier is used for delaying work of the NPCs.
function SeasonsGrowthNPCMissions.inj_fsBaseMission_getFoliageGrowthStateTimeMultiplier(mission, superFunc)
    local multiplier = g_seasons.environment.daysPerSeason / 3 * 1.3

    return multiplier / mission.missionInfo.timeScale
end

---Update the foliage updaters with a forced speed of 0
function SeasonsGrowthNPCMissions.inj_fsBaseMission_updateFoliageGrowthStateTime(mission, superFunc)
    local old = mission.getFoliageGrowthStateTimeMultiplier
    mission.getFoliageGrowthStateTimeMultiplier = function()
        return 0
    end

    superFunc(mission)

    mission.getFoliageGrowthStateTimeMultiplier = old
end

---Add support for no-fruit-available
function SeasonsGrowthNPCMissions.inj_sowMission_init(mission, superFunc, field, ...)
    mission.fruitType = mission:decideFruitType(field)
    if mission.fruitType == nil then
        return false
    end

    -- Prevent updates again
    local oldFunc = SowMission.decideFruitType
    SowMission.decideFruitType = function() return mission.fruitType end

    local result = superFunc(mission, field, ...)

    SowMission.decideFruitType = oldFunc

    return result
end

---Look into crop rotation and the calendar to pick a fruit
function SeasonsGrowthNPCMissions.inj_sowMission_decideFruitType(mission, superFunc, field)
    -- Fallow
    if field.seasons_selectedFruit == 0 then
        return nil
    end

    -- Check if sowing is possible in the calendar
    if not g_seasons.growth.npcs:canPlantNow(field) then
        return nil
    end

    return field.seasons_selectedFruit
end

---Let NPCs pick proper fruits using rotation and calendar
function SeasonsGrowthNPCMissions.inj_fieldManager_getFruitIndexForField(fieldManager, superFunc, field)
    -- Fallow
    if field.seasons_selectedFruit == 0 then
        return nil
    end

    if not g_seasons.growth.npcs:canPlantNow(field) then
        return nil
    end

    return field.seasons_selectedFruit
end

---Also update rotation map after harvesting. The setFieldPartitionStatus will write it to the map
function SeasonsGrowthNPCMissions.inj_harvestMission_completeField(mission)
    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(mission.field.fruitType)

    mission.field.seasons_n2 = mission.field.seasons_n1
    mission.field.seasons_n1 = fruitDesc.rotation.category
    mission.field.seasons_f = 1
    mission.field.seasons_h = 1
end

---Also update rotation map after baling. The setFieldPartitionStatus will write it to the map
function SeasonsGrowthNPCMissions.inj_baleMission_completeField(mission)
    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(mission.field.fruitType)

    mission.field.seasons_n2 = mission.field.seasons_n1
    mission.field.seasons_n1 = fruitDesc.rotation.category
    mission.field.seasons_f = 1
    mission.field.seasons_h = 1
end

---When updating a field partition, also update the rotation map
-- On top of that, if the first partition is updated, also try to look whether the NPC planted or Harvested.
function SeasonsGrowthNPCMissions.inj_fieldManager_setFieldPartitionStatus(fieldManager, field, fieldPartitions, fieldPartitionIndex, fruitIndex, fieldState, growthState, sprayState, setSpray, plowState, weedState, limeState)
    if fieldPartitionIndex == 1 and fruitIndex ~= nil then
        -- If growth state is PLANTED
        if growthState == SeasonsGrowth.PLANTED_STATE then
            -- Reset harvest bit
            field.seasons_h = 0
        else
            local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
            local fertilizerFruit = fruitDesc.minHarvestingGrowthState == 0 and fruitDesc.maxHarvestingGrowthState == 0 and fruitDesc.cutState == 0

            -- When field is cut and it is not a fertilizer fruit, update the rotation. Use h to check if we already rotated
            if growthState == fruitDesc.cutState and not fertilizerFruit and field.seasons_h == 0 then
                -- A harvest happened, update
                field.seasons_n2 = field.seasons_n1 or 0
                field.seasons_n1 = fruitDesc.rotation.category
                field.seasons_f = 1
                field.seasons_h = 1
            end
        end
    end

    if field.seasons_n2 ~= nil and field.seasons_n1 ~= nil then
        g_seasons.growth.npcs:writeFieldPartitionRotationToMap(field, fieldPartitions[fieldPartitionIndex])
    end
end

---Add the crop rotation yield multiplier to expected fruit
function SeasonsGrowthNPCMissions.inj_abstractFieldMission_getMaxCutLiters(mission, superFunc)
    local liters = superFunc(mission)

    local multiplier = g_seasons.growth.cropRotation:getRotationYieldMultiplier(mission.field.seasons_n2, mission.field.seasons_n1, mission.field.fruitType)

    return liters * multiplier
end

---Disable all tours as the fields are not set up for it.
function SeasonsGrowthNPCMissions.inj_mission00_getIsTourSupported(mission, superFunc)
    return false
end

---Disable any AI when fields are frozen
function SeasonsGrowthNPCMissions.inj_field_getIsAIActive(field, superFunc)
    return superFunc(field) and not g_seasons.weather:isGroundFrozen()
end

---Fix initial borrow visual state
function SeasonsGrowthNPCMissions.inj_abstractFieldMission_loadNextVehicleCallback(mission, vehicle, vehicleLoadState, arguments)
    local length = SeasonsAgeWear.NUM_HOURS_TOTAL_WEAR * 0.5 + (math.random() * 2 - 1) * 0.3 * SeasonsAgeWear.NUM_HOURS_TOTAL_WEAR
    vehicle:seasons_getSpecTable("ageWear").lastRepaintOperatingTime = vehicle:getOperatingTime() - length * 60 * 1000 * 60
    vehicle:seasons_getSpecTable("seasonsVehicle").nextRepair = vehicle:getOperatingTime() / 1000 + ((SeasonsAgeWear.NUM_HOURS_TOTAL_WEAR - 8) + math.random() * 3) * 60 * 60

    -- Update the scratches
    vehicle:setOperatingTime(vehicle:getOperatingTime(), true)
end

---Adjusted detection area and heuristics of weed.
function SeasonsGrowthNPCMissions.inj_fieldUtil_getMaxWeedState(superFunc, field)
    local weedType = g_fruitTypeManager:getWeedFruitType()

    if weedType ~= nil then
        local maxState = 0
        local maxArea = 0

        local states = {}

        local x,z = field:getCenterOfFieldWorldPosition()

        FieldUtil.weedModifier:setParallelogramWorldCoords(x - 8,z - 8, 16,0, 0,16, "pvv")

        local filter = DensityMapFilter:new(FieldUtil.weedModifier)

        for i = 1, 5 do
            filter:setValueCompareParams("equal", i)
            local area, _ = FieldUtil.weedModifier:executeGet(filter, FieldUtil.terrainDetailFilter)

            if area > 1 then
                -- Always go higher, if still at 1 or below
                if i > maxState and maxState <= 1 then
                    maxState = i
                    maxArea = area
                end

                -- Once above 1, only go higher when area is larger
                if area > maxArea and i > 1 then
                    maxState = i
                    maxArea = area
                end
            end
        end

        return maxState
    end

    return 0
end

function SeasonsGrowthNPCMissions.inj_fieldManager_update(fieldManager, superFunc, dt)
    if g_server == nil then
        return
    end

    if fieldManager.fieldStatusParametersToSet ~= nil then
        if fieldManager.currentFieldPartitionIndex == nil then
            fieldManager.currentFieldPartitionIndex = 1
        else
            fieldManager.currentFieldPartitionIndex = fieldManager.currentFieldPartitionIndex + 1
        end

        if fieldManager.currentFieldPartitionIndex > table.getn(fieldManager.fieldStatusParametersToSet[2]) then
            fieldManager.currentFieldPartitionIndex = nil
            fieldManager.fieldStatusParametersToSet = nil
        end

        if fieldManager.fieldStatusParametersToSet ~= nil then
            local args = fieldManager.fieldStatusParametersToSet
            args[3] = fieldManager.currentFieldPartitionIndex

            fieldManager:setFieldPartitionStatus(args[1], args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[9], args[10], args[11])
        end
    else
        -- check for withered/cultivated fields
        local field = fieldManager.fields[fieldManager.fieldIndexToCheck]

        if field ~= nil and field:getIsAIActive() and field.fieldMissionAllowed and field.currentMission == nil and field.fruitType ~= FruitType.GRASS  then
            local multiplier = g_currentMission:getFoliageGrowthStateTimeMultiplier()
            local x,z = field:getCenterOfFieldWorldPosition()

            if field.fruitType ~= nil then
                local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(field.fruitType)
                if fruitDesc == nil then -- Safety check
                    field.fruitType = nil
                    return
                end

                local fertilizerFruit = (fruitDesc.minHarvestingGrowthState == 0) and (fruitDesc.maxHarvestingGrowthState == 0) and (fruitDesc.cutState == 0)
                local maxGrowthState = FieldUtil.getMaxGrowthState(field, field.fruitType)

                if field.maxKnownGrowthState == nil then
                    field.maxKnownGrowthState = maxGrowthState
                elseif field.maxKnownGrowthState ~= maxGrowthState then
                    field.maxKnownGrowthState = maxGrowthState
                    g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_GROWING, true)
                end

                if fertilizerFruit then
                    local area, totalArea = FieldUtil.getFruitArea(x-1,z-1, x+1,z-1, x-1,z+1, {},{}, field.fruitType, 2, 2, 0, 0, 0, false)
                    if area > 0.5 * totalArea then
                        fieldManager.fieldStatusParametersToSet = {field, field.setFieldStatusPartitions, 1, nil, FieldManager.FIELDSTATE_CULTIVATED, 0, g_currentMission.sprayLevelMaxValue, true}

                        g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_CULTIVATED)
                    end
                end

                if not fertilizerFruit then
                    local forceWithering = g_currentMission.missionInfo.isPlantWitheringEnabled and math.random() > 0.7

                    if forceWithering then
                        -- withered -> cultivated
                        local witheredState = fruitDesc.witheringNumGrowthStates - 1
                        if fruitDesc.witheringNumGrowthStates == fruitDesc.numGrowthStates then       -- potato case
                            witheredState = nil
                        end

                        if witheredState ~= nil then
                            local area, totalArea = FieldUtil.getFruitArea(x-1,z-1, x+1,z-1, x-1,z+1, {},{}, field.fruitType, witheredState, witheredState, 0, 0, 0, false)
                            if area > 0.5 * totalArea then
                                g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_WITHERED)

                                if field.lastCheckedTime == nil then
                                    field.lastCheckedTime = g_currentMission.time
                                elseif g_currentMission.time > field.lastCheckedTime + (fieldManager.minFieldGrowthStateTime * multiplier) then
                                    local sprayFactor = FieldUtil.getSprayFactor(field) * g_currentMission.sprayLevelMaxValue
                                    fieldManager.fieldStatusParametersToSet = {field, field.setFieldStatusPartitions, 1, nil, FieldManager.FIELDSTATE_CULTIVATED, 0, sprayFactor, false}
                                    field.lastCheckedTime = nil

                                    g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_CULTIVATED)
                                end
                            end
                        end
                    else
                        -- fully grown -> cut
                        local maxState = fruitDesc.maxHarvestingGrowthState
                        if fruitDesc.maxPreparingGrowthState > -1 then
                            maxState = fruitDesc.maxPreparingGrowthState
                        end

                        local area, totalArea = FieldUtil.getFruitArea(x-1,z-1, x+1,z-1, x-1,z+1, {},{}, field.fruitType, maxState, maxState, 0, 0, 0, false)
                        if area > 0.5 * totalArea then
                            -- Check a flag so we don't spam the MM every frame. Not saved. This is possible because nothing is allowed at grown except harvesting.
                            -- Once harvested by code, this is reset. Once done manually, it is also reset.
                            if field.lastCheckedTime == nil then
                                field.lastCheckedTime = g_currentMission.time
                            elseif g_currentMission.time > field.lastCheckedTime + (fieldManager.minFieldGrowthStateTime * multiplier) then
                                fieldManager.fieldStatusParametersToSet = {field, field.setFieldStatusPartitions, 1, field.fruitType, FieldManager.FIELDSTATE_HARVESTED, fruitDesc.cutState, 0, false, nil, 0}
                                field.lastCheckedTime = nil

                                g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_HARVESTED)
                            end
                        end
                    end

                    if maxGrowthState >= fruitDesc.minHarvestingGrowthState or (fruitDesc.preparedGrowthState ~= -1 and maxGrowthState >= fruitDesc.minPreparingGrowthState + 1 and maxGrowthState <= fruitDesc.maxPreparingGrowthState) then
                        g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_GROWN)
                    end

                    -- sown+weeds -> weeded
                    -- if fieldManager.fieldStatusParametersToSet == nil then
                    local maxWeedState = FieldUtil.getMaxWeedState(field)
                    if field.maxKnownWeedState == nil then
                        field.maxKnownWeedState = maxWeedState
                    elseif field.maxKnownWeedState ~= maxWeedState then
                        field.maxKnownWeedState = maxWeedState
                        g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_GROWING, true)
                    end


                    if maxWeedState == 2 and (maxGrowthState == 1 or maxGrowthState == 2) then

                        if field.lastCheckedTime == nil then
                            field.lastCheckedTime = g_currentMission.time
                        elseif g_currentMission.time > field.lastCheckedTime + (fieldManager.minFieldGrowthStateTime * multiplier * 0.5) then
                            local sprayFactor = FieldUtil.getSprayFactor(field) * g_currentMission.sprayLevelMaxValue
                            fieldManager.fieldStatusParametersToSet = {field, field.setFieldStatusPartitions, 1, field.fruitType, FieldManager.FIELDSTATE_GROWING, maxGrowthState, sprayFactor, false, nil, 0}
                            field.lastCheckedTime = nil

                            g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_WEEDED)
                        end

                    -- growing+weeds -> sprayed
                    -- SEASONS: The change is here. Also allow other state combinations
                    elseif (maxWeedState >= 2 and maxWeedState <= 3 and maxGrowthState >= 1) or (maxWeedState == 1 and maxGrowthState >= 3) then
                        if field.lastCheckedTime == nil then
                            field.lastCheckedTime = g_currentMission.time
                        elseif g_currentMission.time > field.lastCheckedTime + (fieldManager.minFieldGrowthStateTime * multiplier) then
                            local sprayFactor = FieldUtil.getSprayFactor(field) * g_currentMission.sprayLevelMaxValue
                            local weedState = FieldUtil.getMaxWeedState(field)
                            local weedType = g_fruitTypeManager:getWeedFruitType()
                            local newWeedState

                            for _, data in ipairs(weedType.weed.herbicideReplaces) do
                                if data.src == weedState then
                                    newWeedState = data.target
                                    break
                                end
                            end

                            fieldManager.fieldStatusParametersToSet = {field, field.setFieldStatusPartitions, 1, field.fruitType, FieldManager.FIELDSTATE_GROWING, maxGrowthState, sprayFactor, false, nil, newWeedState}
                            field.lastCheckedTime = nil

                            g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_SPRAYED)
                        end
                    end

                    -- cut -> cultivated
                    local area, totalArea = FieldUtil.getFruitArea(x-1,z-1, x+1,z-1, x-1,z+1, {},{}, field.fruitType, fruitDesc.cutState, fruitDesc.cutState, 0, 0, 0, false)

                    if area > 0.5 * totalArea then
                        field.stateIsKnown = false -- reset after manual harvest

                        if field.lastCheckedTime == nil then
                            field.lastCheckedTime = g_currentMission.time
                        elseif g_currentMission.time > field.lastCheckedTime + (fieldManager.minFieldGrowthStateTime * multiplier) then
                            local sprayFactor = FieldUtil.getSprayFactor(field) * g_currentMission.sprayLevelMaxValue
                            fieldManager.fieldStatusParametersToSet = {field, field.setFieldStatusPartitions, 1, nil, FieldManager.FIELDSTATE_CULTIVATED, 0, sprayFactor, false}
                            field.lastCheckedTime = nil

                            g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_CULTIVATED)
                        end
                    end

                end
            else
                if field.lastCheckedTime == nil then
                    field.lastCheckedTime = g_currentMission.time
                elseif g_currentMission.time > field.lastCheckedTime + (fieldManager.minFieldGrowthStateTime * multiplier) then
                    -- cultivated -> sown
                    local fruitIndex = fieldManager:getFruitIndexForField(field)
                    if fruitIndex ~= nil then
                        local sprayFactor = FieldUtil.getSprayFactor(field) * g_currentMission.sprayLevelMaxValue
                        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
                        fieldManager.fieldStatusParametersToSet = {field, field.setFieldStatusPartitions, 1, fruitIndex, FieldManager.FIELDSTATE_GROWING, 1, sprayFactor, false, nil, fruitDesc.plantsWeed and 1 or 0}

                        g_missionManager:validateMissionOnField(field, FieldManager.FIELDEVENT_SOWN)
                    end

                    field.lastCheckedTime = nil
                end
            end
        end

        --renderText(0.8, 0.5, 0.02, "fieldManager.fieldIndexToCheck "..tostring(fieldManager.fieldIndexToCheck))

        fieldManager.fieldIndexToCheck = fieldManager.fieldIndexToCheck - 1
        if fieldManager.fieldIndexToCheck == 0 then
            fieldManager.fieldIndexToCheck = table.getn(fieldManager.fields)
        end
    end
end
