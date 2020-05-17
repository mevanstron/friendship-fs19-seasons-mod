----------------------------------------------------------------------------------------------------
-- SeasonsEconomy
----------------------------------------------------------------------------------------------------
-- Purpose:  Economy changes
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsEconomy = {}

local SeasonsEconomy_mt = Class(SeasonsEconomy)

SeasonsEconomy.RANDOM_IMPACT = 0.2
SeasonsEconomy.BASE_LOAN_INTEREST = 10

function SeasonsEconomy.installSpecializations()
    SeasonsModUtil.overwrittenFunction(AIVehicle, "onUpdateTick", SeasonsEconomy.inj_aiVehicle_onUpdateTick)
end

function SeasonsEconomy:new(mission, messageCenter, environment, fillTypeManager, farmManager, animalManager)
    local self = setmetatable({}, SeasonsEconomy_mt)

    self.mission = mission
    self.messageCenter = messageCenter
    self.environment = environment
    self.farmManager = farmManager

    self.data = SeasonsEconomyData:new(mission, fillTypeManager, environment)
    self.history = SeasonsEconomyHistory:new(mission, messageCenter, environment, fillTypeManager, animalManager, self.data)

    -- SeasonsModUtil.overwrittenConstant(EconomyManager, "DEFAULT_LEASING_DEPOSIT_FACTOR",    0.020) -- factor of price (vanilla: 0.02)
    -- SeasonsModUtil.overwrittenConstant(EconomyManager, "DEFAULT_RUNNING_LEASING_FACTOR",    0.021) -- factor of price (vanilla: 0.021)
    -- SeasonsModUtil.overwrittenConstant(EconomyManager, "PER_DAY_LEASING_FACTOR",            0.010) -- factor of price (vanilla: 0.01)

    SeasonsModUtil.appendedFunction(Placeable,          "dayChanged",                   SeasonsEconomy.inj_placeable_dayChanged)
    SeasonsModUtil.appendedFunction(Placeable,          "delete",                       SeasonsEconomy.inj_placeable_delete)
    SeasonsModUtil.appendedFunction(Placeable,          "finalizePlacement",            SeasonsEconomy.inj_placeable_finalizePlacement)
    SeasonsModUtil.appendedFunction(Placeable,          "readStream",                   SeasonsEconomy.inj_placeable_readStream)
    SeasonsModUtil.appendedFunction(Placeable,          "saveToXMLFile",                SeasonsEconomy.inj_placeable_saveToXMLFile)
    SeasonsModUtil.appendedFunction(Placeable,          "writeStream",                  SeasonsEconomy.inj_placeable_writeStream)
    SeasonsModUtil.appendedFunction(Storage,            "delete",                       SeasonsEconomy.inj_storage_delete)
    SeasonsModUtil.overwrittenConstant(Placeable,       "onSeasonLengthChanged",        SeasonsEconomy.inj_placeable_onSeasonLengthChanged)
    SeasonsModUtil.overwrittenConstant(Storage,         "onSeasonLengthChanged",        SeasonsEconomy.inj_storage_onSeasonLengthChanged)
    SeasonsModUtil.overwrittenFunction(AnimalItem,      "new",                          SeasonsEconomy.inj_animalItem_new)
    SeasonsModUtil.overwrittenFunction(Bga,             "load",                         SeasonsEconomy.inj_bga_load)
    SeasonsModUtil.overwrittenFunction(BuyingStation,   "addFillLevelToFillableObject", SeasonsEconomy.inj_buyingStation_addFillLevelToFillableObject)
    SeasonsModUtil.overwrittenFunction(EconomyManager,  "getCostPerLiter",              SeasonsEconomy.inj_economyManager_getCostPerLiter)
    SeasonsModUtil.overwrittenFunction(EconomyManager,  "getPricePerLiter",             SeasonsEconomy.inj_economyManager_getPricePerLiter)
    SeasonsModUtil.overwrittenFunction(EconomyManager,  "startGreatDemand",             SeasonsEconomy.inj_economyManager_startGreatDemand)
    SeasonsModUtil.overwrittenFunction(Placeable,       "getDailyUpkeep",               SeasonsEconomy.inj_placeable_getDailyUpkeep)
    SeasonsModUtil.overwrittenFunction(Placeable,       "getSellPrice",                 SeasonsEconomy.inj_placeable_getSellPrice)
    SeasonsModUtil.overwrittenFunction(Placeable,       "loadFromXMLFile",              SeasonsEconomy.inj_placeable_loadFromXMLFile)
    SeasonsModUtil.overwrittenFunction(SellingStation,  "doPriceDrop",                  SeasonsEconomy.inj_sellingStation_doPriceDrop)
    SeasonsModUtil.overwrittenFunction(SellingStation,  "getEffectiveFillTypePrice",    SeasonsEconomy.inj_sellingStation_getEffectiveFillTypePrice)
    SeasonsModUtil.overwrittenFunction(Storage,         "load",                         SeasonsEconomy.inj_storage_load)

    -- Not actually used in vanilla but a mod might
    SeasonsModUtil.overwrittenFunction(Bale,            "getValue",                     SeasonsEconomy.inj_bale_getValue)

    self:addFinanceStats()

    return self
end

function SeasonsEconomy:delete()
    self.history:delete()
    self.data:delete()

    self.messageCenter:unsubscribeAll(self)

    self:removeFinanceStats()
end

function SeasonsEconomy:load()
    self.data:load()
    self.history:load()

    self:updateLoanInterestRates()

    MoneyType.SEASONS_LIVERY = MoneyType.getMoneyType("seasons_livery_stable", "seasons_livery_stable")

    self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)
end

function SeasonsEconomy:readStream(streamId, connection)
    self.history:readStream(streamId, connection)
end

function SeasonsEconomy:writeStream(streamId, connection)
    self.history:writeStream(streamId, connection)
end

----------------------
-- Loading
----------------------

function SeasonsEconomy:setDataPaths(paths)
    self.data:setDataPaths(paths)
end

function SeasonsEconomy:loadFromSavegame(xmlFile)
    self.history:loadFromSavegame(xmlFile)
end

function SeasonsEconomy:saveToSavegame(xmlFile)
    self.history:saveToSavegame(xmlFile)
end

function SeasonsEconomy:onGameLoaded()
    self.history:onGameLoaded()
end

----------------------
-- Finance stats
----------------------

---Add new finance statistics for better insight into animals.
function SeasonsEconomy:addFinanceStats()
    self.addedFinanceStatsIndices = {}

    local function add(name)
        local index = #FinanceStats.statNames + 1
        FinanceStats.statNames[index] = name
        FinanceStats.statNameToIndex[name] = index

        table.insert(self.addedFinanceStatsIndices, index)
    end

    add("seasons_livery_stable")
end

---Remove the finance stats we added above
function SeasonsEconomy:removeFinanceStats()
    for _, index in ipairs(self.addedFinanceStatsIndices) do
        local name = FinanceStats.statNames[index]
        FinanceStats.statNames[index] = nil
        FinanceStats.statNameToIndex[name] = nil
    end
end

----------------------
-- Economy changes
----------------------

function SeasonsEconomy:getIsWorkingHours()
    local hour = self.mission.environment.currentHour
    return hour >= self.data.ai.workdayStart and hour <= self.data.ai.workdayEnd
end

---Update the loan interests of all farms to be normalized over the length of a year.
function SeasonsEconomy:updateLoanInterestRates()
    -- TODO: change
    local yearInterest = SeasonsEconomy.BASE_LOAN_INTEREST / 2 * (self.mission.missionInfo.economicDifficulty or self.mission.missionInfo.difficulty)

    for _, farm in ipairs(self.farmManager:getFarms()) do
        -- Convert the interest to be made in a Seasons year to a vanilla year so that the daily interests are correct
        farm.loanAnnualInterestRate = yearInterest * (365 / (self.environment.daysPerSeason * SeasonsEnvironment.SEASONS_IN_YEAR))
    end
end

------------------------------------------------
--- Events
------------------------------------------------

function SeasonsEconomy:onSeasonLengthChanged()
    self:updateLoanInterestRates()
end

------------------------------------------------
--- Injections
------------------------------------------------

---Add factor to the bale price
function SeasonsEconomy.inj_bale_getValue(bale, superFunc)
    return superFunc(bale) * g_seasons.economy.data:getBaleFactor(bale:getFillType())
end

---Update the pay of workers depending on the working hours
function SeasonsEconomy.inj_aiVehicle_onUpdateTick(vehicle, superFunc, dt, ...)
    local economy = g_seasons.economy

    if vehicle.isServer and vehicle:getIsAIActive() then
        local spec = vehicle.spec_aiVehicle
        if economy:getIsWorkingHours() then
            spec.pricePerMS = economy.data.ai.workdayPayMS
        else
            spec.pricePerMS = economy.data.ai.overtimePayMS
        end
    end

    superFunc(vehicle, dt, ...)
end

---Decide a new price depending on the tool type (bale)
function SeasonsEconomy.inj_sellingStation_getEffectiveFillTypePrice(sellingStation, superFunc, fillType, toolType)
    local price = superFunc(sellingStation, fillType, toolType)

    if sellingStation.isServer then
        local factor = 0

        if toolType == ToolType.BALE then
            factor = g_seasons.economy.data:getBaleFactor(fillType)
        else
            factor = g_seasons.economy.data:getFillTypeFactor(fillType)
        end

        -- Ignore random delta when factor is 0 to always get a 0 price
        if factor == 0 then
            return 0
        else
            return ((sellingStation.fillTypePrices[fillType] * factor + sellingStation.fillTypePriceRandomDelta[fillType] * SeasonsEconomy.RANDOM_IMPACT) * sellingStation.priceMultipliers[fillType]) * EconomyManager.getPriceMultiplier()
        end

    else
        -- Price is directly shared from server to client and thus already adjusted
        return price
    end
end

---Disabling price drops by emptying the function
function SeasonsEconomy.inj_sellingStation_doPriceDrop(sellingStation, superFunc, fillLevel, fillType)
    -- Disable price drops
end

---Adjust buying prices so it can't be cheated
function SeasonsEconomy.inj_buyingStation_addFillLevelToFillableObject(buyingStation, superFunc, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType)
    local oldScale = buyingStation.fillTypePricesScale[fillTypeIndex]

    buyingStation.fillTypePricesScale[fillTypeIndex] = oldScale * g_seasons.economy.data:getFillTypeFactor(fillTypeIndex)

    local delta = superFunc(buyingStation, fillableObject, fillUnitIndex, fillTypeIndex, fillDelta, fillInfo, toolType)

    buyingStation.fillTypePricesScale[fillTypeIndex] = oldScale

    return delta
end

function SeasonsEconomy.inj_economyManager_getPricePerLiter(economyManager, superFunc, fillTypeIndex, useMultiplier)
    return superFunc(economyManager, fillTypeIndex, useMultiplier) * g_seasons.economy.data:getFillTypeFactor(fillTypeIndex)
end

function SeasonsEconomy.inj_economyManager_getCostPerLiter(economyManager, superFunc, fillTypeIndex, useMultiplier)
    return superFunc(economyManager, fillTypeIndex, useMultiplier) * g_seasons.economy.data:getFillTypeFactor(fillTypeIndex)
end

---Do not start great demands that give 0 money
function SeasonsEconomy.inj_economyManager_startGreatDemand(economyManager, superFunc, greatDemand)
    local factor = g_seasons.economy.data:getFillTypeFactor(greatDemand.fillTypeIndex)
    if factor == 0 then
        greatDemand.isValid = false
    else
        return superFunc(economyManager, greatDemand)
    end
end

---Update price of silage in the bga from 0.2 to 0.15
function SeasonsEconomy.inj_bga_load(bga, superFunc, ...)
    if not superFunc(bga, ...) then
        return false
    end

    for _, slot in ipairs(bga.bunker.slots) do
        for fillTypeIndex, info in pairs(slot.fillTypes) do
            if fillTypeIndex == FillType.SILAGE then
                info.pricePerLiter = 0.15
            end
        end
    end

    return true
end

------------------------------------------------
--- Injections: Placeable updates
------------------------------------------------

---Read years from the server
function SeasonsEconomy.inj_placeable_readStream(placeable, streamId, connection)
    placeable.seasons_years = streamReadFloat32(streamId)
end

---Transfer years over to the client
function SeasonsEconomy.inj_placeable_writeStream(placeable, streamId, connection)
    streamWriteFloat32(streamId, placeable.seasons_years)
end

---Load years from files
function SeasonsEconomy.inj_placeable_loadFromXMLFile(placeable, superFunc, xmlFile, key, resetVehicles)
    if superFunc(placeable, xmlFile, key, resetVehicles) then

        local default = placeable.age / (4 * g_seasons.environment.daysPerSeason)
        placeable.seasons_years = Utils.getNoNil(getXMLFloat(xmlFile, key .. "#seasonsYears"), default)

        return true
    end

    return false
end

function SeasonsEconomy.inj_placeable_saveToXMLFile(placeable, xmlFile, key, usedModNames)
    setXMLFloat(xmlFile, key .. "#seasonsYears", placeable.seasons_years)
end

---Subscribe to season length changes
function SeasonsEconomy.inj_placeable_finalizePlacement(placeable)
    g_messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, placeable.onSeasonLengthChanged, placeable)

    placeable.seasons_originalIncomePerHour = placeable.incomePerHour
    placeable.seasons_years = 0

    placeable:onSeasonLengthChanged()
end

---Remove season listener
function SeasonsEconomy.inj_placeable_delete(placeable)
    g_messageCenter:unsubscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, placeable)
end

---Update income per hour to make it the same per year
function SeasonsEconomy.inj_placeable_onSeasonLengthChanged(placeable)
    if placeable.isSeasonsPrepared then
        -- Do not touch
        return
    end

    local difficultyFactor = 1 - (2 - g_currentMission.missionInfo.economicDifficulty) * 0.1

    placeable.incomePerHour = 6 / g_seasons.environment.daysPerSeason * placeable.seasons_originalIncomePerHour * difficultyFactor
end

---Daily upkeep depends on whether there is any income and on age
function SeasonsEconomy.inj_placeable_getDailyUpkeep(placeable, superFunc)
    local storeItem = g_storeManager:getItemByXMLFilename(placeable.configFileName)

    local years = Utils.getNoNil(placeable.seasons_years, 0) -- can be nil when placing
    local multiplier = 1 + years * 2.5

    if placeable.incomePerHour == 0 then
        multiplier = 1 + years * 0.25
    end

    return StoreItemUtil.getDailyUpkeep(storeItem, nil) * multiplier / g_seasons.environment.daysPerSeason
end

---Change sell prices to be based on either age or on income
function SeasonsEconomy.inj_placeable_getSellPrice(placeable, superFunc)
    local storeItem = g_storeManager:getItemByXMLFilename(placeable.configFileName)
    local priceMultiplier = 0.5

    if placeable.incomePerHour == 0 then
        local ageFactor = 0.5
        -- for some reason getSellPrice is loaded very early in load before values are loaded from vehicle.xml
        if placeable.seasons_years ~= nil then
            ageFactor = 0.5 - 0.05 * placeable.seasons_years
        end

        if ageFactor > 0.1 then
            priceMultiplier = ageFactor
        else
            priceMultiplier = -0.05
        end
    else
        local daysPerSeason = g_seasons.environment.daysPerSeason

        local annualCost = placeable:getDailyUpkeep() * 4 * daysPerSeason
        local annualIncome = placeable.incomePerHour * 24 * 4 * daysPerSeason
        local annualProfitPriceRatio = (annualIncome - annualCost) / placeable.price

        if annualProfitPriceRatio > 0.1 then
            priceMultiplier = math.min(annualProfitPriceRatio, 0.5)
        else
            priceMultiplier = -0.05
        end
    end

    return math.floor(placeable.price * priceMultiplier)
end

---Update the years (lifetime) every day
function SeasonsEconomy.inj_placeable_dayChanged(placeable)
    if placeable.seasons_years == nil then
        log("SEASONS_YEARS IS NIL OF", placeable.configFileName, placeable.age)
    end
    placeable.seasons_years = placeable.seasons_years + 1 / (4 * g_seasons.environment.daysPerSeason)
end

------------------------------------------------
--- Injections: Silo storage cost
------------------------------------------------

---Update cost of storage and listen to season length change events
function SeasonsEconomy.inj_storage_load(storage, superFunc, ...)
    if superFunc(storage, ...) then
        g_messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, SeasonsEconomy.inj_storage_onSeasonLengthChanged, storage)

        storage.seasons_originalCostsPerFillLevelAndDay = storage.costsPerFillLevelAndDay

        -- TODO: not updated on start of new map?
        storage:onSeasonLengthChanged()

        return true
    end

    return false
end

---Remove the event listening
function SeasonsEconomy.inj_storage_delete(storage)
    g_messageCenter:unsubscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, storage)
end

---Update the cost of storing stuff
function SeasonsEconomy.inj_storage_onSeasonLengthChanged(storage)
    if storage.costsPerFillLevelAndDay ~= 0 then
        local original = storage.seasons_originalCostsPerFillLevelAndDay
        local difficultyFactor = 1 - (2 - g_currentMission.missionInfo.economicDifficulty) * 0.1

        storage.costsPerFillLevelAndDay = original / g_seasons.environment.daysPerSeason * difficultyFactor
    end
end

------------------------------------------------
--- Injections: Animal sale
------------------------------------------------

---Update price to use economic factors
function SeasonsEconomy.inj_animalItem_new(item, superFunc, ...)
    item = superFunc(item, ...)

    -- New item
    if item.animalId == nil then
        item.price = item.subType.storeInfo.buyPrice * g_seasons.economy.data:getAnimalFactor(item.subType.type)
    end

    return item
end
