----------------------------------------------------------------------------------------------------
-- SeasonsBaleFermentEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Event for bale state updates
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsBaleFermentEvent = {}
local SeasonsBaleFermentEvent_mt = Class(SeasonsBaleFermentEvent, Event)

InitEventClass(SeasonsBaleFermentEvent, "SeasonsBaleFermentEvent")

function SeasonsBaleFermentEvent:emptyNew()
    local self = Event:new(SeasonsBaleFermentEvent_mt)

    return self
end

function SeasonsBaleFermentEvent:new(bale)
    local self = SeasonsBaleFermentEvent:emptyNew()

    self.bale = bale
    self.fillType = self.bale:getFillType()

    return self
end

function SeasonsBaleFermentEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.bale)
    streamWriteUIntN(streamId, self.fillType, FillTypeManager.SEND_NUM_BITS)
end

function SeasonsBaleFermentEvent:readStream(streamId, connection)
    self.bale = NetworkUtil.readNodeObject(streamId)
    self.fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)

    self:run(connection)
end

function SeasonsBaleFermentEvent:run(connection)
    if self.bale ~= nil then
        self.bale:setFillType(self.fillType)
    end
end

function SeasonsBaleFermentEvent:sendEvent(bale)
    if g_server ~= nil then
        g_server:broadcastEvent(SeasonsBaleFermentEvent:new(bale), nil, nil, bale)
    end
end
