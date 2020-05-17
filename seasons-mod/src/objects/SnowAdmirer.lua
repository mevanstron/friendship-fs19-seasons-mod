----------------------------------------------------------------------------------------------------
-- SnowAdmirer
----------------------------------------------------------------------------------------------------
-- Purpose:  Object with a snow dependent visibility
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SnowAdmirer = {}

local SnowAdmirer_mt = Class(SnowAdmirer)

---Handle a node with an SnowAdmirer onCreate
function SnowAdmirer:create(mission, nodeId, messageCenter, snowHandler)
    mission:addNonUpdateable(SnowAdmirer:new(nodeId, messageCenter, snowHandler))
end

function SnowAdmirer:new(nodeId, messageCenter, snowHandler)
    local self = setmetatable({}, SnowAdmirer_mt)

    self.nodeId = nodeId
    self.messageCenter = messageCenter
    self.snowHandler = snowHandler

    self.hideWhenSnow = Utils.getNoNil(getUserAttribute(nodeId, "hideWhenSnow"), false)
    self.minimumLevel = Utils.getNoNil(getUserAttribute(nodeId, "minimumLevel"), 1) * snowHandler.LAYER_HEIGHT

    self.collisionMask = Utils.getNoNil(getUserAttribute(nodeId, "collisionMask"), getCollisionMask(nodeId))

    self.messageCenter:subscribe(SeasonsMessageType.SNOW_HEIGHT_CHANGED, self.onSnowHeightChanged, self)

    return self
end

function SnowAdmirer:delete()
    self.messageCenter:unsubscribeAll(self)
end

---Set object visibility. Also update the collision mask: only active when visible
function SnowAdmirer:setVisible(visible)
    if self.hideWhenSnow then
        visible = not visible
    end

    setVisibility(self.nodeId, visible)
    setCollisionMask(self.nodeId, visible and self.collisionMask or 0)
end

---The snow height has changed
function SnowAdmirer:onSnowHeightChanged()
    self:setVisible(self.snowHandler:getHeight() >= self.minimumLevel)
end
