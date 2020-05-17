----------------------------------------------------------------------------------------------------
-- SeasonsWorkshop
----------------------------------------------------------------------------------------------------
-- Purpose:  Adding changing vehicle inside the DirectSellDialog to any in the trigger
--           Credits to LordBanana for the idea.
--           Added to Seasons so it also arrives on console. very useful with the changed
--           repair system in Seasons.
--           Also added repaint button
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsWorkshop = {}

local SeasonsWorkshop_mt = Class(SeasonsWorkshop)

function SeasonsWorkshop:new(mission, gui, i18n)
    local self = setmetatable({}, SeasonsWorkshop_mt)

    self.mission = mission
    self.gui = gui
    self.i18n = i18n

    SeasonsModUtil.appendedFunction(g_directSellDialog.elements[1],     "onCloseCallback",          self.inj_directSellDialog_onClose)
    SeasonsModUtil.appendedFunction(g_directSellDialog.elements[1],     "onOpenCallback",           self.inj_directSellDialog_onOpen)
    SeasonsModUtil.overwrittenFunction(DirectSellDialog,                "onClickMenuExtra1",        self.inj_directSellDialog_onClickMenuExtra1)
    SeasonsModUtil.overwrittenFunction(DirectSellDialog,                "setVehicle",               self.inj_directSellDialog_setVehicle)
    SeasonsModUtil.overwrittenFunction(VehicleSellingPoint,             "onActivateObject",         self.inj_vehicleSellingPoint_onActivateObject)

    return self
end

function SeasonsWorkshop:delete()
end

function SeasonsWorkshop:load()
end

---Install a new button in the workshop dialog to repaint a vehicle
function SeasonsWorkshop:installCustomUI()
    local workshopDialog = g_directSellDialog

    -- Add a new docked button with a new action for repainting
    local repaintElement = workshopDialog.repairButton:clone(workshopDialog)
    repaintElement:setText(self.i18n:getText("seasons_ui_repaint"))
    repaintElement:setInputAction("MENU_EXTRA_1")
    repaintElement.onClickCallback = function(dialog)
        if dialog.vehicle ~= nil then
            local price = dialog.vehicle:getRepaintPrice(true)

            if price >= 1 then
                g_gui:showYesNoDialog({
                    text = string.format(self.i18n:getText("seasons_ui_repaintDialog"), self.i18n:formatMoney(price)),
                    callback = SeasonsWorkshop.inj_directSellDialog_onYesNoRepaintDialog,
                    target = dialog,
                })
                return true
            end
        end

        return false
    end

    workshopDialog.repairButton.parent:addElement(repaintElement)
    workshopDialog.seasons_repaintButton = repaintElement
end

---Remove the button from the workshop dialog
function SeasonsWorkshop:uninstallCustomUI()
    local workshopDialog = g_directSellDialog

    workshopDialog.seasons_repaintButton:unlinkElement()
    workshopDialog.seasons_repaintButton:delete()
end

----------------------
-- Injections
----------------------

-- Register new input
function SeasonsWorkshop.inj_directSellDialog_onOpen(dialog)
    g_inputBinding:removeActionEventsByActionName(InputAction.MENU_PAGE_NEXT)
    g_inputBinding:removeActionEventsByActionName(InputAction.MENU_PAGE_PREV)

    local valid, eventId = g_inputBinding:registerActionEvent(InputAction.MENU_PAGE_NEXT, dialog, SeasonsWorkshop.inj_directSellDialog_switchVehicleEvent, false, true, false, true, 1)
    dialog.seasons_tabbingEventIdNext = eventId
    local valid, eventId = g_inputBinding:registerActionEvent(InputAction.MENU_PAGE_PREV, dialog, SeasonsWorkshop.inj_directSellDialog_switchVehicleEvent, false, true, false, true, -1)
    dialog.seasons_tabbingEventIdPrev = eventId

    g_messageCenter:subscribe(SeasonsMessageType.VEHICLE_REPAINTED, SeasonsWorkshop.inj_directSellDialog_onVehicleRepaintEvent, dialog)
end

-- Unregister input
function SeasonsWorkshop.inj_directSellDialog_onClose(dialog)
    g_inputBinding:removeActionEvent(dialog.seasons_tabbingEventIdNext)
    g_inputBinding:removeActionEvent(dialog.seasons_tabbingEventIdPrev)
end

---Override the passing of a single vehicle to all vehicles.
function SeasonsWorkshop.inj_vehicleSellingPoint_onActivateObject(point, superFunc)
    local oldFunc = g_gui.showDirectSellDialog

    -- Closure so we have the selling point. Override vehicle.
    g_gui.showDirectSellDialog = function(gui, options)
        local vehicles = {}
        local seenVehicles = {}

        for vehicleId, _ in pairs(point.vehicleInRange) do
            local vehicle = g_currentMission.nodeToObject[vehicleId]
            if vehicle ~= nil and seenVehicles[vehicle] == nil then
                seenVehicles[vehicle] = true
                if not SpecializationUtil.hasSpecialization(Rideable, vehicle.specializations) or vehicle:getOwnerFarmId() ~= point:getOwnerFarmId() then
                    table.insert(vehicles, vehicle)
                end
            end
        end

        options.vehicle = vehicles

        return oldFunc(gui, options)
    end

    superFunc(point)

    g_gui.showDirectSellDialog = oldFunc
end

---Adjust for when multiple vehicles are passed from the vehicle selling point
---Update the repaint button state when the vehicle is set
function SeasonsWorkshop.inj_directSellDialog_setVehicle(dialog, superFunc, vehicle, owner, ownWorkshop)
    if vehicle ~= nil and vehicle.configFileName == nil then
        dialog.vehicles = vehicle

        dialog.currentVehicleIndex = 1
        vehicle = vehicle[dialog.currentVehicleIndex]
    end

    superFunc(dialog, vehicle, owner, ownWorkshop)

    if vehicle ~= nil and vehicle.getRepaintPrice ~= nil then
        dialog.seasons_repaintButton:setDisabled(vehicle:getRepaintPrice() < 1)
    else
        dialog.seasons_repaintButton:setDisabled(true)
    end
end

---Event for switching vehicle
function SeasonsWorkshop.inj_directSellDialog_switchVehicleEvent(dialog, _, _, direction)
    local current = dialog.currentVehicleIndex
    dialog.currentVehicleIndex = math.max(math.min(dialog.currentVehicleIndex + direction, #dialog.vehicles), 1)

    if current ~= dialog.currentVehicleIndex then
        -- Change
        dialog:setVehicle(dialog.vehicles[dialog.currentVehicleIndex], dialog.owner, dialog.ownWorkshop)
    end
end

-- Repainting
----------------

---The yes/no dialog for repainting was closed
function SeasonsWorkshop.inj_directSellDialog_onYesNoRepaintDialog(dialog, yes)
    if yes then
        g_client:getServerConnection():sendEvent(SeasonsAgeWearRepaintEvent:new(dialog.vehicle, true))
    end
end

---A vehicle repaint state changed. Update the dialog contents so button state changes.
function SeasonsWorkshop.inj_directSellDialog_onVehicleRepaintEvent(dialog, vehicle, atSellingPoint)
    if vehicle == dialog.vehicle then
        dialog:setVehicle(vehicle)
    end
end

---Due to how the input system works in fs19, the input is not only handled with a click callback but also via these events
function SeasonsWorkshop.inj_directSellDialog_onClickMenuExtra1(dialog, superFunc, ...)
    if superFunc ~= nil then
        superFunc(dialog, ...)
    end

    dialog.seasons_repaintButton.onClickCallback(dialog)
end
