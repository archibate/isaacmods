local DoorGraph = {}

local function room_key(desc)
    return desc.SafeGridIndex .. ":" .. desc.ListIndex .. ":" .. desc.SpawnSeed
end

local function is_secret(room_type)
    return room_type == RoomType.ROOM_SECRET or room_type == RoomType.ROOM_SUPERSECRET
        or room_type == RoomType.ROOM_ULTRASECRET
end

local function remember(history, source, target, open)
    history[source] = history[source] or {}
    history[target] = history[target] or {}
    history[source][target] = open
    history[target][source] = open
end

function DoorGraph.observe(room, source, cells, history)
    local source_key = room_key(source)
    local observed, live = {}, {}
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        local target = door and cells[door.TargetRoomIndex]
        if target and source.ListIndex ~= target.ListIndex then
            local target_key = room_key(target)
            local state = observed[target_key] or {target = target}
            observed[target_key] = state
            local variant = door.Desc.Variant
            state.revealed = state.revealed or variant == DoorVariant.DOOR_UNLOCKED
            if variant ~= DoorVariant.DOOR_HIDDEN and door:IsOpen() then
                state.open = true
                live[target.SafeGridIndex] = true
            end
        end
    end

    for target_key, state in pairs(observed) do
        local secret = is_secret(source.Data.Type) or is_secret(state.target.Data.Type)
        if state.open then
            remember(history, source_key, target_key, true)
        elseif (secret and not state.revealed) or (not secret and source.Clear) then
            remember(history, source_key, target_key, false)
        end
    end
    for target_key, open in pairs(history[source_key] or {}) do
        if open and not observed[target_key] then remember(history, source_key, target_key, false) end
    end
    return live
end

local function connect(rooms, left, right)
    local secret = rooms[left].secret or rooms[right].secret
    rooms[left].doors[right] = secret
    rooms[right].doors[left] = secret
end

function DoorGraph.build(cells, source, live, history)
    local rooms, keys, ids, layout = {}, {}, {}, {}
    for _, desc in pairs(cells) do
        local id = desc.SafeGridIndex
        if not rooms[id] then
            rooms[id] = {
                doors = {},
                visible = (desc.DisplayFlags & 1) ~= 0,
                pass_through = desc.VisitedCount > 0 and desc.Clear,
                curse = desc.Data.Type == RoomType.ROOM_CURSE,
                secret = is_secret(desc.Data.Type),
            }
            local key = room_key(desc)
            keys[id], ids[key] = key, id
            local allowed = desc.AllowedDoors
            if not rooms[id].secret and allowed ~= 0 then
                local neighbors = {}
                layout[id] = neighbors
                for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
                    if (allowed & (1 << slot)) ~= 0 then
                        local target = cells[desc.Doors[slot]]
                        if target then neighbors[target.SafeGridIndex] = true end
                    end
                end
            end
        end
    end

    -- Unloaded ordinary doors need reciprocal layout records. Hidden walls
    -- may have layout neighbors long before the player opens a passage.
    for id, neighbors in pairs(layout) do
        if id ~= source then
            local known = history[keys[id]] or {}
            for neighbor in pairs(neighbors) do
                if neighbor > id and neighbor ~= source and layout[neighbor] and layout[neighbor][id]
                    and known[keys[neighbor]] ~= false then
                    connect(rooms, id, neighbor)
                end
            end
        end
    end
    for key, known in pairs(history) do
        local id = ids[key]
        if id and id ~= source then
            for target_key, open in pairs(known) do
                local neighbor = ids[target_key]
                if open and neighbor and neighbor > id and neighbor ~= source then
                    connect(rooms, id, neighbor)
                end
            end
        end
    end
    if rooms[source] then
        for neighbor in pairs(live) do
            if rooms[neighbor] then connect(rooms, source, neighbor) end
        end
    end
    return rooms
end

return DoorGraph
