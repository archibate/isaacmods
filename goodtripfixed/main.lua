local hasoldgoodtrip = (gt and not gt.isgtfixed)
local _gt = RegisterMod("GoodTrip [Fixed]", 1)
gt = _gt
_gt.isgtfixed = true
_gt.debug = false --teleport anywhere, no tolls, no transition; read at call time everywhere
--EARLY priority: a mod returning a value from a callback silences every later mod
--in that round, and this one loads late (alphabetical). Not for MC_USE_ITEM/CARD/PILL,
--where a return means "handled".
--warnings stay until fixed, drawn only in-run (render runs on menus too). Either
--GoodTrip may load first, so both checks are needed.
local warn_in_run = false
local warned = false
local function draw_warns()
    local warnings = {}
    if hasoldgoodtrip or gt ~= _gt then
        warnings[#warnings + 1] = 'WARNING: You must disable the old GoodTrip before using GoodTrip [Fixed]!'
    end
    if not REPENTANCE then
        warnings[#warnings + 1] = 'WARNING: This mod only works for Repentance!'
    end
    if #warnings == 0 then
        return
    end
    if not warned then
        warned = true
        for _, warnmsg in ipairs(warnings) do
            print(warnmsg)
        end
    end
    if not warn_in_run then
        return
    end
    for i, warnmsg in ipairs(warnings) do
        Isaac.RenderScaledText(warnmsg, 40, 50 + (i - 1) * 12, 0.5, 0.5, 1, 1, 0, 1)
    end
end

local sfx = SFXManager()
local mouse_pressed = {false, false, false, false, false}
local mpos = Vector(0, 0)
local last_mpos = Vector(0, 0)
local mouse_moved = false --physical mouse motion this frame (tracked every frame in step)
local mouse_in_ui = false
local tele_maze = false
local tele_door_slot = -1 --the door a trip means to arrive by
local n_room_num = 0
--modules. Only main.lua includes, each file once, at load: include re-reads the
--file on every luamod (require would cache it) and never resolves into another
--mod's folder. Modules never include each other; what one needs is passed in.
--gtconfig.lua is the hand-edited pins table; include, not require, so an edit
--shows on the next luamod and the old GoodTrip's copy of the file can never be
--the one found. A broken file is no pins
local pins_ok, pins = pcall(include, "gtconfig")
if not pins_ok or type(pins) ~= "table" then
    pins = nil
end
local config = include("scripts.config")({ gt = _gt, pins = pins })
local gtconfig = config.cfg
_gt.save_config = config.save --so the console can make a hand-edited config stick
local floor = include("scripts.floor")({ cfg = gtconfig })
local rules = include("scripts.rules")({ gt = _gt, cfg = gtconfig, floor = floor })
local gamemap = include("scripts.gamemap")({ cfg = gtconfig, floor = floor })
local widget = include("scripts.widget")({ gt = _gt, cfg = gtconfig, config = config, floor = floor, rules = rules, gamemap = gamemap })

local tele_cd = 0
local bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}
if ModConfigMenu then
    include("scripts.mcm")({ cfg = gtconfig, config = config, widget = widget })
end
_gt:AddPriorityCallback(ModCallbacks.MC_POST_GAME_STARTED, CallbackPriority.EARLY, function(_, isContined)
    config.load_saved()
    widget.apply_config()
end)
_gt:AddPriorityCallback(ModCallbacks.MC_PRE_GAME_EXIT, CallbackPriority.EARLY, function(_, shouldSave)
    config.save()
end)
--console helper: lua print(gt.dump(...))
function _gt.dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         local key = k
         if type(key) ~= 'number' then key = '"'..key..'"' end
         s = s .. '['..key..'] = ' .. _gt.dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

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

--everyone a landing carries: players, familiars by type, and anything owned by
--a player (Mom's Knife, a carried tear)
function _gt:landed_party()
    local party = {}
    for i = 0, Game():GetNumPlayers() - 1 do
      party[#party + 1] = Isaac.GetPlayer(i)
    end
    for _, e in ipairs(Isaac.GetRoomEntities()) do
      local owner = e.Parent or e.SpawnerEntity
      if e.Type ~= EntityType.ENTITY_PLAYER
          and (e.Type == EntityType.ENTITY_FAMILIAR or (owner and owner:ToPlayer())) then
        party[#party + 1] = e
      end
    end
    return party
end

--put the party one step inside the arrival door by hand. Direction is ignored,
--EnterDoor ignores writes, LeaveDoor changes nothing (all measured)
function _gt:land_at_door()
    local slot = tele_door_slot
    tele_door_slot = -1
    if slot < 0 then return end
    local door = floor.room:GetDoor(slot)
    if not door then return end
    local dx, dy = 0, 0
    local side = slot % 4
    if side == 0 then dx = 40 elseif side == 2 then dx = -40
    elseif side == 1 then dy = 40 else dy = -40 end
    local stand = Vector(door.Position.X + dx, door.Position.Y + dy)
    --one shift for all, so a co-op pair keeps its spacing
    local shift = stand - floor.player.Position
    for _, e in ipairs(_gt:landed_party()) do
      e.Position = e.Position + shift
    end
end

function _gt:hurt(n)
  local player = floor.player
  player:TakeDamage(n, DamageFlag.DAMAGE_CURSED_DOOR | DamageFlag.DAMAGE_NO_PENALTIES, EntityRef(player), 0)
end

function _gt:tele_failed()
  sfx:Play(187, 0.5, 0, false, 1)
end

function _gt:check_curse_room(gid)
    if _gt.debug then return end
    local crid = floor.crid
    --a bombed secret-room wall has no spikes, so secret<->guard room is free
    --both ways, even when the guard is the curse room
    if floor.secret_pre_room_id[crid] == gid or floor.secret_pre_room_id[gid] == crid then
      return
    end
    local trd = floor.grid_room[gid]
    if floor.crd.Data.Type == 10 then
      if not rules.curse_toll_free(floor.crsid, true, false) then
        _gt:hurt(1)
      end
    elseif trd.Data.Type == 10 and not floor.player:IsFlying() then
      if not rules.curse_toll_free(trd.SafeGridIndex, false, true) then
        _gt:hurt(1)
      end
    end
end

--floor.* is read at each use, never copied at the top: an antechamber hop
--mid-call changes the room, and with it the descriptor and the grid
function _gt:teleport_to_grid_index(gid)
    for _,en in pairs(Isaac.GetRoomEntities()) do
			if en.Type == 867 then
        _gt:tele_failed()
        return
			end
		end
    if floor.crd.Data.Name == "Mom" or floor.crd.Data.Name == "Ultra Greed" then
      _gt:tele_failed()
      return
    elseif floor.grid_room[gid].Data.Type == 11 and not floor.grid_room[gid].ChallengeDone then
      if floor.stage%2 == 0 and floor.stage ~= 10 then
        if floor.player:GetHearts()+floor.player:GetSoulHearts()+ floor.player:GetBlackHearts() > 2 then
          _gt:tele_failed()
          return
        end
      else
        if floor.player:GetHearts() + floor.player:GetSoulHearts() + floor.player:GetBlackHearts() < floor.player:GetMaxHearts() then
          _gt:tele_failed()
          return
        end
      end
    end
    _gt:check_curse_room(gid)
    floor.level.EnterDoor = -1
    floor.level.LeaveDoor = -1
    if floor.level:GetCurses() & LevelCurse.CURSE_OF_MAZE ~= 0 then
      floor.level:RemoveCurses(LevelCurse.CURSE_OF_MAZE)
      tele_maze = true
    end

    local dist = 0
    if gtconfig.FairTripTime then
      dist = rules.fair_trip(floor.crd.SafeGridIndex, gid)
      if dist == 999 then
        _gt:tele_failed()
        return
      end
    end

    --an L room's anchor cell is not in grid_room, so the antechamber may be missing
    local from_pre = floor.crd.Data.Type == 7 and floor.secret_pre_room_id[floor.crid] or nil
    local from_prd = from_pre and floor.grid_room[from_pre] or nil
    if from_prd then --from secret room
      if from_prd.ListIndex == floor.grid_room[gid].ListIndex then
        gid = from_pre
      elseif not (floor.grid_room[gid].Data.Type == 10 and floor.secret_pre_room_id[gid] and floor.secret_pre_room_id[gid] == floor.crid) then
        --the toll is for the curse room's own door on the far side, not the bombed hole
        if from_prd.Data.Type == 10 and not rules.curse_toll_free(from_prd.SafeGridIndex, true, true) then
          _gt:hurt(1)
        end
        Game():ChangeRoom(from_pre,-1)
      end
    end
    if floor.grid_room[gid].Data.Type == 7 then --to secret room
      local to_pre = floor.secret_pre_room_id[gid]
      local to_prd = to_pre and floor.grid_room[to_pre] or nil
      if to_prd then
        if to_prd.ListIndex == floor.crd.ListIndex then --crd, since grid_room[crid] is nil in an L room
          if floor.crd.Data.Shape > 3 then
            Game():ChangeRoom(to_pre,-1)
          end
        elseif not (floor.crd.Data.Type == 10 and floor.secret_pre_room_id[floor.crid] and floor.secret_pre_room_id[floor.crid] == gid) then
          if to_prd.Data.Type == 10 and not floor.player:IsFlying()
              and not rules.curse_toll_free(to_prd.SafeGridIndex, false, true) then
            _gt:hurt(1)
          end
          Game():ChangeRoom(to_pre,-1)
        end
      end
    end
    --read here, not up top: an antechamber hop may have moved the player
    local trd = floor.grid_room[gid]
    local here = Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex
    local there = trd and trd.SafeGridIndex or gid
    tele_door_slot = -1
    local arrive = gid --the cell handed over; see _gt:landing_route
    if gtconfig.LandAtDoor then
      local cell, walked = rules.landing_route(here, there)
      arrive = cell or gid
      --a room bigger than the screen, reached from further than next door, needs
      --the wall chosen too, and the wall comes from the room the trip starts in
      if walked and trd and trd.Data.Shape >= RoomShape.ROOMSHAPE_1x2 then
        Game():ChangeRoom(walked, -1)
        here = walked
      end
      tele_door_slot = rules.landing_slot(here, there)
    end
    if _gt.debug then
      Game():ChangeRoom(arrive,-1)
    else
        if dist ~= 0 then
          local speed = floor.player.MoveSpeed
          local addTime = math.floor((60.0*dist/speed)+0.5)
          Game().TimeCounter = Game().TimeCounter + addTime --boss rush reads TimeCounter; Hush does not
        end
      tele_cd = 45
      if not gtconfig.TeleportAnimation then tele_cd = 10 end
      if _gt.debug or gtconfig.FastTransition then tele_cd = 1 end
    end
    if gtconfig.FastTransition or _gt.debug then
      Game():ChangeRoom(arrive,-1)
      Game():GetRoom():PlayMusic()
      widget.take_cursor()
      return
    end
    local tele_anime = gtconfig.TeleportAnimation and 3 or 1
    Game():StartRoomTransition(arrive, Direction.NO_DIRECTION, tele_anime, floor.player, -1) --direction is ignored, measured twice
    tele_cd = tele_anime == 3 and 45 or 10
end

function _gt:prep()
    if gtconfig.KeyboardMapEnable then
      widget.prep_minimap()
    end
end
function _gt:player_shoot_cooldown()
    local player = floor.player
    player:SetShootingCooldown(2)
    local twin = player:GetOtherTwin()
    if twin then
        twin:SetShootingCooldown(2)
    end
end

--uncleared room: draw the window faint and inert instead of hiding it (hidden
--reads as "mod broken"). Not for Curse of the Lost or an unknown room
function _gt:dim_map_only()
    return gtconfig.KeyboardMapEnable and gtconfig.DimMapInCombat
        and not rules.check_teleble(false)
        and floor.grid_room[floor.crd.SafeGridIndex] ~= nil
        and not (gtconfig.FollowCurseOfLost and floor.level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0)
end

function _gt:tab_action()
    local player = floor.player
    gamemap.refresh_screen()
    if gtconfig.FastRestartEnable
        and (Input.IsButtonTriggered(Keyboard.KEY_R, player.ControllerIndex)
            or (gtconfig.ControllerAlternateR and Input.IsButtonTriggered(gtconfig.ControllerAlternateR, player.ControllerIndex))) then
      print('GoodTrip [Fixed] !!!FAST RESTARTING!!!')
      Isaac.ExecuteCommand("restart")
    end
    if gtconfig.QuicklyOneRoomMove and floor.crd.Clear and player.ControlsCooldown < 2 then
      player.ControlsCooldown = player.ControlsCooldown + 1
    end
    if _gt:dim_map_only() and not _gt.debug then
      widget.mmp_ctrl = false --no cursor while inert
      widget.draw_minimap(mpos, true)
    elseif (gtconfig.KeyboardMapEnable and rules.check_teleble(false)) or _gt.debug then
      local movement_pressed = false
      for i = 1, 4 do
        if Input.IsActionPressed(config.movkey[i], player.ControllerIndex) then
          movement_pressed = true
          break
        end
      end
      if not movement_pressed or gtconfig.QuicklyOneRoomMove or gtconfig.IgnoreMovementKeys then
        local arrowdown = Input.IsActionPressed(config.key[1],player.ControllerIndex)
            or Input.IsActionPressed(config.key[2],player.ControllerIndex)
            or Input.IsActionPressed(config.key[3],player.ControllerIndex)
            or Input.IsActionPressed(config.key[4],player.ControllerIndex)
        --the region where the mouse takes the cursor over: the widget, or the
        --game's map under the game-map cursor mode
        local in_ui
        if gamemap.gon_map_cursor() then
          in_ui = gamemap.get_pos_grid_index(mpos) >= 0
        else
          in_ui = widget.in_ui_zone(mpos)
        end
        if arrowdown then
          widget.kb_active = true
        elseif mouse_moved and in_ui then
          widget.kb_active = false
        end
        if widget.kb_active or not in_ui then --keyboard owns the cursor
          if not widget.mmp_ctrl then
            widget.take_cursor()
          else
            widget.mmp_ctrl_move(tele_cd < 1)
            _gt:player_shoot_cooldown()
          end
        else --mouse owns the cursor
          widget.mmp_ctrl = false
        end
        widget.draw_minimap_ui()
      else
        --a movement key only pauses the cursor; dropping mmp_ctrl would lose the aimed room
        if widget.mmp_pin == 1 or widget.in_ui_zone(mpos) then
          widget.draw_minimap_ui()
        else
          widget.ui_timer = 0
        end
      end
      widget.draw_minimap(mpos)
    end
    _gt:mouse_action()
end

--nil follows the vanilla map key; a custom binding replaces it (dodges EID's TAB overlay)
function _gt:is_overlay_triggerd()
    if gtconfig.OverlayKey or gtconfig.OverlayKeyController then
      return (gtconfig.OverlayKey ~= nil and Input.IsButtonTriggered(gtconfig.OverlayKey, 0))
          or (gtconfig.OverlayKeyController ~= nil and Input.IsButtonTriggered(gtconfig.OverlayKeyController, floor.player.ControllerIndex))
    end
    return Input.IsActionTriggered(ButtonAction.ACTION_MAP, floor.player.ControllerIndex)
end

function _gt:is_overlay_pressed()
    if gtconfig.OverlayKey or gtconfig.OverlayKeyController then
      return (gtconfig.OverlayKey ~= nil and Input.IsButtonPressed(gtconfig.OverlayKey, 0))
          or (gtconfig.OverlayKeyController ~= nil and Input.IsButtonPressed(gtconfig.OverlayKeyController, floor.player.ControllerIndex))
    end
    return Input.IsActionPressed(ButtonAction.ACTION_MAP, floor.player.ControllerIndex)
end

function _gt:mouse_action()
    if _gt:IsMouseBtnTriggered(0) then
      local crd = floor.crd
      if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
        floor.pre_secret_room()
      elseif crd.Data.Type == 10 then
        floor.pre_secret_curse_room()
      end
      local mgid = gamemap.get_pos_grid_index(mpos)
      if (rules.check_teleble(mgid) and tele_cd < 1) then
        _gt:teleport_to_grid_index(mgid)
      elseif gtconfig.KeyboardMapEnable and not gamemap.gon_map_cursor() then --widget zones, only while it is visible
        mgid = widget.get_pos_grid_index_mmp(widget.mirror_mmp_pos(mpos))
        if (rules.check_teleble(mgid) and tele_cd < 1) then
          _gt:teleport_to_grid_index(mgid)
        else
          widget.click_chrome(mpos)
        end
      end
    end
    widget.drag(mpos)
end

function _gt:itemused()
    widget.mmp_ctrl = false
    floor.get_grid_room()
    floor.get_room_neighbours()
    _gt:prep()
end
function _gt:check_and_tele_room(tgid)
    local crd = floor.crd
    if (rules.check_teleble(tgid) and tele_cd < 1) then
        if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
            floor.pre_secret_room()
        elseif crd.Data.Type == 10 then
            floor.pre_secret_curse_room()
        end
        _gt:teleport_to_grid_index(tgid)
        widget.mmp_ctrl = false
    elseif tgid ~= crd.SafeGridIndex then
        _gt:tele_failed()
    end
end
function _gt:step()
    draw_warns()
    if n_room_num == 0 then
        print('GoodTrip [Fixed] luamod reload detected')
        _gt:prep()
        _gt:new_room()
        _gt:new_level()
    end
    local player = floor.player
    mpos = Isaac.WorldToScreen(Input.GetMousePosition(true))
    mouse_moved = (mpos - last_mpos):LengthSquared() > 4 --every frame, so the baseline is fresh at TAB-open
    last_mpos = mpos

    if _gt:is_overlay_triggerd() then
      floor.get_grid_room()
      _gt:prep()
      widget.kb_active = false --every opening starts as a read; an arrow key claims it
    end

    if _gt:is_overlay_pressed() then
      if gtconfig.LastRoomShortcut then
        if Input.IsButtonTriggered(Keyboard.KEY_Z, player.ControllerIndex)
        or (gtconfig.ControllerAlternateZ and Input.IsButtonTriggered(
                    gtconfig.ControllerAlternateZ, player.ControllerIndex)) then
         _gt:check_and_tele_room(floor.level:GetLastRoomDesc().SafeGridIndex)
        end
      end
      if gtconfig.AllowBookmarking then
        --whatever is aimed at: keyboard cursor, else mouse (game map, then
        --widget, the order a click resolves in), else the current room
        local mgid = floor.crd.SafeGridIndex
        if gtconfig.KeyboardMapEnable and widget.mmp_ctrl then
            mgid = widget.cursor_cell()
        else
            local aim = gamemap.get_pos_grid_index(mpos)
            if aim < 0 and gtconfig.KeyboardMapEnable then
                aim = widget.get_pos_grid_index_mmp(widget.mirror_mmp_pos(mpos))
            end
            if aim >= 0 then
                mgid = aim
            end
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
      if widget.mmp_1step_tp then
        widget.mmp_1step_tp = false
        if widget.mmp_ctrl and rules.check_teleble(false) then
          widget.mmp_ctrl = false
          local mgid = widget.cursor_cell()
          widget.mmp_1step_mgid = mgid
          if (rules.check_teleble(mgid) and tele_cd < 1) then
            local crd = floor.crd
            if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
              floor.pre_secret_room()
            elseif crd.Data.Type == 10 then
              floor.pre_secret_curse_room()
            end
            _gt:teleport_to_grid_index(mgid)
            widget.mmp_ctrl = false
          end
        end
        widget.draw_minimap_ui()
      else
        _gt:tab_action()
      end
    elseif (gtconfig.KeyboardMapEnable) or _gt.debug then
      --pinned window without TAB
      if widget.mmp_pin == 1 and not gamemap.gon_map_cursor() and floor.crd.Clear and rules.check_teleble(false) then
        if mouse_in_ui then
          if gtconfig.NoShootWhenClick then
            _gt:player_shoot_cooldown()
          end
          if _gt:IsMouseBtnTriggered(0) then
            --pinned, so the bar's pin unpins and its zoom cycles, and no drag can start
            if not widget.click_chrome(mpos) then
              local mgid = widget.get_pos_grid_index_mmp(widget.mirror_mmp_pos(mpos))
              if (rules.check_teleble(mgid) and tele_cd < 1) then
                _gt:teleport_to_grid_index(mgid)
              end
            end
          end
          widget.draw_minimap_ui()
        else
          widget.ui_timer = 0
        end
        widget.draw_minimap(mpos)
      elseif widget.mmp_pin == 1 and not gamemap.gon_map_cursor() and _gt:dim_map_only() and not _gt.debug then
        widget.ui_timer = 0
        widget.mmp_ctrl = false
        widget.draw_minimap(mpos, true)
      else
        widget.ui_timer = 0
      end
      if widget.mmp_ctrl and rules.check_teleble(false) then
        widget.mmp_ctrl = false
        local mgid = widget.cursor_cell()
        if (rules.check_teleble(mgid) and tele_cd < 1) then
          local crd = floor.crd
          if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
            floor.pre_secret_room()
          elseif crd.Data.Type == 10 then
            floor.pre_secret_curse_room()
          end
          _gt:teleport_to_grid_index(mgid)
        end
      end
    end
    if widget.prep_alarm then
      widget.prep_minimap()
      widget.prep_alarm = false
    end
    if tele_cd > 0 then
      tele_cd = tele_cd - 1
    end
end

function _gt:step2()
    --a wall can open under the player's feet (bomb, red key), so sweep every
    --tick; but not mid-transition, when the live room and the cached descriptor disagree
    if floor.level:GetCurrentRoomDesc().SafeGridIndex == floor.crsid then
      floor.sweep_doors()
    end
    if widget.mmp_pin == 1 and gtconfig.KeyboardMapEnable then
      mpos = Isaac.WorldToScreen(Input.GetMousePosition(true))
      if widget.in_ui_zone(mpos) then
        mouse_in_ui = true
      else
        mouse_in_ui = false
      end
    end
end

function _gt:new_room()
    warn_in_run = true
    floor.refresh_room()
    widget.mmp_ctrl = false
    widget.kb_active = false
    _gt:land_at_door()
    if gtconfig.KeyboardMapEnable then
      widget.prep_alarm = true
      widget.prep_minimap()
    end
    if tele_maze then
      floor.level:AddCurse(LevelCurse.CURSE_OF_MAZE,false)
      tele_maze = false
    end
    local crd = floor.crd
    if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
      floor.pre_secret_room()
    elseif crd.Data.Type == 10 then
      floor.pre_secret_curse_room()
    end
end

function _gt:new_level()
    gamemap.refresh_screen()
    bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}
    floor.refresh_level()
    n_room_num = floor.level:GetRooms().Size
    if gtconfig.KeyboardMapEnable then
      widget.prep_alarm = true
      widget.prep_minimap()
    end
end
function _gt:get_config()
    return gtconfig
end

_gt:AddPriorityCallback(ModCallbacks.MC_POST_GAME_STARTED, CallbackPriority.EARLY, function()
  _gt:prep()
  _gt:new_room()
  _gt:new_level()
end)
_gt:AddCallback(ModCallbacks.MC_USE_ITEM, _gt.itemused)
_gt:AddCallback(ModCallbacks.MC_USE_CARD, _gt.itemused)
_gt:AddCallback(ModCallbacks.MC_USE_PILL, _gt.itemused)
--EARLY render: a later HUD may cover the window, but another mod's render
--returning a value can no longer hide it
_gt:AddPriorityCallback(ModCallbacks.MC_POST_RENDER, CallbackPriority.EARLY, _gt.step)
_gt:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.EARLY, _gt.step2)
_gt:AddPriorityCallback(ModCallbacks.MC_POST_NEW_ROOM, CallbackPriority.EARLY, _gt.new_room)
_gt:AddPriorityCallback(ModCallbacks.MC_POST_NEW_LEVEL, CallbackPriority.EARLY, _gt.new_level)
if REPENTOGON then
  _gt:AddCallback(ModCallbacks.MC_POST_HUD_RENDER, widget.gon_draw_map_cursor)
end
