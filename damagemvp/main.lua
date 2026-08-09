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

-- familiars that hit for you but report the player rather than themselves, so the
-- swing names no weapon. The familiar is in the room, and that is what names it --
-- the same creature whether it came from an item or from the character
local SWINGING_FAMILIARS = {
    [FamiliarVariant.UMBILICAL_BABY] = "Gello",
}

-- A laser entity's variant is the only trace left of which item fired it, and only
-- where that variant is one item's own signature. Two below were measured to be
-- shared by two items each and are named accordingly; the rest are inherited from
-- an earlier build and unmeasured, so any of them may yet prove shared too.
local LASER_LABELS = {
    [LaserVariant.THICK_RED] = "Brimstone",
    [LaserVariant.THICKER_RED] = "Brimstone",
    [LaserVariant.GIANT_RED] = "Brimstone",
    [LaserVariant.THIN_RED] = "Technology",
    -- Trisagion fires this one too, and nothing the game exposes tells the two
    -- apart -- variant, subtype, sprite and animation all match, and every measure
    -- of shape reads nil. Merged under the better known of the pair, by choice
    [LaserVariant.SHOOP] = "Shoop",
    [LaserVariant.LIGHT_BEAM] = "Holy Light",
    [LaserVariant.LIGHT_RING] = "Tech X",
    [LaserVariant.BRIM_TECH] = "Tech X",
    [LaserVariant.THICKER_BRIM_TECH] = "Tech X",
    [LaserVariant.GIANT_BRIM_TECH] = "Tech X",
    [LaserVariant.TRACTOR_BEAM] = "Tractor Beam",
    -- Technology Zero and Jacob's Ladder both fire this one, so it is named for the
    -- beam; either item's name here would be wrong half the time
    [LaserVariant.ELECTRIC] = "Electric",
}

-- An item riding another's beam variant is told apart only by its subtype: Maw of
-- the Void's ring is a Brimstone beam in every respect but that, and without this
-- its damage is quietly swallowed by the Brimstone row.
local LASER_SUBTYPES = {
    [LaserVariant.THICK_RED] = { [3] = "Maw of the Void" },
}

local function beamName(variant, subtype)
    local bySubtype = LASER_SUBTYPES[variant]
    if bySubtype ~= nil and subtype ~= nil then
        local named = bySubtype[subtype]
        if named ~= nil then return named end
    end
    return LASER_LABELS[variant]
end

-- some weapons throw a tear that is not a tear -- the swords their beam, the urn
-- its flame -- and none of them may fall through to "Tears"
local TEAR_LABELS = {
    [TearVariant.BOBS_HEAD] = "Bob's Rotten Head",
    [TearVariant.FIRE] = "Urn of Souls",
    [TearVariant.KEY] = "Sharp Key",
    [TearVariant.KEY_BLOOD] = "Sharp Key",
    [TearVariant.SWORD_BEAM] = "Spirit Sword",
    [TearVariant.TECH_SWORD_BEAM] = "Tech Sword",
}

-- Development aid, to be dropped before release: most tear variants are a skin on
-- the same tear stream and belong on one row, but a few are a weapon of their own.
-- This reports which ones are landing on the plain row, so the difference can be
-- judged from what actually turns up rather than guessed off the enum.
local seenTear = {}

local function logPlainTear(source)
    local line = "[DMVP] plain tear variant=" .. tostring(source.Variant)
        .. " spawner=" .. tostring(source.SpawnerType) .. "." .. tostring(source.SpawnerVariant)
    if seenTear[line] then return end
    seenTear[line] = true
    Isaac.DebugString(line)
end

-- Development aid, to be dropped before release: every colour of creep laid by the
-- player shares one row. This reports the variant and who laid it, so whether they
-- can be told apart at all stays a measurement rather than a hope.
local seenCreep = {}

local function logCreep(source)
    local line = string.format("[DMVP] creep variant=%d spawner=%d.%d",
        source.Variant, source.SpawnerType, source.SpawnerVariant)
    if seenCreep[line] then return end
    seenCreep[line] = true
    Isaac.DebugString(line)
end

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

-- Development aid, to be dropped before release: a bare "Laser" row means a beam
-- nothing could name. Report which beams are alive and whose they are, since the
-- entity is the only thing left that still knows what fired.
local seenLaser = {}

-- everything is stringified rather than formatted as a number: a field the stubs
-- promise can still come back nil, and a probe must never be what crashes a run
local function logPlainLaser(player, amount, verdict, flags, victim)
    local alive = {}
    for _, laser in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER, -1, -1, false, false)) do
        local owner = ownerOf(laser)
        local whose = "orphan"
        if owner ~= nil then
            whose = GetPtrHash(owner) == GetPtrHash(player) and "mine" or "other"
        end
        alive[#alive + 1] = tostring(laser.Variant) .. "." .. tostring(laser.SubType)
            .. "/" .. whose .. "/dmg" .. tostring(laser.CollisionDamage)
    end
    local line = "[DMVP] beam -> " .. tostring(verdict)
        .. "  flags=" .. string.format("0x%X", flags or 0)
        .. "  amount=" .. tostring(amount)
        .. "  alive=" .. table.concat(alive, " ")
    if seenLaser[line] then return end
    seenLaser[line] = true
    Isaac.DebugString(line)
end


-- The hit names only the player, but the beam that landed it is still in the room
-- at that moment -- measured -- so what is in flight names it. Nil when two
-- different kinds are, because nothing the game exposes ties a hit to one beam:
-- not the damage, which matches; not the geometry, which reads nil; and not the
-- order they arrive in, since a beam can hit before it ever reports an update.
local function beamInFlight(player)
    local kinds, count, any = {}, 0, nil
    for _, laser in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER, -1, -1, false, false)) do
        local owner = ownerOf(laser)
        if owner ~= nil and GetPtrHash(owner) == GetPtrHash(player) then
            local label = beamName(laser.Variant, laser.SubType)
            if label ~= nil and not kinds[label] then
                kinds[label] = true
                count = count + 1
                any = label
            end
        end
    end
    if count == 1 then return any end
    return nil
end

-- Whichever of the player's familiars could have thrown a blow that names no
-- weapon. Nil when none is out, or when two different ones are and the swing could
-- have been either.
local function swingBehind(player)
    local kinds, count, any = {}, 0, nil
    for _, familiar in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, -1, -1, false, false)) do
        local label = SWINGING_FAMILIARS[familiar.Variant]
        if label ~= nil and not kinds[label] then
            local owner = ownerOf(familiar)
            if owner ~= nil and GetPtrHash(owner) == GetPtrHash(player) then
                kinds[label] = true
                count = count + 1
                any = label
            end
        end
    end
    if count == 1 then return any end
    return nil
end

-- Development aid, to be dropped before release: a crushing blow names no weapon.
-- Report what of the player's is in the room when one lands, in case something
-- there can name it -- the alternative is guessing from what he happens to own.
local seenCrush = {}

local function logSwing(player, what, flags, amount)
    local alive = {}
    for _, kind in ipairs({ EntityType.ENTITY_FAMILIAR, EntityType.ENTITY_KNIFE }) do
        for _, entity in ipairs(Isaac.FindByType(kind, -1, -1, false, false)) do
            local owner = ownerOf(entity)
            if owner ~= nil and GetPtrHash(owner) == GetPtrHash(player) then
                alive[#alive + 1] = tostring(entity.Type) .. "." .. tostring(entity.Variant)
            end
        end
    end
    local line = "[DMVP] " .. what .. " char=" .. tostring(player:GetPlayerType())
        .. " flags=" .. string.format("0x%X", flags or 0)
        .. " amount=" .. tostring(amount)
        .. " alive=" .. table.concat(alive, ",")
    if seenCrush[line] then return end
    seenCrush[line] = true
    Isaac.DebugString(line)
end

-- Development aid, to be dropped before release: a hit whose shape nothing knows
local seenShape = {}

local function logShape(source, flags)
    local line = "[DMVP] unknown shape src=" .. tostring(source.Type) .. "."
        .. tostring(source.Variant) .. " spawner=" .. tostring(source.SpawnerType) .. "."
        .. tostring(source.SpawnerVariant) .. " flags=" .. string.format("0x%X", flags)
    if seenShape[line] then return end
    seenShape[line] = true
    Isaac.DebugString(line)
end

-- The bare name of the weapon behind a hit, or nil when it was not ours.
-- Modifiers such as "(explosion)" are the caller's business.
local function weaponOf(source, flags, amount, victim)
    local entity = source.Entity

    -- the player's own beams and swings carry no weapon of their own
    if source.Type == EntityType.ENTITY_PLAYER then
        local player = entity ~= nil and entity:ToPlayer() or nil
        if player == nil then return nil end
        -- the beam is in the room at the instant it lands its hit, so what is in
        -- flight names it; the weapon wielded answers only when none is
        if flags & DamageFlag.DAMAGE_LASER ~= 0 then
            return beamInFlight(player) or heldWeapon(player, LASER_WEAPONS) or "Laser"
        end
        -- walking into enemies -- the Nail, Unicorn Horn, Game Kid -- is not the
        -- character's melee, and the cooldown flag is what tells them apart
        if flags & DamageFlag.DAMAGE_COUNTDOWN ~= 0 then return "Contact" end
        -- a crushing blow claims no weapon at all, and nothing in the room says
        -- which one landed it, so it stays a crush rather than a guess
        if flags & DamageFlag.DAMAGE_CRUSH ~= 0 then
            logSwing(player, "crush", flags, amount)
            return "Crush"
        end
        -- Damage dealt to the whole room for spending or losing health -- Blood
        -- Rights, The Negative, a black heart -- arrives as you carrying only the
        -- armour-piercing flag, with nothing in the room and a flat amount. A real
        -- swing carries no flag at all, so this is not one, and the weapon wielded
        -- must not take it. Which of those items it was, the hit does not say.
        if flags == DamageFlag.DAMAGE_IGNORE_ARMOR then return "Unknown" end

        local swing = heldWeapon(player, MELEE_WEAPONS) or swingBehind(player)
        if swing ~= nil then return swing end
        logSwing(player, "melee", flags, amount)
        return "Melee"
    end

    local owner = ownerOf(entity)
    if owner == nil then return nil end

    -- a familiar's doing belongs to the familiar whatever shape it arrives in -- a
    -- tear, a beam, a blast, a trail of creep. This comes first because a familiar
    -- that only lays creep would otherwise never appear on the board at all.
    if source.Type == EntityType.ENTITY_FAMILIAR then
        return familiarLabel(source.Variant)
    end
    if source.SpawnerType == EntityType.ENTITY_FAMILIAR then
        return familiarLabel(source.SpawnerVariant)
    end

    -- what a shot leaves behind outlives the shot and is its own hazard: the fire
    -- from a blast, the gas from it, the creep you walk out yourself
    if source.Type == EntityType.ENTITY_EFFECT then
        if source.Variant == EffectVariant.RED_CANDLE_FLAME then
            if source.SpawnerType == EntityType.ENTITY_PLAYER then return "Red Candle" end
            return "Fire"
        end
        local label = EFFECT_LABELS[source.Variant]
        if label ~= nil then
            logCreep(source)
            return label
        end
        local name = EFFECT_NAMES[source.Variant]
        if name ~= nil then return prettify(name) end
    end
    if source.Type == EntityType.ENTITY_BOMB then
        return bombLabel(entity, source.Variant)
    end
    if source.Type == EntityType.ENTITY_LASER then
        local beam = beamName(source.Variant, entity ~= nil and entity.SubType or nil)
        if beam ~= nil then return beam end
        logPlainLaser(owner, amount, "unknown variant " .. source.Variant)
        return "Laser"
    end
    if source.Type == EntityType.ENTITY_KNIFE then
        return heldWeapon(owner, MELEE_WEAPONS) or "Melee"
    end
    if source.Type == EntityType.ENTITY_TEAR then
        local label = TEAR_LABELS[source.Variant]
        if label ~= nil then return label end
        logPlainTear(source)
        return "Tears"
    end
    -- nothing above knew this shape at all; the probe is how it stops being a
    -- surprise on the board and becomes a case to name
    logShape(source, flags)
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

-- Development aid, to be dropped before release: the board goes to the game log
-- whenever it changes, so a run's rows can be read out of log.txt afterwards
-- instead of being read off the screen and described.
local changed = false

local function logBoard()
    Isaac.DebugString(string.format("[DMVP] board total=%.1f", total))
    for _, row in ipairs(sortedRows()) do
        Isaac.DebugString(string.format("[DMVP]   %s = %.1f", row.label, row.damage))
    end
end

local function credit(label, damage)
    if damage <= 0 then return end
    tally[label] = (tally[label] or 0) + damage
    total = total + damage
    changed = true
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

-- One shape for every tick -- "<who> (<what>)" -- so the rows read alike instead of
-- in the several forms these used to take. Nothing set the status that we saw, and
-- it says Unknown rather than inventing a culprit or dropping the damage.
local function statusLabel(data, burning, poisoned)
    if burning and not poisoned then
        return (data.dmvpBurnFrom or "Unknown") .. " (burn)"
    end
    if poisoned and not burning then
        return (data.dmvpPoisonFrom or "Unknown") .. " (poison)"
    end

    -- both at once, or a tick arriving with neither flag still set: the tick names
    -- no status of its own and the two run on the same schedule, so it belongs to
    -- whoever set them -- one name when that is the same for both
    local fromBurn = data.dmvpBurnFrom or "Unknown"
    local fromPoison = data.dmvpPoisonFrom or "Unknown"
    if fromBurn == fromPoison then
        return fromBurn .. " (burn + poison)"
    end
    return fromBurn .. " / " .. fromPoison .. " (burn + poison)"
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

    local weapon = weaponOf(source, flags, amount, victim)
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

    -- once a second catches the board settling without burying the log
    if changed and frame % 30 == 0 then
        changed = false
        logBoard()
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

-- The stubs promise fields and methods the game does not always have -- Radius,
-- Timeout and IsSampleLaser each came back missing -- and reaching for one inside
-- the damage callback took the whole mod down with it. A development aid may cost
-- its own output when it is wrong; it may not cost the run.
local function guarded(fn)
    return function(...) pcall(fn, ...) end
end

logPlainTear = guarded(logPlainTear)
logCreep = guarded(logCreep)
logPlainLaser = guarded(logPlainLaser)
logSwing = guarded(logSwing)
logShape = guarded(logShape)
logBoard = guarded(logBoard)

mod:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.LATE, mod.onEntityTakeDamage)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onUpdate)
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.onRender)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.onNewRoom)

