----------------------------------------------------------------------------------------------------
-- SeasonsWeatherModel
----------------------------------------------------------------------------------------------------
-- Purpose:  A collection on functions that together defines the weather model for Seasons
-- Authors:  reallogger
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsWeatherModel = {}

local SeasonsWeatherModel_mt = Class(SeasonsWeatherModel)

function SeasonsWeatherModel:new(data, environment, mission)
    local self = setmetatable({}, SeasonsWeatherModel_mt)

    self.data = data
    self.environment = environment
    self.mission = mission

    return self
end

function SeasonsWeatherModel:delete()
end

function SeasonsWeatherModel:load()
end

-- function to calculate relative humidity
-- http://onlinelibrary.wiley.com/doi/10.1002/met.258/pdf
function SeasonsWeatherModel:calculateRelativeHumidity(currentTemp, lowTemp, dropScale, mist, print)
    local dewPointTemp = lowTemp - (10 - 9 * mist)
    local es = 6.1078 - math.exp(17.2669 * dewPointTemp / (dewPointTemp + 237.3))
    local e = 6.1078 - math.exp(17.2669 * currentTemp / (currentTemp + 237.3))

    local rh = 100 * e / es
    local relativeHumidity = rh + (100 - rh) * dropScale --math.max(dropScale, fogScale / SeasonsWeather.FOGSCALE)

    if print then
        -- log(currentTemp, relativeHumidity, rh, dropScale, fogScale/SeasonsWeather.FOGSCALE)
    end

    return MathUtil.clamp(relativeHumidity, 5, 100)
end

function SeasonsWeatherModel:calculateSoilWaterContent(prevSoilWaterCont, currentTemp, lowTemp, meltedSnow, snowDepth, isGroundFrozen)
    --Soil moisture bucket model
    --Guswa, A. J., M. A. Celia, and I. Rodriguez-Iturbe, Models of soil moisture dynamics in ecohydrology: A comparative study,
    --Water Resour. Res., 38(9), 1166, doi:10.1029/2001WR000826, 2002

    -- every hour air temperature < 5 deg, or solarRadiation < 1.5, no transpiration

    -- note: not for simulation as takes day, dayTime and cloudCoverage directly
    local julianDay = self.environment.daylight:getCurrentJulianDay()
    local dayTime = self.mission.environment.dayTime / 60 / 60 / 1000 --current time in hours
    local cloudCoverage = self.mission.environment.weather.cloudUpdater.currentCloudCoverage

    -- constants
    local depthRootZone = 20 -- cm
    local Ksat = 109.8 / 24 -- saturated conductivity cm/day | divided by 24 due to update every hour
    local Sfc = 0.29 -- field capacity, gravity drainage becomes negligible compared to evotranspiration when saturation is above
    local beta = 9.0 -- drainage curve parameter
    local soilPorosity = 0.42
    local stomatalSaturation = 0.105 -- evotranspiration reaches maximum when saturation is above this value
    local wiltingSaturation = 0.036 -- if saturation is below this value the plant wilts
    local hygroscopicSaturation = 0.02 -- if saturation is below this value evaporation stops
    local maxEvaporation = 0.15 / self.environment.daysPerSeason -- cm/day | gameification with daysInSeason
    local maxTranspiration = 0.325 / self.environment.daysPerSeason -- cm/day | gameification with daysInSeason

    -- update variables
    local relativeHumidity = self:calculateRelativeHumidity(currentTemp, lowTemp, 0, 0)
    local solarRadiation = self.environment.daylight:getCurrentSolarRadiation(julianDay, dayTime, cloudCoverage)
    local soilWaterInfiltration = self:calculateWaterInfiltration(meltedSnow, snowDepth, isGroundFrozen)

    -- calculate evaporation, if relativeHumidity > 90% or snow on the ground, no evaporation
    local soilWaterEvaporation
    if prevSoilWaterCont <= hygroscopicSaturation or relativeHumidity > 90 or snowDepth > 0 then
        soilWaterEvaporation = 0
    elseif prevSoilWaterCont >= stomatalSaturation then
        soilWaterEvaporation = maxEvaporation
    else
        soilWaterEvaporation = (prevSoilWaterCont - hygroscopicSaturation) / (stomatalSaturation - hygroscopicSaturation) * maxEvaporation / 24
    end

    -- calculate transpiration, if air temperature < 5 deg, no transpiration
    local soilWaterTranspiration
    if prevSoilWaterCont <= wiltingSaturation or currentTemp < 5 then
        soilWaterTranspiration = 0
    elseif prevSoilWaterCont >= stomatalSaturation then
        soilWaterTranspiration = maxTranspiration
    else
        soilWaterTranspiration = (prevSoilWaterCont - wiltingSaturation) / (stomatalSaturation - wiltingSaturation) * maxTranspiration / 24
    end

    local soilWaterLeakage = math.max(Ksat * (math.exp(beta*(prevSoilWaterCont - Sfc)) - 1) / (math.exp(beta*(1 - Sfc)) - 1),0)

    return math.min(prevSoilWaterCont + 1 / (soilPorosity * depthRootZone) * (soilWaterInfiltration - soilWaterLeakage - soilWaterTranspiration - soilWaterEvaporation), 1)
end

function SeasonsWeatherModel:calculateWaterInfiltration(meltedSnow, snowDepth, isGroundFrozen)
    local snowMelt = 0
    local dropScale = self.mission.environment.weather.downfallUpdater.currentDropScale
    local rainAmount = self:getRainAmount(self.environment.currentDay, dropScale)

    -- not add water from melted snow if only piles are melting or if the ground is not frozen
    if meltedSnow ~= 0 and snowDepth > 0 and not isGroundFrozen then
        -- 30% of melted snow infiltrates, meltedSnow in meter, snow density 400 kg/m3
        -- dividing by 10 due to unit cm
        snowMelt = 0.3 * meltedSnow * 400 / 10
    end

    return snowMelt + rainAmount
end

---Returns the amount of rain
function SeasonsWeatherModel:getRainAmount(day, dropScale)
    local period = self.environment:periodAtDay(day, self.environment.daysPerSeason)
    local seasonLengthFactor = (3.0 * self.environment.daysPerSeason) ^ 0.1
    local rainfall = self.data.rainfall[period]
    local rainProb = self.data.rainProbability[period]

    return rainfall * seasonLengthFactor * dropScale / 24 / 30 / rainProb
end

--- based on the Penman-Monteith method (evotranspiration being the sum of wind, sun and humidity effects)
function SeasonsWeatherModel:updateCropMoistureContent(prevCropMoist, julianDay, dayTime, currentTemp, lowTemp, windSpeed, cloudCoverage, dropScale, fogScale, timeSinceLastRain, print)
    local mist = math.max(fogScale/SeasonsWeather.FOGSCALE - cloudCoverage, 0)
    local relativeHumidity = self:calculateRelativeHumidity(currentTemp, lowTemp, dropScale, mist, print)
    local solarRadiation = self.environment.daylight:getCurrentSolarRadiation(julianDay, dayTime, cloudCoverage)

    local EMC = self:equilibriumMoistureContent(currentTemp, relativeHumidity)
    local evotranspiration = (0.1 * windSpeed + 0.25 * solarRadiation + 0.25 * (prevCropMoist - EMC)) * -1
    local maxTranspiration = math.max(evotranspiration / 2, -5)

    if print then
        -- season, day, dropScale, moist, EMC, wind, sun, relMoist, rh
        if dropScale > 0 then
            evotranspiration = 5 * dropScale
        end
    end

    -- increase crop Moisture when it rains with up to 5% every hour it rains
    if dropScale > 0 then
        if prevCropMoist < 20 then
            return 20.1, 5 * dropScale
        else
            return prevCropMoist + 5 * dropScale, 5 * dropScale
        end
    else
        if prevCropMoist > 20 then
            delta = 0
        else
            delta = evotranspiration
        end
        return MathUtil.clamp(prevCropMoist + math.max(evotranspiration, maxTranspiration), EMC, 80), delta
    end
end

---returns the eqilibrium moisture content based on temperature and relative humidity
function SeasonsWeatherModel:equilibriumMoistureContent(temp, rh)
    rh = rh / 100
    local tF = temp * 9/5 + 32
    local W = 330 + 0.5 * tF + 0.004 * tF^2
    local k = 0.79 + 5e-4 * tF - 1e-6 * tF^2
    local k1 = 6 + 1e-3 * tF - 1e4 * tF^2
    local k2 = 1 + 3e-2 * tF - 1e4 * tF^2

    return 1800 / W * ((k * rh) / (1 - k * rh) + (k1 * k * rh + 2 * k1 * k2 * k^2 * rh^2) / (1 + k1 * k * rh + k1 * k2 * k^2 * rh^2))
end

function SeasonsWeatherModel:calculateWindSpeed(p, pPrev, growthPeriod)
    -- wind speed is related to changing barometric pressure
    -- simulated as a change in weather
    -- weibull distribution for wind speed for 10 min average wind speed
    -- assumed shape parameter for all locations
    -- if using hourly average multiply all values with 1.5
    local shape = 1.5
    local scale = self.data.wind[growthPeriod] + 4
    local pressureGradient = math.abs(pPrev - p)^0.7

    return scale * (-1 * math.log(1 - pressureGradient)) ^ (1 / shape)
end

function SeasonsWeatherModel:calculateAveragePeriodTemp(growthPeriod, deterministic)
    local averageDailyMaximum = self.data.temperature[growthPeriod]

    if not deterministic then
        local seasonalTempVariance = 0.009 * growthPeriod ^ 2 - 0.1 * growthPeriod + 1.15
        return SeasonsMathUtil.normDist(averageDailyMaximum, seasonalTempVariance)
    else
        return averageDailyMaximum
    end
end

function SeasonsWeatherModel:calculateAirTemp(meanMaxTemp, deterministic)
    local highTemp = meanMaxTemp
    local lowTemp = 0.75 * meanMaxTemp - 5

    if not deterministic then
        highTemp = SeasonsMathUtil.normDist(meanMaxTemp, 2)
        lowTemp = SeasonsMathUtil.normDist(0, 1.5) + 0.75 * meanMaxTemp - 5
    end

    return lowTemp, highTemp
end

function SeasonsWeatherModel:randomRain(ssTmax, season, highTemp)
    local p
    if season == SeasonsEnvironment.WINTER or season == SeasonsEnvironment.AUTUMN then
        if highTemp > ssTmax then
            p = math.random() ^ 1.5 --increasing probability for precipitation if the temp is high
        else
            p = math.random() ^ 0.75 --decreasing probability for precipitation if the temp is high
        end
    elseif season == SeasonsEnvironment.SPRING or season == SeasonsEnvironment.SUMMER then
        if highTemp < ssTmax then
            p = math.random() ^ 1.5 --increasing probability for precipitation if the temp is high
        else
            p = math.random() ^ 0.75 --decreasing probability for precipitation if the temp is high
        end
    end

    return p
end

--- function for calculating soil temperature
--- Based on Rankinen et al. (2004), A simple model for predicting soil temperature in snow-covered and seasonally frozen soil: model description and testing
function SeasonsWeatherModel:calculateSoilTemp(soilTemp, soilTempMax, lowTemp, highTemp, snowDepth, daysPerSeason, simulation)
    local avgAirTemp = (highTemp * 8 + lowTemp * 16) / 24
    local deltaT = 365 / SeasonsEnvironment.SEASONS_IN_YEAR / daysPerSeason / 2

    -- average soil thermal conductivity, unit: kW/m/deg C, typical value s0.4-0.8
    local facKT = 0.6
    -- average thermal conductivity of soil and ice C_S + C_ICE, unit: kW/m/deg C, typical values C_S = 1-1.3, C_ICE = 4-15
    local facCA = 10
    -- empirical snow damping parameter, unit 1/m, typical values -2 - -7
    local facfs = -5

    soilTemp = soilTemp + math.min(deltaT * facKT / (0.81 * facCA), 0.8) * (avgAirTemp - soilTemp) * math.exp(facfs * math.max(snowDepth, 0))

    if not simulation and soilTemp > soilTempMax then
        soilTempMax = soilTemp
    end

    return soilTemp, soilTempMax
end
