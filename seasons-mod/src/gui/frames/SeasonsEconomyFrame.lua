----------------------------------------------------------------------------------------------------
-- SeasonsEconomyFrame
----------------------------------------------------------------------------------------------------
-- Purpose:  The frame for the calendar page in the Seasons menu
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsEconomyFrame = {}
local SeasonsEconomyFrame_mt = Class(SeasonsEconomyFrame, TabbedMenuFrameElement)

SeasonsEconomyFrame.CONTROLS = {
    CONTAINER = "container",
    LIST = "list",
    TEMPLATE = "listItemTemplate",
    CATEGORY_TEMPLATE = "listCategoryTemplate",
    CHART = "chart",
    HEADER = "graphHeader",
}

function SeasonsEconomyFrame:new(i18n)
    local self = TabbedMenuFrameElement:new(nil, SeasonsEconomyFrame_mt)

    self.i18n = i18n
    self.fillTypeManager = g_fillTypeManager
    self.messageCenter = g_messageCenter
    self.animalManager = g_animalManager
    self.environment = g_seasons.environment
    self.economy = g_seasons.economy

    self:registerControls(SeasonsEconomyFrame.CONTROLS)

    self.rowToFillType = {}

    return self
end

function SeasonsEconomyFrame:copyAttributes(src)
    SeasonsEconomyFrame:superClass().copyAttributes(self, src)

    self.i18n = src.i18n
end

function SeasonsEconomyFrame:initialize()
end

function SeasonsEconomyFrame:onFrameOpen()
    SeasonsEconomyFrame:superClass().onFrameOpen(self)

    self:buildList()
    self:setPeriodTitles()

    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)
end

function SeasonsEconomyFrame:onFrameClose()
    self.messageCenter:unsubscribeAll(self)

    SeasonsEconomyFrame:superClass().onFrameClose(self)
end

---Get the frame's main content element's screen size.
function SeasonsEconomyFrame:getMainElementSize()
    return self.container.size
end

---Get the frame's main content element's screen position.
function SeasonsEconomyFrame:getMainElementPosition()
    return self.container.absPosition
end

----------------------
-- Table building
----------------------

function SeasonsEconomyFrame:buildList()
    local selectedElement = self.list:getSelectedElement()
    local selectedFillType, selectedIndex = nil, 2
    if selectedElement ~= nil then
        selectedFillType = self.rowToFillType[selectedElement]
    end

    self.list:deleteListItems()
    self.rowToFillType = {}

    local item

    -- Fills
    item = self:createHeader(self.i18n:getText("seasons_ui_products"))
    for _, fillDesc in ipairs(self.fillTypeManager:getFillTypes()) do
        if fillDesc.seasons_economyType == SeasonsEconomyHistory.TYPE.FILL then
            local row = self:createItem(fillDesc.title)
            self.rowToFillType[row] = fillDesc.index

            if fillDesc.index == selectedFillType then
                selectedIndex = #self.list.elements
            end
        end
    end

    -- Bales
    item = self:createHeader(self.i18n:getText("category_bales"))
    for _, fillDesc in ipairs(self.fillTypeManager:getFillTypes()) do
        if fillDesc.seasons_economyType == SeasonsEconomyHistory.TYPE.BALE then
            local row = self:createItem(fillDesc.title)
            self.rowToFillType[row] = fillDesc.index

            if fillDesc.index == selectedFillType then
                selectedIndex = #self.list.elements
            end
        end
    end

    -- Animals
    item = self:createHeader(self.i18n:getText("category_animals"))
    for _, fillDesc in ipairs(self.fillTypeManager:getFillTypes()) do
        if fillDesc.seasons_economyType == SeasonsEconomyHistory.TYPE.ANIMAL then
            local animal = self.animalManager:getAnimalByFillType(fillDesc.index)

            local row = self:createItem(animal.storeInfo.shopItemName)
            self.rowToFillType[row] = fillDesc.index

            if fillDesc.index == selectedFillType then
                selectedIndex = #self.list.elements
            end
        end
    end

    self.list:updateAbsolutePosition()

    -- Go to cell 2 and cell 1 is a category
    self.list:setSelectedIndex(selectedIndex)
    self:onListSelectionChanged(selectedIndex)
end

---Create a list header
function SeasonsEconomyFrame:createHeader(title)
    local item = self.listCategoryTemplate:clone(self.list)
    item:applyProfile("seasonsEconomyListCategory")
    item:getDescendantByName("title"):setText(title)
    item.doNotAlternate = true

    return item
end

---Create a list item
function SeasonsEconomyFrame:createItem(title)
    local item = self.listItemTemplate:clone(self.list)
    item:getDescendantByName("title"):setText(title)

    return item
end

---Set the period days in their titles
function SeasonsEconomyFrame:setPeriodTitles()
    local daysPerPeriod = self.environment.daysPerSeason / 3

    for i = 1, 12 do
        local element = self.graphHeader[i]
        local j = (i - 1) % 3 + 1 -- within season

        if daysPerPeriod == 1 then
            element:setText(tostring(j))
        else
            element:setText(string.format("%d - %d", (j - 1) * daysPerPeriod + 1, j * daysPerPeriod))
        end
    end
end

----------------------
-- Graph config
----------------------

---Update graph content based on list selection
function SeasonsEconomyFrame:updateGraph()
    local fillType = self.rowToFillType[self.list:getSelectedElement()]

    if fillType ~= nil then
        self:setGraph(fillType)
    else
        self.chart:setData({})
    end
end

---Set graph content for given fill
function SeasonsEconomyFrame:setGraph(fillType)
    local data = self.economy.history:getHistory(fillType)

    if data ~= nil then
        local min = luafp.reduce(data, math.min, math.huge)
        local max = math.ceil(luafp.reduce(data, math.max, 0))
        min = 0
        -- min = math.floor(math.max(min + (max - min) / 3, 0))

        self.chart:setMinValue(min)
        self.chart:setMaxValue(max)
        self.chart:setActiveX(self.environment:currentDayInYear())
        self.chart:setData(data)
    else
        self.chart:setData({})
    end
end

----------------------
-- Events
----------------------

function SeasonsEconomyFrame:onListSelectionChanged()
    self:updateGraph()
end

function SeasonsEconomyFrame:onDayChanged()
    self:updateGraph()
end

function SeasonsEconomyFrame:onSeasonLengthChanged()
    self:buildList()
    self:setPeriodTitles()
end

SeasonsEconomyFrame.L10N_SYMBOL = {
}
