----------------------------------------------------------------------------------------------------
-- SeasonsEnvironment
----------------------------------------------------------------------------------------------------
-- Purpose:  Add concept of seasons, years and periods to the game
--
-- Essentially this class defines that the game is on a sphere-like planet that rotates around its
-- axis, and also rotates around a star. The axis of the planet is angled to the star.
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsEnvironment = {}

local SeasonsEnvironment_mt = Class(SeasonsEnvironment)

SeasonsEnvironment.MAX_DAYS_IN_SEASON = 24
SeasonsEnvironment.SEASONS_IN_YEAR = 4
SeasonsEnvironment.PERIODS_IN_YEAR = 12

SeasonsEnvironment.SPRING = 0 -- important to start at 0, not 1
SeasonsEnvironment.SUMMER = 1
SeasonsEnvironment.AUTUMN = 2
SeasonsEnvironment.WINTER = 3

SeasonsEnvironment.EARLY_SPRING = 1
SeasonsEnvironment.MID_SPRING = 2
SeasonsEnvironment.LATE_SPRING = 3

SeasonsEnvironment.EARLY_SUMMER = 4
SeasonsEnvironment.MID_SUMMER = 5
SeasonsEnvironment.LATE_SUMMER = 6

SeasonsEnvironment.EARLY_AUTUMN = 7
SeasonsEnvironment.MID_AUTUMN = 8
SeasonsEnvironment.LATE_AUTUMN = 9

SeasonsEnvironment.EARLY_WINTER = 10
SeasonsEnvironment.MID_WINTER = 11
SeasonsEnvironment.LATE_WINTER = 12

SeasonsEnvironment.seasonKeyToId = {
    ["spring"] = 0,
    ["summer"] = 1,
    ["autumn"] = 2,
    ["winter"] = 3
}

function SeasonsEnvironment:new(mission, messageCenter, sleepManager)
    local self = setmetatable({}, SeasonsEnvironment_mt)

    self.mission = mission
    self.messageCenter = messageCenter

    self.daylight = SeasonsDaylight:new(mission, messageCenter, sleepManager)

    self.year = 0
    self.season = SeasonsEnvironment.SPRING
    self.period = SeasonsEnvironment.EARLY_SPRING

    self.currentDayOffset = 0
    self.daysPerSeason = 9

    self.isNewSavegame = true

    self.paths = {}
    self.latitudeCategories = {}

    -- Earliest of all subscribers so all values are updated
    self.messageCenter:subscribe(SeasonsMessageType.HOUR_CHANGED_FIX, self.onHourChanged, self)

    addConsoleCommand("rmGetEnvironmentInfo", "Get environment info", "consoleCommandGetInfo", self)

    return self
end

function SeasonsEnvironment:delete()
    self.messageCenter:unsubscribeAll(self)

    self.daylight:delete()

    removeConsoleCommand("rmGetEnvironmentInfo")
end

function SeasonsEnvironment:load()
    -- Makes Seasons always begin in spring. Overwritten by a Seasons save
    self.currentDayOffset = -(self.mission.environment.currentDay - 1)
    self.lastDay = self.mission.environment.currentDay

    self.daylight:load()

    self:loadDataFromFiles()

    self:updateTimeValues()
end

function SeasonsEnvironment:loadFromSavegame(xmlFile)
    self.currentDayOffset = Utils.getNoNil(getXMLInt(xmlFile, "seasons.environment.currentDayOffset"), self.currentDayOffset)
    self.daysPerSeason = Utils.getNoNil(getXMLInt(xmlFile, "seasons.environment.daysPerSeason"), self.daysPerSeason)

    self.isNewSavegame = false

    self:updateTimeValues()
end

function SeasonsEnvironment:saveToSavegame(xmlFile)
    setXMLInt(xmlFile, "seasons.environment.currentDayOffset", self.currentDayOffset)
    setXMLInt(xmlFile, "seasons.environment.daysPerSeason", self.daysPerSeason)
end

function SeasonsEnvironment:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.currentDayOffset)
    streamWriteUInt8(streamId, self.daysPerSeason)
end

function SeasonsEnvironment:readStream(streamId, connection)
    self.currentDayOffset = streamReadInt32(streamId)
    self.daysPerSeason = streamReadUInt8(streamId)

    self:updateTimeValues()
end

---Listen to hour changes and trigger day change if a new day started.
-- This causes the internal dates to be updated before any other hour listener is called
function SeasonsEnvironment:onHourChanged(hour)
    if self.lastDay ~= self.mission.currentDay or hour == 0 then
        self:onDayChanged()
        self.lastDay = self.mission.currentDay
    end
end

function SeasonsEnvironment:onDayChanged()
    local oldPeriod = self.period
    local oldSeason = self.season
    local oldYear = self.year

    self:updateTimeValues()

    if oldPeriod ~= self.period then
        self.messageCenter:publishDelayed(SeasonsMessageType.PERIOD_CHANGED, {self.period})
    end

    if oldSeason ~= self.season then
        self.messageCenter:publishDelayed(SeasonsMessageType.SEASON_CHANGED, {self.season, false})
    end

    if oldYear ~= self.year then
        self.messageCenter:publishDelayed(SeasonsMessageType.YEAR_CHANGED, {self.year})
    end
end

function SeasonsEnvironment:onGameLoaded()
    self.messageCenter:publish(SeasonsMessageType.SEASON_CHANGED, {self.season, true})
end

---Update seasonal time values. Depends on currentDayOffset, vanilla currentDay, seasonLength
function SeasonsEnvironment:updateTimeValues()
    self.currentDay = self.mission.environment.currentDay + self.currentDayOffset

    self.period = self:periodAtDay(self.currentDay, self.daysPerSeason)
    self.season = self:seasonAtDay(self.currentDay, self.daysPerSeason)
    self.dayInSeason = self:dayInSeasonAtDay(self.currentDay, self.daysPerSeason)
    self.year = self:yearAtDay(self.currentDay, self.daysPerSeason)

    self.daylight:setCurrentJulianDay(self:julianDay(self.currentDay))
    self.messageCenter:publishDelayed(SeasonsMessageType.DAYLIGHT_CHANGED)
end

---Set a new season length.
-- This is a complex algorithm to keep the current period: it adjusts the day offset to keep the current game day
-- in the same period after the season length change as before.
function SeasonsEnvironment:setSeasonLength(length)
    local oldSeasonLength = self.daysPerSeason
    if oldSeasonLength == length then
        return
    end

    local actualCurrentDay = self.currentDay

    local seasonThatWouldBe = math.fmod(math.floor((actualCurrentDay - 1) / length), self.SEASONS_IN_YEAR)

    local dayThatNeedsToBe = math.floor((self.dayInSeason - 1) / oldSeasonLength * length) + 1

    local realDifferenceInSeason = self.season - seasonThatWouldBe

    local relativeYearThatNeedsTobe = realDifferenceInSeason < 0 and 1 or 0

    local resultingDayNumber = ((self.year + relativeYearThatNeedsTobe) * self.SEASONS_IN_YEAR + self.season) * length + dayThatNeedsToBe
    local resultingOffset = resultingDayNumber - actualCurrentDay
    local newOffset = math.fmod(self.currentDayOffset + resultingOffset, self.SEASONS_IN_YEAR * length)

    self.daysPerSeason = length
    self.currentDayOffset = newOffset

    self:updateTimeValues()
    self.messageCenter:publish(SeasonsMessageType.SEASON_LENGTH_CHANGED)

    -- This method is called on every server and client from the SeasonsSettingsEvent. No need for events here.
end

function SeasonsEnvironment:setDataPaths(paths)
    self.daylight:setDataPaths(paths)
end

function SeasonsEnvironment:setLatitudeDataPaths(paths)
    self.paths = paths
end

function SeasonsEnvironment:loadDataFromFiles()
    for _, path in ipairs(self.paths) do
        local xmlFile = loadXMLFile("latitudeSeason", path.file)
        if xmlFile ~= 0 then
            self:loadLatitudeDataFromFile(xmlFile)

            delete(xmlFile)
        end
    end
end

function SeasonsEnvironment:loadLatitudeDataFromFile(xmlFile)
    local i = 0
    while true do
        local key = string.format("visualSeason.latitudeCategory(%i)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local type = getXMLInt(xmlFile, key .. "#type")
        if type == nil then
            Logging.error("SeasonsEnvironment: type of latitude category invalid")
            break
        end

        if self.latitudeCategories[type] == nil then
            self.latitudeCategories[type] = {}
        end

        local j = 0
        while true do
            local vkey = string.format("%s.visual(%i)", key, j)
            if not hasXMLProperty(xmlFile, vkey) then
                break
            end

            local period = getXMLInt(xmlFile, vkey .. "#period")
            if period == nil then
                Logging.error("SeasonsEnvironment: invalid transition in latitude categories")
                break
            end

            self.latitudeCategories[type][period] = getXMLString(xmlFile, vkey)

            j = j + 1
        end

        i = i + 1
    end

    self.numVisualSeasons = {}
    for i, _ in pairs(self.seasonKeyToId) do
        self.numVisualSeasons[i] = 0
    end

    for _, v in pairs(self.latitudeCategories[self:latitudeCategory()]) do
        self.numVisualSeasons[v] = self.numVisualSeasons[v] + 1
    end
end

---------------------
-- Visual season calc
---------------------

---Get the latitude category number for configured latitude
function SeasonsEnvironment:latitudeCategory()
    local lat = math.abs(self.daylight.latitude)

    if lat <= 30 then
        return 1
    elseif lat <= 35 then
        return 2
    elseif lat <= 45 then
        return 3
    elseif lat <= 50 then
        return 4
    elseif lat <= 60 then
        return 5
    end

    return 6
end

---Get the number of visual categories
function SeasonsEnvironment:getNumVisualCategories(category)
    return self.numVisualSeasons[category]
end

---Get the current visual season
function SeasonsEnvironment:getCurrentVisualSeason(period)
    if period == nil then period = self.period end

    local type = self:latitudeCategory()

    return self.latitudeCategories[type][period]
end

---Get the percentage into the visual season
function SeasonsEnvironment:getPercentageIntoVisualSeason()
    local currentVisualSeason = self:getCurrentVisualSeason()
    local lengthVisualSeason = self.numVisualSeasons[currentVisualSeason]

    local periodsPerSeason = self.PERIODS_IN_YEAR / self.SEASONS_IN_YEAR
    local daysPerPeriod = self.daysPerSeason / periodsPerSeason

    local previousVisualSeasons = 0

    local previous = self:getCurrentVisualSeason(self:previousPeriod())
    local period = self.period

    local singleVisualSeason = false
    local count = 1

    while previous == currentVisualSeason do
        previousVisualSeasons = previousVisualSeasons + 1

        if period == SeasonsEnvironment.EARLY_SPRING then
            period = SeasonsEnvironment.LATE_WINTER
        else
            period =  period - 1
        end

        previous = self:getCurrentVisualSeason(self:previousPeriod(period))

        -- all visual seasons are equal so no need to continue for an eternity
        if count == 13 then
            return 1
        end
        count = count + 1
    end

    local base = (self:currentDayInPeriod() - 1 + previousVisualSeasons * daysPerPeriod) / (daysPerPeriod * lengthVisualSeason)
    local alphaOfDay = 1 / (daysPerPeriod * lengthVisualSeason)
    local time = (self.mission.environment.dayTime / (60 * 60 * 1000 * 24) + 0.0001) * alphaOfDay

    return base + time
end

function SeasonsEnvironment:getPercentageIntoPeriod()
    local periodsPerSeason = self.PERIODS_IN_YEAR / self.SEASONS_IN_YEAR
    local daysPerPeriod = self.daysPerSeason / periodsPerSeason

    local base = (self:currentDayInPeriod() - 1) / (daysPerPeriod)
    local alphaOfDay = 1 / daysPerPeriod
    local time = (self.mission.environment.dayTime / (60 * 60 * 1000 * 24) + 0.0001) * alphaOfDay

    return base + time
end

----------------------
-- Utilities
----------------------

---Get the season at given day and season length
function SeasonsEnvironment:seasonAtDay(day, seasonLength)
    if seasonLength == nil then seasonLength = self.daysPerSeason end

    return math.fmod(math.floor((day - 1) / seasonLength), self.SEASONS_IN_YEAR)
end

---Get the day within a season, for given game day and season length
-- @return number Value ranging 1 to daysPerSeason
function SeasonsEnvironment:dayInSeasonAtDay(day, seasonLength)
    if seasonLength == nil then seasonLength = self.daysPerSeason end

    local season = self:seasonAtDay(day, seasonLength) -- 0-3
    local dayInYear = math.fmod(day - 1, seasonLength * self.SEASONS_IN_YEAR) + 1

    return (dayInYear - 1 - season * seasonLength) + 1
end

---Get the current day but within the year (mod year length)
function SeasonsEnvironment:currentDayInYear()
    return math.fmod(self.currentDay - 1, SeasonsEnvironment.SEASONS_IN_YEAR * self.daysPerSeason) + 1
end

---Get the current day but within the period
function SeasonsEnvironment:currentDayInPeriod()
    local periodsPerSeason = self.PERIODS_IN_YEAR / self.SEASONS_IN_YEAR

    return math.fmod(self.currentDay - 1, self.daysPerSeason / periodsPerSeason) + 1
end

---Get the year for given day
-- @param day [number] Day
-- @returns 0-based number year. 0 is first year.
function SeasonsEnvironment:yearAtDay(day, seasonLength)
    if seasonLength == nil then seasonLength = self.daysPerSeason end

    return math.floor((day - 1) / (seasonLength * self.SEASONS_IN_YEAR))
end

function SeasonsEnvironment:periodAtDay(day, seasonLength)
    if seasonLength == nil then
        seasonLength = self.daysPerSeason
    end

    local season = self:seasonAtDay(day, seasonLength)
    local seasonTransition = self:periodInSeasonAtDay(day, seasonLength)

    return (seasonTransition + (season * 3))
end

function SeasonsEnvironment:periodInSeasonAtDay(day, seasonLength)
    if day == nil then day = self.currentDay end
    if seasonLength == nil then seasonLength = self.daysPerSeason end

    -- Length of a state
    local l = seasonLength / 3.0
    local dayInSeason = self:dayInSeasonAtDay(day, seasonLength)

    if dayInSeason >= MathUtil.round(2 * l) + 1 then -- Turn 3
        return 3
    elseif dayInSeason >= MathUtil.round(1 * l) + 1 then -- Turn 2
        return 2
    else
        return 1
    end

    return nil
end

-- This function calculates the real-ish daynumber from an ingame day number
-- Used by function that calculate a realistic weather / etc
-- Spring: Mar (60)  - May (151)
-- Summer: Jun (152) - Aug (243)
-- Autumn: Sep (244) - Nov (305)
-- Winter: Dec (335) - Feb (59)
function SeasonsEnvironment:julianDay(day)
    local season, partInSeason, dayInSeason
    local starts = {[0] = 60, 152, 244, 335 }
    local latitude = self.daylight:getLatitude()

    if latitude < 0 then
        starts = {[0] = 244, 335, 60, 152 }
    end

    season = self:seasonAtDay(day)
    dayInSeason = (day - 1) % self.daysPerSeason
    partInSeason = dayInSeason / self.daysPerSeason

    return math.fmod(math.floor(starts[season] + partInSeason * 91), 365)
end

---Get the previous period, or that of the given period.
function SeasonsEnvironment:previousPeriod(period)
    if period == nil then period = self.period end

    if period == SeasonsEnvironment.EARLY_SPRING then
        return SeasonsEnvironment.LATE_WINTER
    else
        return period - 1
    end
end

---Get the next period, or that of the given period.
function SeasonsEnvironment:nextPeriod(period)
    if period == nil then period = self.period end

    if period == SeasonsEnvironment.LATE_WINTER then
        return SeasonsEnvironment.EARLY_SPRING
    else
        return period + 1
    end
end

---Get how far we are into the current season
-- @return number from 0-1
function SeasonsEnvironment:getPercentageIntoSeason()
    local base = self.dayInSeason / self.daysPerSeason
    local alphaOfDay = 1 / self.daysPerSeason
    local time = (self.mission.environment.dayTime / (60 * 60 * 1000 * 24) + 0.0001) * alphaOfDay

    return base + time
end

---Get the time of the day in hours 0-23.99
function SeasonsEnvironment:getTimeInHours()
    return (self.mission.environment.dayTime / (60 * 60 * 1000) + 0.0001) % 24
end

----------------------
-- Commands
----------------------

function SeasonsEnvironment:consoleCommandGetInfo()
    log("day =",self.currentDay,"; period =", self.period, "; season =", self.season, "; day within season =", self.dayInSeason, "; days per season = ", self.daysPerSeason)
end
