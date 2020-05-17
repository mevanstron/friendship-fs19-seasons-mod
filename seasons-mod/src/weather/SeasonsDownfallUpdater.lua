----------------------------------------------------------------------------------------------------
-- SeasonsDownfallUpdater
----------------------------------------------------------------------------------------------------
-- Purpose:  Updating downfall
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsDownfallUpdater = {}

local SeasonsDownfallUpdater_mt = Class(SeasonsDownfallUpdater)

function SeasonsDownfallUpdater:new(messageCenter)
    self = setmetatable({}, SeasonsDownfallUpdater_mt)

    self.messageCenter = messageCenter

    self.isVisible = true

    self.alpha = 1
    self.duration = 1
    self.currentDropScale = 0
    self.lastDropScale = 0
    self.targetDropScale = 0

    self.downfallTypes = {}
    self.lastDownfallTypeIndex = 0

    self.currentDownfallType = nil
    self.targetDownfallType = nil
    self.lastDownfallType = nil

    self.messageCenter:subscribe(MessageType.GAME_STATE_CHANGED, self.onGameStateChanged, self)

    return self
end

function SeasonsDownfallUpdater:delete()
    for _, downfallType in pairs(self.downfallTypes) do
        if downfallType.rootNode ~= nil then
            delete(downfallType.rootNode)
            downfallType.rootNode = nil
        end
    end

    self.messageCenter:unsubscribeAll(self)
end

---Slowly update to the target if needed.
function SeasonsDownfallUpdater:update(dt)
    if self.alpha ~= 1 then
        self.alpha = math.min(self.alpha + dt / self.duration, 1)

        self.currentDropScale = MathUtil.lerp(self.lastDropScale, self.targetDropScale, self.alpha)

        -- From downfall to no downfall
        if self.targetDownfallType ~= nil and (self.lastDownfallType == self.targetDownfallType or self.lastDownfallType == nil) then
            self.targetDownfallType.lastDropScale = self.currentDropScale
            for _, geometry in ipairs(self.targetDownfallType.geometries) do
                setDropCountScale(geometry, self.currentDropScale)
            end

            self.currentDownfallType = self.targetDownfallType
            setVisibility(self.targetDownfallType.rootNode, self.isVisible and self.currentDropScale ~= 0)

        -- From downfall to no-downfall
        elseif self.targetDownfallType == nil and self.lastDownfallType ~= nil then
            self.lastDownfallType.lastDropScale = self.currentDropScale
            for _, geometry in ipairs(self.lastDownfallType.geometries) do
                setDropCountScale(geometry, self.currentDropScale)
            end

            self.currentDownfallType = self.lastDownfallType
            setVisibility(self.lastDownfallType.rootNode, self.isVisible and self.currentDropScale ~= 0)

        -- Same intensity but different downfall type
        elseif self.targetDownfallType ~= nil and self.lastDownfallType ~= nil then -- Changing the downfall type. Keep current drop scale as the average for gameplay.
            -- Lerp from 0 to mix previous and new downfall
            local targetDropScale = MathUtil.lerp(0, self.targetDropScale, self.alpha)
            self.targetDownfallType.lastDropScale = targetDropScale
            for _, geometry in ipairs(self.targetDownfallType.geometries) do
                setDropCountScale(geometry, targetDropScale)
            end

            if targetDropScale ~= 0 then
                setVisibility(self.targetDownfallType.rootNode, self.isVisible)
            end

            -- Switch current when at the half of the switch
            if self.alpha > 0.5 then
                self.currentDownfallType = self.targetDownfallType
            end

            -- Same for the previous downfall
            local lastDropOff = MathUtil.lerp(self.lastDropScale, 0, self.alpha)
            self.lastDownfallType.lastDropScale = lastDropOff
            for _, geometry in ipairs(self.lastDownfallType.geometries) do
                setDropCountScale(geometry, lastDropOff)
            end

            if lastDropOff == 0 then
                setVisibility(self.lastDownfallType.rootNode, false)
            end
        end
    end
end

---Force downfall to be hidden
function SeasonsDownfallUpdater:setHidden(hidden)
    self.isVisible = not hidden

    if self.targetDownfallType ~= nil then
        setVisibility(self.targetDownfallType.rootNode, self.isVisible and self.currentDropScale ~= 0)
    end

    if self.lastDownfallType ~= nil then
        setVisibility(self.lastDownfallType.rootNode, self.isVisible and self.currentDropScale ~= 0)
    end
end

---Get current downfall state
function SeasonsDownfallUpdater:getCurrentValues()
    return self.currentDropScale, (self.currentDownfallType ~= nil and self.currentDownfallType.name or nil)
end

---Get current state including fade information between weathers
function SeasonsDownfallUpdater:getCurrentFadeState()
    if self.alpha > 0.5 and self.alpha < 1 and self.lastDownfallType ~= nil then
        return self.currentDropScale, (self.lastDownfallType ~= nil and self.lastDownfallType.name or nil), (self.targetDownfallType ~= nil and self.targetDownfallType.name or nil), self.alpha
    end

    return self.currentDropScale, (self.currentDownfallType ~= nil and self.currentDownfallType.name or nil), (self.targetDownfallType ~= nil and self.targetDownfallType.name or nil), self.alpha
end

function SeasonsDownfallUpdater:setTargetValues(typeName, intensity, duration)
    -- No change needed
    if typeName == nil and self.targetDownfallType == nil then
        return
    end

    self.alpha = 0
    self.duration = math.max(1, duration)

    self.lastDropScale = self.currentDropScale
    self.targetDropScale = intensity

    self.lastDownfallType = self.currentDownfallType

    if typeName == nil or self.downfallTypes[typeName] == nil then -- Disable
        self.targetDownfallType = nil
        self.targetDropScale = 0
    else
        self.targetDownfallType = self.downfallTypes[typeName]
    end
end

---Add a new downfall type
function SeasonsDownfallUpdater:addDownfallType(name, filename, baseDirectory)
    self.lastDownfallTypeIndex = self.lastDownfallTypeIndex + 1

    -- add type info
    local downfallType = {
        name = name,
        filename = filename,
        baseDirectory = baseDirectory,
        index = self.lastDownfallTypeIndex
    }

    if self:loadDownfallType(downfallType) then
        self.downfallTypes[name] = downfallType
    end
end

---Load a downfall from an i3d file
function SeasonsDownfallUpdater:loadDownfallType(downfallType)
    if downfallType.rootNode ~= nil then
        delete(downfallType.rootNode)
    end

    local path = Utils.getFilename(downfallType.filename, downfallType.baseDirectory)
    local i3dNode = loadI3DFile(path, false, false, false)
    if i3dNode == 0 then
        return false
    end

    downfallType.rootNode = i3dNode
    link(getRootNode(), downfallType.rootNode)

    setCullOverride(downfallType.rootNode, true)
    setVisibility(downfallType.rootNode, false)

    downfallType.geometries = {}
    for i = 1, getNumOfChildren(downfallType.rootNode) do
        local child = getChildAt(downfallType.rootNode, i - 1)

        if getHasClassId(child, ClassIds.SHAPE) then
            local geometry = getGeometry(child)

            if geometry ~= 0 and getHasClassId(geometry, ClassIds.PRECIPITATION) then
                table.insert(downfallType.geometries, geometry)
                setDropCountScale(geometry, 0)
            end
        end
    end

    return true
end

function SeasonsDownfallUpdater:setWindValues(windDirX, windDirZ, windVelocity, cirrusCloudSpeedFactor)
    local nDirX = (-windDirX * windVelocity) / WindUpdater.MAX_SPEED
    local nDirZ = (-windDirZ * windVelocity) / WindUpdater.MAX_SPEED

    local downfallType = self.currentDownfallType
    if downfallType ~= nil and downfallType.geometries ~= nil then
        for _, geometry in ipairs(downfallType.geometries) do
            setWindVelocity(geometry, nDirX, 0, nDirZ)
        end
    end
end

---Switch type of the downfall directly. Used for temperature changes turning now into rain and vice versa
function SeasonsDownfallUpdater:switchDownfallType(from, to)
    self:setTargetValues(to, self.targetDropScale, 0.1 * 60 * 1000)
end

----------------------
-- Networking
----------------------

function SeasonsDownfallUpdater:writeStream(streamId, connection)
    NetworkUtil.writeCompressedPercentages(streamId, self.alpha, 8)
    streamWriteInt32(streamId, self.duration)
    NetworkUtil.writeCompressedPercentages(streamId, self.lastDropScale, 8)
    NetworkUtil.writeCompressedPercentages(streamId, self.targetDropScale, 8)

    streamWriteUIntN(streamId, self.lastDownfallType ~= nil and self.lastDownfallType.index or 0, 3)
    streamWriteUIntN(streamId, self.targetDownfallType ~= nil and self.targetDownfallType.index or 0, 3)
end

function SeasonsDownfallUpdater:readStream(streamId, connection)
    self.alpha = NetworkUtil.readCompressedPercentages(streamId, 8)
    self.duration = streamReadInt32(streamId)
    self.lastDropScale = NetworkUtil.readCompressedPercentages(streamId, 8)
    self.targetDropScale = NetworkUtil.readCompressedPercentages(streamId, 8)

    self.lastDownfallType = self:getDownfallTypeByIndex(streamReadUIntN(streamId, 3))
    self.targetDownfallType = self:getDownfallTypeByIndex(streamReadUIntN(streamId, 3))
end

function SeasonsDownfallUpdater:getDownfallTypeByIndex(index)
    for _, typ in pairs(self.downfallTypes) do
        if typ.index == index then
            return typ
        end
    end

    return nil
end

----------------------
-- Events
----------------------

---Disable downfall in the shop
function SeasonsDownfallUpdater:onGameStateChanged(newGameState, oldGameState)
    self:setHidden(newGameState == GameState.MENU_SHOP_CONFIG)
end
