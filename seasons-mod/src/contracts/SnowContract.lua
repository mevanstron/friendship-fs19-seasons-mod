----------------------------------------------------------------------------------------------------
-- SnowContract
----------------------------------------------------------------------------------------------------
-- Purpose:  A contract for moving/clearing snow
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SnowContract = {}

local SnowContract_mt = Class(SnowContract, AbstractMission)

InitObjectClass(SnowContract, "SnowContract")

SnowContract.COMPLETION_PERCENTAGE = 0.98
SnowContract.REWARD_PER_HA = 12000

function SnowContract:new(isServer, isClient, customMt)
    local self = AbstractMission:new(isServer, isClient, customMt or SnowContract_mt)

    self.isInMissionMap = false

    self.workAreaTypes = { [WorkAreaType.SPRAYER] = true }

    return self
end

function SnowContract:delete()
    self:removeFromMissionMap()

    SnowContract:superClass().delete(self)
end

function SnowContract:saveToXMLFile(xmlFile, key)
    SnowContract:superClass().saveToXMLFile(self, xmlFile, key)

    setXMLString(xmlFile, key.."#config", self.config.name)
end

function SnowContract:loadFromXMLFile(xmlFile, key)
    if not SnowContract:superClass().loadFromXMLFile(self, xmlFile, key) then
        return false
    end

    local name = getXMLString(xmlFile, key .. "#config")
    self.config = g_seasons.contracts:getSnowConfigByName(name)
    if self.config == nil then -- When mission config was removed from the map since last save
        return false
    end

    if self.status == AbstractMission.STATUS_RUNNING then
        self:showSigns()
        self:addToMissionMap()
    end

    return true
end

function SnowContract:writeStream(streamId)
    SnowContract:superClass().writeStream(self, streamId)

    streamWriteUInt8(streamId, self.config.id)
end

function SnowContract:readStream(streamId)
    SnowContract:superClass().readStream(self, streamId)

    self.config = g_seasons.contracts:getSnowConfigById(streamReadUInt8(streamId))

    if self.status == AbstractMission.STATUS_RUNNING then
        self:addToMissionMap()
    end
end

---Initialize the new mission
function SnowContract:init(config)
    if not SnowContract:superClass().init(self) then
        return false
    end

    if config == nil then
        return false
    end

    -- Configure the mission
    self.config = config

    self.reward = self:calculateReward()

    return true
end

---Calculate the reward for this mission
function SnowContract:calculateReward()
    local difficultyMultiplier = 0.8
    if g_currentMission.missionInfo.economicDifficulty == 2 then
        difficultyMultiplier = 1.0
    elseif g_currentMission.missionInfo.economicDifficulty == 1 then
        difficultyMultiplier = 1.2
    end

    local area = self.config.area
    local rewardPerHa = SnowContract.REWARD_PER_HA

    return area * rewardPerHa * self.config.rewardScale * difficultyMultiplier
end

function SnowContract:start()
    if not SnowContract:superClass().start(self) then
        return false
    end

    self:showSigns()
    self:addToMissionMap()

    return true
end

---Mission was started
function SnowContract:started()
    if self.isClient then
        self:showSigns()
        self:addToMissionMap()
    end
end

function SnowContract:finish(success)
    SnowContract:superClass().finish(self, success)

    if success then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, g_i18n:getText("seasons_contract_finished"))
    else
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, g_i18n:getText("seasons_contract_failed"))
    end
end

function SnowContract:dismiss()
    SnowContract:superClass().dismiss(self)

    self:hideSigns()
    self:removeFromMissionMap()
end

---Show any helpful signs and area markers
function SnowContract:showSigns()
    if self.config.nodes.sign ~= nil then
        setVisibility(self.config.nodes.sign, true)
        self:createHotspot()
    end
end

---Hide any helpful signs and area markers
function SnowContract:hideSigns()
    if self.config.nodes.sign ~= nil then
        setVisibility(self.config.nodes.sign, false)
        self:destroyHotspot()
    end
end

---Add to mission map
function SnowContract:addToMissionMap()
    if not self.isInMissionMap then
        g_seasons.contracts:addMissionToMissionMap(self)
        self.isInMissionMap = false
    end
end

---Remove from mission map if it was added
function SnowContract:removeFromMissionMap()
    if self.isInMissionMap then
        g_seasons.contracts:removeMissionFromMissionMap(self)
        self.isInMissionMap = false
    end
end

function SnowContract:createHotspot(color, trigger)
    local width, height = getNormalizedScreenValues(11, 11)
    local x, _, z = getWorldTranslation(self.config.nodes.sign)

    local hotspot = MapHotspot:new("missionHotspot", MapHotspot.CATEGORY_MISSION)
    hotspot:setBorderedImage(nil, getNormalizedUVs(MapHotspot.UV.CIRCLE), color)
    hotspot:setWorldPosition(x, z)
    hotspot:setPersistent(true)
    hotspot:setSize(width, height)
    hotspot:setOwnerFarmId(self.farmId)
    hotspot:setHasDetails(false)

    g_currentMission:addMapHotspot(hotspot)

    self.hotspot = hotspot
end

function SnowContract:destroyHotspot()
    if self.hotspot ~= nil then
        g_currentMission:removeMapHotspot(self.hotspot)
        self.hotspot:delete()
        self.hotspot = nil
    end
end

---------------------------
-- Data to UI
---------------------------

function SnowContract:getData()

    return {
        location = self.config.location,
        jobType = g_i18n:getText("seasons_snowContract_jobType"),
        action = g_i18n:getText("seasons_snowContract_action"),
        description = self.config.text,
    }
end

function SnowContract:getNPC()
    return self.config.npc
end

function SnowContract:getCompletion()
    -- When the terrain snow is being modified by the weather, ignore any changes until it is done.
    -- By returning the last completion we don't change the mission completion.
    if g_seasons.snowHandler.isDoingTerrainModifications then
        return self.completion
    end

    local _, _, percentage = SnowContract.getSnowInArea(self.config.nodes.clearArea)

    return (1 - percentage) / SnowContract.COMPLETION_PERCENTAGE
end

---------------------------
-- Generation and validation
---------------------------

---Check whether this mission can still run
function SnowContract:validate()
    return SnowContract.canRun(self.config, self.status == AbstractMission.STATUS_RUNNING)
end

---Get the amount of terrain covered in snow for given area
function SnowContract.getSnowInArea(area)
    local num, total = 0, 0

    local numSections = getNumOfChildren(area)
    for i = 1, numSections do
        -- First node: corner, then children rotate clockwise
        local width = getChildAt(area, i - 1)
        local start = getChildAt(width, 0)
        local height = getChildAt(width, 1)

        local x0,_,z0 = getWorldTranslation(start)
        local x1,_,z1 = getWorldTranslation(width)
        local x2,_,z2 = getWorldTranslation(height)

        local liters, numPixels, totalPixels = DensityMapHeightUtil.getFillLevelAtArea(FillType.SNOW, x0,z0, x1,z1, x2,z2)

        -- This is an approximation. With overlapping areas this is not nearly correct.
        num = num + numPixels
        total = total + totalPixels
    end

    if total == 0 then
        return 0, 0, 0
    end

    return num, total, num / total
end

function SnowContract.canRun(config, isAlreadyRunning)
    -- Snow must exist according to the snow handler
    if g_seasons.snowHandler.height < SeasonsSnowHandler.LAYER_HEIGHT then
        return false
    end

    if not isAlreadyRunning then
        -- Check if snow exists in the to-be-cleaned area. If it is already running, ignore this check or it auto-fails at 80% completion
        local num, total, percentage = SnowContract.getSnowInArea(config.nodes.clearArea)
        if percentage < 0.20 then
            return false
        end
    end

    return true
end

g_missionManager:registerMissionType(SnowContract, "snow", SeasonsContracts.CATEGORY_SNOW, 1)
