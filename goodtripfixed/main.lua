local hasoldgoodtrip = (gt and not gt.isgtfixed)
local _gt = RegisterMod("GoodTrip [Fixed]", 1)
gt = _gt
_gt.isgtfixed = true
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

local player = Isaac.GetPlayer(0)
local level = Game():GetLevel()
local stage = level:GetStage()
local stageeffect = 0
local room = Game():GetRoom()
local crd = level:GetCurrentRoomDesc()
local crid = crd.GridIndex
local crsid = crd.SafeGridIndex
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
local mouse_pressed = {false, false, false, false, false}
local icon_room = {"RoomOutline", "RoomVisited", "RoomUnvisited", "RoomCurrent"}
local icon_flag = {"1_IconNormal", "IconShop", "3_IconError", "IconTreasureRoom", "IconBoss",
                  "IconMiniboss", "IconSecretRoom", "IconSuperSecretRoom", "IconArcade", "IconCurseRoom",
                  "IconAmbushRoom", "IconLibrary", "IconSacrificeRoom", "IconDevilRoom", "IconAngelRoom",
                  "16_IconDungeon", "17_IconBossRush", "IconIsaacsRoom", "IconBarrenRoom", "IconChestRoom",
                  "IconDiceRoom", "22_IconBlackMarket", "23_IconGreedExit","IconPlanetarium","TeleporterRoom","TeleporterRoom","27_SecretExit","28_Blue","IconUltraSecretRoom"}
local icon_flag2 = {"IconLockedRoom", "IconTreasureRoomGreed", "IconBossAmbushRoom","IconTreasureRoomRed","IconMirrorRoom", "IconWhiteFireRoom","IconTintSkullRoom","IconMinecartRoom","IconMineButtonRoom"}
local scpos = Vector(0, 0)
local grid_room = {}
local grid_room_mark = {}
local room_neighbours = {}
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
local ctrl_ltroom = Vector(6, 6) --the same two corners before the widget's 3x3 padding widens them
local ctrl_rbroom = Vector(6, 6)
local mmp_pos0 = Vector(0, 0)
local mmp_ltpos_ = Vector(0, 0)
local mmp_ltpos = Vector(100, 100)
local mmp_rbpos_ = Vector(0, 0)
local mmp_rbpos = Vector(0, 0)
local d_pos = Vector(0, 0)
local mmp_pin = 0
local mouse_magnet = false
local mpos = Vector(0, 0)
local ui_timer = 0
local mmp_ctrl = false
local mmp_ctrl_pos = Vector(0, 0)
local fast_move_cd = {0, 0, 0, 0} --FasterCursorMove: per-direction hold-to-repeat cooldown
local FAST_MOVE_REPEAT_FRAMES = 6 --frames between room-jumps while a key stays held
local last_mpos = Vector(0, 0)
local mouse_moved = false --physical mouse motion this frame (tracked every frame in step)
local kb_active = false --keyboard is the active map-cursor device, for this opening of the map
local mouse_in_ui = false
local mmp_1step_tp = false
local mmp_1step_mgid = -1
local tele_maze = false
local tele_door_slot = -1 --the door a trip means to arrive by
--door graph, learned one room at a time: grid adjacency alone cannot tell a
--doorway from a secret room's unbombed wall. Per dimension: the mirror world
--reuses the same grid numbers for different rooms.
local door_link = {}  --door_link[dim][a][b]: a passage, seen from either end
local door_swept = {} --door_swept[dim][a]: a's own walls were read
local secret_pre_room_id = {}
--curse-room door spikes seen from outside / inside; Flat File strips only the
--side it was used on, so the two are kept apart
local curse_bare_outside, curse_bare_inside = {}, {}
local prep_alarm = false
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
--gon_ functions check REPENTOGON themselves: on a plain game every gon_ test is
--false and every gon_ action is a no-op. Nothing else may call a REPENTOGON-only API.
--(without REPENTOGON a cursor on the game's map draws behind it)
function _gt:gon_map_cursor()
    return REPENTOGON ~= nil and gtconfig.CursorOnGameMap
end
local mmsc = 1.0 --keyboard minimap scale factor (gtconfig.MinimapScale / 10)
local function update_mmscale()
    --hand-edited, so it can arrive as anything; a scale of 0 draws nothing
    local scale = gtconfig.MinimapScale
    if type(scale) ~= "number" or scale < 5 then
        scale = 5
    elseif scale > 25 then
        scale = 25
    end
    gtconfig.MinimapScale = scale
    mmsc = scale / 10
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
    config.save()
end

local hudoffset = Options.HUDOffset * 10
local debug = false
local tele_cd = 0
local bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}
if ModConfigMenu then
    include("scripts.mcm")({ cfg = gtconfig, config = config, widget = {
        --stand-ins until the widget is a module of its own
        rescale = function()
            update_mmscale()
            prep_alarm = true
        end,
        get_top_left = function()
            return mmp_ltpos.X, mmp_ltpos.Y
        end,
        set_top_left = function(x, y)
            mmp_ltpos = Vector(x, y)
            gtconfig.TopLeftX, gtconfig.TopLeftY = x, y --the window position rides in the settings
        end,
    } })
end
_gt:AddPriorityCallback(ModCallbacks.MC_POST_GAME_STARTED, CallbackPriority.EARLY, function(_, isContined)
    config.load_saved()
    mmp_ltpos = Vector(gtconfig.TopLeftX or 100, gtconfig.TopLeftY or 100)
    gtconfig.TopLeftX, gtconfig.TopLeftY = mmp_ltpos.X, mmp_ltpos.Y --the window position rides in the settings
    update_mmscale()
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

function _gt:check_pos_en_box(pos,ltpos,rbpos)
  if pos.X > ltpos.X and pos.X < rbpos.X and pos.Y > ltpos.Y and pos.Y < rbpos.Y then
    return true
  else
    return false
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

function _gt:check_neigh_connected(trd, cond)
    local tid = trd.SafeGridIndex
    if (trd.DisplayFlags & 1) ~= 0 then
      --a red-key room stands open already, whatever it turned out to hold
      if (trd.VisitedCount == 0 or not trd.Clear) and
        trd.Flags & RoomDescriptor.FLAG_RED_ROOM == 0 and
        trd.Data.Type ~= 1 and trd.Data.Type ~= 5 and
        trd.Data.Type ~= 6 and trd.Data.Type ~= 13 and
        not (((stage == 1 and level:GetStageType() < StageType.STAGETYPE_REPENTANCE) or room:IsMirrorWorld())
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
        local rd = grid_room[id]
        return rd ~= nil and cond(rd)
      end
      local near_room = {check_grid(-13), check_grid(13), check_grid(-1), check_grid(1)}
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
        if near_room[1] or near_room[4] or near_room[2] or near_room[3] then
          return true
        end
        for _, off in ipairs(neighlut[trd.Data.Shape]) do
            if check_grid(off) then
                return true
            end
        end
      end
    end
    return false
end

function _gt:get_reachable_rooms()
    --flood from the current room through visited+cleared rooms; each step needs
    --a door too, else a secret room counts as a corridor on all four sides
    local start = crd.SafeGridIndex
    _gt:sweep_doors() --a wall bombed since entering would still read as solid
    local reach = {[start] = true}
    local queue = {start}
    local head = 1
    while queue[head] do
      local cur = queue[head]
      local node = room_neighbours[cur]
      head = head + 1
      if node then
        for _, adj in ipairs(node.Neighbors) do
          local rd = grid_room[adj]
          if rd and not reach[adj] and rd.VisitedCount > 0 and rd.Clear
              and _gt:linked(cur, adj) then
            reach[adj] = true
            queue[#queue + 1] = adj
          end
        end
      end
    end
    return reach
end

--the door graph for the side of the mirror being stood on. Read off the live
--room, not the cached one: a trip hops through an antechamber mid-call
function _gt:door_graph()
    local d = Game():GetRoom():IsMirrorWorld() and 1 or 0
    door_link[d] = door_link[d] or {}
    door_swept[d] = door_swept[d] or {}
    return door_link[d], door_swept[d]
end

--read the current room's doors (the only room the game answers for) into the
--graph both ways. DOOR_HIDDEN is an unbombed wall, so no passage; everything
--else, locked included, is walkable. All read live so nothing is from different moments.
function _gt:sweep_doors()
    local live = Game():GetRoom()
    local lvl = Game():GetLevel()
    local here = lvl:GetCurrentRoomDesc().SafeGridIndex
    local link, swept = _gt:door_graph()
    link[here] = link[here] or {}
    swept[here] = true
    for i = 0, 7 do
      local door = live:GetDoor(i)
      if door and door.Desc.Variant ~= DoorVariant.DOOR_HIDDEN then
        local there = lvl:GetRoomByIdx(door.TargetRoomIndex, -1).SafeGridIndex
        --curse-room spikes are read off the door itself: Flat File strips them
        --once and for good, so the trinket in hand says nothing about this door
        if door.TargetRoomType == RoomType.ROOM_CURSE then
          curse_bare_outside[there] = door.VarData ~= 0
        elseif live:GetType() == RoomType.ROOM_CURSE then
          curse_bare_inside[here] = door.VarData ~= 0
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
function _gt:linked(a, b)
    local link, swept = _gt:door_graph()
    if link[a] and link[a][b] ~= nil then
      return true
    end
    return not (swept[a] or swept[b])
end

--which door of the target room to land at: the one facing the room a walk would
--have come from. The game ignores Direction (measured twice) and picks the wall
--from the two grid indices; only the cell handed over and the room left from
--steer it, see _gt:landing_route.
--route_parent: the step before the target on the shortest walk through walked rooms
function _gt:route_parent(from, to)
    local parent = {[from] = from}
    local queue, head = {from}, 1
    while queue[head] do
      local cur = queue[head]
      head = head + 1
      if cur == to then break end
      local node = room_neighbours[cur]
      if node then
        for _, adj in ipairs(node.Neighbors) do
          local rd = grid_room[adj]
          --the target may be an uncleared neighbour: a landing, not a pass-through
          if rd and not parent[adj] and _gt:linked(cur, adj)
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

function _gt:landing_slot(from, to)
    local link = _gt:door_graph()
    local slots = link[to]
    if not slots then return -1 end
    if type(slots[from]) == "number" then --neighbours: the door between them
      return slots[from]
    end
    local walked = _gt:route_parent(from, to)
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

--the target cell a walk from `from` would step into. Read off the grid, not the
--door sweep, so a room nobody has been inside yet answers too
function _gt:touching_cell(from, to)
    local src, dst = grid_room[from], grid_room[to]
    if not (src and dst) then return nil end
    for cell, d in pairs(grid_room) do
      if d.ListIndex == src.ListIndex then
        local col = cell % 13
        for _, step in ipairs({ -13, 13, -1, 1 }) do
          if not ((step == -1 and col == 0) or (step == 1 and col == 12)) then --column guard
            local nd = grid_room[cell + step]
            if nd and nd.ListIndex == dst.ListIndex then return cell + step end
          end
        end
      end
    end
    return nil
end

--the cell to hand the transition, and the room to leave from to make it stick.
--The game reads the cell to pick among the doors on one wall, and the wall from
--the room the trip starts in; so next door the cell is enough, further off the
--trip must also start from the room the walk would have come from
function _gt:landing_route(from, to)
    local cell = _gt:touching_cell(from, to)
    if cell then return cell, nil end
    local walked = _gt:route_parent(from, to)
    if not walked then return nil, nil end
    return _gt:touching_cell(walked, to), walked
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
    local door = room:GetDoor(slot)
    if not door then return end
    local dx, dy = 0, 0
    local side = slot % 4
    if side == 0 then dx = 40 elseif side == 2 then dx = -40
    elseif side == 1 then dy = 40 else dy = -40 end
    local stand = Vector(door.Position.X + dx, door.Position.Y + dy)
    --one shift for all, so a co-op pair keeps its spacing
    local shift = stand - player.Position
    for _, e in ipairs(_gt:landed_party()) do
      e.Position = e.Position + shift
    end
end

function _gt:check_teleble(gid)
    if gid == -99 or (gtconfig.FollowCurseOfLost and level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0) then
      return false
    elseif debug and grid_room[gid] then
      return true
    end
    local cid = crd.SafeGridIndex
    if grid_room[cid] == nil or not crd.Clear then
      return false
    elseif (crd.Data.Type == 6 or crd.Data.Type == 11) then --miniboss/challengeroom
      if not _gt:check_room_open() then
        return false
      end
    end
    if gid == false then return true end --current room only
    if grid_room[gid] == nil then
      return false
    else
      local trd = grid_room[gid]
      if trd.ListIndex == crd.ListIndex then
        return false
      end
      if gtconfig.AllowAnyRoom then
        return true
      end
      --the room stepped off from must be on the player's own island, else an
      --Emperor'd boss room is a free lift back across unexplored rooms
      local reach = gtconfig.FairTripPath and _gt:get_reachable_rooms() or nil
      if trd.VisitedCount > 0 and trd.Clear
          and (not reach or reach[trd.SafeGridIndex] == true) then
        --AllowNeighborRoom only widens this: an Emperor'd start room has no cleared neighbour
        return true
      elseif not gtconfig.AllowNeighborRoom then
        return false
      end
      --the last hop needs a door too; `reach` is nil exactly when path rules are off
      return _gt:check_neigh_connected(trd, function(rd)
          return (rd.DisplayFlags & 1 ~= 0) and rd.VisitedCount > 0 and rd.Clear
            and (not reach or (reach[rd.SafeGridIndex]
              and _gt:linked(rd.SafeGridIndex, trd.SafeGridIndex)))
      end)
    end
    return true
end

function _gt:hurt(n)
  player:TakeDamage(n, DamageFlag.DAMAGE_CURSED_DOOR | DamageFlag.DAMAGE_NO_PENALTIES, EntityRef(player), 0)
end

function _gt:tele_failed()
  sfx:Play(187, 0.5, 0, false, 1)
end

--is this curse-room door free? Isaac's Heart / Tooth and Nail take the hit.
--Flat File acts on the door as the room is laid down, so the trinket in hand
--only answers for a door about to be laid down again, not the one stood beside
function _gt:curse_toll_free(gid, by_inner_door, room_reloads)
    if player:HasCollectible(276) or player:HasCollectible(663) then
      return true
    end
    if room_reloads and player:HasTrinket(151) then
      return true
    end
    local bare = curse_bare_outside[gid]
    if by_inner_door then bare = curse_bare_inside[gid] end
    return bare == true
end

function _gt:check_curse_room(gid)
    if debug then return end
    --a bombed secret-room wall has no spikes, so secret<->guard room is free
    --both ways, even when the guard is the curse room
    if secret_pre_room_id[crid] == gid or secret_pre_room_id[gid] == crid then
      return
    end
    local trd = grid_room[gid]
    if crd.Data.Type == 10 then
      if not _gt:curse_toll_free(crsid, true, false) then
        _gt:hurt(1)
      end
    elseif trd.Data.Type == 10 and not player:IsFlying() then
      if not _gt:curse_toll_free(trd.SafeGridIndex, false, true) then
        _gt:hurt(1)
      end
    end
end

function _gt:teleport_to_grid_index(gid)
    for _,en in pairs(Isaac.GetRoomEntities()) do
			if en.Type == 867 then
        _gt:tele_failed()
        return
			end
		end
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
    _gt:check_curse_room(gid)
    level.EnterDoor = -1
    level.LeaveDoor = -1
    if level:GetCurses() & LevelCurse.CURSE_OF_MAZE ~= 0 then
      level:RemoveCurses(LevelCurse.CURSE_OF_MAZE)
      tele_maze = true
    end

    local dist = 0
    if gtconfig.FairTripTime then
      dist = _gt:fair_trip(crd.SafeGridIndex, gid)
      if dist == 999 then
        _gt:tele_failed()
        return
      end
    end

    --an L room's anchor cell is not in grid_room, so the antechamber may be missing
    local from_pre = crd.Data.Type == 7 and secret_pre_room_id[crid] or nil
    local from_prd = from_pre and grid_room[from_pre] or nil
    if from_prd then --from secret room
      if from_prd.ListIndex == grid_room[gid].ListIndex then
        gid = from_pre
      elseif not (grid_room[gid].Data.Type == 10 and secret_pre_room_id[gid] and secret_pre_room_id[gid] == crid) then
        --the toll is for the curse room's own door on the far side, not the bombed hole
        if from_prd.Data.Type == 10 and not _gt:curse_toll_free(from_prd.SafeGridIndex, true, true) then
          _gt:hurt(1)
        end
        Game():ChangeRoom(from_pre,-1)
      end
    end
    if grid_room[gid].Data.Type == 7 then --to secret room
      local to_pre = secret_pre_room_id[gid]
      local to_prd = to_pre and grid_room[to_pre] or nil
      if to_prd then
        if to_prd.ListIndex == crd.ListIndex then --crd, since grid_room[crid] is nil in an L room
          if crd.Data.Shape > 3 then
            Game():ChangeRoom(to_pre,-1)
          end
        elseif not (crd.Data.Type == 10 and secret_pre_room_id[crid] and secret_pre_room_id[crid] == gid) then
          if to_prd.Data.Type == 10 and not player:IsFlying()
              and not _gt:curse_toll_free(to_prd.SafeGridIndex, false, true) then
            _gt:hurt(1)
          end
          Game():ChangeRoom(to_pre,-1)
        end
      end
    end
    --read here, not up top: an antechamber hop may have moved the player
    local trd = grid_room[gid]
    local here = Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex
    local there = trd and trd.SafeGridIndex or gid
    tele_door_slot = -1
    local arrive = gid --the cell handed over; see _gt:landing_route
    if gtconfig.LandAtDoor then
      local cell, walked = _gt:landing_route(here, there)
      arrive = cell or gid
      --a room bigger than the screen, reached from further than next door, needs
      --the wall chosen too, and the wall comes from the room the trip starts in
      if walked and trd and trd.Data.Shape >= RoomShape.ROOMSHAPE_1x2 then
        Game():ChangeRoom(walked, -1)
        here = walked
      end
      tele_door_slot = _gt:landing_slot(here, there)
    end
    if debug then
      Game():ChangeRoom(arrive,-1)
    else
        if dist ~= 0 then
          local speed = player.MoveSpeed
          local addTime = math.floor((60.0*dist/speed)+0.5)
          Game().TimeCounter = Game().TimeCounter + addTime --boss rush reads TimeCounter; Hush does not
        end
      tele_cd = 45
      if not gtconfig.TeleportAnimation then tele_cd = 10 end
      if debug or gtconfig.FastTransition then tele_cd = 1 end
    end
    if gtconfig.FastTransition or debug then
      Game():ChangeRoom(arrive,-1)
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
    local tele_anime = gtconfig.TeleportAnimation and 3 or 1
    Game():StartRoomTransition(arrive, Direction.NO_DIRECTION, tele_anime, player, -1) --direction is ignored, measured twice
    tele_cd = tele_anime == 3 and 45 or 10
end

--hit-test against MinimapAPI's own rendered rooms: RenderOffset has position,
--display mode, pitch and the mirror flip baked in, so invert that
function _gt:get_pos_grid_index_minimapapi(pos)
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
    local rtr = _gt:get_corner_room(2)
    local ltx = scpos.X - (rtr.X + 1) * 17 - 4 - hudoffset * 2.4 --calibrated
    local lty = - (rtr.Y) * 15 + 5 + hudoffset * 1.3
    local mirrorsum = nil
    if room:IsMirrorWorld() then
      --the mirrored map keeps its box and flips the drawing about the box's middle
      local ltr = _gt:get_corner_room(3)
      mirrorsum = 2 * ltx + (ltr.X + rtr.X + 1) * 17
    end
    return ltx, lty, mirrorsum
end

function _gt:get_pos_grid_index(pos)
    if (not gtconfig.FollowCurseOfLost and level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0) then
      return -99
    end
    local mir = room:IsMirrorWorld()
    local calibx = mir and (gtconfig.CalibMirrorX or 0) or (gtconfig.CalibMainX or 0)
    local caliby = mir and (gtconfig.CalibMirrorY or 0) or (gtconfig.CalibMainY or 0)
    pos = Vector(pos.X + calibx, pos.Y + caliby) --fresh Vector: the caller's mouse position stays untouched
    if MinimapAPI then
      return _gt:get_pos_grid_index_minimapapi(pos)
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
function _gt:cell_to_screen(mgid, fcol, frow)
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
      local target = grid_room[mgid]
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
    local mir = room:IsMirrorWorld()
    local calibx = mir and (gtconfig.CalibMirrorX or 0) or (gtconfig.CalibMainX or 0)
    local caliby = mir and (gtconfig.CalibMirrorY or 0) or (gtconfig.CalibMainY or 0)
    local px = ltx + fcol * 17 + 8.5
    if mirrorsum then
      px = mirrorsum - px
    end
    return Vector(px - calibx, lty + frow * 15 + 7.5 - caliby), 1
end

function _gt:get_pos_grid_index_mmp(pos)
    if _gt:check_pos_en_box(pos,mmp_ltpos + Vector(1, 1) * mmsc, mmp_rbpos + Vector(11, 10) * mmsc) then
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

function _gt:get_room_neighbours()
    room_neighbours = {}
    local all_room = level:GetRooms()
    for i = 0, all_room.Size do
      local des = all_room:Get(i)
      if des then
            room_neighbours[des.SafeGridIndex] = {
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
      for _, room in pairs(room_neighbours) do
        local safeIndex = room.Descriptor.SafeGridIndex

        for gridIndex, cellRoom in pairs(grid_room) do
          if cellRoom.SafeGridIndex == safeIndex then
              for _, offset in ipairs(offsets) do
                  --column guard, as in check_neigh_connected
                  local wrapped = (offset == -1 and gridIndex % 13 == 0)
                               or (offset == 1 and gridIndex % 13 == 12)
                  local other = not wrapped and grid_room[gridIndex + offset] or nil

                  if other and other.SafeGridIndex ~= safeIndex then
                      room.Neighbors[other.SafeGridIndex] = true
                  end
              end
          end
        end
      end
      for _, room in pairs(room_neighbours) do
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
function _gt:get_corner_room(num)
    local corner_room = Vector(6, 6)
    local fx = {1, -1, 1, -1}
    local fy = {1, 1, -1, -1}
    local ffx = fx[num]
    local ffy = fy[num]
    for i = 6 - 6 * ffx, 6 + 6 * ffx, ffx do
      local found = false
      for j = 0, 12 do
        if grid_room[i+j*13] then
          if grid_room[i+j*13].DisplayFlags > 0 then
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
        if grid_room[i+j*13] then
          if grid_room[i+j*13].DisplayFlags > 0 then
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

function _gt:prep_minimap()
    draw_room_id = {}
    draw_room_pos = {}
    draw_room_shape = {}
    ltroom = _gt:get_corner_room(1)
    rbroom = _gt:get_corner_room(4)
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
    if mmp_ctrl then
      if mmp_1step_mgid == -2 then
      else
        local gx = crsid % 13
        local gy = (crsid - gx)/ 13
        mmp_ctrl_pos = mmp_pos0 + Vector(gx * 8 + 6, gy * 7 + 5) * mmsc
      end
    end
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

function _gt:draw_minimap_ui()
    if _gt:gon_map_cursor() then
      return
    end
    if not ((gtconfig.KeyboardMapEnable and _gt:check_teleble(false)) or debug) then
      ui_timer = 0
      return
    elseif ui_timer < 10 then
      ui_timer = ui_timer + 1
    end
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
    if mmp_pin == 1 then
      gtui:SetFrame("pin1", ui_timer)
    else
      gtui:SetFrame("pin0", ui_timer)
    end
    gtui:Render(mmp_ltpos, Vector(0, 0), Vector(0, 0))
    gtui:SetFrame("zoom", ui_timer)
    gtui:Render(mmp_ltpos + Vector(12, 0) * mmsc, Vector(0, 0), Vector(0, 0))
end

--the keyboard cursor drawn on the game's own map; selection and teleport logic untouched
function _gt:gon_draw_map_cursor()
    --checked here too: under REPENTOGON this also runs from MC_POST_HUD_RENDER
    if not _gt:gon_map_cursor() or not mmp_ctrl then
      return
    end
    --the game's map is always on screen, so draw nothing until an arrow key is
    --used: a red cursor on the current room would greet anyone just reading it
    if not kb_active then
      return
    end
    local mgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
    if mgid < 0 then
      return
    end
    --fractional cell position, so the sprite glides instead of snapping
    local fcol = (mmp_ctrl_pos.X - mmp_pos0.X - 2 * mmsc) / (8 * mmsc)
    local frow = (mmp_ctrl_pos.Y - mmp_pos0.Y - 2 * mmsc) / (7 * mmsc)
    local center, scale = _gt:cell_to_screen(mgid, fcol, frow)
    if not center then
      return
    end
    if _gt:check_teleble(mgid) then
      cursor.Color = Color(1, 1, 1, 1, 0, 0, 0)
    else
      cursor.Color = Color(1, 0.3, 0.3, 1, 0, 0, 0) --not teleportable
    end
    --(1, 9): cursor.anm2's pivot is the pointer's hotspot, not its centre.
    --gmcoff: residual measured in-game under REPENTOGON, X flips with the mirror
    local gmcoff = room:IsMirrorWorld() and Vector(9, 2) or Vector(-8, 2)
    cursor.Scale = Vector(scale, scale)
    cursor:Render(center - Vector(1, 9) * scale + gmcoff, Vector(0, 0), Vector(0, 0))
    cursor.Scale = Vector(1, 1)
    cursor.Color = Color(1, 1, 1, 1, 0, 0, 0)
end

function _gt:draw_minimap(faint)
    if _gt:gon_map_cursor() then
      --under REPENTOGON the game's map is drawn in MC_HUD_RENDER, so the cursor
      --goes in MC_POST_HUD_RENDER instead
      if not REPENTOGON then
        _gt:gon_draw_map_cursor()
      end
      return
    end
    --faint: uncleared room, window drawn dim without chrome or cursor
    local alpha = faint and math.min(math.max(gtconfig.DimMapAlpha or 35, 5), 100) / 100 or 1
    mic.Color = Color(1, 1, 1, alpha, 0, 0, 0)
    select.Color = Color(1, 1, 1, alpha, 0, 0, 0)
    mmp.Color = Color(1, 1, 1, alpha, 0, 0, 0)
    mmp:SetFrame(icon_room[1], 0)
    for i = 1, #draw_room_id do
      local s = grid_room[draw_room_id[i]].Data.Shape
      if (not room:IsMirrorWorld() and s == RoomShape.ROOMSHAPE_LTL) or (room:IsMirrorWorld() and s >= RoomShape.ROOMSHAPE_2x1 and s ~= RoomShape.ROOMSHAPE_LTL) then
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
        local markclr = grid_room_mark[rd.SafeGridIndex]
        if markclr ~= nil then
            mmp.Color = Color(markclr.Red, markclr.Green, markclr.Blue, alpha, 0, 0, 0)
        else
            mmp.Color = Color(1, 1, 1, alpha, 0, 0, 0)
        end
      end
      if rd.SafeGridIndex == draw_room_id[i] or (rd.Data.Type == 5 and stage == 12) then
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
        mmp.Color = Color(1, 1, 1, alpha, 0, 0, 0)
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
        --visited only: read from the spawn list, so drawing early spoils the floor
        elseif gtconfig.ShowSpecialIcons and rd.Data.Type == 1 and rd.VisitedCount > 0 then
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
    if mmp_ctrl then
      checkid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
    else
      checkid = _gt:get_pos_grid_index_mmp(_gt:mirror_mmp_pos(mpos))
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
        if _gt:check_teleble(checkid) then
          select:SetFrame("select", draw_room_shape[at])
        else
          select:SetFrame("select_false", draw_room_shape[at])
        end
        select:Render(draw_room_pos[at], Vector(0, 0), Vector(0, 0))
      end
    end
    if mmp_ctrl and not faint then
      cursor:Render(_gt:mirror_mmp_pos(mmp_ctrl_pos), Vector(0, 0), Vector(0, 0))
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

function _gt:mmp_ctrl_move()
    for i = 1,4 do
      if gtconfig.QuicklyOneRoomMove then
        if Input.IsActionTriggered(config.movkey[i], player.ControllerIndex) then
          local npos = clamp_ctrl_pos(mmp_ctrl_pos + _gt:mirror_mmp_dir(config.dir[i] * Vector(8, 7) * mmsc))
          if npos.X ~= mmp_ctrl_pos.X or npos.Y ~= mmp_ctrl_pos.Y then
            mmp_ctrl_pos = npos
            local nmgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
            if _gt:check_teleble(nmgid) and tele_cd < 1 then
              mmp_1step_tp = true
              mmp_1step_mgid = nmgid
            end
          end
        end
      end
      if gtconfig.FasterCursorMove then
        --a tap jumps at once; held, it repeats a room at a time
        if Input.IsActionPressed(config.key[i], player.ControllerIndex) then
          if fast_move_cd[i] <= 0 then
            mmp_ctrl_pos = clamp_ctrl_pos(mmp_ctrl_pos + _gt:mirror_mmp_dir(config.dir[i]) * Vector(8, 7) * mmsc)
            fast_move_cd[i] = FAST_MOVE_REPEAT_FRAMES
          else
            fast_move_cd[i] = fast_move_cd[i] - 1
          end
        else
          fast_move_cd[i] = 0
        end
      else
        if Input.IsActionPressed(config.key[i], player.ControllerIndex) then
          local step = _gt:mirror_mmp_dir(config.dir[i]) * mmsc
          if _gt:gon_map_cursor() then
            step = step * Vector(8 / 17, 7 / 15) --game-map cells are 17x15, the widget's 8x7
          end
          mmp_ctrl_pos = clamp_ctrl_pos(mmp_ctrl_pos + step)
        end
      end
    end
end

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

--uncleared room: draw the window faint and inert instead of hiding it (hidden
--reads as "mod broken"). Not for Curse of the Lost or an unknown room
function _gt:dim_map_only()
    return gtconfig.KeyboardMapEnable and gtconfig.DimMapInCombat
        and not _gt:check_teleble(false)
        and grid_room[crd.SafeGridIndex] ~= nil
        and not (gtconfig.FollowCurseOfLost and level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0)
end

function _gt:tab_action()
    local cp = Isaac.WorldToRenderPosition(Vector(320,280))
    scpos = cp + cp
    hudoffset = Options.HUDOffset * 10 --live: the map moves the moment the slider moves
    if gtconfig.FastRestartEnable
        and (Input.IsButtonTriggered(Keyboard.KEY_R, player.ControllerIndex)
            or (gtconfig.ControllerAlternateR and Input.IsButtonTriggered(gtconfig.ControllerAlternateR, player.ControllerIndex))) then
      print('GoodTrip [Fixed] !!!FAST RESTARTING!!!')
      Isaac.ExecuteCommand("restart")
    end
    if gtconfig.QuicklyOneRoomMove and crd.Clear and player.ControlsCooldown < 2 then
      player.ControlsCooldown = player.ControlsCooldown + 1
    end
    if _gt:dim_map_only() and not debug then
      mmp_ctrl = false --no cursor while inert
      _gt:draw_minimap(true)
    elseif (gtconfig.KeyboardMapEnable and _gt:check_teleble(false)) or debug then
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
        if _gt:gon_map_cursor() then
          in_ui = _gt:get_pos_grid_index(mpos) >= 0
        else
          in_ui = _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-8, -18) * mmsc,mmp_rbpos + Vector(20, 20) * mmsc) --ui zone
        end
        if arrowdown then
          kb_active = true
        elseif mouse_moved and in_ui then
          kb_active = false
        end
        if kb_active or not in_ui then --keyboard owns the cursor
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
        else --mouse owns the cursor
          mmp_ctrl = false
        end
        _gt:draw_minimap_ui()
      else
        --a movement key only pauses the cursor; dropping mmp_ctrl would lose the aimed room
        if mmp_pin == 1 or _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-8, -18) * mmsc,mmp_rbpos + Vector(20, 20) * mmsc) then --ui zone
          _gt:draw_minimap_ui()
        else
          ui_timer = 0
        end
      end
      _gt:draw_minimap()
    end
    _gt:mouse_action()
end

function _gt:mirror_mmp_pos(p)
    if room:IsMirrorWorld() then
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

--nil follows the vanilla map key; a custom binding replaces it (dodges EID's TAB overlay)
function _gt:is_overlay_triggerd()
    if gtconfig.OverlayKey or gtconfig.OverlayKeyController then
      return (gtconfig.OverlayKey ~= nil and Input.IsButtonTriggered(gtconfig.OverlayKey, 0))
          or (gtconfig.OverlayKeyController ~= nil and Input.IsButtonTriggered(gtconfig.OverlayKeyController, player.ControllerIndex))
    end
    return Input.IsActionTriggered(ButtonAction.ACTION_MAP, player.ControllerIndex)
end

function _gt:is_overlay_pressed()
    if gtconfig.OverlayKey or gtconfig.OverlayKeyController then
      return (gtconfig.OverlayKey ~= nil and Input.IsButtonPressed(gtconfig.OverlayKey, 0))
          or (gtconfig.OverlayKeyController ~= nil and Input.IsButtonPressed(gtconfig.OverlayKeyController, player.ControllerIndex))
    end
    return Input.IsActionPressed(ButtonAction.ACTION_MAP, player.ControllerIndex)
end

function _gt:mouse_action()
    if _gt:IsMouseBtnTriggered(0) then
      if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
        _gt:pre_secret_room()
      elseif crd.Data.Type == 10 then
        _gt:pre_secret_curse_room()
      end
      local mgid = _gt:get_pos_grid_index(mpos)
      if (_gt:check_teleble(mgid) and tele_cd < 1) then
        _gt:teleport_to_grid_index(mgid)
      elseif gtconfig.KeyboardMapEnable and not _gt:gon_map_cursor() then --widget zones, only while it is visible
        mgid = _gt:get_pos_grid_index_mmp(_gt:mirror_mmp_pos(mpos))
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
      end
    end
    if not gtconfig.KeyboardMapEnable then return end
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
        if _gt:check_pos_en_box(mpos, cp + Vector(-16, -16), cp + Vector(16, 116)) then
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
        if _gt:check_pos_en_box(mpos, cp + Vector(-16, -16), cp + Vector(16, 16)) then
          gtconfig.KeyboardMapEnable = false
        end
      end
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
      gtconfig.TopLeftX, gtconfig.TopLeftY = mmp_ltpos.X, mmp_ltpos.Y --the window position rides in the settings
      if drag_ended then --alt-F4 and TAB+R never reach MC_PRE_GAME_EXIT
        config.save()
      end
    end
end

function _gt:itemused()
    mmp_ctrl = false
    _gt:get_grid_room()
    _gt:get_room_neighbours()
    _gt:prep()
end
function _gt:check_and_tele_room(tgid)
    if (_gt:check_teleble(tgid) and tele_cd < 1) then
        if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
            _gt:pre_secret_room()
        elseif crd.Data.Type == 10 then
            _gt:pre_secret_curse_room()
        end
        _gt:teleport_to_grid_index(tgid)
        mmp_ctrl = false
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
    mpos = Isaac.WorldToScreen(Input.GetMousePosition(true))
    mouse_moved = (mpos - last_mpos):LengthSquared() > 4 --every frame, so the baseline is fresh at TAB-open
    last_mpos = mpos

    if _gt:is_overlay_triggerd() then
      _gt:get_grid_room()
      _gt:prep()
      kb_active = false --every opening starts as a read; an arrow key claims it
    end

    if _gt:is_overlay_pressed() then
      if gtconfig.LastRoomShortcut then
        if Input.IsButtonTriggered(Keyboard.KEY_Z, player.ControllerIndex)
        or (gtconfig.ControllerAlternateZ and Input.IsButtonTriggered(
                    gtconfig.ControllerAlternateZ, player.ControllerIndex)) then
         _gt:check_and_tele_room(level:GetLastRoomDesc().SafeGridIndex)
        end
      end
      if gtconfig.AllowBookmarking then
        --whatever is aimed at: keyboard cursor, else mouse (game map, then
        --widget, the order a click resolves in), else the current room
        local mgid = crd.SafeGridIndex
        if gtconfig.KeyboardMapEnable and mmp_ctrl then
            mgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
        else
            local aim = _gt:get_pos_grid_index(mpos)
            if aim < 0 and gtconfig.KeyboardMapEnable then
                aim = _gt:get_pos_grid_index_mmp(_gt:mirror_mmp_pos(mpos))
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
            mmp_ctrl = false
          end
        end
        _gt:draw_minimap_ui()
      else
        _gt:tab_action()
      end
    elseif (gtconfig.KeyboardMapEnable) or debug then
      --pinned window without TAB
      if mmp_pin == 1 and not _gt:gon_map_cursor() and crd.Clear and _gt:check_teleble(false) then
        if mouse_in_ui then
          if gtconfig.NoShootWhenClick then
            _gt:player_shoot_cooldown()
          end
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
          _gt:draw_minimap_ui()
        else
          ui_timer = 0
        end
        _gt:draw_minimap()
      elseif mmp_pin == 1 and not _gt:gon_map_cursor() and _gt:dim_map_only() and not debug then
        ui_timer = 0
        mmp_ctrl = false
        _gt:draw_minimap(true)
      else
        ui_timer = 0
      end
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
    end
    if prep_alarm then
      _gt:prep_minimap()
      prep_alarm = false
    end
    if tele_cd > 0 then
      tele_cd = tele_cd - 1
    end
end

function _gt:step2()
    --a wall can open under the player's feet (bomb, red key), so sweep every
    --tick; but not mid-transition, when the live room and the cached descriptor disagree
    if level:GetCurrentRoomDesc().SafeGridIndex == crsid then
      _gt:sweep_doors()
    end
    if mmp_pin == 1 and gtconfig.KeyboardMapEnable then
      mpos = Isaac.WorldToScreen(Input.GetMousePosition(true))
      if _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-8, -18) * mmsc,mmp_rbpos + Vector(20, 20) * mmsc) then --ui zone
        mouse_in_ui = true
      else
        mouse_in_ui = false
      end
    end
end

function _gt:new_room()
    warn_in_run = true
    local last_crd = crd
    _gt:get_grid_room()
    _gt:get_room_neighbours()
    room = Game():GetRoom()
    crd = level:GetCurrentRoomDesc()
    crid = crd.GridIndex
    crsid = crd.SafeGridIndex
    _gt:sweep_doors()
    mmp_ctrl = false
    kb_active = false
    player = Isaac.GetPlayer(0)
    stage = level:GetStage()
    _gt:land_at_door()
    if gtconfig.KeyboardMapEnable then
      prep_alarm = true
      _gt:prep_minimap()
    end
    if tele_maze then
      level:AddCurse(LevelCurse.CURSE_OF_MAZE,false)
      tele_maze = false
    end
    if last_crd.Data then
      if last_crd.Data.Type == 7 or (last_crd.Data.Type == 8 and Game():IsGreedMode()) then
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
      end
    end
    if crd.Data.Type == 7 or (crd.Data.Type == 8 and Game():IsGreedMode()) then
      _gt:pre_secret_room()
    elseif crd.Data.Type == 10 then
      _gt:pre_secret_curse_room()
    end
end

function _gt:new_level()
    hudoffset = Options.HUDOffset * 10
    bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}
    curse_bare_outside, curse_bare_inside = {}, {}
    level = Game():GetLevel()
    _gt:get_grid_room()
    _gt:get_room_neighbours()
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
    door_link = {}
    door_swept = {}
    if gtconfig.KeyboardMapEnable then
      prep_alarm = true
      _gt:prep_minimap()
    end
end
function _gt:get_config()
    return gtconfig
end

--BFS distance through cleared rooms; any room connected to the target is the last hop
function _gt:fair_trip(roomIndex, target)
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
		if _gt:check_neigh_connected(targetRoom, function(rd)
			return rd.SafeGridIndex == safeIndex
				and (not gtconfig.FairTripPath or _gt:linked(safeIndex, safeTarget))
		end) then
			return cur.dist + 1
		end
		if cur.room.Clear then
			for _, adj in ipairs(room_neighbours[cur.room.SafeGridIndex].Neighbors) do
        local adj_dsc = grid_room[adj]
				local sid = adj_dsc.SafeGridIndex
				if not visited[sid]
					and (not gtconfig.FairTripPath or _gt:linked(safeIndex, sid)) then
					visited[sid] = true
					queue[#queue+1] = {room = adj_dsc, dist = cur.dist + 1}
				end
			end
		end
	end
	return 999
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
  _gt:AddCallback(ModCallbacks.MC_POST_HUD_RENDER, _gt.gon_draw_map_cursor)
end
