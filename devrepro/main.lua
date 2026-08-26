-- Dev Repro -- one key replays a reproduction.
--
-- Press F1 and the driver reloads ITSELF first, so the list that runs is always
-- the one last written to this file -- no retyping, no stale copy. A plain global
-- carries the "run once you come back" intent across that reload, because `luamod`
-- throws away everything else in here.
--
-- STEPS and HINT are the only parts meant to be rewritten. In STEPS a string is a
-- console command and a number is that many frames of waiting; `restart` and
-- `stage` only take effect on a later frame, so each of them needs a wait behind
-- it or whatever follows is swallowed.

local STEPS = {
    "luamod rangevis",
    "restart 0", 10,
    "debug 3",
    "giveitem c579", -- Spirit Sword
    -- plenty of range, because range is what pushes the sword forward and so what
    -- makes the wrong indicator obvious
    "giveitem c731",
    "giveitem c30",
    "giveitem c14",
    "giveitem c339",
    "giveitem c345",
    "giveitem c370",
    "giveitem c29",
    "giveitem c31", 5,
    -- the bug lives with the range fix absent, so the run has to start from there
    "lua RangeFixForBonesAndSword:SetEnabled(false)",
    "stage 2", 12,
    "spawn 33.0.0", 3,
    "spawn 33.0.0", 3,
    "spawn 33.0.0",
}

local HINT = "fix OFF: does the band cover the swing now? F4 to check it on too"

-- range ups handed out one at a time by F5; Magic Mushroom is deliberately absent
-- because it also grows the player sprite, which muddies a reach measurement
local RANGE_ITEMS = { 731, 30, 14, 339, 345, 370, 29, 31 }
local rangeItemStep = 0

local mod = RegisterMod("devrepro", 1)

-- carries which key was pressed across the reload that brought this copy in; a
-- plain game start finds it absent and sits still rather than replaying anything
local pressed = DevReproPending
DevReproPending = nil

local running = pressed == "run"

-- F2 writes something out of the game rather than playing anything. Rewrite this
-- for whatever needs enumerating; it beats reading a wiki, which is where
-- hallucinated ids come from.
local KIND = { [ItemType.ITEM_PASSIVE] = "P", [ItemType.ITEM_ACTIVE] = "A",
    [ItemType.ITEM_FAMILIAR] = "F" }

local function dump()
    local config = Isaac.GetItemConfig()
    for id = 1, 5000 do
        local item = config:GetCollectible(id)
        if item ~= nil then
            Isaac.DebugString("[ITEM] " .. id
                .. "|" .. (KIND[item.Type] or tostring(item.Type))
                .. "|" .. tostring(item.Name))
        end
    end
    Isaac.DebugString("[ITEM] end of table")
end

if pressed == "dump" then dump() end

local step = 0
local waiting = 0

-- TEMP instrument: how far a swung weapon really reaches, to compare against what
-- RangeVis draws. Everything here is tracked at its peak across each knife's life --
-- scale and target offset hold still through a swing, so keying the log on those
-- sampled the travelling values exactly once and missed the entire sweep.
local knifeSeen = {}

-- whether the range fix is loaded, and at what factor, belongs in the log rather
-- than in a question afterwards; it publishes itself as a global
local function logRangeFix()
    local fix = RangeFixForBonesAndSword
    if not fix then
        Isaac.DebugString("[RVFIX] range fix mod not loaded")
        return
    end
    Isaac.DebugString(string.format("[RVFIX] enabled=%s factor=%s boc=%s",
        tostring(fix:IsEnabled()), tostring(fix:GetRangeFactor()),
        tostring(fix:IsEnabledBOC())))
end

-- Tainted Samson only swings while berserk, and earning that honestly in a test room
-- is slow and fiddly; his meter is a plain 0-100000 field, so pinning it keeps the
-- club out for as long as the run needs
local function keepBerserk()
    local player = Isaac.GetPlayer(0)
    if player:GetPlayerType() == PlayerType.PLAYER_SAMSON_B then
        player.SamsonBerserkCharge = 100000
    end
end

local function logKnives()
    local player = Isaac.GetPlayer(0)
    for _, ent in ipairs(Isaac.FindByType(EntityType.ENTITY_KNIFE, -1, -1, false, false)) do
        local knife = ent:ToKnife()
        local id = GetPtrHash(ent)
        local tgt, scale = ent.TargetPosition.X, knife.Scale
        local seen = knifeSeen[id]
        if seen == nil then
            seen = { reach = -1, dist = -1 }
            knifeSeen[id] = seen
            Isaac.DebugString(string.format(
                "[RVKNIFE] born range=%.0f var=%d sub=%d age=%d scale=%.2f sprite=%.2f tgt=%.1f",
                player.TearRange, ent.Variant, ent.SubType, ent.FrameCount, scale,
                ent.SpriteScale.X, tgt))
        end
        -- how far the weapon reaches from the body is the thing a reach indicator
        -- needs, and the engine answers that directly; position is logged beside it
        -- because the two disagree once a mod moves the weapon around
        local reach = knife:GetKnifeDistance()
        local dist = (ent.Position - player.Position):Length()
        if reach > seen.reach + 2 or dist > seen.dist + 2 then
            seen.reach = math.max(seen.reach, reach)
            seen.dist = math.max(seen.dist, dist)
            Isaac.DebugString(string.format(
                "[RVKNIFE] far range=%.0f var=%d sub=%d reach=%.1f dist=%.1f scale=%.2f tgt=%.1f size=%.1f",
                player.TearRange, ent.Variant, ent.SubType, reach, dist, scale, tgt,
                ent.Size))
        end
    end
end

if running then logRangeFix() end

function mod:onUpdate()
    keepBerserk()
    logKnives()
    if not running then return end
    if waiting > 0 then
        waiting = waiting - 1
        return
    end

    step = step + 1
    local entry = STEPS[step]
    if entry == nil then
        running = false
        return
    end
    if type(entry) == "number" then
        waiting = entry
    else
        Isaac.ExecuteCommand(entry)
    end
end

function mod:onRender()
    -- a fresh target on demand, for tests that burn through dummies faster than one
    -- run can supply them; no reload, so it stays usable mid-run
    if Input.IsButtonTriggered(Keyboard.KEY_F3, 0) then
        Isaac.ExecuteCommand("spawn 33.0.0")
    end

    -- fitting reach against the range stat needs several ranges, and handing them out
    -- one key press at a time beats one run per point
    if Input.IsButtonTriggered(Keyboard.KEY_F5, 0) then
        local item = RANGE_ITEMS[rangeItemStep + 1]
        if item then
            rangeItemStep = rangeItemStep + 1
            Isaac.ExecuteCommand("giveitem c" .. item)
        end
    end

    -- flipping the fix mid-run is the only way to see both shapes of the same swing
    -- without two separate presses; the next swing picks the new setting up
    if Input.IsButtonTriggered(Keyboard.KEY_F4, 0) then
        local fix = RangeFixForBonesAndSword
        if fix then
            fix:SetEnabled(not fix:IsEnabled())
            Isaac.DebugString("[RVFIX] toggled to " .. tostring(fix:IsEnabled()))
        end
    end

    for key, intent in pairs({ [Keyboard.KEY_F1] = "run", [Keyboard.KEY_F2] = "dump" }) do
        if Input.IsButtonTriggered(key, 0) then
            DevReproPending = intent
            Isaac.ExecuteCommand("luamod devrepro")
            return
        end
    end

    if running then
        Isaac.RenderText(string.format("running  %d/%d", step, #STEPS), 25, 25, 1, 0.9, 0.3, 1)
    elseif pressed == "dump" then
        Isaac.RenderText("dumped to log", 25, 25, 0.6, 0.9, 0.6, 1)
    elseif step > 0 then
        Isaac.RenderText(HINT, 25, 25, 0.6, 0.9, 0.6, 1)
    else
        Isaac.RenderText("F1: run repro    F2: dump", 25, 25, 0.5, 0.5, 0.5, 1)
    end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
