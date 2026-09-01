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

local STEPS = {
    "luamod goodtripfixed",
    "restart 0", 10,
    "debug 3",
    "debug 10",
    "stage 12", 12,
    "giveitem c333",
    "lua gt:get_config().AllowAnyRoom = true",
}

local HINT = "F3 redraws the floor; hover and click Delirium each time"

local mod = RegisterMod("devrepro", 1)

-- which copy of this file the game is actually running. Bump it with any edit worth
-- reading a log for: a run that logs nothing new is otherwise indistinguishable from
-- a run whose reload never happened
local REV = 106
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
    -- every boss room the Void lays out, with the shape the game gave it. The 2x2
    -- one is Delirium's, so if the mod treats it differently from its 1x2 and 2x1
    -- neighbours, a refused trip names it
    for i = 0, Game():GetLevel():GetRooms().Size - 1 do
        local d = Game():GetLevel():GetRooms():Get(i)
        if d.Data.Type == 5 then
            local ok = gt and gt.check_teleble and gt:check_teleble(d.SafeGridIndex)
            Isaac.DebugString(string.format(
                "[VOID] boss room grid %d safe %d shape %d visited %d display %d tripable %s",
                d.GridIndex, d.SafeGridIndex, d.Data.Shape, d.VisitedCount, d.DisplayFlags,
                tostring(ok)))
        end
    end
end

if pressed == "dump" then dump() end

-- F3 redraws this floor once and lists its boss rooms. The Void joins Delirium's
-- 2x2 at a different one of its cells every layout, and that cell is what the map
-- files it under, so pressing F3 a few times walks through the shapes the fix has
-- to hold for.
local hunting = pressed == "hunt"
local hunt_wait, hunt_tries = 0, 0

local function floor_wanted()
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local d = rooms:Get(i)
        if d.Data.Type == 5 then
            Isaac.DebugString(string.format("[VOID] boss room grid %d safe %d shape %d",
                d.GridIndex, d.SafeGridIndex, d.Data.Shape))
        end
    end
    return true
end

local step = 0
local waiting = 0

function mod:onUpdate()
    if hunting then
        if hunt_wait > 0 then
            hunt_wait = hunt_wait - 1
            return
        end
        if hunt_tries > 0 then
            hunting = false
            floor_wanted()
            return
        end
        hunt_tries = hunt_tries + 1
        Isaac.ExecuteCommand("reseed")
        hunt_wait = 10
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
        Isaac.RenderText("floor redrawn, see the log", 25, 25, 0.6, 0.9, 0.6, 1)
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
