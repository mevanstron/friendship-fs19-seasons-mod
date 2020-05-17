----------------------------------------------------------------------------------------------------
-- SeasonsLighting
----------------------------------------------------------------------------------------------------
-- Purpose:  Lighting system for Seasons
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsLighting = {}

local SeasonsLighting_mt = Class(SeasonsLighting)

function SeasonsLighting:new(mission, environment, weather, messageCenter, modDirectory)
    local self = setmetatable({}, SeasonsLighting_mt)

    self.mission = mission
    self.environment = environment
    self.weather = weather
    self.messageCenter = messageCenter
    self.modDirectory = modDirectory

    self.envMapTimes = {}

    self.paths = {}

    SeasonsModUtil.overwrittenFunction(Lighting, "update", SeasonsLighting.inj_lighting_update)

    return self
end

function SeasonsLighting:delete()
    self.messageCenter:unsubscribeAll(self)
end

function SeasonsLighting:load()
    self:loadDataFromFiles()

    self.dayStart, self.dayEnd, self.nightEnd, self.nightStart = self.environment.daylight:getLightTimes()
    self:updateCurves()

    self.messageCenter:subscribe(SeasonsMessageType.DAYLIGHT_CHANGED, self.onDaylightChanged, self)
end

---------------------
-- Data loading
---------------------

function SeasonsLighting:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("lighting", path.file)
        if xmlFile then
            self:loadDataFromFile(xmlFile, path.modDir)

            delete(xmlFile)
        end
    end
end

function SeasonsLighting:loadDataFromFile(xmlFile, basePath)
    local path = getXMLString(xmlFile, "lighting.envMap#basePath")
    if path ~= nil then
        self.envMapBasePath = Utils.getFilename(path, basePath)
        self.mission.environment.baseLighting.envMapBasePath = self.envMapBasePath
    end

    if hasXMLProperty(xmlFile, "lighting.envMap.timeProbe(0)") then
        -- Always needs to be a consistent set
        local envMapTimes = {}

        local i = 0
        while true do
            local key = string.format("lighting.envMap.timeProbe(%d)", i)
            if not hasXMLProperty(xmlFile, key) then
                break
            end

            table.insert(envMapTimes, getXMLFloat(xmlFile, key .. "#timeHours"))

            i = i + 1
        end

        if #envMapTimes < 2 then
            Logging.error("At least two env map probes need to be configured in lighting.xml")
        else
            self.envMapTimes = envMapTimes
        end
    end

    local day = getXMLString(xmlFile, "lighting.colorGrading.day#filename")
    if day ~= nil then
        self.colorGradingDay = Utils.getFilename(day, basePath)
    end

    local night = getXMLString(xmlFile, "lighting.colorGrading.night#filename")
    if night ~= nil then
        self.colorGradingNight = Utils.getFilename(night, basePath)
    end

    self.sunRotationCurve                       = self:loadCurveDataFromXML(xmlFile, "lighting.curves.sunRotationCurve", true)
    self.moonBrightnessScaleCurveWithMoon       = self:loadCurveDataFromXML(xmlFile, "lighting.curves.moonBrightnessScaleCurveWithMoon")
    self.moonBrightnessScaleCurveWithoutMoon    = self:loadCurveDataFromXML(xmlFile, "lighting.curves.moonBrightnessScaleCurveWithoutMoon")
    self.moonSizeScaleCurve                     = self:loadCurveDataFromXML(xmlFile, "lighting.curves.moonSizeScaleCurve")
    self.sunIsPrimaryCurve                      = self:loadCurveDataFromXML(xmlFile, "lighting.curves.sunIsPrimaryCurve")
    self.sunBrightnessScaleCurve                = self:loadCurveDataFromXML(xmlFile, "lighting.curves.sunBrightnessScaleCurve")
    self.sunSizeScaleCurve                      = self:loadCurveDataFromXML(xmlFile, "lighting.curves.sunSizeScaleCurve")
    self.asymmetryFactorCurve                   = self:loadCurveDataFromXML(xmlFile, "lighting.curves.asymmetryFactorCurve")
    self.primaryExtraterrestrialColorCurve      = self:loadCurveDataFromXML(xmlFile, "lighting.curves.primaryExtraterrestrialColorCurve")
    self.secondaryExtraterrestrialColorCurve    = self:loadCurveDataFromXML(xmlFile, "lighting.curves.secondaryExtraterrestrialColorCurve")
    self.primaryDynamicLightingScaleCurve       = self:loadCurveDataFromXML(xmlFile, "lighting.curves.primaryDynamicLightingScaleCurve")
    self.lightScatteringRotationCurve           = self:loadCurveDataFromXML(xmlFile, "lighting.curves.lightScatteringRotationCurve", true)
    self.autoExposureCurve                      = self:loadCurveDataFromXML(xmlFile, "lighting.curves.autoExposureCurve")
end

---Load the raw data from the XML curve
function SeasonsLighting:loadCurveDataFromXML(xmlFile, key, convertRadians)
    local data = {}

    local i = 0
    while true do
        local timeKey = string.format("%s.key(%d)", key, i)
        if not hasXMLProperty(xmlFile, timeKey) then
            break
        end

        local time = getXMLFloat(xmlFile, timeKey .. "#time")
        local values = StringUtil.splitString(" ", getXMLString(xmlFile, timeKey.."#value"))

        for i, value in ipairs(values) do
            local number = tonumber(value)
            if convertRadians then
                number = math.rad(number)
            end

            values[i] = number
        end

        table.insert(data, {time, values})

        i = i + 1
    end

    return data
end

function SeasonsLighting:setDataPaths(paths)
    self.paths = paths
end

------------------------------------------------
-- Updating lighting
------------------------------------------------

---Convert a hardcoded time to a julian based time
-- 6 => nightEnd, 7 => dayStart etc
function SeasonsLighting:getTimeFromHardcoded(hardcoded)
    local dayStart, dayEnd = self.dayStart, self.dayEnd
    local nightStart, nightEnd = self.nightStart, self.nightEnd

    if hardcoded < 6 then
        local alpha = hardcoded / 6
        return  nightEnd * alpha
    elseif hardcoded >= 6 and hardcoded < 7 then
        local alpha = (hardcoded - 6)
        return (dayStart - nightEnd) * alpha + nightEnd
    elseif hardcoded >= 7 and hardcoded < 19 then
        local alpha = (hardcoded - 7) / (19 - 7)
        return (dayEnd - dayStart) * alpha + dayStart
    elseif hardcoded >= 19 and hardcoded < 20 then
        local alpha = (hardcoded - 19)
        return (nightStart - dayEnd) * alpha + dayEnd
    elseif hardcoded >= 20 and hardcoded <= 24 then
        local alpha = (hardcoded - 20) / (24 - 20)
        return (24 - nightStart) * alpha + nightStart
    end
end

---Convert a julian based time to a hardcoded time
-- nightEnd => 6, dayStart => 7 etc
function SeasonsLighting:getHardcodedFromTime(time)
    local dayStart, dayEnd = self.dayStart, self.dayEnd
    local nightStart, nightEnd = self.nightStart, self.nightEnd

    if time < nightEnd then
        local alpha = time / nightEnd
        return 6 * alpha
    elseif time >= nightEnd and time < dayStart then
        local alpha = (time - nightEnd) / (dayStart - nightEnd)
        return (7 - 6) * alpha + 6
    elseif time >= dayStart and time < dayEnd then
        local alpha = (time - dayStart) / (dayEnd - dayStart)
        return (19 - 7) * alpha + 7
    elseif time >= dayEnd and time < nightStart then
        local alpha = (time - dayEnd) / (nightStart - dayEnd)
        return (20 - 19) * alpha + 19
    else
        local alpha = (time - nightStart) / (24 - nightStart)
        return (24 - 20) * alpha + 20
    end
end

function SeasonsLighting:updateCurves()
    local vanillaEnvironment = self.mission.environment
    local vanillaLighting = vanillaEnvironment.baseLighting
    local showMoon = false

    vanillaLighting.lightScatteringRotCurve         = self:createCurve(linearInterpolator2, self.lightScatteringRotationCurve)
    vanillaLighting.asymmetryFactorCurve            = self:createCurve(linearInterpolator1, self.asymmetryFactorCurve)

    vanillaLighting.sunBrightnessScaleCurve         = self:createCurve(linearInterpolator1, self.sunBrightnessScaleCurve)
    vanillaLighting.sunSizeScaleCurve               = self:createCurve(linearInterpolator1, self.sunSizeScaleCurve)

    if showMoon then
        vanillaLighting.moonBrightnessScaleCurve    = self:createCurve(linearInterpolator1, self.moonBrightnessScaleCurveWithMoon)
    else
        vanillaLighting.moonBrightnessScaleCurve    = self:createCurve(linearInterpolator1, self.moonBrightnessScaleCurveWithoutMoon)
    end

    vanillaLighting.moonSizeScaleCurve              = self:createCurve(linearInterpolator1, self.moonSizeScaleCurve)

    vanillaLighting.sunIsPrimaryCurve               = self:createCurve(linearInterpolator1, self.sunIsPrimaryCurve)

    vanillaLighting.primaryDynamicLightingScale     = self:createCurve(linearInterpolator1, self.primaryDynamicLightingScaleCurve)

    vanillaLighting.primaryExtraterrestrialColor    = self:createCurve(linearInterpolator3, self.primaryExtraterrestrialColorCurve)
    vanillaLighting.secondaryExtraterrestrialColor  = self:createCurve(linearInterpolator3, self.secondaryExtraterrestrialColorCurve)

    vanillaLighting.autoExposureCurve               = self:createCurve(linearInterpolator3, self.autoExposureCurve)
    vanillaLighting.colorGradingFileCurve           = self:getColorGradingFileCurve()

    vanillaEnvironment.sunHeightAngle               = self.environment.daylight:calculateSunHeightAngle()
    vanillaEnvironment.sunRotCurve                  = self:createCurve(linearInterpolator1, self.sunRotationCurve)
end

---Update the env map based on current time with seasonal conversion.
function SeasonsLighting:updateEnvMaps(vanillaLighting, dayMinutes)
    -- We can do some assumptions because we force our own envMaps:
    -- - always available
    -- - always more than 1

    local envMap0, envMap1
    local blendWeight = 0

    local dayHours = dayMinutes / 60

    -- Convert the time to the default time setup used to create env maps
    local hardHours = self:getHardcodedFromTime(dayHours)

    local secondIndex = 1
    for i, time in ipairs(self.envMapTimes) do
        if time > hardHours then
            secondIndex = i
            break
        end
    end

    local firstIndex = secondIndex - 1
    local firstTime, secondTime = self.envMapTimes[firstIndex], self.envMapTimes[secondIndex]
    if firstIndex <= 0 then
        firstIndex = #self.envMapTimes
        firstTime =  self.envMapTimes[firstIndex]

        blendWeight = (hardHours - firstTime - 24) / (secondTime - (firstTime - 24))
    else
        blendWeight = (hardHours - firstTime) / (secondTime - firstTime)
    end

    envMap0 = self.envMapBasePath .. Lighting.getEnvMapBaseFilename(firstTime) .. ".png"
    envMap1 = self.envMapBasePath .. Lighting.getEnvMapBaseFilename(secondTime) .. ".png"

    -- Note: blending just does <0.5 or >=0.5 and not actually blend
    setEnvMap(envMap0, envMap1, blendWeight)
end

------------------------------------------------
-- Events
------------------------------------------------

---Update all lighting curves
function SeasonsLighting:onDaylightChanged()
    self.dayStart, self.dayEnd, self.nightEnd, self.nightStart = self.environment.daylight:getLightTimes()
    self:updateCurves()
end

------------------------------------------------
-- Injections
------------------------------------------------

function SeasonsLighting.inj_lighting_update(lighting, superFunc, dt, force)
    -- Custom lighting is enabled (like in the shop)
    if lighting ~= g_currentMission.environment.baseLighting then
        return superFunc(lighting, dt, force)
    end

    if force or math.abs(lighting.environment.dayTime - lighting.lastDayTime) > lighting.updateInterval then
        local dayMinutes = lighting.environment.dayTime / (1000 * 60)

        -- Prevent env map updates by removing them
        local oldPath = lighting.envMapBasePath
        lighting.envMapBasePath = nil

        -- Adjust the cloud coverage. The formula used is -0.1*globalCloudCoverage+1.0 to remove 10% light with 100% coverage
        -- We want to change this so we adjust the cloud coverage value temporarily
        local actualCoverage = lighting.globalCloudCoverage
        lighting.globalCloudCoverage = lighting.globalCloudCoverage * 2

        -- Do all normal lighting updates
        superFunc(lighting, dt, force)

        -- Reset
        lighting.globalCloudCoverage = actualCoverage
        lighting.envMapBasePath = oldPath

        -- Run custom envMap code
        g_seasons.lighting:updateEnvMaps(lighting, dayMinutes)
    end
end

------------------------------------------------
-- Curve generators
--
-- New curves with lighting depending on julian
-- day. Original framework times are added
-- behind the keyframe
--
-- Original from environment.xml file:
-- nightEnd    = 6 (dark)
-- dayStart    = 7 (light)
-- dayEnd      =19 (light)
-- nightStart  =20 (dark)
------------------------------------------------

---Add keyframe given an hardcoded hour and values
function SeasonsLighting:addJulianKeyframe(curve, hours, ...)
    curve:addKeyframe({time = self:getTimeFromHardcoded(hours) * 60, ...})
end

---Add keyframe given an hardcoded hour and file
function SeasonsLighting:addJulianFileKeyframe(curve, hours, file)
    curve:addKeyframe({time = self:getTimeFromHardcoded(hours) * 60, file = file})
end

---Create a curve from data with given interpolator
function SeasonsLighting:createCurve(interpolator, data)
    local curve = AnimCurve:new(interpolator)

    for _, values in ipairs(data) do
        self:addJulianKeyframe(curve, values[1], unpack(values[2]))
    end

    return curve
end

---Color grading throughout the day
function SeasonsLighting:getColorGradingFileCurve()
    local curve = AnimCurve:new(Lighting.fileInterpolator)

    self:addJulianFileKeyframe(curve,  0.0, self.colorGradingNight)
    self:addJulianFileKeyframe(curve,  5.0, self.colorGradingNight)
    self:addJulianFileKeyframe(curve,  6.0, self.colorGradingDay)
    self:addJulianFileKeyframe(curve, 20.0, self.colorGradingDay)
    self:addJulianFileKeyframe(curve, 22.0, self.colorGradingNight)
    self:addJulianFileKeyframe(curve, 24.0, self.colorGradingNight)

    return curve
end
