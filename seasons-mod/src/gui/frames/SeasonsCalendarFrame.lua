----------------------------------------------------------------------------------------------------
-- SeasonsCalendarFrame
----------------------------------------------------------------------------------------------------
-- Purpose:  The frame for the calendar page in the Seasons menu
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsCalendarFrame = {}
local SeasonsCalendarFrame_mt = Class(SeasonsCalendarFrame, TabbedMenuFrameElement)

SeasonsCalendarFrame.CONTROLS = {
    CONTAINER = "container",
    CALENDAR = "calendar",
    TEMPLATE = "fruitRowTemplate",
    TODAY_BAR = "todayBar",
    SLIDER = "calendarSlider",
    HEADER = "calendarHeader",
    LEGEND_PLANTING_SEASON = "legendPlantingSeason",
    LEGEND_HARVEST_SEASON = "legendHarvestSeason",
}

SeasonsCalendarFrame.BLOCK_TYPE_PLANTABLE = 1
SeasonsCalendarFrame.BLOCK_TYPE_HARVESTABLE = 2

SeasonsCalendarFrame.BLOCK_COLORS = {
    [false] = {
        [SeasonsCalendarFrame.BLOCK_TYPE_PLANTABLE] = {0.0143, 0.2582, 0.0126, 1},
        [SeasonsCalendarFrame.BLOCK_TYPE_HARVESTABLE] = {0.8308, 0.5841, 0.0529, 1},
    },
    [true] = {
        [SeasonsCalendarFrame.BLOCK_TYPE_PLANTABLE] = {0.2122, 0.1779, 0.0027, 1},
        [SeasonsCalendarFrame.BLOCK_TYPE_HARVESTABLE] = {0.3372, 0.4397, 0.9911, 1},
    }
}


function SeasonsCalendarFrame:new(i18n)
    local self = TabbedMenuFrameElement:new(nil, SeasonsCalendarFrame_mt)

    self.i18n = i18n
    self.fruitTypeManager = g_fruitTypeManager
    self.growthData = g_seasons.growth.data
    self.messageCenter = g_messageCenter
    self.environment = g_seasons.environment
    self.gameSettings = g_gameSettings

    self:registerControls(SeasonsCalendarFrame.CONTROLS)

    self.isColorBlindMode = false

    self.scrollInputDelay = 0
    self.scrollInputDelayDir = 0

    return self
end

function SeasonsCalendarFrame:delete()
    self.fruitRowTemplate:delete()

    SeasonsCalendarFrame:superClass().delete(self)
end

function SeasonsCalendarFrame:copyAttributes(src)
    SeasonsCalendarFrame:superClass().copyAttributes(self, src)

    self.i18n = src.i18n
end

function SeasonsCalendarFrame:initialize()
end

function SeasonsCalendarFrame:onFrameOpen()
    SeasonsCalendarFrame:superClass().onFrameOpen(self)

    self.isColorBlindMode = self.gameSettings:getValue(GameSettings.SETTING.USE_COLORBLIND_MODE) or false

    self:rebuildTable()
    self:updateTodayBar()
    self:setPeriodTitles()
    self:updateLegend()

    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)
    self.messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_COLORBLIND_MODE], self.setColorBlindMode, self)
end

function SeasonsCalendarFrame:onFrameClose()
    self.messageCenter:unsubscribe(MessageType.DAY_CHANGED, self)
    self.messageCenter:unsubscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self)
    self.messageCenter:unsubscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_COLORBLIND_MODE], self)

    SeasonsCalendarFrame:superClass().onFrameClose(self)
end

---Get the frame's main content element's screen size.
function SeasonsCalendarFrame:getMainElementSize()
    return self.container.size
end

---Get the frame's main content element's screen position.
function SeasonsCalendarFrame:getMainElementPosition()
    return self.container.absPosition
end

---Update the position of the 'today' indicator
function SeasonsCalendarFrame:updateTodayBar()
    local season = self.environment.season
    local intoSeason = (self.environment.dayInSeason - 1) / self.environment.daysPerSeason

    local percentage = season * 0.25 + intoSeason * 0.25
    local parentSize = self.todayBar.parent.size[1]

    self.todayBar:setPosition(parentSize * percentage + parentSize / (self.environment.daysPerSeason * 4) * 0.5, nil)
end

---Set the period days in their titles
function SeasonsCalendarFrame:setPeriodTitles()
    local daysPerPeriod = self.environment.daysPerSeason / 3

    for i = 1, 12 do
        local element = self.calendarHeader[i]
        local j = (i - 1) % 3 + 1 -- within season

        if daysPerPeriod == 1 then
            element:setText(tostring(j))
        else
            element:setText(string.format("%d - %d", (j - 1) * daysPerPeriod + 1, j * daysPerPeriod))
        end
    end
end

function SeasonsCalendarFrame:updateLegend()
    self.legendPlantingSeason:setImageColor(nil, unpack(SeasonsCalendarFrame.BLOCK_COLORS[self.isColorBlindMode][SeasonsCalendarFrame.BLOCK_TYPE_PLANTABLE]))
    self.legendHarvestSeason:setImageColor(nil, unpack(SeasonsCalendarFrame.BLOCK_COLORS[self.isColorBlindMode][SeasonsCalendarFrame.BLOCK_TYPE_HARVESTABLE]))
end

----------------------
-- Table building
----------------------

---Rebuild the fruits table
function SeasonsCalendarFrame:rebuildTable()
    self.calendar:deleteListItems()

    for index, _ in pairs(g_currentMission.fruits) do
        local fruitDesc = self.fruitTypeManager:getFruitTypeByIndex(index)
        if fruitDesc.allowsSeeding then
            self:buildFruitRow(fruitDesc)
        end
    end
end

---Build a single row for a fruit
function SeasonsCalendarFrame:buildFruitRow(fruitDesc)
    local row = self.fruitRowTemplate:clone(self.calendar)
    local fillType = self.fruitTypeManager:getFillTypeByFruitTypeIndex(fruitDesc.index)

    row:getDescendantByName("fruitIcon"):setImageFilename(fillType.hudOverlayFilename)
    row:getDescendantByName("fruitName"):setText(fillType.title)

    local germTemp = fruitDesc.germinateTemp
    local cell = row:getDescendantByName("germination")
    cell:setTemperature(germTemp)

    if g_seasons.weather:getCurrentSoilTemperature() < germTemp then
        cell:applyProfile("seasonsCalendarGerminationCellTooCold")
    else
        cell:applyProfile("seasonsCalendarGerminationCell")
    end

    local plantColor = SeasonsCalendarFrame.BLOCK_COLORS[self.isColorBlindMode][SeasonsCalendarFrame.BLOCK_TYPE_PLANTABLE]
    local harvestColor = SeasonsCalendarFrame.BLOCK_COLORS[self.isColorBlindMode][SeasonsCalendarFrame.BLOCK_TYPE_HARVESTABLE]

    -- Set data for the periods
    for i = 1, 12 do
        local cell = row.elements[1].elements[i + 3] -- hacky but fast

        local plantCell = cell.elements[1]
        if self.growthData:canFruitBePlanted(fruitDesc.name, i) then
            plantCell:setImageColor(nil, unpack(plantColor))
        end

        local harvestCell = cell.elements[2]
        if self.growthData:canFruitBeHarvested(fruitDesc.name, i) then
            harvestCell:setImageColor(nil, unpack(harvestColor))
        end
    end

    return row
end

----------------------
-- Events
----------------------

---Update the temperatures every day (soil temp updates daily)
function SeasonsCalendarFrame:onDayChanged()
    local i = 1
    for i, row in ipairs(self.calendar.elements) do
        local cell = row:getDescendantByName("germination")

        if g_seasons.weather:getCurrentSoilTemperature() < cell.temperature then
            cell:applyProfile("seasonsCalendarGerminationCellTooCold")
        else
            cell:applyProfile("seasonsCalendarGerminationCell")
        end
    end

    self:updateTodayBar()
end

---Season length changed: update the season dependend info
function SeasonsCalendarFrame:onSeasonLengthChanged()
    self:setPeriodTitles()
    self:updateTodayBar()
end

function SeasonsCalendarFrame:setColorBlindMode(isActive)
    if self.isColorBlindMode ~= isActive then
        self.isColorBlindMode = isActive

        self:rebuildTable()
        self:updateLegend()
    end
end

---Add scrolling with gamepad and mouse
function SeasonsCalendarFrame:inputEvent(action, value, eventUsed)
    local pressedUp = false
    local pressedDown = false

    pressedUp = action == InputAction.MENU_AXIS_UP_DOWN and value > g_analogStickVTolerance
    pressedDown = action == InputAction.MENU_AXIS_UP_DOWN and value < -g_analogStickVTolerance

    if pressedUp or pressedDown then
        local dir = pressedUp and -1 or 1

        if dir ~= self.scrollInputDelayDir or g_time - self.scrollInputDelay > 250 then
            self.scrollInputDelayDir = dir
            self.scrollInputDelay = g_time

            self.calendarSlider:setValue(self.calendarSlider:getValue() + dir)
        end
    end

    return true
end

SeasonsCalendarFrame.L10N_SYMBOL = {
}
