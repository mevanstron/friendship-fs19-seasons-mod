----------------------------------------------------------------------------------------------------
-- SeasonsContracts
----------------------------------------------------------------------------------------------------
-- Purpose:  Contract handler for Seasons
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsContracts = {}

local SeasonsContracts_mt = Class(SeasonsContracts)

SeasonsContracts.CATEGORY_SNOW = 4

function SeasonsContracts:new(mission, missionManager, environment, weather, npcManager, i18n, messageCenter, farmlandManager)
    local self = setmetatable({}, SeasonsContracts_mt)

    self.mission = mission
    self.missionManager = missionManager
    self.environment = environment
    self.weather = weather
    self.npcManager = npcManager
    self.i18n = i18n
    self.messageCenter = messageCenter
    self.farmlandManager = farmlandManager
    self.isServer = mission:getIsServer()

    self.contractNameToNodes = {}
    self.snowContractNameToConfig = {}

    SeasonsModUtil.appendedFunction(MissionManager,                 "generateMissions",         self.inj_missionManager_generateMissions)
    SeasonsModUtil.appendedFunction(MissionManager,                 "updateMissions",           self.inj_missionManager_updateMissions)
    SeasonsModUtil.overwrittenFunction(InGameMenuContractsFrame,    "updateFieldContractInfo",  self.inj_inGameMenuContractsFrame_updateFieldContractInfo)

    if g_addCheatCommands then
        addConsoleCommand("rmGenerateMissions", "", "generateMissions", self)
    end

    return self
end

function SeasonsContracts:delete()
    self.messageCenter:unsubscribeAll(self)

    if g_addCheatCommands then
        removeConsoleCommand("rmGenerateMissions")
    end
end

function SeasonsContracts:load()
    self:loadContractsFromXML()
    self:findSnowAreaSizes()

    self.messageCenter:subscribe(SeasonsMessageType.SNOW_HEIGHT_CHANGED, self.onSnowHeightChanged, self)
end

-- Load contracts from map.xml
function SeasonsContracts:loadContractsFromXML()
    self.snowContractConfigs = {}

    local xmlFilename = Utils.getFilename(self.mission.missionInfo.mapXMLFilename, self.mission.baseDirectory)
    local xmlFile = loadXMLFile("map", xmlFilename)

    local i = 0
    while true do
        local key = string.format("map.seasons.missions.mission(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local config = {}

        config.name = getXMLString(xmlFile, key .. "#name")
        config.type = getXMLString(xmlFile, key .. "#type")

        if config.name ~= nil and config.type ~= nil then
            config.rewardScale = getXMLFloat(xmlFile, key .. "#rewardScale") or 1
            config.npc = self.npcManager:getNPCByName(getXMLString(xmlFile, key .. "#npcName"))
            config.location = self.i18n:convertText(getXMLString(xmlFile, key .. "#location"), self.mission.missionInfo.customEnvironment) or ""
            config.text = self.i18n:convertText(getXMLString(xmlFile, key .. "#text"), self.mission.missionInfo.customEnvironment) or ""
            config.farmlandId = getXMLInt(xmlFile, key .. "#farmlandId") -- Farmland that, if bought, prohibits the contract
            config.id = #self.snowContractConfigs + 1

            if self.contractNameToNodes[config.name] ~= nil then
                config.nodes = self.contractNameToNodes[config.name]
            end

            self.snowContractNameToConfig[config.name] = config
            table.insert(self.snowContractConfigs, config)
        end

        i = i + 1
    end

    delete(xmlFile)
end

---Register a new node for contracts. A node contains a config reference, and a set of sub nodes
-- such as clearing areas
function SeasonsContracts:addNewSnowContractNode(nodeId)
    local name = getUserAttribute(nodeId, "name")
    if name == nil then
        Logging.error("Invalid configuration of snow contract node: missing name")
        return
    end

    self.contractNameToNodes[name] = {
        root = nodeId,
        clearArea = getChildAt(nodeId, getUserAttribute(nodeId, "clearAreaIndex")),
        dropArea = getChildAt(nodeId, getUserAttribute(nodeId, "dropAreaIndex")),
        sign = getChildAt(nodeId, getUserAttribute(nodeId, "signIndex")),
    }
end

---Find the covering size of each snow clear area
function SeasonsContracts:findSnowAreaSizes()
    local bitMapSize = 4096
    local terrainSize = getTerrainSize(self.mission.terrainRootNode)

    local function convertWorldToAccessPosition(x, z)
        return math.floor(bitMapSize * (x + terrainSize * 0.5) / terrainSize),
               math.floor(bitMapSize * (z + terrainSize * 0.5) / terrainSize)
    end

    local function pixelToHa(area)
        local pixelToSqm = terrainSize / bitMapSize
        return (area * pixelToSqm * pixelToSqm) / 10000
    end

    for _, config in pairs(self.snowContractConfigs) do
        local sumPixel = 0

        local bitVector = createBitVectorMap("field")
        loadBitVectorMapNew(bitVector, bitMapSize, bitMapSize, 1, true)

        local area = config.nodes.clearArea
        for i = 0, getNumOfChildren(area) - 1 do
            local dimWidth = getChildAt(area, i)
            local dimStart = getChildAt(dimWidth, 0)
            local dimHeight = getChildAt(dimWidth, 1)

            local x0,_,z0 = getWorldTranslation(dimStart)
            local widthX,_,widthZ = getWorldTranslation(dimWidth)
            local heightX,_,heightZ = getWorldTranslation(dimHeight)

            local x,z = convertWorldToAccessPosition(x0, z0)
            local widthX,widthZ = convertWorldToAccessPosition(widthX, widthZ)
            local heightX,heightZ = convertWorldToAccessPosition(heightX, heightZ)

            sumPixel = sumPixel + setBitVectorMapParallelogram(bitVector, x, z, widthX - x, widthZ - z, heightX - x, heightZ - z, 0, 1, 0)
        end

        config.area = pixelToHa(sumPixel)

        delete(bitVector)
    end
end

---------------------------
-- Generation and validation
---------------------------

---Generate new missions that we have added.
-- If they were field or transport missions this would be done automatically. But
-- custom missions need some extra code to trigger generation.
function SeasonsContracts:generateMissions(dt)
    -- Always try to generate any snow mission
    for _, missionConfig in ipairs(self.snowContractConfigs) do
        local missionType = self.missionManager:getMissionType("snow")

        -- If the farmlandId is set, then the farmland must not be owned
        local isOnUnownedLand = true
        if missionConfig.farmlandId ~= nil then
            local farmland = self.farmlandManager:getFarmlandById(missionConfig.farmlandId)
            if farmland ~= nil then
                isOnUnownedLand = not farmland.isOwned
            end
        end

        -- The next loop is relatively expensive so we want to skip it when not needed
        if isOnUnownedLand then
            -- Check whether such contract already exists
            local contractExists = false
            for _, mission in ipairs(self.missionManager.missions) do
                if mission.type.category == SeasonsContracts.CATEGORY_SNOW and mission.config == missionConfig then
                    contractExists = true
                end
            end

            if not contractExists then
                local canRun = missionType.class.canRun(missionConfig)

                if canRun then
                    -- Create an instance
                    local mission = missionType.class:new(true, g_client ~= nil)
                    mission.type = missionType

                    if mission:init(missionConfig) then
                        self.missionManager:assignGenerationTime(mission)

                        mission:register()

                        table.insert(self.missionManager.missions, mission)
                    else
                        mission:delete()
                    end
                end
            end
        end
    end
end

function SeasonsContracts:updateMissions(dt)
end

---Update snow missions: check whether snow still exists
function SeasonsContracts:validateMissions()
    for _, mission in ipairs(self.missionManager.missions) do
        if mission.type.category == SeasonsContracts.CATEGORY_SNOW then
            if not mission:validate() then
                if mission.status == AbstractMission.STATUS_RUNNING then
                    -- Fail the mission
                    mission:finish(false)
                else
                    -- Remove from list so it is not accessible
                    mission:delete()
                end
            end
        end
    end
end

---------------------------
-- Snow configs
---------------------------

---Get the contract config based on the name. Used for loading from savegame
function SeasonsContracts:getSnowConfigByName(name)
    return self.snowContractNameToConfig[name]
end

---Get the contract config based on the name. Used for syncing over network
function SeasonsContracts:getSnowConfigById(id)
    return self.snowContractConfigs[id]
end

---------------------------
-- Managing the bitvector
---------------------------

---Inject values into the mission map thats used to override terrain permissions
function SeasonsContracts:setMissionMapForMission(mission, value)
    self:setMissionMapForArea(mission.config.nodes.clearArea, value)
    self:setMissionMapForArea(mission.config.nodes.dropArea, value)
end

function SeasonsContracts:setMissionMapForArea(area, value)
    for i = 0, getNumOfChildren(area) - 1 do
        local dimWidth = getChildAt(area, i)
        local dimStart = getChildAt(dimWidth, 0)
        local dimHeight = getChildAt(dimWidth, 1)

        local x0,_,z0 = getWorldTranslation(dimStart)
        local widthX,_,widthZ = getWorldTranslation(dimWidth)
        local heightX,_,heightZ = getWorldTranslation(dimHeight)

        local x,z = self.missionManager:convertWorldToAccessPosition(x0, z0)
        local widthX,widthZ = self.missionManager:convertWorldToAccessPosition(widthX, widthZ)
        local heightX,heightZ = self.missionManager:convertWorldToAccessPosition(heightX, heightZ)

        setBitVectorMapParallelogram(self.missionManager.missionMap, x, z, widthX - x, widthZ - z, heightX - x, heightZ - z, 0, self.missionManager.missionMapNumChannels, value)
    end
end

function SeasonsContracts:addMissionToMissionMap(mission)
    self:setMissionMapForMission(mission, mission.activeMissionId)
end

function SeasonsContracts:removeMissionFromMissionMap(mission)
    self:setMissionMapForMission(mission, 0)
end

----------------------
-- Events
----------------------

function SeasonsContracts:onSnowHeightChanged()
    if self.isServer then
        self:validateMissions()
    end
end

----------------------
-- Injections
----------------------

---Generate new missions that we have added.
-- If they were field or transport missions this would be done automatically. But
-- custom missions need some extra code to trigger generation.
function SeasonsContracts.inj_missionManager_generateMissions(missionManager, dt)
    g_seasons.contracts:generateMissions(dt)
end

---Update snow missions: check whether snow still exists
function SeasonsContracts.inj_missionManager_updateMissions(missionManager, dt)
    g_seasons.contracts:updateMissions(dt)
end

function SeasonsContracts.inj_inGameMenuContractsFrame_updateFieldContractInfo(frame, superFunc, mission)
    if mission:isa(AbstractFieldMission) then
        return superFunc(frame, mission)
    end

    if mission:isa(SnowContract) then
        local missionInfo = mission:getData()

        -- Top part
        frame.titleText:setText(g_i18n:getText("fieldJob_contract") .. ": " .. missionInfo.jobType)
        frame.actionText:setText(missionInfo.action)

        frame.rewardText:setText(g_i18n:formatMoney(mission.reward, 0, true, true))
        frame.fieldBigText:setText("")

        -- Bottom part
        frame.contractDescriptionText:setText(missionInfo.description)

        -- Field area
        frame.npcFieldBox:setVisible(true)
        frame.ownerOfText:setText("")
        frame.areaText:setText(frame.i18n:formatArea(mission.config.area, 2))
    end
end
