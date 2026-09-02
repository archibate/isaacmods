--Mod Config Menu: the settings pages and their Chinese translation. Included
--only when ModConfigMenu exists. widget offers rescale(), get_top_left() and
--set_top_left(x, y); config offers update_analog_mappings()
return function(deps)
    local cfg, config, widget = deps.cfg, deps.config, deps.widget
    --the game defines no Controller enum; only Default below reads it
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
    if ModConfigMenu.GetCategoryIDByName("GoodTrip [Fixed]") ~= nil then
        print('GoodTrip [Fixed] is reloading ModConfigMenu options')
        ModConfigMenu.RemoveCategory("GoodTrip [Fixed]")
    end
    --a page scrolls past ten settings, so every tab stays well under that.
    --{tab, key, info, [show-if]}; tabs appear in the order first named here
    local options = {
        { "Map", "KeyboardMapEnable", "Classic GoodTrip minimap, teleport using TAB + arrow keys. Turn this back on if you dragged it into the trash by accident." },
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
              return cfg[info[2]]
            end,
            Display = function()
              return info[2] .. ": " .. (cfg[info[2]] and "on" or "off")
            end,
            OnChange = function(b)
              cfg[info[2]] = b
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
        Minimum = 5, --never 0: invisible window
        Maximum = 100,
        Default = 35,
        CurrentSetting = function()
          return cfg.DimMapAlpha or 35
        end,
        Display = function()
          return ("DimMapAlpha: %d%%"):format(cfg.DimMapAlpha or 35)
        end,
        OnChange = function(b)
          cfg.DimMapAlpha = b
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
          local x = widget.get_top_left()
          return x
        end,
        Display = function()
          local x = widget.get_top_left()
          return "TopLeftX: " .. tostring(math.floor(x))
        end,
        OnChange = function(b)
          local _, y = widget.get_top_left()
          widget.set_top_left(b, y)
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
          local _, y = widget.get_top_left()
          return y
        end,
        Display = function()
          local _, y = widget.get_top_left()
          return "TopLeftY: " .. tostring(math.floor(y))
        end,
        OnChange = function(b)
          local x = widget.get_top_left()
          widget.set_top_left(x, b)
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
          return cfg.MinimapScale
        end,
        Display = function()
          return ("MinimapScale: x%.1f"):format((cfg.MinimapScale or 10) / 10)
        end,
        OnChange = function(b)
          cfg.MinimapScale = b
          widget.rescale()
        end,
        Info = { "Keyboard minimap size, x0.5 (tiny) to x1.0 (original) up to x2.5" },
      }
    )
    --labelled by key name: without the menu the same key is typed into gtconfig.lua
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
            Minimum = -100, --game builds re-anchor the corner map whole cells apart
            Maximum = 100,
            Default = 0,
            CurrentSetting = function()
              return cfg[info[1]] or 0
            end,
            Display = function()
              return ("%s: %+dpx"):format(info[1], cfg[info[1]] or 0)
            end,
            OnChange = function(b)
              cfg[info[1]] = b
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
          return cfg["SwapAnalogSticks"]
        end,
        Display = function()
          return "SwapAnalogSticks" .. ": " .. (cfg["SwapAnalogSticks"] and "on" or "off")
        end,
        OnChange = function(b)
          cfg["SwapAnalogSticks"] = b
          config.update_analog_mappings()
        end,
        Info = { "Swap the left and right analog sticks" },
      }
    )
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]",  "Keybinds",
      {
        Type = ModConfigMenu.OptionType.KEYBIND_CONTROLLER,
        CurrentSetting = function()
          return cfg.ControllerAlternateZ
        end,
        Display = function()
          return "ControllerAlternateZ: " .. (
                    cfg.ControllerAlternateZ and
                    InputHelper.ControllerToString[cfg.ControllerAlternateZ]
                    or 'None'
                )
        end,
        OnChange = function(b)
          cfg.ControllerAlternateZ = b
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
          return cfg.ControllerAlternateR
        end,
        Display = function()
          return "ControllerAlternateR: " .. (
                    cfg.ControllerAlternateR and
                    InputHelper.ControllerToString[cfg.ControllerAlternateR]
                    or 'None'
                )
        end,
        OnChange = function(b)
          cfg.ControllerAlternateR = b
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
          return cfg.OverlayKey
        end,
        Default = Keyboard.KEY_TAB,
        Display = function()
          return "OverlayKey: " .. (
                    cfg.OverlayKey and
                    InputHelper.KeyboardToString[cfg.OverlayKey]
                    or 'None'
                )
        end,
        OnChange = function(b)
          cfg.OverlayKey = b
        end,
            PopupGfx = ModConfigMenu.PopupGfx.WIDE_SMALL,
            PopupWidth = 280,
            Popup = function()
                return "Press a button on your controller to change this setting."
            end,
        Info = { "Keyboard key to open the overlay" },
      }
    )
    ModConfigMenu.AddSetting(
      "GoodTrip [Fixed]", "Keybinds",
      {
        Type = ModConfigMenu.OptionType.KEYBIND_CONTROLLER,
        CurrentSetting = function()
          return cfg.OverlayKeyController
        end,
        Default = Controller.BUTTON_BACK,
        Display = function()
          return "OverlayKeyController: " .. (
                    cfg.OverlayKeyController and
                    InputHelper.ControllerToString[cfg.OverlayKeyController]
                    or 'None'
                )
        end,
        OnChange = function(b)
          cfg.OverlayKeyController = b
        end,
            PopupGfx = ModConfigMenu.PopupGfx.WIDE_SMALL,
            PopupWidth = 280,
            Popup = function()
                return "Press a button on your controller to change this setting."
            end,
        Info = { "Controller button to open the overlay" },
      }
    )
    --Mod配置菜单（中文版）is the only build that draws UTF-8, so only the drawn
    --text is translated; the keys settings save under never move
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
        --Display is built by a function, so these are replace pairs over the
        --finished line; anchored, else OverlayKey eats OverlayKeyController
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
        --Info is matched whole. ASCII punctuation only: the font lacks full-width marks
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
