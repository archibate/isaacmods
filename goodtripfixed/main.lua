local hasoldgoodtrip = (gt and not gt.isgtfixed)
local _gt = RegisterMod("GoodTrip [Fixed]", 1)
gt = _gt
_gt.isgtfixed = true
--these are conditions, not events: they stay on screen until the player fixes
--them. the old code faded out after five seconds counted from load, and since
--render callbacks run on the menus too, those seconds were spent at the title
--screen and nobody ever saw the text.
--the old GoodTrip claims the same `gt` global and either mod can load first, so
--one check cannot cover it: `hasoldgoodtrip` catches it loading before us, and
--the global no longer pointing at us catches it loading after and taking it back
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
    if not warned then --once into the console and the log, however long they play
        warned = true
        for _, warnmsg in ipairs(warnings) do
            print(warnmsg)
        end
    end
    if not warn_in_run then --a menu is no place to tell someone anything
        return
    end
    for i, warnmsg in ipairs(warnings) do
        Isaac.RenderScaledText(warnmsg, 40, 50 + (i - 1) * 12, 0.5, 0.5, 1, 1, 0, 1)
    end
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
local room_neighbours = {} --used instead of minimapi's GetAdjacentRooms() method
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
local fast_move_cd = {0, 0, 0, 0} --FasterCursorMove: per-direction hold-to-repeat cooldown
local FAST_MOVE_REPEAT_FRAMES = 6 --frames between room-jumps while a key stays held
local last_mpos = Vector(0, 0)
local mouse_moved = false --physical mouse motion this frame (tracked every frame in step)
local kb_active = false --keyboard is the active map-cursor device, for this opening of the map
local mouse_in_ui = false
local mmp_1step_tp = false
local mmp_1step_mgid = -1
--
local tele_maze = false
local tele_door_slot = -1 --the door a trip means to arrive by
--the real door graph, learned one room at a time. Grid adjacency alone cannot
--tell a doorway from a secret room's unbombed wall, so a trip that crosses one
--hands out a bomb nobody spent. Kept per dimension: the mirror world reuses the
--same grid numbers for different rooms, and both halves of a Downpour floor are
--one level, so a single table would answer for the wrong side of the mirror.
local door_link = {}  --door_link[dim][a][b]: a passage, seen from either end
local door_swept = {} --door_swept[dim][a]: a's own walls were read, so silence
                      --about b is evidence and not merely ignorance
local secret_pre_room_id = {}
--curse rooms whose doors have been laid eyes on, and whether they had their
--spikes. A door has two of itself, one in each room it joins, and Flat File takes
--the spikes off whichever side it was standing beside, so the way in and the way
--out are remembered apart. Both are needed: a trip out of a secret room hops
--through the curse room that guards it and leaves by its inner door, and is
--decided from inside the secret room, where that door cannot be read
local curse_bare_outside, curse_bare_inside = {}, {}
local prep_alarm = false
local n_room_num = 0
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
    LandAtDoor = true,  --arrive at the door a walk would have come in by, carrying familiars along; off leaves everyone wherever the game drops them
    QuicklyOneRoomMove = false, --true = enable / false = disable. quickly move one entire room by TAB+ASWD
    AllowNeighborRoom = true,  --true = enable / false = disable. allow move to uncleaned neighbor room
    AllowAnyRoom = false,  --trip to any room the map knows, walked to or not; off by default, since it hands out every room on the floor
    AllowBookmarking = true,  --true = enable / false = disable. allow tag bookmarks for rooms using TAB+0~9
    LastRoomShortcut = true,  --true = enable / false = disable. allow TAB+Z to go back to last visited room
    FastTransition = false,  --change room even faster without animation
    NoShootWhenClick = true,  --disable mouse click shooting when holding Tab
    -- AllowRightClick = false,  --mouse right click on bigmap to teleport
    FasterCursorMove = false,  --move cursor faster in keyboard minimap by press arrow keys once instead of having to hold them
    CursorOnGameMap = false,  --draw the cursor on the game's own corner map instead of the draggable window; needs REPENTOGON, see _gt:gon_map_cursor
    DimMapInCombat = true,  --while the room is uncleared and no trip is possible, draw the window faint and inert instead of hiding it
    DimMapAlpha = 35,  --how faint that is, in percent; floored at 5 so a mistyped 0 cannot erase the window the way MinimapScale once did
    DangerCautionCompat = true,  --weather to work with my other mod 'Dangerous room! Caution' by indicate dangerous room by colors
    FairTripTime = false,  --weather to incur fair time according to distance; off by default so the apiless rework doesn't spring time penalties on existing players
    FairTripPath = true,  --true = enable / false = disable. only trip to rooms linked to the current one by cleared rooms
    ShowSpecialIcons = true,  --show icons on visited rooms that have mirror, white fireplace, minecart, mine button, or tinted skull
    -- ShowDoorsAllowed = false,  --show doors allowed for secret rooms
    -- DebugMod = false,  --testonly.
    ControllerAlternateZ = nil,  --replacement for Z in the TAB+Z last room shortcut
    ControllerAlternateR = nil,  --replacement for R in the TAB+R restart shortcut
    MinimapScale = 10,  --keyboard minimap size, 5 = 0.5x .. 10 = 1.0x .. 25 = 2.5x
    --for users with MCM that want their overlay key to always be the map key
    OverlayKey = nil,  --The key to open the overlay on keyboard
    OverlayKeyController = nil, --The button to open the overlay on controller
    SwapAnalogSticks = false, --Swap the left and right analog sticks
    IgnoreMovementKeys = false, --keep aiming while you walk, instead of pausing the cursor
    --self-service calibration for corner-map clicks, in pixels: if clicks land
    --one room LEFT of where you aim, increase; RIGHT of aim, decrease
    --(Y likewise: land ABOVE your aim, increase; BELOW, decrease)
    CalibMainX = 0,
    CalibMirrorX = 0,
    CalibMainY = 0,
    CalibMirrorY = 0,
}
----
--Everything named gon_ belongs to REPENTOGON and to nobody else. Each one asks
--for REPENTOGON itself rather than trusting whoever called it, so on a plain game
--every gon_ test is false and every gon_ action does nothing -- a setting switched
--on without REPENTOGON, from an old saved config or by hand, leaves the mod
--exactly as it was. Nothing outside these may touch a REPENTOGON-only call.

--
--the cursor on the game's own map only lands above it from a REPENTOGON render
--callback; without the script extender it draws behind the map and the window it
--replaces is hidden, which is how the mode broke players before
function _gt:gon_map_cursor()
    return REPENTOGON ~= nil and gtconfig.CursorOnGameMap
end
----
--gtconfig.lua is the config surface for players without Mod Config Menu: it is
--applied after the saved config, so a hand-edited setting wins on every launch,
--and the keys it names are left out of the save so nothing writes over them
local overrides = {}
local function apply_overrides()
    local ok, over = pcall(function()
        if package and package.loaded then package.loaded["gtconfig"] = nil end
        return require("gtconfig")
    end)
    overrides = {}
    if not ok or type(over) ~= "table" then
        return
    end
    for k, v in pairs(over) do
        overrides[k] = true
        gtconfig[k] = v
    end
end
apply_overrides()
----
--config persistence lives here, not in the MCM block below: dragging the map,
--clicking the zoom button and dropping the map in the trash all work without Mod
--Config Menu, so their results have to survive a relaunch for those players too
--(the trash is one-way without MCM -- the console line in the FAQ brings it back)
local cfgdata_written = nil
local cfgdata_loaded = false
local function save_config()
    --never write before the first read of the run: a `luamod` reload throws the
    --locals back to their defaults, and the exit save of the next restart would
    --otherwise bury the real config under them
    if not cfgdata_loaded then return end
    local json = require('json')
    gtconfig.TopLeftX = mmp_ltpos.X
    gtconfig.TopLeftY = mmp_ltpos.Y
    local payload = gtconfig
    if next(overrides) then --a pinned key belongs to gtconfig.lua, so never bank it
        payload = {}
        for k, v in pairs(gtconfig) do
            if not overrides[k] then
                payload[k] = v
            end
        end
    end
    local dat = json.encode(payload)
    if not cfgdata_written or dat ~= cfgdata_written then
        cfgdata_written = dat
        _gt:SaveData(dat)
    end
end
_gt.save_config = save_config --so the console can make a hand-edited config stick
----
local mmsc = 1.0 --keyboard minimap scale factor (gtconfig.MinimapScale / 10)
local function update_mmscale()
    --hand-edited in gtconfig.lua, so it can arrive as anything: a scale of 0
    --draws every sprite at no size at all, which looks exactly like the mod
    --being broken, with every setting still reading correct
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
    save_config()
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
local tele_cd = 0
local bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99} -- press TAB+1~9 to mark or switch to, TAB+0 to clear all marks
-------------------------------
---configs---
if ModConfigMenu then
    if ModConfigMenu.GetCategoryIDByName("GoodTrip [Fixed]") ~= nil then
        print('GoodTrip [Fixed] is reloading ModConfigMenu options')
        ModConfigMenu.RemoveCategory("GoodTrip [Fixed]")
    end
    --a page starts scrolling past ten settings, so every tab is kept well under
    --that, at the cost of paging the tab bar itself (it shows three at a time).
    --first column is the tab; tabs appear in the order they are first named here
    local options = {
        { "Map", "KeyboardMapEnable", "Classic GoodTrip minimap, teleport using TAB + arrow keys. Turn this back on if you dragged it into the trash by accident." },
        --a fourth field is a condition to offer the setting at all: this one
        --does nothing without REPENTOGON, so it is not shown there
        { "Map", "CursorOnGameMap", "Put the cursor on the game's own corner map and hide the mod's window (needs REPENTOGON)", REPENTOGON ~= nil },

        { "Fairness", "AllowNeighborRoom", "Allow moving into uncleaned neighbor room" },
        { "Fairness", "AllowAnyRoom", "Allow teleporting to any room on the map, with no path to it cleared first" },
        { "Fairness", "FairTripPath", "Only allow teleport to rooms reachable through cleared rooms" },
        { "Fairness", "FairTripTime", "Fairly increase game time according to player move speed and distance" },
        { "Fairness", "FollowCurseOfLost", "Disable GoodTrip on curse of lost" },
        { "Fairness", "LandAtDoor", "Arrive standing at the exact door a walk would have come in by" },

        { "Shortcuts", "LastRoomShortcut", "Allow teleport back to last room via TAB + Z" },
        { "Shortcuts", "FastRestartEnable", "Allow restarting the run quickly via TAB + R" },
        { "Shortcuts", "AllowBookmarking", "Allow adding bookmarks for rooms via TAB + 1~9" },


        { "Display", "ShowSpecialIcons", "Show an icon on rooms you have visited that have mirror, white fireplace, minecart, mine button, or tinted skull" },
        { "Display", "DangerCautionCompat", "weather to work with my other mod 'Dangerous room! Caution' (if detected) by indicate dangerous room by colors" },
        { "Display", "TeleportAnimation", "Play cool animation on teleport" },
        { "Display", "FastTransition", "Even faster transition without animation" },
        { "Display", "DimMapInCombat", "While the room is uncleared and no teleport is possible, keep the teleport map on screen faint and inert instead of hiding it" },

        { "Controls", "FasterCursorMove", "Move cursor faster in keyboard minimap by press arrow keys once instead of having to hold them" },
        { "Controls", "IgnoreMovementKeys", "Keep moving the map cursor while you walk, instead of pausing it until you let go" },
        { "Controls", "QuicklyOneRoomMove", "Quickly teleport using TAB + ASWD" },
        { "Controls", "NoShootWhenClick", "Disable shoot when teleporting via TAB + Click" },
    }
    for _, info in ipairs(options) do
      if info[4] == nil or info[4] then
        ModConfigMenu.AddSetting(
          "GoodTrip [Fixed]", info[1],
          {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
              return gtconfig[info[2]]
            end,
            Display = function()
              return info[2] .. ": " .. (gtconfig[info[2]] and "on" or "off")
            end,
            OnChange = function(b)
              gtconfig[info[2]] = b
            end,
            Info = { info[3] },
          }
        )
      end
    end
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", "Display",
      {
        Type = ModConfigMenu.OptionType.NUMBER,
        Minimum = 5, --never 0: an invisible window is the bug this feature exists to end
        Maximum = 100,
        Default = 35,
        CurrentSetting = function()
          return gtconfig.DimMapAlpha or 35
        end,
        Display = function()
          return ("DimMapAlpha: %d%%"):format(gtconfig.DimMapAlpha or 35)
        end,
        OnChange = function(b)
          gtconfig.DimMapAlpha = b
        end,
        Info = { "How faint the teleport map is while the room is uncleared (DimMapInCombat)" },
      }
    )
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", "Map",
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
      "GoodTrip [Fixed]", "Map",
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
      "GoodTrip [Fixed]", "Map",
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
    --shown under the key's own name: without the menu the same setting has to be
    --typed into gtconfig.lua, and a label that differs from the key sends the
    --player to a setting that does not exist
    for _, info in ipairs({
        { "CalibMainX", "Sideways nudge for corner-map clicks in the normal world (pixels): clicks landing LEFT of your aim -> increase, RIGHT of aim -> decrease" },
        { "CalibMirrorX", "Sideways nudge for corner-map clicks in the mirror world (pixels): clicks landing LEFT of your aim -> increase, RIGHT of aim -> decrease" },
        { "CalibMainY", "Vertical nudge for corner-map clicks in the normal world (pixels): clicks landing ABOVE your aim -> increase, BELOW your aim -> decrease" },
        { "CalibMirrorY", "Vertical nudge for corner-map clicks in the mirror world (pixels): clicks landing ABOVE your aim -> increase, BELOW your aim -> decrease" },
    }) do
        ModConfigMenu.AddSetting(
          "GoodTrip [Fixed]", "Calibration",
          {
            Type = ModConfigMenu.OptionType.NUMBER,
            Minimum = -100, --several cells: game builds re-anchor the corner map whole cells apart, ±1 cell wasn't enough
            Maximum = 100,
            Default = 0,
            CurrentSetting = function()
              return gtconfig[info[1]] or 0
            end,
            Display = function()
              return ("%s: %+dpx"):format(info[1], gtconfig[info[1]] or 0)
            end,
            OnChange = function(b)
              gtconfig[info[1]] = b
            end,
            Info = { info[2] },
          }
        )
    end
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", "Controls",
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
        Info = { "we have TAB + Z to teleport to last room, which button on the controller would act as Z?" },
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
        Info = { "we have TAB + R to fast restart, which button on the controller would act as R?" },
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
    --Mod配置菜单（中文版）announces itself, and it is the only build that draws
    --text as UTF-8 -- the plain menu goes byte by byte, where Chinese comes out
    --as rubbish. So the English menu above stays exactly as it is, this only
    --paints over what is drawn, and the keys settings save under never move.
    --Whoever has that menu has a menu, so the setting names go to Chinese too;
    --the English names are for hand-editing gtconfig.lua, which is a different
    --person entirely.
    if ModConfigMenu.i18n == "Chinese" then
        local CAT = "GoodTrip [Fixed]"
        local tabs = {
            { "Map", "地图" },
            { "Fairness", "公平" },
            { "Shortcuts", "快捷键" },
            { "Display", "显示" },
            { "Controls", "操作" },
            { "Calibration", "校准" },
            { "Keybinds", "按键" },
        }
        --Display is built by a function, so these are search-and-replace pairs
        --run over the finished line ("KeyboardMapEnable: on"). Anchored to the
        --front and taking the colon with them: unanchored, OverlayKey would
        --also eat the front of OverlayKeyController, and the pairs are applied
        --in no particular order
        local names = {
            { "^KeyboardMapEnable:", "传送小地图:" },
            { "^CursorOnGameMap:", "光标画在原版地图上:" },
            { "^AllowNeighborRoom:", "允许传送到未清的邻居房:" },
            { "^AllowAnyRoom:", "允许传送到任意房间:" },
            { "^FairTripPath:", "只能传送到已清房连通的房间:" },
            { "^FairTripTime:", "按距离增加游戏时间:" },
            { "^FollowCurseOfLost:", "迷失诅咒下禁用传送:" },
            { "^LastRoomShortcut:", "TAB+Z 回上一个房间:" },
            { "^FastRestartEnable:", "TAB+R 快速重开:" },
            { "^AllowBookmarking:", "TAB+1~9 房间书签:" },
            { "^DimMapInCombat:", "战斗中淡显地图:" },
            { "^DimMapAlpha:", "淡显的浓度:" },
            { "^ShowSpecialIcons:", "显示特殊房间图标:" },
            { "^DangerCautionCompat:", "危险房间提示联动:" },
            { "^TeleportAnimation:", "传送动画:" },
            { "^LandAtDoor:", "传送后站在门口:" },
            { "^FastTransition:", "更快的过场:" },
            { "^FasterCursorMove:", "光标整格移动:" },
            { "^IgnoreMovementKeys:", "走路时不打断瞄准:" },
            { "^QuicklyOneRoomMove:", "TAB+ASWD 走一格:" },
            { "^NoShootWhenClick:", "点击传送时不开火:" },
            { "^SwapAnalogSticks:", "交换左右摇杆:" },
            { "^TopLeftX:", "小地图左上角 X:" },
            { "^TopLeftY:", "小地图左上角 Y:" },
            { "^MinimapScale:", "小地图缩放:" },
            { "^CalibMainX:", "主世界光标校准 X:" },
            { "^CalibMirrorX:", "镜像世界光标校准 X:" },
            { "^CalibMainY:", "主世界光标校准 Y:" },
            { "^CalibMirrorY:", "镜像世界光标校准 Y:" },
            { "^OverlayKeyController:", "手柄打开地图的按键:" },
            { "^OverlayKey:", "打开地图的按键:" },
            { "^ControllerAlternateZ:", "手柄上代替 Z 的键:" },
            { "^ControllerAlternateR:", "手柄上代替 R 的键:" },
            { ": on$", ": 开" },
            { ": off$", ": 关" },
            { ": None$", ": 无" },
        }
        --Info is a plain table of strings, so these match the whole line.
        --Punctuation stays ASCII throughout: the bundled font has the hanzi but
        --not the full-width marks, which come out as gaps on screen
        local infos = {
            ["Classic GoodTrip minimap, teleport using TAB + arrow keys. Turn this back on if you dragged it into the trash by accident."] = "经典款 GoodTrip 传送小窗, 按住 TAB 用方向键选房间传送. 若不小心拖进垃圾桶删掉了, 把这项打开就能回来",
            ["Put the cursor on the game's own corner map and hide the mod's window (needs REPENTOGON)"] = "光标直接画在游戏右上角的地图上, 本 mod 自己的小窗不再显示 (需要 REPENTOGON)",
            ["Allow moving into uncleaned neighbor room"] = "允许传送进紧挨着已清房间的未清房间",
            ["Allow teleporting to any room on the map, with no path to it cleared first"] = "允许传送到地图上任何一个房间, 沿途不必先清干净",
            ["Only allow teleport to rooms reachable through cleared rooms"] = "只允许传送到能经由已清房间走到的房间",
            ["Fairly increase game time according to player move speed and distance"] = "按移动速度和距离折算, 为传送补上应有的游戏时间",
            ["Disable GoodTrip on curse of lost"] = "迷失诅咒下禁用传送, 因为游戏本体就不显示地图",
            ["Allow teleport back to last room via TAB + Z"] = "TAB+Z 回到上一个待过的房间",
            ["Allow restarting the run quickly via TAB + R"] = "TAB+R 直接重开一局",
            ["Allow adding bookmarks for rooms via TAB + 1~9"] = "TAB+1~9 给房间做书签, 再按一次传送过去, TAB+0 全部清空",
            ["While the room is uncleared and no teleport is possible, keep the teleport map on screen faint and inert instead of hiding it"] = "房间还没清干净, 传送本来就用不了, 这时把传送小窗淡淡地留在原地而不是整个藏起来",
            ["How faint the teleport map is while the room is uncleared (DimMapInCombat)"] = "战斗中传送小窗淡到什么程度, 百分比, 最低 5% 免得看不见",
            ["Show an icon on rooms you have visited that have mirror, white fireplace, minecart, mine button, or tinted skull"] = "在待过的房间上标出镜子, 白火, 矿车, 矿洞按钮, 暗色骷髅",
            ["weather to work with my other mod 'Dangerous room! Caution' (if detected) by indicate dangerous room by colors"] = "检测到我的另一个 mod 'Dangerous room! Caution' 时, 用颜色标出危险房间",
            ["Play cool animation on teleport"] = "传送时播放动画",
            ["Arrive standing at the exact door a walk would have come in by"] = "传送后站在正常走过去会进来的那道门边",
            ["Even faster transition without animation"] = "连过场动画也省掉, 房间切换更快",
            ["Move cursor faster in keyboard minimap by press arrow keys once instead of having to hold them"] = "方向键按一下光标就跳一整格, 按住则连续跳, 不必一直按着慢慢挪",
            ["Keep moving the map cursor while you walk, instead of pausing it until you let go"] = "走路时光标继续跟着方向键动, 而不是等你松手",
            ["Quickly teleport using TAB + ASWD"] = "按住 TAB 用 ASWD 一次走一个房间",
            ["Disable shoot when teleporting via TAB + Click"] = "按住 TAB 点地图时不会顺手打出眼泪",
            ["Swap the left and right analog sticks"] = "交换左右摇杆: 用移动摇杆挪光标",
            ["Keyboard minimap top-left X coordinate"] = "传送小窗左上角的横坐标",
            ["Keyboard minimap top-left Y coordinate"] = "传送小窗左上角的纵坐标",
            ["Keyboard minimap size, x0.5 (tiny) to x1.0 (original) up to x2.5"] = "传送小窗大小, x0.5 很小, x1.0 原始大小, 最大 x2.5",
            ["Sideways nudge for corner-map clicks in the normal world (pixels): clicks landing LEFT of your aim -> increase, RIGHT of aim -> decrease"] = "主世界里点原版地图的横向补正, 单位像素: 落点偏左就调大, 偏右就调小",
            ["Sideways nudge for corner-map clicks in the mirror world (pixels): clicks landing LEFT of your aim -> increase, RIGHT of aim -> decrease"] = "镜像世界里点原版地图的横向补正, 单位像素: 落点偏左就调大, 偏右就调小",
            ["Vertical nudge for corner-map clicks in the normal world (pixels): clicks landing ABOVE your aim -> increase, BELOW your aim -> decrease"] = "主世界里点原版地图的纵向补正, 单位像素: 落点偏上就调大, 偏下就调小",
            ["Vertical nudge for corner-map clicks in the mirror world (pixels): clicks landing ABOVE your aim -> increase, BELOW your aim -> decrease"] = "镜像世界里点原版地图的纵向补正, 单位像素: 落点偏上就调大, 偏下就调小",
            ["Keyboard key to open the overlay"] = "用哪个键打开传送地图",
            ["Controller button to open the overlay"] = "用手柄哪个键打开传送地图",
            ["we have TAB + Z to teleport to last room, which button on the controller would act as Z?"] = "TAB+Z 是回上一个房间, 手柄上哪个键当 Z 用?",
            ["we have TAB + R to fast restart, which button on the controller would act as R?"] = "TAB+R 是快速重开, 手柄上哪个键当 R 用?",
        }
        --Popup is a function like Display, so it takes the replace-pair form
        local popups = {
            { "Press a button on your controller to change this setting.", "按一下手柄上的键来设置" },
        }
        ModConfigMenu.SetCategoryNameTranslate(CAT, "GoodTrip [修复版]")
        for _, tab in ipairs(tabs) do
            ModConfigMenu.SetSubcategoryNameTranslate(CAT, tab[1], tab[2])
            ModConfigMenu.TranslateOptionsDisplayWithTable(CAT, tab[1], names)
            ModConfigMenu.TranslateOptionsInfoTextWithTable(CAT, tab[1], infos)
            ModConfigMenu.TranslateOptionsPopupWithTable(CAT, tab[1], popups)
        end
    end
end
_gt:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContined)
    --a saved config that will not read back is worth losing on its own; it is not
    --worth the rest of this callback, which is where the window's own position and
    --scale are set, and where a throw would leave the run with neither
    local cfg
    if _gt:HasData() then
        local dat = _gt:LoadData()
        cfgdata_written = dat
        local json = require('json')
        local ok, read = pcall(json.decode, dat)
        if ok and type(read) == "table" then
          cfg = read
        else
          print("GoodTrip [Fixed]: the saved settings could not be read, starting from defaults")
        end
    end
    if cfg then
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
    end
    --last word goes to the hand-edited file, whether or not a save exists
    apply_overrides()
    mmp_ltpos = Vector(gtconfig.TopLeftX or 100, gtconfig.TopLeftY or 100)
    update_mmscale()
    update_analog_mappings()
    -- mmp_pos0 = mmp_ltpos - mmp_ltpos_
    -- mmp_rbpos = mmp_pos0 + mmp_rbpos_
    cfgdata_loaded = true --a first-time player has nothing on disk, yet still gets saved
end)
_gt:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
    save_config()
end)
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
function _gt:check_neigh_connected(trd, cond)
    local tid = trd.SafeGridIndex
    if (trd.DisplayFlags & 1) ~= 0 then
      --a room bought with a red key stands open: what it turned out to hold, a
      --shop or a treasure room, is not a door the trip is picking. The key was
      --the price, and it is already paid, so its contents do not make it special
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
        --column guard: a +-1-ish offset from the row edge would wrap to a room
        --on the neighboring row (e.g. column 0 "left" hits column 12 above),
        --falsely treating two unconnected rooms across the map as adjacent
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
            if check_grid(off) then
                -- print(tid, off)
                return true
            end
        end
      end
    end
    return false
end
--
function _gt:get_reachable_rooms()
    --flood out of the current room through visited+cleared rooms: a trip may
    --only land on the island the player could have walked to. Grid adjacency
    --alone counts a secret room as a corridor on all four sides, which hands out
    --a free wall the player never bombed, so each step has to hold a door too
    local start = crd.SafeGridIndex
    --a wall blown open since this room was entered would otherwise still read as
    --solid, and the trip it opened would be refused
    _gt:sweep_doors()
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
--
--the half of the door graph that answers for the side of the mirror being stood
--on. Asked of the live room every time rather than the cached one: a trip hops
--through an antechamber mid-call, and a wrong link, unlike a missing one, would
--stand for the rest of the floor
function _gt:door_graph()
    local d = Game():GetRoom():IsMirrorWorld() and 1 or 0
    door_link[d] = door_link[d] or {}
    door_swept[d] = door_swept[d] or {}
    return door_link[d], door_swept[d]
end
--
--read the walls of the room being stood in, the only room whose doors the game
--will answer for, and write them into the graph both ways. A slot still holding
--DOOR_HIDDEN is a wall no bomb has opened yet, so it makes no passage;
--everything else, locked doors included, is somewhere a player could walk.
--Every room here is read live, so the doors, the room they belong to and the
--side of the mirror they are filed under can never come from different moments.
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
        --a curse room's door is spiked or it is not, and reading it here is the
        --only honest way to know: Flat File takes the spikes off the side it was
        --standing beside, and they do not come back, so the trinket picked up or
        --dropped afterwards says nothing about this door. The side facing in and
        --the side facing out are separate doors and are kept apart.
        if door.TargetRoomType == RoomType.ROOM_CURSE then
          curse_bare_outside[there] = door.VarData ~= 0
        elseif live:GetType() == RoomType.ROOM_CURSE then
          curse_bare_inside[here] = door.VarData ~= 0
        end
        if there ~= here then
          --this end knows which of its own walls the door sits in; the far end
          --only learns that when its own turn comes, so it gets a bare mark
          link[here][there] = i
          link[there] = link[there] or {}
          if link[there][here] == nil then link[there][here] = true end
        end
      end
    end
end
--
--may a trip step between these two rooms? A passage seen from either end says
--yes. Otherwise a swept room saying nothing is a no. Where neither room has been
--read -- the mod loaded mid-run, or a save picked up again -- there is no
--evidence either way, and the old grid-adjacency answer stands, so nothing that
--used to work starts refusing.
function _gt:linked(a, b)
    local link, swept = _gt:door_graph()
    if link[a] and link[a][b] ~= nil then
      return true
    end
    return not (swept[a] or swept[b])
end
--
--the door a trip should put the player down at, in the room being arrived in.
--The game is only half a help here. It ignores the Direction it is handed --
--measured twice, the second time by passing the side of the door the trip means
--to use and watching the same landing come out -- and works the wall out from the
--two grid numbers instead, which is right for neighbours and arbitrary for
--anything further, so a long trip can land against a blank wall. The cell it is
--handed does count, but only to choose among the doors on that wall; see
--_gt:landing_route. So the wall is bought by leaving from the right room and the
--door by naming the right cell, and this, which reads the room's own doors off
--the sweep, is what says which door that is: the one facing the room being left,
--and failing that the one on the side it lies on.
--the room a walk would have arrived from: the step before the target on the
--shortest way there through rooms already walked. A trip stands in for that
--walk, so it should come in by the same door -- straight-line direction is not
--the same thing, and on a floor that bends around it points at the wrong wall.
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
          --the target itself may be an uncleared neighbour, which is a room a
          --trip is allowed to land in but not one it may pass through
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
--
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
--
--the cell of the room being arrived in that a walk would have stepped into: the
--two rooms touch somewhere on the floor grid, and the cell on the far side of
--that touch is the one whose door faces the walk. Read off the grid rather than
--off the door sweep, so a room nobody has been inside yet answers too.
function _gt:touching_cell(from, to)
    local src, dst = grid_room[from], grid_room[to]
    if not (src and dst) then return nil end
    for cell, d in pairs(grid_room) do
      if d.ListIndex == src.ListIndex then
        local col = cell % 13
        for _, step in ipairs({ -13, 13, -1, 1 }) do
          --a step sideways has to stay in the same row; the grid is 13 wide and
          --the ends of one row sit next to the ends of the next
          if not ((step == -1 and col == 0) or (step == 1 and col == 12)) then
            local nd = grid_room[cell + step]
            if nd and nd.ListIndex == dst.ListIndex then return cell + step end
          end
        end
      end
    end
    return nil
end
--
--and which cell to hand the transition, with the room to leave from to make it
--stick. The game ignores the direction it is given, but it does read the cell: a
--room laid over several of them has a door for each, and the player is put down
--at the door belonging to the cell handed over -- among the doors on one wall,
--and which wall is read from the room the trip starts in. So next door the cell
--is enough, and further off the room being left has to be the one the walk would
--have come from too, or the arrival is at whatever wall faces the real starting
--room: the wrong door, and in a room bigger than the screen the wrong screen as
--well, since the game fixes the part to show from where it laid him.
function _gt:landing_route(from, to)
    local cell = _gt:touching_cell(from, to)
    if cell then return cell, nil end
    local walked = _gt:route_parent(from, to)
    if not walked then return nil, nil end
    return _gt:touching_cell(walked, to), walked
end
--
--and then put the player there by hand, for whatever the levers above did not
--reach. Of the levers the game does offer, Direction is ignored, EnterDoor
--ignores writes, and LeaveDoor was measured changing nothing at all; the cell and
--the room left from are the two that work, and between them they cover a room
--bigger than the screen, which is the case that mattered. What is left over lands
--here. One step inside the doorway is where walking in leaves you, so that is
--where a trip leaves you.
--everyone a landing has to carry: the players, and everything the game laid down
--alongside them where it thought they came in. Familiars by their type, the rest
--by who owns them, which is how Mom's Knife -- an entity in its own right, not a
--familiar -- and a carried tear come along.
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
--
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
    --everyone moves by the same step, so a co-op pair keeps its spacing. In a room
    --bigger than the screen this step is nearly always nothing at all: the cell
    --handed to the transition already put the game's own landing at this door, and
    --the view with it. What is left here is the rest -- the room the game placed
    --him in by some other rule, and the familiars laid down beside him.
    local shift = stand - player.Position
    for _, e in ipairs(_gt:landed_party()) do
      e.Position = e.Position + shift
    end
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
      --the switch that gives up on paths altogether: any room the map knows is a
      --target, walked to or not, with nothing cleared on the way. Asked after the
      --two refusals that hold whatever it says -- the room being stood in is not
      --a trip, and a room the map has never heard of has no place to land
      if gtconfig.AllowAnyRoom then
        return true
      end
      --the room to step off from must be on the player's own island, else an
      --Emperor'd boss room would be a free lift back across unexplored rooms.
      --only cleared rooms are looked up in reach, where the flood's plain 4-dir
      --adjacency and check_neigh_connected's shape table agree
      local reach = gtconfig.FairTripPath and _gt:get_reachable_rooms() or nil
      if trd.VisitedCount > 0 and trd.Clear
          and (not reach or reach[trd.SafeGridIndex] == true) then
        --the original rule, and still the common one: a room you have already
        --walked and emptied is a valid target on its own. AllowNeighborRoom only
        --ever widens this, so it must not be able to take it away -- a start room
        --left behind by an Emperor card has no cleared neighbor of its own
        return true
      elseif not gtconfig.AllowNeighborRoom then
        return false
      end
      -- print(stage, Game():IsGreedMode(), trd.Data.Type)
      --the same wall applies to the last hop: stepping off a secret room into an
      --uncleared neighbour is only a step where a hole was actually blown. Held
      --to the same switch as the flood -- `reach` is nil exactly when the player
      --asked for no path rules, and a wall is a path rule like any other
      return _gt:check_neigh_connected(trd, function(rd)
          return (rd.DisplayFlags & 1 ~= 0) and rd.VisitedCount > 0 and rd.Clear
            and (not reach or (reach[rd.SafeGridIndex]
              and _gt:linked(rd.SafeGridIndex, trd.SafeGridIndex)))
      end)
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
--is this way through a curse room's door already paid for? Two different things
--waive it and they answer at different times. Isaac's Heart and Tooth and Nail
--take the hit for you, so they are asked about now. Flat File is not asked about
--at all where the door has been seen, because it acts on the door and not on the
--player; only for a side that has never been laid down does the trinket in hand
--decide, and that is right, because that side is about to be laid down under it.
function _gt:curse_toll_free(gid, by_inner_door, room_reloads)
    if player:HasCollectible(276) or player:HasCollectible(663) then
      return true
    end
    --Flat File takes spikes off, it never puts them back, and it does the taking
    --off as the room is laid down. So the trinket in hand answers for any door
    --about to be laid down again -- which is every one of these but the door of
    --the room already being stood in, whose spikes are whatever they are now.
    if room_reloads and player:HasTrinket(151) then
      return true
    end
    local bare = curse_bare_outside[gid]
    if by_inner_door then bare = curse_bare_inside[gid] end
    return bare == true
end
--
function _gt:check_curse_room(gid)
    if debug then return end
    ----
    --a secret room is opened with a bomb, and the hole that leaves has no spikes
    --on it, so a step between a secret room and the room guarding it is free
    --whichever way it is taken -- including when the room guarding it is the curse
    --room, which is the whole of what used to be paid for here. (The two tests
    --that stood here asked this same question the wrong way round: the table is
    --keyed by secret rooms and they looked up curse rooms in it, so they never
    --found anything and never let anyone through.)
    if secret_pre_room_id[crid] == gid or secret_pre_room_id[gid] == crid then
      return
    end
    local trd = grid_room[gid]
    if crd.Data.Type == 10 then --from curse room
      if not _gt:curse_toll_free(crsid, true, false) then
        _gt:hurt(1)
      end
    elseif trd.Data.Type == 10 and not player:IsFlying() then --target to curse room
      if not _gt:curse_toll_free(trd.SafeGridIndex, false, true) then
        _gt:hurt(1)
      end
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
    _gt:check_curse_room(gid)
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
    if gtconfig.FairTripTime then
      dist = _gt:fair_trip(crd.SafeGridIndex, gid)
      if dist == 999 then
        _gt:tele_failed()
        return
      end
    end

    --the antechamber is looked up by grid index, and an L-shaped room's anchor
    --cell is not part of the room, so grid_room has no key for it: bind the
    --descriptor once and skip the hop when there is none, rather than index nil
    local from_pre = crd.Data.Type == 7 and secret_pre_room_id[crid] or nil
    local from_prd = from_pre and grid_room[from_pre] or nil
    if from_prd then -- from secret room (skip if antechamber never recorded)
      if from_prd.ListIndex == grid_room[gid].ListIndex then
        gid = from_pre
      --check_curse_room
      elseif not (grid_room[gid].Data.Type == 10 and secret_pre_room_id[gid] and secret_pre_room_id[gid] == crid) then
        --the hole a bomb made into the secret room carries no spikes, so this toll
        --is not for coming in; it is for the real door being left by on the far
        --side, which is the curse room's own
        if from_prd.Data.Type == 10 and not _gt:curse_toll_free(from_prd.SafeGridIndex, true, true) then
          _gt:hurt(1)
        end
        Game():ChangeRoom(from_pre,-1)
      end
    end
    if grid_room[gid].Data.Type == 7 then --target to secret room
      local to_pre = secret_pre_room_id[gid]
      local to_prd = to_pre and grid_room[to_pre] or nil
      if to_prd then
        --crd is the room we stand in; grid_room[crid] would be nil in an L room
        if to_prd.ListIndex == crd.ListIndex then
          if crd.Data.Shape > 3 then
            Game():ChangeRoom(to_pre,-1)
          end
        --check_curse_room
        elseif not (crd.Data.Type == 10 and secret_pre_room_id[crid] and secret_pre_room_id[crid] == gid) then
          if to_prd.Data.Type == 10 and not player:IsFlying()
              and not _gt:curse_toll_free(to_prd.SafeGridIndex, false, true) then
            _gt:hurt(1)
          end
          Game():ChangeRoom(to_pre,-1)
        end
      end
    end
    --
    --named here rather than up top: an antechamber hop may have moved the
    --player since, and the door to arrive by faces wherever they stand now
    local trd = grid_room[gid]
    local here = Game():GetLevel():GetCurrentRoomDesc().SafeGridIndex
    local there = trd and trd.SafeGridIndex or gid
    tele_door_slot = -1 --off means the game's own landing, so nothing to aim for
    local arrive = gid --the cell handed over, which is the one clicked unless a
                       --better one is known; see _gt:landing_route
    if gtconfig.LandAtDoor then
      local cell, walked = _gt:landing_route(here, there)
      arrive = cell or gid
      --a room bigger than the screen, reached from further off than next door,
      --needs the wall chosen as well as the door, and the wall comes from the room
      --the trip starts in. So the trip starts one room earlier, from the one the
      --walk would have come from -- the same step inside the room that the cell was
      --read off. Kept to the trips that need it: a room next door already has the
      --right wall, and a room one screen big has nothing to choose between.
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
          --for some stupid fucking reason, the boss rush time check goes off of TimeCounter, but the Hush time check doesn't... 
          -- Game().BlueWombParTime = math.max(Game().BlueWombParTime - addTime, 0)
          ----------------------------------------------------------------------
          Game().TimeCounter = Game().TimeCounter + addTime
        end
      --(a legacy duplicate StartRoomTransition sat here passing the boolean
      --TeleportAnimation as the anim id — strict game builds threw "number
      --expected, got boolean" and the teleport died; the properly-typed call
      --below covers every path, only its tele_cd side effect is kept)
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
    --the direction really is ignored, measured twice now: the same trip lands on
    --the same spot whether it is handed NO_DIRECTION or the side of the door it
    --is meant to arrive by. The wall is chosen from the room the trip starts in,
    --which is why the hop above exists.
    Game():StartRoomTransition(arrive, Direction.NO_DIRECTION, tele_anime, player, -1)
    tele_cd = tele_anime == 3 and 45 or 10
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
      --the mirrored map keeps the same box on screen and only flips what is
      --drawn inside it, so the flip reflects about that box's own middle: the
      --drawn columns run ltr.X..rtr.X, half a cell of margin on either side
      local ltr = _gt:get_corner_room(3)
      mirrorsum = 2 * ltx + (ltr.X + rtr.X + 1) * 17
    end
    return ltx, lty, mirrorsum
end
--
function _gt:get_pos_grid_index(pos)
    if (not gtconfig.FollowCurseOfLost and level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0) then
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
--fcol/frow, if given, are the continuous (fractional) column/row to place the
--point at instead of mgid's own -- both branches below are affine in col/row,
--so this traces a pixel-exact position anywhere between cells, not just their
--centers; grid_room/reference-room lookups still key off the whole cell (mgid)
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
    --2 was oversized: the cursor's native 16x32 footprint at 2x already
    --exceeds a single 17x15 room cell on its own; 1x (native size) is a
    --closer starting point and still needs eyes on it to call it right
    return Vector(px - calibx, lty + frow * 15 + 7.5 - caliby), 1
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
function _gt:get_room_neighbours()
    room_neighbours = {}
    local all_room = level:GetRooms()
    for i = 0, all_room.Size do
      local des = all_room:Get(i)
      if des then
            room_neighbours[des.SafeGridIndex] = {
            --may be redundant to keep descriptor here and in grid_room, maybe it could be merged
          Descriptor = des,
          Neighbors = {}
        }
    end
    end

    --discover neighbours
    --maybe use neighlut for more efficient way later

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
                  --column guard: +-1 from a row edge would wrap to the
                  --neighboring row (same fix as in check_neigh_connected)
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
        -- Convert neighbour sets to arrays
      for _, room in pairs(room_neighbours) do
        local list = {}

        for id in pairs(room.Neighbors) do
          list[#list + 1] = id
        end

        room.Neighbors = list
      end

end

--the outermost drawn column and row on the side `num` names (1 left-top,
--2 right-top, 3 left-bottom, 4 right-bottom). the whole 13 are scanned from
--that side inward: the starting room usually pins column 6, but a dimension
--entered part way through -- the mirror -- can have every drawn room on one
--side of it, and stopping at 6 would report the middle instead of the edge
function _gt:get_corner_room(num)
    local corner_room = Vector(6, 6)
    local fx = {1, -1, 1, -1}
    local fy = {1, 1, -1, -1}
    local ffx = fx[num]
    local ffy = fy[num]
    ----
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
    ----
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
    --the cursor's range is the drawn rooms themselves: the padding below only
    --widens the widget's window, and the game's own map never draws those empty
    --cells at all, so a cursor allowed onto one would sit off the map there
    ctrl_ltroom = Vector(ltroom.X, ltroom.Y)
    ctrl_rbroom = Vector(rbroom.X, rbroom.Y)
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
    if _gt:gon_map_cursor() then --the game's own map is the widget: no window chrome
      return
    end
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
--game-map cursor mode: the aux window stays hidden, the keyboard cursor is
--drawn on the game's own map instead; selection & teleport logic untouched
function _gt:gon_draw_map_cursor()
    --checked here, not just at the draw_minimap call site: under REPENTOGON
    --this also runs unconditionally from MC_POST_HUD_RENDER every frame, so
    --GMC off must not leak a cursor through that second path
    if not _gt:gon_map_cursor() or not mmp_ctrl then
      return
    end
    --the widget appearing at all is its own signal that a cursor is in play;
    --the game's map is always on screen, so drawing on it the instant TAB is
    --held puts a cursor (red, since it starts on the room you are standing in
    --and you cannot trip to yourself) in front of someone who only wanted to
    --read the map. wait until the keyboard has actually been used to aim
    if not kb_active then
      return
    end
    local mgid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
    if mgid < 0 then
      return
    end
    --same as get_pos_grid_index_mmp's cx/cy, minus the floor: how far mmp_ctrl_pos
    --sits inside its cell, so the sprite can glide instead of snapping cell to
    --cell -- mmp_ctrl_pos moves in real pixels, cell_to_screen's math is affine
    --in col/row, so this traces the true position rather than a rounded one
    local fcol = (mmp_ctrl_pos.X - mmp_pos0.X - 2 * mmsc) / (8 * mmsc)
    local frow = (mmp_ctrl_pos.Y - mmp_pos0.Y - 2 * mmsc) / (7 * mmsc)
    local center, scale = _gt:cell_to_screen(mgid, fcol, frow)
    if not center then
      return
    end
    if _gt:check_teleble(mgid) then
      cursor.Color = Color(1, 1, 1, 1, 0, 0, 0)
    else
      cursor.Color = Color(1, 0.3, 0.3, 1, 0, 0, 0) --not teleportable: red, like the aux map's red rooms
    end
    --two plot corrections, kept here rather than folded into cell_to_screen so
    --that stays pure geometry (and calibx/caliby keep meaning just the player's
    --sliders). first: cursor.anm2's pivot (7,7) sits well off the layer's own
    --visual center (8,16 -- it's a pointer's hotspot, near the glyph's tip, not
    --its middle), so cancel it deterministically, scaled with the sprite.
    --second: the residual measured in-game under REPENTOGON. Y is the same in
    --both worlds, X flips with the mirrored axis -- the 1px asymmetry matches
    --the one already calibrated into vanilla_map_anchors (-4 main vs -5 mirror)
    local gmcoff = room:IsMirrorWorld() and Vector(9, 2) or Vector(-8, 2)
    cursor.Scale = Vector(scale, scale)
    cursor:Render(center - Vector(1, 9) * scale + gmcoff, Vector(0, 0), Vector(0, 0))
    cursor.Scale = Vector(1, 1)
    cursor.Color = Color(1, 1, 1, 1, 0, 0, 0)
end
--
function _gt:draw_minimap(faint)
    if _gt:gon_map_cursor() then
      --REPENTOGON draws the game's own map during MC_HUD_RENDER, so a cursor
      --drawn here or there both land underneath it; MC_POST_HUD_RENDER is the
      --one that actually runs after -- let it handle drawing instead (below)
      if not REPENTOGON then
        _gt:gon_draw_map_cursor()
      end
      return
    end
    --faint pass: the room is not cleared, so no trip is possible from it. The
    --window stays where it is at low alpha rather than disappearing, which is
    --what players report as the mod being broken. Nothing on it can be used,
    --so the chrome and the cursor are left out (see tab_action)
    local alpha = faint and math.min(math.max(gtconfig.DimMapAlpha or 35, 5), 100) / 100 or 1
    mic.Color = Color(1, 1, 1, alpha, 0, 0, 0)
    select.Color = Color(1, 1, 1, alpha, 0, 0, 0)
    ---draw outline---
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
    ---draw room&icon---
    for i = 1, #draw_room_id do
      local rd = grid_room[draw_room_id[i]]
      --a red room draws red, the way the game's own map draws it. The room says
      --so itself; counting rooms and calling anything past the floor's original
      --tally red missed the ones the list had room for already
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
        --visited only: these icons are read out of the room's spawn list, which
        --the game has not shown you yet, so drawing them early spoils the floor
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
    ---draw select---
    local checkid = nil
    if mmp_ctrl then
      checkid = _gt:get_pos_grid_index_mmp(mmp_ctrl_pos)
    else
      checkid = _gt:get_pos_grid_index_mmp(_gt:mirror_mmp_pos(mpos))
    end
    if grid_room[checkid] then
      --two different questions, and they were being answered by one lookup. What
      --lights up is the cell under the pointer: the drawing pass files a room
      --under each cell it drew it on, so a cell it never drew on should stay
      --dark. Where the outline goes is the room's own corner, which is the entry
      --filed under its top-left cell -- drawing it at the cell hovered instead
      --puts it a room away on anything wider than 1x1. A Void boss room has no
      --entry at its top-left at all, being filed under whichever of its cells
      --passed the test there, so it falls back to the cell that was hit, which is
      --the one it was drawn on. That room used to answer neither question.
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
    ---draw cursor---
    if mmp_ctrl and not faint then
      cursor:Render(_gt:mirror_mmp_pos(mmp_ctrl_pos), Vector(0, 0), Vector(0, 0))
    end
end
---control & run---
--the keyboard cursor may only stand on the drawn map: its range is the
--rectangle between the first and the last drawn room's own resting spot.
--holding the position inside that rectangle -- rather than gating each step by
--how much room is left, which left a few pixels of slack past the last room
--where the cursor selects nothing and, on the game map, is not drawn at all --
--means a held key simply stops on the edge room. it cannot bounce either: the
--clamp lands on the spot movement would reach anyway, so the next frame has
--nothing left to correct. mmp_ctrl_pos is kept unmirrored, only the direction
--of a key flips, so one rectangle serves both worlds
local function clamp_ctrl_pos(pos)
    local minx = mmp_pos0.X + (ctrl_ltroom.X * 8 + 6) * mmsc
    local maxx = mmp_pos0.X + (ctrl_rbroom.X * 8 + 6) * mmsc
    local miny = mmp_pos0.Y + (ctrl_ltroom.Y * 7 + 5) * mmsc
    local maxy = mmp_pos0.Y + (ctrl_rbroom.Y * 7 + 5) * mmsc
    return Vector(math.min(math.max(pos.X, minx), maxx), math.min(math.max(pos.Y, miny), maxy))
end
--
function _gt:mmp_ctrl_move()
    for i = 1,4 do
      if gtconfig.QuicklyOneRoomMove then
        if Input.IsActionTriggered(movkey[i], player.ControllerIndex) then
          local npos = clamp_ctrl_pos(mmp_ctrl_pos + _gt:mirror_mmp_dir(dir[i] * Vector(8, 7) * mmsc))
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
        --a fresh tap jumps immediately (the cooldown resets whenever the key is
        --up); held afterward, it keeps jumping a room at a time instead of
        --needing a fresh tap per room
        if Input.IsActionPressed(key[i], player.ControllerIndex) then
          if fast_move_cd[i] <= 0 then
            mmp_ctrl_pos = clamp_ctrl_pos(mmp_ctrl_pos + _gt:mirror_mmp_dir(dir[i]) * Vector(8, 7) * mmsc)
            fast_move_cd[i] = FAST_MOVE_REPEAT_FRAMES
          else
            fast_move_cd[i] = fast_move_cd[i] - 1
          end
        else
          fast_move_cd[i] = 0
        end
      else
        if Input.IsActionPressed(key[i], player.ControllerIndex) then
          local step = _gt:mirror_mmp_dir(dir[i]) * mmsc
          if _gt:gon_map_cursor() then
            --vanilla map cells (17x15px) are physically bigger than the 8x7
            --virtual unit this step size was tuned around, so the identical
            --held key moves ~2.1x faster in real screen pixels here than it
            --does on the widget; scale the step down to match its own pace
            step = step * Vector(8 / 17, 7 / 15)
          end
          mmp_ctrl_pos = clamp_ctrl_pos(mmp_ctrl_pos + step)
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
--a room still being fought in refuses every trip, and the window used to answer
--that by disappearing -- which reads as the mod having broken, and is most of the
--"my map is gone" reports. Draw it faint and inert instead. Only for that case:
--Curse of the Lost hiding the map is the player's own switch, and a room the map
--does not know is nothing to draw. Asked at both the windows that can be open --
--the one TAB holds up and the one the pin leaves standing -- so neither goes
--missing while the other stays.
function _gt:dim_map_only()
    return gtconfig.KeyboardMapEnable and gtconfig.DimMapInCombat
        and not _gt:check_teleble(false)
        and grid_room[crd.SafeGridIndex] ~= nil
        and not (gtconfig.FollowCurseOfLost and level:GetCurses() & LevelCurse.CURSE_OF_THE_LOST ~= 0)
end
--
function _gt:tab_action()
    local cp = Isaac.WorldToRenderPosition(Vector(320,280))
    scpos = cp + cp
    hudoffset = Options.HUDOffset * 10 --live: the map moves the moment the slider moves, so must our anchor (refreshing only on new_level lagged until the next floor)
    --
    if gtconfig.FastRestartEnable
        and (Input.IsButtonTriggered(Keyboard.KEY_R, player.ControllerIndex)
            or (gtconfig.ControllerAlternateR and Input.IsButtonTriggered(gtconfig.ControllerAlternateR, player.ControllerIndex))) then
      print('GoodTrip [Fixed] !!!FAST RESTARTING!!!')
      Isaac.ExecuteCommand("restart")
    end
    if gtconfig.QuicklyOneRoomMove and crd.Clear and player.ControlsCooldown < 2 then
      player.ControlsCooldown = player.ControlsCooldown + 1
    end
    --
    if _gt:dim_map_only() and not debug then
      mmp_ctrl = false --no cursor while it is inert; it rebuilds at the room you stand in
      _gt:draw_minimap(true)
    elseif (gtconfig.KeyboardMapEnable and _gt:check_teleble(false)) or debug then -------return when gtconfig.KeyboardMapEnable & debug disable
      local movement_pressed = false
      for i = 1, 4 do
        if Input.IsActionPressed(movkey[i], player.ControllerIndex) then
          movement_pressed = true
          break
        end
      end
      if not movement_pressed or gtconfig.QuicklyOneRoomMove or gtconfig.IgnoreMovementKeys then
        local arrowdown = Input.IsActionPressed(key[1],player.ControllerIndex)
            or Input.IsActionPressed(key[2],player.ControllerIndex)
            or Input.IsActionPressed(key[3],player.ControllerIndex)
            or Input.IsActionPressed(key[4],player.ControllerIndex)
        --the hover region the mouse can take the cursor over: the widget's own
        --box normally, the game's map under GMC (where the mouse already draws
        --its own pointer -- showing ours too would be two cursors). same
        --ownership rules either way, only the region differs. get_pos_grid_index
        --is the map's own hit test, so this can't drift from where clicks land
        local in_ui
        if _gt:gon_map_cursor() then
          in_ui = _gt:get_pos_grid_index(mpos) >= 0
        else
          in_ui = _gt:check_pos_en_box(mpos,mmp_ltpos + Vector(-8, -18) * mmsc,mmp_rbpos + Vector(20, 20) * mmsc) --ui zone
        end
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
        --a movement key only pauses the cursor. dropping mmp_ctrl here used to
        --rebuild it at the current room the moment the key came back up, so an
        --accidental tap threw away whatever room the player had lined up
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
      elseif gtconfig.KeyboardMapEnable and not _gt:gon_map_cursor() then --aux-widget zones (window click / pin / zoom / drag): only when the widget is visible
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
      local drag_ended = mouse_magnet --the position is only final once the edge clamps below have run
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
      if drag_ended then --don't wait for a clean quit: alt-F4 and TAB+R never reach MC_PRE_GAME_EXIT
        save_config()
      end
    end
    ---
end
--
function _gt:itemused()
    -- print('itemused', args)
    mmp_ctrl = false
    _gt:get_grid_room()
    _gt:get_room_neighbours()
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
    mouse_moved = (mpos - last_mpos):LengthSquared() > 4 --camera-independent (round-trip cancels camera); every frame so the baseline is fresh at TAB-open
    last_mpos = mpos

    if _gt:is_overlay_triggerd() then
      _gt:get_grid_room()
      _gt:prep()
      kb_active = false --every opening of the map starts as a read; an arrow key claims it
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
        --whatever is being aimed with. the keyboard cursor when it holds the
        --aim, otherwise the mouse -- on the game's own map first, then the
        --widget, the order a click resolves in. pointing at nothing at all
        --(no widget, mouse off the map) leaves the room being stood in
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
        _gt:tab_action() --do when tab pressed
      end
    elseif (gtconfig.KeyboardMapEnable) or debug then -------return when gtconfig.KeyboardMapEnable & debug disable
      --PIN ACTION WITHOUT TAB--
      if mmp_pin == 1 and not _gt:gon_map_cursor() and crd.Clear and _gt:check_teleble(false) then
        if mouse_in_ui then
          --the pointer is over the window, so the click is aimed at a room and not
          --at anything in front of the player. The same holds whether TAB is up or
          --the pin is, and only the held one was ever wired to it
          if gtconfig.NoShootWhenClick then
            _gt:player_shoot_cooldown()
          end
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
      elseif mmp_pin == 1 and not _gt:gon_map_cursor() and _gt:dim_map_only() and not debug then
        --pinned open into a room that refuses a trip: the same faint inert window
        --the held one gets, rather than the pin quietly going missing
        ui_timer = 0
        mmp_ctrl = false
        _gt:draw_minimap(true)
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
    --a wall can open under the player's feet: a bomb, or a red key buying a
    --whole room next door. The room being stood in is the only one the game
    --answers for, so read its walls every tick and the graph is never a door
    --behind. Mid-transition the live room and the cached descriptor disagree,
    --and a link filed against the wrong room would stand for the rest of the
    --floor where a missing one heals itself, so wait until they agree.
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
--
function _gt:new_room()
    warn_in_run = true --a room is on screen, so a warning would actually be read
    local last_crd = crd
    --
    _gt:get_grid_room()
    _gt:get_room_neighbours()
    room = Game():GetRoom()
    crd = level:GetCurrentRoomDesc()
    crid = crd.GridIndex
    crsid = crd.SafeGridIndex
    _gt:sweep_doors()
    mmp_ctrl = false
    --the cursor is rebuilt from scratch in the new room, so let the device
    --claim be rebuilt with it: under GMC the cursor only draws once the
    --keyboard is active, and entering a room is the natural point for
    --"reading the map" to stop implying "aiming at something"
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
    --(the old MinimapAPI position sync is gone: with MinimapAPI present the
    --hit-test now inverts MinimapAPI's own per-room render anchors instead)
    bookmarks = {-99, -99, -99, -99, -99, -99, -99, -99, -99}
    curse_bare_outside, curse_bare_inside = {}, {} --last floor's doors go with it
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
--
--

function _gt:fair_trip(roomIndex, target)
	--BFS shortest distance; only cleared rooms can be passed through,
	--but any room connected to the target counts as the last hop (+1)

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
				--a wall no bomb opened is not a step, so the walk this charges
				--time for is one the player could have taken. Same switch again:
				--with path rules off the old grid answer stands
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
if REPENTOGON then
  _gt:AddCallback(ModCallbacks.MC_POST_HUD_RENDER, _gt.gon_draw_map_cursor)
end
