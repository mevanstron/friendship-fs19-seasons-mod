----------------------------------------------------------------------------------------------------
-- SeasonsWeatherHourlyEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Sends extra weather info to clients
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsWeatherHourlyEvent = {}
local SeasonsWeatherHourlyEvent_mt = Class(SeasonsWeatherHourlyEvent, Event)

InitEventClass(SeasonsWeatherHourlyEvent, "SeasonsWeatherHourlyEvent")

function SeasonsWeatherHourlyEvent:emptyNew()
    local self = Event:new(SeasonsWeatherHourlyEvent_mt)

    return self
end

function SeasonsWeatherHourlyEvent:new(cropMoistureContent, snowDepth, soilWaterContent)
    local self = SeasonsWeatherHourlyEvent:emptyNew()

    self.cropMoistureContent = cropMoistureContent
    self.snowDepth = snowDepth
    self.soilWaterContent = soilWaterContent

    return self
end

function SeasonsWeatherHourlyEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.cropMoistureContent)
    streamWriteFloat32(streamId, self.snowDepth)
    streamWriteFloat32(streamId, self.soilWaterContent)
end

function SeasonsWeatherHourlyEvent:readStream(streamId, connection)
    self.cropMoistureContent = streamReadFloat32(streamId)
    self.snowDepth = streamReadFloat32(streamId)
    self.soilWaterContent = streamReadFloat32(streamId)

    self:run(connection)
end

function SeasonsWeatherHourlyEvent:run(connection)
    if connection:getIsServer() then
        g_seasons.weather:onHourlyDataReceived(self.cropMoistureContent, self.snowDepth, self.soilWaterContent)
    end
end
