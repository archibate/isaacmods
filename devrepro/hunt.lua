-- the floor shape a wrong-wall landing needs, found from the grid alone, so the
-- driver can reseed until one turns up and a plain lua can test the search on a
-- dumped floor. cells: cell -> { safe, list, type, shape }; start: the start cell.
--
-- The game's own landing, read off every arrival logged so far: the wall of the
-- target cell that faces the room the trip starts in, by the axis with the larger
-- grid distance, a tie going to the row; it takes that wall's door even into an
-- unbombed secret room; with no door on that wall, the lowest door slot there is.
-- The mod's landing wants the door the walk would have come in by. So: T, a
-- plain 1x1 room not next to the start, walked to through P on one side, while
-- the game's pick for T is a door on another side
return function(cells, start)
    local OFF = { [0] = -1, -13, 1, 13 } -- side -> grid step toward it
    local function step(c, side)
        local off = OFF[side]
        local col = c % 13
        if (off == -1 and col == 0) or (off == 1 and col == 12) then return nil end
        return cells[c + off] and (c + off) or nil
    end
    local function plain(d) return d.type == 1 end

    -- rooms by list index, each with its cells and the rooms touching it
    local rooms = {}
    for c, d in pairs(cells) do
        local r = rooms[d.list]
        if not r then
            r = { list = d.list, d = d, cells = {}, touch = {} }
            rooms[d.list] = r
        end
        r.cells[#r.cells + 1] = c
    end
    for _, r in pairs(rooms) do
        for _, c in ipairs(r.cells) do
            for side = 0, 3 do
                local n = step(c, side)
                if n and cells[n].list ~= r.list then
                    r.touch[cells[n].list] = true
                end
            end
        end
    end
    local function count(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end
    -- is there a door slot from plain room a into room b? true, false, or "?"
    -- when the grid cannot tell (a special room touching several rooms opens on
    -- one of them; a super secret room likewise; red rooms have no slot at all)
    local function door(a, b)
        if plain(b.d) or b.d.type == 7 then return true end
        if b.d.type == 8 or b.d.type == 29 then return "?" end
        if count(b.touch) == 1 then return true end
        return "?"
    end
    -- room-level flood from the start through plain rooms, keeping out of `avoid`
    local start_room = rooms[cells[start].list]
    local function flood(avoid)
        local parent, depth = { [start_room.list] = start_room.list }, { [start_room.list] = 0 }
        local queue, head = { start_room }, 1
        while queue[head] do
            local cur = queue[head]
            head = head + 1
            for l in pairs(cur.touch) do
                local r = rooms[l]
                if plain(r.d) and not parent[l] and not avoid[l] then
                    parent[l], depth[l] = cur.list, depth[cur.list] + 1
                    queue[#queue + 1] = r
                end
            end
        end
        return parent, depth
    end
    local function facing(from, to)
        local function side(d, neg, pos)
            if d < 0 then return neg elseif d > 0 then return pos end
        end
        local dcol = from % 13 - to % 13
        local drow = (from - from % 13) / 13 - (to - to % 13) / 13
        local tie = math.abs(drow) == math.abs(dcol)
        if math.abs(drow) >= math.abs(dcol) then return side(drow, 1, 3), tie end
        return side(dcol, 0, 2), tie
    end
    -- the game's pick for a 1x1 target: side, and whether it took the facing wall
    -- or fell back to the lowest slot. nil when the grid cannot say
    local function game_pick(t)
        local tr = rooms[cells[t].list]
        local face, tie = facing(start, t)
        local doors = {}
        for side = 0, 3 do
            local n = step(t, side)
            doors[side] = n and door(tr, rooms[cells[n].list]) or false
        end
        if doors[face] == "?" then return nil end
        if doors[face] then return face, tie, true end
        for side = 0, 3 do
            if doors[side] == "?" then return nil end
            if doors[side] then return side, tie, false end
        end
        return nil
    end

    local best = nil
    for t, td in pairs(cells) do
        local tr = rooms[td.list]
        if plain(td) and td.shape == 1 and tr ~= start_room and not tr.touch[start_room.list] then
            local pick, tie, on_face = game_pick(t)
            if pick then
                -- the walk keeps out of T and of a plain room behind the picked
                -- door, so the route cannot come in by that door
                local avoid = { [tr.list] = true }
                local behind = step(t, pick)
                if behind and plain(cells[behind]) then avoid[cells[behind].list] = true end
                local parent, depth = flood(avoid)
                for side = 0, 3 do
                    local pc = side ~= pick and step(t, side)
                    local pr = pc and rooms[cells[pc].list]
                    if pr and plain(pr.d) and depth[pr.list] then
                        -- the route door: the walked room next to T nearest the start
                        local path, cur = {}, pr.list
                        while cur ~= start_room.list do
                            table.insert(path, 1, cur)
                            cur = parent[cur]
                        end
                        local entry = nil
                        for _, l in ipairs(path) do
                            for s = 0, 3 do
                                local n = step(t, s)
                                if n and cells[n].list == l and entry == nil then entry = s end
                            end
                            if entry then break end
                        end
                        if entry and entry ~= pick then
                            local score = #path + (tie and 20 or 0) + (on_face and 0 or 50)
                            if best == nil or score < best.score then
                                best = { score = score, t = t, path = path, entry = entry, pick = pick,
                                         tie = tie, on_face = on_face }
                            end
                        end
                    end
                end
            end
        end
    end
    if not best then return nil end
    local walk = {}
    for _, l in ipairs(best.path) do walk[#walk + 1] = rooms[l].d.safe end
    return {
        walk = walk, target = best.t, entry = best.entry, pick = best.pick, tie = best.tie,
        on_face = best.on_face, start = start,
    }
end
