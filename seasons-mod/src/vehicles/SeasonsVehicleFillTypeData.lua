----------------------------------------------------------------------------------------------------
-- SeasonsVehicleFillTypeData
----------------------------------------------------------------------------------------------------
-- Purpose: Manage configuration for spraying on frozen ground
-- Authors:
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsVehicleFillTypeData = {}

local SeasonsVehicleFillTypeData_mt = Class(SeasonsVehicleFillTypeData)

function SeasonsVehicleFillTypeData:new(fillTypeManager)
    local self = setmetatable({}, SeasonsVehicleFillTypeData_mt)

    self.fillTypeManager = fillTypeManager

    self.paths = {}

    self.fillTypes = {}

    return self
end

function SeasonsVehicleFillTypeData:delete()
end

function SeasonsVehicleFillTypeData:load()
    self:loadDataFromFiles()
end

function SeasonsVehicleFillTypeData:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("fillTypes", path.file)
        if xmlFile then
            self:loadDataFromFile(xmlFile)

            delete(xmlFile)
        end
    end
end

function SeasonsVehicleFillTypeData:loadDataFromFile(xmlFile)
    self:loadFillTypeProperties(xmlFile)
end

function SeasonsVehicleFillTypeData:loadFillTypeProperties(xmlFile)
    local i = 0
    while true do
        local key = string.format("fillTypes.fillType(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local name = getXMLString(xmlFile, key .. "#name")
        local allowedWithFrozenSoil = Utils.getNoNil(getXMLBool(xmlFile, key .. "#allowedWithFrozenSoil"), true)

        local fillType = self.fillTypeManager:getFillTypeIndexByName(name)
        if fillType ~= nil then
            if self.fillTypes[fillType] == nil then
                self.fillTypes[fillType] = {}
            end

            self.fillTypes[fillType].allowedWithFrozenSoil = allowedWithFrozenSoil
        end

        i = i + 1
    end
end

function SeasonsVehicleFillTypeData:setDataPaths(paths)
    self.paths = paths
end

----------------------
-- Getters
----------------------

function SeasonsVehicleFillTypeData:getIsFillTypeAllowedWithFrozenSoil(fillType)
    if self.fillTypes[fillType] == nil then
        return true
    end

    return self.fillTypes[fillType].allowedWithFrozenSoil
end
