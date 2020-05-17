----------------------------------------------------------------------------------------------------
-- SeasonsVehicle
----------------------------------------------------------------------------------------------------
-- Purpose:  Vehicle changes for Seasons
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsVehicle = {}

local SeasonsVehicle_mt = Class(SeasonsVehicle)

---Install specs and inject into vehicle types. This has to be done super early as the
-- vehicle types are finalized before mission creation
function SeasonsVehicle.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    -- Specializations are namespaced for mods: the names are prefixed with the mod folder/zip name and a dot. E.g. FS19_RM_Seasons.snowTracks
    specializationManager:addSpecialization("snowTracks", "SeasonsSnowTracks", Utils.getFilename("src/vehicles/specs/SeasonsSnowTracks.lua", modDirectory), nil) -- Nil is important here
    specializationManager:addSpecialization("snowDirt", "SeasonsSnowDirt", Utils.getFilename("src/vehicles/specs/SeasonsSnowDirt.lua", modDirectory), nil)
    specializationManager:addSpecialization("ageWear", "SeasonsAgeWear", Utils.getFilename("src/vehicles/specs/SeasonsAgeWear.lua", modDirectory), nil)
    specializationManager:addSpecialization("seasonsVehicle", "SeasonsVehicleSpec", Utils.getFilename("src/vehicles/specs/SeasonsVehicleSpec.lua", modDirectory), nil)
    specializationManager:addSpecialization("seasonsWorkArea", "SeasonsWorkArea", Utils.getFilename("src/vehicles/specs/SeasonsWorkArea.lua", modDirectory), nil)
    specializationManager:addSpecialization("seasonsFillUnit", "SeasonsFillUnit", Utils.getFilename("src/vehicles/specs/SeasonsFillUnit.lua", modDirectory), nil)
    specializationManager:addSpecialization("variableTreePlanter", "SeasonsVariableTreePlanter", Utils.getFilename("src/vehicles/specs/SeasonsVariableTreePlanter.lua", modDirectory), nil)
    specializationManager:addSpecialization("seasonsLivestockTrailer", "SeasonsLivestockTrailer", Utils.getFilename("src/vehicles/specs/SeasonsLivestockTrailer.lua", modDirectory), nil)
    specializationManager:addSpecialization("seasonsCutter", "SeasonsCutter", Utils.getFilename("src/vehicles/specs/SeasonsCutter.lua", modDirectory), nil)
    specializationManager:addSpecialization("seasonsShovel", "SeasonsShovel", Utils.getFilename("src/vehicles/specs/SeasonsShovel.lua", modDirectory), nil)
    
    for typeName, typeEntry in pairs(vehicleTypeManager:getVehicleTypes()) do
        vehicleTypeManager:addSpecialization(typeName, modName .. ".seasonsVehicle")

        if SpecializationUtil.hasSpecialization(Wheels, typeEntry.specializations) then
            -- Make sure to namespace the spec again
            vehicleTypeManager:addSpecialization(typeName, modName .. ".snowTracks")
        end

        if SpecializationUtil.hasSpecialization(Washable, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".snowDirt")
        end

        if SpecializationUtil.hasSpecialization(Wearable, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".ageWear")
        end

        if SpecializationUtil.hasSpecialization(WorkArea, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".seasonsWorkArea")
        end

        if SpecializationUtil.hasSpecialization(FillUnit, typeEntry.specializations) and SpecializationUtil.hasSpecialization(Dischargeable, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".seasonsFillUnit")
        end

        if SpecializationUtil.hasSpecialization(TreePlanter, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".variableTreePlanter")
        end

        if SpecializationUtil.hasSpecialization(LivestockTrailer, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".seasonsLivestockTrailer")
        end

        if SpecializationUtil.hasSpecialization(Cutter, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".seasonsCutter")
        end

        if SpecializationUtil.hasSpecialization(Shovel, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".seasonsShovel")
        end
    end

    SeasonsModUtil.overwrittenFunction(Wheels,      "getCurrentSurfaceSound",       SeasonsVehicle.inj_wheels_getCurrentSurfaceSound)
    SeasonsModUtil.overwrittenFunction(Rideable,    "getHoofSurfaceSound",          SeasonsVehicle.inj_rideable_getHoofSurfaceSound)

    SeasonsModUtil.appendedFunction(Baler,          "onPostLoad",                   SeasonsVehicle.inj_baler_onPostLoad)
    SeasonsModUtil.appendedFunction(Baler,          "registerOverwrittenFunctions", SeasonsVehicle.inj_baler_registerOverwrittenFunctions)
    SeasonsModUtil.appendedFunction(Combine,        "loadCombineSetup",             SeasonsVehicle.inj_combine_loadCombineSetup)
    SeasonsModUtil.appendedFunction(Tedder,         "onLoad",                       SeasonsVehicle.inj_tedder_onLoad)
    SeasonsModUtil.appendedFunction(Windrower,      "onLoad",                       SeasonsVehicle.inj_windrower_onLoad)
    SeasonsModUtil.overwrittenFunction(Combine,     "getIsThreshingAllowed",        SeasonsVehicle.inj_combine_getIsThreshingAllowed)
    SeasonsModUtil.overwrittenFunction(ForageWagon, "processForageWagonArea",       SeasonsVehicle.inj_forageWagon_processForageWagonArea)
    SeasonsModUtil.overwrittenFunction(Mower,       "processDropArea",              SeasonsVehicle.inj_mower_processDropArea)
    SeasonsModUtil.overwrittenFunction(Shovel,      "onUpdateTick",                 SeasonsVehicle.inj_shovel_onUpdateTick)
    SeasonsModUtil.overwrittenFunction(Tedder,      "processDropArea",              SeasonsVehicle.inj_tedder_processDropArea)
    SeasonsModUtil.overwrittenFunction(Windrower,   "processDropArea",              SeasonsVehicle.inj_windrower_processDropArea)
    SeasonsModUtil.overwrittenFunction(Windrower,   "processWindrowerArea",         SeasonsVehicle.inj_windrower_processWindrowerArea)
end

function SeasonsVehicle:new(mission, specializationManager, modDirectory, vehicleTypeManager, workAreaTypeManager, fillTypeManager, i18n)
    local self = setmetatable({}, SeasonsVehicle_mt)

    self.mission = mission
    self.isServer = mission:getIsServer()
    self.specializationManager = specializationManager
    self.vehicleTypeManager = vehicleTypeManager
    self.modDirectory = modDirectory

    self.data = SeasonsVehicleData:new(workAreaTypeManager)
    self.fillTypeData = SeasonsVehicleFillTypeData:new(fillTypeManager)
    self.vehiclesToUpdate = {}

    self.updateDelay = 250
    self.currentUpdateDelay = 0

    self.snowTracksEnabled = true

    SeasonsModUtil.overwrittenConstant(getfenv(0).g_i18n.texts, "warning_doNotThreshDuringRainOrHail", i18n:getText("seasons_warning_doNotThreshWithMoistCrops"))

    return self
end

function SeasonsVehicle:delete()
    self.vehiclesToUpdate = {}

    self.data:delete()
    self.fillTypeData:delete()
end

function SeasonsVehicle:load()
    self.data:load()
    self.fillTypeData:load()

    self.lastMinute = math.abs(self.mission.environment.currentMinute)
end

function SeasonsVehicle:update(dt)
    if self.isServer then
        local currentMinute = math.abs(self.mission.environment.currentMinute)
        local diff = math.abs(currentMinute - self.lastMinute)

        -- Interval ever 15 min
        if diff > 0 and diff % 15 == 0 then
            self.lastMinute = currentMinute

            for _, vehicle in ipairs(self.vehiclesToUpdate) do
                vehicle:onQuarterOfAnHourChanged(dt)
            end
        end

        self.currentUpdateDelay = self.currentUpdateDelay - dt

        if self.currentUpdateDelay < 0 then
            for _, vehicle in ipairs(self.vehiclesToUpdate) do
                vehicle:onIntervalUpdate(dt)
            end

            self.currentUpdateDelay = self.updateDelay
        end
    end
end

function SeasonsVehicle:loadFromSavegame(xmlFile)
    self.snowTracksEnabled = Utils.getNoNil(getXMLBool(xmlFile, "seasons.vehicle.snowTracksEnabled"), self.snowTracksEnabled)
end

function SeasonsVehicle:saveToSavegame(xmlFile)
    setXMLBool(xmlFile, "seasons.vehicle.snowTracksEnabled", self.snowTracksEnabled)
end

function SeasonsVehicle:addVehicleToUpdateList(vehicle)
    if not self:isVehicleInUpdateList(vehicle) then
        ListUtil.addElementToList(self.vehiclesToUpdate, vehicle)
    end
end

function SeasonsVehicle:isVehicleInUpdateList(vehicle)
    return ListUtil.hasListElement(self.vehiclesToUpdate, vehicle)
end

function SeasonsVehicle:removeVehicleFromToUpdateList(vehicle)
    ListUtil.removeElementFromList(self.vehiclesToUpdate, vehicle)
end

function SeasonsVehicle:setDataPaths(paths)
    self.data:setDataPaths(paths)
end

function SeasonsVehicle:setFillTypeDataPaths(paths)
    self.fillTypeData:setDataPaths(paths)
end

function SeasonsVehicle:getSnowTracksEnabled()
    return self.snowTracksEnabled
end

function SeasonsVehicle:setSnowTracksEnabled(enabled)
    self.snowTracksEnabled = enabled
end

----------------------
-- Injections
----------------------

---Add support for snow surface sounds
function SeasonsVehicle.inj_wheels_getCurrentSurfaceSound(vehicle, superFunc)
    local spec = vehicle.spec_wheels

    for _, wheel in ipairs(spec.wheels) do
        if wheel.isInSnow then
            return spec.surfaceNameToSound["snow"]
        elseif wheel.contact ~= Wheels.WHEEL_NO_CONTACT then
            break
        end
    end

    return superFunc(vehicle)
end

---Add hoof sounds based on height type
function SeasonsVehicle.inj_rideable_getHoofSurfaceSound(vehicle, superFunc, x, y, z, hitTerrain)
    local spec = vehicle.spec_rideable

    if hitTerrain then
        local heightType = DensityMapHeightUtil.getHeightTypeDescAtWorldPos(x, y, z, 0.5)
        if heightType ~= nil and heightType.soundMaterialId ~= nil then
            return spec.surfaceIdToSound[heightType.soundMaterialId]
        end
    end

    return superFunc(vehicle, x, y, z, hitTerrain)
end

---Make changes for the grass system: drop wet/semidry depending on weather and update drying mask
function SeasonsVehicle.inj_mower_processDropArea(vehicle, superFunc, dropArea, dt)
    local prevLiters = dropArea.litersToDrop
    local realType = dropArea.fillType

    if realType == FillType.GRASS_WINDROW then
        if g_seasons.weather:isCropWet() then
            dropArea.fillType = FillType.GRASS_WINDROW
        else
            dropArea.fillType = FillType.SEMIDRY_GRASS_WINDROW
        end
    end

    superFunc(vehicle, dropArea, dt)

    -- Reset
    dropArea.fillType = realType

    -- Set drying map to 1
    if realType == FillType.GRASS_WINDROW and dropArea.litersToDrop ~= prevLiters then
        local xs, _, zs = getWorldTranslation(dropArea.start)
        local xw, _, zw = getWorldTranslation(dropArea.width)
        local xh, _, zh = getWorldTranslation(dropArea.height)

        g_seasons.grass:setDryingValue(xs, zs, xw, zw, xh, zh, 1)
        g_seasons.grass:setGrassDelayBit(xs, zs, xw, zw, xh, zh)
    end
end

---A tedder turns grass into semidry, semidry stays and dry stays dry.
function SeasonsVehicle.inj_tedder_onLoad(vehicle, savegame)
    local spec = vehicle.spec_tedder

    -- Convert grass to semidry
    spec.fillTypeConverters[FillType.GRASS_WINDROW] = { targetFillTypeIndex = FillType.SEMIDRY_GRASS_WINDROW, conversionFactor = 1 }
    spec.fillTypeConverters[FillType.SEMIDRY_GRASS_WINDROW] = { targetFillTypeIndex = FillType.SEMIDRY_GRASS_WINDROW, conversionFactor = 1 }

    -- Keep semidry and drygrass
    spec.fillTypeConvertersReverse[FillType.SEMIDRY_GRASS_WINDROW] = { FillType.GRASS_WINDROW, FillType.SEMIDRY_GRASS_WINDROW }
    spec.fillTypeConvertersReverse[FillType.DRYGRASS_WINDROW] = { FillType.DRYGRASS_WINDROW }
end

---Add windrower AI support for semi dry
function SeasonsVehicle.inj_windrower_onLoad(vehicle, savegame)
    if vehicle.addAIFruitRequirement ~= nil then
        vehicle:addAIFruitRequirement(FruitType.SEMIDRY_GRASS_WINDROW, 0, g_currentMission.terrainDetailHeightTypeNumChannels)
    end
end

---Always make the shovel think there is grass instead of semidry. Picking up semidry destroys the dryness
function SeasonsVehicle.inj_shovel_onUpdateTick(vehicle, superFunc, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local oldGet = DensityMapHeightUtil.getFillTypeAtLine
    DensityMapHeightUtil.getFillTypeAtLine = function(...)
        local fillType = oldGet(...)

        if fillType == FillType.SEMIDRY_GRASS_WINDROW then
            return FillType.GRASS_WINDROW
        end

        return fillType
    end

    -- When picking things up, always grab both grass and semidry (treat them as the same thing)
    local oldTip = DensityMapHeightUtil.tipToGroundAroundLine
    DensityMapHeightUtil.tipToGroundAroundLine = function(vehicle, delta, fillTypeIndex, ...)
        local dropped, lineOffset = oldTip(vehicle, delta, fillTypeIndex, ...)

        -- If request is grass windrow also pick up semi. Semi will never be asked for as we changed that in the getFillTypeAtLine
        if fillTypeIndex == FillType.GRASS_WINDROW then
            local dropped2, lineOffset2 = oldTip(vehicle, delta, FillType.SEMIDRY_GRASS_WINDROW, ...)

            dropped = dropped + dropped2
            lineOffset = lineOffset + lineOffset2
        end

        return dropped, lineOffset
    end

    superFunc(vehicle, dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)

    DensityMapHeightUtil.getFillTypeAtLine = oldGet
    DensityMapHeightUtil.tipToGroundAroundLine = oldTip
end

---Add support for the semidry to the windrower but output grass
function SeasonsVehicle.inj_windrower_processWindrowerArea(vehicle, superFunc, workArea, dt)
    local dummy = #g_fruitTypeManager.fruitTypes + 1

    -- Create a dummy fruit for Semidry so it can be picked up
    g_fruitTypeManager.fruitTypes[dummy] = 0
    g_fruitTypeManager.fruitTypeIndexToWindrowFillTypeIndex[dummy] = FillType.SEMIDRY_GRASS_WINDROW

    local lastDroppedLiters, area = superFunc(vehicle, workArea, dt)

    g_fruitTypeManager.fruitTypes[dummy] = nil
    g_fruitTypeManager.fruitTypeIndexToWindrowFillTypeIndex[dummy] = nil

    return lastDroppedLiters, area
end

---When dropping semidry, drop it as grass instead because info on the drying map is lost
function SeasonsVehicle.inj_windrower_processDropArea(vehicle, superFunc, dropArea, litersToDrop, fillType)
    local dropped = superFunc(vehicle, dropArea, litersToDrop, fillType)

    if dropped > 0 then
        local xs, _, zs = getWorldTranslation(dropArea.start)
        local xw, _, zw = getWorldTranslation(dropArea.width)
        local xh, _, zh = getWorldTranslation(dropArea.height)

        g_seasons.grass:setGrassDelayBit(xs, zs, xw, zw, xh, zh)
    end

    return dropped
end

---When tedding, delay the drying
function SeasonsVehicle.inj_tedder_processDropArea(vehicle, superFunc, dropArea, fillType, litersToDrop)
    local dropped = superFunc(vehicle, dropArea, fillType, litersToDrop)

    if dropped > 0 then
        local xs, _, zs = getWorldTranslation(dropArea.start)
        local xw, _, zw = getWorldTranslation(dropArea.width)
        local xh, _, zh = getWorldTranslation(dropArea.height)

        g_seasons.grass:setGrassDelayBit(xs, zs, xw, zw, xh, zh)
    end

    return dropped
end

---When changing a fill unit for semigrass, transparently use grass instead.
function SeasonsVehicle.inj_baler_addFillUnitFillLevel(vehicle, superFunc, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    if fillTypeIndex == FillType.SEMIDRY_GRASS_WINDROW then
        fillTypeIndex = FillType.GRASS_WINDROW
    end

    return superFunc(vehicle, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
end

---Overwrite fill unit changes for baler
function SeasonsVehicle.inj_baler_registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addFillUnitFillLevel", SeasonsVehicle.inj_baler_addFillUnitFillLevel)
end

---Add semidry as pickup type
function SeasonsVehicle.inj_baler_onPostLoad(vehicle, savegame)
    table.insert(vehicle.spec_baler.pickupFillTypes, FillType.SEMIDRY_GRASS_WINDROW)
end

---Treat semidry and wet as the same
function SeasonsVehicle.inj_forageWagon_processForageWagonArea(vehicle, superFunc, workArea)
    -- When picking things up, always grab both grass and semidry (treat them as the same thing)
    local oldTip = DensityMapHeightUtil.tipToGroundAroundLine
    DensityMapHeightUtil.tipToGroundAroundLine = function(vehicle, delta, fillTypeIndex, ...)
        local dropped, lineOffset = oldTip(vehicle, delta, fillTypeIndex, ...)

        -- If request is grass windrow also pick up semi. Semi will never be asked for as we changed that in the getFillTypeAtLine
        if fillTypeIndex == FillType.GRASS_WINDROW then
            local dropped2, lineOffset2 = oldTip(vehicle, delta, FillType.SEMIDRY_GRASS_WINDROW, ...)

            dropped = dropped + dropped2
            lineOffset = lineOffset + lineOffset2
        end

        return dropped, lineOffset
    end

    local realArea, area = superFunc(vehicle, workArea)

    DensityMapHeightUtil.tipToGroundAroundLine = oldTip

    return realArea, area
end

---Update the warning of threshing and the actual allowing of threshing depending on moist
function SeasonsVehicle.inj_combine_getIsThreshingAllowed(vehicle, superFunc, earlyWarning)
    if g_seasons.weather:isCropWet() and g_seasons.weather:getCropMoistureEnabled() then
        -- Always act as if it rains
        g_seasons.weather.handler:setRainIndicationForced(true, 0)
    end

    local result = superFunc(vehicle, earlyWarning)

    g_seasons.weather.handler:setRainIndicationForced(false)

    return result
end

---Update combine config to fix a missing option
function SeasonsVehicle.inj_combine_loadCombineSetup(vehicle, xmlFile, baseKey, entry)
    -- Set a missing option from basegame XML
    if vehicle.configFileName == "data/vehicles/grimme/SE260/SE260.xml" then
        entry.allowThreshingDuringRain = true
    end
end
