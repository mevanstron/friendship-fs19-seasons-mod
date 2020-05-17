----------------------------------------------------------------------------------------------------
-- SeasonsSnowTracks
----------------------------------------------------------------------------------------------------
-- Purpose:  Snow tracks for wheels
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsSnowTracks = {}

SeasonsSnowTracks.SNOWLAYER_THRESHOLD = 1
SeasonsSnowTracks.SNOW_TIRE_TRACK_COLOR = { 0.95, 0.95, 0.95, 1, 1 }
SeasonsSnowTracks.SNOW_DIRT_MULTIPLIER = 75

-- Todo: what todo with the following:
-- Mud
-- Offroad
-- Street
SeasonsSnowTracks.FRICTION_TIRETYPE_SETTINGS = {
    ["chains"] = 1.0,
    ["crawler"] = 0.5,
    ["studded"] = 0.7
}
-- Default friction
SeasonsSnowTracks.SNOW_TIRE_FRICTION = GS_IS_CONSOLE_VERSION and 0.4 or 0.3

function SeasonsSnowTracks.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Wheels, specializations)
end

function SeasonsSnowTracks.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "updateWheelSnowTracks", SeasonsSnowTracks.updateWheelSnowTracks)
    SpecializationUtil.registerFunction(vehicleType, "updateWheelSnowTracksFriction", SeasonsSnowTracks.updateWheelSnowTracksFriction)
    SpecializationUtil.registerFunction(vehicleType, "isWheelInSnow", SeasonsSnowTracks.isWheelInSnow)
    SpecializationUtil.registerFunction(vehicleType, "getHasSnowContact", SeasonsSnowTracks.getHasSnowContact)
    SpecializationUtil.registerFunction(vehicleType, "getSnowLayers", SeasonsSnowTracks.getSnowLayers)
    SpecializationUtil.registerFunction(vehicleType, "getWheelParallelogram", SeasonsSnowTracks.getWheelParallelogram)
end

function SeasonsSnowTracks.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateWheelContact", SeasonsSnowTracks.inj_updateWheelTireTracks)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateWheelFriction", SeasonsSnowTracks.inj_updateWheelFriction)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getTireTrackColor", SeasonsSnowTracks.inj_getTireTrackColor)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateWheelDirtAmount", SeasonsSnowTracks.inj_updateWheelDirtAmount)
end

function SeasonsSnowTracks.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", SeasonsSnowTracks)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", SeasonsSnowTracks)
end

function SeasonsSnowTracks:onLoad(savegame)
    local spec = self:seasons_getSpecTable("snowTracks")

    -- NOTE(JK): I don't like this global call, but the vehicle system is very on itself and does not allow setting
    -- variables easily... or at all.
    spec.snowHandler = g_seasons.snowHandler
end

function SeasonsSnowTracks:onPostLoad(savegame)
    local spec = self:seasons_getSpecTable("wheels")

    for _, wheel in pairs(spec.wheels) do
        wheel.isInSnow = false
    end
end

function SeasonsSnowTracks:onLoadFinished(savegame)
end

---Update the snow tracks of a wheel
function SeasonsSnowTracks:updateWheelSnowTracks(wheel, isAdditionalWheel)
    if (not wheel.hasGroundContact and not isAdditionalWheel)
        or not self.isServer
        or not self.isAddedToPhysics then
        return
    end

    local spec = self:seasons_getSpecTable("snowTracks")
    local snowHandler = spec.snowHandler

    -- Contact is already calculated so use it. Do not only check for Height contact because when the wheel sinks
    -- into the snow it touches the ground instead. (<=2 layers)
    if wheel.contact == Wheels.WHEEL_GROUND_HEIGHT_CONTACT or wheel.contact == Wheels.WHEEL_GROUND_CONTACT or isAdditionalWheel then
        wheel.isInSnow = self:isWheelInSnow(wheel, snowHandler)
    else
        wheel.isInSnow = false
    end

    if wheel.isInSnow then
        local targetSnowDepth = math.min(snowHandler.MAX_HEIGHT, snowHandler.height) -- Target snow depth in meters. Never higher than 0.48
        local targetSnowLayers = math.modf(targetSnowDepth / snowHandler.LAYER_HEIGHT)

        -- Use a parallogram to calculate the average snow height. Using the density height at 1 point does not work
        -- as it does not average.
        local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ = self:getWheelParallelogram(wheel, isAdditionalWheel)
        wheel.snowLayers = self:getSnowLayers(snowHandler, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
        local reduceSnow = targetSnowLayers == wheel.snowLayers
        local isOnSnowHeap = targetSnowLayers == 0 and wheel.snowLayers > SeasonsSnowTracks.SNOWLAYER_THRESHOLD

        if wheel.snowLayers > SeasonsSnowTracks.SNOWLAYER_THRESHOLD and (reduceSnow or isOnSnowHeap) then
            local sink = 0.7 * targetSnowDepth
            if isOnSnowHeap then
                sink = 0.1 * (wheel.snowLayers * snowHandler.LAYER_HEIGHT)
            end

            local sinkLayers = math.min(math.modf(sink / snowHandler.LAYER_HEIGHT), wheel.snowLayers)
            snowHandler:removeSnow(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, sinkLayers)
        end
    end
end

function SeasonsSnowTracks:updateWheelSnowTracksFriction(wheel)
    if not wheel.isInSnow or not self.isServer then
        return
    end

    if self:getLastSpeed() < 0.2 then
        return
    end

    local spec = self:seasons_getSpecTable("snowTracks")
    local tireSnowDepth = wheel.snowLayers / spec.snowHandler.LAYER_HEIGHT / 100 -- tireSnowDepth in m
    local tireType = WheelsUtil.tireTypes[wheel.tireType]

    local coeffTire = SeasonsSnowTracks.FRICTION_TIRETYPE_SETTINGS[tireType.name]
    if coeffTire == nil then
        coeffTire = SeasonsSnowTracks.SNOW_TIRE_FRICTION
    end

    local coeffSnow = coeffTire * 0.2
    local coeff = MathUtil.round(coeffTire + coeffSnow * (1 - tireSnowDepth), 2)

    if wheel.tireGroundFrictionCoeff ~= coeff then
        wheel.tireGroundFrictionCoeff = coeff
        self:setWheelTireFrictionDirty(wheel)
    end
end

---Get whether a wheel is in snow of at least 1 (0 gives no type)
function SeasonsSnowTracks:isWheelInSnow(wheel, snowHandler)
    local wx, wy, wz = 0, 0, 0
    if wheel.netInfo ~= nil then
        wx, wy, wz = wheel.netInfo.x, wheel.netInfo.y, wheel.netInfo.z
    else
        wx, wy, wz = worldToLocal(wheel.node, getWorldTranslation(wheel.wheelTire))
    end

    wy = wy - wheel.radius
    wx = wx + wheel.xOffset
    wx, wy, wz = localToWorld(wheel.node, wx, wy, wz)

    local terrainDetail = g_currentMission.terrainDetailHeightId

    -- Get density value
    local density = getDensityAtWorldPos(terrainDetail, wx, wy, wz)

    -- Extract type and height
    local heightType = bitAND(density, 2 ^ g_currentMission.terrainDetailHeightTypeNumChannels - 1)

    return heightType == snowHandler.snowHeightType.index
end

---Get whether the vehicle has contact with snow
function SeasonsSnowTracks:getHasSnowContact()
    local spec = self:seasons_getSpecTable("wheels")

    local wheel = spec.wheels[1]
    if wheel ~= nil then
        if not wheel.isInSnow then
            local lastWheel = spec.wheels[#spec.wheels]
            return lastWheel.isInSnow
        end

        return wheel.isInSnow
    end

    return false
end

---Get a parallelogram covering the ground the wheel is on
function SeasonsSnowTracks:getWheelParallelogram(wheel, isAdditionalWheel)
    local x, y, z = wheel.positionX, wheel.positionY, wheel.positionZ
    local node = wheel.node
    local width = wheel.width * 0.5

    local dir = -1
    if self.movingDirection > 0 then
        dir = 1
    end

    local delta1 = -0.6 * wheel.radius * dir
    local delta2 = 1.2 * wheel.radius * dir

    if wheel.repr ~= wheel.driveNode and not isAdditionalWheel then
        node = wheel.repr
        x, y, z = localToLocal(wheel.driveNode, wheel.repr, 0, 0, 0)
    end

    if isAdditionalWheel then
        x, y, z = localToLocal(wheel.wheelTire, node, 0, 0, 0)
    end

    local x0, _, z0 = localToWorld(node, x + width, y, z - delta1)
    local x1, _, z1 = localToWorld(node, x - width, y, z - delta1)
    local x2, _, z2 = localToWorld(node, x + width, y, z + delta2)

    return x0, z0, x1, z1, x2, z2
end

---Get the number of snow layers below a wheel
function SeasonsSnowTracks:getSnowLayers(snowHandler, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
    local modifiers = snowHandler.modifiers.height
    local modifier = modifiers.modifierHeight
    local filter = modifiers.filterSnowType

    modifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, "ppp")

    local density, area, _ = modifier:executeGet(filter)
    if area == 0 then
        -- Prevent nan
        return 0
    end

    local layers = density / area

    return layers
end

---------------------
-- Injections
---------------------

function SeasonsSnowTracks.inj_updateWheelTireTracks(vehicle, superFunc, wheel)
    superFunc(vehicle, wheel)

    if g_seasons.vehicle:getSnowTracksEnabled() then
        vehicle:updateWheelSnowTracks(wheel, false)

        if wheel.additionalWheels ~= nil then
            for _, additionalWheel in pairs(wheel.additionalWheels) do
                vehicle:updateWheelSnowTracks(additionalWheel, true)
            end
        end
    end
end

function SeasonsSnowTracks.inj_updateWheelFriction(vehicle, superFunc, wheel, dt)
    if not wheel.isInSnow then
        -- We need to set this else the tireGroundFrictionCoeff is overwritten each frame
        superFunc(vehicle, wheel, dt)
    end

    vehicle:updateWheelSnowTracksFriction(wheel)
end

function SeasonsSnowTracks.inj_getTireTrackColor(vehicle, superFunc, wheel, wx, wy, wz)
    if wheel.isInSnow then
        local r, g, b, a, w = unpack(SeasonsSnowTracks.SNOW_TIRE_TRACK_COLOR)

        wheel.lastColor[1] = r
        wheel.lastColor[2] = g
        wheel.lastColor[3] = b

        return r, g, b, a, w
    end

    return superFunc(vehicle, wheel, wx, wy, wz)
end

function SeasonsSnowTracks.inj_updateWheelDirtAmount(vehicle, superFunc, nodeData, dt)
    local amount = superFunc(vehicle, nodeData, dt)

    if nodeData.wheel ~= nil and nodeData.wheel.isInSnow then
        local isOnField = nodeData.wheel.densityType ~= 0
        if not isOnField then
            return amount * SeasonsSnowTracks.SNOW_DIRT_MULTIPLIER
        end
    end

    return amount
end
