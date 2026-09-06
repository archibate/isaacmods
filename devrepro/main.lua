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
local REV = 134
Isaac.DebugString("[DEVREPRO] rev " .. REV)

local tick = 0 -- the driver's own update count; the game's resets on restart
local rframe = 0 -- and its render count, 60 a second: how long a thing was on screen

local function log(fmt, ...)
    Isaac.DebugString(string.format("[DR%d t%d r%d] " .. fmt, REV, tick, rframe, ...))
end

local function vec(v)
    return string.format("(%.1f,%.1f)", v.X, v.Y)
end

-- the question, Moe&OF's: with ArriveAtDoor on, the first trip into a room lands
-- at the wrong wall, a trip into the same room after a rewind lands at the right
-- one, and a quit-and-continue makes it wrong again. The suspect is the door
-- graph: a room's own door slots are only learned by standing in it, the far end
-- of a swept door is a bare mark, and the continue path wipes the graph. So the
-- run walks two plain rooms, comes back, and takes the far trip three times:
-- fresh, after the room was entered once, and after the continue path. Each
-- trip's slot is logged before it goes, and the arrival door after

local trip_asked = false -- a trip was asked for and has not landed yet

local function here()
    return Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex
end

-- every room of the floor, once each, by descriptor
local function rooms()
    local out = {}
    local all = Game():GetLevel():GetRooms()
    for i = 0, all.Size - 1 do
        local d = all:Get(i)
        if d and d.Data then out[#out + 1] = d end
    end
    return out
end

local function arm_instruments()
    log("instruments armed, REPENTOGON=%s", tostring(REPENTOGON ~= nil))
    local real_trip = gt.trip.teleport_to_grid_index
    gt.trip.teleport_to_grid_index = function(gid)
        local from = here()
        local trd = gt.floor.grid_room[gid]
        local there = trd and trd.SafeGridIndex or gid
        local cell, walked, slot = gt.rules.landing_route(from, there)
        local link = gt.floor.door_graph()
        local known = {}
        for k, v in pairs(link[there] or {}) do known[#known + 1] = k .. "=" .. tostring(v) end
        log("TRIP asked: from %d to %d (safe %d) shape %s teleble=%s ready=%s route cell=%s walked=%s slot=%s link[to]={%s}",
            from, gid, there, trd and tostring(trd.Data.Shape) or "?",
            tostring(gt.rules.check_teleble(gid)), tostring(gt.trip.ready()),
            tostring(cell), tostring(walked), tostring(slot), table.concat(known, " "))
        trip_asked = true
        return real_trip(gid)
    end
    local real_land = gt.trip.land_at_door
    gt.trip.land_at_door = function()
        local p = Isaac.GetPlayer(0)
        local pre = p.Position
        real_land()
        log("LAND shift: pre=%s post=%s moved=%.1f", vec(pre), vec(p.Position), (p.Position - pre):Length())
    end
end

local function describe_room(tag)
    local lvl = Game():GetLevel()
    local d = lvl:GetCurrentRoomDesc()
    local p = Isaac.GetPlayer(0)
    local doors = {}
    for i = 0, 7 do
        local door = Game():GetRoom():GetDoor(i)
        if door then doors[#doors + 1] = i .. ">" .. door.TargetRoomIndex end
    end
    log("%s: safe %d type %d shape %d visited %d clear %s enter %d doors=%s player=%s screen=%s",
        tag, d.SafeGridIndex, d.Data.Type, d.Data.Shape, d.VisitedCount, tostring(d.Clear),
        lvl.EnterDoor, table.concat(doors, ","), vec(p.Position), vec(Isaac.WorldToScreen(p.Position)))
end

-- the trip as the input loop makes it: refused rooms are refused here too
local function trip_to(label, pick)
    return function()
        local gid = pick()
        if not gid then
            log("TRIP %s: no room picked", label)
            return
        end
        local d = gt.floor.grid_room[gid]
        log("TRIP %s: safe %d type %d shape %d visited %d clear %s", label, gid, d.Data.Type,
            d.Data.Shape, d.VisitedCount, tostring(d.Clear))
        if gt.rules.check_teleble(gid) and gt.trip.ready() then
            gt.trip.teleport_to_grid_index(gid)
        else
            log("TRIP %s: refused", label)
        end
    end
end

-- the plan found on this floor, by hunt.lua: a walk through plain rooms to P, a
-- plain 1x1 target T next to P, and a door on T's wall facing the start that the
-- walk leaves unvisited
local plan = nil -- { walk, target, entry, pick, tie, on_face, start }
local SIDE = { [0] = "LEFT", "UP", "RIGHT", "DOWN" }
local hunt = include("hunt")

local function find_plan()
    local lvl = Game():GetLevel()
    local cells = {} -- cell -> { safe, list, type, shape }, as the mod lays the grid out
    for _, d in ipairs(rooms()) do
        for jx = 0, 1 do
            for jy = 0, 1 do
                local c = d.GridIndex + jx + jy * 13
                if lvl:GetRoomByIdx(c, -1).ListIndex == d.ListIndex then
                    cells[c] = { safe = d.SafeGridIndex, list = d.ListIndex, type = d.Data.Type, shape = d.Data.Shape }
                end
            end
        end
    end
    return hunt(cells, lvl:GetStartingRoomIndex())
end

-- F2 writes something out of the game rather than playing anything. Rewrite this
-- for whatever needs enumerating; it beats reading a wiki, which is where
-- hallucinated ids come from.
local function dump()
    log("floor: seed %s stage %d, %d rooms", Game():GetSeeds():GetStartSeedString(),
        Game():GetLevel():GetStage(), #rooms())
    for _, d in ipairs(rooms()) do
        log("  room safe %d grid %d type %d shape %d visited %d clear %s",
            d.SafeGridIndex, d.GridIndex, d.Data.Type, d.Data.Shape, d.VisitedCount, tostring(d.Clear))
    end
end

-- reseeds until a plan turns up, then hands the mod the new floor. Every floor
-- passed over is dumped, so the search can be tuned offline against real floors
local hunt_wait, hunt_tries = 0, 0
local function hunt_plan()
    if hunt_wait > 0 then
        hunt_wait = hunt_wait - 1
        return true
    end
    plan = find_plan()
    if plan then
        log("PLAN on seed %s after %d reseeds: start %d, walk %s, target %d entered by %s, game should pick %s%s%s",
            Game():GetSeeds():GetStartSeedString(), hunt_tries, plan.start, table.concat(plan.walk, ">"),
            plan.target, SIDE[plan.entry], SIDE[plan.pick], plan.on_face and " (facing)" or " (lowest slot)",
            plan.tie and " TIE" or "")
        gt.control.new_level()
        gt.control.new_room()
        return false
    end
    dump()
    if hunt_tries >= 100 then
        log("PLAN: none in %d reseeds, giving up", hunt_tries)
        return false
    end
    hunt_tries = hunt_tries + 1
    Isaac.ExecuteCommand("reseed")
    hunt_wait = 10
    return true
end

-- step into every room of the walk in turn, each held until it is clear, then back
-- to the start. One ChangeRoom per entry so the mod sweeps every room's doors
local walk_at, walk_hold = 0, 0
local function walk_path()
    if not plan then return end
    if walk_at > 0 and walk_at <= #plan.walk then
        if not Game():GetRoom():IsClear() and walk_hold < 300 then
            walk_hold = walk_hold + 1
            return true
        end
        log("WALK room %d clear after %d ticks", here(), walk_hold)
    end
    walk_at = walk_at + 1
    walk_hold = 0
    if walk_at <= #plan.walk then
        Game():ChangeRoom(plan.walk[walk_at], -1)
        return true
    end
    Game():ChangeRoom(plan.start, -1)
end

local function back_to_start()
    if plan then Game():ChangeRoom(plan.start, -1) end
end

local banner = "" -- what the run is doing right now, drawn on screen for the watcher
local saved_arrive = nil

local STEPS = {
    "luamod goodtripfixed",
    "restart 0", 10,
    "stage 5", 15, -- deeper floors hold more rooms, so more dead-end special rooms to face
    "debug 3",
    "debug 10", -- the walked rooms hold enemies; the route needs them cleared
    function()
        saved_arrive = gt:get_config().ArriveAtDoor
        gt:get_config().ArriveAtDoor = true
        gt:get_config().AllowAnyRoom = false -- the reporter's value; rev 128 had left it on in the save
        log("CONFIG ArriveAtDoor was %s, now on; AllowNeighborRoom=%s AllowAnyRoom=%s FairTripPath=%s FairTripTime=%s",
            tostring(saved_arrive), tostring(gt:get_config().AllowNeighborRoom), tostring(gt:get_config().AllowAnyRoom),
            tostring(gt:get_config().FairTripPath), tostring(gt:get_config().FairTripTime))
    end,
    arm_instruments,
    hunt_plan,
    walk_path, 30,
    function()
        describe_room("START")
        banner = "trip 1: fresh"
    end,
    trip_to("1 fresh: the far room, never entered", function() return plan and plan.target end), 90,
    back_to_start, 45,
    function() banner = "trip 2: after entering once" end,
    trip_to("2 entered once", function() return plan and plan.target end), 90,
    back_to_start, 45,
    function()
        banner = "trip 3: after the continue path"
        gt.control.new_room()
        gt.control.new_level() -- the continue path, in the order MC_POST_GAME_STARTED runs them
    end, 5,
    trip_to("3 after the continue path", function() return plan and plan.target end), 90,
    back_to_start, 45,
    function() banner = "trip 4: a cleared walked room, after the continue path" end,
    trip_to("4 cleared walked room", function() return plan and plan.walk[#plan.walk] end), 90,
    function()
        gt:get_config().ArriveAtDoor = saved_arrive
        banner = ""
    end,
}

local HINT = "four trips run by themselves; nothing to do by hand"

-- carries which key was pressed across the reload that brought this copy in; a
-- plain game start finds it absent and sits still rather than replaying anything
local pressed = DevReproPending
DevReproPending = nil

local running = pressed == "run"

if pressed == "dump" then dump() end

local step = 0
local waiting = 0

function mod:onNewRoom()
    if not (gt and gt.floor) then return end
    describe_room(trip_asked and "ARRIVED by trip" or "ARRIVED, no trip asked")
    trip_asked = false
end

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
        Isaac.ExecuteCommand(entry)
    end
end

function mod:onRender()
    rframe = rframe + 1
    for key, intent in pairs({ [Keyboard.KEY_F1] = "run", [Keyboard.KEY_F2] = "dump" }) do
        if Input.IsButtonTriggered(key, 0) then
            DevReproPending = intent
            Isaac.ExecuteCommand("luamod devrepro")
            return
        end
    end

    if running then
        Isaac.RenderText(string.format("running  %d/%d  %s", step, #STEPS, banner), 25, 25, 1, 0.9, 0.3, 1)
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
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
