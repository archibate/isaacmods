-- Damage MVP -- shows what dealt your damage to enemies.
--
-- What the game actually tells us (measured in-game, not guessed):
--   * tears, knives, bombs and familiar shots all name themselves as the source,
--     and their spawner chain walks back to the player who owns them;
--   * LASERS DO NOT. A Brimstone / Technology / Tech X hit reports the player as
--     its source with only a DAMAGE_LASER flag, so the weapon has to be recovered
--     by looking at which lasers the player currently has alive;
--   * burn and poison ticks carry NO source at all -- empty entity, empty spawner --
--     so each enemy remembers who last hurt it, and its ticks are credited back;
--   * enemies damage each other (a boss's own eye laser hits it); those hits must
--     not be credited to the player.

local mod = RegisterMod("damagemvp", 1)

local ROW_LIMIT = 8
local TEXT_X = 25
local TEXT_Y = 55
local LINE_HEIGHT = 11

local function prettify(enumName)
    local words = {}
    for word in enumName:gmatch("[^_]+") do
        words[#words + 1] = word:sub(1, 1) .. word:sub(2):lower()
    end
    return table.concat(words, " ")
end

local function invert(enum)
    local names = {}
    if enum == nil then return names end
    for name, value in pairs(enum) do
        names[value] = name
    end
    return names
end

local FAMILIAR_VARIANT_NAMES = invert(FamiliarVariant)
local BOMB_VARIANT_NAMES = invert(BombVariant)

-- a laser's variant is the only trace left of which item fired it
local LASER_LABELS = {
    [LaserVariant.THICK_RED] = "Brimstone",
    [LaserVariant.THICKER_RED] = "Brimstone",
    [LaserVariant.GIANT_RED] = "Brimstone",
    [LaserVariant.THIN_RED] = "Technology",
    [LaserVariant.SHOOP] = "Shoop da Whoop",
    [LaserVariant.LIGHT_BEAM] = "Holy Light",
    [LaserVariant.LIGHT_RING] = "Tech X",
    [LaserVariant.BRIM_TECH] = "Tech X",
    [LaserVariant.THICKER_BRIM_TECH] = "Tech X",
    [LaserVariant.GIANT_BRIM_TECH] = "Tech X",
    [LaserVariant.TRACTOR_BEAM] = "Tractor Beam",
    [LaserVariant.ELECTRIC] = "Jacob's Ladder",
}

-- melee weapons all arrive as a knife entity, so ask the player which one it is
local MELEE_LABELS = {
    { weapon = WeaponType.WEAPON_KNIFE, label = "Mom's Knife" },
    { weapon = WeaponType.WEAPON_SPIRIT_SWORD, label = "Spirit Sword" },
    { weapon = WeaponType.WEAPON_BONE, label = "Bone Club" },
}

local function ownerPlayerOf(entity)
    local current = entity
    for _ = 1, 4 do
        if current == nil then return nil end
        local player = current:ToPlayer()
        if player ~= nil then return player end
        local familiar = current:ToFamiliar()
        if familiar ~= nil and familiar.Player ~= nil then
            current = familiar.Player
        else
            current = current.SpawnerEntity or current.Parent
        end
    end
    return nil
end

-- the familiar that fired this shot, if any (it is the shot's spawner, one hop up)
local function familiarBehind(entity)
    if entity == nil then return nil end
    local familiar = entity:ToFamiliar()
    if familiar ~= nil then return familiar end
    local spawner = entity.SpawnerEntity
    if spawner ~= nil then return spawner:ToFamiliar() end
    return nil
end

local function familiarLabel(familiar)
    local name = FAMILIAR_VARIANT_NAMES[familiar.Variant]
    if name == nil then return "Familiar" end
    return prettify(name)
end

-- lasers name the player as their source, so recover the weapon from the lasers
-- the player still has alive this frame
local function laserLabel(player)
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER, -1, -1, false, false)) do
        if ownerPlayerOf(entity) ~= nil then
            local label = LASER_LABELS[entity.Variant]
            if label ~= nil then
                local familiar = familiarBehind(entity)
                if familiar ~= nil then
                    return familiarLabel(familiar) .. " (" .. label .. ")"
                end
                return label
            end
        end
    end
    if player ~= nil then
        if player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE) then return "Brimstone" end
        if player:HasWeaponType(WeaponType.WEAPON_TECH_X) then return "Tech X" end
        if player:HasWeaponType(WeaponType.WEAPON_LASER) then return "Technology" end
    end
    return "Laser"
end

local function meleeLabel(player)
    for _, melee in ipairs(MELEE_LABELS) do
        if player:HasWeaponType(melee.weapon) then return melee.label end
    end
    return "Melee"
end

local function bombLabel(entity)
    local bomb = entity ~= nil and entity:ToBomb() or nil
    if bomb == nil then return "Bombs" end
    if bomb.IsFetus then return "Dr. Fetus" end
    local name = BOMB_VARIANT_NAMES[bomb.Variant]
    if name ~= nil and bomb.Variant ~= BombVariant.BOMB_NORMAL then
        return prettify(name)
    end
    return "Bombs"
end

-- Returns the label to credit, or nil when this hit was not the player's doing.
local function resolveSource(source, flags)
    local entity = source.Entity

    -- a laser reports the player himself as the source, with nothing else attached
    if source.Type == EntityType.ENTITY_PLAYER and flags & DamageFlag.DAMAGE_LASER ~= 0 then
        return laserLabel(entity ~= nil and entity:ToPlayer() or nil)
    end

    local player = ownerPlayerOf(entity)
    if player == nil then return nil end

    if source.Type == EntityType.ENTITY_KNIFE then
        return meleeLabel(player)
    end
    if source.Type == EntityType.ENTITY_BOMB then
        return bombLabel(entity)
    end

    local familiar = familiarBehind(entity)
    if source.Type == EntityType.ENTITY_LASER then
        local label = LASER_LABELS[source.Variant] or "Laser"
        if familiar ~= nil then
            return familiarLabel(familiar) .. " (" .. label .. ")"
        end
        return label
    end
    if familiar ~= nil then
        return familiarLabel(familiar)
    end

    if source.Type == EntityType.ENTITY_TEAR then return "Tears" end
    if source.Type == EntityType.ENTITY_EFFECT then return "Creep" end
    if source.Type == EntityType.ENTITY_PLAYER then return "Contact" end
    return "Other"
end

local tally = {}
local total = 0

local function credit(label, damage)
    tally[label] = (tally[label] or 0) + damage
    total = total + damage
end

function mod:onEntityTakeDamage(entity, amount, flags, source, countdownFrames)
    if entity:ToPlayer() ~= nil then return end
    if not entity:IsActiveEnemy(false) then return end

    -- overkill would otherwise credit damage the enemy never had left to lose
    local dealt = math.min(amount, entity.HitPoints)

    -- burn and poison ticks arrive sourceless, so credit whoever last hurt the enemy
    if source.Entity == nil and flags & DamageFlag.DAMAGE_POISON_BURN ~= 0 then
        local culprit = entity:GetData().dmvpLastSource
        if culprit ~= nil then
            credit(culprit .. " (burn)", dealt)
        end
        return
    end

    local label = resolveSource(source, flags)
    if label == nil then return end

    credit(label, dealt)
    entity:GetData().dmvpLastSource = label

    -- observer only: returning non-nil would stop other mods' damage callbacks
    return nil
end

local function sortedRows()
    local rows = {}
    for label, damage in pairs(tally) do
        rows[#rows + 1] = { label = label, damage = damage }
    end
    table.sort(rows, function(a, b) return a.damage > b.damage end)
    return rows
end

function mod:onRender()
    if total <= 0 then return end

    local y = TEXT_Y
    for index, row in ipairs(sortedRows()) do
        if index > ROW_LIMIT then break end
        local share = row.damage / total * 100
        Isaac.RenderText(string.format("%s  %.0f  (%.0f%%)", row.label, row.damage, share),
            TEXT_X, y, 1, 1, 1, 1)
        y = y + LINE_HEIGHT
    end
end

function mod:onNewRoom()
    tally = {}
    total = 0
end

mod:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.LATE, mod.onEntityTakeDamage)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
