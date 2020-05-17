----------------------------------------------------------------------------------------------------
-- SeasonsLivestockTrailer
----------------------------------------------------------------------------------------------------
-- Purpose:  Removes animals when the night passes
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsLivestockTrailer = {}

function SeasonsLivestockTrailer.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(LivestockTrailer, specializations)
end

function SeasonsLivestockTrailer.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "dayChanged", SeasonsLivestockTrailer.dayChanged)
end

function SeasonsLivestockTrailer:dayChanged(superFunc)
    local spec = self.spec_livestockTrailer

    superFunc(self)

    local num = #spec.loadedAnimals

    for i = #spec.loadedAnimals, 1, -1 do
        self:removeAnimal(spec.loadedAnimals[i])
    end

    if num > 0 then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, string.format(g_i18n:getText("seasons_notification_animalsDiedInTrailer"), num))
    end
end
