----------------------------------------------------------------------------------------------------
-- SeasonsGrowthData
----------------------------------------------------------------------------------------------------
-- Purpose:  Growth data holder
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsGrowthData = {}

local SeasonsGrowthData_mt = Class(SeasonsGrowthData)

function SeasonsGrowthData:new(mission, environment, weather, fruitTypeManager)
    local self = setmetatable({}, SeasonsGrowthData_mt)

    self.mission = mission
    self.environment = environment
    self.weather = weather
    self.fruitTypeManager = fruitTypeManager
    self.paths = {}
    self.growth = {}
    self.defaultFruits = {}
    self.plantable = {}
    self.harvestable = {}
    self.cropRotation = {}
    self.isNewGame = true

    return self
end

function SeasonsGrowthData:delete()
    self.growth = nil
    self.defaultFruits = nil
    self.harvestable = nil
    self.plantable = nil
end

--loads data from files and builds the necessary tables related to growth
function SeasonsGrowthData:load()
    self:loadDataFromFiles()
    self:addCustomFruits()
    self:buildPlantableData()
    self:buildHarvestableData()
end

function SeasonsGrowthData:loadFromSavegame(xmlFile)
    self.isNewGame = false
end

--- loading functions for crops.xml

function SeasonsGrowthData:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("xml", path.file)
        if xmlFile then
            self:loadDataFromFile(xmlFile)
            delete(xmlFile)
        end
    end
end

function SeasonsGrowthData:loadDataFromFile(xmlFile)
    local overwriteGrowthData = Utils.getNoNil(getXMLBool(xmlFile, "crops.growth#overwrite"), false)
    self:loadDefaultFruitsData(xmlFile, overwriteGrowthData)
    self:loadGrowthData(xmlFile, overwriteGrowthData)
    self:loadRotationData(xmlFile)
end

function SeasonsGrowthData:setDataPaths(growthPaths)
    self.paths = growthPaths
end

function SeasonsGrowthData:loadDefaultFruitsData(xmlFile, overwriteData)
    if overwriteData == true then
        self.defaultFruits = {}
    end

    local defaultFruitsKey = "crops.growth.defaultCrops"

    if not hasXMLProperty(xmlFile, defaultFruitsKey) then
        Logging.error("SeasonsGrowthData:loadDefaultFruitsData: XML loading failed " .. defaultFruitsKey .. " not found")
        return
    end

    local i = 0
    while true do
        local defaultFruitKey = string.format("%s.defaultCrop(%i)#name", defaultFruitsKey, i)

        if not hasXMLProperty(xmlFile, defaultFruitKey) then
            break
        end

        local fruitName = (getXMLString(xmlFile, defaultFruitKey)):upper()
        if fruitName ~= nil then
            --local index = self.fruitTypeManager:getFruitTypeByName(fruitName).index
            self.defaultFruits[fruitName] = 1
        else
            Logging.error("SeasonsGrowthData:loadDefaultFruitsData: XML loading failed " .. xmlFile)
            return
        end

        i = i + 1
    end
end

function SeasonsGrowthData:loadGrowthData(xmlFile, overwriteData)
    local transitionsKey = "crops.growth.growthTransitions"

    if not hasXMLProperty(xmlFile, transitionsKey) then
        Logging.error("SeasonsGrowthData:loadGrowthData: XML loading failed transitionsKey" .. transitionsKey .. " not found")
        return
    end

    local i = 0

    while true do
        local transitionKey = string.format("%s.gt(%i)", transitionsKey, i)

        if not hasXMLProperty(xmlFile, transitionKey) then
            break
        end

        local transitionNumKey = transitionKey .. "#index"
        local transitionNum = getXMLString(xmlFile, transitionNumKey)

        if transitionNum == nil then
            Logging.error("SeasonsGrowthData:loadGrowthData: XML loading failed transitionNumKey:" .. transitionNumKey)
            return
        elseif transitionNum == "FIRST_LOAD_TRANSITION" then
            transitionNum = SeasonsGrowth.FIRST_LOAD_TRANSITION
        else
            transitionNum = tonumber(transitionNum)
        end

        --insert growth transition into datatable
        if self.growth[transitionNum] ~= nil then
            if overwriteData == true then
                self.growth[transitionNum] = {}
            end
        else
            table.insert(self.growth, transitionNum, {})
        end

        self:loadFruitsTransitionStates(transitionKey, xmlFile, transitionNum)

        i = i + 1
    end
end

function SeasonsGrowthData:loadFruitsTransitionStates(transitionKey, xmlFile, transitionNum)
    local i = 0

    while true do
        local fruitKey = string.format("%s.crop(%i)", transitionKey, i)

        if not hasXMLProperty(xmlFile, fruitKey) then
            break
        end

        local fruitName = (getXMLString(xmlFile, fruitKey .. "#name")):upper()
        if fruitName == nil then
            Logging.error("SeasonsGrowthData:loadFruitsTransitionStates: XML loading failed fruitKey" .. fruitKey .. " not found")
        end

        self.growth[transitionNum][fruitName] = {}
        local data = self.growth[transitionNum][fruitName]

        data.fruitName = fruitName
        data.incrementByOneMin, data.incrementByOneMax = self:loadRangeFromXML(xmlFile, fruitKey .. "#incrementByOneRange")
        data.setFromMin, data.setFromMax = self:loadRangeFromXML(xmlFile, fruitKey .. "#setRange")

        local setTo = getXMLString(xmlFile, fruitKey .. "#setTo")
        if setTo ~= nil then
            data.setTo = self:translateToState(setTo)
        end

        data.incrementByMin, data.incrementByMax = self:loadRangeFromXML(xmlFile, fruitKey .. "#incrementByRange")

        local incrementBy = getXMLInt(xmlFile, fruitKey .. "#incrementBy")
        if incrementBy ~= nil then
            data.incrementBy = incrementBy
        end

        local removeTransition = getXMLBool(xmlFile, fruitKey .. "#removeTransition")
        if removeTransition == true then
            data = nil
        end

        local event1 = getXMLString(xmlFile, fruitKey .. "#event1")
        if event1 ~= nil then
            data.event1 = self:translateToState(event1)
        end
        data.event1RangeMin, data.event1RangeMax = self:loadRangeFromXML(xmlFile, fruitKey .. "#event1Range")

        local event2 = getXMLString(xmlFile, fruitKey .. "#event2")
        if event2 ~= nil then
            data.event2 = self:translateToState(event2)
        end
        data.event2RangeMin, data.event2RangeMax = self:loadRangeFromXML(xmlFile, fruitKey .. "#event2Range")


        i = i + 1
    end

    return
end

local _states = {
    ["MAX"] = SeasonsGrowth.MAX_STATE,
    ["CUT"] = SeasonsGrowth.CUT,
    ["WITHERED"] = SeasonsGrowth.WITHERED,
    ["FAILED"] = SeasonsGrowth.GERMINATION_FAILED_STATE,
}

function SeasonsGrowthData:translateToState(input)
    if _states[input] ~= nil then
        return _states[input]
    end

    return tonumber(input)
end

function SeasonsGrowthData:getMinMax(input)
    local min
    local max
    local pos = 1

    for word in input:gmatch("%w+") do
        word = self:translateToState(word)

        if pos == 1 then
            min = word
        elseif pos == 2 then
            max = word
        else
            Logging.error("SeasonsGrowthData: Incorrect format in growth file range: " .. input)
            return nil, nil
        end

        pos = pos + 1
    end

    return min, max
end

function SeasonsGrowthData:loadRangeFromXML(file, rangeKey)
    local range = getXMLString(file, rangeKey)

    if range ~= nil then
        return self:getMinMax(range)
    end

    return nil, nil
end

-----------------------------------
-- check for new fruits and update
-----------------------------------

function SeasonsGrowthData:addCustomFruits()
    for index, fruit in pairs(self.mission.fruits) do
        local fruitType = self.fruitTypeManager:getFruitTypeByIndex(index)
        local fruitName = fruitType.name

        if self.defaultFruits[fruitName] == nil then -- new fruit found
            -- Logging.info("Growth New fruit found: %s", fruitName)
            self:updateDefaultFruitsWithNewFruit(fruitName)
            self:updateGrowthWithNewFruit(fruitName)
            self:updateFruitTypesDataWithNewFruit(fruitName)
        end
    end
end

function SeasonsGrowthData:updateGrowthWithNewFruit(fruitName)
    for transition, fruit in pairs(self.growth) do
        if self.growth[transition][SeasonsGrowth.UNKNOWN_FRUIT_COPY_SOURCE] ~= nil then
            self.growth[transition][fruitName] = ListUtil.copyTable(self.growth[transition][SeasonsGrowth.UNKNOWN_FRUIT_COPY_SOURCE])
            self.growth[transition][fruitName].fruitName = fruitName
        end
    end
end

function SeasonsGrowthData:updateDefaultFruitsWithNewFruit(fruitName)
    self.defaultFruits[fruitName] = self.defaultFruits[SeasonsGrowth.UNKNOWN_FRUIT_COPY_SOURCE]
end

function SeasonsGrowthData:updateFruitTypesDataWithNewFruit(fruitName)
    local fruitType = self.fruitTypeManager:getFruitTypeByName(fruitName)
    local fruitTypeTemplate = self.fruitTypeManager:getFruitTypeByName(SeasonsGrowth.UNKNOWN_FRUIT_COPY_SOURCE)

    fruitType.germinateTemp = fruitTypeTemplate.germinateTemp
    fruitType.germinatesoilMoisture = fruitTypeTemplate.germinatesoilMoisture
    fruitType.maxFertiliseState = fruitTypeTemplate.maxFertiliseState
    fruitType.seedDamageState = SeasonsGrowth.GERMINATION_FAILED_STATE

    if fruitType.index == FruitType.WEED then --TODO magic values
        fruitType.youngPlantDamageState = 4
        fruitType.maturePlantDamageState = 5
        fruitType.weedWitherSoilTemp = 1
        fruitType.weedMatureSoilTemp = 10
    else
        fruitType.youngPlantDamageState = fruitTypeTemplate.youngPlantDamageState
        fruitType.maturePlantDamageState = fruitTypeTemplate.maturePlantDamageState
    end

    fruitType.youngPlantMaxState = fruitTypeTemplate.youngPlantMaxState
    fruitType.maturePlantMinState = fruitTypeTemplate.maturePlantMinState

    fruitType.seedDroughtResistanceFactor = fruitTypeTemplate.seedDroughtResistanceFactor
    fruitType.youngPlantDroughtResistanceFactor = fruitTypeTemplate.youngPlantDroughtResistanceFactor
    fruitType.maturePlantDroughtResistanceFactor = fruitTypeTemplate.maturePlantDroughtResistanceFactor
    fruitType.seedFrostResistanceFactor = fruitTypeTemplate.seedFrostResistanceFactor
    fruitType.youngPlantFrostResistanceFactor = fruitTypeTemplate.youngPlantFrostResistanceFactor
    fruitType.maturePlantFrostResistanceFactor = fruitTypeTemplate.maturePlantFrostResistanceFactor

    fruitType.rotation = {}
    fruitType.rotation.category = SeasonsCropRotation.CATEGORIES.CEREAL
    fruitType.rotation.returnPeriod = 1
end

-----------------------------------
--germinate data functions
-----------------------------------

function SeasonsGrowthData:buildGerminationData(soilTempMax, soilMoistureMax)
    local germinationData = {}
    --TODO: implement soilMoistureMax in the future maybe
    if soilTempMax == nil then -- if not passed in, then use today's soil temp max
        soilTempMax = self.weather.soilTempMax
    end

    for index, fruit in pairs(self.mission.fruits) do
        local fruitName = self.fruitTypeManager:getFruitTypeByIndex(index).name
        if fruitName ~= "DRYGRASS" then
            germinationData[fruitName] = self:canSow(fruitName, soilTempMax)
        end
    end

    return germinationData
end

function SeasonsGrowthData:getGerminationTemperature(fruitName)
    return Utils.getNoNil(self.fruitTypeManager:getFruitTypeByName(fruitName).germinateTemp, self.fruitTypeManager:getFruitTypeByName(SeasonsGrowth.UNKNOWN_FRUIT_COPY_SOURCE).germinateTemp)
end

function SeasonsGrowthData:getGerminationSoilMoisture(fruitName)
    return Utils.getNoNil(self.fruitTypeManager:getFruitTypeByName(fruitName).germinatesoilMoisture, self.fruitTypeManager:getFruitTypeByName(SeasonsGrowth.UNKNOWN_FRUIT_COPY_SOURCE).germinatesoilMoisture)
end

-- On server this uses the max temp.
-- Otherwise, returns nil
function SeasonsGrowthData:canSow(fruitName, soilTempMax)
    if self.mission:getIsServer() then --this will be redundant since the check is done by functions calling this
        return soilTempMax >= self:getGerminationTemperature(fruitName)
    else
        return nil
    end
end

--- build plantable data
function SeasonsGrowthData:buildPlantableData()
    local tooColdTransitions = self.weather:getLowSoilTemperature()

    for fruitName, value in pairs(self.defaultFruits) do
        local fruitType = self.fruitTypeManager:getFruitTypeByName(fruitName)

        if fruitType ~= nil and fruitName ~= "DRYGRASS" and fruitName ~= "WEED" then
            local transitionTable = {}

            local germTemp = self:getGerminationTemperature(fruitName)
            local fruitNumStates = fruitType.numGrowthStates --FruitUtil.fruitTypeGrowths[fruitName].numGrowthStates

            for transition, v in pairs(self.growth) do
                if transition == SeasonsGrowth.FIRST_LOAD_TRANSITION then
                    break
                end

                if tooColdTransitions[transition] < germTemp - 1 then
                    table.insert(transitionTable, transition, false)
                else
                    local plantedTransition = transition
                    local currentGrowthState = 1
                    local maxAllowedCounter = 0
                    local transitionToCheck = plantedTransition + 1 -- need to start checking from the next transition after planted transition

                    while currentGrowthState < fruitNumStates and maxAllowedCounter < SeasonsGrowth.MAX_ALLOWABLE_GROWTH_PERIOD do
                        if transitionToCheck > self.environment.PERIODS_IN_YEAR then transitionToCheck = 1 end

                        currentGrowthState = self:simulateGrowth(fruitName, transitionToCheck, currentGrowthState)
                        if currentGrowthState >= fruitNumStates then -- have to break or transitionToCheck will be incremented when it does not have to be
                            break
                        end

                        transitionToCheck = transitionToCheck + 1
                        maxAllowedCounter = maxAllowedCounter + 1
                    end

                    table.insert(transitionTable, plantedTransition, currentGrowthState == fruitNumStates)
                end
            end

            self.plantable[fruitName] = transitionTable
        end
    end
end

-- simulate growth helper function to calculate the next growth state based on current growth state and the current transition
function SeasonsGrowthData:simulateGrowth(fruitName, transitionToCheck, currentGrowthState)
    local newGrowthState = currentGrowthState

    if transitionToCheck > 12 then
        transitionToCheck = transitionToCheck - 12
    end

    local data = self.growth[transitionToCheck][fruitName]

    if data ~= nil then
        if data.setFromMin ~= nil
            and data.setTo ~= nil then
            if data.setFromMax ~= nil then
                if currentGrowthState >= data.setFromMin and currentGrowthState <= data.setFromMax then
                    newGrowthState = data.setTo
                end
            else
                if currentGrowthState == data.setFromMin then
                    newGrowthState = data.setTo
                end
            end
        end

        if data.incrementByMin ~= nil
                and data.incrementByMax ~= nil
                and data.incrementBy ~= nil then
            local incrementByMin = data.incrementByMin
            local incrementByMax = data.incrementByMax

            if currentGrowthState >= incrementByMin and currentGrowthState <= incrementByMax then
                newGrowthState = newGrowthState + data.incrementBy
            end

        end

       if data.incrementByOneMin ~= nil then
            local incrementByOneMin = data.incrementByOneMin
            if data.incrementByOneMax ~= nil then
                local incrementByOneMax = data.incrementByOneMax
                if currentGrowthState >= incrementByOneMin and currentGrowthState <= incrementByOneMax then
                    newGrowthState = newGrowthState + 1
                end
            else
                if currentGrowthState == incrementByOneMin then
                    newGrowthState = newGrowthState + 1
                end
            end
        end
    end

    return newGrowthState
end

-----------------------------------
-- harvestable data functions
-----------------------------------

function SeasonsGrowthData:buildHarvestableData()
    for fruitName, transition in pairs(self.plantable) do
        local fruitType = self.fruitTypeManager:getFruitTypeByName(fruitName)
        if fruitType ~= nil then
            local transitionTable = {}

            local plantedTransition = 1
            local fruitNumStates = fruitType.numGrowthStates

            local skipFruit = fruitName == "POPLAR" --or fruitName == "grass"

            for plantedTransition = 1, SeasonsGrowth.MAX_ALLOWABLE_GROWTH_PERIOD do
                if self.plantable[fruitName][plantedTransition] == true and not skipFruit then
                    local growthState = 1
                    local transitionToCheck = plantedTransition + 1

                    if plantedTransition > 12 then
                        transitionToCheck = transitionToCheck - 12
                    end

                    if transitionToCheck == 12 then
                        transitionToCheck = 1
                    end

                    local safetyCheck = 1

                    while growthState <= fruitNumStates do
                        growthState = self:simulateGrowth(fruitName, transitionToCheck, growthState)
                        if growthState == fruitNumStates or (growthState >= fruitType.minHarvestingGrowthState + 1 and growthState <= fruitType.maxHarvestingGrowthState + 1) then
                            transitionTable[transitionToCheck] = true
                        end

                        transitionToCheck = transitionToCheck + 1
                        safetyCheck = safetyCheck + 1
                        if transitionToCheck > self.environment.PERIODS_IN_YEAR then transitionToCheck = 1 end
                        if safetyCheck > SeasonsGrowth.MAX_ALLOWABLE_GROWTH_PERIOD then break end --so we don't end up in infinite loop if growth pattern is not correct
                    end
                end
            end

            --fill in the gaps
            for plantedTransition = 1, SeasonsGrowth.MAX_ALLOWABLE_GROWTH_PERIOD do
                if fruitName == "POPLAR" then --hardcoding for poplar. No withering
                    transitionTable[plantedTransition] = true
                elseif transitionTable[plantedTransition] ~= true then
                    transitionTable[plantedTransition] = false
                end
            end

            self.harvestable[fruitName] = transitionTable
        end
    end
end

function SeasonsGrowthData:getHarvestable()
    return self.harvestable
end

function SeasonsGrowthData:getPlantable()
    return self.plantable
end

function SeasonsGrowthData:canFruitBePlanted(fruitName, period)
    if self.plantable[fruitName][period] ~= nil then
        return self.plantable[fruitName][period]
    else
        return false
    end
end

function SeasonsGrowthData:canFruitBeHarvested(fruitName, period)
    if self.harvestable[fruitName][period] ~= nil then
        return self.harvestable[fruitName][period]
    else
        return false
    end
end

-----------------------------------
-- crop rotation
-----------------------------------

function SeasonsGrowthData:loadRotationData(xmlFile)
    local i = 0
    while true do
        local key = string.format("crops.cropRotation.crop(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local category = getXMLString(xmlFile, key .. "#category")
        local categoryId = SeasonsCropRotation.CATEGORIES[category]
        if categoryId ~= nil then
            local rotations = {}

            local j = 0
            while true do
                local rotationKey = string.format("%s.rotation(%d)", key, j)
                if not hasXMLProperty(xmlFile, rotationKey) then
                    break
                end

                local cat = getXMLString(xmlFile, rotationKey .. "#category")
                if SeasonsCropRotation.CATEGORIES[cat] ~= nil then
                    rotations[SeasonsCropRotation.CATEGORIES[cat]] = Utils.getNoNil(getXMLInt(xmlFile, rotationKey .. "#value"), 1)
                end

                j = j + 1
            end

            self.cropRotation[categoryId] = rotations
        end

        i = i + 1
    end
end

function SeasonsGrowthData:getRotationCategoryValue(n, current)
    if n == SeasonsCropRotation.CATEGORIES.FALLOW then
        return 2
    end

    return self.cropRotation[current][n]
end
