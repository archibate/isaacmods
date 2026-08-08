-- Damage MVP -- ranks what dealt your damage in the current room.
--
-- Everything below follows from what the game was measured to report, not from
-- what the API suggests it should:
--   * tears, knives, bombs and lasers fired by a familiar name their familiar in
--     the source's spawner slot, and a familiar's own beam names the familiar;
--   * the player's OWN lasers and melee swings report the player himself and
--     nothing else, so the weapon is recovered from what he wields;
--   * the Spirit Sword's beam arrives as a tear variant, its stab as the player;
--   * burn and poison ticks arrive with an entirely empty source, tick on the same
--     20-frame schedule and deal the same damage, so they are told apart only by
--     which status the victim is carrying;
--   * a status always lands on the same frame as the hit that applied it;
--   * enemies hurt each other and themselves, and troll bombs hurt everyone --
--     none of those chains reach a player, which is how they are excluded.

local mod = RegisterMod("damagemvp", 1)

local ROW_LIMIT = 8
local TEXT_X = 25
local TEXT_Y = 55
local LINE_HEIGHT = 11

-- pinned when a status appears with nothing of ours behind it; such a tick is
-- reported bare rather than handed to whatever weapon happens to fire next
local UNATTRIBUTED = false

-- the enum names have no punctuation, and a name read off one of them reads wrong
-- without it -- "Bobs Brain", "Moms Razor"
local WORD_FIXUPS = {
    BLUEBABYS = "Blue Baby's",
    BOBS = "Bob's",
    CAINS = "Cain's",
    DR = "Dr.",
    EVES = "Eve's",
    FATES = "Fate's",
    GUPPYS = "Guppy's",
    ISAACS = "Isaac's",
    MOMS = "Mom's",
    MR = "Mr.",
    SAMSONS = "Samson's",
}

local function prettify(enumName)
    local words = {}
    for word in enumName:gmatch("[^_]+") do
        words[#words + 1] = WORD_FIXUPS[word] or (word:sub(1, 1) .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

local function invert(enum)
    local names = {}
    for name, value in pairs(enum) do
        names[value] = name
    end
    return names
end

local FAMILIAR_NAMES = invert(FamiliarVariant)
local BOMB_NAMES = invert(BombVariant)

local WEAPON_LABELS = {
    [WeaponType.WEAPON_BRIMSTONE] = "Brimstone",
    [WeaponType.WEAPON_LASER] = "Technology",
    [WeaponType.WEAPON_TECH_X] = "Tech X",
    [WeaponType.WEAPON_KNIFE] = "Mom's Knife",
    [WeaponType.WEAPON_BONE] = "Bone Club",
    [WeaponType.WEAPON_NOTCHED_AXE] = "Notched Axe",
    [WeaponType.WEAPON_URN_OF_SOULS] = "Urn of Souls",
    [WeaponType.WEAPON_SPIRIT_SWORD] = "Spirit Sword",
    [WeaponType.WEAPON_UMBILICAL_WHIP] = "Umbilical Whip",
}

local LASER_WEAPONS = {
    WeaponType.WEAPON_BRIMSTONE,
    WeaponType.WEAPON_LASER,
    WeaponType.WEAPON_TECH_X,
}

local MELEE_WEAPONS = {
    WeaponType.WEAPON_KNIFE,
    WeaponType.WEAPON_SPIRIT_SWORD,
    WeaponType.WEAPON_BONE,
    WeaponType.WEAPON_NOTCHED_AXE,
    WeaponType.WEAPON_URN_OF_SOULS,
    WeaponType.WEAPON_UMBILICAL_WHIP,
}

-- a character whose melee claims no weapon of its own can only be named by who
-- is swinging it
local CHARACTER_MELEE = {
    [PlayerType.PLAYER_LILITH_B] = "Gello",
}

-- a laser entity's variant is the only trace left of which item fired it
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

-- some weapons throw a tear that is not a tear -- the swords their beam, the urn
-- its flame -- and none of them may fall through to "Tears"
local TEAR_LABELS = {
    [TearVariant.FIRE] = "Urn of Souls",
    [TearVariant.SWORD_BEAM] = "Spirit Sword",
    [TearVariant.TECH_SWORD_BEAM] = "Tech Sword",
}

-- a shot leaves hazards behind that outlive it -- creep, gas, fire -- and each is
-- named from the game's own effect table so none of them lands on an "Other" row.
-- Creep is the exception: every colour of it is one hazard to a damage board.
local EFFECT_NAMES = invert(EffectVariant)
local EFFECT_LABELS = {}
for name, variant in pairs(EffectVariant) do
    if name:match("^PLAYER_CREEP") then EFFECT_LABELS[variant] = "Creep" end
end

local function familiarLabel(variant)
    local name = FAMILIAR_NAMES[variant]
    if name == nil then return "Familiar" end
    return prettify(name)
end

local function bombLabel(entity, variant)
    if entity ~= nil then
        local bomb = entity:ToBomb()
        if bomb ~= nil and bomb.IsFetus then return "Dr. Fetus" end
    end
    if variant == BombVariant.BOMB_NORMAL then return "Bombs" end
    local name = BOMB_NAMES[variant]
    if name == nil then return "Bombs" end
    return prettify(name:gsub("^BOMB_", "")) .. " Bomb"
end

local function heldWeapon(player, candidates)
    for _, weapon in ipairs(candidates) do
        if player:HasWeaponType(weapon) then return WEAPON_LABELS[weapon] end
    end
    return nil
end

-- a hit's chain back to a player; nil means nobody of ours dealt it, which is the
-- whole of "enemies never damage you on my behalf"
local function ownerOf(entity)
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

-- The bare name of the weapon behind a hit, or nil when it was not ours.
-- Modifiers such as "(explosion)" are the caller's business.
local function weaponOf(source, flags)
    local entity = source.Entity

    -- the player's own beams and swings carry no weapon of their own
    if source.Type == EntityType.ENTITY_PLAYER then
        local player = entity ~= nil and entity:ToPlayer() or nil
        if player == nil then return nil end
        if flags & DamageFlag.DAMAGE_LASER ~= 0 then
            -- a beam still in flight after an item swap no longer matches the
            -- weapon held, so it stays a plain laser rather than a wrong name
            return heldWeapon(player, LASER_WEAPONS) or "Laser"
        end
        -- walking into enemies -- the Nail, Unicorn Horn, Game Kid -- is not the
        -- character's melee, and the cooldown flag is what tells them apart
        if flags & DamageFlag.DAMAGE_COUNTDOWN ~= 0 then return "Contact" end
        -- the axe's swing claims no weapon at all, only a crushing blow, so the
        -- item in hand is the only thing left that names it
        if flags & DamageFlag.DAMAGE_CRUSH ~= 0
            and player:HasCollectible(CollectibleType.COLLECTIBLE_NOTCHED_AXE) then
            return "Notched Axe"
        end
        return heldWeapon(player, MELEE_WEAPONS)
            or CHARACTER_MELEE[player:GetPlayerType()]
            or "Melee"
    end

    local owner = ownerOf(entity)
    if owner == nil then return nil end

    -- a lingering fire is its own hazard: the candle's is dropped by the player,
    -- the one an exploding shot leaves behind is dropped by that shot
    if source.Type == EntityType.ENTITY_EFFECT then
        if source.Variant == EffectVariant.RED_CANDLE_FLAME then
            if source.SpawnerType == EntityType.ENTITY_PLAYER then return "Red Candle" end
            return "Fire"
        end
        local label = EFFECT_LABELS[source.Variant]
        if label ~= nil then return label end
        local name = EFFECT_NAMES[source.Variant]
        if name ~= nil then return prettify(name) end
    end
    -- a familiar's doing belongs to the familiar whatever shape it arrives in -- a
    -- tear, a beam, a blast -- so this comes before naming the shape itself. The
    -- hazards above are the exception: a fire is a fire whoever lit it.
    if source.Type == EntityType.ENTITY_FAMILIAR then
        return familiarLabel(source.Variant)
    end
    if source.SpawnerType == EntityType.ENTITY_FAMILIAR then
        return familiarLabel(source.SpawnerVariant)
    end

    if source.Type == EntityType.ENTITY_BOMB then
        return bombLabel(entity, source.Variant)
    end
    if source.Type == EntityType.ENTITY_LASER then
        return LASER_LABELS[source.Variant] or "Laser"
    end
    if source.Type == EntityType.ENTITY_KNIFE then
        return heldWeapon(owner, MELEE_WEAPONS) or "Melee"
    end
    if source.Type == EntityType.ENTITY_TEAR then
        return TEAR_LABELS[source.Variant] or "Tears"
    end
    return "Other"
end

local tally = {}
local total = 0

local function sortedRows()
    local rows = {}
    for label, damage in pairs(tally) do
        rows[#rows + 1] = { label = label, damage = damage }
    end
    table.sort(rows, function(a, b) return a.damage > b.damage end)
    return rows
end

local function credit(label, damage)
    if damage <= 0 then return end
    tally[label] = (tally[label] or 0) + damage
    total = total + damage
end

-- Whoever hurt an enemy last is not always whoever set it alight. A status is
-- pinned to an owner the moment it appears and is never re-pinned while it lasts,
-- so a later weapon can never inherit someone else's burn.
local function syncStatus(victim, frame)
    local data = victim:GetData()
    local burning = victim:HasEntityFlags(EntityFlag.FLAG_BURN)
    local poisoned = victim:HasEntityFlags(EntityFlag.FLAG_POISON)

    local fresh = data.dmvpHitFrame ~= nil and frame - data.dmvpHitFrame <= 1
    local applier = fresh and data.dmvpHitLabel or UNATTRIBUTED

    if burning and not data.dmvpBurning then data.dmvpBurnFrom = applier end
    if poisoned and not data.dmvpPoisoned then data.dmvpPoisonFrom = applier end
    data.dmvpBurning = burning
    data.dmvpPoisoned = poisoned
end

local function statusLabel(data, burning, poisoned)
    local burnFrom = data.dmvpBurnFrom
    local poisonFrom = data.dmvpPoisonFrom

    if burning and poisoned then
        -- the tick names neither status and both run on the same schedule, so it
        -- is only nameable when one weapon is behind both
        if burnFrom and burnFrom == poisonFrom then
            return burnFrom .. " (burn + poison)"
        end
        return "Burn + poison"
    end
    if burning then
        return burnFrom and burnFrom .. " (burn)" or "Burn"
    end
    if poisoned then
        return poisonFrom and poisonFrom .. " (poison)" or "Poison"
    end
    return "Burn/poison"
end

function mod:onEntityTakeDamage(victim, amount, flags, source, countdownFrames)
    if victim:ToPlayer() ~= nil then return nil end
    if not victim:IsEnemy() then return nil end

    local frame = Game():GetFrameCount()

    -- a status set by an earlier hit this frame is already visible here, which is
    -- what keeps its owner from being stolen by a shot that landed alongside it
    syncStatus(victim, frame)

    -- overkill would otherwise credit damage the enemy never had left to lose, and
    -- a corpse still ticking has negative health that would count against us
    local dealt = math.max(0, math.min(amount, victim.HitPoints))
    local data = victim:GetData()

    if flags & DamageFlag.DAMAGE_POISON_BURN ~= 0 then
        credit(statusLabel(data, data.dmvpBurning, data.dmvpPoisoned), dealt)
        return nil
    end

    local weapon = weaponOf(source, flags)
    if weapon == nil then
        -- something not ours touched this enemy last, so a status appearing now
        -- belongs to nobody rather than to whatever we hit it with earlier
        data.dmvpHitLabel = nil
        data.dmvpHitFrame = nil
        return nil
    end

    -- remembered bare, so a status this hit is about to apply reads as the weapon
    -- rather than as the blast or the fire it leaves behind
    data.dmvpHitLabel = weapon
    data.dmvpHitFrame = frame

    -- a shot that explodes still arrives as the shot, so its blast has to say so;
    -- bombs already name themselves and need no marking
    if flags & DamageFlag.DAMAGE_EXPLOSION ~= 0 and source.Type ~= EntityType.ENTITY_BOMB then
        weapon = weapon .. " (explosion)"
    end

    credit(weapon, dealt)

    -- observer only: returning non-nil would stop other mods' damage callbacks
    return nil
end

-- catches a status applied by the last hit of a frame, which no later hit can see
function mod:onUpdate()
    local frame = Game():GetFrameCount()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        if entity:IsEnemy() then syncStatus(entity, frame) end
    end
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
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)
