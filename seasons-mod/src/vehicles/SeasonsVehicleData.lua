----------------------------------------------------------------------------------------------------
-- SeasonsVehicleData
----------------------------------------------------------------------------------------------------
-- Purpose:  Data for the economy, with value changes and other configurations.
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsVehicleData = {}

local SeasonsVehicleData_mt = Class(SeasonsVehicleData)

function SeasonsVehicleData:new(workAreaTypeManager)
    local self = setmetatable({}, SeasonsVehicleData_mt)

    self.workAreaTypeManager = workAreaTypeManager

    self.paths = {}

    self.workAreaTypes = {}

    return self
end

function SeasonsVehicleData:delete()
end

function SeasonsVehicleData:load()
    self:loadDataFromFiles()
end

function SeasonsVehicleData:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("vehicle", path.file)
        if xmlFile then
            self:loadDataFromFile(xmlFile)

            delete(xmlFile)
        end
    end
end

function SeasonsVehicleData:loadDataFromFile(xmlFile)
    self:loadWorkAreaTypeProperties(xmlFile)
end

function SeasonsVehicleData:loadWorkAreaTypeProperties(xmlFile)

    local i = 0
    while true do
        local key = string.format("vehicle.workAreaTypes.workAreaType(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local name = getXMLString(xmlFile, key .. "#name")
        local allowedWithFrozenSoil = Utils.getNoNil(getXMLBool(xmlFile, key .. "#allowedWithFrozenSoil"), true)

        local workAreaType = self.workAreaTypeManager:getWorkAreaTypeIndexByName(name)
        if workAreaType ~= nil then
            if self.workAreaTypes[workAreaType] == nil then
                self.workAreaTypes[workAreaType] = {}
            end

            self.workAreaTypes[workAreaType].allowedWithFrozenSoil = allowedWithFrozenSoil
        end

        i = i + 1
    end

end

function SeasonsVehicleData:setDataPaths(paths)
    self.paths = paths
end

----------------------
-- Getters
----------------------

function SeasonsVehicleData:getIsWorkAreaTypeAllowedWithFrozenSoil(workAreaType)
    if self.workAreaTypes[workAreaType] == nil then
        return true
    end

    return self.workAreaTypes[workAreaType].allowedWithFrozenSoil
end
