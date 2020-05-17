----------------------------------------------------------------------------------------------------
-- SeasonsBaleRotEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Event for bale rotting state change
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsBaleRotEvent = {}
local SeasonsBaleRotEvent_mt = Class(SeasonsBaleRotEvent, Event)

InitEventClass(SeasonsBaleRotEvent, "SeasonsBaleRotEvent")

function SeasonsBaleRotEvent:emptyNew()
    local self = Event:new(SeasonsBaleRotEvent_mt)

    return self
end

function SeasonsBaleRotEvent:new(bale)
    local self = SeasonsBaleRotEvent:emptyNew()

    self.bale = bale
    self.fillLevel = self.bale:getFillLevel()

    return self
end

function SeasonsBaleRotEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.bale)
    streamWriteFloat32(streamId, self.fillLevel)
end

function SeasonsBaleRotEvent:readStream(streamId, connection)
    self.bale = NetworkUtil.readNodeObject(streamId)
    self.fillLevel = streamReadFloat32(streamId)

    self:run(connection)
end

function SeasonsBaleRotEvent:run(connection)
    if self.bale ~= nil then
        self.bale:setFillLevel(self.fillLevel)
    end
end

function SeasonsBaleRotEvent:sendEvent(bale)
    if g_server ~= nil then
        g_server:broadcastEvent(SeasonsBaleRotEvent:new(bale), nil, nil, bale)
    end
end
