----------------------------------------------------------------------------------------------------
-- SeasonsMask
----------------------------------------------------------------------------------------------------
-- Purpose:  Abstracting the Seasons mask
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsMask = {}

local SeasonsMask_mt = Class(SeasonsMask)

SeasonsMask.MASK_FIRST_CHANNEL = 0
SeasonsMask.MASK_NUM_CHANNELS = 1

function SeasonsMask:new(mission, modDirectory)
    local self = setmetatable({}, SeasonsMask_mt)

    self.mission = mission
    self.modDirectory = modDirectory
    self.isServer = mission:getIsServer()

    self.mask = 0

    self.visualizeMask = false

    self.customPlaceableMasks = {}

    SeasonsModUtil.appendedFunction(Placeable, "finalizePlacement", SeasonsMask.inj_placeable_finalizePlacement)
    SeasonsModUtil.appendedFunction(Placeable, "onSell", SeasonsMask.inj_placeable_onSell)
    SeasonsModUtil.overwrittenFunction(Placeable, "load", SeasonsMask.inj_placeable_load)

    return self
end

function SeasonsMask:delete()
    if self.mask ~= 0 then
        delete(self.mask)
    end

    removeConsoleCommand("rmReloadPlaceableMasks")
    removeConsoleCommand("rmShowMask")
end

function SeasonsMask:load()
    addConsoleCommand("rmReloadPlaceableMasks", "Reload placeables.xml with new masks", "consoleCommandReloadPlaceableMasks", self)
    addConsoleCommand("rmShowMask", "Show the snow mask", "consoleCommandToggleMask", self)
end

function SeasonsMask:onTerrainLoaded(mapFilename)
    self:loadMask(mapFilename)
    self:loadExtraPlaceableMasks()

    self.terrainSize = self.mission.terrainSize

    -- Changing the seasonsMask
    if self.mask ~= 0 then
        self.modifierValue = DensityMapModifier:new(self.mask, SeasonsMask.MASK_FIRST_CHANNEL, SeasonsMask.MASK_NUM_CHANNELS)
        self.filter = DensityMapFilter:new(self.mask, SeasonsMask.MASK_FIRST_CHANNEL, SeasonsMask.MASK_NUM_CHANNELS)
    end
end

-- Look for a seasons mask in the map and load it if available
function SeasonsMask:loadMask(mapFilename)
    local xmlFilename = Utils.getFilename(self.mission.missionInfo.mapXMLFilename, self.mission.baseDirectory)
    local xmlFile = loadXMLFile("mapXML", xmlFilename)
    if xmlFile ~= 0 then
        local relativePath = getXMLString(xmlFile, "map.seasons.mask#filename")
        if relativePath ~= nil then
            local path = Utils.getFilename(relativePath, self.mission.baseDirectory)
            self:loadMaskAtPath(path, false)
        elseif mapFilename == "data/maps/mapUS.i3d" then
            self:loadMaskAtPath(Utils.getFilename("resources/seasonsMasks/mapUS_seasonsMask.grle", self.modDirectory), false)
        elseif mapFilename == "data/maps/mapDE.i3d" then
            self:loadMaskAtPath(Utils.getFilename("resources/seasonsMasks/mapDE_seasonsMask.grle", self.modDirectory), false)
        else
            -- When no mask is found, fall back on the collision map so at least there is something.
            -- We load it ourselves in a separate object so we can write to it without interfering
            -- with the tipCol system. (Also, the tipCol system uses a map from the savegame)
            self:loadMaskAtPath(mapFilename .. ".colMap.grle", true)
        end

        delete(xmlFile)
    end
end

---Load the mask from the infolayer at given path. If it fails the seasons mask variable is reset.
function SeasonsMask:loadMaskAtPath(path, isTipCol)
    self.mask = createBitVectorMap("SeasonsMask")

    local success = loadBitVectorMapFromFile(self.mask, path, SeasonsMask.MASK_NUM_CHANNELS)
    if not success then
        Logging.info("No Seasons mask has been loaded for the map. Snow will fall everywhere.")
        delete(self.mask)
        self.mask = 0
    end

    if self.mask ~= 0 then
        self.maskSize = getBitVectorMapSize(self.mask)
        self.maskIsTipCol = isTipCol
    end
end

---Load custom snow masks for objects that exist in the vanilla game
function SeasonsMask:loadExtraPlaceableMasks()
    local xmlFile = loadXMLFile("placeables", Utils.getFilename("resources/placeables.xml", self.modDirectory))
    if xmlFile == 0 then
        return
    end

    local i = 0
    while true do
        local key = string.format("placeables.placeable(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local xmlFilename = getXMLString(xmlFile, key .. "#xmlFilename")
        if xmlFilename ~= nil then
            self.customPlaceableMasks[xmlFilename] = {}
            self:loadCustomPlaceableMasks(xmlFile, key, self.customPlaceableMasks[xmlFilename], xmlFilename)
        end

        i = i + 1
    end

    delete(xmlFile)
end

---Load a single custom area
function SeasonsMask:loadCustomPlaceableMasks(xmlFile, key, areas, xmlFilename)
    local i = 0
    while true do
        local areaKey = string.format("%s.maskAreas.maskArea(%d)", key, i)
        if not hasXMLProperty(xmlFile, areaKey) then
            break
        end

        local startX = getXMLFloat(xmlFile, areaKey .. "#startX")
        local startZ = getXMLFloat(xmlFile, areaKey .. "#startZ")
        local widthX = getXMLFloat(xmlFile, areaKey .. "#widthX")
        local widthZ = getXMLFloat(xmlFile, areaKey .. "#widthZ")
        local heightX = getXMLFloat(xmlFile, areaKey .. "#heightX")
        local heightZ = getXMLFloat(xmlFile, areaKey .. "#heightZ")

        if startX == nil or startZ == nil or widthX == nil or widthZ == nil or heightX == nil or heightZ == nil then
            Logging.error("The mask area set for placeable %s is incorrect", xmlFilename)
        else
            local area = {startX, startZ, startX + widthX, startZ + widthZ, startX + heightX, startZ + heightZ}
            table.insert(areas, area)
        end

        i = i + 1
    end
end

function SeasonsMask:draw()
    if self.visualizeMask then
        self:visualize()
    end
end

----------------------
-- Handling of placeables
----------------------

---Update mask when an object is placed
function SeasonsMask.inj_placeable_finalizePlacement(placeable)
    g_seasons.mask:setPlacableInSnowMask(placeable, 1)
end

---Update mask when an object is sold
function SeasonsMask.inj_placeable_onSell(placeable)
    g_seasons.mask:setPlacableInSnowMask(placeable, 0)
end

---Set a value in the snow mask for the best placeable mask area
function SeasonsMask:setPlacableInSnowMask(placeable, value)
    if self.mask == 0 then
        return
    end

    -- If placeable has seasons mask areas, use them
    if placeable.seasons_maskAreas ~= nil then
        for _, area in ipairs(placeable.seasons_maskAreas) do
            self:setPlacableAreaInSnowMask(area, value)
        end

    -- Look for overwritten areas
    elseif self.customPlaceableMasks[placeable.configFileName] ~= nil then
        local areas = self.customPlaceableMasks[placeable.configFileName]
        if #areas > 0 then
            local x, y, z = getWorldTranslation(placeable.nodeId)
            local _, ry, _ = getRotation(placeable.nodeId)

            local s, c = math.sin(-ry), math.cos(-ry)

            for _, area in ipairs(areas) do
                local startX, startZ = area[1], area[2]
                local widthX, widthZ = area[3], area[4]
                local heightX, heightZ = area[5], area[6]

                -- Rotate around origin
                startX, startZ = startX * c - startZ * s, startX * s + startZ * c
                widthX, widthZ = widthX * c - widthZ * s, widthX * s + widthZ * c
                heightX, heightZ = heightX * c - heightZ * s, heightX * s + heightZ * c

                local worldArea = {x + startX, z + startZ, x + widthX, z + widthZ, x + heightX, z + heightZ}
                self:setPlacableAreaInSnowMask(worldArea, value, true)
            end
        end

    -- Fall back to clear area
    else
        for _, area in ipairs(placeable.clearAreas) do
            self:setPlacableAreaInSnowMask(area, value)
        end
    end
end

---Set areas in the mask to given value. If isCoords is true, the area contains the coords
function SeasonsMask:setPlacableAreaInSnowMask(area, value, isCoords)
    local x, z, x1, z1, x2, z2, _

    if isCoords then
        x, z, x1, z1, x2, z2 = unpack(area)
    else
        x, _, z = getWorldTranslation(area.start)
        x1, _, z1 = getWorldTranslation(area.width)
        x2, _, z2 = getWorldTranslation(area.height)
    end

    -- UV coords 0 - 1
    -- World coords -tSize/2 - tSize/2
    self:setParallelogramUVCoords(self.modifierValue, x, z, x1, z1, x2, z2)
    self.modifierValue:executeSet(value)
end

---Load seasons mask areas
function SeasonsMask.inj_placeable_load(placeable, superFunc, xmlFilename, x,y,z, rx,ry,rz, initRandom)
    if superFunc(placeable, xmlFilename, x,y,z, rx,ry,rz, initRandom) then
        local xmlFile = loadXMLFile("TempXML", xmlFilename)

        if hasXMLProperty(xmlFile, "placeable.seasons.maskAreas") then
            -- When none are defined this list should be empty so masks can be disabled
            placeable.seasons_maskAreas = {}
            if hasXMLProperty(xmlFile, "placeable.seasons.maskAreas.maskArea(0)") then
                placeable:loadAreasFromXML(placeable.seasons_maskAreas, xmlFile, "placeable.seasons.maskAreas.maskArea(%d)", false, false, false)
            end
        end

        delete(xmlFile)

        return true
    end

    return false
end

----------------------
-- Utilities
----------------------

---Get whether there is a mask
function SeasonsMask:hasMask()
    return self.mask ~= 0
end

---Get whether the mask is a truly painted mask and not a fallback
function SeasonsMask:hasPaintedMask()
    return self.mask ~= 0 and not self.maskIsTipCol
end

---Get a modifier filter equalling given value
function SeasonsMask:getFilter(equals)
    if self.mask ~= 0 then
        self.filter:setValueCompareParams("equals", equals)
        return self.filter
    end

    return nil
end

---Get the density at given parallelogram
function SeasonsMask:getDensityAt(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local modifier = self.modifierValue
    self:setParallelogramUVCoords(modifier, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)

    local density, _, _ = modifier:executeGet()

    return density
end

---Set the UV coords based on world points.
function SeasonsMask:setParallelogramUVCoords(modifier, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local terrainSize = self.terrainSize
    modifier:setParallelogramUVCoords(startWorldX / terrainSize + 0.5, startWorldZ / terrainSize + 0.5, widthWorldX / terrainSize + 0.5, widthWorldZ / terrainSize + 0.5, heightWorldX / terrainSize + 0.5, heightWorldZ / terrainSize + 0.5, "ppp")
end

function SeasonsMask:visualize()
    local worldToDensityMap = self.maskSize / self.terrainSize
    local densityToWorldMap = self.terrainSize / self.maskSize

    if self.mask ~= 0 then
        local x,y,z = getWorldTranslation(getCamera(0))

        if self.mission.controlledVehicle ~= nil then
            local object = self.mission.controlledVehicle

            if self.mission.controlledVehicle.selectedImplement ~= nil then
                object = self.mission.controlledVehicle.selectedImplement.object
            end

            x, y, z = getWorldTranslation(object.components[1].node)
        end

        local terrainHalfSize = self.terrainSize * 0.5
        local xi = math.floor((x + terrainHalfSize) * worldToDensityMap)
        local zi = math.floor((z + terrainHalfSize) * worldToDensityMap)

        local minXi = math.max(xi - 20, 0)
        local minZi = math.max(zi - 20, 0)
        local maxXi = math.min(xi + 20, self.maskSize - 1)
        local maxZi = math.min(zi + 20, self.maskSize - 1)

        for zi = minZi, maxZi do
            for xi = minXi, maxXi do
                local v = getBitVectorMapPoint(self.mask, xi, zi, SeasonsMask.MASK_FIRST_CHANNEL, SeasonsMask.MASK_NUM_CHANNELS)

                local r,g,b = 0, 1, 0
                if v == 1 then
                    r, g, b = 1, 0, 0.1
                end

                local x = (xi * densityToWorldMap) - terrainHalfSize
                local z = (zi * densityToWorldMap) - terrainHalfSize
                local y = getTerrainHeightAtWorldPos(self.mission.terrainRootNode, x,0,z) + 0.05

                Utils.renderTextAtWorldPosition(x, y, z, tostring(v), getCorrectTextSize(0.009), 0, {r, g, b, 1})
            end
        end
    end
end

----------------------
-- Console commands
----------------------

function SeasonsMask:consoleCommandReloadPlaceableMasks()
    self:loadExtraPlaceableMasks()
    return "Done. Make sure to sell before reloading, and buy after reloading, for the mask to be updated properly."
end

function SeasonsMask:consoleCommandToggleMask()
    self.visualizeMask = not self.visualizeMask

    return tostring(self.visualizeMask)
end
