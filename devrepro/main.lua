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

-- The shape the report describes -- a secret room with a curse room next door --
-- is not something a console command can ask for, so this run rerolls the floor
-- until one turns up (see the hunt below) rather than sending anyone wandering.
-- No invincibility here: a heart has to be able to leave, or the thing being
-- measured cannot be seen.
local STEPS = {
    "luamod goodtripfixed",
    "restart 0", 10,
    "debug 10", -- enemies die on a touch: clearing the floor is not the test
    "stage 2", 12,
    "giveitem c333", -- The Mind: whole map at once, secret room included
    "giveitem c40", -- Kamikaze!: blows the wall you stand at, no bomb to place
}

local HINT = "read the line above: bomb into the secret room from the CURSE room only"

local mod = RegisterMod("devrepro", 1)

-- which copy of this file the game is actually running. Bump it with any edit worth
-- reading a log for: a run that logs nothing new is otherwise indistinguishable from
-- a run whose reload never happened
local REV = 18
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
end

if pressed == "dump" then dump() end

-- the hunt. `reseed` redraws the current floor and leaves the run otherwise
-- alone, so a layout can be asked for over and over without restarting and
-- re-granting everything each try.
local TRIES = 60
local hunting, tries, found = false, 0, nil

local function rooms_by_grid()
    local all = Game():GetLevel():GetRooms()
    local by = {}
    for i = 0, all.Size - 1 do
        local d = all:Get(i)
        if d and d.Data then by[d.SafeGridIndex] = d end
    end
    return by
end

-- the four grid steps, minus the one that would wrap off the end of a row into
-- the row above or below and read two unrelated rooms as neighbours
local function neighbours(by, idx)
    local out = {}
    for _, off in ipairs({ -13, 13, -1, 1 }) do
        local wrapped = (off == -1 and idx % 13 == 0) or (off == 1 and idx % 13 == 12)
        local n = not wrapped and by[idx + off] or nil
        if n and n.SafeGridIndex ~= idx then out[n.SafeGridIndex] = n end
    end
    return out
end

local function find_shape()
    local by = rooms_by_grid()
    for idx, d in pairs(by) do
        if d.Data.Type == RoomType.ROOM_SECRET then
            local curse, others = nil, {}
            for nidx, n in pairs(neighbours(by, idx)) do
                if n.Data.Type == RoomType.ROOM_CURSE then
                    curse = nidx
                else
                    others[#others + 1] = string.format("%d(t%d)", nidx, n.Data.Type)
                end
            end
            if curse then
                table.sort(others)
                return { secret = idx, curse = curse,
                    others = #others > 0 and table.concat(others, " ") or "none" }
            end
        end
    end
end

local step = 0
local waiting = 0

function mod:onUpdate()
    if hunting then
        if waiting > 0 then
            waiting = waiting - 1
            return
        end
        found = find_shape()
        if found or tries >= TRIES then
            hunting = false
            Isaac.DebugString(found
                and string.format("[HUNT] secret %d, curse room %d, its other sides %s, %d rerolls",
                    found.secret, found.curse, found.others, tries)
                or string.format("[HUNT] no curse room beside a secret room in %d rerolls", tries))
            return
        end
        tries = tries + 1
        Isaac.ExecuteCommand("reseed")
        waiting = 15
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
        hunting = true
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

    if hunting then
        Isaac.RenderText(string.format("rerolling the floor  %d/%d", tries, TRIES),
            25, 25, 1, 0.9, 0.3, 1)
    elseif found then
        Isaac.RenderText(string.format("secret %d, curse room %d, other sides %s",
            found.secret, found.curse, found.others), 25, 25, 0.6, 0.9, 0.6, 1)
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
