--settings: the defaults, the saved config over them, gtconfig.lua pins over
--both; the JSON save; the key tables that follow SwapAnalogSticks
return function(deps)
    local gt, pins = deps.gt, deps.pins
    local M = {}

    --defaults only; see gtconfig.lua for what each one does
    local cfg = {
        KeyboardMapEnable = true,
        FastRestartEnable = true,
        FollowCurseOfLost = true,
        TeleportAnimation = false,
        LandAtDoor = true,
        QuicklyOneRoomMove = false,
        AllowNeighborRoom = true,
        AllowAnyRoom = false,
        AllowBookmarking = true,
        LastRoomShortcut = true,
        FastTransition = false,
        NoShootWhenClick = true,
        FasterCursorMove = false,
        CursorOnGameMap = false,
        DimMapInCombat = true,
        DimMapAlpha = 35,
        DangerCautionCompat = true,
        FairTripTime = false,
        FairTripPath = true,
        ShowSpecialIcons = true,
        ControllerAlternateZ = nil,
        ControllerAlternateR = nil,
        MinimapScale = 10,
        OverlayKey = nil,
        OverlayKeyController = nil,
        SwapAnalogSticks = false,
        IgnoreMovementKeys = false,
        CalibMainX = 0,
        CalibMirrorX = 0,
        CalibMainY = 0,
        CalibMirrorY = 0,
    }
    M.cfg = cfg --the live table; never reassigned, so a caller may keep it

    --gtconfig.lua is applied after the saved config and its keys are left out of
    --the save, so a hand-edited setting wins on every launch. pins is that file's
    --table, read once per load by main.lua; nil when the file is broken or missing
    local overrides = {}
    function M.apply_pins()
        overrides = {}
        if not pins then
            return
        end
        for k, v in pairs(pins) do
            overrides[k] = true
            cfg[k] = v
        end
    end
    M.apply_pins()

    --saved here, not in the MCM block: dragging, zoom and the trash work without MCM
    local cfgdata_written = nil
    local cfgdata_loaded = false
    function M.save()
        --never write before the first read: a luamod reload resets the locals, and
        --the next exit save would bury the real config under them
        if not cfgdata_loaded then return end
        local json = require('json')
        local payload = cfg
        if next(overrides) then --pinned keys belong to gtconfig.lua
            payload = {}
            for k, v in pairs(cfg) do
                if not overrides[k] then
                    payload[k] = v
                end
            end
        end
        local dat = json.encode(payload)
        if not cfgdata_written or dat ~= cfgdata_written then
            cfgdata_written = dat
            gt:SaveData(dat)
        end
    end

    --the game-start read. A bad save must not throw: defaults stand in
    function M.load_saved()
        local saved
        if gt:HasData() then
            local dat = gt:LoadData()
            cfgdata_written = dat
            local json = require('json')
            local ok, read = pcall(json.decode, dat)
            if ok and type(read) == "table" then
              saved = read
            else
              print("GoodTrip [Fixed]: the saved settings could not be read, starting from defaults")
            end
        end
        if saved then
            for k, v in pairs(saved) do
                cfg[k] = v
            end
            --one-shot migration: FairTripTime was inert unless the retired
            --MinimapAPICompat switch was on, yet old saves store it true
            if not saved.FairTripMigrated then
                cfg.FairTripMigrated = true
                if not saved.MinimapAPICompat then
                    cfg.FairTripTime = false
                end
            end
        end
        M.apply_pins() --last word goes to the hand-edited file
        M.update_analog_mappings()
        cfgdata_loaded = true --a first-time player has nothing on disk, yet still gets saved
    end

    --key aims the map cursor, movkey walks; SwapAnalogSticks trades them.
    --Reassigned whole, so read them at call time, never keep a copy
    M.key = {ButtonAction.ACTION_SHOOTUP,ButtonAction.ACTION_SHOOTLEFT,ButtonAction.ACTION_SHOOTRIGHT,ButtonAction.ACTION_SHOOTDOWN}
    M.movkey = {ButtonAction.ACTION_UP,ButtonAction.ACTION_LEFT,ButtonAction.ACTION_RIGHT,ButtonAction.ACTION_DOWN}
    M.dir = {Vector(0, -1),Vector(-1, 0),Vector(1, 0),Vector(0, 1)}
    function M.update_analog_mappings()
        if cfg.SwapAnalogSticks then
            M.key = {ButtonAction.ACTION_UP, ButtonAction.ACTION_LEFT, ButtonAction.ACTION_RIGHT, ButtonAction.ACTION_DOWN}
            M.movkey = {ButtonAction.ACTION_SHOOTUP, ButtonAction.ACTION_SHOOTLEFT, ButtonAction.ACTION_SHOOTRIGHT, ButtonAction.ACTION_SHOOTDOWN}
        else
            M.key = {ButtonAction.ACTION_SHOOTUP, ButtonAction.ACTION_SHOOTLEFT, ButtonAction.ACTION_SHOOTRIGHT, ButtonAction.ACTION_SHOOTDOWN}
            M.movkey = {ButtonAction.ACTION_UP, ButtonAction.ACTION_LEFT, ButtonAction.ACTION_RIGHT, ButtonAction.ACTION_DOWN}
        end
    end
    M.update_analog_mappings() --also needed without MCM

    return M
end
