----------------------------------------------------------------------------------------------------
-- SeasonsAnimalsData
----------------------------------------------------------------------------------------------------
-- Purpose:  Data for the animals changes
--
-- Adds seasonal data to the animal type manager
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsAnimalsData = {}

local SeasonsAnimalsData_mt = Class(SeasonsAnimalsData)

function SeasonsAnimalsData:new(animalManager)
    local self = setmetatable({}, SeasonsAnimalsData_mt)

    self.animalManager = animalManager

    self.paths = {}

    return self
end

function SeasonsAnimalsData:delete()
end

function SeasonsAnimalsData:load()
    self:loadDataFromFiles()
end

function SeasonsAnimalsData:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("animals", path.file)
        if xmlFile then
            self:loadDataFromFile(xmlFile)

            delete(xmlFile)
        end
    end
end

function SeasonsAnimalsData:loadDataFromFile(xmlFile)
    local i = 0
    while true do
        local animalKey = string.format("animals.animal(%d)", i)
        if not hasXMLProperty(xmlFile, animalKey) then
            break
        end

        local animalType = getXMLString(xmlFile, animalKey .. "#type")

        local j = 0
        while true do
            local subKey = string.format("%s.subType(%d)", animalKey, j)
            if not hasXMLProperty(xmlFile, subKey) then
                break
            end

            local fillTypeName = getXMLString(xmlFile, subKey .. "#fillTypeName")
            local fillType = g_fillTypeManager:getFillTypeByName(fillTypeName)

            local isBird = getXMLBool(xmlFile, subKey .. "#isBird")
            local isSheep = getXMLBool(xmlFile, subKey .. "#isSheep")

            local animal = self.animalManager:getAnimalByFillType(fillType.index)
            if animal ~= nil then
                local data = animal.seasons or {}

                data.food = getXMLFloat(xmlFile, subKey .. ".input#food")
                data.straw = getXMLFloat(xmlFile, subKey .. ".input#straw")
                data.water = getXMLFloat(xmlFile, subKey .. ".input#water")
                data.buyWeight = getXMLFloat(xmlFile, subKey .. ".weight#buy")
                data.bornWeight = getXMLFloat(xmlFile, subKey .. ".weight#born")
                data.gainBorn = getXMLFloat(xmlFile, subKey .. ".growth#gainBorn")
                data.gainPeakMale = getXMLFloat(xmlFile, subKey .. ".growth#gainPeakMale")
                data.gainPeakFemale = getXMLFloat(xmlFile, subKey .. ".growth#gainPeakFemale")
                data.daysPeak = getXMLFloat(xmlFile, subKey .. ".growth#daysPeak")
                data.gainLevel = getXMLFloat(xmlFile, subKey .. ".growth#gainLevel")
                data.daysLevel = getXMLFloat(xmlFile, subKey .. ".growth#daysLevel")
                data.maxAge = getXMLFloat(xmlFile, subKey .. ".growth#maxAge")
                data.milk = getXMLFloat(xmlFile, subKey .. ".output#milk")
                data.manure = getXMLFloat(xmlFile, subKey .. ".output#manure")
                data.liquidManure = getXMLFloat(xmlFile, subKey .. ".output#liquidManure")
                data.pallets = getXMLFloat(xmlFile, subKey .. ".output#pallets")
                data.foodSpillage = getXMLFloat(xmlFile, subKey .. ".output#foodSpillage")
                data.buyPrice = getXMLFloat(xmlFile, subKey .. ".store#buyPrice")
                data.baseSellPrice = getXMLFloat(xmlFile, subKey .. ".store#baseSellPrice")
                data.pricePerKg = getXMLFloat(xmlFile, subKey .. ".store#pricePerKg")
                data.priceDropAge = getXMLFloat(xmlFile, subKey .. ".store#priceDropAge")
                data.transportPrice = getXMLFloat(xmlFile, subKey .. ".store#transportPrice")
                data.buyIsFemale = getXMLBool(xmlFile, subKey .. ".store#buyIsFemale")
                data.buyAge = getXMLFloat(xmlFile, subKey .. ".store#buyAge")
                data.fertileAge = getXMLFloat(xmlFile, subKey .. ".breeding#fertileAge")
                data.gestationPeriod = getXMLFloat(xmlFile, subKey .. ".breeding#gestationPeriod")
                data.gestationInterval = getXMLFloat(xmlFile, subKey .. ".breeding#interval")
                data.averageLitterSize = getXMLFloat(xmlFile, subKey .. ".breeding#averageLitterSize")
                data.variationLitterSize = getXMLFloat(xmlFile, subKey .. ".breeding#variationLitterSize")
                data.birthRate = getXMLFloat(xmlFile, subKey .. ".breeding#birthRate")
                data.femalePercentage = getXMLFloat(xmlFile, subKey .. ".breeding#femalePercentage")

                data.cleanDuration = getXMLInt(xmlFile, subKey .. ".livery#cleanDuration")
                data.liveryIncome = getXMLInt(xmlFile, subKey .. ".livery#income")
                data.trainingDifficulty = getXMLFloat(xmlFile, subKey .. ".livery#trainingDifficulty")

                data.isBird = isBird
                data.isSheep = isSheep

                animal.seasons = data
            end

            j = j + 1
        end

        i = i + 1
    end
end

function SeasonsAnimalsData:setDataPaths(paths)
    self.paths = paths
end

----------------------
-- Getters
----------------------
