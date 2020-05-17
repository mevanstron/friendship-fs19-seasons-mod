----------------------------------------------------------------------------------------------------
-- SeasonsAnimals
----------------------------------------------------------------------------------------------------
-- Purpose:  Animal changes
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsAnimals = {}

local SeasonsAnimals_mt = Class(SeasonsAnimals)

SeasonsAnimals.PRODUCTIVITY_START = 0.8
SeasonsAnimals.WATER_MIN_LEVEL = 0.1
SeasonsAnimals.WATER_TEMP_LIMIT = 10
SeasonsAnimals.STRAW_TEMP_LIMIT = 0
SeasonsAnimals.HEN_PER_ROOSTER = 8
SeasonsAnimals.DEAD_HORSE_PAYMENT = 10000
SeasonsAnimals.INITIAL_FITNESS_SCALE = 0.7
SeasonsAnimals.INITIAL_FITNESS_VAR = 0.2
SeasonsAnimals.MINIMUM_GESTATION_HEALTH = 0.2
SeasonsAnimals.COW_LACTATING_DURATION = 300

-- TODO store these in XML for extendability
SeasonsAnimals.MATURE_GROWTH_FACTOR = {
    COW = 0.002,
    SHEEP = 0.006,
    PIG = 0.001,
    CHICKEN = 0.01,
    HORSE = 0,
    DEFAULT = 0.003,
}
SeasonsAnimals.DEATH_FACTORS = {
    COW = 0.15, -- can live approx 4 weeks without food
    SHEEP = 0.1, -- can probably live longer than cows without food
    PIG = 0.25, -- can live approx 2 weeks without food
    CHICKEN = 0.4, -- shortlived without food
    -- Horse has own health bar
}

SeasonsAnimals.AGE_CLASSIFIER = {
    NEWBORN = 1,
    YOUNG = 2,
    MATURE = 3,
    OLD = 4,
}

function SeasonsAnimals.onMissionWillLoad()
    SeasonsModUtil.overwrittenFunction(AnimalManager,       "loadAnimals",      SeasonsAnimals.inj_animalManager_loadAnimals)
    SeasonsModUtil.overwrittenFunction(AnimalFoodManager,   "loadFoodGroups",   SeasonsAnimals.inj_animalFoodManager_loadFoodGroups)
    SeasonsModUtil.overwrittenFunction(AnimalFoodManager,   "loadMixtures",     SeasonsAnimals.inj_animalFoodManager_loadMixtures)
end

function SeasonsAnimals:new(mission, animalManager, animalFoodManager, messageCenter, environment, weather, i18n, fruitTypeManager)
    local self = setmetatable({}, SeasonsAnimals_mt)

    self.mission = mission
    self.animalManager = animalManager
    self.animalFoodManager = animalFoodManager
    self.messageCenter = messageCenter
    self.environment = environment
    self.weather = weather
    self.i18n = i18n
    self.isServer = mission:getIsServer()

    self.data = SeasonsAnimalsData:new(animalManager)
    self.grazing = SeasonsGrazing:new(mission, fruitTypeManager)
    self.ui = SeasonsAnimalsUI:new(mission, i18n)

    -- List of new IDs for animals per filltype
    self.animalIds = {}

    SeasonsModUtil.appendedFunction(Animal,                         "loadFromXMLFile",                  self.inj_animal_loadFromXMLFile)
    SeasonsModUtil.appendedFunction(Animal,                         "readStream",                       self.inj_animal_readStream)
    SeasonsModUtil.appendedFunction(Animal,                         "readUpdateStream",                 self.inj_animal_readUpdateStream)
    SeasonsModUtil.appendedFunction(Animal,                         "saveToXMLFile",                    self.inj_animal_saveToXMLFile)
    SeasonsModUtil.appendedFunction(Animal,                         "writeStream",                      self.inj_animal_writeStream)
    SeasonsModUtil.appendedFunction(Animal,                         "writeUpdateStream",                self.inj_animal_writeUpdateStream)
    SeasonsModUtil.appendedFunction(AnimalHusbandry,                "readStream",                       self.inj_animalHusbandry_readStream)
    SeasonsModUtil.appendedFunction(AnimalHusbandry,                "saveToXMLFile",                    self.inj_animalHusbandry_saveToXMLFile)
    SeasonsModUtil.appendedFunction(AnimalHusbandry,                "writeStream",                      self.inj_animalHusbandry_writeStream)
    SeasonsModUtil.appendedFunction(HusbandryModuleAnimal,          "updateAnimalParameters",           self.inj_husbandryModuleAnimals_updateAnimalParameters)
    SeasonsModUtil.appendedFunction(HusbandryModuleWater,           "delete",                           self.inj_husbandryModuleWater_delete)
    SeasonsModUtil.appendedFunction(HusbandryModuleWater,           "onIntervalUpdate",                 self.inj_husbandryModuleWater_onIntervalUpdate)
    SeasonsModUtil.overwrittenConstant(Animal,                      "setWeight",                        self.inj_animal_setWeight)
    SeasonsModUtil.overwrittenConstant(Horse,                       "getDayReward",                     self.inj_horse_getDayReward)
    SeasonsModUtil.overwrittenConstant(HusbandryModuleAnimal,       "HEALTH_DECREASE_AT_INTERVAL",      -0.0075) -- -0.0075
    SeasonsModUtil.overwrittenConstant(HusbandryModuleAnimal,       "HEALTH_DECREASE_FOR_PRODUCTION",    0.015) -- 0.015
    SeasonsModUtil.overwrittenConstant(HusbandryModuleAnimal,       "TROUGH_CAPACITY",                  2) -- 10
    SeasonsModUtil.overwrittenFunction(Animal,                      "getAgeClassifier",                 self.inj_animal_getAgeClassifier)
    SeasonsModUtil.overwrittenFunction(Animal,                      "getName",                          self.inj_animal_getName)
    SeasonsModUtil.overwrittenFunction(Animal,                      "getValue",                         self.inj_animal_getValue)
    SeasonsModUtil.overwrittenFunction(Animal,                      "getWeightWithUnborn",              self.inj_animal_getWeightWithUnborn)
    SeasonsModUtil.overwrittenFunction(Animal,                      "new",                              self.inj_animal_new)
    SeasonsModUtil.overwrittenFunction(Animal,                      "startGestation",                   self.inj_animal_startGestation)
    SeasonsModUtil.overwrittenFunction(AnimalHusbandry,             "getGlobalProductionFactor",        self.inj_animalHusbandry_getGlobalProductionFactor)
    SeasonsModUtil.overwrittenFunction(AnimalHusbandry,             "loadFromXMLFile",                  self.inj_animalHusbandry_loadFromXMLFile)
    SeasonsModUtil.overwrittenFunction(AnimalHusbandry,             "seasons_getCondition",             self.inj_animalHusbandry_getCondition)
    SeasonsModUtil.overwrittenFunction(AnimalHusbandry,             "updateGlobalProductionFactor",     self.inj_animalHusbandry_updateGlobalProductionFactor)
    SeasonsModUtil.overwrittenFunction(Horse,                       "new",                              self.inj_horse_new)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleAnimal,       "addSingleAnimal",                  self.inj_husbandryModuleAnimal_addSingleAnimal)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleAnimal,       "hasMaleAnimal",                    self.inj_husbandryModuleAnimal_hasMaleAnimal)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleAnimal,       "load",                             self.inj_husbandryModuleAnimal_load)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleAnimal,       "removeSingleAnimal",               self.inj_husbandryModuleAnimal_removeSingleAnimal)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleAnimal,       "updateBreeding",                   self.inj_husbandryModuleAnimal_updateBreeding)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleAnimal,       "updateHealth",                     self.inj_husbandryModuleAnimal_updateHealth)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleFood,         "setCapacity",                      self.inj_husbandryModuleFood_setCapacity)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleLiquidManure, "loadFromXMLFile",                  self.inj_husbandryModuleLiquidManure_loadFromXMLFile)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleLiquidManure, "onFillProgressChanged",            self.inj_husbandryModuleLiquidManure_onFillProgressChanged)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleLiquidManure, "onIntervalUpdate",                 self.inj_husbandryModuleLiquidManure_onIntervalUpdate)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleLiquidManure, "updateFillPlane",                  self.inj_husbandryModuleLiquidManure_updateFillPlane)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleMilk,         "onIntervalUpdate",                 self.inj_husbandryModuleMilk_onIntervalUpdate)
    SeasonsModUtil.overwrittenFunction(HusbandryModulePallets,      "onIntervalUpdate",                 self.inj_husbandryModulePallets_onIntervalUpdate)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleWater,        "finalizePlacement",                self.inj_husbandryModuleWater_finalizePlacement)
    SeasonsModUtil.overwrittenFunction(HusbandryModuleWater,        "load",                             self.inj_husbandryModuleWater_load)
    SeasonsModUtil.overwrittenFunction(UnloadTrigger,               "updateBales",                      self.inj_unloadTrigger_updateBales)
    SeasonsModUtil.overwrittenStaticFunction(Animal,                "createFromFillType",               self.inj_animal_createFromFillType)
    SeasonsModUtil.prependedFunction(HusbandryModuleAnimal,         "onDayChanged",                     self.inj_husbandryModuleAnimal_onDayChanged)

    return self
end

function SeasonsAnimals:delete()
    self.ui:delete()
    self.data:delete()
    self.grazing:delete()

    self.messageCenter:unsubscribeAll(self)
end

function SeasonsAnimals:load()
    self.data:load()
    self.grazing:load()
    self.ui:load()

    self.messageCenter:subscribe(SeasonsMessageType.HOUR_CHANGED_FIX, self.onHourChanged, self)
    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)

    self:setUpStore()
end

function SeasonsAnimals:onTerrainLoaded()
    self.grazing:onTerrainLoaded()
end

function SeasonsAnimals:onGameLoaded()
    self:adjustAnimalAttributes()
end

function SeasonsAnimals:setDataPaths(paths)
    self.data:setDataPaths(paths)
end

---Load the list of next ids for animal ids
function SeasonsAnimals:loadFromSavegame(xmlFile)
    local i = 0
    while true do
        local key = string.format("seasons.animals.identifiers.type(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local name = getXMLString(xmlFile, key .. "#name")
        local nextId = getXMLInt(xmlFile, key .. "#next")

        if name ~= nil and nextId ~= nil then
            self.animalIds[name] = nextId
        end

        i = i + 1
    end
end

---Save the next id for custom animal identifiers
function SeasonsAnimals:saveToSavegame(xmlFile)
    local i = 0
    for name, nextId in pairs(self.animalIds) do
        local key = string.format("seasons.animals.identifiers.type(%d)", i)

        setXMLString(xmlFile, key .. "#name", name)
        setXMLInt(xmlFile, key .. "#next", nextId)

        i = i + 1
    end
end

---Early load store values for initial animal setup
-- The store needs valid values when the game loads for the new Animal objects.
function SeasonsAnimals:setUpStore()
    for _, animalType in ipairs(self.animalManager:getAnimals()) do
        for _, animal in ipairs(animalType.subTypes) do
            self:updateStoreInfo(animalType, animal, animal.seasons)
        end
    end
end

---Adjust all animal properties based on time of the year.
function SeasonsAnimals:adjustAnimalAttributes()
    local factorAnnual = 1 / (self.environment.daysPerSeason * 4) -- when values are for a year
    local factorDaily = 365 * factorAnnual -- when values are for a day

    local day = self.environment.currentDay
    local dayForecast = ListUtil.copyTable(self.weather.forecast:getForecastForDay(day))
    local averageTemp = (dayForecast.lowTemp * 15 + dayForecast.highTemp * 9) / 24

    for _, animalType in ipairs(self.animalManager:getAnimals()) do
        for _, animal in ipairs(animalType.subTypes) do
            local data = animal.seasons
            if data == nil then
                Logging.error("No Seasons data for animal type %s", animalType.type)
                data = {}
            end

            -- Distinguishes chicken
            animal.isBird = Utils.getNoNil(data.isBird, false)
            animal.isSheep = Utils.getNoNil(data.isSheep, false)

            animal.breeding.birthRatePerDay = Utils.getNoNil(data.birthRate, 0) * factorAnnual
            animal.breeding.fertileAge = Utils.getNoNil(data.fertileAge, 1)
            animal.breeding.gestationPeriod = Utils.getNoNil(data.gestationPeriod, 1)
            animal.breeding.gestationInterval = Utils.getNoNil(data.gestationInterval, 0)
            animal.breeding.averageLitterSize = Utils.getNoNil(data.averageLitterSize, 1)
            animal.breeding.variationLitterSize = Utils.getNoNil(data.variationLitterSize, 1)
            animal.breeding.femalePercentage = Utils.getNoNil(data.femalePercentage, 0.5)

            animal.input.strawPerDay = Utils.getNoNil(data.straw, 0) * factorAnnual * self:getStrawFactor(averageTemp)
            animal.input.waterPerDay = Utils.getNoNil(data.water, 0) * factorDaily * self:getWaterFactor(averageTemp)
            animal.input.foodPerDay = Utils.getNoNil(data.food, 0) * factorDaily --foodPerDay is now feed needed as a fraction of bodyweight

            if animal.growth == nil then
                animal.growth = {}
            end

            animal.growth.bornWeight = Utils.getNoNil(data.bornWeight, 0)

            animal.growth.gainBorn = Utils.getNoNil(data.gainBorn, 0)
            animal.growth.gainPeakMale = Utils.getNoNil(data.gainPeakMale, 0)
            animal.growth.gainPeakFemale = Utils.getNoNil(data.gainPeakFemale, 0)
            animal.growth.daysPeak = Utils.getNoNil(data.daysPeak, 0)
            animal.growth.gainLevel = Utils.getNoNil(data.gainLevel, 0)
            animal.growth.daysLevel = Utils.getNoNil(data.daysLevel, 0)
            animal.growth.maxAge = Utils.getNoNil(data.maxAge, 0)

            animal.output.milkPerDay = Utils.getNoNil(data.milk, 0) * factorDaily
            animal.output.palletsPerDay = Utils.getNoNil(data.pallets, 0) * factorAnnual
            animal.output.manurePerDay = Utils.getNoNil(data.manure, 0) * factorDaily
            animal.output.liquidManurePerDay = Utils.getNoNil(data.liquidManure, 0) * factorDaily
            animal.output.foodSpillagePerDay = Utils.getNoNil(data.foodSpillage, 0) * animal.input.foodPerDay

            if animal.livery == nil then
                animal.livery = {}
            end

            animal.livery.income = Utils.getNoNil(data.liveryIncome, 0) * factorAnnual
            animal.livery.trainingDifficulty = math.max(Utils.getNoNil(data.trainingDifficulty, 1), 0)
            animal.dirt.cleanDuration = Utils.getNoNil(data.cleanDuration, 500)

            self:updateStoreInfo(animalType, animal, data)
        end
    end

    for  _, husbandry in pairs(self.mission.husbandries) do
        local animalModule = husbandry:getModuleByName("animals")
        if animalModule ~= nil then
            animalModule:updateAnimalParameters()
        end
    end
end

---Update the animal store info. This has to be done earlier than the attributes.
function SeasonsAnimals:updateStoreInfo(animalType, subType, data)
    -- If no data is defined at all, put some default values in.
    if data == nil then
        Logging.error("No Seasons data for animal type %s", animalType.type)
        data = {}
    end

    -- TODO: this would override the economy changes? maybe?
    subType.storeInfo.sellPrice = Utils.getNoNil(data.sellPrice, 0)
    subType.storeInfo.transportPrice = Utils.getNoNil(data.transportPrice, 0)

    subType.storeInfo.buyWeight = Utils.getNoNil(data.buyWeight, 0)
    subType.storeInfo.buyIsFemale = Utils.getNoNil(data.buyIsFemale, false)
    subType.storeInfo.buyAge = Utils.getNoNil(data.buyAge, 0) / 365 -- provided in days
    subType.storeInfo.transportPrice = Utils.getNoNil(data.transportPrice, 0)

    subType.storeInfo.baseSellPrice = Utils.getNoNil(data.baseSellPrice, 0)
    subType.storeInfo.pricePerKg = Utils.getNoNil(data.pricePerKg, 0)
    subType.storeInfo.priceDropAge = Utils.getNoNil(data.priceDropAge, 0)

    subType.storeInfo.buyPrice = (subType.storeInfo.baseSellPrice + subType.storeInfo.pricePerKg * subType.storeInfo.buyWeight) * Utils.getNoNil(data.buyPrice, 1)
end

---Get the factors defining how quick animals die without food
function SeasonsAnimals:getDeathFactors()
    return SeasonsAnimals.DEATH_FACTORS, 0.1
end

function SeasonsAnimals:getAverageFactors()
    local strawFactor = 0
    local waterFactor = 0

    for period = 1, self.environment.PERIODS_IN_YEAR do
        local averageTemp = self.weather.model:calculateAveragePeriodTemp(period, true)

        strawFactor = strawFactor + self:getStrawFactor(averageTemp)
        waterFactor = waterFactor + self:getWaterFactor(averageTemp)
    end

    return strawFactor / 12, waterFactor / 12
end

-- higher straw demand for temperatures below the limit
function SeasonsAnimals:getStrawFactor(temp)
    return math.max(1.1^((temp - self.STRAW_TEMP_LIMIT) / 5), 1)
end

-- higher water need for temperatures above the limit
function SeasonsAnimals:getWaterFactor(temp)
    return math.max(1.05^((self.WATER_TEMP_LIMIT - temp) / 5), 1)
end

---Returns scaling factor for milk production for lactating cows
---input is real life days since birth
function SeasonsAnimals:calculateUnitMilkProduction(days)
    if days < 0 or days > SeasonsAnimals.COW_LACTATING_DURATION then
        return 0
    else
        return 6.083e-8 * days^3 - 5.094e-5 * days^2 + 9.424e-3 * days + 5.028e-1
    end
end

---Cause death for animals that are not cared for
-- TODO: notifications per farm only, and send over MP
function SeasonsAnimals:applyDeath()
    local factors, generic = self:getDeathFactors()
    local numKilled = {}
    local seasonLengthFactor = 6 / self.environment.daysPerSeason

    for  _, husbandry in pairs(self.mission.husbandries) do
        local animalType = husbandry:getAnimalType()
        if animalType ~= nil then
            local factor = Utils.getNoNil(factors[animalType], generic)

            local farmId = husbandry:getOwnerFarmId()
            if numKilled[farmId] == nil then
                numKilled[farmId] = 0
            end

            -- If an animal does not need food, skip killing it
            local foodModule = husbandry:getModuleByName("food")
            if foodModule ~= nil and foodModule.singleAnimalUsagePerDay > 0 then
                numKilled[farmId] = numKilled[farmId] + self:killAnimals(husbandry, factor * seasonLengthFactor)
            end
        end
    end

    for farmId, num in pairs(numKilled) do
        -- TODO should be at clients too
        if num > 0 then
            if self.mission.accessHandler:canFarmAccessOtherId(self.mission:getFarmId(), farmId) then
                self.mission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, string.format(self.i18n:getText("seasons_notification_animalsKilled"), num))
            end
        end
    end
end

---Kill animals with given chance in husbandry
function SeasonsAnimals:killAnimals(husbandry, p)
    local animalModule = husbandry:getModuleByName("animals") -- assume it exists

    if not self:areAnimalsCaredFor(husbandry) then
        local animalsToKill = math.ceil(p * #animalModule.animals)
        if animalsToKill > 0 then
            local killedAnimals = 0
            local animalsTried = 0 -- Infinite loop prevention when no killable animals are in a pen

            -- Kill individual animals
            while killedAnimals < animalsToKill and animalsTried < animalsToKill * 2 do
                local animal = ListUtil.getRandomElement(animalModule.animals)
                if animal == nil then
                    break
                end

                -- Ignore animals with their own health bar
                if animal.getHealthScale == nil then
                    self:killAnimal(husbandry, animal)

                    killedAnimals = killedAnimals + 1
                end

                animalsTried = animalsTried + 1
            end

            return killedAnimals
        end
    end

    return 0
end

function SeasonsAnimals:killAnimal(husbandry, animal)
    local animalModule = husbandry:getModuleByName("animals") -- assume it exists

    -- Remove any rideable first
    if animal.deactivateRiding ~= nil then
        animal:deactivateRiding(false)
    end

    animalModule:removeSingleAnimal(animal, false, true)
end

---Get whether the animals in given husbandry are cared for
function SeasonsAnimals:areAnimalsCaredFor(husbandry)
    local foodModule = husbandry:getModuleByName("food")

    local hasWater, hasFood = husbandry:hasWater(), foodModule == nil or foodModule:getFoodFactor() ~= 0
    if hasWater and hasFood then
        return true
    end

    return false
end

function SeasonsAnimals:updateAverageProductivity()
    for _, husbandry in pairs(self.mission.husbandries) do
        local averageProductivity = husbandry.averageGlobalProductionFactor
        local productivity = husbandry.globalProductionFactor

        local reductionFactor = 0.1
        local seasonFactor = g_seasons.environment.daysPerSeason * 24

        -- Only update when there are animals. Otherwise the husbandry average production will reach zero before a player adds animals
        local animalModule = husbandry:getModuleByName("animals")
        if animalModule ~= nil and #animalModule.animals > 0 then
            if productivity < 0.75 and productivity < averageProductivity then
                seasonFactor = seasonFactor * reductionFactor
            end

            husbandry.averageGlobalProductionFactor = MathUtil.clamp(averageProductivity * (seasonFactor - 1) / seasonFactor + productivity / seasonFactor, 0.01, 1)
        end
    end
end

---Update age of all animals for given interval (in days)
function SeasonsAnimals:updateAnimalAge(interval)
    local addedAge = 1 / (interval * 4 * self.environment.daysPerSeason)

    for  _, husbandry in pairs(self.mission.husbandries) do
        local animalsModule = husbandry:getModuleByName("animals")

        for _, animal in pairs(animalsModule.animals) do
            animal.seasons_age = animal.seasons_age + addedAge
        end

        if animalsModule.animalsToAdd ~= nil then
            for _, animal in pairs(animalsModule.animalsToAdd) do
                animal.seasons_age = animal.seasons_age + addedAge
            end
        end
    end
end

-- calculate gain dependent on animal age, gender and type
function SeasonsAnimals:calculateGain(animal, age, b0)
    local days = age * 365

    local subType = animal.subType
    local growthInfo = subType.growth
    local gainPeak = growthInfo.gainPeakMale
    local daysPeak = growthInfo.daysPeak
    local daysLevel = growthInfo.daysLevel
    local gainStart = growthInfo.gainBorn
    local gainLevel = growthInfo.gainLevel

    -- adjust growth for females
    if animal.seasons_isFemale and gainPeak ~= 0 then -- check for 0 because divison will cause NaN instead of no-update
        local gainPeakMale = gainPeak
        gainPeak = growthInfo.gainPeakFemale

        daysPeak = daysPeak * gainPeak / gainPeakMale

        daysLevel = daysLevel * gainPeak / gainPeakMale
    end

    if days <= daysPeak then
        local a2 = (gainStart - gainPeak) / daysPeak^2
        local a1 = -2 * a2 * daysPeak
        local a0 = gainStart

        return a2 * days^2 + a1 * days + a0
    elseif days > daysPeak and days <= daysLevel then
        local a2 = (gainLevel - gainPeak) / (daysLevel^2 - 2 * daysLevel * daysPeak + daysPeak^2)
        local a1 = -2 * a2 * daysPeak
        local a0 = a2 * daysPeak^2 + gainPeak

        return a2 * days^2 + a1 * days + a0
    else
        local b1 = gainLevel

        return b1 * math.exp(-1 * b0 * (days - daysLevel))
    end
end

-- update weight for all animals
function SeasonsAnimals:updateWeight()
    local timeFactor = 365 / (4 * self.environment.daysPerSeason)

    for  _, husbandry in pairs(self.mission.husbandries) do
        local productivity = husbandry.averageGlobalProductionFactor
        local animalsModule = husbandry:getModuleByName("animals")
        local animalType = husbandry:getAnimalType()

        for _, animal in pairs(animalsModule.animals) do
            local growthFactor = SeasonsAnimals.MATURE_GROWTH_FACTOR[animalType]
            if growthFactor == nil then
                growthFactor = SeasonsAnimals.MATURE_GROWTH_FACTOR.DEFAULT
            end
            local gain = self:calculateGain(animal, animal.seasons_age, growthFactor) * productivity * timeFactor
            animal.seasons_weight = animal.seasons_weight + gain
        end
    end
end

-- calculates the needed feed for one year for a husbandry
function SeasonsAnimals:calculateAnnualFeedAmount(husbandry)
    local annualFeedAmount = 0

    local productivity = husbandry.averageGlobalProductionFactor
    local animalsModule = husbandry:getModuleByName("animals")
    local animalType = husbandry:getAnimalType()

    -- It does not actually matter (significantly) how many days we simulate, as it should be the same always, per year
    local daysPerSeason = 6
    -- Factor for converting the foodPerDay value to a yearly factor
    local dayConvertFactor = self.environment.daysPerSeason / daysPerSeason

    local timeFactor = 365 / (4 * daysPerSeason)

    local addedAge = 1 / (4 * daysPerSeason)
    local ageOffset = 0

    for _, animal in ipairs(animalsModule.animals) do
        animal._weight = animal.seasons_weight
    end

    -- For every day, assume full food supply and weight gain
    for days = 1, 4 * daysPerSeason do
        for _, animal in ipairs(animalsModule.animals) do
            local growthFactor = SeasonsAnimals.MATURE_GROWTH_FACTOR[animalType]
            if growthFactor == nil then
                growthFactor = SeasonsAnimals.MATURE_GROWTH_FACTOR.DEFAULT
            end
            local gain = self:calculateGain(animal, animal.seasons_age + ageOffset, growthFactor) * productivity * timeFactor

            animal._weight = animal._weight + gain
            annualFeedAmount = annualFeedAmount + animal._weight * animal.subType.input.foodPerDay * dayConvertFactor
        end

        ageOffset = ageOffset + addedAge
    end

    return annualFeedAmount
end

---Birth a new animal
function SeasonsAnimals:birthAnimal(husbandry, animalModule, animal)
    local subType = animal.subType
    local fillTypeIndex = subType.fillType

    local desc = g_animalManager:getAnimalsByType(subType.type)
    local newAnimal = Animal.createFromFillType(husbandry.isServer, husbandry.isClient, husbandry, fillTypeIndex)

    newAnimal.seasons_age = 0
    newAnimal.seasons_isFemale = math.random() <= subType.breeding.femalePercentage

    newAnimal.seasons_weight = subType.growth.bornWeight
    newAnimal.seasons_weightSent = newAnimal.seasons_weight

    if newAnimal.seasons_isFemale then
        -- must be nil when male
        newAnimal.seasons_timeUntilBirth = 0
        newAnimal.seasons_timeSinceBirth = -100
    end

    newAnimal:register()
    animalModule:addSingleAnimal(newAnimal)

    -- update stats
    if desc.stats.breeding ~= "" then
        self.mission:farmStats(husbandry:getOwnerFarmId()):updateStats(desc.stats.breeding, 1)
    end

    -- log("BIRTH A NEW ANIMAL FROM", animal.subType.storeInfo.shopItemName)
end

---Update payouts for a livery. Called fron onDayChanged from a husbandry
function SeasonsAnimals:updateLiveryPayouts(husbandry)
    if self.isServer and husbandry:getAnimalType() == "HORSE" then
        local farmId = husbandry:getOwnerFarmId()
        local animalsModule = husbandry:getModuleByName("animals")

        for _, animal in pairs(animalsModule.animals) do
            local reward = animal:getDayReward() * (1.5 - self.mission.missionInfo.economicDifficulty * 0.25)
            self.mission:addMoney(reward, farmId, MoneyType.SEASONS_LIVERY, true, false)
        end

        self.mission:broadcastNotifications(MoneyType.SEASONS_LIVERY, farmId)
    end
end

-- Animal IDs
----------------------

---Get the next available identifier for an animal type
function SeasonsAnimals:getNextIdentifierForType(animalType)
    if self.animalIds[animalType] == nil then
        self.animalIds[animalType] = 1
    end

    local id = self.animalIds[animalType]

    -- Wrap after 9999
    if id == 9999 then
        self.animalIds[animalType] = 1
    else
        self.animalIds[animalType] = id + 1
    end

    return id
end

----------------------
-- Events
----------------------

function SeasonsAnimals:onDayChanged()
    self:adjustAnimalAttributes()

    self:updateAnimalAge(1)
    self:updateWeight()

    if self.isServer then
        self:applyDeath()
    end
end

function SeasonsAnimals:onHourChanged()
    self:updateAverageProductivity()
end

function SeasonsAnimals:onSeasonChanged()
    -- update troughs
end

function SeasonsAnimals:onSeasonLengthChanged()
    self:adjustAnimalAttributes()
end

----------------------
-- Injections
----------------------

---Update the parameters to use water and food based on animal weight
function SeasonsAnimals.inj_husbandryModuleAnimals_updateAnimalParameters(module)
    local averageWaterUsagePerDay = 0
    local averageFoodUsagePerDay = 0
    local averageFoodSpillageProductionPerDay = 0
    local averageManureProductionPerDay = 0
    local averageLiquidManureProductionPerDay = 0

    for i = 1, #module.animals do
        local animal = module.animals[i]
        local subType = animal.subType

        local weightWithUnborns = animal:getWeightWithUnborn()
        local weight = animal.seasons_weight

        averageFoodUsagePerDay = averageFoodUsagePerDay + weightWithUnborns * subType.input.foodPerDay
        averageWaterUsagePerDay = averageWaterUsagePerDay + weightWithUnborns * subType.input.waterPerDay

        averageFoodSpillageProductionPerDay = averageFoodSpillageProductionPerDay + weight * subType.output.foodSpillagePerDay
        averageManureProductionPerDay = averageManureProductionPerDay + weight * subType.output.manurePerDay
        averageLiquidManureProductionPerDay = averageLiquidManureProductionPerDay + weight * subType.output.liquidManurePerDay
    end

    -- Calculate total number of animals to take into account
    local numAnimals = #module.animals
    if module.animalsToAdd ~= nil then
        numAnimals = numAnimals + #module.animalsToAdd
    end

    -- Calculate average per animal
    if numAnimals > 0 then
        averageWaterUsagePerDay = averageWaterUsagePerDay / numAnimals
        averageFoodUsagePerDay = averageFoodUsagePerDay / numAnimals

        averageFoodSpillageProductionPerDay = averageFoodSpillageProductionPerDay / numAnimals
        averageManureProductionPerDay = averageManureProductionPerDay / numAnimals
        averageLiquidManureProductionPerDay = averageLiquidManureProductionPerDay / numAnimals
    end

    -- Calculate new food capacity requirements
    local usageMultiplier = HusbandryModuleAnimal.TROUGH_CAPACITY * math.max(1, numAnimals)
    local foodCapacity = math.max(averageFoodUsagePerDay * usageMultiplier, 1000)
    local waterCapacity = math.max(averageWaterUsagePerDay * usageMultiplier, 250)

    local foodSpillageCapacity = averageFoodSpillageProductionPerDay * module.maxNumAnimals

    local defaultMaxCapacity = 800000

    local owner = module.owner
    owner:setModuleParameters("food", foodCapacity, averageFoodUsagePerDay)
    owner:setModuleParameters("water", waterCapacity, averageWaterUsagePerDay)
    owner:setModuleParameters("foodSpillage", foodSpillageCapacity, averageFoodSpillageProductionPerDay)
    owner:setModuleParameters("manure", defaultMaxCapacity, averageManureProductionPerDay)
    owner:setModuleParameters("liquidManure", defaultMaxCapacity, averageLiquidManureProductionPerDay)
end

-- Health (running average productivity)
----------------------

function SeasonsAnimals.inj_husbandryModuleAnimal_load(module, superFunc, xmlFile, configKey, rootNode, owner)
    if not superFunc(module, xmlFile, configKey, rootNode, owner) then
        return false
    end

    if module.owner.averageGlobalProductionFactor == nil then
        module.owner.averageGlobalProductionFactor = SeasonsAnimals.PRODUCTIVITY_START
    end

    return true
end

function SeasonsAnimals.inj_animalHusbandry_readStream(husbandry, streamId, connection)
    husbandry.averageGlobalProductionFactor = NetworkUtil.readCompressedPercentages(streamId, 12)
end

function SeasonsAnimals.inj_animalHusbandry_writeStream(husbandry, streamId, connection)
    NetworkUtil.writeCompressedPercentages(streamId, husbandry.averageGlobalProductionFactor, 12)
end

---When adding an animal, assume this animal is at starting productivity
function SeasonsAnimals.inj_husbandryModuleAnimal_addSingleAnimal(module, superFunc, animal, noEventSend)
    if not superFunc(module, animal, noEventSend) then
        return false
    end

    local addedAnimals = 1
    local addedTo = #module.animals - addedAnimals

    if addedTo ~= 0 then
        -- Only add when the animalsToAdd is empty. This list is used for loading savegames
        if module.animalsToAdd == nil or #module.animalsToAdd == 0 then
            module.owner.averageGlobalProductionFactor = (module.owner.averageGlobalProductionFactor * addedTo + SeasonsAnimals.PRODUCTIVITY_START * addedAnimals) / #module.animals
        end
    end

    return true
end

---Reset the husbandry after removing all animals
function SeasonsAnimals.inj_husbandryModuleAnimal_removeSingleAnimal(module, superFunc, animal, noEventSend)
    if not superFunc(module, animal, noEventSend) then
        return false
    end

    if #module.animals == 0 then
        module.owner.averageGlobalProductionFactor = SeasonsAnimals.PRODUCTIVITY_START
    end

    return true
end

---Disable food spillage causing health detriment
function SeasonsAnimals.inj_animalHusbandry_updateGlobalProductionFactor(husbandry, superFunc)
    husbandry.globalProductionFactor = 0.0

    if husbandry:hasWater() then
        if husbandry:hasStraw() then
            husbandry.globalProductionFactor = 0.1
        end

        husbandry.globalProductionFactor = husbandry.globalProductionFactor + 0.1 + husbandry:getFoodProductionFactor() * 0.8
    end
end

---Use running average for productivity calculations
function SeasonsAnimals.inj_animalHusbandry_getGlobalProductionFactor(husbandry, superFunc)
    return husbandry.averageGlobalProductionFactor
end

---Load running average
function SeasonsAnimals.inj_animalHusbandry_loadFromXMLFile(husbandry, superFunc, xmlFile, key)
    if superFunc(husbandry, xmlFile, key) then
        husbandry.averageGlobalProductionFactor = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#averageGlobalProductionFactor"), SeasonsAnimals.PRODUCTIVITY_START)

        return true
    end

    return false
end

---Save running average
function SeasonsAnimals.inj_animalHusbandry_saveToXMLFile(husbandry, xmlFile, key, usedModNames)
    setXMLFloat(xmlFile, key .. "#averageGlobalProductionFactor", Utils.getNoNil(husbandry.averageGlobalProductionFactor, SeasonsAnimals.PRODUCTIVITY_START))
end

---After updating animal health, kill them if their health is 0 or if they should die of old age
function SeasonsAnimals.inj_husbandryModuleAnimal_updateHealth(module, superFunc, noEventSend)
    -- Override to not use average that we implanted (the average is also a health)
    local old = module.owner.getGlobalProductionFactor
    module.owner.getGlobalProductionFactor = function (husbandry) return husbandry.globalProductionFactor end

    superFunc(module, noEventSend)

    module.owner.getGlobalProductionFactor = old

    if module.owner.isServer then
        local numDied = 0
        local farmId = module.owner:getOwnerFarmId()

        for _, animal in ipairs(module.animals) do
            if animal.getHealthScale ~= nil then -- is a Horse
                if animal:getHealthScale() == 0 then
                    g_seasons.animals:killAnimal(module.owner, animal)

                    g_currentMission:addMoney(-SeasonsAnimals.DEAD_HORSE_PAYMENT, farmId, MoneyType.SEASONS_LIVERY, true, false)

                    -- TODO: move this so the clients have it too
                    if g_currentMission.accessHandler:canPlayerAccess(module.owner) then
                        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, string.format(g_i18n:getText("seasons_notification_horseDied"), animal:getName()))
                    end
                end
            elseif animal.seasons_age * 365 > animal.subType.growth.maxAge then
                -- Die of old age
                g_seasons.animals:killAnimal(module.owner, animal)

                numDied = numDied + 1
            end
        end

        g_currentMission:broadcastNotifications(MoneyType.SEASONS_LIVERY, farmId)

        if numDied > 0 then
            g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, string.format(g_i18n:getText("seasons_notification_animalsDiedOfAge"), numDied))
        end
    end
end

---Rewrite the breeding system using individual animal breeding periods
function SeasonsAnimals.inj_husbandryModuleAnimal_updateBreeding(module, superFunc, dayToInterval)
    -- Do not call superfunc: we overwrite all breeding
    -- Interval is part-of-hour.

    local partOfYearForDay = (1 / (g_seasons.environment.daysPerSeason * 4))
    local interval = partOfYearForDay * dayToInterval
    if dayToInterval == 0 then
        return
    end

    for i = 1, #module.animals do
        local animal = module.animals[i]

        -- Is female and not already pregnant
        if animal.seasons_isFemale then
            local isPregnant = animal.seasons_timeUntilBirth > 0
            local health = module.owner.averageGlobalProductionFactor

            if not isPregnant then
                local isFertile = animal.seasons_age >= animal.subType.breeding.fertileAge and health > SeasonsAnimals.MINIMUM_GESTATION_HEALTH

                -- Wait a gestation interval. When animal.seasons_timeSinceBirth < 0 there was never a birth.
                local enoughTimeSinceLastBirth = animal.seasons_timeSinceBirth < 0 or animal.seasons_timeSinceBirth > animal.subType.breeding.gestationInterval

                if module.owner.isServer and isFertile and enoughTimeSinceLastBirth then
                    local startGestation = false

                    -- Chicken are special because they lay eggs.
                    -- For gameplay it has been decided they only breed chicks when there is a male
                    if animal.subType.isBird then
                        -- Chance of brooding depends on the % of male and birth rate
                        local numMale = 0
                        for j = 1, #module.animals do
                            local animal = module.animals[j]
                            if not animal.seasons_isFemale then
                                numMale = numMale + 1
                            end
                        end

                        local numFemale = #module.animals - numMale
                        local percentageMale = numMale / numFemale

                        -- Percentage of females able to get fertile eggs.
                        local breedablePercentage = math.min(numMale / (numFemale / SeasonsAnimals.HEN_PER_ROOSTER), 1)

                        -- The less roosters the less chance of getting fertile eggs.
                        startGestation = math.random() < (animal.subType.breeding.birthRatePerDay * breedablePercentage * dayToInterval)

                    elseif animal.subType.isSheep then
                        local season = g_seasons.environment.season
                        if season == g_seasons.environment.AUTUMN then
                            startGestation = math.random() < animal.subType.breeding.birthRatePerDay * dayToInterval
                        end
                    else
                        -- The birth rate only tries to prevent direct-pregnancy again, to give a big of randomness
                        startGestation = math.random() < animal.subType.breeding.birthRatePerDay * dayToInterval
                    end

                    if startGestation then
                        animal:startGestation(animal.subType.breeding.gestationPeriod)
                    end
                end

                -- Update since-birth counter so we can use it for testing how long the animal has not been pregnant
                animal.seasons_timeSinceBirth = animal.seasons_timeSinceBirth + interval
            else
                -- Is gestating, update days
                animal.seasons_timeUntilBirth = animal.seasons_timeUntilBirth - interval
                animal.seasons_timeSinceBirth = animal.seasons_timeSinceBirth + interval

                -- Gestation finished
                if module.owner.isServer and animal.seasons_timeUntilBirth <= 0 then
                    -- todo: improve variation
                    local litterSize = animal.subType.breeding.averageLitterSize
                    local variationLitterSize = animal.subType.breeding.variationLitterSize
                    local num = math.max(MathUtil.round(litterSize + (math.random() - 0.5) * variationLitterSize, 0), 1)
                    for c = 1, num do
                        g_seasons.animals:birthAnimal(module.owner, module, animal)
                    end

                    -- Start counting time since birth
                    animal.seasons_timeSinceBirth = 0
                end

                -- aborting if health is low
                if health < SeasonsAnimals.MINIMUM_GESTATION_HEALTH then
                    animal.seasons_timeSinceBirth = 0
                    animal.seasons_timeUntilBirth = 0
                end
            end
        end -- isFemale
    end -- animals
end

---Check for a male animal. Used for chicken breeding that require males.
function SeasonsAnimals.inj_husbandryModuleAnimal_hasMaleAnimal(module, superFunc)
    for i = 1, #module.animals do
        local animal = module.animals[i]

        -- Is female and not already pregnant
        if not animal.seasons_isFemale then
            return true
        end
    end

    return false
end

-- Base games fixes
----------------------

---Fix an issue with bale handling. Could not be done by proper injections:
-- the changed value was never used from addFillLevelFromTool, causing bales to always
-- be deleted even if only part of them was used.
-- NOTE: this bug has been fixed in 1.4, however we still supply the wrapping state for fixing baling contracts
function SeasonsAnimals.inj_unloadTrigger_updateBales(unloadTrigger, superFunc, dt)
    for index, bale in ipairs(unloadTrigger.balesInTrigger) do
        if bale ~= nil and bale.nodeId ~= 0 then
            if bale.dynamicMountJointIndex == nil then
                local fillType = bale:getFillType()
                local fillLevel = bale:getFillLevel()
                local fillInfo = bale.wrappingState

                local delta = bale:getFillLevel()
                if unloadTrigger.baleDeleteLitersPerMS ~= nil then
                    delta = unloadTrigger.baleDeleteLitersPerMS * dt
                end

                if delta > 0 then
                    delta = unloadTrigger.target:addFillLevelFromTool(bale:getOwnerFarmId(), delta, fillType, fillInfo, ToolType.BALE)
                    bale:setFillLevel(fillLevel - delta)
                    local newFillLevel = bale:getFillLevel()
                    if newFillLevel < 0.01 then
                        bale:delete()
                        table.remove(unloadTrigger.balesInTrigger, index)
                        break
                    end
                end
            end
        else
            table.remove(unloadTrigger.balesInTrigger, index)
        end
    end

    if #unloadTrigger.balesInTrigger > 0 then
        unloadTrigger:raiseActive()
    end
end

-- Water pump
----------------------

---Register new messages for the water pump system
function SeasonsAnimals.inj_husbandryModuleWater_load(module, superFunc, ...)
    if not superFunc(module, ...) then
        return false
    end

    g_messageCenter:subscribe(SeasonsMessageType.WATER_PUMP_ADDED, SeasonsAnimals.inj_husbandryModuleWater_findNearestPump, module)
    g_messageCenter:subscribe(SeasonsMessageType.WATER_PUMP_REMOVED, SeasonsAnimals.inj_husbandryModuleWater_findNearestPump, module)

    return true
end

---Unsubscrive from the water pump messages
function SeasonsAnimals.inj_husbandryModuleWater_delete(module)
    g_messageCenter:unsubscribe(SeasonsMessageType.WATER_PUMP_ADDED, module)
    g_messageCenter:unsubscribe(SeasonsMessageType.WATER_PUMP_REMOVED, module)
end

---Look for water pumps that can reach the husbandry
function SeasonsAnimals.inj_husbandryModuleWater_findNearestPump(module)
    local husbandry = module.owner

    -- Use trigger as center so we are not depending on root position
    local wx, wy, wz = getWorldTranslation(module.unloadPlace.exactFillRootNode)

    -- Calculate the husbandry radius using its footprint
    local hx = husbandry.placementSizeX * 0.3 -- bit smaller than 0.5 was are now centered around the water trough
    local hz = husbandry.placementSizeZ * 0.3
    local moduleRadius = math.sqrt(hx * hx + hz * hz)

    -- Reset
    module.seasons_waterPump = nil

    local farmId = husbandry:getOwnerFarmId()
    for _, placeable in pairs(g_currentMission.placeables) do
        if placeable:getOwnerFarmId() == farmId and placeable:isa(WaterPump) then
            local x, y, z = getWorldTranslation(placeable.nodeId)

            -- Calculate distance
            local intersects = MathUtil.hasSphereSphereIntersection(wx, wy, wz, moduleRadius, x, y, z, placeable:getEffectRadius())

            if intersects then
                module.seasons_waterPump = placeable
                break
            end
        end
    end

    if module.seasons_waterPump ~= nil then
        SeasonsAnimals.inj_husbandryModuleWater_updateWaterPump(module)
    end
end

function SeasonsAnimals.inj_husbandryModuleWater_updateWaterPump(module)
    if module.seasons_waterPump ~= nil then
        local waterLevel = module.fillLevels[FillType.WATER]
        if waterLevel ~= nil then
            local capacity = module:getCapacity()

            local percentageFull = waterLevel / capacity
            if percentageFull < SeasonsAnimals.WATER_MIN_LEVEL then
                local diff = SeasonsAnimals.WATER_MIN_LEVEL * capacity - waterLevel
                if diff > 10 then
                    module.seasons_waterPump:onWaterUsed(diff)
                    module:changeFillLevels(diff, FillType.WATER)
                    module:updateFillPlane()
                end
            end

        end
    end
end

---After water content was removed, see if a pump can and should add again
function SeasonsAnimals.inj_husbandryModuleWater_onIntervalUpdate(module, dayToInterval)
    SeasonsAnimals.inj_husbandryModuleWater_updateWaterPump(module)
end

---When placing a husbandry, look for pumps
function SeasonsAnimals.inj_husbandryModuleWater_finalizePlacement(module, superFunc)
    if superFunc ~= nil then
        if not superFunc(module) then
            return false
        end
    end

    SeasonsAnimals.inj_husbandryModuleWater_findNearestPump(module)

    return true
end

-- New animal names
----------------------

---Overwrite the names of the animal shop items with new versions
function SeasonsAnimals.inj_animalManager_loadAnimals(animalManager, superFunc, xmlHandle, baseDirectory)
    -- Does not actually return true on success
    if superFunc(animalManager, xmlHandle, baseDirectory) == false then
        return false
    end

    for _, animal in ipairs(animalManager.animals) do
        for _, subType in ipairs(animal.subTypes) do
            -- Only change if a seasons key is available
            local customEnv = Utils.getModNameAndBaseDirectory(baseDirectory)
            if g_i18n:hasText("seasons_shopItem_" .. subType.fillTypeDesc.name) then
                local text = g_i18n:getText("seasons_shopItem_" .. subType.fillTypeDesc.name)
                subType.storeInfo.shopItemName = text
                subType.subTypeName = text
            elseif g_i18n:hasText("seasons_shopItem_" .. subType.fillTypeDesc.name, customEnv) then
                local text = g_i18n:getText("seasons_shopItem_" .. subType.fillTypeDesc.name, customEnv)
                subType.storeInfo.shopItemName = text
                subType.subTypeName = text
                subType.customEnv = customEnv
            end

            -- Make the brown type into a white sheep
            if subType.fillType == FillType.SHEEP_TYPE_BROWN then
                subType.texture.tileVIndex = 2
                subType.storeInfo.imageFilename = Utils.getFilename("$data/store/animals/sheeps/store_sheepWhite.png", baseDirectory)
            elseif subType.fillType == FillType.CHICKEN_TYPE_BLACK then
                subType.texture.tileUIndex = 2
                subType.storeInfo.imageFilename = Utils.getFilename("$data/store/animals/chickens/store_chickenWhite.png", baseDirectory)
            elseif subType.fillType == FillType.SHEEP_TYPE_BLACK then
                subType.texture.tileUIndex = 2
                subType.texture.tileVIndex = 2
                subType.storeInfo.imageFilename = Utils.getFilename("$data/store/animals/sheeps/store_sheepWhite.png", baseDirectory)
            end
        end
    end

    return true
end

-- Adjusted liquid manure production
----------------------

---Only produce liquid manure when there is no straw
function SeasonsAnimals.inj_husbandryModuleLiquidManure_onIntervalUpdate(module, superFunc, dayToInterval)
    -- The liquid manure is only produced when water is available.
    -- Use that check to add our straw check

    local oldFunc = module.owner.hasWater
    module.owner.hasWater = function(husbandry)
        return oldFunc(husbandry) and not husbandry:hasStraw()
    end

    superFunc(module, dayToInterval)

    module.owner.hasWater = oldFunc
end

-- New animal attributes
----------------------

-- Weird local here. There is no other way to forward the code nicely. And the scripts are single threaded..
local isCreatingNewAnimal = false

---Add default values for age, weight and sex. Add new weight dirty flag
function SeasonsAnimals.inj_animal_new(animal, superFunc, isServer, isClient, owner, fillTypeIndex, customMt)
    local animal = superFunc(animal, isServer, isClient, owner, fillTypeIndex, customMt)

    if isServer then
        animal.seasons_isFemale = animal.subType.storeInfo.buyIsFemale
        animal.seasons_weight = animal.subType.storeInfo.buyWeight
        animal.seasons_age = animal.subType.storeInfo.buyAge

        if animal.seasons_isFemale then
            animal.seasons_timeUntilBirth = 0
            animal.seasons_timeSinceBirth = -100
        end

        if isCreatingNewAnimal then
            animal.seasons_id = g_seasons.animals:getNextIdentifierForType(animal.subType.type)
        else
            animal.seasons_id = -1
        end

        animal.seasons_weightSent = animal.seasons_weight
    end

    animal.weightDirtyFlag = animal:getNextDirtyFlag()

    return animal
end

---Mark the husbandry when we're adding a real animal so it is passed to :new
function SeasonsAnimals.inj_animal_createFromFillType(superFunc, isServer, isClient, husbandry, ...)
    isCreatingNewAnimal = true

    local animal = superFunc(isServer, isClient, husbandry, ...)

    isCreatingNewAnimal = false

    return animal
end

---Update algorithm for animal worth
function SeasonsAnimals.inj_animal_getValue(animal, superFunc)
    if animal:isa(Horse) then
        -- Horses can't be sold for money
        return 0
    end

    local storeInfo = animal.subType.storeInfo
    local pricePerKg = storeInfo.pricePerKg
    local priceDropAge = storeInfo.priceDropAge
    local age = animal.seasons_age * 365
    local maxAge = animal.subType.growth.maxAge

    if age > priceDropAge then
        pricePerKg = pricePerKg * (1 - 0.25 * (age - priceDropAge) / (maxAge - priceDropAge))
    end

    local economyFactor = g_seasons.economy.data:getAnimalFactor(animal.subType.type)

    return (storeInfo.baseSellPrice + animal.seasons_weight * pricePerKg) * economyFactor
end

---Load age, weight and sex
function SeasonsAnimals.inj_animal_loadFromXMLFile(animal, xmlFile, key)
    animal.seasons_isFemale = Utils.getNoNil(getXMLBool(xmlFile, key.."#seasons_isFemale"), animal.seasons_isFemale)
    animal:setWeight(Utils.getNoNil(getXMLFloat(xmlFile, key.."#seasons_weight"), animal.seasons_weight))
    animal.seasons_age = Utils.getNoNil(getXMLFloat(xmlFile, key.."#seasons_age"), animal.seasons_age)
    animal.seasons_id = getXMLInt(xmlFile, key .. "#seasons_id")

    if animal.seasons_id == nil then
        animal.seasons_id = g_seasons.animals:getNextIdentifierForType(animal.subType.type)
    end

    if animal.seasons_isFemale then
        animal.seasons_timeUntilBirth = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#seasons_timeUntilBirth"), animal.seasons_timeUntilBirth)
        animal.seasons_timeSinceBirth = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#seasons_timeSinceBirth"), -animal.seasons_timeUntilBirth)
    end
end

---Save age, weight and sex
function SeasonsAnimals.inj_animal_saveToXMLFile(animal, xmlFile, key, usedModNames)
    setXMLBool(xmlFile, key.."#seasons_isFemale", animal.seasons_isFemale)
    setXMLFloat(xmlFile, key.."#seasons_weight", animal.seasons_weight)
    setXMLFloat(xmlFile, key.."#seasons_age", animal.seasons_age)
    setXMLInt(xmlFile, key.."#seasons_id", animal.seasons_id)

    if animal.seasons_isFemale then
        setXMLFloat(xmlFile, key .. "#seasons_timeUntilBirth", animal.seasons_timeUntilBirth)
        setXMLFloat(xmlFile, key .. "#seasons_timeSinceBirth", animal.seasons_timeSinceBirth)
    end
end

---Share age, weight and sex
function SeasonsAnimals.inj_animal_readStream(animal, streamId)
    animal.seasons_isFemale = streamReadBool(streamId)
    animal.seasons_weight = streamReadFloat32(streamId)
    animal.seasons_age = streamReadFloat32(streamId)
    animal.seasons_id = streamReadIntN(streamId, 15)

    if animal.seasons_isFemale then
        animal.seasons_timeUntilBirth = streamReadFloat32(streamId)
    end
end

---Share age, weight and sex
function SeasonsAnimals.inj_animal_writeStream(animal, streamId)
    streamWriteBool(streamId, animal.seasons_isFemale)
    streamWriteFloat32(streamId, animal.seasons_weight)
    streamWriteFloat32(streamId, animal.seasons_age)
    streamWriteIntN(streamId, animal.seasons_id, 15)

    if animal.seasons_isFemale then
        streamWriteFloat32(streamId, animal.seasons_timeUntilBirth)
    end
end

---Update weight
function SeasonsAnimals.inj_animal_readUpdateStream(animal, streamId, timestamp, connection)
    if connection:getIsServer() then
        if streamReadBool(streamId) then
            animal:setWeight(NetworkUtil.readCompressedRange(streamId, 0, 5000, 16))
        end
    end
end

---Update weight
function SeasonsAnimals.inj_animal_writeUpdateStream(animal, streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        if streamWriteBool(streamId, bitAND(dirtyMask, animal.weightDirtyFlag) ~= 0) then
            NetworkUtil.writeCompressedRange(streamId, animal.seasons_weight, 0, 5000, 16)
        end
    end
end

---New setter
function SeasonsAnimals.inj_animal_setWeight(animal, weight)
    animal.seasons_weight = math.max(weight, 0)

    if animal.isServer and math.abs(animal.seasons_weight - animal.seasons_weightSent) > 0.01 then
        animal.seasons_weightSent = animal.seasons_weight
        animal:raiseDirtyFlags(animal.weightDirtyFlag)

        g_messageCenter:publish(MessageType.HUSBANDRY_ANIMALS_CHANGED, animal.owner)
    end
end

---Start gestation of a new unborn
function SeasonsAnimals.inj_animal_startGestation(animal, superFunc, duration, noEventSend)
    animal.seasons_timeUntilBirth = duration

    if animal.isServer then
        SeasonsStartAnimalGestation:sendEvent(animal, duration)
    end
end

---Get the weight of the animal including a growing unborn
function SeasonsAnimals.inj_animal_getWeightWithUnborn(animal, superFunc)
    local unborn = 0
    if animal.seasons_isFemale and animal.seasons_timeUntilBirth > 0 then
        local subType = animal.subType

        -- Birds do gestation outside their body
        if not subType.isBird then
            local aging = subType.breeding.gestationPeriod - animal.seasons_timeUntilBirth
            unborn = aging * subType.growth.bornWeight * subType.breeding.averageLitterSize
        end
    end

    return animal.seasons_weight + unborn
end

---Create a new unique name for an animal
function SeasonsAnimals.inj_animal_getName(animal)
    local breedName = animal.subType.storeInfo.shopItemName

    -- Strip possible colors
    local start = breedName:find("(", nil, true)
    if start ~= nil then
        breedName = breedName:sub(1, start - 2) -- assume space before (
    end

    return string.format("%s %03d", breedName, animal.seasons_id)
end

---Get the monetary reward for caring for the horse on the current day
function SeasonsAnimals.inj_horse_getDayReward(horse)
    local trainingDifficulty = horse.subType.livery.trainingDifficulty
    local income = horse.subType.livery.income

    local scale = 0.4 * horse:getHealthScale() + 0.6 * math.pow(math.min(horse.ridingScale, 1), trainingDifficulty) - 0.6 * horse.dirtScale + 0.1 * horse:getFitnessScale()

    return math.max(scale * income, 0)
end

---Add an initial fitness higher than basegame
function SeasonsAnimals.inj_horse_new(horse, superFunc, ...)
    local horse = superFunc(horse, ...)

    horse.fitnessScale = SeasonsAnimals.INITIAL_FITNESS_SCALE + (math.random() - 0.5) * SeasonsAnimals.INITIAL_FITNESS_VAR

    return horse
end


---Prepend with horse livery payouts
function SeasonsAnimals.inj_husbandryModuleAnimal_onDayChanged(module)
    g_seasons.animals:updateLiveryPayouts(module.owner)
end

-- Changed food
----------------------

---Adjust grazing productivity from 0.25 to 0.6
function SeasonsAnimals.inj_animalFoodManager_loadFoodGroups(foodManager, superFunc, xmlFile)
    if not superFunc(foodManager, xmlFile) then
        return false
    end

    for _, foodGroup in ipairs(foodManager.foodGroups["COW"].content) do
        if #foodGroup.fillTypes == 1 and foodGroup.fillTypes[1] == FillType.GRASS_WINDROW then
            foodGroup.productionWeight = 0.6
            break
        end
    end

    local group = foodManager.foodGroups["PIG"]
    -- Properties changed by mod map: do not do any other changes
    if group.consumptionType ~= AnimalFoodManager.FOOD_CONSUME_TYPE_PARALLEL then
        return true
    end

    local list = group.content
    if list ~= nil then
        for i, foodGroup in ipairs(list) do
            ---Add more weight to SOYBEAN CANOLA SUNFLOWER
            if #foodGroup.fillTypes == 3 and foodGroup.productionWeight - 0.2 < 0.001 then
                foodGroup.productionWeight = 0.25
                foodGroup.eatWeight = 0.25

            -- Remove the potato/beets category
            elseif #foodGroup.fillTypes == 2 and foodGroup.fillTypes[1] == FillType.POTATO and foodGroup.fillTypes[2] == FillType.SUGARBEET then
                list[i] = nil
            end
        end
    else
        Logging.error("Cannot find the PIG food group contents. This is most likely an error in the map.")
    end

    return true
end

---Adjust the pig mixture contents to match their food groups
function SeasonsAnimals.inj_animalFoodManager_loadMixtures(foodManager, superFunc, xmlFile)
    if not superFunc(foodManager, xmlFile) then
        return false
    end

    -- Some weird maps break the pigs by killing the mixtures
    if foodManager.animalFoodMixtures["PIG"] == nil then
        Logging.error("Map has no pig food mixture defined. This breaks the pig food pallet.")
        return true
    end

    for _, mixtureType in ipairs(foodManager.animalFoodMixtures["PIG"]) do
        local list = foodManager.foodMixtures[mixtureType].ingredients
        if list ~= nil then
            for i, ingredient in ipairs(list) do
                ---Add more weight to SOYBEAN CANOLA SUNFLOWER
                if #ingredient.fillTypes == 3 and ingredient.weight - 0.2 < 0.001 then
                    ingredient.weight = 0.25

                -- Remove the potato/beets category
                elseif #ingredient.fillTypes == 2 and ingredient.fillTypes[1] == FillType.POTATO and ingredient.fillTypes[2] == FillType.SUGARBEET then
                    list[i] = nil
                end
            end
        else
            Logging.error("Cannot find the PIG food micture ingredients. This is most likely an error in the map.")
        end
    end

    return true
end

---Adjust food capacities: for parallel, multiply by eat weight. For serial: do nothing.
function SeasonsAnimals.inj_husbandryModuleFood_setCapacity(module, superFunc, newCapacity)
    module.fillCapacity = 0.0
    for _, foodGroupInfo in pairs(module.foodGroupCapacities) do
        foodGroupInfo.capacity = newCapacity * foodGroupInfo.foodGroup.eatWeight
    end

    module:updateFillPlane()
end

-- Adjusted production
----------------------

---Add scaling of milk production dependent on lactation and birth
function SeasonsAnimals.inj_husbandryModuleMilk_onIntervalUpdate(module, superFunc, dayToInterval)
    -- With no output there is nothing to adjust
    if module.singleAnimalUsagePerDay == 0 then
        return superFunc(module, dayToInterval)
    end

    local oldUsage = module.singleAnimalUsagePerDay

    -- We need to find the average factor of all animals that have a positive milkPerDay value.
    -- This value was already used by the rest of the system. Then for each animal we find their milking factor.
    -- This is 0 for males (thus the isFemale check). And also for cows that can't give milk

    local factorSum = 0
    local factorNum = 0

    local seasonsAnimals = g_seasons.animals

    local animals = module.owner:getModuleByName("animals").animals
    for _, animal in ipairs(animals) do
        if animal.subType.output.milkPerDay > 0 then
            if animal.seasons_isFemale then
                local daysSinceBirth = animal.seasons_timeSinceBirth * 365

                if daysSinceBirth > 0 then
                    local factor = seasonsAnimals:calculateUnitMilkProduction(daysSinceBirth)

                    factorSum = factorSum + factor
                end
            end

            factorNum = factorNum + 1
        end
    end

    local scale = 1
    if factorNum > 0 then
        scale = factorSum / factorNum
    end

    module.singleAnimalUsagePerDay = oldUsage * scale

    superFunc(module, dayToInterval)

    module.singleAnimalUsagePerDay = oldUsage
end

---Produce less pallets for chicken when brooding
-- The basegame has a bug in the pallet production. Instead of resetting the fill-delta, it puts in
-- what was applied. So every time something is added to a pallet, the delta increases for next time.
-- This only resets once not everything fits inside the pallet.
-- Whatever way you look at it, you will never get the output you expect.
-- We fix that here by returning from addFillUnitFillLevel what the rest of the code expects:
-- the new delta (so delta-applied).
function SeasonsAnimals.inj_husbandryModulePallets_onIntervalUpdate(module, superFunc, dayToInterval)
    HusbandryModulePallets:superClass().onIntervalUpdate(module, dayToInterval)
    local totalNumAnimals = module.owner:getNumOfAnimals()

    local animalModule = module.owner:getModuleByName("animals")
    local isChicken = #animalModule.animals > 0 and animalModule.animals[1].subType.isBird
    local isSheep = #animalModule.animals > 0 and animalModule.animals[1].subType.isSheep

    if module.singleAnimalUsagePerDay > 0 and totalNumAnimals > 0 then
        local productivity = module.owner:getGlobalProductionFactor()

        if isChicken then
            -- Chicken that are brooding do not produce
            local numTotal = #animalModule.animals
            local numBrooding = 0

            for i = 1, numTotal do
                local animal = animalModule.animals[i]
                if animal.seasons_isFemale and animal.seasons_timeUntilBirth > 0 then
                    numBrooding = numBrooding + 1
                end
            end

            -- Lower productivity for brooding
            productivity = (1 - numBrooding / numTotal) * productivity
        end

        if isSheep then
            -- Sheep that are less than a year yields no wool
            local numTotal = #animalModule.animals
            local toBeSheared = 0

            for i = 1, numTotal do
                local animal = animalModule.animals[i]
                if animal.seasons_age > 1 then
                    toBeSheared = toBeSheared + 1
                end
            end

            local season = g_seasons.environment.season
            local hour = g_seasons.environment:getTimeInHours()

            -- shearing only in spring and between 6 and 20 during day
            if season == g_seasons.environment.SPRING and (hour > 6 or hour <= 20) then
                productivity = toBeSheared / numTotal * productivity * 4 * 24 / 14
            else
                productivity = 0
            end
        end

        local fillDelta = productivity * totalNumAnimals * module.singleAnimalUsagePerDay * dayToInterval

        module.palletSpawnerFillDelta = module.palletSpawnerFillDelta + fillDelta

        if productivity > 0 and module.palletSpawnerFillDelta > 0 then
            -- check if last pallet is still valid
            if module.currentPallet ~= nil then
                if module.currentPallet:getFillUnitFreeCapacity(module.palletFillUnitIndex) < 0.001 then
                    module.currentPallet = nil
                end
            end

            if module.currentPallet ~= nil then
                if not entityExists(module.currentPallet.rootNode) then
                    module.currentPallet = nil
                else
                    local x, _, z = localToLocal(module.currentPallet.rootNode, module.palletSpawnerNode, 0,0,0)
                    if x < 0 or z < 0 or x > module.palletSpawnerAreaSizeX or z > module.palletSpawnerAreaSizeZ then
                        module.currentPallet = nil
                    end
                end
            end

            -- check if there is a pallet which can be filled
            if module.currentPallet == nil then
                module.availablePallet = nil
                local x,y,z = localToWorld(module.palletSpawnerNode, 0.5 * module.palletSpawnerAreaSizeX, 0, 0.5 * module.palletSpawnerAreaSizeZ)
                local rx,ry,rz = getWorldRotation(module.palletSpawnerNode)
                local nbShapesOverlap = overlapBox(x, y - 5, z, rx, ry, rz, 0.5 * module.palletSpawnerAreaSizeX, 10, 0.5 * module.palletSpawnerAreaSizeZ, "palletSpawnerCollisionTestCallback", module, nil, true, false, true)
                if module.availablePallet ~= nil then
                    module.currentPallet = module.availablePallet
                end
            end

            if module.currentPallet == nil then
                local rx, ry, rz = getWorldRotation(module.palletSpawnerNode)
                local x, y, z = getWorldTranslation(module.palletSpawnerNode)
                local canCreatePallet = false

                local widthHalf = module.sizeWidth * 0.5
                local heightHalf = module.sizeLength * 0.5

                for dx = widthHalf, module.palletSpawnerAreaSizeX - widthHalf, widthHalf do
                    for dz = heightHalf, module.palletSpawnerAreaSizeZ - heightHalf, widthHalf do
                        x, y, z = localToWorld(module.palletSpawnerNode, dx, 0, dz)
                        module.palletSpawnerCollisionObjectId = 0
                        local nbShapesOverlap = overlapBox(x, y - 5, z, rx, ry, rz, widthHalf, 10.0, heightHalf, "palletSpawnerCollisionTestCallback", module, nil, true, false, true)
                        if module.palletSpawnerCollisionObjectId == 0 then
                            canCreatePallet = true
                            break
                        end
                    end
                    if canCreatePallet then
                        break
                    end
                end

                if canCreatePallet and module.palletSpawnerFillDelta > HusbandryModulePallets.fillLevelThresholdForDeletion then
                    module.currentPallet = g_currentMission:loadVehicle(module.palletConfigFilename, x, nil, z, 1.2, ry, true, 0, Vehicle.PROPERTY_STATE_OWNED, module.owner:getOwnerFarmId(), nil, nil)
                end
            end

            if module.currentPallet ~= nil then
                -- FIX is here
                local appliedDiff = module.currentPallet:addFillUnitFillLevel(module.owner:getOwnerFarmId(), module.palletFillUnitIndex, module.palletSpawnerFillDelta, module.palletFillTypeIndex, ToolType.UNDEFINED)
                module.palletSpawnerFillDelta = module.palletSpawnerFillDelta - appliedDiff

                -- Set the fill level for syncing with clients
                module:setFillLevel(module.palletFillUnitIndex, module:getCurrentPalletFillLevel())
            elseif module.palletSpawnerFillDelta > HusbandryModulePallets.fillLevelThresholdForDeletion then
                module:showSpawnerBlockedWarning()
            end
        end
    end
end

-- Extra player feedback
----------------------

---Get an algorithmic value from 0 to 1 depending on the condition of the husbandry
function SeasonsAnimals.inj_animalHusbandry_getCondition(husbandry)
    local animalModule = husbandry:getModuleByName("animals")
    local waterModule = husbandry:getModuleByName("water")
    local foodModule = husbandry:getModuleByName("food")
    local foodSpillageModule = husbandry:getModuleByName("foodSpillage")

    local condition = 1

    -- Cleanness limits condition to 90%
    if foodSpillageModule ~= nil and foodSpillageModule:getSpillageFactor() ~= nil and foodSpillageModule:getSpillageFactor() < 0.2 then
        condition = condition * 0.9
    end

    -- With no animals, only cleanness has an effect
    if animalModule:getNumOfAnimals() == 0 then
        return condition
    end

    -- Water is very important so the lower the water the worse the condition.
    -- Ignore when a pump is active
    if waterModule ~= nil then
        local hasPump = waterModule.seasons_waterPump ~= nil
        if not hasPump then
            local totalWater = 0
            for _, fillLevel in pairs(waterModule.fillLevels) do
                totalWater = totalWater + fillLevel
            end

            local capacity = waterModule.unloadPlace.target:getCapacity()
            if capacity > 0 then
                local perc = totalWater / capacity
                if perc < 0.15 then
                    condition = condition * (3 * perc)
                end
            end
        end
    end

    -- Food
    -- Needs something to eat. Pull alarm when low on food
    local capacity = foodModule:getCapacity()
    local level = foodModule:getTotalFillLevel()
    if capacity > 0 then
        local percentage = level / capacity
        if percentage < 0.4 then
            condition = condition * (percentage / 0.4)
        end
    end

    return condition
end

---Calculate an age classifier for feedback on maturity and death
function SeasonsAnimals.inj_animal_getAgeClassifier(animal)
    local age = animal.seasons_age

    -- Math is year based
    local level = animal.subType.growth.daysLevel / 365
    local maxAge = animal.subType.growth.maxAge / 365

    if age > maxAge * 0.9 then
        return SeasonsAnimals.AGE_CLASSIFIER.OLD
    elseif age > level or (animal.seasons_isFemale and age > animal.subType.breeding.fertileAge) then
        return SeasonsAnimals.AGE_CLASSIFIER.MATURE
    elseif age > level * 0.5 then
        return SeasonsAnimals.AGE_CLASSIFIER.YOUNG
    else
        return SeasonsAnimals.AGE_CLASSIFIER.NEWBORN
    end
end

-- Liquid manure basegame bug fix
----------------------

function SeasonsAnimals.inj_husbandryModuleLiquidManure_loadFromXMLFile(module, superFunc, xmlFile, key)
    if superFunc ~= nil then
        superFunc(module, xmlFile, key)
    else
        HusbandryModuleLiquidManure:superClass().loadFromXMLFile(module, xmlFile, key)
    end

    module:updateFillPlane()
end

function SeasonsAnimals.inj_husbandryModuleLiquidManure_updateFillPlane(module, superFunc)
    if module.fillPlane ~= nil then
        module.fillPlane:setState(module:getFillProgress())
    end
end

---Update fillplane when filllevel changed
function SeasonsAnimals.inj_husbandryModuleLiquidManure_onFillProgressChanged(module, superFunc)
    module:updateFillPlane()
end
