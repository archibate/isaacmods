-- Damage MVP -- PROBE BUILD (logging only, no gameplay effect)
--
-- Answers three open questions by measurement, not guessing:
--   1. Does a Brimstone / Tech X / Mom's Knife hit report the laser/knife entity
--      as its damage source, or does it collapse to ENTITY_PLAYER?
--   2. Is the damage amount handed to the callback before or after boss armor
--      scaling? (log line prints claimed amount vs. real HP lost one frame later)
--   3. Do burn/poison ticks still point back at the player who applied them?

local mod = RegisterMod("damagemvp", 1)

-- KnifeVariant only exists under REPENTOGON, so tolerate a missing enum
local function invert(enum)
    local names = {}
    if enum == nil then
        return names
    end
    for name, value in pairs(enum) do
        names[value] = name
    end
    return names
end

local ENTITY_TYPE_NAMES = invert(EntityType)
local TEAR_VARIANT_NAMES = invert(TearVariant)
local LASER_VARIANT_NAMES = invert(LaserVariant)
local BOMB_VARIANT_NAMES = invert(BombVariant)
local FAMILIAR_VARIANT_NAMES = invert(FamiliarVariant)
local EFFECT_VARIANT_NAMES = invert(EffectVariant)
local KNIFE_VARIANT_NAMES = invert(KnifeVariant)

-- variant namespace is per entity type, so pick the right table
local VARIANT_NAMES_BY_TYPE = {
    [EntityType.ENTITY_TEAR] = TEAR_VARIANT_NAMES,
    [EntityType.ENTITY_LASER] = LASER_VARIANT_NAMES,
    [EntityType.ENTITY_BOMB] = BOMB_VARIANT_NAMES,
    [EntityType.ENTITY_FAMILIAR] = FAMILIAR_VARIANT_NAMES,
    [EntityType.ENTITY_EFFECT] = EFFECT_VARIANT_NAMES,
    [EntityType.ENTITY_KNIFE] = KNIFE_VARIANT_NAMES,
}

local function describeType(entityType, variant)
    local typeName = ENTITY_TYPE_NAMES[entityType] or ("TYPE_" .. tostring(entityType))
    local variantNames = VARIANT_NAMES_BY_TYPE[entityType]
    local variantName = variantNames and variantNames[variant]
    if variantName then
        return typeName .. "/" .. variantName
    end
    return typeName .. "/" .. tostring(variant)
end

local DAMAGE_FLAG_NAMES = {}
for name, bit in pairs(DamageFlag) do
    DAMAGE_FLAG_NAMES[#DAMAGE_FLAG_NAMES + 1] = { name = name, bit = bit }
end
table.sort(DAMAGE_FLAG_NAMES, function(a, b) return a.bit < b.bit end)

local function describeFlags(flags)
    local set = {}
    for _, flag in ipairs(DAMAGE_FLAG_NAMES) do
        if flags & flag.bit ~= 0 then
            set[#set + 1] = flag.name
        end
    end
    if #set == 0 then
        return "-"
    end
    return table.concat(set, "|")
end

-- climb from the damaging entity up to the player that owns it
local function describeOwner(entity)
    local hops = {}
    local current = entity
    for _ = 1, 4 do
        if current == nil then break end
        local familiar = current:ToFamiliar()
        if familiar ~= nil and familiar.Player ~= nil then
            hops[#hops + 1] = "familiar.Player"
            current = familiar.Player
        elseif current.SpawnerEntity ~= nil then
            hops[#hops + 1] = "SpawnerEntity"
            current = current.SpawnerEntity
        elseif current.Parent ~= nil then
            hops[#hops + 1] = "Parent"
            current = current.Parent
        else
            break
        end
        if current:ToPlayer() ~= nil then
            return "player via " .. table.concat(hops, ">")
        end
    end
    if current == nil then
        return "owner=nil"
    end
    return "owner stops at " .. describeType(current.Type, current.Variant)
end

-- HitPoints is only decremented the frame AFTER the callback fires, so the real
-- HP lost has to be read back one update later.
local pending = {}

-- One line per DISTINCT source signature, otherwise a Brimstone run floods the log.
-- Bosses stay verbose: that is where boss-armor scaling shows up, and it needs
-- every single hit to be visible.
local seenSignatures = {}

function mod:onEntityTakeDamage(entity, amount, flags, source, countdownFrames)
    if entity:ToPlayer() ~= nil then return end
    if not entity:IsActiveEnemy(false) then return end

    local isBoss = entity:IsBoss()
    if not isBoss then
        local signature = string.format("%d.%d|%d.%d|%d",
            source.Type, source.Variant, source.SpawnerType, source.SpawnerVariant, flags)
        if seenSignatures[signature] then return end
        seenSignatures[signature] = true
    end

    local parts = {}
    parts[#parts + 1] = "[dmvp] hit " .. describeType(entity.Type, entity.Variant)
    parts[#parts + 1] = string.format("claims %.2f", amount)
    parts[#parts + 1] = "src=" .. describeType(source.Type, source.Variant)
    parts[#parts + 1] = "spawner=" .. describeType(source.SpawnerType, source.SpawnerVariant)

    if source.Entity ~= nil then
        parts[#parts + 1] = describeOwner(source.Entity)
    else
        parts[#parts + 1] = "src.Entity=nil"
    end

    parts[#parts + 1] = "flags=" .. describeFlags(flags)
    if countdownFrames ~= nil and countdownFrames > 0 then
        parts[#parts + 1] = "countdown=" .. tostring(countdownFrames)
    end

    pending[#pending + 1] = {
        ptr = EntityPtr(entity),
        hitPointsBefore = entity.HitPoints,
        frame = Game():GetFrameCount(),
        line = table.concat(parts, " "),
    }

    -- observer only: never swallow the hit, and never block later mods' callbacks
    return nil
end

function mod:onPostUpdate()
    if #pending == 0 then return end

    local frame = Game():GetFrameCount()
    local stillWaiting = {}

    for _, hit in ipairs(pending) do
        if hit.frame >= frame then
            stillWaiting[#stillWaiting + 1] = hit
        else
            local entity = hit.ptr.Ref
            if entity == nil or entity:IsDead() then
                -- overkill: HP lost is unknowable, the hit only had this much left to take
                print(hit.line .. string.format(" | KILLED (had %.2f hp)", hit.hitPointsBefore))
            else
                local realLoss = hit.hitPointsBefore - entity.HitPoints
                print(hit.line .. string.format(" | real %.2f (hp %.2f left)", realLoss, entity.HitPoints))
            end
        end
    end

    pending = stillWaiting
end

mod:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.LATE, mod.onEntityTakeDamage)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.onPostUpdate)

-- console: lua dmvpreset()  -- forget seen signatures, log every source kind again
function _G.dmvpreset()
    seenSignatures = {}
    print("[dmvp] signatures reset")
end

print("[dmvp] damage probe loaded")
