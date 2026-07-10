local json = require('json')
local mod = RegisterMod("Jacob Esau Auto Aligns", 1)

local defaultConfig = {
	AlignRadius = 15,
	ForceScale = 10,
	ShootAlignTime = 18,
	JacobAsFront = true,
	OuterRadius = 100,
	InnerRadius = 3,
	OnlyAlignOnShoot = true,
	NoShootAlignOnMove = false,
	DecoupleOnCtrl = true,
	SwapFrontKey = Keyboard.KEY_H,
	MoveEsauKey = Keyboard.KEY_LEFT_ALT,
	SwapFrontBtn = -1,
	MoveEsauBtn = -1,
}
-- begin config
if ModConfigMenu then
    function mod:getConfig()
        return ModConfigMenu.Config["Jacob Esau Auto Aligns"]
    end
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.NUMBER, "Jacob Esau Auto Aligns", nil, "AlignRadius",
		-1, 60, nil, 15, "Align Radius", nil, true,
		"Auto-aligns when the distance between Jacob & Esau below this size (unit: 10 px), -1 for INF, i.e. always align")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.NUMBER, "Jacob Esau Auto Aligns", nil, "ForceScale",
		0, 30, nil, 10, "Force Scale", nil, true,
		"The speed of align movement Jacob & Esau (unit: 0.1 px/s), the larger the faster they aligns")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.NUMBER, "Jacob Esau Auto Aligns", nil, "ShootAlignTime",
		-1, 150, nil, 18, "Shoot Align Time", nil, true,
		"Aligns along shoot direction when shoot for this long time (unit: 0.1 sec), -1 to never align along shoot")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.BOOLEAN, "Jacob Esau Auto Aligns", nil, "JacobAsFront",
		nil, nil, nil, true, "Jacob As Front", nil, true,
		"True to let Jacob in front of Esau along shooting direction, Esau in front of Jacob otherwise")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.NUMBER, "Jacob Esau Auto Aligns", nil, "OuterRadius",
		0, 500, nil, 100, "Outer Radius", nil, true,
		"At which radius Jacob & Esau have max attract force (unit: px), the smaller the stronger")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.NUMBER, "Jacob Esau Auto Aligns", nil, "InnerRadius",
		0, 40, nil, 3, "Inner Radius", nil, true,
		"Inside which radius Jacob & Esau have no attract force (unit: px), to prevent collision")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.BOOLEAN, "Jacob Esau Auto Aligns", nil, "OnlyAlignOnShoot",
		nil, nil, nil, true, "Only Align On Shoot", nil, true,
		"True to only align when shooting tears, otherwise Jacob & Esau will always align once they are close enough")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.BOOLEAN, "Jacob Esau Auto Aligns", nil, "NoShootAlignOnMove",
		nil, nil, nil, false, "No Shoot Align On Move", nil, true,
		"True to disable align along shoot direction when moving, to prevent hurt when it suddenly turns when you're moving")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.BOOLEAN, "Jacob Esau Auto Aligns", nil, "DecoupleOnCtrl",
		nil, nil, nil, true, "Decouple On Ctrl", nil, true,
		"True to allow temporary disable alignment when holding Ctrl (drop button), so that Jacob could move along")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.KEYBIND_KEYBOARD, "Jacob Esau Auto Aligns", nil,
		"SwapFrontKey", nil, nil, nil, Keyboard.KEY_H, "Swap Front Key", nil, true,
		"Key to toggle 'Jacob As Front', i.e. swap Jacob front to Esau front and vice versa, None to disable")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.KEYBIND_KEYBOARD, "Jacob Esau Auto Aligns", nil,
		"MoveEsauKey", nil, nil, nil, Keyboard.KEY_LEFT_ALT, "Move Esau Key", nil, true,
		"As we all know, holding Ctrl would allow Jacob move along, but sometimes we want Esau to move along, this key is for that")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.KEYBIND_CONTROLLER, "Jacob Esau Auto Aligns", nil,
		"SwapFrontBtn", nil, nil, nil, nil, "Swap Front Button", nil, true,
		"Key to toggle 'Jacob As Front', i.e. swap Jacob front to Esau front and vice versa, None to disable")
	ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.KEYBIND_CONTROLLER, "Jacob Esau Auto Aligns", nil,
		"MoveEsauBtn", nil, nil, nil, nil, "Move Esau Button", nil, true,
		"As we all know, holding Ctrl would allow Jacob move along, but sometimes we want Esau to move along, this key is for that")
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContined)
		mod:initializeState()
        if mod:HasData() then
            local dat = mod:LoadData()
            mod.oldDat = dat
            local cfg = json.decode(dat)
            for k, v in pairs(cfg) do
                mod:getConfig()[k] = v
            end
        end
    end)
    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
        local dat = json.encode(mod:getConfig())
        if not mod.oldDat or dat ~= mod.oldDat then
            mod.oldDat = dat
            mod:SaveData(dat)
        end
    end)
else
    function mod:getConfig()
        return defaultConfig
    end
end
-- end config

function mod:initializeState()
	mod.State = {
		shootTime = 0,
		lastShotTime = -1,
		lastShotDir = Vector(0, 0),
	}
end

mod:initializeState()

function mod:mayRotateByShoot(player)
    local cfg = mod:getConfig()
	if cfg.ShootAlignTime == -1 then
		return false
	end
	local shot = player:GetShootingInput()
	if shot:Length() < 0.1 then
		mod.State.shootTime = 0
		mod.State.lastShotDir = Vector(0, 0)
		return false
	end
	local moveDisabled = cfg.NoShootAlignOnMove and player:GetMovementInput():Length() > 0.1
	if mod.State.lastShotDir:DistanceSquared(shot) < 0.1 then
		local nowTime = Isaac.GetTime()
		local dt = 0
		if mod.State.lastShotTime ~= -1 then
			dt = nowTime - mod.State.lastShotTime
		end
		if moveDisabled then
			dt = 0
		end
		mod.State.lastShotTime = nowTime
		mod.State.shootTime = mod.State.shootTime + dt
	else
		mod.State.lastShotDir = Vector(0, 0)
		mod.State.shootTime = 0
		mod.State.lastShotTime = -1
	end
	mod.State.lastShotDir = shot
	if mod.State.shootTime >= cfg.ShootAlignTime * 100 then
		mod.State.shootTime = cfg.ShootAlignTime * 100
		if not moveDisabled then
			return true
		end
	end
	return false
end

function mod:performAlignment(player)
    local cfg = mod:getConfig()
    local playerType = player:GetPlayerType()
    if playerType == PlayerType.PLAYER_JACOB then
        if cfg.SwapFrontKey ~= -1 and Input.IsButtonTriggered(cfg.SwapFrontKey, player.ControllerIndex)
        or cfg.SwapFrontBtn ~= -1 and Input.IsButtonTriggered(cfg.SwapFrontBtn, player.ControllerIndex)
        then
            cfg.JacobAsFront = not cfg.JacobAsFront
        end
    end
    local shot = player:GetShootingInput()
	if cfg.OnlyAlignOnShoot and shot:Length() < 0.1 then
		return
	end
	if cfg.DecoupleOnCtrl then
		if Input.IsActionPressed(ButtonAction.ACTION_DROP, player.ControllerIndex) then
			return
		end
		if cfg.MoveEsauKey and Input.IsButtonPressed(cfg.MoveEsauKey, player.ControllerIndex) then
			return
		end
	end
	local twin = player:GetOtherTwin()
	local dir = twin.Position - player.Position
	if cfg.AlignRadius == -1 or dir:Length() < cfg.AlignRadius * 10 then
		local maxLen = cfg.OuterRadius
		local extraLen = cfg.InnerRadius
		local scale = cfg.ForceScale / 20
		local minLen = math.max(1, twin.Size + player.Size + extraLen)
		if mod:mayRotateByShoot(player) then
			shot = shot:Normalized()
			if not cfg.JacobAsFront then
				shot = -shot
			end
			if playerType == PlayerType.PLAYER_ESAU then
				shot = -shot
			end
			if dir:Dot(shot) > 0.618 * dir:Length() then
				if dir:Cross(shot) > 0 then
					shot = shot:Rotated(90)
				else
					shot = shot:Rotated(-90)
				end
			end
			dir = dir + shot * minLen
			minLen = 0
		end
		local len = dir:Length()
		local tmp = math.min(1, math.min(maxLen - minLen, math.max(len - minLen, 0)) / math.max(1, maxLen - minLen))
		dir = dir * (tmp / math.max(1, math.max(minLen, len)))
		local corr = math.max(player.Velocity:Dot(dir), 0)
		player.Velocity = dir * (1 - math.min(1, corr * corr * corr)) * scale + player.Velocity
	end
end

mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
    local playerType = player:GetPlayerType()
	if (playerType == PlayerType.PLAYER_JACOB or playerType == PlayerType.PLAYER_ESAU) and player:GetOtherTwin() then
		mod:performAlignment(player)
	end
end)

--holding MoveEsauKey freezes Jacob: block only his movement input so he keeps
--shooting, mirroring how vanilla Ctrl keeps Esau shooting while standing still
local moveActions = {
	[ButtonAction.ACTION_LEFT] = true,
	[ButtonAction.ACTION_RIGHT] = true,
	[ButtonAction.ACTION_UP] = true,
	[ButtonAction.ACTION_DOWN] = true,
}

mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, hook, action)
	if not moveActions[action] or not entity then return end
	local player = entity:ToPlayer()
	if not player or player:GetPlayerType() ~= PlayerType.PLAYER_JACOB or not player:GetOtherTwin() then return end
	local cfg = mod:getConfig()
	if cfg.MoveEsauKey ~= -1 and Input.IsButtonPressed(cfg.MoveEsauKey, player.ControllerIndex)
	or cfg.MoveEsauBtn ~= -1 and Input.IsButtonPressed(cfg.MoveEsauBtn, player.ControllerIndex)
	then
		if hook == InputHook.GET_ACTION_VALUE then
			return 0
		else
			return false
		end
	end
end)
