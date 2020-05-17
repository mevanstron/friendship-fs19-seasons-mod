----------------------------------------------------------------------------------------------------
-- SeasonsWeather
----------------------------------------------------------------------------------------------------
-- Purpose:  Weather system for Seasons
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsWeather = {}

local SeasonsWeather_mt = Class(SeasonsWeather)

SeasonsWeather.FORECAST_SUN = 0
SeasonsWeather.FORECAST_PARTLY_CLOUDY = 1
SeasonsWeather.FORECAST_RAIN_SHOWERS = 2
SeasonsWeather.FORECAST_SNOW_SHOWERS = 3
SeasonsWeather.FORECAST_SLEET = 4
SeasonsWeather.FORECAST_CLOUDY = 5
SeasonsWeather.FORECAST_RAIN = 6
SeasonsWeather.FORECAST_SNOW = 7
SeasonsWeather.FORECAST_FOG = 8
SeasonsWeather.FORECAST_THUNDER = 9
SeasonsWeather.FORECAST_HAIL = 10

SeasonsWeather.WEATHERTYPE_SUN = 0
SeasonsWeather.WEATHERTYPE_CLOUDY = 1
SeasonsWeather.WEATHERTYPE_RAIN = 2
SeasonsWeather.WEATHERTYPE_SNOW = 3
SeasonsWeather.WEATHERTYPE_FOG = 4
SeasonsWeather.WEATHERTYPE_HAIL = 5
SeasonsWeather.WEATHERTYPE_THUNDER = 6

SeasonsWeather.WINDTYPE_CALM = 0
SeasonsWeather.WINDTYPE_GENTLE_BREEZE = 1
SeasonsWeather.WINDTYPE_STRONG_BREEZE = 2
SeasonsWeather.WINDTYPE_GALE = 3

SeasonsWeather.FOGSCALE = 40

SeasonsWeather.NUM_DAYS_GENERATED = 3

SeasonsWeather.PRECIPITATION_TYPES = {nil, nil, 'rain', 'snow', nil, nil, 'rain'}

---Change the HUD before it is created by the mission
function SeasonsWeather.onMissionWillLoad()
    SeasonsModUtil.overwrittenFunction(GameInfoDisplay, "getWeatherUVs", SeasonsWeather.inj_gameInfoDisplay_getWeatherUVs)
end

function SeasonsWeather:new(mission, environment, snowHandler, messageCenter, modDirectory, server)
    local self = setmetatable({}, SeasonsWeather_mt)

    self.mission = mission
    self.environment = environment
    self.snowHandler = snowHandler
    self.messageCenter = messageCenter
    self.isClient = mission:getIsClient()
    self.isServer = mission:getIsServer()
    self.server = server

    self.data = SeasonsWeatherData:new()
    self.model = SeasonsWeatherModel:new(self.data, self.environment, mission)
    self.forecast = SeasonsWeatherForecast:new(self.data, self.model, self.environment, server)
    self.handler = SeasonsWeatherHandler:new(mission, environment, self, messageCenter, modDirectory)

    self.handler:setSoilWetnessFunction(function ()
        return self:getSoilWetness()
    end)

    -- Replace the Weather system with our own
    SeasonsModUtil.overwrittenFunction(Environment, "new", SeasonsWeather.inj_environment_new)
    SeasonsModUtil.overwrittenFunction(GameInfoDisplay, "getWeatherStates", SeasonsWeather.inj_gameInfoDisplay_getWeatherStates)
    SeasonsModUtil.overwrittenFunction(WindTurbinePlaceable, "updateHeadRotation", SeasonsWeather.inj_windTurbinePlaceable_updateHeadRotation)
    SeasonsModUtil.overwrittenFunction(WindTurbinePlaceable, "update", SeasonsWeather.inj_windTurbinePlaceable_update)
    SeasonsModUtil.overwrittenFunction(WindTurbinePlaceable, "hourChanged", SeasonsWeather.inj_windTurbinePlaceable_hourChanged)

    addConsoleCommand("rmWeatherAddEvent", "Add a basic event", "consoleCommandAddEvent", self)
    addConsoleCommand("rmWeatherSetWindVelocity", "Set wind velocity", "consoleCommandSetWindVelocity", self)

    return self
end

function SeasonsWeather:delete()
    self.data:delete()
    self.model:delete()
    self.forecast:delete()
    -- Do not delete the handler, already deleted by vanilla environment

    self.messageCenter:unsubscribeAll(self)

    removeConsoleCommand("rmWeatherAddEvent")
    removeConsoleCommand("rmWeatherSetWindVelocity")
end

function SeasonsWeather:load()
    self.data:load()
    self.forecast:load()
    self.handler:load()

    self.soilTemp = self.data.startValues.soilTemp
    self.soilTempMax = self.soilTemp
    self.highTempPrev = self.data.startValues.highAirTemp
    self.snowDepth = self.data.startValues.snowDepth

    self.cropMoistureContent = 15.0
    self.soilWaterContent =  0.25
    self.averageSoilWaterContent = self.soilWaterContent
    self.lowAirTemp = 0
    self.rotDryFactor = 0
    self.cropMoistureEnabled = true
    self.meltedSnow = 0 -- won't change on clients
    self.airWasFrozen = false

    self.messageCenter:subscribe(SeasonsMessageType.HOUR_CHANGED_FIX, self.onHourChanged, self)
    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)
end

function SeasonsWeather:onItemsLoaded()
    self.forecast:onItemsLoaded()

    if #self.handler.events <= 1 and self.isServer then
        self:build()
    end

    if not self.forecast:forecastVerified() then
        self:onSeasonLengthChanged()
        Logging.error("Weather forecast rebuilt during load due to inconsistency.")
    end
end

function SeasonsWeather:loadFromSavegame(xmlFile)
    self.soilTemp = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.soilTemp"), self.soilTemp)
    self.soilTempMax = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.soilTempMax"), self.soilTempMax)
    self.highTempPrev = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.highTempPrev"), self.highTempPrev)
    self.cropMoistureContent = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.cropMoistureContent"), self.cropMoistureContent)
    self.soilWaterContent = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.soilWaterContent"), self.soilWaterContent)
    self.averageSoilWaterContent = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.averageSoilWaterContent"), self.averageSoilWaterContent)
    self.lowAirTemp = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.lowAirTemp"), self.lowAirTemp)
    self.snowDepth = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.snowDepth"), self.snowDepth)
    self.rotDryFactor = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.rotDryFactor"), self.rotDryFactor)
    self.cropMoistureEnabled = Utils.getNoNil(getXMLBool(xmlFile, "seasons.weather.moistureEnabled"), self.cropMoistureEnabled)

    self.handler:loadFromSavegame(xmlFile)
    self.forecast:loadFromSavegame(xmlFile)

    self:verifyOrRebuildWeather()
end

function SeasonsWeather:saveToSavegame(xmlFile)
    setXMLFloat(xmlFile, "seasons.weather.soilTemp", self.soilTemp)
    setXMLFloat(xmlFile, "seasons.weather.soilTempMax", self.soilTempMax)
    setXMLFloat(xmlFile, "seasons.weather.highTempPrev", self.highTempPrev)
    setXMLFloat(xmlFile, "seasons.weather.cropMoistureContent", self.cropMoistureContent)
    setXMLFloat(xmlFile, "seasons.weather.soilWaterContent", self.soilWaterContent)
    setXMLFloat(xmlFile, "seasons.weather.lowAirTemp", self.lowAirTemp)
    setXMLFloat(xmlFile, "seasons.weather.snowDepth", self.snowDepth)
    setXMLFloat(xmlFile, "seasons.weather.rotDryFactor", self.rotDryFactor)
    setXMLFloat(xmlFile, "seasons.weather.averageSoilWaterContent", self.averageSoilWaterContent)
    setXMLBool(xmlFile, "seasons.weather.moistureEnabled", self.cropMoistureEnabled)

    self.handler:saveToSavegame(xmlFile)
    self.forecast:saveToSavegame(xmlFile)
end

function SeasonsWeather:setDataPaths(paths)
    self.data:setDataPaths(paths)
end

function SeasonsWeather:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.soilTemp)
    streamWriteFloat32(streamId, self.cropMoistureContent)
    streamWriteFloat32(streamId, self.soilWaterContent)
    streamWriteFloat32(streamId, self.highTempPrev)
    streamWriteBool(streamId, self.cropMoistureEnabled)
end

function SeasonsWeather:readStream(streamId, connection)
    self.soilTemp = streamReadFloat32(streamId)
    self.yesterdaySoilTemp = self.soilTemp
    self.cropMoistureContent = streamReadFloat32(streamId)
    self.soilWaterContent = streamReadFloat32(streamId)
    self.highTempPrev = streamReadFloat32(streamId)
    self.cropMoistureEnabled = streamReadBool(streamId)
end

----------------------
-- Events
----------------------

function SeasonsWeather:update(dt)
    -- Do not run weather handler update: already done by basegame

    self.handler:setAirTemperature(self:getCurrentAirTemperature())
end

---Once game loaded, call the change handlers so everything has the correct state
function SeasonsWeather:onGameLoaded()
    self.messageCenter:publish(SeasonsMessageType.FREEZING_CHANGED)
    self.airWasFrozen = self:getIsFreezing()

    if self.mission:getIsServer() then
        if g_seasons.isNewSavegame and self.snowDepth > 0 then
            self.snowHandler:setSnowHeight(self.snowDepth)
        end
    end

    self:updateWeatherConditionals()
    self.cropDryingForecast = self:cropDryingSimulation(self.cropMoistureContent, self.environment.currentDay, self.environment:getTimeInHours())
end

function SeasonsWeather:onHourChanged()
    local deltaMoisture

    if self.isServer then
        self.meltedSnow = 0
        self:updateSnowDepth()

        local windSpeed = self.handler:getCurrentWindSpeed()
        local currentForecastItem = self.forecast:getCurrentItem()
        local cloudCoverage = self.mission.environment.weather.cloudUpdater.currentCloudCoverage
        local dropScale = self.mission.environment.weather.downfallUpdater.currentDropScale
        local fogScale = self.mission.environment.weather.fogUpdater.currentMieScale
        local timeSinceLastRain = self.mission.environment.weather.timeSinceLastRain
        local dayTime = self.mission.environment.dayTime / 60 / 60 / 1000 --current time in hours
        local julianDay = self.environment.daylight:getCurrentJulianDay()

        self.cropMoistureContent, deltaMoisture = self.model:updateCropMoistureContent(self.cropMoistureContent, julianDay, dayTime, self:getCurrentAirTemperature(), currentForecastItem.lowTemp, windSpeed, cloudCoverage, dropScale, fogScale, timeSinceLastRain, true)
        self.rotDryFactor = self.rotDryFactor + deltaMoisture
        -- log(self.cropMoistureContent, deltaMoisture, self.rotDryFactor)

        if not self:isGroundFrozen() then
            self.soilWaterContent = self.model:calculateSoilWaterContent(self.soilWaterContent, self:getCurrentAirTemperature(), currentForecastItem.lowTemp, self.meltedSnow, self.snowDepth, self:isGroundFrozen())
            self:updateAverageSoilWaterContent()
        end
    end

    if self.isServer then
        g_server:broadcastEvent(SeasonsWeatherHourlyEvent:new(self.cropMoistureContent, self.snowDepth, self.soilWaterContent))
    end

    -- Update objects when freezing in air changes
    local isFreezing = self:getIsFreezing()
    if (self.airWasFrozen and not isFreezing) or (not self.airWasFrozen and isFreezing) then
        self.messageCenter:publish(SeasonsMessageType.FREEZING_CHANGED)
    end
    self.airWasFrozen = isFreezing

    self.cropDryingForecast = self:cropDryingSimulation(self.cropMoistureContent, self.environment.currentDay, self.environment:getTimeInHours())
end

function SeasonsWeather:onDayChanged()
    self:updateLowAirTemp()

    if self.isServer then
        if not self.forecast:forecastVerified() then
            self:onSeasonLengthChanged()
            Logging.error("Weather forecast rebuilt due to inconsistency.")
        end

        self.forecast:generateNextDay()
    end

    self.forecast:updateCurrentItem(self.environment.currentDay)

    if self.isServer then
        self.yesterdaySoilTemp = self.soilTemp
        local currentForecastItem = self.forecast:getCurrentItem()
        self.highTempPrev = currentForecastItem.highTemp
        self.soilTemp, self.soilTempMax = self.model:calculateSoilTemp(self.soilTemp, self.soilTempMax, currentForecastItem.lowTemp, currentForecastItem.highTemp, self.snowDepth, self.environment.daysPerSeason, false)

        self:generateWeatherIfNeeded()

        -- Send new values so we don't deviate on clients
        g_server:broadcastEvent(SeasonsWeatherDailyEvent:new(self.yesterdaySoilTemp, self.soilTemp, self.soilTempMax))

        self:onTemperaturesChanged()
    end
end

---Temperatures changed (soil temp)
function SeasonsWeather:onTemperaturesChanged()
    -- Update objects when freezing in ground changes
    if (self.yesterdaySoilTemp <= 0 and self.soilTemp > 0) or (self.yesterdaySoilTemp > 0 and self.soilTemp <= 0) then
        self.messageCenter:publish(SeasonsMessageType.FREEZING_CHANGED)
    end

    self:updateWeatherConditionals()
end

function SeasonsWeather:onPeriodChanged()
    -- weather runs before growth?
    self.frostIndex = 4
end

---Regenerate the weather when the season length changed
function SeasonsWeather:onSeasonLengthChanged()
    if self.isServer then
        self.forecast:rebuild()
        self:rebuild()
        self.server:broadcastEvent(WeatherAddObjectEvent:new(self.handler.events, true))
    end
end

---Send any initial state. Called once a client joins
function SeasonsWeather:onClientJoined(connection)
    self.forecast:onClientJoined(connection)
end

---Data received from server
function SeasonsWeather:onHourlyDataReceived(cropMoistureContent, snowDepth, soilWaterContent)
    if not self.isServer then
        self.cropMoistureContent = cropMoistureContent
        self.snowDepth = snowDepth
        self.soilWaterContent = soilWaterContent
    end
end

---Data received from server to prevent deviation
function SeasonsWeather:onDailyDataReceived(yesterdaySoilTemp, soilTemp, soilTempMax, highTempPrev)
    if not self.isServer then
        self.yesterdaySoilTemp = yesterdaySoilTemp
        self.soilTemp = soilTemp
        self.soilTempMax = soilTempMax
        self.highTempPrev = highTempPrev

        self:onTemperaturesChanged()
    end
end

----------------------
-- Generating weather
----------------------

---Build actual weather and add it to the handler.
function SeasonsWeather:build()
    local day = self.environment.currentDay
    local lastDay = day + SeasonsWeather.NUM_DAYS_GENERATED
    local event, prevEvent, transitionEvent
    local firstForecastDay = self.forecast.items[1].day -- To turn day into forecast item

    while day <= lastDay do
        if prevEvent == nil then
            prevEvent = self:getFirstEvent()
            -- new event does not always start on day 1
            prevEvent.startDay = self.environment.currentDay - self.environment.currentDayOffset
            prevEvent.endDay = self.environment.currentDay - self.environment.currentDayOffset
            event, transitionEvent = self:getWeatherEvent(day, prevEvent, false)
        else
            prevEvent = event
            event, transitionEvent = self:getWeatherEvent(day, prevEvent, false)
        end

        if transitionEvent ~= nil then
            if not self.handler:appendEvent(transitionEvent) then
                Logging.error("Weather generation is corrupt, rebuilding now. (A)")
                return self:rebuild()
            end
        end
        if not self.handler:appendEvent(event) then
            Logging.error("Weather generation is corrupt, rebuilding now. (B)")
            return self:rebuild()
        end

        -- forecast days are in Seasons-time, while weather event days are in basegame-time
        day = event.endDay + self.environment.currentDayOffset
    end
end

---Rebuild weather from scratch
function SeasonsWeather:rebuild()
    self.handler:clearEvents()
    self:build()
end

-- In previous versions the weather data could be corrupted. Check these cases and rebuild otherwise.
function SeasonsWeather:verifyOrRebuildWeather()
    local needsRebuilding = false

    if self.forecast:getForecastForDay(self.environment.currentDay) == nil
        or self.forecast:getForecastForDay(self.environment.currentDay + 1) == nil
        or self.forecast:getForecastForDay(self.environment.currentDay + 2) == nil then
        needsRebuilding = true
    end

    local firstEventTime = self.handler.events[1].startTime + 0.01
    for i = 0, SeasonsWeather.NUM_DAYS_GENERATED - 1 - 1 do -- 1 for 0 indexing, 1 for the time
        if self.handler:getEventAtTime(self.environment.currentDay - self.environment.currentDayOffset + i, firstEventTime) == nil then
            needsRebuilding = true
        end
    end

    if needsRebuilding then
        Logging.error("The weather in this savegame is invalid. A full rebuild is done to prevent freezes and crashes.")

        self.forecast:rebuild()
        self:rebuild()
    end
end

function SeasonsWeather:generateWeatherIfNeeded()
    local prevEvent = self.handler.events[#self.handler.events]
    local firstForecastDay = self.forecast.items[1].day

    -- From the last event in our event list
    local day = prevEvent.endDay + self.environment.currentDayOffset -- Turn seasonal

    -- Until N days into the future
    local lastDay = self.environment.currentDay + SeasonsWeather.NUM_DAYS_GENERATED

    local addedEvents = {}

    -- We generate events for the last day in the events list
    -- and any day after until we have enough filled.
    while day <= lastDay do
        -- Create a new event for the current last day.
        local event, transitionEvent = self:getWeatherEvent(day, prevEvent, false)

        if transitionEvent ~= nil then
            if not self.handler:appendEvent(transitionEvent) then
                Logging.error("Weather generation is corrupt, rebuilding now. (C)")
                return self:rebuild()
            end
            table.insert(addedEvents, transitionEvent)
        end

        if not self.handler:appendEvent(event) then
            Logging.error("Weather generation is corrupt, rebuilding now. (D)")
            return self:rebuild()
        end
        table.insert(addedEvents, event)

        -- Then move the day to the end day of the last event. (seasonal)
        -- This is our loop iterator
        prevEvent = event
        day = event.endDay + self.environment.currentDayOffset
    end

    if #addedEvents > 0 then
        self.server:broadcastEvent(WeatherAddObjectEvent:new(addedEvents, false))
    end
end

--- function to keep track of snow accumulation
--- snowDepth in meters
function SeasonsWeather:updateSnowDepth()
    local seasonLengthFactor = math.max(9 / self.environment.daysPerSeason, 1.0)
    local currentTemp = self:getCurrentAirTemperature()
    local effectiveMeltTemp = math.max(currentTemp, 0) + math.max(self.soilTemp, 0)
    local windMeltFactor = 1 + math.max(self:getWindVelocity() - 5, 0) / 25
    local dropScale = self.handler.downfallUpdater.currentDropScale

    local julianDay = self.environment.daylight:getCurrentJulianDay()
    local dayTime = self.mission.environment.dayTime / 60 / 60 / 1000 --current time in hours
    local cloudCoverage = self.handler.cloudUpdater.currentCloudCoverage
    local solarRad = self.environment.daylight:getCurrentSolarRadiation(julianDay, dayTime, cloudCoverage) / 5

    local period = self.environment:periodAtDay(self.environment.currentDay, self.environment.daysPerSeason)
    local rainfall = self.data.rainfall[period]
    local rainProb = self.data.rainProbability[period]

    -- calculating snow melt as a function of radiation
    local snowMelt = math.max(0.001 * effectiveMeltTemp ) * (1 + (1 + solarRad) * seasonLengthFactor * windMeltFactor)

    -- melting snow
    if not self:getIsFreezing() then
        -- assume snow melts up to 50% faster if it rains
        self.meltedSnow = snowMelt * (1 + 0.5 * dropScale)
        self.snowDepth = self.snowDepth - self.meltedSnow

    -- accumulating snow
    elseif self:getIsFreezing() and dropScale > 0 then
        -- Initial value of 10 mm/hr accumulation rate. Higher rate when there is little snow to get the visual effect
        if self.snowDepth < 0 then
            self.snowDepth = 0
            self.snowHandler.height = 0
        elseif self.snowDepth > 0.06 then
            -- setting a maximum accumuation rate as safeguard
            local maxAcc = 1 / (self.environment.daysPerSeason * 24)
            local accumulation = math.min(rainfall / 9 / rainProb / 1000 * seasonLengthFactor * dropScale, maxAcc)
            self.snowDepth = self.snowDepth + accumulation
        else
            self.snowDepth = self.snowDepth + 31 / 1000
        end
    end

    -- We have seen games with extreme snow that never melts in time. To prevent this,
    -- we limit internal height to 60cm (visual height is limited to 48cm already)
    self.snowDepth = math.min(self.snowDepth, 0.60)

    self.snowHandler:setSnowHeight(self.snowDepth)
end

-- Weather event generator
-- days in weather events are according to base game
function SeasonsWeather:getWeatherEvent(day, prevEvent, cloudTransitionEvent)
    local event = SeasonsWeatherEvent:new()

    local dayForecast = self.forecast:getForecastForDay(day)
    local nextDayForecast = self.forecast:getForecastForDay(day + 1)

    local highTempPrev = self.highTempPrev

    local prevDayForecast = self.forecast:getForecastForDay(day - 1)
    if prevDayForecast ~= nil then
        highTempPrev = prevDayForecast.highTemp
    end

    event.n = math.random() -- random number for weather type determination

    event.startDay = dayForecast.day - self.environment.currentDayOffset -- days in handler need to be basegame days so they are always continious
    event.endDay = event.startDay
    event.startTime = prevEvent.endTime
    event.duration = SeasonsMathUtil.triDist(3 , 4 , 6)

    local season = dayForecast.season
    local period = self.environment:periodAtDay(event.startDay, self.environment.daysPerSeason)
    local pRain = self.data.rainProbability[period]
    local avgHighTemp = self.data.temperature[period]

    if cloudTransitionEvent then
        event.duration = 1
        event.n = math.min(pRain + 0.1, 1)
    end

    event.endTime = SeasonsMathUtil.truncate(event.startTime + event.duration, SeasonsWeatherEvent.TIME_TRUNCATE_DECIMALS)

    -- correcting endTime if event ends next day
    if event.endTime > 24 then
        event.endTime = event.endTime - 24
        event.endDay = event.endDay + 1
    end

    local startTemp = self.forecast:diurnalTemp(event.startDay, highTempPrev, dayForecast.lowTemp, dayForecast.highTemp, nextDayForecast.lowTemp)
    local endTemp = self.forecast:diurnalTemp(math.min(event.startTime + event.duration, 23.59), highTempPrev, dayForecast.lowTemp, dayForecast.highTemp, nextDayForecast.lowTemp)
    event.temperatureIndication = (startTemp + endTemp) / 2

    event.weatherType = self:getWeatherType(dayForecast.forecastType, event.temperatureIndication, avgHighTemp, event.n, pRain)
    if cloudTransitionEvent then
        event.weatherType = self.WEATHERTYPE_CLOUDY
    end

    event = self:updateWeatherEvent(event, prevEvent, dayForecast, pRain)

    --inserting cloud event for transitioning to and from event with precipitation
    local transitionEvent = nil
    if prevEvent.precipitationIntensity == 0 and event.precipitationIntensity > 0 and not cloudTransitionEvent then
        event.startTime = event.startTime + 1
        event.duration = event.duration - 1
        if event.startTime > 24 then
            event.startTime = event.startTime - 24
            event.startDay = event.startDay + 1
        end

        local cloudEvent = self:addCloudEvent(prevEvent)
        transitionEvent = cloudEvent
    elseif prevEvent.precipitationIntensity > 0 and event.precipitationIntensity == 0 and not cloudTransitionEvent then
        event = self:addCloudEvent(prevEvent)
    end

    return event, transitionEvent
end

-- determine the severity of weather event whether sunny or rain/snow
function calculateWeatherSeverity(n, p)
    if n <= p then
        return (p - n) / p
    else
        return 1 - (n - p) / (1 - p)
    end
end

function SeasonsWeather:calculateWindDirection(dirX, dirZ, change)
    local angle = math.atan2(dirX, dirZ) + math.rad(15 * change)

    return math.cos(angle), math.sin(angle)
end

function SeasonsWeather:updateWeatherEvent(event, prevEvent, dayForecast, pRain)
    local severity = calculateWeatherSeverity(event.n, pRain)

    -- if cloudy there are more cumulus clouds and less cirrus
    event.cirrusCloudDensityScale = severity
    if event.weatherType ~= SeasonsWeather.WEATHERTYPE_SUN then
        event.cirrusCloudDensityScale = severity * 0.2
        severity = (severity + 0.4 ) / 1.4
    end

    event.precipitationType = SeasonsWeather.PRECIPITATION_TYPES[event.weatherType + 1]
    event.precipitationIntensity = 0
    if event.precipitationType ~= nil then
        event.precipitationIntensity = severity
    end

    event.cloudCoverage = severity
    event.cloudTypeTo = severity / 2

    -- more fog if recent rain or with wet ground
    local fogFactor = math.max(math.max(1 - self.handler:getTimeSinceLastRain() / 48 * 60, 0), math.max(1 - self.soilWaterContent / 0.15, 0))
    event.fogScale = self.FOGSCALE * fogFactor

    if event.precipitationIntensity > 0 then
        event.cloudCoverage = 1
        event.cloudTypeTo = math.max(severity, 0.5)
    end

    if event.weatherType == SeasonsWeather.WEATHERTYPE_SUN then
        event.cloudCoverage = severity * 0.4
        event.cloudTypeTo = severity * 0.25
    end

    event.cloudTypeFrom = prevEvent.cloudTypeTo

    event.stormIntensity = 0
    if event.weatherType == self.WEATHERTYPE_THUNDER then
        event.stormIntensity = severity
    end

    event.windVelocity = dayForecast.windSpeed + (prevEvent.windVelocity - dayForecast.windSpeed) / 2 + (severity - 0.5) / 2 * self.forecast:getWindType(prevEvent.windVelocity)

    event.cirrusCloudSpeedFactor = 0
    if event.cirrusCloudDensityScale ~= 0 then
        event.cirrusCloudSpeedFactor = MathUtil.clamp((event.windVelocity - 3) / 10, 0, 1)
    end

    event.windDirX, event.windDirZ = self:calculateWindDirection(prevEvent.windDirX, prevEvent.windDirZ, (prevEvent.n - event.n))

    return event
end

-- cloud transition event to prevent rain from clear sky
function SeasonsWeather:addCloudEvent(prevEvent)
    local day = prevEvent.endDay + self.environment.currentDayOffset

    local firstForecastDay = self.forecast.items[1].day
    return self:getWeatherEvent(day, prevEvent, true)
end

function SeasonsWeather:getFirstEvent()
    return SeasonsWeatherEvent:new()
end

function SeasonsWeather:getWeatherType(forecastType, temp, avgHighTemp, n, pRain)

    if forecastType == SeasonsWeather.FORECAST_SUN then
        return SeasonsWeather.WEATHERTYPE_SUN
    elseif forecastType == SeasonsWeather.FORECAST_RAIN_SHOWERS or forecastType == SeasonsWeather.FORECAST_SNOW_SHOWERS then
        -- always leave 10% probability for sunny weather
        if n > 0.9 then
            return SeasonsWeather.WEATHERTYPE_SUN
        elseif n < pRain then
            if temp < 1 then
                return SeasonsWeather.WEATHERTYPE_SNOW
            else
                return SeasonsWeather.WEATHERTYPE_RAIN
            end
        else
            return SeasonsWeather.WEATHERTYPE_CLOUDY
        end

    elseif forecastType == SeasonsWeather.FORECAST_PARTLY_CLOUDY or forecastType == SeasonsWeather.FORECAST_CLOUDY then
        return SeasonsWeather.WEATHERTYPE_CLOUDY

    elseif forecastType == SeasonsWeather.FORECAST_RAIN or forecastType == SeasonsWeather.FORECAST_SNOW or forecastType == SeasonsWeather.FORECAST_SLEET then
        if n > pRain then
            return SeasonsWeather.WEATHERTYPE_CLOUDY
        else
            if temp < 1 then
                return SeasonsWeather.WEATHERTYPE_SNOW
            elseif temp > avgHighTemp and n < 0.1 then
                return SeasonsWeather.WEATHERTYPE_THUNDER
            else
                return SeasonsWeather.WEATHERTYPE_RAIN
            end
        end
    end
end

----------------------
-- Crop weather damage functions
----------------------

function SeasonsWeather:updateAverageSoilWaterContent()
    local oldWaterContent = self.averageSoilWaterContent
    local duration = self.environment.daysPerSeason * 24

    self.averageSoilWaterContent = oldWaterContent * (duration - 1) / duration + self.soilWaterContent / duration
end

function SeasonsWeather:getDroughtSeverity()
    if self.averageSoilWaterContent < 0.05 then
        return 1 -- max damage
    elseif self.averageSoilWaterContent >= 0.05 and self.averageSoilWaterContent < 0.08 then
        return 2
    elseif self.averageSoilWaterContent >= 0.08 and self.averageSoilWaterContent < 0.12 then
        return 3
    else
        return 4 -- no damage
    end
end

-- low air temp for the day that passed
function SeasonsWeather:updateLowAirTemp()
    local lowTemp = self.forecast:getCurrentItem().lowTemp

    if lowTemp < self.lowAirTemp then
        self.lowAirTemp = lowTemp
    end
end

-- http://www.fao.org/docrep/008/y7223e/y7223e0a.htm
-- returns 4 (no damage, 0 to -1 deg Celsius) to 1 (max damage, below -6 deg Celsius)
function SeasonsWeather:getFrostSeverity()
    return 4 - math.floor(MathUtil.clamp(self.lowAirTemp * - 0.5, 0, 3))
end

----------------------
-- Updaters
----------------------

---Update things that depend on the weather state, like pedestrians
function SeasonsWeather:updateWeatherConditionals()
    if self.forecast:getCurrentItem().lowTemp < 1 then
        if self.mission.pedestrianSystem ~= nil then
            self.mission.pedestrianSystem:setNightTimeRange(0, 0)
        end
    end
end

----------------------
-- Getters
----------------------

---Set whether crop moisture is enabled
function SeasonsWeather:setCropMoistureEnabled(enabled)
    self.cropMoistureEnabled = enabled
end

---Get whether crop moisture is enabled
function SeasonsWeather:getCropMoistureEnabled()
    return self.cropMoistureEnabled
end

---Get whether the ground is currently frozen
function SeasonsWeather:isGroundFrozen()
    -- Can be nil when called during loading which is done by the field NPCs
    return self.soilTemp ~= nil and self.soilTemp < 0
end

---Get whether crops are likely to be wet
function SeasonsWeather:isCropWet()
    if self.cropMoistureEnabled then
        return self.cropMoistureContent > 20 or self.handler:getTimeSinceLastRain() == 0
    else
        return self.handler:getTimeSinceLastRain() < 2 * 60
    end
end

---Get the current air temperature
function SeasonsWeather:getCurrentAirTemperature()
    local hour = self.mission.environment.currentHour
    local minute = self.mission.environment.currentMinute
    if hour == nil or minute == nil then
        -- These values in Environment must be nil sometime, otherwise this function would never return nil
        local timeHoursF = self.mission.environment.dayTime / (60 * 60 * 1000) + 0.0001
        hours = math.floor(timeHoursF)
        minutes = math.floor((timeHoursF - timeHours) * 60)
    end

    -- Caching
    if self.latestCurrentTemp ~= nil and self.latestCurrentTempHour == hour and self.latestCurrentTempMinute == minute then
        return self.latestCurrentTemp
    end

    self.latestCurrentTempHour = hour
    self.latestCurrentTempMinute = minute

    local dayForecast = self.forecast:getForecastForDay(self.environment.currentDay)
    local nextDayForecast = self.forecast:getForecastForDay(self.environment.currentDay + 1)
    self.latestCurrentTemp = self.forecast:diurnalTemp(hour, self.highTempPrev, dayForecast.lowTemp, dayForecast.highTemp, nextDayForecast.lowTemp)

    return self.latestCurrentTemp
end

---Get the current soil temperature
function SeasonsWeather:getCurrentSoilTemperature()
    return self.soilTemp
end

---Get the soil wetness. If the ground is frozen, wetness is always zero.
function SeasonsWeather:getSoilWetness()
    if self:isGroundFrozen() then
        return 0
    else
        return self.soilWaterContent
    end
end

---Generate a table with minimum soil temperatures over a year, by simulating the weather quickly.
-- If lowTemp < germTemp-1, it is too cold to germinate
function SeasonsWeather:getLowSoilTemperature()
    local lowSoilTemp = {}
    local soilTemp = {}

    local daysPerSeason = 9

    for i = 1,12 do
        lowSoilTemp[i] = -math.huge
    end

    -- run after loading data from xml so self.soilTemp will be initial value at this point
    soilTemp[1] = self.data.startValues.soilTemp

    -- building table with hard coded 9 day season
    for i = 2, 4 * daysPerSeason do
        local period = self.environment:periodAtDay(i, daysPerSeason)
        local periodPrevDay = self.environment:periodAtDay(i - 1, daysPerSeason)

        local averageDailyMaximum = self.data.temperature[period]

        local lowTemp, highTemp = self.model:calculateAirTemp(averageDailyMaximum, true)

        soilTemp[i], _ = self.model:calculateSoilTemp(soilTemp[i - 1], soilTemp[i - 1], lowTemp, highTemp, 0, daysPerSeason, true)
        if soilTemp[i] > lowSoilTemp[period] then
            lowSoilTemp[period] = soilTemp[i]
        end

        if period > periodPrevDay and soilTemp[i] > soilTemp[i - 1] then
            lowSoilTemp[period - 1] = soilTemp[i]
        end
    end

    return lowSoilTemp
end

---Get the maximum soil temperature from yesterday
function SeasonsWeather:getYesterdayMaxSoilTemp()
    return Utils.getNoNil(self.yesterdaySoilTemp, 0)
end

function SeasonsWeather:getForecast(day, time, duration)
    local daysUntil = day - self.environment.currentDay
    local std = 0.15 + 0.05 * daysUntil
    local uncertaintyFactor = std / 0.15

    if not self.forecast.FORECAST_UNCERTAINTY then
        uncertaintyFactor = 0
    end

    if daysUntil > 1 or duration == 24 then
        -- use forecast
        local info = ListUtil.copyTable(self.forecast:getForecastForDay(day))

        info.averageTemp = (info.lowTemp + info.highTemp) / 2
        local tempRange = info.averageTemp - info.lowTemp
        info.lowTemp = info.averageTemp - tempRange * (1 + info.tempUncertainty * uncertaintyFactor)
        info.highTemp = info.averageTemp + tempRange * (1 + info.tempUncertainty * uncertaintyFactor)

        info.windSpeed = info.windSpeed * (1 + info.windUncertainty * uncertaintyFactor)

        local temp = self.forecast:diurnalTemp(info.startTimeIndication, info.highTemp, info.lowTemp, info.highTemp, info.lowTemp)
        local period = self.environment:periodAtDay(day)
        local rainProb = self.data.rainProbability[period]

        info.p = MathUtil.clamp(info.p * (1 + info.weatherTypeUncertainty * uncertaintyFactor), 0, 1)
        info.forecastType, _ = self.forecast:getForecastType(day, info.p, temp, info.averageTemp, info.windSpeed)

        info.precipitationAmount = 0
        info.precipitationChance = 0

        if self:getRainScale(info.forecastType) ~= 0 then
            local realPrecipitationAmount = self.model:getRainAmount(day, self:getRainScale(info.forecastType)) * 24
            local maxPrecipitationAmount = self.model:getRainAmount(day, 1) * 24
            info.precipitationAmount = math.max(realPrecipitationAmount + maxPrecipitationAmount * info.precipitationUncertainty * uncertaintyFactor, 1)
            info.precipitationChance = math.max(MathUtil.round(SeasonsMathUtil.normCDF(rainProb, info.p, std), 1), 0.1)
        end

        return info
    elseif duration > 24 or (duration == 24 and time ~= 0) then
        return nil

    else
        local hoursUntil = math.max(time - self.mission.environment.currentHour, 0)
        if daysUntil > 0 then
            hoursUntil = time - self.mission.environment.currentHour + daysUntil * 24
        end

        local dayForecast = self.forecast:getForecastForDay(day)
        local nextDayForecast = self.forecast:getForecastForDay(day + 1)

        local info = {}

        local highTempPrev = self.highTempPrev
        if day ~= self.environment.currentDay then
            local prevDayForecast = self.forecast:getForecastForDay(day - 1)
            highTempPrev = prevDayForecast.highTemp
        end

        -- Find the events within the period
        local baseDay = day - self.environment.currentDayOffset -- basegame day we want in events
        local events = self:getEventsInPeriod(baseDay, time, duration)

        -- #events can't be nil normally, unless it is looking too far away.
        -- Force a forecast lookup instead
        if #events == 0 then
            return self:getForecast(day, 0, 24)
        end

        uncertaintyFactor = uncertaintyFactor * hoursUntil / 24
        if not self.forecast.FORECAST_UNCERTAINTY then
            uncertaintyFactor = 0
        end

        -- Find temps
        local startTemp = self.forecast:diurnalTemp(time, highTempPrev, dayForecast.lowTemp, dayForecast.highTemp, nextDayForecast.lowTemp)
        local endTemp = self.forecast:diurnalTemp(time + duration, highTempPrev, dayForecast.lowTemp, dayForecast.highTemp, nextDayForecast.lowTemp)
        info.averageTemp = (startTemp + endTemp) / 2

        local tempRange = info.averageTemp - math.min(startTemp, endTemp)
        info.lowTemp = info.averageTemp - tempRange * (1 + dayForecast.tempUncertainty * uncertaintyFactor)
        info.highTemp = info.averageTemp + tempRange * (1 + dayForecast.tempUncertainty * uncertaintyFactor)

        local eventDuration = 3

        local n = MathUtil.clamp(events[1].n * (1 + dayForecast.weatherTypeUncertainty * uncertaintyFactor), 0, 1)
        local period = self.environment:periodAtDay(day)
        local avgHighTemp = self.data.temperature[period]
        local rainProb = self.data.rainProbability[period]

        info.weatherType = self:getWeatherType(dayForecast.forecastType, info.averageTemp, avgHighTemp, n, rainProb)
        local severity = calculateWeatherSeverity(n, rainProb)

        local realPrecipitationAmount = self.model:getRainAmount(events[1].startDay, events[1].precipitationIntensity) * eventDuration
        local maxPrecipitationAmount = self.model:getRainAmount(events[1].startDay, 1) * eventDuration

        local precipitationType = SeasonsWeather.PRECIPITATION_TYPES[info.weatherType + 1]
        local realPrecipitationAmount = 0
        info.precipitationAmount = 0
        info.precipitationChance = 0

        if precipitationType ~= nil then
            realPrecipitationAmount = self.model:getRainAmount(events[1].startDay, severity) * eventDuration
            info.precipitationAmount = math.max(realPrecipitationAmount * (1 + dayForecast.precipitationUncertainty * uncertaintyFactor), 0.1)
            info.precipitationChance = math.max(MathUtil.round(SeasonsMathUtil.normCDF(rainProb, n, std), 1), 0.1)
        end

        info.windSpeed = events[1].windVelocity * (1 + dayForecast.windUncertainty * uncertaintyFactor)

        info.dryingPotential = 0
        if self.cropDryingForecast ~= nil then
            for i = 1,duration do
                info.dryingPotential = info.dryingPotential + self.cropDryingForecast[hoursUntil + i]
                -- log(day, time, info.dryingPotential, self.cropDryingForecast[hoursUntil + i])
            end
        end

        return info
    end
end

function SeasonsWeather:cropDryingSimulation(cropMoistureContent, day, hour)
    -- It is possible that due to lag, the hour is e.g. '9' but the time is 9.5, deleting an event that contains 9.
    -- Ignore these cases
    local firstEvent = self.handler.events[1]
    if self.handler:getEventAtTime(day - self.environment.currentDayOffset, hour) == nil then
        return
    end

    local delta = 0
    local prevCropMoistureContent = cropMoistureContent
    local highTempPrev = self.highTempPrev
    local forecast = self.forecast:getForecastForDay(day)
    local nextDayForecast = self.forecast:getForecastForDay(day + 1)
    local futureDryingPotential = {}

    -- simulate for the next 48 hours
    for i = 1, 48 do
        hour = hour + 1
        if hour >= 24 then
            hour = hour - 24
            day = day + 1
            highTempPrev = forecast.highTemp
            forecast = self.forecast:getForecastForDay(day)
        end

        local julianDay = self.environment:julianDay(day)
        local event = self.handler:getEventAtTime(day - self.environment.currentDayOffset, hour)

        local currentTemp = self.forecast:diurnalTemp(hour, highTempPrev, forecast.lowTemp, forecast.highTemp, nextDayForecast.lowTemp)
        -- When not generated far enough into the future these events don't exist yet
        if event ~= nil then
            local timeSinceLastRain = 0

            if event.precipitationIntensity == 0 then
                timeSinceLastRain = 1
            end

            cropMoistureContent, delta = self.model:updateCropMoistureContent(cropMoistureContent, julianDay, hour, currentTemp, forecast.lowTemp, event.windVelocity, event.cloudCoverage, event.precipitationIntensity, event.fogScale, timeSinceLastRain)
            table.insert(futureDryingPotential, delta)
        end
    end

    return futureDryingPotential
end

function SeasonsWeather:getRainScale(forecastType)
    if forecastType == SeasonsWeather.FORECAST_RAIN_SHOWERS or forecastType == SeasonsWeather.FORECAST_SNOW_SHOWERS then
        return 0.3
    elseif forecastType == SeasonsWeather.FORECAST_RAIN or forecastType == SeasonsWeather.FORECAST_SNOW or forecastType == SeasonsWeather.FORECAST_SLEET or forecastType == SeasonsWeather.FORECAST_THUNDER then
        return 0.9
    else
        return 0
    end
end

---Get a list of events within given time slot
function SeasonsWeather:getEventsInPeriod(baseDay, time, duration)
    local events = {}
    local endTime = time + duration

    for _, event in ipairs(self.handler.events) do
        if event.startDay <= baseDay and event.endDay >= baseDay then
            -- We need to check for days a lot because the hours reset. An event can start and end at 6
            -- but that does not mean a time at 9 is not within the event: it could be a day-long event

            if baseDay == event.startDay and baseDay == event.endDay then -- Event is in 1 day only, and in same day
                if (time > event.startTime and time < event.endTime) or (endTime > event.startTime and endTime < event.endTime) then
                    table.insert(events, event)
                end
            elseif baseDay == event.startDay then -- In first day of event, start part only
                if time > event.startTime or endTime > event.startTime then
                    table.insert(events, event)
                end
            elseif baseDay == event.endDay then -- In last day of event, end part only
                if time < event.endTime or endTime < event.endTime then
                    table.insert(events, event)
                end
            else
                -- Covers whole event
                table.insert(events, event)
                break
            end
        end

        -- Won't find later
        if event.startDay > baseDay then
            break
        end
    end

    return events
end

---Convert meters per second to Beaufort scale
function SeasonsWeather:getBeaufortScale(ms)
    return MathUtil.round(math.pow(ms / 0.836, 0.6666), 0)
end

---Get current state of downfall
function SeasonsWeather:getDownfallState()
    return self.handler.downfallUpdater:getCurrentValues()
end

---Get current state of downfall including fading info (left and right plus fade info)
function SeasonsWeather:getDownfallFadeState()
    return self.handler.downfallUpdater:getCurrentFadeState()
end

---Get whether it is currently freezing outside
function SeasonsWeather:getIsFreezing()
    local temp = self:getCurrentAirTemperature()
    if temp == nil then
        return false
    end
    return math.floor(temp) <= 0
end

---Returns true when the current weatherType is snow, false otherwise
function SeasonsWeather:isSnowing()
    local event = self.handler:getCurrentEvent()
    if event == nil then
        return false
    end

    return event.weatherType == SeasonsWeather.WEATHERTYPE_SNOW
end

---Get current wind velocity. 0-27m/s
function SeasonsWeather:getWindVelocity()
    local _, _, velocity = self.handler.windUpdater:getCurrentValues()
    return velocity
end

---Get whether a storm is active
function SeasonsWeather:getIsStorming()
    return self.handler.stormUpdater:getCurrentValues() > 0
end

---Get the rot/dry factor
function SeasonsWeather:getRotDryFactor()
    return self.rotDryFactor
end

---Reset the rot/dry factor
function SeasonsWeather:resetRotDryFactor()
    self.rotDryFactor = 0
end

----------------------
-- Injections
----------------------

---Insert the new weather handling into the environment
function SeasonsWeather.inj_environment_new(environment, superFunc, xmlFilename)
    -- Disable initialization of the vanilla weather
    local old = Weather.new
    Weather.new = function() return { setIsRainAllowed = function() end, load = function() end } end

    local self = superFunc(environment, xmlFilename)

    -- Reset class
    Weather.new = old

    -- Use our own weather system
    self.weather = g_seasons.weather.handler

    return self
end

---Use Seasons weather types and more icons
function SeasonsWeather.inj_gameInfoDisplay_getWeatherUVs(gameInfoDisplay, superFunc)
    return {
        [SeasonsWeather.WEATHERTYPE_SUN]        = GameInfoDisplay.UV.WEATHER_ICON_CLEAR,
        [SeasonsWeather.WEATHERTYPE_CLOUDY]     = GameInfoDisplay.UV.WEATHER_ICON_CLOUDY,
        [SeasonsWeather.WEATHERTYPE_RAIN]       = GameInfoDisplay.UV.WEATHER_ICON_RAIN,
        [SeasonsWeather.WEATHERTYPE_SNOW]       = GameInfoDisplay.UV.WEATHER_ICON_SNOW,
        [SeasonsWeather.WEATHERTYPE_FOG]        = GameInfoDisplay.UV.WEATHER_ICON_FOG,
        [SeasonsWeather.WEATHERTYPE_THUNDER]    = GameInfoDisplay.UV.WEATHER_ICON_THUNDER,
        [SeasonsWeather.WEATHERTYPE_HAIL]       = GameInfoDisplay.UV.WEATHER_ICON_HAIL,
    }
end

function SeasonsWeather.inj_gameInfoDisplay_getWeatherStates(gameInfoDisplay, superFunc)
    return g_seasons.weather.handler:getHUDInfo()
end

----------------------
-- Wind turbine affected by wind speed and direction
----------------------

function SeasonsWeather:inj_windTurbinePlaceable_updateHeadRotation(superFunc)
    local x, z, _, _ = g_seasons.weather.handler.windUpdater:getCurrentValues()
    local angle = math.atan2(x, z)

    -- local eventAngle = math.atan2(g_seasons.weather.handler.events[1].windDirX, g_seasons.weather.handler.events[1].windDirZ)
    -- local _,y1,_ = getWorldRotation(self.headNode)
    -- log(eventAngle, angle, y1)

    local dx,_,dz = worldDirectionToLocal(self.nodeId, math.sin(angle),0,math.cos(angle))
    setDirection(self.headNode, dx,0,dz, 0,1,0)
end

function SeasonsWeather:inj_windTurbinePlaceable_update(superFunc, dt)
    local _, _, windSpeed, _ = g_seasons.weather.handler.windUpdater:getCurrentValues()
    -- not running at low wind speeds and shutting down at high wind speeds
    local speed = MathUtil.clamp(windSpeed - 3, 0, 8)
    if windSpeed > 25 then
        speed = 0
    end

    if self.rotationNode ~= 0 then
        if speed > 0 then
            rotate(self.rotationNode, 0, 0, -0.0005 * (speed + 3) * dt)
            self:updateHeadRotation()
        end

        self:raiseActive()
    end
end

function SeasonsWeather:inj_windTurbinePlaceable_hourChanged()
    local _, _, windSpeed, _ = g_seasons.weather.handler.windUpdater:getCurrentValues()
    local effectRatio = MathUtil.clamp(windSpeed - 3, 0, 8) / 8
    local income = self.incomePerHour

    if windSpeed < 25 then
        income = income * effectRatio
    else
        income = 0
    end

    if self.isServer and income > 0 then
        g_currentMission:addMoney(income, self:getOwnerFarmId(), MoneyType.PROPERTY_INCOME, true)
    end
end

----------------------
-- Console commands
----------------------

---Add a basic weather event for the next hour
function SeasonsWeather:consoleCommandAddEvent(typ, intensity, offset)
    if typ == nil or intensity == nil then
        return "Usage: rmWeatherAddEvent rain/snow/hail 0-1 [offset]"
    end

    local offset = tonumber(offset) or 0

    local currentEvent = self.handler:getCurrentEvent()
    local nextEvent = self.handler:getNextEvent()

    -- Create new event for 1 hour
    local newEvent = SeasonsWeatherEvent:new()
    newEvent.startDay = currentEvent.startDay
    newEvent.startTime = math.ceil(self.mission.environment.currentHour + 0.5 + offset)
    if newEvent.startTime == 24 then
        newEvent.startDay = newEvent.startDay + 1
        newEvent.startTime = 0
    end

    newEvent.endTime = newEvent.startTime + 1
    newEvent.endDay = newEvent.startDay
    if newEvent.endTime == 24 then
        newEvent.endTime = 0
        newEvent.endDay = newEvent.endDay + 1
    end

    if typ == "rain" then
        newEvent.precipitationIntensity = tonumber(intensity)
        newEvent.precipitationType = typ
        newEvent.weatherType = SeasonsWeather.WEATHERTYPE_RAIN
    elseif typ == "snow" then
        newEvent.precipitationIntensity = tonumber(intensity)
        newEvent.precipitationType = typ
        newEvent.weatherType = SeasonsWeather.WEATHERTYPE_SNOW
    elseif typ == "hail" then
        newEvent.precipitationIntensity = tonumber(intensity)
        newEvent.precipitationType = typ
        newEvent.weatherType = SeasonsWeather.WEATHERTYPE_HAIL
    end

    table.insert(self.handler.events, 2, newEvent)

    -- Cut the current event down to stop at end of the hour
    local originalEndDay, originalEndTime = currentEvent.endDay, currentEvent.endTime
    currentEvent.endDay = newEvent.startDay
    currentEvent.endTime = newEvent.startTime

    -- Always set next event start time to end of new event (easiest)
    nextEvent.startTime = newEvent.endTime
    nextEvent.startDay = newEvent.endDay

    if nextEvent.startTime == nextEvent.endTime and nextEvent.startDay == nextEvent.endDay then
        List.removeElement(self.handler.events, nextEvent)
    end

    return "Added new event from " .. tostring(newEvent.startTime) .. " to " .. tostring(newEvent.endTime)
end

function SeasonsWeather:consoleCommandSetWindVelocity(velocity, duration)
    if velocity == nil then
        return "Usage: velocity (in m/s, from 0-27) [switch duration]"
    end

    velocity = tonumber(velocity)
    duration = Utils.getNoNil(tonumber(duration), 1000 * 60 * 5)

    local x, z, _, cirrus = self.handler.windUpdater:getCurrentValues()
    self.handler.windUpdater:setTargetValues(x, z, velocity, cirrus, duration)

    return "Switching to " .. tostring(velocity) .. "m/s in " .. (duration / 1000) .. " ingame seconds"
end
