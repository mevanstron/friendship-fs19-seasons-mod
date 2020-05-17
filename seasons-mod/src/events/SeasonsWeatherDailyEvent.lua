----------------------------------------------------------------------------------------------------
-- SeasonsWeatherDailyEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Sends extra weather info to clients
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsWeatherDailyEvent = {}
local SeasonsWeatherDailyEvent_mt = Class(SeasonsWeatherDailyEvent, Event)

InitEventClass(SeasonsWeatherDailyEvent, "SeasonsWeatherDailyEvent")

function SeasonsWeatherDailyEvent:emptyNew()
    local self = Event:new(SeasonsWeatherDailyEvent_mt)

    return self
end

function SeasonsWeatherDailyEvent:new(yesterdaySoilTemp, soilTemp, soilTempMax)
    local self = SeasonsWeatherDailyEvent:emptyNew()

    self.yesterdaySoilTemp = yesterdaySoilTemp
    self.soilTemp = soilTemp
    self.soilTempMax = soilTempMax

    return self
end

function SeasonsWeatherDailyEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.yesterdaySoilTemp)
    streamWriteFloat32(streamId, self.soilTemp)
    streamWriteFloat32(streamId, self.soilTempMax)
end

function SeasonsWeatherDailyEvent:readStream(streamId, connection)
    self.yesterdaySoilTemp = streamReadFloat32(streamId)
    self.soilTemp = streamReadFloat32(streamId)
    self.soilTempMax = streamReadFloat32(streamId)

    self:run(connection)
end

function SeasonsWeatherDailyEvent:run(connection)
    if connection:getIsServer() then
        g_seasons.weather:onDailyDataReceived(self.yesterdaySoilTemp, self.soilTemp, self.soilTempMax)
    end
end
