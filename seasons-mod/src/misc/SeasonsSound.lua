----------------------------------------------------------------------------------------------------
-- SeasonsSound
----------------------------------------------------------------------------------------------------
-- Purpose:  Sound system
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsSound = {}

local SeasonsSound_mt = Class(SeasonsSound)

function SeasonsSound.onMissionWillLoad()
    SeasonsModUtil.overwrittenFunction(SoundNode, "new", SeasonsSound.inj_soundNode_new)
end

function SeasonsSound:new(mission, soundManager, modDirectory, ambientSoundManager, weather, gui)
    local self = setmetatable({}, SeasonsSound_mt)

    self.mission = mission
    self.modDirectory = modDirectory
    self.soundManager = soundManager
    self.ambientSoundManager = ambientSoundManager
    self.weather = weather
    self.gui = gui

    self:resetAmbientData()

    self.debug = false

    self.isThunderSoundPending = false
    self.weather.handler.stormUpdater:setSoundHandler(function()
        self.isThunderSoundPending = true
    end)

    SeasonsModUtil.overwrittenFunction(Player, "getCurrentSurfaceSound", SeasonsSound.inj_player_getCurrentSurfaceSound)

    local noop = function() end
    SeasonsModUtil.overwrittenConstant(getfenv(0), "setEnableAmbientSound", noop)
    SeasonsModUtil.overwrittenConstant(getfenv(0), "updateAmbientSound", noop)
    SeasonsModUtil.overwrittenConstant(getfenv(0), "unloadAmbientSound", noop)
    SeasonsModUtil.overwrittenConstant(getfenv(0), "loadAmbientSound", noop)
    SeasonsModUtil.overwrittenFunction(AmbientSoundManager, "getState", SeasonsSound.inj_ambientSoundManager_getState)
    SeasonsModUtil.overwrittenFunction(SoundNode, "getCanPlaySound", SeasonsSound.inj_soundNode_getCanPlaySound)

    addConsoleCommand("rmToggleSoundDebug", "Toggle sound debugging", "consoleCommandToggleDebug", self)
    addConsoleCommand("rmReloadSound", "Reload sounds", "consoleCommandReload", self)

    return self
end

function SeasonsSound:delete()
    self:deleteAmbientSounds()

    removeConsoleCommand("rmToggleSoundDebug")
    removeConsoleCommand("rmReloadSound")
end

function SeasonsSound:load()
    self:loadExtraSounds()
    self:loadAmbientSoundsFromXML()
    self:initializeAmbientSounds()
end

---Load extra surface sounds from Seasons into the game on top of the existing vanilla ones
function SeasonsSound:loadExtraSounds()
    local surfaceSounds = self.mission.surfaceSounds
    local cuttingSounds = self.mission.cuttingSounds
    self.mission:loadMapSounds(Utils.getFilename("resources/sound.xml", self.modDirectory), self.modDirectory)

    for _, sound in ipairs(self.mission.surfaceSounds) do
        table.insert(surfaceSounds, sound)
    end
    for _, sound in ipairs(self.mission.cuttingSounds) do
        table.insert(cuttingSounds, sound)
    end

    self.mission.surfaceSounds = surfaceSounds
    self.mission.cuttingSounds = cuttingSounds
end

---Load sounds for rain/snow/wind/hail
function SeasonsSound:loadAmbientSoundsFromXML()
    local xmlFile = loadXMLFile("SeasonsSound", Utils.getFilename("resources/sound.xml", self.modDirectory))
    if not xmlFile then
        return
    end

    local i = 0
    while true do
        local key = string.format("sound.ambient.weather(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local weather = {}
        weather.sounds = {}
        weather.name = getXMLString(xmlFile, key .. "#name")
        weather.layer = getXMLString(xmlFile, key .. "#layer")

        local j = 0
        while true do
            local soundKey = string.format("%s.sound(%d)", key, j)
            if not hasXMLProperty(xmlFile, soundKey) then
                break
            end

            local sound = {}
            local filename = getXMLString(xmlFile, soundKey .. "#file")
            if filename ~= nil then
                sound.file = Utils.getFilename(filename, self.modDirectory)

                sound.minIntensity = getXMLFloat(xmlFile, soundKey .. "#minIntensity")
                sound.maxIntensity = getXMLFloat(xmlFile, soundKey .. "#maxIntensity")

                sound.probabilityMultiplier = Utils.getNoNil(getXMLInt(xmlFile, soundKey .. "#probabilityMultiplier"), 1)

                if sound.minIntensity > sound.maxIntensity then
                    Logging.error("Ambient: minIntensity is larger than maxIntensity of sound in '%s'!", weather.name)
                    break
                end

                sound.volumeIndoor = getXMLFloat(xmlFile, soundKey .. ".volume#indoor")
                sound.volumeOutdoor = getXMLFloat(xmlFile, soundKey .. ".volume#outdoor")

                sound.lowpassGainIndoor = getXMLFloat(xmlFile, soundKey .. ".lowpassGain#indoor")
                sound.lowpassGainOutdoor = getXMLFloat(xmlFile, soundKey .. ".lowpassGain#outdoor")

                sound.pitchIndoor = getXMLFloat(xmlFile, soundKey .. ".pitch#indoor")
                sound.pitchOutdoor = getXMLFloat(xmlFile, soundKey .. ".pitch#outdoor")

                sound.weatherName = weather.name -- used for active list

                table.insert(weather.sounds, sound)
            end

            j = j + 1
        end

        self.ambient.weather[weather.name] = weather
        table.insert(self.ambient.weathers, weather)

        if self.ambient.layers[weather.layer] == nil then
            self.ambient.layers[weather.layer] = {}
        end
        table.insert(self.ambient.layers[weather.layer], weather)

        i = i + 1
    end

    delete(xmlFile)
end

----------------------
-- Events
----------------------

function SeasonsSound:update(dt)
    self:updateAmbientSound(dt)
end

----------------------
-- Ambient sound management
----------------------

function SeasonsSound:resetAmbientData()
    self.ambient = {}
    self.ambient.weather = {}
    self.ambient.weathers = {}
    self.ambient.layers = {}

    self.ambient.weatherCrossFadePosition = 0
    self.ambient.active = setmetatable({}, {__mode = "k"})
    self.ambient.currentWeatherName = nil
    self.ambient.currentIntensity = 0
    self.activeThunderSounds = setmetatable({}, {__mode = "k"})

    self.activeThunderSound = nil
end

--- Load all sounds
function SeasonsSound:initializeAmbientSounds()
    for _, weather in pairs(self.ambient.weather) do
        for i, sound in ipairs(weather.sounds) do
            sound.sample = createSample(weather.name .. tostring(i))
            loadSample(sound.sample, sound.file, false)
            setSampleGroup(sound.sample, AudioGroup.ENVIRONMENT)
            sound.duration = getSampleDuration(sound.sample)
        end
    end

    -- Create weighted list for thunders
    local thunders = self.ambient.layers["thunder"]
    if thunders ~= nil then
        for _, thunder in ipairs(thunders) do
            thunder.weighted = {}

            for s, sound in ipairs(thunder.sounds) do
                for i = 1, sound.probabilityMultiplier do
                    table.insert(thunder.weighted, s)
                end
            end
        end
    end
end

function SeasonsSound:deleteAmbientSounds()
    for _, weather in pairs(self.ambient.weather) do
        for _, sound in ipairs(weather.sounds) do
            if sound.sample ~= nil then
                delete(sound.sample)
                sound.sample = nil
            end
        end
    end

    self.ambient.active = nil
end

---Update weather ambient sound by cross fading for intensities and for switching weather types
function SeasonsSound:updateAmbientSound(dt)
     local _, isIndoor = self.ambientSoundManager:getState()

    local gameStateFactor = not g_gui:getIsGuiVisible() and 1 or 0

    self:updateDownfallLayer(isIndoor, gameStateFactor)
    self:updateThunderLayer(isIndoor, gameStateFactor)
    self:updateWindLayer(isIndoor, gameStateFactor)
end

---Update downfall sounds based on weather and intensity
function SeasonsSound:updateDownfallLayer(isIndoor, gameStateFactor)
    local intensity, downfallType, targetDownfallType, targetAlpha = self.weather:getDownfallFadeState()
    if downfallType == nil then
        -- Disable all sounds. Should already have faded out
        if self.ambient.currentWeatherName ~= "none" then
            for _, sound in pairs(self.ambient.active) do
                stopSample(sound.sample, 0.0, 0.25)
                self.ambient.active[sound] = nil
            end
        end

        self.ambient.currentWeatherName = "none"
        return
    end

    -- When switching between two weather types, run both and fade between them
    if targetDownfallType == nil or targetDownfallType == downfallType then
        self:updateAmbientWeatherSound(downfallType, intensity, isIndoor, 1 * gameStateFactor, 0)
    else
        -- https://dsp.stackexchange.com/questions/14754/equal-power-crossfade
        local t = 2 * targetAlpha - 1
        self:updateAmbientWeatherSound(downfallType, intensity, isIndoor, math.sqrt(0.5 * (1 - t)) * gameStateFactor, 1)
        self:updateAmbientWeatherSound(targetDownfallType, intensity, isIndoor, math.sqrt(0.5 * (1 + t)) * gameStateFactor, 2)
    end

    self.ambient.currentWeatherName = weatherName
end

---Update ambient sound for given weather to match intensity
-- @param weatherName string Type of the weather to update
-- @param intensity number Intensity to set for this weather sound
-- @param isIndoor boolean whether the listener is indoor (sound configuration)
-- @param alphaFadeFactor number Factor applied to all volumes for fading between weathers
function SeasonsSound:updateAmbientWeatherSound(weatherName, intensity, isIndoor, alphaFadeFactor, p)
    -- Get samples we want to run
    local info = self.ambient.weather[weatherName]
    if info == nil then
        -- No configuration for given weather
        return
    end

    -- Go over all sounds. Activate those that should be active. Stop others
    for _, sound in ipairs(info.sounds) do
        -- Use < here so there is no sound for intensity 0
        if sound.minIntensity < intensity and sound.maxIntensity >= intensity then
            if self.ambient.active[sound] == nil then
                self.ambient.active[sound] = sound

                if self.debug then
                    log("Starting sound", weatherName, _)
                end

                local volume = 0
                playSample(sound.sample, 0, volume, 0, 0, 0)
            end
        else
            if self.ambient.active[sound] ~= nil then
                local fadeOut = 0.25
                stopSample(sound.sample, 0.0, fadeOut)

                if self.debug then
                    log("Stopped sound", weatherName, _)
                end

                self.ambient.active[sound] = nil
            end
        end
    end

    -- We can only fade between two samples. Find the left (fading out) and right (fading in) samples
    local left, right
    for _, sound in pairs(self.ambient.active) do
        -- Notes: right can only be set once. Once it is, disable all other sounds
        if sound.weatherName == weatherName then
            if left == nil then
                left = sound
            elseif right == nil and sound.minIntensity < left.minIntensity then
                right = left
                left = sound
            elseif right == nil and left.minIntensity < sound.minIntensity then
                right = sound
            end
        end
    end

    -- If no sounds are active, or none for given weather type: stop
    if left == nil then
        return
    end

    if self.debug then
        local text
        if right == nil then
            text = string.format("L %f %f %s", left.minIntensity, left.maxIntensity, left.weatherName)
        else
            text = string.format("L %f %f %s, R %f %f %s", left.minIntensity, left.maxIntensity, left.weatherName, right.minIntensity, right.maxIntensity, right.weatherName)
        end
        renderText(0.5, 0.25 + p * 2 * 0.01, getCorrectTextSize(0.01), text)
        renderText(0.5, 0.25 + ((p * 2) + 1) * 0.01, getCorrectTextSize(0.01), weatherName .. " / " .. tostring(intensity) .. " / " .. tostring(alphaFadeFactor))
    end

    -- A single sample because we are not fading. Make sure volume is 1
    if right == nil then
        self:updateSoundAttributes(left, alphaFadeFactor, isIndoor)
    else
        -- Find fading alpha ('slider' position)
        a = right.minIntensity
        b = left.maxIntensity
        local alpha = (intensity - a) / (b - a) -- divide by length to make 0-1

        -- https://dsp.stackexchange.com/questions/14754/equal-power-crossfade
        local t = 2 * alpha - 1 -- [-1, 1]

        local leftVolume = math.sqrt(0.5 * (1 - t))
        self:updateSoundAttributes(left, leftVolume * alphaFadeFactor, isIndoor)

        local rightVolume = math.sqrt(0.5 * (1 + t))
        self:updateSoundAttributes(right, rightVolume * alphaFadeFactor, isIndoor)
    end
end

---Update sound properties
function SeasonsSound:updateSoundAttributes(sound, volumeFactor, isIndoor)
    -- Prevent drastic changes to the lowpassGain to prevent popping when switching between indoor and outdoor
    local target = isIndoor and sound.lowpassGainIndoor or sound.lowpassGainOutdoor
    local current = Utils.getNoNil(sound.currentLowpassGain, target)
    sound.currentLowpassGain = current + math.max(-0.05, math.min(0.05, target - current))

    setSampleVolume(sound.sample, volumeFactor * (isIndoor and sound.volumeIndoor or sound.volumeOutdoor))
    setSampleFrequencyFilter(sound.sample, 1.0, sound.currentLowpassGain)
    setSamplePitch(sound.sample, isIndoor and sound.pitchIndoor or sound.pitchOutdoor)
end

---Play thunder sounds if the weather wants to.
function SeasonsSound:updateThunderLayer(isIndoor, gameStateFactor)
    if self.isThunderSoundPending then
        local sound = self:playRandomThunderSound(isIndoor, gameStateFactor)
        self.activeThunderSounds[sound] = sound

        self.isThunderSoundPending = false
    end

    for _, sound in pairs(self.activeThunderSounds) do
        if isSamplePlaying(sound.sample) then
            self:updateSoundAttributes(sound, gameStateFactor, isIndoor)
        else
            self.activeThunderSounds[sound] = nil
        end
    end

--[[
    if self.isThunderSoundPending then
        if self.activeThunderSound == nil then
            self.activeThunderSound = self:playRandomThunderSound(isIndoor, gameStateFactor)
        end

        self.isThunderSoundPending = false
    end

    if self.activeThunderSound ~= nil then
        if isSamplePlaying(self.activeThunderSound.sample) then
            self:updateSoundAttributes(self.activeThunderSound, gameStateFactor, isIndoor)
        else
            self.activeThunderSound = nil
        end
    end
]]
end

---Play a one-shot thunder sound
function SeasonsSound:playRandomThunderSound(isIndoor, gameStateFactor)
    local thunders = self.ambient.layers["thunder"]
    if #thunders > 0 then
        local thunder = ListUtil.getRandomElement(thunders)

        local index = ListUtil.getRandomElement(thunder.weighted)
        local sound = thunder.sounds[index]

        self:updateSoundAttributes(sound, gameStateFactor, isIndoor)
        playSample(sound.sample, 1, 1, 0, 0, 0)

        return sound
    end
end

---Update the wind layer that backs all others
function SeasonsSound:updateWindLayer(isIndoor, gameStateFactor)
    local speedFactor = self.weather:getWindVelocity() / WindUpdater.MAX_SPEED
    local intensity = speedFactor
    local volumeModifier = math.sqrt(speedFactor)

    if self.debug then
        renderText(0.5, 0.25, getCorrectTextSize(0.01), string.format("Wind speed: %0.2f m/s, %d km/h, speedFactor %0.2f", speedFactor * WindUpdater.MAX_SPEED, speedFactor * WindUpdater.MAX_SPEED * 3.6, speedFactor))
    end

    self:updateAmbientWeatherSound("wind", intensity, isIndoor, gameStateFactor * volumeModifier, 4)
end

----------------------
-- Injections
----------------------

---Get a surface sound for the player. Needs extra checks to look for snow
function SeasonsSound.inj_player_getCurrentSurfaceSound(player, superFunc, x, y, z)
    local heightType = DensityMapHeightUtil.getHeightTypeDescAtWorldPos(x,y,z, 0.5)
    if heightType ~= nil and heightType.soundMaterialId ~= nil then
        return player.soundInformation.surfaceIdToSound[heightType.soundMaterialId], shallowWater
    end

    return superFunc(player, x, y, z)
end

---Add new properties
function SeasonsSound.inj_ambientSoundManager_getState(ambientSoundManager, superFunc)
    local info = { superFunc(ambientSoundManager) }

    local season = g_seasons.environment.season
    local isFreezing = g_seasons.weather:getIsFreezing()

    local downfall = g_seasons.weather:getDownfallState()
    local isSnowing = downfall == "snow"

    local isStorming = g_seasons.weather:getIsStorming()

    info[9] = {season, isFreezing, isSnowing, isStorming}

    return unpack(info)
end

---Load custom attributes for seasonal properties
function SeasonsSound.inj_soundNode_new(soundNode, superFunc, node, group, customMt)
    soundNode = superFunc(soundNode, node, group, customMt)

    -- Whether to have the sound active during snow
    soundNode.playDuringSnow = Utils.getNoNil(getUserAttribute(node, "playDuringSnow"), false)

    -- Whether to have the sound acitve during a season. Default to vanilla behaviour: yes
    soundNode.playInSpring = Utils.getNoNil(getUserAttribute(node, "playInSpring"), true)
    soundNode.playInSummer = Utils.getNoNil(getUserAttribute(node, "playInSummer"), true)
    soundNode.playInAutumn = Utils.getNoNil(getUserAttribute(node, "playInAutumn"), true)
    soundNode.playInWinter = Utils.getNoNil(getUserAttribute(node, "playInWinter"), true)
    if not soundNode.playInSpring and not soundNode.playInSummer and not soundNode.playInAutumn and not soundNode.playInWinter then
        -- Disabled for Seasons
        soundNode:delete()
        return nil
    end

    -- Weather based, default to vanilla behavior
    soundNode.playWhenFreezing = Utils.getNoNil(getUserAttribute(node, "playWhenFreezing"), true)
    soundNode.playDuringStorm = Utils.getNoNil(getUserAttribute(node, "playDuringStorm"), true)

    return soundNode
end

---Determine whether a sound is playable using new seasonal properties
function SeasonsSound.inj_soundNode_getCanPlaySound(soundNode, superFunc, isDay, isSun, isRain, isHail, isIndoor, isInsideBuilding, dayTime, extra)
    local canPlaySound = superFunc(soundNode, isDay, isSun, isRain, isHail, isIndoor, isInsideBuilding, dayTime, extra)
    if not canPlaySound then
        return false
    end

    if extra ~= nil then
        local season, isFreezing, isSnowing, isStorming = unpack(extra)

        canPlaySound = canPlaySound and ((season == SeasonsEnvironment.SPRING and soundNode.playInSpring) or (season == SeasonsEnvironment.SUMMER and soundNode.playInSummer) or (season == SeasonsEnvironment.AUTUMN and soundNode.playInAutumn) or (season == SeasonsEnvironment.WINTER and soundNode.playInWinter))
        canPlaySound = canPlaySound and (soundNode.playWhenFreezing or not isFreezing)
        canPlaySound = canPlaySound and (soundNode.playDuringSnow or not isSnowing)
        canPlaySound = canPlaySound and (soundNode.playDuringStorm or not isStorming)
    end

    return canPlaySound
end

----------------------
-- Commands
----------------------

function SeasonsSound:consoleCommandToggleDebug()
    self.debug = not self.debug
    return tostring(self.debug)
end

function SeasonsSound:consoleCommandReload()
    log("Unloading...")
    self:deleteAmbientSounds()
    self:resetAmbientData()

    log("Loading...")
    self:loadAmbientSoundsFromXML()
    self:initializeAmbientSounds()

    log("Reloaded!")
end
