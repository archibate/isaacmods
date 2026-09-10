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
local REV = 149
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

-- the question, 神魔蜀黍's: on Rep+ the HUD paints over the predictor icon.
-- Each run holds Metronome and stops; the answer is the screen, with the held
-- item and its charge logged so the shot can be trusted
local function describe_active(tag)
    local p = Isaac.GetPlayer(0)
    local active = p:GetActiveItem(ActiveSlot.SLOT_PRIMARY)
    local cfg = Isaac.GetItemConfig():GetCollectible(active)
    log("%s: REPENTANCE_PLUS=%s player=%d active=%d charge=%d/%d screen=%dx%d hudoffset=%.2f", tag,
        tostring(REPENTANCE_PLUS), p:GetPlayerType(), active, p:GetActiveCharge(ActiveSlot.SLOT_PRIMARY),
        cfg and cfg.MaxCharges or -1, Isaac.GetScreenWidth(), Isaac.GetScreenHeight(), Options.HUDOffset)
end

-- F2 writes something out of the game rather than playing anything. Rewrite this
-- for whatever needs enumerating; it beats reading a wiki, which is where
-- hallucinated ids come from.
local function dump()
    log("floor: seed %s stage %d", Game():GetSeeds():GetStartSeedString(), Game():GetLevel():GetStage())
    describe_active("held")
end

local banner = "" -- what the run is doing right now, drawn on screen for the watcher

-- the feature under test: a Mod Config Menu switch per predicted item. The
-- Metronome switch is flipped through the menu's own option table, the way the
-- menu would, and put back at the end; each stage is held for a shot
local function stage(name)
    return function()
        describe_active("STAGE " .. name)
        banner = name
    end
end

local function setSwitch(index, on)
    local id = ModConfigMenu.GetCategoryIDByName("Predicable Metronome")
    local opt = ModConfigMenu.MenuData[id].Subcategories[1].Options[index]
    opt.OnChange(on)
    log("switch %d (%s) := %s, menu reads %s", index, opt.Display(), tostring(on), tostring(opt.CurrentSetting()))
end

local STEPS = {
    "luamod metronome_predictor",
    "restart 0", 10,
    "giveitem c488", 20, -- Metronome
    stage("F: both switches on, Metronome held"), 240,
    function() setSwitch(1, false) end,
    stage("G: Metronome switch off, icon should be gone"), 240,
    "giveitem c124", 20, -- Dead Sea Scrolls
    stage("H: Dead Sea Scrolls held, its switch still on"), 240,
    function() setSwitch(1, true) end,
}

local HINT = "three stages: icon, no icon, icon again; the shots are the answer"

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
