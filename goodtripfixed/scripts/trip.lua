--performing a teleport: the refusals, the curse-room tolls, the maze curse
--lifted and restored, the antechamber hops, the time charge, the transition,
--the landing at the door a walk would have used, and the cooldown after
return function(deps)
    local gt, cfg, floor, rules, widget = deps.gt, deps.cfg, deps.floor, deps.rules, deps.widget
    local M = {}

    local sfx = SFXManager()
    local tele_cd = 0
    local tele_maze = false
    local tele_door_slot = -1 --the door a trip means to arrive by

    --the cooldown has run out, so a trip may start
    function M.ready()
        return tele_cd < 1
    end
    --once a frame
    function M.tick()
        if tele_cd > 0 then
          tele_cd = tele_cd - 1
        end
    end
    --on arrival: a maze curse lifted for the trip comes back
    function M.restore_maze()
        if tele_maze then
          floor.level:AddCurse(LevelCurse.CURSE_OF_MAZE,false)
          tele_maze = false
        end
    end

    --everyone a landing carries: players, familiars by type, and anything owned by
    --a player (Mom's Knife, a carried tear)
    function M.landed_party()
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
    function M.land_at_door()
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
        for _, e in ipairs(M.landed_party()) do
          e.Position = e.Position + shift
        end
    end

    function M.hurt(n)
      local player = floor.player
      player:TakeDamage(n, DamageFlag.DAMAGE_CURSED_DOOR | DamageFlag.DAMAGE_NO_PENALTIES, EntityRef(player), 0)
    end

    function M.tele_failed()
      sfx:Play(187, 0.5, 0, false, 1)
    end

    function M.check_curse_room(gid)
        if gt.debug then return end
        local crid = floor.crid
        --a bombed secret-room wall has no spikes, so secret<->guard room is free
        --both ways, even when the guard is the curse room
        if floor.secret_pre_room_id[crid] == gid or floor.secret_pre_room_id[gid] == crid then
          return
        end
        local trd = floor.grid_room[gid]
        if floor.crd.Data.Type == 10 then
          if not rules.curse_toll_free(floor.crsid, true, false) then
            M.hurt(1)
          end
        elseif trd.Data.Type == 10 and not floor.player:IsFlying() then
          if not rules.curse_toll_free(trd.SafeGridIndex, false, true) then
            M.hurt(1)
          end
        end
    end

    --floor.* is read at each use, never copied at the top: an antechamber hop
    --mid-call changes the room, and with it the descriptor and the grid
    function M.teleport_to_grid_index(gid)
        for _,en in pairs(Isaac.GetRoomEntities()) do
    			if en.Type == 867 then
            M.tele_failed()
            return
    			end
    		end
        if floor.crd.Data.Name == "Mom" or floor.crd.Data.Name == "Ultra Greed" then
          M.tele_failed()
          return
        elseif floor.grid_room[gid].Data.Type == 11 and not floor.grid_room[gid].ChallengeDone then
          if floor.stage%2 == 0 and floor.stage ~= 10 then
            if floor.player:GetHearts()+floor.player:GetSoulHearts()+ floor.player:GetBlackHearts() > 2 then
              M.tele_failed()
              return
            end
          else
            if floor.player:GetHearts() + floor.player:GetSoulHearts() + floor.player:GetBlackHearts() < floor.player:GetMaxHearts() then
              M.tele_failed()
              return
            end
          end
        end
        M.check_curse_room(gid)
        floor.level.EnterDoor = -1
        floor.level.LeaveDoor = -1
        if floor.level:GetCurses() & LevelCurse.CURSE_OF_MAZE ~= 0 then
          floor.level:RemoveCurses(LevelCurse.CURSE_OF_MAZE)
          tele_maze = true
        end

        local dist = 0
        if cfg.FairTripTime then
          dist = rules.fair_trip(floor.crd.SafeGridIndex, gid)
          if dist == 999 then
            M.tele_failed()
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
              M.hurt(1)
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
                M.hurt(1)
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
        local arrive = gid --the cell handed over; see rules.landing_route
        if cfg.LandAtDoor then
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
        if gt.debug then
          Game():ChangeRoom(arrive,-1)
        else
            if dist ~= 0 then
              local speed = floor.player.MoveSpeed
              local addTime = math.floor((60.0*dist/speed)+0.5)
              Game().TimeCounter = Game().TimeCounter + addTime --boss rush reads TimeCounter; Hush does not
            end
          tele_cd = 45
          if not cfg.TeleportAnimation then tele_cd = 10 end
          if gt.debug or cfg.FastTransition then tele_cd = 1 end
        end
        if cfg.FastTransition or gt.debug then
          Game():ChangeRoom(arrive,-1)
          Game():GetRoom():PlayMusic()
          widget.take_cursor()
          return
        end
        local tele_anime = cfg.TeleportAnimation and 3 or 1
        Game():StartRoomTransition(arrive, Direction.NO_DIRECTION, tele_anime, floor.player, -1) --direction is ignored, measured twice
        tele_cd = tele_anime == 3 and 45 or 10
    end

    return M
end
