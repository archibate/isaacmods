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

-- no restart: the floor already has its rooms walked and its big room found, and a
-- restart would only make that work be done again. The debug flags and The Mind
-- from the earlier runs are still on, since only a restart clears them.
local STEPS = {
    -- nothing granted: the point of the run is a door Flat File has already been
    -- past, with the trinket now lying on the floor
    "luamod goodtripfixed",
}

local HINT = "walk past the curse door once, Flat File on the ground, then trip in and out"

local mod = RegisterMod("devrepro", 1)

-- which copy of this file the game is actually running. Bump it with any edit worth
-- reading a log for: a run that logs nothing new is otherwise indistinguishable from
-- a run whose reload never happened
local REV = 81
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

local step = 0
local waiting = 0

function mod:onUpdate()
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
        Isaac.RenderText("F1: run repro    F2: dump    rev " .. REV, 25, 25, 0.5, 0.5, 0.5, 1)
    end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
