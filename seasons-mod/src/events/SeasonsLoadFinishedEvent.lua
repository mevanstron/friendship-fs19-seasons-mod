----------------------------------------------------------------------------------------------------
-- SeasonsLoadFinishedEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Event sent after all initial events (weather, seasons state) so
--           other processes can start
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsLoadFinishedEvent = {}
local SeasonsLoadFinishedEvent_mt = Class(SeasonsLoadFinishedEvent, Event)

InitEventClass(SeasonsLoadFinishedEvent, "SeasonsLoadFinishedEvent")

function SeasonsLoadFinishedEvent:emptyNew(seasons)
    local self = Event:new(SeasonsLoadFinishedEvent_mt)

    self.seasons = seasons or g_seasons -- use global for client side init

    return self
end

function SeasonsLoadFinishedEvent:new(seasons)
    return SeasonsLoadFinishedEvent:emptyNew(seasons)
end

function SeasonsLoadFinishedEvent:writeStream(streamId, connection)
end

function SeasonsLoadFinishedEvent:readStream(streamId, connection)
    g_seasons:onGameLoaded()
end
