----------------------------------------------------------------------------------------------------
-- main
----------------------------------------------------------------------------------------------------
-- Purpose:  Mod entrance point. Hooks into the game
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

-- Do not reset this variable, we can't re-set it again
local modDirectory = g_currentModDirectory
local modName = g_currentModName

source(modDirectory .. "src/Seasons.lua")
source(modDirectory .. "src/SeasonsMessageTypes.lua")
source(modDirectory .. "src/SeasonsThirdPartyMods.lua")
source(modDirectory .. "src/animals/SeasonsAnimals.lua")
source(modDirectory .. "src/animals/SeasonsAnimalsData.lua")
source(modDirectory .. "src/animals/SeasonsAnimalsUI.lua")
source(modDirectory .. "src/animals/SeasonsGrazing.lua")
source(modDirectory .. "src/collections/Queue.lua")
source(modDirectory .. "src/contracts/SeasonsContracts.lua")
source(modDirectory .. "src/contracts/SnowContract.lua")
source(modDirectory .. "src/economy/SeasonsEconomy.lua")
source(modDirectory .. "src/economy/SeasonsEconomyData.lua")
source(modDirectory .. "src/economy/SeasonsEconomyHistory.lua")
source(modDirectory .. "src/environment/SeasonsDaylight.lua")
source(modDirectory .. "src/environment/SeasonsEnvironment.lua")
source(modDirectory .. "src/environment/SeasonsLighting.lua")
source(modDirectory .. "src/environment/SeasonsSnowHandler.lua")
source(modDirectory .. "src/environment/SeasonsVisuals.lua")
source(modDirectory .. "src/events/SeasonsAddWeatherForecastEvent.lua")
source(modDirectory .. "src/events/SeasonsAgeWearRepaintEvent.lua")
source(modDirectory .. "src/events/SeasonsBaleFermentEvent.lua")
source(modDirectory .. "src/events/SeasonsBaleRotEvent.lua")
source(modDirectory .. "src/events/SeasonsEconomyHistoryEvent.lua")
source(modDirectory .. "src/events/SeasonsInitialStateEvent.lua")
source(modDirectory .. "src/events/SeasonsLoadFinishedEvent.lua")
source(modDirectory .. "src/events/SeasonsMeasurementDataEvent.lua")
source(modDirectory .. "src/events/SeasonsMeasurementRequestEvent.lua")
source(modDirectory .. "src/events/SeasonsSettingsEvent.lua")
source(modDirectory .. "src/events/SeasonsStartAnimalGestation.lua")
source(modDirectory .. "src/events/SeasonsVariablePlantDistanceEvent.lua")
source(modDirectory .. "src/events/SeasonsWeatherDailyEvent.lua")
source(modDirectory .. "src/events/SeasonsWeatherHourlyEvent.lua")
source(modDirectory .. "src/growth/SeasonsCropRotation.lua")
source(modDirectory .. "src/growth/SeasonsGrowth.lua")
source(modDirectory .. "src/growth/SeasonsGrowthData.lua")
source(modDirectory .. "src/growth/SeasonsGrowthFruitTypes.lua")
source(modDirectory .. "src/growth/SeasonsGrowthManager.lua")
source(modDirectory .. "src/growth/SeasonsGrowthNPCMissions.lua")
source(modDirectory .. "src/growth/SeasonsGrowthPatchyCropFailure.lua")
source(modDirectory .. "src/gui/BarChartElement.lua")
source(modDirectory .. "src/gui/LocalizedTextElement.lua")
source(modDirectory .. "src/gui/SeasonsCatchingUp.lua")
source(modDirectory .. "src/gui/SeasonsFieldInfo.lua")
source(modDirectory .. "src/gui/SeasonsMeasurementDialog.lua")
source(modDirectory .. "src/gui/SeasonsMenu.lua")
source(modDirectory .. "src/gui/SeasonsUI.lua")
source(modDirectory .. "src/gui/SeasonsWorkshop.lua")
source(modDirectory .. "src/gui/frames/SeasonsAnimalsFrame.lua")
source(modDirectory .. "src/gui/frames/SeasonsCalendarFrame.lua")
source(modDirectory .. "src/gui/frames/SeasonsCropsFrame.lua")
source(modDirectory .. "src/gui/frames/SeasonsEconomyFrame.lua")
source(modDirectory .. "src/gui/frames/SeasonsForecastFrame.lua")
source(modDirectory .. "src/gui/frames/SeasonsRotationFrame.lua")
source(modDirectory .. "src/gui/frames/SeasonsSettingsFrame.lua")
source(modDirectory .. "src/gui/hud/SeasonsHUD.lua")
source(modDirectory .. "src/handtools/MeasureTool.lua")
source(modDirectory .. "src/luafp.lua")
source(modDirectory .. "src/misc/SeasonsDensityMapScanner.lua")
source(modDirectory .. "src/misc/SeasonsGrass.lua")
source(modDirectory .. "src/misc/SeasonsMask.lua")
source(modDirectory .. "src/misc/SeasonsSound.lua")
source(modDirectory .. "src/misc/SeasonsTrees.lua")
source(modDirectory .. "src/objects/IcePlane.lua")
source(modDirectory .. "src/objects/ObjectFactory.lua")
source(modDirectory .. "src/objects/SeasonAdmirer.lua")
source(modDirectory .. "src/objects/SnowAdmirer.lua")
source(modDirectory .. "src/objects/SnowContractNode.lua")
source(modDirectory .. "src/placeables/PlaceableAdmirers.lua")
source(modDirectory .. "src/utils/Logging.lua")
source(modDirectory .. "src/utils/SeasonsLocalStorage.lua")
source(modDirectory .. "src/utils/SeasonsMathUtil.lua")
source(modDirectory .. "src/utils/SeasonsModUtil.lua")
source(modDirectory .. "src/vehicles/SeasonsVehicle.lua")
source(modDirectory .. "src/vehicles/SeasonsVehicleData.lua")
source(modDirectory .. "src/vehicles/SeasonsVehicleFillTypeData.lua")
source(modDirectory .. "src/weather/SeasonsDownfallUpdater.lua")
source(modDirectory .. "src/weather/SeasonsStormUpdater.lua")
source(modDirectory .. "src/weather/SeasonsWeather.lua")
source(modDirectory .. "src/weather/SeasonsWeatherData.lua")
source(modDirectory .. "src/weather/SeasonsWeatherEvent.lua")
source(modDirectory .. "src/weather/SeasonsWeatherForecast.lua")
source(modDirectory .. "src/weather/SeasonsWeatherHandler.lua")
source(modDirectory .. "src/weather/SeasonsWeatherModel.lua")

local seasons = nil -- localize
local version = 1

-- Active test: needed for console version where the code is always sourced.
function isActive()
    if GS_IS_CONSOLE_VERSION and not g_isDevelopmentConsoleScriptModTesting then
        return g_modIsLoaded["FS19_RM_Seasons_console"]
    end

    -- Normally this code never runs if Seasons was not active. However, in development mode
    -- this might not always hold true.
    return g_modIsLoaded["FS19_RM_Seasons"]
end

---Initialize the mod. This code is run once for the lifetime of the program. Every override needs to check if Seasons
-- is still active for consoles: a game might start without Seasons active.
function init()
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)
    FSBaseMission.initTerrain = Utils.appendedFunction(FSBaseMission.initTerrain, initTerrain)
    FSBaseMission.loadMapFinished = Utils.prependedFunction(FSBaseMission.loadMapFinished, loadedMap)
    FSBaseMission.onConnectionFinishedLoading = Utils.overwrittenFunction(FSBaseMission.onConnectionFinishedLoading, connectionFinishedLoading)
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, saveToXMLFile)

    Mission00.load = Utils.prependedFunction(Mission00.load, load)
    Mission00.loadItemsFinished = Utils.appendedFunction(Mission00.loadItemsFinished, loadedItems)
    Mission00.loadMission00Finished = Utils.overwrittenFunction(Mission00.loadMission00Finished, loadedMission)
    Mission00.loadVehiclesFinish = Utils.appendedFunction(Mission00.loadVehiclesFinish, loadedVehicles)
    Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, startMission)

    MPLoadingScreen.setButtonState = Utils.appendedFunction(MPLoadingScreen.setButtonState, inj_mpLoadingScreen_setButtonState)
    MPLoadingScreen.onClickCancel = Utils.overwrittenFunction(MPLoadingScreen.onClickCancel, inj_mpLoadingScreen_onClickCancel)

    VehicleTypeManager.validateVehicleTypes = Utils.prependedFunction(VehicleTypeManager.validateVehicleTypes, validateVehicleTypes)

    if GS_IS_CONSOLE_VERSION then
        -- Static overwritten function
        local originalLoadPlaceable = PlacementUtil.loadPlaceable
        PlacementUtil.loadPlaceable = function(...)
            return inj_placementUtil_loadPlaceable(originalLoadPlaceable, ...)
        end
    end
end

-- Super early prepend: we need to load specs and vehicle type changes even before the mission is created
-- Normally, when loading of a game starts, the mods are loaded. This includes loading specializations from
-- the modDesc, and then the vehicle types with these specs. However, we inject specializations into vehicles
-- so we need to register them ourselves and add them to the vehicle types. All of this has to be done before
-- the vehicle types are finalized (the specs are installed). There is a bit of validation too, so we do our
-- changes before that so we are covered.
-- Note that nothing is available at this point: no other managers are initialized, and no mission is created.
function validateVehicleTypes(vehicleTypeManager)
    if not isActive() then return end

    g_placeableTypeManager:addPlaceableType("waterPump", "WaterPump", modDirectory .. "src/placeables/WaterPump.lua")

    Seasons.onMissionWillLoad(g_i18n)
    Seasons.installSpecializations(g_vehicleTypeManager, g_specializationManager, modDirectory, modName)
end

function load(mission)
    if not isActive() then return end
    assert(g_seasons == nil)

    seasons = Seasons:new(mission, g_messageCenter, g_i18n, modDirectory, g_densityMapHeightManager, g_fillTypeManager, g_modManager, g_deferredLoadingManager, g_gui, g_gui.inputManager, g_fruitTypeManager, g_specializationManager, g_vehicleTypeManager, g_onCreateUtil, g_treePlantManager, g_farmManager, g_missionManager, g_sprayTypeManager, g_gameplayHintManager, g_helpLineManager, g_soundManager, g_animalManager, g_animalFoodManager, g_workAreaTypeManager, g_dedicatedServerInfo, g_sleepManager, g_settingsScreen.settingsModel, g_ambientSoundManager, g_depthOfFieldManager, g_server, g_fieldManager, g_particleSystemManager, g_baleTypeManager, g_npcManager, g_farmlandManager)
    seasons.version = version

    -- Guessed texture memory usage of Seasons (snow, salt)
    mission.textureMemoryUsage = mission.textureMemoryUsage + 3 * 1024 * 1024

    getfenv(0)["g_seasons"] = seasons

    addModEventListener(seasons)


    -- HACKS
    if not g_addTestCommands then
        addConsoleCommand("gsToggleDebugFieldStatus", "Shows field status", "consoleCommandToggleDebugFieldStatus", mission)
        addConsoleCommand("gsTakeEnvProbes", "Takes env. probes from current camera position", "consoleCommandTakeEnvProbes", mission)
    end
end

-- Map object is loaded but not configured into the game
function loadedMap(mission, node)
    if not isActive() then return end

    if node ~= 0 then
        seasons:onMapLoaded(mission, node)
    end
end

--sets terrain root node.set lod, culling, audio culing, creates fruit updaters, sets fruit types to menu, installs weed, DM syncing
function initTerrain(mission, terrainId, filename)
    if not isActive() then return end

    seasons:onTerrainLoaded(mission, terrainId, filename)
end

---All vehicles are loaded. In here the items will start loading (deferred)
function loadedVehicles(mission)
    if not isActive() then return end

    seasons:onVehiclesLoaded(mission)
end

-- in this, missions are created and farms merged
function loadedItems(mission)
    if not isActive() then return end

    if mission:getIsServer() then
        -- Needs deferring so it is loaded after the mission manager
        g_deferredLoadingManager:addTask(function ()
            seasons:onItemsLoaded(mission)
        end)

        g_deferredLoadingManager:addTask(function ()
            seasons:onGameLoaded()
        end)
    end
end

-- Calling saveToXML (after saving)
function saveToXMLFile(missionInfo)
    if not isActive() then return end

    if missionInfo.isValid then
        local xmlFile = createXMLFile("SeasonsXML", missionInfo.savegameDirectory .. "/seasons.xml", "seasons")
        if xmlFile ~= nil then
            seasons:onMissionSaveToSavegame(g_currentMission, xmlFile)

            saveXMLFile(xmlFile)
            delete(xmlFile)
        end
    end
end

-- called after the map is async loaded from :load. has :loadMapData calls. NOTE: self.xmlFile is also deleted here. (Is map.xml)
function loadedMission(mission, superFunc, node)
    if not isActive() then
        return superFunc(mission, node)
    end

    local function callSeasons()
        seasons:onMissionLoading(mission)

        if mission:getIsServer() and mission.missionInfo.savegameDirectory ~= nil and fileExists(mission.missionInfo.savegameDirectory .. "/seasons.xml") then
            local xmlFile = loadXMLFile("SeasonsXML", mission.missionInfo.savegameDirectory .. "/seasons.xml")
            if xmlFile ~= nil then
                seasons:onMissionLoadFromSavegame(mission, xmlFile)
                delete(xmlFile)
            end
        end
    end

    -- The function called for loading vehicles and items depends on the map setup and savegame setup
    -- We want to get a call out before they are called so we need to overwrite the correct one.
    if mission.missionInfo.vehiclesXMLLoad ~= nil then
        local old = mission.loadVehicles
        mission.loadVehicles = function (...)
            callSeasons()
            old(...)
        end
    elseif mission.missionInfo.itemsXMLLoad ~= nil then
        local old = mission.loadItems
        mission.loadItems = function (...)
            callSeasons()
            old(...)
        end
    else
        local old = mission.loadItemsFinished
        mission.loadItemsFinished = function (...)
            callSeasons()
            old(...)
        end
    end

    superFunc(mission, node)

    if mission.cancelLoading then
        return
    end

    g_deferredLoadingManager:addTask(function()
        seasons:onMissionLoaded(mission)
    end)
end

-- Player clicked on start
function startMission(mission)
    if not isActive() then return end

    seasons:onMissionStart(mission)
end

function unload()
    if not isActive() then return end

    removeModEventListener(seasons)

    if GS_IS_CONSOLE_VERSION then
        SeasonsModUtil.unregisterAdjustedFunctions()
        SeasonsModUtil.unregisterConstants()
        SeasonsModUtil.unregisterTireTypes()
    end

    if seasons ~= nil then
        seasons:delete()
        seasons = nil -- Allows garbage collecting
        getfenv(0)["g_seasons"] = nil
    else
        Seasons.onMissionWillUnload(g_i18n)
    end
end

---We inject here and inject ourself in the creation of the farmland initial state event.
-- It is an event that is sent after farms, farmlands and objects have been shared. Weather is also
-- shared by now. It is also before the splitshapes are streamed which would not allow us to
-- wait for the ReadyEvent that causes the Start button to become active. By overwriting this
-- old fashioned way we have access to the connection and we overwrite it only in this specific case.
function connectionFinishedLoading(mission, superFunc, connection, x,y,z, viewDistanceCoeff)
    if not isActive() then return superFunc(mission, connection, x,y,z, viewDistanceCoeff) end

    local oldNew = GreatDemandsEvent.new
    GreatDemandsEvent.new = function (...)
        seasons:onClientJoined(connection)
        return oldNew(...)
    end

    superFunc(mission, connection, x,y,z, viewDistanceCoeff)

    GreatDemandsEvent.new = oldNew

    -- Appending also seems to work
    -- then disable BaseMissionReadyEvent in the other events and keep track ourselves
end

---Disallow all load cancelling
function inj_mpLoadingScreen_setButtonState(screen, state)
    -- Always hide
    if isActive() then
        screen.buttonDeletePC:setVisible(false)
    end
end

function inj_mpLoadingScreen_onClickCancel(screen, superFunc)
    if not isActive() then
        return superFunc(screen)
    end
end

init()

-------------------------------------------------------------------------------
--- Extra functionality to abstract away some internal details
-------------------------------------------------------------------------------

function Vehicle:seasons_getSpecTable(name)
    local spec = self["spec_" .. modName .. "." .. name]
    if spec ~= nil then
        return spec
    end

    return self["spec_" .. name]
end

function Vehicle:seasons_getModName()
    return modName
end

function Vehicle:seasons_getSpecSaveKey(key, specName)
    return ("%s.%s.%s"):format(key, modName, specName)
end

---Add unloading for UIs for proper console unloading. Not used by
-- the basegame because it loads all UI up front (not per savegame).
function Gui:unloadGui(name)
    if self.guis[name] ~= nil then
        local screenClass = self.nameScreenTypes[name]

        self.guis[name] = nil
        self.nameScreenTypes[name] = nil

        if screenClass ~= nil then
            self.screens[screenClass] = nil
            self.screenControllers[screenClass] = nil
        end
    else
        self.frames[name] = nil
    end
end

-------------------------------------------------------------------------------
--- Development only
-------------------------------------------------------------------------------

if g_isDevelopmentVersion or g_showDevelopmentWarnings and g_addCheatCommands then
    function Utils.getTimeScaleIndex(timeScale)
        if timeScale >= 12000 then return 7
        elseif timeScale >= 120 then return 6
        elseif timeScale >= 60 then return 5
        elseif timeScale >= 30 then return 4
        elseif timeScale >= 15 then return 3
        elseif timeScale >= 5 then return 2
        end
        return 1
    end

    function Utils.getTimeScaleFromIndex(timeScaleIndex)
        if timeScaleIndex >= 7 then return 12000
        elseif timeScaleIndex >= 6 then return 120
        elseif timeScaleIndex >= 5 then return 60
        elseif timeScaleIndex >= 4 then return 30
        elseif timeScaleIndex >= 3 then return 15
        elseif timeScaleIndex >= 2 then return 5
        end
        return 1
    end
end

-------------------------------------------------------------------------------
--- Basegame fixes
-------------------------------------------------------------------------------

if g_gameVersion < 7 then

    ---Add a new check when adding types. Adding too many crashes the game
    local oldDensityFunc = DensityMapHeightManager.addDensityMapHeightType
    function DensityMapHeightManager:addDensityMapHeightType(fillTypeName, ...)
        if self.fillTypeNameToHeightType[fillTypeName] == nil then
            if self.numHeightTypes >= (2 ^ g_currentMission.terrainDetailHeightTypeNumChannels) - 1 then
                g_logManager:error("addDensityMapHeightType: maximum number of height types already registered.")
                return nil
            end
        end

        return oldDensityFunc(self, fillTypeName, ...)
    end

    ---Fix handtool sync in MP
    function SellHandToolEvent:run(connection)
        local dataStoreItem = g_storeManager:getItemByXMLFilename(self.filename)
        local filename = self.filename
        if dataStoreItem ~= nil then
            filename = dataStoreItem.xmlFilename
        end

        if not connection:getIsServer() then
            local state = SellHandToolEvent.STATE_FAILED

            if not g_currentMission:getHasPlayerPermission("sellVehicle", connection) then
                state = SellHandToolEvent.STATE_NO_PERMISSION
                dataStoreItem = nil
            end

            -- make sure that currently equipped hand tools cannot be sold
            local toolInUse = false
            if g_currentMission.players ~= nil then
                for _, player in pairs(g_currentMission.players) do
                    if player:getEquippedHandtoolFilename():lower() == filename:lower() then
                        toolInUse = true
                        break
                    end
                end
            end

            if dataStoreItem ~= nil and not toolInUse and g_currentMission.players ~= nil then
                self:removeHandTool(filename, self.farmId)
                state = SellHandToolEvent.STATE_SUCCESS
                if g_currentMission:getIsServer() then
                    g_server:broadcastEvent(SellHandToolEvent:new(filename, self.farmId), false, connection)

                    g_currentMission:addMoney(g_currentMission.economyManager:getSellPrice(dataStoreItem), self.farmId, MoneyType.SHOP_VEHICLE_SELL, true)
                end
            end

            connection:sendEvent(SellHandToolEvent:newServerToClient(state, filename, self.farmId))
        else
            if self.isAnswer then
                if self.state == SellHandToolEvent.STATE_SUCCESS then
                    self:removeHandTool(filename, self.farmId)
                end

                g_messageCenter:publish(SellHandToolEvent, {self.state})
            else
                self:removeHandTool(filename, self.farmId)
            end
        end
    end

    ---Use proper casing
    function BuyHandToolEvent:addHandTool(xmlFilename, useStoreItemPath, farmId)
        if useStoreItemPath then
            xmlFilename = g_storeManager:getItemByXMLFilename(xmlFilename).xmlFilename
        end

        g_farmManager:getFarmById(farmId):addHandTool(xmlFilename)
    end

    ---Use proper casing
    function Farm:hasHandtool(xmlFilename)
        return ListUtil.hasListElement(self.handTools, xmlFilename)
    end

    ---Use proper casing
    function Farm:addHandTool(xmlFilename)
        ListUtil.addElementToList(self.handTools, xmlFilename)
    end

    ---Use proper casing
    function Farm:removeHandTool(xmlFilename)
        ListUtil.removeElementFromList(self.handTools, xmlFilename)
    end

    local oldFarmLoadFunc = Farm.loadFromXMLFile
    function Farm:loadFromXMLFile(xmlFile, key)
        if not oldFarmLoadFunc(self, xmlFile, key) then
            return false
        end

        for i, filename in ipairs(self.handTools) do
            -- In previous versions the name was stored in lowercase. In that case, find the correct path.
            if filename:lower() == filename then
                local xmlFilenameLower = filename:lower()
                for _, item in ipairs(g_storeManager:getItems()) do
                    local name = item.xmlFilename:lower()
                    if name == xmlFilenameLower then
                        self.handTools[i] = item.xmlFilename
                        break
                    end
                end
            end
        end

        return true
    end
end

---Fixes for basegame unloading of UIs. This is only needed because of proper unloading for consoles
function ListElement:delete()
    -- This forwards to removeElement
    self.deletingAllListItems = true

    local numItems = #self.listItems
    for i = 1,numItems do
        self.listItems[1]:delete()
    end

    ListElement:superClass().delete(self)
end

local oldListElementRemoveElement = ListElement.removeElement
function ListElement:removeElement(element)
    if self.deletingAllListItems then
        ListElement:superClass().removeElement(self, element)
        return
    end

    return oldListElementRemoveElement(self, element)
end

---Full override. Bug in basegame where valid missions are not updated with their last growth state and other properties.
---In seasons this breaks the missions mostly.
function MissionManager:canMissionStillRun(mission)
    local field = mission.field
    if field == nil then
        return true
    end

    local fieldSpraySet, sprayFactor, fieldPlowFactor, limeFactor, weedFactor, maxWeedState = self:getFieldData(field)

    local canRun, fieldState, growthState, weedState = mission.type.class.canRunOnField(field, sprayFactor, fieldSpraySet, fieldPlowFactor, limeFactor, maxWeedState)

    if canRun then
        -- if it can run, update mission parameters so they are up to date.
        mission.sprayFactor = sprayFactor
        mission.fieldSpraySet = fieldSpraySet
        mission.fieldPlowFactor = fieldPlowFactor
        mission.fieldState = fieldState
        mission.growthState = growthState
        mission.limeFactor = limeFactor
        mission.weedFactor = weedFactor
        mission.weedState = weedState
    end

    return canRun
end

---Fix rounding of negative numbers with precision 0
function I18N:formatNumber(number, precision, forcePrecision)
    local currencyString = ""
    -- use currency symbol and separator to format the number correctly
    -- Examples: 54040 --> 54,040 $    -3470 --> -3'470 ?
    if precision == nil then
        precision = 0
    end

    if precision == 0 then
        -- if precision is 0 always use floor to avoid "No money"-Issues if price is 70 and you only have 69.9. But the game shows 70 in the money menu
        if number == nil then
            printCallstack()
        end

        -- Rown DOWN to 0, instead of rounding low
        if number < 0 then
            number = -math.floor(-number)
        else
            number = math.floor(number)
        end
    end

    local baseString = string.format("%1."..precision.."f", number)
    -- special case show 0$ instead of -0$
    if baseString == "-0" then
        baseString = "0"
    end

    local groupingChar = self:getText("unit_digitGroupingSymbol")
    if groupingChar ~= " " and groupingChar ~= "." and groupingChar ~= "," then
        groupingChar = " "
    end

    local prefix, num, decimal = string.match(baseString, "^([^%d]*%d)(%d*)[.]?(%d*)")
    currencyString = prefix .. (num:reverse():gsub("(%d%d%d)", "%1" .. groupingChar):reverse())
    local prec = decimal:len()
    if prec > 0 then
        if decimal ~= string.rep("0", prec) or forcePrecision then
            currencyString = currencyString .. self:getDecimalSeparator() ..decimal:sub(1, precision)
        end
    end

    return currencyString
end

-------------------------------------------------------------------------------
--- Console script fixes
-------------------------------------------------------------------------------

if GS_IS_CONSOLE_VERSION then
    ---Turn FS19_RM_Seasons into a _console version
    function inj_placementUtil_loadPlaceable(superFunc, placeableType, ...)
        if isActive() then
            if placeableType == "FS19_RM_Seasons.waterPump" then
                placeableType = "FS19_RM_Seasons_console.waterPump"
            end
        end

        return superFunc(placeableType, ...)
    end
end

