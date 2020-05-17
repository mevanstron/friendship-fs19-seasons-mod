----------------------------------------------------------------------------------------------------
-- SeasonsAnimalsFrame
----------------------------------------------------------------------------------------------------
-- Purpose:  New frame for animals assuming a lot of them in a pen, individually.
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsAnimalsFrame = {}
local SeasonsAnimalsFrame_mt = Class(SeasonsAnimalsFrame, TabbedMenuFrameElement)

SeasonsAnimalsFrame.CONTROLS = {
    "husbandryListBox",
    "husbandryList",
    "husbandryItemTemplate",

    "husbandryDetailsLayout",

    "husbandryDetailBox",
    "husbandryDetailLabels",
    "husbandryDetailValues",

    "conditionRow",
    "conditionLabel",
    "conditionValue",
    "conditionStatusBar",

    "foodRow",
    "foodLabel",
    "foodValue",
    "foodStatusBar",

    "animalList",
    "animalListBox",

    "animalDetailBox",
    "animalDetailImage",
    "animalDetailTitle",
    "animalDetailBreed",
    "animalDetailLabels",
    "animalDetailValues",

    "noAnimalsBox",
    "noHusbandriesBox",
}

SeasonsAnimalsFrame.UPDATE_INTERVAL = 10000 -- 10s but due to a bug it becomes 5s

function SeasonsAnimalsFrame:new(i18n)
    local self = TabbedMenuFrameElement:new(nil, SeasonsAnimalsFrame_mt)

    self.i18n = i18n
    self.fruitTypeManager = g_fruitTypeManager
    self.growthData = g_seasons.growth.data
    self.messageCenter = g_messageCenter
    self.environment = g_seasons.environment
    self.gameSettings = g_gameSettings
    self.animalManager = g_animalManager
    self.animalFoodManager = g_animalFoodManager
    self.fillTypeManager = g_fillTypeManager

    self:registerControls(SeasonsAnimalsFrame.CONTROLS)

    self.husbandriesDataSource = GuiDataSource:new()
    self.animalsDataSource = GuiDataSource:new()

    self.nextAnimalInfoLine = 1
    self.nextHusbandryInfoLine = 1

    self.updateTime = SeasonsAnimalsFrame.UPDATE_INTERVAL

    self.hasCustomMenuButtons = true
    self.renameButtonInfo = {}

    return self
end

function SeasonsAnimalsFrame:copyAttributes(src)
    SeasonsAnimalsFrame:superClass().copyAttributes(self, src)

    self.i18n = src.i18n
end

function SeasonsAnimalsFrame:onGuiSetupFinished()
    SeasonsAnimalsFrame:superClass().onGuiSetupFinished(self)

    self.husbandryList:setDataSource(self.husbandriesDataSource)
    self.husbandryList:setAssignItemDataFunction(function (...)
        self:assignHusbandryData(...)
    end)

    self.animalList:setDataSource(self.animalsDataSource)
    self.animalList:setAssignItemDataFunction(function (...)
        self:assignAnimalData(...)
    end)

    self.husbandriesDataSource:addChangeListener(self, self.onHusbandryDataSourceChanged)
    self.animalsDataSource:addChangeListener(self, self.onAnimalDataSourceChanged)
end

function SeasonsAnimalsFrame:initialize()
    self.hotspotButtonInfo = {inputAction = InputAction.MENU_CANCEL, text = self.i18n:getText("button_showOnMap"), callback = function() self:onButtonHotspot() end}
    self.renameButtonInfo = {inputAction = InputAction.MENU_ACTIVATE, text = self.i18n:getText("button_rename"), callback = function() self:onButtonRename() end}
end

function SeasonsAnimalsFrame:onFrameOpen()
    SeasonsAnimalsFrame:superClass().onFrameOpen(self)

    self:updateHusbandryData()

    FocusManager:setFocus(self.husbandryList)

    -- Select first item if there is no selection
    if self.husbandryList.selectedIndex == 0 then
        self.husbandryList:setSelectedIndex(1, true)
    end

    self.messageCenter:subscribe(MessageType.HUSBANDRY_ANIMALS_CHANGED, self.onAnimalDataChanged, self)
end

function SeasonsAnimalsFrame:onFrameClose()
    self.messageCenter:unsubscribe(MessageType.HUSBANDRY_ANIMALS_CHANGED, self)

    SeasonsAnimalsFrame:superClass().onFrameClose(self)
end

---Get the frame's main content element's screen size.
function SeasonsAnimalsFrame:getMainElementSize()
    return self.husbandryList.size
end

---Get the frame's main content element's screen position.
function SeasonsAnimalsFrame:getMainElementPosition()
    return self.husbandryList.absPosition
end

---Automatic update the page
function SeasonsAnimalsFrame:update(dt)
    SeasonsAnimalsFrame:superClass().update(self, dt)

    if self.selectedHusbandry ~= nil then
        self.updateTime = self.updateTime - dt

        if self.updateTime < 0 then
            self:updateHusbandryData()

            self.updateTime = SeasonsAnimalsFrame.UPDATE_INTERVAL
        end
    end
end

---Update contextual menu buttons.
function SeasonsAnimalsFrame:updateMenuButtons()
    self.menuButtonInfo = {{inputAction = InputAction.MENU_BACK}}

    local husbandry = self.selectedHusbandry

    if husbandry ~= nil and #husbandry.mapHotspots > 0 then
        if husbandry.mapHotspots[1] == g_currentMission.currentMapTargetHotspot then
            self.hotspotButtonInfo.text = self.i18n:getText("action_untag")
        else
            self.hotspotButtonInfo.text = self.i18n:getText("action_tag")
        end

        table.insert(self.menuButtonInfo, self.hotspotButtonInfo)

        if self.selectedHorse ~= nil then
            table.insert(self.menuButtonInfo, self.renameButtonInfo)
        end
    end

    self:setMenuButtonInfoDirty()
end


---Rename the currently selected horse if the new name has been confirmed.
function SeasonsAnimalsFrame:renameCurrentHorse(newName, hasConfirmed)
    if hasConfirmed and self.selectedHorse ~= nil then
        self.selectedHusbandry:renameAnimal(NetworkUtil.getObjectId(self.selectedHorse), newName)
    end
end

----------------------
-- Animal data
----------------------

---Get a sorted array of husbandries belonging to the current player's farm.
function SeasonsAnimalsFrame:getSortedFarmHusbandries()
    return g_currentMission.inGameMenu.pageAnimals:getSortedFarmHusbandries()
end

---The data source for the husbandries changed. Update the list
function SeasonsAnimalsFrame:onHusbandryDataSourceChanged()
    local hasHusbandries = self.husbandriesDataSource:getCount() > 0

    self.selectedHusbandry = nil

    self.noHusbandriesBox:setVisible(not hasHusbandries)
    self.husbandryListBox:setVisible(hasHusbandries)
    self.husbandryDetailBox:setVisible(hasHusbandries)

    -- If there is any animal this will be updated by the animal data source
    self.animalListBox:setVisible(false)
    self.animalDetailBox:setVisible(false)
    self.noAnimalsBox:setVisible(false)

    if hasHusbandries then
        local selectedIndex = self.husbandryList:getSelectedDataIndex()
        self.husbandryList:updateAlternatingBackground()
        self.husbandryList:updateItemPositions()

        -- restore selection
        self.husbandryList:setSelectedIndex(selectedIndex, true)
    end
end

---The data source for animals changes. Update the list
function SeasonsAnimalsFrame:onAnimalDataSourceChanged()
    local hasAnimals = self.animalsDataSource:getCount() > 0

    -- self.selectedHusbandry = nil
    -- self.selectedHorse = nil

    self.animalListBox:setVisible(hasAnimals)
    self.animalDetailBox:setVisible(hasAnimals)
    self.noAnimalsBox:setVisible(not hasAnimals)

    if hasAnimals then
        local selectedIndex = math.max(self.animalList:getSelectedDataIndex(), 1)
        self.animalList:updateAlternatingBackground()
        self.animalList:updateItemPositions()

        -- restore selection
        self.animalList:setSelectedIndex(selectedIndex, true)
    end
end

---Update the info shown for a husbandry
function SeasonsAnimalsFrame:updateHusbandryInfo(husbandry)
    self:resetHusbandryInfoLines()

    local conditionIndex = 1
    for i = 1, #self.conditionRow do
        self.conditionRow[i]:setVisible(true)
    end

    local cleanliness = husbandry:getFoodSpillageFactor()
    if cleanliness ~= nil then
        self.conditionLabel[conditionIndex]:setText(self.i18n:getText("statistic_cleanliness"))
        self.conditionValue[conditionIndex]:setText(string.format("%.0f%%", cleanliness * 100))
        self:setStatusBarValue(self.conditionStatusBar[conditionIndex], cleanliness)

        conditionIndex = conditionIndex + 1
    end

    local waterInfos = husbandry:getWaterFilltypeInfo()
    if waterInfos ~= AnimalHusbandry.NO_FILLTYPE_INFOS then
        local level, capacity, label = self:summarizeFillLevelInfos(waterInfos)
        if capacity > 0 then
            -- Override color of the bar when there is a pump. Also show there is a pump in the text
            local hasPump = husbandry:getModuleByName("water").seasons_waterPump ~= nil
            local colorValue = level / capacity
            if hasPump then
                label = label .. " (" .. self.i18n:getText("seasons_shopItem_waterPump") .. ")"
                colorValue = 1
            end

            self.conditionLabel[conditionIndex]:setText(label)
            self.conditionValue[conditionIndex]:setText(self.i18n:formatVolume(level, 0))
            self:setStatusBarValue(self.conditionStatusBar[conditionIndex], level / capacity, nil, colorValue)

            conditionIndex = conditionIndex + 1
        end
    end

    local strawInfos = husbandry:getStrawFilltypeInfo()
    if strawInfos ~= AnimalHusbandry.NO_FILLTYPE_INFOS then
        local level, capacity, label = self:summarizeFillLevelInfos(strawInfos)
        if capacity > 0 then
            self.conditionLabel[conditionIndex]:setText(label)
            self.conditionValue[conditionIndex]:setText(self.i18n:formatVolume(level, 0))
            self:setStatusBarValue(self.conditionStatusBar[conditionIndex], level / capacity)

            conditionIndex = conditionIndex + 1
        end
    end

    -- Hide all unused bars
    for i = conditionIndex, #self.conditionRow do
        self.conditionRow[i]:setVisible(false)
    end

    -- Food
    local foodInfos = husbandry:getFoodFilltypeInfo()
    local foodGroups = self.animalFoodManager:getFoodGroupByAnimalType(husbandry:getAnimalType())
    for i = 1, #self.foodRow do
        local info = foodInfos[i]

        if info ~= nil then
            self.foodRow[i]:setVisible(true)

            local title = ""

            for i, foodFillTypeIndex in ipairs(info.foodGroup.fillTypes) do
                local filltype = self.fillTypeManager:getFillTypeByIndex(foodFillTypeIndex)
                title = title .. filltype.title

                if i < #info.foodGroup.fillTypes then
                    title = title .. " / "
                end
            end

            self.foodLabel[i]:setText(title)--info.foodGroup.title)
            self.foodValue[i]:setText(self.i18n:formatVolume(info.fillLevel, 0))
            self:setStatusBarValue(self.foodStatusBar[i], info.fillLevel / info.capacity)
        else
            self.foodRow[i]:setVisible(false)
        end
    end

    -- Production
    local productionInfos = husbandry:getProductionFilltypeInfo() -- production infos are returned in display order
    for _, productionInfo in ipairs(productionInfos) do
        local level, capacity, label = self:summarizeFillLevelInfos(productionInfo)

        self:addHusbandryInfoLine(label, self.i18n:formatVolume(level, 0))
    end

    -- Food/water/straw estimates
    self:addHusbandryInfoLine("", "") -- divider

    local food = g_seasons.animals:calculateAnnualFeedAmount(husbandry)
    self:addHusbandryInfoLine(self.i18n:getText("seasons_ui_estimatedFoodRequired"), string.format("%s / %s", self.i18n:formatVolume(food, 0), self.i18n:getText("seasons_animal_age_short")))

    -- self.husbandryDetailsLayout:invalidateLayout()
end

function SeasonsAnimalsFrame:setStatusBarValue(bar, value, isList, colorValue)
    local profiles = isList and SeasonsAnimalsFrame.PROFILE.STATUS_BAR_LIST or SeasonsAnimalsFrame.PROFILE.STATUS_BAR
    local profile

    if colorValue == nil then
        colorValue = value
    end
    if colorValue >= InGameMenuAnimalsFrame.STATUS_BAR_HIGH then
        profile = profiles.HIGH
    elseif colorValue >= InGameMenuAnimalsFrame.STATUS_BAR_MEDIUM then
        profile = profiles.MEDIUM
    else
        profile = profiles.LOW
    end

    bar:applyProfile(profile) -- reset size and other attributes

    local fullSize = bar.parent.size[1]
    local partSize = fullSize * math.max(math.min(value, 1), 0)
    bar:setSize(partSize)
end

function SeasonsAnimalsFrame:addHusbandryInfoLine(label, value)
    local index = self.nextHusbandryInfoLine

    self.husbandryDetailLabels[index]:setText(label)
    self.husbandryDetailValues[index]:setText(value)

    self.nextHusbandryInfoLine = index + 1
end

function SeasonsAnimalsFrame:resetHusbandryInfoLines(toNum)
    if toNum == nil then
        toNum = 1
    end

    for i = self.nextHusbandryInfoLine - 1, toNum, -1 do
        self.husbandryDetailLabels[i]:setText("")
        self.husbandryDetailValues[i]:setText("")
    end

    self.nextHusbandryInfoLine = toNum
end

---Update the info shown for an animal
function SeasonsAnimalsFrame:updateAnimalInfo(animal)
    local subType = animal:getSubType()

    self:resetAnimalInfoLines()

    self.animalDetailImage:setImageFilename(subType.storeInfo.imageFilename)

    if self.selectedHusbandry:getAnimalType() == "HORSE" then
        self.animalDetailTitle:setText(animal:getName())
        self.animalDetailBreed:setText(animal.subType.subTypeName)

        self:addAnimalInfoLine(self.i18n:getText("seasons_statistic_health"), string.format("%.0f%%", math.floor(animal:getHealthScale() * 100)))
        self:addAnimalInfoLine(self.i18n:getText("ui_horseFitness"), string.format("%.0f%%", math.floor(animal:getFitnessScale() * 100)))
        self:addAnimalInfoLine(self.i18n:getText("statistic_cleanliness"), string.format("%.0f%%", (1 - animal:getDirtScale()) * 100))
        self:addAnimalInfoLine(self.i18n:getText("ui_horseDailyRiding"), string.format("%.0f%%", math.floor(animal.ridingScale * 100)))
        self:addAnimalInfoLine(self.i18n:getText("ui_sellValue"), self.i18n:formatMoney(animal:getValue()))
    else
        self.animalDetailTitle:setText(string.format("%s (%s)", animal:getName(), SeasonsModUtil.formatSex(animal.seasons_isFemale)))
        self.animalDetailBreed:setText(animal.subType.subTypeName)

        self:addAnimalInfoLine(self.i18n:getText("seasons_statistic_health"), string.format("%.0f%%", math.floor(self.selectedHusbandry:getGlobalProductionFactor() * 100)))
        self:addAnimalInfoLine(self.i18n:getText("seasons_statistic_age"), string.format("%s (%s)", SeasonsModUtil.formatAge(animal.seasons_age), self.i18n:getText(SeasonsAnimalsFrame.L10N_AGECLASSIFIER[animal:getAgeClassifier()])))

        self:addAnimalInfoLine(self.i18n:getText("seasons_statistic_weight"), SeasonsModUtil.formatSmallWeight(animal.seasons_weight, 0, false))

        if animal.seasons_isFemale then
            local label = self.i18n:getText("statistic_timeTillNextAnimal")
            if animal.seasons_age < animal.subType.breeding.fertileAge then
                self:addAnimalInfoLine(label, self.i18n:getText("seasons_ui_notFertile"))
            elseif animal.seasons_timeUntilBirth <= 0 then
                self:addAnimalInfoLine(label, "-")
            else
                self:addAnimalInfoLine(label, SeasonsModUtil.formatAge(animal.seasons_timeUntilBirth))
            end
        end
    end
end

---Add a new info line for the animal details
function SeasonsAnimalsFrame:addAnimalInfoLine(label, value)
    local index = self.nextAnimalInfoLine

    self.animalDetailLabels[index]:setText(label)
    self.animalDetailValues[index]:setText(value)

    self.nextAnimalInfoLine = index + 1
end

---Remove all animal detail info line
function SeasonsAnimalsFrame:resetAnimalInfoLines(toNum)
    if toNum == nil then
        toNum = 1
    end

    for i = self.nextAnimalInfoLine - 1, toNum, -1 do
        self.animalDetailLabels[i]:setText("")
        self.animalDetailValues[i]:setText("")
    end

    self.nextAnimalInfoLine = toNum
end

function SeasonsAnimalsFrame:summarizeFillLevelInfos(fillLevelInfos)
    local level = 0
    local capacity = 0
    local label = ""

    for _, fillLevelInfo in pairs(fillLevelInfos) do
        level = level + fillLevelInfo.fillLevel
        capacity = capacity + fillLevelInfo.capacity

        if label == "" then
            label = fillLevelInfo.fillType.title
        end
    end

    return level, capacity, label
end

----------------------
-- List building
----------------------

---Update the data of the husbandries
function SeasonsAnimalsFrame:updateHusbandryData()
    local data = {}

    local husbandries = self:getSortedFarmHusbandries()
    for _, husbandry in ipairs(husbandries) do
        table.insert(data, {
            name = husbandry:getName(),
            numAnimals = husbandry:getNumOfAnimals(),
            husbandry = husbandry,
        })
    end

    self.husbandriesDataSource:setData(data)
end

---Update the data of the animals based on current husbandry
function SeasonsAnimalsFrame:updateAnimalData()
    local data = {}

    local typedAnimals = self.selectedHusbandry:getTypedAnimals()
    for fillTypeIndex, typedAnimals in pairs(typedAnimals) do
        for _, animal in ipairs(typedAnimals) do
            table.insert(data, {
                fillTypeIndex = fillTypeIndex,
                animal = animal,
            })
        end
    end

    self.animalsDataSource:setData(data)
end

---Assign data to a list item
function SeasonsAnimalsFrame:assignHusbandryData(listItem, husbandryData)
    local nameText = listItem:getDescendantByName("name")
    local numAnimalsText = listItem:getDescendantByName("numAnimals")
    local icon = listItem:getDescendantByName("icon")
    local bar = listItem:getDescendantByName("bar")

    nameText:setText(husbandryData.name)
    numAnimalsText:setText(husbandryData.numAnimals)

    -- Assume there is only 1 animal type
    local type = husbandryData.husbandry:getAnimalType()
    if type ~= nil then
        icon:setImageFilename(self.animalManager:getAnimalsByType(type).subTypes[1].fillTypeDesc.hudOverlayFilename)
    end

    -- Limit to 0.05 so it always shows a bit of red
    self:setStatusBarValue(bar, math.max(husbandryData.husbandry:seasons_getCondition(), 0.02), true)
end

---Assign data to a list item
function SeasonsAnimalsFrame:assignAnimalData(listItem, animalData)
    local nameText = listItem:getDescendantByName("name")
    local weightText = listItem:getDescendantByName("weight")

    local animal = animalData.animal
    local subType = animal.subType

    if self.selectedHusbandry:getAnimalType() == "HORSE" then
        nameText:setText(animal:getName())
        weightText:setText("")
    else
        nameText:setText(string.format("%s (%s)", animal:getName(), SeasonsModUtil.formatSex(animal.seasons_isFemale)))
        weightText:setText(SeasonsModUtil.formatSmallWeight(animal.seasons_weight, 0, false))
    end
end

----------------------
-- Events
----------------------

---Called when husbandry and animal information changes in the game.
function SeasonsAnimalsFrame:onAnimalDataChanged()
    self:updateHusbandryData()
end

function SeasonsAnimalsFrame:onHusbandryListSelectionChanged(selectedIndex)
    self.selectedHusbandry = nil

    if self.husbandriesDataSource:getCount() > 0 then
        local selectedData = self.husbandriesDataSource:getItem(selectedIndex)

        if selectedData ~= nil then
            self.selectedHusbandry = selectedData.husbandry

            -- Reset contents of animal list
            self:updateAnimalData()

            -- Update husbandry info
            self:updateHusbandryInfo(self.selectedHusbandry)
        end
    end

    self:updateMenuButtons()
end

function SeasonsAnimalsFrame:onAnimalListSelectionChanged(selectedIndex)
    self.selectedAnimal = nil
    self.selectedHorse = nil

    if self.animalsDataSource:getCount() > 0 then
        local selectedData = self.animalsDataSource:getItem(selectedIndex)

        if selectedData ~= nil then
            self.selectedAnimal = selectedData.animal
            if self.selectedHusbandry:getAnimalType() == "HORSE" then
                self.selectedHorse = selectedData.animal
            end

            self:updateAnimalInfo(selectedData.animal)
        end
    end

    self:updateMenuButtons()
end

function SeasonsAnimalsFrame:onButtonHotspot()
    local husbandry = self.selectedHusbandry

    if husbandry ~= nil and next(husbandry.mapHotspots) ~= nil then
        -- Toggle hotspot
        if husbandry.mapHotspots[1] == g_currentMission.currentMapTargetHotspot then
            g_currentMission:setMapTargetHotspot()
        else
            g_currentMission:setMapTargetHotspot(husbandry.mapHotspots[1])
        end

        -- Update button text
        self:updateMenuButtons()
    end
end

---Handle "rename" button activation when a horse is selected.
function SeasonsAnimalsFrame:onButtonRename()
    g_gui:showTextInputDialog{
        target = self,
        callback = self.renameCurrentHorse,
        defaultText = self.selectedHorse:getName(),
        dialogPrompt = self.i18n:getText("ui_enterHorseName"),
        imePrompt = self.i18n:getText("ui_horseName"),
        confirmText = self.i18n:getText("button_confirm"),
        maxCharacters = InGameMenuAnimalsFrame.MAX_ANIMAL_NAME_LENGTH,
        activateInputText = self.i18n:getText("button_rename")
    }
end

SeasonsAnimalsFrame.PROFILE = {
    STATUS_BAR = {
        HIGH = "seasonsAnimalsSmallStatusBar",
        MEDIUM = "seasonsAnimalsSmallStatusBarMedium",
        LOW = "seasonsAnimalsSmallStatusBarLow",
    },
    STATUS_BAR_LIST = {
       HIGH = "seasonsAnimalsHusbandryListItemStatusBar",
       MEDIUM = "seasonsAnimalsHusbandryListItemStatusBarMedium",
       LOW = "seasonsAnimalsHusbandryListItemStatusBarLow",
    }
}

SeasonsAnimalsFrame.L10N_AGECLASSIFIER = {
    [SeasonsAnimals.AGE_CLASSIFIER.NEWBORN] = "seasons_ui_ageClassifier_newborn",
    [SeasonsAnimals.AGE_CLASSIFIER.YOUNG] = "seasons_ui_ageClassifier_young",
    [SeasonsAnimals.AGE_CLASSIFIER.MATURE] = "seasons_ui_ageClassifier_mature",
    [SeasonsAnimals.AGE_CLASSIFIER.OLD] = "seasons_ui_ageClassifier_old",
}
