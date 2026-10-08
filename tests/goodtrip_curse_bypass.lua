-- Run from the workspace root: lua tests/goodtrip_curse_bypass.lua
-- Game enum values come from isaac-lua-api/vanilla/enums.lua.
local room_type = {ROOM_DEFAULT = 1, ROOM_SECRET = 7, ROOM_CURSE = 10}
local env = setmetatable({
    RoomType = room_type,
    SFXManager = function() return {} end,
}, {__index = _G})
local new_rules = assert(loadfile("goodtripfixed/scripts/rules.lua", "t", env))()
local new_trip = assert(loadfile("goodtripfixed/scripts/trip.lua", "t", env))()
local count = 0
local function equal(actual, expected, name)
    assert(actual == expected, name .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    count = count + 1
end

local function fixture(edges)
    local rooms, graph = {}, {}
    -- C=curse, S=secret, N=normal exit, D=destination, X=another curse, T=another secret.
    local ids = {C = 71, S = 72, N = 85, D = 86, X = 58, T = 70}
    for name, id in pairs(ids) do
        local kind = (name == "C" or name == "X") and room_type.ROOM_CURSE
            or ((name == "S" or name == "T") and room_type.ROOM_SECRET or room_type.ROOM_DEFAULT)
        rooms[id] = {SafeGridIndex = id, GridIndex = id, ListIndex = id,
            Data = {Type = kind}, VisitedCount = 1, Clear = true}
    end
    for _, edge in ipairs(edges) do
        local a, b = ids[edge:sub(1, 1)], ids[edge:sub(2, 2)]
        graph[a], graph[b] = graph[a] or {}, graph[b] or {}
        graph[a][b], graph[b][a] = 0, true --slot zero and reverse-end marker are both passages
    end
    local player = {
        HasCollectible = function() return false end,
        HasTrinket = function() return false end,
        IsFlying = function() return false end,
    }
    local floor = {
        grid_room = rooms, crd = rooms[ids.C], crid = ids.C, crsid = ids.C, player = player,
        secret_pre_room_id = {}, curse_bare_inside = {}, curse_bare_outside = {},
        sweep_doors = function() end,
        door_graph = function() return graph end,
        linked = function() error("unknown adjacency must not prove a safe passage") end,
    }
    local deps = {gt = {}, cfg = {}, floor = floor}
    local rules = new_rules(deps)
    return rules, floor, graph, ids
end

local cases = {
    {"opened safe route", {"CS", "SN", "ND"}, true},
    {"unopened first secret wall", {"SN", "ND", "CD"}, false},
    {"unopened second secret wall", {"CS", "ND", "CD"}, false},
    {"dead-end secret room", {"CS", "CD"}, false},
    {"unrelated safe outlet cannot reach destination", {"CS", "SN", "CD"}, false},
    {"another curse blocks the onward route", {"CS", "SX", "XD"}, false},
    {"second secret provides the safe route", {"CS", "CT", "TN", "ND"}, true},
    {"secret holes on both sides of another curse are free", {"CS", "SX", "XT", "TD"}, true},
    {"cycle cannot create a route", {"CS", "SN", "NT", "TS", "CD"}, false},
}
for _, case in ipairs(cases) do
    local rules, _, _, ids = fixture(case[2])
    equal(rules.has_curse_bypass(ids.C, ids.D), case[3], case[1])
end

do
    local rules, floor, graph, ids = fixture({"CS", "SN", "ND"})
    floor.grid_room[ids.S].Clear = false
    equal(rules.has_curse_bypass(ids.C, ids.D), false, "uncleared secret cannot be crossed")
    floor.grid_room[ids.S].Clear = true
    floor.grid_room[ids.N].VisitedCount = 0
    equal(rules.has_curse_bypass(ids.C, ids.D), false, "unvisited intermediate room cannot be crossed")
    floor.grid_room[ids.N].VisitedCount = 1
    floor.grid_room[ids.D].VisitedCount, floor.grid_room[ids.D].Clear = 0, false
    equal(rules.has_curse_bypass(ids.C, ids.D), true, "eligible uncleared destination is not transit")
    floor.grid_room[99] = floor.grid_room[ids.C]
    equal(rules.has_curse_bypass(99, ids.D), true, "room aliases use safe grid indices")
    graph[ids.N][100] = true
    equal(rules.has_curse_bypass(ids.C, 100), false, "missing destination descriptor")
    equal(rules.has_curse_bypass(ids.C, ids.D), true, "missing neighbor descriptor is skipped")
    floor.door_graph = function() return {} end
    floor.secret_pre_room_id[ids.C], floor.secret_pre_room_id[ids.S] = ids.S, ids.N
    equal(rules.has_curse_bypass(ids.C, ids.D), false, "stale antechamber data cannot bridge dimensions")
end

for _, arrive in ipairs({false, true}) do
    local _, floor, graph, ids = fixture({"CS", "SN", "ND", "CD"})
    local damage = 0
    -- The toll must be independent of landing configuration.
    local cfg = {ArriveAtDoor = arrive}
    local deps = {gt = {}, cfg = cfg, floor = floor}
    deps.rules = new_rules(deps)
    local trip = new_trip(deps)
    trip.hurt = function(n) damage = damage + n end
    trip.check_curse_room(ids.D)
    equal(damage, 0, "safe curse exit")
    floor.crd, floor.crid, floor.crsid = floor.grid_room[ids.D], ids.D, ids.D
    trip.check_curse_room(ids.C)
    equal(damage, 0, "safe curse entry")
    graph[ids.S][ids.N], graph[ids.N][ids.S] = nil, nil
    trip.check_curse_room(ids.C)
    equal(damage, 1, "entry still pays without bypass")
    floor.player.IsFlying = function() return true end
    trip.check_curse_room(ids.C)
    equal(damage, 1, "flying entry remains free")
    floor.crd, floor.crid, floor.crsid = floor.grid_room[ids.C], ids.C, ids.C
    trip.check_curse_room(ids.D)
    equal(damage, 2, "flying exit still pays without bypass")
    floor.curse_bare_inside[ids.C] = true
    trip.check_curse_room(ids.D)
    equal(damage, 2, "bare door remains free")
end
print("ok: " .. count .. " curse-room regression checks")
