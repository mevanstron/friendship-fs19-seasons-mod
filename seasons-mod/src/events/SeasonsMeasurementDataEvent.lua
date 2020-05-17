----------------------------------------------------------------------------------------------------
-- SeasonsMeasurementDataEvent
----------------------------------------------------------------------------------------------------
-- Purpose:  Event to ask for measurement and to receive new data.
--           Only contains extra data
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsMeasurementDataEvent = {}
local SeasonsMeasurementDataEvent_mt = Class(SeasonsMeasurementDataEvent, Event)

InitEventClass(SeasonsMeasurementDataEvent, "SeasonsMeasurementDataEvent")

function SeasonsMeasurementDataEvent:emptyNew()
    local self = Event:new(SeasonsMeasurementDataEvent_mt)
    return self
end

function SeasonsMeasurementDataEvent:new(measuredObject, baleFermentation, treeId, treeType, treeHeight, treeDistance)
    local self = SeasonsMeasurementDataEvent:emptyNew()

    self.measuredObject = measuredObject
    self.baleFermentation = baleFermentation
    self.treeType = treeType
    self.treeHeight = treeHeight
    self.treeDistance = treeDistance
    self.treeId = treeId

    return self
end

function SeasonsMeasurementDataEvent:writeStream(streamId, connection)
    if self.baleFermentation ~= nil then
        streamWriteUIntN(streamId, 1, 2)

        NetworkUtil.writeNodeObject(streamId, self.measuredObject)
        streamWriteFloat32(streamId, self.baleFermentation)
    elseif self.treeId ~= nil then
        streamWriteUIntN(streamId, 2, 2)

        streamWriteInt32(streamId, self.treeType)
        streamWriteInt32(streamId, self.treeId)

        NetworkUtil.writeCompressedPercentages(streamId, self.treeDistance / 100, 8)
        NetworkUtil.writeCompressedPercentages(streamId, self.treeHeight / 100, 8)
    else
        streamWriteUIntN(streamId, 3, 2)
    end

end

function SeasonsMeasurementDataEvent:readStream(streamId, connection)
    local type = streamReadUIntN(streamId, 2)

    if type == 1 then
        self.measuredObject = NetworkUtil.readNodeObject(streamId)
        self.baleFermentation = streamReadFloat32(streamId)
    elseif type == 2 then
        self.treeType = streamReadInt32(streamId)
        self.treeId = streamReadInt32(streamId)

        self.treeDistance = NetworkUtil.readCompressedPercentages(streamId, 8) * 100
        self.treeHeight = NetworkUtil.readCompressedPercentages(streamId, 8) * 100
    end

    self:run(connection)
end

function SeasonsMeasurementDataEvent:run(connection)
    if connection:getIsServer() then
        if self.measuredObject ~= nil then
            MeasureTool.onReceiveExtraBaleData(self.measuredObject, self.baleFermentation)
        elseif self.treeId ~= nil then
            MeasureTool.onReceiveExtraTreeData(self.treeId, self.treeType, self.treeHeight, self.treeDistance)
        end
    end
end
