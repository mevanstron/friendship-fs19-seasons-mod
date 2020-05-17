----------------------------------------------------------------------------------------------------
-- LocalizedTextElement
----------------------------------------------------------------------------------------------------
-- Purpose:  A text element with a localized value: e.g. a temperature
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

LocalizedTextElement = {}
local LocalizedTextElement_mt = Class(LocalizedTextElement, TextElement)

function LocalizedTextElement:new(target, custom_mt)
    local self = TextElement:new(target, custom_mt or LocalizedTextElement_mt)

    self.temperature = nil
    self.temperatureDecimalPlaces = 0

    return self
end

function LocalizedTextElement:loadFromXML(xmlFile, key)
    LocalizedTextElement:superClass().loadFromXML(self, xmlFile, key)

    self.temperatureDecimalPlaces = Utils.getNoNil(getXMLString(xmlFile, key.."#temperatureDecimalPlaces"), self.temperatureDecimalPlaces)

    self:updateSize()
end

function LocalizedTextElement:loadProfile(profile, applyProfile)
    LocalizedTextElement:superClass().loadProfile(self, profile, applyProfile)

    self.temperatureDecimalPlaces = Utils.getNoNil(profile:getValue("temperatureDecimalPlaces"), self.temperatureDecimalPlaces)

    if applyProfile then
        self:updateSize()
    end
end

function LocalizedTextElement:copyAttributes(src)
    LocalizedTextElement:superClass().copyAttributes(self, src)

    self.temperature = src.temperature
    self.temperatureDecimalPlaces  = src.temperatureDecimalPlaces

    if self.temperature ~= nil then
        g_messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_FAHRENHEIT], self.onTemperatureUnitChanged, self)
    end

    self:updateContent()
end

---Reset the localized content
function LocalizedTextElement:resetContent()
    g_messageCenter:unsubscribeAll(self)

    self.temperature = nil
end

---Set the content as a localized temperature display
function LocalizedTextElement:setTemperature(celcius)
    self:resetContent()

    self.temperature = celcius

    if self.temperature ~= nil then
        g_messageCenter:subscribe(MessageType.SETTING_CHANGED[GameSettings.SETTING.USE_FAHRENHEIT], self.onTemperatureUnitChanged, self)
    end

    self:updateContent()
end

---The temperature unit changed: update the text
function LocalizedTextElement:onTemperatureUnitChanged()
    self:updateContent()
end

---Update the text
function LocalizedTextElement:updateContent()
    if self.temperature ~= nil then
        self:setText(g_i18n:formatTemperature(self.temperature, self.temperatureDecimalPlaces))
    else
        self:setText("")
    end
end
