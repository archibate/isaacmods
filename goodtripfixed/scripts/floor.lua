--the floor as the mod knows it: the level, the room stood in and its
--descriptor, the player, the stage; the 13x13 grid of descriptors and each
--room's neighbours; the secret rooms' antechambers; the door graph learned one
--room at a time; the curse-door spikes seen from either side
return function(deps)
    local cfg = deps.cfg
    local M = {}

    --reassigned on every room and floor change, so read them at call time
    M.player = Isaac.GetPlayer(0)
    M.level = Game():GetLevel()
    M.stage = M.level:GetStage()
    M.stageeffect = 0
    M.room = Game():GetRoom()
    M.crd = M.level:GetCurrentRoomDesc()
    M.crid = M.crd.GridIndex
    M.crsid = M.crd.SafeGridIndex
    M.grid_room = {}
    M.grid_room_mark = {}
    M.room_neighbours = {}
    M.neighlut = {
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
    --door graph, learned one room at a time: grid adjacency alone cannot tell a
    --doorway from a secret room's unbombed wall. Per dimension: the mirror world
    --reuses the same grid numbers for different rooms.
    M.door_link = {}  --door_link[dim][a][b]: a passage, seen from either end
    M.door_swept = {} --door_swept[dim][a]: a's own walls were read
    M.secret_pre_room_id = {}
    --curse-room door spikes seen from outside / inside; Flat File strips only the
    --side it was used on, so the two are kept apart
    M.curse_bare_outside, M.curse_bare_inside = {}, {}

    function M.get_grid_room()
        M.grid_room = {}
        M.grid_room_mark = {}
        local all_room = M.level:GetRooms()
        for i = 0, all_room.Size do
          local des = all_room:Get(i)
          if des then
            local gid = des.GridIndex
            if cfg.DangerCautionCompat and DangerCaution then
                local danger = DangerCaution:roomDangerFlags(des)
                if danger ~= 0 then
                    M.grid_room_mark[des.SafeGridIndex] = DangerCaution:dangerFlagToColor(danger)
                end
            end
            for jx=0, 1 do
              for jy=0, 1 do
                local tgid = gid + jx + jy * 13
                local tdes = M.level:GetRoomByIdx(tgid,-1)
                if tdes.ListIndex == des.ListIndex then
                  M.grid_room[tgid] = des
                end
              end
            end
          end
        end
    end

    function M.get_room_neighbours()
        M.room_neighbours = {}
        local all_room = M.level:GetRooms()
        for i = 0, all_room.Size do
          local des = all_room:Get(i)
          if des then
                M.room_neighbours[des.SafeGridIndex] = {
              Descriptor = des,
              Neighbors = {}
            }
        end
        end

          local offsets = {
            -13,
            13,
            -1,
            1
          }
          for _, room in pairs(M.room_neighbours) do
            local safeIndex = room.Descriptor.SafeGridIndex

            for gridIndex, cellRoom in pairs(M.grid_room) do
              if cellRoom.SafeGridIndex == safeIndex then
                  for _, offset in ipairs(offsets) do
                      --column guard, as in check_neigh_connected
                      local wrapped = (offset == -1 and gridIndex % 13 == 0)
                                   or (offset == 1 and gridIndex % 13 == 12)
                      local other = not wrapped and M.grid_room[gridIndex + offset] or nil

                      if other and other.SafeGridIndex ~= safeIndex then
                          room.Neighbors[other.SafeGridIndex] = true
                      end
                  end
              end
            end
          end
          for _, room in pairs(M.room_neighbours) do
            local list = {}

            for id in pairs(room.Neighbors) do
              list[#list + 1] = id
            end

            room.Neighbors = list
          end

    end

    --the outermost drawn column and row on the side `num` names (1 left-top,
    --2 right-top, 3 left-bottom, 4 right-bottom). All 13 are scanned: in the
    --mirror world every drawn room can sit on one side of column 6
    function M.get_corner_room(num)
        local corner_room = Vector(6, 6)
        local fx = {1, -1, 1, -1}
        local fy = {1, 1, -1, -1}
        local ffx = fx[num]
        local ffy = fy[num]
        for i = 6 - 6 * ffx, 6 + 6 * ffx, ffx do
          local found = false
          for j = 0, 12 do
            if M.grid_room[i+j*13] then
              if M.grid_room[i+j*13].DisplayFlags > 0 then
                found = true
                break
              end
            end
          end
          if found then
            corner_room.X = i
            break
          end
        end
        for j = 6 - 6 * ffy, 6 + 6 * ffy, ffy do
          local found = false
          for i = 0, 12 do
            if M.grid_room[i+j*13] then
              if M.grid_room[i+j*13].DisplayFlags > 0 then
                found = true
                break
              end
            end
          end
          if found then
            corner_room.Y = j
            break
          end
        end
        return corner_room
    end

    function M.pre_secret_room()
      local door = nil
      for i =0, 7 do
        door = M.room:GetDoor(i)
        if door then
          local id = door.TargetRoomIndex
          if door.Desc.Variant == 8 then
            if door.TargetRoomType == 10 then
              if not M.secret_pre_room_id[M.crid] then
                M.secret_pre_room_id[M.crid] = id
              end
            elseif M.grid_room[id].VisitedCount == 0 then
              M.secret_pre_room_id[M.crid] = id
            else
              M.secret_pre_room_id[M.crid] = id
              break
            end
          end
        end
      end
    end

    function M.pre_secret_curse_room()
      local door = nil
      for i =0, 7 do
        door = M.room:GetDoor(i)
        if door then
          local id = door.TargetRoomIndex
          if door.Desc.Variant == 8 then
            if door.TargetRoomType == 7 then
              if M.secret_pre_room_id[id] and M.secret_pre_room_id[id] ~= M.crid then
                M.secret_pre_room_id[M.crid] = id
                break
              else
                M.secret_pre_room_id[M.crid] = id
              end
            end
          end
        end
      end
    end

    --the door graph for the side of the mirror being stood on. Read off the live
    --room, not the cached one: a trip hops through an antechamber mid-call
    function M.door_graph()
        local d = Game():GetRoom():IsMirrorWorld() and 1 or 0
        M.door_link[d] = M.door_link[d] or {}
        M.door_swept[d] = M.door_swept[d] or {}
        return M.door_link[d], M.door_swept[d]
    end

    --read the current room's doors (the only room the game answers for) into the
    --graph both ways. DOOR_HIDDEN is an unbombed wall, so no passage; everything
    --else, locked included, is walkable. All read live so nothing is from different moments.
    function M.sweep_doors()
        local live = Game():GetRoom()
        local lvl = Game():GetLevel()
        local here = lvl:GetCurrentRoomDesc().SafeGridIndex
        local link, swept = M.door_graph()
        link[here] = link[here] or {}
        swept[here] = true
        for i = 0, 7 do
          local door = live:GetDoor(i)
          if door and door.Desc.Variant ~= DoorVariant.DOOR_HIDDEN then
            local there = lvl:GetRoomByIdx(door.TargetRoomIndex, -1).SafeGridIndex
            --curse-room spikes are read off the door itself: Flat File strips them
            --once and for good, so the trinket in hand says nothing about this door
            if door.TargetRoomType == RoomType.ROOM_CURSE then
              M.curse_bare_outside[there] = door.VarData ~= 0
            elseif live:GetType() == RoomType.ROOM_CURSE then
              M.curse_bare_inside[here] = door.VarData ~= 0
            end
            if there ~= here then
              --this end knows its slot; the far end gets a bare mark until its own turn
              link[here][there] = i
              link[there] = link[there] or {}
              if link[there][here] == nil then link[there][here] = true end
            end
          end
        end
    end

    --may a trip step between these rooms? A passage seen from either end: yes. A
    --swept room saying nothing: no. Neither swept (mod loaded mid-run): grid adjacency stands.
    function M.linked(a, b)
        local link, swept = M.door_graph()
        if link[a] and link[a][b] ~= nil then
          return true
        end
        return not (swept[a] or swept[b])
    end

    --the target cell a walk from `from` would step into. Read off the grid, not the
    --door sweep, so a room nobody has been inside yet answers too
    function M.touching_cell(from, to)
        local src, dst = M.grid_room[from], M.grid_room[to]
        if not (src and dst) then return nil end
        for cell, d in pairs(M.grid_room) do
          if d.ListIndex == src.ListIndex then
            local col = cell % 13
            for _, step in ipairs({ -13, 13, -1, 1 }) do
              if not ((step == -1 and col == 0) or (step == 1 and col == 12)) then --column guard
                local nd = M.grid_room[cell + step]
                if nd and nd.ListIndex == dst.ListIndex then return cell + step end
              end
            end
          end
        end
        return nil
    end

    --a new room: the grid, the neighbours, the room and its descriptor, its
    --doors, the player and the stage; then, for a secret room just left through
    --a hole nobody had swept, which room it opened into
    function M.refresh_room()
        local last_crd = M.crd
        M.get_grid_room()
        M.get_room_neighbours()
        M.room = Game():GetRoom()
        M.crd = M.level:GetCurrentRoomDesc()
        M.crid = M.crd.GridIndex
        M.crsid = M.crd.SafeGridIndex
        M.sweep_doors()
        M.player = Isaac.GetPlayer(0)
        M.stage = M.level:GetStage()
        if last_crd.Data then
          if last_crd.Data.Type == 7 or (last_crd.Data.Type == 8 and Game():IsGreedMode()) then
            if not M.secret_pre_room_id[last_crd.GridIndex] then
              if (M.level:GetRoomByIdx(last_crd.GridIndex + 1,-1)).ListIndex == M.crd.ListIndex then
                M.secret_pre_room_id[last_crd.GridIndex] = last_crd.GridIndex + 1
              elseif (M.level:GetRoomByIdx(last_crd.GridIndex - 1,-1)).ListIndex == M.crd.ListIndex then
                M.secret_pre_room_id[last_crd.GridIndex] = last_crd.GridIndex - 1
              elseif (M.level:GetRoomByIdx(last_crd.GridIndex + 13,-1)).ListIndex == M.crd.ListIndex then
                M.secret_pre_room_id[last_crd.GridIndex] = last_crd.GridIndex + 13
              elseif (M.level:GetRoomByIdx(last_crd.GridIndex - 13,-1)).ListIndex == M.crd.ListIndex then
                M.secret_pre_room_id[last_crd.GridIndex] = last_crd.GridIndex - 13
              end
            end
          end
        end
    end

    --a new floor: everything learned about the old one goes, and the stage
    --effect (which special-room icons the floor can hold) is read
    function M.refresh_level()
        M.curse_bare_outside, M.curse_bare_inside = {}, {}
        M.level = Game():GetLevel()
        M.get_grid_room()
        M.get_room_neighbours()
        M.stageeffect = 0
        if not M.level:IsAscent() then
            if M.level:GetStage() == 2 or (M.level:GetStage() == 1 and M.level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0) and M.level:GetStageType() >= StageType.STAGETYPE_REPENTANCE then
                M.stageeffect = 1
            elseif M.level:GetStage() == 4 or (M.level:GetStage() == 3 and M.level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0) and M.level:GetStageType() >= StageType.STAGETYPE_REPENTANCE then
                M.stageeffect = 2
            elseif M.level:GetStage() == 6 or (M.level:GetStage() == 5 and M.level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0) and M.level:GetStageType() < StageType.STAGETYPE_REPENTANCE then
                M.stageeffect = 3
            end
        end
        M.secret_pre_room_id = {}
        M.door_link = {}
        M.door_swept = {}
    end

    return M
end
