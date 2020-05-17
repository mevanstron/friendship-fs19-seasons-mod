----------------------------------------------------------------------------------------------------
-- SeasonsWeatherHandler
----------------------------------------------------------------------------------------------------
-- Purpose:  Handles actual weather visuals and effects
--
-- Note that this re-implements the Weather class of vanilla and is directly called by the
-- vanille environment as well.
--
-- This class handles the change of clouds, downfall, etc according to known weather forecast.
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsWeatherHandler = {}

local SeasonsWeatherHandler_mt = Class(SeasonsWeatherHandler)

function SeasonsWeatherHandler:new(mission, environment, weatherInfo, messageCenter, modDirectory)
    self = setmetatable({}, SeasonsWeatherHandler_mt)

    self.mission = mission
    self.environment = environment
    self.weatherInfo = weatherInfo
    self.messageCenter = messageCenter
    self.modDirectory = modDirectory

    self.timeSinceLastRain = math.huge -- ms
    self.airTemperature = 1

    -- Updaters that handle the engine calls from vanilla
    self.cloudUpdater = CloudUpdater:new()
    self.fogUpdater = FogUpdater:new()
    self.windUpdater = WindUpdater:new()
    self.weatherFrontUpdater = WeatherFrontUpdater:new(self.windUpdater)
    self.downfallUpdater = SeasonsDownfallUpdater:new(messageCenter)
    self.stormUpdater = SeasonsStormUpdater:new(messageCenter)

    self.windUpdater:addWindChangedListener(self.cloudUpdater)
    self.windUpdater:addWindChangedListener(self.downfallUpdater)

    self.events = {} -- List of weather events

    local noop = function () end

    -- Ignore the versions from vanilla
    self.saveToXMLFile = noop
    self.loadFromXMLFile = noop

    -- This is a value used by FSBaseMission when syncing. Setting it to an empty table prevents nil errors when joining
    self.fog = {}

    -- Use constants because we don't user superfunc and it is more performance. Kills moddability by 3rd parties
    -- but that would never work anyways here.
    SeasonsModUtil.overwrittenConstant(WeatherAddObjectEvent, "run", SeasonsWeatherHandler.inj_weatherAddObjectEvent_run)
    SeasonsModUtil.overwrittenConstant(WeatherAddObjectEvent, "writeStream", SeasonsWeatherHandler.inj_weatherAddObjectEvent_writeStream)
    SeasonsModUtil.overwrittenConstant(WeatherAddObjectEvent, "readStream", SeasonsWeatherHandler.inj_weatherAddObjectEvent_readStream)

    -- In basegame, wind is done using wind objects. We have it enclosed in the actual weather events already.
    -- We can't prevent them from sending (sendEvent does not allow nil as input) so we need to block them from
    -- sending anything instead.
    SeasonsModUtil.overwrittenConstant(WindObjectChangedEvent, "run", noop)
    SeasonsModUtil.overwrittenConstant(WindObjectChangedEvent, "writeStream", noop)
    SeasonsModUtil.overwrittenConstant(WindObjectChangedEvent, "readStream", noop)
    -- Same for fog
    SeasonsModUtil.overwrittenConstant(FogStateEvent, "run", noop)
    SeasonsModUtil.overwrittenConstant(FogStateEvent, "writeStream", noop)
    SeasonsModUtil.overwrittenConstant(FogStateEvent, "readStream", noop)

    -- Add state exchange to the wind and cloud updater
    SeasonsModUtil.overwrittenConstant(WindUpdater, "writeStream", SeasonsWeatherHandler.inj_windUpdater_writeStream)
    SeasonsModUtil.overwrittenConstant(WindUpdater, "readStream", SeasonsWeatherHandler.inj_windUpdater_readStream)
    SeasonsModUtil.overwrittenConstant(CloudUpdater, "writeStream", SeasonsWeatherHandler.inj_cloudUpdater_writeStream)
    SeasonsModUtil.overwrittenConstant(CloudUpdater, "readStream", SeasonsWeatherHandler.inj_cloudUpdater_readStream)

    return self
end

function SeasonsWeatherHandler:load()
    self.downfallUpdater:addDownfallType("rain", "resources/environment/downfall/rain.i3d", self.modDirectory)
    self.downfallUpdater:addDownfallType("snow", "resources/environment/downfall/snow.i3d", self.modDirectory)
    self.downfallUpdater:addDownfallType("hail", "resources/environment/downfall/hail.i3d", self.modDirectory)

    self.stormUpdater:addLightningObject("resources/environment/lightning/lightning.i3d", self.modDirectory)

    self:init()

    self.messageCenter:subscribe(MessageType.TIMESCALE_CHANGED, self.onTimeScaleChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.HOUR_CHANGED_FIX, self.onHourChanged, self)
end

function SeasonsWeatherHandler:delete()
    self.cloudUpdater:delete()
    self.fogUpdater:delete()
    self.windUpdater:delete()
    self.weatherFrontUpdater:delete()
    self.downfallUpdater:delete()

    self.messageCenter:unsubscribeAll(self)
end

function SeasonsWeatherHandler:saveToSavegame(xmlFile)
    local key = "seasons.weather"

    setXMLInt(xmlFile, key.."#timeSinceLastRain", MathUtil.msToMinutes(self.timeSinceLastRain))

    for i, event in ipairs(self.events) do
        event:saveToXML(xmlFile, string.format("seasons.weather.events.event(%d)", i - 1))
    end

    self.fogUpdater:saveToXMLFile(xmlFile, "seasons.weather.fog")
end

function SeasonsWeatherHandler:loadFromSavegame(xmlFile)
    local timeSinceLastRain = getXMLInt(xmlFile, "seasons.weather#timeSinceLastRain")
    if timeSinceLastRain ~= nil then
        self.timeSinceLastRain = MathUtil.minutesToMs(timeSinceLastRain)
    end

    local i = 0
    while true do
        local key = string.format("seasons.weather.events.event(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local event = SeasonsWeatherEvent:new()
        if event:loadFromXML(xmlFile, key) then
            table.insert(self.events, event)
        else
            event:delete()
            Logging.warning("Invalid weather event was skipped")
        end

        i = i + 1
    end

    self.fogUpdater:loadFromXMLFile(xmlFile, "seasons.weather.fog")

    self:init()
end

function SeasonsWeatherHandler:init(state)
    local currentEvent = self:getCurrentEvent()

    if currentEvent ~= nil then
        if state == nil then
            currentEvent:activate(self.cloudUpdater, self.windUpdater, self.fogUpdater, self.weatherFrontUpdater, self.downfallUpdater, self.stormUpdater, 0)
        else
            log("TODO: use state to set all updaters")
        end
    end
end

---Update, called from vanilla environment
function SeasonsWeatherHandler:update(dt)
    local scaledDt = dt * self.mission.missionInfo.timeScale

    local currentEvent = self.events[1] -- assume there is an event

    local time = self.environment:getTimeInHours()
    local day = self.mission.environment.currentDay

    if day > currentEvent.endDay or (day == currentEvent.endDay and time > currentEvent.endTime) then
        local duration = 1000 * 60 * 30 -- 30min

        local currentEvent = self.events[1]
        local nextEvent = self.events[2]

        if nextEvent == nil then
            log("NEXT EVENT IS NIL")
            log("TIME", time, day)
            print_r(self.events)
        end

        currentEvent:deactivate(duration)
        nextEvent:activate(self.cloudUpdater, self.windUpdater, self.fogUpdater, self.weatherFrontUpdater, self.downfallUpdater, self.stormUpdater, duration)

        -- Remove old
        table.remove(self.events, 1)
    end

    self.cloudUpdater:update(scaledDt)
    self.windUpdater:update(scaledDt)
    self.fogUpdater:update(scaledDt)
    self.weatherFrontUpdater:update(scaledDt)
    self.downfallUpdater:update(scaledDt)
    self.stormUpdater:update(scaledDt)

    if self.downfallUpdater:getCurrentValues() > 0.01 then
        self.timeSinceLastRain = 0

        self:updateDownfallForTemperature(self.airTemperature)
    else
        self.timeSinceLastRain = self.timeSinceLastRain + scaledDt
    end
end

function SeasonsWeatherHandler:updateDownfallForTemperature(temperature)
    local _, typeName = self.downfallUpdater:getCurrentValues()

    if temperature <= 0 and typeName == "rain" then
        if not self.switchingDownfallType then
            self.downfallUpdater:switchDownfallType("rain", "snow")
        end

        self.switchingDownfallType = true

        -- Set current event icon
        local event = self:getCurrentEvent()
        event.weatherType = SeasonsWeather.WEATHERTYPE_SNOW
    elseif temperature > 0 and typeName == "snow" then
        if not self.switchingDownfallType then
            self.downfallUpdater:switchDownfallType("snow", "rain")
        end

        self.switchingDownfallType = true

        -- Set current event icon
        local event = self:getCurrentEvent()
        event.weatherType = SeasonsWeather.WEATHERTYPE_RAIN
    else
        self.switchingDownfallType = false
    end
end

----------------------
-- Events
----------------------

function SeasonsWeatherHandler:onHourChanged()
end

---Update the timescale.
function SeasonsWeatherHandler:onTimeScaleChanged()
    self.cloudUpdater:setTimeScale(self.mission.missionInfo.timeScale)
end

----------------------
-- Setters
----------------------

---Add a new event to the end of the event list
function SeasonsWeatherHandler:appendEvent(event)
    local lastEvent = self.events[#self.events]

    if lastEvent ~= nil then
        if event.startDay ~= lastEvent.endDay or math.abs(event.startTime - lastEvent.endTime) > 0.0001 then
            Logging.error("New weather event does not attach to the last event in the queue. Match start and end times. %f vs %f", event.startTime, lastEvent.endTime)
            printCallstack()
            return false
        end
    end

    table.insert(self.events, event)

    return true
end

---Remove all events
function SeasonsWeatherHandler:clearEvents()
    self.events = {}
end

----------------------
-- Getters
----------------------

---Get all scheduled events
function SeasonsWeatherHandler:getEvents()
    return self.events
end

---Get the current event
function SeasonsWeatherHandler:getCurrentEvent()
    return self.events[1]
end

---Get the event next up.
function SeasonsWeatherHandler:getNextEvent()
    return self.events[2]
end

---Get the rainfall scale, 0 if none
function SeasonsWeatherHandler:getRainFallScale()
    local dropScale, downfallType = self.downfallUpdater:getCurrentValues()
    return dropScale
end

---Get the time since last rain. Returns 0 if it is currently raining
function SeasonsWeatherHandler:getTimeSinceLastRain()
    if self.forcedRainIndication ~= nil then
        return self.forcedRainIndication
    end

    return MathUtil.msToMinutes(self.timeSinceLastRain)
end

-- TODO: use our own ground wetness
function SeasonsWeatherHandler:getGroundWetness()
    return self.getSoilWetnessCb()
end

---Get whether there is currently any precipitation
function SeasonsWeatherHandler:getIsRaining()
    return self:getCurrentEvent().precipitationIntensity > 0
end

---Get the weather for the HUD (unused as its functionality is overwritten. Implemented for compatibility with mods)
function SeasonsWeatherHandler:getWeatherTypeAtTime(day, dayTime)
    local event = self:getEventAtTime(day, dayTime)

    if event ~= nil then
        return event.weatherType
    end

    return SeasonsWeather.WEATHERTYPE_SUN
end

---Get the event at given day and time *unadjusted, vanilla day)
function SeasonsWeatherHandler:getEventAtTime(day, dayTime)
    for _, event in ipairs(self.events) do

        if day >= event.startDay and day <= event.endDay then
            if day == event.startDay then
                if dayTime > event.startTime then
                    return event
                end
            elseif day == event.endDay then
                if dayTime <= event.endTime then
                    return event
                end
            else -- Somewhere in between
                return event
            end
        end

        -- Will not ever find it
        if event.startDay > day then
            return nil
        end
    end

    return nil
end

---Get current cloud coverage. Used for lighting.
function SeasonsWeatherHandler:getGlobalCloudCoverate()
    local _, _, _, currentCloudCoverage = self.cloudUpdater:getCurrentValues()
    return currentCloudCoverage
end

---Wind speed used for modelling temperatures
function SeasonsWeatherHandler:getCurrentWindSpeed()
    return self.windUpdater.currentVelocity
end

function SeasonsWeatherHandler:getHUDInfo()
    local event1, event2 = self.events[1], self.events[2]
    if event2 == nil then
        return nil
    end

    local day, time = self.mission.environment.currentDay, self.environment:getTimeInHours()

    -- If there is an event within the next 6 hours, show that too
    if event2.startDay == day and event2.startTime < time + 6 then
        return event1.weatherType, event2.weatherType
    else
        return event1.weatherType
    end
end

function SeasonsWeatherHandler:setRainIndicationForced(forced, value)
    if forced then
        self.forcedRainIndication = value
    else
        self.forcedRainIndication = nil
    end
end

function SeasonsWeatherHandler:setSoilWetnessFunction(fun)
    self.getSoilWetnessCb = fun
end

function SeasonsWeatherHandler:setAirTemperature(temperature)
    self.airTemperature = temperature
end

----------------------
-- Injections
----------------------

-- Multiplayer
----------------------

---This event is already called by the mission when player joins. Easiest to lift on it because we can't prevent them from sending
function SeasonsWeatherHandler.inj_weatherAddObjectEvent_writeStream(event, streamId, connection)
    local handler = g_seasons.weather.handler

    local events
    if event.isInitialSync then
        events = handler.events
    else
        events = event.instances -- from initializer
    end
    streamWriteBool(streamId, event.isInitialSync)

    streamWriteUInt8(streamId, #events)
    for _, event in ipairs(events) do
        event:writeStream(streamId, connection)
    end

    if event.isInitialSync then
        handler.cloudUpdater:writeStream(streamId, connection)
        handler.windUpdater:writeStream(streamId, connection)
        handler.downfallUpdater:writeStream(streamId, connection)
        handler.stormUpdater:writeStream(streamId, connection)
    end
end

function SeasonsWeatherHandler.inj_weatherAddObjectEvent_readStream(event, streamId, connection)
    event.isInitialSync = streamReadBool(streamId)
    event.instances = {}

    local num = streamReadUInt8(streamId)
    for i = 1, num do
        local weatherEvent = SeasonsWeatherEvent:new()

        weatherEvent:readStream(streamId, connection)

        table.insert(event.instances, weatherEvent)
    end

    if event.isInitialSync then
        local handler = g_seasons.weather.handler

        handler.cloudUpdater:readStream(streamId, connection)
        handler.windUpdater:readStream(streamId, connection)
        handler.downfallUpdater:readStream(streamId, connection)
        handler.stormUpdater:readStream(streamId, connection)
    end

    event:run(connection)
end

function SeasonsWeatherHandler.inj_weatherAddObjectEvent_run(event, connection)
    local handler = g_seasons.weather.handler

    if event.isInitialSync then
        handler.events = event.instances
        handler:init(event.state) -- TODO
    else
        for _, e in ipairs(event.instances) do
            handler:appendEvent(e)
        end
    end
end

---Write state of wind updater so it matches once a player joins. Current weather influences weather state values.
function SeasonsWeatherHandler.inj_windUpdater_writeStream(updater, streamId, connection)
    local maxBitValue = (2 ^ 8) - 1
    local function writePercentage(value)
        local value = MathUtil.clamp(value * maxBitValue, 0, maxBitValue)
        streamWriteUIntN(streamId, value, 8)
    end

    writePercentage(updater.alpha)
    streamWriteInt32(streamId, updater.duration)

    writePercentage((updater.lastDirX + 1) / 2)
    writePercentage((updater.lastDirZ + 1) / 2)
    writePercentage(updater.lastVelocity / WindUpdater.MAX_SPEED)
    writePercentage(updater.lastCirrusSpeedFactor)

    writePercentage((updater.targetDirX + 1) / 2)
    writePercentage((updater.targetDirZ + 1) / 2)
    writePercentage(updater.targetVelocity / WindUpdater.MAX_SPEED)
    writePercentage(updater.targetCirrusSpeedFactor)
end

function SeasonsWeatherHandler.inj_windUpdater_readStream(updater, streamId, connection)
    local maxBitValue = (2 ^ SeasonsWeatherEvent.SEND_BITS_PERCENTAGE) - 1
    local function readPercentage()
        local value = streamReadUIntN(streamId, SeasonsWeatherEvent.SEND_BITS_PERCENTAGE)
        return value / maxBitValue
    end

    updater.alpha = readPercentage()
    updater.duration = streamReadInt32(streamId)

    updater.lastDirX = readPercentage() * 2 - 1
    updater.lastDirZ = readPercentage() * 2 - 1
    updater.lastVelocity = readPercentage() * WindUpdater.MAX_SPEED
    updater.lastCirrusSpeedFactor = readPercentage()

    updater.targetDirX = readPercentage() * 2 - 1
    updater.targetDirZ = readPercentage() * 2 - 1
    updater.targetVelocity = readPercentage() * WindUpdater.MAX_SPEED
    updater.targetCirrusSpeedFactor = readPercentage()
end

function SeasonsWeatherHandler.inj_cloudUpdater_writeStream(updater, streamId, connection)
    local maxBitValue = (2 ^ 8) - 1
    local function writePercentage(value)
        local value = MathUtil.clamp(value * maxBitValue, 0, maxBitValue)
        streamWriteUIntN(streamId, value, 8)
    end

    writePercentage(updater.alpha)
    streamWriteInt32(streamId, updater.duration)

    writePercentage(updater.lastCloudTypeFrom)
    writePercentage(updater.lastCloudTypeTo)
    writePercentage(updater.lastCirrusCloudDensityScale)
    writePercentage(updater.lastCloudCoverage)

    writePercentage(updater.targetCloudTypeFrom)
    writePercentage(updater.targetCloudTypeTo)
    writePercentage(updater.targetCirrusCloudDensityScale)
    writePercentage(updater.targetCloudCoverage)
end

function SeasonsWeatherHandler.inj_cloudUpdater_readStream(updater, streamId, connection)
    local maxBitValue = (2 ^ 8) - 1
    local function readPercentage()
        local value = streamReadUIntN(streamId, 8)
        return value / maxBitValue
    end

    updater.alpha = NetworkUtil.readCompressedPercentages(streamId, 8)
    updater.duration = streamReadInt32(streamId)

    updater.lastCloudTypeFrom = readPercentage()
    updater.lastCloudTypeTo = readPercentage()
    updater.lastCirrusCloudDensityScale = readPercentage()
    updater.lastCloudCoverage = readPercentage()

    updater.targetCloudTypeFrom = readPercentage()
    updater.targetCloudTypeTo = readPercentage()
    updater.targetCirrusCloudDensityScale = readPercentage()
    updater.targetCloudCoverage = readPercentage()
end
