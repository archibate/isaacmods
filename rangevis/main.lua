local mod = RegisterMod("Azazel's RangeVis", 1)

local defaultConfig = {
    EnableMod = true,
    SpriteOpacity = 4,
    ChargeVisMode = 2,
    TractorBeamMode = false,
    UseVanillaBeam = false,
    OnlyWhenFire = false,
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
    Brimstone = false,
    MeleeBone = true,
    RangedBone = true,
    TaintedForgotten = true,
    MomsKnife = true,
    SpiritSword = true,
    BagOfCrafting = true,
    BobsRottenHead = true,
    TaintedLilith = true,
    StopOnPause = true,
    OnlyHeadDir = false,
    DebugInfo = false,
    InfAimLength = 200,
}
local configDescs = {
    { "EnableMod", "Toggle this mod globally on and off" },
    { "TractorBeamMode", "Use game built-in tractor beam for visualization (experimental, restart game after change)" },
    { "UseVanillaBeam", "Use game built-in tractor beam texture (only in tractor beam mode)" },
    { "OnlyWhenFire", "Only enable this mod when fire, rid four annoying lines when not shooting" },
    { "HasTearFlags", "Take tear flags (homing, wiggle worm, etc.) into account (only in tractor beam mode)" },
    { "TearSpectral", "Aiming line can pass through obstacles (spectral tear) (only in tractor beam mode)" },
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
    { "SpiritSword", "Show range of the Spirit Sword (work in progress)" },
    { "BagOfCrafting", "Show pickup collecting range of the Bag of Crafting" },
    { "BobsRottenHead", "Show bomb landing site of the Bob's Rotten Head" },
    { "TaintedLilith", "Show shoot range of Tainted Lilith's Gello" },
    { "OnlyHeadDir", "Only show head direction aiming line when not shooting" },
    { "StopOnPause", "Do not render indicators when game paused" },
    { "DebugInfo", "Show debug infomation for mod developers (not in tractor beam mode)" },
}

-- begin config
function mod:getConfig()
    if ModConfigMenu then
        return ModConfigMenu.Config["Azazel's RangeVis"]
    else
        return defaultConfig
    end
end

if ModConfigMenu then
    for _, info in ipairs(configDescs) do
        ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.BOOLEAN, "Azazel's RangeVis", nil,
            info[1], nil, nil, nil, defaultConfig[info[1]], info[1], nil, true, info[2])
    end
    ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.NUMBER, "Azazel's RangeVis", nil,
        "SpriteOpacity", 0, 10, nil, defaultConfig.SpriteOpacity, "SpriteOpacity", nil, true,
        "Aiming line opacity, 0 for invisible, 10 for full opacit")
    ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.NUMBER, "Azazel's RangeVis", nil,
        "ChargeVisMode", 0, 2, nil, defaultConfig.ChargeVisMode, "ChargeVisMode", nil, true,
        "Charge visualization mode, 0 for none, 1 for dot, 2 for segment")
    ModConfigMenu.SimpleAddSetting(ModConfigMenu.OptionType.NUMBER, "Azazel's RangeVis", nil,
        "InfAimLength", 10, 800, nil, defaultConfig.InfAimLength, "InfAimLength", nil, true,
        "Aiming line length when range is infinity (e.g. Brimstone, Technology) (not in tractor beam mode)")
    local json = require('json')
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContined)
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
    -- mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, isContined)
    --     if mod:HasData() then
    --         local cfg = json.decode(mod:LoadData())
    --         for k, v in pairs(cfg) do
    --             mod:getConfig()[k] = v
    --         end
    --     end
    -- end)
    -- mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
    --     if shouldSave then
    --         mod:SaveData(json.encode(mod:getConfig()))
    --     end
    -- end)
end
-- end config

local kOldMode = not mod:getConfig().TractorBeamMode
local kInfinityLength = kOldMode and mod:getConfig().InfAimLength or 800
local kBeamTipLength = 4

local AimMode = {
    AIM_TEAR = 0, -- Normal tears
    AIM_LASER = 1, -- Technology series
    AIM_BOMB = 2, -- Dr. Fetus
    AIM_NOAIM = 3, -- Ludovico's Technique, Marked
    AIM_THROW = 4, -- Tainted Forgotten's soul throw his body
    AIM_HEMOPTYSIS = 5, -- Tainted Azazel's hemoptysis
    AIM_CRAFTBAG = 6, -- Tainted Cain's Bag of Crafting
    AIM_BOBHEAD = 7, -- Bob's Rotten Head
    MAX_CHARGELESS_AIM_MODES = 7,
    AIM_AZAZEL = 8, -- Azazel's short-ranged brimstone
    AIM_BRIMSTONE = 9, -- True infinite-ranged brimstone
    AIM_KNIFE = 10, -- Mom's Knife
    AIM_FARBONE = 11, -- Forgotten's ranged bone attack
    AIM_TECHX = 12, -- Technology X
    NUM_AIM_MODES = 13,
}

local ShootMode = {
    SHOOT_AUTO = 0, -- Auto shoots
    SHOOT_CHARGE = 1, -- Charged shoots
    SHOOT_CHOCOLATE = 2, -- Chocolate Milk
    SHOOT_BONE = 4, -- Forgotten's bone
    SHOOT_360 = 8, -- Analog Stick
    SHOOT_TSAMSON = 16, -- Tainted Samson's bone
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
    LINE_CRAFTBAG = 10,
    NUM_LINE_MODES = 11,
}

local lineColorTear = Color(0.50, 0.55, 0.6)
local lineColorBone = Color(0.55, 0.65, 0.7)
local lineColorKnife = Color(0.7, 0.4, 0.6)
local lineColorBrim = Color(0.95, 0.35, 0.2)
local lineColorSamson = Color(0.85, 0.1, 0.1)
local lineColorLaser = Color(0.9, 0.15, 0.15)
local lineColorChoco = Color(0.75, 0.45, 0.45)
local lineColorGello = Color(0.85, 0.45, 0.3)
local lineColorBomb = Color(0.15, 0.15, 0.2)
local lineColorRed = Color(0.85, 0.25, 0.25)
local lineColorGreen = Color(0.3, 0.65, 0.3)
local lineColorBlue = Color(0.4, 0.55, 0.85)
local targetSprite = nil

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

local function fixMirrorPos(pos)
    if Game():GetRoom():IsMirrorWorld() then
        local cent = getScreenBottomRight().X / 2
        -- local cent = 320
        -- if Game():GetLevel():GetCurrentRoomDesc().Data.Shape >= RoomShape.ROOMSHAPE_2x1 then
        -- return Vector(4 * cent - pos.X, pos.Y)
        -- end
        return Vector(2 * cent - pos.X, pos.Y)
    end
    return pos
end

local function fixMirrorDir(dir)
    if Game():GetRoom():IsMirrorWorld() then
        return Vector(-dir.X, dir.Y)
    end
    return dir
end

local function fixMirrorRotation(angle)
    if Game():GetRoom():IsMirrorWorld() then
        return 180 - angle
    end
    return angle
end

local function renderTargetSprite(name, pos, opacity)
    local frame = 1
    if opacity >= 100 then
        frame = 0
    end
    targetSprite:SetFrame(name, frame)
    local spos = fixMirrorPos(Isaac.WorldToScreen(pos))
    for _ = 1, opacity do
        targetSprite:Render(spos)
    end
end

if kOldMode then
    function mod:clearDraws(player)
        local pData = player:GetData()
        pData.rvDraws = {}
    end

    function mod:drawLine(player, from, to, aimMode, color, percent, spectral)
        local opacity = mod:getConfig().SpriteOpacity
        if opacity >= 10 then
            opacity = 100
        end

        if not targetSprite then
            targetSprite = Sprite()
            targetSprite:Load("gfx/aimer_target.anm2", true)
        end
        if not targetSprite:IsLoaded() or opacity <= 0 then return end

        local diffVector = to - from
        local angle = diffVector:GetAngleDegrees()
        local sectionLength = 12
        local sectionCount = math.floor(diffVector:Length() / sectionLength - 0.4)
        percent = math.max(0, math.min(percent, 1))
        local percentCount = math.min(sectionCount, math.max(1,
            math.floor(diffVector:Length() * percent / sectionLength - 0.4)))
        local delta = Vector.One * sectionLength * Vector.FromAngle(angle)

        targetSprite.Color = color
        targetSprite.Rotation = fixMirrorRotation(angle)
        targetSprite.FlipX = false
        targetSprite.FlipY = false
        if mod:getConfig().ChargeVisMode == 0 then
            percentCount = sectionCount
        end
        if percent >= 1 and mod:getConfig().ChargeVisMode == 2 then
            opacity = opacity * 2
        end
        for i = 1, percentCount do
            renderTargetSprite("Line", from + i * delta, opacity)
        end
        if percent < 1 then
            if opacity >= 100 then
                opacity = 5
            end
            if mod:getConfig().ChargeVisMode == 2 then
                for i = 0, sectionCount do
                    renderTargetSprite("Line", from + i * delta, opacity)
                end
            else
                for i = percentCount, sectionCount do
                    renderTargetSprite("Line", from + i * delta, opacity)
                end
            end
        else
            opacity = opacity * 2
        end

        if aimMode == LineMode.LINE_CROSS then
            targetSprite.Rotation = 0
            renderTargetSprite("Cross", to, opacity)
        elseif aimMode == LineMode.LINE_BONE then
            renderTargetSprite("Bone", to, opacity)
        elseif aimMode == LineMode.LINE_BRIMSTONE then
            renderTargetSprite("Brimstone", to, opacity)
        elseif aimMode == LineMode.LINE_HEMOPT then
            renderTargetSprite("Hemopt", to, opacity)
        elseif aimMode == LineMode.LINE_LASER then
            renderTargetSprite("Laser", to, opacity)
        elseif aimMode == LineMode.LINE_KNIFE then
            if Vector.FromAngle(angle).X < -0.1 then
                targetSprite.FlipY = true
                targetSprite.Rotation = -targetSprite.Rotation
            end
            renderTargetSprite("Knife", to, opacity)
        elseif aimMode == LineMode.LINE_TARGET then
            targetSprite.Rotation = 0
            renderTargetSprite("Target", to, opacity)
        elseif aimMode == LineMode.LINE_BOMB then
            targetSprite.Rotation = 0
            renderTargetSprite("Bomb", to, opacity)
        elseif aimMode == LineMode.LINE_GELLO then
            targetSprite.Rotation = 0
            renderTargetSprite("Gello", to, opacity)
        elseif aimMode == LineMode.LINE_CRAFTBAG then
            targetSprite.Rotation = 0
            renderTargetSprite("Craftbag", to, opacity)
        end
    end

else

    mod.draws = {}

    function mod:clearDraws(player)
        local pData = player:GetData()
        pData.rvDraws = {}
    end

    function mod:drawLine(player, from, to, mode, color, percent, spectral)
        if mod:getConfig().UseVanillaBeam then
            color = Color(1, 1, 1, 1)
        end
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

function mod:renderAimline(player, shotVel, aimMode, shootMode)
    if aimMode == AimMode.AIM_NOAIM then
        return
    end
    if mod:getConfig().OnlyWhenFire and player:GetAimDirection():Length() < 0.1 then
        return
    end
    local percent = 1 - math.max(player.FireDelay, 0) / player.MaxFireDelay
    local extraVel = player:GetTearMovementInheritance(shotVel * 10) / 10
    local origPos = player.Position

    if aimMode == AimMode.AIM_CRAFTBAG then
        shotVel = shotVel * math.max(260, player.TearRange) * 0.15
        local svl = shotVel:Length()
        local svn = shotVel:Normalized()
        local size = math.max(player.SpriteScale.X - 1, 0)
        local shotMin = svn * (svl - 42)
        shotVel = svn * (svl + 20 + size * 64)
        if mod:getConfig().BagOfCrafting then
            mod:drawLine(player, origPos + shotMin, origPos + shotVel, LineMode.LINE_CRAFTBAG, lineColorChoco, percent, true)
            return
        end
    end

    if aimMode == AimMode.AIM_BOBHEAD then
        shotVel = shotVel * 380
        if mod:getConfig().BobsRottenHead then
            mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BOMB, lineColorGreen, percent, true)
            return
        end
    end

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
            mod:drawLine(player, origPos + shotVel * (-4 + ext), origPos + shotVel * (64 - 15 + ext),
                LineMode.LINE_HEMOPT, lineColorBrim, percent, true)
        end
    elseif aimMode == AimMode.AIM_THROW then
        shotVel = shotVel + extraVel
        shotVel = shotVel * 331
        percent = 1
        if mod:getConfig().TaintedForgotten then
            mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_TARGET, lineColorBone, percent, true)
        end
    elseif (shootMode & ShootMode.SHOOT_BONE) ~= 0 then
        if (shootMode & ShootMode.SHOOT_TSAMSON) ~= 0 then
            percent = math.min(1, 2 * percent)
        end
        if aimMode == AimMode.AIM_KNIFE then
            percent = mod.shootTime / (11.5 + 3 * player.MaxFireDelay)
            -- if (shootMode & ShootMode.SHOOT_TSAMSON) ~= 0 then
            --     percent = math.min(1, percent)
            -- end
            if (shootMode & ShootMode.SHOOT_CHOCOLATE) ~= 0 then
                percent = mod.shootTime / (11.5 + 2.5 * player.MaxFireDelay)
                shotVel = shotVel * math.max(260, player.TearRange) * 0.15
                local ssc = math.max(0, math.min(1, percent) - 0.25) / 0.75 + 1
                local svl = shotVel:Length()
                local svn = shotVel:Normalized()
                local size = math.max(player.SpriteScale.X - 1, 0)
                local shotMin = svn * (svl - 42)
                shotVel = svn * (svl + 20 + size * 64) * ssc
                if mod:getConfig().MeleeBone then
                    local lineColor = lineColorBone
                    if (shootMode & ShootMode.SHOOT_TSAMSON) ~= 0 then
                        lineColor = lineColorSamson
                    end
                    mod:drawLine(player, origPos + shotMin, origPos + shotVel, LineMode.LINE_BONE, lineColor, percent, true)
                end
            else
                percent = math.min(1, percent)
                if percent > 0 then
                    shotVel = shotVel * percent
                    local svl = shotVel:Length()
                    local svn = shotVel:Normalized()
                    percent = 1
                    local lineColor = lineColorBone
                    if (shootMode & ShootMode.SHOOT_TSAMSON) ~= 0 then
                        shotVel = svn * (svl * math.min(260, player.TearRange) * 1.125 - 10)
                        lineColor = lineColorSamson
                    else
                        shotVel = svn * (svl * 260 - 10)
                    end
                    if mod:getConfig().RangedBone then
                        mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BONE, lineColor, percent, true)
                    end
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
            shotVel = shotVel * math.max(260, player.TearRange) * 0.15
            local svl = shotVel:Length()
            local svn = shotVel:Normalized()
            local size = math.max(player.SpriteScale.X - 1, 0)
            local shotMin = svn * (svl - 42)
            shotVel = svn * (svl + 20 + size * 64)
            if mod:getConfig().MeleeBone then
                local lineColor = lineColorBone
                if (shootMode & ShootMode.SHOOT_TSAMSON) ~= 0 then
                    lineColor = lineColorSamson
                end
                mod:drawLine(player, origPos + shotMin, origPos + shotVel, LineMode.LINE_BONE, lineColor, percent, true)
            end
        end
    elseif (shootMode & (ShootMode.SHOOT_CHARGE | ShootMode.SHOOT_CHOCOLATE)) == 0 then
        if aimMode == AimMode.AIM_BOMB then
            shotVel = shotVel + extraVel * 0.8
            shotVel = shotVel * math.abs(player.TearHeight) * player.ShotSpeed * 8
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
                    mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BRIMSTONE, lineColorChoco, percent,
                        true)
                end
            else
                percent = math.min(mod.shootTime, player.MaxFireDelay) / player.MaxFireDelay
                if enable then
                    mod:drawLine(player, origPos, origPos + shotVel, LineMode.LINE_BRIMSTONE, lineColorBrim, percent,
                        true)
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
        or player:HasCollectible(CollectibleType.COLLECTIBLE_SPIRIT_SWORD)
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
        if player:GetPlayerType() == PlayerType.PLAYER_SAMSON_B then
            shootMode = shootMode | ShootMode.SHOOT_BONE | ShootMode.SHOOT_TSAMSON
        end
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
                shootMode = shootMode | ShootMode.SHOOT_CHARGE
            end
        end
    end
    if player:IsHoldingItem() and player:HasCollectible(CollectibleType.COLLECTIBLE_BAG_OF_CRAFTING) then
        aimMode = AimMode.AIM_CRAFTBAG
    end
    if player:IsHoldingItem() and player:HasCollectible(CollectibleType.COLLECTIBLE_BOBS_ROTTEN_HEAD) then
        aimMode = AimMode.AIM_BOBHEAD
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

    -- print(aimMode, shootMode, mod.shootTime, aimDir)

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

if kOldMode then

    mod:AddCallback(ModCallbacks.MC_POST_RENDER, function(_)
        if not mod:getConfig().EnableMod or (mod:getConfig().StopOnPause and Game():IsPaused()) then
            return
        end
        mod:calcShootTime(Isaac.GetPlayer(0))
        for i = 0, Game():GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            mod:renderOverlay(player)
        end
    end)

else

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
        eff = eff:ToEffect()
        if eff and eff.SpawnerEntity and eff.SpawnerEntity:GetData().isRvBeam then
            local effSprite = eff:GetSprite()
            if not mod:getConfig().UseVanillaBeam then
                if effSprite:GetFilename() ~= "gfx/rangevis_target.anm2" then
                    effSprite:Load("gfx/rangevis_target.anm2", true)
                    effSprite:LoadGraphics()
                end
                local anim = "Target"
                local mode = eff.SpawnerEntity:GetData().rvBeamMode
                if mode == LineMode.LINE_TARGET then
                    anim = "Target"
                    -- effSprite.Rotation = -90
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
                    -- effSprite.Rotation = -90
                elseif mode == LineMode.LINE_BOMB then
                    anim = "Bomb"
                    -- effSprite.Rotation = -90
                elseif mode == LineMode.LINE_LASER then
                    anim = "Laser"
                elseif mode == LineMode.LINE_CRAFTBAG then
                    anim = "Craftbag"
                    -- effSprite.Rotation = -90
                elseif mode == LineMode.LINE_ONLY then
                    anim = "None"
                end
                -- effSprite.Scale = Vector(5, 5)
                effSprite:Play(anim, true)
                -- print(Isaac.GetTime(), anim)
            else
                if effSprite:GetFilename() ~= "gfx/rangevis_beam_tip.anm2" then
                    effSprite:Load("gfx/rangevis_beam_tip.anm2", true)
                    effSprite:LoadGraphics()
                    effSprite:Play("End", true)
                end
            end

            -- effSprite.FlipY = eff.FrameCount % 2 == 0
            -- effSprite.FlipX = eff.FrameCount % 2 == 0
            -- effSprite.Rotation = eff.FrameCount % 2 == 0 and 270 or 90
            -- print(effSprite.Rotation, eff.Rotation)
            effSprite:SetFrame(eff.SpawnerEntity:GetSprite():GetFrame())
            eff.Color = eff.SpawnerEntity.Color
            eff.SpriteScale = eff.SpawnerEntity.SpriteScale
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_INIT, mod.fixLaserTip, EffectVariant.LASER_IMPACT)
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, mod.fixLaserTip, EffectVariant.LASER_IMPACT)
    mod:AddCallback(ModCallbacks.MC_POST_EFFECT_RENDER, mod.fixLaserTip, EffectVariant.LASER_IMPACT)

    function mod:fixLaserBounce(laser)
        -- if laser.SpawnerEntity and laser.SpawnerEntity:GetData().isRvBeam then
        --     if laserSprite:GetFilename() ~= "gfx/rangevis_beam.anm2" then
        --         laserSprite:Load("gfx/rangevis_beam.anm2", true)
        --         laserSprite:LoadGraphics()
        --         laserSprite:Play("Laser0", true)
        --     end
        --     laser:GetData().isRvBeam = true
        --     laser.Color = laser.SpawnerEntity.Color
        -- if laser:GetData().isRvBeam then
        --     return
        -- end
        -- if laser.Parent then
        --     print(laser.Parent.Type, laser.Parent.Variant, laser.Parent.SubType)
        --     print(laser.Parent:GetData().isRvBeam)
        --     print(laser.Parent.Position)
        -- end
        -- if laser.SpawnerEntity then
        --     print('se', laser.SpawnerEntity.Type, laser.SpawnerEntity.Variant, laser.SpawnerEntity.SubType)
        --     print(laser.SpawnerEntity:GetData().isRvBeam)
        --     print(laser.SpawnerEntity.Position)
        -- end
        if laser.Parent and laser.Parent:GetData().isRvBeam then
            local laserSprite = laser:GetSprite()
            if not mod:getConfig().UseVanillaBeam then
                if laserSprite:GetFilename() ~= "gfx/rangevis_line.anm2" then
                    laserSprite:Load("gfx/rangevis_line.anm2", true)
                    laserSprite:LoadGraphics()
                    laserSprite:Play("Laser0", true)
                end
            else
                if laserSprite:GetFilename() ~= "gfx/rangevis_beam.anm2" then
                    laserSprite:Load("gfx/rangevis_beam.anm2", true)
                    laserSprite:LoadGraphics()
                    laserSprite:Play("Laser0", true)
                end
            end
            laser:GetData().isRvBeam = true
            laser:GetData().rvBeamMode = laser.Parent:GetData().rvBeamMode
            laser.Color = laser.Parent.Color
            laser:Update()
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_LASER_INIT, mod.fixLaserBounce)
    mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.fixLaserBounce)
    mod:AddCallback(ModCallbacks.MC_POST_LASER_RENDER, mod.fixLaserBounce)


    mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, function(_, player)
        if GetPtrHash(player) == GetPtrHash(Isaac.GetPlayer(0)) then
            mod:calcShootTime(player)
        end
        mod:renderOverlay(player)

        local pData = player:GetData()
        if not pData.rvDraws then return end
        if not pData.rvBeams then
            pData.rvBeams = {}
        end

        if not (function()
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
                beam.Color = Color(draw.color.R, draw.color.G, draw.color.B, mod:getConfig().SpriteOpacity / 10)
                -- beam.RenderZOffset = 0
                beam.SpriteScale = Vector.One
                beam.SpriteOffset = Vector.Zero
                beam.PositionOffset = Vector(0, player.TearHeight)
                -- beam.Position = draw.from
                beam.Visible = false
                beam:SetMaxDistance(draw.to:Distance(draw.from) - kBeamTipLength)
                beam:GetData().isRvBeam = true
                beam:GetData().rvBeamMode = draw.mode
                local beamSprite = beam:GetSprite()
                if not mod:getConfig().UseVanillaBeam then
                    beamSprite:Load("gfx/rangevis_line.anm2", true)
                else
                    beamSprite:Load("gfx/rangevis_beam.anm2", true)
                end
                beamSprite:LoadGraphics()
                beamSprite:Play("Laser0")
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
                beam:SetMaxDistance(len - kBeamTipLength)
                beam.Angle = dir:GetAngleDegrees()
                -- beam.EndPoint = pos + dir * len
                beam.Visible = beam.FrameCount > 4
                beam:GetData().rvBeamMode = draw.mode
                beam.Color = Color(draw.color.R, draw.color.G, draw.color.B, mod:getConfig().SpriteOpacity / 10)
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

    function mod:preTakeDamage(entity, damage, damageFlags, damageSourceRef)
        -- print(entity, damage, damageFlags, damageSourceRef)
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

end
