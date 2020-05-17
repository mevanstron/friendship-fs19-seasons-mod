----------------------------------------------------------------------------------------------------
-- SeasonsInitialStateEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Event for sending the initial game state to a client
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsInitialStateEvent = {}
local SeasonsInitialStateEvent_mt = Class(SeasonsInitialStateEvent, Event)

InitEventClass(SeasonsInitialStateEvent, "SeasonsInitialStateEvent")

SeasonsInitialStateEvent.MAGIC = 0x3AFEBEEF -- Must be signed

function SeasonsInitialStateEvent:emptyNew(seasons)
    local self = Event:new(SeasonsInitialStateEvent_mt)

    self.seasons = seasons or g_seasons -- use global for client side init

    return self
end

function SeasonsInitialStateEvent:new(seasons)
    local self = SeasonsInitialStateEvent:emptyNew(seasons)
    return self
end

function SeasonsInitialStateEvent:writeStream(streamId, connection)
    self.seasons:writeStream(streamId, connection)

    streamWriteInt32(streamId, SeasonsInitialStateEvent.MAGIC)
end

function SeasonsInitialStateEvent:readStream(streamId, connection)
    self.seasons:readStream(streamId, connection)

    if streamReadInt32(streamId) ~= SeasonsInitialStateEvent.MAGIC then
        Logging.error("SeasonsInitialStateEvent: mismatch in stream content")
    end
end
