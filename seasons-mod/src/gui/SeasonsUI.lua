----------------------------------------------------------------------------------------------------
-- SeasonsUI
----------------------------------------------------------------------------------------------------
-- Purpose:  Constructor of the UI system for Seasons: installs HUDs and menus.
--           Also handles UI overrides.
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsUI = {}

local SeasonsUI_mt = Class(SeasonsUI)


function SeasonsUI:new(mission, messageCenter, environment, i18n, gui, modDirectory, inputManager, weather, gameplayHintManager, helpLineManager, densityMapScanner, settingsModel, growth, localStorage)
    local self = setmetatable({}, SeasonsUI_mt)

    self.mission = mission
    self.messageCenter = messageCenter
    self.i18n = i18n
    self.gui = gui
    self.environment = environment
    self.modDirectory = modDirectory
    self.inputManager = inputManager
    self.isClient = mission:getIsClient()
    self.weather = weather
    self.gameplayHintManager = gameplayHintManager
    self.helpLineManager = helpLineManager
    self.settingsModel = settingsModel
    self.growth = growth
    self.localStorage = localStorage

    self.uiFilename = Utils.getFilename("resources/gui/seasons_2160p.png", modDirectory)
    -- if g_screenHeight < 720 then
    --     self.uiFilename = Utils.getFilename("resources/gui/seasons_720p.png", modDirectory)
    if g_screenHeight <= 1080 or GS_IS_CONSOLE_VERSION then
        self.uiFilename = Utils.getFilename("resources/gui/seasons_1080p.png", modDirectory)
    end

    self.hud = SeasonsHUD:new(mission, mission.hud.gameInfoDisplay, i18n, messageCenter, self.uiFilename)
    self.fieldInfo = SeasonsFieldInfo:new(mission.hud)
    self.catchingUp = SeasonsCatchingUp:new(mission, densityMapScanner, gui, i18n)
    self.workshop = SeasonsWorkshop:new(mission, gui, i18n)

    -- Early, as we want to show these in the loading screen
    self:overwriteGameplayHints()

    self.nextInfoStateUpdate = 0

    SeasonsModUtil.appendedFunction(BaseMission,                        "unregisterActionEvents",   self.inj_baseMission_unregisterActionEvents)
    SeasonsModUtil.appendedFunction(FSBaseMission,                      "registerActionEvents",     self.inj_fsBaseMission_registerActionEvents)
    SeasonsModUtil.appendedFunction(InGameMenuStatisticsFrame,          "updateStatistics",         self.inj_inGameMenuStatisticsFrame_updateStatistics)
    SeasonsModUtil.overwrittenConstant(Gui.CONFIGURATION_CLASS_MAPPING, "barChart",                 BarChartElement)
    SeasonsModUtil.overwrittenConstant(Gui.CONFIGURATION_CLASS_MAPPING, "localizedText",            LocalizedTextElement)
    SeasonsModUtil.overwrittenFunction(HUD,                             "addSideNotification",      self.inj_HUD_addSideNotification)
    SeasonsModUtil.overwrittenFunction(HUD,                             "showMoneyChange",          self.inj_HUD_showMoneyChange)
    SeasonsModUtil.overwrittenFunction(MultiTextOptionElement,          "inputEvent",               self.inj_multiTextOptionElement_inputEvent)
    SeasonsModUtil.overwrittenFunction(SideNotification,                "addNotification",          self.inj_sideNotification_addNotification)
    SeasonsModUtil.overwrittenFunction(TextElement,                     "updateSize",               self.inj_textElement_updateSize)
    SeasonsModUtil.overwrittenStaticFunction(GuiOverlay,                "loadOverlay",              self.inj_guiOverlay_loadOverlay)

    -- Hide the original animals page.
    local menu = self.mission.inGameMenu
    SeasonsModUtil.overwrittenStaticFunction(menu.pageEnablingPredicates, menu.pageAnimals, function()
        return false
    end)

    return self
end

function SeasonsUI:delete()
    if self.isClient then
        self.catchingUp:delete()
        self.fieldInfo:delete()
        self.hud:delete()
        self.workshop:delete()

        -- self:unregisterActionEvents()
        self:ejectFromBasegameMenus()
        self:unloadMenu()

        self.messageCenter:unsubscribeAll(self)
    end
end

function SeasonsUI:load()
    if self.isClient then
        self.hud:load()
        self.fieldInfo:load()
        self.catchingUp:load()
        self.workshop:load()

        self.gui:loadProfiles(Utils.getFilename("resources/gui/guiProfiles.xml", self.modDirectory))

        self:loadMenu()
        self:injectIntoBasegameMenus()

        self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
        self.messageCenter:subscribe(SeasonsMessageType.HOUR_CHANGED_FIX, self.onHourChanged, self)
        self.messageCenter:subscribe(SeasonsMessageType.SEASON_CHANGED, self.onSeasonChanged, self)
        self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)
    end
end

function SeasonsUI:onMissionLoaded()
    -- Load after the basegame help menu is loaded so it shows up at the end
    self:loadHelplineCategories()

    if self.growth.data.isNewGame and self.mission.missionInfo.isValid and g_dedicatedServer == nil and self.mission:getIsServer() then
        self.gui:showYesNoDialog({
            text = self.i18n:getText("seasons_ui_resetGrowth"),
            title = self.i18n:getText("seasons_ui_resetGrowth_title"),
            yesText = self.i18n:getText("seasons_ui_resetGrowth_yes"),
            noText = self.i18n:getText("seasons_ui_resetGrowth_no"),
            target = self,
            callback = self.onGrowthResetDialogClosed,
        })
    end
end

function SeasonsUI:onMissionStart()
    local airTemp = self.weather:getCurrentAirTemperature()
    local soilTemp = self.weather:getCurrentSoilTemperature()

    self.hud:setTemperature(airTemp, soilTemp)
    self.hud:setDate(self.environment.dayInSeason, self.environment.period)
    self.hud:setSeason(self.environment.season)

        -- Whether to show the initial season dialog
    self.shouldShowSeasonStartInfo = self.mission.missionInfo.isNewSPCareer and not self.mission.missionDynamicInfo.isMultiplayer and self.localStorage:getShowTutorialMessages()
end

----------------------
-- Events
----------------------

function SeasonsUI:onSeasonChanged(season, isLoadingSavegame)
    self.hud:setSeason(season)

    if not isLoadingSavegame and self.localStorage:getShowTutorialMessages() then
        self:showSeasonInfo()
    end
end

function SeasonsUI:showSeasonInfo()
    self.gui:showYesNoDialog({
        dialogType = DialogElement.TYPE_INFO,
        text = self.i18n:getText("seasons_intro_" .. self.environment.season),
        yesText = self.i18n:getText("button_ok"),
        noText = self.i18n:getText("seasons_ui_dontShowAgain"),
        target = self,
        callback = self.onSeasonIntroDialogClosed,
    })
end

function SeasonsUI:onDayChanged()
    self.hud:setDate(self.environment.dayInSeason, self.environment.period)
end

function SeasonsUI:onHourChanged()
    local airTemp = self.weather:getCurrentAirTemperature()
    local soilTemp = self.weather:getCurrentSoilTemperature()
    self.hud:setTemperature(airTemp, soilTemp)
end

function SeasonsUI:onSeasonLengthChanged()
    self.hud:setDate(self.environment.dayInSeason, self.environment.period)
end

function SeasonsUI:onGrowthResetDialogClosed(doReset)
    if doReset then
        self.growth:resetGrowth()
    end
end

function SeasonsUI:onSeasonIntroDialogClosed(keep)
    if not keep then
        self.localStorage:setShowTutorialMessages(false)
    end
end

---Called by the toggle action event
function SeasonsUI:onToggleMenu()
    if not self.mission.isSynchronizingWithPlayers then
        self.gui:changeScreen(nil, SeasonsMenu)
    end
end

----------------------
-- Setting up
----------------------

---Create the main menu
function SeasonsUI:loadMenu()
    local calendarFrame = SeasonsCalendarFrame:new(self.i18n)
    local forecastFrame = SeasonsForecastFrame:new(self.i18n)
    local cropsFrame = SeasonsCropsFrame:new(self.i18n)
    local economyFrame = SeasonsEconomyFrame:new(self.i18n)
    local settingsFrame = SeasonsSettingsFrame:new(self.i18n, self.settingsModel, self.environment, self.localStorage)
    local rotationFrame = SeasonsRotationFrame:new(self.i18n, self.localStorage)
    local animalsFrame = SeasonsAnimalsFrame:new(self.i18n)

    self.menu = SeasonsMenu:new(self.messageCenter, self.i18n, self.inputManager)

    local root = Utils.getFilename("resources/gui/", self.modDirectory)
    self.gui:loadGui(root .. "SeasonsCalendarFrame.xml", "SeasonsCalendarFrame", calendarFrame, true)
    self.gui:loadGui(root .. "SeasonsForecastFrame.xml", "SeasonsForecastFrame", forecastFrame, true)
    self.gui:loadGui(root .. "SeasonsCropsFrame.xml", "SeasonsCropsFrame", cropsFrame, true)
    self.gui:loadGui(root .. "SeasonsEconomyFrame.xml", "SeasonsEconomyFrame", economyFrame, true)
    self.gui:loadGui(root .. "SeasonsSettingsFrame.xml", "SeasonsSettingsFrame", settingsFrame, true)
    self.gui:loadGui(root .. "SeasonsRotationFrame.xml", "SeasonsRotationFrame", rotationFrame, true)
    self.gui:loadGui(root .. "SeasonsAnimalsFrame.xml", "SeasonsAnimalsFrame", animalsFrame, true)
    self.gui:loadGui(root .. "SeasonsMenu.xml", "SeasonsMenu", self.menu)

    self.measurementDialog = SeasonsMeasurementDialog:new()
    self.gui:loadGui(root .. "SeasonsMeasurementDialog.xml", "SeasonsMeasurementDialog", self.measurementDialog)

    self.workshop:installCustomUI()
end

---Remove the main menu from the game.
function SeasonsUI:unloadMenu()
    -- Frames use names inside the XML
    self.gui:unloadGui("seasonsCalendar")
    self.gui:unloadGui("seasonsForecast")
    self.gui:unloadGui("seasonsCrops")
    self.gui:unloadGui("seasonsEconomy")
    self.gui:unloadGui("seasonsSettings")
    self.gui:unloadGui("seasonsCropRotation")
    self.gui:unloadGui("seasonsAnimals")

    self.gui:unloadGui("SeasonsMenu")
    self.gui:unloadGui("SeasonsMeasurementDialog")

    self.menu:delete()
    self.measurementDialog:delete()

    self.workshop:uninstallCustomUI()
end

function SeasonsUI:registerActionEvents()
    local _, eventId = self.inputManager:registerActionEvent(InputAction.SEASONS_SHOW_MENU, self, self.onToggleMenu, false, true, false, true)
    self.inputManager:setActionEventTextVisibility(eventId, true)

    self.openMenuEvent = eventId
end

function SeasonsUI:unregisterActionEvents()
    self.inputManager:removeActionEventsByTarget(self)
end

function SeasonsUI:injectIntoBasegameMenus()
    local gameSettingsFrame = self.mission.inGameMenu.pageSettingsGame

    gameSettingsFrame.checkPlantGrowthRate:setVisible(false)
    gameSettingsFrame.checkPlantWithering:setVisible(false)

    gameSettingsFrame.checkPlantWithering.parent:invalidateLayout()
end

function SeasonsUI:ejectFromBasegameMenus()
    local gameSettingsFrame = self.mission.inGameMenu.pageSettingsGame

    gameSettingsFrame.checkPlantGrowthRate:setVisible(true)
    gameSettingsFrame.checkPlantWithering:setVisible(true)

    gameSettingsFrame.checkPlantWithering.parent:invalidateLayout()
end

---Load new gameplay hints (changes of vanilla and new ones)
function SeasonsUI:overwriteGameplayHints()
    self.gameplayHintManager.gameplayHints = {} -- reset

    local xmlFile = loadXMLFile("gameplayHints", Utils.getFilename("resources/gameplayHints.xml", self.modDirectory))

    local i = 0
    while true do
        local key = string.format("gameplayHints.gameplayHint(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local text = getXMLString(xmlFile, key)
        if text:sub(1,6) == "$l10n_" then
            text = g_i18n:getText(text:sub(7))
        end
        table.insert(self.gameplayHintManager.gameplayHints, text)

        i = i + 1
    end
    delete(xmlFile)

    g_mpLoadingScreen.currentGameplayHints = nil
end

---Load the Seasons help
function SeasonsUI:loadHelplineCategories()
    self.helpLineManager:loadFromXML(Utils.getFilename("resources/helpLine.xml", self.modDirectory))
end

function SeasonsUI:update(dt)
    self.catchingUp:update(dt)
    self:updateInfoState(dt)

    if self.shouldShowSeasonStartInfo then
        if not self.mission.hud:isInGameMessageVisible() and not self.gui:getIsGuiVisible() and #self.mission.hud.popupMessage.pendingMessages == 0 then
            self.shouldShowSeasonStartInfo = false

            self:showSeasonInfo()
        end
    end
end

---Update the HUD info state every 5 seconds
function SeasonsUI:updateInfoState(dt)
    if self.nextInfoStateUpdate < 0 then
        self.nextInfoStateUpdate = 5000

        if self.weather:isGroundFrozen() then
            self.hud:setInfoState(SeasonsHUD.INFO_STATE.FROZEN_SOIL)
        elseif self.weather:isCropWet() then
            self.hud:setInfoState(SeasonsHUD.INFO_STATE.MOIST_CROPS)
        else
            self.hud:setInfoState(SeasonsHUD.INFO_STATE.NONE)
        end
    else
        self.nextInfoStateUpdate = self.nextInfoStateUpdate - dt
    end
end

function SeasonsUI:showMeasurementDialog(list, callback, target)
    local dialog = self.gui:showDialog("SeasonsMeasurementDialog")
    if dialog ~= nil then
        dialog.target:setContent(list)
        dialog.target:setCallback(callback, target)
    end
end

----------------------
-- Injections
----------------------

function SeasonsUI.inj_guiOverlay_loadOverlay(superFunc, ...)
    local overlay = superFunc(...)
    if overlay == nil then
        return nil
    end

    if overlay.filename == "g_seasonsUIFilename" then
        overlay.filename = g_seasons.ui.uiFilename
    end

    return overlay
end

function SeasonsUI.inj_fsBaseMission_registerActionEvents(mission)
    g_seasons.ui:registerActionEvents()
end

function SeasonsUI.inj_baseMission_unregisterActionEvents(mission)
    g_seasons.ui:unregisterActionEvents()
end

---Fix a scaling bug. Full overwrite to prevent double-fixing (which causes more issues)
function SeasonsUI.inj_textElement_updateSize(element, superFunc, forceTextSize)
    if not element.textAutoSize and not forceTextSize then
        return
    end

    local offset = element:getTextOffset()
    local textWidth = element:getTextWidth()

    local width = offset + textWidth
    local height = element.size[2]
    if height == 0 then
        height = element.textSize
    end

    -- Added
    local xScale, yScale = element:getAspectScale()
    element:setSize(width / xScale, height)

    if element.parent ~= nil and element.parent.invalidateLayout ~= nil then
        element.parent:invalidateLayout()
    end
end

---Do not display duplicate notifications
function SeasonsUI.inj_sideNotification_addNotification(notification, superFunc, text, color, displayDuration, doNotDeduplicate)
    local last = notification.notificationQueue[#notification.notificationQueue]
    if last ~= nil and last.text == text and not doNotDeduplicate then
        return
    end

    return superFunc(notification, text, color, displayDuration)
end

---For money changes, always ignore de-duplication
function SeasonsUI.inj_HUD_showMoneyChange(hud, superFunc, moneyType, text)
    -- Activate no-dedeplication
    local old = hud.addSideNotification
    hud.addSideNotification = function(hud, color, text, duration)
        return old(hud, color, text, duration, true)
    end

    superFunc(hud, moneyType, text)

    hud.addSideNotification = old
end

---Add non-deduplication parameter
function SeasonsUI.inj_HUD_addSideNotification(hud, superFunc, color, text, duration, doNotDeduplicate)
    -- Override and add no-dedup
    local old = hud.sideNotifications.addNotification
    hud.sideNotifications.addNotification = function(notification, text, color, duration)
        return old(notification, text, color, duration, doNotDeduplicate)
    end

    superFunc(hud, color, text, duration)

    hud.sideNotifications.addNotification = old
end

---Fix an issue with the inputAction of opening the menu causing a tabbing event in the settings frame with controllers
-- Bit of a hack...
function SeasonsUI.inj_multiTextOptionElement_inputEvent(element, superFunc, action, value, eventUsed)
    if (element.id == "temperatureUnitElement" or element.id == "rotationOne[1]") and action == InputAction.MENU_PAGE_PREV then
        return true
    end

    return superFunc(element, action, value, eventUsed)
end

---Add the year as a statistic
function SeasonsUI.inj_inGameMenuStatisticsFrame_updateStatistics(frame)
    local table = frame.statisticsTable[2]

    local title = g_i18n:getText("seasons_statistic_year")

    local dataRow = TableElement.DataRow:new(title, frame.dataBindings)
    local nameCell = dataRow.columnCells[frame.dataBindings[InGameMenuStatisticsFrame.DATA_BINDING.STAT_TYPE]]
    local sessionValueCell = dataRow.columnCells[frame.dataBindings[InGameMenuStatisticsFrame.DATA_BINDING.SESSION_VALUE]]

    nameCell.text = title
    sessionValueCell.text = g_seasons.environment.year

    table:addRow(dataRow)

    table:updateView(false)
end
