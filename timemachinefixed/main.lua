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
tmmc.supressFly = false
tmmc.supressBomb = false
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
        end,
        Info = { "How fast the speed builds up while touching a machine (percent per tick)" },
      }
    )
    for _, info in ipairs({
        { "supressFly", "KillSpawnedFlies", "Kill flies spawned by Shell Game / Hell Game / beggars so speeding up won't get you hurt" },
        { "supressBomb", "DefuseSpawnedBombs", "Delay troll bombs dropped by machines / beggars so they explode after you finished" },
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
            end,
            Info = { info[3] },
          }
        )
    end
    for i, name in ipairs(machine_names) do
        ModConfigMenu.AddSetting(
          "TimeMachine [Fixed]", "Machines",
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
            end,
            Info = { "Accelerate " .. name .. " while touching it" },
          }
        )
    end
    _tmmc:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContined)
        if _tmmc:HasData() then
            local dat = _tmmc:LoadData()
            oldcfgdatas = dat
            local json = require('json')
            local ok, cfg = pcall(json.decode, dat)
            if ok and type(cfg) == 'table' then
                tmmc.speedmax = cfg.speedmax or tmmc.speedmax
                tmmc.speeda = cfg.speeda or tmmc.speeda
                if cfg.supressFly ~= nil then tmmc.supressFly = cfg.supressFly end
                if cfg.supressBomb ~= nil then tmmc.supressBomb = cfg.supressBomb end
                if type(cfg.enable) == 'table' then
                    for i = 1, #tmmc.enable do
                        if cfg.enable[i] ~= nil then tmmc.enable[i] = cfg.enable[i] end
                    end
                end
            end
        end
    end)
    _tmmc:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
        local json = require('json')
        local dat = json.encode({
            speedmax = tmmc.speedmax,
            speeda = tmmc.speeda,
            supressFly = tmmc.supressFly,
            supressBomb = tmmc.supressBomb,
            enable = tmmc.enable,
        })
        if not oldcfgdatas or dat ~= oldcfgdatas then
            oldcfgdatas = dat
            _tmmc:SaveData(dat)
        end
    end)
end
---machine speedup---
local speedNow = tmmc.speedmin
local speedAccum = 0.0
function tmmc:new_room()
    speedNow = tmmc.speedmin
end
function tmmc:find_slot()
    local machines = {}
    local slots = Isaac.FindByType(6, -1, -1, false, false)
    for _, slot in ipairs(slots) do
        if tmmc.enable[slot.Variant] then
            table.insert(machines, slot)
        end
    end
    return machines
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
function tmmc:step()
    if Game():GetRoom():IsClear() then
        local machines = tmmc:find_slot()
        if #machines > 0 then
            local timeplus = 0
            local count = 1
            speedAccum = speedAccum + math.max(0, speedNow)
            while speedAccum > 1 do
                speedAccum = speedAccum - 1
                timeplus = timeplus + 1
                count = count + 1
            end
            local isTouched = false
            local accelerated = false
            for i = 1, Game():GetNumPlayers() do
                local player = Isaac.GetPlayer(i)
                for _, slot in ipairs(machines) do
                    if player.Position:Distance(slot.Position) < (player.Size + slot.Size) then
                        --invincibility from an effect (The Chariot / Power Pill / Unicorn) has no
                        --damage cooldown, unlike post-hit i-frames
                        local effect_invinc = player:GetDamageCooldown() <= 0 and player:HasInvincibility()
                        --keep health-taking machines at vanilla speed when the next hit could
                        --kill (player needs real time to walk away), and during effect
                        --invincibility (never burn the buff under their feet, and no
                        --faster-than-vanilla free donations either)
                        local danger = health_machine[slot.Variant]
                            and (tmmc:hp_halves(player) <= tmmc:machine_cost(slot.Variant) or effect_invinc)
                        if not danger then
                            isTouched = true
                            accelerated = true
                            local dx = player.Position.X - slot.Position.X
                            local dy = player.Position.Y - slot.Position.Y
                            if math.abs(dx) < math.max(5, 6 * player.MoveSpeed) then
                                if ((Input.IsActionPressed(ButtonAction.ACTION_UP, player.ControllerIndex) and dy > 0) or (Input.IsActionPressed(ButtonAction.ACTION_DOWN, player.ControllerIndex) and dy < 0))
                                    and (not Input.IsActionPressed(ButtonAction.ACTION_RIGHT, player.ControllerIndex)) and (not Input.IsActionPressed(ButtonAction.ACTION_LEFT, player.ControllerIndex)) then
                                    player.Position = Vector(player.Position.X - dx / 2, player.Position.Y + dy / math.abs(dy) * (player.Size + slot.Size - math.abs(dy)) * (player.MoveSpeed + speedNow) / 2)
                                else
                                end
                            end
                            for _ = 1, count do
                                slot:Update()
                                if not effect_invinc then
                                    local oldPosition = player.Position
                                    player:Update()
                                    player.Position = oldPosition
                                    if health_machine[slot.Variant] and player:GetDamageCooldown() > 0
                                        and tmmc:hp_halves(player) > tmmc:machine_cost(slot.Variant) then
                                        oldPosition = player.Position
                                        player:Update()
                                        player.Position = oldPosition
                                    end
                                end
                            end
                        end
                        if tmmc.supressFly then
                            for _, e in ipairs(Isaac.FindByType(85, 0, 0)) do
                                e:Kill()
                            end
                            for _, e in ipairs(Isaac.FindByType(18, 0, 0)) do
                                e:Kill()
                            end
                        end
                        if tmmc.supressBomb then
                            for _, e in ipairs(Isaac.FindByType(4, -1, -1)) do
                                e:ToBomb():SetExplosionCountdown(100)
                                e.Velocity = -e.Velocity
                            end
                        end
                    end
                end
            end
            if isTouched then
                if speedNow <= tmmc.speedmax then
                    speedNow = speedNow + tmmc.speeda
                end
            else
                speedNow = tmmc.speedmin
            end
            if accelerated then
                Game().TimeCounter = Game().TimeCounter + timeplus
            end
        end
    end
end

tmmc:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, tmmc.new_room)
tmmc:AddCallback(ModCallbacks.MC_POST_UPDATE, tmmc.step)
