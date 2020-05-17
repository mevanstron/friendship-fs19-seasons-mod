----------------------------------------------------------------------------------------------------
-- SeasonsSnowHandler
----------------------------------------------------------------------------------------------------
-- Purpose:  Handles snow placement and removal
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsSnowHandler = {}

local SeasonsSnowHandler_mt = Class(SeasonsSnowHandler)

SeasonsSnowHandler.MODE = {
    OFF = 1,
    ONE_LAYER = 2,
    ON = 3,
}

SeasonsSnowHandler.LAYER_HEIGHT = 0.06 -- in meters
SeasonsSnowHandler.MAX_HEIGHT = 0.48 -- in meters

function SeasonsSnowHandler:new(mission, densityMapScanner, modDirectory, i18n, densityMapHeightManager, fillTypeManager, mask, messageCenter, particleSystemManager)
    local self = setmetatable({}, SeasonsSnowHandler_mt)

    self.mission = mission
    self.densityMapScanner = densityMapScanner
    self.i18n = i18n
    self.densityMapHeightManager = densityMapHeightManager
    self.fillTypeManager = fillTypeManager
    self.modDirectory = modDirectory
    self.isServer = mission:getIsServer()
    self.mask = mask
    self.messageCenter = messageCenter
    self.particleSystemManager = particleSystemManager

    self.height = 0
    self.mode = SeasonsSnowHandler.MODE.ON --SeasonsSnowHandler.MODE.ONE_LAYER -- switch to ON if mask is found

    self.isDoingTerrainModifications = false --true when the DMS is running. Useful for skipping mission tests

    SeasonsModUtil.appendedFunction(Player, "updateTick", self.inj_player_updateTick)

    if g_addCheatCommands then
        addConsoleCommand("rmAddSnow", "Add snow", "consoleCommandAddSnow", self)
        addConsoleCommand("rmSetSnow", "Set snow", "consoleCommandSetSnow", self)
        addConsoleCommand("rmResetSnow", "Reset snow", "consoleCommandResetSnow", self)
        addConsoleCommand("rmSalt", "Salt around player", "consoleCommandSalt", self)
    end

    return self
end

function SeasonsSnowHandler:delete()
    self.densityMapScanner:unregisterCallback("AddSnow")
    self.densityMapScanner:unregisterCallback("RemoveSnow")

    self:unloadSnowTypes()
    self:unloadSaltTypes()

    if g_addCheatCommands then
        removeConsoleCommand("rmAddSnow")
        removeConsoleCommand("rmSetSnow")
        removeConsoleCommand("rmResetSnow")
        removeConsoleCommand("rmSalt")
    end
end

function SeasonsSnowHandler:onMapLoaded()
    -- Load snow types before the height map system gets initialized
    self:loadSnowTypes()
    self:loadSaltTypes()

    -- The HUD cached a list of filltypes. We added a new one so need to refresh that list to prevent errors
    self.mission.hud.fillLevelsDisplay:refreshFillTypes(self.fillTypeManager)
end

function SeasonsSnowHandler:load()
    self.densityMapScanner:registerCallback("AddSnow", self.dms_addSnow, self, self.dms_removeSnowUnderObjects, true, self.dms_foldJob)
    self.densityMapScanner:registerCallback("RemoveSnow", self.dms_removeSnow, self, self.onHeightChanged, true, self.dms_foldJob)
    self.densityMapScanner:registerCallback("RemoveSwaths", self.dms_removeSwaths, self, nil, true)
end

function SeasonsSnowHandler:loadSnowTypes()
    local hudOverlayFilename = "resources/gui/hud/fillTypes/hud_fill_snow.png"
    local hudOverlayFilenameSmall = "resources/gui/hud/fillTypes/hud_fill_snow_sml.png"
    local fillType = self.fillTypeManager:addFillType("SNOW", self.i18n:getText("fillType_snow"), false, 0, 0.00016, 38, hudOverlayFilename, hudOverlayFilenameSmall, self.modDirectory, nil, { 1, 1, 1 }, nil, false)

    self.fillTypeManager:addFillTypeToCategory(fillType.index, self.fillTypeManager.nameToCategoryIndex["BULK"])

    local diffuseMapFilename = Utils.getFilename("resources/fillTypes/snow/snow_diffuse.png", self.modDirectory)
    local normalMapFilename = Utils.getFilename("resources/fillTypes/snow/snow_normal.png", self.modDirectory)
    local distanceMapFilename = Utils.getFilename("resources/fillTypes/snow/snowDistance_diffuse.png", self.modDirectory)

    self.snowHeightType = self.densityMapHeightManager:addDensityMapHeightType("SNOW", math.rad(38), 0.8, 0.10, 0.10, 1.20, 2, false, diffuseMapFilename, normalMapFilename, distanceMapFilename, false)
    if self.snowHeightType == nil then
        Logging.error("Could not create the snow height type. The combination of map and mods are not compatible")
        return
    end

    self.snowHeightType.soundMaterialId = 50

    -- New particle types
    self.particleSystemManager:addParticleType("snow")
    self.particleSystemManager:addParticleType("snow_smoke")
    self.particleSystemManager:addParticleType("snow_chunks")
    self.particleSystemManager:addParticleType("snow_big_chunks")

    local snowMaterialHolderFilename = Utils.getFilename("resources/fillTypes/snow/snowMaterialHolder.i3d", self.modDirectory)
    self.snowMaterialHolder = loadI3DFile(snowMaterialHolderFilename, false, true, false)

    local snowParticleMaterialHolderFileName = Utils.getFilename("resources/fillTypes/snow/snowParticleMaterialHolder.i3d", self.modDirectory)
    self.snowParticleMaterialHolder = loadI3DFile(snowParticleMaterialHolderFileName, false, true, false)
end

---Add a salt material for salting
function SeasonsSnowHandler:loadSaltTypes()
    local hudOverlayFilename = "resources/gui/hud/fillTypes/hud_fill_salt.png"
    local hudOverlayFilenameSmall = "resources/gui/hud/fillTypes/hud_fill_salt_sml.png"
    local price = 10
    local massPerLiter = 2.17 / 1000

    local fillType = self.fillTypeManager:addFillType("SALT", self.i18n:getText("fillType_salt"), false, price, massPerLiter, 32, hudOverlayFilename, hudOverlayFilenameSmall, self.modDirectory, nil, { 1, 1, 1 }, nil, false)

    self.fillTypeManager:addFillTypeToCategory(fillType.index, self.fillTypeManager.nameToCategoryIndex["BULK"])

    local diffuseMapFilename = Utils.getFilename("resources/fillTypes/salt/salt_diffuse.png", self.modDirectory)
    local normalMapFilename = Utils.getFilename("resources/fillTypes/salt/salt_normal.png", self.modDirectory)
    local distanceMapFilename = Utils.getFilename("resources/fillTypes/salt/saltDistance_diffuse.png", self.modDirectory)

    self.saltHeightType = self.densityMapHeightManager:addDensityMapHeightType("SALT", math.rad(32), 0.8, 0.10, 0.10, 0.9, 1, false, diffuseMapFilename, normalMapFilename, distanceMapFilename, false)
    if self.saltHeightType == nil then
        Logging.error("Could not create the salt height type. The combination of map and mods are not compatible")
        return
    end

    local saltMaterialHolderFilename = Utils.getFilename("resources/fillTypes/salt/saltMaterialHolder.i3d", self.modDirectory)
    self.saltMaterialHolder = loadI3DFile(saltMaterialHolderFilename, false, true, false)
end

function SeasonsSnowHandler:unloadSnowTypes()
    if self.snowMaterialHolder ~= nil then
        delete(self.snowMaterialHolder)
        self.snowMaterialHolder = nil
    end

    if self.snowParticleMaterialHolder ~= nil then
        delete(self.snowParticleMaterialHolder)
        self.snowParticleMaterialHolder = nil
    end
end

function SeasonsSnowHandler:unloadSaltTypes()
    if self.saltMaterialHolder ~= nil then
        delete(self.saltMaterialHolder)
        self.saltMaterialHolder = nil
    end
end

function SeasonsSnowHandler:onTerrainLoaded()
    if self.snowHeightType == nil then
        return
    end

    local terrainDetailHeightId = self.mission.terrainDetailHeightId

    local modifiers = {}

    -- Changing height
    modifiers.height = {}
    modifiers.height.modifierHeight = DensityMapModifier:new(terrainDetailHeightId, getDensityMapHeightFirstChannel(terrainDetailHeightId), getDensityMapHeightNumChannels(terrainDetailHeightId))
    modifiers.height.filterHeight = DensityMapFilter:new(modifiers.height.modifierHeight)
    modifiers.height.filterType = DensityMapFilter:new(terrainDetailHeightId, self.mission.terrainDetailHeightTypeFirstChannel, self.mission.terrainDetailHeightTypeNumChannels)

    -- Reading snow layers
    modifiers.height.filterSnowType = DensityMapFilter:new(terrainDetailHeightId, self.mission.terrainDetailHeightTypeFirstChannel, self.mission.terrainDetailHeightTypeNumChannels)
    modifiers.height.filterSnowType:setValueCompareParams("equal", self.snowHeightType.index)

    -- Changing type
    modifiers.fillType = {}
    modifiers.fillType.modifierType = DensityMapModifier:new(terrainDetailHeightId, self.mission.terrainDetailHeightTypeFirstChannel, self.mission.terrainDetailHeightTypeNumChannels)
    modifiers.fillType.filterHeight = DensityMapFilter:new(terrainDetailHeightId, getDensityMapHeightFirstChannel(terrainDetailHeightId), getDensityMapHeightNumChannels(terrainDetailHeightId))
    modifiers.fillType.filterType = DensityMapFilter:new(modifiers.fillType.modifierType)

    modifiers.sprayLevel = {}
    modifiers.sprayLevel.modifier = DensityMapModifier:new(self.mission.terrainDetailId, self.mission.sprayLevelFirstChannel, self.mission.sprayLevelNumChannels)

    self.modifiers = modifiers
end

function SeasonsSnowHandler:onGameLoaded()
    self.messageCenter:publish(SeasonsMessageType.SNOW_HEIGHT_CHANGED)
end

function SeasonsSnowHandler:loadFromSavegame(xmlFile)
    self.height = MathUtil.round(Utils.getNoNil(getXMLFloat(xmlFile, "seasons.environment.snow#height"), self.height), 2)
    self.mode = Utils.getNoNil(getXMLInt(xmlFile, "seasons.environment.snow#mode"), self.mode)

    self:onHeightChanged()
end

function SeasonsSnowHandler:saveToSavegame(xmlFile)
    setXMLFloat(xmlFile, "seasons.environment.snow#height", self.height)
    setXMLInt(xmlFile, "seasons.environment.snow#mode", self.mode)
end

function SeasonsSnowHandler:readStream(streamId, connection)
    self.mode = streamReadUIntN(streamId, 2)
end

function SeasonsSnowHandler:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.mode, 2)
end

---Set the achieved snow height. Will increase or decrease depending on current height
-- The set height will not necessarily be uniform over the map.
-- @param height number Requested height in meters
function SeasonsSnowHandler:setSnowHeight(height)
    if not self.isServer then
        return
    end

    local layerHeight = SeasonsSnowHandler.LAYER_HEIGHT

    -- Clamp the height depending on the mode
    height = MathUtil.clamp(height, -4.02, self:getMaxHeight())

    -- Reset in case of weird melting
    if self.height < 0 and height > 0 then
        self.height = 0
    -- prevent even weirder melting lead to adding snow
    elseif self.height < 0 and self.height < height then
        self.height = height
    end

    -- Only continue if the change is at least a layer we can put down. Otherwise, ignore it
    if math.abs(height - self.height) >= layerHeight then
        local deltaLayers = math.modf((height - self.height) / layerHeight)

        if deltaLayers > 0 then
            if self.height == 0 then
                -- Remove swaths before adding first layer of snow
                self.densityMapScanner:queueJob("RemoveSwaths", 100)
            end

            self.densityMapScanner:queueJob("AddSnow", deltaLayers)
        else
            self.densityMapScanner:queueJob("RemoveSnow", -deltaLayers)
        end

        self.height = self.height + deltaLayers * layerHeight
    end
end

---Remove all snow on the map
function SeasonsSnowHandler:removeAllSnow()
    self.densityMapScanner:queueJob("RemoveSnow", 100)
    self.height = 0
end

----------------------
-- Scan functions
----------------------

---Density map scanner function adding one or more layers of snow.
function SeasonsSnowHandler:dms_addSnow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, parameters)
    local layers = parameters[1]

    self.isDoingTerrainModifications = true

    -- First step: update the fill type on the ground
    local modifiers = self.modifiers.fillType
    local modifier = modifiers.modifierType
    local filter = modifiers.filterType

    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    filter:setValueCompareParams("equal", 0) -- nothing on ground yet

    -- With snow mask, only set snow type where masked and where nothing else lays
    -- Without the mask, set snow type everywhere nothing else lays
    if self.mask:hasMask() then
        modifier:executeSet(self.snowHeightType.index, filter, self.mask:getFilter(0))
    else
        modifier:executeSet(self.snowHeightType.index, filter)
    end

    -- Second step: update the height where the type is snow
    modifiers = self.modifiers.height
    modifier = modifiers.modifierHeight
    filter = modifiers.filterType

    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    filter:setValueCompareParams("equal", self.snowHeightType.index)
    modifier:executeAdd(layers, filter)
end

---Density map scanner function removing one or more layers of snow.
function SeasonsSnowHandler:dms_removeSnow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, parameters)
    local layers = parameters[1]

    self.isDoingTerrainModifications = true

    self:removeSnow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, layers)
end

function SeasonsSnowHandler:dms_removeSwaths(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local multiModifier = self.removeSwathsMultiModifier

    if multiModifier == nil then
        multiModifier = DensityMapMultiModifier:new()

        local modifiers = self.modifiers.height
        local modifier = modifiers.modifierHeight
        local filter = modifiers.filterType

        for _, fillType in ipairs({FillType.GRASS_WINDROW, FillType.DRYGRASS_WINDROW, FillType.STRAW, FillType.SEMIDRY_GRASS_WINDROW}) do
            local heightType = self.densityMapHeightManager:getDensityMapHeightTypeByFillTypeIndex(fillType)
            filter:setValueCompareParams("equals", heightType.index)

            multiModifier:addExecuteSet(0, modifier, filter, self.mask:getFilter(0))
        end

        self.removeSwathsMultiModifier = multiModifier
    end

    multiModifier:updateParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    multiModifier:execute(false)

    local modifiers = self.modifiers.fillType
    local modifier = modifiers.modifierType
    local filter = modifiers.filterHeight

    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    filter:setValueCompareParams("equals", 0) -- No height anymore
    modifier:executeSet(0, filter) -- Reset fillype
end

---Density map scanner finalizer removing snow under objects
function SeasonsSnowHandler:dms_removeSnowUnderObjects(parameters)
    for _, object in pairs(self.mission.itemsToSave) do
        if object.className == "Bale" then
            local width, length
            local bale = object.item

            if bale.baleDiameter ~= nil then
                width = bale.baleWidth
                length = bale.baleDiameter

                -- change dimension if bale is lying down
                if bale.sendRotX > 1.5 then
                    width = bale.baleDiameter
                end
            elseif bale.baleLength ~= nil then
                width = bale.baleWidth
                length = bale.baleLength
            end


            local scale = 0.65

            local x0 = bale.sendPosX + width * scale
            local x1 = bale.sendPosX - width * scale
            local x2 = bale.sendPosX + width * scale
            local z0 = bale.sendPosZ - length * scale
            local z1 = bale.sendPosZ - length * scale
            local z2 = bale.sendPosZ + length * scale

            self:dms_removeSnow(x0, z0, x1, z1, x2, z2, parameters)
        end
    end

    for _, vehicle in pairs(self.mission.vehicles) do
        if vehicle.spec_wheels ~= nil then
            for _, wheel in pairs(vehicle.spec_wheels.wheels) do

                local width = 0.5 * wheel.width
                local length = math.min(0.5, 0.5 * wheel.width)
                local x, _, z = localToLocal(wheel.driveNode, wheel.repr, 0, 0, 0)
                local x0, y0, z0 = localToWorld(wheel.repr, x + width, 0, z - length)
                local x1, y1, z1 = localToWorld(wheel.repr, x - width, 0, z - length)
                local x2, y2, z2 = localToWorld(wheel.repr, x + width, 0, z + length)

                self:dms_removeSnow(x0, z0, x1, z1, x2, z2, parameters)
            end
        end
    end

    self:onHeightChanged()
end

---Fold a new snow job into existing snow job in the dms queue
function SeasonsSnowHandler:dms_foldJob(newJob, queue)
    local folded = false

    local newDiff = newJob.parameters[1]
    if newJob.callbackId == "RemoveSnow" then
        newDiff = -newDiff
    end

    -- Find first snow command and adjust it
    queue:iteratePopOrder(function (job)
        local layers = 0

        if job.callbackId == "AddSnow" then
            layers = job.parameters[1]
        elseif job.callbackId == "RemoveSnow" then
            layers = -1 * job.parameters[1]
        end

        if layers ~= 0 then
            local newLayers = layers + newDiff

            if newLayers == 0 then
                queue:remove(job)
            elseif newLayers < 0 then
                job.parameters = {-newLayers}
                job.callbackId = "RemoveSnow"
            else
                job.parameters = {newLayers}
                job.callbackId = "AddSnow"
            end

            folded = true
            return true -- break
        end
    end)

    return folded
end

function SeasonsSnowHandler:onHeightChanged()
    self.isDoingTerrainModifications = false

    self.messageCenter:publish(SeasonsMessageType.SNOW_HEIGHT_CHANGED)
end

----------------------
-- Utilities
----------------------

---Salt given area
-- @return number Area that changed snow height
-- @return number Total area of the parallelogram
function SeasonsSnowHandler:saltArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local modifiers = self.modifiers.height
    local modifier = modifiers.modifierHeight
    local filter1 = modifiers.filterType
    local filter2 = modifiers.filterHeight

    -- If snow <=1 set 0
    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    filter1:setValueCompareParams("equal", self.snowHeightType.index)
    filter2:setValueCompareParams("equal", 1)
    local _, area, totalArea = modifier:executeSet(0, filter1, filter2)

    -- Reset spray level
    modifiers = self.modifiers.sprayLevel
    modifier = modifiers.modifier

    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    modifier:executeSet(0)

    return area, totalArea
end

---Remove some actual snow
function SeasonsSnowHandler:removeSnow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, layers)
    -- First step: decrease height
    local modifiers = self.modifiers.height
    local modifier = modifiers.modifierHeight
    local filter = modifiers.filterType

    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
    filter:setValueCompareParams("equal", self.snowHeightType.index)
    local density = modifier:executeAdd(-layers, filter)

    -- Second step: reset fill type when there is no height. Only if any snow was removed
    if density ~= 0 then
        modifiers = self.modifiers.fillType
        modifier = modifiers.modifierType
        filter = modifiers.filterHeight

        modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")
        filter:setValueCompareParams("equal", 0)
        modifier:executeSet(0, filter)
    end
end

----------------------
-- Getters and setters
----------------------

---Get the maximum snow height depending on the mode.
function SeasonsSnowHandler:getMaxHeight()
    if self.mode == SeasonsSnowHandler.MODE.ONE_LAYER then
        return SeasonsSnowHandler.LAYER_HEIGHT
    elseif self.mode == SeasonsSnowHandler.MODE.OFF then
        return 0
    end

    return SeasonsSnowHandler.MAX_HEIGHT
end

---Set snow mode
function SeasonsSnowHandler:setMode(mode)
    if mode ~= self.mode then
        local oldMode = self.mode

        self.mode = mode

        -- Reset snow
        if oldMode == SeasonsSnowHandler.MODE.ON then
            if mode == SeasonsSnowHandler.MODE.OFF then
                self:setSnowHeight(-100)
            else
                self:setSnowHeight(self.height)
            end
        end
    end
end

---Get snow mode
function SeasonsSnowHandler:getMode()
    return self.mode
end

---Get current snow height
function SeasonsSnowHandler:getHeight()
    return self.height
end

----------------------
-- Injections
----------------------

---Because snow is a sudden-appearing height, it can cause physics issues for players:
-- When snow appears its physical body is inside the body of the player, getting the player stuck
-- The only way to move again is to tab into a vehicle. This is not acceptable.
-- These issues can also appear when cutting open bales. So here we make sure the player is always above
-- a tip when it is too far down.
function SeasonsSnowHandler.inj_player_updateTick(player, dt)
    -- Prevent player from getting stuck in a high level of snow
    if player.isControlled then
        local px, py, pz = getTranslation(player.rootNode)
        local dy, delta = DensityMapHeightUtil.getCollisionHeightAtWorldPos(px, py, pz)

        local heightOffset =  0.5 * player.baseInformation.capsuleHeight -- for root node origin to terrain
        if py < dy + heightOffset - 0.1 then
            py = dy + heightOffset
            setTranslation(player.rootNode, px, py, pz)
        end
    end
end

----------------------
-- Commands
----------------------

function SeasonsSnowHandler:consoleCommandAddSnow(layers)
    if layers == nil or tonumber(layers) == nil then
        return "Usage: rmAddSnow layers"
    end

    local layers = tonumber(layers)

    self:setSnowHeight(self.height + layers * SeasonsSnowHandler.LAYER_HEIGHT)
end

function SeasonsSnowHandler:consoleCommandSetSnow(height)
    if height == nil or tonumber(height) == nil then
        return "Usage: rmSetSnow height"
    end

    local height = tonumber(height)

    self:setSnowHeight(height)
end

function SeasonsSnowHandler:consoleCommandResetSnow()
    self:removeAllSnow()
end

function SeasonsSnowHandler:consoleCommandSalt(radius)
    local radius = tonumber(radius) or 5

    local x, y, z = getWorldTranslation(getCamera(0))

    local startWorldX = x - radius
    local startWorldZ = z - radius
    local widthWorldX = x + radius
    local widthWorldZ = z - radius
    local heightWorldX = x - radius
    local heightWorldZ = z + radius

    self:saltArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
end
