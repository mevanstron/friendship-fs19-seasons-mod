----------------------------------------------------------------------------------------------------
-- SeasonsWeatherForecast
----------------------------------------------------------------------------------------------------
-- Purpose:  Creating the weather forecast for Seasons
-- Authors:  reallogger
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsWeatherForecast = {}

local SeasonsWeatherForecast_mt = Class(SeasonsWeatherForecast)

SeasonsWeatherForecast.UNITTIME = 60 * 60 * 1000 -- ms to hours
SeasonsWeatherForecast.LENGTH = 8
SeasonsWeatherForecast.FORECAST_UNCERTAINTY = true

function SeasonsWeatherForecast:new(data, model, environment, server)
    local self = setmetatable({}, SeasonsWeatherForecast_mt)

    self.paths = {}
    self.data = data
    self.model = model
    self.server = server
    self.environment = environment

    self.items = {}

    return self
end

function SeasonsWeatherForecast:delete()
end

function SeasonsWeatherForecast:load()
    self.prevHighTemp = self.data.startValues.highAirTemp -- initial assumption high temperature during last day of winter.
end

function SeasonsWeatherForecast:loadFromSavegame(xmlFile)
    self.prevHighTemp = Utils.getNoNil(getXMLFloat(xmlFile, "seasons.weather.prevHighTemp"), self.prevHighTemp)

    local i = 0
    while true do
        local key = string.format("seasons.weather.forecast.item(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local item = {}
        item.day = getXMLInt(xmlFile, key .. "#day")
        item.season = getXMLInt(xmlFile, key .. "#season")
        item.averagePeriodTemp = getXMLFloat(xmlFile, key .. "#averagePeriodTemp")
        item.p = getXMLFloat(xmlFile, key .. "#p")
        item.startTimeIndication = getXMLFloat(xmlFile, key .. "#startTimeIndication")
        item.windSpeed = getXMLFloat(xmlFile, key .. "#windSpeed")
        item.windType = getXMLInt(xmlFile, key .. "#windType")
        item.forecastType = getXMLInt(xmlFile, key .. "#forecastType")
        item.cloudCover = getXMLFloat(xmlFile, key .. "#cloudCover")
        item.lowTemp = getXMLFloat(xmlFile, key .. "#lowTemp")
        item.highTemp = getXMLFloat(xmlFile, key .. "#highTemp")
        item.tempUncertainty = getXMLFloat(xmlFile, key .. "#tempUncertainty")
        item.windUncertainty = getXMLFloat(xmlFile, key .. "#windUncertainty")
        item.precipitationUncertainty = getXMLFloat(xmlFile, key .. "#precipitationUncertainty")
        item.weatherTypeUncertainty = getXMLFloat(xmlFile, key .. "#weatherTypeUncertainty")

        table.insert(self.items, item)

        i = i + 1
    end
end

function SeasonsWeatherForecast:saveToSavegame(xmlFile)
    setXMLFloat(xmlFile, "seasons.weather.prevHighTemp", self.prevHighTemp)

    for i, item in ipairs(self.items) do
        local key = string.format("seasons.weather.forecast.item(%d)", i - 1)

        setXMLInt(xmlFile, key .. "#day", item.day)
        setXMLInt(xmlFile, key .. "#season", item.season)
        setXMLFloat(xmlFile, key .. "#averagePeriodTemp", item.averagePeriodTemp)
        setXMLFloat(xmlFile, key .. "#p", item.p)
        setXMLFloat(xmlFile, key .. "#startTimeIndication", item.startTimeIndication)
        setXMLFloat(xmlFile, key .. "#windSpeed", item.windSpeed)
        setXMLInt(xmlFile, key .. "#windType", item.windType)
        setXMLInt(xmlFile, key .. "#forecastType", item.forecastType)
        setXMLFloat(xmlFile, key .. "#cloudCover", item.cloudCover)
        setXMLFloat(xmlFile, key .. "#lowTemp", item.lowTemp)
        setXMLFloat(xmlFile, key .. "#highTemp", item.highTemp)
        setXMLFloat(xmlFile, key .. "#tempUncertainty", item.tempUncertainty)
        setXMLFloat(xmlFile, key .. "#windUncertainty", item.windUncertainty)
        setXMLFloat(xmlFile, key .. "#precipitationUncertainty", item.precipitationUncertainty)
        setXMLFloat(xmlFile, key .. "#weatherTypeUncertainty", item.weatherTypeUncertainty)
    end
end

function SeasonsWeatherForecast:writeStream(streamId, connection)
    -- Prev High Temp is used for the diurnalTemp. We send it once and
    -- then update it when we add new events from the server
    streamWriteFloat32(streamId, self.prevHighTemp)
end

function SeasonsWeatherForecast:readStream(streamId, connection)
    self.prevHighTemp = streamReadFloat32(streamId)
end

function SeasonsWeatherForecast:onItemsLoaded()
    if #self.items == 0 then
        self:build()
    end
end

----------------------
-- Events
----------------------

---Send any initial state. Called once a client joins
function SeasonsWeatherForecast:onClientJoined(connection)
    -- Send the whole forecast
    connection:sendEvent(SeasonsAddWeatherForecastEvent:new(self.items, true))
end

----------------------
-- Building and updating
----------------------

-- Only run this the very first time or if season length changes
function SeasonsWeatherForecast:build()
    local startDayNum = self.environment.currentDay

    self.items = {}
    for i = 1, SeasonsWeatherForecast.LENGTH do
        local forecastItem = self:oneDayForecast(i, self.items[#self.items])

        table.insert(self.items, forecastItem)
    end

    -- Setting windSpeed from forecast when building new forecast
    self.windSpeed = self.items[1].windSpeed
end

---Update the forecast by adding a new item
function SeasonsWeatherForecast:generateNextDay()
    local forecastItem = self:oneDayForecast(SeasonsWeatherForecast.LENGTH, self.items[#self.items])

    self:addItem(forecastItem)

    -- This calls addItem on all clients
    self.server:broadcastEvent(SeasonsAddWeatherForecastEvent:new({forecastItem}, false))
end

---Generate a single day forecast given the previous one and the index
function SeasonsWeatherForecast:oneDayForecast(i, prevDayForecast)
    local dayForecast = {}
    local pPrev = 0.5

    dayForecast.day = self.environment.currentDay + i - 1
    dayForecast.season = self.environment:seasonAtDay(dayForecast.day)

    local growthPeriod = self.environment:periodAtDay(dayForecast.day)
    local periodLength = self.environment.daysPerSeason / 3
    local dayInPeriod = (self.environment:dayInSeasonAtDay(dayForecast.day) - 1) % periodLength + 1

    if dayInPeriod == 1 or prevDayForecast == nil then
        dayForecast.averagePeriodTemp = self.model:calculateAveragePeriodTemp(growthPeriod)
    else
        dayForecast.averagePeriodTemp = prevDayForecast.averagePeriodTemp
    end

    local lowTemp, highTemp = self.model:calculateAirTemp(dayForecast.averagePeriodTemp)
    dayForecast.p = self.model:randomRain(dayForecast.averagePeriodTemp, dayForecast.season, highTemp)

    dayForecast.startTimeIndication = math.random() * 22 + 1 -- avoiding 1 hour before and after midnight
    local startTimeTemp = self:diurnalTemp(dayForecast.startTimeIndication, highTemp, lowTemp, highTemp, lowTemp)
    local avgTemp = (lowTemp + highTemp) / 2

    if i ~= 1 then
        pPrev = prevDayForecast.p
    end

    dayForecast.windSpeed = self.model:calculateWindSpeed(dayForecast.p, pPrev, growthPeriod)
    dayForecast.windType = self:getWindType(dayForecast.windSpeed)
    dayForecast.forecastType, dayForecast.cloudCover = self:getForecastType(dayForecast.day, dayForecast.p, startTimeTemp, avgTemp, dayForecast.windSpeed)

    -- lower daily high temperatures if it is rain, sleet or snow
    if dayForecast.forecastType == SeasonsWeather.FORECAST_SLEET or
            dayForecast.forecastType == SeasonsWeather.FORECAST_RAIN or
            dayForecast.forecastType == SeasonsWeather.FORECAST_SNOW then
        highTemp = avgTemp
    end

    dayForecast.lowTemp = lowTemp
    dayForecast.highTemp = highTemp

    dayForecast.tempUncertainty = 0
    dayForecast.windUncertainty = 0
    dayForecast.weatherTypeUncertainty = 0
    dayForecast.precipitationUncertainty = 0

    if SeasonsWeatherForecast.FORECAST_UNCERTAINTY then
        -- should have used beta distribution instead
        dayForecast.tempUncertainty = MathUtil.clamp(SeasonsMathUtil.normDist(0, 0.15), -1, 1)
        dayForecast.windUncertainty = MathUtil.clamp(SeasonsMathUtil.normDist(0, 0.15), -1, 1)
        dayForecast.weatherTypeUncertainty = MathUtil.clamp(SeasonsMathUtil.normDist(0, 0.2), -1, 1)
        dayForecast.precipitationUncertainty = MathUtil.clamp(SeasonsMathUtil.normDist(0, 0.5), -1, 1)
    end

    return dayForecast
end

---Rebuild a new forecast
function SeasonsWeatherForecast:rebuild()
    self:build()
    self.server:broadcastEvent(SeasonsAddWeatherForecastEvent:new(self.items, true))
end

function SeasonsWeatherForecast:forecastVerified()
    for i = 2, SeasonsWeatherForecast.LENGTH do
        if self.items[i].day ~= self.items[i - 1].day + 1  then
            return false
        end
    end

    return true
end

----------------------
-- Getters
----------------------

function SeasonsWeatherForecast:getWindType(windSpeed)
    if windSpeed < 4 then
        return SeasonsWeather.WINDTYPE_CALM
    elseif windSpeed >= 4 and windSpeed < 8 then
        return SeasonsWeather.WINDTYPE_GENTLE_BREEZE
    elseif windSpeed >= 8 and windSpeed < 14 then
        return SeasonsWeather.WINDTYPE_STRONG_BREEZE
    elseif windSpeed >= 14  then
        return SeasonsWeather.WINDTYPE_GALE
    end
end

function SeasonsWeatherForecast:getForecastType(day, p, temp, avgTemp, windSpeed)
    local period = self.environment:periodAtDay(day)
    local season = self.environment:seasonAtDay(day)

    local probRain = self.data.rainProbability[period]
    local probClouds = self.data.cloudProbability[period]

    -- todo: write manual for weather files
    local probOvercast = math.max(probClouds - 0.2, 0.1)
    local probPartlyCloudy = math.min(probClouds / 2 + 0.55, 1.0)
    local cloudCover = 1 - MathUtil.clamp((p - probOvercast) / (probPartlyCloudy - probOvercast), 0, 1)

    local tempLimit = 3
    local fType = SeasonsWeather.FORECAST_SUN

    if p <= probPartlyCloudy and p > probOvercast then
        if p < probRain and temp >= tempLimit then
            fType = SeasonsWeather.FORECAST_RAIN_SHOWERS
        elseif p < probRain and temp < -tempLimit then
            fType = SeasonsWeather.FORECAST_SNOW_SHOWERS
        else
            fType = SeasonsWeather.FORECAST_PARTLY_CLOUDY
        end

    elseif p <= probOvercast then
        if p < probRain and temp >= tempLimit then
            fType = SeasonsWeather.FORECAST_RAIN
        elseif p < probRain and temp >= -tempLimit and temp < tempLimit then
            fType = SeasonsWeather.FORECAST_SLEET
        elseif p < probRain and temp < -tempLimit then
            fType = SeasonsWeather.FORECAST_SNOW
        else
            fType = SeasonsWeather.FORECAST_CLOUDY
        end
    end

    return fType, cloudCover
end

-- function to output the temperature during the day and night
function SeasonsWeatherForecast:diurnalTemp(currentHour, highTempPrev, lowTemp, highTemp, lowTempNext)
    -- use todays temperatures if nothing is passed
    -- if forecast uncertainty replace with weather
    if highTempPrev == nil or lowTemp == nil or highTemp == nil or lowTempNext == nil then
        local currentItem = self.items[1]
        if currentItem == nil then printCallstack() end
        lowTemp = currentItem.lowTemp
        highTemp = currentItem.highTemp
        lowTempNext = currentItem.lowTemp
        highTempPrev = self.prevHighTemp
    end

    local currentTemp
    if currentHour < 7 then
        currentTemp = (math.cos(((currentHour + 9) / 16) * math.pi / 2)) ^ 2 * (highTempPrev - lowTemp) + lowTemp
    elseif currentHour > 15 then
        currentTemp = (math.cos(((currentHour - 15) / 16) * math.pi / 2)) ^ 2 * (highTemp - lowTempNext) + lowTempNext
    else
        currentTemp = (math.cos((1 - (currentHour -  7) / 8) * math.pi / 2) ^ 2) * (highTemp - lowTemp) + lowTemp
    end

    return currentTemp
end

---Get the whole forecast
function SeasonsWeatherForecast:getForecast()
    return self.items
end

---Get the forecast for given day.
function SeasonsWeatherForecast:getForecastForDay(day)
    local firstDay = self.items[1].day
    return self.items[day - firstDay + 1]
end

---Get forecast item for today
function SeasonsWeatherForecast:getCurrentItem()
    return self.items[1]
end

----------------------
-- Setters from networking
----------------------

---Overwrite the whole forecast table
function SeasonsWeatherForecast:setForecast(items)
    self.items = items
end

---Add a new forecast day, and remove the old ones
function SeasonsWeatherForecast:addItem(item)
    -- Append a new item
    table.insert(self.items, item)
end

function SeasonsWeatherForecast:updateCurrentItem(day)
    if self.items[1].day >= day then
        return
    end

    -- Remove the old item, but update the prevHigh
    while #self.items > 1 and self.items[1].day < day do
        self.prevHighTemp = self.items[1].highTemp
        table.remove(self.items, 1)
    end
end
