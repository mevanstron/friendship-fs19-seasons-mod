----------------------------------------------------------------------------------------------------
-- SeasonsCutter
----------------------------------------------------------------------------------------------------
-- Purpose:  Update AI of cutters
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsCutter = {}

function SeasonsCutter.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Cutter, specializations)
end

function SeasonsCutter.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setAIFruitRequirements", SeasonsCutter.setAIFruitRequirements)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getAIFruitRequirements", SeasonsCutter.getAIFruitRequirements)
end

---Allow partial cutting into withered and germination failed spots to be more lenient on workers in regular fields.
--This has to be a new spec because we add a new override to the Cutter spec
function SeasonsCutter:setAIFruitRequirements(superFunc, fruitType, minGrowthState, maxGrowthState)
    superFunc(self, fruitType, minGrowthState, maxGrowthState)

    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitType)

    -- Germ failed
    self:addAIFruitRequirement(fruitType, SeasonsGrowth.GERMINATION_FAILED_STATE + 1, SeasonsGrowth.GERMINATION_FAILED_STATE + 1)
    self.spec_aiImplement.requiredFruitTypes[#self.spec_aiImplement.requiredFruitTypes].fromSeasons = true

    -- Withered
    if fruitDesc.witheringNumGrowthStates > fruitDesc.numGrowthStates then
        self:addAIFruitRequirement(fruitType, fruitDesc.maxHarvestingGrowthState + 1, fruitDesc.maxHarvestingGrowthState + 1)
        self.spec_aiImplement.requiredFruitTypes[#self.spec_aiImplement.requiredFruitTypes].fromSeasons = true
    end
end

---Cutter code expects the 1 item. If there used to be 2 (now more), then fail
function SeasonsCutter:getAIFruitRequirements(superFunc)
    local items = superFunc(self)

    if #items >= 2 and #items <= 3 and items[2].fromSeasons and (items[3] == nil or items[3].fromSeasons) then
        return {items[1]}
    else
        return items
    end
end
