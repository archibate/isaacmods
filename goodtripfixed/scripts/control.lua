--per-frame input and the run's events: TAB and the overlay, click dispatch,
--bookmarks, the last-room and fast-restart shortcuts, the one-step move, and
--what happens on a new room, a new floor and an item use. Owns the mouse
return function(deps)
    local gt, config, floor, rules, gamemap, widget, trip =
        deps.gt, deps.config, deps.floor, deps.rules, deps.gamemap, deps.widget, deps.trip
    local cfg = config.cfg
    local M = {}

    local in_run = false --a run has begun, so drawing on screen is fine (render runs on menus too)
    local mouse_pressed = {false, false, false, false, false}
    local mpos = Vector(0, 0)
    local last_mpos = Vector(0, 0)
    local mouse_moved = false --physical mouse motion this frame (tracked every frame in step)
    local mouse_in_ui = false
    local n_room_num = 0
    local bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}

    function M.IsMouseBtnTriggered(m)
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

    function M.prep()
        if cfg.KeyboardMapEnable then
          widget.prep_minimap()
        end
    end
    function M.player_shoot_cooldown()
        local player = floor.player
        player:SetShootingCooldown(2)
        local twin = player:GetOtherTwin()
        if twin then
            twin:SetShootingCooldown(2)
        end
    end

    --uncleared room: draw the window faint and inert instead of hiding it (hidden
    --reads as "mod broken"). Not for Curse of the Lost or an unknown room
    function M.dim_map_only()
        return cfg.KeyboardMapEnable and cfg.DimMapInCombat
            and not rules.check_teleble(false)
            and floor.grid_room[floor.crd.SafeGridIndex] ~= nil
            and not (cfg.FollowCurseOfLost and floor.level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0)
    end

    function M.tab_action()
        local player = floor.player
        gamemap.refresh_screen()
        if cfg.FastRestartEnable
            and (Input.IsButtonTriggered(Keyboard.KEY_R, player.ControllerIndex)
                or (cfg.ControllerAlternateR and Input.IsButtonTriggered(cfg.ControllerAlternateR, player.ControllerIndex))) then
          print('GoodTrip [Fixed] !!!FAST RESTARTING!!!')
          Isaac.ExecuteCommand("restart")
        end
        if cfg.QuicklyOneRoomMove and floor.crd.Clear and player.ControlsCooldown < 2 then
          player.ControlsCooldown = player.ControlsCooldown + 1
        end
        if M.dim_map_only() and not gt.debug then
          widget.mmp_ctrl = false --no cursor while inert
          widget.draw_minimap(mpos, true)
        elseif (cfg.KeyboardMapEnable and rules.check_teleble(false)) or gt.debug then
          local movement_pressed = false
          for i = 1, 4 do
            if Input.IsActionPressed(config.movkey[i], player.ControllerIndex) then
              movement_pressed = true
              break
            end
          end
          if not movement_pressed or cfg.QuicklyOneRoomMove or cfg.IgnoreMovementKeys then
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
                widget.mmp_ctrl_move(trip.ready())
                M.player_shoot_cooldown()
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
        M.mouse_action()
    end

    --nil follows the vanilla map key; a custom binding replaces it (dodges EID's TAB overlay)
    function M.is_overlay_triggerd()
        if cfg.OverlayKey or cfg.OverlayKeyController then
          return (cfg.OverlayKey ~= nil and Input.IsButtonTriggered(cfg.OverlayKey, 0))
              or (cfg.OverlayKeyController ~= nil and Input.IsButtonTriggered(cfg.OverlayKeyController, floor.player.ControllerIndex))
        end
        return Input.IsActionTriggered(ButtonAction.ACTION_MAP, floor.player.ControllerIndex)
    end

    function M.is_overlay_pressed()
        if cfg.OverlayKey or cfg.OverlayKeyController then
          return (cfg.OverlayKey ~= nil and Input.IsButtonPressed(cfg.OverlayKey, 0))
              or (cfg.OverlayKeyController ~= nil and Input.IsButtonPressed(cfg.OverlayKeyController, floor.player.ControllerIndex))
        end
        return Input.IsActionPressed(ButtonAction.ACTION_MAP, floor.player.ControllerIndex)
    end

    --a click while the map is held: a trip via the game's map, else via the
    --widget, else the widget's top bar; then the drag, every frame
    function M.mouse_action()
        if M.IsMouseBtnTriggered(0) then
          local crd = floor.crd
          if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
            floor.pre_secret_room()
          elseif crd.Data.Type == 10 then
            floor.pre_secret_curse_room()
          end
          local mgid = gamemap.get_pos_grid_index(mpos)
          if (rules.check_teleble(mgid) and trip.ready()) then
            trip.teleport_to_grid_index(mgid)
          elseif cfg.KeyboardMapEnable and not gamemap.gon_map_cursor() then --widget zones, only while it is visible
            mgid = widget.get_pos_grid_index_mmp(widget.mirror_mmp_pos(mpos))
            if (rules.check_teleble(mgid) and trip.ready()) then
              trip.teleport_to_grid_index(mgid)
            else
              widget.click_chrome(mpos)
            end
          end
        end
        widget.drag(mpos)
    end

    function M.itemused()
        widget.mmp_ctrl = false
        floor.get_grid_room()
        floor.get_room_neighbours()
        M.prep()
    end
    function M.check_and_tele_room(tgid)
        local crd = floor.crd
        if (rules.check_teleble(tgid) and trip.ready()) then
            if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
                floor.pre_secret_room()
            elseif crd.Data.Type == 10 then
                floor.pre_secret_curse_room()
            end
            trip.teleport_to_grid_index(tgid)
            widget.mmp_ctrl = false
        elseif tgid ~= crd.SafeGridIndex then
            trip.tele_failed()
        end
    end
    function M.step()
        gt.draw_warns(in_run)
        if n_room_num == 0 then
            print('GoodTrip [Fixed] luamod reload detected')
            M.prep()
            M.new_room()
            M.new_level()
        end
        local player = floor.player
        mpos = Isaac.WorldToScreen(Input.GetMousePosition(true))
        mouse_moved = (mpos - last_mpos):LengthSquared() > 4 --every frame, so the baseline is fresh at TAB-open
        last_mpos = mpos

        if M.is_overlay_triggerd() then
          floor.get_grid_room()
          M.prep()
          widget.kb_active = false --every opening starts as a read; an arrow key claims it
        end

        if M.is_overlay_pressed() then
          if cfg.LastRoomShortcut then
            if Input.IsButtonTriggered(Keyboard.KEY_Z, player.ControllerIndex)
            or (cfg.ControllerAlternateZ and Input.IsButtonTriggered(
                        cfg.ControllerAlternateZ, player.ControllerIndex)) then
             M.check_and_tele_room(floor.level:GetLastRoomDesc().SafeGridIndex)
            end
          end
          if cfg.AllowBookmarking then
            --whatever is aimed at: keyboard cursor, else mouse (game map, then
            --widget, the order a click resolves in), else the current room
            local mgid = floor.crd.SafeGridIndex
            if cfg.KeyboardMapEnable and widget.mmp_ctrl then
                mgid = widget.cursor_cell()
            else
                local aim = gamemap.get_pos_grid_index(mpos)
                if aim < 0 and cfg.KeyboardMapEnable then
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
                        M.check_and_tele_room(bookmarks[i])
                    end
                end
            end
            if Input.IsButtonTriggered(Keyboard.KEY_0, player.ControllerIndex) then
                player:AnimateSad()
                bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}
            end
          end
          if cfg.NoShootWhenClick then
            M.player_shoot_cooldown()
          end
          if widget.mmp_1step_tp then
            widget.mmp_1step_tp = false
            if widget.mmp_ctrl and rules.check_teleble(false) then
              widget.mmp_ctrl = false
              local mgid = widget.cursor_cell()
              widget.mmp_1step_mgid = mgid
              if (rules.check_teleble(mgid) and trip.ready()) then
                local crd = floor.crd
                if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
                  floor.pre_secret_room()
                elseif crd.Data.Type == 10 then
                  floor.pre_secret_curse_room()
                end
                trip.teleport_to_grid_index(mgid)
                widget.mmp_ctrl = false
              end
            end
            widget.draw_minimap_ui()
          else
            M.tab_action()
          end
        elseif (cfg.KeyboardMapEnable) or gt.debug then
          --pinned window without TAB
          if widget.mmp_pin == 1 and not gamemap.gon_map_cursor() and floor.crd.Clear and rules.check_teleble(false) then
            if mouse_in_ui then
              if cfg.NoShootWhenClick then
                M.player_shoot_cooldown()
              end
              if M.IsMouseBtnTriggered(0) then
                --pinned, so the bar's pin unpins and its zoom cycles, and no drag can start
                if not widget.click_chrome(mpos) then
                  local mgid = widget.get_pos_grid_index_mmp(widget.mirror_mmp_pos(mpos))
                  if (rules.check_teleble(mgid) and trip.ready()) then
                    trip.teleport_to_grid_index(mgid)
                  end
                end
              end
              widget.draw_minimap_ui()
            else
              widget.ui_timer = 0
            end
            widget.draw_minimap(mpos)
          elseif widget.mmp_pin == 1 and not gamemap.gon_map_cursor() and M.dim_map_only() and not gt.debug then
            widget.ui_timer = 0
            widget.mmp_ctrl = false
            widget.draw_minimap(mpos, true)
          else
            widget.ui_timer = 0
          end
          if widget.mmp_ctrl and rules.check_teleble(false) then
            widget.mmp_ctrl = false
            local mgid = widget.cursor_cell()
            if (rules.check_teleble(mgid) and trip.ready()) then
              local crd = floor.crd
              if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
                floor.pre_secret_room()
              elseif crd.Data.Type == 10 then
                floor.pre_secret_curse_room()
              end
              trip.teleport_to_grid_index(mgid)
            end
          end
        end
        if widget.prep_alarm then
          widget.prep_minimap()
          widget.prep_alarm = false
        end
        trip.tick()
    end

    function M.step2()
        --a wall can open under the player's feet (bomb, red key), so sweep every
        --tick; but not mid-transition, when the live room and the cached descriptor disagree
        if floor.level:GetCurrentRoomDesc().SafeGridIndex == floor.crsid then
          floor.sweep_doors()
        end
        if widget.mmp_pin == 1 and cfg.KeyboardMapEnable then
          mpos = Isaac.WorldToScreen(Input.GetMousePosition(true))
          if widget.in_ui_zone(mpos) then
            mouse_in_ui = true
          else
            mouse_in_ui = false
          end
        end
    end

    function M.new_room()
        in_run = true
        floor.refresh_room()
        widget.mmp_ctrl = false
        widget.kb_active = false
        trip.land_at_door()
        if cfg.KeyboardMapEnable then
          widget.prep_alarm = true
          widget.prep_minimap()
        end
        trip.restore_maze()
        local crd = floor.crd
        if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
          floor.pre_secret_room()
        elseif crd.Data.Type == 10 then
          floor.pre_secret_curse_room()
        end
    end

    function M.new_level()
        gamemap.refresh_screen()
        bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}
        floor.refresh_level()
        n_room_num = floor.level:GetRooms().Size
        if cfg.KeyboardMapEnable then
          widget.prep_alarm = true
          widget.prep_minimap()
        end
    end

    return M
end
