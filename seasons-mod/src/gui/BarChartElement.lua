----------------------------------------------------------------------------------------------------
-- BarChartElement
----------------------------------------------------------------------------------------------------
-- Purpose:  An element that shows a bar chart
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

BarChartElement = {}
local BarChartElement_mt = Class(BarChartElement, BitmapElement)

function BarChartElement:new(target, custom_mt)
    local self = BitmapElement:new(target, custom_mt or BarChartElement_mt)

    self.minValue = 0
    self.maxValue = 1
    self.activeX = nil
    self.data = {}

    return self
end

function BarChartElement:loadFromXML(xmlFile, key)
    BarChartElement:superClass().loadFromXML(self, xmlFile, key)

end

function BarChartElement:loadProfile(profile, applyProfile)
    BarChartElement:superClass().loadProfile(self, profile, applyProfile)

end

function BarChartElement:copyAttributes(src)
    BarChartElement:superClass().copyAttributes(self, src)

end




function BarChartElement:setData(data)
    self.data = data
end

---Set the minimum value shown on the Y axis
function BarChartElement:setMinValue(value)
    self.minValue = value
end

---Set the maximum value shown on the Y axis
function BarChartElement:setMaxValue(value)
    self.maxValue = value
end

function BarChartElement:setActiveX(value)
    self.activeX = value
end


function BarChartElement:updateAbsolutePosition()
    BarChartElement:superClass().updateAbsolutePosition(self)
end

function BarChartElement:draw()
    -- local xOffset, yOffset = self:getOffset()
    -- GuiOverlay.renderOverlay(self.overlay, self.absPosition[1]+xOffset, self.absPosition[2]+yOffset, self.size[1], self.size[2], self:getOverlayState())

    BarChartElement:superClass():superClass().draw(self)

    local marginX, marginY = getNormalizedScreenValues(20, 20)
    local lineWidth, lineHeight = getNormalizedScreenValues(1, 1)
    lineHeight = math.max(lineHeight, 1 / g_screenHeight)
    lineWidth = math.max(lineWidth, 1 / g_screenWidth)

    local axisWidth, axisHeight = getNormalizedScreenValues(2, 2)
    local nudgeWidth, nudgeHeight = getNormalizedScreenValues(8, 8)
    local valueWidth = self.size[1] / #self.data

    self.overlay.color = {0.5, 0.5, 0.5, 1}

    -- left axis
    GuiOverlay.renderOverlay(self.overlay, self.absPosition[1] - lineWidth, self.absPosition[2], axisWidth, self.size[2])

    -- bottom axis
    GuiOverlay.renderOverlay(self.overlay, self.absPosition[1] - lineWidth, self.absPosition[2], self.size[1], axisHeight)

    setTextAlignment(RenderText.ALIGN_RIGHT)

    local _, axisTextSize = getNormalizedScreenValues(0, 18)
    local textHeight = getTextHeight(axisTextSize, "1")

    if self.maxValue > 0 then
        -- Draw axis values

        local segmentHeight = self.size[2] / 5
        local segmentValue = (self.maxValue - self.minValue) / 5

        for i = 0, 5 do
            -- Small nudge
            GuiOverlay.renderOverlay(self.overlay, self.absPosition[1] - nudgeWidth, self.absPosition[2] + i * segmentHeight, nudgeWidth, lineHeight)

            -- Text
            renderText(
                self.absPosition[1] - 2 * nudgeWidth,
                self.absPosition[2] + i * segmentHeight - textHeight / 2.3,
                axisTextSize,
                tostring(math.floor(segmentValue * i + self.minValue))
                )
        end

        local valueFactor = (self.size[2] - lineHeight) / (self.maxValue - self.minValue)
        for x, value in ipairs(self.data) do

            if x == self.activeX then
                self.overlay.color = {0.2195, 0.2346, 0.0273, 1}
            else
                self.overlay.color = {0.6172, 0.4072, 0.0782, 1}
            end

            GuiOverlay.renderOverlay(self.overlay,
                self.absPosition[1] + valueWidth * (x - 1),
                self.absPosition[2] + lineHeight,
                valueWidth - lineWidth,
                (value - self.minValue) * valueFactor
                )
        end
    end

    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end
