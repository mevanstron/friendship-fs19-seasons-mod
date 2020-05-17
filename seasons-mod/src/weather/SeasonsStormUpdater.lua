----------------------------------------------------------------------------------------------------
-- SeasonsStormUpdater
----------------------------------------------------------------------------------------------------
-- Purpose:  Updating storms
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsStormUpdater = {}

local SeasonsStormUpdater_mt = Class(SeasonsStormUpdater)

function SeasonsStormUpdater:new(messageCenter)
    self = setmetatable({}, SeasonsStormUpdater_mt)

    self.messageCenter = messageCenter

    self.soundHandler = nil

    self.alpha = 1
    self.duration = 1

    self.currentIntensity = 0
    self.lastIntensity = 0
    self.targetIntensity = 0

    self.nextFlicker = 0
    self.flickerDuration = 100
    self.isFlickerActive = false
    self.lightningTime = 0

    self.soundPendingTimer = nil

    return self
end

function SeasonsStormUpdater:delete()
    if self.lightningNode ~= nil then
        delete(self.lightningNode)
    end
end

---Slowly update to the target if needed.
function SeasonsStormUpdater:update(dt)
    if self.alpha ~= 1 then
        self.alpha = math.min(self.alpha + dt / self.duration, 1)

        self.currentIntensity = MathUtil.lerp(self.lastIntensity, self.targetIntensity, self.alpha)
    end

    -- Increase chance with intensity
    local p = self.currentIntensity * 0.002
    if math.random() < p then
        if self.currentIntensity > 0.5 and math.random() < (self.currentIntensity * 0.3) then
            self:showLighting()
            self.soundPendingTimer = SeasonsMathUtil.normDist(1400, 700)
        else
            -- Directly make a sound
            self.soundPendingTimer = 0
        end
    end

    self:updateSound(dt)
    self:updateLightning(dt)
end

---Update sound for thunder. Uses a pending timer to space lightning and thunder
function SeasonsStormUpdater:updateSound(dt)
    if self.soundPendingTimer ~= nil then
        self.soundPendingTimer = self.soundPendingTimer - dt

        if self.soundPendingTimer <= 0 then
            if self.soundHandler ~= nil then
                self.soundHandler()
            end

            self.soundPendingTimer = nil
        end
    end
end

---Activate lightning
function SeasonsStormUpdater:showLighting()
    self.lightningTime = math.ceil(math.random() * 300)
    self.nextFlicker = 0
end

---Update lightning to quickly hide it after a time
function SeasonsStormUpdater:updateLightning(dt)
    if self.lightningTime > 0 then
        self.lightningTime = self.lightningTime - dt

        self.nextFlicker = self.nextFlicker - dt
        if self.nextFlicker <= 0 then
            self.isFlickerActive = true

            -- local x, _, z = getWorldTranslation(self.mission.player.rootNode)
            -- setWorldTranslation(self.lightningNode, x, 1800, z)

            setVisibility(self.lightningNode, true)
            self.nextFlicker = math.floor(math.random() * 60 + self.flickerDuration + 10) -- set next flicker at least 10ms after this one
        end
    end

    if self.isFlickerActive then
        self.flickerDuration = self.flickerDuration - dt
        if self.flickerDuration <= 0 then
            self.isFlickerActive = false
            self.flickerDuration = math.floor(math.random() * 100) -- how long visible
            setVisibility(self.lightningNode, false)
        end
    end
end

----------------------
-- Setters/getters
----------------------

---Get current state
function SeasonsStormUpdater:getCurrentValues()
    return self.currentIntensity
end

function SeasonsStormUpdater:setTargetValues(targetIntensity, duration)
    self.alpha = 0
    self.duration = math.max(1, duration)

    self.lastIntensity = self.currentIntensity
    self.targetIntensity = math.min(math.max(0, targetIntensity), 1)
end

function SeasonsStormUpdater:setSoundHandler(handler)
    self.soundHandler = handler
end

function SeasonsStormUpdater:addLightningObject(filename, baseDirectory)
    local path = Utils.getFilename(filename, baseDirectory)
    local rootNode = loadI3DFile(path, false, false, false)
    if rootNode == 0 then
        return false
    end

    self.lightningNode = rootNode
    link(getRootNode(), rootNode)

    setVisibility(rootNode, false)

    setWorldTranslation(rootNode, 0, 1800, 0)
end

----------------------
-- Networking
----------------------

function SeasonsStormUpdater:writeStream(streamId, connection)
    NetworkUtil.writeCompressedPercentages(streamId, self.alpha, 8)
    streamWriteInt32(streamId, self.duration)
    NetworkUtil.writeCompressedPercentages(streamId, self.lastIntensity, 8)
    NetworkUtil.writeCompressedPercentages(streamId, self.targetIntensity, 8)
end

function SeasonsStormUpdater:readStream(streamId, connection)
    self.alpha = NetworkUtil.readCompressedPercentages(streamId, 8)
    self.duration = streamReadInt32(streamId)
    self.lastIntensity = NetworkUtil.readCompressedPercentages(streamId, 8)
    self.targetIntensity = NetworkUtil.readCompressedPercentages(streamId, 8)
end

----------------------
-- Events
----------------------
