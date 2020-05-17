----------------------------------------------------------------------------------------------------
-- SeasonsVisuals
----------------------------------------------------------------------------------------------------
-- Purpose:  Visual change system
--
-- Replacing materials of nodes dependent on the (visual) season. Also supports replacing materials
-- add all times: especially for the seasonal tree shader.
--
-- Stores the replaced materials from the basegame into a cache in order to prevent a GC
-- and to be able to re-set them once a season arrive that does not replace it.
--
--
-- Copyright (c) Realismus Modding, 2018-2019
----------------------------------------------------------------------------------------------------

SeasonsVisuals = {}

local SeasonsVisuals_mt = Class(SeasonsVisuals)

function SeasonsVisuals:new(mission, environment, messageCenter, depthOfFieldManager)
    local self = setmetatable({}, SeasonsVisuals_mt)

    self.mission = mission
    self.environment = environment
    self.messageCenter = messageCenter
    self.depthOfFieldManager = depthOfFieldManager
    self.isClient = self.mission:getIsClient()

    self.paths = {}
    self.data = {
        always = {},
        seasons = {
            [SeasonsEnvironment.SPRING] = {},
            [SeasonsEnvironment.SUMMER] = {},
            [SeasonsEnvironment.AUTUMN] = {},
            [SeasonsEnvironment.WINTER] = {},
        },
        seasonsFoliage = {
            [SeasonsEnvironment.SPRING] = {},
            [SeasonsEnvironment.SUMMER] = {},
            [SeasonsEnvironment.AUTUMN] = {},
            [SeasonsEnvironment.WINTER] = {},
        }
    }

    self.materialHolders = {} -- Paths of the material holders
    self.replacementNodes = {} -- Nodes of the material holders
    self.defaultMaterials = {} -- Materials of basegame
    self.changedFoliageTextures = {} -- List of type changes made

    -- List of layer names to check when updating. We can't list them from the game because:
    -- - the parent shape also has all terrain chunks and terrain detail
    -- - the fruit types associated are missing for things like deco and bushes
    self.installedFoliageLayers = {}

    -- Caching of default materials
    self.cacheNodeId = 0 -- Template of keep-alive nodes
    self.cacheRoot = 0 -- Root node of all keep-alive nodes

    self.memoryUsage = 0

    self.disableDoF = false

    self.video = false

    self.visualValue = 0

    addConsoleCommand("rmSetShader", "Set shader", "consoleCommandSetShader", self)
    addConsoleCommand("rmSetTexture", "Set textures", "consoleCommandSetTexture", self)
    addConsoleCommand("rmTextureVideo", "Start texture animation", "consoleCommandTextureVideo", self)

    SeasonsModUtil.appendedFunction(Placeable, "finalizePlacement", SeasonsVisuals.inj_placeable_finalizePlacement)
    SeasonsModUtil.overwrittenFunction(DepthOfFieldManager, "setManipulatedParams", SeasonsVisuals.inj_depthOfFieldManager_setManipulatedParams)

    return self
end

function SeasonsVisuals:delete()
    self:unloadMaterialHolders()

    if self.cacheRoot ~= 0 then
        delete(self.cacheRoot)
    end

    removeConsoleCommand("rmSetShader")
    removeConsoleCommand("rmSetTexture")
    removeConsoleCommand("rmTextureVideo")

    self.messageCenter:unsubscribeAll()
end

function SeasonsVisuals:load()
    if self.isClient then
        self:loadDataFromFiles()
        self:loadMaterialHolders()

        self:findMaterialsForReplacements(self.data)

        self.mission.textureMemoryUsage = self.mission.textureMemoryUsage + self.memoryUsage

        self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    end
end

---Called after all objects have been loaded (vehicles, items)
function SeasonsVisuals:updateAllNodes()
    self:initialTextureUpdate()
end

---------------------
-- Data loading
---------------------

function SeasonsVisuals:setDataPaths(paths)
    self.paths = paths
end

---Load data from all active visuals.xml files
function SeasonsVisuals:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("visuals", path.file)
        if xmlFile ~= 0 then
            self:loadDataFromFile(path, xmlFile)

            delete(xmlFile)
        end
    end
end

---Load all data from given visuals.xml file
function SeasonsVisuals:loadDataFromFile(path, xmlFile)
    self:loadMaterialsFromFile(path, xmlFile)

    if Utils.getNoNil(getXMLBool(xmlFile, "visuals#disableDoF"), false) then
        self.depthOfFieldManager.initialState[4] = 0
        self.depthOfFieldManager.initialState[5] = 0
        self.depthOfFieldManager:reset()
        self.disableDoF = true
    end
end

---Load all material configurations from given visuals.xml file
function SeasonsVisuals:loadMaterialsFromFile(path, xmlFile)
    local version = Utils.getNoNil(getXMLInt(xmlFile, "visuals#version"), 1)
    if version == 2 then
        local materialHolderFilename = getXMLString(xmlFile, "visuals.filename")
        if materialHolderFilename ~= nil then
            self:loadMaterialHolderInfo(path, xmlFile, materialHolderFilename, 2)
        end
    else
        local materialHolderFilename = getXMLString(xmlFile, "visuals.materials#filename")
        if materialHolderFilename ~= nil then
            -- Version 1 is only allowed on PC
            if not GS_IS_CONSOLE_VERSION then
                self:loadMaterialHolderInfo(path, xmlFile, materialHolderFilename, 1)
            elseif g_isDevelopmentVersion then
                -- Show an error for QA
                g_gui:showInfoDialog({
                    text = "This map contains custom seasonal textures, but has not been prepared for console. It has to use version 2 of the visuals format"
                })
            end
        end
    end

    self:loadMaterialSetFromFile(path, xmlFile, "visuals.materials.always", self.data.always)

    self:loadMaterialSetFromFile(path, xmlFile, "visuals.materials.spring", self.data.seasons[SeasonsEnvironment.SPRING])
    self:loadMaterialSetFromFile(path, xmlFile, "visuals.materials.summer", self.data.seasons[SeasonsEnvironment.SUMMER])
    self:loadMaterialSetFromFile(path, xmlFile, "visuals.materials.autumn", self.data.seasons[SeasonsEnvironment.AUTUMN])
    self:loadMaterialSetFromFile(path, xmlFile, "visuals.materials.winter", self.data.seasons[SeasonsEnvironment.WINTER])

    self:loadFoliageSetFromFile(path, xmlFile, "visuals.materials.spring", self.data.seasonsFoliage[SeasonsEnvironment.SPRING])
    self:loadFoliageSetFromFile(path, xmlFile, "visuals.materials.summer", self.data.seasonsFoliage[SeasonsEnvironment.SUMMER])
    self:loadFoliageSetFromFile(path, xmlFile, "visuals.materials.autumn", self.data.seasonsFoliage[SeasonsEnvironment.AUTUMN])
    self:loadFoliageSetFromFile(path, xmlFile, "visuals.materials.winter", self.data.seasonsFoliage[SeasonsEnvironment.WINTER])
end

---Load a material holder file with optional cache shape
function SeasonsVisuals:loadMaterialHolderInfo(path, xmlFile, filename, version)
    local materialHolderFilename = Utils.getFilename(filename, path.modDir)
    if not fileExists(materialHolderFilename) then
        Logging.error("Visuals configuration at %s is invalid: meterial holder not found at %s.", path.file, materialHolderFilename)
        return
    end

    table.insert(self.materialHolders, materialHolderFilename)

    -- Consoles have a memory limit with 'slots'. To keep this slot usage correct,
    -- we need to keep track of the memory used.
    if GS_IS_CONSOLE_VERSION then
        local vertexBufferMemoryUsage = getXMLInt(xmlFile, "visuals.vertexBufferMemoryUsage")
        local indexBufferMemoryUsage = getXMLInt(xmlFile, "visuals.indexBufferMemoryUsage")
        local textureMemoryUsage = getXMLInt(xmlFile, "visuals.textureMemoryUsage")

        if vertexBufferMemoryUsage == nil or indexBufferMemoryUsage == nil or textureMemoryUsage == nil then
            Logging.error("Visual configuration at %s supplies a material holder. Memory usage indication is required or consoles, but is missing.", path.file)

            if g_isDevelopmentVersion then
                -- Show an error for QA
                g_gui:showInfoDialog({
                    text = "The seasonal visuals configuration in this map uses custom materials, but it has no memory usage defined."
                })
            end

            return
        else
            local size = vertexBufferMemoryUsage + indexBufferMemoryUsage + textureMemoryUsage
            self.memoryUsage = self.memoryUsage + size
        end
    end

    -- Cache shape is used to store copies of the default materials so they are not destroyed
    local cacheNodeName = getXMLString(xmlFile, "visuals.materials.cache#name")
    if cacheNodeName == nil and self.cacheNodeName == nil then
        Logging.error("Visuals configuration at %s is invalid: no cache material reference found.", path.file)
        return
    end
    self.cacheNodeName = cacheNodeName
end

function SeasonsVisuals:loadMaterialSetFromFile(path, xmlFile, key, data)
    local i = 0
    while true do
        local shapeKey = string.format("%s.shape(%d)", key, i)
        if not hasXMLProperty(xmlFile, shapeKey) then
            break
        end

        local name = getXMLString(xmlFile, shapeKey .. "#name")
        local childName = Utils.getNoNil(getXMLString(xmlFile, shapeKey .. "#childName"), name)
        local to = getXMLString(xmlFile, shapeKey .. "#to")

        if name == nil or to == nil then
            Logging.error("Invalid visual configuration in %s at %s.", path.file, shapeKey)
            return
        end

        if data[name] == nil then
            data[name] = {}
        end

        data[name][childName] = to

        i = i + 1
    end
end

function SeasonsVisuals:loadFoliageSetFromFile(path, xmlFile, key, data)
    local i = 0
    while true do
        local foliageKey = string.format("%s.foliage(%d)", key, i)
        if not hasXMLProperty(xmlFile, foliageKey) then
            break
        end

        local name = getXMLString(xmlFile, foliageKey .. "#name")
        local to = getXMLString(xmlFile, foliageKey .. "#to")
        local visible = getXMLBool(xmlFile, foliageKey .. "#visible")

        -- Skip if not configured in map
        if getTerrainDetailByName(self.mission.terrainRootNode, name) ~= 0 then
            if name == nil then
                Logging.error("Invalid visual configuration in %s at %s.", path.file, foliageKey)
                return
            end

            -- When child does not exist, just skip
            if visible ~= nil or (visible == nil and to ~= nil and getTerrainDetailByName(self.mission.terrainRootNode, to) ~= nil) then
                if to ~= nil then
                    data[name] = to
                else
                    data[name] = visible
                end

                self.installedFoliageLayers[name] = name
            end
        end

        i = i + 1
    end
end

---Load all found material holders into memory.
function SeasonsVisuals:loadMaterialHolders()
    for _, path in ipairs(self.materialHolders) do
        local holder = loadI3DFile(path)
        if holder ~= 0 then
            table.insert(self.replacementNodes, holder)
        end

        if self.cacheNodeId == 0 then
            self.cacheNodeId = self:findNodeByName(holder, self.cacheNodeName)
        end
    end

    if self.cacheNodeId ~= 0 then
        self.cacheRoot = createTransformGroup("SeasonsMaterialCacheRoot")
        link(getRootNode(), self.cacheRoot)
    end
end

function SeasonsVisuals:unloadMaterialHolders()
    for _, shape in ipairs(self.replacementNodes) do
        delete(shape)
    end
end

---------------------
-- Node utilities
---------------------

---Find a node with given name in the tree starting at nodeId.
function SeasonsVisuals:findNodeByName(nodeId, name, skipCurrent)
    if skipCurrent ~= true and getName(nodeId) == name then
        return nodeId
    end

    for i = 0, getNumOfChildren(nodeId) - 1 do
        local tmp = self:findNodeByName(getChildAt(nodeId, i), name)

        if tmp ~= 0 then
            return tmp
        end
    end

    return 0
end

---Get all materials of given node.
function SeasonsVisuals:getNodeMaterials(nodeId)
    local list = {}

    for i = 0, getNumMaterials(nodeId) - 1 do
        table.insert(list, getMaterial(nodeId, i))
    end

    return list
end

---Set the materials of a node. Only sets as many as either supplied or in the node.
function SeasonsVisuals:setNodeMaterials(nodeId, materialIds)
    local numMats = getNumMaterials(nodeId)

    for i = 1, math.min(numMats, #materialIds) do
        setMaterial(nodeId, materialIds[i], i - 1)
    end
end

---Force keeping the given materials alive (prevent GC) by putting them in nodes
function SeasonsVisuals:forceMaterialKeepAlive(materialIds)
    if materialIds == nil or #materialIds == 0 then
        return
    end

    for _, materialId in ipairs(materialIds) do
        local node = clone(self.cacheNodeId, false, false, false)

        link(self.cacheRoot, node)
        setMaterial(node, materialId, 0)
    end
end

---------------------
-- Handling replacement nodes
---------------------

---Search a node in all replacement holders.
function SeasonsVisuals:findNodeByNameInReplacements(name)
    for _, rootNodeId in ipairs(self.replacementNodes) do
        local nodeId = self:findNodeByName(rootNodeId, name)
        if nodeId ~= 0 then
            return nodeId
        end
    end

    return 0
end

---Finds the materials in the material holders, specified by the configuration.
function SeasonsVisuals:findMaterialsForReplacements()
    self:findMaterialsForReplacementsInSet(self.data.always)

    for seasonId, set in pairs(self.data.seasons) do
        self:findMaterialsForReplacementsInSet(set)
    end

    for seasonId, replacement in pairs(self.data.seasonsFoliage) do
        self:findFoliageMaterialsForReplacement(replacement)
    end
end

---In the set, find all replacements and replace their node name with the materials they represent
function SeasonsVisuals:findMaterialsForReplacementsInSet(set)
    for shapeName, childShapes in pairs(set) do
        for childName, toName in pairs(childShapes) do
            -- Find shape
            local replacementId = self:findNodeByNameInReplacements(toName)
            if replacementId ~= 0 then
                childShapes[childName] = self:getNodeMaterials(replacementId)
            else
                -- No replacement found: remove
                childShapes[childName] = nil
            end
        end
    end
end

---Find foliage materials in the replacement files
function SeasonsVisuals:findFoliageMaterialsForReplacement(set)
    for name, visibleOrName in pairs(set) do
        -- Boolean values are for hiding, strings are shape names
        if type(visibleOrName) == "string" then
            local terrainDetail = getTerrainDetailByName(self.mission.terrainRootNode, visibleOrName)
            local firstNode = getChildAt(terrainDetail, 0)

            set[name] = self:getNodeMaterials(firstNode)
        end
    end
end

---Add materials to the default set.
function SeasonsVisuals:addDefaultMaterials(shapeName, childName, materialIds)
    if self.defaultMaterials[shapeName] == nil then
        self.defaultMaterials[shapeName] = {}
    end

    self.defaultMaterials[shapeName][childName] = materialIds
end

---Get the materials from the default set, if any
function SeasonsVisuals:getHasDefaultMaterials(shapeName, childName)
    if self.defaultMaterials[shapeName] == nil then
        self.defaultMaterials[shapeName] = {}
    end

    return self.defaultMaterials[shapeName][childName] ~= nil
end

---------------------
-- Foliage
---------------------

---Update foliage visuals by hiding/showing layers or updating terrain shapes to switch visuals
function SeasonsVisuals:updateFoliage(data, terrainRootNode)
    -- Go through all known foliage layers and either set from data or reset to default
    for _, layerName in pairs(self.installedFoliageLayers) do
        local layerId = getChild(terrainRootNode, layerName)

        local visibleOrMaterials = data[layerName]

        if visibleOrMaterials == nil then
            -- If we marked it as 'changed textures' then we have to reset the textures
            if self.changedFoliageTextures[layerName] then
                -- Only proceed when there are default materials saved (should always be the case)
                if self:getHasDefaultMaterials("$_foliage", layerName) then
                    local materialIds = self.defaultMaterials["$_foliage"][layerName]

                    self:updateFoliageTextures(layerName, materialIds, terrainRootNode)

                    -- Reset state
                    self.changedFoliageTextures[layerName] = false
                end
            else
                -- Otherwise we just make it visible so we are sure the invisibility has been fixed
                setVisibility(layerId, true)
            end
        else
            -- WHen boolean, it is hiding/unhinding
            if type(visibleOrMaterials) == "boolean" then
                setVisibility(layerId, visibleOrMaterials)
            else
                -- Else it is a table with replacement materials

                -- Find defaults if not loaded yet
                if not self:getHasDefaultMaterials("$_foliage", layerName) then
                    local terrainDetail = getTerrainDetailByName(terrainRootNode, layerName)
                    local firstShape = getChildAt(terrainDetail, 0)

                    local materialIds = self:getNodeMaterials(firstShape)

                    self:addDefaultMaterials("$_foliage", layerName, materialIds)
                    self:forceMaterialKeepAlive(materialIds)
                end

                -- Then perform a massive change of materials
                if self:updateFoliageTextures(layerName, visibleOrMaterials, terrainRootNode) > 0 then
                    -- Only set if anything changed to save performance on resetting
                    self.changedFoliageTextures[layerName] = true
                end
            end
        end

    end
end

---Update the textures of the terrain foliage
function SeasonsVisuals:updateFoliageTextures(layerName, materialIds, terrainRootNode)
    -- In FS19, foliage is not a single shape anymore but is divided in many small shapes
    -- We need to update all these shapes
    local terrainDetail = getTerrainDetailByName(terrainRootNode, layerName)

    for i = 0, getNumOfChildren(terrainDetail) - 1 do
        local nodeId = getChildAt(terrainDetail, i)

        self:setNodeMaterials(nodeId, materialIds)
    end

    return 1
end

---------------------
-- Updating objects
---------------------

---Set the initial textures: set current season and the 'always' replacements.
function SeasonsVisuals:initialTextureUpdate()
    self:updateTextures(self.data.always, getRootNode(), false)
    self:updateShaders()

    self.lastUpdate = g_time
end

---Update global shader parameters
function SeasonsVisuals:updateShaders()
    local season = self.environment.season
    local dayInSeasonAlpha = self.environment:getPercentageIntoSeason()

    -- setSharedShaderParameter(3, (season + 1 + dayInSeasonAlpha) % 4)
    setSharedShaderParameter(3, self.visualValue)
end

-- @param storeDefault boolean [optional, default = true] Store any missing vanilla textures in the default material set
function SeasonsVisuals:updateTextures(data, nodeId, storeDefault)
    local nodeName = getName(nodeId)

    if data[nodeName] ~= nil then
        for childName, materialIds in pairs(data[nodeName]) do
            self:updateTexturesSubNode(nodeId, childName, materialIds, nodeName, storeDefault)
        end
    elseif self.defaultMaterials[nodeName] ~= nil then
        for childName, materialIds in pairs(self.defaultMaterials[nodeName]) do
            self:updateTexturesSubNode(nodeId, childName, materialIds, nodeName, storeDefault)
        end
    end

    for i = 0, getNumOfChildren(nodeId) - 1 do
        local childId = getChildAt(nodeId, i)
        if childId ~= 0 then
            self:updateTextures(data, childId, storeDefault)
        end
    end
end

function SeasonsVisuals:updateTexturesSubNode(nodeId, nodeName, replacementMaterials, parentName, storeDefault)
    if getHasClassId(nodeId, ClassIds.SHAPE) and getName(nodeId) == nodeName then
        -- Before overwriting, store the vanilla materials for when a season comes that has no replacement (e.g. summer)
        if storeDefault ~= false and not self:getHasDefaultMaterials(parentName, nodeName) then
            local materialIds = self:getNodeMaterials(nodeId)
            self:addDefaultMaterials(parentName, nodeName, materialIds)
            self:forceMaterialKeepAlive(materialIds)
        end

        self:setNodeMaterials(nodeId, replacementMaterials)
        return true
    end

    for i = 0, getNumOfChildren(nodeId) - 1 do
        local childId = getChildAt(nodeId, i)

        if self:updateTexturesSubNode(childId, nodeName, replacementMaterials, parentName, storeDefault) then
            return true
        end
    end

    return false
end

---Update materials of a placeable
function SeasonsVisuals:updatePlaceable(placeable)
    self:updateTextures(self.data.always, placeable.nodeId, false)
end

function SeasonsVisuals:updateVisualSeason()
    -- todo: only change if different (is this running before or after period change?)
    local currentPeriod = self.environment.period
    local currentCategory = self.environment.latitudeCategories[self.environment:latitudeCategory()]
    local currentVisual = currentCategory[currentPeriod]
    local visualSeasonsId = self.environment.seasonKeyToId[currentVisual]

    self:updateTextures(self.data.seasons[visualSeasonsId], getRootNode())
    self:updateFoliage(self.data.seasonsFoliage[visualSeasonsId], self.mission.terrainRootNode)
end

function SeasonsVisuals:updateVisualValue()
    -- visual value intervals:
    -- spring: 0-0.3 (fallback 0.1)
    -- summer: 0.3-2.0 (fallback 1.5)
    -- autumn: 2.0-3.8 (fallback 3)
    -- to winter: 3.8-4.0
    -- winter: 4.0/0.0 (fallback 0)

    local currentPeriod = self.environment.period
    local lastPeriod = self.environment:previousPeriod(currentPeriod)
    local nextPeriod = self.environment:nextPeriod(currentPeriod)
    local currentCategory = self.environment.latitudeCategories[self.environment:latitudeCategory()]

    local currentVisual = currentCategory[currentPeriod]
    local lastVisual = currentCategory[lastPeriod]
    local nextVisual = currentCategory[nextPeriod]

    local percentageIntoVisualSeason = self.environment:getPercentageIntoVisualSeason()
    local percentageIntoPeriod = self.environment:getPercentageIntoPeriod()

    if currentVisual == "spring" then
        self.visualValue = 0.5 * percentageIntoVisualSeason

    elseif currentVisual == "summer" and lastPeriod == "spring" then
        self.visualValue = 1.5 * percentageIntoPeriod + 0.5

    elseif currentVisual == "summer" then
        self.visualValue = 2.0

    elseif currentVisual == "autumn" then
        self.visualValue = 1.7 * percentageIntoVisualSeason + 2.0

    elseif currentVisual == "winter" and lastVisual == "autumn" then
        self.visualValue = 0.3 * percentageIntoPeriod + 3.7

    else
        self.visualValue = 0

    end

    -- todo:
    --      -add possible reduction in length of visual season
    --          -for spring: based on air temp > 5 and snow cover == 0
    --          -for winter: based on air temp < 0
end

---------------------
-- Events
---------------------

function SeasonsVisuals:update(dt)
    if self.video == true then
        self.videoState = (self.videoState + dt * 0.00005) % 4
        setSharedShaderParameter(3, self.videoState)
    else
        if self.lastUpdate + 1000 < g_time then
            self:updateVisualValue()
            self:updateShaders()
            self.lastUpdate = g_time
        end
    end

    if self.queuedVisualSeasonUpdate then
        self.queuedVisualSeasonUpdate = false
        self:updateVisualSeason()
    end
end

function SeasonsVisuals:onDayChanged()
    if self.isClient then
        self:updateVisualSeason()
    end
end

function SeasonsVisuals:onGameLoaded()
    if self.isClient then
        -- Delay until first update(). Otherwise it doesn't work on MP clients
        self.queuedVisualSeasonUpdate = true
    end
end

---------------------
-- Injections
---------------------

function SeasonsVisuals.inj_placeable_finalizePlacement(placeable)
    if placeable.isClient then
        g_seasons.visuals:updatePlaceable(placeable)
    end
end

---Fix the override for the shop
function SeasonsVisuals.inj_depthOfFieldManager_setManipulatedParams(manager, superFunc, nearCoCRadius, nearBlurEnd, farCoCRadius, farBlurStart, farBlurEnd)
    if g_seasons.visuals.disableDoF and farBlurEnd == nil then
        farBlurEnd = 1400
    end
    return superFunc(manager, nearCoCRadius, nearBlurEnd, farCoCRadius, farBlurStart, farBlurEnd)
end

---------------------
-- Commands
---------------------

function SeasonsVisuals:consoleCommandSetShader(val)
    if val == nil then
        return "Usage: ssSetShader num"
    end

    val = tonumber(val)

    setSharedShaderParameter(3, val)
end

function SeasonsVisuals:consoleCommandSetTexture(val)
    if val == nil then
        return "Usage: rmSetTexture num"
    end

    val = tonumber(val)

    if val >= 0 and val <= 3 then
        self:updateTextures(self.data.seasons[val], getRootNode())
        self:updateFoliage(self.data.seasonsFoliage[val], self.mission.terrainRootNode)
    end
end

function SeasonsVisuals:consoleCommandTextureVideo(val)
    self.video = not self.video
    if self.video then
        self.videoState = 0
    end
end
