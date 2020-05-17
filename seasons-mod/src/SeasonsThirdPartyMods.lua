----------------------------------------------------------------------------------------------------
-- SeasonsThirdPartyMods
----------------------------------------------------------------------------------------------------
-- Purpose:  Third party mod information
-- Authors:  Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsThirdPartyMods = {}

local SeasonsThirdPartyMods_mt = Class(SeasonsThirdPartyMods)

function SeasonsThirdPartyMods:new(modManager, modDirectory, deferredLoadingManager, mission)
    self = setmetatable({}, SeasonsThirdPartyMods_mt)

    self.modManager = modManager
    self.modDirectory = modDirectory
    self.deferredLoadingManager = deferredLoadingManager
    self.mission = mission

    self.minAPIVersion = 10
    self.maxAPIVersion = 11 -- 1,2,3 = fs17, 10 = fs19 1.0, 11 = fs19 1.0.1 (geo fix)

    self.mods = {}
    self.dataDirectories = {}
    self.isGEOModActive = false

    return self
end

function SeasonsThirdPartyMods:delete()
end

function SeasonsThirdPartyMods:load()
    local mods = self.modManager:getActiveMods()

    for _, mod in ipairs(mods) do
        local xmlFile = loadXMLFile("ModDesc", mod.modFile)

        if xmlFile then
            self:loadMod(mod, xmlFile)

            delete(xmlFile)
        end
    end
end

---Load a third party mod
function SeasonsThirdPartyMods:loadMod(mod, xmlFile)
    local version = getXMLInt(xmlFile, "modDesc.seasons#version")

    -- Version parameter is required
    if version == nil then
        return
    end

    if version > self.maxAPIVersion or version < self.minAPIVersion then
        Logging.warning("Mod '" .. mod.title .. "' is not compatible with the current version of Seasons. Skipping.")
        return
    end

    local modType = getXMLString(xmlFile, "modDesc.seasons.type")
    if modType == nil then
        Logging.error("Mod '" .. mod.title .. "' has a Seasons information block but it missing a type. Skipping.")
        return
    end
    modType = modType:lower()

    -- Loading multiple GEO mods is never something that a player would want.
    if modType == "geo" and self.isGEOModActive then
        Logging.error("Multiple GEO mods are active. Mod '" .. mod.title .. "' will not be loaded.")
        return
    end

    local modInfo = {}
    modInfo.mod = mod
    modInfo.modType = modType

    local dataFolder = getXMLString(xmlFile, "modDesc.seasons.dataFolder")
    if dataFolder ~= nil then
        modInfo.dataFolder = Utils.getFilename(dataFolder, mod.modDir)
        self:addDataDirectory(modInfo.dataFolder, mod.modDir)
    end

    if modType == "geo" then
        modInfo.isGEO = true
        self.isGEOModActive = true
    end

    table.insert(self.mods, modInfo)

    -- Call an optional function in the mods environment to indicate that we loaded/exist
    local modEnv = getfenv(0)[mod.modName]
    if modEnv ~= nil and modEnv.rm_seasons_load ~= nil then
        self.deferredLoadingManager:addSubtask(function()
            modEnv.rm_seasons_load()
        end)
    end
end

---Get list of third party mods
function SeasonsThirdPartyMods:getMods()
    return self.mods
end

---Add a data directory
function SeasonsThirdPartyMods:addDataDirectory(path, modDir)
    table.insert(self.dataDirectories, { path = path, modDir = modDir })
end

---Get a list of data directories to find files, in order.
-- This also includes the folder from Seasons.
function SeasonsThirdPartyMods:getDataDirectories()
    return self.dataDirectories
end

---Get all data directories, in order
function SeasonsThirdPartyMods:getDataPaths(filename)
    local paths = {}

    -- Add map
    if self.mission.missionInfo.map ~= nil then
        local path = Utils.getFilename("seasons/" .. filename, self.mission.missionInfo.baseDirectory)
        if fileExists(path) then
            table.insert(paths, { file = path, modDir = self.mission.missionInfo.baseDirectory })
        end
    end

    -- Add third party mods
    for _, dir in ipairs(self.dataDirectories) do
        local path = Utils.getFilename(filename, dir.path)

        if fileExists(path) then
            table.insert(paths, { file = path, modDir = dir.modDir })
        end
    end

    return paths
end
