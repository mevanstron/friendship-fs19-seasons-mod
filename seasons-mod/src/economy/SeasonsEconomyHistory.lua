----------------------------------------------------------------------------------------------------
-- SeasonsEconomyHistory
----------------------------------------------------------------------------------------------------
-- Purpose:  1-year history of the economy to be displayed as feedback to the player
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsEconomyHistory = {}

local SeasonsEconomyHistory_mt = Class(SeasonsEconomyHistory)

SeasonsEconomyHistory.TYPE = {}
SeasonsEconomyHistory.TYPE.FILL = 1
SeasonsEconomyHistory.TYPE.ANIMAL = 2
SeasonsEconomyHistory.TYPE.BALE = 3

SeasonsEconomyHistory.SEND_NUM_BITS_PRICE = 8

function SeasonsEconomyHistory.installSpecializations()
    SeasonsModUtil.overwrittenFunction(AIVehicle, "onUpdateTick", SeasonsEconomyHistory.inj_aiVehicle_onUpdateTick)
end

function SeasonsEconomyHistory:new(mission, messageCenter, environment, fillTypeManager, animalManager, data)
    local self = setmetatable({}, SeasonsEconomyHistory_mt)

    self.mission = mission
    self.messageCenter = messageCenter
    self.fillTypeManager = fillTypeManager
    self.environment = environment
    self.animalManager = animalManager
    self.economyData = data

    self.data = {}

    return self
end

function SeasonsEconomyHistory:delete()
    self.messageCenter:unsubscribeAll(self)
end

function SeasonsEconomyHistory:load()
    self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)
    self.messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
end

function SeasonsEconomyHistory:loadFromSavegame(xmlFile)
    local i = 0
    while true do
        local key = string.format("seasons.economy.history.fill(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local name = getXMLString(xmlFile, key .. "#fillType")
        local str = getXMLString(xmlFile, key .. ".values")
        if name ~= nil and str ~= nil then
            local values = StringUtil.parseList(str, ";", tonumber)

            local index = self.fillTypeManager:getFillTypeIndexByName(name)
            if index ~= nil then -- Ignore any values not currently loaded
                self.data[index] = values
            end
        end

        i = i + 1
    end
end

function SeasonsEconomyHistory:saveToSavegame(xmlFile)
    local i = 0
    for fillType, values in pairs(self.data) do
        local key = string.format("seasons.economy.history.fill(%d)", i)

        setXMLString(xmlFile, key .. "#fillType", self.fillTypeManager:getFillTypeNameByIndex(fillType))

        local str = table.concat(values, ";")
        setXMLString(xmlFile, key .. ".values", str)

        i = i + 1
    end
end

---Send the whole history in a compressed manner: send min and max of each fillType and 8bit positions
function SeasonsEconomyHistory:writeStream(streamId, connection)
    streamWriteUIntN(streamId, ListUtil.size(self.data), FillTypeManager.SEND_NUM_BITS)

    for fillTypeIndex, values in pairs(self.data) do
        streamWriteUIntN(streamId, fillTypeIndex, FillTypeManager.SEND_NUM_BITS)

        -- Find min, send
        local minValue = luafp.reduce(values, math.min, math.huge)
        streamWriteFloat32(streamId, minValue)

        -- Find max, send
        local maxValue = luafp.reduce(values, math.max, 0)
        streamWriteFloat32(streamId, maxValue)

        streamWriteUIntN(streamId, #values, 7)

        for _, price in ipairs(values) do
            NetworkUtil.writeCompressedRange(streamId, price, minValue, maxValue, SeasonsEconomyHistory.SEND_NUM_BITS_PRICE)
        end
    end
end

function SeasonsEconomyHistory:readStream(streamId, connection)
    local numTypes = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)

    for i = 1, numTypes do
        local fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)

        local minValue = streamReadFloat32(streamId)
        local maxValue = streamReadFloat32(streamId)
        local numValues = streamReadUIntN(streamId, 7)

        local values = {}
        for j = 1, numValues do
            values[j] = NetworkUtil.readCompressedRange(streamId, minValue, maxValue, SeasonsEconomyHistory.SEND_NUM_BITS_PRICE)
        end

        self.data[fillTypeIndex] = values
    end
end

---We need all items (also unloading stations) to be loaded
function SeasonsEconomyHistory:onGameLoaded()
    local currentDay = self.environment:currentDayInYear()

    for index, fillDesc in pairs(self.fillTypeManager:getFillTypes()) do
        fillDesc.seasons_economyType = self:getEconomyType(fillDesc)

        if fillDesc.seasons_economyType ~= nil then
            local values = Utils.getNoNil(self.data[index], {})

            -- Make sure there are values for a whole year
            for i = 1, self.environment.daysPerSeason * 4 do
                if values[i] == nil then
                    if i == currentDay then
                        values[i] = self:getPrice(fillDesc)
                    else
                        values[i] = self:getSimulatedPrice(fillDesc, i)
                    end
                end
            end

            self.data[index] = values
        end
    end
end

------------------------------------------------
--- Events
------------------------------------------------

---When the season length changes we have to change the values as they are day based.
-- More days means we need more values, and vice versa. We do this by throwing away data
-- or generating data between existing data.
function SeasonsEconomyHistory:onSeasonLengthChanged()
    local newSize = self.environment.daysPerSeason * 4

    for index, fillDesc in pairs(self.fillTypeManager:getFillTypes()) do
        if fillDesc.seasons_economyType ~= nil then
            local oldSize = #self.data[index]

            if newSize > oldSize then
                self.data[index] = self:expandedArray(self.data[index], newSize)
            elseif newSize < oldSize then
                self.data[index] = self:contractedArray(self.data[index], newSize)
            end
        end
    end
end

---Expand given array of values to the new size, filling in values as guesses.
function SeasonsEconomyHistory:expandedArray(list, newSize)
    local data = {}
    local oldSize = #list
    local expansionFactor = oldSize / newSize

    for i = 1, newSize do
        -- Interpolate value
        local location = (i - 1) * expansionFactor + 1

        -- Find value left and right of the new value
        local left = list[math.max(math.floor(location), 1)]
        local right = list[math.min(math.ceil(location), oldSize)]
        local alpha = location % 1

        -- Add new data point
        data[i] = (right - left) * alpha + left
    end

    return data
end

---Contract an array to given size by removing values
function SeasonsEconomyHistory:contractedArray(list, newSize)
    local data = {}
    local oldSize = #list
    local contractionFactor = oldSize / newSize

    for i = 1, newSize do
        -- Get average value of section this value replaces
        local left = math.max(math.floor((i - 1) * contractionFactor + 1), 1)
        local right = math.min(math.ceil(i * contractionFactor), oldSize)

        local sum = 0
        for j = left, right do
            sum = sum + list[j]
        end

        data[i] = sum / (right - left + 1)
    end

    return data
end

---Update the new price when the day changes
function SeasonsEconomyHistory:onDayChanged()
    if self.mission:getIsServer() then
        local currentDay = self.environment:currentDayInYear()
        local eventData = {}

        for index, fillDesc in pairs(self.fillTypeManager:getFillTypes()) do
            if fillDesc.seasons_economyType ~= nil then
                local price = self:getPrice(fillDesc)
                self.data[index][currentDay] = price
                eventData[index] = price
            end
        end

        SeasonsEconomyHistoryEvent:sendEvent(currentDay, eventData)
    end
end

---Received history from event
function SeasonsEconomyHistory:onReceivedHistory(day, prices)
    for index, fillDesc in pairs(self.fillTypeManager:getFillTypes()) do
        if fillDesc.seasons_economyType ~= nil then
            self.data[index][day] = prices[index] or 0
        end
    end
end

------------------------------------------------
--- Getters
------------------------------------------------

---Get the type of economic object the fill belongs to (fill, bale, animal)
function SeasonsEconomyHistory:getEconomyType(fillDesc)
    if fillDesc.showOnPriceTable then
        if fillDesc.index == FillType.GRASS_WINDROW then
            return nil
        else
            local fillType = self.economyData.repricing.fillTypes[fillDesc.name]
            local bale = self.economyData.repricing.bales[fillDesc.name]

            if fillType ~= nil and fillType.allZero and bale ~= nil then
                return SeasonsEconomyHistory.TYPE.BALE
            end
        end

        return SeasonsEconomyHistory.TYPE.FILL
    end

    local animalType = self.animalManager:getAnimalByFillType(fillDesc.index)
    if animalType ~= nil then
        -- The horse has no economy. Skip syncing, displaying, and so on.
        if animalType.type ~= "HORSE" then
            return SeasonsEconomyHistory.TYPE.ANIMAL
        end
    end

    return nil
end

---Get the current price of a fill. This is the average price over all sell stations that accept the fill
-- For animal prices the value is per animal, for others it is per 1000 liters.
function SeasonsEconomyHistory:getPrice(fillDesc)
    local fillType = fillDesc.index

    if fillDesc.seasons_economyType == SeasonsEconomyHistory.TYPE.ANIMAL then
        local animal = self.animalManager:getAnimalByFillType(fillType)
        return animal.storeInfo.pricePerKg * self.economyData:getAnimalFactor(animal.type)
    else
        local toolType = ToolType.UNDEFINED
        if fillDesc.seasons_economyType == SeasonsEconomyHistory.TYPE.BALE then
            toolType = ToolType.BALE
        end

        local numPrices, totalPrice = 0, 0

        -- Average every price in selling stations
        for _, unloadingStation in pairs(self.mission.storageSystem:getUnloadingStations()) do
            local isSellplace = unloadingStation.owningPlaceable ~= nil and unloadingStation.isSellingPoint
            if isSellplace and unloadingStation.acceptedFillTypes[fillType] then
                totalPrice = totalPrice + unloadingStation:getEffectiveFillTypePrice(fillType, toolType)
                numPrices = numPrices + 1
            end
        end

        if numPrices == 0 then
            return 0
        else
            return 1000 * totalPrice / numPrices -- 1000 liter
        end
    end

    return 0
end

---Get the simulated price: the price we expect it to be on an average year based on the base price and seasonal factors
-- For animal prices the value is per animal, for others it is per 1000 liters.
function SeasonsEconomyHistory:getSimulatedPrice(fillDesc, day)
    local multiplier = EconomyManager.getPriceMultiplier()

    if fillDesc.seasons_economyType == SeasonsEconomyHistory.TYPE.FILL then
        return 1000 * fillDesc.pricePerLiter * self.economyData:getFillTypeFactor(fillDesc.index, day) * multiplier
    elseif fillDesc.seasons_economyType == SeasonsEconomyHistory.TYPE.ANIMAL then
        local animal = self.animalManager:getAnimalByFillType(fillDesc.index)
        return animal.storeInfo.pricePerKg * self.economyData:getAnimalFactor(animal.type, day)
    elseif fillDesc.seasons_economyType == SeasonsEconomyHistory.TYPE.BALE then
        return 1000 * fillDesc.pricePerLiter * self.economyData:getBaleFactor(fillDesc.index, day) * multiplier
    end

    return 0
end

function SeasonsEconomyHistory:getHistory(fillType)
    return self.data[fillType]
end
