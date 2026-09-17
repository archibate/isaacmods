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
local REV = 168
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

-- the question, the user's: in Damage MVP The Bean's poison lands on an "Unknown"
-- row, and the knife the Yes Mother? transformation gives lands on Mom's Knife's.
-- Each round sets up one case beside an immortal dummy and holds the player still;
-- the mod's own [DMVP] lines say what every hit carried and which knives are out.
--   A  The Bean alone, used twice
--   B  the transformation's knife alone
--   C  that knife and the Mom's Knife item together
--   D  the transformation's knife and The Bean, the user's own combination
local ROUND = "D"
local MOM_FORM = ROUND ~= "A"
local KNIFE_ITEM = ROUND == "C"
local USES_BEAN = ROUND == "A" or ROUND == "D"
local BEAN = 111 -- CollectibleType.COLLECTIBLE_BEAN
local HUSH = 408 -- EntityType.ENTITY_HUSH_SKINLESS

local anchor

local function report()
    local p = Isaac.GetPlayer(0)
    log("ROUND %s form %s knife item %s knife weapon %s active %d", ROUND,
        tostring(p:HasPlayerForm(PlayerForm.PLAYERFORM_MOM)),
        tostring(p:HasCollectible(CollectibleType.COLLECTIBLE_MOMS_KNIFE)),
        tostring(p:HasWeaponType(WeaponType.WEAPON_KNIFE)), p:GetActiveItem())
end

-- the dummy goes on the knives where there are any, so they touch it while the
-- player stands still; otherwise just inside the fart's reach
local function place()
    local p = Isaac.GetPlayer(0)
    anchor = Game():GetRoom():GetCenterPos()
    p.Position = anchor
    p.Velocity = Vector.Zero
    local sum, n = Vector.Zero, 0
    for _, k in ipairs(Isaac.FindByType(EntityType.ENTITY_KNIFE, -1, -1, false, false)) do
        log("knife %d.%d.%d at %.1f,%.1f from player", k.Type, k.Variant, k.SubType,
            k.Position.X - p.Position.X, k.Position.Y - p.Position.Y)
        sum = sum + k.Position
        n = n + 1
    end
    local at = n > 0 and sum / n or anchor + Vector(0, -60)
    Isaac.Spawn(HUSH, 0, 0, at, Vector.Zero, nil)
    log("PLACED dummy at %.1f,%.1f from player", at.X - anchor.X, at.Y - anchor.Y)
    banner = "hands off: the run holds the player still"
end

-- the dummy has 500 health, which the knife and Mom's Heels take in five seconds,
-- so it is topped up every tick
local function hold(ticks)
    local left
    return function()
        left = (left or ticks) - 1
        local p = Isaac.GetPlayer(0)
        p.Position = anchor
        p.Velocity = Vector.Zero
        for _, dummy in ipairs(Isaac.FindByType(HUSH, -1, -1, false, false)) do
            dummy.HitPoints = dummy.MaxHitPoints
        end
        if left > 0 then return true end
        left = nil
        return false
    end
end

local function bean()
    log("USE bean")
    Isaac.GetPlayer(0):UseActiveItem(BEAN)
end

local STEPS = { "luamod damagemvp", "restart 0", 10, "debug 3" }
local function add(...)
    for _, entry in ipairs({ ... }) do STEPS[#STEPS + 1] = entry end
end
if MOM_FORM then add("giveitem c29", "giveitem c30", "giveitem c31") end
if KNIFE_ITEM then add("giveitem c114") end
if USES_BEAN then add("debug 8", "giveitem c111") end
add(10, report, place)
if USES_BEAN then
    add(hold(30), bean, hold(220), bean, hold(220))
else
    add(hold(300))
end
add(report)

local HINT = "done: tell Claude the round finished"

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
