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

local STEPS = {
    "luamod damagemvp",
    "restart 0", 60,
    "debug 3",
    "debug 8",
    "stage 1", 60,
    "giveitem c308",
    "giveitem c269",
    "spawn 16.0.0",
    "spawn 16.0.0",
    "spawn 16.0.0",
    "spawn 16.0.0",
    "spawn 16.0.0",
    "spawn 16.0.0",
}

local HINT = "walk about and let the Mulligans chase you through your Aquarius creep and the baby's"

local mod = RegisterMod("devrepro", 1)

-- set just before the reload that brought this copy in, so a plain game start
-- (where the global is absent) sits still instead of replaying the last script
local running = DevReproPending == true
DevReproPending = nil

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
        return
    end
    if type(entry) == "number" then
        waiting = entry
    else
        Isaac.ExecuteCommand(entry)
    end
end

function mod:onRender()
    if Input.IsButtonTriggered(Keyboard.KEY_F1, 0) then
        DevReproPending = true
        Isaac.ExecuteCommand("luamod devrepro")
        return
    end

    if running then
        Isaac.RenderText(string.format("running  %d/%d", step, #STEPS), 25, 25, 1, 0.9, 0.3, 1)
    elseif step > 0 then
        Isaac.RenderText(HINT, 25, 25, 0.6, 0.9, 0.6, 1)
    else
        Isaac.RenderText("F1: run repro", 25, 25, 0.5, 0.5, 0.5, 1)
    end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
