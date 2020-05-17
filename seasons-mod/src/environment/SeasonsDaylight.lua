----------------------------------------------------------------------------------------------------
-- SeasonsDaylight
----------------------------------------------------------------------------------------------------
-- Purpose:  Creating a rotating planet and timezones
--
-- Uses julian days to convert between game days and real days needed for the simulation math.
-- The position based on latitiude is used for the sun and thus influences temperatures.
-- There is an option to configure the summer time in order to match properly with what players
-- expect.
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsDaylight = {}

local SeasonsDaylight_mt = Class(SeasonsDaylight)

SeasonsDaylight.DST_OFF = 0
SeasonsDaylight.DST_ON = 1
SeasonsDaylight.DST_ALWAYS = 2

function SeasonsDaylight:new(mission, messageCenter, sleepManager)
    self = setmetatable({}, SeasonsDaylight_mt)

    self.mission = mission
    self.sleepManager = sleepManager

    return self
end

function SeasonsDaylight:delete()
end

function SeasonsDaylight:load()
    self:loadDataFromFiles()

    -- Calculate some constants for the daytime calculator
    self.latRad = self.latitude * math.pi / 180

    -- Using different values for as it fits better ingame
    self.pNightEnd = 5 * math.pi / 180      -- Suns inclination below the horizon when first light appears
    self.pNightStart = 14 * math.pi / 180   -- Suns inclination below the horizon when last light disappears
    self.pDayStart = -12 * math.pi / 180    -- Suns inclination above the horizon when full 'daylight' appears in morning
    self.pDayEnd = -5 * math.pi / 180       -- Suns inclination above the horizon when full 'daylight' disappears in evening
end

---------------------
-- Data loading
---------------------

function SeasonsDaylight:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("environment", path.file)
        if xmlFile then
            self:loadDataFromFile(xmlFile)

            delete(xmlFile)
        end
    end
end

function SeasonsDaylight:loadDataFromFile(xmlFile)
    self.latitude = getXMLFloat(xmlFile, "environment.latitude")

    local dst = Utils.getNoNil(getXMLString(xmlFile, "environment.daylight#dst"), "always"):lower()
    if dst == "yes" then
        self.dst = self.DST_ON
    elseif dst == "no" then
        self.dst = self.DST_OFF
    else
        self.dst = self.DST_ALWAYS
    end
end

function SeasonsDaylight:setDataPaths(paths)
    self.paths = paths
end

---------------------
-- Adapting start and end of day
---------------------

function SeasonsDaylight:adaptTime()
    local dayStart, dayEnd, nightEnd, nightStart = self:calculateStartEndOfDay(self.julianDay)

    -- This is for the logical night. Used for turning on lights in houses / streets.
    -- 0.3 and 0.8 determined using vanilla values
    local env = self.mission.environment

    local nightStart = MathUtil.lerp(dayEnd, nightStart, 0.1)
    local nightEnd = MathUtil.lerp(nightEnd, dayStart, 0.9)

    env.nightStart = nightStart
    env.nightEnd = nightEnd
    env.nightStartMinutes = nightStart * 60
    env.nightEndMinutes = nightEnd * 60

    local sleepRanges = self.sleepManager.sleepingRanges
    sleepRanges[1][1] = nightStart -- Before midnight
    sleepRanges[2][2] = nightEnd -- After midnight, end

    -- Update the ranges for spawn rates and lights.
    if self.mission.pedestrianSystem ~= nil then
        self.mission.pedestrianSystem:setNightTimeRange(nightStart, nightEnd)
    end
    if self.mission.trafficSystem ~= nil then
        self.mission.trafficSystem:setNightTimeRange(nightStart, nightEnd)
    end
end

---------------------
-- Setters and getters
---------------------

---Get the latitude.
function SeasonsDaylight:getLatitude()
    return self.latitude
end

---Get the julian day
function SeasonsDaylight:getCurrentJulianDay()
    return self.julianDay
end

---Set the current julian day.
function SeasonsDaylight:setCurrentJulianDay(julianDay)
    self.julianDay = julianDay

    self:adaptTime()
end

function SeasonsDaylight:getLightTimes()
    return self:calculateStartEndOfDay(self.julianDay)
end

---------------------
-- Modelling
---------------------

---Calculate the start and end of the daylight.
-- @return dayStart, dayEnd, nightEnd, nightStart in hours
function SeasonsDaylight:calculateStartEndOfDay(julianDay)
    local dayStart, dayEnd, nightEnd, nightStart

    -- Calculate the day
    dayStart = self:calculateDay(self.pDayStart, julianDay, true)
    dayEnd = self:calculateDay(self.pDayEnd, julianDay, false)

    -- True blackness
    nightStart = self:calculateDay(self.pNightStart, julianDay, false)
    nightEnd = self:calculateDay(self.pNightEnd, julianDay, true)

    -- Restrict the values to prevent errors
    nightEnd = math.max(nightEnd, 1.01) -- nightEnd > 1.0
    if dayStart == dayEnd then
        dayEnd = dayEnd + 0.01
    end
    nightStart = math.min(nightStart, 22.99) -- nightStart < 23
    dayEnd = math.min(dayEnd, nightStart - 0.01) -- dayEnd < nightStart

    return dayStart, dayEnd, nightEnd, nightStart
end

---Calculate a time given the day and dawn parameters using the p parameter
-- @param p number Position within the day
function SeasonsDaylight:calculateDay(p, julianDay, dawn)
    local time
    local D, offset = 0, 1
    local eta = self:calculateSunDeclination(julianDay)
    local latRad = self.latRad

    local gamma = (math.sin(p) + math.sin(latRad) * math.sin(eta)) / (math.cos(latRad) * math.cos(eta))

    -- Account for polar day and night
    if gamma < -1 then
        D = 0
    elseif gamma > 1 then
        D = 24
    else
        D = 24 - 24 / math.pi * math.acos(gamma)
    end

    -- Daylight saving between 30 March and 31 October as an approximation
    -- julianDay 89 is used so day 4 in spring on a 9 day season will be with DST
    if self.dst == SeasonsDaylight.DST_ON then
        local hasDST = ((julianDay < 89 or julianDay > 304) or ((julianDay >= 89 and julianDay <= 304) and (gamma < -1 or gamma > 1)))
        if self.latitude >= 0 then
            hasDST = not hasDST
        end

        offset = hasDST and 1 or 0
    elseif self.dst == SeasonsDaylight.DST_OFF then
        offset = 0
    end

    if dawn then
        time = math.max(12 - D / 2 + offset, 0.01)
    else
        time = math.min(12 + D / 2 + offset, 23.99)
    end

    return time
end

---Calculate the angle between the sun and the horizon
-- gives negative angles due to FS convention of the sun (todo: check this is still valid in 19)
-- universal for both northern and southern hemisphere
function SeasonsDaylight:calculateSunHeightAngle(julianDay)
    if julianDay == nil then
        julianDay = self.julianDay
    end

    local dec = self:calculateSunDeclination(julianDay)

    return self.latRad - dec - math.pi / 2
end

---Calculate the suns declination according to the CBM model
function SeasonsDaylight:calculateSunDeclination(julianDay)
    if julianDay == nil then
        julianDay = self.julianDay
    end

    local theta = 0.216 + 2 * math.atan(0.967 * math.tan(0.0086 * (julianDay - 186)))

    return math.asin(0.4 * math.cos(theta))
end

---Calculate the suns azimuth angle
-- @return angle in degrees
function SeasonsDaylight:calculateSunAzimuthAngle(julianDay)
    local dec = self:calculateSunDeclination(julianDay)
    local zenithAngle = math.pi + self:calculateSunHeightAngle(julianDay)
    local time = self.mission.environment.dayTime / 60 / 1000 / 24
    local hourAngle = 1/12 * math.pi * (time - 12)

    local sinAzimuth = -1 * math.sin(hourAngle) * math.cos(dec) / math.sin(zenithAngle)

    local corr = 0
    if sinAzimuth > 1 then
        corr = -1
    elseif sinAzimuth < -1 then
        corr = 1
    end

    return (math.asin(sinAzimuth + corr) - corr * math.pi/2) * 180 / math.pi
end

---Calculate the solar radiation at current day and time.
-- http://swat.tamu.edu/media/1292/swat2005theory.pdf
function SeasonsDaylight:getCurrentSolarRadiation(julianDay, dayTime, cloudCoverage)
    local eta = self:calculateSunDeclination(julianDay)
    local sunHeightAngle = self:calculateSunHeightAngle(julianDay)
    local sunZenithAngle = math.pi / 2 + sunHeightAngle --sunHeightAngle always negative due to FS convention

    local dayStart, dayEnd, _, _ = self:calculateStartEndOfDay(julianDay)

    local lengthDay = dayEnd - dayStart
    local midDay = dayStart + lengthDay / 2

    local solarRadiation = 0
    -- lower solar radiation if it is overcast
    -- https://scool.larc.nasa.gov/lesson_plans/CloudCoverSolarRadiation.pdf
    local Isc = 4.921 * (1 - 0.9 * cloudCoverage^3) --MJ / (m2 * h)

    if dayTime < dayStart or dayTime > dayEnd then
        -- no radiation before sun rises
        return 0
    else
        return Isc * math.cos(sunZenithAngle) * math.cos(( dayTime - midDay) / (lengthDay / 2))
    end
end
