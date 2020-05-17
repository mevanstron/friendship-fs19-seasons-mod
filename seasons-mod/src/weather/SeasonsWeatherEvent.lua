----------------------------------------------------------------------------------------------------
-- SeasonsWeatherEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Holds data of some weather
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsWeatherEvent = {}

SeasonsWeatherEvent.SEND_BITS_WEATHER_TYPE = 3 -- 7 max value
SeasonsWeatherEvent.SEND_BITS_PERCENTAGE = 8
SeasonsWeatherEvent.SEND_BITS_FOGSCALE = 10
SeasonsWeatherEvent.TIME_TRUNCATE_DECIMALS = 4
SeasonsWeatherEvent.TIME_DECIMALS = 10000 -- must be same number of zeroes as TIME_TRUNCATE_DECIMALS
SeasonsWeatherEvent.TIME_BITS = 18 -- ceil(log2(SeasonsWeatherEvent.TIME_DECIMALS * 24))


local SeasonsWeatherEvent_mt = Class(SeasonsWeatherEvent)

function SeasonsWeatherEvent:new()
    self = setmetatable({}, SeasonsWeatherEvent_mt)

    self.startDay = 1
    self.endDay = 1
    self.startTime = 0
    self.endTime = 0

    self.weatherType = SeasonsWeather.WEATHERTYPE_SUN

    self.fogScale = 0

    self.cloudTypeFrom = 0
    self.cloudTypeTo = 0
    self.cloudCoverage = 0
    self.cirrusCloudDensityScale = 0
    self.cirrusCloudSpeedFactor = 0

    self.windDirX = 1
    self.windDirZ = 0
    self.windVelocity = 0

    self.precipitationIntensity = 0
    self.precipitationType = nil

    self.stormIntensity = 0

    self.temperatureIndication = 0

    self.n = 1

    return self
end

function SeasonsWeatherEvent:delete()
end

function SeasonsWeatherEvent:loadFromXML(xmlFile, key)
    self.startDay = getXMLInt(xmlFile, key .. "#startDay")
    self.endDay = getXMLInt(xmlFile, key .. "#endDay")

    -- These values need to match exactly. Due to floating point precision we need to truncate
    self.startTime = SeasonsMathUtil.truncate(getXMLFloat(xmlFile, key .. "#startTime"), SeasonsWeatherEvent.TIME_TRUNCATE_DECIMALS)
    self.endTime = SeasonsMathUtil.truncate(getXMLFloat(xmlFile, key .. "#endTime"), SeasonsWeatherEvent.TIME_TRUNCATE_DECIMALS)

    self.weatherType = getXMLInt(xmlFile, key .. "#weatherType")

    self.fogScale = getXMLFloat(xmlFile, key .. ".fog#scale")

    self.cloudTypeFrom = getXMLFloat(xmlFile, key .. ".clouds#typeFrom")
    self.cloudTypeTo = getXMLFloat(xmlFile, key .. ".clouds#typeTo")
    self.cloudCoverage = getXMLFloat(xmlFile, key .. ".clouds#coverage")
    self.cirrusCloudDensityScale = getXMLFloat(xmlFile, key .. ".clouds#cirrusDensityScale")
    self.cirrusCloudSpeedFactor = getXMLFloat(xmlFile, key .. ".clouds#cirrusSpeedFactor")

    self.windDirX = getXMLFloat(xmlFile, key .. ".wind#dirX")
    self.windDirZ = getXMLFloat(xmlFile, key .. ".wind#dirZ")
    self.windVelocity = getXMLFloat(xmlFile, key .. ".wind#velocity")

    self.precipitationIntensity = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".precipitation#intensity"), 0)
    self.precipitationType = getXMLString(xmlFile, key .. ".precipitation#type")

    self.stormIntensity = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".storm#intensity"), 0)

    self.temperatureIndication = getXMLFloat(xmlFile, key .. ".temperature#indication")

    self.n = getXMLFloat(xmlFile, key .. ".n")

    return true
end

function SeasonsWeatherEvent:saveToXML(xmlFile, key)
    setXMLInt(xmlFile, key .. "#startDay", self.startDay)
    setXMLInt(xmlFile, key .. "#endDay", self.endDay)
    setXMLFloat(xmlFile, key .. "#startTime", self.startTime)
    setXMLFloat(xmlFile, key .. "#endTime", self.endTime)

    setXMLInt(xmlFile, key .. "#weatherType", self.weatherType)

    setXMLFloat(xmlFile, key .. ".fog#scale", self.fogScale)

    setXMLFloat(xmlFile, key .. ".clouds#typeFrom", self.cloudTypeFrom)
    setXMLFloat(xmlFile, key .. ".clouds#typeTo", self.cloudTypeTo)
    setXMLFloat(xmlFile, key .. ".clouds#coverage", self.cloudCoverage)
    setXMLFloat(xmlFile, key .. ".clouds#cirrusDensityScale", self.cirrusCloudDensityScale)
    setXMLFloat(xmlFile, key .. ".clouds#cirrusSpeedFactor", self.cirrusCloudSpeedFactor)

    setXMLFloat(xmlFile, key .. ".wind#dirX", self.windDirX)
    setXMLFloat(xmlFile, key .. ".wind#dirZ", self.windDirZ)
    setXMLFloat(xmlFile, key .. ".wind#velocity", self.windVelocity)

    if self.precipitationType ~= nil then
        setXMLFloat(xmlFile, key .. ".precipitation#intensity", self.precipitationIntensity)
        setXMLString(xmlFile, key .. ".precipitation#type", self.precipitationType)
    end

    if self.stormIntensity ~= 0 then
        setXMLFloat(xmlFile, key .. ".storm#intensity", self.stormIntensity)
    end

    setXMLFloat(xmlFile, key .. ".temperature#indication", self.temperatureIndication)
    setXMLFloat(xmlFile, key .. ".n", self.n)
end

function SeasonsWeatherEvent:writeStream(streamId, connection)
    local maxBitValue = (2 ^ SeasonsWeatherEvent.SEND_BITS_PERCENTAGE) - 1
    local function writePercentage(value)
        local value = MathUtil.clamp(value * maxBitValue, 0, maxBitValue)
        streamWriteUIntN(streamId, value, SeasonsWeatherEvent.SEND_BITS_PERCENTAGE)
    end

    streamWriteUInt16(streamId, self.startDay)
    streamWriteUInt16(streamId, self.endDay)

    -- Turn values whole-integer
    streamWriteUIntN(streamId, math.floor(self.startTime * SeasonsWeatherEvent.TIME_DECIMALS), SeasonsWeatherEvent.TIME_BITS)
    streamWriteUIntN(streamId, math.floor(self.endTime * SeasonsWeatherEvent.TIME_DECIMALS), SeasonsWeatherEvent.TIME_BITS)

    streamWriteUIntN(streamId, self.weatherType, SeasonsWeatherEvent.SEND_BITS_WEATHER_TYPE)

    streamWriteUInt8(streamId, self.fogScale)

    writePercentage(self.cloudTypeFrom)
    writePercentage(self.cloudTypeTo)
    writePercentage(self.cloudCoverage)
    writePercentage(self.cirrusCloudDensityScale)
    writePercentage(self.cirrusCloudSpeedFactor)

    -- Both are -1-1 (because normalized) so we can do percentages
    writePercentage((self.windDirX + 1) / 2)
    writePercentage((self.windDirZ + 1) / 2)
    writePercentage(self.windVelocity / WindUpdater.MAX_SPEED)

    streamWriteBool(streamId, self.precipitationType ~= nil)
    if self.precipitationType ~= nil then
        writePercentage(self.precipitationIntensity)
        streamWriteString(streamId, self.precipitationType)
    end

    writePercentage(self.stormIntensity)

    streamWriteFloat32(streamId, self.temperatureIndication)
    streamWriteFloat32(streamId, self.n)
end

function SeasonsWeatherEvent:readStream(streamId, connection)
    local maxBitValue = (2 ^ SeasonsWeatherEvent.SEND_BITS_PERCENTAGE) - 1
    local function readPercentage()
        local value = streamReadUIntN(streamId, SeasonsWeatherEvent.SEND_BITS_PERCENTAGE)
        return value / maxBitValue
    end

    self.startDay = streamReadUInt16(streamId)
    self.endDay = streamReadUInt16(streamId)

    -- Values are moved to the whole-integer space so we turn them back
    self.startTime = streamReadUIntN(streamId, SeasonsWeatherEvent.TIME_BITS) / SeasonsWeatherEvent.TIME_DECIMALS
    self.endTime = streamReadUIntN(streamId, SeasonsWeatherEvent.TIME_BITS) / SeasonsWeatherEvent.TIME_DECIMALS

    self.weatherType = streamReadUIntN(streamId, SeasonsWeatherEvent.SEND_BITS_WEATHER_TYPE)

    self.fogScale = streamReadUInt8(streamId)

    self.cloudTypeFrom = readPercentage()
    self.cloudTypeTo = readPercentage()
    self.cloudCoverage = readPercentage()
    self.cirrusCloudDensityScale = readPercentage()
    self.cirrusCloudSpeedFactor = readPercentage()

    -- Both are -1-1 (because normalized) so we can do percentages
    self.windDirX = readPercentage() * 2 - 1
    self.windDirZ = readPercentage() * 2 - 1
    self.windVelocity = readPercentage() * WindUpdater.MAX_SPEED

    if streamReadBool(streamId) then
        self.precipitationIntensity = readPercentage()
        self.precipitationType = streamReadString(streamId)
    end

    self.stormIntensity = readPercentage()

    self.temperatureIndication = streamReadFloat32(streamId)
    self.n = streamReadFloat32(streamId)
end

---Activate the event by setting updater targets
function SeasonsWeatherEvent:activate(cloudUpdater, windUpdater, fogUpdater, weatherFrontUpdater, downfallUpdater, stormUpdater, duration)
    local duration = Utils.getNoNil(duration, 1000) -- switch duration

    cloudUpdater:setTargetValues(self.cloudTypeFrom, self.cloudTypeTo, self.cloudCoverage, self.cirrusCloudDensityScale, duration)
    windUpdater:setTargetValues(self.windDirX, self.windDirZ, self.windVelocity, self.cirrusCloudSpeedFactor, duration)
    fogUpdater:setTargetValues(self.fogScale, duration)
    downfallUpdater:setTargetValues(self.precipitationType, self.precipitationIntensity, duration)
    stormUpdater:setTargetValues(self.stormIntensity, duration)
end

---Deactivate the event
function SeasonsWeatherEvent:deactivate(duration)
end

function SeasonsWeatherEvent:getIsWithinEvent(day, time)
    return day >= self.startDay and day <= self.endDay and (hour >= self.startTime or day ~= self.startDay) and (hour <= self.endTime or day ~= self.endDay)
end
