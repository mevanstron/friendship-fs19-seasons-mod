----------------------------------------------------------------------------------------------------
-- SeasonsAnimalsUI
----------------------------------------------------------------------------------------------------
-- Purpose:  Animal UI changes
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsAnimalsUI = {}

local SeasonsAnimalsUI_mt = Class(SeasonsAnimalsUI)

function SeasonsAnimalsUI:new(mission, i18n)
    local self = setmetatable({}, SeasonsAnimalsUI_mt)

    self.i18n = i18n
    self.mission = mission
    self.isServer = mission:getIsServer()

    SeasonsModUtil.appendedFunction(AnimalScreen, "applyDataToItemRow", self.inj_animalScreen_applyDataToItemRow)
    SeasonsModUtil.appendedFunction(AnimalScreen, "updateInfoBox",      self.inj_animalScreen_updateInfoBox)

    return self
end

function SeasonsAnimalsUI:delete()
end

function SeasonsAnimalsUI:load()
end

----------------------
-- Injections
----------------------

---Update text in the animal screen lists
function SeasonsAnimalsUI.inj_animalScreen_applyDataToItemRow(animalScreen, listRow, animalItem)
    local stateLabel = listRow:getDescendantByName(AnimalScreen.ITEM_STATE)

    local age, weight, isFemale, isHorse = -1, -1, false, false

    if animalItem.animalId ~= nil then -- real animal
        local animal = NetworkUtil.getObject(animalItem.animalId)
        age = animal.seasons_age
        weight = animal:getWeightWithUnborn()
        isFemale = animal.seasons_isFemale
        isHorse = animal:isa(Horse)
    else -- new animal
        local subType = animalItem.subType
        age = subType.storeInfo.buyAge
        weight = subType.storeInfo.buyWeight
        isFemale = subType.storeInfo.buyIsFemale
        isHorse = subType.rideableFileName ~= ""
    end

    if isHorse then
        return
    end

    local stateText = animalScreen.l10n:getText("animal_new")
    if animalItem.state == AnimalItem.STATE_STOCK then
        stateText = animalScreen.l10n:getText("animal_stock")
    end

    local formattedWeight = SeasonsModUtil.formatSmallWeight(weight, 0, false)
    stateLabel:setText(string.format("%s, %0.1f %s, %s", stateText, age, animalScreen.l10n:getText("seasons_animal_age"), formattedWeight))

    local nameLabel = listRow:getDescendantByName(AnimalScreen.ITEM_NAME)
    nameLabel:setText(string.format("%s (%s)", nameLabel.text, SeasonsModUtil.formatSex(isFemale)))
end

---Add custom info to the animal on the animal screen
function SeasonsAnimalsUI.inj_animalScreen_updateInfoBox(animalScreen, isSourceSelected)
    if isSourceSelected == nil then
        isSourceSelected = animalScreen.isSourceSelected
    end

    local animal = nil
    if isSourceSelected then
        local dataIndex = animalScreen.listSource:getSelectedDataIndex()
        animal = animalScreen.sourceDataSource:getItem(dataIndex)
    else
        local dataIndex = animalScreen.listTarget:getSelectedDataIndex()
        animal = animalScreen.targetDataSource:getItem(dataIndex)
    end

    if animal ~= nil then

        local isFemale = animal.subType.storeInfo.buyIsFemale
        if animal.animalId ~= nil then
            local animal = NetworkUtil.getObject(animal.animalId)
            if animal ~= nil then
                -- this can sometimes be nil, see 30240
                isFemale = animal.seasons_isFemale
            end
        end

        animalScreen.animalTitle:setText(string.format("%s (%s)", animalScreen.animalTitle.text, SeasonsModUtil.formatSex(isFemale)))

        local elements = animalScreen.infoBox.elements
        local infoTextBox = elements[#elements]

        local text = animalScreen.l10n:getText("seasons_animalInfo_" ..  animal.subType.fillTypeDesc.name)
        local customEnv = animal.subType.customEnv
        if animalScreen.l10n:hasText("seasons_animalInfo_" ..  animal.subType.fillTypeDesc.name, customEnv) then
            text = animalScreen.l10n:getText("seasons_animalInfo_" ..  animal.subType.fillTypeDesc.name, customEnv)
        end

        infoTextBox:setText(text)
    end
end
