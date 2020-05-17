----------------------------------------------------------------------------------------------------
-- IcePlane
----------------------------------------------------------------------------------------------------
-- Purpose:  Object that is only visible when there is ice
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

IcePlane = {}

local IcePlane_mt = Class(IcePlane)

---Handle a node with an Ice Plane onCreate
function IcePlane:create(mission, nodeId, messageCenter, weather)
    mission:addNonUpdateable(IcePlane:new(nodeId, messageCenter, weather))
end

function IcePlane:new(nodeId, messageCenter, weather)
    local self = setmetatable({}, IcePlane_mt)

    self.nodeId = nodeId
    self.messageCenter = messageCenter
    self.weather = weather

    self.collisionMask = Utils.getNoNil(getUserAttribute(nodeId, "collisionMask"), getCollisionMask(nodeId))

    self.messageCenter:subscribe(SeasonsMessageType.FREEZING_CHANGED, self.onFreezingChanged, self)

    return self
end

function IcePlane:delete()
    self.messageCenter:unsubscribeAll(self)
end

---Set the ice plane visible. Also update the collision mask: only active when visible
function IcePlane:setVisible(visible)
    setVisibility(self.nodeId, visible)
    setCollisionMask(self.nodeId, visible and self.collisionMask or 0)
end

---The freezing state has changed
function IcePlane:onFreezingChanged()
    self:setVisible(self.weather:isGroundFrozen())
end
