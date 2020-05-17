----------------------------------------------------------------------------------------------------
-- SeasonsWorkArea
----------------------------------------------------------------------------------------------------
-- Purpose:  Update work areas to only work depending on new ground conditions
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsWorkArea = {}

function SeasonsWorkArea.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(WorkArea, specializations)
end

function SeasonsWorkArea.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsWorkAreaActive", SeasonsWorkArea.getIsWorkAreaActive)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "loadWorkAreaFromXML", SeasonsWorkArea.loadWorkAreaFromXML)
end

function SeasonsWorkArea:getIsWorkAreaActive(superFunc, workArea)
    local spec = self:seasons_getSpecTable("seasonsWorkArea")

    if not superFunc(self, workArea) then
        return false
    end

    if workArea.seasons_ignoresFrozenSoil then
        return true
    end

    if g_seasons.weather:isGroundFrozen() then
        local allowed = g_seasons.vehicle.data:getIsWorkAreaTypeAllowedWithFrozenSoil(workArea.type)
        if not allowed then
            if self.getIsTurnedOn == nil or self:getIsTurnedOn() then
                -- If the ground is frozen, then we might still be allowed to spray certain fillTypes
                if SpecializationUtil.hasSpecialization(Sprayer, self.specializations) then

                    -- Get the current fillType index
                    local fillUnitIndex = self:getSprayerFillUnitIndex()
                    local fillUnitFillType = self:getFillUnitFillType(fillUnitIndex)

                    -- Check configuration to see if this fillType is allowed
                    local fillTypeAllowed = g_seasons.vehicle.fillTypeData:getIsFillTypeAllowedWithFrozenSoil(fillUnitFillType)

                    if fillTypeAllowed then 
                        return true 
                    end 
                end

                g_currentMission:showBlinkingWarning(g_i18n:getText("seasons_warning_soilIsFrozen"))
            end

            return false
        end
    end

    return true
end

function SeasonsWorkArea:loadWorkAreaFromXML(superFunc, workArea, xmlFile, key)
    if not superFunc(self, workArea, xmlFile, key) then
        return false
    end

    workArea.seasons_ignoresFrozenSoil = Utils.getNoNil(getXMLBool(xmlFile, key .. "#ignoresFrozenSoil"), false)

    return true
end
