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
--
-- Instruments belong to the task at hand: add whatever the current question needs,
-- and take it out again once that question is answered, so the next run's log and
-- screen carry only what is being asked now.

-- The Mind draws the whole floor, a bomb opens the secret room, and the trinket is
-- the one the toll is meant to answer to. F3 reseeds until a curse room shares a
-- wall with a secret room, which is the shape the hop under test needs
local STEPS = {
    "luamod goodtripfixed",
    "restart 0", 10,
    "debug 3",
    "debug 10",
    "stage 7", 12,
    "giveitem c333",
}

local HINT = "one throw only: does the map come back on the next frame or stay gone?"

local mod = RegisterMod("devrepro", 1)

-- which copy of this file the game is actually running. Bump it with any edit worth
-- reading a log for: a run that logs nothing new is otherwise indistinguishable from
-- a run whose reload never happened
local REV = 94
Isaac.DebugString("[DEVREPRO] rev " .. REV)

-- carries which key was pressed across the reload that brought this copy in; a
-- plain game start finds it absent and sits still rather than replaying anything
local pressed = DevReproPending
DevReproPending = nil

local running = pressed == "run"

-- F2 writes something out of the game rather than playing anything. Rewrite this
-- for whatever needs enumerating; it beats reading a wiki, which is where
-- hallucinated ids come from.
local function dump()
    Isaac.DebugString("[SEED] " .. Game():GetSeeds():GetStartSeedString()
        .. " stage " .. Game():GetLevel():GetStage()
        .. "." .. Game():GetLevel():GetStageType())
    -- everything a door carries, so the one field that says "these spikes are gone
    -- for good" can be picked out by comparing a door Flat File has seen against
    -- one it has not
    local room = Game():GetRoom()
    Isaac.DebugString(string.format("[DOOR] room %d type %d, flat file held %s",
        Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex,
        Game():GetLevel():GetCurrentRoomDesc().Data.Type,
        tostring(Isaac.GetPlayer(0):HasTrinket(151))))
    for slot = 0, 7 do
        local d = room:GetDoor(slot)
        if d then
            local s = d:GetSprite()
            Isaac.DebugString(string.format(
                "[DOOR] slot %d to room type %d, variant %d state %d vardata %d, anim %s overlay %s frame %d, open %s busted %s locked %s",
                slot, d.TargetRoomType, d:GetVariant(), d.State, d.VarData,
                s:GetAnimation(), s:GetOverlayAnimation(), s:GetFrame(),
                tostring(d:IsOpen()), tostring(d:IsBusted()), tostring(d:IsLocked())))
        end
    end
end

if pressed == "dump" then dump() end

-- F3 hunts a floor shaped for the question at hand. No console command asks for a
-- layout, but reseed redraws the floor and leaves the run otherwise alone, so the
-- driver loops it and reads the room list each try. Wanted here: an L-shaped room,
-- where a trip to the secret room has to pass the curse room's own door.
local hunting = pressed == "hunt"
local hunt_wait, hunt_tries = 0, 0

local function floor_wanted()
    local rooms = Game():GetLevel():GetRooms()
    local curse, secret = {}, {}
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        if d.Data.Type == 10 then curse[#curse + 1] = d.SafeGridIndex end
        if d.Data.Type == 7 then secret[#secret + 1] = d.SafeGridIndex end
    end
    for _, c in ipairs(curse) do
        for _, s in ipairs(secret) do
            local samerow = (c - c % 13) == (s - s % 13)
            if (samerow and math.abs(c - s) == 1) or math.abs(c - s) == 13 then
                Isaac.DebugString(string.format("[HUNT] curse %d beside secret %d", c, s))
                return true
            end
        end
    end
    return false
end

local step = 0
local waiting = 0

function mod:onUpdate()
    if hunting then
        if hunt_wait > 0 then
            hunt_wait = hunt_wait - 1
            return
        end
        if floor_wanted() then
            hunting = false
            return
        end
        hunt_tries = hunt_tries + 1
        if hunt_tries > 300 then
            hunting = false
            Isaac.DebugString("[HUNT] gave up after " .. hunt_tries .. " reseeds")
            return
        end
        Isaac.ExecuteCommand("reseed")
        hunt_wait = 5
        return
    end
    if not running then return end
    if waiting > 0 then
        waiting = waiting - 1
        return
    end

    step = step + 1
    local entry = STEPS[step]
    if entry == nil then
        running = false
        dump() -- the seed, so a run that drifted off the intended one says so
        return
    end
    if type(entry) == "number" then
        waiting = entry
    else
        Isaac.ExecuteCommand(entry)
    end
end

function mod:onRender()
    for key, intent in pairs({ [Keyboard.KEY_F1] = "run", [Keyboard.KEY_F2] = "dump",
                               [Keyboard.KEY_F3] = "hunt" }) do
        if Input.IsButtonTriggered(key, 0) then
            DevReproPending = intent
            Isaac.ExecuteCommand("luamod devrepro")
            return
        end
    end

    if hunting then
        Isaac.RenderText(string.format("hunting a floor  %d reseeds", hunt_tries), 25, 25, 1, 0.9, 0.3, 1)
    elseif pressed == "hunt" then
        Isaac.RenderText("floor found, see the log", 25, 25, 0.6, 0.9, 0.6, 1)
    elseif running then
        Isaac.RenderText(string.format("running  %d/%d", step, #STEPS), 25, 25, 1, 0.9, 0.3, 1)
    elseif pressed == "dump" then
        Isaac.RenderText("dumped to log", 25, 25, 0.6, 0.9, 0.6, 1)
    elseif step > 0 then
        Isaac.RenderText(HINT, 25, 25, 0.6, 0.9, 0.6, 1)
    else
        Isaac.RenderText("F1: run repro    F2: dump    rev " .. REV, 25, 25, 0.5, 0.5, 0.5, 1)
    end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
