--may I go there: the predicates a trip is checked against, the reachable set,
--the fair distance, the door a walk would have come in by. Pure: they read the
--floor and the settings and keep nothing of their own
return function(deps)
    local gt, cfg, floor = deps.gt, deps.cfg, deps.floor
    local M = {}

    function M.check_room_open()
        local door = nil
        for i =0, 7 do
          door = floor.room:GetDoor(i)
          if door then
            if door:IsOpen() then
              return true
            end
          end
        end
        return false
    end

    function M.check_neigh_connected(trd, cond)
        local tid = trd.SafeGridIndex
        if (trd.DisplayFlags & 1) ~= 0 then
          --a red-key room stands open already, whatever it turned out to hold
          if (trd.VisitedCount == 0 or not trd.Clear) and
            trd.Flags & RoomDescriptor.FLAG_RED_ROOM == 0 and
            trd.Data.Type ~= 1 and trd.Data.Type ~= 5 and
            trd.Data.Type ~= 6 and trd.Data.Type ~= 13 and
            not (((floor.stage == 1 and floor.level:GetStageType() < StageType.STAGETYPE_REPENTANCE) or floor.room:IsMirrorWorld())
                    and ((not Game():IsGreedMode() and trd.Data.Type == 4) or trd.Data.Type == 2)) then --free: stage-1 normal floor, or Downpour/Dross mirror world
            return false
          end
          local function check_grid(off)
            local id = tid + off
            if id < 0 or id > 168 then
              return false
            end
            --column guard: a sideways offset must not wrap to the neighbouring row
            local dcol = ((off % 13) + 6) % 13 - 6
            if (tid % 13) + dcol ~= id % 13 then
              return false
            end
            local rd = floor.grid_room[id]
            return rd ~= nil and cond(rd)
          end
          local near_room = {check_grid(-13), check_grid(13), check_grid(-1), check_grid(1)}
          if floor.stage == 12 and trd.Data.Type == 5 and trd.Data.Shape > 3 then
            --void bossrooms--type4=1x2/type6=2x1/type8=2x2=Delirium
            if (near_room[1] and near_room[4])
              or (near_room[2] and near_room[3])
              or (trd.Data.Shape == 6 and (near_room[1] or near_room[4]))
              or (trd.Data.Shape == 4 and (near_room[2] or near_room[3]))
            then
              return true
            end
          else
            if near_room[1] or near_room[4] or near_room[2] or near_room[3] then
              return true
            end
            for _, off in ipairs(floor.neighlut[trd.Data.Shape]) do
                if check_grid(off) then
                    return true
                end
            end
          end
        end
        return false
    end

    function M.get_reachable_rooms()
        --flood from the current room through visited+cleared rooms; each step needs
        --a door too, else a secret room counts as a corridor on all four sides
        local start = floor.crd.SafeGridIndex
        floor.sweep_doors() --a wall bombed since entering would still read as solid
        local reach = {[start] = true}
        local queue = {start}
        local head = 1
        while queue[head] do
          local cur = queue[head]
          local node = floor.room_neighbours[cur]
          head = head + 1
          if node then
            for _, adj in ipairs(node.Neighbors) do
              local rd = floor.grid_room[adj]
              if rd and not reach[adj] and rd.VisitedCount > 0 and rd.Clear
                  and floor.linked(cur, adj) then
                reach[adj] = true
                queue[#queue + 1] = adj
              end
            end
          end
        end
        return reach
    end

    --which door of the target room to land at: the one facing the room a walk would
    --have come from. The game ignores Direction (measured twice) and picks the wall
    --from the two grid indices; only the cell handed over and the room left from
    --steer it, see landing_route.
    --route_parent: the step before the target on the shortest walk through walked rooms
    function M.route_parent(from, to)
        local parent = {[from] = from}
        local queue, head = {from}, 1
        while queue[head] do
          local cur = queue[head]
          head = head + 1
          if cur == to then break end
          local node = floor.room_neighbours[cur]
          if node then
            for _, adj in ipairs(node.Neighbors) do
              local rd = floor.grid_room[adj]
              --the target may be an uncleared neighbour: a landing, not a pass-through
              if rd and not parent[adj] and floor.linked(cur, adj)
                  and (adj == to or (rd.VisitedCount > 0 and rd.Clear)) then
                parent[adj] = cur
                queue[#queue + 1] = adj
              end
            end
          end
        end
        local p = parent[to]
        return p ~= to and p or nil
    end

    function M.landing_slot(from, to)
        local link = floor.door_graph()
        local slots = link[to]
        if not slots then return -1 end
        if type(slots[from]) == "number" then --neighbours: the door between them
          return slots[from]
        end
        local walked = M.route_parent(from, to)
        if walked and type(slots[walked]) == "number" then
          return slots[walked]
        end
        --no route to trace: fall back on the side the room being left lies on
        local function side(d, neg, pos)
          if d < 0 then return neg elseif d > 0 then return pos end
        end
        local dcol = from % 13 - to % 13
        local drow = (from - from % 13) / 13 - (to - to % 13) / 13
        local across, along = side(dcol, 0, 2), side(drow, 1, 3)
        if math.abs(drow) > math.abs(dcol) then across, along = along, across end
        --a big room has two doors to a side, 4-7 repeating 0-3; either is that side
        local function on_side(want)
          local best
          for _, s in pairs(slots) do
            if type(s) == "number" and (want == nil or s % 4 == want)
                and (best == nil or s < best) then
              best = s
            end
          end
          return best
        end
        return (across and on_side(across)) or (along and on_side(along))
          or on_side(nil) or -1
    end

    --the cell to hand the transition, and the room to leave from to make it stick.
    --The game reads the cell to pick among the doors on one wall, and the wall from
    --the room the trip starts in; so next door the cell is enough, further off the
    --trip must also start from the room the walk would have come from
    function M.landing_route(from, to)
        local cell = floor.touching_cell(from, to)
        if cell then return cell, nil end
        local walked = M.route_parent(from, to)
        if not walked then return nil, nil end
        return floor.touching_cell(walked, to), walked
    end

    function M.check_teleble(gid)
        if gid == -99 or (cfg.FollowCurseOfLost and floor.level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0) then
          return false
        elseif gt.debug and floor.grid_room[gid] then
          return true
        end
        local crd = floor.crd
        local cid = crd.SafeGridIndex
        if floor.grid_room[cid] == nil or not crd.Clear then
          return false
        elseif (crd.Data.Type == 6 or crd.Data.Type == 11) then --miniboss/challengeroom
          if not M.check_room_open() then
            return false
          end
        end
        if gid == false then return true end --current room only
        if floor.grid_room[gid] == nil then
          return false
        else
          local trd = floor.grid_room[gid]
          if trd.ListIndex == crd.ListIndex then
            return false
          end
          if cfg.AllowAnyRoom then
            return true
          end
          --the room stepped off from must be on the player's own island, else an
          --Emperor'd boss room is a free lift back across unexplored rooms
          local reach = cfg.FairTripPath and M.get_reachable_rooms() or nil
          if trd.VisitedCount > 0 and trd.Clear
              and (not reach or reach[trd.SafeGridIndex] == true) then
            --AllowNeighborRoom only widens this: an Emperor'd start room has no cleared neighbour
            return true
          elseif not cfg.AllowNeighborRoom then
            return false
          end
          --the last hop needs a door too; `reach` is nil exactly when path rules are off
          return M.check_neigh_connected(trd, function(rd)
              return (rd.DisplayFlags & 1 ~= 0) and rd.VisitedCount > 0 and rd.Clear
                and (not reach or (reach[rd.SafeGridIndex]
                  and floor.linked(rd.SafeGridIndex, trd.SafeGridIndex)))
          end)
        end
        return true
    end

    --is this curse-room door free? Isaac's Heart / Tooth and Nail take the hit.
    --Flat File acts on the door as the room is laid down, so the trinket in hand
    --only answers for a door about to be laid down again, not the one stood beside
    function M.curse_toll_free(gid, by_inner_door, room_reloads)
        local player = floor.player
        if player:HasCollectible(276) or player:HasCollectible(663) then
          return true
        end
        if room_reloads and player:HasTrinket(151) then
          return true
        end
        local bare = floor.curse_bare_outside[gid]
        if by_inner_door then bare = floor.curse_bare_inside[gid] end
        return bare == true
    end

    --BFS distance through cleared rooms; any room connected to the target is the last hop
    function M.fair_trip(roomIndex, target)
    	local grid_room, room_neighbours = floor.grid_room, floor.room_neighbours
    	local startRoom = grid_room[roomIndex]
    	local targetRoom = grid_room[target]
    	if not startRoom or not targetRoom then
    		return 0
    	end
    	local safeTarget = targetRoom.SafeGridIndex
    	local visited = {[startRoom.SafeGridIndex] = true}
    	local queue = {{room = startRoom, dist = 0}}
    	local head = 1
    	while queue[head] do
    		local cur = queue[head]
    		head = head + 1
    		local safeIndex = cur.room.SafeGridIndex
    		if safeIndex == safeTarget and cur.room.Clear then
    			return cur.dist
    		end
    		if M.check_neigh_connected(targetRoom, function(rd)
    			return rd.SafeGridIndex == safeIndex
    				and (not cfg.FairTripPath or floor.linked(safeIndex, safeTarget))
    		end) then
    			return cur.dist + 1
    		end
    		if cur.room.Clear then
    			for _, adj in ipairs(room_neighbours[cur.room.SafeGridIndex].Neighbors) do
            local adj_dsc = grid_room[adj]
    				local sid = adj_dsc.SafeGridIndex
    				if not visited[sid]
    					and (not cfg.FairTripPath or floor.linked(safeIndex, sid)) then
    					visited[sid] = true
    					queue[#queue+1] = {room = adj_dsc, dist = cur.dist + 1}
    				end
    			end
    		end
    	end
    	return 999
    end

    return M
end
