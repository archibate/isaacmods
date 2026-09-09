local mod = RegisterMod("Predicable Metronome and Dead Sea Scrolls", 1)

local deadSeaScrollsList = {34,35,37,38,39,41,42,44,45,56,49,58,77,65,66,78,83,84,85,86,93,97,107,102,47,123,136,146,158,160,171,192}

local function popDeadSeaScrollsNext(rng)
    local i = rng:RandomInt(#deadSeaScrollsList) + 1
    return deadSeaScrollsList[i]
end

local metronomeBannedList = {
    [CollectibleType.COLLECTIBLE_METRONOME] = 1,
    [CollectibleType.COLLECTIBLE_PLAN_C] = 1,
    [CollectibleType.COLLECTIBLE_GLOWING_HOUR_GLASS] = 1,
    [CollectibleType.COLLECTIBLE_BREATH_OF_LIFE] = 1,
    [CollectibleType.COLLECTIBLE_CLICKER] = 1,
    [CollectibleType.COLLECTIBLE_R_KEY] = 1,
    [CollectibleType.COLLECTIBLE_DEATH_CERTIFICATE] = 0.85,
    [CollectibleType.COLLECTIBLE_GENESIS] = 0.75,
}

local cachedMaxCollectibleID = nil

local function getMaxCollectibleID()
    if cachedMaxCollectibleID then return cachedMaxCollectibleID end
    local itemConfig = Isaac.GetItemConfig()
    local id = CollectibleType.NUM_COLLECTIBLES - 1
    local step = 16
    while step > 0 do
        if itemConfig:GetCollectible(id+step) ~= nil then
            id = id + step
        else
            step = step // 2
        end
    end
    cachedMaxCollectibleID = id
    return id
end

---@param rng RNG
---@return CollectibleType
local function popMetronomeNext(rng)
    local rerollRng = RNG()
    rerollRng:SetSeed(rng:Next(), 15)
    local maxId = getMaxCollectibleID()
    for _ = 1, 15 do
        local c = rng:RandomInt(maxId) + 1
        if Isaac.GetItemConfig():GetCollectible(c) ~= nil then
            local banned = metronomeBannedList[c]
            if not banned or (banned < 1 and rerollRng:RandomFloat() < 1 - banned) then
                return c
            end
        end
    end
    return 0
end

local cacheSprites = {}

local activePredictor = {
    [CollectibleType.COLLECTIBLE_METRONOME] = popMetronomeNext,
    [CollectibleType.COLLECTIBLE_DEAD_SEA_SCROLLS] = popDeadSeaScrollsNext,
}

local function renderPredictUI(player, pos)
    local active = player:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
    local predFunc = activePredictor[active]
    if predFunc then
        if not cacheSprites[player.Index] then
            cacheSprites[player.Index] = {
                sprite = Sprite(),
                lastItem = 0,
            }
        end
        local cache = cacheSprites[player.Index]
        local rng = RNG()
        rng:SetSeed(player:GetCollectibleRNG(active):GetSeed(), 35)
        local c = predFunc(rng)
        if not cache.sprite:IsLoaded() then
            cache.sprite:Load("gfx/sprite_dummy_item.anm2", true)
        end
        if cache.lastItem ~= c then
            local info = Isaac.GetItemConfig():GetCollectible(c)
            if info then
                cache.sprite:ReplaceSpritesheet(0, info.GfxFileName)
                cache.sprite:LoadGraphics()
                cache.lastItem = c
            else
                cache.lastItem = 0
            end
        end
        if cache.lastItem ~= 0 then
            cache.sprite:SetFrame("default", 0)
            cache.sprite.Scale = Vector(0.5, 0.5)
            cache.sprite.Color = Color(1, 1, 1, 0.5)
            cache.sprite:Render(pos)
        end
    end
end

-- Rep+ paints the HUD over anything a mod draws, so the icon cannot sit on the
-- slot itself any more: the item, its charge bar and, for Bethany's or Judas's
-- book, the book backdrop all cover it there. It goes just under the charge bar
-- and the hearts, right of the counters: the one place near the slot that stays
-- clear of the second slot, two rows of hearts and the counters at every HUD
-- offset. Measured with the offset option at 1; the HUD slides (20, 12) per unit.
local ICON_AT_FULL_OFFSET = Vector(60, 48)
-- Esau's HUD hangs off the bottom-right corner, hearts left of the charge bar and
-- extra heart rows growing downward, so his icon sits just above the bar
local ESAU_ICON_FROM_CORNER = Vector(64, 62)

local function hudShift()
    return Vector(20, 12) * (Options.HUDOffset - 1)
end

mod:AddPriorityCallback(ModCallbacks.MC_POST_RENDER, CallbackPriority.EARLY, function (_)
    local player = Isaac.GetPlayer(0)
    renderPredictUI(player, ICON_AT_FULL_OFFSET + hudShift())
    if player:GetPlayerType() == PlayerType.PLAYER_JACOB then
        local corner = Vector(Isaac.GetScreenWidth(), Isaac.GetScreenHeight())
        renderPredictUI(player:GetOtherTwin(), corner - ESAU_ICON_FROM_CORNER - hudShift())
    end
end)

-- local lut = {}
-- for _ = 1, #deadSeaScrollsList do
--     lut[_] = 0
-- end
-- mod:AddCallback(ModCallbacks.MC_USE_ITEM, function (_, item)
--     if item ~= CollectibleType.COLLECTIBLE_DEAD_SEA_SCROLLS then
--         local player = Isaac.GetPlayer(0)
--         local rng = RNG()
--         lut[last_c] = item
--         local res = '{'
--         for _, v in ipairs(lut) do
--             res = res .. v .. ','
--         end
--         res = res .. '}'
--         print(res)
--         mod:SaveData(res)
--     end
-- end)
