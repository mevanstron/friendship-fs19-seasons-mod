----------------------------------------------------------------------------------------------------
-- SeasonsCropsFrame
----------------------------------------------------------------------------------------------------
-- Purpose:  Frame that shows extra crop data
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsCropsFrame = {}
local SeasonsCropsFrame_mt = Class(SeasonsCropsFrame, TabbedMenuFrameElement)

SeasonsCropsFrame.CONTROLS = {
    CONTAINER = "container",
    TEMPLATE = "fruitRowTemplate",
    FRUIT_LIST = "fruitList",
    INFO_TEXT = "infoText",
    SLIDER = "cropsSlider",
}

SeasonsCropsFrame.BLOCK_TYPE_PLANTABLE = 1
SeasonsCropsFrame.BLOCK_TYPE_HARVESTABLE = 2

function SeasonsCropsFrame:new(i18n)
    local self = TabbedMenuFrameElement:new(nil, SeasonsCropsFrame_mt)

    self.i18n = i18n
    self.fruitTypeManager = g_fruitTypeManager
    self.growthData = g_seasons.growth.data
    self.messageCenter = g_messageCenter
    self.environment = g_seasons.environment
    self.gameSettings = g_gameSettings

    self:registerControls(SeasonsCropsFrame.CONTROLS)

    self.scrollInputDelay = 0
    self.scrollInputDelayDir = 0

    return self
end

function SeasonsCropsFrame:delete()
    self.fruitRowTemplate:delete()

    SeasonsCropsFrame:superClass().delete(self)
end

function SeasonsCropsFrame:copyAttributes(src)
    SeasonsCropsFrame:superClass().copyAttributes(self, src)

    self.i18n = src.i18n
end

function SeasonsCropsFrame:initialize()
end

function SeasonsCropsFrame:onFrameOpen()
    SeasonsCropsFrame:superClass().onFrameOpen(self)

    self:rebuildTable()
    self:setInfoText()

    self.messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_FAHRENHEIT], self.onTemperatureUnitChanged, self)
end

function SeasonsCropsFrame:onFrameClose()
    SeasonsCropsFrame:superClass().onFrameClose(self)

    self.messageCenter:unsubscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_FAHRENHEIT], self)
end

---Get the frame's main content element's screen size.
function SeasonsCropsFrame:getMainElementSize()
    return self.container.size
end

---Get the frame's main content element's screen position.
function SeasonsCropsFrame:getMainElementPosition()
    return self.container.absPosition
end

---Set the info text which requires localization
function SeasonsCropsFrame:setInfoText()
    local text = string.format(self.i18n:getText("seasons_ui_pcf_info"), self.i18n:formatTemperature(0, 0))
    self.infoText:setText(text)
end

----------------------
-- Table building
----------------------

---Rebuild the fruits table
function SeasonsCropsFrame:rebuildTable()
    self.fruitList:deleteListItems()

    for index, _ in pairs(g_currentMission.fruits) do
        local fruitDesc = self.fruitTypeManager:getFruitTypeByIndex(index)
        if fruitDesc.allowsSeeding then
            self:buildFruitRow(fruitDesc)
        end
    end
end

---Build a single row for a fruit
function SeasonsCropsFrame:buildFruitRow(fruitDesc)
    local row = self.fruitRowTemplate:clone(self.fruitList)
    local fillType = self.fruitTypeManager:getFillTypeByFruitTypeIndex(fruitDesc.index)

    row:getDescendantByName("fruitIcon"):setImageFilename(fillType.hudOverlayFilename)
    row:getDescendantByName("fruitName"):setText(fillType.title)

    local setValue = function(name, value)
        local element = row:getDescendantByName(name)

        local text, color
        if value >= 4 then
            text = "seasons_ui_crops_high"
        elseif value >= 3 then
            text = "seasons_ui_crops_medium"
        elseif value >= 2 then
            text = "seasons_ui_crops_low"
        else
            text = "seasons_ui_crops_high_none"
        end
        element:setText(self.i18n:getText(text))

        local color = SeasonsCropsFrame.COLORS[value]
        local colorElem = element.elements[1]
        colorElem:setImageColor(GuiOverlay.STATE_NORMAL, unpack(color))
        colorElem:setImageColor(GuiOverlay.STATE_SELECTED, unpack(color))
    end

    setValue("frostSeed", fruitDesc.seedFrostResistanceFactor)
    setValue("frostYoung", fruitDesc.youngPlantFrostResistanceFactor)
    setValue("frostMature", fruitDesc.maturePlantFrostResistanceFactor)
    setValue("droughtSeed", fruitDesc.seedDroughtResistanceFactor)
    setValue("droughtYoung", fruitDesc.youngPlantDroughtResistanceFactor)
    setValue("draightMature", fruitDesc.maturePlantDroughtResistanceFactor)

    return row
end

----------------------
-- Events
----------------------

---Add scrolling with gamepad and mouse
function SeasonsCropsFrame:inputEvent(action, value, eventUsed)
    local pressedUp = false
    local pressedDown = false

    pressedUp = action == InputAction.MENU_AXIS_UP_DOWN and value > g_analogStickVTolerance
    pressedDown = action == InputAction.MENU_AXIS_UP_DOWN and value < -g_analogStickVTolerance

    if pressedUp or pressedDown then
        local dir = pressedUp and -1 or 1

        if dir ~= self.scrollInputDelayDir or g_time - self.scrollInputDelay > 250 then
            self.scrollInputDelayDir = dir
            self.scrollInputDelay = g_time

            self.cropsSlider:setValue(self.cropsSlider:getValue() + dir)
        end
    end

    return true
end

function SeasonsCropsFrame:onTemperatureUnitChanged()
    self:setInfoText()
end

SeasonsCropsFrame.L10N_SYMBOL = {
}

SeasonsCropsFrame.COLORS = {
    {0.6444, 0.0160, 0.0262, 1},
    {0.8550, 0.2270, 0.0000, 1},
    {1.0000, 0.5210, 0.0000, 1},
    -- {1.0000, 0.5210, 0.0000, 1},
    -- {0.0168, 0.2462, 0.0168, 1},
    {0.0000, 0.1620, 0.0000, 1},
}
