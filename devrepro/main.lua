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
local REV = 10148
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
end

local banner = "" -- what the run is doing right now, drawn on screen for the watcher

-- Oct 28 report (mata): "cursor tends to jump/jitter on L rooms with minimapi".
-- MinimapAPI on, game-map cursor on, the player inside an L room missing its
-- top-left cell (LTL); hold TAB and move the cursor across that room.
local original
local function restore()
    if original then
        for key, value in pairs(original) do gt:get_config()[key] = value end
        original = nil
    end
end
mod:AddPriorityCallback(ModCallbacks.MC_PRE_GAME_EXIT, CallbackPriority.EARLY - 1, restore)

local ltl -- the LTL room's descriptor once a floor has one

-- reseed until the floor has an LTL room, then walk into it
local reseed_wait = 0
local function find_ltl()
    if reseed_wait > 0 then
        reseed_wait = reseed_wait - 1
        return true
    end
    local rooms = Game():GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local rd = rooms:Get(i)
        if rd.Data.Shape == RoomShape.ROOMSHAPE_LTL then
            ltl = rd
            log("LTL gi=%d safe=%d seed %s", rd.GridIndex, rd.SafeGridIndex, Game():GetSeeds():GetStartSeedString())
            Game():StartRoomTransition(rd.SafeGridIndex, Direction.NO_DIRECTION, RoomTransitionAnim.TELEPORT)
            return false
        end
    end
    Isaac.ExecuteCommand("reseed")
    reseed_wait = 10
    return true
end

-- every cell of the LTL room: where the cursor is drawn for it, and which room
-- MinimapAPI's own hit test finds under that point
local function sweep()
    local g = gt.gamemap
    for _, cell in ipairs({ ltl.GridIndex + 1, ltl.GridIndex + 13, ltl.GridIndex + 14 }) do
        local c = g.cell_to_screen(cell)
        local hit = c and g.get_pos_grid_index_minimapapi(c) or -99
        log("[SWEEP] cell=%d drawn=%s hit=%d want=%d %s", cell, c and string.format("%.1f,%.1f", c.X, c.Y) or "-",
            hit, ltl.SafeGridIndex, hit == ltl.SafeGridIndex and "ok" or "MISS")
    end
end

local function setup()
    local cfg = gt:get_config()
    original = {}
    for _, key in ipairs({"CursorOnGameMap", "KeyboardMapEnable", "AllowAnyRoom"}) do
        original[key] = cfg[key]
    end
    cfg.CursorOnGameMap, cfg.KeyboardMapEnable, cfg.AllowAnyRoom = true, true, true
    log("ENV rgon=%s mmapi=%s", tostring(REPENTOGON), tostring(MinimapAPI ~= nil))
    sweep()
end

-- [GMC] one line whenever the keyboard cell changes while TAB is held, with the
-- hit test of the drawn point: a MISS is a cursor drawn off its own room
local last_key = ""
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not original or not Input.IsActionPressed(ButtonAction.ACTION_MAP, 0) then return end
    local w, g = gt.widget, gt.gamemap
    local kcell = w.mmp_ctrl and w.kb_active and w.cursor_cell() or -1
    local key = string.format("%d %s", kcell, tostring(MinimapAPI and MinimapAPI:IsLarge()))
    if key == last_key then return end
    last_key = key
    local c, s, hit
    if kcell >= 0 then c, s = g.cell_to_screen(kcell) end
    if c then hit = g.get_pos_grid_index_minimapapi(c) end
    local want = gt.floor.grid_room[kcell]
    want = want and want.SafeGridIndex or -1
    log("[GMC] kcell=%d at=%s scale=%s large=%s hit=%s want=%d %s", kcell,
        c and string.format("%.0f,%.0f", c.X, c.Y) or "-", tostring(s), tostring(MinimapAPI and MinimapAPI:IsLarge()),
        tostring(hit), want, hit == want and "ok" or "MISS")
end)

local STEPS = {
    "luamod goodtripfixed", 10,
    "restart 0", 10,
    "debug 3", "debug 10", "stage 6", 10,
    find_ltl, 30,
    "giveitem c333", 10, -- The Mind: whole floor on the map
    setup,
}

local HINT = "Hold TAB, move the cursor across the L room; Esc-exit when done."

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
