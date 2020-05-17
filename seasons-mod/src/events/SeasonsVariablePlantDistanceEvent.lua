----------------------------------------------------------------------------------------------------
-- SeasonsVariablePlantDistanceEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Event setting the variable plant distance.
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsVariablePlantDistanceEvent = {}
local SeasonsVariablePlantDistanceEvent_mt = Class(SeasonsVariablePlantDistanceEvent, Event)

InitEventClass(SeasonsVariablePlantDistanceEvent, "SeasonsVariablePlantDistanceEvent")

function SeasonsVariablePlantDistanceEvent:emptyNew()
    local self = Event:new(SeasonsVariablePlantDistanceEvent_mt)

    return self
end

function SeasonsVariablePlantDistanceEvent:new(vehicle, distance)
    local self = SeasonsVariablePlantDistanceEvent:emptyNew()

    self.vehicle = vehicle
    self.distance = distance

    return self
end

function SeasonsVariablePlantDistanceEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteInt8(streamId, self.distance)
end

function SeasonsVariablePlantDistanceEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.distance = streamReadInt8(streamId)

    self:run(connection)
end

function SeasonsVariablePlantDistanceEvent:run(connection)
    self.vehicle:setTreePlantDistance(self.distance, true)

    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection, self.vehicle)
    end
end

function SeasonsVariablePlantDistanceEvent.sendEvent(vehicle, distance, noEventSend)
    if noEventSend == nil or not noEventSend then
        if g_server ~= nil then
            g_server:broadcastEvent(SeasonsVariablePlantDistanceEvent:new(vehicle, distance), nil, nil, vehicle)
        else
            g_client:getServerConnection():sendEvent(SeasonsVariablePlantDistanceEvent:new(vehicle, distance))
        end
    end
end