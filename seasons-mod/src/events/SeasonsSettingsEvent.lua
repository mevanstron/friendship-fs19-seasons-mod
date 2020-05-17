----------------------------------------------------------------------------------------------------
-- SeasonsSettingsEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Event for setting mod settings from client to server
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsSettingsEvent = {}
local SeasonsSettingsEvent_mt = Class(SeasonsSettingsEvent, Event)

InitEventClass(SeasonsSettingsEvent, "SeasonsSettingsEvent")

function SeasonsSettingsEvent:emptyNew()
    local self = Event:new(SeasonsSettingsEvent_mt)

    self.seasons = g_seasons

    return self
end

function SeasonsSettingsEvent:new(daysPerSeason, snowMode, snowTracksEnabled, cropMoistureEnabled)
    local self = SeasonsSettingsEvent:emptyNew()

    self.daysPerSeason = daysPerSeason
    self.snowMode = snowMode
    self.snowTracksEnabled = snowTracksEnabled
    self.cropMoistureEnabled = cropMoistureEnabled

    return self
end

function SeasonsSettingsEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.daysPerSeason, 6)
    streamWriteUIntN(streamId, self.snowMode, 2)
    streamWriteBool(streamId, self.snowTracksEnabled)
    streamWriteBool(streamId, self.cropMoistureEnabled)
end

function SeasonsSettingsEvent:readStream(streamId, connection)
    self.daysPerSeason = streamReadUIntN(streamId, 6)
    self.snowMode = streamReadUIntN(streamId, 2)
    self.snowTracksEnabled = streamReadBool(streamId)
    self.cropMoistureEnabled = streamReadBool(streamId)

    self:run(connection)
end

function SeasonsSettingsEvent:run(connection)
    -- To server, check for permission
    if connection:getIsServer() or g_currentMission.userManager:getIsConnectionMasterUser(connection) then
        self.seasons.snowHandler:setMode(self.snowMode)
        self.seasons.weather:setCropMoistureEnabled(self.cropMoistureEnabled)
        self.seasons.vehicle:setSnowTracksEnabled(self.snowTracksEnabled)
        self.seasons.environment:setSeasonLength(self.daysPerSeason)

        -- If this came from client, send to all clients
        if not connection:getIsServer() then
            g_server:broadcastEvent(self)
        end

        g_messageCenter:publish(SeasonsSettingsEvent)
    end
end
