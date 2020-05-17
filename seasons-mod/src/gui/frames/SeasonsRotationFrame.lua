----------------------------------------------------------------------------------------------------
-- SeasonsRotationFrame
----------------------------------------------------------------------------------------------------
-- Purpose:  The frame for crop rotation info
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsRotationFrame = {}
local SeasonsRotationFrame_mt = Class(SeasonsRotationFrame, TabbedMenuFrameElement)

SeasonsRotationFrame.SHORT_SLOT = 3

SeasonsRotationFrame.CONTROLS = {
    CONTAINER = "container",
    ROTATION_1 = "rotationOne",
    ROTATION_2 = "rotationTwo",
    ROTATION_3 = "rotationThree",
    ROTATION_4 = "rotationFour",
}

function SeasonsRotationFrame:new(i18n, localStorage)
    local self = TabbedMenuFrameElement:new(nil, SeasonsRotationFrame_mt)

    self.i18n = i18n
    self.messageCenter = g_messageCenter
    self.environment = g_seasons.environment
    self.gameEnvironment = g_currentMission.environment
    self.weather = g_seasons.weather
    self.localStorage = localStorage

    self.cropRotation = g_seasons.growth.cropRotation

    self:registerControls(SeasonsRotationFrame.CONTROLS)

    return self
end

function SeasonsRotationFrame:copyAttributes(src)
    SeasonsRotationFrame:superClass().copyAttributes(self, src)

    self.i18n = src.i18n
    self.localStorage = src.localStorage
end

function SeasonsRotationFrame:initialize()
    self.elementToRotationIndex = {}
    self.elementToRotationPosition = {}
    self.stateToFruitType = {}
    self.fruitTypeToState = {}
    self.rotations = {
        self.rotationOne,
        self.rotationTwo,
        self.rotationThree,
        self.rotationFour,
    }

    self.titles = {}
    table.insert(self.titles, self.i18n:getText("seasons_rotationCategory_0")) -- FALLOW
    for _, fruitType in ipairs(g_fruitTypeManager:getFruitTypes()) do
        if fruitType.allowsSeeding and fruitType.index ~= FruitType.OILSEEDRADISH and g_currentMission.fruits[fruitType.index] ~= nil then
            table.insert(self.titles, fruitType.fillType.title)
            self.stateToFruitType[#self.titles] = fruitType
            self.fruitTypeToState[fruitType] = #self.titles
        end
    end

    self.titlesWithoutOptionNone = {unpack(self.titles)} -- clone table / make a copy of the table
    table.insert(self.titles, "-") -- 'NONE'. This _shall_be_ the last entry, else "odd things" may happen, when `updateRotation` begins calling `setTexts()` on the MTOs.

    for rotIndex, rotation in pairs(self.rotations) do
        for i, element in ipairs(rotation) do
            element:setTexts(self.titles)
            self.elementToRotationIndex[element] = rotIndex
            self.elementToRotationPosition[element] = i
        end
    end

    self:setSettings(self.localStorage:getCropRotations())

    self:updateRotations()
end

function SeasonsRotationFrame:delete()
    self.elementToRotationIndex = {}
    self.elementToRotationPosition = {}

    SeasonsRotationFrame:superClass().delete(self)
end

function SeasonsRotationFrame:onFrameOpen()
    SeasonsRotationFrame:superClass().onFrameOpen(self)
end

function SeasonsRotationFrame:onFrameClose()
    SeasonsRotationFrame:superClass().onFrameClose(self)

    self.localStorage:saveIfDirty()
end

---Get the frame's main content element's screen size.
function SeasonsRotationFrame:getMainElementSize()
    return self.container.size
end

---Get the frame's main content element's screen position.
function SeasonsRotationFrame:getMainElementPosition()
    return self.container.absPosition
end

function SeasonsRotationFrame:updateRotations(updateStorage)
    for rotIndex, _ in pairs(self.rotations) do
        self:updateRotation(rotIndex)
    end

    if updateStorage ~= false then
        self.localStorage:setCropRotations(self:getSettings())
    end
end

---Update the rotation at given index
function SeasonsRotationFrame:updateRotation(rotIndex)
    self.debounceOnValueChanged = true -- In case call to :setTexts() activates the 'onValueChanged' callback.
    local showRemainingElements = true
    local prevElement = nil
    for yearIndex, element in ipairs(self.rotations[rotIndex]) do
        element:setVisible(showRemainingElements)

        local category, fruitIndex = self:getYearFruitAndCategory(rotIndex, yearIndex)
        local resultText = element:getDescendantByName("resultName")

        if category == nil or not showRemainingElements then
            if prevElement ~= nil and prevElement.texts ~= self.titles then
              prevElement:setTexts(self.titles) -- Allow option 'NONE'
            end

            resultText:setText("-")
            element:setLabel("-")
            showRemainingElements = false
        else
            if prevElement ~= nil and prevElement.texts ~= self.titlesWithoutOptionNone then
              prevElement:setTexts(self.titlesWithoutOptionNone) -- Remove option 'NONE'
            end

            if category == SeasonsCropRotation.CATEGORIES.FALLOW then
                resultText:setText("-")
                element:setLabel(self.i18n:getText("character_option_none"))
            else
                local previousYear = self:getPreviousYear(rotIndex, yearIndex)
                local secondPreviousYear = self:getPreviousYear(rotIndex, previousYear)

                local n1 = self:getYearFruitAndCategory(rotIndex, previousYear)
                local n2 = self:getYearFruitAndCategory(rotIndex, secondPreviousYear)

                local multiplier = self.cropRotation:getRotationYieldMultiplier(n2, n1, fruitIndex)

                resultText:setText(string.format("%0.2f", multiplier))
                element:setLabel(self.cropRotation:getCategoryName(category))
            end
        end

        prevElement = element
    end
    self.debounceOnValueChanged = nil
end

---Get the year index of the input before given one. Used so we support rotations smaller than 5 items
function SeasonsRotationFrame:getPreviousYear(rotIndex, yearIndex)
    local previous = yearIndex

    repeat
        previous = previous - 1
        if previous == 0 then
            previous = #self.rotations[rotIndex]
        end

        -- Do not keep wrapping around. Assume given item does have a category as well
        if previous == yearIndex then
            return yearIndex
        end
    until self:getYearFruitAndCategory(rotIndex, previous) ~= nil

    return previous
end

function SeasonsRotationFrame:getYearFruitAndCategory(rotIndex, yearIndex)
    local STATE_NONE   = #self.titles
    local STATE_FALLOW = 1

    local state = self.rotations[rotIndex][yearIndex]:getState()

    if state == STATE_NONE then
        return nil -- "none"
    elseif state == STATE_FALLOW then
        return SeasonsCropRotation.CATEGORIES.FALLOW, 0
    else
        local fruitType = self.stateToFruitType[state]
        return fruitType.rotation.category, fruitType.index
    end
end

----------------------
-- Saving and loading
----------------------

---Set the settings for all rotations (fruit types)
function SeasonsRotationFrame:setSettings(settings)
    local STATE_NONE   = #self.titles
    local STATE_FALLOW = 1

    for rotIndex, rotation in pairs(self.rotations) do
        for yearIndex, _ in pairs(rotation) do
            local fruitName = "NONE"
            -- Don't trust that localStorage have a filled 'settings'-table.
            if settings[rotIndex] ~= nil then
                fruitName = Utils.getNoNil(settings[rotIndex][yearIndex], fruitName)
            end

            local state = STATE_NONE
            if fruitName == "FALLOW" then
                state = STATE_FALLOW
            else
                local fruitType = g_fruitTypeManager:getFruitTypeByName(fruitName)
                -- Old rotations not valid anymore: reset
                if fruitType ~= nil and self.fruitTypeToState[fruitType] ~= nil then
                    state = self.fruitTypeToState[fruitType]
                end
            end

            self.rotations[rotIndex][yearIndex]:setState(state)
        end
        -- Fix any backwards-compability problems, in case the localStorage contained "invalid" rotation-planner-sequence.
        -- Example:
        --          YearIdx: 1        2         3         4         5         6
        -- Invalid sequence: Wheat -> None   -> Fallow -> None   -> Barley -> None
        --   Fixed sequence: Wheat -> Fallow -> Fallow -> Fallow -> Barley -> None
        local noneIsDisallowed = false
        for yearIndex=#rotation, 1, -1 do
            local state = self.rotations[rotIndex][yearIndex]:getState()
            if state == STATE_NONE and noneIsDisallowed then
                -- Force change 'None' to 'Fallow', because 'None' is not allowed inbetween fruit rotations
                self.rotations[rotIndex][yearIndex]:setState(STATE_FALLOW)
            elseif state ~= STATE_NONE then
                noneIsDisallowed = true
            end
        end
    end

    self:updateRotations(false)
end

---Get a list of rotations, for each a fruit type, fallow, or none
function SeasonsRotationFrame:getSettings()
    local STATE_NONE   = #self.titles
    local STATE_FALLOW = 1

    local settings = {}
    for rotIndex, rotation in pairs(self.rotations) do
        local rot = {}

        for yearIndex, element in ipairs(rotation) do
            local state = element:getState()
            if state == STATE_NONE then
                rot[yearIndex] = nil
            elseif state == STATE_FALLOW then
                rot[yearIndex] = "FALLOW"
            else
                local fruitType = self.stateToFruitType[state]
                if fruitType ~= nil then
                    rot[yearIndex] = fruitType.fillType.name:upper()
                else
                    rot[yearIndex] = "FALLOW"
                end
            end
        end

        settings[rotIndex] = rot
    end

    return settings
end

----------------------
-- Events
----------------------

function SeasonsRotationFrame:onValueChanged(value, element)
    if self.debounceOnValueChanged then
        return
    end
    local rotIndex = self.elementToRotationIndex[element]

    self:updateRotation(rotIndex)

    self.localStorage:setCropRotations(self:getSettings())
end

SeasonsRotationFrame.L10N_SYMBOL = {
}
