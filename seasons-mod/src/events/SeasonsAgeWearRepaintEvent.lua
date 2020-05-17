----------------------------------------------------------------------------------------------------
-- SeasonsAgeWearRepaintEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Asks for a repaint
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsAgeWearRepaintEvent = {}
local SeasonsAgeWearRepaintEvent_mt = Class(SeasonsAgeWearRepaintEvent, Event)

InitEventClass(SeasonsAgeWearRepaintEvent, "SeasonsAgeWearRepaintEvent")

function SeasonsAgeWearRepaintEvent:emptyNew()
    local self = Event:new(SeasonsAgeWearRepaintEvent_mt)
    return self
end

function SeasonsAgeWearRepaintEvent:new(vehicle, atSellingPoint)
    local self = SeasonsAgeWearRepaintEvent:emptyNew()

    self.vehicle = vehicle
    self.atSellingPoint = atSellingPoint

    return self
end

function SeasonsAgeWearRepaintEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.atSellingPoint)
end

function SeasonsAgeWearRepaintEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.atSellingPoint = streamReadBool(streamId)

    self:run(connection)
end

function SeasonsAgeWearRepaintEvent:run(connection)
    if not connection:getIsServer() then
        if self.vehicle.repaintVehicle ~= nil then
            self.vehicle:repaintVehicle(self.atSellingPoint)

            g_server:broadcastEvent(self) -- broadcast for UI updates
            g_messageCenter:publish(SeasonsMessageType.VEHICLE_REPAINTED, {self.vehicle, self.atSellingPoint})
        end
    else
        g_messageCenter:publish(SeasonsMessageType.VEHICLE_REPAINTED, {self.vehicle, self.atSellingPoint})
    end
end
