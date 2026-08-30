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

-- a name reads as shouted when every word of it is capitalised: Halo Of Flies
local SMALL_WORDS = { OF = "of", THE = "the", AND = "and" }

local function prettify(enumName)
    local words = {}
    for word in enumName:gmatch("[^_]+") do
        local small = #words > 0 and SMALL_WORDS[word] or nil
        words[#words + 1] = WORD_FIXUPS[word] or small
            or (word:sub(1, 1) .. word:sub(2):lower())
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

-- Every melee weapon swings a knife entity of its own, and the variant is finer than
-- the wielded weapon type: bone club and Berserk!'s club both answer to the same bone
-- weapon, and Berserk!'s damage was reading as the Forgotten's. Vanilla names none of
-- these numbers -- the enum for them came with REPENTOGON -- so they are written out.
local KNIFE_LABELS = {
    [0] = "Mom's Knife",
    [1] = "Bone Club",
    [2] = "Bone Scythe",
    [3] = "Berserk!",
    [4] = "Bag of Crafting",
    [5] = "Sumptorium",
    [9] = "Notched Axe",
    [10] = "Spirit Sword",
    [11] = "Tech Sword",
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

-- A laser's SubType is the shape it takes rather than the item that fired it, and
-- where a shape has only one maker it names the weapon better than the variant can.
-- Tech X's ring is a Technology beam in colour, girth and everything else the game
-- exposes; measured, its shape is the only thing that says otherwise, and without
-- this its damage was landing quietly on Technology's row.
local LASER_SHAPES = {
    [LaserSubType.LASER_SUBTYPE_RING_PROJECTILE] = "Tech X",
}

-- A laser entity's variant is the only trace left of which item fired it, and only
-- where that variant is one item's own signature. Two below were measured to be
-- shared by two items each and are named accordingly; the rest are inherited from
-- an earlier build and unmeasured, so any of them may yet prove shared too.
local LASER_LABELS = {
    [LaserVariant.THICK_RED] = "Brimstone",
    [LaserVariant.THICKER_RED] = "Brimstone",
    [LaserVariant.GIANT_RED] = "Brimstone",
    -- the whole tech family fires this one: Technology's constant beam, and the
    -- stray beams Tech.5 throws between tears, both measured. Named for the family
    -- rather than for whichever of them the player happens to be holding
    [LaserVariant.THIN_RED] = "Technology",
    -- Trisagion fires this one too, and nothing the game exposes tells the two
    -- apart -- variant, subtype, sprite and animation all match, and every measure
    -- of shape reads nil. Merged under the better known of the pair, by choice
    [LaserVariant.SHOOP] = "Shoop",
    -- Holy Light drops one of these where a tear lands and Revelation fires one on
    -- a charged shot, so it is named for the beam; Revelation's damage was reading
    -- as Holy Light's
    [LaserVariant.LIGHT_BEAM] = "Light Beam",
    -- Tech X's ring was measured to be none of this -- it is a Technology beam by
    -- variant -- so whatever fires this one is unknown and it is named for itself
    [LaserVariant.LIGHT_RING] = "Light Ring",
    -- these are what Brimstone and Technology make together -- measured, with no
    -- Tech X held at all, which is what the old table called them
    [LaserVariant.BRIM_TECH] = "Brim Tech",
    [LaserVariant.THICKER_BRIM_TECH] = "Brim Tech",
    [LaserVariant.GIANT_BRIM_TECH] = "Brim Tech",
    [LaserVariant.TRACTOR_BEAM] = "Tractor Beam",
    -- Technology Zero and Jacob's Ladder both fire this one; they part on shape
    -- below, and anything else electric keeps the beam's own name
    [LaserVariant.ELECTRIC] = "Electric",
}

-- An item riding another's beam variant is told apart only by its subtype: the black
-- ring is a Brimstone beam in every respect but that, and without this its damage is
-- quietly swallowed by the Brimstone row. Maw of the Void and Athame both drop one
-- and the two are identical to everything the game exposes, so the ring is named
-- rather than either item -- Athame's damage had been reading as Maw's.
local LASER_SUBTYPES = {
    [LaserVariant.THICK_RED] = {
        [LaserSubType.LASER_SUBTYPE_RING_FOLLOW_PARENT] = "Black Ring",
    },
    -- the two electric items were sharing one row until each was measured alone:
    -- the spark that leaves no impact is Technology Zero's, the plain one the
    -- ladder's. A third electric shape, if there is one, still reads as the beam
    [LaserVariant.ELECTRIC] = {
        [LaserSubType.LASER_SUBTYPE_NO_IMPACT] = "Technology Zero",
        [LaserSubType.LASER_SUBTYPE_LINEAR] = "Jacob's Ladder",
    },
}

local function beamName(variant, subtype)
    local byShape = subtype ~= nil and LASER_SHAPES[subtype] or nil
    if byShape ~= nil then return byShape end

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

local function kin(entity, name)
    local relative = entity ~= nil and entity[name] or nil
    if relative == nil then return name .. "=nil" end
    return name .. "=" .. tostring(relative.Type) .. "." .. tostring(relative.Variant)
end

local function logPlainTear(source)
    local tear = source.Entity
    local line = "[DMVP] plain tear variant=" .. tostring(source.Variant)
        .. " spawner=" .. tostring(source.SpawnerType) .. "." .. tostring(source.SpawnerVariant)
        .. " " .. kin(tear, "SpawnerEntity") .. " " .. kin(tear, "Parent")
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

-- Holy Light drops this where a tear landed and Crack the Sky calls the same light
-- down itself, so one row covers both -- the enum's own name would credit the item
-- you may not even have.
EFFECT_LABELS[EffectVariant.CRACK_THE_SKY] = "Holy Light"

-- these two grow through four variants as they eat, and each stage would take a row
-- of its own -- "Cube Of Meat 1" beside "Cube Of Meat 2" for the one familiar. The
-- other numbered names are separate items and keep their numbers
local GROWING_FAMILIARS = {
    CUBE_OF_MEAT = true,
    BALL_OF_BANDAGES = true,
}

local function familiarLabel(variant)
    local name = FAMILIAR_NAMES[variant]
    if name == nil then return "Familiar" end
    local stem = name:match("^(.*)_%d$")
    if stem ~= nil and GROWING_FAMILIARS[stem] then name = stem end
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

local function logPlainLaser(player, amount, verdict, flags, victim)
    local alive = {}
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_LASER, -1, -1, false, false)) do
        local owner = ownerOf(entity)
        local whose = "orphan"
        if owner ~= nil then
            whose = GetPtrHash(owner) == GetPtrHash(player) and "mine" or "other"
        end
        alive[#alive + 1] = tostring(entity.Variant) .. "." .. tostring(entity.SubType)
            .. "/" .. whose .. "/dmg" .. tostring(entity.CollisionDamage)
    end
    local line = "[DMVP] beam -> " .. tostring(verdict)
        .. "  flags=" .. string.format("0x%X", flags or 0)
        .. "  amount=" .. tostring(amount)
        .. "  alive=" .. table.concat(alive, " | ")
    if seenLaser[line] then return end
    seenLaser[line] = true
    Isaac.DebugString(line)
end


-- Development aid, to be dropped before release: every kind of beam of yours seen,
-- variant and subtype both. Two items sharing a variant may still differ here --
-- that is what told Maw's ring from Brimstone -- and only this says so.
local seenBeamKind = {}

local function logBeamKind(laser)
    -- where a beam begins is the difference the entity type hides: Holy Light drops
    -- one where a tear landed, Revelation fires one out of the player
    local owner = ownerOf(laser)
    local away = "?"
    if owner ~= nil and laser.Position ~= nil and owner.Position ~= nil then
        local dx = laser.Position.X - owner.Position.X
        local dy = laser.Position.Y - owner.Position.Y
        -- bucketed, or every beam at its own distance would be a fresh line
        away = math.sqrt(dx * dx + dy * dy) < 1 and "onYou" or "elsewhere"
    end
    local spawner = laser.SpawnerEntity
    local line = "[DMVP] beamkind " .. tostring(laser.Type) .. ":"
        .. tostring(laser.Variant) .. "." .. tostring(laser.SubType)
        .. " spawner=" .. (spawner == nil and "nil"
            or (tostring(spawner.Type) .. "." .. tostring(spawner.Variant)))
        .. " refspawner=" .. tostring(laser.SpawnerType) .. "." .. tostring(laser.SpawnerVariant)
        .. " away=" .. away
    if seenBeamKind[line] then return end
    seenBeamKind[line] = true
    Isaac.DebugString(line)
end

-- The fallback for a beam of yours, and only where REPENTOGON is absent -- with it,
-- the hit hands over the beam itself and none of the below is reached.
--
-- The hit names only the player, but the beam that landed it is still in the room at
-- that moment, so what is in flight names it. Two returns: the one kind of beam of
-- yours up there, and how many kinds there were. A second kind is the end of it in
-- plain Repentance, and every way out of that was tried and measured: the damage
-- matches to the decimal, the order they arrive in cannot be anchored since a beam
-- can hit before it ever reports an update, and vanilla has no collision callback for
-- lasers as it has for tears and knives.
--
-- Their geometry does read -- through :ToLaser(), which is what an earlier attempt
-- was missing -- and the game will even sample a beam's whole path. But a hit was
-- measured up to 20px clear of the path that dealt it while a ring that dealt
-- nothing passed within 42px, so no reach test tells them apart without sometimes
-- naming the wrong one, which is worse than naming neither.
-- The one thing of yours of a kind that could have dealt a blow naming no weapon,
-- and how many kinds of it were out. Nil for the name when that is not exactly one.
local function soleOwned(player, entityType, nameOf)
    local kinds, count, any = {}, 0, nil
    for _, entity in ipairs(Isaac.FindByType(entityType, -1, -1, false, false)) do
        local label = nameOf(entity)
        if label ~= nil and not kinds[label] then
            local owner = ownerOf(entity)
            if owner ~= nil and GetPtrHash(owner) == GetPtrHash(player) then
                kinds[label] = true
                count = count + 1
                any = label
            end
        end
    end
    if count == 1 then return any, count end
    return nil, count
end

-- What REPENTOGON hands the hit alongside the player: the blade or beam that actually
-- landed it, which is the one thing plain Repentance never says. Two returns: the
-- name, and the plain word for its kind where the tables have no name for it -- the
-- second is what parts a thing handed over from nothing being handed over, and it
-- matters because letting the flags answer instead would name the wrong weapon.
-- Measured on both counts: two beams of yours in the air at once, where the guess
-- below gives up and this named each hit correctly; and the axe, whose blow arrives
-- crushing and was landing on the Crush row rather than its own.
-- Both nil without REPENTOGON and on hits it does not cover, so the guesses stay
-- behind this rather than being replaced.
local function weaponFromHit(player, extraSource)
    if extraSource == nil then return nil, nil end
    local held = extraSource.Entity
    local subtype = held ~= nil and held.SubType or nil
    if extraSource.Type == EntityType.ENTITY_LASER then
        return beamName(extraSource.Variant, subtype), "Laser"
    end
    -- a blade of a kind the table does not know still falls back to the weapon
    -- wielded, the same as one that arrives naming itself
    if extraSource.Type == EntityType.ENTITY_KNIFE then
        local named = KNIFE_LABELS[extraSource.Variant]
        if named ~= nil then return named, nil end
        return nil, heldWeapon(player, MELEE_WEAPONS) or "Melee"
    end
    if extraSource.Type == EntityType.ENTITY_FAMILIAR then
        return familiarLabel(extraSource.Variant), "Familiar"
    end
    return nil, nil
end

local function beamInFlight(player)
    return soleOwned(player, EntityType.ENTITY_LASER, function(laser)
        return beamName(laser.Variant, laser.SubType)
    end)
end

-- Which blade of yours is out. The wielded weapon type cannot tell the Forgotten's
-- bone club from the one Berserk! hands you -- both answer to the same bone weapon --
-- but the game gives each its own knife entity, and the variant parts them.
local function knifeInHand(player)
    return (soleOwned(player, EntityType.ENTITY_KNIFE, function(knife)
        return KNIFE_LABELS[knife.Variant]
    end))
end

-- A dash that hurts whatever it passes through arrives as you carrying no flag at all,
-- the same shape as a swing, and hands nothing over. The state the game puts you in to
-- dash was the witness, but measured on Tainted Judas it is already gone by the time
-- the blow lands -- no state of any kind is on. What is on the floor at that moment is
-- the snare the dash drops, so that names it. The state is still asked first, since
-- the item's dash was measured through it and only the character's was measured here.
--
-- The snare's own damage is not this: it arrives as the snare and keeps its own row,
-- the way a bomb's fire stands apart from the bomb.
local function dashing(player)
    if player:GetEffects():HasNullEffect(NullItemID.ID_DARK_ARTS) then return "Dark Arts" end
    if #Isaac.FindByType(EntityType.ENTITY_EFFECT, EffectVariant.DARK_SNARE,
        -1, false, false) > 0 then
        return "Dark Arts"
    end
    return nil
end

-- Holy Light's damage arrives as the player carrying no flag at all, so the only
-- witness is the light itself standing in the room. No owner chain is required of
-- it, because half of them carry no spawner to walk -- which assumes nothing but
-- your own items makes one. That is untested; an enemy able to call the same light
-- down would be credited to you.
local function holyLightInRoom()
    for _, light in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT,
        EffectVariant.CRACK_THE_SKY, -1, false, false)) do
        if light ~= nil then return "Holy Light" end
    end
    return nil
end

-- Whichever of the player's familiars could have thrown a blow that names no
-- weapon. Nil when none is out, or when two different ones are and the swing could
-- have been either.
local function swingBehind(player)
    return (soleOwned(player, EntityType.ENTITY_FAMILIAR, function(familiar)
        return SWINGING_FAMILIARS[familiar.Variant]
    end))
end

-- Development aid, to be dropped before release: a crushing blow names no weapon.
-- Report what of the player's is in the room when one lands, in case something
-- there can name it -- the alternative is guessing from what he happens to own.
local seenCrush = {}

local function logSwing(player, what, flags, amount)
    local alive = {}
    for _, kind in ipairs({ EntityType.ENTITY_FAMILIAR, EntityType.ENTITY_KNIFE,
        EntityType.ENTITY_LASER }) do
        for _, entity in ipairs(Isaac.FindByType(kind, -1, -1, false, false)) do
            local owner = ownerOf(entity)
            if owner ~= nil and GetPtrHash(owner) == GetPtrHash(player) then
                alive[#alive + 1] = tostring(entity.Type) .. "." .. tostring(entity.Variant)
                    .. "." .. tostring(entity.SubType)
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

-- Development aid, to be dropped before release: a hit the board throws away for
-- tracing back to nobody. Absence of a row proves nothing on its own -- this is
-- what tells a hit correctly ignored from one that never happened.
local seenDropped = {}

local function logDropped(source, flags)
    local line = "[DMVP] dropped src=" .. tostring(source.Type) .. "."
        .. tostring(source.Variant) .. " spawner=" .. tostring(source.SpawnerType) .. "."
        .. tostring(source.SpawnerVariant) .. " flags=" .. string.format("0x%X", flags)
    if seenDropped[line] then return end
    seenDropped[line] = true
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
local function weaponOf(source, flags, amount, victim, extraSource)
    local entity = source.Entity

    -- the player's own beams and swings carry no weapon of their own
    if source.Type == EntityType.ENTITY_PLAYER then
        local player = entity ~= nil and entity:ToPlayer() or nil
        if player == nil then return nil end
        -- REPENTOGON hands over the thing that actually landed the blow, and that
        -- settles the hit outright whatever flag it carries -- the axe's swing arrives
        -- crushing, and the crush row below was taking it. Everything after this is
        -- for plain Repentance, where the flags are all there is to read.
        local exact, plain = weaponFromHit(player, extraSource)
        if exact ~= nil then return exact end
        if plain ~= nil then
            -- handed over, and no table has a name for it. Letting the flags answer
            -- instead would name the wrong weapon, so it stays plain; an unnamed beam
            -- is reported, since a variant nothing knows is a case worth naming
            if extraSource.Type == EntityType.ENTITY_LASER then
                logPlainLaser(player, amount, "unknown variant " .. tostring(extraSource.Variant),
                    flags, victim)
            end
            return plain
        end

        -- the beam is in the room at the instant it lands its hit, so what is in
        -- flight names it, and the weapon wielded answers only where nothing of yours
        -- is up there at all. With two beams flying that guess would name one of them
        -- for certain and be wrong about half the hits, which is worse than saying so.
        if flags & DamageFlag.DAMAGE_LASER ~= 0 then
            local beam, kinds = beamInFlight(player)
            if kinds > 0 then
                logPlainLaser(player, amount, beam or "ambiguous", flags, victim)
                return beam or "Laser"
            end
            return heldWeapon(player, LASER_WEAPONS) or "Laser"
        end
        -- walking into enemies -- the Nail, Unicorn Horn, Game Kid -- is not the
        -- character's melee, and the cooldown flag is what tells them apart
        if flags & DamageFlag.DAMAGE_COUNTDOWN ~= 0 then return "Contact" end
        -- a crushing blow claims no weapon at all. The axe's swing is one -- measured,
        -- and the hit hands the axe over where REPENTOGON is there to hand it. Where it
        -- is not, the blade is still out at that moment, so one blade of yours up there
        -- names it the way one beam in flight does. Two, and it stays a crush rather
        -- than a guess between them.
        if flags & DamageFlag.DAMAGE_CRUSH ~= 0 then
            local blade = knifeInHand(player)
            if blade ~= nil then return blade end
            logSwing(player, "crush", flags, amount)
            return "Crush"
        end
        -- Damage dealt to the whole room for spending or losing health -- Blood
        -- Rights, The Negative, a black heart -- arrives as you carrying only the
        -- armour-piercing flag, with nothing in the room and a flat amount. A real
        -- swing carries no flag at all, so this is not one, and the weapon wielded
        -- must not take it. Which of those items it was, the hit does not say, so
        -- the row is named for what they all are rather than guessed between them.
        if flags == DamageFlag.DAMAGE_IGNORE_ARMOR then return "Screen Damage" end

        -- a blast credited to you with no shot behind it -- setting off your own
        -- TNT does this. Not a swing, so the weapon wielded must not take it
        if flags == DamageFlag.DAMAGE_EXPLOSION then return "Explosion" end
        if flags == (DamageFlag.DAMAGE_EXPLOSION | DamageFlag.DAMAGE_TNT) then
            return "TNT"
        end

        -- Nothing in Isaac swings bare-handed, so a hit with no weapon wielded and
        -- nothing of yours swinging is not melee at all. Holy Light's beam arrives
        -- exactly so -- no laser flag, and usually no beam left in the room to ask
        -- -- and there is nothing in the hit that names it.
        local swing = knifeInHand(player)
            or dashing(player)
            or heldWeapon(player, MELEE_WEAPONS)
            or swingBehind(player)
            or holyLightInRoom()
        if swing ~= nil then return swing end
        logSwing(player, "melee", flags, amount)
        return "Unknown"
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
    -- and where the hit's own reference names you instead -- which is what Incubus
    -- and Twisted Baby do, their whole damage arriving as your tears -- the shot
    -- still remembers what fired it
    if entity ~= nil and entity.SpawnerEntity ~= nil
        and entity.SpawnerEntity.Type == EntityType.ENTITY_FAMILIAR then
        return familiarLabel(entity.SpawnerEntity.Variant)
    end

    -- what a shot leaves behind outlives the shot and is its own hazard: the fire
    -- from a blast, the gas from it, the creep you walk out yourself
    if source.Type == EntityType.ENTITY_EFFECT then
        -- a flame outlives what lit it and is its own hazard, kept off the blast's
        -- row: Hot Bombs leaves one burning where the bomb went off, and it was
        -- reading as scenery. Only a flame nothing of ours owns stays plain Fire
        if source.Variant == EffectVariant.RED_CANDLE_FLAME then
            if source.SpawnerType == EntityType.ENTITY_BOMB then return "Bomb Fire" end
            if source.SpawnerType == EntityType.ENTITY_PLAYER then return "Red Candle" end
            return "Fire"
        end
        -- Ghost Pepper and The Candle throw the same blue one
        if source.Variant == EffectVariant.BLUE_FLAME then return "Blue Candle" end
        -- every colour of creep is one hazard on a damage board, and whose it is
        -- cannot be narrowed further: the pool Bob's Bladder leaves where a bomb
        -- went off names the player in every slot it has, bomb nowhere in the
        -- chain -- measured -- so it cannot stand apart the way the fire does
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
    -- a barrel you put there yourself: the one the room came with has no spawner
    -- and is dropped before reaching here, the same as any other scenery
    if source.Type == EntityType.ENTITY_MOVABLE_TNT then
        return "TNT"
    end
    if source.Type == EntityType.ENTITY_LASER then
        local subtype = entity ~= nil and entity.SubType or nil
        local beam = beamName(source.Variant, subtype)
        if beam ~= nil then return beam end
        logPlainLaser(owner, amount, "unknown variant " .. source.Variant, flags, victim)
        return "Laser"
    end
    if source.Type == EntityType.ENTITY_KNIFE then
        return KNIFE_LABELS[source.Variant] or heldWeapon(owner, MELEE_WEAPONS) or "Melee"
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

-- extraSource is REPENTOGON's sixth argument: the beam or blade behind a hit that
-- names only the player. Nil without REPENTOGON, and nil on hits it does not cover
function mod:onEntityTakeDamage(victim, amount, flags, source, countdownFrames, extraSource)
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

    local weapon = weaponOf(source, flags, amount, victim, extraSource)
    if weapon == nil then
        pcall(logDropped, source, flags)
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

    -- a shot that explodes still arrives as the shot, so its blast has to say so.
    -- Things that are an explosion to begin with -- a bomb, a barrel, a blast that
    -- names no shot at all -- would only be saying it twice.
    if flags & DamageFlag.DAMAGE_EXPLOSION ~= 0
        and source.Type ~= EntityType.ENTITY_BOMB
        and source.Type ~= EntityType.ENTITY_MOVABLE_TNT
        and source.Type ~= EntityType.ENTITY_PLAYER then
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
        -- development aid: sweep here rather than on a hit, so a beam whose damage
        -- never takes the laser path -- Holy Light's -- is still seen
        -- every beam, not only ones whose chain reaches a player: a beam with no
        -- owner is exactly what would stay invisible here and go unattributed.
        -- Effects too: Holy Light's light is one of those rather than a beam
        if entity.Type == EntityType.ENTITY_LASER or entity.Type == EntityType.ENTITY_EFFECT then
            pcall(logBeamKind, entity)
        end
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

