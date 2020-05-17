----------------------------------------------------------------------------------------------------
-- SeasonsShovel
----------------------------------------------------------------------------------------------------
-- Purpose:  Allow snow handling in contracts
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsShovel = {}

function SeasonsShovel.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Shovel, specializations)
end

function SeasonsShovel.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanShovelAtPosition", SeasonsShovel.canFarmAccessLandOverride)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanDischargeToLand", SeasonsShovel.canFarmAccessLandOverride)
end

---Allow shoveling in missions
function SeasonsShovel:canFarmAccessLandOverride(superFunc, ...)
    local accessHandler = g_currentMission.accessHandler

    local oldFunc = accessHandler.canFarmAccessLand
    accessHandler.canFarmAccessLand = function(handler, farmId, x, z)
        return oldFunc(handler, farmId, x, z) or g_missionManager:getIsMissionWorkAllowed(farmId, x, z)
    end

    local result = superFunc(self, ...)

    accessHandler.canFarmAccessLand = oldFunc

    return result
end
