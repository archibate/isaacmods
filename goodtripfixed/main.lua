local hasoldgoodtrip = (gt and not gt.isgtfixed)
local _gt = RegisterMod("GoodTrip [Fixed]", 1)
gt = _gt
_gt.isgtfixed = true
local function show_warn(warnmsg)
    local warncounter = 300
    print(warnmsg)
    _gt:AddCallback(ModCallbacks.MC_POST_RENDER, function (_)
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
if hasoldgoodtrip then
    show_warn('WARNING: You must disable the old GoodTrip before using GoodTrip [Fixed]!')
end
if not REPENTANCE then
    show_warn('WARNING: This mod only works for Repentance!')
end
-------------------------------------------
--local test1 = -1
local player = Isaac.GetPlayer(0)
local level = Game():GetLevel()
local stage = level:GetStage()
local stageeffect = 0
local room = Game():GetRoom()
local crd = level:GetCurrentRoomDesc()
local crid = crd.GridIndex
local crsid = crd.SafeGridIndex
---
local sfx = SFXManager()
local mmp = Sprite()
mmp:Load("sprite/gt/minimap0.anm2", true)
local mic = Sprite()
mic:Load("sprite/gt/minimap_icons.anm2", true)
local gtui = Sprite()
gtui:Load("sprite/gt/gt_ui.anm2", true)
local select = Sprite()
select:Load("sprite/gt/gt_ui.anm2", true)
local cursor = Sprite()
cursor:Load("sprite/gt/cursor.anm2", true)
cursor:SetFrame("Idle", 0)
local trash = Sprite()
trash:Load("sprite/gt/gt_exit.anm2", true)
---
local mouse_pressed = {false, false, false, false, false}
local key = {ButtonAction.ACTION_SHOOTUP,ButtonAction.ACTION_SHOOTLEFT,ButtonAction.ACTION_SHOOTRIGHT,ButtonAction.ACTION_SHOOTDOWN}
local movkey = {ButtonAction.ACTION_UP,ButtonAction.ACTION_LEFT,ButtonAction.ACTION_RIGHT,ButtonAction.ACTION_DOWN}
local dir = {Vector(0, -1),Vector(-1, 0),Vector(1, 0),Vector(0, 1)}
local icon_room = {"RoomOutline", "RoomVisited", "RoomUnvisited", "RoomCurrent"}
local icon_flag = {"1_IconNormal", "IconShop", "3_IconError", "IconTreasureRoom", "IconBoss",
                  "IconMiniboss", "IconSecretRoom", "IconSuperSecretRoom", "IconArcade", "IconCurseRoom",
                  "IconAmbushRoom", "IconLibrary", "IconSacrificeRoom", "IconDevilRoom", "IconAngelRoom",
                  "16_IconDungeon", "17_IconBossRush", "IconIsaacsRoom", "IconBarrenRoom", "IconChestRoom",
                  "IconDiceRoom", "22_IconBlackMarket", "23_IconGreedExit","IconPlanetarium","TeleporterRoom","TeleporterRoom","27_SecretExit","28_Blue","IconUltraSecretRoom"}
                  --miniboss/sacrifice.3=nil--
                  --LKJWEDVBhard=IsaacsRoom--
local icon_flag2 = {"IconLockedRoom", "IconTreasureRoomGreed", "IconBossAmbushRoom","IconTreasureRoomRed","IconMirrorRoom", "IconWhiteFireRoom","IconTintSkullRoom","IconMinecartRoom","IconMineButtonRoom"}
local scpos = Vector(0, 0)
local grid_room = {}
local grid_room_mark = {}
local draw_room_id = {}
local draw_room_pos = {}
local draw_room_shape = {}
local draw_icon_pos = {Vector(0, 0),Vector(0, 0),Vector(0, 0),Vector(0,3),
                      Vector(0,3),Vector(4, 0),Vector(4, 0),Vector(4,3),
                      Vector(8, 7),Vector(0, 7),Vector(8, 0),Vector(0, 0),}
local neighlut = {
    {-1, 1, -13, 13},
    {-1, 1},
    {-13, 13},
    {-1, 1, -1+13, 1+13, -13, 13+13},
    {-13, 13+13},
    {-1, 2, -13, 13, -13+1, 13+1},
    {-1, 2},
    {-1, 2, -1+13, 2+13, -13, 13+13, -13+1, 13+13+1},
    {-1, 1, -13, -2+13, 1+13, 13+13-1, 13+13},
    {-13, -1, 1, -1+13, 2+13, 13+13, 13+13+1},
    {-13, -13+1, -1, 2, 13, 13+2, 13+13+1},
    {-13, -13+1, -1, 2, 13-1, 13+1, 13+13},
}
local ltroom = Vector(6, 6)
local rbroom = Vector(6, 6)
local mmp_pos0 = Vector(0, 0)
local mmp_ltpos_ = Vector(0, 0)
local mmp_ltpos = Vector(100, 100) --main
local mmp_rbpos_ = Vector(0, 0)
local mmp_rbpos = Vector(0, 0)
local d_pos = Vector(0, 0)
local mmp_pin = 0
local mouse_magnet = false
local mpos = Vector(0, 0)
local ui_timer = 0
local mmp_ctrl = false
local mmp_ctrl_pos = Vector(0, 0)
local last_mpos = Vector(0, 0)
local mouse_moved = false --physical mouse motion this frame (tracked every frame in step)
local kb_active = false --keyboard is the active map-cursor device (persists across TAB sessions)
local mouse_in_ui = false
local mmp_1step_tp = false
local mmp_1step_mgid = -1
--
local tele_maze = false
local secret_pre_room_id = {}
local prep_alarm = false
local n_room_num = 0

----
local gtconfig = {
    KeyboardMapEnable = true, --An extra minimap for controller or keyboard. true = enable. false = disable.
    FastRestartEnable = true, --true = enable / false = disable. !Press TAB+R to FAST RESTART!
    FollowCurseOfLost = true, --true = enable / false = disable. cannot use goodtrip in curse of lost
    TeleportAnimation = false, --true = play / false = don't play
    QuicklyOneRoomMove = false, --true = enable / false = disable. quickly move one entire room by TAB+ASWD
    AllowNeighborRoom = true,  --true = enable / false = disable. allow move to uncleaned neighbor room
    AllowBookmarking = true,  --true = enable / false = disable. allow tag bookmarks for rooms using TAB+0~9
    LastRoomShortcut = true,  --true = enable / false = disable. allow TAB+Z to go back to last visited room
    FastTransition = false,  --change room even faster without animation
    NoShootWhenClick = true,  --disable mouse click shooting when holding Tab
    -- AllowRightClick = false,  --mouse right click on bigmap to teleport
    FasterCursorMove = false,  --move cursor faster in keyboard minimap by press arrow keys once instead of having to hold them
    DangerCautionCompat = true,  --weather to work with my other mod 'Dangerous room! Caution' by indicate dangerous room by colors
    MinimapAPICompat = false,  --master switch for MinimapAPI integration (FairTripTime needs this); off by default for low-end machines
    FairTripTime = true,  --weather to incur fair time according to distance
    ShowSpecialIcons = true,  --show icons on room that have mirror, white fireplace, minecart, mine button, or tinted skull
    -- ShowDoorsAllowed = false,  --show doors allowed for secret rooms
    -- DebugMod = false,  --testonly.
    ControllerAlternateZ = nil,  --replacement for Z in the TAB+Z last room shortcut
    ControllerAlternateR = nil,  --replacement for R in the TAB+R restart shortcut
    MinimapScale = 10,  --keyboard minimap size, 5 = 0.5x .. 10 = 1.0x .. 25 = 2.5x
}
----
local mmsc = 1.0 --keyboard minimap scale factor (gtconfig.MinimapScale / 10)
local function update_mmscale()
    mmsc = (gtconfig.MinimapScale or 10) / 10
    mmp.Scale = Vector(mmsc, mmsc)
    mic.Scale = Vector(mmsc, mmsc)
    gtui.Scale = Vector(mmsc, mmsc)
    select.Scale = Vector(mmsc, mmsc)
    cursor.Scale = Vector(mmsc, mmsc)
end
update_mmscale()
local function cycle_mmscale() --zoom button: x1.0 -> x1.5 -> x2.0 -> x1.0
    local cur = gtconfig.MinimapScale or 10
    if cur < 15 then
        gtconfig.MinimapScale = 15
    elseif cur < 20 then
        gtconfig.MinimapScale = 20
    else
        gtconfig.MinimapScale = 10
    end
    update_mmscale()
    prep_alarm = true
end
----
local hudoffset = Options.HUDOffset * 10  --need your real hudoffset of game [0,10]
local minimapoffx = 0
local minimapoffy = 0
local debug = false
local tele_cd = 0
local bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99} -- press TAB+1~9 to mark or switch to, TAB+0 to clear all marks
-------------------------------
---configs---
if ModConfigMenu then
    local oldcfgdatas = nil
    if ModConfigMenu.GetCategoryIDByName("GoodTrip [Fixed]") ~= nil then
        print('GoodTrip [Fixed] is reloading ModConfigMenu options')
        ModConfigMenu.RemoveCategory("GoodTrip [Fixed]")
    end
    for _, info in ipairs({
        { "KeyboardMapEnable", "Teleport using TAB + arrow keys" },
        { "FollowCurseOfLost", "Disable GoodTrip on curse of lost" },
        { "TeleportAnimation", "Play cool animation on teleport" },
        { "QuicklyOneRoomMove", "Quickly teleport using TAB + ASWD" },
        { "AllowNeighborRoom", "Allow moving into uncleaned neighbor room" },
        { "AllowBookmarking", "Allow adding bookmarks for rooms via TAB + 1~9" },
        { "LastRoomShortcut", "Allow teleport back to last room via TAB + Z" },
        { "NoShootWhenClick", "Disable shoot when teleporting via TAB + Click" },
        { "FasterCursorMove", "Move cursor faster in keyboard minimap by press arrow keys once instead of having to hold them" },

        { "ShowSpecialIcons", "Show an icon on room that have mirror, white fireplace, minecart, mine button, or tinted skull" },
        { "DangerCautionCompat", "weather to work with my other mod 'Dangerous room! Caution' (if detected) by indicate dangerous room by colors" },
        { "MinimapAPICompat", "Master switch for MinimapAPI integration, needed by FairTripTime (off by default)" },
        { "FairTripTime", "Fairly increase game time according to player move speed and distance (requires MinimapAPI and MinimapAPICompat on)" },
        { "FastTransition", "Even faster transition without animation" },
    }) do
        ModConfigMenu.AddSetting(
          "GoodTrip [Fixed]", nil,
          {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
              return gtconfig[info[1]]
            end,
            Display = function()
              return info[1] .. ": " .. (gtconfig[info[1]] and "on" or "off")
            end,
            OnChange = function(b)
              gtconfig[info[1]] = b
            end,
            Info = { info[2] },
          }
        )
    end
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", nil,
      {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = 5,
        Maximum = 1000,
        Default = 100,
        CurrentSetting = function()
          return mmp_ltpos.X
        end,
        Display = function()
          return "TopLeftX: " .. tostring(math.floor(mmp_ltpos.X))
        end,
        OnChange = function(b)
          mmp_ltpos.X = b
        end,
        Info = { "Keyboard minimap top-left X coordinate" },
      }
    )
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", nil,
      {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = 14,
        Maximum = 1000,
        Default = 100,
        CurrentSetting = function()
          return mmp_ltpos.Y
        end,
        Display = function()
          return "TopLeftY: " .. tostring(math.floor(mmp_ltpos.Y))
        end,
        OnChange = function(b)
          mmp_ltpos.Y = b
        end,
        Info = { "Keyboard minimap top-left Y coordinate" },
      }
    )
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", nil,
      {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = 5,
        Maximum = 25,
        Default = 10,
        CurrentSetting = function()
          return gtconfig.MinimapScale
        end,
        Display = function()
          return ("MinimapScale: x%.1f"):format((gtconfig.MinimapScale or 10) / 10)
        end,
        OnChange = function(b)
          gtconfig.MinimapScale = b
          update_mmscale()
          prep_alarm = true
        end,
        Info = { "Keyboard minimap size, x0.5 (tiny) to x1.0 (original) up to x2.5" },
      }
    )
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", nil,
      {
        Type = ModConfigMenu.OptionType.KEYBIND_CONTROLLER,
        CurrentSetting = function()
          return gtconfig.ControllerAlternateZ
        end,
        Display = function()
          return "ControllerAlternateZ: " .. (
                    gtconfig.ControllerAlternateZ and
                    InputHelper.ControllerToString[gtconfig.ControllerAlternateZ]
                    or 'None'
                )
        end,
        OnChange = function(b)
          gtconfig.ControllerAlternateZ = b
        end,
            PopupGfx = ModConfigMenu.PopupGfx.WIDE_SMALL,
            PopupWidth = 280,
            Popup = function()
                return "Press a button on your controller to change this setting."
            end,
        Info = { "(For controller users only) we have TAB + Z to teleport to last room, which button on the controller would act as Z?" },
      }
    )
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", nil,
      {
        Type = ModConfigMenu.OptionType.KEYBIND_CONTROLLER,
        CurrentSetting = function()
          return gtconfig.ControllerAlternateR
        end,
        Display = function()
          return "ControllerAlternateR: " .. (
                    gtconfig.ControllerAlternateR and
                    InputHelper.ControllerToString[gtconfig.ControllerAlternateR]
                    or 'None'
                )
        end,
        OnChange = function(b)
          gtconfig.ControllerAlternateR = b
        end,
            PopupGfx = ModConfigMenu.PopupGfx.WIDE_SMALL,
            PopupWidth = 280,
            Popup = function()
                return "Press a button on your controller to change this setting."
            end,
        Info = { "(For controller users only) we have TAB + R to fast restart, which button on the controller would act as R?" },
      }
    )
    _gt:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContined)
        if _gt:HasData() then
            local dat = _gt:LoadData()
            oldcfgdatas = dat
            local json = require('json')
            local cfg = json.decode(dat)
            for k, v in pairs(cfg) do
                gtconfig[k] = v
            end
            mmp_ltpos = Vector(gtconfig.TopLeftX or 100, gtconfig.TopLeftY or 100)
            update_mmscale()
            -- mmp_pos0 = mmp_ltpos - mmp_ltpos_
            -- mmp_rbpos = mmp_pos0 + mmp_rbpos_
        end
    end)
    _gt:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
        local json = require('json')
        gtconfig.TopLeftX = mmp_ltpos.X
        gtconfig.TopLeftY = mmp_ltpos.Y
        local dat = json.encode(gtconfig)
        if not oldcfgdatas or dat ~= oldcfgdatas then
            oldcfgdatas = dat
            _gt:SaveData(dat)
        end
    end)
end
---functions---
function _gt:check_pos_en_box(pos,ltpos,rbpos)
  if pos.X > ltpos.X and pos.X < rbpos.X and pos.Y > ltpos.Y and pos.Y < rbpos.Y then
    return true
  else
    return false
  end
end
--
function _gt:IsMouseBtnTriggered(m)
    if Input.IsMouseBtnPressed(m) then
      if not mouse_pressed[m+1] then
        mouse_pressed[m+1] = true
        return true
      end
    else
      mouse_pressed[m+1] = false
    end
    return false
end
--
function _gt:check_room_open()
    local door = nil
    for i =0, 7 do
      door = room:GetDoor(i)
      if door then
        if door:IsOpen() then
          return true
        end
      end
    end
    return false
end
--
function _gt:check_neigh_connected(trd, cond)
    local tid = trd.SafeGridIndex
    if (trd.DisplayFlags & 1) ~= 0 then
      if (trd.VisitedCount == 0 or not trd.Clear) and
        trd.Data.Type ~= 1 and trd.Data.Type ~= 5 and
        trd.Data.Type ~= 6 and trd.Data.Type ~= 13 and
        not (((stage == 1 and level:GetStageType() < StageType.STAGETYPE_REPENTANCE) or room:IsMirrorWorld())
                and ((not Game():IsGreedMode() and trd.Data.Type == 4) or trd.Data.Type == 2)) then --free: stage-1 normal floor, or Downpour/Dross mirror world
        return false
      end
      local function check_grid(id)
        if id <= 0 or id >= 169 then
          return false
        end
        local rd = grid_room[id]
        return rd ~= nil and cond(rd)
      end
      local near_room = {check_grid(tid-13), check_grid(tid+13), check_grid(tid-1), check_grid(tid+1)}
      if stage == 12 and trd.Data.Type == 5 and trd.Data.Shape > 3 then
        --void bossrooms--type4=1x2/type6=2x1/type8=2x2=Delirium
        if (near_room[1] and near_room[4])
          or (near_room[2] and near_room[3])
          or (trd.Data.Shape == 6 and (near_room[1] or near_room[4]))
          or (trd.Data.Shape == 4 and (near_room[2] or near_room[3]))
        then
          return true
        end
      else
        --LTLonly
        -- if trd.Data.Shape == RoomShape.ROOMSHAPE_LTL
        --             and trd.Data.SafeGridIndex ~= trd.Data.GridIndex
        --             and trd.Data.GridIndex == tid then
        --   return false
        -- end
        --normal
        if near_room[1] or near_room[4] or near_room[2] or near_room[3] then
          return true
        end
        --specialshape
        for _, off in ipairs(neighlut[trd.Data.Shape]) do
            if check_grid(tid + off) then
                -- print(tid, off)
                return true
            end
        end
      end
    end
    return false
end
--
function _gt:check_teleble(gid)
    --Isaac.RenderText("check_teleble_running", 50, 50, 1, 1, 1, 1)--test
    if gid == -99 or (gtconfig.FollowCurseOfLost and level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0) then
      return false
    elseif debug and grid_room[gid] then
      return true
    end
    --check_current_room--
    local cid = crd.SafeGridIndex
    if grid_room[cid] == nil or not crd.Clear then --inmap/cleaned/  --(romved)momboss
      return false
    elseif (crd.Data.Type == 6 or crd.Data.Type == 11) then --miniboss/challengeroom
      if not _gt:check_room_open() then
        return false
      end
    end
    ----
    if gid == false then return true end --skip targetroom check
    --check_target_room--
    -- print('ct', grid_room[gid], gid)
    if grid_room[gid] == nil then
      return false
    else
      local trd = grid_room[gid]
      if trd.ListIndex == crd.ListIndex then --notcurrent
        return false
      end
      if not gtconfig.AllowNeighborRoom then
        if trd.VisitedCount == 0 or not trd.Clear then --notvisited/notcleaned
          return false
        end
        return true
      else
        -- print(stage, Game():IsGreedMode(), trd.Data.Type)
        if _gt:check_neigh_connected(trd, function(rd)
            return (rd.DisplayFlags & 1 ~= 0) and rd.VisitedCount > 0 and rd.Clear
        end) then
            return true
        end
      end
      return false
    end
    --[[
    if (crd.Data.Type == 7 and grid_room[secret_pre_room_id[crid] ].VisitedCount == 0)
      or (grid_room[gid].Data.Type == 7 and not grid_room[secret_pre_room_id[gid] ].VisitedCount == 0)
    then
      return
    end
    ]]--todo---??? cannot understand
    --
    return true
end
--
function _gt:hurt(n)
  --local ent = Isaac.Spawn(EntityType.ENTITY_SLOT,1,Vector(0, 0), Vector(0, 0),nil,0,Game():GetRoom():GetSpawnSeed())
  player:TakeDamage(n, DamageFlag.DAMAGE_CURSED_DOOR | DamageFlag.DAMAGE_NO_PENALTIES, EntityRef(player), 0)
  --player:UseActiveItem(326, false, false, false, false, 0)
end
--
function _gt:tele_failed()
  sfx:Play(187, 0.5, 0, false, 1)
end
--
function _gt:check_curse_room(gid)
    if debug then return end
    ----
    local trd = grid_room[gid]
    if crd.Data.Type == 10 then --from curse room
      if secret_pre_room_id[crid] and (secret_pre_room_id[crid] == gid or (secret_pre_room_id[secret_pre_room_id[crid]] and secret_pre_room_id[secret_pre_room_id[crid]] ~= crid)) then
        return
      end
      _gt:hurt(1)
    elseif trd.Data.Type == 10 and not player:IsFlying() then --target to curse room
      if secret_pre_room_id[gid] and (secret_pre_room_id[gid] == crid or (secret_pre_room_id[secret_pre_room_id[gid]] and secret_pre_room_id[secret_pre_room_id[gid]] ~= gid)) then
        return
      end
      _gt:hurt(1)
    end
end
--
function _gt:teleport_to_grid_index(gid) ----core
    --
    for _,en in pairs(Isaac.GetRoomEntities()) do
			if en.Type == 867 then
        _gt:tele_failed()
        return
			end
		end
    --
    if crd.Data.Name == "Mom" or crd.Data.Name == "Ultra Greed" then
      _gt:tele_failed()
      return
    elseif grid_room[gid].Data.Type == 11 and not grid_room[gid].ChallengeDone then
      if stage%2 == 0 and stage ~= 10 then
        if player:GetHearts()+player:GetSoulHearts()+ player:GetBlackHearts() > 2 then
          _gt:tele_failed()
          return
        end
      else
        if player:GetHearts() + player:GetSoulHearts() + player:GetBlackHearts() < player:GetMaxHearts() then
          _gt:tele_failed()
          return
        end
      end
    end
    --
    local flat = player:HasTrinket(151) or player:HasCollectible(276) or player:HasCollectible(663)----has flat file[rep]---- 276 = Isaac's Heart; 663=Tooth and Nail
    --
    if not flat then
      _gt:check_curse_room(gid)
    end
    --
    level.EnterDoor = -1
    level.LeaveDoor = -1
    --
    --
    if level:GetCurses() & LevelCurse.CURSE_OF_MAZE ~= 0 then
      level:RemoveCurses(LevelCurse.CURSE_OF_MAZE)
      tele_maze = true
    end

    local dist = 0
    if gtconfig.FairTripTime and gtconfig.MinimapAPICompat and MinimapAPI then
        local curRoom = MinimapAPI:GetCurrentRoom()
        if curRoom then
          dist = _gt:fair_trip(curRoom.Descriptor.SafeGridIndex, gid)
          if dist == 999 then
            _gt:tele_failed()
            return
          end
        end
    end

    if crd.Data.Type == 7 and secret_pre_room_id[crid] then -- from secret room (skip if antechamber never recorded)
      if grid_room[secret_pre_room_id[crid]].ListIndex == grid_room[gid].ListIndex then
        gid = secret_pre_room_id[crid]
      else
        --check_curse_room
        if grid_room[gid].Data.Type == 10 and secret_pre_room_id[gid] and secret_pre_room_id[gid] == crid then
          --do notheing-- not hurt, not change
        else
          if grid_room[secret_pre_room_id[crid]].Data.Type == 10 and not flat then
            _gt:hurt(1)
          end
          Game():ChangeRoom(secret_pre_room_id[crid],-1)
        end
      end
    end
    if grid_room[gid].Data.Type == 7 then --target to secret room
      if secret_pre_room_id[gid] then
        if grid_room[secret_pre_room_id[gid]].ListIndex == grid_room[crid].ListIndex then
          if grid_room[crid].Data.Shape > 3 then
            Game():ChangeRoom(secret_pre_room_id[gid],-1)
          end
        else
          --check_curse_room
          if crd.Data.Type == 10 and secret_pre_room_id[crid] and secret_pre_room_id[crid] == gid then
            --do notheing-- not hurt, not change
          else
            if grid_room[secret_pre_room_id[gid]].Data.Type == 10 and not player:IsFlying() and not flat then
              _gt:hurt(1)
            end
            Game():ChangeRoom(secret_pre_room_id[gid],-1)
          end
        end
      else
        --do nothing
      end
    end
    --
    if debug then
      Game():ChangeRoom(gid,-1)
    else
      --Game():ChangeRoom(gid,-1)
        if dist ~= 0 then
          local speed = player.MoveSpeed
          local addTime = math.floor((60.0*dist/speed)+0.5)
          --for some stupid fucking reason, the boss rush time check goes off of TimeCounter, but the Hush time check doesn't... 
          -- Game().BlueWombParTime = math.max(Game().BlueWombParTime - addTime, 0)
          ----------------------------------------------------------------------
          Game().TimeCounter = Game().TimeCounter + addTime
        end
      Game():StartRoomTransition(gid, Direction.NO_DIRECTION, gtconfig.TeleportAnimation,player,-1)
      tele_cd = 45
    end
    -- print('goto', gid)
    -- local cid = crd.SafeGridIndex
    if gtconfig.FastTransition or debug then
      Game():ChangeRoom(gid,-1)
      Game():GetRoom():PlayMusic()
      mmp_ctrl = true
      local gx = crsid % 13
      local gy = (crsid - gx)/ 13
        if mmp_1step_mgid >= 0 then
            gx = mmp_1step_mgid % 13
            gy = (mmp_1step_mgid - gx)/ 13
            mmp_1step_mgid = -2
        end
      mmp_ctrl_pos = mmp_pos0 + Vector(gx * 8 + 6, gy * 7 + 5) * mmsc
      return
    end
    local tele_anime
    local tele_dir
    if gtconfig.TeleportAnimation then
      tele_anime = 3
      tele_dir = Direction.NO_DIRECTION
    else
      if gtconfig.FastTransition then
        tele_anime = 0
      else
        tele_anime = 1
      end
      tele_dir = Direction.NO_DIRECTION
    end
    Game():StartRoomTransition(gid, tele_dir, tele_anime,player,-1)
    tele_cd = 45
    if not gtconfig.TeleportAnimation then tele_cd = 10 end
    if debug or gtconfig.FastTransition then tele_cd = 1 end
end
--
function _gt:get_pos_grid_index(pos)
    if (not gtconfig.FollowCurseOfLost and level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0) then
      return -99
    end
    local rtr = _gt:get_corner_room(2)
    -----RTmap----- 
    local ltx = scpos.X - (rtr.X + 1) * 17 - 5 - hudoffset * 2.4 - minimapoffx --withrighttopmap
    local lty = - (rtr.Y) * 15 + 5 + hudoffset * 1.3 + minimapoffy --whthrighttopmap
    if pos.X > ltx and pos.Y > lty and pos.X < ltx + 222 and pos.Y < lty + 196 then
        local px = pos.X
        --repentance stage 2c:mirror--
        if room:IsMirrorWorld() then
          local ltr = _gt:get_corner_room(3)
          local rtx = scpos.X - (ltr.X + 1) * 17 - 5 - hudoffset * 2.4 - minimapoffx --withleftbottommap
          -- print(rtr.X, ltr.X) -- 3 -> 9; 4 -> 9; 5 -> 9; 6 -> 7; 7 -> 5
          -- Repentance+ re-anchored the corner map: +27, vs -32 on old Repentance
          px = ltx + (rtx - px) + (9 - math.max(0, rtr.X - ltr.X - 5) * 2)*17 + (REPENTANCE_PLUS and 27 or -32)
        end
      local mgid = math.floor((px - ltx)/ 17) + math.floor((pos.Y - lty)/ 15) * 13
      return mgid
    else
      return -99
    end
end
--
function _gt:get_pos_grid_index_mmp(pos)
    -----minimap-----
    if _gt:check_pos_en_box(pos,mmp_ltpos + Vector(1, 1) * mmsc, mmp_rbpos + Vector(11, 10) * mmsc) then
      local cx = math.floor((pos.X - mmp_pos0.X - 2 * mmsc)/ (8 * mmsc))
      local cy = math.floor((pos.Y - mmp_pos0.Y - 2 * mmsc)/ (7 * mmsc))
      if cx < 0 or cx > 12 or cy < 0 or cy > 12 then
        --outside the 13x13 grid: without this, edge pixels (and the 3x3
        --padding cells) would wrap around to a room on another row
        return -99
      end
      return cx + cy * 13
    else
      return -99
    end
end
--
function _gt:get_grid_room()
    grid_room = {}
    grid_room_mark = {}
    local all_room = level:GetRooms()
    for i = 0, all_room.Size do
      local des = all_room:Get(i)
      if des then
        local gid = des.GridIndex
        if gtconfig.DangerCautionCompat and DangerCaution then
            local danger = DangerCaution:roomDangerFlags(des)
            if danger ~= 0 then
                grid_room_mark[des.SafeGridIndex] = DangerCaution:dangerFlagToColor(danger)
            end
        end
        for jx=0, 1 do
          for jy=0, 1 do
            local tgid = gid + jx + jy * 13
            local tdes = level:GetRoomByIdx(tgid,-1)
            if tdes.ListIndex == des.ListIndex then
              grid_room[tgid] = des
            end
          end
        end
      end
    end
end
--
function _gt:get_corner_room(num)
    local corner_room = Vector(6, 6)
    local fx = {1, -1, 1, -1}
    local fy = {1, 1, -1, -1}
    local ffx = fx[num]
    local ffy = fy[num]
    ----
    for i = 6 - 6 * ffx, 6 - ffx, ffx do
      for j = 0, 12 do
        if grid_room[i+j*13] then
          if grid_room[i+j*13].DisplayFlags > 0 then
            corner_room.X = i
            break
          end
        end
      end
      if corner_room.X ~= 6 then
        break
      end
    end
    ----
    for j = 6 - 6 * ffy, 6 - ffy, ffy do
      for i = 0, 12 do
        if grid_room[i+j*13] then
          if grid_room[i+j*13].DisplayFlags > 0 then
            corner_room.Y = j
            break
          end
        end
      end
      if corner_room.Y ~= 6 then
        break
      end
    end
    ----
    return corner_room
end
--
function _gt:pre_secret_room()
  local door = nil
  for i =0, 7 do
    door = room:GetDoor(i)
    if door then
      local id = door.TargetRoomIndex
      if door.Desc.Variant == 8 then
        if door.TargetRoomType == 10 then
          if not secret_pre_room_id[crid] then
            secret_pre_room_id[crid] = id
          end
        elseif grid_room[id].VisitedCount == 0 then
          secret_pre_room_id[crid] = id
        else
          secret_pre_room_id[crid] = id
          break
        end
      end
    end
  end
end
--
function _gt:pre_secret_curse_room()
  local door = nil
  for i =0, 7 do
    door = room:GetDoor(i)
    if door then
      local id = door.TargetRoomIndex
      if door.Desc.Variant == 8 then
        if door.TargetRoomType == 7 then
          if secret_pre_room_id[id] and secret_pre_room_id[id] ~= crid then
            secret_pre_room_id[crid] = id
            break
          else
            secret_pre_room_id[crid] = id
          end
        end
      end
    end
  end
end
--
---draw works---
function _gt:print_center_map()
    --test useing--
    local cp = scpos / 2
    for i = 0, 12 do
      for j = 0, 12 do
        if grid_room[i * 13 + j] == nil then
          Isaac.RenderText(0, cp.X + 17 * (j-6) - 2, cp.Y + 15 * (i-6) - 5, 1, 1, 1, 0.1)
        else
          local color = {}
          if crd.ListIndex == grid_room[i * 13 + j].ListIndex then
            color = {1 , 0.5 , 0.5 , 1}
          elseif grid_room[i * 13 + j].VisitedCount > 0 and grid_room[i * 13 + j].Clear then
            color = {1 , 1 , 1 , 1}
          elseif grid_room[i * 13 + j].DisplayFlags > 0 then
            color = {1 , 1 , 1 , 0.5}
          else
            color = {0.5 , 0.5 , 1 , 0.5}
          end
          Isaac.RenderText(grid_room[i * 13 + j].Data.Type.."/"..grid_room[i * 13 + j].DisplayFlags, cp.X + 17 * (j-6) - 3, cp.Y + 15 * (i-6) - 6, color[1] ,color[2] ,color[3] ,color[4])
        end
      end
    end
end
--
function _gt:prep_minimap()
    --Isaac.RenderText("prep_minimap_running", 50, 50, 1, 1, 1, 1)--test
    draw_room_id = {}
    draw_room_pos = {}
    draw_room_shape = {}
    ----
    ltroom = _gt:get_corner_room(1)
    rbroom = _gt:get_corner_room(4)
    --minimum 3x3 window (the top bar must fit the pin + zoom buttons);
    --split the padding to both sides so the rooms sit centered
    local padx = 2 - (rbroom.X - ltroom.X)
    if padx > 0 then
      ltroom.X = ltroom.X - math.floor(padx / 2)
      rbroom.X = rbroom.X + math.ceil(padx / 2)
    end
    local pady = 2 - (rbroom.Y - ltroom.Y)
    if pady > 0 then
      ltroom.Y = ltroom.Y - math.floor(pady / 2)
      rbroom.Y = rbroom.Y + math.ceil(pady / 2)
    end
    mmp_ltpos_ = Vector(ltroom.X * 8, ltroom.Y * 7) * mmsc -- + Vector(-4, -4)
    mmp_rbpos_ = Vector(rbroom.X * 8, rbroom.Y * 7) * mmsc -- + Vector(4, 4)
    mmp_pos0 = mmp_ltpos - mmp_ltpos_
    mmp_rbpos = mmp_pos0 + mmp_rbpos_
    ---ctrl pos prep---
    if mmp_ctrl then
      if mmp_1step_mgid == -2 then
      else
        local gx = crsid % 13
        local gy = (crsid - gx)/ 13
        -- print('writemgpos')
        mmp_ctrl_pos = mmp_pos0 + Vector(gx * 8 + 6, gy * 7 + 5) * mmsc
      end
    end
    ---draw prep---
    for i = 0, 12 do
      for j = 0, 12 do
        local drd = grid_room[i * 13 + j]
        if drd then
          if drd.DisplayFlags > 0 then
            if drd.Data.Type == 5 and drd.Data.Shape > 3 and stage == 12 then
              --void bossrooms--type4=1x2/type6=2x1/type8=2x2=Delirium
              local near_room = {grid_room[i * 13 + j - 13] ~= nil, grid_room[i * 13 + j - 1] and j > 0, grid_room[i * 13 + j + 1] and j < 12, grid_room[i * 13 + j + 13] ~= nil}
              if (near_room[1] and near_room[4])
                or (near_room[2] and near_room[3])
                or (drd.Data.Shape == 6 and (near_room[1] or near_room[4]))
                or (drd.Data.Shape == 4 and (near_room[2] or near_room[3]))
              then
                table.insert(draw_room_id, i * 13 + j)
                table.insert(draw_room_shape, 1)
                table.insert(draw_room_pos, Vector(mmp_pos0.X + 8 * j * mmsc, mmp_pos0.Y + 7 * i * mmsc))
              end
              --else draw nothing
            elseif drd.Data.Shape == RoomShape.ROOMSHAPE_LTL then
              --LTLonly
              table.insert(draw_room_id, i * 13 + j)
              table.insert(draw_room_shape, drd.Data.Shape)
              table.insert(draw_room_pos, Vector(mmp_pos0.X + 8 * (j - 1) * mmsc, mmp_pos0.Y + 7 * i * mmsc))
              --
            else
              --normal
              table.insert(draw_room_id, i * 13 + j)
              table.insert(draw_room_shape, drd.Data.Shape)
              table.insert(draw_room_pos, Vector(mmp_pos0.X + 8 * j * mmsc, mmp_pos0.Y + 7 * i * mmsc))
              --
            end
          end
        end
      end
    end
    --repentance stage 2c:mirror--
    if room:IsMirrorWorld() then
      for i = 1, #draw_room_pos do
        local p = draw_room_pos[i]
        p.X = mmp_pos0.X + 8 * ltroom.X * mmsc + (mmp_pos0.X + 8 * rbroom.X * mmsc - p.X)
        local s = draw_room_shape[i]
        local need = true
        if s == RoomShape.ROOMSHAPE_LTL then
          s = RoomShape.ROOMSHAPE_LTR
        elseif s == RoomShape.ROOMSHAPE_LBL then
          s = RoomShape.ROOMSHAPE_LBR
        elseif s == RoomShape.ROOMSHAPE_LTR then
          s = RoomShape.ROOMSHAPE_LTL
        elseif s == RoomShape.ROOMSHAPE_LBR then
          s = RoomShape.ROOMSHAPE_LBL
        elseif s ~= RoomShape.ROOMSHAPE_2x2
          and s ~= RoomShape.ROOMSHAPE_2x1
          and s ~= RoomShape.ROOMSHAPE_IIH then
          need = false
        end
        if need then
          p.X = p.X - 8 * mmsc
          draw_room_shape[i] = s
        end
        draw_room_pos[i] = p
      end
    end
end
--
function _gt:draw_minimap_ui()
    if not ((gtconfig.KeyboardMapEnable and _gt:check_teleble(false)) or debug) then -------return when gtconfig.KeyboardMapEnable disable & debug disable
      ui_timer = 0
      return
    elseif ui_timer < 10 then
      ui_timer = ui_timer + 1
    end
    ---draw ui---
    gtui:SetFrame("ui1", ui_timer)
    gtui:Render(Vector(mmp_ltpos.X, mmp_ltpos.Y), Vector(0, 0), Vector(0, 0))
    gtui:SetFrame("ui3", ui_timer)
    gtui:Render(Vector(mmp_rbpos.X, mmp_ltpos.Y), Vector(0, 0), Vector(0, 0))
    gtui:SetFrame("ui7", ui_timer)
    gtui:Render(Vector(mmp_ltpos.X, mmp_rbpos.Y), Vector(0, 0), Vector(0, 0))
    gtui:SetFrame("ui9", ui_timer)
    gtui:Render(Vector(mmp_rbpos.X, mmp_rbpos.Y), Vector(0, 0), Vector(0, 0))
    ---
    for i = ltroom.X, rbroom.X do
      gtui:SetFrame("ui2", ui_timer)
      gtui:Render(mmp_pos0 + Vector(i * 8, ltroom.Y * 7) * mmsc, Vector(0, 0), Vector(0, 0))
      gtui:SetFrame("ui8", ui_timer)
      gtui:Render(mmp_pos0 + Vector(i * 8, rbroom.Y * 7) * mmsc, Vector(0, 0), Vector(0, 0))
    end
    for j = ltroom.Y, rbroom.Y do
      gtui:SetFrame("ui4", ui_timer)
      gtui:Render(mmp_pos0 + Vector(ltroom.X * 8, j * 7) * mmsc, Vector(0, 0), Vector(0, 0))
      gtui:SetFrame("ui6", ui_timer)
      gtui:Render(mmp_pos0 + Vector(rbroom.X * 8, j * 7) * mmsc, Vector(0, 0), Vector(0, 0))
    end
    ---
    gtui:SetFrame("ui5", ui_timer)
    for i = ltroom.X, rbroom.X do
      for j = ltroom.Y, rbroom.Y do
        gtui:Render(mmp_pos0 + Vector(i * 8, j * 7) * mmsc, Vector(0, 0), Vector(0, 0))
      end
    end
    --pin--
    if mmp_pin == 1 then
      gtui:SetFrame("pin1", ui_timer)
    else
      gtui:SetFrame("pin0", ui_timer)
    end
    gtui:Render(mmp_ltpos, Vector(0, 0), Vector(0, 0))
    --zoom button--
    gtui:SetFrame("zoom", ui_timer)
    gtui:Render(mmp_ltpos + Vector(12, 0) * mmsc, Vector(0, 0), Vector(0, 0))
end
--
function _gt:draw_minimap()
    ---draw outline---
    mmp:SetFrame(icon_room[1], 0)
    for i = 1, #draw_room_id do
      local s = grid_room[draw_room_id[i]].Data.Shape
      if (not room:IsMirrorWorld() and s == RoomShape.ROOMSHAPE_LTL) or (room:IsMirrorWorld() and s >= RoomShape.ROOMSHAPE_2x1 and s ~= RoomShape.ROOMSHAPE_LTL) then
        mmp:Render(draw_room_pos[i] + Vector(8 * mmsc, 0), Vector(0, 0), Vector(0, 0))
      else
        mmp:Render(draw_room_pos[i], Vector(0, 0), Vector(0, 0))
      end
    end
    ---draw room&icon---
    for i = 1, #draw_room_id do
      local rd = grid_room[draw_room_id[i]]
      if rd.ListIndex < n_room_num then --and rd.Data.Type ~= 29 then
        local markclr = grid_room_mark[rd.SafeGridIndex]
        if markclr ~= nil then
            mmp.Color = Color(markclr.Red, markclr.Green, markclr.Blue, 1, 0, 0, 0)
        else
            mmp.Color = Color(1, 1, 1, 1, 0, 0, 0)
        end
      else
        mmp.Color = Color(1, 0.3, 0.3, 1, 0, 0, 0)
      end
      if rd.SafeGridIndex == draw_room_id[i] or (rd.Data.Type == 5 and stage == 12) then
        -----room
        if crd.ListIndex == rd.ListIndex then
          mmp:SetFrame(icon_room[4], draw_room_shape[i] - 1)
          mmp:Render(draw_room_pos[i], Vector(0, 0), Vector(0, 0))
        elseif rd.VisitedCount > 0 and rd.Clear then
          mmp:SetFrame(icon_room[2], draw_room_shape[i] - 1)
          mmp:Render(draw_room_pos[i], Vector(0, 0), Vector(0, 0))
        elseif rd.Data.Type ~= 7 and rd.Data.Type ~= 8 then
          mmp:SetFrame(icon_room[3], draw_room_shape[i] - 1)
          mmp:Render(draw_room_pos[i], Vector(0, 0), Vector(0, 0))
        end
        -- if gtconfig.ShowDoorsAllowed then
        --     for j = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        --         if rd.Data.Doors & (1 << j) ~= 0 then
        --         end
        --     end
        -- end
        -----icon
        mmp.Color = Color(1, 1, 1, 1, 0, 0, 0)
        if rd.Data.Type > 1 and rd.DisplayFlags > 1 and (rd.DisplayFlags ~= 3 or (rd.Data.Type ~= 6 and rd.Data.Type ~= 13)) and rd.Data.Type ~= 23 then
          if (rd.Data.Type == 2 or rd.Data.Type == 12 or (rd.Data.Type > 17 and rd.Data.Type < 22)) and rd.DisplayFlags == 3 then
            mic:SetFrame(icon_flag2[1], 0)
          elseif rd.Data.Type == 4 then
            if Game():IsGreedMode() and rd.GridIndex == 98 then
              mic:SetFrame(icon_flag2[2], 0)
            elseif player:HasTrinket(146) then
              mic:SetFrame(icon_flag2[4], 0)
            else
              mic:SetFrame(icon_flag[4], 0)
            end
          elseif rd.Data.Type == 11 and stage%2 == 0 and stage ~= 10 then
            mic:SetFrame(icon_flag2[3], 0)
          else
            mic:SetFrame(icon_flag[rd.Data.Type], 0)
          end
          mic:Render(draw_room_pos[i] + draw_icon_pos[draw_room_shape[i]] * mmsc, Vector(0, 0), Vector(0, 0))
        elseif gtconfig.ShowSpecialIcons and rd.Data.Type == 1 then
          local iid = 0
          local spawns = rd.Data.Spawns
          if stageeffect == 1 then -- downpour
            for j = 0, spawns.Size - 1 do
                local e = spawns:Get(j):PickEntry(0)
                if e.Type == 970 and e.Variant == 2 then
                    iid = 5
                    break
                elseif e.Type == 33 and e.Variant == 4 then
                    iid = 6
                    break
                end
            end
          elseif stageeffect == 2 then -- mines
            for j = 0, spawns.Size - 1 do
                local e = spawns:Get(j):PickEntry(0)
                if e.Type == 965 and e.Variant == 10 then
                    iid = 8
                    break
                elseif e.Type == 4500 and e.Variant == 3 then
                    iid = 9
                end
            end
          elseif stageeffect == 3 then -- depths
            for j = 0, spawns.Size - 1 do
                local e = spawns:Get(j):PickEntry(0)
                if e.Type == 1008 then
                    iid = 7
                    break
                end
            end
          end
          if iid ~= 0 then
            mic:SetFrame(icon_flag2[iid], 0)
            mic:Render(draw_room_pos[i] + draw_icon_pos[draw_room_shape[i]] * mmsc, Vector(0, 0), Vector(0, 0))
          end
        end
      end
    end
    ---draw select---
    local checkid = nil
    if mmp_ctrl then
      checkid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
    else
      checkid = _gt:get_pos_grid_index_mmp(_gt:mirror_mmp_pos(mpos))
    end
    if grid_room[checkid] then
      local safecheckid = grid_room[checkid].SafeGridIndex
      for i = 1, #draw_room_id do
        if safecheckid == draw_room_id[i] then
          if _gt:check_teleble(checkid) then
            select:SetFrame("select", draw_room_shape[i])
          else
            select:SetFrame("select_false", draw_room_shape[i])
          end
          select:Render(draw_room_pos[i], Vector(0, 0), Vector(0, 0))
          break
        end
      end
    end
    ---draw cursor---
    if mmp_ctrl then
      cursor:Render(_gt:mirror_mmp_pos(mmp_ctrl_pos), Vector(0, 0), Vector(0, 0))
    end
end
---control & run---
function _gt:mmp_ctrl_move()
  local dif = {mmp_ctrl_pos.Y - mmp_ltpos.Y + 2 * mmsc, mmp_ctrl_pos.X - mmp_ltpos.X + 2 * mmsc, mmp_rbpos.X - mmp_ctrl_pos.X + 14 * mmsc, mmp_rbpos.Y - mmp_ctrl_pos.Y + 13 * mmsc}
    if room:IsMirrorWorld() then dif[2], dif[3] = dif[3], dif[2] end --X movement is mirrored, so left/right bound guards swap too
    for i = 1,4 do
      if gtconfig.QuicklyOneRoomMove then
        if Input.IsActionTriggered(movkey[i], player.ControllerIndex) and dif[i] > 0 then
          -- local s = room:GetRoomShape()
          mmp_ctrl_pos = mmp_ctrl_pos + _gt:mirror_mmp_dir(dir[i] * Vector(8, 7) * mmsc)
          local nmgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
          if _gt:check_teleble(nmgid) and tele_cd < 1 then
            mmp_1step_tp = true
            mmp_1step_mgid = nmgid
          end
        end
      end
      if gtconfig.FasterCursorMove then
        if Input.IsActionTriggered(key[i], player.ControllerIndex) and dif[i] > 0 then
          mmp_ctrl_pos = mmp_ctrl_pos + _gt:mirror_mmp_dir(dir[i]) * Vector(8, 7) * mmsc
        end
      else
        if Input.IsActionPressed(key[i], player.ControllerIndex) and dif[i] > 0 then
          mmp_ctrl_pos = mmp_ctrl_pos + _gt:mirror_mmp_dir(dir[i]) * mmsc
        end
      end
    end
end
--
function _gt:prep()
    if gtconfig.KeyboardMapEnable then
      _gt:prep_minimap()
    end
end
function _gt:player_shoot_cooldown()
    player:SetShootingCooldown(2)
    local twin = player:GetOtherTwin()
    if twin then
        twin:SetShootingCooldown(2)
    end
end
--
function _gt:tab_action()
    local cp = Isaac.WorldToRenderPosition(Vector(320,280))
    scpos = cp + cp
    --
    if gtconfig.FastRestartEnable and Input.IsButtonTriggered(Keyboard.KEY_R, player.ControllerIndex)
        or (gtconfig.ControllerAlternateR and Input.IsButtonTriggered(gtconfig.ControllerAlternateR, player.ControllerIndex)) then
      print('GoodTrip [Fixed] !!!FAST RESTARTING!!!')
      Isaac.ExecuteCommand("restart")
    end
    if gtconfig.QuicklyOneRoomMove and crd.Clear and player.ControlsCooldown < 2 then
      player.ControlsCooldown = player.ControlsCooldown + 1
    end
    --
    if (gtconfig.KeyboardMapEnable and _gt:check_teleble(false)) or debug then -------return when gtconfig.KeyboardMapEnable & debug disable
      if not (Input.IsActionPressed(ButtonAction.ACTION_UP,player.ControllerIndex)
          or Input.IsActionPressed(ButtonAction.ACTION_LEFT,player.ControllerIndex)
          or Input.IsActionPressed(ButtonAction.ACTION_RIGHT,player.ControllerIndex)
          or Input.IsActionPressed(ButtonAction.ACTION_DOWN,player.ControllerIndex)) or gtconfig.QuicklyOneRoomMove
      then
        local arrowdown = Input.IsActionPressed(key[1],player.ControllerIndex)
            or Input.IsActionPressed(key[2],player.ControllerIndex)
            or Input.IsActionPressed(key[3],player.ControllerIndex)
            or Input.IsActionPressed(key[4],player.ControllerIndex)
        local in_ui = _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-8, -18) * mmsc,mmp_rbpos + Vector(20, 20) * mmsc) --ui zone
        if arrowdown then --keyboard used: it becomes the active device
          kb_active = true
        elseif mouse_moved and in_ui then --mouse physically moved over the minimap: it takes over
          kb_active = false
        end
        if kb_active or not in_ui then --keyboard owns the cursor (show it at current room even if mouse rests on the widget), or mouse is away from the minimap
          if not mmp_ctrl then
            mmp_ctrl = true
            local gx = crsid % 13
            local gy = (crsid - gx)/ 13
            if mmp_1step_mgid >= 0 then
              gx = mmp_1step_mgid % 13
              gy = (mmp_1step_mgid - gx)/ 13
              mmp_1step_mgid = -2
            end
            mmp_ctrl_pos = mmp_pos0 + Vector(gx * 8 + 6, gy * 7 + 5) * mmsc
          else
            _gt:mmp_ctrl_move()
            _gt:player_shoot_cooldown()
          end
        else --mouse owns the cursor (hover-select follows the mouse)
          mmp_ctrl = false
        end
        _gt:draw_minimap_ui()
      else
        mmp_ctrl = false
        if mmp_pin == 1 or _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-8, -18) * mmsc,mmp_rbpos + Vector(20, 20) * mmsc) then --ui zone
          _gt:draw_minimap_ui()
        else
          ui_timer = 0
        end
      end
      _gt:draw_minimap()
    end
    -----
    _gt:mouse_action()
end

--
function _gt:mirror_mmp_pos(p)
    if room:IsMirrorWorld() then
      -- local ltroom = _gt:get_corner_room(1)
      -- local rbroom = _gt:get_corner_room(4)
      return Vector(mmp_pos0.X + 8 * ltroom.X * mmsc + (mmp_pos0.X + 8 * rbroom.X * mmsc - p.X) + 12 * mmsc, p.Y)
    else
      return p
    end
end

function _gt:mirror_mmp_dir(p)
    if room:IsMirrorWorld() then
      return Vector(-p.X, p.Y)
    else
      return p
    end
end

function _gt:mouse_action()
    if _gt:IsMouseBtnTriggered(0) then
      --
      if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
        _gt:pre_secret_room()
      elseif crd.Data.Type == 10 then
        _gt:pre_secret_curse_room()
      end
      --
      local mgid = _gt:get_pos_grid_index(mpos)
      ---
      if (_gt:check_teleble(mgid) and tele_cd < 1) then
        _gt:teleport_to_grid_index(mgid)
      elseif gtconfig.KeyboardMapEnable then -----------------------gtconfig.KeyboardMapEnable enable
        mgid = _gt:get_pos_grid_index_mmp(_gt:mirror_mmp_pos(mpos))
        --
        if (_gt:check_teleble(mgid) and tele_cd < 1) then
          _gt:teleport_to_grid_index(mgid)
        elseif _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-6, -15) * mmsc,Vector(mmp_rbpos.X + 18 * mmsc, mmp_ltpos.Y - 1 * mmsc)) then --magnet zone
          if _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-3, -13) * mmsc,mmp_ltpos + Vector(5,-4) * mmsc) then --pin zone
            if mmp_pin == 1 then
              mmp_pin = 0
            else
              mmp_pin = 1
            end
          elseif _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(8, -13) * mmsc,mmp_ltpos + Vector(19, -3) * mmsc) then --zoom button
            cycle_mmscale()
          elseif mmp_pin == 0 then
            mouse_magnet = true
            d_pos = mmp_ltpos - mpos
          end
        end
        --
      end
      ---
    end
    ----------------------------------
    if not gtconfig.KeyboardMapEnable then return end
    ----------------------------------
    local cp = scpos / 2
    if Input.IsMouseBtnPressed(0) then
      if mouse_magnet then
        mmp_ltpos = mpos + d_pos
        mmp_pos0 = mmp_ltpos - mmp_ltpos_
        mmp_rbpos = mmp_pos0 + mmp_rbpos_
        _gt:prep_minimap()
        player:SetShootingCooldown(2)
        local twin = player:GetOtherTwin()
        if twin then
          twin:SetShootingCooldown(2)
        end
        --

        if _gt:check_pos_en_box(mpos, cp + Vector(-16, -16), cp + Vector(16, 116)) then
          trash:SetFrame("trash", 1)
          trash:Render(cp, Vector(0, 0), Vector(0, 0))
        else
          trash:SetFrame("trash", 0)
          trash:Render(cp, Vector(0, 0), Vector(0, 0))
        end
        --
      end
    else
      if mouse_magnet then
        mouse_magnet = false
        if _gt:check_pos_en_box(mpos, cp + Vector(-16, -16), cp + Vector(16, 16)) then
          gtconfig.KeyboardMapEnable = false
        end
      end
      --
      if mmp_ltpos.X < 5 then
        mmp_ltpos.X = 5
        mmp_pos0 = mmp_ltpos - mmp_ltpos_
        mmp_rbpos = mmp_pos0 + mmp_rbpos_
        _gt:prep_minimap()
      elseif mmp_rbpos.X > scpos.X - 17 * mmsc then
        mmp_rbpos.X = scpos.X - 17 * mmsc
        mmp_pos0 = mmp_rbpos - mmp_rbpos_
        mmp_ltpos = mmp_pos0 + mmp_ltpos_
        _gt:prep_minimap()
      end
      if mmp_ltpos.Y < 14 * mmsc then
        mmp_ltpos.Y = 14 * mmsc
        mmp_pos0 = mmp_ltpos - mmp_ltpos_
        mmp_rbpos = mmp_pos0 + mmp_rbpos_
        _gt:prep_minimap()
      elseif mmp_rbpos.Y > scpos.Y - 16 * mmsc then
        mmp_rbpos.Y = scpos.Y - 16 * mmsc
        mmp_pos0 = mmp_rbpos - mmp_rbpos_
        mmp_ltpos = mmp_pos0 + mmp_ltpos_
        _gt:prep_minimap()
      end
      --
    end
    ---
end
--
function _gt:itemused()
    -- print('itemused', args)
    mmp_ctrl = false
    _gt:get_grid_room()
    _gt:prep()
end
function _gt:check_and_tele_room(tgid)
    if (_gt:check_teleble(tgid) and tele_cd < 1) then
        -- player:AnimateTeleport(true)
        if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
            _gt:pre_secret_room()
        elseif crd.Data.Type == 10 then
            _gt:pre_secret_curse_room()
        end
        _gt:teleport_to_grid_index(tgid)
        mmp_ctrl_pos = Vector(0, 0)
        mmp_ctrl = false
    elseif tgid ~= crd.SafeGridIndex then
        _gt:tele_failed()
    end
end
function _gt:step()
    if n_room_num == 0 then
        print('GoodTrip [Fixed] luamod reload detected')
        _gt:prep()
        _gt:new_room()
        _gt:new_level()
    end
    mpos = Isaac.WorldToScreen(Input.GetMousePosition(true))
    mouse_moved = (mpos - last_mpos):LengthSquared() > 4 --camera-independent (round-trip cancels camera); every frame so the baseline is fresh at TAB-open
    last_mpos = mpos
    if Input.IsActionTriggered(ButtonAction.ACTION_MAP,player.ControllerIndex) then
      _gt:get_grid_room()
      _gt:prep()
    end
    if Input.IsActionPressed(ButtonAction.ACTION_MAP,player.ControllerIndex) then
      if gtconfig.LastRoomShortcut then
        if Input.IsButtonTriggered(Keyboard.KEY_Z, player.ControllerIndex)
        or (gtconfig.ControllerAlternateZ and Input.IsButtonTriggered(
                    gtconfig.ControllerAlternateZ, player.ControllerIndex)) then
         _gt:check_and_tele_room(level:GetLastRoomDesc().SafeGridIndex)
        end
      end
      if gtconfig.AllowBookmarking then
        local mgid
        if gtconfig.KeyboardMapEnable then
            mgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
        else
            mgid = crd.SafeGridIndex
        end
        for i = 1, 9 do
            if Input.IsButtonTriggered(Keyboard.KEY_0 + i, player.ControllerIndex) then
                if bookmarks[i] == -99 then
                    player:AnimateHappy()
                    bookmarks[i] = mgid
                else
                    _gt:check_and_tele_room(bookmarks[i])
                end
            end
        end
        if Input.IsButtonTriggered(Keyboard.KEY_0, player.ControllerIndex) then
            player:AnimateSad()
            bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}
        end
      end
      if gtconfig.NoShootWhenClick then
        _gt:player_shoot_cooldown()
      end
      if mmp_1step_tp then
        mmp_1step_tp = false
        if mmp_ctrl and _gt:check_teleble(false) then
          mmp_ctrl = false
          local mgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
          mmp_1step_mgid = mgid
          if (_gt:check_teleble(mgid) and tele_cd < 1) then
            if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
              _gt:pre_secret_room()
            elseif crd.Data.Type == 10 then
              _gt:pre_secret_curse_room()
            end
            _gt:teleport_to_grid_index(mgid)
            mmp_ctrl_pos = Vector(0, 0)
            mmp_ctrl = false
          end
        end
        _gt:draw_minimap_ui()
      else
        _gt:tab_action() --do when tab pressed
      end
    elseif (gtconfig.KeyboardMapEnable) or debug then -------return when gtconfig.KeyboardMapEnable & debug disable
      --PIN ACTION WITHOUT TAB--
      if mmp_pin == 1 and crd.Clear and _gt:check_teleble(false) then
        if mouse_in_ui then
          ---click
          if _gt:IsMouseBtnTriggered(0) then
            if _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-3, -13) * mmsc,mmp_ltpos + Vector(5,-4) * mmsc) then --pin zone
            mmp_pin = 0
            elseif _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(8, -13) * mmsc,mmp_ltpos + Vector(19, -3) * mmsc) then --zoom button
              cycle_mmscale()
            else
              local mgid = _gt:get_pos_grid_index_mmp(_gt:mirror_mmp_pos(mpos))
              if (_gt:check_teleble(mgid) and tele_cd < 1) then
                _gt:teleport_to_grid_index(mgid)
              end
            end
          end
          ---click end
          _gt:draw_minimap_ui()
        else
          ui_timer = 0
        end
        _gt:draw_minimap()
      else
        ui_timer = 0
      end
      --do when tab not pressed with pin always--
      if mmp_ctrl and _gt:check_teleble(false) then
        mmp_ctrl = false
        local mgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
        if (_gt:check_teleble(mgid) and tele_cd < 1) then
          if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
            _gt:pre_secret_room()
          elseif crd.Data.Type == 10 then
            _gt:pre_secret_curse_room()
          end
          _gt:teleport_to_grid_index(mgid)
        end
      end
    end--PINend
    ----other stepworks----
    if prep_alarm then
      _gt:prep_minimap()
      prep_alarm = false
    end
    if tele_cd > 0 then
      tele_cd = tele_cd - 1
    end
    if debug then
      --test--
      --------
    end
    ---undebug test---
    --_gt:print_center_map()
    --Isaac.RenderText(crd.Data.Type.."/"..crd.Data.Name.."/"..crd.Data.Spawns.Size.."//"..crd.DisplayFlags.."/"..n_room_num.."/"..crd.ListIndex, 50, 150, 1, 1, 1, 1)
    --Isaac.RenderText(test1, 50, 50, 1, 1, 1, 1)
    --Isaac.RenderText(player:GetHearts().."/"..player:GetMaxHearts(), 50, 120, 1, 1, 1, 1)
    ------
    --local tst1 = 0
    --if level:IsDevilRoomDisabled () then tst1 = 1 else tst1 = 0 end
    --Isaac.RenderText(level:GetStage().."/"..level:GetStageType().."/"..tst1, 50, 50, 1, 1, 1, 1)
    ------

    --[[
    if secret_pre_room_id[crid] then
      Isaac.RenderText(secret_pre_room_id[crid], 50, 150, 1, 1, 1, 1)
    else
      Isaac.RenderText(0, 50, 150, 1, 1, 1, 1)
    end
    ]]
    ------------------
end
--
function _gt:step2()
    if mmp_pin == 1 and gtconfig.KeyboardMapEnable then
      mpos = Isaac.WorldToScreen(Input.GetMousePosition(true))
      if _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-8, -18) * mmsc,mmp_rbpos + Vector(20, 20) * mmsc) then --ui zone
        mouse_in_ui = true
      else
        mouse_in_ui = false
      end
    end
end
--
function _gt:new_room()
    local last_crd = crd
    --
    _gt:get_grid_room()
    room = Game():GetRoom()
    crd = level:GetCurrentRoomDesc()
    crid = crd.GridIndex
    crsid = crd.SafeGridIndex
    mmp_ctrl = false
    player = Isaac.GetPlayer(0)
    stage = level:GetStage()
    if gtconfig.KeyboardMapEnable then
      prep_alarm = true
      _gt:prep_minimap()
    end
    if tele_maze then
      level:AddCurse(LevelCurse.CURSE_OF_MAZE,false)
      tele_maze = false
    end
    --
    if last_crd.Data then
      if last_crd.Data.Type == 7 or (last_crd.Data.Type == 8 and Game():IsGreedMode()) then
        --
        if not secret_pre_room_id[last_crd.GridIndex] then
          if (level:GetRoomByIdx(last_crd.GridIndex + 1,-1)).ListIndex == crd.ListIndex then
            secret_pre_room_id[last_crd.GridIndex] = last_crd.GridIndex + 1
          elseif (level:GetRoomByIdx(last_crd.GridIndex - 1,-1)).ListIndex == crd.ListIndex then
            secret_pre_room_id[last_crd.GridIndex] = last_crd.GridIndex - 1
          elseif (level:GetRoomByIdx(last_crd.GridIndex + 13,-1)).ListIndex == crd.ListIndex then
            secret_pre_room_id[last_crd.GridIndex] = last_crd.GridIndex + 13
          elseif (level:GetRoomByIdx(last_crd.GridIndex - 13,-1)).ListIndex == crd.ListIndex then
            secret_pre_room_id[last_crd.GridIndex] = last_crd.GridIndex - 13
          end
        end
        --
      end
    end
    if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
      _gt:pre_secret_room()
    elseif crd.Data.Type == 10 then
      _gt:pre_secret_curse_room()
    end
end
--
function _gt:new_level()
    hudoffset = Options.HUDOffset * 10 --refresh in case the HUD-offset slider changed mid-run
    if MinimapAPI then
        -- print('GoodTrip [Fixed] detected MinimapAPI')
        pcall(function ()
            minimapoffx = MinimapAPI.Config.PositionX - 6 --* 2.4
            minimapoffy = MinimapAPI.Config.PositionY - 6 --* 1.3
        end)
    end
    bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}
    level = Game():GetLevel()
    _gt:get_grid_room()
    n_room_num = level:GetRooms().Size
    stageeffect = 0
    if not level:IsAscent() then
        if level:GetStage() == 2 or (level:GetStage() == 1 and level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0) and level:GetStageType() >= StageType.STAGETYPE_REPENTANCE then
            stageeffect = 1
        elseif level:GetStage() == 4 or (level:GetStage() == 3 and level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0) and level:GetStageType() >= StageType.STAGETYPE_REPENTANCE then
            stageeffect = 2
        elseif level:GetStage() == 6 or (level:GetStage() == 5 and level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0) and level:GetStageType() < StageType.STAGETYPE_REPENTANCE then
            stageeffect = 3
        end
end
    secret_pre_room_id = {}
    if gtconfig.KeyboardMapEnable then
      prep_alarm = true
      _gt:prep_minimap()
    end
end
function _gt:get_config()
    return gtconfig
end
--
--
function _gt:fair_trip(roomIndex, target)
	--BFS shortest distance; only cleared rooms can be passed through,
	--but any room connected to the target counts as the last hop (+1)
	local startRoom = MinimapAPI:GetRoomAtPosition(MinimapAPI:GridIndexToVector(roomIndex))
	local targetRoom = MinimapAPI:GetRoomAtPosition(MinimapAPI:GridIndexToVector(target))
	if not startRoom or not targetRoom then
		return 0
	end
	local safeTarget = targetRoom.Descriptor.SafeGridIndex
	local visited = {[startRoom.Descriptor.SafeGridIndex] = true}
	local queue = {{room = startRoom, dist = 0}}
	local head = 1
	while queue[head] do
		local cur = queue[head]
		head = head + 1
		local safeIndex = cur.room.Descriptor.SafeGridIndex
		if safeIndex == safeTarget and cur.room.Clear then
			return cur.dist
		end
		if _gt:check_neigh_connected(targetRoom.Descriptor, function(rd)
			return rd.SafeGridIndex == safeIndex
		end) then
			return cur.dist + 1
		end
		if cur.room.Clear then
			for _, adj in ipairs(cur.room:GetAdjacentRooms()) do
				local sid = adj.Descriptor.SafeGridIndex
				if not visited[sid] then
					visited[sid] = true
					queue[#queue+1] = {room = adj, dist = cur.dist + 1}
				end
			end
		end
	end
	return 999
end
--
-------------------------------
_gt:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
  _gt:prep()
  _gt:new_room()
  _gt:new_level()
end)
_gt:AddCallback(ModCallbacks.MC_USE_ITEM, _gt.itemused)
_gt:AddCallback(ModCallbacks.MC_USE_CARD, _gt.itemused)
_gt:AddCallback(ModCallbacks.MC_USE_PILL, _gt.itemused)
_gt:AddCallback(ModCallbacks.MC_POST_RENDER, _gt.step)
_gt:AddCallback(ModCallbacks.MC_POST_UPDATE, _gt.step2)
_gt:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, _gt.new_room)
_gt:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, _gt.new_level)
