----------------------------------------------------------------------------------------------------
-- SeasonsForecastFrame
----------------------------------------------------------------------------------------------------
-- Purpose:  The frame for the calendar page in the Seasons menu
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsForecastFrame = {}
local SeasonsForecastFrame_mt = Class(SeasonsForecastFrame, TabbedMenuFrameElement)

SeasonsForecastFrame.SHORT_SLOT = 3

SeasonsForecastFrame.CONTROLS = {
    CONTAINER = "container",
    FORECAST = "forecast",
    TEMPLATE = "forecastColumnTemplate",
}

function SeasonsForecastFrame:new(i18n)
    local self = TabbedMenuFrameElement:new(nil, SeasonsForecastFrame_mt)

    self.i18n = i18n
    self.messageCenter = g_messageCenter
    self.environment = g_seasons.environment
    self.gameEnvironment = g_currentMission.environment
    self.weather = g_seasons.weather

    self:registerControls(SeasonsForecastFrame.CONTROLS)

    -- Weather is not yet loaded when the code here is so can't do this outside the class
    self.forecastIcons = {
        [SeasonsWeather.FORECAST_SUN]           = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_CLEAR},
        [SeasonsWeather.FORECAST_PARTLY_CLOUDY] = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_MIXED},
        [SeasonsWeather.FORECAST_RAIN_SHOWERS]  = {g_seasons.ui.uiFilename, {48, 144, 48, 48}},
        [SeasonsWeather.FORECAST_SNOW_SHOWERS]  = {g_seasons.ui.uiFilename, {96, 144, 48, 48}},
        [SeasonsWeather.FORECAST_SLEET]         = {g_seasons.ui.uiFilename, {0, 144, 48, 48}},
        [SeasonsWeather.FORECAST_CLOUDY]        = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_CLOUDY},
        [SeasonsWeather.FORECAST_RAIN]          = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_RAIN},
        [SeasonsWeather.FORECAST_SNOW]          = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_SNOW},
        [SeasonsWeather.FORECAST_FOG]           = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_FOG},
        [SeasonsWeather.FORECAST_THUNDER]       = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_THUNDER},
        [SeasonsWeather.FORECAST_HAIL]          = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_HAIL},
    }

    self.weatherIcons = {
        [SeasonsWeather.WEATHERTYPE_SUN]        = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_CLEAR},
        [SeasonsWeather.WEATHERTYPE_CLOUDY]     = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_CLOUDY},
        [SeasonsWeather.WEATHERTYPE_RAIN]       = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_RAIN},
        [SeasonsWeather.WEATHERTYPE_SNOW]       = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_SNOW},
        [SeasonsWeather.WEATHERTYPE_FOG]        = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_FOG},
        [SeasonsWeather.WEATHERTYPE_THUNDER]    = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_THUNDER},
        [SeasonsWeather.WEATHERTYPE_HAIL]       = {g_baseHUDFilename, GameInfoDisplay.UV.WEATHER_ICON_HAIL},
    }

    return self
end

function SeasonsForecastFrame:copyAttributes(src)
    SeasonsForecastFrame:superClass().copyAttributes(self, src)

    self.i18n = src.i18n
end

function SeasonsForecastFrame:initialize()
end

function SeasonsForecastFrame:onFrameOpen()
    SeasonsForecastFrame:superClass().onFrameOpen(self)

    self:rebuildTable()

    self.messageCenter:subscribe(SeasonsMessageType.HOUR_CHANGED_FIX, self.onHourChanged, self)
    self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)
end

function SeasonsForecastFrame:onFrameClose()
    SeasonsForecastFrame:superClass().onFrameClose(self)

    self.messageCenter:unsubscribe(SeasonsMessageType.HOUR_CHANGED_FIX, self)
    self.messageCenter:unsubscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self)
end

---Get the frame's main content element's screen size.
function SeasonsForecastFrame:getMainElementSize()
    return self.container.size
end

---Get the frame's main content element's screen position.
function SeasonsForecastFrame:getMainElementPosition()
    return self.container.absPosition
end

----------------------
-- Table building
----------------------

---Rebuild the whole forecast
function SeasonsForecastFrame:rebuildTable(hourFix)
    self.forecast:deleteListItems()

    local today = self.environment.currentDay
    local currentHour = self.gameEnvironment.currentHour

    --- Lower to nearest block
    local currentTimeBlock = math.floor(currentHour / SeasonsForecastFrame.SHORT_SLOT) * SeasonsForecastFrame.SHORT_SLOT

    for i = 1, 16 do
        local day, time, duration = today, 0, SeasonsForecastFrame.SHORT_SLOT

        -- Do slots first, then do days
        if i <= 10 then
            time = currentTimeBlock + (i - 1) * SeasonsForecastFrame.SHORT_SLOT
            if time >= 24 then
                time = time - 24
                day = day + 1
            end
        else
            day = day + (i - 10)
            duration = 24
        end

        -- Weekdays need to match with the weekday names in Finances, so we need to convert to the game day base
        local weekDay = 1 + (day + self.environment.currentDayOffset - 1) % 7

        self:buildColumn(day, time, duration, today, weekDay)
    end

    self.forecast:updateAbsolutePosition()
end

function SeasonsForecastFrame:buildColumn(day, time, duration, today, weekDay)
    local column = self.forecastColumnTemplate:clone(self.forecast)

    local dateCell = column:getDescendantByName("date")
    if day == today then
        dateCell:setText(self.i18n:getText("ui_today"))
    else
        dateCell:setText(self.i18n:getText("seasons_weekday" .. weekDay))
    end

    local timeCell = column:getDescendantByName("time")
    if duration == 3 then
        timeCell:setText(string.format("%02d:00", time))
    else
        timeCell:setText("")
    end

    local forecastInfo = self.weather:getForecast(day, time, duration)
    if forecastInfo == nil then
        return column
    end

    -- Weather type icon
    local typeCell = column:getDescendantByName("type")
    local filename, uvs

    if forecastInfo.forecastType ~= nil then
        filename, uvs = self:getIconForForecastType(forecastInfo.forecastType)
    else
        filename, uvs = self:getIconForWeatherType(forecastInfo.weatherType)
    end

    typeCell:setImageFilename(filename)
    typeCell:setImageUVs(nil, unpack(uvs))

    -- Temperatures
    column:getDescendantByName("lowTemp"):setTemperature(forecastInfo.lowTemp)
    column:getDescendantByName("highTemp"):setTemperature(forecastInfo.highTemp)
    column:getDescendantByName("avgTemp"):setTemperature(forecastInfo.averageTemp)

    local precisionFormatter = "%.1f"
    if duration > 3 then
        precisionFormatter = "%d"
    end

    -- Wind
    column:getDescendantByName("windSpeed"):setText(string.format(precisionFormatter, forecastInfo.windSpeed))

    -- Downfall
    if forecastInfo.precipitationAmount ~= nil then
        column:getDescendantByName("precipitationAmount"):setText(string.format(precisionFormatter, forecastInfo.precipitationAmount))
    end
    if forecastInfo.precipitationChance ~= nil then
        column:getDescendantByName("probabilityOfPrecipitation"):setText(string.format("%d%%", forecastInfo.precipitationChance * 100))
    end

    -- Drying potential
    if forecastInfo.dryingPotential ~= nil then
        column:getDescendantByName("dryingPotential"):setText(self:stringifyDryingPotential(forecastInfo.dryingPotential))
    end

    return column
end

function SeasonsForecastFrame:getIconForForecastType(forecastType)
    local info = self.forecastIcons[forecastType]
    return info[1], getNormalizedUVs(info[2])
end

function SeasonsForecastFrame:getIconForWeatherType(weatherType)
    local info = self.weatherIcons[weatherType]
    return info[1], getNormalizedUVs(info[2])
end

---Create a string representation of the rotDry number
function SeasonsForecastFrame:stringifyDryingPotential(potential)
    if potential <= -9 then
        return "(++)"
    elseif potential <= -2 then
        return "(+)"
    elseif potential <= 0.2 then
        return "(0)"
    elseif potential <= 2 then
        return "(-)"
    else
        return "(--)"
    end
end

----------------------
-- Events
----------------------

---When the season length changes all weather data is reset so we must rebuild
function SeasonsForecastFrame:onSeasonLengthChanged()
    self:rebuildTable()
end

---We have hourly data so update the table to move it along once an hour changed
function SeasonsForecastFrame:onHourChanged()
    self:rebuildTable()
end

SeasonsForecastFrame.L10N_SYMBOL = {
}
