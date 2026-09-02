--the game's own corner map, or MinimapAPI's: screen <-> cell both ways, the
--anchors the vanilla map is drawn from, the HUD offset, and the REPENTOGON gate
--for drawing the cursor on that map
return function(deps)
    local cfg, floor = deps.cfg, deps.floor
    local M = {}

    --screen size and HUD offset, refreshed every frame the map is held open:
    --the corner map moves the moment the slider moves
    M.scpos = Vector(0, 0)
    M.hudoffset = Options.HUDOffset * 10
    function M.refresh_screen()
        local cp = Isaac.WorldToRenderPosition(Vector(320,280))
        M.scpos = cp + cp
        M.hudoffset = Options.HUDOffset * 10
    end

    --gon_ functions check REPENTOGON themselves: on a plain game every gon_ test is
    --false and every gon_ action is a no-op. Nothing else may call a REPENTOGON-only API.
    --(without REPENTOGON a cursor on the game's map draws behind it)
    function M.gon_map_cursor()
        return REPENTOGON ~= nil and cfg.CursorOnGameMap
    end

    --hit-test against MinimapAPI's own rendered rooms: RenderOffset has position,
    --display mode, pitch and the mirror flip baked in, so invert that
    function M.get_pos_grid_index_minimapapi(pos)
        local sx = MinimapAPI.GlobalScaleX or 1
        if sx ~= 1 and sx ~= -1 then
          return -99 --mid mirror-flip animation
        end
        local mlevel = MinimapAPI:GetLevel()
        if not mlevel then
          return -99
        end
        local large = MinimapAPI:IsLarge()
        local pw, ph = large and 17 or 8, large and 15 or 7
        local pivot = large and Vector(-4, -4) or Vector(-2, -2)
        for _, mroom in ipairs(mlevel) do
          if mroom.RenderOffset and mroom.Descriptor and mroom:IsVisible() then
            local ox = mroom.RenderOffset.X - pivot.X
            if sx == -1 then
              ox = ox + pivot.X * 2 --the sprite flips around its anm2 pivot (measured)
            end
            local oy = mroom.RenderOffset.Y - pivot.Y
            for _, c in ipairs(MinimapAPI:GetRoomShapePositions(mroom.Shape)) do
              local x0 = ox + c.X * pw * sx
              local x1 = x0 + pw * sx
              local y0 = oy + c.Y * ph
              if pos.X >= math.min(x0, x1) and pos.X < math.max(x0, x1)
                  and pos.Y >= y0 and pos.Y < y0 + ph then
                return mroom.Descriptor.SafeGridIndex
              end
            end
          end
        end
        return -99
    end

    --screen anchors of the vanilla corner map, shared by the click hit test and
    --cell_to_screen; mirrorsum is the mirror flip: flipped_x = mirrorsum - x
    local function vanilla_map_anchors()
        local rtr = floor.get_corner_room(2)
        local ltx = M.scpos.X - (rtr.X + 1) * 17 - 4 - M.hudoffset * 2.4 --calibrated
        local lty = - (rtr.Y) * 15 + 5 + M.hudoffset * 1.3
        local mirrorsum = nil
        if floor.room:IsMirrorWorld() then
          --the mirrored map keeps its box and flips the drawing about the box's middle
          local ltr = floor.get_corner_room(3)
          mirrorsum = 2 * ltx + (ltr.X + rtr.X + 1) * 17
        end
        return ltx, lty, mirrorsum
    end

    function M.get_pos_grid_index(pos)
        if (not cfg.FollowCurseOfLost and floor.level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0) then
          return -99
        end
        local mir = floor.room:IsMirrorWorld()
        local calibx = mir and (cfg.CalibMirrorX or 0) or (cfg.CalibMainX or 0)
        local caliby = mir and (cfg.CalibMirrorY or 0) or (cfg.CalibMainY or 0)
        pos = Vector(pos.X + calibx, pos.Y + caliby) --fresh Vector: the caller's mouse position stays untouched
        if MinimapAPI then
          return M.get_pos_grid_index_minimapapi(pos)
        end
        local ltx, lty, mirrorsum = vanilla_map_anchors()
        if pos.X > ltx and pos.Y > lty and pos.X < ltx + 222 and pos.Y < lty + 196 then
          local px = pos.X
          if mirrorsum then
            px = mirrorsum - px
          end
          local mgid = math.floor((px - ltx)/ 17) + math.floor((pos.Y - lty)/ 15) * 13
          return mgid
        else
          return -99
        end
    end

    --inverse of get_pos_grid_index: screen centre of a grid cell on the game's own
    --map, plus its cell scale; nil when the geometry is unavailable. fcol/frow are
    --an optional fractional column/row (both branches are affine), mgid still
    --keys the reference-room lookup
    function M.cell_to_screen(mgid, fcol, frow)
        local col = mgid % 13
        local row = (mgid - col) / 13
        fcol = fcol or col
        frow = frow or row
        if MinimapAPI then
          local sx = MinimapAPI.GlobalScaleX or 1
          if sx ~= 1 and sx ~= -1 then
            return nil
          end
          local mlevel = MinimapAPI:GetLevel()
          if not mlevel then
            return nil
          end
          local large = MinimapAPI:IsLarge()
          local pw, ph = large and 17 or 8, large and 15 or 7
          local pivot = large and Vector(-4, -4) or Vector(-2, -2)
          --reference room for the cell->screen affine map: the room under the
          --cursor if any, else a 1x1 room (unambiguous anchor)
          local ref = nil
          local target = floor.grid_room[mgid]
          for _, mroom in ipairs(mlevel) do
            if mroom.RenderOffset and mroom.Descriptor and mroom:IsVisible() then
              if target and mroom.Descriptor.SafeGridIndex == target.SafeGridIndex then
                ref = mroom
                break
              end
              if not ref or (ref.Shape ~= RoomShape.ROOMSHAPE_1x1 and mroom.Shape == RoomShape.ROOMSHAPE_1x1) then
                ref = mroom
              end
            end
          end
          if not ref then
            return nil
          end
          local ox = ref.RenderOffset.X - pivot.X
          if sx == -1 then
            --the sprite flips around its anm2 pivot, same as in the hit test
            ox = ox + pivot.X * 2
          end
          local oy = ref.RenderOffset.Y - pivot.Y
          local gi = ref.Descriptor.GridIndex
          local gcol = gi % 13
          local grow = (gi - gcol) / 13
          local x0 = ox + (fcol - gcol) * pw * sx
          local y0 = oy + (frow - grow) * ph
          return Vector(x0 + pw * sx / 2, y0 + ph / 2), (large and 2 or 1)
        end
        local ltx, lty, mirrorsum = vanilla_map_anchors()
        local mir = floor.room:IsMirrorWorld()
        local calibx = mir and (cfg.CalibMirrorX or 0) or (cfg.CalibMainX or 0)
        local caliby = mir and (cfg.CalibMirrorY or 0) or (cfg.CalibMainY or 0)
        local px = ltx + fcol * 17 + 8.5
        if mirrorsum then
          px = mirrorsum - px
        end
        return Vector(px - calibx, lty + frow * 15 + 7.5 - caliby), 1
    end

    return M
end
