----------------------------------------------------------------------------------------------------
-- SeasonsLocalStorage
----------------------------------------------------------------------------------------------------
-- Purpose:  Local settings holder, based on data from the user profile
--
-- Copyright (c) Realismus Modding, 2019
----------------------------------------------------------------------------------------------------

SeasonsLocalStorage = {}

local SeasonsLocalStorage_mt = Class(SeasonsLocalStorage)

function SeasonsLocalStorage:new(mission)
    self = setmetatable({}, SeasonsLocalStorage_mt)

    self.mission = mission
    self.isDirty = false

    self.showTutorialMessages = true
    self.cropRotations = {}

    return self
end

function SeasonsLocalStorage:delete()
end

----------------------
-- Loading and saving
----------------------

---Save to profile only if the data is dirty
function SeasonsLocalStorage:saveIfDirty()
    if self.isDirty then
        self:saveToProfile()
        self.isDirty = false
    end
end

---Load data from profile
function SeasonsLocalStorage:loadFromProfile()
    local path = self:getFilePath()
    if not fileExists(path) then
        return
    end

    local xmlFile = loadXMLFile("seasonsProfile", path)
    if xmlFile == nil then
        return
    end

    -- Only load for current game
    local gameKey = self:getOrCreateGameKey(xmlFile)

    self:loadCropRotations(xmlFile, gameKey)
    self.showTutorialMessages = Utils.getNoNil(getXMLBool(xmlFile, gameKey .. ".showTutorialMessages"), self.showTutorialMessages)

    delete(xmlFile)
end

---Load crop rotations from file
function SeasonsLocalStorage:loadCropRotations(xmlFile, gameKey)
    self.cropRotations = {}

    local i = 0
    while true do
        local rotKey = string.format("%s.cropRotations.rotation(%d)", gameKey, i)
        if not hasXMLProperty(xmlFile, rotKey) then
            break
        end

        local rotation = {}

        local j = 0
        while true do
            local key = string.format("%s.item(%d)", rotKey, j)
            if not hasXMLProperty(xmlFile, key) then
                break
            end

            local index = getXMLInt(xmlFile, key .. "#index")
            local value = getXMLString(xmlFile, key)

            rotation[index] = value

            j = j + 1
        end

        local index = getXMLInt(xmlFile, rotKey .. "#index")
        self.cropRotations[index] = rotation

        i = i + 1
    end

    if self.rotationsFrame ~= nil then
        self.rotationsFrame:setSettings(self.cropRotations)
    end
end

---Save settings to profile. Use an existing profile file, or create a new one
function SeasonsLocalStorage:saveToProfile()
    local path = self:getFilePath()
    local xmlFile
    if fileExists(path) then
        xmlFile = loadXMLFile("seasonsProfile", path)
    else
        xmlFile = createXMLFile("seasonsProfile", path, "seasonsProfile")
    end

    if xmlFile == nil then
        Logging.error("Failed to save Seasons profile settings")
        return
    end

    -- Only load for current game
    local gameKey = self:getOrCreateGameKey(xmlFile)

    self:saveCropRotations(xmlFile, gameKey)
    setXMLBool(xmlFile, gameKey .. ".showTutorialMessages", self.showTutorialMessages)

    saveXMLFile(xmlFile)
    delete(xmlFile)
end

---Save crop rotations to file
function SeasonsLocalStorage:saveCropRotations(xmlFile, gameKey)
    -- Remove previous XML-elements, in case they are not forced overwritten, due to `rotation`-table containing less elements
    local maxIterations = 10
    while maxIterations > 0 do
      if not removeXMLProperty(xmlFile, string.format("%s.cropRotations.rotation(0)", gameKey)) then
        maxIterations = 0
      end
      maxIterations = maxIterations - 1
    end

    local k = 0
    for i, rotation in pairs(self.cropRotations) do
        setXMLInt(xmlFile, string.format("%s.cropRotations.rotation(%d)#index", gameKey, k), i)

        local j = 0
        for index, value in pairs(rotation) do
            local key = string.format("%s.cropRotations.rotation(%d).item(%d)", gameKey, k, j)

            setXMLInt(xmlFile, key .. "#index", index)
            setXMLString(xmlFile, key, value)

            j = j + 1
        end

        k = k + 1
    end
end

---Get the game key for the current game, or create a new one
function SeasonsLocalStorage:getOrCreateGameKey(xmlFile)
    local name
    if not self.mission:getIsServer() then
        name = getMD5(self.mission.missionDynamicInfo.serverAddress) .. "_" .. self.mission.missionInfo.mapId
    else
        name = self.mission.missionInfo.mapId .. "_" .. self.mission.missionInfo.savegameIndex
    end

    -- Try to find it
    local i = 0
    while true do
        local key = string.format("seasonsProfile.games.game(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        if getXMLString(xmlFile, key .. "#name") == name then
            return key
        end

        i = i + 1
    end

    -- Set the new key
    local newKey = string.format("seasonsProfile.games.game(%d)", i)
    setXMLString(xmlFile, newKey .. "#name", name)

    return newKey
end

---Get the filepath for the seasons profile settings
function SeasonsLocalStorage:getFilePath()
    return Utils.getFilename("seasons.xml", getUserProfileAppPath())
end

----------------------
-- Setters and getters
----------------------

---Set stored crop rotations
function SeasonsLocalStorage:setCropRotations(rotations)
    self.cropRotations = rotations
    self.isDirty = true
end

---Get stored crop rotations
function SeasonsLocalStorage:getCropRotations()
    return self.cropRotations
end

function SeasonsLocalStorage:setShowTutorialMessages(show)
    if self.showTutorialMessages ~= show then
        self.showTutorialMessages = show
        self.isDirty = true
    end
end

function SeasonsLocalStorage:getShowTutorialMessages()
    return self.showTutorialMessages
end
