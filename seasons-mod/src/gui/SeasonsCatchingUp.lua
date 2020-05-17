----------------------------------------------------------------------------------------------------
-- SeasonsCatchingUp
----------------------------------------------------------------------------------------------------
-- Purpose:  Handles a dialog that makes the player wait for completion of enough DMS jobs
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsCatchingUp = {}

SeasonsCatchingUp.FAST_FORWARD_THRESHOLD = 300
SeasonsCatchingUp.DMS_THRESHOLD = GS_IS_CONSOLE_VERSION and 2 or 4

local SeasonsCatchingUp_mt = Class(SeasonsCatchingUp)

function SeasonsCatchingUp:new(mission, densityMapScanner, gui, i18n)
    local self = setmetatable({}, SeasonsCatchingUp_mt)

    self.mission = mission
    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()
    self.densityMapScanner = densityMapScanner
    self.gui = gui
    self.i18n = i18n

    self.densityMapScanner:setCatchingUp(self)

    return self
end

function SeasonsCatchingUp:delete()
end

function SeasonsCatchingUp:load()
    self.showDialog = false
    self.didFastForward = false
end

function SeasonsCatchingUp:update(dt)
    -- Only on hosts with a UI
    if not self.isServer or not self.isClient then
        return
    end

    local timeScale = self.mission.missionInfo.timeScale

    -- Detect fast forwarding
    if timeScale > SeasonsCatchingUp.FAST_FORWARD_THRESHOLD then
        self.didFastForward = true
    end

    -- Finished fast forwarding
    if self.didFastForward and timeScale < SeasonsCatchingUp.FAST_FORWARD_THRESHOLD then
        local queueSize = self.densityMapScanner:getQueueSize()

        if queueSize > SeasonsCatchingUp.DMS_THRESHOLD then
            self.showDialog = true
        else
            -- Reset
            self.showDialog = false
            self.didFastForward = false
        end
    else
        self.showDialog = false
    end

    if self.showDialog then
        if self.dialog == nil then
            self.dialog = self.gui:showDialog("MessageDialog", true)

            self.dialog.target:setDialogType(DialogElement.TYPE_LOADING)
            self.dialog.target:setIsCloseAllowed(false)
            self.dialog.target:setText(self.i18n:getText("seasons_warning_catchingUp"))

            self.previousTimeScale = timeScale
            self.mission:setTimeScale(1)
        end
    elseif self.dialog ~= nil then
        self.gui:closeDialog(self.dialog)
        self.dialog = nil

        self.mission:setTimeScale(self.previousTimeScale)
    end
end
