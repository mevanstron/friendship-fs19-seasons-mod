----------------------------------------------------------------------------------------------------
-- SeasonsWeatherData
----------------------------------------------------------------------------------------------------
-- Purpose:  Weather system for Seasons
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsWeatherData = {}

local SeasonsWeatherData_mt = Class(SeasonsWeatherData)

function SeasonsWeatherData:new()
    local self = setmetatable({}, SeasonsWeatherData_mt)

    self.paths = {}

    return self
end

function SeasonsWeatherData:delete()
end

function SeasonsWeatherData:load()
    self:loadDataFromFiles()
end

function SeasonsWeatherData:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("weather", path.file)
        if xmlFile then
            self:loadDataFromFile(xmlFile)

            delete(xmlFile)
        end
    end
end

function SeasonsWeatherData:loadDataFromFile(xmlFile)
    -- Load start values. This assumes at least 1 file has those values. (Seasons data)
    self.startValues = {}
    self.startValues.soilTemp = getXMLFloat(xmlFile, "weather.startValues.soilTemp")
    self.startValues.highAirTemp = getXMLFloat(xmlFile, "weather.startValues.highAirTemp")
    self.startValues.snowDepth = getXMLFloat(xmlFile, "weather.startValues.snowDepth")

    self.temperature = self:loadValuesFromXML(xmlFile, "weather.temperature.dailyMaximum")
    self.cloudProbability = self:loadValuesFromXML(xmlFile, "weather.clouds.probability")
    self.rainProbability = self:loadValuesFromXML(xmlFile, "weather.rain.probability")
    self.rainfall = self:loadValuesFromXML(xmlFile, "weather.rain.rainfall")
    self.wind = self:loadValuesFromXML(xmlFile, "weather.wind.speed")
end

function SeasonsWeatherData:loadValuesFromXML(xmlFile, key)
    local values = {}

    -- Load for each
    local i = 0
    while true do
        local fKey = string.format("%s.value(%d)", key, i)
        if not hasXMLProperty(xmlFile, fKey) then break end

        local period = getXMLInt(xmlFile, fKey .. "#period")
        local value = getXMLFloat(xmlFile, fKey)

        values[period] = value

        i = i + 1
    end

    if table.getn(values) ~= SeasonsEnvironment.PERIODS_IN_YEAR then
        Logging.error("Error in weather data: not all period are configured in " .. key)
    end

    return values
end

function SeasonsWeatherData:loadFromSavegame(xmlFile)

end

function SeasonsWeatherData:setDataPaths(paths)
    self.paths = paths
end

----------------------
-- Getters
----------------------
