----------------------------------------------------------------------------------------------------
-- WaterPump
----------------------------------------------------------------------------------------------------
-- Purpose:  A water pump for animal pens
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

WaterPump = {}
local WaterPump_mt = Class(WaterPump, Placeable)

InitObjectClass(WaterPump, "WaterPump")

function WaterPump:new(isServer, isClient)
    self = Placeable:new(isServer, isClient, WaterPump_mt)
    return self
end

function WaterPump:delete()
    unregisterObjectClassName(self)

    WaterPump:superClass().delete(self)
end

function WaterPump:load(xmlFilename, x,y,z, rx,ry,rz, initRandom)
    if not WaterPump:superClass().load(self, xmlFilename, x,y,z, rx,ry,rz, initRandom) then
        return false
    end

    local xmlFile = loadXMLFile("pump", xmlFilename)

    self.priceScale = Utils.getNoNil(getXMLFloat(xmlFile, "placeable.waterPump#priceScale"), 1)
    self.reachRadius = Utils.getNoNil(getXMLInt(xmlFile, "placeable.waterPump#reachRadius"), 30)

    delete(xmlFile)

    registerObjectClassName(self, "WaterPump")

    return true
end

function WaterPump:finalizePlacement()
    WaterPump:superClass().finalizePlacement(self)

    g_messageCenter:publish(SeasonsMessageType.WATER_PUMP_ADDED, {self})
end

function WaterPump:onSell()
    g_messageCenter:publish(SeasonsMessageType.WATER_PUMP_REMOVED, {self})

    WaterPump:superClass().onSell(self)
end

---Get the radius the pump can reach
function WaterPump:getEffectRadius()
    return self.reachRadius
end

---A number of liters were used
function WaterPump:onWaterUsed(amount)
    if self.isServer then
        local price = amount * g_currentMission.economyManager:getCostPerLiter(FillType.WATER) * self.priceScale
        g_currentMission:addMoney(-price, self:getOwnerFarmId(), MoneyType.ANIMAL_UPKEEP, false)
    end
end
