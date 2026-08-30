local hasoldtmmc = (tmmc and not tmmc.istmmcfixed and tmmc or nil)
local _tmmc = RegisterMod("TimeMachine [Fixed]", 1)
tmmc = _tmmc
_tmmc.istmmcfixed = true
local function show_warn(warnmsg)
    local warncounter = 300
    print(warnmsg)
    _tmmc:AddCallback(ModCallbacks.MC_POST_RENDER, function (_)
        if warncounter >= 0 then
            local alpha = math.min(60, math.max(0, warncounter)) / 60
            local player = Isaac.GetPlayer(0)
            local pos = Isaac.WorldToScreen(player.Position - Vector(0, player.Size * 5))
            pos.X = pos.X - Isaac.GetTextWidth(warnmsg) * 0.25
            Isaac.RenderScaledText(warnmsg, pos.X, pos.Y, 0.5, 0.5, 1, 1, 0, alpha)
            warncounter = warncounter - 1
        end
    end)
end
if hasoldtmmc then
    show_warn('WARNING: You must disable the old TimeMachine before using TimeMachine [Fixed]!')
    tmmc = hasoldtmmc
    return
end

tmmc.speedmin = 0
tmmc.speeda = 0.05
tmmc.speedmax = 5
tmmc.supressFly = true
tmmc.supressBomb = true
tmmc.preventDeath = true
tmmc.enableChest = true
tmmc.enableModded = true
tmmc.moddedmax = 5
tmmc.moddedGuard = true
tmmc.enable = {
    true,   --1.Slot Machine
    true,   --2.Blood Donation Machine
    true,   --3.Fortune Telling Machine
    true,   --4.Beggar
    true,   --5.Devil Beggar
    true,  --6.Shell Game
    true,   --7.Key Master
    false,  --8.Donation Machine
    true,   --9.Bomb Bum
    false,  --10.Shop Restock Machine
    true,  --11.Greed Donation Machine
    false,  --12.Mom's Dressing Table
    true,   --13.Battery Bum
    false,  --14.Isaac (secret)
    true,  --15.Hell Game
    true,   --16.Crane Game
    true,   --17.Confessional
    true,   --18.Rotten Beggar
}
local machine_names = {
    "Slot Machine", "Blood Donation Machine", "Fortune Telling Machine",
    "Beggar", "Devil Beggar", "Shell Game", "Key Master", "Donation Machine",
    "Bomb Bum", "Shop Restock Machine", "Greed Donation Machine",
    "Mom's Dressing Table", "Battery Bum", "Isaac (secret)", "Hell Game",
    "Crane Game", "Confessional", "Rotten Beggar",
}
--machines that take health instead of coins: fast-forward here is deadly when misjudged
local health_machine = {
    [2] = true,   --Blood Donation Machine
    [5] = true,   --Devil Beggar
    [15] = true,  --Hell Game
    [17] = true,  --Confessional
}
---configs---
if ModConfigMenu then
    local oldcfgdatas = nil
    --persist on change so a setting survives a luamod hot-reload (and a crash):
    --the only built-in save trigger is leaving a run, so a mid-run toggle change
    --used to be discarded the moment Lua was re-executed
    local function save_config()
        local json = require('json')
        local dat = json.encode({
            speedmax = tmmc.speedmax,
            speeda = tmmc.speeda,
            supressFly = tmmc.supressFly,
            supressBomb = tmmc.supressBomb,
            preventDeath = tmmc.preventDeath,
            enableChest = tmmc.enableChest,
            enableModded = tmmc.enableModded,
            moddedmax = tmmc.moddedmax,
            moddedGuard = tmmc.moddedGuard,
            enable = tmmc.enable,
        })
        if not oldcfgdatas or dat ~= oldcfgdatas then
            oldcfgdatas = dat
            _tmmc:SaveData(dat)
        end
    end
    local function load_config()
        if not _tmmc:HasData() then return end
        local dat = _tmmc:LoadData()
        oldcfgdatas = dat
        local json = require('json')
        local ok, cfg = pcall(json.decode, dat)
        if ok and type(cfg) == 'table' then
            tmmc.speedmax = cfg.speedmax or tmmc.speedmax
            tmmc.speeda = cfg.speeda or tmmc.speeda
            if cfg.supressFly ~= nil then tmmc.supressFly = cfg.supressFly end
            if cfg.supressBomb ~= nil then tmmc.supressBomb = cfg.supressBomb end
            if cfg.preventDeath ~= nil then tmmc.preventDeath = cfg.preventDeath end
            if cfg.enableChest ~= nil then tmmc.enableChest = cfg.enableChest end
            if cfg.enableModded ~= nil then tmmc.enableModded = cfg.enableModded end
            tmmc.moddedmax = cfg.moddedmax or tmmc.moddedmax
            if cfg.moddedGuard ~= nil then tmmc.moddedGuard = cfg.moddedGuard end
            if type(cfg.enable) == 'table' then
                for i = 1, #tmmc.enable do
                    if cfg.enable[i] ~= nil then tmmc.enable[i] = cfg.enable[i] end
                end
            end
        end
    end
    if ModConfigMenu.GetCategoryIDByName("TimeMachine [Fixed]") ~= nil then
        print('TimeMachine [Fixed] is reloading ModConfigMenu options')
        ModConfigMenu.RemoveCategory("TimeMachine [Fixed]")
    end
    ModConfigMenu.AddSetting(
      "TimeMachine [Fixed]", nil,
      {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = 1,
        Maximum = 10,
        Default = 5,
        CurrentSetting = function()
          return tmmc.speedmax
        end,
        Display = function()
          return "MaxSpeed: " .. tostring(tmmc.speedmax)
        end,
        OnChange = function(b)
          tmmc.speedmax = b
          save_config()
        end,
        Info = { "Maximum extra speed a machine can reach (in game ticks per real tick)" },
      }
    )
    ModConfigMenu.AddSetting(
      "TimeMachine [Fixed]", nil,
      {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = 1,
        Maximum = 50,
        Default = 5,
        CurrentSetting = function()
          return math.floor(tmmc.speeda * 100 + 0.5)
        end,
        Display = function()
          return "SpeedUpPercent: " .. tostring(math.floor(tmmc.speeda * 100 + 0.5))
        end,
        OnChange = function(b)
          tmmc.speeda = b / 100
          save_config()
        end,
        Info = { "How fast the speed builds up while touching a machine (percent per tick)" },
      }
    )
    ModConfigMenu.AddSetting(
      "TimeMachine [Fixed]", nil,
      {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = 1,
        Maximum = 10,
        Default = 5,
        CurrentSetting = function()
          return tmmc.moddedmax
        end,
        Display = function()
          return "ModdedMaxSpeed: " .. tostring(tmmc.moddedmax)
        end,
        OnChange = function(b)
          tmmc.moddedmax = b
          save_config()
        end,
        Info = { "Top speed for a machine another mod added, recommend lower to avoid compatibility or performance issues" },
      }
    )
    for _, info in ipairs({
        { "supressFly", "KillSpawnedFlies", "Kill flies spawned by Shell Game / Hell Game / beggars so speeding up won't get you hurt" },
        { "supressBomb", "DefuseSpawnedBombs", "Delay troll bombs dropped by machines / beggars so they explode after you finished" },
        { "preventDeath", "PreventSuddenDeath", "Pause acceleration at blood-taking machines when the next donation could kill you (turn it off to keep accelerating at lethal HP too)" },
        { "enableChest", "EternalChest", "Speed up the eternal chest (the blue one in Angel Rooms) so its open-close-reopen wait is not dead time" },
        { "enableModded", "ModdedMachines", "Speed up beggars and machines added by other mods -- potentially compatibility issue, turn this off if one of them misbehaves" },
        { "moddedGuard", "ModdedDeathGuard", "Treat a machine another mod added as if it took a full heart, and stop speeding it up when the next use could kill" },
    }) do
        ModConfigMenu.AddSetting(
          "TimeMachine [Fixed]", nil,
          {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
              return tmmc[info[1]]
            end,
            Display = function()
              return info[2] .. ": " .. (tmmc[info[1]] and "on" or "off")
            end,
            OnChange = function(b)
              tmmc[info[1]] = b
              save_config()
            end,
            Info = { info[3] },
          }
        )
    end
    for i, name in ipairs(machine_names) do
        ModConfigMenu.AddSetting(
          "TimeMachine [Fixed]", nil,
          {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
              return tmmc.enable[i]
            end,
            Display = function()
              return name .. ": " .. (tmmc.enable[i] and "on" or "off")
            end,
            OnChange = function(b)
              tmmc.enable[i] = b
              save_config()
            end,
            Info = { "Accelerate " .. name .. " while touching it" },
          }
        )
    end
    --Mod配置菜单（中文版）announces itself, and it is the only build that draws
    --text as UTF-8 -- the plain menu goes byte by byte, where Chinese comes out
    --as rubbish. The English menu above is untouched; this paints over what is
    --drawn, and the keys settings save under never move. Punctuation stays
    --ASCII: the bundled font has the hanzi but not the full-width marks, which
    --render as gaps
    if ModConfigMenu.i18n == "Chinese" then
        local CAT = "TimeMachine [Fixed]"
        --Display is a function, so these are search-and-replace pairs run over
        --the finished line ("MaxSpeed: 5"), anchored to the front so a name
        --cannot eat the front of a longer one
        local names = {
            { "^MaxSpeed:", "最高倍速:" },
            { "^SpeedUpPercent:", "加速快慢:" },
            { "^KillSpawnedFlies:", "清掉刷出来的苍蝇:" },
            { "^DefuseSpawnedBombs:", "延后刷出来的即爆炸弹:" },
            { "^PreventSuddenDeath:", "血量危险时停下:" },
            { "^EternalChest:", "永恒宝箱:" },
            { "^ModdedMachines:", "模组机器:" },
            { "^ModdedMaxSpeed:", "模组机器最高倍速:" },
            { "^ModdedDeathGuard:", "模组机器保守血量:" },
            { ": on$", ": 开" },
            { ": off$", ": 关" },
        }
        --Info is a plain table of strings, matched whole
        local infos = {
            ["Maximum extra speed a machine can reach (in game ticks per real tick)"] = "机器最多能快到几倍, 也就是一个真实帧里跑多少个游戏帧",
            ["How fast the speed builds up while touching a machine (percent per tick)"] = "贴着机器时倍速涨得多快, 每帧涨百分之几",
            ["Kill flies spawned by Shell Game / Hell Game / beggars so speeding up won't get you hurt"] = "把猜球游戏, 地狱猜球和乞丐刷出来的苍蝇清掉, 免得快进的时候挨一下",
            ["Delay troll bombs dropped by machines / beggars so they explode after you finished"] = "机器和乞丐掉出来的恶搞炸弹推迟引爆, 等你弄完再炸",
            ["Pause acceleration at blood-taking machines when the next donation could kill you (turn it off to keep accelerating at lethal HP too)"] = "在抽血的机器前, 如果下一次抽血就会要命, 就先停住不加速 (关掉的话血量再低也照样加速)",
            ["Speed up the eternal chest (the blue one in Angel Rooms) so its open-close-reopen wait is not dead time"] = "贴着天使房的蓝宝箱时加速, 开了关关了开的那段等待就不用干等了",
            ["Treat a machine another mod added as if it took a full heart, and stop speeding it up when the next use could kill"] = "模组乞丐和模组机器一律假设要扣一颗心, 下一次可能致命就不再加速",
            ["Top speed for a machine another mod added, recommend lower to avoid compatibility or performance issues"] = "模组机器最多能快到几倍, 建议不要太高, 避免兼容性或性能问题",
            ["Speed up beggars and machines added by other mods -- potentially compatibility issue, turn this off if one of them misbehaves"] = "模组乞丐和模组机器也加速, 可能有兼容性问题, 如果表现不对劲就关掉",
        }
        --every machine's own switch and its one-line description come from the
        --same name, so both sides are generated from one table. The pattern
        --side is escaped: "Isaac (secret)" would otherwise read as a capture
        local machines = {
            { "Slot Machine", "老虎机" },
            { "Blood Donation Machine", "献血机" },
            { "Fortune Telling Machine", "预言机" },
            { "Beggar", "乞丐" },
            { "Devil Beggar", "恶魔乞丐" },
            { "Shell Game", "三选一游戏" },
            { "Key Master", "钥匙大师" },
            { "Donation Machine", "捐款机" },
            { "Bomb Bum", "炸弹乞丐" },
            { "Shop Restock Machine", "商店补货机" },
            { "Greed Donation Machine", "贪婪捐款机" },
            { "Mom's Dressing Table", "妈妈的梳妆台" },
            { "Battery Bum", "电池乞丐" },
            { "Isaac (secret)", "以撒 (隐藏)" },
            { "Hell Game", "恶魔三选一" },
            { "Crane Game", "抓娃娃机" },
            { "Confessional", "忏悔室" },
            { "Rotten Beggar", "腐烂乞丐" },
        }
        for _, m in ipairs(machines) do
            local pattern = m[1]:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            names[#names + 1] = { "^" .. pattern .. ":", m[2] .. ":" }
            infos["Accelerate " .. m[1] .. " while touching it"] = "贴着" .. m[2] .. "时加速"
        end
        ModConfigMenu.SetCategoryNameTranslate(CAT, "TimeMachine [修复版]")
        ModConfigMenu.TranslateOptionsDisplayWithTable(CAT, nil, names)
        ModConfigMenu.TranslateOptionsInfoTextWithTable(CAT, nil, infos)
    end
    load_config()
    _tmmc:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContined)
        load_config()
    end)
    _tmmc:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
        save_config()
    end)
end
---machine speedup---
local speedNow = tmmc.speedmin
local speedAccum = 0.0
--upvalue shared with the damage guard: true while a machine is being accelerated
local accelerating = false
--vanilla holds an eternal chest open for 60 frames before it shuts, so four times
--that is a wait no live chest is still in. Past it the chest has paid out a
--collectible and will never reclose, and nothing readable tells that apart from a
--chest mid-cycle -- both read open and idle -- so the updates already pushed since
--its last flip are the tell
local CHEST_SPENT = 60 * 4
local chest_ticks = {}
--what counts as touching a machine is measured off its size, and a machine
--another mod added can carry any size at all: this beggar's reach and its
--collision radius are the same number, so the player stands exactly at the
--distance the test excludes and the machine was never seen as touched. The
--engine settles the same question every frame anyway, so it is asked instead --
--nothing is returned, so the collision itself behaves as it always did
local touched = {}
_tmmc:AddCallback(ModCallbacks.MC_PRE_PLAYER_COLLISION, function(_, player, collider)
    if collider.Type == 6 then
        touched[GetPtrHash(collider)] = Game():GetFrameCount()
    end
end)
--a machine another mod added is driven by that mod, not by the game: the entity
--carries only the animation, and every decision it makes -- what it pays, when
--it pays, when it goes back to idle -- is taken in the once-a-frame pass that
--mod subscribes to, off exact animation frames. An extra tick does move such a
--machine, so a tick its owner never sees is a tick that did not happen for it:
--the animation races past the frame the payout hangs on and the beggar freezes
--there, paying nothing. So each extra tick is followed by that pass. It runs
--every other mod's per-frame code too, which costs nothing measurable but does
--run that code at the machine's speed -- hence a ceiling of its own
--one subscriber at a time rather than Isaac.RunCallback, which stops at the
--first one that returns a value and would leave the rest of the mods unfed --
--the machine's owner among them, depending on the order they loaded in. Reading
--the list back is a Repentance+ function, so on older Repentance no machine is
--taken to be modded at all: a beggar left at plain speed beats a frozen one
local can_pump = Isaac.GetCallbacks ~= nil
local pumping = false
local function pump_mods()
    if pumping then return end
    pumping = true
    for _, cb in ipairs(Isaac.GetCallbacks(ModCallbacks.MC_POST_UPDATE)) do
        if cb.Mod ~= _tmmc then
            pcall(cb.Function, cb.Mod)
        end
    end
    pumping = false
end
function tmmc:new_room()
    speedNow = tmmc.speedmin
    chest_ticks = {}
    touched = {}
end
--everything the player can stand against and wait on: slot machines by their own
--switches, plus the eternal chest, which is not a machine but is the same shape of
--waiting -- one accumulator has to drive both, or the run timer counts twice
function tmmc:find_targets()
    local targets = {}
    local slots = Isaac.FindByType(6, -1, -1, false, false)
    for _, slot in ipairs(slots) do
        --membership is the variant being one the game itself ships, not the
        --switch being on: a modded machine is free to claim a number inside the
        --vanilla range, and it would otherwise inherit that machine's switch
        --and its "costs health or not" answer, neither of which is about it
        if slot.Variant >= 1 and slot.Variant <= #machine_names then
            if tmmc.enable[slot.Variant] then
                table.insert(targets, { ent = slot, chest = false, modded = false })
            end
        elseif tmmc.enableModded and can_pump then
            table.insert(targets, { ent = slot, chest = false, modded = true })
        end
    end
    if tmmc.enableChest then
        --variant 53 only: the spiked and mimic chests next to it both hurt
        local chests = Isaac.FindByType(5, PickupVariant.PICKUP_ETERNALCHEST, -1, false, false)
        for _, chest in ipairs(chests) do
            table.insert(targets, { ent = chest, chest = true })
        end
    end
    return targets
end
function tmmc:hp_halves(player)
    return player:GetHearts() + player:GetSoulHearts()
         + player:GetBoneHearts() + player:GetEternalHearts()
end
--half-hearts one activation takes: Blood Donation Machine takes a FULL heart
--from the Womb onwards (wiki: Machines), the other health machines half
function tmmc:machine_cost(variant)
    if variant == 2 then
        local stage = Game():GetLevel():GetStage()
        if Game():IsGreedMode() and stage >= 4 or stage >= LevelStage.STAGE4_1 then
            return 2
        end
    end
    return 1
end
--one machine, count extra ticks: the player is held against it and stepped along
--with it, because the interaction only advances while the two stay in contact
function tmmc:accel_slot(player, slot, count, modded)
    --keep health-taking machines at vanilla speed when the next hit could kill,
    --so the player has real time to walk away. A machine another mod added is
    --held to its own switch: what it charges cannot be read from here, so it is
    --taken to charge the most the game itself charges, a full heart. The cost of
    --being wrong is a modded coin beggar that stops speeding up on the last
    --heart, against a death at one that turned out to take blood
    local danger
    if modded then
        danger = tmmc.moddedGuard and tmmc:hp_halves(player) <= 2
    else
        danger = tmmc.preventDeath and health_machine[slot.Variant]
            and tmmc:hp_halves(player) <= tmmc:machine_cost(slot.Variant)
    end
    if danger then
        return false
    end
    local dx = player.Position.X - slot.Position.X
    local dy = player.Position.Y - slot.Position.Y
    if math.abs(dx) < math.max(5, 6 * player.MoveSpeed) then
        if ((Input.IsActionPressed(ButtonAction.ACTION_UP, player.ControllerIndex) and dy > 0) or (Input.IsActionPressed(ButtonAction.ACTION_DOWN, player.ControllerIndex) and dy < 0))
            and (not Input.IsActionPressed(ButtonAction.ACTION_RIGHT, player.ControllerIndex)) and (not Input.IsActionPressed(ButtonAction.ACTION_LEFT, player.ControllerIndex)) then
            player.Position = Vector(player.Position.X - dx / 2, player.Position.Y + dy / math.abs(dy) * (player.Size + slot.Size - math.abs(dy)) * (player.MoveSpeed + speedNow) / 2)
        end
    end
    for _ = 1, count do
        --the player's body shoves a machine another mod owns the way it shoves a
        --monster, and every tick is a whole shove: at ten ticks a frame the
        --beggar visibly shakes. The game's own tick still moves it; ours do not
        local slotPos, slotVel
        if modded then
            slotPos, slotVel = slot.Position, slot.Velocity
        end
        slot:Update()
        if modded then
            slot.Position, slot.Velocity = slotPos, slotVel
            pump_mods()
        end
        --kill spawned flies before the player update below runs, so a fly
        --spawned this tick never gets a collision/damage pass against the
        --player (otherwise it could land one hit before the end-of-step kill)
        if tmmc.supressFly then
            for _, e in ipairs(Isaac.FindByType(18, 0, 0)) do
                e:Kill()
            end
            for _, e in ipairs(Isaac.FindByType(85, 0, 0)) do
                e:Kill()
            end
        end
        local oldPosition = player.Position
        player:Update()
        player.Position = oldPosition
        --post-hit i-frames would stall the accelerated machine (it cannot
        --take blood again until they expire), so burn them at double rate.
        --Effect invincibility (The Chariot / Power Pill / Unicorn) has no
        --damage cooldown and must NOT be burned this way: it has to flow
        --1:1 with the machine, or the free donations it buys drop below
        --vanilla
        if health_machine[slot.Variant] and player:GetDamageCooldown() > 0
            and (not tmmc.preventDeath
                 or tmmc:hp_halves(player) > tmmc:machine_cost(slot.Variant)) then
            oldPosition = player.Position
            player:Update()
            player.Position = oldPosition
        end
    end
    return true
end
--an eternal chest is nothing but waiting: it holds open about 60 frames, shuts with
--a 30 frame lockout, and only then takes another key. Extra updates on the chest
--compress both, and the player is deliberately left alone -- a chest costs no
--health, so none of the machine's player-stepping is needed here
function tmmc:accel_chest(player, chest, count)
    local id = GetPtrHash(chest)
    local seen = chest_ticks[id]
    if seen == nil or seen.sub ~= chest.SubType then
        seen = { sub = chest.SubType, ticks = 0 }
        chest_ticks[id] = seen
    end
    --a dead chest would otherwise ramp to full speed and push the run timer along
    --for as long as the player stood on it, and an Angel Room chest sits right in
    --the walking line to the pedestals
    if seen.ticks >= CHEST_SPENT then
        return false
    end
    --a closed chest with no key left is not waiting for anything either, so let the
    --ramp fall back instead of running the clock for nothing
    if chest.SubType ~= ChestSubType.CHEST_OPENED and player:GetNumKeys() <= 0 then
        return false
    end
    for _ = 1, count do
        chest:Update()
    end
    seen.ticks = seen.ticks + count
    return true
end
function tmmc:step()
    --this same pass is what a modded machine's extra ticks re-run, and stepping
    --machines from inside a step is how one tick becomes a hundred
    if pumping then
        return
    end
    accelerating = false
    if not Game():GetRoom():IsClear() then
        return
    end
    local targets = tmmc:find_targets()
    if #targets == 0 then
        return
    end
    local timeplus = 0
    local count = 1
    speedAccum = speedAccum + math.max(0, speedNow)
    while speedAccum > 1 do
        speedAccum = speedAccum - 1
        timeplus = timeplus + 1
        count = count + 1
    end
    local accelerated = false
    local acceleratedSlot = false
    local acceleratedModded = false
    for i = 0, Game():GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        for _, target in ipairs(targets) do
            local ent = target.ent
            local contact = player.Position:Distance(ent.Position) < (player.Size + ent.Size)
            if target.modded and not contact then
                --a collision reported this frame or the one before it: the tick
                --the player bounces off is still part of standing against it
                local when = touched[GetPtrHash(ent)]
                contact = when ~= nil and Game():GetFrameCount() - when <= 1
            end
            if contact then
                local ran
                if target.chest then
                    ran = tmmc:accel_chest(player, ent, count)
                else
                    ran = tmmc:accel_slot(player, ent, count, target.modded)
                    acceleratedSlot = acceleratedSlot or ran
                    acceleratedModded = acceleratedModded or (ran and target.modded)
                    if tmmc.supressBomb then
                        for _, e in ipairs(Isaac.FindByType(4, -1, -1)) do
                            e:ToBomb():SetExplosionCountdown(100)
                            e.Velocity = -e.Velocity
                        end
                    end
                end
                accelerated = accelerated or ran
            end
        end
    end
    if accelerated then
        --the ramp is what a modded machine's own ceiling holds down, not the
        --tick count, so the run timer keeps counting exactly the ticks that ran
        local cap = tmmc.speedmax
        if acceleratedModded then
            cap = math.min(cap, tmmc.moddedmax)
        end
        if speedNow > cap then
            speedNow = cap
        elseif speedNow <= cap then
            speedNow = speedNow + tmmc.speeda
        end
        --the fly-damage block covers machines only: nothing a chest does spawns a
        --fly, and widening it would swallow hits that are real
        accelerating = acceleratedSlot
        Game().TimeCounter = Game().TimeCounter + timeplus
    else
        speedNow = tmmc.speedmin
    end
end

tmmc:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, tmmc.new_room)
tmmc:AddCallback(ModCallbacks.MC_POST_UPDATE, tmmc.step)

--a fly spawned by a machine is born in the main update pass and lands one
--contact hit there before our MC_POST_UPDATE cull can remove it, so blocking
--the hit is the only way to close that 1-frame gap. Only while accelerating at
--a machine, with KillSpawnedFlies on, in a cleared room — so real combat and
--blood-machine donations (source = the slot, not a fly) stay untouched.
_tmmc:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, function(_, _ent, _amount, _flags, source)
    if not accelerating or not tmmc.supressFly or not Game():GetRoom():IsClear() then return end
    local s = source and source.Entity
    if s and (s.Type == 18 or s.Type == 85) then
        return false
    end
end, EntityType.ENTITY_PLAYER)
