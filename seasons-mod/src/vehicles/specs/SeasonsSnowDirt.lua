----------------------------------------------------------------------------------------------------
-- SeasonsSnowDirt
----------------------------------------------------------------------------------------------------
-- Purpose:  Makes snowfall visual on vehicles
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsSnowDirt = {}

SeasonsSnowDirt.SNOW_COLOR = { 0.95, 0.95, 0.95 }
SeasonsSnowDirt.SNOW_COLOR_ALPHA = 0.25

function SeasonsSnowDirt.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Washable, specializations)
end

function SeasonsSnowDirt.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "updateSnowDirtAmount", SeasonsSnowDirt.updateSnowDirtAmount)
end

function SeasonsSnowDirt.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setNodeDirtAmount", SeasonsSnowDirt.setNodeDirtAmount)
end

function SeasonsSnowDirt.registerEventListeners(vehicleType)
    -- SpecializationUtil.registerEventListener(vehicleType, "onLoadFinished", SeasonsSnowDirt)
end

-- Disabled: this currently breaks MP sync.
-- function SeasonsSnowDirt:onLoadFinished(savegame)
--     local spec = self:seasons_getSpecTable("washable")
--     if spec.washableNodes[1] ~= nil then
--         local nodeData = spec.washableNodes[1]
--         for _, node in pairs(nodeData.nodes) do
--             self:removeWashableNode(node) -- remove from global
--             self:addToLocalWashableNode(node, self.updateSnowDirtAmount, nil, { isSnowNode = true }) -- add to local
--         end
--     end
-- end

---Updates the dirtAmount depending on the snow weather event
---@param nodeData table
---@param dt number
function SeasonsSnowDirt:updateSnowDirtAmount(nodeData, dt)
    local dirtAmount = self:updateDirtAmount(nodeData, dt)

    if nodeData.isSnowNode then
        local weather = g_seasons.weather
        local timeSinceLastSnow = weather.handler:getTimeSinceLastRain()

        if weather:isSnowing() then
            if not self:getIsOnField() then
                local snowScale = weather.handler:getRainFallScale()

                if snowScale > 0.1 and timeSinceLastSnow < 30 then
                    local currentAmount = self:getNodeDirtAmount(nodeData)
                    if currentAmount < 0.9 then
                        dirtAmount = dirtAmount * 75
                    end
                end
            end
        else
            if timeSinceLastSnow < 15 then
                if not weather:getIsFreezing() then
                    dirtAmount = -(dt * 0.00001)
                end
            end
        end
    end

    return dirtAmount
end

function SeasonsSnowDirt:setNodeDirtAmount(superFunc, nodeData, dirtAmount, force)
    nodeData.dirtAmount = MathUtil.clamp(dirtAmount, 0, 1)

    local diff = nodeData.dirtAmountSent - nodeData.dirtAmount
    if force or math.abs(diff) > Washable.SEND_THRESHOLD then
        local weather = g_seasons.weather

        local isSnowing = weather:isSnowing()
        local hasSnowContact = SeasonsSnowDirt.isNodeDataWheelInSnow(nodeData)

        if nodeData.rmOriginalDirtColor == nil then
            nodeData.rmOriginalDirtColor = {}
        end

        for _, node in pairs(nodeData.nodes) do
            local rb, gb, bb, a = getShaderParameter(node, "dirtColor")
            if nodeData.rmOriginalDirtColor[node] == nil then
                nodeData.rmOriginalDirtColor[node] = { r = rb, g = gb, b = bb, a = a }
            end

            local target = nodeData.rmOriginalDirtColor[node]
            local rt, gt, bt = target.r, target.g, target.b
            if hasSnowContact or (isSnowing and nodeData.isSnowNode) then
                rt, gt, bt = unpack(SeasonsSnowDirt.SNOW_COLOR)
            end

            local r, g, b = MathUtil.vector3Lerp(rb, gb, bb, rt, gt, bt, SeasonsSnowDirt.SNOW_COLOR_ALPHA)
            setShaderParameter(node, "dirtColor", r, g, b, a, false)

            local x, _, z, w = getShaderParameter(node, "RDT")
            setShaderParameter(node, "RDT", x, nodeData.dirtAmount, z, w, false)
        end

        if self.isServer then
            local specWashable = self:seasons_getSpecTable("washable")
            self:raiseDirtyFlags(specWashable.dirtyFlag)
            nodeData.dirtAmountSent = nodeData.dirtAmount
        end
    end
end

---Get whether or not the wheel from the nodeData has contact with snow
function SeasonsSnowDirt.isNodeDataWheelInSnow(nodeData)
    if nodeData.wheel ~= nil then
        return nodeData.wheel.isInSnow
    end

    return false
end
