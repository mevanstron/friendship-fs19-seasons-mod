----------------------------------------------------------------------------------------------------
-- SeasonsTrees
----------------------------------------------------------------------------------------------------
-- Purpose:  Tree growth inhibition dependent on coverage (tree distance). Also update of growth time
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsTrees = {}

SeasonsTrees.YEARS_GROWTH = 5
SeasonsTrees.MIN_DISTANCE = 9.5
SeasonsTrees.MIN_DISTANCE_SQ = SeasonsTrees.MIN_DISTANCE * SeasonsTrees.MIN_DISTANCE

local SeasonsTrees_mt = Class(SeasonsTrees)

function SeasonsTrees:new(mission, treePlantManager, messageCenter, environment)
    local self = setmetatable({}, SeasonsTrees_mt)

    self.mission = mission
    self.treePlantManager = treePlantManager
    self.messageCenter = messageCenter
    self.environment = environment
    self.isServer = mission:getIsServer()

    SeasonsModUtil.appendedFunction(ChainsawUtil,           "cutSplitShapeCallback",    SeasonsTrees.inj_chainsawUtil_cutSplitShapeCallback)
    SeasonsModUtil.overwrittenFunction(TreePlantManager,    "plantTree",                SeasonsTrees.inj_treePlantManager_plantTree)
    SeasonsModUtil.overwrittenFunction(TreePlantManager,    "updateTrees",              SeasonsTrees.inj_treePlantManager_updateTrees)
    SeasonsModUtil.prependedFunction(TreePlantManager,      "cleanupDeletedTrees",      SeasonsTrees.inj_treePlantManager_cleanupDeletedTrees)

    return self
end

function SeasonsTrees:delete()
end

function SeasonsTrees:load()
    if self.isServer then
        self.messageCenter:subscribe(SeasonsMessageType.SEASON_LENGTH_CHANGED, self.onSeasonLengthChanged, self)
    end
end

function SeasonsTrees:onGameLoaded()
    if self.isServer then
        self:adjustTreeGrowthDuration()
    end
end

function SeasonsTrees:onSeasonLengthChanged()
    self:adjustTreeGrowthDuration()
end

---Change the trees to adhere to season length by changing the growth time
function SeasonsTrees:adjustTreeGrowthDuration()
    for _, treeType in ipairs(self.treePlantManager.treeTypes) do
        treeType.growthTimeHours = self.environment.daysPerSeason * 4 * 24 * SeasonsTrees.YEARS_GROWTH
    end
end

---Get whether the growth of given tree is limited by coverage
function SeasonsTrees:isTreeGrowthLimited(tree)
    local limits = {
        [4.5] = 0.45,
        [6.5] = 0.65,
        [SeasonsTrees.MIN_DISTANCE] = 0.85,
    }
    local eps = 0.02

    for distance, state in pairs(limits) do
        if tree.nearestDistance < distance and tree.growthState < state + eps and tree.growthState > state - eps then
            return true
        end
    end

    return false
end

---Find the nearest in the small set
local function updateNearestTrees(tree)
    tree.nearestDistance = SeasonsTrees.MIN_DISTANCE_SQ + 1

    for other, distance in pairs(tree.near) do
        if distance < tree.nearestDistance then
            tree.nearestDistance = distance
        end
    end

    tree.nearestDistance = math.sqrt(tree.nearestDistance)
end

---Remove the tree from all its neighbors
local function removeTreeFromDatastructure(tree)
    -- Remove the cut tree from all its neighbors
    for otherTree, _ in pairs(tree.near) do
        otherTree.near[tree] = nil

        updateNearestTrees(otherTree)
    end

    tree.near = {}
end

------------------------------------------------
--- Injections
------------------------------------------------

---Limit the growth of any tree depending on the closest neighbouring tree
function SeasonsTrees.inj_treePlantManager_updateTrees(treePlantManager, superFunc, dt, dtGame)
    local treesData = treePlantManager.treesData

    if treesData.updateDtGame + dtGame > 1000 * 60 * 10 then -- the game does not update more often
        for _, tree in ipairs(treesData.growingTrees) do
            -- Capping growthState if the distance is too small for the tree to grow
            -- Distances are somwehat larger than what should be expected in RL
            if tree.nearestDistance ~= nil then
                if tree.nearestDistance < 4.5 and tree.growthState > 0.45 then
                    tree.growthState = 0.45
                elseif tree.nearestDistance < 6.5 and tree.growthState > 0.65 then
                    tree.growthState = 0.65
                elseif tree.nearestDistance < SeasonsTrees.MIN_DISTANCE and tree.growthState > 0.85 then
                    tree.growthState = 0.85
                end
            end
        end
    end

    return superFunc(treePlantManager, dt, dtGame)
end

---There can be trees that are not really 'cut' but deleted either way. Clear them from the datastructure.
function SeasonsTrees.inj_treePlantManager_cleanupDeletedTrees(treePlantManager)
    local treesData = treePlantManager.treesData

    for _, tree in ipairs(treesData.growingTrees) do
        if getNumOfChildren(tree.node) == 0 then
            removeTreeFromDatastructure(tree)
        end
    end
end

---For a planted tree, find the nearest trees.
-- This code is roughly O(n)
function SeasonsTrees.inj_treePlantManager_plantTree(treePlantManager, superFunc, treeType, x,y,z, ...)
    local growingTrees = treePlantManager.treesData.growingTrees
    local sizeBeforeNew = #growingTrees

    -- Verify if an actual tree was placed
    superFunc(treePlantManager, treeType, x,y,z, ...)

    local latestTreeIndex = #growingTrees
    if latestTreeIndex == 0 or sizeBeforeNew == latestTreeIndex then
        return
    end

    local plantedTree = growingTrees[latestTreeIndex]

    plantedTree.near = {}
    for _, tree in pairs(growingTrees) do
        if tree ~= plantedTree then
            local distance = MathUtil.vector3LengthSq(tree.x - x, tree.y - y, tree.z - z)

            -- If the trees are in distance, store their relation
            if distance < SeasonsTrees.MIN_DISTANCE_SQ then
                plantedTree.near[tree] = distance

                tree.near[plantedTree] = distance
                updateNearestTrees(tree)
            end
        end
    end

    updateNearestTrees(plantedTree)
end

-- This code is about O(5) (theoretically max O(n) but can't plant trees that close)
function SeasonsTrees.inj_chainsawUtil_cutSplitShapeCallback(...)
    local cutTree

    -- Find the tree that was just cut
    for _, tree in pairs(g_treePlantManager.treesData.growingTrees) do
        if getChildAt(tree.node, 0) ~= tree.origSplitShape and tree.cutHandled ~= true then
            tree.cutHandled = true

            cutTree = tree

            break
        end
    end

    if cutTree ~= nil then
        removeTreeFromDatastructure(cutTree)
    end
end
