----------------------------------------------------------------------------------------------------
-- SeasonsHUD
----------------------------------------------------------------------------------------------------
-- Purpose:  HUD for Seasons
--           - Current seasona and period
--           - Temperatures
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsHUD = {}

local SeasonsHUD_mt = Class(SeasonsHUD)

SeasonsHUD.INFO_STATE = {
    NONE = 0,
    FROZEN_SOIL = 1,
    MOIST_CROPS = 2,
}

function SeasonsHUD:new(mission, gameInfoDisplay, i18n, messageCenter, seasonsAtlasPath)
    self = setmetatable({}, SeasonsHUD_mt)

    self.messageCenter = messageCenter
    self.gameInfoDisplay = gameInfoDisplay
    self.hudAtlasPath = g_baseHUDFilename
    self.i18n = i18n
    self.seasonIcons = {}
    self.seasonsAtlasPath = seasonsAtlasPath

    self.airTemperature = ""
    self.soilTemperature = ""
    self.dateText = ""

    SeasonsModUtil.appendedFunction(GameInfoDisplay, "draw", SeasonsHUD.gameInfoDisplay_draw)
    SeasonsModUtil.appendedFunction(GameInfoDisplay, "storeScaledValues", SeasonsHUD.gameInfoDisplay_storeScaledValues)
    SeasonsModUtil.prependedFunction(GameInfoDisplay, "setWeatherVisible", SeasonsHUD.gameInfoDisplay_setWeatherVisible)

    self.messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_FAHRENHEIT], self.onTemperatureUnitChanged, self)

    return self
end

function SeasonsHUD:delete()
    if self.seasonsBox ~= nil then
        self.seasonsBox:delete()
    end

    if self.temperatureBox ~= nil then
        self.temperatureBox:delete()
    end

    if self.stateBox ~= nil then
        self.stateBox:delete()
    end

    self.messageCenter:unsubscribeAll(self)
end

function SeasonsHUD:load()
    self:createElements()
end

--------------------------------
-- Creating
--------------------------------

function SeasonsHUD:createElements()
    local topRightX, topRightY = GameInfoDisplay.getBackgroundPosition(1)
    local bottomY = topRightY - self.gameInfoDisplay:getHeight()
    local centerY = bottomY + self.gameInfoDisplay:getHeight() * 0.5
    local marginWidth, marginHeight = self.gameInfoDisplay:scalePixelToScreenVector(GameInfoDisplay.SIZE.BOX_MARGIN)

    local sepX = self.gameInfoDisplay.timeBox.overlay.x
    local rightX = self:createSeasonBox(self.hudAtlasPath, self.gameInfoDisplay.timeBox.overlay.x - marginWidth, bottomY) - marginWidth

    local separator = self.gameInfoDisplay:createVerticalSeparator(self.hudAtlasPath, sepX, centerY)
    self.seasonBox:addChild(separator)
    self.seasonBox.separator = separator

    sepX = rightX
    rightX = self:createTemperatureBox(self.seasonsAtlasPath, rightX - marginWidth, bottomY) - marginWidth

    separator = self.gameInfoDisplay:createVerticalSeparator(self.hudAtlasPath, sepX, centerY)
    self.temperatureBox:addChild(separator)
    self.temperatureBox.separator = separator

    sepX = rightX
    rightX = self:createStateBox(self.seasonsAtlasPath, rightX - marginWidth, bottomY) - marginWidth

    separator = self.gameInfoDisplay:createVerticalSeparator(self.hudAtlasPath, sepX, centerY)
    self.stateBox:addChild(separator)
    self.stateBox.separator = separator

    self.gameInfoDisplay:updateSizeAndPositions()
end

---Create the box with the season icon and info
function SeasonsHUD:createSeasonBox(hudAtlasPath, rightX, bottomY)
    local boxWidth, boxHeight = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.SIZE.SEASONS_BOX)
    local posX = rightX - boxWidth

    local boxOverlay = Overlay:new(nil, posX, bottomY, boxWidth, boxHeight)
    local boxElement = HUDElement:new(boxOverlay)
    self.seasonBox = boxElement
    self.gameInfoDisplay:addChild(boxElement)
    self:addBoxBeforeWeather(boxElement)

    -- Use function so new weather types can be added
    local seasonUVs = {
        [SeasonsEnvironment.SPRING] = SeasonsHUD.UV.SPRING,
        [SeasonsEnvironment.SUMMER] = SeasonsHUD.UV.SUMMER,
        [SeasonsEnvironment.AUTUMN] = SeasonsHUD.UV.AUTUMN,
        [SeasonsEnvironment.WINTER] = SeasonsHUD.UV.WINTER,
    }

    for season, uvs in pairs(seasonUVs) do
        local icon = self:createSeasonIcon(hudAtlasPath, posX, bottomY, boxHeight, uvs, GameInfoDisplay.COLOR.ICON)
        boxElement:addChild(icon)
        self.seasonIcons[season] = icon
    end

    return rightX - boxWidth
end

---Create icon for a season
function SeasonsHUD:createSeasonIcon(hudAtlasPath, leftX, bottomY, boxHeight, uvs, color)
    local width, height = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.SIZE.SEASON_ICON)
    local posY = bottomY + (boxHeight - height) * 0.5

    local overlay = Overlay:new(hudAtlasPath, leftX, posY, width, height) -- position is set on update
    overlay:setUVs(getNormalizedUVs(uvs))

    local element = HUDElement:new(overlay)
    element:setVisible(false)

    return element
end

---Create the temperature display box.
function SeasonsHUD:createTemperatureBox(hudAtlasPath, rightX, bottomY)
    local boxWidth, boxHeight = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.SIZE.TEMPERATURE_BOX)
    local posX = rightX - boxWidth

    local boxOverlay = Overlay:new(nil, posX, bottomY, boxWidth, boxHeight)
    local boxElement = HUDElement:new(boxOverlay)
    self.temperatureBox = boxElement
    self.gameInfoDisplay:addChild(boxElement)
    self:addBoxBeforeWeather(boxElement)

    local _, offsetAir = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.POSITION.TEMPERATURE_AIR_ICON)
    local _, offsetSoil = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.POSITION.TEMPERATURE_SOIL_ICON)

    local icon = self:createTemperatureIcon(hudAtlasPath, posX, bottomY + offsetAir, boxHeight, SeasonsHUD.UV.AIR_TEMPERATURE, GameInfoDisplay.COLOR.ICON)
    boxElement:addChild(icon)
    icon:setVisible(true)

    icon = self:createTemperatureIcon(hudAtlasPath, posX, bottomY + offsetSoil, boxHeight, SeasonsHUD.UV.SOIL_TEMPERATURE, GameInfoDisplay.COLOR.ICON)
    boxElement:addChild(icon)
    icon:setVisible(true)

    return rightX - boxWidth
end

function SeasonsHUD:createTemperatureIcon(hudAtlasPath, leftX, bottomY, boxHeight, uvs, color)
    local width, height = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.SIZE.TEMPERATURE_ICON)
    local posY = bottomY

    local overlay = Overlay:new(hudAtlasPath, leftX, posY, width, height) -- position is set on update
    overlay:setUVs(getNormalizedUVs(uvs))

    local element = HUDElement:new(overlay)
    element:setVisible(false)

    return element
end

function SeasonsHUD:createStateBox(hudAtlasPath, rightX, bottomY)
    local boxWidth, boxHeight = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.SIZE.STATE_BOX)
    local posX = rightX - boxWidth

    local boxOverlay = Overlay:new(nil, posX, bottomY, boxWidth, boxHeight)
    local boxElement = HUDElement:new(boxOverlay)
    self.stateBox = boxElement
    self.gameInfoDisplay:addChild(boxElement)
    self:addBoxBeforeWeather(boxElement)

    self.moistStateIcon = self:createStateIcon(hudAtlasPath, posX, bottomY, boxHeight, SeasonsHUD.UV.STATE_MOIST, GameInfoDisplay.COLOR.ICON)
    boxElement:addChild(self.moistStateIcon)
    self.moistStateIcon:setVisible(false)

    self.frozenStateIcon = self:createStateIcon(hudAtlasPath, posX, bottomY, boxHeight, SeasonsHUD.UV.STATE_FROZEN, GameInfoDisplay.COLOR.ICON)
    boxElement:addChild(self.frozenStateIcon)
    self.frozenStateIcon:setVisible(false)

    return rightX - boxWidth
end

function SeasonsHUD:createStateIcon(hudAtlasPath, leftX, bottomY, boxHeight, uvs, color)
    local width, height = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.SIZE.SEASON_ICON)
    local posY = bottomY + (boxHeight - height) * 0.5

    local overlay = Overlay:new(hudAtlasPath, leftX, posY, width, height) -- position is set on update
    overlay:setUVs(getNormalizedUVs(uvs))

    local element = HUDElement:new(overlay)
    element:setVisible(false)

    return element
end

function SeasonsHUD:addBoxBeforeWeather(box)
    local pos = 1
    for i, box in ipairs(self.gameInfoDisplay.infoBoxes) do
        if box == self.gameInfoDisplay.weatherBox then
            pos = i
            break
        end
    end
    table.insert(self.gameInfoDisplay.infoBoxes, pos, box)
end

--------------------------------
-- Updating
--------------------------------

function SeasonsHUD:storeScaledValues()
    -- This function is called once before our :load
    if self.seasonBox == nil then
        return
    end

    local seasonBoxPosX, seasonBoxPosY = self.seasonBox:getPosition()
    local seasonBoxWidth, seasonBoxHeight = self.seasonBox:getWidth(), self.seasonBox:getHeight()
    local textOffX, textOffY = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.POSITION.SEASON_TEXT)
    local iconWidth, _ = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.SIZE.SEASON_ICON)
    self.dateTextWrapWidth = seasonBoxWidth - textOffX - iconWidth
    self.dateTextPositionX = seasonBoxPosX + seasonBoxWidth + textOffX - self.dateTextWrapWidth / 2
    self.dateTextPositionY = seasonBoxPosY + textOffY
    self.dateTextSize = self.gameInfoDisplay:scalePixelToScreenHeight(SeasonsHUD.TEXT_SIZE.DATE)

    self.temperatureTextSize = self.gameInfoDisplay:scalePixelToScreenHeight(SeasonsHUD.TEXT_SIZE.TEMPERATURE)

    local tempBoxPosX, tempBoxPosY = self.temperatureBox:getPosition()
    local tempBoxWidth, tempBoxHeight = self.temperatureBox:getWidth(), self.temperatureBox:getHeight()
    textOffX, textOffY = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.POSITION.TEMPERATURE_AIR_TEXT)
    self.temperatureAirTextPositionX = tempBoxPosX + tempBoxWidth + textOffX
    self.temperatureAirTextPositionY = tempBoxPosY + tempBoxHeight * 0.5 + textOffY

    textOffX, textOffY = self.gameInfoDisplay:scalePixelToScreenVector(SeasonsHUD.POSITION.TEMPERATURE_SOIL_TEXT)
    self.temperatureSoilTextPositionX = tempBoxPosX + tempBoxWidth + textOffX
    self.temperatureSoilTextPositionY = tempBoxPosY + tempBoxHeight * 0.5 + textOffY
end

---Update the contents of the season box
function SeasonsHUD:setSeason(season)
    for s, icon in pairs(self.seasonIcons) do
        icon:setVisible(s == season)
    end
end

function SeasonsHUD:setDate(day, period)
    self.dateText = string.format("%02d/%s", day, self.i18n:getText("seasons_periodNameFull_" .. period))

    setTextWrapWidth(self.dateTextWrapWidth)
    setTextLineHeightScale(RenderText.DEFAULT_LINE_HEIGHT_SCALE)

    local height, numLines = getTextHeight(self.dateTextSize, self.dateText)
    self.dateTextHeight = height

    setTextLineHeightScale(RenderText.DEFAULT_LINE_HEIGHT_SCALE)
    setTextWrapWidth(0)
end

function SeasonsHUD:setTemperature(air, soil)
    self.tempAir, self.tempSoil = air, math.floor(soil)
    self.airTemperature = self.i18n:formatTemperature(self.tempAir, 0)
    self.soilTemperature = self.i18n:formatTemperature(self.tempSoil, 0)
end

function SeasonsHUD:setVisible(visible)
    if self.seasonBox ~= nil then
        self.seasonBox:setVisible(visible)
        self.temperatureBox:setVisible(visible)
    end
end

---Set state: visible
function SeasonsHUD:setInfoState(state)
    self.stateBox:setVisible(state ~= SeasonsHUD.INFO_STATE.NONE)

    self.moistStateIcon:setVisible(state == SeasonsHUD.INFO_STATE.MOIST_CROPS)
    self.frozenStateIcon:setVisible(state == SeasonsHUD.INFO_STATE.FROZEN_SOIL)

    self.gameInfoDisplay:updateSizeAndPositions()
end

---Update temperature strings when unit changed
function SeasonsHUD:onTemperatureUnitChanged()
    self:setTemperature(self.tempAir, self.tempSoil)
end

--------------------------------
-- Drawing
--------------------------------

-- Only draw the text. Everything else are sub-elements of the hud already
function SeasonsHUD:drawText()
    setTextBold(false)
    setTextColor(unpack(GameInfoDisplay.COLOR.TEXT))

    self:drawDateText()
    self:drawTemperatures()

    setTextAlignment(RenderText.ALIGN_LEFT)
end

function SeasonsHUD:drawDateText()
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextWrapWidth(self.dateTextWrapWidth)
    renderText(self.dateTextPositionX, self.dateTextPositionY + self.dateTextHeight / 2, self.dateTextSize, self.dateText)
    setTextWrapWidth(0)
end

function SeasonsHUD:drawTemperatures()
    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(self.temperatureAirTextPositionX, self.temperatureAirTextPositionY, self.temperatureTextSize, self.airTemperature)
    renderText(self.temperatureSoilTextPositionX, self.temperatureSoilTextPositionY, self.temperatureTextSize, self.soilTemperature)
end

--------------------------------
-- Injections
--------------------------------

function SeasonsHUD.gameInfoDisplay_storeScaledValues(gameInfoDisplay)
    g_seasons.ui.hud:storeScaledValues()
end

function SeasonsHUD.gameInfoDisplay_draw(gameInfoDisplay)
    g_seasons.ui.hud:drawText()
end

function SeasonsHUD.gameInfoDisplay_setWeatherVisible(gameInfoDisplay, visible)
    g_seasons.ui.hud:setVisible(visible)
end

SeasonsHUD.SIZE = {
    SEASONS_BOX = {220, GameInfoDisplay.BOX_HEIGHT},
    TEMPERATURE_BOX = {70, GameInfoDisplay.BOX_HEIGHT},
    STATE_BOX = {54, 54},

    SEASON_ICON = {54, 54},
    TEMPERATURE_ICON = {24, 24},
}

SeasonsHUD.UV = {
    SPRING = {384, 240, 48, 48},
    SUMMER = {432, 240, 48, 48},
    AUTUMN = {480, 240, 48, 48},
    WINTER = {336, 240, 48, 48},

    AIR_TEMPERATURE = {0, 192, 48, 48},
    SOIL_TEMPERATURE = {48, 192, 48, 48},

    STATE_FROZEN = {0, 65, 65, 65},
    STATE_MOIST = {65, 65, 65, 65},
}

SeasonsHUD.POSITION = {
    TEMPERATURE_AIR_TEXT = {0, 8},
    TEMPERATURE_SOIL_TEXT = {0, -20},

    TEMPERATURE_SOIL_ICON = {0, 2},
    TEMPERATURE_AIR_ICON = {0, 30},

    SEASON_TEXT = {0, 10},
}

SeasonsHUD.TEXT_SIZE = {
    DATE = 19,
    TEMPERATURE = 18,
}
