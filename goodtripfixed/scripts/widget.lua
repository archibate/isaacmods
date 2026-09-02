--the mod's own map window: its sprites, layout and drawing; the hit test; the
--keyboard cursor and its one-step move; the pin, the zoom button and the drag;
--and the cursor drawn on the game's map under REPENTOGON. mpos, the mouse in
--screen space, is handed in by the caller, which owns the input
return function(deps)
    local gt, cfg, config, floor, rules, gamemap =
        deps.gt, deps.cfg, deps.config, deps.floor, deps.rules, deps.gamemap
    local M = {}

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
    local icon_room = {"RoomOutline", "RoomVisited", "RoomUnvisited", "RoomCurrent"}
    local icon_flag = {"1_IconNormal", "IconShop", "3_IconError", "IconTreasureRoom", "IconBoss",
                      "IconMiniboss", "IconSecretRoom", "IconSuperSecretRoom", "IconArcade", "IconCurseRoom",
                      "IconAmbushRoom", "IconLibrary", "IconSacrificeRoom", "IconDevilRoom", "IconAngelRoom",
                      "16_IconDungeon", "17_IconBossRush", "IconIsaacsRoom", "IconBarrenRoom", "IconChestRoom",
                      "IconDiceRoom", "22_IconBlackMarket", "23_IconGreedExit","IconPlanetarium","TeleporterRoom","TeleporterRoom","27_SecretExit","28_Blue","IconUltraSecretRoom"}
    local icon_flag2 = {"IconLockedRoom", "IconTreasureRoomGreed", "IconBossAmbushRoom","IconTreasureRoomRed","IconMirrorRoom", "IconWhiteFireRoom","IconTintSkullRoom","IconMinecartRoom","IconMineButtonRoom"}
    local draw_room_id = {}
    local draw_room_pos = {}
    local draw_room_shape = {}
    local draw_icon_pos = {Vector(0, 0),Vector(0, 0),Vector(0, 0),Vector(0,3),
                          Vector(0,3),Vector(4, 0),Vector(4, 0),Vector(4,3),
                          Vector(8, 7),Vector(0, 7),Vector(8, 0),Vector(0, 0),}
    local ltroom = Vector(6, 6)
    local rbroom = Vector(6, 6)
    local ctrl_ltroom = Vector(6, 6) --the same two corners before the widget's 3x3 padding widens them
    local ctrl_rbroom = Vector(6, 6)
    local mmp_pos0 = Vector(0, 0)
    local mmp_ltpos_ = Vector(0, 0)
    local mmp_ltpos = Vector(100, 100)
    local mmp_rbpos_ = Vector(0, 0)
    local mmp_rbpos = Vector(0, 0)
    local d_pos = Vector(0, 0)
    local mouse_magnet = false
    local mmp_ctrl_pos = Vector(0, 0)
    local fast_move_cd = {0, 0, 0, 0} --FasterCursorMove: per-direction hold-to-repeat cooldown
    local FAST_MOVE_REPEAT_FRAMES = 6 --frames between room-jumps while a key stays held
    local mmsc = 1.0 --keyboard minimap scale factor (cfg.MinimapScale / 10)

    --shared with the caller, which reads and writes them at call time
    M.mmp_pin = 0
    M.ui_timer = 0
    M.mmp_ctrl = false --the keyboard owns the cursor
    M.kb_active = false --keyboard is the active map-cursor device, for this opening of the map
    M.mmp_1step_tp = false --QuicklyOneRoomMove: a step was taken, the trip is due
    M.mmp_1step_mgid = -1 --the cell it stepped onto; -2 once the cursor has been placed there
    M.prep_alarm = false --the layout is stale: prep_minimap on the next frame

    function M.rescale()
        --hand-edited, so it can arrive as anything; a scale of 0 draws nothing
        local scale = cfg.MinimapScale
        if type(scale) ~= "number" or scale < 5 then
            scale = 5
        elseif scale > 25 then
            scale = 25
        end
        cfg.MinimapScale = scale
        mmsc = scale / 10
        mmp.Scale = Vector(mmsc, mmsc)
        mic.Scale = Vector(mmsc, mmsc)
        gtui.Scale = Vector(mmsc, mmsc)
        select.Scale = Vector(mmsc, mmsc)
        cursor.Scale = Vector(mmsc, mmsc)
        M.prep_alarm = true
    end
    M.rescale()
    function M.cycle_scale() --zoom button: x1.0 -> x1.5 -> x2.0 -> x1.0
        local cur = cfg.MinimapScale or 10
        if cur < 15 then
            cfg.MinimapScale = 15
        elseif cur < 20 then
            cfg.MinimapScale = 20
        else
            cfg.MinimapScale = 10
        end
        M.rescale()
        config.save()
    end

    --the window position rides in the settings, so a save needs nothing from here
    function M.apply_config()
        mmp_ltpos = Vector(cfg.TopLeftX or 100, cfg.TopLeftY or 100)
        cfg.TopLeftX, cfg.TopLeftY = mmp_ltpos.X, mmp_ltpos.Y
        M.rescale()
    end
    function M.get_top_left()
        return mmp_ltpos.X, mmp_ltpos.Y
    end
    function M.set_top_left(x, y)
        mmp_ltpos = Vector(x, y)
        cfg.TopLeftX, cfg.TopLeftY = x, y
    end

    function M.check_pos_en_box(pos,ltpos,rbpos)
      if pos.X > ltpos.X and pos.X < rbpos.X and pos.Y > ltpos.Y and pos.Y < rbpos.Y then
        return true
      else
        return false
      end
    end

    --the region where the mouse takes the cursor over, a little wider than the window
    function M.in_ui_zone(mpos)
        return M.check_pos_en_box(mpos,mmp_ltpos + Vector(-8, -18) * mmsc,mmp_rbpos + Vector(20, 20) * mmsc) --ui zone
    end

    function M.get_pos_grid_index_mmp(pos)
        if M.check_pos_en_box(pos,mmp_ltpos + Vector(1, 1) * mmsc, mmp_rbpos + Vector(11, 10) * mmsc) then
          local cx = math.floor((pos.X - mmp_pos0.X - 2 * mmsc)/ (8 * mmsc))
          local cy = math.floor((pos.Y - mmp_pos0.Y - 2 * mmsc)/ (7 * mmsc))
          if cx < 0 or cx > 12 or cy < 0 or cy > 12 then --padding cells would wrap to another row
            return -99
          end
          return cx + cy * 13
        else
          return -99
        end
    end

    --the cell under the keyboard cursor
    function M.cursor_cell()
        return M.get_pos_grid_index_mmp(mmp_ctrl_pos)
    end

    function M.prep_minimap()
        local grid_room = floor.grid_room
        draw_room_id = {}
        draw_room_pos = {}
        draw_room_shape = {}
        ltroom = floor.get_corner_room(1)
        rbroom = floor.get_corner_room(4)
        --the cursor's range is the drawn rooms, before the padding below
        ctrl_ltroom = Vector(ltroom.X, ltroom.Y)
        ctrl_rbroom = Vector(rbroom.X, rbroom.Y)
        --minimum 3x3 window (the top bar must fit the pin + zoom buttons), centred
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
        mmp_ltpos_ = Vector(ltroom.X * 8, ltroom.Y * 7) * mmsc
        mmp_rbpos_ = Vector(rbroom.X * 8, rbroom.Y * 7) * mmsc
        mmp_pos0 = mmp_ltpos - mmp_ltpos_
        mmp_rbpos = mmp_pos0 + mmp_rbpos_
        if M.mmp_ctrl then
          if M.mmp_1step_mgid == -2 then
          else
            local gx = floor.crsid % 13
            local gy = (floor.crsid - gx)/ 13
            mmp_ctrl_pos = mmp_pos0 + Vector(gx * 8 + 6, gy * 7 + 5) * mmsc
          end
        end
        for i = 0, 12 do
          for j = 0, 12 do
            local drd = grid_room[i * 13 + j]
            if drd then
              if drd.DisplayFlags > 0 then
                if drd.Data.Type == 5 and drd.Data.Shape > 3 and floor.stage == 12 then
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
                elseif drd.Data.Shape == RoomShape.ROOMSHAPE_LTL then
                  table.insert(draw_room_id, i * 13 + j)
                  table.insert(draw_room_shape, drd.Data.Shape)
                  table.insert(draw_room_pos, Vector(mmp_pos0.X + 8 * (j - 1) * mmsc, mmp_pos0.Y + 7 * i * mmsc))
                else
                  table.insert(draw_room_id, i * 13 + j)
                  table.insert(draw_room_shape, drd.Data.Shape)
                  table.insert(draw_room_pos, Vector(mmp_pos0.X + 8 * j * mmsc, mmp_pos0.Y + 7 * i * mmsc))
                end
              end
            end
          end
        end
        if floor.room:IsMirrorWorld() then
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

    function M.draw_minimap_ui()
        if gamemap.gon_map_cursor() then
          return
        end
        if not ((cfg.KeyboardMapEnable and rules.check_teleble(false)) or gt.debug) then
          M.ui_timer = 0
          return
        elseif M.ui_timer < 10 then
          M.ui_timer = M.ui_timer + 1
        end
        local ui_timer = M.ui_timer
        gtui:SetFrame("ui1", ui_timer)
        gtui:Render(Vector(mmp_ltpos.X, mmp_ltpos.Y), Vector(0, 0), Vector(0, 0))
        gtui:SetFrame("ui3", ui_timer)
        gtui:Render(Vector(mmp_rbpos.X, mmp_ltpos.Y), Vector(0, 0), Vector(0, 0))
        gtui:SetFrame("ui7", ui_timer)
        gtui:Render(Vector(mmp_ltpos.X, mmp_rbpos.Y), Vector(0, 0), Vector(0, 0))
        gtui:SetFrame("ui9", ui_timer)
        gtui:Render(Vector(mmp_rbpos.X, mmp_rbpos.Y), Vector(0, 0), Vector(0, 0))
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
        gtui:SetFrame("ui5", ui_timer)
        for i = ltroom.X, rbroom.X do
          for j = ltroom.Y, rbroom.Y do
            gtui:Render(mmp_pos0 + Vector(i * 8, j * 7) * mmsc, Vector(0, 0), Vector(0, 0))
          end
        end
        if M.mmp_pin == 1 then
          gtui:SetFrame("pin1", ui_timer)
        else
          gtui:SetFrame("pin0", ui_timer)
        end
        gtui:Render(mmp_ltpos, Vector(0, 0), Vector(0, 0))
        gtui:SetFrame("zoom", ui_timer)
        gtui:Render(mmp_ltpos + Vector(12, 0) * mmsc, Vector(0, 0), Vector(0, 0))
    end

    --the keyboard cursor drawn on the game's own map; selection and teleport logic untouched
    function M.gon_draw_map_cursor()
        --checked here too: under REPENTOGON this also runs from MC_POST_HUD_RENDER
        if not gamemap.gon_map_cursor() or not M.mmp_ctrl then
          return
        end
        --the game's map is always on screen, so draw nothing until an arrow key is
        --used: a red cursor on the current room would greet anyone just reading it
        if not M.kb_active then
          return
        end
        local mgid = M.get_pos_grid_index_mmp(mmp_ctrl_pos)
        if mgid < 0 then
          return
        end
        --fractional cell position, so the sprite glides instead of snapping
        local fcol = (mmp_ctrl_pos.X - mmp_pos0.X - 2 * mmsc) / (8 * mmsc)
        local frow = (mmp_ctrl_pos.Y - mmp_pos0.Y - 2 * mmsc) / (7 * mmsc)
        local center, scale = gamemap.cell_to_screen(mgid, fcol, frow)
        if not center then
          return
        end
        if rules.check_teleble(mgid) then
          cursor.Color = Color(1, 1, 1, 1, 0, 0, 0)
        else
          cursor.Color = Color(1, 0.3, 0.3, 1, 0, 0, 0) --not teleportable
        end
        --(1, 9): cursor.anm2's pivot is the pointer's hotspot, not its centre.
        --gmcoff: residual measured in-game under REPENTOGON, X flips with the mirror
        local gmcoff = floor.room:IsMirrorWorld() and Vector(9, 2) or Vector(-8, 2)
        cursor.Scale = Vector(scale, scale)
        cursor:Render(center - Vector(1, 9) * scale + gmcoff, Vector(0, 0), Vector(0, 0))
        cursor.Scale = Vector(1, 1)
        cursor.Color = Color(1, 1, 1, 1, 0, 0, 0)
    end

    function M.draw_minimap(mpos, faint)
        if gamemap.gon_map_cursor() then
          --under REPENTOGON the game's map is drawn in MC_HUD_RENDER, so the cursor
          --goes in MC_POST_HUD_RENDER instead
          if not REPENTOGON then
            M.gon_draw_map_cursor()
          end
          return
        end
        --faint: uncleared room, window drawn dim without chrome or cursor
        local alpha = faint and math.min(math.max(cfg.DimMapAlpha or 35, 5), 100) / 100 or 1
        local grid_room, stage, stageeffect = floor.grid_room, floor.stage, floor.stageeffect
        local mirror = floor.room:IsMirrorWorld()
        mic.Color = Color(1, 1, 1, alpha, 0, 0, 0)
        select.Color = Color(1, 1, 1, alpha, 0, 0, 0)
        mmp.Color = Color(1, 1, 1, alpha, 0, 0, 0)
        mmp:SetFrame(icon_room[1], 0)
        for i = 1, #draw_room_id do
          local s = grid_room[draw_room_id[i]].Data.Shape
          if (not mirror and s == RoomShape.ROOMSHAPE_LTL) or (mirror and s >= RoomShape.ROOMSHAPE_2x1 and s ~= RoomShape.ROOMSHAPE_LTL) then
            mmp:Render(draw_room_pos[i] + Vector(8 * mmsc, 0), Vector(0, 0), Vector(0, 0))
          else
            mmp:Render(draw_room_pos[i], Vector(0, 0), Vector(0, 0))
          end
        end
        for i = 1, #draw_room_id do
          local rd = grid_room[draw_room_id[i]]
          if rd.Flags & RoomDescriptor.FLAG_RED_ROOM ~= 0 then
            mmp.Color = Color(1, 0.3, 0.3, alpha, 0, 0, 0)
          else
            local markclr = floor.grid_room_mark[rd.SafeGridIndex]
            if markclr ~= nil then
                mmp.Color = Color(markclr.Red, markclr.Green, markclr.Blue, alpha, 0, 0, 0)
            else
                mmp.Color = Color(1, 1, 1, alpha, 0, 0, 0)
            end
          end
          if rd.SafeGridIndex == draw_room_id[i] or (rd.Data.Type == 5 and stage == 12) then
            if floor.crd.ListIndex == rd.ListIndex then
              mmp:SetFrame(icon_room[4], draw_room_shape[i] - 1)
              mmp:Render(draw_room_pos[i], Vector(0, 0), Vector(0, 0))
            elseif rd.VisitedCount > 0 and rd.Clear then
              mmp:SetFrame(icon_room[2], draw_room_shape[i] - 1)
              mmp:Render(draw_room_pos[i], Vector(0, 0), Vector(0, 0))
            elseif rd.Data.Type ~= 7 and rd.Data.Type ~= 8 then
              mmp:SetFrame(icon_room[3], draw_room_shape[i] - 1)
              mmp:Render(draw_room_pos[i], Vector(0, 0), Vector(0, 0))
            end
            mmp.Color = Color(1, 1, 1, alpha, 0, 0, 0)
            if rd.Data.Type > 1 and rd.DisplayFlags > 1 and (rd.DisplayFlags ~= 3 or (rd.Data.Type ~= 6 and rd.Data.Type ~= 13)) and rd.Data.Type ~= 23 then
              if (rd.Data.Type == 2 or rd.Data.Type == 12 or (rd.Data.Type > 17 and rd.Data.Type < 22)) and rd.DisplayFlags == 3 then
                mic:SetFrame(icon_flag2[1], 0)
              elseif rd.Data.Type == 4 then
                if Game():IsGreedMode() and rd.GridIndex == 98 then
                  mic:SetFrame(icon_flag2[2], 0)
                elseif floor.player:HasTrinket(146) then
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
            --visited only: read from the spawn list, so drawing early spoils the floor
            elseif cfg.ShowSpecialIcons and rd.Data.Type == 1 and rd.VisitedCount > 0 then
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
        local checkid = nil
        if M.mmp_ctrl then
          checkid = M.get_pos_grid_index_mmp(mmp_ctrl_pos)
        else
          checkid = M.get_pos_grid_index_mmp(M.mirror_mmp_pos(mpos))
        end
        if grid_room[checkid] then
          --hit = the cell under the pointer (any cell the room was drawn on);
          --anchor = the room's top-left entry, where the outline goes. Void boss
          --rooms have no top-left entry, so fall back to hit
          local hit, anchor
          for i = 1, #draw_room_id do
            if checkid == draw_room_id[i] then hit = i end
            if grid_room[checkid].SafeGridIndex == draw_room_id[i] then anchor = i end
          end
          if hit then
            local at = anchor or hit
            if rules.check_teleble(checkid) then
              select:SetFrame("select", draw_room_shape[at])
            else
              select:SetFrame("select_false", draw_room_shape[at])
            end
            select:Render(draw_room_pos[at], Vector(0, 0), Vector(0, 0))
          end
        end
        if M.mmp_ctrl and not faint then
          cursor:Render(M.mirror_mmp_pos(mmp_ctrl_pos), Vector(0, 0), Vector(0, 0))
        end
    end
    --cursor range is the drawn rooms' rectangle; clamping (not per-step gating)
    --means a held key stops on the edge room without bouncing. The position is
    --unmirrored, only key direction flips, so one rectangle serves both worlds
    local function clamp_ctrl_pos(pos)
        local minx = mmp_pos0.X + (ctrl_ltroom.X * 8 + 6) * mmsc
        local maxx = mmp_pos0.X + (ctrl_rbroom.X * 8 + 6) * mmsc
        local miny = mmp_pos0.Y + (ctrl_ltroom.Y * 7 + 5) * mmsc
        local maxy = mmp_pos0.Y + (ctrl_rbroom.Y * 7 + 5) * mmsc
        return Vector(math.min(math.max(pos.X, minx), maxx), math.min(math.max(pos.Y, miny), maxy))
    end

    --the keyboard takes the cursor: on the current room, or on the room a one-step
    --move just stepped onto
    function M.take_cursor()
        M.mmp_ctrl = true
        local gx = floor.crsid % 13
        local gy = (floor.crsid - gx)/ 13
        if M.mmp_1step_mgid >= 0 then
          gx = M.mmp_1step_mgid % 13
          gy = (M.mmp_1step_mgid - gx)/ 13
          M.mmp_1step_mgid = -2
        end
        mmp_ctrl_pos = mmp_pos0 + Vector(gx * 8 + 6, gy * 7 + 5) * mmsc
    end

    --can_trip: the teleport cooldown has run out, so a one-step move may queue a trip
    function M.mmp_ctrl_move(can_trip)
        local player = floor.player
        for i = 1,4 do
          if cfg.QuicklyOneRoomMove then
            if Input.IsActionTriggered(config.movkey[i], player.ControllerIndex) then
              local npos = clamp_ctrl_pos(mmp_ctrl_pos + M.mirror_mmp_dir(config.dir[i] * Vector(8, 7) * mmsc))
              if npos.X ~= mmp_ctrl_pos.X or npos.Y ~= mmp_ctrl_pos.Y then
                mmp_ctrl_pos = npos
                local nmgid = M.get_pos_grid_index_mmp(mmp_ctrl_pos)
                if rules.check_teleble(nmgid) and can_trip then
                  M.mmp_1step_tp = true
                  M.mmp_1step_mgid = nmgid
                end
              end
            end
          end
          if cfg.FasterCursorMove then
            --a tap jumps at once; held, it repeats a room at a time
            if Input.IsActionPressed(config.key[i], player.ControllerIndex) then
              if fast_move_cd[i] <= 0 then
                mmp_ctrl_pos = clamp_ctrl_pos(mmp_ctrl_pos + M.mirror_mmp_dir(config.dir[i]) * Vector(8, 7) * mmsc)
                fast_move_cd[i] = FAST_MOVE_REPEAT_FRAMES
              else
                fast_move_cd[i] = fast_move_cd[i] - 1
              end
            else
              fast_move_cd[i] = 0
            end
          else
            if Input.IsActionPressed(config.key[i], player.ControllerIndex) then
              local step = M.mirror_mmp_dir(config.dir[i]) * mmsc
              if gamemap.gon_map_cursor() then
                step = step * Vector(8 / 17, 7 / 15) --game-map cells are 17x15, the widget's 8x7
              end
              mmp_ctrl_pos = clamp_ctrl_pos(mmp_ctrl_pos + step)
            end
          end
        end
    end

    function M.mirror_mmp_pos(p)
        if floor.room:IsMirrorWorld() then
          return Vector(mmp_pos0.X + 8 * ltroom.X * mmsc + (mmp_pos0.X + 8 * rbroom.X * mmsc - p.X) + 12 * mmsc, p.Y)
        else
          return p
        end
    end

    function M.mirror_mmp_dir(p)
        if floor.room:IsMirrorWorld() then
          return Vector(-p.X, p.Y)
        else
          return p
        end
    end

    --a click on the window's top bar: the pin, the zoom button, or the start of a
    --drag. True when the click landed on the bar at all, whatever it did
    function M.click_chrome(mpos)
        if not M.check_pos_en_box(mpos,mmp_ltpos + Vector(-6, -15) * mmsc,Vector(mmp_rbpos.X + 18 * mmsc, mmp_ltpos.Y - 1 * mmsc)) then --magnet zone
          return false
        end
        if M.check_pos_en_box(mpos,mmp_ltpos + Vector(-3, -13) * mmsc,mmp_ltpos + Vector(5,-4) * mmsc) then --pin zone
          if M.mmp_pin == 1 then
            M.mmp_pin = 0
          else
            M.mmp_pin = 1
          end
        elseif M.check_pos_en_box(mpos,mmp_ltpos + Vector(8, -13) * mmsc,mmp_ltpos + Vector(19, -3) * mmsc) then --zoom button
          M.cycle_scale()
        elseif M.mmp_pin == 0 then
          mouse_magnet = true
          d_pos = mmp_ltpos - mpos
        end
        return true
    end

    --every held-TAB frame: the drag while the button is down, and once it is up
    --the trash drop, the edge clamps and the save
    function M.drag(mpos)
        if not cfg.KeyboardMapEnable then return end
        local scpos = gamemap.scpos
        local cp = scpos / 2
        if Input.IsMouseBtnPressed(0) then
          if mouse_magnet then
            mmp_ltpos = mpos + d_pos
            mmp_pos0 = mmp_ltpos - mmp_ltpos_
            mmp_rbpos = mmp_pos0 + mmp_rbpos_
            M.prep_minimap()
            floor.player:SetShootingCooldown(2)
            local twin = floor.player:GetOtherTwin()
            if twin then
              twin:SetShootingCooldown(2)
            end
            if M.check_pos_en_box(mpos, cp + Vector(-16, -16), cp + Vector(16, 116)) then
              trash:SetFrame("trash", 1)
              trash:Render(cp, Vector(0, 0), Vector(0, 0))
            else
              trash:SetFrame("trash", 0)
              trash:Render(cp, Vector(0, 0), Vector(0, 0))
            end
          end
        else
          local drag_ended = mouse_magnet --saved only after the edge clamps below
          if mouse_magnet then
            mouse_magnet = false
            if M.check_pos_en_box(mpos, cp + Vector(-16, -16), cp + Vector(16, 16)) then
              cfg.KeyboardMapEnable = false
            end
          end
          if mmp_ltpos.X < 5 then
            mmp_ltpos.X = 5
            mmp_pos0 = mmp_ltpos - mmp_ltpos_
            mmp_rbpos = mmp_pos0 + mmp_rbpos_
            M.prep_minimap()
          elseif mmp_rbpos.X > scpos.X - 17 * mmsc then
            mmp_rbpos.X = scpos.X - 17 * mmsc
            mmp_pos0 = mmp_rbpos - mmp_rbpos_
            mmp_ltpos = mmp_pos0 + mmp_ltpos_
            M.prep_minimap()
          end
          if mmp_ltpos.Y < 14 * mmsc then
            mmp_ltpos.Y = 14 * mmsc
            mmp_pos0 = mmp_ltpos - mmp_ltpos_
            mmp_rbpos = mmp_pos0 + mmp_rbpos_
            M.prep_minimap()
          elseif mmp_rbpos.Y > scpos.Y - 16 * mmsc then
            mmp_rbpos.Y = scpos.Y - 16 * mmsc
            mmp_pos0 = mmp_rbpos - mmp_rbpos_
            mmp_ltpos = mmp_pos0 + mmp_ltpos_
            M.prep_minimap()
          end
          cfg.TopLeftX, cfg.TopLeftY = mmp_ltpos.X, mmp_ltpos.Y --the window position rides in the settings
          if drag_ended then --alt-F4 and TAB+R never reach MC_PRE_GAME_EXIT
            config.save()
          end
        end
    end

    return M
end
