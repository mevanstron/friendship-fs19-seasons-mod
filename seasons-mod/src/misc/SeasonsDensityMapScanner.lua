----------------------------------------------------------------------------------------------------
-- SeasonsDensityMapScanner
----------------------------------------------------------------------------------------------------
-- Purpose:  Performs updates of density maps on behalf of other modules.
-- Authors:  mrbear, Rahkiin
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsDensityMapScanner = {}

local SeasonsDensityMapScanner_mt = Class(SeasonsDensityMapScanner)

SeasonsDensityMapScanner.BLOCK_WIDTH = 32
SeasonsDensityMapScanner.BLOCK_HEIGHT = 32

function SeasonsDensityMapScanner:new(mission, deferredLoadingManager, dedicatedServerInfo, sleepManager)
    local self = setmetatable({}, SeasonsDensityMapScanner_mt)

    self.mission = mission
    self.deferredLoadingManager = deferredLoadingManager
    self.isServer = mission:getIsServer()
    self.isDedicatedServer = dedicatedServerInfo ~= nil
    self.sleepManager = sleepManager

    self.queue = Queue:new()
    self.callbacks = {}

    return self
end

function SeasonsDensityMapScanner:delete()
    self.queue:delete()
end

function SeasonsDensityMapScanner:load()
end

function SeasonsDensityMapScanner:loadFromSavegame(xmlFile)
    if hasXMLProperty(xmlFile, "seasons.dms.currentJob") then
        local key = "seasons.dms.currentJob"

        local job = {}
        job.x = Utils.getNoNil(getXMLInt(xmlFile, key .. ".x"), 0)
        job.z = Utils.getNoNil(getXMLInt(xmlFile, key .. ".z"), -1)
        job.callbackId = getXMLString(xmlFile, key .. ".callbackId")
        job.numSegments = getXMLInt(xmlFile, key .. ".numSegments")

        local parameters = Utils.getNoNil(getXMLString(xmlFile, key .. ".parameters"), "")
        job.parameters = StringUtil.splitString(";", parameters)
        for i, v in ipairs(job.parameters) do
            job.parameters[i] = tonumber(v)
        end

        self.currentJob = job

        log("[SeasonsDensityMapScanner] Loaded current job:", job.callbackId, "with", #job.parameters, "parameters")
    end

    local i = 0
    while true do
        local key = string.format("seasons.dms.queue.job(%d)", i)
        if not hasXMLProperty(xmlFile, key) then
            break
        end

        local job = {}
        job.callbackId = getXMLString(xmlFile, key .. "#callbackId")

        local parameters = Utils.getNoNil(getXMLString(xmlFile, key .. "#parameters"), "")
        job.parameters = StringUtil.splitString(";", parameters)
        for i, v in ipairs(job.parameters) do
            job.parameters[i] = tonumber(v)
        end

        self.queue:push(job)

        log("[SeasonsDensityMapScanner] Loaded queued job:", job.callbackId, "with parameter", job.parameter)

        i = i + 1
    end
end

function SeasonsDensityMapScanner:saveToSavegame(xmlFile)
    if self.currentJob ~= nil then
        local key = "seasons.dms.currentJob"

        setXMLInt(xmlFile, key .. ".x", self.currentJob.x)
        setXMLInt(xmlFile, key .. ".z", self.currentJob.z)
        setXMLString(xmlFile, key .. ".callbackId", self.currentJob.callbackId)
        setXMLString(xmlFile, key .. ".parameters", table.concat(self.currentJob.parameters, ";"))

        if self.currentJob.numSegments ~= nil then
            setXMLInt(xmlFile, key .. ".numSegments", self.currentJob.numSegments)
        end
    end

    -- Save queue
    self.queue:iteratePushOrder(function (job, i)
        local key = string.format("seasons.dms.queue.job(%d)", i - 1)

        setXMLString(xmlFile, key .. "#callbackId", job.callbackId)

        if job.parameters ~= nil then
            setXMLString(xmlFile, key .. "#parameters", table.concat(job.parameters, ";"))
        end
    end)
end

---Run the whole queue. Use only when the game is being loaded as different jobs are deferred to keep the loading indicator alive.
function SeasonsDensityMapScanner:runWholeQueue()
    -- Quickly run any job already queued, with async steps to keep the loading spinner going between jobs

    if self.currentJob ~= nil then
        self.deferredLoadingManager:addSubtask(function ()
            while self.currentJob ~= nil do
                if not self:run(self.currentJob) then
                    self.currentJob = nil
                end
            end
        end)
    end

    self.queue:iteratePushOrder(function (job)
        self.deferredLoadingManager:addSubtask(function ()
            self.currentJob = self.queue:pop()
            self.currentJob.x = 0
            self.currentJob.z = 0

            -- log("[SeasonsDensityMapScanner] Dequed job:", self.currentJob.callbackId, "(", table.concat(self.currentJob.parameters, ";"), ")")

            while self.currentJob ~= nil do
                if not self:run(self.currentJob) then
                    self.currentJob = nil
                end
            end
        end)
    end)
end

function SeasonsDensityMapScanner:setCatchingUp(catchingUp)
    self.catchingUp = catchingUp
end

function SeasonsDensityMapScanner:update(dt)
    if not self.isServer then
        return
    end

    -- Start a nw job
    if self.currentJob == nil then
        self.currentJob = self.queue:pop()

        -- A new job has started
        if self.currentJob then
            self.currentJob.x = 0
            self.currentJob.z = 0

            -- log("[SeasonsDensityMapScanner] Dequed job:", self.currentJob.callbackId, "(", table.concat(self.currentJob.parameters, ";"), ")")
        end
    end

    if self.currentJob ~= nil then
        local num = 4 -- do 4x a 16m^2 area, for caching purposes within the engine

        -- Increase number of blocks when 4x or 16x map.
        num = num * math.floor(self.mission.terrainSize / 2048)

        -- Run console at half the speed of PC
        if not GS_IS_CONSOLE_VERSION then
            num = num * 2
        end

        -- When skipping night, do a bit more per frame, the player can't move anyways.
        if self.sleepManager.isSleeping or self.catchingUp.showDialog then
            num = num * 8
        end

        -- On a dedi, run while rows at a time. This causes optimal network syncing behaviour.
        -- There is no UI so we don't need 60+ fps all the time, especially if we would be blocking the network queue instead.
        if self.isDedicatedServer then
            num = self.mission.terrainSize / SeasonsDensityMapScanner.BLOCK_WIDTH
        end

        -- Run one or more chunks
        for i = 1, num do
            if not self:run(self.currentJob) then
                self.currentJob = nil

                break
            end
        end
    end
end

---Get whether the DMS is currently performing any work
function SeasonsDensityMapScanner:isBusy()
    return self.currentJob ~= nil or not self.queue:isEmpty()
end

---Get the size of the queue
function SeasonsDensityMapScanner:getQueueSize()
    return self.queue.size
end

---Queue a new job
function SeasonsDensityMapScanner:queueJob(callbackId, parameters)
    if self.isServer then
        if type(parameters) ~= "table" then
            parameters = {parameters}
        end

        if self.callbacks[callbackId] == nil then
            Logging.error("Callback '" .. callbackId .. "' is not registered with the density map scanner.")
            return
        end

        -- log("[SeasonsDensityMapScanner] Enqued job:", callbackId, "(", table.concat(parameters, ";"), ")")

        local job = {
            callbackId = callbackId,
            parameters = parameters
        }

        -- Fold the job first to limit number of jobs in queue and number of updates
        if not self:foldNewJob(job) then
            self.queue:push(job)
        end
    end
end

---Register a new DMS callback
--
-- A callback is bound to the callbackId: the name of the DMS action.
-- When a job with given callbackId is queued, func is called on target,
-- with the job parameter as last argument, after world parallelogram.
-- After the job finished, a possible finalizer is called on the target,
-- also with the job paramater.
--
-- @param callbackId String, name of jobrunner
-- @param target table, contains func and finalizer functions
-- @param func function to run for each segment of the world
-- @param finalizer function to run after all segments are run, optional
-- @param detailHeightId bool on whether this is a job over the terrainDetailHeightId, optional
-- @param mergeFunction function to run when adding a task to optimize the queue, optional
function SeasonsDensityMapScanner:registerCallback(callbackId, func, target, finalizer, detailHeightId, mergeFunction)
    log("[SeasonsDensityMapScanner] Registering callback: " .. callbackId)

    if self.callbacks == nil then
        self.callbacks = {}
    end

    if detailHeightId == nil then
        detailHeightId = false
    end

    self.callbacks[callbackId] = {
        target = target,
        func = func,
        finalizer = finalizer,
        detailHeightId = detailHeightId,
        mergeFunction = mergeFunction,
    }
end

---Remove a calback
-- Note that if the callback is in use it will crash upon usage.
function SeasonsDensityMapScanner:unregisterCallback(callbackId)
    self.callbacks[callbackId] = nil
end

-- Returns: true when new cycle needed. false when done
function SeasonsDensityMapScanner:run(job)
    assert(job ~= nil)

    local jobRunnerInfo = self.callbacks[job.callbackId]
    if jobRunnerInfo == nil then
        logInfo("[SeasonsDensityMapScanner] Tried to run unknown callback '", job.callbackId, "'")

        return false
    end

    -- Row height (64px for caching)
    local height = SeasonsDensityMapScanner.BLOCK_HEIGHT
    local width = SeasonsDensityMapScanner.BLOCK_WIDTH

    local size = self.mission.terrainSize
    local pixelSize = size / getDensityMapSize(self.mission.terrainDetailHeightId)

    if not jobRunnerInfo.detailHeightId then
        pixelSize = size / getDensityMapSize(self.mission.terrainDetailId)
    end


    local startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ

    if jobRunnerInfo.detailHeightId then
        startWorldX = job.x * width - size / 2
        startWorldZ = job.z * height - size / 2

        widthWorldX = startWorldX + width - pixelSize
        widthWorldZ = startWorldZ

        heightWorldX = startWorldX
        heightWorldZ = startWorldZ + height - pixelSize
    else
        startWorldX = job.x * width - size / 2 + pixelSize * 0.25
        startWorldZ = job.z * height - size / 2 + pixelSize * 0.25

        widthWorldX = startWorldX + width - pixelSize * 0.5
        widthWorldZ = startWorldZ

        heightWorldX = startWorldX
        heightWorldZ = startWorldZ + height - pixelSize * 0.5
    end

    jobRunnerInfo.func(jobRunnerInfo.target, startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, job.parameters)

    -- Update current job
    if job.x < (size / width) - 1 then -- Starting with row 0
        -- Next row
        job.x = job.x + 1
    elseif job.z < (size / height) - 1 then
        job.z = job.z + 1
        job.x = 0
    else
        -- Done with the loop, call finalizer
        if jobRunnerInfo.finalizer ~= nil then
            jobRunnerInfo.finalizer(jobRunnerInfo.target, job.parameters)
        end

        return false -- finished
    end

    return true -- not finished
end

---Attempt to fold a job into the queue to optimize it.
-- For example, two jobs that both add a layer of snow could be one job adding two layers of snow.
-- @param job job to fold
-- @return true when folded, false when enqueueing is needed
function SeasonsDensityMapScanner:foldNewJob(job)
    local jobRunnerInfo = self.callbacks[job.callbackId]
    if jobRunnerInfo == nil then
        return false
    end

    local folded = false

    if jobRunnerInfo.mergeFunction ~= nil then
        folded = jobRunnerInfo.mergeFunction(jobRunnerInfo.target, job, self.queue)
    end

    return folded
end
