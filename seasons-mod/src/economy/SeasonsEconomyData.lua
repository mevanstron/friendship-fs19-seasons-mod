----------------------------------------------------------------------------------------------------
-- SeasonsEconomyData
----------------------------------------------------------------------------------------------------
-- Purpose:  Data for the economy, with value changes and other configurations.
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsEconomyData = {}

local SeasonsEconomyData_mt = Class(SeasonsEconomyData)

function SeasonsEconomyData:new(mission, fillTypeManager, environment)
    local self = setmetatable({}, SeasonsEconomyData_mt)

    self.fillTypeManager = fillTypeManager
    self.environment = environment
    self.mission = mission

    self.paths = {}

    self.ai = {}
    self.repricing = {}
    self.repricing.fillTypes = {}
    self.repricing.animals = {}
    self.repricing.bales = {}

    return self
end

function SeasonsEconomyData:delete()
end

function SeasonsEconomyData:load()
    self:loadDataFromFiles()
end

function SeasonsEconomyData:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("economy", path.file)
        if xmlFile then
            self:loadDataFromFile(xmlFile)

            delete(xmlFile)
        end
    end
end

function SeasonsEconomyData:loadDataFromFile(xmlFile)
    self.ai.workdayStart = Utils.getNoNil(getXMLFloat(xmlFile, "economy.ai#workdayStart"), self.ai.workdayStart)
    self.ai.workdayEnd = Utils.getNoNil(getXMLFloat(xmlFile, "economy.ai#workdayEnd"), self.ai.workdayEnd)
    self.ai.workdayPay = Utils.getNoNil(getXMLFloat(xmlFile, "economy.ai#workdayPay"), self.ai.workdayPay)
    self.ai.overtimePay = Utils.getNoNil(getXMLFloat(xmlFile, "economy.ai#overtimePay"), self.ai.overtimePay)

    -- The AI system uses milliseconds
    self.ai.workdayPayMS = self.ai.workdayPay / 60 / 60 / 1000
    self.ai.overtimePayMS = self.ai.overtimePay / 60 / 60 / 1000

    self:loadRepricing(xmlFile, "economy.repricing.animals", self.repricing.animals)
    self:loadRepricing(xmlFile, "economy.repricing.bales", self.repricing.bales)
    self:loadRepricing(xmlFile, "economy.repricing.fillTypes", self.repricing.fillTypes)
end

---Load all types of a group
function SeasonsEconomyData:loadRepricing(xmlFile, root, data)
    local i = 0
    while true do
        local key = string.format("%s.type(%d)", root, i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local name = getXMLString(xmlFile, key .. "#name")
        if name ~= nil then
            if data[name] == nil then
                data[name] = {}
            end

            if not self:loadRepricingFactors(xmlFile, key .. ".factors", data[name]) then
                if data[name][1] == 0 then
                    data[name].allZero = true
                end
            end
        end

        i = i + 1
    end
end

---Load a single block of factors
-- Returns whether there were factors. False when all zero or all 1 value
function SeasonsEconomyData:loadRepricingFactors(xmlFile, root, data)
    if getXMLFloat(xmlFile, root .. "#all") ~= nil then -- hasXMLProperty does not work
        local value = getXMLFloat(xmlFile, root .. "#all")

        for i = 1, SeasonsEnvironment.PERIODS_IN_YEAR do
            data[i] = value
        end

        return false
    else
        local i = 0
        while true do
            local key = string.format("%s.factor(%d)", root, i)
            if not hasXMLProperty(xmlFile, key) then
                break
            end

            local period = getXMLInt(xmlFile, key .. "#period")
            local value = getXMLFloat(xmlFile, key)

            if period ~= nil and value ~= nil then
                data[period] = value
            end

            i = i + 1
        end

        return true
    end
end

function SeasonsEconomyData:setDataPaths(paths)
    self.paths = paths
end

----------------------
-- Getters
----------------------

---Get the repricing factor for given group and type, at current day or given day.
-- Facotors are lerped.
function SeasonsEconomyData:getRepricingFactor(groupName, type, day)
    local hour = 12 -- default to mid-day
    if day == nil then
        day = self.environment.currentDay
        hour = self.mission.environment.currentHour
    end


    local group = self.repricing[groupName]
    if group ~= nil and group[type] ~= nil then
        local factors = group[type]

        -- Lerp between two periods to create a nice curve
        local period = self.environment:periodAtDay(day)
        local nextPeriod = period % SeasonsEnvironment.PERIODS_IN_YEAR + 1

        local periodLength = self.environment.daysPerSeason / 3
        local dayInPeriod = (self.environment:dayInSeasonAtDay(day) - 1) % periodLength + 1

        local alpha = (dayInPeriod - 1) / periodLength + 1 / periodLength * (hour / 24)

        return MathUtil.lerp(factors[period], factors[nextPeriod], alpha)
    end

    return 1
end

function SeasonsEconomyData:getFillTypeFactor(fillType, day)
    local name = self.fillTypeManager:getFillTypeNameByIndex(fillType)
    if name ~= nil then
        return self:getRepricingFactor("fillTypes", name, day)
    end

    return 1
end

function SeasonsEconomyData:getBaleFactor(fillType, day)
    local name = self.fillTypeManager:getFillTypeNameByIndex(fillType)
    if name ~= nil then
        return self:getRepricingFactor("bales", name, day)
    end

    return 1
end

function SeasonsEconomyData:getAnimalFactor(animalType, day)
    return self:getRepricingFactor("animals", animalType, day)
end
