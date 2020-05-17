----------------------------------------------------------------------------------------------------
-- SeasonsGrowthPatchyCropFailure
----------------------------------------------------------------------------------------------------
-- Purpose:  PatchyCropFailure execution functions
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsGrowthPatchyCropFailure = {}

local SeasonsGrowthPatchyCropFailure_mt = Class(SeasonsGrowthPatchyCropFailure)

function SeasonsGrowthPatchyCropFailure:new(mission, data)
    local self = setmetatable({}, SeasonsGrowthPatchyCropFailure_mt)

    self.mission = mission
    self.data = data

    self.numberOfFruits = 0
    self.fruits = {}
    self.fruitToProcessIndex = 0
    self.timerInterval = 0

    return self
end

function SeasonsGrowthPatchyCropFailure:delete()
    self.mission = nil
    self.data = nil
    self.fruits = nil
end

function SeasonsGrowthPatchyCropFailure:load()
    if self.data.isNewGame then
        self:resetForNewDay()
    end
end

function SeasonsGrowthPatchyCropFailure:loadFromSavegame(xmlFile)
    local key = "seasons.growth.cpf.numberOfFruits"
    if not hasXMLProperty(xmlFile, key) then
        self:resetForNewDay() -- because something is super wrong with the save game file
        return
    end

    self.numberOfFruits = getXMLInt(xmlFile, key)
    self.fruitToProcessIndex = getXMLInt(xmlFile, "seasons.growth.cpf.fruitToProcessIndex")
    self.timerInterval = getXMLFloat(xmlFile, "seasons.growth.cpf.timerInterval")

    local i = 0
    while true do
        local cpfKey = string.format("seasons.growth.cpf.fruitIndex(%d)", i)
        if not hasXMLProperty(xmlFile, cpfKey) then
            break
        end

        local index = getXMLInt(xmlFile, cpfKey .. "#index")
        local value = getXMLInt(xmlFile, cpfKey .. "#value")

        if index ~= nil and value ~= nil then
            self.fruits[index] = value
        end

        i = i + 1
    end
end

function SeasonsGrowthPatchyCropFailure:saveToSavegame(xmlFile)
    setXMLInt(xmlFile, "seasons.growth.cpf.numberOfFruits", self.numberOfFruits)
    setXMLInt(xmlFile, "seasons.growth.cpf.fruitToProcessIndex", self.fruitToProcessIndex)
    setXMLFloat(xmlFile, "seasons.growth.cpf.timerInterval", self.timerInterval)

    local i = 0

    for index, value in pairs(self.fruits) do
        local key = string.format("seasons.growth.cpf.fruitIndex(%d)", i)
        setXMLInt(xmlFile, key .. "#index", index)
        setXMLInt(xmlFile, key .. "#value", value)
        i = i + 1
    end
end

function SeasonsGrowthPatchyCropFailure:getFruits()
    local numberOfFruits = 0

    for index, fruit in pairs(self.mission.fruits) do
        if index ~= FruitType.DRYGRASS then
            numberOfFruits = numberOfFruits + 1
            self.fruits[numberOfFruits] = index
        end
    end

    return numberOfFruits
end

function SeasonsGrowthPatchyCropFailure:getTimerIntervalInMS(numberOfFruits)
    return self.timerInterval
end

function SeasonsGrowthPatchyCropFailure:resetForNewDay()
    self.fruitToProcessIndex = 1
    self.numberOfFruits = self:getFruits() -- in case map was updated since last save with more fruits
    self.timerInterval = (23 * 60 * 60 * 1000) / self.numberOfFruits --TODO magic values
end

function SeasonsGrowthPatchyCropFailure:getNextFruitIndex()
    local currentIndex = self.fruitToProcessIndex

    if currentIndex <= self.numberOfFruits then
        self.fruitToProcessIndex = self.fruitToProcessIndex + 1
        return self.fruits[currentIndex]
    else
        return nil
    end
end
