----------------------------------------------------------------------------------------------------
-- SeasonsEconomyHistoryEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Event for sending new history data
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsEconomyHistoryEvent = {}
local SeasonsEconomyHistoryEvent_mt = Class(SeasonsEconomyHistoryEvent, Event)

InitEventClass(SeasonsEconomyHistoryEvent, "SeasonsEconomyHistoryEvent")

function SeasonsEconomyHistoryEvent:emptyNew()
    local self = Event:new(SeasonsEconomyHistoryEvent_mt)

    return self
end

function SeasonsEconomyHistoryEvent:new(day, data)
    local self = SeasonsEconomyHistoryEvent:emptyNew()

    self.day = day
    self.data = data

    return self
end

function SeasonsEconomyHistoryEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.day, 10)

    local num = 0
    for _, _ in pairs(self.data) do
        num = num + 1
    end
    streamWriteUInt8(streamId, num)

    for fillTypeIndex, price in pairs(self.data) do
        streamWriteUIntN(streamId, fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
        streamWriteFloat32(streamId, price)
    end
end

function SeasonsEconomyHistoryEvent:readStream(streamId, connection)
    self.day = streamReadUIntN(streamId, 10)
    self.data = {}

    local num = streamReadUInt8(streamId)
    for i = 1, num do

        local fillType = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
        local price = streamReadFloat32(streamId)

        self.data[fillType] = price
    end

    self:run(connection)
end

function SeasonsEconomyHistoryEvent:run(connection)
    g_seasons.economy.history:onReceivedHistory(self.day, self.data)
end

function SeasonsEconomyHistoryEvent:sendEvent(day, data)
    if g_server ~= nil then
        g_server:broadcastEvent(SeasonsEconomyHistoryEvent:new(day, data))
    end
end
