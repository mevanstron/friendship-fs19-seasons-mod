----------------------------------------------------------------------------------------------------
-- SeasonsStartAnimalGestation
----------------------------------------------------------------------------------------------------
-- Purpose:  Event for starting gestation of an animal
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsStartAnimalGestation = {}
local SeasonsStartAnimalGestation_mt = Class(SeasonsStartAnimalGestation, Event)

InitEventClass(SeasonsStartAnimalGestation, "SeasonsStartAnimalGestation")

SeasonsStartAnimalGestation.GESTATION_SEND_NUM_BITS = 10

function SeasonsStartAnimalGestation:emptyNew()
    local self = Event:new(SeasonsStartAnimalGestation_mt)

    return self
end

function SeasonsStartAnimalGestation:new(animal, duration)
    local self = SeasonsStartAnimalGestation:emptyNew()

    self.animal = animal
    self.duration = duration

    return self
end

function SeasonsStartAnimalGestation:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.animal)
    streamWriteUIntN(streamId, self.duration, SeasonsStartAnimalGestation.GESTATION_SEND_NUM_BITS)
end

function SeasonsStartAnimalGestation:readStream(streamId, connection)
    self.animal = NetworkUtil.readNodeObject(streamId)
    self.duration = streamReadUIntN(streamId, SeasonsStartAnimalGestation.GESTATION_SEND_NUM_BITS)

    self:run(connection)
end

function SeasonsStartAnimalGestation:run(connection)
    if self.bale ~= nil then
        self.animal:startGestation(self.duration, false)
    end
end

function SeasonsStartAnimalGestation:sendEvent(animal, duration)
    if g_server ~= nil then
        g_server:broadcastEvent(SeasonsStartAnimalGestation:new(animal, duration), nil, nil, animal)
    end
end
