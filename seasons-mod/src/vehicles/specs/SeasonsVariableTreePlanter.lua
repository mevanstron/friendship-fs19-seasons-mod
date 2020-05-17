----------------------------------------------------------------------------------------------------
-- SeasonsVariableTreePlanter
----------------------------------------------------------------------------------------------------
-- Purpose:  Adds variable distance for tree planters.
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsVariableTreePlanter = {}

SeasonsVariableTreePlanter.PLANTING_DISTANCES = {}
for i = 2, 20 do
    table.insert(SeasonsVariableTreePlanter.PLANTING_DISTANCES, i)
end

function SeasonsVariableTreePlanter.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(TreePlanter, specializations)
end

function SeasonsVariableTreePlanter.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "setTreePlantDistance", SeasonsVariableTreePlanter.setTreePlantDistance)
end

function SeasonsVariableTreePlanter.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", SeasonsVariableTreePlanter)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", SeasonsVariableTreePlanter)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", SeasonsVariableTreePlanter)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", SeasonsVariableTreePlanter)
end

function SeasonsVariableTreePlanter:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient then
        local spec = self:seasons_getSpecTable("variableTreePlanter")

        self:clearActionEventsTable(spec.actionEvents)

        if isActiveForInputIgnoreSelection then
            local _, actionEventIdToggle = self:addActionEvent(spec.actionEvents, InputAction.IMPLEMENT_EXTRA2, self, SeasonsVariableTreePlanter.actionEventOnToggleTreePlantDistance, false, true, false, true, nil, nil, true)
            g_inputBinding:setActionEventTextVisibility(actionEventIdToggle, true)
            g_inputBinding:setActionEventTextPriority(actionEventIdToggle, GS_PRIO_NORMAL)
            g_inputBinding:setActionEventText(actionEventIdToggle, g_i18n:getText("action_toggle_plant_distance"):format(self.spec_treePlanter.minDistance))
        end
    end
end

function SeasonsVariableTreePlanter:onLoad(savegame)
    local spec = self.spec_treePlanter

    spec.minDistance = SeasonsVariableTreePlanter.PLANTING_DISTANCES[1]

    if savegame ~= nil and not savegame.resetVehicles then
        local key = self:seasons_getSpecSaveKey(savegame.key, "variableTreePlanter")
        spec.minDistance = Utils.getNoNil(getXMLInt(savegame.xmlFile, key .. "#plantingDistance"), spec.minDistance)
    end
end

function SeasonsVariableTreePlanter:onWriteStream(streamId, connection)
    local spec = self.spec_treePlanter
    streamWriteInt8(streamId, spec.minDistance)
end

function SeasonsVariableTreePlanter:onReadStream(streamId, connection)
    local spec = self.spec_treePlanter
    spec.minDistance = streamReadInt8(streamId)
end

function SeasonsVariableTreePlanter:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_treePlanter
    setXMLInt(xmlFile, key .. "#plantingDistance", spec.minDistance)
end

---Sets the current minimum distance for the planter.
---@param distance number
---@param noEventSend boolean
function SeasonsVariableTreePlanter:setTreePlantDistance(distance, noEventSend)
    local spec = self.spec_treePlanter
    if spec.minDistance ~= distance then
        spec.minDistance = distance

        SeasonsVariablePlantDistanceEvent.sendEvent(self, distance, noEventSend)
    end
end

function SeasonsVariableTreePlanter.actionEventOnToggleTreePlantDistance(self, actionName, inputValue, callbackState, isAnalog)
    local distances = SeasonsVariableTreePlanter.PLANTING_DISTANCES
    local max = distances[#distances]

    local spec = self.spec_treePlanter
    if spec.minDistance >= max then
        spec.minDistance = distances[1] - 1 -- reset
    end

    local newDistance = math.min(spec.minDistance + 1, max)

    local specVariableTreePlanter = self:seasons_getSpecTable("variableTreePlanter")
    local actionEvent = specVariableTreePlanter.actionEvents[InputAction.IMPLEMENT_EXTRA2]
    if actionEvent ~= nil then
        g_inputBinding:setActionEventText(actionEvent.actionEventId, g_i18n:getText("action_toggle_plant_distance"):format(newDistance))
    end

    self:setTreePlantDistance(newDistance, false)
end
