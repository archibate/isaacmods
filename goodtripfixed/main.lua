local hasoldgoodtrip = (gt and not gt.isgtfixed)
local _gt = RegisterMod("GoodTrip [Fixed]", 1)
gt = _gt
_gt.isgtfixed = true
_gt.debug = false --teleport anywhere, no tolls, no transition; read at call time everywhere
--warnings stay until fixed, printed once and drawn only in-run (render runs on
--menus too). Either GoodTrip may load first, so both checks are needed.
local warned = false
function _gt.draw_warns(in_run)
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
    if not in_run then
        return
    end
    for i, warnmsg in ipairs(warnings) do
        Isaac.RenderScaledText(warnmsg, 40, 50 + (i - 1) * 12, 0.5, 0.5, 1, 1, 0, 1)
    end
end

--modules. Only main.lua includes, each file exactly once, here at load: include
--re-reads the file on every luamod (require would cache it) and never resolves
--into another mod's folder, so a luamod always runs the code on disk with fresh
--module state. Modules never include each other; what one needs is passed in,
--in dependency order. A module may keep a dependency's table or function, never
--a copy of its data (floor.crd and the like are reassigned every room).
--gtconfig.lua is the hand-edited pins table, read once here; a broken file is no pins
local pins_ok, pins = pcall(include, "gtconfig")
if not pins_ok or type(pins) ~= "table" then
    pins = nil
end
local config = include("scripts.config")({ gt = _gt, pins = pins })
local cfg = config.cfg
local floor = include("scripts.floor")({ cfg = cfg })
local rules = include("scripts.rules")({ gt = _gt, cfg = cfg, floor = floor })
local gamemap = include("scripts.gamemap")({ cfg = cfg, floor = floor })
local widget = include("scripts.widget")({ gt = _gt, cfg = cfg, config = config, floor = floor, rules = rules, gamemap = gamemap })
local trip = include("scripts.trip")({ gt = _gt, cfg = cfg, floor = floor, rules = rules, widget = widget })
local control = include("scripts.control")({ gt = _gt, config = config, floor = floor, rules = rules, gamemap = gamemap, widget = widget, trip = trip })
if ModConfigMenu then
    include("scripts.mcm")({ cfg = cfg, config = config, widget = widget })
end

--what the console and devrepro reach for: lua gt:get_config().AllowAnyRoom = true,
--gt.save_config() to make a hand-edited config stick, lua print(gt.dump(...)).
--The modules hang here too, for poking: lua print(gt.floor.crd.SafeGridIndex)
function _gt:get_config()
    return cfg
end
_gt.save_config = config.save
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
_gt.config, _gt.floor, _gt.rules, _gt.gamemap = config, floor, rules, gamemap
_gt.widget, _gt.trip, _gt.control = widget, trip, control

--EARLY priority: a mod returning a value from a callback silences every later mod
--in that round, and this one loads late (alphabetical). Not for MC_USE_ITEM/CARD/PILL,
--where a return means "handled". Same priority keeps registration order, so the
--settings are read before the first room is laid out
_gt:AddPriorityCallback(ModCallbacks.MC_POST_GAME_STARTED, CallbackPriority.EARLY, function(_, isContined)
    config.load_saved()
    widget.apply_config()
end)
_gt:AddPriorityCallback(ModCallbacks.MC_PRE_GAME_EXIT, CallbackPriority.EARLY, function(_, shouldSave)
    config.save()
end)
_gt:AddPriorityCallback(ModCallbacks.MC_POST_GAME_STARTED, CallbackPriority.EARLY, function()
  control.prep()
  control.new_room()
  control.new_level()
end)
_gt:AddCallback(ModCallbacks.MC_USE_ITEM, control.itemused)
_gt:AddCallback(ModCallbacks.MC_USE_CARD, control.itemused)
_gt:AddCallback(ModCallbacks.MC_USE_PILL, control.itemused)
--EARLY render: a later HUD may cover the window, but another mod's render
--returning a value can no longer hide it
_gt:AddPriorityCallback(ModCallbacks.MC_POST_RENDER, CallbackPriority.EARLY, control.step)
_gt:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.EARLY, control.step2)
_gt:AddPriorityCallback(ModCallbacks.MC_POST_NEW_ROOM, CallbackPriority.EARLY, control.new_room)
_gt:AddPriorityCallback(ModCallbacks.MC_POST_NEW_LEVEL, CallbackPriority.EARLY, control.new_level)
if REPENTOGON then
  --the game's map is drawn in MC_HUD_RENDER there, so the cursor on it goes after
  _gt:AddCallback(ModCallbacks.MC_POST_HUD_RENDER, widget.gon_draw_map_cursor)
end
