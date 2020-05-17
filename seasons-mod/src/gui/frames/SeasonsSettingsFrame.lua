----------------------------------------------------------------------------------------------------
-- SeasonsSettingsFrame
----------------------------------------------------------------------------------------------------
-- Purpose:  The frame for the calendar page in the Seasons menu
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsSettingsFrame = {}
local SeasonsSettingsFrame_mt = Class(SeasonsSettingsFrame, TabbedMenuFrameElement)

SeasonsSettingsFrame.CONTROLS = {
    SETTINGS_CONTAINER = "settingsContainer",

    TEMPERATURE_UNIT_ELEMENT = "temperatureUnitElement",
    SEASON_INTRODUCTIONS_ELEMENT = "seasonIntroductionsElement",
    SEASON_LENGTH_ELEMENT = "seasonLengthElement",
    CROP_MOISTURE_ELEMENT = "cropMoistureElement",
    SNOW_MODE_ELEMENT = "snowModeElement",
    SNOW_TRACKS_ELEMENT = "snowTracksElement",

    HELP_BOX = "settingsHelpBox",
}

function SeasonsSettingsFrame:new(i18n, settingsModel, environment, localStorage)
    local self = TabbedMenuFrameElement:new(nil, SeasonsSettingsFrame_mt)

    self.i18n = i18n
    self.settingsModel = settingsModel
    self.environment = environment
    self.messageCenter = g_messageCenter
    self.localStorage = localStorage

    self:registerControls(SeasonsSettingsFrame.CONTROLS)

    self.isServer = g_currentMission:getIsServer()
    self.isMasterUser = false
    self.hasMasterRights = self.isServer or self.isMasterUser

    return self
end

function SeasonsSettingsFrame:copyAttributes(src)
    SeasonsSettingsFrame:superClass().copyAttributes(self, src)

    self.i18n = src.i18n
    self.settingsModel = src.settingsModel
    self.environment = src.environment
    self.localStorage = src.localStorage
end

function SeasonsSettingsFrame:delete()
    self.messageCenter:unsubscribe(MessageType.MASTERUSER_ADDED, self)

    SeasonsSettingsFrame:superClass().delete(self)
end

function SeasonsSettingsFrame:initialize()
    local texts = {}
    for i = 1, SeasonsEnvironment.MAX_DAYS_IN_SEASON / 3 do
        table.insert(texts, string.format(self.i18n:getText("seasons_ui_days"), i * 3))
    end
    self.seasonLengthElement:setTexts(texts)

    self.temperatureUnitElement:setTexts({self.i18n:getText("unit_celsius"), self.i18n:getText("unit_fahrenheit")})
    self.snowModeElement:setTexts({self.i18n:getText("ui_off"), self.i18n:getText("seasons_ui_snowOneLayer"), self.i18n:getText("ui_on")})

    self.messageCenter:subscribe(MessageType.MASTERUSER_ADDED, self.onMasterUserAdded, self)
end

function SeasonsSettingsFrame:onFrameOpen()
    self.messageCenter:subscribe(SeasonsSettingsEvent, self.onSettingsChanged, self)

    self:updateContent()
end

function SeasonsSettingsFrame:onFrameClose()
    SeasonsSettingsFrame:superClass().onFrameClose(self)

    self.messageCenter:unsubscribe(SeasonsSettingsEvent, self)

    -- Local
    self.settingsModel:setValue(SettingsModel.SETTING.USE_FAHRENHEIT, self.temperatureUnitElement:getIsChecked())
    self.settingsModel:applyChanges(SettingsModel.SETTING_CLASS.SAVE_NONE)

    self.localStorage:setShowTutorialMessages(self.seasonIntroductionsElement:getIsChecked())
    self.localStorage:saveIfDirty()

    local daysPerSeason = self.seasonLengthElement:getState() * 3
    local snowMode = self.snowModeElement:getState()
    local snowTracksEnabled = self.snowTracksElement:getIsChecked()
    local cropMoistureEnabled = self.cropMoistureElement:getIsChecked()

    if self.hasMasterRights then
        local event = SeasonsSettingsEvent:new(daysPerSeason, snowMode, snowTracksEnabled, cropMoistureEnabled)
        g_client:getServerConnection():sendEvent(event)
    end
end

---Set master rights status of the current game instance / player.
function SeasonsSettingsFrame:updateHasMasterRights()
    self.hasMasterRights = self.isMasterUser or self.isServer

    if g_currentMission ~= nil then
        self:updateContent()
    end
end

function SeasonsSettingsFrame:updateContent()
    -- Update states
    self.temperatureUnitElement:setIsChecked(self.settingsModel:getValue(SettingsModel.SETTING.USE_FAHRENHEIT))

    self.seasonIntroductionsElement:setIsChecked(self.localStorage:getShowTutorialMessages())

    self.seasonLengthElement:setState(self.environment.daysPerSeason / 3)
    self.snowModeElement:setState(g_seasons.snowHandler:getMode())
    self.snowTracksElement:setIsChecked(g_seasons.vehicle:getSnowTracksEnabled())
    self.cropMoistureElement:setIsChecked(g_seasons.weather:getCropMoistureEnabled())

    -- Disable items with no permission to change
    self.seasonLengthElement:setDisabled(not self.hasMasterRights)
    self.snowModeElement:setDisabled(not self.hasMasterRights)
    self.snowTracksElement:setDisabled(not self.hasMasterRights)
    self.cropMoistureElement:setDisabled(not self.hasMasterRights)
end

---Get the frame's main content element's screen size.
function SeasonsSettingsFrame:getMainElementSize()
    return self.settingsContainer.size
end

---Get the frame's main content element's screen position.
function SeasonsSettingsFrame:getMainElementPosition()
    return self.settingsContainer.absPosition
end

---Update visibility of tool tip box, only show when there is text to display.
function SeasonsSettingsFrame:updateToolTipBoxVisibility(box)
    local hasText = box.text ~= nil and box.text ~= ""
    self.settingsHelpBox:setVisible(hasText)
end

----------------------
-- Events
----------------------

function SeasonsSettingsFrame:onToolTipBoxTextChanged(element, text)
    self:updateToolTipBoxVisibility(element)
end

---Master user was added. If it is the current player, update content
function SeasonsSettingsFrame:onMasterUserAdded(user)
    if user:getId() == g_currentMission.playerUserId then
        self.isMasterUser = true
        self:updateHasMasterRights()
    end
end

---Settings changed, update visible content
function SeasonsSettingsFrame:onSettingsChanged()
    self:updateContent()
end

SeasonsSettingsFrame.L10N_SYMBOL = {
}
