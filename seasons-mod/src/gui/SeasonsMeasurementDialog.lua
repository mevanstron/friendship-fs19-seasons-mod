----------------------------------------------------------------------------------------------------
-- SeasonsMeasurementDialog
----------------------------------------------------------------------------------------------------
-- Purpose:  Dialog that shows measurements
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsMeasurementDialog = {}

SeasonsMeasurementDialog.CONTROLS = {
    "dialogTitleElement",
    "measurementsList",
    "template",
}

local SeasonsMeasurementDialog_mt = Class(SeasonsMeasurementDialog, DialogElement)

function SeasonsMeasurementDialog:new(target, custom_mt)
    local self = DialogElement:new(target, custom_mt or SeasonsMeasurementDialog_mt)

    self.isBackAllowed = false
    self.inputDelay = 250

    self:registerControls(SeasonsMeasurementDialog.CONTROLS)

    return self
end

function SeasonsMeasurementDialog:onOpen()
    SeasonsMeasurementDialog:superClass().onOpen(self)
    self.inputDelay = self.time + 250
end

function SeasonsMeasurementDialog:onClickBack(forceBack, usedMenuButton)
    self:playSample(GuiSoundPlayer.SOUND_SAMPLES.BACK)
    self:sendCallback(false)
    return false -- -> event is used
end

function SeasonsMeasurementDialog:sendCallback(value)
    if self.inputDelay < self.time then -- ignore input for a brief time to avoid accidental triggering
        self:close()
        if self.callbackFunc ~= nil then
            if self.target ~= nil then
                self.callbackFunc(self.target, value)
            else
                self.callbackFunc(value)
            end
        end
    end
end

function SeasonsMeasurementDialog:setCallback(callbackFunc, target)
    self.callbackFunc = callbackFunc
    self.target = target
end

function SeasonsMeasurementDialog:setContent(list)
    self.listContent = list
    self:updateContent()
end

function SeasonsMeasurementDialog:updateContent()
    self.measurementsList:deleteListItems()

    for _, item in ipairs(self.listContent) do
        local row = self.template:clone(self.measurementsList)

        local image = row:getDescendantByName("image")
        local text = row:getDescendantByName("text")

        text:setText(item.text)
        if item.iconUVs ~= nil then
            image:setImageUVs(nil, unpack(getNormalizedUVs(item.iconUVs)))
            image:setVisible(true)
        else
            image:setVisible(false)
        end

        row:updateAbsolutePosition()
    end
end

function SeasonsMeasurementDialog:addData(item)
    table.insert(self.listContent, item)
    self:updateContent()
end
