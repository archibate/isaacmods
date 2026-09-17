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
local REV = 157
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

-- the question, Alooha's: with Glitched Crown, a beggar sped up by TimeMachine
-- pays out an item that is taken the moment it appears, no time to pick one of
-- the cycling choices. The answer under test is TimeMachine's ReleaseToPickUp:
-- an item that appears while the player holds a direction stays out of reach
-- until they let go once. The log follows the item, the player's distance and
-- movement keys, and the item that ends up taken; the mod's own [TMHOLD] lines
-- say when it locked, blocked and released. The last step puts both switches back
local MODE = "fast"
local BEGGAR = 4 -- SlotVariant.BEGGAR
local saved_switch, saved_hold
local watch = { t = 0, items = {}, anim = nil, since = nil, count = nil, queued = nil, taken = nil }

local function keys()
    local s = ""
    for name, action in pairs({ L = ButtonAction.ACTION_LEFT, R = ButtonAction.ACTION_RIGHT,
        U = ButtonAction.ACTION_UP, D = ButtonAction.ACTION_DOWN }) do
        if Input.IsActionPressed(action, 0) then s = s .. name end
    end
    return s == "" and "-" or s
end

local function setup()
    local room = Game():GetRoom()
    local p = Isaac.GetPlayer(0)
    local c = room:GetCenterPos()
    Isaac.Spawn(EntityType.ENTITY_SLOT, BEGGAR, 0, c + Vector(0, -80), Vector.Zero, nil)
    p.Position = c + Vector(0, 40)
    saved_switch = tmmc.enable[BEGGAR]
    tmmc.enable[BEGGAR] = MODE == "fast"
    saved_hold = tmmc.holdItems
    tmmc.holdItems = true
    watch.count = p:GetCollectibleCount()
    log("CONFIG mode %s beggar switch was %s now %s hold was %s now %s speedmax %s coins %d",
        MODE, tostring(saved_switch), tostring(tmmc.enable[BEGGAR]), tostring(saved_hold),
        tostring(tmmc.holdItems), tostring(tmmc.speedmax), p:GetNumCoins())
    banner = "feed from above, keep holding DOWN after the item appears"
end

local function watch_items()
    local p = Isaac.GetPlayer(0)
    watch.t = watch.t + 1
    local b = Isaac.FindByType(EntityType.ENTITY_SLOT, BEGGAR, -1, false, false)[1]
    local anim = b and b:GetSprite():GetAnimation() or "gone"
    -- how many ticks the last animation held is the pace: the mod's speed is a
    -- local of its own, and a run where it never engaged looks like vanilla
    if anim ~= watch.anim then
        log("beggar %s (%d ticks) -> %s coins %d dist %.1f keys %s", tostring(watch.anim), watch.t - (watch.since or 0),
            anim, p:GetNumCoins(), b and p.Position:Distance(b.Position) or -1, keys())
        watch.anim = anim
        watch.since = watch.t
    end
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, -1, false, false)) do
        local k = GetPtrHash(e)
        local seen = watch.items[k]
        if not seen then
            seen = { born = watch.t, sub = nil }
            watch.items[k] = seen
            banner = "item out: hold DOWN a while, let go and wait, then walk in"
        end
        local age = watch.t - seen.born
        local d = p.Position:Distance(e.Position)
        local k2 = keys()
        -- every change of item, of keys, and each tick of the player's approach
        if e.SubType ~= seen.sub or k2 ~= seen.keys or d < 40 or age <= 25 then
            log("item %d age %d sub %d wait %d dist %.1f reach %.1f keys %s", k, age, e.SubType, e:ToPickup().Wait, d,
                p.Size + e.Size, k2)
            seen.sub = e.SubType
            seen.keys = k2
        end
    end
    local queued = p.QueuedItem.Item and p.QueuedItem.Item.ID or 0
    if queued ~= watch.queued then
        log("queued %d", queued)
        watch.queued = queued
    end
    local n = p:GetCollectibleCount()
    if n ~= watch.count and not watch.taken then
        log("TAKEN count %d -> %d", watch.count, n)
        watch.taken = watch.t
        banner = "taken"
    end
    if watch.taken and watch.t - watch.taken > 15 then return false end
    if watch.t > 30 * 300 then
        log("watch timed out")
        return false
    end
    return true
end

local function restore()
    tmmc.enable[BEGGAR] = saved_switch
    tmmc.holdItems = saved_hold
    log("RESTORED beggar switch %s hold %s; watch end", tostring(tmmc.enable[BEGGAR]), tostring(tmmc.holdItems))
    banner = ""
end

local STEPS = {
    "luamod timemachinefixed",
    "restart 0", 10,
    "debug 3",
    "giveitem c689", -- Glitched Crown
    "giveitem c18", -- A Dollar: 99 coins to feed the beggar
    setup,
    watch_items,
    restore,
}

local HINT = "done: tell Claude whether letting go of DOWN took the item"

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
