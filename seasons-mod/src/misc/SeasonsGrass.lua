----------------------------------------------------------------------------------------------------
-- SeasonsGrass
----------------------------------------------------------------------------------------------------
-- Purpose:  Bale, grass rotting. Bale and silo fermentation. And hay drying delays.
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsGrass = {}

local SeasonsGrass_mt = Class(SeasonsGrass)

SeasonsGrass.BALE_MASK_RECT_SIZE = 2
SeasonsGrass.MAP_NUM_CHANNELS = 2

-- Value must be equal or bigger than threshold to pass
SeasonsGrass.DRYING_THRESHOLD = -20
SeasonsGrass.RAIN_THRESHOLD = 10

-- Very early installation
function SeasonsGrass.installSpecializations()
    SeasonsModUtil.appendedFunction(BaleWrapper,    "doStateChange",        SeasonsGrass.inj_baleWrapper_doStateChange)
    SeasonsModUtil.appendedFunction(BaleWrapper,    "onPostLoad",           SeasonsGrass.inj_baleWrapper_onPostLoad)
    SeasonsModUtil.appendedFunction(BaleWrapper,    "saveToXMLFile",        SeasonsGrass.inj_baleWrapper_saveToXMLFile)
    SeasonsModUtil.prependedFunction(BaleWrapper,   "pickupWrapperBale",    SeasonsGrass.inj_baleWrapper_pickupWrapperBale)
end

function SeasonsGrass:new(mission, densityMapScanner, densityMapHeightManager, messageCenter, modDirectory, fillTypeManager, environment, mask, weather, fruitTypeManager, baleTypeManager)
    local self = setmetatable({}, SeasonsGrass_mt)

    self.mission = mission
    self.densityMapScanner = densityMapScanner
    self.densityMapHeightManager = densityMapHeightManager
    self.messageCenter = messageCenter
    self.modDirectory = modDirectory
    self.fillTypeManager = fillTypeManager
    self.environment = environment
    self.mask = mask
    self.isServer = mission:getIsServer()
    self.weather = weather
    self.fruitTypeManager = fruitTypeManager
    self.baleTypeManager = baleTypeManager

    self.dryingMap = 0

    --Initialize cached lists of bale paths
    self.basegameToSeasonsHayBales = {}
    self.seasonsToBasegameHayBales = {}

    local seasonsBale = Utils.getFilename("resources/objects/bales/baleHay240.i3d", self.modDirectory)
    self.basegameToSeasonsHayBales["data/objects/squarebales/baleHay240.i3d"] = seasonsBale
    self.seasonsToBasegameHayBales[seasonsBale] = "data/objects/squarebales/baleHay240.i3d"

    local seasonsBale = Utils.getFilename("resources/objects/bales/roundbaleHay_w112_d130.i3d", self.modDirectory)
    self.basegameToSeasonsHayBales["data/objects/roundbales/roundbaleHay_w112_d130.i3d"] = seasonsBale
    self.seasonsToBasegameHayBales[seasonsBale] = "data/objects/roundbales/roundbaleHay_w112_d130.i3d"

    -- Note: spec injections are below, loaded earlier

    SeasonsModUtil.overwrittenFunction(BunkerSilo,  "load",                     SeasonsGrass.inj_bunkerSilo_load)
    SeasonsModUtil.appendedFunction(BunkerSilo,     "delete",                   SeasonsGrass.inj_bunkerSilo_delete)
    SeasonsModUtil.overwrittenConstant(BunkerSilo,  "onSeasonLengthChanged",    SeasonsGrass.inj_bunkerSilo_onSeasonLengthChanged)

    SeasonsModUtil.appendedFunction(Bale,               "readStream",           SeasonsGrass.inj_bale_readStream)
    SeasonsModUtil.appendedFunction(Bale,               "saveToXMLFile",        SeasonsGrass.inj_bale_saveToXMLFile)
    SeasonsModUtil.appendedFunction(FSBaseMission,      "addLimitedObject",     SeasonsGrass.inj_fsBaseMission_addLimitedObject)
    SeasonsModUtil.appendedFunction(FSBaseMission,      "removeLimitedObject",  SeasonsGrass.inj_fsBaseMission_removeLimitedObject)

    SeasonsModUtil.appendedFunction(Bale,               "load",                 SeasonsGrass.inj_bale_load)
    SeasonsModUtil.appendedFunction(Bale,               "writeStream",          SeasonsGrass.inj_bale_writeStream)
    SeasonsModUtil.appendedFunction(Mission00,          "loadAdditionalFiles",  SeasonsGrass.inj_mission00_loadAdditionalFiles)
    SeasonsModUtil.overwrittenConstant(Bale,            "getIsFermenting",      SeasonsGrass.inj_bale_getIsFermenting)
    SeasonsModUtil.overwrittenConstant(Bale,            "setFillType",          SeasonsGrass.inj_bale_setFillType)
    SeasonsModUtil.overwrittenFunction(Bale,            "createNode",           SeasonsGrass.inj_bale_createNode)
    SeasonsModUtil.overwrittenFunction(Bale,            "loadFromXMLFile",      SeasonsGrass.inj_bale_loadFromXMLFile)
    SeasonsModUtil.overwrittenFunction(SellingStation,  "addFillLevelFromTool", SeasonsGrass.inj_sellingStation_addFillLevelFromTool)

    local andersonDlc = getfenv(0)["pdlc_andersonPack"]
    if andersonDlc ~= nil and g_modIsLoaded["pdlc_andersonPack"] then
        SeasonsModUtil.overwrittenFunction(andersonDlc.InlineBale, "replacePendingBale", SeasonsGrass.inj_inlineBale_replacePendingBale)
        SeasonsModUtil.overwrittenFunction(andersonDlc.InlineBale, "openBale", SeasonsGrass.inj_inlineBale_openBale)
    end

    return self
end

function SeasonsGrass:delete()
    if self.dryingMap ~= 0 then
        delete(self.dryingMap)
    end

    delete(self.materialHolder)
    delete(self.particleMaterialHolder)
    if self.hayMaterialHolder then
        delete(self.hayMaterialHolder)
    end

    self.messageCenter:unsubscribeAll(self)
end

function SeasonsGrass:load()
    self.densityMapScanner:registerCallback("ReduceStraw", self.dms_reduceStraw, self, nil, true, self.dms_foldJob)
    self.densityMapScanner:registerCallback("DryingMidnight", self.dms_dryingMidnight, self, nil, true)
    self.densityMapScanner:registerCallback("DryingInterval", self.dms_dryingInterval, self, nil, true)
    self.densityMapScanner:registerCallback("DryingDelay", self.dms_dryingDelay, self, nil, true, self.dms_dryingDelay_foldJob)

    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.HOUR_CHANGED_FIX, self.onHourChanged, self)

    if self.isServer then
        self.mission.environment:addMinuteChangeListener(self)
    end
end

function SeasonsGrass:onTerrainLoaded()
    self:loadDryingMap()

    local terrainDetailHeightId = self.mission.terrainDetailHeightId

    local modifiers = {}

    -- Changing height
    modifiers.height = {}
    modifiers.height.modifierHeight = DensityMapModifier:new(terrainDetailHeightId, getDensityMapHeightFirstChannel(terrainDetailHeightId), getDensityMapHeightNumChannels(terrainDetailHeightId))
    modifiers.height.filterType = DensityMapFilter:new(terrainDetailHeightId, self.mission.terrainDetailHeightTypeFirstChannel, self.mission.terrainDetailHeightTypeNumChannels)

    -- Changing type
    modifiers.fillType = {}
    modifiers.fillType.modifierType = DensityMapModifier:new(terrainDetailHeightId, self.mission.terrainDetailHeightTypeFirstChannel, self.mission.terrainDetailHeightTypeNumChannels)
    modifiers.fillType.filterHeight = DensityMapFilter:new(terrainDetailHeightId, getDensityMapHeightFirstChannel(terrainDetailHeightId), getDensityMapHeightNumChannels(terrainDetailHeightId))
    modifiers.fillType.filterHeight:setValueCompareParams("equals", 0) -- No height anymore

    modifiers.dryingMap = {}
    modifiers.dryingMap.modifier = DensityMapModifier:new(self.dryingMap, 0, 1)
    modifiers.dryingMap.filter = DensityMapFilter:new(modifiers.dryingMap.modifier)

    modifiers.delayMap = {}
    modifiers.delayMap.modifier = DensityMapModifier:new(self.dryingMap, 1, 1)
    modifiers.delayMap.filter = DensityMapFilter:new(modifiers.delayMap.modifier)
    modifiers.delayMap.filter:setValueCompareParams("equals", 0)

    self.grassHeightType = self.densityMapHeightManager:getDensityMapHeightTypeByFillTypeIndex(FillType.GRASS_WINDROW)
    self.strawHeightType = self.densityMapHeightManager:getDensityMapHeightTypeByFillTypeIndex(FillType.STRAW)
    self.hayHeightType = self.densityMapHeightManager:getDensityMapHeightTypeByFillTypeIndex(FillType.DRYGRASS_WINDROW)

    self.modifiers = modifiers
end

function SeasonsGrass:loadFromSavegame(xmlFile)
end

function SeasonsGrass:saveToSavegame(xmlFile)
    if self.dryingMap ~= 0 then
        saveBitVectorMapToFile(self.dryingMap, self.mission.missionInfo.savegameDirectory .. "/seasons_grassMap.grle")
    end
end

----------------------
-- Multi-step drying
----------------------

---Load the drying info map
function SeasonsGrass:loadDryingMap()
    self.dryingMap = createBitVectorMap("DryingMap")
    local success = false

    if self.mission.missionInfo.isValid then
        local path = self.mission.missionInfo.savegameDirectory .. "/seasons_grassMap.grle"

        -- The old path is different and thus won't be loaded here.
        if fileExists(path) then
            success = loadBitVectorMapFromFile(self.dryingMap, path, SeasonsGrass.MAP_NUM_CHANNELS)
        end
    end

    if not success then
        local size = getDensityMapSize(self.mission.terrainDetailHeightId)
        loadBitVectorMapNew(self.dryingMap, size, size, SeasonsGrass.MAP_NUM_CHANNELS, false)
    end
end

function SeasonsGrass:onMapLoaded()
    -- Load height types before the height map system gets initialized
    self:loadHeightTypes()
end

---Load new height types
function SeasonsGrass:loadHeightTypes()
    local hudOverlayFilename = "resources/gui/hud/fillTypes/hud_fill_semidry_grass_windrow.png" -- unused but required
    local hudOverlayFilenameSmall = "resources/gui/hud/fillTypes/hud_fill_semidry_grass_windrow_sml.png"
    self.semiDryFillType = self.fillTypeManager:addFillType("SEMIDRY_GRASS_WINDROW", "SEMIDRY_GRASS_WINDROW", false, 0, 0.00016, 50, hudOverlayFilename, hudOverlayFilenameSmall, self.modDirectory, nil, { 1, 1, 1 }, nil, false)

    -- Create a fruit type to allow for conversion in foragers
    self.semiDryFruitType = self.fruitTypeManager:addFruitType("SEMIDRY_GRASS_WINDROW", false, false, 0, false)

    -- Add windrow properties so foragers can pick it up
    self.semiDryFruitType.hasWindrow = true
    self.semiDryFruitType.windrowName = "SEMIDRY_GRASS_WINDROW"
    self.semiDryFruitType.windrowLiterPerSqm = 4.37
    self.semiDryFruitType.literPerSqm = 4.37 -- windrowLitersPerSqm is not properly used
    self.fruitTypeManager.windrowFillTypes[FillType.SEMIDRY_GRASS_WINDROW] = true
    self.fruitTypeManager.fruitTypeIndexToWindrowFillTypeIndex[self.semiDryFruitType.index] = FillType.SEMIDRY_GRASS_WINDROW
    self.fruitTypeManager.fillTypeIndexToFruitTypeIndex[FillType.SEMIDRY_GRASS_WINDROW] = self.semiDryFruitType.index

    -- Manually insert it, there is no function for this without using XML
    table.insert(self.fruitTypeManager.fruitTypes, self.semiDryFruitType)
    self.fruitTypeManager.nameToFruitType[self.semiDryFruitType.name] = self.semiDryFruitType
    self.fruitTypeManager.nameToIndex[self.semiDryFruitType.name] = self.semiDryFruitType.index
    self.fruitTypeManager.indexToFruitType[self.semiDryFruitType.index] = self.semiDryFruitType

    self.fruitTypeManager.fillTypeIndexToFruitTypeIndex[FillType.SEMIDRY_GRASS_WINDROW] = self.semiDryFruitType.index
    self.fruitTypeManager.fruitTypeIndexToFillType[self.semiDryFruitType.index] = self.semiDryFruitType.fillType

    -- Semidry always gets converted to wet
    self.fruitTypeManager:addFruitTypeConversion(self.fruitTypeManager.converterNameToIndex["FORAGEHARVESTER"], self.semiDryFruitType.index, FillType.GRASS_WINDROW, 1, 1)

    -- Add so it is recognized by foragers
    self.fruitTypeManager:addFruitTypeToCategory(self.semiDryFruitType.index, self.fruitTypeManager.categories["PICKUP"])

    -- Use Hay textures as SemiDry, and we add new textures for hay
    local diffuseMapFilename = Utils.getFilename("$data/fillPlanes/hay_diffuse.png")
    local normalMapFilename = Utils.getFilename("$data/fillPlanes/hay_normal.png")
    local distanceMapFilename = Utils.getFilename("$data/fillPlanes/distance/hayDistance_diffuse.png")
    self.semiDryHeightType = self.densityMapHeightManager:addDensityMapHeightType("SEMIDRY_GRASS_WINDROW", math.rad(35), 0.35, 0.10, 0.10, 1.20, 6.5, false, diffuseMapFilename, normalMapFilename, distanceMapFilename, false)
    if self.semiDryHeightType == nil then
        Logging.error("Could not create the semidry grass windrow height type. The combination of map and mods are not compatible")
        return
    end

    -- Whenever a unit tips SEMIDRY, drop GRASS
    self.fruitTypeManager.fillTypeIndexToFruitTypeIndex[FillType.SEMIDRY_GRASS_WINDROW] = FillType.GRASS_WINDROW

    local materialHolderFilename = Utils.getFilename("resources/fillTypes/semiDry_grass_windrow/materialHolder.i3d", self.modDirectory)
    self.materialHolder = loadI3DFile(materialHolderFilename, false, true, false)
    local materialHolderFilename = Utils.getFilename("resources/fillTypes/semiDry_grass_windrow/particle_materialHolder.i3d", self.modDirectory)
    self.particleMaterialHolder = loadI3DFile(materialHolderFilename, false, true, false)

    -- Overwrite Hay textres
    local hayHeightType = self.densityMapHeightManager.fillTypeIndexToHeightType[FillType.DRYGRASS_WINDROW]
    hayHeightType.diffuseMapFilename = Utils.getFilename("resources/fillTypes/hay/diffuse.png", self.modDirectory)
    hayHeightType.distanceMapFilename = Utils.getFilename("resources/fillTypes/hay/distance_diffuse.png", self.modDirectory)
    -- Hay material holder is loaded after the basegame is loaded

    -- Overwrite bale type for hay
    for _, baleType in ipairs(self.baleTypeManager.roundBales) do
        baleType.filename = self:hayGetSeasonsBale(baleType.filename)
    end
    for _, baleType in ipairs(self.baleTypeManager.squareBales) do
        baleType.filename = self:hayGetSeasonsBale(baleType.filename)
    end

    -- The HUD cached a list of filltypes. We added a new one so need to refresh that list to prevent errors
    self.mission.hud.fillLevelsDisplay:refreshFillTypes(self.fillTypeManager)
end

---Set given value on the drying map.
function SeasonsGrass:setDryingValue(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, value)
    local modifier = self.modifiers.dryingMap.modifier

    self.mask:setParallelogramUVCoords(modifier, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    modifier:executeSet(value)
end

---Set the 3 hour delay on the grass
function SeasonsGrass:setGrassDelayBit(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local modifier = self.modifiers.delayMap.modifier

    self.mask:setParallelogramUVCoords(modifier, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    modifier:executeSet(1)
end

----------------------
-- Bales
----------------------

---Get the duration of a whole fermentation process
function SeasonsGrass:getFermentationDuration()
    return self.environment.daysPerSeason / 3 * 24 * 60 * 60 * 1000 -- 4 weeks
end

---Get the percentage the bale should be kept after rotting
function SeasonsGrass:getBaleReduction(bale, fillType, age)
    local reductionFactor = 1
    local daysPerSeason = self.environment.daysPerSeason

    if fillType == FillType.STRAW or fillType == FillType.DRYGRASS_WINDROW then
        reductionFactor = math.min(0.965 + math.sqrt(daysPerSeason / 30000), 0.99)
    elseif fillType == FillType.GRASS_WINDROW then
        local dayReductionFactor = 1 - ( (2 * age / daysPerSeason + 1 ) ^ 10) / 100
        -- no rotting of grass bales the first day (before the first midnight)
        if age == 0 then
            dayReductionFactor = 1
        end
        reductionFactor = math.max(1 - (1 - dayReductionFactor) / 24, 0.975)
    end

    return reductionFactor
end

---Get whether the bale is outside in the rain (using mask)
function SeasonsGrass:getIsBaleOutside(bale)
    local x0 = bale.sendPosX - (SeasonsGrass.BALE_MASK_RECT_SIZE / 2)
    local z0 = bale.sendPosZ - (SeasonsGrass.BALE_MASK_RECT_SIZE / 2)
    local x1 = x0 + SeasonsGrass.BALE_MASK_RECT_SIZE
    local z1 = z0
    local x2 = x0
    local z2 = z0 + SeasonsGrass.BALE_MASK_RECT_SIZE

    local density = self.mask:getDensityAt(x0, z0, x1, z1, x2, z2)

    return density == 0
end

function SeasonsGrass:rotBales()
    for item, _ in pairs(self.mission.itemsToSave) do
        if item:isa(Bale) then
            local bale = item

            -- Wrapped bales do not rot
            if bale.wrappingState ~= 1 then
                local fillType = bale:getFillType()
                local isGrassBale = fillType == FillType.GRASS_WINDROW
                local rotsInRain = (fillType == FillType.DRYGRASS_WINDROW or fillType == FillType.STRAW)
                local hadRain = self.mission.environment.weather:getTimeSinceLastRain() < 60

                -- Always rot grass, and only rot straw+hay when it has been outside in the rain
                if isGrassBale or (rotsInRain and hadRain and self.mask:hasPaintedMask() and self:getIsBaleOutside(bale)) then
                    -- Always rot unwrapped grass bales
                    bale.rotVolume = (bale.rotVolume or 0) + bale:getFillLevel() * (1 - self:getBaleReduction(bale, fillType, bale.age or 0))
                    bale:setFillLevel(bale:getFillLevel() * self:getBaleReduction(bale, fillType, bale.age or 0))

                    SeasonsBaleRotEvent:sendEvent(bale)
                end
            end

        end
    end
end

---Update bale age and remove empty bales
function SeasonsGrass:updateBaleAgeAndRemoval()
    for item, _ in pairs(self.mission.itemsToSave) do
        if item:isa(Bale) then
            local bale = item

            bale.age = Utils.getNoNil(bale.age, 0) + 1

            local fillType = bale:getFillType()
            if fillType == FillType.STRAW or fillType == FillType.DRYGRASS_WINDROW then
                local volume = math.huge

                -- When fillLevel is less than volume (i.e. uncompressed) the bale will be deleted
                if bale.baleDiameter ~= nil then
                    volume = math.pi * (bale.baleDiameter / 2 ) ^ 2 * bale.baleWidth * 1000
                else
                    volume = bale.baleWidth * bale.baleLength * bale.baleHeight * 1000
                end

                -- TODO What cases exist where this is run before the values are set? Where do we need to inject to do so?
                if (bale.initVolume or 4000) - volume < (bale.rotVolume or 0) or bale:getFillLevel() < (bale.rotVolume or 0) then
                    bale:delete()
                end
            elseif fillType == FillType.GRASS_WINDROW and bale.wrappingState ~= 1 then
                -- Unwrapped grass bales are deleted after 2 days
                if bale.age > 2 then
                    bale:delete()
                end
            end
        end
    end
end

function SeasonsGrass:hayGetSeasonsBale(i3dFilename)
    return self.basegameToSeasonsHayBales[i3dFilename] or i3dFilename
end

function SeasonsGrass:hayGetBasegameBale(i3dFilename)
    return self.seasonsToBasegameHayBales[i3dFilename] or i3dFilename
end

---Update the fermentation state of all fermenting bales
function SeasonsGrass:updateBaleFermentation(deltaTime)
    local bales = self.mission.limitedObjects[FSBaseMission.LIMITED_OBJECT_TYPE_BALE].objects
    local timeScale = self.mission.missionInfo.timeScale

    for i = 1, #bales do
        local bale = bales[i]

        if bale:getIsFermenting() then
            bale.fermentingProcess = bale.fermentingProcess + (deltaTime / self:getFermentationDuration())

            if bale.fermentingProcess >= 1 then
                -- Finish fermenting process
                bale:setFillType(FillType.SILAGE)
                bale.fermentingProcess = nil

                SeasonsBaleFermentEvent:sendEvent(bale)
            end
        end
    end
end

----------------------
-- Events
----------------------

function SeasonsGrass:onDayChanged()
    if self.isServer then
        self.densityMapScanner:queueJob("DryingMidnight")

        self:updateBaleAgeAndRemoval()
    end
end

function SeasonsGrass:onHourChanged()
    if self.isServer then
        if self.mission.environment.weather:getTimeSinceLastRain() < 60 then
            self.densityMapScanner:queueJob("ReduceStraw", 1)
        end

        if self.mission.environment.currentHour % 6 == 0 then
            local factor = self.weather:getRotDryFactor()
            local cropMoisture = self.weather.cropMoistureContent
            self.densityMapScanner:queueJob("DryingInterval", {factor, factor})

            if (cropMoisture < 20 and factor < SeasonsGrass.DRYING_THRESHOLD) or factor > SeasonsGrass.RAIN_THRESHOLD then
                if factor < SeasonsGrass.DRYING_THRESHOLD then
                    Logging.info("Drying conditions met")
                else
                    Logging.info("Rotting conditions met")
                end
                self.weather:resetRotDryFactor()
            end
        elseif self.mission.environment.currentHour % 3 == 0 then -- Already handled in the drying interval for every 6th hour
            -- self.densityMapScanner:queueJob("DryingDelay")
        end

        self:rotBales()
    end
end

--Server only
function SeasonsGrass:minuteChanged(minute)
    if minute % 15 == 0 then
        self:updateBaleFermentation(15 * 60 * 1000)
    end
end

----------------------
-- Scan functions
----------------------

---Reduce straw height (used after rain)
function SeasonsGrass:dms_reduceStraw(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, parameters)
    local layers = parameters[1]

    local modifiers = self.modifiers.height
    local modifier = modifiers.modifierHeight
    local filter = modifiers.filterType

    local maskFilter = self.mask:getFilter(0)

    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    filter:setValueCompareParams("equals", self.strawHeightType.index)

    local _, _, total = modifier:executeAdd(-layers, filter, maskFilter)
    if total ~= 0 then
        local modifiers = self.modifiers.fillType
        local modifier = modifiers.modifierType
        local filter = modifiers.filterHeight

        modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
        modifier:executeSet(0, filter) -- Reset fillype
    end
end

function SeasonsGrass:dms_foldJob(newJob, queue)
    local folded = false

    queue:iteratePopOrder(function (job)
        if job.callbackId == newJob.callbackId then
            job.parameters[1] = job.parameters[1] + newJob.parameters[1]

            folded = true
            return true -- break
        end
    end)

    return folded
end

---Drying step at midnight: resets the drying map and rots grass
function SeasonsGrass:dms_dryingMidnight(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, parameters)
    local modifier = self.modifiers.height.modifierHeight
    local filterType = self.modifiers.height.filterType
    local filterMask = self.modifiers.dryingMap.filter

    -- Where drying mask is 0, rot the grass
    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    filterMask:setValueCompareParams("equals", 0)
    filterType:setValueCompareParams("equals", self.grassHeightType.index)
    local _, _, total = modifier:executeAdd(-1, filterMask, filterType)

    -- Where height is 0, reset type
    if total ~= 0 then
        local typeModifier = self.modifiers.fillType.modifierType
        local heightFilter = self.modifiers.fillType.filterHeight

        typeModifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
        typeModifier:executeSet(0, heightFilter)
    end

    -- Where drying mask is 1, switch to 0
    modifier = self.modifiers.dryingMap.modifier
    self.mask:setParallelogramUVCoords(modifier, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    filterType:setValueCompareParams("equals", self.grassHeightType.index)
    modifier:executeSet(0) -- no need to filter on value, as 0->0 and 1->0 is fine.
end

---Drying step at an interval.
function SeasonsGrass:dms_dryingInterval(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, parameters)
    local dryingFactor = parameters[1]
    local rainFactor = parameters[2]

    local modifier = self.modifiers.fillType.modifierType
    local filter = self.modifiers.height.filterType
    local filterDelay = self.modifiers.delayMap.filter

    -- When it is drying, turn semi into dry
    if dryingFactor < SeasonsGrass.DRYING_THRESHOLD then
        modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
        filter:setValueCompareParams("equals", self.semiDryHeightType.index)

        modifier:executeSet(self.hayHeightType.index, filter, filterDelay)

    -- When it is raining, turn semi into grass
    elseif rainFactor > SeasonsGrass.RAIN_THRESHOLD then
        modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")

        filter:setValueCompareParams("equals", self.semiDryHeightType.index)
        modifier:executeSet(self.grassHeightType.index, filter, filterDelay)

        -- And rot hay
        local modifier = self.modifiers.height.modifierHeight
        local filterType = self.modifiers.height.filterType
        modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
        filterType:setValueCompareParams("equals", self.hayHeightType.index)
        local _, _, total = modifier:executeAdd(-1, filterDelay, filterType)

        -- Reset type
        if total ~= 0 then
            local typeModifier = self.modifiers.fillType.modifierType
            local heightFilter = self.modifiers.fillType.filterHeight

            typeModifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
            typeModifier:executeSet(0, heightFilter)
        end
    end

    -- Also update the delaymap
    self:dms_dryingDelay(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
end

---Decrement the delay counter
function SeasonsGrass:dms_dryingDelay(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, parameters)
    local modifier = self.modifiers.delayMap.modifier

    self.mask:setParallelogramUVCoords(modifier, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    modifier:executeSet(0)
end

---Running this multiple times is rather useless as its value only changes by a vehicle
function SeasonsGrass:dms_dryingDelay_foldJob(newJob, queue)
    local folded = false

    queue:iteratePopOrder(function (job)
        if job.callbackId == newJob.callbackId then
            folded = true
            return true -- break
        end
    end)

    return folded
end

----------------------
-- Injections
----------------------

-- Bunker silo fermentation
----------------------

---Adjust fermenting duration based on season length
function SeasonsGrass.inj_bunkerSilo_load(bunkerSilo, superFunc, ...)
    superFunc(bunkerSilo, ...)

    bunkerSilo.fermentingDuration = g_seasons.grass:getFermentationDuration()

    g_messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, bunkerSilo.onSeasonLengthChanged, bunkerSilo)

    return true
end

---Delete the listener to season length changes to prevent nils.
function SeasonsGrass.inj_bunkerSilo_delete(bunkerSilo, ...)
    g_messageCenter:unsubscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, bunkerSilo)
end

---Update the fermenting duration when the season length changes
function SeasonsGrass.inj_bunkerSilo_onSeasonLengthChanged(bunkerSilo, ...)
    bunkerSilo.fermentingDuration = g_seasons.grass:getFermentationDuration()
end

-- Bale fermentation
----------------------

---Load age and fermenting information from bale
function SeasonsGrass.inj_bale_loadFromXMLFile(bale, superFunc, xmlFile, key, resetVehicles)
    local success = false

    local oldFunc = NetworkUtil.convertFromNetworkFilename
    NetworkUtil.convertFromNetworkFilename = function(filename)
        return oldFunc(g_seasons.grass:hayGetSeasonsBale(filename))
    end

    if superFunc(bale, xmlFile, key, resetVehicles) then
        bale.age = Utils.getNoNil(getXMLInt(xmlFile, key .. "#age"), 0)
        bale.rotVolume = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#rotVolume"), 0)
        bale.initVolume = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#initVolume"), 4000)
        bale.fermentingProcess = getXMLFloat(xmlFile, key .. "#fermentingProcess")
        local fermentingFillTypeName = Utils.getNoNil(getXMLString(xmlFile, key .. "#fermentingFillType"), "GRASS_WINDROW")

        if bale.fermentingProcess ~= nil then
            bale:setFillType(g_fillTypeManager:getFillTypeIndexByName(fermentingFillTypeName))
        end

        success = true
    end

    NetworkUtil.convertFromNetworkFilename = oldFunc

    return success
end

function SeasonsGrass.inj_bale_load(bale, i3dFilename, x,y,z, rx,ry,rz, fillLevel)
    bale.initVolume = fillLevel
    bale.rotVolume = 0
end

---Save age and fermenting information for bale
function SeasonsGrass.inj_bale_saveToXMLFile(bale, xmlFile, key)
    setXMLInt(xmlFile, key .. "#age", bale.age or 0)
    setXMLFloat(xmlFile, key .. "#rotVolume", bale.rotVolume or 0)
    setXMLFloat(xmlFile, key .. "#initVolume", bale.initVolume or 4000)

    if bale.fermentingProcess ~= nil then
        setXMLFloat(xmlFile, key .. "#fermentingProcess", bale.fermentingProcess)

        local name = g_fillTypeManager:getFillTypeNameByIndex(bale:getFillType())
        setXMLString(xmlFile, key .. "#fermentingFillType", name)
    end
end

---Update the fill type with a mass update
function SeasonsGrass.inj_bale_setFillType(bale, fillType)
    bale.fillType = fillType

    -- Update fill level to force a mass update
    bale:setFillLevel(bale:getFillLevel())
end

---Write filltype (normally defined by the i3d of the bale)
function SeasonsGrass.inj_bale_writeStream(bale, streamId, connection)
    streamWriteUIntN(streamId, bale.fillType, FillTypeManager.SEND_NUM_BITS)
end

---Read filltype (normally defined by the i3d of the bale)
function SeasonsGrass.inj_bale_readStream(bale, streamId, connection)
    bale.fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
end

---Get whether the bale is fermenting
function SeasonsGrass.inj_bale_getIsFermenting(bale)
    return bale.fermentingProcess ~= nil and bale:getFillType() ~= FillType.DRYGRASS_WINDROW and bale:getFillType() ~= FillType.STRAW
end

-- Bale fermentation: wrapper
-----------------------------

function SeasonsGrass.inj_baleWrapper_pickupWrapperBale(vehicle, bale, baleType)
    local spec = vehicle.spec_baleWrapper

    spec.baleFillTypeSource = bale:getFillType()
end

function SeasonsGrass.inj_baleWrapper_doStateChange(vehicle, id, nearestBaleServerId)
    local spec = vehicle.spec_baleWrapper

    if vehicle.isServer then
        if id == BaleWrapper.CHANGE_WRAPPER_BALE_DROPPED and spec.lastDroppedBale ~= nil then
            local bale = spec.lastDroppedBale

            if bale:getFillType() == FillType.SILAGE and bale.wrappingState >= 0.999 then
                bale:setFillType(Utils.getNoNil(spec.baleFillTypeSource, FillType.GRASS_WINDROW))
                bale.fermentingProcess = 0
                bale.wrappingState = 1 -- normalize

                SeasonsBaleFermentEvent:sendEvent(bale)
            end

            spec.baleFillTypeSource = nil
        end
    end
end

function SeasonsGrass.inj_baleWrapper_onPostLoad(vehicle, savegame)
    local spec = vehicle.spec_baleWrapper

    if savegame ~= nil and not savegame.resetVehicles then
        local baleFillTypeSourceName = getXMLString(savegame.xmlFile, savegame.key .. ".baleWrapper#baleFillTypeSource")

        if baleFillTypeSourceName ~= nil then
            spec.baleFillTypeSource = g_fillTypeManager:getFillTypeIndexByName(baleFillTypeSourceName)
        end
    end
end

function SeasonsGrass.inj_baleWrapper_saveToXMLFile(vehicle, xmlFile, key, usedModNames)
    local spec = vehicle.spec_baleWrapper

    if spec.baleFillTypeSource ~= nil then
        setXMLString(xmlFile, key .. "#baleFillTypeSource", g_fillTypeManager:getFillTypeNameByIndex(spec.baleFillTypeSource))
    end
end

-- Bale fermentation: missions
------------------------------

---A wrapped-bale mission expects silage from a bale. When fill is being sold to such mission
-- we will also call with silage as type so it works even for grass bales. Otherwise the player
-- needs to wait for bales to ferment.
function SeasonsGrass.inj_sellingStation_addFillLevelFromTool(station, superFunc, farmId, deltaFillLevel, fillType, fillInfo, toolType)
    local moved = 0

    if deltaFillLevel > 0 and station:getIsFillTypeAllowed(fillType) and station:getIsToolTypeAllowed(toolType) then
        -- Look for wrapped grass bales that are fermenting
        if toolType == ToolType.BALE and fillType == FillType.GRASS_WINDROW and fillInfo == 1 then
            -- See if it is for a mission
            for _, mission in pairs(station.missions) do
                if mission.fillSold ~= nil and mission.fillType == FillType.SILAGE and mission.farmId == farmId then
                    -- Act as if silage was delivered
                    moved = superFunc(station, farmId, deltaFillLevel, FillType.SILAGE, fillInfo, toolType)

                    break -- supercall will handle it for any other mission too
                end
            end
        end

        -- If there was no delivery for silage mission, handle normally
        if moved == 0 then
            moved = superFunc(station, farmId, deltaFillLevel, fillType, fillInfo, toolType)
        end
    end

    return moved
end

-- Bale fermentation: optimizations
-----------------------------------

---Track any loaded bales (console already does)
function SeasonsGrass.inj_fsBaseMission_addLimitedObject(mission, objectType, object)
    if not GS_IS_CONSOLE_VERSION then
        table.insert(mission.limitedObjects[objectType].objects, object);
    end
end

---Remove tracking on unloaded bales (console already does)
function SeasonsGrass.inj_fsBaseMission_removeLimitedObject(mission, objectType, object)
    if not GS_IS_CONSOLE_VERSION then
        local objects = mission.limitedObjects[objectType].objects
        for i = 1, #objects do
            if objects[i] == object then
                table.remove(objects, i)
                break
            end
        end
    end
end

-- Bale fermentation and handling: Anderson
-------------------------------------------

---Turn a bale into grass when added to the tube
function SeasonsGrass.inj_inlineBale_replacePendingBale(inlineBale, superFunc, bale)
    local pendingBale = inlineBale.pendingBale

    if superFunc(inlineBale, bale) then
        bale:setFillType(Utils.getNoNil(pendingBale:getFillType(), FillType.GRASS_WINDROW))
        bale.fermentingProcess = 0

        return true
    end

    return false
end

---Change bale object into the one for grass for unfermented bales
function SeasonsGrass.inj_inlineBale_openBale(inlineBale, superFunc, bale, isFirst, replaceBale)
    local old = inlineBale.unwrappedFilename

    if bale:getFillType() == FillType.GRASS_WINDROW then
        local isRound = bale.baleDiameter ~= nil and bale.baleWidth ~= nil

        if isRound then
            local baleType = g_baleTypeManager:getBale(FillType.GRASS_WINDROW, true, 1.12, nil, nil, 1.3)
            inlineBale.unwrappedFilename = baleType.filename
        else
            -- Square bales in line are smaller than normal bales so above code would not work
            -- instead we look up the small bales in the DLC
            inlineBale.unwrappedFilename = g_modNameToDirectory["pdlc_andersonPack"] .. "objects/squarebales/baleSilageWrapped240.i3d"
        end
    end

    superFunc(inlineBale, bale, isFirst, replaceBale)

    inlineBale.unwrappedFilename = old
end

-- Hay bales need to look like hay bales
----------------------------------------

---Overwrite the hay bale I3D with one that has a different hay texture
function SeasonsGrass.inj_bale_createNode(bale, superFunc, i3dFilename)
    return superFunc(bale, g_seasons.grass:hayGetSeasonsBale(i3dFilename))
end

---Overwrite hay material holder. This is loaded from additional files and we need
-- to do it after otherwise we are overwritten
function SeasonsGrass.inj_mission00_loadAdditionalFiles(mission, xmlFile)
    g_deferredLoadingManager:addSubtask(function()
        -- Disable warnings: we know what we are doing
        local oldWarnings = g_showDevelopmentWarnings
        g_showDevelopmentWarnings = false

        local materialHolderFilename = Utils.getFilename("resources/fillTypes/hay/materialHolder.i3d", g_seasons.modDirectory)
        g_seasons.grass.hayMaterialHolder = loadI3DFile(materialHolderFilename, false, true, false)

        g_showDevelopmentWarnings = oldWarnings
    end)
end

----------------------
-- Debugging
----------------------

function SeasonsGrass:visualize()
    local mapSize = getBitVectorMapSize(self.dryingMap)
    local terrainSize = self.mission.terrainSize

    local worldToDensityMap = mapSize / terrainSize
    local densityToWorldMap = terrainSize / mapSize

    if self.dryingMap ~= 0 then
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
                local drying = getBitVectorMapPoint(self.dryingMap, xi, zi, 0, 1)
                local delay = getBitVectorMapPoint(self.dryingMap, xi, zi, 1, 1)

                local r,g,b = 1, drying, delay

                local x = (xi * densityToWorldMap) - terrainHalfSize
                local z = (zi * densityToWorldMap) - terrainHalfSize
                local y = getTerrainHeightAtWorldPos(self.mission.terrainRootNode, x,0,z) + 0.05

                local text = string.format("%d,%d", drying,delay)
                Utils.renderTextAtWorldPosition(x, y, z, text, getCorrectTextSize(0.01), 0, {r, g, b, 1})
            end
        end
    end
end
