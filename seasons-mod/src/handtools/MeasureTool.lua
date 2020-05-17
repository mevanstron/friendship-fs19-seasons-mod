----------------------------------------------------------------------------------------------------
-- MeasureTool
----------------------------------------------------------------------------------------------------
-- Purpose:  Tool to read from objects, terrain and trees
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

MeasureTool = {}
local MeasureTool_mt = Class(MeasureTool, HandTool)

InitObjectClass(MeasureTool, "MeasureTool")

MeasureTool.MEASURE_TIME = 1700 -- ms
MeasureTool.MEASURE_TIME_VAR = 600
MeasureTool.MEASURE_TIMEOUT = 2000
MeasureTool.MEASURE_PULSE = 483
MeasureTool.BREATH_TIME = 4400

MeasureTool.MEASURE_DISTANCE = 5 -- meters

MeasureTool.BLINKING_MESSAGE_DURATION = MeasureTool.MEASURE_TIMEOUT


function MeasureTool:new(isServer, isClient, customMt)
    local self = HandTool:new(isServer, isClient, customMt or MeasureTool_mt)

    self.i18n = g_i18n
    self.mission = g_currentMission
    self.weather = g_seasons.weather

    return self
end

function MeasureTool:load(xmlFilename, player)
    if not MeasureTool:superClass().load(self, xmlFilename, player) then
        return false
    end

    local xmlFile = loadXMLFile("TempXML", xmlFilename)

    self.pricePerMilliSecond = Utils.getNoNil(getXMLFloat(xmlFile, "handTool.measureTool.pricePerSecond"), 50) / 1000
    self.moveCounter = 0

    if self.isClient then
        self.sampleMeasure = g_soundManager:loadSampleFromXML(xmlFile, "handTool.measureTool.sounds", "measure", self.baseDirectory, self.rootNode, 1, AudioGroup.VEHICLE, nil, nil)
    end

    delete(xmlFile)

    return true
end

function MeasureTool:delete()
    if self.isClient then
        g_soundManager:deleteSample(self.sampleMeasure)
    end

    MeasureTool:superClass().delete(self)
end

function MeasureTool:update(dt, allowInput)
    MeasureTool:superClass().update(self, dt, allowInput)

    if self.isServer and self.activatePressed then
        local price = self.pricePerMilliSecond * dt

        g_farmManager:getFarmById(self.player.farmId).stats:updateStats("expenses", price)
        self.mission:addMoney(-price, self.player.farmId, MoneyType.VEHICLE_RUNNING_COSTS)
    end

    if allowInput then
        if self.activatePressed and self.measuringTimeoutStart == nil then
            if self.measuringStart == nil then
                self.measuringStart = self.mission.time
                self.measureDuration = math.random(MeasureTool.MEASURE_TIME - MeasureTool.MEASURE_TIME_VAR, MeasureTool.MEASURE_TIME + MeasureTool.MEASURE_TIME_VAR)

                self.measureDuration = self.measureDuration - self.measureDuration % MeasureTool.MEASURE_PULSE
            end

            if self.isClient then
                if not g_soundManager:getIsSamplePlaying(self.sampleMeasure, 0) then
                    g_soundManager:playSample(self.sampleMeasure)
                end
            end
        else
            self.measuringStart = nil

            if self.isClient then
                g_soundManager:stopSample(self.sampleMeasure)
            end
        end

        -- Timers for scanning and timeout
        if self.measuringStart ~= nil and self.mission.time - self.measuringStart >= self.measureDuration then
            self.measuringStart = nil
            self.measuringTimeoutStart = self.mission.time

            if self.isClient then
                g_soundManager:stopSample(self.sampleMeasure)
            end

            self:performMeasurement()
        elseif self.measuringTimeoutStart ~= nil and self.mission.time - self.measuringTimeoutStart >= MeasureTool.MEASURE_TIMEOUT then
            self.measuringTimeoutStart = nil
        end
    end

    self.activatePressed = false
end

function MeasureTool:draw()
    MeasureTool:superClass().draw(self)

    local player = self.player
    local overlay = player.pickedUpObjectOverlay
    overlay:setUVs(player.pickedUpObjectAimingUVs)

    if self.player:getIsInputAllowed() then
        -- Draw pointer, which is also a measure indicator
        local scale = 1
        if self.measuringStart ~= nil then
            local timeLapsed = self.mission.time - self.measuringStart
            local pulse = math.abs(math.sin(timeLapsed / MeasureTool.MEASURE_PULSE * math.pi))

            scale = pulse * 0.6 + 0.4
        elseif self.measuringTimeoutStart ~= nil then
            overlay:setColor(0.6514, 0.0399, 0.0399, 0.3)
        else
            overlay:setColor(1, 1, 1, 0.3)
        end

        overlay:setDimension(player.pickedUpObjectAimingWidth * scale, player.pickedUpObjectAimingHeight * scale)
    else
        overlay:setDimension(player.pickedUpObjectAimingWidth, player.pickedUpObjectAimingHeight)
    end

    if self.blinkingMessage then
        self.mission:showBlinkingWarning(self.blinkingMessage)

        if self.blinkingMessageUntil > self.mission.time then
            self.blinkingMessage = nil
        end
    else
        overlay:render()
    end
end

function MeasureTool:onDeactivate(allowInput)
    MeasureTool:superClass().onDeactivate(self)

    if self.isClient then
        local overlay = self.player.pickedUpObjectOverlay
        overlay:setColor(1, 1, 1, 0.3)
    end
end

function MeasureTool:performMeasurement()
    -- Raycast from the player
    local x, y, z = localToWorld(self.player.cameraNode, 0, 0, 0.5)
    local dx, dy, dz = localDirectionToWorld(self.player.cameraNode, 0, 0, -1)

    raycastClosest(x, y, z, dx, dy, dz, "raycastCallback", MeasureTool.MEASURE_DISTANCE, self, 32+64+128+256+4096)
end

---Callback called by the raycaster
function MeasureTool:raycastCallback(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex, hitShapeId)
    -- Too close or too far away
    if hitObjectId == 0 then
        self:showFailed()

    -- We did only hit the terrain
    elseif hitObjectId == self.mission.terrainRootNode then
        self:showTerrainInfo(x, y, z)

    -- Some other object
    else
        local type = getRigidBodyType(hitObjectId)

        -- Skip vehicles
        if type == "NoRigidBody" then
            self:showFailed()
        else -- Any object, either static or dynamic
            local object = self.mission:getNodeObject(hitObjectId)
            if object then
                self.currentObject = object

                -- Ask the server for more info
                if not self.isServer then
                    g_client:getServerConnection():sendEvent(SeasonsMeasurementRequestEvent:new(object))
                end

                if object:isa(Bale) then
                    self:showBaleInfo(object)
                elseif object:isa(Vehicle) then
                    local vehicle = object

                    if hitObjectId ~= hitShapeId then
                        local parentId = hitShapeId
                        while parentId ~= 0 do
                            if self.mission.nodeToObject[parentId] ~= nil then
                                vehicle = self.mission.nodeToObject[parentId]
                                break
                            end

                            parentId = getParent(parentId)
                        end
                    end

                    if self:isPallet(vehicle) then
                        self:showFillablePallet(vehicle)
                    end
                elseif object:isa(TreePlaceable) then
                    local nameI18N
                    local storeItem = g_storeManager:getItemByXMLFilename(object.configFileName)
                    if storeItem then
                        nameI18N = storeItem.name
                    end

                    self:showStaticTreeInfo({
                        nameI18N = nameI18N
                    })
                end
            else
                local tree = self:findTree(hitObjectId)

                if tree == nil and not self.isServer then
                    local serverId = self:findClientTree(hitObjectId)
                    if serverId ~= nil then
                        g_client:getServerConnection():sendEvent(SeasonsMeasurementRequestEvent:new(nil, serverId))
                        self.currentObject = serverId
                        self:showPlantedTreeInfo(nil, true)
                    else
                        self:showNoInfo()
                    end
                else
                    if tree then
                        self:showPlantedTreeInfo(tree)
                    elseif getSplitType(hitObjectId) ~= 0 then
                        self:showStaticTreeInfo({treeType = getSplitType(hitObjectId)})
                    else
                        self:showNoInfo()
                    end
                end
            end
        end
    end

    return true
end

-- TODO: more strict!
function MeasureTool:isPallet(vehicle)
    local fillUnits = vehicle:getFillUnits()
    if #fillUnits > 0 then
        return true
    end

    return false
end

function MeasureTool:findClientTree(objectId)
    if getRigidBodyType(objectId):lower() ~= "static" then
        return nil
    end

    local treeId = getParent(getParent(objectId))

    for serverSplitShapeFileId, nodeId in pairs(g_treePlantManager.treesData.clientTrees) do
        if nodeId == treeId then
            return serverSplitShapeFileId
        end
    end

    return nil
end

---Try finding a planted tree for given object
function MeasureTool:findTree(objectId)
    if getRigidBodyType(objectId):lower() ~= "static" then
        return nil
    end

    local treeId = getParent(getParent(objectId))

    for _, tree in pairs(g_treePlantManager.treesData.growingTrees) do
        if tree.node == treeId then
            tree.growing = true

            return tree
        end
    end

    for _, tree in pairs(g_treePlantManager.treesData.splitTrees) do
        if tree.node == treeId then
            tree.growing = false

            return tree
        end
    end

    return nil
end

function MeasureTool:showFailed()
    self.blinkingMessage = self.i18n:getText("seasons_measuretool_failed")
    self.blinkingMessageUntil = self.mission.time + MeasureTool.BLINKING_MESSAGE_DURATION
end

function MeasureTool:showNoInfo()
    self.blinkingMessage = self.i18n:getText("seasons_measuretool_no_info")
    self.blinkingMessageUntil = self.mission.time + MeasureTool.BLINKING_MESSAGE_DURATION
end

function MeasureTool:showTerrainInfo(x, y, z)
    local data = {}

    -- Get spray level but only on fields
    local sprayLevel = self:getSprayInformation(x, z)

    -- Get fruit and fruit height
    local crop = self:getCropInformation(x, z)

    -- Create world coordinates
    local worldSize = self.mission.terrainSize
    local normalizedPlayerPosX = MathUtil.clamp((x + worldSize * 0.5) / worldSize, 0, 1)
    local normalizedPlayerPosZ = MathUtil.clamp((z + worldSize * 0.5) / worldSize, 0, 1)

    local posX = normalizedPlayerPosX * worldSize
    local posZ = normalizedPlayerPosZ * worldSize

    table.insert(data, {
        iconUVs = MeasureTool.UVS.COMPASS,
        text = string.format("%.2f, %.2f", posX, posZ)
    })

    local terrainHeight = getTerrainHeightAtWorldPos(self.mission.terrainRootNode, x, 0, z)
    table.insert(data, {
        iconUVs = MeasureTool.UVS.ELEVATION,
        text = self:formatLength(terrainHeight)
    })

    if crop ~= nil then
        local length = 0
        local densityState = crop.state - 1
        local numStates = crop.desc.numGrowthStates - 1

        if densityState <= numStates then
            length = MathUtil.clamp(densityState / numStates, 0, 1)
        end

        table.insert(data, {
            iconUVs = MeasureTool.UVS.CROP_TYPE,
            text = g_fruitTypeManager:getFillTypeByFruitTypeIndex(crop.index).title
        })

        table.insert(data, {
            iconUVs = MeasureTool.UVS.CROP_HEIGHT,
            text = string.format("%.0f%%", length * 100)
        })

        local growingMoisture = 0
        if crop.state == crop.desc.minHarvestingGrowthState - 1 then
            growingMoisture = 25
        elseif crop.state < crop.desc.minHarvestingGrowthState - 1 then
            growingMoisture = 50
        end

        local moisture = math.max(math.min(self.weather.cropMoistureContent + growingMoisture, 90), 0)
        table.insert(data, {
            iconUVs = MeasureTool.UVS.CROP_MOISTURE,
            text = string.format("%.0f%%", moisture)
        })
    end

    if sprayLevel ~= nil then
        table.insert(data, {
            iconUVs = MeasureTool.UVS.FERTILIZATION,
            text = string.format("%.0f%%", sprayLevel / self.mission.sprayLevelMaxValue * 100)
        })
    end

    local moisture = math.max(math.min(self.mission.environment.weather:getGroundWetness(), 1), 0)
    table.insert(data, {
        iconUVs = MeasureTool.UVS.MOISTURE,
        text = string.format("%.0f%%", moisture * 100)
    })

    self:openDialog(data)
end

function MeasureTool:formatLength(meters)
    if self.i18n.useMiles then
        return string.format("%.1f %s", meters * 3.2808, self.i18n:getText("unit_feetShort"))
    end

    return string.format("%.1f %s", meters, self.i18n:getText("unit_meterShort"))
end

function MeasureTool:showBaleInfo(bale)
    local data = {}

    local fillType = bale:getFillType()
    local fillLevel = bale:getFillLevel()

    -- Anderson pack tubes, show tube contents
    if bale.connectedInline ~= nil then
        local inlineBale = bale.connectedInline
        fillLevel = 0

        for _, connectedBale in ipairs(inlineBale:getBales()) do
            fillLevel = fillLevel + connectedBale:getFillLevel()
        end
    end

    table.insert(data, {
        iconUVs = MeasureTool.UVS.CONTENTS,
        text = string.format("%s (%.0f %s)", g_fillTypeManager:getFillTypeByIndex(fillType).title, fillLevel, self.i18n:getText("unit_literShort"))
    })

    if bale.wrappingState == 1 and bale.fermentingProcess ~= nil then
        table.insert(data, self:makeBaleFermentationData(fillType, bale.fermentingProcess))
    end

    self:openDialog(data)
end

function MeasureTool:showFillablePallet(pallet)
    local data = {}

    for fillUnitIndex, unit in ipairs(pallet:getFillUnits()) do
        local fillType = pallet:getFillUnitFillType(fillUnitIndex)
        local fillLevel = pallet:getFillUnitFillLevel(fillUnitIndex)

        table.insert(data, {
            iconUVs = MeasureTool.UVS.CONTENTS,
            text = string.format("%s (%d)", g_fillTypeManager:getFillTypeByIndex(fillType).title, fillLevel)
        })
    end

    if fillType == FillType.TREESAPLINGS then
        table.insert(data, {
            iconUVs = MeasureTool.UVS.TREE_TYPE,
            text = g_treePlantManager:getTreeTypeDescFromIndex(self:getTreeTypeFromPallet(pallet)).nameI18N
        })
    end

    self:openDialog(data)
end

---Gets the spray information at the given location.
function MeasureTool:getSprayInformation(x, z)
    FieldUtil.sprayModifier:setParallelogramWorldCoords(x - 0.5, z - 0.5, 1,0, 0,1, "pvv")
    local area, totalArea, _ = FieldUtil.sprayModifier:executeGet(FieldUtil.terrainDetailFilter)
    if totalArea ~= 0 then -- on field
        return area / totalArea
    end

    return nil
end

---Gets the crop information at the given location.
function MeasureTool:getCropInformation(x, z)
    local modifier = self.mission.densityMapModifiers.cutFruitArea.modifier

    for index, fruit in pairs(self.mission.fruits) do
        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(index)

        modifier:resetDensityMapAndChannels(fruit.id, fruitDesc.startStateChannel, fruitDesc.numStateChannels)
        modifier:setParallelogramWorldCoords(x - 0.5, z - 0.5, 1,0, 0,1, "pvv")

        local area, totalArea, _ = modifier:executeGet()
        if area > 0 then
            return { desc = fruitDesc, index = index, state = area / totalArea }
        end
    end

    return nil
end

---Get the tree type from the pallet
function MeasureTool:getTreeTypeFromPallet(pallet)
    local treeTypeName = getUserAttribute(pallet.rootNode, "treeType")

    if treeTypeName ~= nil then
        local desc = g_treePlantManager:getTreeTypeDescFromName(treeTypeName)
        if desc ~= nil then
            return desc.index
        end
    end

    return 1
end

---Show info about a static tree (only type and distance)
function MeasureTool:showStaticTreeInfo(tree)
    local data = {}
    local treeTypeDesc = g_treePlantManager:getTreeTypeDescFromIndex(tree.treeType)
    local typeName

    if treeTypeDesc then
        typeName = self.i18n:getText(treeTypeDesc.nameI18N)
    elseif tree.nameI18N then
        typeName = tree.nameI18N
    end

    if typeName then
        table.insert(data, {
            iconUVs = MeasureTool.UVS.TREE_TYPE,
            text = typeName
        })
    end

    table.insert(data, {
        iconUVs = MeasureTool.UVS.TREE_HEIGHT,
        text = "100%"
    })

    self:openDialog(data)
end

---Show info about a planted tree (includes growth)
function MeasureTool:showPlantedTreeInfo(tree, isClient)
    local data = {}

    if not isClient then -- needs receiving
        self:addTreeGrowthInfo(data, tree.treeType, tree.nearestDistance, (tree.growing and tree.growthState or 1) * 100)
    end

    self:openDialog(data)
end

function MeasureTool:addTreeGrowthInfo(data, treeType, treeDistance, treeHeight)
    table.insert(data, {
        iconUVs = MeasureTool.UVS.TREE_TYPE,
        text = self.i18n:getText(g_treePlantManager:getTreeTypeDescFromIndex(treeType).nameI18N)
    })

    table.insert(data, {
        iconUVs = MeasureTool.UVS.TREE_HEIGHT,
        text = string.format("%.0f%%", treeHeight)
    })

    -- Split trees don't have info
    if treeDistance ~= nil then
        table.insert(data, {
            iconUVs = MeasureTool.UVS.TREE_DISTANCE,
            text = self:formatLength(treeDistance)
        })
    end
end

function MeasureTool:makeBaleFermentationData(fillType, fermentingProcess)
    local hours = g_seasons.environment.daysPerSeason / 3 * 24 * (1 - fermentingProcess)

    local text = ""
    if fillType ~= FillType.DRYGRASS_WINDROW then
        if hours <= 1 then
            text = self.i18n:getText("seasons_measuretool_fermentation_time_low")
        else
            text = string.format(self.i18n:getText("seasons_measuretool_fermentation_time"), math.ceil(hours))
        end
        text = "(" .. text .. ")"
    end

    return {
        iconUVs = MeasureTool.UVS.FERMENTATION,
        text = string.format("%.2f%% %s", fermentingProcess * 100, text)
    }
end

---Open the measure dialog
function MeasureTool:openDialog(data)
    g_seasons.ui:showMeasurementDialog(data, function()
        self.dialogIsOpen = false
        self.currentObject = nil
    end)
    self.dialogIsOpen = true
end

---Received extra measurement data on a bale from the server
function MeasureTool.onReceiveExtraBaleData(measuredObject, baleFermentation)
    local tool = g_currentMission.player.baseInformation.currentHandtool
    if not tool.dialogIsOpen or tool.currentObject ~= measuredObject then
        return
    end

    local dialog = g_gui.guis["SeasonsMeasurementDialog"].target

    -- Add fermentation for bales
    if baleFermentation ~= nil and measuredObject:isa(Bale) then
        dialog:addData(tool:makeBaleFermentationData(measuredObject:getFillType(), baleFermentation))
    end
end

---Received extra measurement data on a tree from the server
function MeasureTool.onReceiveExtraTreeData(treeId, treeType, treeHeight, treeDistance)
    local tool = g_currentMission.player.baseInformation.currentHandtool
    if not tool.dialogIsOpen or tool.currentObject ~= treeId then
        return
    end

    local dialog = g_gui.guis["SeasonsMeasurementDialog"].target

    local data = {}
    tool:addTreeGrowthInfo(data, treeType, treeDistance, treeHeight)

    for _, d in ipairs(data) do
        dialog:addData(d)
    end
end

---Client has requested extra measurement data on an object
function MeasureTool.onRequestExtraMeasureData(connection, measuredObject, serverSplitShapeFileId)
    local baleFermentation
    local treeId, treeHeight, treeDistance, treeType

    if measuredObject ~= nil then
        if measuredObject:isa(Bale) then-- and measuredObject.wrappingState == 1 and measuredObject.fermentingProcess ~= nil then
            baleFermentation = measuredObject.fermentingProcess
        end
    elseif serverSplitShapeFileId ~= nil then
        local tree = MeasureTool.findServerTree(serverSplitShapeFileId)

        if tree ~= nil then
            treeId = serverSplitShapeFileId
            treeType = tree.treeType
            treeHeight = (tree.growing and tree.growthState or 1) * 100
            treeDistance = tree.nearestDistance
        end

    end

    connection:sendEvent(SeasonsMeasurementDataEvent:new(measuredObject, baleFermentation, treeId, treeType, treeHeight, treeDistance))
end

function MeasureTool.findServerTree(serverSplitShapeFileId)
    for _, tree in pairs(g_treePlantManager.treesData.growingTrees) do
        if tree.splitShapeFileId == serverSplitShapeFileId then
            tree.growing = true

            return tree
        end
    end

    for _, tree in pairs(g_treePlantManager.treesData.splitTrees) do
        if tree.splitShapeFileId == serverSplitShapeFileId then
            tree.growing = false

            return tree
        end
    end

    return nil
end

registerHandTool("seasonsMeasureTool", MeasureTool)

MeasureTool.UVS = {
    TREE_TYPE = {585, 0, 65, 65},
    TREE_HEIGHT = {195, 0, 65, 65},
    TREE_DISTANCE = {650, 0, 65, 65},
    CONTENTS = {780, 0, 65, 65},
    FERMENTATION = {390, 0, 65, 65},
    COMPASS = {845, 0, 65, 65},
    SOIL_COMPRESSION = {910, 0, 65, 65},
    CROP_HEIGHT = {715, 0, 65, 65},
    CROP_MOISTURE = {520, 0, 65, 65},
    ELEVATION = {455, 0, 65, 65},
    FERTILIZATION = {325, 0, 65, 65},
    CROP_TYPE = {260, 0, 65, 65},
    MOISTURE = {195, 65, 65, 65},
}
