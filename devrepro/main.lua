-- Dev Repro -- one key replays a reproduction.
--
-- Press F1 and the driver reloads ITSELF first, so the list that runs is always
-- the one last written to this file -- no retyping, no stale copy. A plain global
-- carries the "run once you come back" intent across that reload, because `luamod`
-- throws away everything else in here.
--
-- STEPS and HINT are the only parts meant to be rewritten. In STEPS a string is a
-- console command, a number is that many frames of waiting, and a function is
-- called once an update until it stops returning true; `restart`, `seed` and
-- `stage` only take effect on a later frame, so each of them needs a wait behind
-- it or whatever follows is swallowed.
--
-- Instruments belong to the task at hand: add whatever the current question needs,
-- and take it out again once that question is answered, so the next run's log and
-- screen carry only what is being asked now.

local mod = RegisterMod("devrepro", 1)

-- which copy of this file the game is actually running. Bump it with any edit worth
-- reading a log for: a run that logs nothing new is otherwise indistinguishable from
-- a run whose reload never happened
local REV = 10142
Isaac.DebugString(string.format("[DEVREPRO] rev %d screen %dx%d", REV, Isaac.GetScreenWidth(), Isaac.GetScreenHeight()))

-- when no key can reach the game (the vanilla exe on the agent's desktop never
-- fires a mod's render callback, where F1 is read, and its `lua` console command
-- is a no-op without --luadebug), set this and type `luamod devrepro` in the
-- console: the run starts on load
local AUTORUN = false

local tick = 0 -- the driver's own update count; the game's resets on restart
local rframe = 0 -- and its render count, 60 a second: how long a thing was on screen

local function log(fmt, ...)
    Isaac.DebugString(string.format("[DR%d t%d r%d] " .. fmt, REV, tick, rframe, ...))
end

-- F2 writes something out of the game rather than playing anything. Rewrite this
-- for whatever needs enumerating; it beats reading a wiki, which is where
-- hallucinated ids come from.
local function dump()
    log("floor: seed %s stage %d", Game():GetSeeds():GetStartSeedString(), Game():GetLevel():GetStage())
    for i, cb in ipairs(Isaac.GetCallbacks(ModCallbacks.MC_POST_HUD_RENDER)) do
        log("HUDCB %d mod=%s prio=%s fn=%s", i, tostring(cb.Mod and cb.Mod.Name), tostring(cb.Priority), tostring(cb.Function))
    end
    log("HUDCB icons=%s cursor=%s", tostring(gt.widget.gon_draw_map_icons), tostring(gt.widget.gon_draw_map_cursor))
end

local banner = "" -- what the run is doing right now, drawn on screen for the watcher

-- Oct 11 request (mata): special icons on the game's own map under REPENTOGON.
-- Downpour II: visit every room whose spawn list holds a white fire or a mirror,
-- come back to the start room, then the map is held open from outside with TAB.
local pending
local original
local targets = {}
local start_room
local function restore()
    if original then
        for key, value in pairs(original) do gt:get_config()[key] = value end
        original = nil
    end
end
mod:AddPriorityCallback(ModCallbacks.MC_PRE_GAME_EXIT, CallbackPriority.EARLY - 1, restore)

mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if pending then
        local target = pending
        pending = nil
        gt.control.check_and_tele_room(target)
    end
end)

local function setup()
    local cfg = gt:get_config()
    original = {}
    for _, key in ipairs({"FastTransition", "TeleportAnimation", "ArriveAtDoor", "AllowAnyRoom", "FairTripPath"}) do
        original[key] = cfg[key]
    end
    cfg.FastTransition, cfg.TeleportAnimation, cfg.ArriveAtDoor = true, false, false
    cfg.AllowAnyRoom, cfg.FairTripPath = true, false
    local level = Game():GetLevel()
    start_room = level:GetCurrentRoomDesc().SafeGridIndex
    log("ENV rgon=%s stage=%d type=%d effect=%d seed=%s gmc=%s icons=%s", tostring(REPENTOGON),
        level:GetStage(), level:GetStageType(), gt.floor.stageeffect,
        Game():GetSeeds():GetStartSeedString(), tostring(cfg.CursorOnGameMap), tostring(cfg.SpecialIconsOnGameMap))
    targets = {}
    local rooms = level:GetRooms()
    for i = 0, rooms.Size - 1 do
        local rd = rooms:Get(i)
        if rd.Data.Type == RoomType.ROOM_DEFAULT and rd.SafeGridIndex >= 0 then
            local spawns = rd.Data.Spawns
            for j = 0, spawns.Size - 1 do
                local e = spawns:Get(j):PickEntry(0)
                if (e.Type == 33 and e.Variant == 4) or (e.Type == 970 and e.Variant == 2) then
                    log("TARGET %d name=%s shape=%d ent=%d.%d", rd.SafeGridIndex, rd.Data.Name, rd.Data.Shape, e.Type, e.Variant)
                    table.insert(targets, rd.SafeGridIndex)
                    break
                end
            end
        end
    end
    table.insert(targets, start_room)
end

local function tour()
    local index, age = 1, 0
    return function()
        if index > #targets then return false end
        banner = string.format("hop %d/%d target %d", index, #targets, targets[index])
        if age == 0 then pending = targets[index] end
        age = age + 1
        if age >= 40 then
            log("AT %d visited=%d", Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex,
                Game():GetLevel():GetCurrentRoomDesc().VisitedCount)
            age, index = 0, index + 1
        end
        return true
    end
end

-- sits still long enough for the map to be held open and photographed from outside
local function hold(name)
    local age = 0
    return function()
        if age == 0 then
            log("HOLD %s mirror=%s room=%d", name, tostring(Game():GetRoom():IsMirrorWorld()),
                Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex)
        end
        banner = "hold " .. name
        age = age + 1
        if age >= 450 then
            log("HOLD %s end", name)
            return false
        end
        return true
    end
end

local STEPS = {
    "luamod goodtripfixed", 10,
    "restart 0", 10,
    "debug 3", "debug 10", "stage 2c", 10,
    setup,
    tour(),
    hold("non"),
    function() gt:get_config().SpecialIconsOnGameMap = false return false end,
    hold("noff"),
    function() gt:get_config().SpecialIconsOnGameMap = true return false end,
    function() Game():ChangeRoom(start_room, 1) return false end, 30,
    function() Game():ChangeRoom(start_room - 1, 1) return false end, 30,
    function() Game():ChangeRoom(start_room - 26, 1) return false end, 30,
    function() Game():ChangeRoom(start_room, 1) return false end, 30,
    hold("mon"),
    function() gt:get_config().SpecialIconsOnGameMap = false return false end,
    hold("moff"),
    function() gt:get_config().SpecialIconsOnGameMap = true return false end,
    restore,
}

local HINT = "Downpour tour done; hold TAB to see the icons."

-- carries which key was pressed across the reload that brought this copy in; a
-- plain game start finds it absent and sits still rather than replaying anything
local pressed = DevReproPending
DevReproPending = nil
if AUTORUN then pressed = "run" end

local running = pressed == "run"

if pressed == "dump" then dump() end

local step = 0
local waiting = 0

function mod:onUpdate()
    tick = tick + 1
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
    elseif type(entry) == "function" then
        if entry() then step = step - 1 end -- busy: same entry again next update
    else
        log("exec %s t %d", entry, Isaac.GetTime())
        Isaac.ExecuteCommand(entry)
    end
end

function mod:onRender()
    rframe = rframe + 1
    if rframe == 1 then log("render alive, screen %dx%d", Isaac.GetScreenWidth(), Isaac.GetScreenHeight()) end
    for key, intent in pairs({ [Keyboard.KEY_F1] = "run", [Keyboard.KEY_F2] = "dump" }) do
        if Input.IsButtonTriggered(key, 0) then
            DevReproPending = intent
            Isaac.ExecuteCommand("luamod devrepro")
            return
        end
    end

    -- along the bottom edge: the top-left corner is the HUD under test
    local y = Isaac.GetScreenHeight() - 20
    if running then
        Isaac.RenderText(string.format("running  %d/%d  %s", step, #STEPS, banner), 25, y, 1, 0.9, 0.3, 1)
    elseif pressed == "dump" then
        Isaac.RenderText("dumped to log", 25, y, 0.6, 0.9, 0.6, 1)
    elseif step > 0 then
        Isaac.RenderText(HINT, 25, y, 0.6, 0.9, 0.6, 1)
    else
        Isaac.RenderText("F1: run repro    F2: dump    rev " .. REV, 25, y, 0.5, 0.5, 0.5, 1)
    end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
