----------------------------------------------------------------------------------------------------
-- PlaceableAdmirers
----------------------------------------------------------------------------------------------------
-- Purpose:  Loads the object admirers on placeables
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

PlaceableAdmirers = {}

local PlaceableAdmirer_mt = Class(PlaceableAdmirers)

PlaceableAdmirers.TYPE_SEASON_ADMIRER = "seasonAdmirer"
PlaceableAdmirers.TYPE_SNOW_ADMIRER = "snowAdmirer"
PlaceableAdmirers.TYPE_ICE_ADMIRER = "iceAdmirer"

function PlaceableAdmirers:new(messageCenter, weather, environment, snowHandler)
    local self = setmetatable({}, PlaceableAdmirer_mt)

    self.messageCenter = messageCenter
    self.weather = weather
    self.environment = environment
    self.snowHandler = snowHandler

    SeasonsModUtil.appendedFunction(Placeable, "delete", PlaceableAdmirers.inj_placeable_delete)
    SeasonsModUtil.overwrittenFunction(Placeable, "load", PlaceableAdmirers.inj_placeable_load)
    SeasonsModUtil.overwrittenFunction(Placeable, "weatherChanged", PlaceableAdmirers.inj_placeable_weatherChanged)

    return self
end

---Called on delete.
function PlaceableAdmirers:delete()
end

---Load the admirer for the given type on the placeable.
function PlaceableAdmirers:loadAdmirers(placeable, xmlFile, type)
    local i = 0
    while true do
        local key = ("placeable.seasons.admirers.%s(%d)"):format(type, i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local node = I3DUtil.indexToObject(placeable.nodeId, getXMLString(xmlFile, key .. "#node"))
        if node ~= nil then
            local admirer = self:createAdmirerByType(node, type)
            table.insert(placeable.seasons_admirers, admirer)
        end

        i = i + 1
    end
end

---Create an instance for the given admirer.
function PlaceableAdmirers:createAdmirerByType(node, type)
    if type == PlaceableAdmirers.TYPE_SNOW_ADMIRER then
        return SnowAdmirer:new(node, self.messageCenter, self.snowHandler)
    elseif type == PlaceableAdmirers.TYPE_ICE_ADMIRER then
        return IcePlane:new(node, self.messageCenter, self.weather)
    end

    return SeasonAdmirer:new(node, self.messageCenter, self.environment)
end

---Inject into the load fucntion of placeables to load the admirers from the XML.
function PlaceableAdmirers.inj_placeable_load(placeable, superFunc, xmlFilename, x, y, z, rx, ry, rz, initRandom)
    if superFunc(placeable, xmlFilename, x, y, z, rx, ry, rz, initRandom) then
        local xmlFile = loadXMLFile("TempXML", xmlFilename)
        if hasXMLProperty(xmlFile, "placeable.seasons.admirers") then
            placeable.seasons_admirers = {}

            local placeableAdmirers = g_seasons.placeableAdmirers
            placeableAdmirers:loadAdmirers(placeable, xmlFile, PlaceableAdmirers.TYPE_SEASON_ADMIRER)
            placeableAdmirers:loadAdmirers(placeable, xmlFile, PlaceableAdmirers.TYPE_SNOW_ADMIRER)
            placeableAdmirers:loadAdmirers(placeable, xmlFile, PlaceableAdmirers.TYPE_ICE_ADMIRER)
        end

        delete(xmlFile)

        return true
    end

    return false
end

---Delete the admirers from the placeable when the placeable is deleted.
function PlaceableAdmirers.inj_placeable_delete(placeable)
    if placeable.seasons_admirers ~= nil then
        for _, admirer in pairs(placeable.seasons_admirers) do
            admirer:delete()
        end
    end
end

---Fix an issue with the weather changed event and dayNightObjects"
-- when it is raining, it assumes isSunOn
function PlaceableAdmirers.inj_placeable_weatherChanged(placeable, superFunc)
    local weather = g_currentMission.environment.weather
    local oldFunc = weather.getIsRaining
    weather.getIsRaining = function()
        return false
    end

    superFunc(placeable)

    weather.getIsRaining = oldFunc
end
