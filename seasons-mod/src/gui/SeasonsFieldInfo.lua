----------------------------------------------------------------------------------------------------
-- SeasonsFieldInfo
----------------------------------------------------------------------------------------------------
-- Purpose:  NPC and mission updates
--
-- Copyright (c) Realismus Modding, 2018
----------------------------------------------------------------------------------------------------

SeasonsFieldInfo = {}

SeasonsFieldInfo.MAP_OVERLAY = {}
SeasonsFieldInfo.MAP_OVERLAY.GROWTH_STATE_INDEX_PLANTED = 8
SeasonsFieldInfo.MAP_OVERLAY.GROWTH_STATE_INDEX_FAILED_GERMINATION = 9

local SeasonsFieldInfo_mt = Class(SeasonsFieldInfo)

function SeasonsFieldInfo:new(hud)
    local self = setmetatable({}, SeasonsFieldInfo_mt)

    self.hud = hud

    local threeStageFertilizationColors = {
        [false] = {
            {0.0595, 0.2086, 0.8227, 1},
            {0.0091, 0.0931, 0.5841, 1},
            {0.0018, 0.0382, 0.2961, 1},
        },
        [true] = {
            {0.0976, 0.2086, 0.8148, 1},
            {0.0086, 0.0976, 0.5776, 1},
            {0.0000, 0.0409, 0.2918, 1},
        }
    }

    SeasonsModUtil.appendedFunction(FieldInfoDisplay,           "onFieldDataUpdateFinished",    SeasonsFieldInfo.inj_fieldInfoDisplay_onFieldDataUpdateFinished)
    SeasonsModUtil.appendedFunction(FieldInfoDisplay,           "setFruitType",                 SeasonsFieldInfo.inj_fieldInfoDisplay_setFruitType)
    SeasonsModUtil.appendedFunction(MapOverlayGenerator,        "buildGrowthStateMapOverlay",   SeasonsFieldInfo.inj_mapOverlayGenerator_buildGrowthStateMapOverlay)
    SeasonsModUtil.appendedFunction(Player,                     "readUpdateStream",             SeasonsFieldInfo.inj_player_readUpdateStream)
    SeasonsModUtil.appendedFunction(Player,                     "updateTick",                   SeasonsFieldInfo.inj_player_updateTick)
    SeasonsModUtil.appendedFunction(Player,                     "writeUpdateStream",            SeasonsFieldInfo.inj_player_writeUpdateStream)
    SeasonsModUtil.overwrittenConstant(MapOverlayGenerator,     "FRUIT_COLORS_FERTILIZED",      threeStageFertilizationColors)
    SeasonsModUtil.overwrittenFunction(FieldInfoDisplay,        "setCropRotationInfo",          SeasonsFieldInfo.inj_fieldInfoDisplay_setCropRotationInfo)
    SeasonsModUtil.overwrittenFunction(MapOverlayGenerator,     "getDisplayGrowthStates",       SeasonsFieldInfo.inj_mapOverlayGenerator_getDisplayGrowthStates)
    SeasonsModUtil.overwrittenFunction(Player,                  "new",                          SeasonsFieldInfo.inj_player_new)

    return self
end

function SeasonsFieldInfo:delete()
end

function SeasonsFieldInfo:load()
    self:setupRows()
end

function SeasonsFieldInfo:setupRows()
    local fieldInfoDisplay = self.hud.fieldInfoDisplay

    fieldInfoDisplay.seasons_beforePreviousRotationRow = 10
    fieldInfoDisplay.rows[fieldInfoDisplay.seasons_beforePreviousRotationRow] = {
        infoType = FieldInfoDisplay.INFO_TYPE.CUSTOM,
        leftText = "",
        rightText = "",
        leftColor = {unpack(FieldInfoDisplay.COLOR.TEXT_DEFAULT)}
    }

    fieldInfoDisplay.seasons_previousRotationRow = 11
    fieldInfoDisplay.rows[fieldInfoDisplay.seasons_previousRotationRow] = {
        infoType = FieldInfoDisplay.INFO_TYPE.CUSTOM,
        leftText = "",
        rightText = "",
        leftColor = {unpack(FieldInfoDisplay.COLOR.TEXT_DEFAULT)}
    }
end

------------------------------------------------
--- Injections
------------------------------------------------

---Add support for showing our planting state to the map overview
function SeasonsFieldInfo.inj_mapOverlayGenerator_buildGrowthStateMapOverlay(mapOverlayGenerator, growthStateFilter, fruitTypeFilter)
    for _, displayCropType in ipairs(mapOverlayGenerator.displayCropTypes) do
        if fruitTypeFilter[displayCropType.fruitTypeIndex] then
            local foliageId = displayCropType.foliageId
            local desc = mapOverlayGenerator.fruitTypeManager:getFruitTypeByIndex(displayCropType.fruitTypeIndex)
            if desc.maxHarvestingGrowthState >= 0 then

                if growthStateFilter[SeasonsFieldInfo.MAP_OVERLAY.GROWTH_STATE_INDEX_PLANTED] then
                    local colors = mapOverlayGenerator.displayGrowthStates[SeasonsFieldInfo.MAP_OVERLAY.GROWTH_STATE_INDEX_PLANTED].colors[mapOverlayGenerator.isColorBlindMode]
                    setDensityMapVisualizationOverlayGrowthStateColor(mapOverlayGenerator.foliageStateOverlay, foliageId, SeasonsGrowth.PLANTED_STATE, colors[1][1], colors[1][2], colors[1][3])
                end

                if growthStateFilter[SeasonsFieldInfo.MAP_OVERLAY.GROWTH_STATE_INDEX_FAILED_GERMINATION] then
                    local colors = mapOverlayGenerator.displayGrowthStates[SeasonsFieldInfo.MAP_OVERLAY.GROWTH_STATE_INDEX_FAILED_GERMINATION].colors[mapOverlayGenerator.isColorBlindMode]
                    setDensityMapVisualizationOverlayGrowthStateColor(mapOverlayGenerator.foliageStateOverlay, foliageId, SeasonsGrowth.GERMINATION_FAILED_STATE, colors[1][1], colors[1][2], colors[1][3])
                end

            end
        end
    end
end

function SeasonsFieldInfo.inj_mapOverlayGenerator_getDisplayGrowthStates(mapOverlayGenerator, superFunc)
    local list = superFunc(mapOverlayGenerator)

    list[SeasonsFieldInfo.MAP_OVERLAY.GROWTH_STATE_INDEX_PLANTED] = {
        colors = {
            [true] = {{0.9301, 0.8404, 0.3439, 1}},
            [false] = {{0.7681, 0.7514, 0.0529, 1}},
        },
        description = g_i18n:getText("seasons_ui_growthMapPlanted")
    }

    list[SeasonsFieldInfo.MAP_OVERLAY.GROWTH_STATE_INDEX_FAILED_GERMINATION] = {
        colors = {
            [true] = {{0.0086, 0.0976, 0.8776, 1}},
            [false] = {{0.0091, 0.0931, 0.5841, 1}},
        },
        description = g_i18n:getText("seasons_ui_growthMapGerminationFailed")
    }

    return list
end

---Add planted, germination success and failure to the hud.
function SeasonsFieldInfo.inj_fieldInfoDisplay_setFruitType(fieldInfoDisplay, fruitTypeIndex, fruitGrowthState)
    local fieldStateRow = fieldInfoDisplay.rows[FieldInfoDisplay.INFO_TYPE.FIELD_STATE]

    if fruitTypeIndex > 0 then
        local text = fieldStateRow.rightText
        if fruitGrowthState == SeasonsGrowth.PLANTED_STATE then
            text = fieldInfoDisplay.l10n:getText("seasons_ui_growthMapPlanted")
        elseif fruitGrowthState == SeasonsGrowth.GERMINATION_FAILED_STATE then
            text = fieldInfoDisplay.l10n:getText("seasons_ui_growthMapGerminationFailed")
        elseif fruitGrowthState == 1 then
            text = fieldInfoDisplay.l10n:getText("seasons_ui_fruitGerminated")
        end

        if text ~= "" then
            fieldStateRow.leftText = fieldInfoDisplay.l10n:getText(FieldInfoDisplay.L10N_SYMBOL.FIELD_STATE)
            fieldStateRow.rightText = text
        else
            fieldInfoDisplay:clearInfoRow(fieldStateRow)
        end
    end
end

---Add crop rotation lines
function SeasonsFieldInfo.inj_fieldInfoDisplay_onFieldDataUpdateFinished(fieldInfoDisplay, data)
    if data ~= nil then
        local x, y, z = fieldInfoDisplay.player:getPositionData()
        local density = getDensityAtWorldPos(g_currentMission.terrainDetailId, x, y, z)

        if density ~= 0 then
            local n2, n1
            local player = g_currentMission.player

            if g_currentMission:getIsServer() then
                n2, n1 = g_seasons.growth.cropRotation:getInfoAtWorldCoords(x, z)
            else
                n2 = player.seasons_cropRotation_n2
                n1 = player.seasons_cropRotation_n1
            end

            fieldInfoDisplay:setCropRotationInfo(n2, n1)
        else
            fieldInfoDisplay:setCropRotationInfo(nil)
        end
    end
end

---Show crop rotation lines
function SeasonsFieldInfo.inj_fieldInfoDisplay_setCropRotationInfo(fieldInfoDisplay, superFunc, n2, n1)
    local bpRow = fieldInfoDisplay.rows[fieldInfoDisplay.seasons_beforePreviousRotationRow]
    local pRow = fieldInfoDisplay.rows[fieldInfoDisplay.seasons_previousRotationRow]

    if n2 ~= nil then
        bpRow.leftText = fieldInfoDisplay.l10n:getText("seasons_ui_beforePreviousFruit")
        pRow.leftText = fieldInfoDisplay.l10n:getText("seasons_ui_previousFruit")

        bpRow.rightText = g_seasons.growth.cropRotation:getCategoryName(n2)
        pRow.rightText = g_seasons.growth.cropRotation:getCategoryName(n1)
    else
        fieldInfoDisplay:clearInfoRow(bpRow)
        fieldInfoDisplay:clearInfoRow(pRow)
    end

    fieldInfoDisplay.needResize = true
end

---If dirty, send crop rotation field info
function SeasonsFieldInfo.inj_player_writeUpdateStream(player, streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        if streamWriteBool(streamId, bitAND(dirtyMask, player.seasons_fieldInfoDirtyFlag) ~= 0) then
            streamWriteUIntN(streamId, player.seasons_cropRotation_n2, 3)
            streamWriteUIntN(streamId, player.seasons_cropRotation_n1, 3)
        end
    end
end

---Read crop rotation field info
function SeasonsFieldInfo.inj_player_readUpdateStream(player, streamId, timestamp, connection)
    if connection:getIsServer() then
        if streamReadBool(streamId) then
            player.seasons_cropRotation_n2 = streamReadUIntN(streamId, 3)
            player.seasons_cropRotation_n1 = streamReadUIntN(streamId, 3)
            player.seasons_cropRotation_lastUpdate = g_time
        end
    end
end

---Determine if crop rotation field info should be updated, and if so, update it
function SeasonsFieldInfo.inj_player_updateTick(player, dt)
    if player.isControlled and player.isServer and not player.isOwner then

        -- Only update sometimes. Very high precision is not needed
        player.seasons_fieldInfoTimer = player.seasons_fieldInfoTimer + dt
        if player.seasons_fieldInfoTimer > player.seasons_fieldInfoDelay then
            player.seasons_fieldInfoTimer = player.seasons_fieldInfoTimer - player.seasons_fieldInfoDelay

            local x, y, z = getTranslation(player.graphicsRootNode)
            local density = getDensityAtWorldPos(g_currentMission.terrainDetailId, x, y, z)

            -- Be on a field
            if density ~= 0 then
                local n2, n1 = g_seasons.growth.cropRotation:getInfoAtWorldCoords(x, z)

                -- There was a change
                if player.seasons_cropRotation_n2 ~= n2 or player.seasons_cropRotation_n1 ~= n1 then
                    player.seasons_cropRotation_n2 = n2
                    player.seasons_cropRotation_n1 = n1
                    player:raiseDirtyFlags(player.seasons_fieldInfoDirtyFlag)
                end
            end
        end
    end
end

---Get a new dirty flag and build a timer
function SeasonsFieldInfo.inj_player_new(player, superFunc, ...)
    player = superFunc(player, ...)

    player.seasons_fieldInfoDirtyFlag = player:getNextDirtyFlag()
    player.seasons_fieldInfoDelay = 1000
    player.seasons_fieldInfoTimer = 0

    return player
end
