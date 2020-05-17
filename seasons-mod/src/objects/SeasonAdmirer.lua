----------------------------------------------------------------------------------------------------
-- SeasonAdmirer
----------------------------------------------------------------------------------------------------
-- Purpose:  Object that has a season-dependent visibility
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonAdmirer = {}

local SeasonAdmirer_mt = Class(SeasonAdmirer)

---Handle a node with an Ice Plane onCreate
function SeasonAdmirer:create(mission, nodeId, messageCenter, environment)
    mission:addNonUpdateable(SeasonAdmirer:new(nodeId, messageCenter, environment))
end

---Create a new instance of the SeasonAdmirer
function SeasonAdmirer:new(nodeId, messageCenter, environment)
    local self = setmetatable({}, SeasonAdmirer_mt)

    self.nodeId = nodeId
    self.messageCenter = messageCenter
    self.environment = environment

    self.isDynamicRigidBody = getRigidBodyType(nodeId):lower() == "dynamic"

    self.collisionMask = Utils.getNoNil(getUserAttribute(nodeId, "collisionMask"), getCollisionMask(nodeId))
    self.visibilityMask = Utils.getNoNil(getUserAttribute(nodeId, "mask"), 0)

    self:setVisible(self:getShouldBeVisible())

    self.messageCenter:subscribe(SeasonsMessageType.SEASON_CHANGED, self.onSeasonChanged, self)

    return self
end

function SeasonAdmirer:delete()
    self.messageCenter:unsubscribeAll(self)
end

---Set object visibility. Also update the collision mask: only active when visible
function SeasonAdmirer:setVisible(visible)
    setVisibility(self.nodeId, visible)
    if not self.isDynamicRigidBody then
        setCollisionMask(self.nodeId, visible and self.collisionMask or 0)
    end
end

---Checks if the object should be visible
---@return boolean true when the object should be visible, false otherwise
function SeasonAdmirer:getShouldBeVisible()
    local season = self.environment.season
    return bitAND(self.visibilityMask, math.pow(2, season)) ~= 0
end

---The season state has changed
function SeasonAdmirer:onSeasonChanged()
    self:setVisible(self:getShouldBeVisible())
end
