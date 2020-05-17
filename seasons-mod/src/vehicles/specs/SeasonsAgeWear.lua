----------------------------------------------------------------------------------------------------
-- SeasonsAgeWear
----------------------------------------------------------------------------------------------------
-- Purpose:  Makes visual wear based on age, not on maintenance
--
-- Overwrite wear change used by Wearable
-- Then sets wear based on age
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsAgeWear = {}

SeasonsAgeWear.NORM_FACTOR = 6
SeasonsAgeWear.SEND_NUM_BITS = 6
SeasonsAgeWear.SEND_MAX_VALUE = 63
SeasonsAgeWear.NUM_HOURS_TOTAL_WEAR = 30
SeasonsAgeWear.NUM_MS_TOTAL_WEAR = SeasonsAgeWear.NUM_HOURS_TOTAL_WEAR * 60 * 1000 * 60

function SeasonsAgeWear.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Wearable, specializations)
end

function SeasonsAgeWear.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "setNodeScratchAmount", SeasonsAgeWear.setNodeScratchAmount)
    SpecializationUtil.registerFunction(vehicleType, "getOperatingTimeBasedWearAmount", SeasonsAgeWear.getOperatingTimeBasedWearAmount)
    SpecializationUtil.registerFunction(vehicleType, "getRepaintPrice", SeasonsAgeWear.getRepaintPrice)
    SpecializationUtil.registerFunction(vehicleType, "repaintVehicle", SeasonsAgeWear.repaintVehicle)
end

function SeasonsAgeWear.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setOperatingTime", SeasonsAgeWear.inj_setOperatingTime)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setNodeWearAmount", SeasonsAgeWear.inj_setNodeWearAmount)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIntervalMultiplier", SeasonsAgeWear.inj_getIntervalMultiplier)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "onUpdateTick", SeasonsAgeWear.inj_onUpdateTick)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getWearTotalAmount", SeasonsAgeWear.getWearTotalAmount)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "repairVehicle", SeasonsAgeWear.repairVehicle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getRepairPrice", SeasonsAgeWear.getRepairPrice)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getVehicleDamage", SeasonsAgeWear.getVehicleDamage)
end

function SeasonsAgeWear.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", SeasonsAgeWear)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", SeasonsAgeWear)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", SeasonsAgeWear)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", SeasonsAgeWear)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", SeasonsAgeWear)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", SeasonsAgeWear)
end

function SeasonsAgeWear:onLoad(savegame)
    local spec = self:seasons_getSpecTable("ageWear")

    spec.dirtyFlag = self:getNextDirtyFlag()
    spec.lastRepaintOperatingTime = 0
end

function SeasonsAgeWear:onPostLoad(savegame)
    local hasSaveGame = savegame ~= nil and not savegame.resetVehicles
    local key = hasSaveGame and self:seasons_getSpecSaveKey(savegame.key, "ageWear") or ""

    if hasSaveGame then
        local spec = self:seasons_getSpecTable("ageWear")
        spec.lastRepaintOperatingTime = Utils.getNoNil(getXMLFloat(savegame.xmlFile, key .. "#lastRepaintOperatingTime"), spec.lastRepaintOperatingTime) * 1000
    end

    local nodes = self.spec_wearable.wearableNodes
    for i, nodeData in ipairs(nodes) do
        nodeData.scratchAmountSent = 0

        local amount = 0
        if hasSaveGame then
            local nodeKey = ("%s.scratchNode(%d)"):format(key, i - 1)
            amount = Utils.getNoNil(getXMLFloat(savegame.xmlFile, nodeKey .. "#amount"), self:getOperatingTimeBasedWearAmount())
        end

        self:setNodeScratchAmount(nodeData, amount, true)
    end
end

function SeasonsAgeWear:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self:seasons_getSpecTable("ageWear")

    setXMLFloat(xmlFile, key .. "#lastRepaintOperatingTime", spec.lastRepaintOperatingTime / 1000)

    local nodes = self.spec_wearable.wearableNodes
    for i, nodeData in ipairs(nodes) do
        local nodeKey = ("%s.scratchNode(%d)"):format(key, i - 1)
        setXMLFloat(xmlFile, nodeKey .. "#amount", nodeData.scratchAmount)
    end
end

function SeasonsAgeWear:onReadStream(streamId, connection)
    local spec = self:seasons_getSpecTable("ageWear")

    spec.lastRepaintOperatingTime = streamReadFloat32(streamId)

    local nodes = self.spec_wearable.wearableNodes
    if nodes ~= nil then
        for _, nodeData in ipairs(nodes) do
            local scratchAmount = streamReadUIntN(streamId, SeasonsAgeWear.SEND_NUM_BITS) / SeasonsAgeWear.SEND_MAX_VALUE
            self:setNodeScratchAmount(nodeData, scratchAmount, true)
        end
    end
end

function SeasonsAgeWear:onWriteStream(streamId, connection)
    local spec = self:seasons_getSpecTable("ageWear")

    streamWriteFloat32(streamId, spec.lastRepaintOperatingTime)

    local nodes = self.spec_wearable.wearableNodes
    if nodes ~= nil then
        for _, nodeData in ipairs(nodes) do
            streamWriteUIntN(streamId, math.floor(nodeData.scratchAmount * SeasonsAgeWear.SEND_MAX_VALUE + 0.5), SeasonsAgeWear.SEND_NUM_BITS)
        end
    end
end

function SeasonsAgeWear:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        local nodes = self.spec_wearable.wearableNodes
        if nodes ~= nil then
            if streamReadBool(streamId) then
                for _, nodeData in ipairs(nodes) do
                    local scratchAmount = streamReadUIntN(streamId, SeasonsAgeWear.SEND_NUM_BITS) / SeasonsAgeWear.SEND_MAX_VALUE
                    self:setNodeScratchAmount(nodeData, scratchAmount, true)
                end
            end
        end
    end
end

function SeasonsAgeWear:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local nodes = self.spec_wearable.wearableNodes
        if nodes ~= nil then
            local spec = self:seasons_getSpecTable("ageWear")
            if streamWriteBool(streamId, bitAND(dirtyMask, spec.dirtyFlag) ~= 0) then
                for _, nodeData in ipairs(nodes) do
                    streamWriteUIntN(streamId, math.floor(nodeData.scratchAmount * SeasonsAgeWear.SEND_MAX_VALUE + 0.5), SeasonsAgeWear.SEND_NUM_BITS)
                end
            end
        end
    end
end

---Set the amount of scratches
function SeasonsAgeWear:setNodeScratchAmount(nodeData, scratchAmount, force)
    local amount = MathUtil.clamp(scratchAmount, 0, 1)
    local difference = nodeData.scratchAmountSent - amount

    nodeData.scratchAmount = amount

    if math.abs(difference) > Wearable.SEND_THRESHOLD or force then
        for _, node in pairs(nodeData.nodes) do
            local _, y, z, w = getShaderParameter(node, "RDT")
            setShaderParameter(node, "RDT", amount, y, z, w, false)
        end

        if self.isServer then
            local spec = self:seasons_getSpecTable("ageWear")
            self:raiseDirtyFlags(spec.dirtyFlag)
            nodeData.scratchAmountSent = nodeData.scratchAmount
        end
    end
end

function SeasonsAgeWear:getWearTotalAmount(superFunc)
    local spec = self:seasons_getSpecTable("seasonsVehicle")

    local durationToService = (spec.nextRepair - self:getOperatingTime() / 1000) / (60 * 60)

    return MathUtil.clamp(1 - durationToService / 30, 0, 1)
end

function SeasonsAgeWear:repairVehicle(superFunc, atSellingPoint)
    if self.isServer then
        local specVehicle = self:seasons_getSpecTable("seasonsVehicle")

        g_currentMission:addMoney(-self:getRepairPrice(atSellingPoint), self:getOwnerFarmId(), MoneyType.VEHICLE_REPAIR, true, true)

        specVehicle.nextRepair = self:getOperatingTime() / 1000 + SeasonsAgeWear.NUM_HOURS_TOTAL_WEAR * 60 * 60 --* ageRepairMultiplier
        self:raiseDirtyFlags(specVehicle.dirtyFlag)
    end
end

function SeasonsAgeWear:getRepairPrice(superFunc, atSellingPoint)
    local ret = superFunc(self, atSellingPoint)

    local specVehicle = self:seasons_getSpecTable("seasonsVehicle")
    local ageCostMultiplier = (1 + specVehicle.years) ^ 0.1

    return ret * ageCostMultiplier
end

function SeasonsAgeWear:getVehicleDamage(superFunc)
    return MathUtil.clamp(Wearable.DAMAGE_CURVE:get(self:getWearTotalAmount()), 0, 1)
end

---Get the wear based on the vehicle total usage
function SeasonsAgeWear:getOperatingTimeBasedWearAmount()
    local spec = self:seasons_getSpecTable("ageWear")
    return math.min((self.operatingTime - spec.lastRepaintOperatingTime) / SeasonsAgeWear.NUM_MS_TOTAL_WEAR * 0.9, 1) -- test for 10 hours
end

---Repaint price.
function SeasonsAgeWear:getRepaintPrice()
    local spec = self:seasons_getSpecTable("ageWear")
    local diff = self.operatingTime - spec.lastRepaintOperatingTime

    if diff < 1000 * 60 * 30 then
        return 0
    end

    --- Minimum of 500 with a 5% of new price added, to make it more costly for larger vehicles
    return 500 + self:getPrice() * 0.05
end

function SeasonsAgeWear:repaintVehicle()
    if self.isServer then
        local spec = self:seasons_getSpecTable("ageWear")

        local repaintPrice = self:getRepaintPrice()
        g_currentMission:addMoney(-repaintPrice, self:getOwnerFarmId(), MoneyType.VEHICLE_REPAIR, true, true)

        local nodes = self.spec_wearable.wearableNodes
        for _, nodeData in ipairs(nodes) do
            self:setNodeScratchAmount(nodeData, 0, true)
        end

        spec.lastRepaintOperatingTime = self:getOperatingTime()
        self:raiseDirtyFlags(spec.dirtyFlag)
    end
end

---------------------
-- Injections
---------------------

---Reduce time to next service if working hard.
function SeasonsAgeWear:inj_onUpdateTick(superFunc, dt, isActive, isActiveForInput, isSelected)
    superFunc(self, dt, isActive, isActiveForInput, isSelected)

    local specVehicle = self:seasons_getSpecTable("seasonsVehicle")
    local specWear = self.spec_wearable

    specVehicle.nextRepair = specVehicle.nextRepair - math.max(specWear:getWorkMultiplier() - 1, 0) * dt / (60 * 60 * 1000)
end

--- TODO: Delay as opTime changes every tick. Also make it additive instead of overwriting so we can reset it with painting
function SeasonsAgeWear:inj_setOperatingTime(superFunc, operatingTime, isLoading)
    superFunc(self, operatingTime, isLoading)

    -- Scratches are updating using a network sync
    if self.isServer then
        local nodes = self.spec_wearable.wearableNodes
        if nodes ~= nil then
            for _, nodeData in ipairs(nodes) do
                local amount = self:getOperatingTimeBasedWearAmount()
                self:setNodeScratchAmount(nodeData, amount)
            end
        end
    end

    -- Update total, used for applying damage
    self.spec_wearable.totalAmount = self:getWearTotalAmount()
end

---Disable shader changes for Wearable
function SeasonsAgeWear:inj_setNodeWearAmount(superFunc, nodeData, wearAmount, force)
    local nodes = nodeData.nodes
    nodeData.nodes = {} -- empty list so they can't be updated

    superFunc(self, nodeData, wearAmount, force)

    nodeData.nodes = nodes
end

function SeasonsAgeWear:inj_getIntervalMultiplier(superFunc)
    return superFunc(self) / SeasonsAgeWear.NORM_FACTOR
end
