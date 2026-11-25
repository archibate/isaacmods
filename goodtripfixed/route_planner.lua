local RoutePlanner = {}

function RoutePlanner.door_damage(from, to, secret, traveller)
    if secret or traveller.protected then return 0 end
    if from.curse or (to.curse and not traveller.flying) then return 1 end
    return 0
end

local function costs_less(damage, distance, other)
    return not other or damage < other.damage
        or (damage == other.damage and distance < other.distance)
end

function RoutePlanner.find(rooms, source, target, traveller, require_visible_neighbor)
    if not rooms[source] or not rooms[target] then return nil end
    local best = {[source] = {damage = 0, distance = 0}}
    local frontier = {[source] = true}
    while next(frontier) do
        local current, cost
        for id in pairs(frontier) do
            local candidate = best[id]
            if costs_less(candidate.damage, candidate.distance, cost)
                or (candidate.damage == cost.damage and candidate.distance == cost.distance and id < current) then
                current, cost = id, candidate
            end
        end
        if current == target then
            local path = {}
            local room_id = target
            while room_id do
                path[best[room_id].distance + 1] = room_id
                room_id = best[room_id].previous
            end
            return {path = path, damage = cost.damage, distance = cost.distance}
        end

        frontier[current] = nil
        local room = rooms[current]
        for neighbor, secret in pairs(room.doors) do
            local next_room = rooms[neighbor]
            local can_enter = neighbor == target and (not require_visible_neighbor or room.visible)
                or neighbor ~= target and next_room.pass_through
            if can_enter then
                local damage = cost.damage + RoutePlanner.door_damage(room, next_room, secret, traveller)
                local distance = cost.distance + 1
                if costs_less(damage, distance, best[neighbor]) then
                    best[neighbor] = {damage = damage, distance = distance, previous = current}
                    frontier[neighbor] = true
                end
            end
        end
    end
end

return RoutePlanner
