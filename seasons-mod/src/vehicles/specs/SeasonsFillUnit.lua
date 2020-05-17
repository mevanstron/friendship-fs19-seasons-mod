----------------------------------------------------------------------------------------------------
-- SeasonsFillUnit
----------------------------------------------------------------------------------------------------
-- Purpose:  Add snow when it is snowing, remove snow when it is warm, and rot grass.
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsFillUnit = {}

function SeasonsFillUnit.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(FillUnit, specializations)
        and SpecializationUtil.hasSpecialization(Dischargeable, specializations)
end

function SeasonsFillUnit.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "onIntervalUpdate", SeasonsFillUnit.onIntervalUpdate)
    SpecializationUtil.registerFunction(vehicleType, "onQuarterOfAnHourChanged", SeasonsFillUnit.onQuarterOfAnHourChanged)
    SpecializationUtil.registerFunction(vehicleType, "isVehicleOutside", SeasonsFillUnit.isVehicleOutside)
    SpecializationUtil.registerFunction(vehicleType, "needsFillUnitUpdateForSeasons", SeasonsFillUnit.needsFillUnitUpdateForSeasons)
    SpecializationUtil.registerFunction(vehicleType, "updateFillUnitsForSeasons", SeasonsFillUnit.updateFillUnitsForSeasons)
    SpecializationUtil.registerFunction(vehicleType, "onGrassRot", SeasonsFillUnit.onGrassRot)
    SpecializationUtil.registerFunction(vehicleType, "isCoverOpen", SeasonsFillUnit.isCoverOpen)
end

function SeasonsFillUnit.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addFillUnitFillLevel", SeasonsFillUnit.inj_addFillUnitFillLevel)
end

function SeasonsFillUnit.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", SeasonsFillUnit)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", SeasonsFillUnit)
end

function SeasonsFillUnit:onDelete()
    g_seasons.vehicle:removeVehicleFromToUpdateList(self)
end

function SeasonsFillUnit:onUpdateTick(dt)
    -- We only check when we are active
    if self.isServer then
        if not g_seasons.weather:isSnowing() then
            return
        end

        local isInList = g_seasons.vehicle:isVehicleInUpdateList(self)

        -- when we are not in the list we check if it's snowing and if we are outside
        if not isInList and self:isCoverOpen() and self:isVehicleOutside() then
            g_seasons.vehicle:addVehicleToUpdateList(self)
        end
    end
end

---Called by the SeasonsVehicle on an interval.
---@param dt number
function SeasonsFillUnit:onIntervalUpdate(dt)
    self:updateFillUnitsForSeasons(dt)
end

---Called by the SeasonsVehicle on an interval of 15 minutes.
---@param dt number
function SeasonsFillUnit:onQuarterOfAnHourChanged(dt)
    self:onGrassRot(dt)
end

---Returns true if vehicle is detected on the mask, false otherwise.
function SeasonsFillUnit:isVehicleOutside()
    if not g_seasons.mask:hasMask() then
        return false
    end

    -- Don't take the full vehicle width and length to ensure we only mask the vehicle area
    local node = self.components[1].node
    local width = self.sizeWidth * 0.75
    local length = self.sizeLength * 0.75

    local x, y, z = localToWorld(node, width * 0.5, 0, length * 0.5)
    local dx, _, dz = localDirectionToWorld(node, 0, 0, 1)
    local sx, sz = -dz, dx

    local x0 = x
    local z0 = z
    local x1 = x0 + sx * width
    local z1 = z0 + sz * width
    local x2 = x0 - dx * length
    local z2 = z0 - dz * length

    -- If debug
    DebugUtil.drawDebugAreaRectangle(x0, y, z0, x1, y, z1, x2, y, z2, true, 1, 0, 0)

    local density = g_seasons.mask:getDensityAt(x0, z0, x1, z1, x2, z2)

    return density == 0
end

---Returns true when the trailer has the cover in an open state, false otherwise
function SeasonsFillUnit:isCoverOpen()
    local spec = self:seasons_getSpecTable("cover")

    if spec == nil or not spec.hasCovers then
        return true
    end

    return spec.state ~= 0
end

---Returns true when the unit is empty, false otherwise
local function isUnitEmpty(unit)
    return unit.fillLevel == 0
end

---Returns true when the filltype allows rotting, false otherwise
function SeasonsFillUnit.canFillTypeRot(fillType)
    return fillType == FillType.DRYGRASS_WINDROW or fillType == FillType.STRAW
end

---Returns true if the unit needs and update, false otherwise.
function SeasonsFillUnit:needsFillUnitUpdateForSeasons(fillUnitIndex)
    local fillType = self:getFillUnitLastValidFillType(fillUnitIndex)

    if fillType == FillType.SNOW
        or fillType == FillType.GRASS_WINDROW
        or fillType == FillType.DRYGRASS_WINDROW
        or fillType == FillType.STRAW then
        return true
    end

    local unit = self:getFillUnitByIndex(fillUnitIndex)

    return isUnitEmpty(unit) and self:getFillUnitSupportsFillType(fillUnitIndex, FillType.SNOW)
end

---Rots grass if present in the fill unit.
function SeasonsFillUnit:onGrassRot(dt)
    local farmId = self:getOwnerFarmId()
    for index, unit in ipairs(self:getFillUnits()) do
        local fillType = self:getFillUnitLastValidFillType(index)
        if fillType == FillType.GRASS_WINDROW then
            local rotValue = -unit.capacity / 200
            self:addFillUnitFillLevel(farmId, index, rotValue, fillType, ToolType.UNDEFINED, nil)
        end
    end
end

---Updates the fill units based on the conditions.
function SeasonsFillUnit:updateFillUnitsForSeasons(dt)
    local weather = g_seasons.weather
    local isCoverOpen = self:isCoverOpen()
    local isOutside = self:isVehicleOutside()
    local isFreezing = weather:getIsFreezing()
    local allowAddSnow = weather:isSnowing() and isCoverOpen and isOutside
    local allowRotting = weather.handler:getTimeSinceLastRain() < 5 and isCoverOpen and isOutside

    -- Do not add snow when it would be tipped out immediatly.
    if self.getShovelTipFactor ~= nil and self:getShovelTipFactor() > 0 then
        allowAddSnow = false
    end

    -- It's useless to update the fillUnits at this point.
    if isFreezing
        and not allowAddSnow
        and not allowRotting then
        g_seasons.vehicle:removeVehicleFromToUpdateList(self)
    end

    local farmId = self:getOwnerFarmId()
    local fillUnits = self:getFillUnits()
    for index, unit in ipairs(fillUnits) do
        local dischargable = self.spec_dischargeable.fillUnitDischargeNodeMapping[index]

        -- Do not add snow when it can't be put back on ground, like with train wagons
        if dischargable ~= nil and dischargable.canDischargeToGround then
            local fillType = self:getFillUnitLastValidFillType(index)

            -- Perhaps force snow add some fillLevel threshold? so eg if level < 500 force snow
            if fillType == FillType.SNOW or isUnitEmpty(unit) then
                if allowAddSnow then
                    SeasonsFillUnit.addSnowToUnit(self, farmId, index, dt)
                end

                if not isFreezing then
                    SeasonsFillUnit.meldSnowInUnit(self, farmId, index, dt)
                end
            elseif allowRotting and SeasonsFillUnit.canFillTypeRot(fillType) then
                -- We only rot straw and dry grass when it's rained upon
                SeasonsFillUnit.rotInUnit(self, farmId, index, fillType, dt)
            end
        end
    end
end

local function getUnitAddValue(value, multiplier, width, length, dt)
    return value * width * length * 1000 / 60 / 60 * (dt / 1000) * multiplier
end

---Adds snow to the fill unit based on the the current downfall amount
---@param self table
---@param farmId number
---@param fillUnitIndex number
---@param dt number
function SeasonsFillUnit.addSnowToUnit(self, farmId, fillUnitIndex, dt)
    local intensity = g_seasons.weather:getDownfallState()
    local value = math.max(0.5 * intensity, 0.05)
    local add = getUnitAddValue(value, 1, self.sizeWidth, self.sizeLength, dt)
    self:addFillUnitFillLevel(farmId, fillUnitIndex, add, FillType.SNOW, ToolType.UNDEFINED, nil)
end

---Melds the snow in the fill unit based on the the current temperature
---@param self table
---@param farmId number
---@param fillUnitIndex number
---@param dt number
function SeasonsFillUnit.meldSnowInUnit(self, farmId, fillUnitIndex, dt)
    local temp = g_seasons.weather:getCurrentAirTemperature()
    local add = getUnitAddValue(-0.1, temp, self.sizeWidth, self.sizeLength, dt)
    self:addFillUnitFillLevel(farmId, fillUnitIndex, add, FillType.SNOW, ToolType.UNDEFINED, nil)
end

---Rots the given fillType in the fill unit
---@param self table
---@param farmId number
---@param fillUnitIndex number
---@param fillType number
---@param dt number
function SeasonsFillUnit.rotInUnit(self, farmId, fillUnitIndex, fillType, dt)
    if fillType == FillType.UNKNOWN then
        return
    end

    local add = getUnitAddValue(-1, 0.1, self.sizeWidth, self.sizeLength, dt)
    self:addFillUnitFillLevel(farmId, fillUnitIndex, add, fillType, ToolType.UNDEFINED, nil)
end

---------------------
-- Injections
---------------------

function SeasonsFillUnit.inj_addFillUnitFillLevel(vehicle, superFunc, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    local delta = superFunc(vehicle, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)

    if vehicle.isServer then
        if vehicle:needsFillUnitUpdateForSeasons(fillUnitIndex) then
            g_seasons.vehicle:addVehicleToUpdateList(vehicle)
        else
            g_seasons.vehicle:removeVehicleFromToUpdateList(vehicle)
        end
    end

    return delta
end
