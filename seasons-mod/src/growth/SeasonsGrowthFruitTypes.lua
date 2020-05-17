----------------------------------------------------------------------------------------------------
-- SeasonsGrowthFruitTypes
----------------------------------------------------------------------------------------------------
-- Purpose: manipulate fruitType data
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsGrowthFruitTypes = {}

local SeasonsGrowthFruitTypes_mt = Class(SeasonsGrowthFruitTypes)

SeasonsGrowthFruitTypes.DEFAULT_GERMINATION_TEMP = 5
SeasonsGrowthFruitTypes.DEFAULT_GERMINATION_SOIL_MOISTURE = 1 -- not currently used
SeasonsGrowthFruitTypes.DEFAULT_MAX_FERTILISE_STATE = 4
SeasonsGrowthFruitTypes.WEED_YOUNG_DAMAGE_STATE = 4
SeasonsGrowthFruitTypes.WEED_MATURE_DAMAGE_STATE = 5
SeasonsGrowthFruitTypes.WEED_DEFAULT_WITHER_SOIL_TEMP = 1
SeasonsGrowthFruitTypes.WEED_DEFAULT_MATURE_SOIL_TEMP = 10
SeasonsGrowthFruitTypes.DEFAULT_YOUNG_PLANT_MAX_STATE = 4
SeasonsGrowthFruitTypes.DEFAULT_RESISTANCE_FACTOR = 4


function SeasonsGrowthFruitTypes:new(mission, messageCenter, fruitTypeManager)
    local self = setmetatable({}, SeasonsGrowthFruitTypes_mt)

    self.mission = mission
    self.messageCenter = messageCenter
    self.fruitTypeManager = fruitTypeManager

    return self
end

function SeasonsGrowthFruitTypes:delete()
    self.mission = nil
    self.messageCenter = nil
    self.fruitTypeManager = nil
end

function SeasonsGrowthFruitTypes:load()
    self:disableBasegameGrowth()
    self:minimizeHarvestDuration()
    self:setFruitTypeDefaultValues()
    self:loadDataFromFiles()
end

function SeasonsGrowthFruitTypes:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("xml", path.file)
        if xmlFile then
            self:loadDataFromFile(xmlFile)
            delete(xmlFile)
        end
    end
end

--load fruitTypes section of crops.xml
function SeasonsGrowthFruitTypes:loadDataFromFile(xmlFile)
    local i = 0

    while true do
        local key = string.format("crops.fruitTypes.fruitType(%d)", i)
        if not hasXMLProperty(xmlFile, key) then break end

        local fruitName = (getXMLString(xmlFile, key .. "#name")):upper()

        if fruitName == nil then
            Logging.error("SeasonsGrowthFruitTypes:loadDataFromFile fruitTypes section is not defined correctly")
            break
        end

        local fruitType = self.fruitTypeManager:getFruitTypeByName(fruitName)

        -- Fruit type is nil if a fruit is not in the map but is in the GEO.
        if fruitType ~= nil and self.mission.fruits[fruitType.index] ~= nil then
            --TODO remove magic values
            fruitType.plantsWeed = Utils.getNoNil(getXMLBool(xmlFile, key .. ".cultivation#plantsWeed"), fruitType.plantsWeed)
            fruitType.growthRequiresLime = Utils.getNoNil(getXMLBool(xmlFile, key .. ".growth#growthRequiresLime"), fruitType.growthRequiresLime)
            fruitType.germinateTemp = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".growth#germinateTemp"), fruitType.germinateTemp)
            fruitType.germinatesoilMoisture = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".growth#germinatesoilMoisture"), fruitType.germinatesoilMoisture)
            fruitType.maxFertiliseState = Utils.getNoNil(getXMLInt(xmlFile, key .. ".growth#maxFertiliseState"), fruitType.maxFertiliseState)
            fruitType.consumesLime = Utils.getNoNil(getXMLBool(xmlFile, key .. ".options#consumesLime"), fruitType.consumesLime)
            fruitType.lowSoilDensityRequired = Utils.getNoNil(getXMLBool(xmlFile, key .. ".options#lowSoilDensityRequired"), fruitType.lowSoilDensityRequired)
            fruitType.increasesSoilDensity = Utils.getNoNil(getXMLBool(xmlFile, key .. ".options#increasesSoilDensity"), fruitType.increasesSoilDensity)
            fruitType.seedDamageState = SeasonsGrowth.GERMINATION_FAILED_STATE

            if fruitType.index == FruitType.WEED then
                fruitType.youngPlantDamageState = SeasonsGrowthFruitTypes.WEED_YOUNG_DAMAGE_STATE
                fruitType.maturePlantDamageState = SeasonsGrowthFruitTypes.WEED_MATURE_DAMAGE_STATE
                fruitType.weedWitherSoilTemp = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".options#weedWitherSoilTemp"), fruitType.weedWitherSoilTemp)
                fruitType.weedMatureSoilTemp = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".options#weedMatureSoilTemp"), fruitType.weedMatureSoilTemp)
            else
                fruitType.youngPlantDamageState = Utils.getNoNil(getXMLInt(xmlFile, key .. ".growth#youngPlantDamageState"), fruitType.youngPlantDamageState)
                fruitType.maturePlantDamageState = Utils.getNoNil(getXMLInt(xmlFile, key .. ".growth#maturePlantDamageState"), fruitType.maturePlantDamageState)
            end

            fruitType.youngPlantMaxState = Utils.getNoNil(getXMLInt(xmlFile, key .. ".growth#youngPlantMaxState"), fruitType.youngPlantMaxState)
            fruitType.maturePlantMinState = fruitType.youngPlantMaxState + 1

            fruitType.seedDroughtResistanceFactor = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".options#seedDroughtResistanceFactor"), fruitType.seedDroughtResistanceFactor)
            fruitType.youngPlantDroughtResistanceFactor = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".options#youngPlantDroughtResistanceFactor"), fruitType.youngPlantDroughtResistanceFactor)
            fruitType.maturePlantDroughtResistanceFactor = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".options#maturePlantDroughtResistanceFactor"), fruitType.maturePlantDroughtResistanceFactor)
            fruitType.seedFrostResistanceFactor = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".options#seedFrostResistanceFactor"), fruitType.seedFrostResistanceFactor)
            fruitType.youngPlantFrostResistanceFactor = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".options#youngPlantFrostResistanceFactor"), fruitType.youngPlantFrostResistanceFactor)
            fruitType.maturePlantFrostResistanceFactor = Utils.getNoNil(getXMLFloat(xmlFile, key .. ".options#maturePlantFrostResistanceFactor"), fruitType.maturePlantFrostResistanceFactor)

            local category = getXMLString(xmlFile, key .. ".rotation#category")
            if category ~= nil and SeasonsCropRotation.CATEGORIES[category] ~= nil then
                fruitType.rotation.category = SeasonsCropRotation.CATEGORIES[category]
            end
            fruitType.rotation.returnPeriod = Utils.getNoNil(getXMLInt(xmlFile, key .. ".rotation#returnPeriod"), fruitType.rotation.returnPeriod)
        end

        i = i + 1
    end
end

function SeasonsGrowthFruitTypes:setDataPaths(growthPaths)
    self.paths = growthPaths
end

---Disable basegame growth by disabling the growth rate and locking it
function SeasonsGrowthFruitTypes:disableBasegameGrowth()
    Logging.info("Disabling base game growth")
    self.mission:setPlantGrowthRate(0)
    self.mission.plantGrowthRateIsLocked = true
end

---Change the fruits to have a minimal harvest duration and maximal growth time to space out
-- usage of textures. No need to undo this, as the fruit types are reloaded by the game.
function SeasonsGrowthFruitTypes:minimizeHarvestDuration()
    local fruitsToExclude = {}

    -- No updates for these fruits
    fruitsToExclude[FruitType.POPLAR] = true
    fruitsToExclude[FruitType.OILSEEDRADISH] = true
    fruitsToExclude[FruitType.DRYGRASS] = true
    fruitsToExclude[FruitType.GRASS] = true
    fruitsToExclude[FruitType.WEED] = true

    for index, fruit in pairs(self.mission.fruits) do
        if not fruitsToExclude[index] then
            local fruitType = self.fruitTypeManager:getFruitTypeByIndex(index)
            if fruitType.minPreparingGrowthState == -1 then
                -- Minimize the time a crop can be harvested (1 state, not ~3)
                if fruitType.originalMinHarvestingGrowthState == nil then
                    fruitType.originalMinHarvestingGrowthState = fruitType.minHarvestingGrowthState
                end

                fruitType.minHarvestingGrowthState = fruitType.maxHarvestingGrowthState
            else
                -- Handle preparingGrowthState properly for sugarcane, sugarbeet and potatoes (and other similar fruits)
                if fruitType.originalMinPreparingGrowthState == nil then
                    fruitType.originalMinPreparingGrowthState = fruitType.minPreparingGrowthState
                end

                fruitType.minPreparingGrowthState = fruitType.maxPreparingGrowthState
            end
        end
    end
end

function SeasonsGrowthFruitTypes:setFruitTypeDefaultValues()
    local fruitsToExclude = {}
    -- No updates for these fruits
    fruitsToExclude[FruitType.DRYGRASS] = true

    for index, fruit in pairs(self.mission.fruits) do
        if not fruitsToExclude[index] then

            local fruitType = self.fruitTypeManager:getFruitTypeByIndex(index)

            fruitType.germinateTemp = SeasonsGrowthFruitTypes.DEFAULT_GERMINATION_TEMP
            fruitType.germinatesoilMoisture = SeasonsGrowthFruitTypes.DEFAULT_GERMINATION_SOIL_MOISTURE
            fruitType.maxFertiliseState = SeasonsGrowthFruitTypes.DEFAULT_MAX_FERTILISE_STATE

            if fruitType.index == FruitType.WEED then
                fruitType.weedWitherSoilTemp = SeasonsGrowthFruitTypes.WEED_DEFAULT_WITHER_SOIL_TEMP
                fruitType.weedMatureSoilTemp = SeasonsGrowthFruitTypes.WEED_DEFAULT_MATURE_SOIL_TEMP
            else
                fruitType.youngPlantDamageState = fruitType.cutState + 1
                fruitType.maturePlantDamageState = fruitType.witheringNumGrowthStates
            end

            fruitType.youngPlantMaxState = SeasonsGrowthFruitTypes.DEFAULT_YOUNG_PLANT_MAX_STATE
            fruitType.seedDroughtResistanceFactor = SeasonsGrowthFruitTypes.DEFAULT_RESISTANCE_FACTOR
            fruitType.youngPlantDroughtResistanceFactor = SeasonsGrowthFruitTypes.DEFAULT_RESISTANCE_FACTOR
            fruitType.maturePlantDroughtResistanceFactor = SeasonsGrowthFruitTypes.DEFAULT_RESISTANCE_FACTOR
            fruitType.seedFrostResistanceFactor = SeasonsGrowthFruitTypes.DEFAULT_RESISTANCE_FACTOR
            fruitType.youngPlantFrostResistanceFactor = SeasonsGrowthFruitTypes.DEFAULT_RESISTANCE_FACTOR
            fruitType.maturePlantFrostResistanceFactor = SeasonsGrowthFruitTypes.DEFAULT_RESISTANCE_FACTOR

            fruitType.rotation = {}
            fruitType.rotation.category = SeasonsCropRotation.CATEGORIES.CEREAL
            fruitType.rotation.returnPeriod = 1
        end
    end
end
