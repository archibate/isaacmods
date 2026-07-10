local mod = RegisterMod("RangeVis", 1)

local kTractor = true
local kInfinityLength = 800

local defaultConfig = {
    EnableMod = true,
    OnlyHeadDir = false,
    HasTearFlags = true,
    TearSpectral = false,
    NormalTear = false,
    IpecacTear = true,
    HaemolacriaTear = true,
    ChocolateCharge = true,
    TechLaser = false,
    TechX = true,
    DrFetus = true,
    Azazel = true,
    TaintedAzazel = true,
    Brimstone = true,
    MeleeBone = true,
    RangedBone = true,
    TaintedForgotten = true,
    MomsKnife = true,
    TaintedLilith = true,
    StopOnPause = true,
}
local configDescs = {
    { "EnableMod", "Toggle this mod globally on and off" },
    { "OnlyHeadDir", "Only show head direction aiming line when not shooting" },
    { "HasTearFlags", "Take tear flags (homing, wiggle worm, etc.) into account" },
    { "TearSpectral", "Aiming line can pass through obstacles (spectral tear)" },
    { "NormalTear", "Show range of normal tear" },
    { "IpecacTear", "Show range of Ipecac tear" },
    { "HaemolacriaTear", "Show range of Haemolacria tear" },
    { "ChocolateCharge", "Show range and charge of Chocolate tear" },
    { "TechLaser", "Show aim direction of Technology series laser" },
    { "TechX", "Show aim direction of Tech X laser ring" },
    { "DrFetus", "Show range of Dr. Fetus bombs" },
    { "Azazel", "Show range of Azazel's short brimstone" },
    { "TaintedAzazel", "Show range of Tainted Azazel's hemoptysis" },
    { "Brimstone", "Show aiming line for true Brimstone" },
    { "MeleeBone", "Show range of Forgotten's melee bone attack" },
    { "RangedBone", "Show range of Forgotten's ranged bone attack" },
    { "TaintedForgotten", "Show throw range of Tainted Forgotten's body when held" },
    { "MomsKnife", "Show dynamic range of Mom's Knife when charging" },
    { "TaintedLilith", "Show shoot range of Tainted Lilith's Gello" },
    { "StopOnPause", "Do not render indicators when game paused" },
}

-- begin config
function mod:getConfig()
    if ModConfigMenu then
        return ModConfigMenu.Config["RangeVis"]
    else
        return defaultConfig
    end
end

if ModConfigMenu then
    for _, info in ipairs(configDescs) do
        ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.BOOLEAN, "RangeVis", nil,
            info[1], nil, nil, nil, defaultConfig[info[1]], info[1], nil, true, info[2])
    end
    ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.NUMBER, "RangeVis", nil,
        "InfinityLength", 10, 1500, nil, defaultConfig.InfAimLength, "InfAimLength", nil, true,
        "Aiming line length when range is infinity (e.g. Brimstone, Technology)")
    local json = require('json')
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContined)
        if mod:HasData() then
            local cfg = json.decode(mod:LoadData())
            for k, v in pairs(cfg) do
                mod:getConfig()[k] = v
            end
        end
    end)
    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
        if shouldSave then
            mod:SaveData(json.encode(mod:getConfig()))
        end
    end)
end
-- end config

local AimMode = {
    AIM_TEAR = 0, -- Normal tears
    AIM_LASER = 1, -- Technology series
    AIM_BOMB = 2, -- Dr. Fetus
    AIM_NOAIM = 3, -- Ludovico's Technique, Marked
    AIM_THROW = 4, -- Tainted Forgotten's soul throw his body
    AIM_HEMOPTYSIS = 5, -- Tainted Azazel's hemoptysis
    MAX_CHARGELESS_AIM_MODES = 5,
    AIM_AZAZEL = 6, -- Azazel's short-ranged brimstone
    AIM_BRIMSTONE = 7, -- True infinite-ranged brimstone
    AIM_KNIFE = 8, -- Mom's Knife
    AIM_FARBONE = 9, -- Forgotten's ranged bone attack
    AIM_TECHX = 10, -- Technology X
    NUM_AIM_MODES = 11,
}

local ShootMode = {
    SHOOT_AUTO = 0, -- Auto shoots
    SHOOT_CHARGE = 1, -- Charged shoots
    SHOOT_CHOCOLATE = 2, -- Chocolate Milk
    SHOOT_BONE = 4, -- Forgotten's bone
    SHOOT_360 = 8, -- Analog Stick
}

local LineMode = {
    LINE_ONLY = 0,
    LINE_CROSS = 1,
    LINE_TARGET = 2,
    LINE_BONE = 3,
    LINE_KNIFE = 4,
    LINE_BRIMSTONE = 5,
    LINE_HEMOPT = 6,
    LINE_LASER = 7,
    LINE_BOMB = 8,
    LINE_GELLO = 9,
    NUM_LINE_MODES = 10,
}

local lineColorTear = Color(0.50, 0.55, 0.6)
local lineColorBone = Color(0.55, 0.65, 0.7)
local lineColorKnife = Color(0.7, 0.4, 0.6)
local lineColorBrim = Color(0.95, 0.35, 0.2)
local lineColorLaser = Color(0.9, 0.15, 0.15)
local lineColorChoco = Color(0.75, 0.45, 0.45)
local lineColorGello = Color(0.85, 0.45, 0.3)
local lineColorBomb = Color(0.15, 0.15, 0.2)
local lineColorRed = Color(0.85, 0.25, 0.25)
local lineColorGreen = Color(0.3, 0.65, 0.3)
local lineColorBlue = Color(0.4, 0.55, 0.85)

mod.draws = {}

function mod:clearDraws(player)
    local pData = player:GetData()
    pData.rvDraws = {}
end

function mod:drawLine(player, from, to, mode, color, percent, spectral)
    color = Color(1, 1, 1, 1)
    local draw = {
        from = from,
        to = to,
        mode = mode,
        color = color,
        percent = percent,
        spectral = spectral,
    }
    local pData = player:GetData()
    table.insert(pData.rvDraws, draw)
end

mod.shootTime = 0
mod.lastShootTime = -1


function mod:clearShootTime(player)
    mod.shootTime = 0
    mod.lastShootTime = -1
end

function mod:calcShootTime(player)
    if Game():IsPaused() then
        return
    end
    -- if player.FrameCount == lastShootTime then
    --     return
    -- end
    if player:HasWeaponType(WeaponType.WEAPON_BONE) and player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
        if player.HeadFrameDelay > 28 then
            mod:clearShootTime(player)
            return
        end
    end
    local knife = player:GetActiveWeaponEntity()
    if knife then
        knife = knife:ToKnife()
    end
    if knife and knife:IsFlying() then
        mod:clearShootTime(player)
        return
    end
    if player:GetAimDirection():Length() <= 0.1 then
        mod:clearShootTime(player)
        return
    end
    if mod.lastShootTime ~= -1 then
        mod.shootTime = mod.shootTime + math.max(0, player.FrameCount - mod.lastShootTime)
    else
        mod.shootTime = mod.shootTime + 1
    end
    mod.lastShootTime = player.FrameCount
end

local function getScreenBottomRight()
    return Game():GetRoom():GetRenderSurfaceTopLeft() * 2 + Vector(442, 286)
end

local function directionToVector(dir)
    local lut = {
        [Direction.NO_DIRECTION] = Vector(0, 0),
        [Direction.LEFT] = Vector(-1, 0),
        [Direction.UP] = Vector(0, -1),
        [Direction.RIGHT] = Vector(1, 0),
        [Direction.DOWN] = Vector(0, 1),
    }
    return lut[dir]
end

function mod:renderAimline(player, shotVel, aimMode, shootMode)
    if aimMode == AimMode.AIM_NOAIM then
        return
    end
    local percent = 1 - math.max(player.FireDelay, 0) / player.MaxFireDelay
    local extraVel = player:GetTearMovementInheritance(shotVel * 10) / 10
    local origPos = player.Position

    if player:GetPlayerType() == PlayerType.PLAYER_LILITH then
        local incubuses = Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.INCUBUS, -1, true, false)
        if #incubuses ~= 0 then
            local incubus = incubuses[1]:ToFamiliar()
            percent = 1 - math.max(incubus.HeadFrameDelay, 0) / player.MaxFireDelay
            origPos = incubus.Position
            local origVel = incubus.Velocity / 16.6
            local shotDir = shotVel:Normalized()
            local shotTan = shotDir:Rotated(90)
            extraVel = shotTan * shotDir:Cross(origVel) + shotDir * math.max(0, shotDir:Dot(origVel))
        end
    elseif player:GetPlayerType() == PlayerType.PLAYER_LILITH_B then
        -- local gellos = Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FamiliarVariant.UMBILICAL_BABY, -1, false, false)
        -- if #gellos == 0 then
        local percent = 1 - math.max(player.FireDelay, 0) / (player.MaxFireDelay * 2)
        -- if aimDir:Length() <= 0.1 or percent == 1 then
        shotVel = shotVel + extraVel * 0.75
        shotVel = shotVel:Normalized() * 215
        if mod:getConfig().TaintedLilith then
            mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_GELLO, lineColorGello, percent, true)
        end
        -- end
        return
    end

    if player:HasCollectible(CollectibleType.COLLECTIBLE_TRACTOR_BEAM) then
        extraVel = shotVel / shotVel:LengthSquared() * extraVel:Dot(shotVel)
    end

    if aimMode == AimMode.AIM_HEMOPTYSIS then
        local ext = (player.ShotSpeed - 1) * 40
        if mod:getConfig().TaintedAzazel then
            mod:drawLine(player, origPos + shotVel * (-4 + ext), origPos + shotVel * (64 - 15 + ext), LineMode.LINE_HEMOPT, lineColorBrim, percent, true)
        end
    elseif aimMode == AimMode.AIM_THROW then
        shotVel = shotVel + extraVel
        shotVel = shotVel * 331
        percent = 1
        if mod:getConfig().TaintedForgotten then
            mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_TARGET, lineColorBone, percent, true)
        end
    elseif (shootMode & ShootMode.SHOOT_BONE) ~= 0 then
        if aimMode == AimMode.AIM_KNIFE then
            percent = math.min(1, mod.shootTime / 73.5)
            if percent > 0 then
                shotVel = shotVel * percent
                local svl = shotVel:Length()
                local svn = shotVel:Normalized()
                percent = 1
                shotVel = svn * (svl * 260 - 10)
                if mod:getConfig().RangedBone then
                    mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BONE, lineColorBone, percent, true)
                end
            end
        elseif aimMode == AimMode.AIM_BRIMSTONE then
            percent = math.min(mod.shootTime / (player.MaxFireDelay * 2), 1)
            shotVel = shotVel * 125
            if mod:getConfig().RangedBone or mod:getConfig().Brimstone then
                mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BRIMSTONE, lineColorBrim, percent, true)
            end
        elseif aimMode == AimMode.AIM_BOMB then
            shotVel = shotVel + extraVel * 0.36
            shotVel = shotVel:Normalized() * kInfinityLength
            percent = 1
            if mod:getConfig().RangedBone or mod:getConfig().DrFetus then
                mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BOMB, lineColorBomb, percent, false)
            end
        else
            shotVel = shotVel * player.TearRange * 0.15
            local svl = shotVel:Length()
            local svn = shotVel:Normalized()
            local size = math.max(player.SpriteScale.X - 1, 0)
            local shotMin = svn * (svl - 42)
            shotVel = svn * (svl + 20 + size * 64)
            if mod:getConfig().MeleeBone then
                mod:drawLine(player, origPos + shotMin, origPos + shotVel, LineMode.LINE_BONE, lineColorBone, percent, true)
            end
        end
    elseif (shootMode & (ShootMode.SHOOT_CHARGE | ShootMode.SHOOT_CHOCOLATE)) == 0 then
        if aimMode == AimMode.AIM_BOMB then
            shotVel = shotVel + extraVel * 0.8
            shotVel = shotVel * player.TearRange * 0.75
            if mod:getConfig().DrFetus then
                mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BOMB, lineColorBomb, percent, false)
            end
        elseif aimMode == AimMode.AIM_LASER then
            shotVel = shotVel + extraVel * 0.5
            shotVel = shotVel:Normalized() * kInfinityLength
            if mod:getConfig().TechLaser then
                mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_LASER, lineColorLaser, percent, false)
            end
        else
            local color = lineColorTear
            local lineMode = LineMode.LINE_CROSS
            local enable = mod:getConfig().NormalTear
            local spectral = false
            if aimMode == AimMode.AIM_AZAZEL then
                color = lineColorBrim
                lineMode = LineMode.LINE_BRIMSTONE
                shotVel = shotVel * (player.TearRange * 0.252 + 42)
                enable = mod:getConfig().Azazel
                spectral = true
            elseif aimMode == AimMode.AIM_BRIMSTONE then
                color = lineColorBrim
                lineMode = LineMode.LINE_BRIMSTONE
                shotVel = shotVel:Normalized() * kInfinityLength
                enable = mod:getConfig().Brimstone
                spectral = true
            elseif aimMode == AimMode.AIM_TECHX then
                color = lineColorLaser
                lineMode = LineMode.LINE_LASER
                enable = mod:getConfig().TechX
                shotVel = shotVel + extraVel
                shotVel = shotVel:Normalized() * kInfinityLength
                shotVel = shotVel + extraVel * 0.8
                shotVel = shotVel * player.TearRange * 0.75
            else
                shotVel = shotVel + extraVel
                shotVel = shotVel * player.TearRange
            end
            if player:HasCollectible(CollectibleType.COLLECTIBLE_IPECAC) then
                color = lineColorGreen
                lineMode = LineMode.LINE_TARGET
                enable = enable or mod:getConfig().IpecacTear
            elseif player:HasCollectible(CollectibleType.COLLECTIBLE_HAEMOLACRIA) then
                color = lineColorRed
                lineMode = LineMode.LINE_TARGET
                enable = enable or mod:getConfig().HaemolacriaTear
            elseif player:HasCollectible(CollectibleType.COLLECTIBLE_NEPTUNUS) then
                color = lineColorBlue
            elseif player:GetPlayerType() == PlayerType.PLAYER_ESAU then
                color = lineColorRed
            end
            if enable then
                mod:drawLine(player, origPos, origPos + shotVel, lineMode, color, percent, spectral)
            end
        end
    else
        if aimMode == AimMode.AIM_AZAZEL or aimMode == AimMode.AIM_BRIMSTONE then
            local enable = mod:getConfig().Brimstone
            if aimMode == AimMode.AIM_AZAZEL then
                shotVel = shotVel * (player.TearRange * 0.252 + 42)
                enable = mod:getConfig().Azazel
            else
                shotVel = shotVel:Normalized() * kInfinityLength
            end
            if (shootMode & ShootMode.SHOOT_CHOCOLATE) ~= 0 then
                percent = math.min(mod.shootTime / (player.MaxFireDelay * 2.5), 1)
                if enable then
                    mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BRIMSTONE, lineColorChoco, percent, true)
                end
            else
                percent = math.min(mod.shootTime, player.MaxFireDelay) / player.MaxFireDelay
                if enable then
                    mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BRIMSTONE, lineColorBrim, percent, true)
                end
            end
        elseif aimMode == AimMode.AIM_TECHX then
            shotVel = shotVel + extraVel
            shotVel = shotVel:Normalized() * kInfinityLength
            percent = math.min(mod.shootTime / (player.MaxFireDelay * 3), 1)
            if mod:getConfig().TechX then
                mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_LASER, lineColorLaser, percent, false)
            end
        elseif aimMode == AimMode.AIM_KNIFE then
            percent = math.min(1, mod.shootTime / (player.MaxFireDelay * 4))
            if percent > 0 then
                shotVel = shotVel * percent
                local svl = shotVel:Length()
                local svn = shotVel:Normalized()
                percent = 1
                shotVel = svn * (svl * math.min(500, player.TearRange) * 0.62 + 6)
                if mod:getConfig().MomsKnife then
                    mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_KNIFE, lineColorKnife, percent, true)
                end
            end
        elseif aimMode == AimMode.AIM_LASER then
            shotVel = shotVel + extraVel * 0.5
            shotVel = shotVel:Normalized() * kInfinityLength
            percent = math.min(mod.shootTime / (player.MaxFireDelay * 3), 1)
            if mod:getConfig().TechLaser or (percent > 0 and mod:getConfig().ChocolateCharge) then
                mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_LASER, lineColorLaser, percent, false)
            end
        else
            shotVel = shotVel + extraVel
            shotVel = shotVel * player.TearRange
            percent = math.min(mod.shootTime / (player.MaxFireDelay * 2.8), 1)
            local color = lineColorChoco
            local lineMode = LineMode.LINE_CROSS
            local enable = mod:getConfig().NormalTear
            if player:HasCollectible(CollectibleType.COLLECTIBLE_IPECAC) then
                color = lineColorGreen
                lineMode = LineMode.LINE_TARGET
                enable = enable or mod:getConfig().IpecacTear
            elseif player:HasCollectible(CollectibleType.COLLECTIBLE_HAEMOLACRIA) then
                color = lineColorRed
                lineMode = LineMode.LINE_TARGET
                enable = enable or mod:getConfig().HaemolacriaTear
            end
            if enable or (percent > 0 and mod:getConfig().ChocolateCharge) then
                mod:drawLine(player, origPos, origPos + shotVel, lineMode, color, percent, false)
            end
        end
    end
end

function mod:renderOverlay(player)
    mod:clearDraws(player)
    if not mod:getConfig().EnableMod or (mod:getConfig().StopOnPause and Game():IsPaused()) then
        return
    end

    local aimMode = AimMode.AIM_TEAR
    local shootMode = ShootMode.SHOOT_AUTO
    if player:HasCollectible(CollectibleType.COLLECTIBLE_MARKED)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_C_SECTION)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_EPIC_FETUS)
        or player:HasCollectible(CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT)
    -- or player:HasCollectible(CollectibleType.COLLECTIBLE_TRACTOR_BEAM)
    then
        aimMode = AimMode.AIM_NOAIM
    else
        if player:HasCollectible(CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE) then
            aimMode = AimMode.AIM_NOAIM
        else
            if player:HasCollectible(CollectibleType.COLLECTIBLE_CHOCOLATE_MILK) then
                shootMode = shootMode | ShootMode.SHOOT_CHOCOLATE
            end
            if player:HasWeaponType(WeaponType.WEAPON_TEARS) then
                aimMode = AimMode.AIM_TEAR
            end
            if player:HasWeaponType(WeaponType.WEAPON_LASER) then
                aimMode = AimMode.AIM_LASER
            end
            if player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE) then
                aimMode = AimMode.AIM_BRIMSTONE
                shootMode = shootMode | ShootMode.SHOOT_CHARGE
                if player:GetPlayerType() == PlayerType.PLAYER_AZAZEL and
                    not player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
                    aimMode = AimMode.AIM_AZAZEL
                end
            end
            if player:HasWeaponType(WeaponType.WEAPON_TECH_X) then
                aimMode = AimMode.AIM_TECHX
                shootMode = shootMode | ShootMode.SHOOT_CHARGE
            end
            if player:HasWeaponType(WeaponType.WEAPON_KNIFE) then
                aimMode = AimMode.AIM_KNIFE
                shootMode = (shootMode & ~ShootMode.SHOOT_CHOCOLATE) | ShootMode.SHOOT_CHARGE | ShootMode.SHOOT_360
            elseif player:HasCollectible(CollectibleType.COLLECTIBLE_SOY_MILK) or
                player:HasCollectible(CollectibleType.COLLECTIBLE_ALMOND_MILK) then
                shootMode = (shootMode & ~ShootMode.SHOOT_CHOCOLATE & ~ShootMode.SHOOT_CHARGE) | ShootMode.SHOOT_360
            end
        end
        if player:HasWeaponType(WeaponType.WEAPON_BOMBS) then
            aimMode = AimMode.AIM_BOMB
            shootMode = shootMode & ~ShootMode.SHOOT_CHOCOLATE & ~ShootMode.SHOOT_CHARGE
        end
    end
    if player:HasWeaponType(WeaponType.WEAPON_BONE) then
        shootMode = shootMode | ShootMode.SHOOT_BONE
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_ANALOG_STICK) then
        shootMode = shootMode | ShootMode.SHOOT_360
    end

    local aimDir = player:GetAimDirection()
    if (shootMode & ShootMode.SHOOT_360) == 0 then
        local fireDir = player:GetFireDirection()
        aimDir = directionToVector(fireDir)
    end

    if (shootMode & ShootMode.SHOOT_BONE) ~= 0 and aimDir:Length() > 0.1 then
        if player:HasCollectible(CollectibleType.COLLECTIBLE_BRIMSTONE) then
            if mod:getConfig().RangedBone or mod:getConfig().Brimstone then
                aimMode = AimMode.AIM_BRIMSTONE
                shootMode = shootMode | ShootMode.SHOOT_CHARGE
            end
        elseif player:HasCollectible(CollectibleType.COLLECTIBLE_DR_FETUS) then
            if mod:getConfig().RangedBone or mod:getConfig().DrFetus then
                aimMode = AimMode.AIM_BOMB
                shootMode = shootMode | ShootMode.SHOOT_CHARGE
            end
        elseif player.HeadFrameDelay <= 4 then
            if mod:getConfig().RangedBone then
                aimMode = AimMode.AIM_KNIFE
                shootMode = shootMode & ~ShootMode.SHOOT_CHOCOLATE | ShootMode.SHOOT_CHARGE
            end
        end
    end
    local twin = player:GetOtherTwin()
    if twin then
        if player:GetPlayerType() == PlayerType.PLAYER_THEFORGOTTEN_B then
            if twin:IsHoldingItem() then
                return
            end
        elseif twin:GetPlayerType() == PlayerType.PLAYER_THEFORGOTTEN_B then
            if player:IsHoldingItem() then
                aimMode = AimMode.AIM_THROW
                shootMode = ShootMode.SHOOT_AUTO
            else
                return
            end
        end
    end
    if aimMode == AimMode.AIM_BRIMSTONE and player:GetPlayerType() == PlayerType.PLAYER_AZAZEL_B then
        if aimDir:Length() <= 0.1 then -- or not getConfig().Brimstone then
            aimMode = AimMode.AIM_HEMOPTYSIS
        end
    end

    -- print(aimMode, shootMode, mod.shootTime)

    if aimMode ~= AimMode.AIM_NOAIM then
        if aimDir:Length() > 0.1 then
            mod:renderAimline(player, aimDir:Normalized(), aimMode, shootMode)
        elseif aimMode <= AimMode.MAX_CHARGELESS_AIM_MODES then
            if mod:getConfig().OnlyHeadDir then
                local headDir = player:GetHeadDirection()
                aimDir = directionToVector(headDir)
                mod:renderAimline(player, aimDir:Normalized(), aimMode, shootMode)
            else
                local shotTpls = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
                for _, shotTpl in ipairs(shotTpls) do
                    shotTpl = Vector(shotTpl[1], shotTpl[2]):Normalized()
                    mod:renderAimline(player, shotTpl, aimMode, shootMode)
                end
            end
        end
    end

    -- if getConfig().DebugInfo then
    --     local tp = getScreenBottomRight() - Vector(100, 60)
    --     local info = string.format("aim: %.2f %.2f", aimDir.X, aimDir.Y)
    --     Isaac.RenderText(info, tp.X - 80, tp.Y - 30, 0.25, 0.25, 0.5, 0.5)
    --     local info = string.format("tear: %.2f %.2f %d", player.FireDelay, player.MaxFireDelay, player.HeadFrameDelay)
    --     Isaac.RenderText(info, tp.X - 80, tp.Y - 40, 0.25, 0.25, 0.5, 0.5)
    --     local info = string.format("modes: %d %d", aimMode, shootMode)
    --     Isaac.RenderText(info, tp.X - 80, tp.Y - 30, 0.25, 0.25, 0.5, 0.5)
    --     local info = string.format("charge: %d", shootTime)
    --     Isaac.RenderText(info, tp.X - 80, tp.Y - 20, 0.25, 0.25, 0.5, 0.5)
    -- end
end

-- mod:AddCallback(ModCallbacks.MC_POST_RENDER, function(_)
--     if not getConfig().EnableMod or (getConfig().StopOnPause and Game():IsPaused()) then
--         return
--     end
--     local player = Isaac.GetPlayer(0)
--     calcShootTime(player)
--     renderOverlay(player)
-- end)

local kAcceptableTearFlags =
TearFlags.TEAR_SPECTRAL
    | TearFlags.TEAR_PIERCING
    | TearFlags.TEAR_HOMING
    -- Items
    | TearFlags.TEAR_BOOMERANG
    | TearFlags.TEAR_BOUNCE
    | TearFlags.TEAR_OCCULT
    | TearFlags.TEAR_ORBIT
    | TearFlags.TEAR_ORBIT_ADVANCED
    | TearFlags.TEAR_CONTINUUM
    -- Worms
    | TearFlags.TEAR_WIGGLE
    | TearFlags.TEAR_SPIRAL
    | TearFlags.TEAR_SQUARE
    | TearFlags.TEAR_BIG_SPIRAL
    | TearFlags.TEAR_TURN_HORIZONTAL

function mod:fixLaserTip(eff)
    if eff.SpawnerEntity and eff.SpawnerEntity:GetData().isRvBeam then
        if not kTractor then
            if eff:GetSprite():GetFilename() ~= "gfx/aimer_target.anm2" then
                eff:GetSprite():Load("gfx/aimer_target.anm2", true)
                eff:GetSprite():LoadGraphics()
            end
            local anim = "Target"
            local mode = eff.SpawnerEntity:GetData().rvBeamMode
            if mode == LineMode.LINE_TARGET then
                anim = "Target"
            elseif mode == LineMode.LINE_CROSS then
                anim = "Cross"
            elseif mode == LineMode.LINE_BONE then
                anim = "Bone"
            elseif mode == LineMode.LINE_BRIMSTONE then
                anim = "Brimstone"
            elseif mode == LineMode.LINE_HEMOPT then
                anim = "Hemopt"
            elseif mode == LineMode.LINE_KNIFE then
                anim = "Knife"
            elseif mode == LineMode.LINE_GELLO then
                anim = "Gello"
            elseif mode == LineMode.LINE_BOMB then
                anim = "Bomb"
            elseif mode == LineMode.LINE_LASER then
                anim = "Laser"
            elseif mode == LineMode.LINE_ONLY then
                anim = "None"
            end
            eff:GetSprite():Play(anim, true)
            -- print(Isaac.GetTime(), anim)
        else
            if eff:GetSprite():GetFilename() ~= "gfx/rangevis_beam_tip.anm2" then
                eff:GetSprite():Load("gfx/rangevis_beam_tip.anm2", true)
                eff:GetSprite():LoadGraphics()
                eff:GetSprite():Play("End", true)
            end
        end

        eff:GetSprite():SetFrame(eff.SpawnerEntity:GetSprite():GetFrame())
        eff.Color = eff.SpawnerEntity.Color
        eff.SpriteScale = eff.SpawnerEntity.SpriteScale
    end
end

mod:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, mod.fixLaserTip, EffectVariant.LASER_IMPACT)
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, mod.fixLaserTip, EffectVariant.LASER_IMPACT)

function mod:fixLaserBounce(laser)
    -- if laser.SpawnerEntity and laser.SpawnerEntity:GetData().isRvBeam then
    --     if laser:GetSprite():GetFilename() ~= "gfx/rangevis_beam.anm2" then
    --         laser:GetSprite():Load("gfx/rangevis_beam.anm2", true)
    --         laser:GetSprite():LoadGraphics()
    --         laser:GetSprite():Play("Laser0", true)
    --     end
    --     laser:GetData().isRvBeam = true
    --     laser.Color = laser.SpawnerEntity.Color
    if laser.Parent and laser.Parent:GetData().isRvBeam then
        if laser:GetSprite():GetFilename() ~= "gfx/rangevis_beam.anm2" then
            laser:GetSprite():Load("gfx/rangevis_beam.anm2", true)
            laser:GetSprite():LoadGraphics()
            laser:GetSprite():Play("Laser0", true)
        end
        laser:GetData().isRvBeam = true
        laser.Color = laser.Parent.Color
    end
end

mod:AddCallback(ModCallbacks.MC_POST_LASER_INIT, mod.fixLaserBounce)
mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.fixLaserBounce)


mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
    if GetPtrHash(player) == GetPtrHash(player:GetMainTwin()) then
        mod:calcShootTime(player)
    end
    mod:renderOverlay(player)

    local pData = player:GetData()
    if not pData.rvDraws then return end
    if not pData.rvBeams then
        pData.rvBeams = {}
    end

    if not (function ()
        for _, beam in ipairs(pData.rvBeams) do
            if not beam:Exists() then
                return false
            end
        end
        return #pData.rvDraws <= #pData.rvBeams
    end)() then
        for _, beam in ipairs(pData.rvBeams) do
            beam:Remove()
        end
        pData.rvBeams = {}

        for _, draw in ipairs(pData.rvDraws) do
            local dir = (draw.to - draw.from):Normalized()

            local beam = player:FireTechLaser(Vector.Zero, 0, dir, false, false, player, 0)
            beam.Mass = 0
            beam.CollisionDamage = 0
            beam.SpawnerEntity = nil
            beam.Timeout = -1
            if mod:getConfig().HasTearFlags then
                beam.TearFlags = player:GetTearHitParams(WeaponType.WEAPON_LASER).TearFlags & kAcceptableTearFlags
            else
                beam.TearFlags = TearFlags.TEAR_NORMAL
            end
            if draw.spectral or (mod:getConfig().TearSpectral and not beam:HasTearFlags(TearFlags.TEAR_BOUNCE)) then
                beam:AddTearFlags(TearFlags.TEAR_SPECTRAL)
            end
            beam.Parent = Isaac.Spawn(EntityType.ENTITY_SHOPKEEPER, 0, 0, Vector.Zero, Vector.Zero, nil)
            beam.Parent:Remove()
            beam.Color = draw.color
            -- beam.RenderZOffset = 0
            beam.SpriteScale = Vector.One
            beam.SpriteOffset = Vector.Zero
            beam.PositionOffset = Vector(0, player.TearHeight)
            -- beam.Position = draw.from
            beam.Visible = false
            beam:SetMaxDistance(draw.to:Distance(draw.from))
            beam:GetData().isRvBeam = true
            beam:GetData().rvBeamMode = draw.mode
            beam:GetSprite():Load("gfx/rangevis_beam.anm2", true)
            beam:GetSprite():LoadGraphics()
            beam:GetSprite():Play("Laser0")
            beam:Update()

            for _, laser in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER)) do
                if laser.Parent and GetPtrHash(laser.Parent) == GetPtrHash(beam) then
                    laser:ToLaser():SetMaxDistance(1)
                    laser:Update()
                end
            end

            for _, eff in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.LASER_IMPACT)) do
                mod:fixLaserTip(eff)
            end
            beam:Update()

            local sfxManager = SFXManager()
            sfxManager:Stop(SoundEffect.SOUND_REDLIGHTNING_ZAP_WEAK)
            sfxManager:Stop(SoundEffect.SOUND_REDLIGHTNING_ZAP)
            sfxManager:Stop(SoundEffect.SOUND_REDLIGHTNING_ZAP_STRONG)
            sfxManager:Stop(SoundEffect.SOUND_REDLIGHTNING_ZAP_BURST)

            table.insert(pData.rvBeams, beam)
        end

    else
        for i, draw in ipairs(pData.rvDraws) do
            local beam = pData.rvBeams[i]
            local pos = draw.from
            local dir = (draw.to - draw.from):Normalized()
            local len = draw.to:Distance(draw.from)

            if mod:getConfig().HasTearFlags then
                beam.TearFlags = player:GetTearHitParams(WeaponType.WEAPON_LASER).TearFlags & kAcceptableTearFlags
            else
                beam.TearFlags = TearFlags.TEAR_NORMAL
            end
            if draw.spectral or (mod:getConfig().TearSpectral and not beam:HasTearFlags(TearFlags.TEAR_BOUNCE)) then
                beam:AddTearFlags(TearFlags.TEAR_SPECTRAL)
            end
            beam.Timeout = -1
            beam.Position = pos
            beam:SetMaxDistance(len)
            beam.Angle = dir:GetAngleDegrees()
            -- beam.EndPoint = pos + dir * len
            beam.Visible = beam.FrameCount > 4
            beam:GetData().rvBeamMode = draw.mode
            beam.Color = draw.color
        end

        if #pData.rvDraws < #pData.rvBeams then
            for i = #pData.rvDraws + 1, #pData.rvBeams do
                pData.rvBeams[i].Visible = false
            end
        end
    end
end)

-- function mod:postLaserUpdate(laser)
--     if laser:GetData().isRvBeam then
--         print('mb', laser.Color.R, laser.Color.G, laser.Color.B)
--     else
--         print('nb', laser.Color.R, laser.Color.G, laser.Color.B)
--     end
-- end
-- mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.postLaserUpdate)

function mod:preTakeDamage(tookDamage, damage, damageFlags, damageSourceRef)
    -- print(tookDamage, damage, damageFlags, damageSourceRef)
	if damageSourceRef.Type == EntityType.ENTITY_LASER then
        local laser = damageSourceRef.Entity
        if laser:GetData().isRvBeam then
            return false
        end
        if laser.Parent and laser.Parent:GetData().isRvBeam then
            return false
        end
    end
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.preTakeDamage)
