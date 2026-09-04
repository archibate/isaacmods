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
local REV = 128
Isaac.DebugString("[DEVREPRO] rev " .. REV)

local tick = 0 -- the driver's own update count; the game's resets on restart
local rframe = 0 -- and its render count, 60 a second: how long a thing was on screen

local function log(fmt, ...)
    Isaac.DebugString(string.format("[DR%d t%d r%d] " .. fmt, REV, tick, rframe, ...))
end

local function vec(v)
    return string.format("(%.1f,%.1f)", v.X, v.Y)
end

-- the question, li3397450972's: a trip from one big room to another with a big
-- room between them makes the view twitch. Whitor's "landed in an empty room,
-- then went on into the next" may be the same thing seen from the other side:
-- since 09-02 a far trip into a big room first ChangeRooms into the last walked
-- room on the way (cleared, so empty) and starts the transition from there. The
-- Void is nearly all big rooms, so the floor is reseeded until three sit in a
-- row, the first two are walked, and the trip goes from the first to the third.
-- Every arrival is stamped with the render count, and for 90 render frames after
-- a landing the player's place on screen is logged whenever it jumps

local trip_asked = false -- a trip was asked for and has not landed yet
local watch = 0 -- render frames of the view watch still to run
local watch_screen = nil
local watch_room = nil

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
        local cell, walked = gt.rules.landing_route(from, there)
        log("TRIP asked: from %d to %d (safe %d) shape %s teleble=%s ready=%s route cell=%s walked=%s slot=%s",
            from, gid, there, trd and tostring(trd.Data.Shape) or "?",
            tostring(gt.rules.check_teleble(gid)), tostring(gt.trip.ready()),
            tostring(cell), tostring(walked), tostring(gt.rules.landing_slot(from, there)))
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
    log("%s: safe %d type %d shape %d visited %d clear %s enter %d player=%s screen=%s scroll=%s",
        tag, d.SafeGridIndex, d.Data.Type, d.Data.Shape, d.VisitedCount, tostring(d.Clear),
        lvl.EnterDoor, vec(p.Position), vec(Isaac.WorldToScreen(p.Position)),
        vec(Game():GetRoom():GetRenderScrollOffset()))
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

-- the chain found on this floor: three rooms bigger than one screen, the first
-- and third each touching the middle one and not each other
local chain = nil

local function find_chain()
    local lvl = Game():GetLevel()
    local cells = {} -- cell -> room descriptor
    local big = {}
    for _, d in ipairs(rooms()) do
        for jx = 0, 1 do
            for jy = 0, 1 do
                local c = d.GridIndex + jx + jy * 13
                if lvl:GetRoomByIdx(c, -1).ListIndex == d.ListIndex then cells[c] = d end
            end
        end
        if d.Data.Shape >= RoomShape.ROOMSHAPE_1x2 and d.SafeGridIndex ~= lvl:GetStartingRoomIndex() then
            big[#big + 1] = d
        end
    end
    local function touch(a, b)
        for c, d in pairs(cells) do
            if d.ListIndex == a.ListIndex then
                local col = c % 13
                for _, step in ipairs({ -13, 13, -1, 1 }) do
                    if not ((step == -1 and col == 0) or (step == 1 and col == 12)) then
                        local n = cells[c + step]
                        if n and n.ListIndex == b.ListIndex then return true end
                    end
                end
            end
        end
        return false
    end
    for _, a in ipairs(big) do
        for _, b in ipairs(big) do
            if a ~= b and touch(a, b) then
                for _, c in ipairs(big) do
                    if c ~= a and c ~= b and touch(b, c) and not touch(a, c) then
                        return { a.SafeGridIndex, b.SafeGridIndex, c.SafeGridIndex }
                    end
                end
            end
        end
    end
    return nil
end

-- reseeds until a chain turns up, then hands the mod the new floor
local hunt_wait, hunt_tries = 0, 0
local function hunt_chain()
    if hunt_wait > 0 then
        hunt_wait = hunt_wait - 1
        return true
    end
    chain = find_chain()
    if chain then
        log("CHAIN on seed %s after %d reseeds: %d -> %d -> %d", Game():GetSeeds():GetStartSeedString(),
            hunt_tries, chain[1], chain[2], chain[3])
        gt.control.new_level()
        gt.control.new_room()
        return false
    end
    if hunt_tries >= 60 then
        log("CHAIN: none in %d reseeds, giving up", hunt_tries)
        return false
    end
    hunt_tries = hunt_tries + 1
    Isaac.ExecuteCommand("reseed")
    hunt_wait = 10
    return true
end

-- round 6: the hop is on screen for 10 render frames because the room is switched
-- before the fade starts, so the middle room is what fades out. The fade takes
-- 10 render frames (5 updates) to load the target. Here the transition is asked
-- for from the first room, and the switch into the middle room is made some
-- updates later, under the darkening screen. Two things to learn: does the game
-- still take the wall from the middle room (arrival at the door facing it, as the
-- hop gives: enter 2, player 1080,280 on this floor), and does the middle room
-- still show. Raw calls, not the mod's trip, so the mod's own hop stays out of it
local banner = "" -- what the run is doing right now, drawn on screen for the watcher

-- round 8: the hop even one frame before the load still showed the middle room
-- (the fade is not black at the switch, under either animation), so the door
-- landing goes off by default instead, under a new name. This run takes the far
-- trip once with the default and once with the switch on: the first should land
-- in one go, the game's own way, and the second should hop as before

local STEPS = {
    "luamod goodtripfixed",
    "restart 0", 10,
    "stage 12", 15,
    "debug 3",
    "debug 10", -- the chain's rooms hold bosses; the route needs them cleared
    "lua gt:get_config().AllowAnyRoom = true",
    arm_instruments,
    hunt_chain,
    function()
        describe_room("START")
        log("CONFIG ArriveAtDoor=%s LandAtDoor=%s", tostring(gt:get_config().ArriveAtDoor), tostring(gt:get_config().LandAtDoor))
    end,
    trip_to("A: first big room", function() return chain and chain[1] end), 90,
    trip_to("B: the middle big room, next door", function() return chain and chain[2] end), 120,
    trip_to("A again", function() return chain and chain[1] end), 90,
    function() banner = "default: ArriveAtDoor off" end,
    trip_to("C: the far big room, ArriveAtDoor off", function() return chain and chain[3] end), 150,
    trip_to("A again", function() return chain and chain[1] end), 90,
    "lua gt:get_config().ArriveAtDoor = true",
    function() banner = "ArriveAtDoor on" end,
    trip_to("C: the far big room, ArriveAtDoor on", function() return chain and chain[3] end), 150,
    "lua gt:get_config().ArriveAtDoor = false",
    function() banner = "" end,
}

local HINT = "two trips into the far room: switch off, then on. only the second should show the middle room"

-- carries which key was pressed across the reload that brought this copy in; a
-- plain game start finds it absent and sits still rather than replaying anything
local pressed = DevReproPending
DevReproPending = nil

local running = pressed == "run"

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

if pressed == "dump" then dump() end

local step = 0
local waiting = 0

function mod:onNewRoom()
    if not (gt and gt.floor) then return end
    describe_room(trip_asked and "ARRIVED by trip" or "ARRIVED, no trip asked (AUTO?)")
    trip_asked = false
    watch = 90
    watch_screen = Isaac.WorldToScreen(Isaac.GetPlayer(0).Position)
    watch_room = here()
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

    if watch > 0 then
        watch = watch - 1
        local p = Isaac.GetPlayer(0)
        if here() ~= watch_room then
            log("WATCH room changed %d -> %d", watch_room, here())
            watch_room = here()
        end
        local s = Isaac.WorldToScreen(p.Position)
        if (s - watch_screen):Length() > 30 then
            log("WATCH view jump: player on screen %s -> %s, in world %s, scroll %s",
                vec(watch_screen), vec(s), vec(p.Position), vec(Game():GetRoom():GetRenderScrollOffset()))
        end
        watch_screen = s
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
