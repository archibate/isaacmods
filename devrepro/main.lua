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
    "luamod timemachinefixed",
    "restart 0", 10,
    -- no "debug 3" in this one: invincibility is the very thing under test, and the
    -- cheat would pay for every donation
    "giveitem k8", -- The Chariot
    "stage 2", 12,
    "spawn 6.2.0", -- Blood Donation Machine
    "spawn 5.10.1", 3,
    "spawn 5.10.1", 3,
    "spawn 5.10.1",
}

local HINT = "sell blood: F4 flips acceleration off for a vanilla count, F3 more hearts"

local mod = RegisterMod("devrepro", 1)

-- which copy of this file the game is actually running. Bump it with any edit worth
-- reading a log for: a run that logs nothing new is otherwise indistinguishable from
-- a run whose reload never happened
local REV = 8
Isaac.DebugString("[TMBOOT] devrepro rev " .. REV)

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

-- TEMP instrument. Run 2 read the shape of one chest cycle off the log -- about 60 frames held open, then
-- a 30 frame lockout -- and run 3 showed extra Update() calls compress it exactly in
-- proportion. The driver now only watches: the mod under test does the speeding up,
-- and these cycle lines are how a fast cycle proves itself against those numbers
local chests = {}
local chestCount = 0

local function logChests()
    local player = Isaac.GetPlayer(0)
    -- subtype -1: the chest must stay in the list across its own open/close flips
    for _, ent in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,
            PickupVariant.PICKUP_ETERNALCHEST, -1, false, false)) do
        local pickup = ent:ToPickup()
        local touching = player.Position:Distance(ent.Position) < (player.Size + ent.Size)
        local id = GetPtrHash(ent)
        local st = chests[id]
        if st == nil then
            chestCount = chestCount + 1
            st = { n = chestCount, sub = ent.SubType, since = ent.FrameCount,
                   touched = 0, ready = false }
            chests[id] = st
        end
        if touching then st.touched = st.touched + 1 end

        if ent.SubType ~= st.sub then
            local phase = st.sub == 1 and "closed->open" or "open->closed"
            Isaac.DebugString(string.format(
                "[TMCYCLE] c%d %s after %d frames, touching %d of them",
                st.n, phase, ent.FrameCount - st.since, st.touched))
            st.sub = ent.SubType
            st.since = ent.FrameCount
            st.touched = 0
            st.ready = false
        elseif ent.SubType == 1 and not st.ready and pickup.Wait == 0 then
            st.ready = true
            Isaac.DebugString(string.format(
                "[TMCYCLE] c%d openable again %d frames after closing",
                st.n, ent.FrameCount - st.since))
        end

        -- the frame-by-frame field trace stays, at a tenth of the volume: the cycle
        -- lines say what happened, this says which field carried it
        if ent.FrameCount % 10 == 0 then
            Isaac.DebugString(string.format(
                "[TMCHEST] c%d age=%d sub=%d state=%d wait=%d anim=%s aframe=%d keys=%d touch=%s",
                st.n, ent.FrameCount, ent.SubType, pickup.State, pickup.Wait,
                ent:GetSprite():GetAnimation(), ent:GetSprite():GetFrame(),
                player:GetNumKeys(), tostring(touching)))
        end
    end
end

-- the run timer is what a dead chest would quietly steal: the mod pushes it forward
-- by one tick per accelerated frame, so its climb against real frames says whether
-- anything is still being accelerated -- 1:1 means the guard let go
local ticks = 0
local lastFrame, lastTime
-- the same reading the log gets, kept for the screen: standing in the right spot is
-- half of this test, and the player cannot see a log while doing it
local clockLine = "waiting"
local function logClock()
    local game = Game()
    local frame, time = game:GetFrameCount(), game.TimeCounter
    ticks = ticks + 1
    if lastFrame == nil then
        lastFrame, lastTime = frame, time
        return
    end
    -- counted here rather than off the game's own frame number: this instrument is
    -- measuring that number, so it cannot also be the thing that decides when to look
    if ticks % 30 ~= 0 then return end
    local player = Isaac.GetPlayer(0)
    local on = "none"
    for _, ent in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP,
            PickupVariant.PICKUP_ETERNALCHEST, -1, false, false)) do
        if player.Position:Distance(ent.Position) < (player.Size + ent.Size) then
            on = "chest sub=" .. ent.SubType
        end
    end
    clockLine = string.format("on %s, timer %d per 30", on, time - lastTime)
    Isaac.DebugString(string.format(
        "[TMTIME] 30 updates -> %d game frames, %d timer frames (frame=%d timer=%d), on %s, hearts=%d coins=%d keys=%d",
        frame - lastFrame, time - lastTime, frame, time, on,
        player:GetHearts() + player:GetSoulHearts(),
        player:GetNumCoins(), player:GetNumKeys()))
    lastFrame, lastTime = frame, time
end

-- every donation, one line: what it cost, what it paid, and whether it was bought
-- with invincibility. Counting donations per Chariot with acceleration on and then
-- off is the only honest way to say the payout still matches vanilla
local blood = nil
local function logBlood()
    local player = Isaac.GetPlayer(0)
    local now = { red = player:GetHearts(), soul = player:GetSoulHearts(),
                  coins = player:GetNumCoins() }
    if blood == nil then
        blood = now
        return
    end
    if now.red ~= blood.red or now.soul ~= blood.soul or now.coins ~= blood.coins then
        Isaac.DebugString(string.format(
            "[TMBLOOD] red %d->%d soul %d->%d coins %d->%d, cooldown=%d, accel=%s, frame=%d",
            blood.red, now.red, blood.soul, now.soul, blood.coins, now.coins,
            player:GetDamageCooldown(), tostring(tmmc and tmmc.enable and tmmc.enable[2]),
            Game():GetFrameCount()))
        blood = now
    end
end

-- what an open actually paid out: the reclose is supposed to depend on it (pickups
-- reclose, a collectible or nothing ends the cycle), so the drops have to be on the
-- record beside the chest's own state
local function onPickupInit(_, pickup)
    if pickup.Variant == PickupVariant.PICKUP_ETERNALCHEST then return end
    Isaac.DebugString(string.format("[TMDROP] var=%d sub=%d price=%d",
        pickup.Variant, pickup.SubType, pickup.Price))
end

function mod:onUpdate()
    logChests()
    logClock()
    logBlood()
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
    -- blood runs out faster than a measurement does
    if Input.IsButtonTriggered(Keyboard.KEY_F3, 0) then
        Isaac.ExecuteCommand("spawn 5.10.1")
    end

    -- the vanilla control, inside the same run: with the machine's own switch off,
    -- the mod leaves it alone entirely, so a Chariot's worth of donations counted
    -- here is the number the accelerated one has to match
    if Input.IsButtonTriggered(Keyboard.KEY_F4, 0) then
        if tmmc and tmmc.enable then
            tmmc.enable[2] = not tmmc.enable[2]
            Isaac.DebugString("[TMBLOOD] blood machine acceleration -> "
                .. tostring(tmmc.enable[2]))
        end
    end

    -- the chest was added by rewriting the same loop the machines run through, and
    -- the blood machine is the delicate half of it, so one is in reach of this run
    if Input.IsButtonTriggered(Keyboard.KEY_F5, 0) then
        Isaac.ExecuteCommand("spawn 6.2.0")
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
        Isaac.RenderText(clockLine, 25, 40, 0.9, 0.8, 0.4, 1)
    else
        Isaac.RenderText("F1: run repro    F2: dump    rev " .. REV, 25, 25, 0.5, 0.5, 0.5, 1)
    end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, onPickupInit)
