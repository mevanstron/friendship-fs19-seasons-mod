----------------------------------------------------------------------------------------------------
-- SeasonsVehicleSpec
----------------------------------------------------------------------------------------------------
-- Purpose:  Gives vehicles a yearly age and updates economics
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsVehicleSpec = {}

function SeasonsVehicleSpec.prerequisitesPresent(specializations)
    return true
end

function SeasonsVehicleSpec.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getYears", SeasonsVehicleSpec.getYears)
end

function SeasonsVehicleSpec.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "dayChanged", SeasonsVehicleSpec.dayChanged)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSellPrice", SeasonsVehicleSpec.getSellPrice)
end

function SeasonsVehicleSpec.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", SeasonsVehicleSpec)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", SeasonsVehicleSpec)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", SeasonsVehicleSpec)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", SeasonsVehicleSpec)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", SeasonsVehicleSpec)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", SeasonsVehicleSpec)
end

function SeasonsVehicleSpec.initSpecialization()
end

function SeasonsVehicleSpec:onLoad(savegame)
    local spec = self:seasons_getSpecTable("seasonsVehicle")

    spec.dirtyFlag = self:getNextDirtyFlag()
    spec.years = 0
    spec.nextRepair = 30 * 60 * 60 -- 30 hours in seconds + operatingTime
end

function SeasonsVehicleSpec:onPostLoad(savegame)
    local spec = self:seasons_getSpecTable("seasonsVehicle")

    --todo: apparently not working
    if savegame ~= nil and not savegame.resetVehicles then
        local opTime = self:getOperatingTime()
        local key = self:seasons_getSpecSaveKey(savegame.key, "seasonsVehicle")
        spec.years = Utils.getNoNil(getXMLFloat(savegame.xmlFile, key .. "#years"), spec.years)
        spec.nextRepair = Utils.getNoNil(getXMLFloat(savegame.xmlFile, key .. "#nextRepair"), spec.nextRepair + opTime)
    end
end

function SeasonsVehicleSpec:onReadStream(streamId, connection)
    local spec = self:seasons_getSpecTable("seasonsVehicle")

    spec.years = streamReadFloat32(streamId)
    spec.nextRepair = streamReadFloat32(streamId)
end

function SeasonsVehicleSpec:onWriteStream(streamId, connection)
    local spec = self:seasons_getSpecTable("seasonsVehicle")

    streamWriteFloat32(streamId, spec.years)
    streamWriteFloat32(streamId, spec.nextRepair)
end

function SeasonsVehicleSpec:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        local spec = self:seasons_getSpecTable("seasonsVehicle")

        if streamReadBool(streamId) then
            spec.years = streamReadFloat32(streamId)
            spec.nextRepair = streamReadFloat32(streamId)
        end
    end
end

function SeasonsVehicleSpec:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self:seasons_getSpecTable("seasonsVehicle")

        if streamWriteBool(streamId, bitAND(dirtyMask, spec.dirtyFlag) ~= 0) then
            streamWriteFloat32(streamId, spec.years)
            streamWriteFloat32(streamId, spec.nextRepair)
        end
    end
end

function SeasonsVehicleSpec:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self:seasons_getSpecTable("seasonsVehicle")

    setXMLFloat(xmlFile, key .. "#years", spec.years)
    setXMLFloat(xmlFile, key .. "#nextRepair", spec.nextRepair)
end

function SeasonsVehicleSpec:dayChanged(superFunc)
    superFunc(self)

    local spec = self:seasons_getSpecTable("seasonsVehicle")
    spec.years = spec.years + 1 / (4 * g_seasons.environment.daysPerSeason)
end

---Get the age of the vehicle in years
function SeasonsVehicleSpec:getYears()
    local spec = self:seasons_getSpecTable("seasonsVehicle")

    return spec.years
end

---Create a new sell price
function SeasonsVehicleSpec:getSellPrice(superFunc)
    local spec = self:seasons_getSpecTable("seasonsVehicle")
    local storeItem = g_storeManager:getItemByXMLFilename(self.configFileName)

    local price = self.price
    local minSellPrice = price * 0.03
    local sellPrice = 0
    local operatingTime = self.operatingTime / (60 * 60 * 1000) -- hours
    local lifetime = storeItem.lifetime
    local age = spec.years

    local a = 1.0

    -- power is nil for non-motorized vehicles
    local power = storeItem.specs.power
    if power == nil then
        a = 1.3
    end

    local operatingTimeFactor = 1 - operatingTime ^ a / lifetime
    local ageFactor = math.min(-0.1 * math.log(age) + 0.75, 0.8)

    -- The first day you can try a vehicle for free for 30 min
    if age == 0 and operatingTime < 0.5 then
        sellPrice = price
    else
        -- 50% penalty for not repairing before selling
        sellPrice = math.max(price * operatingTimeFactor * ageFactor - self:getRepairPrice(true) * 1.5, minSellPrice)
    end

    return sellPrice
end
