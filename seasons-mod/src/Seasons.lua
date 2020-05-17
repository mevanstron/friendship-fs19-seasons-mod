----------------------------------------------------------------------------------------------------
-- Seasons
----------------------------------------------------------------------------------------------------
-- Purpose:  Main class
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

Seasons = {}
Seasons.VERSION = 2

local Seasons_mt = Class(Seasons)

function Seasons:new(mission, messageCenter, i18n, modDirectory, densityMapHeightManager, fillTypeManager, modManager, deferredLoadingManager, gui, inputManager, fruitTypeManager, specializationManager, vehicleTypeManager, onCreateUtil, treePlantManager, farmManager, missionManager, sprayTypeManager, gameplayHintManager, helpLineManager, soundManager, animalManager, animalFoodManager, workAreaTypeManager, dedicatedServerInfo, sleepManager, settingsModel, ambientSoundManager, depthOfFieldManager, server, fieldManager, particleSystemManager, baleTypeManager, npcManager, farmlandManager)
    local self = setmetatable({}, Seasons_mt)

    self.isServer = mission:getIsServer()
    self.modDirectory = modDirectory
    self.mission = mission
    self.deferredLoadingManager = deferredLoadingManager
    self.gui = gui
    self.i18n = i18n
    self.messageCenter = messageCenter
    self.densityMapHeightManager = densityMapHeightManager
    self.gui = gui

    self.version = Seasons.VERSION
    self.savegameVersion = self.version
    self.isNewSavegame = true -- new save with seasons (or existing save, but seasons now added)

    self.thirdPartyMods = SeasonsThirdPartyMods:new(modManager, modDirectory, deferredLoadingManager, mission)
    self.localStorage = SeasonsLocalStorage:new(mission)
    self.mask = SeasonsMask:new(mission, modDirectory)
    self.environment = SeasonsEnvironment:new(mission, messageCenter, sleepManager)
    self.densityMapScanner = SeasonsDensityMapScanner:new(mission, deferredLoadingManager, dedicatedServerInfo, sleepManager)
    self.snowHandler = SeasonsSnowHandler:new(mission, self.densityMapScanner, modDirectory, i18n, densityMapHeightManager, fillTypeManager, self.mask, messageCenter, particleSystemManager)
    self.weather = SeasonsWeather:new(mission, self.environment, self.snowHandler, messageCenter, modDirectory, server)
    self.lighting = SeasonsLighting:new(mission, self.environment, self.weather, messageCenter, modDirectory)
    self.growth = SeasonsGrowth:new(mission, self.environment, messageCenter, i18n, fruitTypeManager, self.densityMapScanner, self.weather, sprayTypeManager, fieldManager)
    self.vehicle = SeasonsVehicle:new(mission, specializationManager, modDirectory, vehicleTypeManager, workAreaTypeManager, fillTypeManager, i18n)
    self.visuals = SeasonsVisuals:new(mission, self.environment, messageCenter, depthOfFieldManager)
    self.ui = SeasonsUI:new(mission, messageCenter, self.environment, i18n, gui, modDirectory, inputManager, self.weather, gameplayHintManager, helpLineManager, self.densityMapScanner, settingsModel, self.growth, self.localStorage)
    self.contracts = SeasonsContracts:new(mission, missionManager, self.environment, self.weather, npcManager, i18n, messageCenter, farmlandManager)
    self.objectFactory = ObjectFactory:new(mission, messageCenter, onCreateUtil, self.weather, self.environment, self.snowHandler, self.contracts)
    self.placeableAdmirers = PlaceableAdmirers:new(messageCenter, self.weather, self.environment, self.snowHandler)
    self.grass = SeasonsGrass:new(mission, self.densityMapScanner, densityMapHeightManager, messageCenter, modDirectory, fillTypeManager, self.environment, self.mask, self.weather, fruitTypeManager, baleTypeManager)
    self.trees = SeasonsTrees:new(mission, treePlantManager, messageCenter, self.environment)
    self.economy = SeasonsEconomy:new(mission, messageCenter, self.environment, fillTypeManager, farmManager, animalManager)
    self.sound = SeasonsSound:new(mission, soundManager, modDirectory, ambientSoundManager, self.weather, gui)
    self.animals = SeasonsAnimals:new(mission, animalManager, animalFoodManager, messageCenter, self.environment, self.weather, i18n, fruitTypeManager)

    self.messageCenter:subscribe(MessageType.HOUR_CHANGED, self.onHourChanged, self)

    SeasonsModUtil.appendedFunction(FSBaseMission, "setTimeScale", self.inj_fsBaseMission_setTimeScale)

    return self
end

function Seasons:delete()
    self.contracts:delete()
    self.localStorage:delete()
    self.animals:delete()
    self.sound:delete()
    self.economy:delete()
    self.trees:delete()
    self.grass:delete()
    self.objectFactory:delete()
    self.placeableAdmirers:delete()
    self.ui:delete()
    self.visuals:delete()
    self.vehicle:delete()
    self.growth:delete()
    self.snowHandler:delete()
    self.lighting:delete()
    self.weather:delete()
    self.densityMapScanner:delete()
    self.environment:delete()
    self.mask:delete()
    self.thirdPartyMods:delete()

    Seasons.removeModTranslations(self.i18n)
    self.messageCenter:unsubscribeAll(self)
end

------------------------------------------------
--- Events from mission
------------------------------------------------

function Seasons.onMissionWillLoad(i18n)
    Seasons.addModTranslations(i18n)

    SeasonsSound.onMissionWillLoad()
    SeasonsWeather.onMissionWillLoad()
    SeasonsAnimals.onMissionWillLoad()
end

function Seasons.onMissionWillUnload(i18n)
    Seasons.removeModTranslations(i18n)
end

---Called after the map was loaded
function Seasons:onMapLoaded(mission, node)
    -- Test if we can load 3 more height types
    if self.densityMapHeightManager.numHeightTypes + 3 > (2 ^ self.mission.terrainDetailHeightTypeNumChannels) - 1 then
        self.failedToLoadDueTooManyHeightTypes = true
    end

    self.snowHandler:onMapLoaded()
    self.grass:onMapLoaded()
end

---Called after the terrain has been created, including fruits and terrain detail density maps
function Seasons:onTerrainLoaded(mission, terrainId, mapFilename)
    self.mask:onTerrainLoaded(mapFilename)
    self.snowHandler:onTerrainLoaded()
    self.grass:onTerrainLoaded()
    self.animals:onTerrainLoaded()
    self.growth:onTerrainLoaded()
end

-- Mission is loading
function Seasons:onMissionLoading()
    self.thirdPartyMods:load()

    self.environment:setDataPaths(self:getDataPaths("environment.xml"))
    self.environment:setLatitudeDataPaths(self:getDataPaths("latitudeSeason.xml"))
    self.weather:setDataPaths(self:getDataPaths("weather.xml"))
    self.lighting:setDataPaths(self:getDataPaths("lighting.xml"))
    self.growth:setDataPaths(self:getDataPaths("crops.xml"))
    self.visuals:setDataPaths(self:getDataPaths("visuals.xml"))
    self.economy:setDataPaths(self:getDataPaths("economy.xml"))
    self.animals:setDataPaths(self:getDataPaths("animals.xml"))
    self.vehicle:setDataPaths(self:getDataPaths("vehicle.xml"))
    self.vehicle:setFillTypeDataPaths(self:getDataPaths("fillTypes.xml"))

    self.localStorage:loadFromProfile()

    self.mask:load()
    self.environment:load()
    self.densityMapScanner:load()
    self.weather:load()
    self.lighting:load()
    self.snowHandler:load()
    self.growth:load()
    self.vehicle:load()
    self.visuals:load()
    self.ui:load()
    self.grass:load()
    self.trees:load()
    self.economy:load()
    self.sound:load()
    self.animals:load()
    self.objectFactory:load()
    self.contracts:load()
end

---Called after the savegame is loaded from XML
function Seasons:onMissionLoadFromSavegame(mission, xmlFile)
    self.savegameVersion = getXMLInt(xmlFile, "seasons#version")
    if self.savegameVersion > self.version then
        Logging.error("Your savegame was created with a newer version of Seasons and can't be loaded. A new Seasons savegame is created.")
        return
    end

    self.isNewSavegame = false

    self.environment:loadFromSavegame(xmlFile)
    self.densityMapScanner:loadFromSavegame(xmlFile)
    self.snowHandler:loadFromSavegame(xmlFile)
    self.weather:loadFromSavegame(xmlFile)
    self.growth:loadFromSavegame(xmlFile)
    self.grass:loadFromSavegame(xmlFile)
    self.economy:loadFromSavegame(xmlFile)
    self.vehicle:loadFromSavegame(xmlFile)
    self.animals:loadFromSavegame(xmlFile)
end

---Mission was loaded (without vehicles and items)
function Seasons:onMissionLoaded(mission)
    self.ui:onMissionLoaded()
    self.growth:onMissionLoaded()

    self.deferredLoadingManager:addTask(function ()
        self.densityMapScanner:runWholeQueue()
    end)

    self.deferredLoadingManager:addTask(function ()
        self.visuals:updateAllNodes()
    end)
end

---Called after all vehicles are loaded. Server only.
function Seasons:onVehiclesLoaded(mission)
end

---Called after all items are loaded. Server only.
function Seasons:onItemsLoaded(mission)
    self.weather:onItemsLoaded()
end

---Called after everything is loaded, on client (after read stream) and on server (after items loaded)
function Seasons:onGameLoaded()
    self.weather:onGameLoaded()
    self.economy:onGameLoaded()
    self.animals:onGameLoaded()
    self.trees:onGameLoaded()
    self.visuals:onGameLoaded()
    self.environment:onGameLoaded()
    self.snowHandler:onGameLoaded()

    -- If we were unable to load the height types we need to quit or errors will happen during gameplay
    if self.failedToLoadDueTooManyHeightTypes then
        self.gui:showInfoDialog({
            dialogType = DialogElement.TYPE_INFO,
            text = self.i18n:getText("seasons_message_failedHeightTypes"),
            target = nil,
            callback = function()
                OnInGameMenuMenu()
            end
        })
    end
end

---Called when the player clicks the Start button
function Seasons:onMissionStart(mission)
    self.ui:onMissionStart()
end

---Called after the mission is saved to XML
function Seasons:onMissionSaveToSavegame(mission, xmlFile)
    setXMLInt(xmlFile, "seasons#version", self.version)

    self.environment:saveToSavegame(xmlFile)
    self.densityMapScanner:saveToSavegame(xmlFile)
    self.snowHandler:saveToSavegame(xmlFile)
    self.weather:saveToSavegame(xmlFile)
    self.growth:saveToSavegame(xmlFile)
    self.grass:saveToSavegame(xmlFile)
    self.economy:saveToSavegame(xmlFile)
    self.vehicle:saveToSavegame(xmlFile)
    self.animals:saveToSavegame(xmlFile)
end

------------------------------------------------
--- Networking
------------------------------------------------

function Seasons:writeStream(streamId, connection)
    self.environment:writeStream(streamId, connection)
    self.weather:writeStream(streamId, connection)
    self.snowHandler:writeStream(streamId, connection)
    self.economy:writeStream(streamId, connection)
end

function Seasons:readStream(streamId, connection)
    self.environment:readStream(streamId, connection)
    self.weather:readStream(streamId, connection)
    self.snowHandler:readStream(streamId, connection)
    self.economy:readStream(streamId, connection)
end

---Send any initial state. Called once a client joins
function Seasons:onClientJoined(connection)
    -- Call all writeStream/readStream in the mod
    connection:sendEvent(SeasonsInitialStateEvent:new(self))

    -- Send any extra events
    self.weather:onClientJoined(connection)

    -- Call onGameLoaded on the client
    connection:sendEvent(SeasonsLoadFinishedEvent:new(self))
end

------------------------------------------------
--- Events from mod event handling
------------------------------------------------

---Called every frame update
function Seasons:update(dt)
    self.densityMapScanner:update(dt)
    self.weather:update(dt)
    self.visuals:update(dt)
    self.ui:update(dt)
    self.sound:update(dt)
    self.growth:update(dt)
    self.vehicle:update(dt)
end

---Called every draw
function Seasons:draw()
    self.mask:draw()
    self.growth.cropRotation:visualize()
end

---Called on a key input. Do only use this for custom things. Not for actions. Use the input action system for that.
function Seasons:keyEvent(unicode, sym, modifier, isDown)
end

---Called on a mouse input. Do only use this for mouse movement and custom things. Not for actions. Use the input action system for that.
function Seasons:mouseEvent(posX, posY, isDown, isUp, button)
end

---Get the data paths for a data file with given filename
function Seasons:getDataPaths(filename)
    local paths = self.thirdPartyMods:getDataPaths(filename)

    -- First add base seasons
    local path = Utils.getFilename("data/" .. filename, self.modDirectory)
    if fileExists(path) then
        table.insert(paths, 1, { file = path, modDir = self.modDirectory })
    end

    return paths
end

---Copy our translations to global space.
function Seasons.addModTranslations(i18n)
    -- We can copy all our translations to the global table because we prefix everything with seasons_
    -- The mod-based l10n lookup only really works for vehicles, not UI and script mods.
    local global = getfenv(0).g_i18n.texts

    for key, text in pairs(i18n.texts) do
        if StringUtil.startsWith(key, "overwrite_") then
            -- Need to revert
            SeasonsModUtil.overwrittenConstant(global, key:sub(11), text)
        else
            global[key] = text
        end
    end
end

---Remove mod translations to prevent duplicated next time it gets loaded
function Seasons.removeModTranslations(i18n)
    local global = getfenv(0).g_i18n.texts
    for key, text in pairs(i18n.texts) do
        global[key] = nil
    end
end

---This is called before anything of the game has been created.
-- The vehicle types must not be initialized yet to make any changes to them.
function Seasons.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    SeasonsVehicle.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    SeasonsGrass.installSpecializations()
    SeasonsEconomy.installSpecializations()
end

---When the hour changed we send the hour-changed-fix message that has a correct current day
-- set in the environment
function Seasons:onHourChanged(hour)
    local currentDay = self.mission.environment.currentDay
    if hour == 0 then
        self.mission.environment.currentDay = currentDay + 1
    end

    self.messageCenter:publish(SeasonsMessageType.HOUR_CHANGED_FIX, {hour})

    self.mission.environment.currentDay = currentDay
end

-------------------------------------------------------------------------------
--- Basegame adjustments
-------------------------------------------------------------------------------

---Change the time interval update time in MP depending on the time scale. In basegame
---it is always 60 seconds but 60 seconds when sleeping is very long
function Seasons.inj_fsBaseMission_setTimeScale(mission, timeScale, noEventSend)
    mission.environment.timeUpdateInterval = 1000 * 60 / math.max(timeScale / 60, 1)
end
