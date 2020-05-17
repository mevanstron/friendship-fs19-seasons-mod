----------------------------------------------------------------------------------------------------
-- SeasonsMeasurementRequestEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Event to ask for measurement and to receive new data.
--           Only contains extra data
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsMeasurementRequestEvent = {}
local SeasonsMeasurementRequestEvent_mt = Class(SeasonsMeasurementRequestEvent, Event)

InitEventClass(SeasonsMeasurementRequestEvent, "SeasonsMeasurementRequestEvent")

function SeasonsMeasurementRequestEvent:emptyNew()
    local self = Event:new(SeasonsMeasurementRequestEvent_mt)
    return self
end

function SeasonsMeasurementRequestEvent:new(measuredObject, serverSplitShapeFileId)
    local self = SeasonsMeasurementRequestEvent:emptyNew()

    self.measuredObject = measuredObject
    self.serverSplitShapeFileId = serverSplitShapeFileId

    return self
end

function SeasonsMeasurementRequestEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.measuredObject ~= nil)

    if self.measuredObject ~= nil then
        NetworkUtil.writeNodeObject(streamId, self.measuredObject)
    else
        streamWriteInt32(streamId, self.serverSplitShapeFileId)
    end
end

function SeasonsMeasurementRequestEvent:readStream(streamId, connection)
    if streamReadBool(streamId) then
        self.measuredObject = NetworkUtil.readNodeObject(streamId)
    else
        self.serverSplitShapeFileId = streamReadInt32(streamId)
    end

    self:run(connection)
end

function SeasonsMeasurementRequestEvent:run(connection)
    if not connection:getIsServer() then
        MeasureTool.onRequestExtraMeasureData(connection, self.measuredObject, self.serverSplitShapeFileId)
    end
end
