local hasoldgoodtrip = (gt and not gt.isgtfixed)
local _gt = RegisterMod("GoodTrip [Fixed]", 1)
local CS = include("isaaccs_sdk")
local DoorGraph = include("door_graph")
local RoutePlanner = include("route_planner")
CS.Declare(_gt, {version = "2.2.39", api = 1})
gt = _gt
_gt.isgtfixed = true
local function show_warn(warnmsg)
    local warncounter = 300
    print(warnmsg)
    _gt:AddCallback(ModCallbacks.MC_POST_RENDER, function (_)
        if warncounter >= 0 then
            local alpha = math.min(60, math.max(0, warncounter)) / 60
            local player = CS.GetLocalPlayer()
            if not player then return end
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
local input_controller = 0
local player, level, stage, room, crd, crsid
local dimension = 0

local function get_dimension(current_level, current_room)
    if current_level.GetDimension then return current_level:GetDimension() end
    return current_room:IsMirrorWorld() and 1 or 0
end

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
local red_room_flag = (RoomDescriptor and RoomDescriptor.FLAG_RED_ROOM) or (1 << 10)
local scpos = Vector(0, 0)
local grid_room = {}
local grid_room_mark = {}
local draw_room_id = {}
local draw_room_pos = {}
local draw_room_shape = {}
local draw_icon_pos = {Vector(0, 0),Vector(0, 0),Vector(0, 0),Vector(0,3),
                      Vector(0,3),Vector(4, 0),Vector(4, 0),Vector(4,3),
                      Vector(8, 7),Vector(0, 7),Vector(8, 0),Vector(0, 0),}

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
local mmp_1step_tp = false
local mmp_1step_mgid = -1
--
local tele_maze = false
local travel_applying = false
local pending_travel
local door_history = {}
local live_doors = {}
local route_graph
local prep_alarm = false
local host_initialized = false
local host_room_count
local client_map_frame, client_map_signature
local client_special_icons = {}
local shoot_blocks = {}
local shoot_intent_blocked = false
local shoot_renew_at, shoot_retry_at = 0, 0
local shoot_renew_interval = 250 -- milliseconds
local shoot_block_timeout = 1000
--
	Controller = Controller or {}
	Controller.DPAD_LEFT = 0
	Controller.DPAD_RIGHT = 1
	Controller.DPAD_UP = 2
	Controller.DPAD_DOWN = 3
	Controller.BUTTON_A = 4
	Controller.BUTTON_B = 5
	Controller.BUTTON_X = 6
	Controller.BUTTON_Y = 7
	Controller.BUMPER_LEFT = 8
	Controller.TRIGGER_LEFT = 9
	Controller.STICK_LEFT = 10
	Controller.BUMPER_RIGHT = 11
	Controller.TRIGGER_RIGHT = 12
	Controller.STICK_RIGHT = 13
	Controller.BUTTON_BACK = 14
	Controller.BUTTON_START = 15
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
    FairTripTime = false,  --weather to incur fair time according to distance; off by default so the apiless rework doesn't spring time penalties on existing players
    FairTripPath = true,  --true = enable / false = disable. only trip to rooms linked to the current one by cleared rooms
    ShowSpecialIcons = true,  --show icons on room that have mirror, white fireplace, minecart, mine button, or tinted skull
    -- ShowDoorsAllowed = false,  --show doors allowed for secret rooms
    -- DebugMod = false,  --testonly.
    ControllerAlternateZ = nil,  --replacement for Z in the TAB+Z last room shortcut
    ControllerAlternateR = nil,  --replacement for R in the TAB+R restart shortcut
    MinimapScale = 10,  --keyboard minimap size, 5 = 0.5x .. 10 = 1.0x .. 25 = 2.5x
    --for users with MCM that want their overlay key to always be the map key
    OverlayKey = nil,  --The key to open the overlay on keyboard
    OverlayKeyController = nil, --The button to open the overlay on controller
    SwapAnalogSticks = false, --Swap the left and right analog sticks
    GameMapCursor = false, --draw the keyboard cursor on the game's own map instead of the aux widget
    --self-service calibration for corner-map clicks, in pixels: if clicks land
    --one room LEFT of where you aim, increase; RIGHT of aim, decrease
    --(Y likewise: land ABOVE your aim, increase; BELOW, decrease)
    CalibMainX = 0,
    CalibMirrorX = 0,
    CalibMainY = 0,
    CalibMirrorY = 0,
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

local function update_analog_mappings()
    if gtconfig.SwapAnalogSticks then
        key = {ButtonAction.ACTION_UP, ButtonAction.ACTION_LEFT, ButtonAction.ACTION_RIGHT, ButtonAction.ACTION_DOWN}
        movkey = {ButtonAction.ACTION_SHOOTUP, ButtonAction.ACTION_SHOOTLEFT, ButtonAction.ACTION_SHOOTRIGHT, ButtonAction.ACTION_SHOOTDOWN}
    else
        key = {ButtonAction.ACTION_SHOOTUP, ButtonAction.ACTION_SHOOTLEFT, ButtonAction.ACTION_SHOOTRIGHT, ButtonAction.ACTION_SHOOTDOWN}
        movkey = {ButtonAction.ACTION_UP, ButtonAction.ACTION_LEFT, ButtonAction.ACTION_RIGHT, ButtonAction.ACTION_DOWN}
    end
end
update_analog_mappings() --the other calls live in the MCM block, so hand-edited configs would never take effect
----
local hudoffset = Options.HUDOffset * 10  --need your real hudoffset of game [0,10]
local debug = false
local travel_cooldown = 0
local bookmarks = {} -- TAB+1~9 记录或跳转，TAB+0 清空。本机每层一份。
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
        { "FastRestartEnable", "Allow restarting the run quickly via TAB + R" },
        { "NoShootWhenClick", "Disable shooting while holding the map key" },
        { "FasterCursorMove", "Move cursor faster in keyboard minimap by press arrow keys once instead of having to hold them" },
        { "GameMapCursor", "Draw the keyboard/controller cursor on the game's own map (top-right corner map or MinimapAPI) instead of the mod's draggable widget" },

        { "ShowSpecialIcons", "Show an icon on room that have mirror, white fireplace, minecart, mine button, or tinted skull" },
        { "DangerCautionCompat", "weather to work with my other mod 'Dangerous room! Caution' (if detected) by indicate dangerous room by colors" },
        { "FairTripTime", "Fairly increase game time according to player move speed and distance" },
        { "FairTripPath", "Only allow teleport to rooms reachable through cleared rooms" },
        { "FastTransition", "Even faster transition without animation" },
    }) do
        ModConfigMenu.AddSetting(
          "GoodTrip [Fixed]", "General",
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
      "GoodTrip [Fixed]", "General",
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
      "GoodTrip [Fixed]", "General",
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
      "GoodTrip [Fixed]", "General",
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
    for _, info in ipairs({
        { "CalibMainX", "CalibClickMain", "Corner-map click calibration in normal world (pixels): clicks landing LEFT of your aim -> increase, RIGHT of aim -> decrease" },
        { "CalibMirrorX", "CalibClickMirror", "Corner-map click calibration in mirror world (pixels): clicks landing LEFT of your aim -> increase, RIGHT of aim -> decrease" },
        { "CalibMainY", "CalibClickMainY", "Corner-map click calibration in normal world (pixels): clicks landing ABOVE your aim -> increase, BELOW your aim -> decrease" },
        { "CalibMirrorY", "CalibClickMirrorY", "Corner-map click calibration in mirror world (pixels): clicks landing ABOVE your aim -> increase, BELOW your aim -> decrease" },
    }) do
        ModConfigMenu.AddSetting(
          "GoodTrip [Fixed]", "General",
          {
            Type = ModConfigMenu.OptionType.NUMBER,
            Minimum = -100, --several cells: game builds re-anchor the corner map whole cells apart, ±1 cell wasn't enough
            Maximum = 100,
            Default = 0,
            CurrentSetting = function()
              return gtconfig[info[1]] or 0
            end,
            Display = function()
              return ("%s: %+dpx"):format(info[2], gtconfig[info[1]] or 0)
            end,
            OnChange = function(b)
              gtconfig[info[1]] = b
            end,
            Info = { info[3] },
          }
        )
    end
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", "General",
      {
        Type = ModConfigMenu.OptionType.BOOLEAN,
        CurrentSetting = function()
          return gtconfig["SwapAnalogSticks"]
        end,
        Display = function()
          return "SwapAnalogSticks" .. ": " .. (gtconfig["SwapAnalogSticks"] and "on" or "off")
        end,
        OnChange = function(b)
          gtconfig["SwapAnalogSticks"] = b
          update_analog_mappings()
        end,
        Info = { "Swap the left and right analog sticks" },
      }
    )
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]",  "Keybinds",
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
      "GoodTrip [Fixed]",  "Keybinds",
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
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", "Keybinds",
      {
        Type = ModConfigMenu.OptionType.KEYBIND_KEYBOARD,
        CurrentSetting = function()
          return gtconfig.OverlayKey
        end,
        Default = Keyboard.KEY_TAB,
        Display = function()
          return "OverlayKey: " .. (
                    gtconfig.OverlayKey and
                    InputHelper.KeyboardToString[gtconfig.OverlayKey]
                    or 'None'
                )
        end,
        OnChange = function(b)
          gtconfig.OverlayKey = b
        end,
            PopupGfx = ModConfigMenu.PopupGfx.WIDE_SMALL,
            PopupWidth = 280,
            Popup = function()
                return "Press a button on your controller to change this setting."
            end,
        Info = { "Keyboard key to open the overlay" },
      }
    )

  -- Controller keybind
  -- here we bind Controller input instead of Action input to allow 
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", "Keybinds",
      {
        Type = ModConfigMenu.OptionType.KEYBIND_CONTROLLER,
        CurrentSetting = function()
          return gtconfig.OverlayKeyController
        end,
        Default = Controller.BUTTON_BACK,
        Display = function()
          return "OverlayKeyController: " .. (
                    gtconfig.OverlayKeyController and
                    InputHelper.ControllerToString[gtconfig.OverlayKeyController]
                    or 'None'
                )
        end,
        OnChange = function(b)
          gtconfig.OverlayKeyController = b
        end,
            PopupGfx = ModConfigMenu.PopupGfx.WIDE_SMALL,
            PopupWidth = 280,
            Popup = function()
                return "Press a button on your controller to change this setting."
            end,
        Info = { "Controller button to open the overlay" },
      }
    )
    local function load_config()
        if _gt:HasData() then
            local dat = _gt:LoadData()
            oldcfgdatas = dat
            local json = require('json')
            local cfg = json.decode(dat)
            if type(cfg) ~= "table" then return end
            for k, v in pairs(cfg) do
                gtconfig[k] = v
            end
            --one-shot migration: FairTripTime used to be inert unless the (now
            --retired) MinimapAPICompat switch was on, yet every old save stores
            --FairTripTime=true (the old default). Now that fair trip works
            --standalone, only users who had actually opted into the compat
            --switch keep it enabled; everyone else starts off as before.
            if not cfg.FairTripMigrated then
                gtconfig.FairTripMigrated = true
                if not cfg.MinimapAPICompat then
                    gtconfig.FairTripTime = false
                end
            end
            mmp_ltpos = Vector(gtconfig.TopLeftX or 100, gtconfig.TopLeftY or 100)
            update_mmscale()
            update_analog_mappings()
        end
    end
    -- 客机不运行 MC_POST_GAME_STARTED，进入会话前先读取本机偏好。
    load_config()
    _gt:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, load_config)
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
--debug function for recursive print
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
local function observe_room_doors()
    route_graph = nil
    if not crd or not crd.Data then
        live_doors = {}
        return
    end
    local history = door_history[dimension] or {}
    door_history[dimension] = history
    live_doors = DoorGraph.observe(room, crd, grid_room, history)
end

local function route_rooms()
    if not route_graph then
        route_graph = DoorGraph.build(grid_room, crsid, live_doors, door_history[dimension] or {})
    end
    return route_graph
end

local function has_lost_curse()
    return level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0
end

local function blocked_by_lost_curse()
    return gtconfig.FollowCurseOfLost and has_lost_curse()
end

local function can_leave_room()
    if blocked_by_lost_curse() then return false end
    if not grid_room[crsid] or not crd.Clear then return false end
    local kind = crd.Data.Type
    return (kind ~= RoomType.ROOM_MINIBOSS and kind ~= RoomType.ROOM_CHALLENGE) or _gt:check_room_open()
end

local function target_is_allowed(target)
    if target.ListIndex == crd.ListIndex then return false end
    local cleared = target.VisitedCount > 0 and target.Clear
    if not gtconfig.AllowNeighborRoom then return cleared end
    if (target.DisplayFlags & 1) == 0 then return false end
    if cleared then return true end

    local kind = target.Data.Type
    if kind == RoomType.ROOM_DEFAULT or kind == RoomType.ROOM_BOSS
        or kind == RoomType.ROOM_MINIBOSS or kind == RoomType.ROOM_SACRIFICE then
        return true
    end
    local free_rooms = (stage == 1 and level:GetStageType() < StageType.STAGETYPE_REPENTANCE)
        or room:IsMirrorWorld()
    return free_rooms and (kind == RoomType.ROOM_SHOP
        or (kind == RoomType.ROOM_TREASURE and not Game():IsGreedMode()))
end

local function find_travel_route(gid, traveller)
    local target = grid_room[gid]
    if not target or not traveller or not target_is_allowed(target) then return nil end

    local rooms = route_rooms()
    local to = target.SafeGridIndex
    local traveller_state = {
        flying = traveller:IsFlying(),
        protected = traveller:HasTrinket(151) or traveller:HasCollectible(276) or traveller:HasCollectible(663),
    }
    local route = RoutePlanner.find(rooms, crsid, to, traveller_state, gtconfig.AllowNeighborRoom)
    if route then return route end
    if gtconfig.FairTripPath or gtconfig.FairTripTime then return nil end

    if gtconfig.AllowNeighborRoom then
        local has_visible_neighbor = false
        for neighbor in pairs(rooms[to].doors) do
            if rooms[neighbor].visible and rooms[neighbor].pass_through then
                has_visible_neighbor = true
                break
            end
        end
        if not has_visible_neighbor then return nil end
    end
    -- With both path settings off, use the endpoint damage rules for free trips.
    return {damage = RoutePlanner.door_damage(rooms[crsid], rooms[to], false, traveller_state), distance = 0}
end

function _gt:check_teleble(gid)
    if debug and grid_room[gid] then return true end
    if not can_leave_room() then return false end
    return gid == false or find_travel_route(gid, player) ~= nil
end

function _gt:tele_failed()
  sfx:Play(187, 0.5, 0, false, 1)
end
--
local function plan_travel(gid, traveller)
    if not debug and not can_leave_room() then return nil end
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity.Type == 867 then return nil end
    end
    if crd.Data.Name == "Mom" or crd.Data.Name == "Ultra Greed" then return nil end

    local target = grid_room[gid]
    if not target then return nil end
    if target.Data.Type == RoomType.ROOM_CHALLENGE and not target.ChallengeDone then
        local hearts = traveller:GetHearts() + traveller:GetSoulHearts()
        if stage % 2 == 0 and stage ~= 10 then
            if hearts > 2 then return nil end
        elseif hearts < traveller:GetMaxHearts() then
            return nil
        end
    end

    local route = debug and {damage = 0, distance = 0} or find_travel_route(gid, traveller)
    if not route then return nil end
    local add_time = 0
    if gtconfig.FairTripTime and route.distance > 0 then
        if traveller.MoveSpeed <= 0 then return nil end
        add_time = math.floor(60.0 * route.distance / traveller.MoveSpeed + 0.5)
    end
    return {target = gid, damage = route.damage, add_time = add_time}
end

local function transitioning()
    return RoomTransition and RoomTransition.GetTransitionMode and RoomTransition.GetTransitionMode() ~= 0
end

local function restore_maze()
    if tele_maze then
        Game():GetLevel():AddCurse(LevelCurse.CURSE_OF_MAZE, false)
        tele_maze = false
    end
end

local function can_player_travel(traveller)
    if not traveller then return false end
    return not (traveller.IsCoopGhost and traveller:IsCoopGhost())
end

local function clear_shoot_block(participant)
    local block = shoot_blocks[participant]
    if not block then return end
    shoot_blocks[participant] = nil
    for _, pointer in pairs(block.bodies) do
        local entity = pointer.Ref
        if entity then entity:ToPlayer():SetCanShoot(true) end
    end
end

local function clear_shoot_blocks()
    for participant in pairs(shoot_blocks) do
        clear_shoot_block(participant)
    end
    shoot_intent_blocked = false
    shoot_renew_at, shoot_retry_at = 0, 0
end

local function block_shooting(block, body)
    if not body or not body:CanShoot() then return end
    local id = GetPtrHash(body)
    block.bodies[id] = block.bodies[id] or EntityPtr(body)
    body:SetCanShoot(false)
end

local function set_overlay_shoot_block(traveller, blocked)
    if CS.IsClient() or not traveller or type(blocked) ~= "boolean" then return false end
    local participant = CS.GetParticipant(traveller)
    if participant == nil then return false end
    if not blocked then
        clear_shoot_block(participant)
        return true
    end
    if not host_initialized or not can_player_travel(traveller) or traveller:IsDead() then
        clear_shoot_block(participant)
        return false
    end

    local id = GetPtrHash(traveller)
    local block = shoot_blocks[participant]
    if not block or block.player_id ~= id then
        clear_shoot_block(participant)
        block = {player_id = id, bodies = {}}
        shoot_blocks[participant] = block
    end
    block.expires_at = Isaac.GetTime() + shoot_block_timeout
    block_shooting(block, traveller)
    block_shooting(block, traveller:GetOtherTwin())
    return true
end

local function refresh_shoot_blocks()
    local now = Isaac.GetTime()
    for participant, block in pairs(shoot_blocks) do
        local traveller = CS.GetPlayerByParticipant(participant)
        if now >= block.expires_at or not can_player_travel(traveller) or traveller:IsDead()
            or GetPtrHash(traveller) ~= block.player_id then
            clear_shoot_block(participant)
        else
            block_shooting(block, traveller)
            block_shooting(block, traveller:GetOtherTwin())
        end
    end
end

local function send_overlay_shoot_block(blocked)
    if not blocked and not shoot_intent_blocked then return end
    local now = Isaac.GetTime()
    if blocked and shoot_intent_blocked and now < shoot_renew_at then return end
    if now < shoot_retry_at then return end

    -- Renew while held so a lost release or a disconnected guest cannot leave shooting disabled.
    if CS.SendIntent(_gt, "overlay_shoot_block", blocked) then
        shoot_intent_blocked = blocked
        shoot_renew_at = now + shoot_renew_interval
        shoot_retry_at = 0
    else
        shoot_retry_at = now + shoot_renew_interval
    end
end

local function execute_travel(traveller, args)
    local game = Game()
    if CS.IsClient() or not host_initialized or not can_player_travel(traveller) or type(args) ~= "table"
        or travel_applying or tele_maze or travel_cooldown > 0 or game:IsPaused() or transitioning() then
        return false
    end

    level = game:GetLevel()
    room = game:GetRoom()
    crd = level:GetCurrentRoomDesc()
    if not crd or not crd.Data then return false end
    crsid = crd.SafeGridIndex
    dimension, stage = get_dimension(level, room), level:GetStage()
    if args.source ~= crsid or args.dimension ~= dimension then return false end

    local gid = args.target
    if args.previous then
        if not gtconfig.LastRoomShortcut then return false end
        local previous = level:GetLastRoomDesc()
        if not previous or not previous.Data
            or (previous.GetDimension and previous:GetDimension() ~= dimension) then return false end
        gid = previous.SafeGridIndex
    end
    if math.type(gid) ~= "integer" or gid < 0 or gid >= 169 then return false end

    _gt:get_grid_room()
    local plan = plan_travel(gid, traveller)
    if not plan then return false end

    local immediate = gtconfig.FastTransition or debug
    travel_cooldown = immediate and 1 or (gtconfig.TeleportAnimation and 23 or 5)
    travel_applying = true
    local ok, travelled = pcall(function()
        if plan.damage > 0 then
            traveller:TakeDamage(plan.damage, DamageFlag.DAMAGE_CURSED_DOOR | DamageFlag.DAMAGE_NO_PENALTIES,
                EntityRef(traveller), 0)
            if not can_player_travel(traveller) then return false end
        end
        level.EnterDoor, level.LeaveDoor = -1, -1
        if level:GetCurses() & LevelCurse.CURSE_OF_MAZE ~= 0 then
            level:RemoveCurses(LevelCurse.CURSE_OF_MAZE)
            tele_maze = true
        end
        if plan.add_time > 0 then game.TimeCounter = game.TimeCounter + plan.add_time end
        if immediate then
            game:ChangeRoom(plan.target, -1)
            game:GetRoom():PlayMusic()
        else
            local animation = gtconfig.TeleportAnimation and 3 or 1
            game:StartRoomTransition(plan.target, Direction.NO_DIRECTION, animation, traveller, -1)
        end
        return true
    end)
    travel_applying = false
    if immediate or not ok or not travelled then restore_maze() end
    if not ok then error(travelled) end
    return travelled
end

-- 客机用本机角色和地图提供预览，Host 最终裁决传送。
local function can_select(gid)
    if gid ~= false and not can_player_travel(player) then return false end
    if not CS.IsClient() then return _gt:check_teleble(gid) end
    if blocked_by_lost_curse() then return false end
    if gid == false then return crd.Data ~= nil end
    local target = grid_room[gid]
    return target and target.DisplayFlags > 0 and target.SafeGridIndex ~= crsid
end

function _gt:teleport_to_grid_index(gid, previous)
    if pending_travel then return end
    if not can_player_travel(CS.GetLocalPlayer()) then
        self:tele_failed()
        return false
    end
    pending_travel = CS.SendIntent(self, "travel", {
        target = gid,
        previous = previous == true,
        source = crsid,
        dimension = dimension,
    })
    if not pending_travel then
        self:tele_failed()
        return false
    end
    return true
end
--
--hit-test against MinimapAPI's own rendered rooms: each room carries its
--on-screen anchor (RenderOffset) with position, display mode, small/large
--pitch and the mirror-world flip all baked in, so we invert that instead of
--guessing the vanilla map geometry (which MinimapAPI replaces entirely)
function _gt:get_pos_grid_index_minimapapi(pos)
    local sx = MinimapAPI.GlobalScaleX or 1
    if sx ~= 1 and sx ~= -1 then
      return -99 --mid mirror-flip animation, geometry unreliable for a few frames
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
          --the sprite flips around its anm2 pivot, so the baked-in anim-pivot
          --compensation flips too (measured: half a cell, toward the left)
          ox = ox + pivot.X * 2
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
--
--screen anchors of the vanilla top-right corner map, shared by the click hit
--test and its inverse (cell_to_screen) so the calibrated constants live once;
--mirrorsum is the mirror flip as an involution: flipped_x = mirrorsum - x
local function vanilla_map_anchors()
    local rtr = _gt:get_corner_room(2)
    local ltx = scpos.X - (rtr.X + 1) * 17 - 4 - hudoffset * 2.4 --withrighttopmap; -4 includes the calibrated vanilla-map +1px main-world correction
    local lty = - (rtr.Y) * 15 + 5 + hudoffset * 1.3 --whthrighttopmap
    local mirrorsum = nil
    --repentance stage 2c:mirror--
    if room:IsMirrorWorld() then
      local ltr = _gt:get_corner_room(3)
      local rtx = scpos.X - (ltr.X + 1) * 17 - 5 - hudoffset * 2.4 --withleftbottommap; -5 includes the calibrated vanilla-map +2px mirror-world correction
      -- print(rtr.X, ltr.X) -- 3 -> 9; 4 -> 9; 5 -> 9; 6 -> 7; 7 -> 5
      --the tail constant is the mirror flip's phase, slider-calibrated on each
      --game version (Rep+ re-anchored the corner map 2 cells from old Repentance)
      mirrorsum = ltx + rtx + (9 - math.max(0, rtr.X - ltr.X - 5) * 2)*17 - (REPENTANCE_PLUS and 34 or 0)
    end
    return ltx, lty, mirrorsum
end
--
function _gt:get_pos_grid_index(pos)
    if not gtconfig.FollowCurseOfLost and has_lost_curse() then
      return -99
    end
    --user self-calibration (MCM): shift the perceived click so the selection
    --moves the same screen direction in both worlds; fresh Vector, the
    --caller's mouse position must stay untouched
    local mir = room:IsMirrorWorld()
    local calibx = mir and (gtconfig.CalibMirrorX or 0) or (gtconfig.CalibMainX or 0)
    local caliby = mir and (gtconfig.CalibMirrorY or 0) or (gtconfig.CalibMainY or 0)
    pos = Vector(pos.X + calibx, pos.Y + caliby)
    if MinimapAPI then
      return _gt:get_pos_grid_index_minimapapi(pos)
    end
    -----RTmap-----
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
--
--inverse of get_pos_grid_index: the screen-pixel CENTER of a 13x13 grid cell
--on the game's own map (MinimapAPI's if present, else the vanilla corner map),
--plus the map's cell scale relative to the aux-map cell; nil when the map
--geometry is unavailable (e.g. mid mirror-flip animation)
function _gt:cell_to_screen(mgid)
    local col = mgid % 13
    local row = (mgid - col) / 13
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
      --the reference room's RenderOffset + grid index give the affine map from
      --grid cells to screen; prefer the room the cursor sits on (exact even if
      --rooms are displayed at custom positions), then a 1x1 room (unambiguous
      --anchor) as the fallback for empty cells
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
      local x0 = ox + (col - gcol) * pw * sx
      local y0 = oy + (row - grow) * ph
      return Vector(x0 + pw * sx / 2, y0 + ph / 2), (large and 2 or 1)
    end
    local ltx, lty, mirrorsum = vanilla_map_anchors()
    local mir = room:IsMirrorWorld()
    local calibx = mir and (gtconfig.CalibMirrorX or 0) or (gtconfig.CalibMainX or 0)
    local caliby = mir and (gtconfig.CalibMirrorY or 0) or (gtconfig.CalibMainY or 0)
    local px = ltx + col * 17 + 8.5
    if mirrorsum then
      px = mirrorsum - px
    end
    return Vector(px - calibx, lty + row * 15 + 7.5 - caliby), 2
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
local function read_grid_rooms()
    -- GetRoomByIdx 返回实际占用的格位，多格房间和 GridIndex 异常的房间也可正确命中。
    local cells = {}
    for gid = 0, 168 do
        local desc = level:GetRoomByIdx(gid, -1)
        if desc and desc.Data then
            cells[gid] = desc
        end
    end
    return cells
end

function _gt:get_grid_room()
    grid_room = read_grid_rooms()
    observe_room_doors()
    grid_room_mark = {}
    if not gtconfig.DangerCautionCompat or not DangerCaution then return end
    for gid, desc in pairs(grid_room) do
        if gid == desc.SafeGridIndex then
            local danger = DangerCaution:roomDangerFlags(desc)
            if danger ~= 0 then
                grid_room_mark[gid] = DangerCaution:dangerFlagToColor(danger)
            end
        end
    end
end
--
local function special_stage(current_level)
    if current_level:IsAscent() then return 0 end
    local current_stage = current_level:GetStage()
    local alternate = current_level:GetStageType() >= StageType.STAGETYPE_REPENTANCE
    local labyrinth = current_level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH ~= 0
    if current_stage == 2 or (current_stage == 1 and labyrinth and alternate) then return 1 end
    if current_stage == 4 or (current_stage == 3 and labyrinth and alternate) then return 2 end
    if current_stage == 6 or (current_stage == 5 and labyrinth and not alternate) then return 3 end
    return 0
end

local function get_special_icon(data, effect)
    if effect == 0 or not data or data.Type ~= 1 then return nil end
    local fallback
    local spawns = data.Spawns
    if not spawns then return nil end
    for i = 0, spawns.Size - 1 do
        local entry = spawns:Get(i):PickEntry(0)
        if effect == 1 then
            if entry.Type == 970 and entry.Variant == 2 then return 5 end
            if entry.Type == 33 and entry.Variant == 4 then return 6 end
        elseif effect == 2 then
            if entry.Type == 965 and entry.Variant == 10 then return 8 end
            if entry.Type == 4500 and entry.Variant == 3 then fallback = 9 end
        elseif entry.Type == 1008 then
            return 7
        end
    end
    return fallback
end

local function special_icon_key(room_dimension, grid_index)
    return room_dimension * 169 + grid_index
end

-- 每层只下发有特殊图标的房间。键包含维度，镜像层和主世界可复用同一格位。
local function collect_special_icons()
    local current_level = Game():GetLevel()
    local effect = special_stage(current_level)
    local icons = {}
    if effect == 0 then return icons end
    local rooms = current_level:GetRooms()
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc and desc.SafeGridIndex >= 0 and desc.SafeGridIndex < 169 then
            local icon = get_special_icon(desc.Data, effect)
            if icon then
                local room_dimension = desc.GetDimension and desc:GetDimension() or dimension
                icons[special_icon_key(room_dimension, desc.SafeGridIndex)] = icon
            end
        end
    end
    return icons
end

-- 客机没有进房和用道具回调。每个已安装的 World 帧读一次格位，只在地图变化时重排。
local function refresh_client_map(game)
    level, room = game:GetLevel(), game:GetRoom()
    crd = level:GetCurrentRoomDesc()
    if not crd or not crd.Data then return false end
    local current_dimension = get_dimension(level, room)
    local changed_room = dimension ~= current_dimension or crsid ~= crd.SafeGridIndex
    crsid = crd.SafeGridIndex
    dimension, stage = current_dimension, level:GetStage()
    if changed_room then
        mmp_ctrl = false
        mmp_1step_tp = false
        mouse_magnet = false
    end
    local frame = game:GetFrameCount()
    if frame == client_map_frame and not changed_room then return true end

    local cells = read_grid_rooms()
    local parts = {}
    for gid = 0, 168 do
        local desc = cells[gid]
        if desc then
            parts[#parts + 1] = gid
            parts[#parts + 1] = desc.SafeGridIndex
            parts[#parts + 1] = desc.Data.Type
            parts[#parts + 1] = desc.Data.Shape
            parts[#parts + 1] = desc.DisplayFlags
        end
    end
    local signature = table.concat(parts, ",")
    if changed_room or signature ~= client_map_signature then prep_alarm = true end
    grid_room, client_map_frame, client_map_signature = cells, frame, signature
    return true
end

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
    if gtconfig.GameMapCursor then --the game's own map is the widget: no window chrome
      return
    end
    if not ((gtconfig.KeyboardMapEnable and can_select(false)) or debug) then
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
--GameMapCursor mode: the aux window stays hidden, the keyboard cursor is
--drawn on the game's own map instead; selection & teleport logic untouched
function _gt:draw_gamemap_cursor()
    if not mmp_ctrl then
      return
    end
    local mgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
    if mgid < 0 then
      return
    end
    local center, scale = _gt:cell_to_screen(mgid)
    if not center then
      return
    end
    if can_select(mgid) then
      cursor.Color = Color(1, 1, 1, 1, 0, 0, 0)
    else
      cursor.Color = Color(1, 0.3, 0.3, 1, 0, 0, 0) --not teleportable: red, like the aux map's red rooms
    end
    --the aux map draws the cursor sprite 2,1.5px past the cell center; keep
    --the same relation so the glyph sits identically within the bigger cells
    cursor.Scale = Vector(scale, scale)
    cursor:Render(center + Vector(2, 1.5) * scale, Vector(0, 0), Vector(0, 0))
    cursor.Scale = Vector(1, 1)
    cursor.Color = Color(1, 1, 1, 1, 0, 0, 0)
end
--
function _gt:draw_minimap()
    if gtconfig.GameMapCursor then
      _gt:draw_gamemap_cursor()
      return
    end
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
    local client = CS.IsClient()
    local effect = not client and gtconfig.ShowSpecialIcons and special_stage(level)
    for i = 1, #draw_room_id do
      local rd = grid_room[draw_room_id[i]]
      if (rd.Flags & red_room_flag) == 0 then
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
            elseif player and player:HasTrinket(146) then
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
          local iid
          if client then
            iid = client_special_icons[special_icon_key(dimension, rd.SafeGridIndex)]
          else
            iid = get_special_icon(rd.Data, effect)
          end
          if iid then
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
           if can_select(checkid) then
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
local function local_action(query, action)
    -- 客机 Lua 从本机设备读取动作，键鼠走 0，手柄保留任意本机设备查询。
    return (input_controller == -1 and query(action, 0)) or query(action, input_controller)
end

function _gt:mmp_ctrl_move()
  local dif = {mmp_ctrl_pos.Y - mmp_ltpos.Y + 2 * mmsc, mmp_ctrl_pos.X - mmp_ltpos.X + 2 * mmsc, mmp_rbpos.X - mmp_ctrl_pos.X + 14 * mmsc, mmp_rbpos.Y - mmp_ctrl_pos.Y + 13 * mmsc}
    if room:IsMirrorWorld() then dif[2], dif[3] = dif[3], dif[2] end --X movement is mirrored, so left/right bound guards swap too
    for i = 1,4 do
      if gtconfig.QuicklyOneRoomMove then
        if local_action(Input.IsActionTriggered, movkey[i]) and dif[i] > 0 then
          -- local s = room:GetRoomShape()
          mmp_ctrl_pos = mmp_ctrl_pos + _gt:mirror_mmp_dir(dir[i] * Vector(8, 7) * mmsc)
          local nmgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
          if can_select(nmgid) and not pending_travel then
            mmp_1step_tp = true
            mmp_1step_mgid = nmgid
          end
        end
      end
      if gtconfig.FasterCursorMove then
        if local_action(Input.IsActionTriggered, key[i]) and dif[i] > 0 then
          mmp_ctrl_pos = mmp_ctrl_pos + _gt:mirror_mmp_dir(dir[i]) * Vector(8, 7) * mmsc
        end
      else
        if local_action(Input.IsActionPressed, key[i]) and dif[i] > 0 then
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
--
function _gt:tab_action()
    if not CS.IsClient() and gtconfig.FastRestartEnable
        and (Input.IsButtonTriggered(Keyboard.KEY_R, input_controller)
            or (gtconfig.ControllerAlternateR and Input.IsButtonTriggered(gtconfig.ControllerAlternateR, input_controller))) then
      print('GoodTrip [Fixed] !!!FAST RESTARTING!!!')
      Isaac.ExecuteCommand("restart")
      return
    end
    if not CS.IsClient() and gtconfig.QuicklyOneRoomMove and crd.Clear and player.ControlsCooldown < 2 then
      player.ControlsCooldown = player.ControlsCooldown + 1
    end
    --
    if (gtconfig.KeyboardMapEnable and can_select(false)) or debug then
      local movement_pressed = false
      for i = 1, 4 do
        if local_action(Input.IsActionPressed, movkey[i]) then
          movement_pressed = true
          break
        end
      end
      if not movement_pressed or gtconfig.QuicklyOneRoomMove then
        local arrowdown = local_action(Input.IsActionPressed, key[1])
            or local_action(Input.IsActionPressed, key[2])
            or local_action(Input.IsActionPressed, key[3])
            or local_action(Input.IsActionPressed, key[4])
        --with the cursor on the game's own map there is no widget for the mouse
        --to hover, so the keyboard always owns the cursor
        local in_ui = not gtconfig.GameMapCursor
            and _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-8, -18) * mmsc,mmp_rbpos + Vector(20, 20) * mmsc) --ui zone
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

--nil bindings follow the vanilla map key; once a custom binding is set it
--REPLACES the map key (that's the point for e.g. dodging EID's TAB overlay)
local function overlay_input(button, action)
    if gtconfig.OverlayKey or gtconfig.OverlayKeyController then
        return (gtconfig.OverlayKey ~= nil and button(gtconfig.OverlayKey, 0))
            or (gtconfig.OverlayKeyController ~= nil and button(gtconfig.OverlayKeyController, input_controller))
    end
    -- 联机层原生小地图有自己的地图键路由，Lua 也直接读取客机的默认 TAB。
    return (CS.IsClient() and button(Keyboard.KEY_TAB, 0)) or local_action(action, ButtonAction.ACTION_MAP)
end

function _gt:is_overlay_triggerd()
    return overlay_input(Input.IsButtonTriggered, Input.IsActionTriggered)
end

function _gt:is_overlay_pressed()
    return overlay_input(Input.IsButtonPressed, Input.IsActionPressed)
end

function _gt:mouse_action()
    if _gt:IsMouseBtnTriggered(0) then
      local mgid = _gt:get_pos_grid_index(mpos)
      ---
      if can_select(mgid) then
        _gt:teleport_to_grid_index(mgid)
      elseif gtconfig.KeyboardMapEnable and not gtconfig.GameMapCursor then --aux-widget zones (window click / pin / zoom / drag): only when the widget is visible
        mgid = _gt:get_pos_grid_index_mmp(_gt:mirror_mmp_pos(mpos))
        --
        if can_select(mgid) then
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
    if not host_initialized then return end
    mmp_ctrl = false
    _gt:get_grid_room()
    _gt:prep()
    CS.MarkDirty(self, "special_icons")
end

function _gt:check_and_tele_room(gid)
    if can_select(gid) then
        _gt:teleport_to_grid_index(gid)
        mmp_ctrl = false
    elseif not grid_room[gid] or grid_room[gid].SafeGridIndex ~= crsid then
        _gt:tele_failed()
    end
end

function _gt:step()
    local game = Game()
    local client = CS.IsClient()
    if client then
        if not refresh_client_map(game) then
            send_overlay_shoot_block(false)
            return
        end
    elseif not host_initialized and game:GetNumPlayers() > 0 then
        _gt:new_level()
    end
    player = CS.GetLocalPlayer()
    if not crd or not crd.Data or (not client and not player) then
        send_overlay_shoot_block(false)
        return
    end
    local lost = blocked_by_lost_curse()
    if (client and lost) or (not client and (game:IsPaused() or transitioning())) then
        send_overlay_shoot_block(false)
        mmp_ctrl, mmp_1step_tp, mouse_magnet = false, false, false
        return
    end

    -- 客机用本机各输入设备，角色的 ControllerIndex 不代表客机的物理设备。
    input_controller = client and -1 or player.ControllerIndex
    local center = Isaac.WorldToRenderPosition(Vector(320, 280))
    scpos = center + center
    hudoffset = Options.HUDOffset * 10
    mpos = Isaac.WorldToScreen(Input.GetMousePosition(true))
    mouse_moved = (mpos - last_mpos):LengthSquared() > 4
    last_mpos = mpos

    if _gt:is_overlay_triggerd() then
        if not client then _gt:get_grid_room() end
        prep_alarm = true
    end
    if prep_alarm then
        _gt:prep()
        prep_alarm = false
    end

    local overlay_pressed = _gt:is_overlay_pressed()
    send_overlay_shoot_block(overlay_pressed and gtconfig.NoShootWhenClick and not lost
        and can_player_travel(player) or false)
    if overlay_pressed then
        if gtconfig.LastRoomShortcut and (Input.IsButtonTriggered(Keyboard.KEY_Z, 0)
            or (gtconfig.ControllerAlternateZ and Input.IsButtonTriggered(gtconfig.ControllerAlternateZ, input_controller))) then
            _gt:teleport_to_grid_index(nil, true)
        end

        if gtconfig.AllowBookmarking then
            local selected = mmp_ctrl and _gt:get_pos_grid_index_mmp(mmp_ctrl_pos) or crsid
            local target = grid_room[selected]
            for i = 1, 9 do
                if Input.IsButtonTriggered(Keyboard.KEY_0 + i, 0) then
                    local bookmark = bookmarks[i]
                    if bookmark then
                        if bookmark.dimension == dimension then
                            _gt:check_and_tele_room(bookmark.grid)
                        else
                            _gt:tele_failed()
                        end
                    elseif target and target.DisplayFlags > 0 then
                        bookmarks[i] = {grid = selected, dimension = dimension}
                        if not client then player:AnimateHappy() end
                    end
                end
            end
            if Input.IsButtonTriggered(Keyboard.KEY_0, 0) then
                bookmarks = {}
                if not client then player:AnimateSad() end
            end
        end

        if mmp_1step_tp then
            mmp_1step_tp = false
            if mmp_ctrl and can_select(false) then
                local gid = mmp_1step_mgid
                mmp_ctrl = false
                if not can_select(gid) or not _gt:teleport_to_grid_index(gid) then
                    mmp_1step_mgid = -1
                end
            end
            _gt:draw_minimap_ui()
        else
            _gt:tab_action()
        end
    elseif gtconfig.KeyboardMapEnable or debug then
        if mmp_pin == 1 and not gtconfig.GameMapCursor and can_select(false) then
            local over_map = _gt:check_pos_en_box(mpos, mmp_ltpos + Vector(-8, -18) * mmsc,
                mmp_rbpos + Vector(20, 20) * mmsc)
            if over_map then
                if _gt:IsMouseBtnTriggered(0) then
                    if _gt:check_pos_en_box(mpos, mmp_ltpos + Vector(-3, -13) * mmsc, mmp_ltpos + Vector(5, -4) * mmsc) then
                        mmp_pin = 0
                    elseif _gt:check_pos_en_box(mpos, mmp_ltpos + Vector(8, -13) * mmsc, mmp_ltpos + Vector(19, -3) * mmsc) then
                        cycle_mmscale()
                    else
                        local gid = _gt:get_pos_grid_index_mmp(_gt:mirror_mmp_pos(mpos))
                        if can_select(gid) then _gt:teleport_to_grid_index(gid) end
                    end
                end
                _gt:draw_minimap_ui()
            else
                ui_timer = 0
            end
            _gt:draw_minimap()
        else
            ui_timer = 0
        end
        if mmp_ctrl then
            mmp_ctrl = false
            local gid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
            if can_select(gid) then _gt:teleport_to_grid_index(gid) end
        end
    end

    if prep_alarm then
        _gt:prep()
        prep_alarm = false
    end
end

function _gt:step2()
    if not host_initialized then return end
    refresh_shoot_blocks()
    if travel_cooldown > 0 then travel_cooldown = travel_cooldown - 1 end
    if tele_maze and not travel_applying and travel_cooldown == 0 and not transitioning() then
        restore_maze()
    end
    local count = level:GetRooms().Size
    if count ~= host_room_count then
        host_room_count = count
        _gt:get_grid_room()
        prep_alarm = true
        CS.MarkDirty(self, "special_icons")
    else
        observe_room_doors()
    end
end

function _gt:new_room()
    level, room = Game():GetLevel(), Game():GetRoom()
    crd = level:GetCurrentRoomDesc()
    if not crd or not crd.Data then return end
    crsid = crd.SafeGridIndex
    dimension, stage = get_dimension(level, room), level:GetStage()
    host_room_count = level:GetRooms().Size
    _gt:get_grid_room()
    mmp_ctrl, mmp_1step_tp, mouse_magnet = false, false, false
    prep_alarm = true
    if not travel_applying then restore_maze() end
    CS.MarkDirty(self, "special_icons")
end

function _gt:new_level()
    clear_shoot_blocks()
    bookmarks = {}
    door_history, live_doors, route_graph = {}, {}, nil
    pending_travel = nil
    mmp_1step_mgid = -1
    crd = nil
    _gt:new_room()
    host_initialized = crd ~= nil and crd.Data ~= nil
end

function _gt:get_config()
    return gtconfig
end
--
--

CS.State(_gt, "special_icons", {
    type = {map = {key = "int", of = "int", max = 507}},
    rate = "mark",
    get = collect_special_icons,
    set = function(icons) client_special_icons = icons or {} end,
    reset = function() client_special_icons = {} end,
})

CS.Intent(_gt, "travel", {
    args = {struct = {target = "int", previous = "bool", source = "int", dimension = "int"}},
    handler = execute_travel,
})

CS.Intent(_gt, "overlay_shoot_block", {
    args = "bool",
    handler = set_overlay_shoot_block,
})

CS.AddCallback(_gt, CS.CLIENT_INTENT_RESULT, function(name, sequence, ok)
    if name ~= "travel" or sequence ~= pending_travel then return end
    pending_travel = nil
    if not ok then
        mmp_1step_mgid = -1
        _gt:tele_failed()
    end
end)

local function reset_client_map()
    send_overlay_shoot_block(false)
    shoot_intent_blocked = false
    shoot_renew_at, shoot_retry_at = 0, 0
    client_map_frame, client_map_signature = nil, nil
    grid_room, grid_room_mark, bookmarks = {}, {}, {}
    draw_room_id, draw_room_pos, draw_room_shape = {}, {}, {}
    pending_travel, crd, player = nil, nil, nil
    mmp_ctrl, mmp_1step_tp, mouse_magnet = false, false, false
    mmp_1step_mgid = -1
    mouse_pressed = {false, false, false, false, false}
    prep_alarm = true
end

CS.AddCallback(_gt, CS.CLIENT_SCENE_STARTED, reset_client_map)
CS.AddCallback(_gt, CS.CLIENT_SCENE_ENDED, reset_client_map)

_gt:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function()
    travel_cooldown = 0
    _gt:new_level()
end)
_gt:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
    clear_shoot_blocks()
    restore_maze()
    host_initialized = false
    pending_travel = nil
end)
if ModCallbacks.MC_PRE_MOD_UNLOAD then
    _gt:AddCallback(ModCallbacks.MC_PRE_MOD_UNLOAD, function(owner, unloaded)
        if owner == unloaded then clear_shoot_blocks() end
    end)
end
_gt:AddCallback(ModCallbacks.MC_USE_ITEM, _gt.itemused)
_gt:AddCallback(ModCallbacks.MC_USE_CARD, _gt.itemused)
_gt:AddCallback(ModCallbacks.MC_USE_PILL, _gt.itemused)
_gt:AddCallback(ModCallbacks.MC_POST_RENDER, _gt.step)
_gt:AddCallback(ModCallbacks.MC_POST_UPDATE, _gt.step2)
_gt:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, _gt.new_room)
_gt:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, _gt.new_level)
