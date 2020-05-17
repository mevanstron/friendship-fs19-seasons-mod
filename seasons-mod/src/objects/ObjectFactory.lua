----------------------------------------------------------------------------------------------------
-- ObjectFactory
----------------------------------------------------------------------------------------------------
-- Purpose:  Factory system for objects, to supply parameters to object constructors
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

ObjectFactory = {}

local ObjectFactory_mt = Class(ObjectFactory)

function ObjectFactory:new(mission, messageCenter, onCreateUtil, weather, environment, snowHandler, contracts)
    self = setmetatable({}, ObjectFactory_mt)

    self.mission = mission
    self.messageCenter = messageCenter
    self.onCreateUtil = onCreateUtil

    self.creationQueue = {}

    self:addObjectType(IcePlane, messageCenter, weather)
    self:addObjectType(SeasonAdmirer, messageCenter, environment)
    self:addObjectType(SnowAdmirer, messageCenter, snowHandler)
    self:addObjectType(SnowContractNode, contracts)

    return self
end

function ObjectFactory:delete()
end

function ObjectFactory:load()
    for _, item in ipairs(self.creationQueue) do
        item[1]:create(unpack(item[2]))
    end
    self.creationQueue = {}
end

---Add a type of object to the factory, with creation parameters
-- This needs to be called before a map is loaded.
function ObjectFactory:addObjectType(class, ...)
    if class.className == nil then
        for k, v in pairs(_G) do
            if v == class then
                class.className = k
            end
        end
    end

    local params = {...}

    -- Add an onCreate directly into the global namespace so the engine can access it
    -- Ideally this would never be needed and we tell the engine what to do, but that
    -- is not how it works right now.
    self.onCreateUtil.addOnCreateFunction(class.className, function (nodeId)
        local args = {self.mission, nodeId, unpack(params)}
        table.insert(self.creationQueue, {class, args})
    end)
end
