----------------------------------------------------------------------------------------------------
-- SeasonsAddWeatherForecastEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Sends one or more forecast events to clients
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsAddWeatherForecastEvent = {}
local SeasonsAddWeatherForecastEvent_mt = Class(SeasonsAddWeatherForecastEvent, Event)

InitEventClass(SeasonsAddWeatherForecastEvent, "SeasonsAddWeatherForecastEvent")

function SeasonsAddWeatherForecastEvent:emptyNew()
    local self = Event:new(SeasonsAddWeatherForecastEvent_mt)

    return self
end

function SeasonsAddWeatherForecastEvent:new(items, isInitialSync)
    local self = SeasonsAddWeatherForecastEvent:emptyNew()

    self.items = items
    self.isInitialSync = isInitialSync

    return self
end

function SeasonsAddWeatherForecastEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isInitialSync)

    streamWriteUIntN(streamId, #self.items, 4)
    for _, item in ipairs(self.items) do
        streamWriteInt32(streamId, item.day)
        streamWriteUIntN(streamId, item.season, 2)
        streamWriteFloat32(streamId, item.averagePeriodTemp)
        streamWriteFloat32(streamId, item.windSpeed)
        streamWriteUIntN(streamId, item.windType, 2)
        streamWriteUIntN(streamId, item.forecastType, 4)
        streamWriteFloat32(streamId, item.lowTemp)
        streamWriteFloat32(streamId, item.highTemp)

        streamWriteFloat32(streamId, item.tempUncertainty)
        streamWriteFloat32(streamId, item.weatherTypeUncertainty)
        streamWriteFloat32(streamId, item.p)
        streamWriteFloat32(streamId, item.windUncertainty)
        streamWriteFloat32(streamId, item.startTimeIndication)
        streamWriteFloat32(streamId, item.precipitationUncertainty)
    end
end

function SeasonsAddWeatherForecastEvent:readStream(streamId, connection)
    self.isInitialSync = streamReadBool(streamId)

    local num = streamReadUIntN(streamId, 4)
    self.items = {}
    for i = 1, num do
        local item = {}

        item.day = streamReadInt32(streamId)
        item.season = streamReadUIntN(streamId, 2)
        item.averagePeriodTemp = streamReadFloat32(streamId)
        item.windSpeed = streamReadFloat32(streamId)
        item.windType = streamReadUIntN(streamId, 2)
        item.forecastType = streamReadUIntN(streamId, 4)
        item.lowTemp = streamReadFloat32(streamId)
        item.highTemp = streamReadFloat32(streamId)

        item.tempUncertainty = streamReadFloat32(streamId)
        item.weatherTypeUncertainty = streamReadFloat32(streamId)
        item.p = streamReadFloat32(streamId)
        item.windUncertainty = streamReadFloat32(streamId)
        item.startTimeIndication = streamReadFloat32(streamId)
        item.precipitationUncertainty = streamReadFloat32(streamId)

        table.insert(self.items, item)
    end

    self:run(connection)
end

function SeasonsAddWeatherForecastEvent:run(connection)
    if self.isInitialSync then
        -- Full override
        g_seasons.weather.forecast:setForecast(self.items)
    else
        for _, item in ipairs(self.items) do
            g_seasons.weather.forecast:addItem(item)
        end
    end
end
