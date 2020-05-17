----------------------------------------------------------------------------------------------------
-- SeasonsMenu
----------------------------------------------------------------------------------------------------
-- Purpose:  Menu for all things Seasons
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsMenu = {}
local SeasonsMenu_mt = Class(SeasonsMenu, TabbedMenu)

SeasonsMenu.CONTROLS = {
    PAGE_CALENDAR = "pageCalendar",
    PAGE_FORECAST = "pageForecast",
    PAGE_CROPS = "pageCrops",
    PAGE_ECONOMY = "pageEconomy",
    PAGE_SETTINGS = "pageSettings",
    PAGE_CROP_ROTATION = "pageCropRotation",
    PAGE_ANIMALS = "pageAnimals",
}

local NO_CALLBACK = function() end

function SeasonsMenu:new(messageCenter, i18n, inputManager)
    local self = TabbedMenu:new(nil, SeasonsMenu_mt, messageCenter, i18n, inputManager)

    self.i18n = i18n

    self.performBackgroundBlur = true

    self:registerControls(SeasonsMenu.CONTROLS)

    return self
end

function SeasonsMenu:onGuiSetupFinished()
    SeasonsMenu:superClass().onGuiSetupFinished(self)

    self.clickBackCallback = self:makeSelfCallback(self.onButtonBack) -- store to be able to apply it always when assigning menu button info

    self.pageCalendar:initialize()
    self.pageForecast:initialize()
    self.pageCrops:initialize()
    self.pageEconomy:initialize()
    self.pageSettings:initialize()
    self.pageCropRotation:initialize()
    self.pageAnimals:initialize()

    self:setupPages()
end

function SeasonsMenu:setupPages()
    local predicate = self:makeIsAlwaysVisiblePredicate()

    local orderedPages = { -- default pages, their enabling state predicate functions and tab icon UVs in order
        {self.pageCalendar, predicate, SeasonsMenu.TAB_UV.CALENDAR, g_seasons.ui.uiFilename},
        {self.pageForecast, predicate, SeasonsMenu.TAB_UV.FORECAST, g_baseUIFilename},
        {self.pageCrops, predicate, SeasonsMenu.TAB_UV.CROPS, g_seasons.ui.uiFilename},
        {self.pageAnimals, predicate, SeasonsMenu.TAB_UV.ANIMALS, g_baseUIFilename},
        {self.pageEconomy, predicate, SeasonsMenu.TAB_UV.ECONOMY, g_seasons.ui.uiFilename},
        {self.pageCropRotation, predicate, SeasonsMenu.TAB_UV.CROP_ROTATION, g_seasons.ui.uiFilename},
        {self.pageSettings, predicate, SeasonsMenu.TAB_UV.SETTINGS, g_baseUIFilename},
    }

    for i, pageDef in ipairs(orderedPages) do
        local page, predicate, iconUVs, filename = unpack(pageDef)
        self:registerPage(page, i, predicate)

        local normalizedUVs = getNormalizedUVs(iconUVs)
        self:addPageTab(page, filename, normalizedUVs) -- use the global here because the value changes with resolution settings
    end
end

function SeasonsMenu:onOpen()
    SeasonsMenu:superClass().onOpen(self)

    self.inputDisableTime = 200
end

function SeasonsMenu:inputEvent(action, value, eventUsed)
    local eventUsed = SeasonsMenu:superClass().inputEvent(self, action, value, eventUsed)

    if not eventUsed then
        if self.currentPage == self.pageCalendar then
            eventUsed = self.pageCalendar:inputEvent(action, value, eventUsed)
        elseif self.currentPage == self.pageCrops then
            eventUsed = self.pageCrops:inputEvent(action, value, eventUsed)
        end
    end

    return eventUsed
end

------------------------------------------------------------------------------------------------------------------------
-- Setting up
------------------------------------------------------------------------------------------------------------------------

---Define default properties and retrieval collections for menu buttons.
function SeasonsMenu:setupMenuButtonInfo()
    local onButtonBackFunction = self.clickBackCallback

    self.defaultMenuButtonInfo = {
        {inputAction = InputAction.MENU_BACK, text = self.l10n:getText(SeasonsMenu.L10N_SYMBOL.BUTTON_BACK), callback = onButtonBackFunction},
    }

    self.defaultMenuButtonInfoByActions[InputAction.MENU_BACK] = self.defaultMenuButtonInfo[1]

    self.defaultButtonActionCallbacks = {
        [InputAction.MENU_BACK] = onButtonBackFunction,
    }
end

------------------------------------------------------------------------------------------------------------------------
-- Predicates for showing pages
------------------------------------------------------------------------------------------------------------------------

function SeasonsMenu:makeIsAlwaysVisiblePredicate()
    return function()
        return true
    end
end


---Page tab UV coordinates for display elements.
SeasonsMenu.TAB_UV = {
    CALENDAR = {0, 0, 65, 65},
    FORECAST = {65, 144, 65, 65},
    CROPS = {260, 0, 65, 65},
    ECONOMY = {65, 0, 65, 65},
    SETTINGS = {390, 144, 65, 65},
    CROP_ROTATION = {130, 0, 65, 65},
    ANIMALS = {195, 144, 65, 65},
}

SeasonsMenu.L10N_SYMBOL = {
    BUTTON_BACK = "button_back",
}
