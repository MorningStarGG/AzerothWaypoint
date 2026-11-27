-- ============================================================
-- Polestar routing backend
-- ============================================================
--
-- Adapts Polestar's travel graph, path measurements and terrain walks to AWP
-- route planning and progression.

local NS = _G.AzerothWaypointNS
local P = NS.Internal.PolestarPresentation
local backend = {
    id = "polestar",
    preserveItinerary = true,
    handlesDestinationAreaProgress = true,
    counters = { searches = 0, cancelled = 0, stale = 0, reused = 0, failed = 0, stages = 0, expanded = 0 }
}
NS.RoutingBackend_Polestar = backend
local states = setmetatable({}, { __mode = "k" })
local measures, measureOrder = {}, {}
local pendingMeasure
local measuredState
local graphEpoch, graphFingerprint = 0, nil
local hookedGraphs = setmetatable({}, { __mode = "k" })
local walkingFlags = { "nav.travel", "nav.teleports", "nav.navRouting", "nav.routeStyle" }

local function Combat() return InCombatLockdown() == true end
local function Runtime() return NS.Internal.PolestarProvider.GetRuntime() end
local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) end
local function Finite(v) return not Secret(v) and type(v) == "number" and v == v and math.abs(v) < math.huge end
local function Ready(start, duration)
    if Secret(start) or Secret(duration) or not Finite(start) or not Finite(duration) then return nil end
    return start <= 0 or duration <= 1.5 or start + duration <= GetTime()
end

local function TeleportReady(action)
    if not Finite(action.ready) then return nil end
    -- Compat can replace an inaccessible cooldown with zero. Do not turn
    -- that substitute into a claim that an AWP travel action is ready.
    if C_Spell and type(C_Spell.GetSpellCooldown) == "function" then
        local ok, cooldown = pcall(C_Spell.GetSpellCooldown, action.spell)
        if not ok or type(cooldown) ~= "table" or not Finite(cooldown.startTime) or not Finite(cooldown.duration) then return nil end
    end
    return action.ready
end

local function CopyScalars(values)
    if type(values) ~= "table" then return nil end
    local copy = {}
    for key, value in pairs(values) do
        if type(value) == "number" or type(value) == "boolean" or type(value) == "string" then copy[key] = value end
    end
    return copy
end

local function PortalItems(r)
    local travel = r.Nav.travel
    if type(travel) ~= "table" or type(travel.PortalItems) ~= "function" then return false end
    local ok, values = pcall(travel.PortalItems)
    if not ok or values ~= nil and type(values) ~= "table" then return false end
    local copy
    for id, present in pairs(values or {}) do
        if not Finite(id) or Secret(present) then return false end
        if present == true then
            copy = copy or {}; copy[id] = true
        end
    end
    return true, copy
end

function backend.IsAvailable()
    local r = Runtime()
    return r ~= nil and type(r.Get) == "function" and type(r.Nav) == "table" and type(r.Nav.PlanRoute) == "function"
        and type(r.Nav.GetTravelData) == "function" and type(r.Compat) == "table"
        and type(r.Compat.MapToWorld) == "function" and type(r.Compat.WorldToMap) == "function"
        and type(r.Nav.walk) == "table" and type(r.Nav.walk.Floor) == "function"
        and type(r.Nav.walk.Floors) == "function"
end

local function Path(r)
    if not P.Call(r, "Get", "nav.navRouting") then return nil end
    local path = rawget(_G, "Polestar_NavEngine")
    if not path and not Combat() then
        P.Call(r.Data, "Pack", "Polestar_Nav")
        path = rawget(_G, "Polestar_NavEngine")
    end
    if type(path) == "table" and type(path.Find) == "function" and type(path.Cancel) == "function" then return path end
end

local Walking = NS.Internal.RouteWalking
local WALK_RECOVERY = { interval = 2, retrySeconds = 15, retryDistance = 5 }
local WALK_BUDGET_HOLD = 60

local function ClearWalkBudget(state)
    local hold = state and state.walkBudget
    if not hold then return end
    state.walkBudget = nil
    if hold.timer then hold.timer:Cancel() end
end

local function CancelWalk(s, keepRecovery)
    local job, path = s and s.job, s and s.path
    -- Retire ownership before calling native code: cancellation may deliver
    -- its completion callback synchronously.
    if s then s.job, s.token = nil, nil end
    if not keepRecovery then Walking.CancelRecovery(s) end
    if job then
        pcall(path.Cancel, job)
        backend.counters.cancelled = backend.counters.cancelled + 1
    end
end

local function InvalidateWalkingGeometry(record, state)
    CancelWalk(state)
    ClearWalkBudget(state)
    state.pathTried, state.owed = nil, state.walking == true
    for _, leg in ipairs(record.legs or {}) do
        -- Recheck an unmapped tail only when its policy or data changes.
        if leg.polestarApproach then leg.polestarApproachRetry = true end
    end
end

local function Current(record, state)
    return states[record] == state and record.backend == "polestar"
        and NS.IsRoutingEnabled()
        and record.legs ~= nil and record._routeAcceptedPlanGeneration == state.generation
        and NS.IsActiveRouteRecord(record, false)
end

local function Coord(r, point)
    if type(point) ~= "table" then return nil end
    local map = point.map
    local x, y
    if point.c and point.wx and point.wy and map then
        x, y = P.Call(r.Compat, "WorldToMap", point.c, point.wx, point.wy, map)
        if not Finite(x) or not Finite(y) or x < 0 or x > 100 or y < 0 or y > 100 then
            local playerMap = NS.GetPlayerMapID()
            local px, py = P.Call(r.Compat, "WorldToMap", point.c, point.wx, point.wy, playerMap)
            if Finite(px) and Finite(py) and px >= 0 and px <= 100 and py >= 0 and py <= 100 then
                return playerMap,
                    px / 100, py / 100
            end
            for _ = 1, 16 do
                local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
                map = info and info.parentMapID
                if not map or map == 0 then return end
                x, y = P.Call(r.Compat, "WorldToMap", point.c, point.wx, point.wy, map)
                if Finite(x) and Finite(y) and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
                    return map, x / 100,
                        y / 100
                end
            end
        end
    else
        local m, fx, fy = P.Coordinates(r, point)
        return m, fx, fy
    end
    if not Finite(x) or not Finite(y) or x < 0 or x > 100 or y < 0 or y > 100 then return nil end
    return map, x / 100, y / 100
end

local function Point(point)
    if type(point) ~= "table" then return nil end
    return {
        c = point.c,
        wx = point.wx,
        wy = point.wy,
        map = point.map,
        x = point.x,
        y = point.y,
        f = point.f,
        z = point.z,
        id = point.id,
        name = point.name,
        area = point.area
    }
end

-- ============================================================
-- Walking geometry and graph identity
-- ============================================================

local function GeometryKey(point)
    if not point then return "-" end
    return table.concat({ tostring(point.c), tostring(point.wx), tostring(point.wy), tostring(point.z) }, "/")
end

-- These native queries describe the player's physical floor, they do not aim,
-- advance or replace Polestar's trip. Unknown is an answer, not permission to
-- substitute a guessed surface. Mutable candidate tables never leave the read.
local function NativeFloor(r, c, x, y)
    local walk = r.Nav and r.Nav.walk
    if type(walk) ~= "table" or type(walk.Floor) ~= "function" then return false end
    local z = P.Call(walk, "Floor", c, x, y)
    local candidates = not Finite(z) and P.Call(walk, "Floors", c, x, y)
    local floors
    if type(candidates) == "table" then
        floors = {}
        for i = 1, math.min(#candidates, 64) do
            if Finite(candidates[i]) then floors[#floors + 1] = candidates[i] end
        end
        if #floors == 0 then floors = nil end
    end
    return true, Finite(z) and z or nil, floors
end

local function LiveTaxiOffer(r, c, x, y, z, faction)
    local window = NS.Internal.TaxiWindow
    local frame = window and window.GetOpenFrame()
    local serial = frame and window.GetOpenSerial(frame)
    if not serial or not Finite(z) or Combat() then return end
    local offer = P.Call(r.Nav.travel, "BoardingAt", c, x, y, z, faction)
    if type(offer) ~= "table" or type(offer.node) ~= "table" or type(offer.reachable) ~= "table" then return end
    local snapshot = window.GetSnapshot(frame)
    if not snapshot or snapshot.mapID ~= offer.map or snapshot.sourceNodeID ~= offer.node.id then return end
    return offer, serial, snapshot
end

local function TaxiOfferKey(offer, serial)
    if not offer then return end
    local ids = {}
    for id, reachable in pairs(offer.reachable) do
        if reachable and Finite(id) then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return table.concat({ serial, offer.map, offer.node.id, table.concat(ids, ",") }, ":")
end

local function TravelContext(r, mapID, x, y, title, record)
    local validItems, items = PortalItems(r)
    if not validItems then return nil end
    local c, wx, wy = P.Call(r.Compat, "GetPlayerWorldPosition")
    local tc, tx, ty = P.Call(r.Compat, "MapToWorld", mapID, x * 100, y * 100)
    if not c or not tc or not Finite(wx) or not Finite(wy) or not Finite(tx) or not Finite(ty) then return nil end
    local faction = P.Call(r.Compat, "GetPlayerFaction")
    local ghost = UnitIsGhost and UnitIsGhost("player") == true
    local timed = P.Call(r.Compat, "QuestTimerRunning") == true
    local escort = P.Call(r.Engine, "EscortRunning") == true
    local context = {
        c = c,
        wx = wx,
        wy = wy,
        map = NS.GetPlayerMapID(),
        target = { c = tc, wx = tx, wy = ty, map = mapID, x = x * 100, y = y * 100, label = title },
        faction = faction == "Alliance" and 1 or faction == "Horde" and 2 or 0,
        factionName = faction,
        _style = P.Call(r, "Get", "nav.routeStyle"),
        _escort = escort,
        _timed = timed,
        known = CopyScalars(P.Call(r.Nav, "GetKnownTaxiNodes")) or {},
        seen = CopyScalars(P.Call(r.Nav, "GetTaxiSeen")) or {},
        items = items,
        level = UnitLevel("player"),
        maybe = function(node) return P.Call(r.Nav, "TaxiMaybe", node.id) == true end,
        speed = 7,
        walkOnly = ghost or escort,
        places = {}
    }
    local _, _, z, instance = P.Call(r.Compat, "GetPlayerUnitPosition")
    if instance == c and Finite(z) and z ~= 0 then
        context.z, context.clientZ = z, z
    end
    if context.z == nil and not Combat() then
        local _, floor, floors = NativeFloor(r, c, wx, wy)
        context.z, context.floors = floor, floors
    end
    if not context.walkOnly then
        context.taxiOffer, context.taxiSerial, context.taxiWindow = LiveTaxiOffer(r, c, wx, wy,
            context.z, context.faction)
        context.liveTaxi = context.taxiOffer ~= nil
    end
    local height, continent = NS.RouteSpecials.GetNavigationHeight(record)
    if continent == tc then context.target.z = height end
    if not ghost and not timed and not escort and not Combat() then
        local boundInn = Point(P.Call(r.Nav, "BoundInn"))
        local count = P.Call(r.Compat, "GetItemCount", 6948)
        local fn = C_Item and C_Item.GetItemCooldown or C_Container and C_Container.GetItemCooldown
        local ok, start, duration = false, nil, nil
        if fn then ok, start, duration = pcall(fn, 6948) end
        if count and not Secret(count) and count > 0 and ok and Ready(start, duration) then
            context.hearth = boundInn
            context.hearthName = P.Call(r.Compat, "GetBindLocation")
            context.hearthLength = P.Call(r.Compat, "GetItemBaseCooldown", 6948)
        end
        context.noStone = context.hearth == nil
        local list = P.Call(r.Transit, "Teleports")
        if type(list) == "table" then
            context.teleports = {}
            for _, action in ipairs(list) do
                local ready = TeleportReady(action)
                if ready then
                    local to = action.bind and boundInn or action.to
                    if to then
                        if action.bind then
                            context.hearth = boundInn
                            context.hearthName = P.Call(r.Compat, "GetBindLocation")
                        end
                        context.teleports[#context.teleports + 1] = {
                            spell = action.spell,
                            name = action.name,
                            to = Point(to),
                            cast = action.cast,
                            ready = ready,
                            bind = action.bind == true,
                            length = Finite(action.length) and action.length or nil,
                        }
                    end
                end
            end
        end
    end
    local now = P.Call(r.Transit, "Now")
    if now then
        context.departure = function(t, side, after)
            return P.Call(r.Transit, "NextDeparture", t.kind, t.id, now + after, side)
        end
    end
    local danger = r.Nav.danger
    local level = P.Call(danger, "Level")
    context._danger = CopyScalars(P.Call(danger, "Table", level,
        P.Call(danger, "ZoneAt", c, wx, wy), P.Call(danger, "ZoneAt", tc, tx, ty)))
    if P.Call(r, "Get", "nav.navRouting") and context._danger then
        context.walkDanger = function(continent, x1, y1, x2, y2)
            return P.Call(danger, "Along", context._danger, continent, x1, y1, x2, y2)
        end
    end
    return context
end

local function GraphFingerprint(data)
    if graphFingerprint then return graphFingerprint end
    local parts = { tostring(data.build), tostring(graphEpoch) }
    local keys = { "id", "kind", "npc", "class", "faction", "item", "map", "wx", "wy", "z", "ab", "ba", "waitA", "waitB",
        "seconds" }
    local function point(node)
        for _, key in ipairs(keys) do parts[#parts + 1] = tostring(node and node[key]) end
    end
    for _, kind in ipairs({ "taxi", "transports", "portals", "inns" }) do
        parts[#parts + 1] = kind
        for _, node in ipairs(data[kind] or {}) do
            point(node); point(node.a); point(node.b)
        end
    end
    local ids = {}
    for id in pairs(data.flights or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id)
        for _, value in ipairs(data.flights[id]) do parts[#parts + 1] = tostring(value) end
    end
    local hash = 5381
    for _, text in ipairs(parts) do
        for i = 1, #text do hash = (hash * 33 + string.byte(text, i)) % 2147483647 end
        hash = (hash * 33 + 31) % 2147483647
    end
    graphFingerprint = tostring(hash) .. ":" .. #parts .. ":" .. graphEpoch
    return graphFingerprint
end

-- ============================================================
-- Travel state and planner options
-- ============================================================

local function Snapshot(record)
    if Combat() then return false end
    local r = Runtime()
    if not backend.IsAvailable() then return false end
    local parts = {}
    for _, key in ipairs(walkingFlags) do parts[#parts + 1] = tostring(P.Call(r, "Get", key)) end
    local data = P.Call(r.Nav, "GetTravelData")
    if type(data) ~= "table" then return false end
    parts[#parts + 1] = GraphFingerprint(data)
    -- Only item-gated portal membership matters, not unrelated bag counts.
    local validItems, items = PortalItems(r)
    if not validItems then return false end
    local itemIDs = {}
    for id, present in pairs(items or {}) do
        if Secret(id) or Secret(present) then return false end
        if present == true then itemIDs[#itemIDs + 1] = id end
    end
    table.sort(itemIDs)
    for _, id in ipairs(itemIDs) do parts[#parts + 1] = "portal_item:" .. id end
    local known = P.Call(r.Nav, "GetKnownTaxiNodes")
    if type(known) ~= "table" then return false end
    local ids = {}
    for id, usable in pairs(known or {}) do if usable then ids[#ids + 1] = id end end
    table.sort(ids)
    for _, id in ipairs(ids) do parts[#parts + 1] = "taxi:" .. id end
    local seen = P.Call(r.Nav, "GetTaxiSeen")
    if type(seen) ~= "table" then return false end
    local continents = {}
    for id, visited in pairs(seen) do if visited then continents[#continents + 1] = id end end
    table.sort(continents)
    for _, id in ipairs(continents) do parts[#parts + 1] = "seen:" .. id end
    local key
    local state = states[record]
    local leg = record and record.currentLeg
    if state and leg and leg.taxi and leg.taxi.offerSerial
        and (state.boardedTaxiLeg == leg or P.Call(r.Compat, "IsOnTaxi") == true) then
        key = state.taxiOfferKey
    elseif NS.Internal.TaxiWindow and NS.Internal.TaxiWindow.GetOpenFrame()
        and not (UnitIsGhost and UnitIsGhost("player")) and not P.Call(r.Engine, "EscortRunning") then
        local x, y, z, continent = P.Call(r.Compat, "GetPlayerUnitPosition")
        local faction = P.Call(r.Compat, "GetPlayerFaction")
        local offer, serial = LiveTaxiOffer(r, continent, x, y, z,
            faction == "Alliance" and 1 or faction == "Horde" and 2 or 0)
        key = TaxiOfferKey(offer, serial)
    end
    if key then parts[#parts + 1] = "offer:" .. key end
    parts[#parts + 1] = tostring(P.Call(r.Compat, "GetBindLocation"))
    parts[#parts + 1] = GeometryKey(P.Call(r.Nav, "BoundInn"))
    parts[#parts + 1] = tostring(UnitLevel("player"))
    parts[#parts + 1] = tostring(UnitIsGhost and UnitIsGhost("player"))
    parts[#parts + 1] = tostring(P.Call(r.Compat, "QuestTimerRunning"))
    parts[#parts + 1] = tostring(P.Call(r.Engine, "EscortRunning"))
    local list = P.Call(r.Transit, "Teleports")
    if P.Call(r, "Get", "nav.teleports") and not list then return false end
    if list ~= nil and type(list) ~= "table" then return false end
    for _, spell in ipairs(list or {}) do
        if type(spell) ~= "table" then return false end
        local ready = TeleportReady(spell)
        if ready == nil then return false end
        if Secret(spell.length) then return false end
        parts[#parts + 1] = tostring(spell.spell) .. ":" .. tostring(ready <= 0)
        parts[#parts + 1] = tostring(spell.bind == true) .. ":" .. tostring(spell.length)
        parts[#parts + 1] = GeometryKey(spell.to)
    end
    local count = P.Call(r.Compat, "GetItemCount", 6948)
    local fn = C_Item and C_Item.GetItemCooldown or C_Container and C_Container.GetItemCooldown
    if fn then
        local ok, start, duration = pcall(fn, 6948)
        local ready = ok and Ready(start, duration)
        if ready == nil or not ok or Secret(count) then return false end
        parts[#parts + 1] = tostring(count) .. ":" .. tostring(ready)
    end
    return true, table.concat(parts, "|")
end

local function Options(r, context)
    return {
        waterWalking = context.walkOnly == true,
        profile = P.Call(r.Compat, "GetPlayerFaction"),
        style = P.Call(r, "Get", "nav.routeStyle"),
        danger = P.Call(r.Nav.danger, "Table", P.Call(r.Nav.danger, "Level") or context.level,
            P.Call(r.Nav.danger, "ZoneAt", context.c, context.wx, context.wy),
            P.Call(r.Nav.danger, "ZoneAt", context.target.c, context.target.wx, context.target.wy)),
        walkLevel = P.Call(r.Nav.danger, "Level") or context.level or 0,
    }
end

local function MeasureKey(r, context, options)
    options = options or Options(r, context)
    local danger = {}
    for key, value in pairs(options.danger or {}) do
        if Secret(key) or Secret(value) then return end
        local kind = type(key)
        if (kind ~= "number" and kind ~= "string")
            or not (Finite(value) or type(value) == "boolean") then
            return
        end
        danger[#danger + 1] = kind .. ":" .. tostring(key) .. "=" .. tostring(value)
    end
    table.sort(danger)
    local t = context.target
    return table.concat({ t.c, t.wx, t.wy, context.faction, tostring(context.walkOnly),
        tostring(options.profile), tostring(options.style), tostring(options.walkLevel), graphEpoch,
        tostring(t.z), tostring(context.z), tostring(context.level), table.concat(danger, ",") }, ":")
end

-- Physical-floor ownership stays with Polestar. A native unknown remains
-- unknown, AWP never chooses a replacement surface from the pathing mesh.
local function Floor(r, state, c, x, y, ignoreUnit)
    local _, _, z, instance = P.Call(r.Compat, "GetPlayerUnitPosition")
    if not ignoreUnit and instance == c and Finite(z) then
        state.floor = z; return z
    end
    if Combat() then return state.floorC == c and state.floor or nil end
    local now = GetTime()
    if state.nativeFloorC == c and state.nativeFloorAt and now - state.nativeFloorAt < .25
        and (x - state.nativeFloorX) ^ 2 + (y - state.nativeFloorY) ^ 2 < 1 then
        return state.floor
    end
    local supported, floor, floors = NativeFloor(r, c, x, y)
    if supported then
        state.floor, state.floorC, state.surfaces = floor, c, floors
        state.surfaceCount = floors and #floors or 0
        state.nativeFloorC, state.nativeFloorAt, state.nativeFloorX, state.nativeFloorY = c, now, x, y
        return floor
    end
    return nil
end

-- These are caller-owned walking stages, not edits to Polestar's active trip.
-- Packed passages are projected once when a path lands and become fixed legs.
local function Project(state, x, y)
    local best, segment, fraction = math.huge, 1, 0
    for i = 1, state.n - 1 do
        local dx, dy = state.xs[i + 1] - state.xs[i], state.ys[i + 1] - state.ys[i]
        local length = dx * dx + dy * dy
        local t = length > 0 and math.max(0, math.min(1, ((x - state.xs[i]) * dx + (y - state.ys[i]) * dy) / length)) or
            0
        local ex, ey = state.xs[i] + dx * t - x, state.ys[i] + dy * t - y
        local d = ex * ex + ey * ey
        if d < best then best, segment, fraction = d, i, t end
    end
    local i, t = segment, fraction
    return best, i, state.xs[i] + (state.xs[i + 1] - state.xs[i]) * t,
        state.ys[i] + (state.ys[i + 1] - state.ys[i]) * t,
        state.left[1] - state.left[i] + (state.left[i] - state.left[i + 1]) * t
end

-- ============================================================
-- Path points and measurements
-- ============================================================

local function PathPoint(state, along)
    for i = 1, state.n - 1 do
        local a, b = state.left[1] - state.left[i], state.left[1] - state.left[i + 1]
        if along <= b then
            local t = b > a and math.max(0, (along - a) / (b - a)) or 0
            return state.xs[i] + (state.xs[i + 1] - state.xs[i]) * t,
                state.ys[i] + (state.ys[i + 1] - state.ys[i]) * t
        end
    end
    return state.xs[state.n], state.ys[state.n]
end

local function StageName(r, entry)
    return P.Text(P.Call(r.Names, "Area", entry.area)) or P.Text(entry.name) or P.Text(entry.lift)
end

local function WalkingStages(r, state)
    state.stages = {}
    local c = state.goal.polestarTo.c
    local packed = rawget(_G, "PolestarNavChokepoints")
    local entries = type(packed) == "table" and packed[c]
    if type(entries) ~= "table" then entries = P.Call(r.Transit, "Lifts") end
    if type(entries) ~= "table" then return end
    local candidates, used = {}, {}
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, state.n do
        minX, maxX = math.min(minX, state.xs[i]), math.max(maxX, state.xs[i])
        minY, maxY = math.min(minY, state.ys[i]), math.max(maxY, state.ys[i])
    end
    for _, entry in ipairs(entries) do
        local radius = type(entry) == "table" and Finite(entry.r) and entry.r or 15
        if type(entry) == "table" and (not entry.c or entry.c == c) and Finite(entry.wx) and Finite(entry.wy)
            and entry.wx + radius >= minX and entry.wx - radius <= maxX
            and entry.wy + radius >= minY and entry.wy - radius <= maxY then
            local d, seg, x, y, along = Project(state, entry.wx, entry.wy)
            local za, zb = state.zs[seg], state.zs[seg + 1]
            local before, after = state.zs[math.max(1, seg - 1)], state.zs[math.min(state.n, seg + 2)]
            if entry.kind == "lift" or entry.kind == nil then
                local first, last = seg, seg + 1
                local function Near(index)
                    return (state.xs[index] - entry.wx) ^ 2 + (state.ys[index] - entry.wy) ^ 2 <= radius ^ 2
                end
                while first > 1 and Near(first - 1) do first = first - 1 end
                while last < state.n and Near(last + 1) do last = last + 1 end
                before, after = state.zs[first], state.zs[last]
            end
            local ridden = (entry.kind == "lift" or entry.kind == nil) and before and after and
                math.abs(after - before) > 20
            if d <= radius * radius and (ridden or along >= 20 and along <= state.left[1] - 20)
                and (ridden or not Finite(entry.z) or not za or not zb
                    or math.abs(za - entry.z) <= 30 or math.abs(zb - entry.z) <= 30) then
                candidates[#candidates + 1] = {
                    entry = entry,
                    seg = seg,
                    wx = x,
                    wy = y,
                    along = along,
                    radius = math.max(5, math.min(20, radius)),
                    before = before,
                    after = after,
                    ridden = ridden
                }
            end
        end
    end
    table.sort(candidates, function(a, b) return a.along < b.along end)
    local last = -math.huge
    for _, candidate in ipairs(candidates) do
        local entry = candidate.entry
        if not used[entry] and (candidate.ridden or candidate.along - last >= 20) then
            local kind, name = entry.kind or "lift", StageName(r, entry)
            local stage = {
                wx = candidate.wx,
                wy = candidate.wy,
                along = candidate.along,
                seg = candidate.seg,
                radius = candidate.radius,
                z = entry.z,
                kind = kind
            }
            local other = type(packed) == "table" and type(packed[c]) == "table" and entry.pair and packed[c]
                [entry.pair]
            local side = candidate.before and candidate.after and
                (candidate.after > candidate.before and "bottom" or "top") or entry.liftEnd
            if kind == "lift" and other and side and other.liftEnd == side and entry.liftEnd ~= side then
                entry, other = other, entry
                name = StageName(r, entry)
            end
            if kind == "lift" and candidate.ridden then
                local own = P.Text(P.Call(r.Names, "Object", entry.liftObject))
                stage.title = "Walk to " .. (own or name or "the elevator")
                stage.z = entry.z or (side == "bottom" and entry.bottom or entry.top) or candidate.before
                local receivingZ = other and other.z or (side == "bottom" and entry.top or entry.bottom)
                if Finite(stage.z) and Finite(receivingZ) then
                    stage.wx, stage.wy = entry.wx, entry.wy
                    stage.lift = {
                        from = { c = c, wx = entry.wx, wy = entry.wy, z = stage.z },
                        to = {
                            c = c,
                            wx = other and other.wx or entry.wx,
                            wy = other and other.wy or entry.wy,
                            z = receivingZ
                        },
                    }
                end
                state.stages[#state.stages + 1] = stage
                if other then used[other] = true end
            elseif kind ~= "lift" then
                local beyondX, beyondY = PathPoint(state, candidate.along + 25)
                local nearest, distance
                for _, sideEntry in ipairs(type(entry.sides) == "table" and entry.sides or {}) do
                    if Finite(sideEntry.wx) and Finite(sideEntry.wy) then
                        local d = (beyondX - sideEntry.wx) ^ 2 + (beyondY - sideEntry.wy) ^ 2
                        if not distance or d < distance then nearest, distance = sideEntry, d end
                    end
                end
                local destination = nearest and
                    (P.Text(P.Call(r.Names, "Area", nearest.zoneArea)) or P.Text(nearest.area))
                stage.title = (kind == "bridge" and "Cross " or kind == "tunnel" and "Go through " or "Walk through ")
                    .. (name or "the passage") .. (destination and (" to " .. destination) or "")
                state.stages[#state.stages + 1] = stage
            end
            used[entry], last = true, candidate.along
        end
    end
    backend.counters.stages = backend.counters.stages + #state.stages
end

local function SameOrigin(a, b)
    return math.abs(a.x - b.x) < .01 and math.abs(a.y - b.y) < .01
        and (a.z == b.z or Finite(a.z) and Finite(b.z) and math.abs(a.z - b.z) < .01)
        and not not a.start == not not b.start
end

local function CostLookup(measure)
    return function(c, x, y, start, z)
        if c ~= measure.c then return nil end
        for i, point in ipairs(measure.points) do
            if math.abs(point.x - x) < .01 and math.abs(point.y - y) < .01
                and (point.z == z or Finite(point.z) and Finite(z) and math.abs(point.z - z) < .01)
                and not not point.start == not not start then
                local cost = measure.costs[i]
                if Finite(cost) and cost >= 0 then return cost, measure.yards[i], measure.checked end
                if cost == false then return false, nil, measure.checked end
            end
        end
    end
end

local function CancelMeasure()
    if pendingMeasure then
        if pendingMeasure.job then pcall(pendingMeasure.path.Cancel, pendingMeasure.job) end
        pendingMeasure = nil
        backend.counters.cancelled = backend.counters.cancelled + 1
    end
end

local function Measure(r, record, state, context, route)
    local path = Path(r)
    local t = context.target
    if not path or type(path.FindMany) ~= "function" or context.c ~= t.c
        or (context.wx - t.wx) ^ 2 + (context.wy - t.wy) ^ 2 < 400 ^ 2 then
        return
    end
    local options = Options(r, context)
    local key = MeasureKey(r, context, options)
    if not key then return end
    if pendingMeasure and pendingMeasure.key == key and pendingMeasure.record == record then return end
    CancelMeasure()
    local pick = {}
    for _, point in ipairs(context.places) do
        local distance = (point.wx - t.wx) ^ 2 + (point.wy - t.wy) ^ 2
        if distance <= 3000 ^ 2 then
            pick[#pick + 1] = {
                x = point.wx,
                y = point.wy,
                z = point.z,
                start = point.start,
                distance =
                    distance
            }
        end
    end
    table.sort(pick, function(a, b) return a.distance < b.distance end)
    while #pick > 16 do pick[#pick] = nil end
    local last = route and route[#route]
    local landing = last and last.kind == "walk" and last.from
    if landing and landing.c == t.c and (landing.wx - t.wx) ^ 2 + (landing.wy - t.wy) ^ 2 <= 6000 ^ 2 then
        local found
        for _, point in ipairs(pick) do if SameOrigin(point, { x = landing.wx, y = landing.wy, z = landing.z }) then found = true end end
        if not found then pick[#pick + 1] = { x = landing.wx, y = landing.wy, z = landing.z } end
    end
    if #pick == 0 then return end
    local cached, covered = measures[key], true
    for _, point in ipairs(pick) do
        local found
        for _, old in ipairs(cached and cached.points or {}) do
            if SameOrigin(point, old) then
                found = true; break
            end
        end
        if not found then
            covered = false; break
        end
    end
    if cached and covered then
        backend.counters.reused = backend.counters.reused + 1; return
    end
    local token = { path = path, key = key, record = record }
    pendingMeasure = token
    backend.counters.searches = backend.counters.searches + 1
    local ok, job = pcall(path.FindMany, t.c, { x = t.wx, y = t.wy, z = t.z, reach = t.z ~= nil and 10 or nil }, pick,
        function(costs, _, answer)
            if pendingMeasure ~= token then
                backend.counters.stale = backend.counters.stale + 1; return
            end
            pendingMeasure = nil
            if Combat() or not Current(record, state) then
                backend.counters.stale = backend.counters.stale + 1; return
            end
            local report = type(answer) == "table" and answer or {}
            local copy = {
                c = t.c,
                points = pick,
                costs = {},
                yards = {},
                checked = report.walkChecked == true,
                unjoined = report.unjoined == true,
                capped = report.capped == true
            }
            for i = 1, #pick do
                local cost
                if type(costs) == "table" then cost = costs[i] end
                local yards = type(report.yards) == "table" and report.yards[i]
                -- A completed batch can leave sparse prices (unjoined/capped).
                -- Only an explicit false removes a planner's estimated walk.
                if not Secret(cost) and cost == false then
                    copy.costs[i] = false
                elseif Finite(cost) and cost >= 0 then
                    copy.costs[i] = cost
                end
                if Finite(yards) and yards >= 0 then copy.yards[i] = yards end
            end
            if not measures[key] then measureOrder[#measureOrder + 1] = key end
            measures[key] = copy
            if #measureOrder > 4 then measures[table.remove(measureOrder, 1)] = nil end
            NS.ScheduleActiveRouteRefresh("polestar_measurement_ready")
        end, options, true)
    if ok and pendingMeasure == token then token.job = job else if not ok then pendingMeasure = nil end end
end

local travelTypes = {
    walk = "travel",
    fly = "taxi",
    boat = "ship",
    zeppelin = "zeppelin",
    airship = "airship",
    tram = "travel",
    portal = "portal",
    hearth = "hearth",
    teleport = "travel",
    lift = "travel"
}

local RIDE_KIND = { boat = true, zeppelin = true, airship = true, tram = true }
local DOCK_RADIUS = 60

-- ============================================================
-- Transport connections and route legs
-- ============================================================

local function NearDock(dock, c, x, y, radius)
    return dock and dock.c == c and Finite(dock.wx) and Finite(dock.wy)
        and (x - dock.wx) ^ 2 + (y - dock.wy) ^ 2 <= radius ^ 2
end

local function SharedDock(r, transport, from, to)
    local data = P.Call(r.Nav, "GetTravelData")
    if not data or not transport then return true end
    local faction = P.Call(r.Compat, "GetPlayerFaction")
    local allowed = faction == "Alliance" and 1 or faction == "Horde" and 2 or 0
    for _, other in ipairs(data.transports or {}) do
        if RIDE_KIND[other.kind] and (other.faction == nil or other.faction == 3 or other.faction == allowed) then
            for _, side in ipairs({ "a", "b" }) do
                local origin = other[side]
                local destination = other[side == "a" and "b" or "a"]
                if NearDock(origin and (origin.board or origin), from.c, from.wx, from.wy, DOCK_RADIUS)
                    and not NearDock(destination, to.c, to.wx, to.wy, DOCK_RADIUS) then
                    return true
                end
            end
        end
    end
    return false
end

local function AppendEndpoint(legs, point, title, role, travelType, worldEndpoint)
    local last = legs[#legs]
    if last and last.polestarKind == "walk"
        and NS.RouteSpecials.SameWalkingEndpoint(last, point, last.polestarTo, worldEndpoint) then
        -- The final walking endpoint keeps destination presentation, its
        -- intermediate terrain points will become separate travel legs.
        last.mapID, last.x, last.y = point.mapID, point.x, point.y
        last.title, last.routeLegKind, last.routeTravelType = title, role, travelType
        if role == "carrier" then last.kind = "entrance" end
        return
    end
    local leg = NS.RouteSpecials.MakeDestinationLeg("polestar", point.mapID, point.x, point.y, title)
    leg.kind = role == "destination" and "destination" or "entrance"
    leg.routeLegKind, leg.routeTravelType, leg.arrivalRadius = role, travelType, 15
    legs[#legs + 1] = leg
end

local function Translate(r, route, final, intent, worldEndpoint, context)
    local legs = {}
    local kinds = {
        walk = true,
        fly = true,
        boat = true,
        zeppelin = true,
        airship = true,
        tram = true,
        portal = true,
        hearth = true,
        teleport = true,
        lift = true
    }
    local sanctum = NS.RouteSpecials.Sanctum
    for _, step in ipairs(route or {}) do
        if type(step) ~= "table" or not kinds[step.kind] then return nil end
        local source = step.from
        local to = step.to
        if type(source) ~= "table" or type(to) ~= "table" then return nil end
        local action = step.kind == "teleport" or step.kind == "hearth"
        local carrier = step.kind == "portal" or step.kind == "boat" or step.kind == "zeppelin" or step.kind == "airship" or
            step.kind == "tram" or
            step.kind == "fly"
        local point = (action or carrier) and source or to
        local map, x, y = Coord(r, point)
        if not map then return nil end
        local kind = step.kind == "walk" and "walk" or step.kind == "fly" and "taxi" or
            step.kind == "hearth" and "hearthstone"
            or step.kind == "teleport" and "spell" or step.kind == "lift" and "movement" or step.kind
        local leg = {
            mapID = map,
            x = x,
            y = y,
            kind = kind,
            routeLegKind = "carrier",
            title = P.Text(step.label) or final.title,
            source = "polestar",
            routeTravelType = travelTypes[step.kind],
            arrivalRadius = step.radius or 12,
            polestarFrom = Point(source),
            polestarTo = Point(to),
            polestarKind = step.kind,
            polestarHandmade = step.handmade == true,
            routeGeometryKey = GeometryKey(source) .. ":" .. GeometryKey(to) .. ":" .. tostring(step.handmade == true)
        }
        if carrier then leg.activationCoords = { mapID = map, x = x, y = y } end
        if sanctum and source.map == 1453 and to.map == 1453 then
            if step.kind == "portal" and step.place == "wizards-sanctum-chamber" then
                sanctum.SetCrossing(leg, sanctum.ForeverChamber(true))
            elseif step.kind == "portal" and step.place == false
                and step.transport and step.transport.id == "portal-sanctum-tower" then
                sanctum.SetCrossing(leg, sanctum.ForeverChamber(false))
            elseif step.kind == "walk" and step.handmade
                and source.wx == -9009.4 and source.wy == 867.7 and to.wx == -9020.1 and to.wy == 880.5 then
                -- The native authored tower chain starts at the mouth. A
                -- terrain segment at the same XY carries no such evidence.
                local doorMap, doorX, doorY = Coord(r, source)
                if doorMap then
                    local crossing = sanctum.ForeverDoorway(true)
                    leg.mapID, leg.x, leg.y = doorMap, doorX, doorY
                    leg.kind, leg.title = "entrance", crossing.title
                    sanctum.SetCrossing(leg, crossing)
                end
            end
        end
        if RIDE_KIND[step.kind] and step.rideLabel then
            local arrivalMap, arrivalX, arrivalY = Coord(r, to)
            if arrivalMap then
                leg.polestarRide = {
                    title = P.Text(step.rideLabel),
                    dock = P.Text(P.Call(r.Nav.travel, "PlaceName", to)) or P.Text(to.name),
                    shared = SharedDock(r, step.transport, source, to),
                    seconds = Finite(step.ride) and step.ride > 0 and step.ride or nil,
                    mapID = arrivalMap,
                    x = arrivalX,
                    y = arrivalY,
                }
            end
        end
        if step.kind == "fly" then
            local first = step.stops and step.stops[1]
            local last = step.stops and step.stops[#step.stops]
            leg.taxi = last and { sourceNodeID = first and first.id, nodeID = last.id, name = last.name } or nil
            if step.taxiOffer then
                local snapshot = context and context.taxiWindow
                local window = NS.Internal.TaxiWindow
                if not snapshot or step.taxiOffer ~= context.taxiOffer or not last or not Finite(last.id)
                    or not window.IsCurrentOffer(snapshot, context.taxiSerial, step.taxiOffer.map, step.taxiOffer.node.id)
                    or not step.taxiOffer.reachable[last.id] then
                    return nil, "expired_flight_offer"
                end
                local reachable
                for _, node in ipairs(snapshot.reachable) do
                    if node.nodeID == last.id then
                        reachable = true; break
                    end
                end
                if not reachable then return nil, "expired_flight_offer" end
                leg.taxi.offerSerial, leg.taxi.offerMap, leg.taxi.offerSource = context.taxiSerial, snapshot.mapID,
                    snapshot.sourceNodeID
            end
        end
        if action then
            local id = step.spell or step.item
            if not Finite(id) or id <= 0 then return nil end
            local ty = step.spell and "spell" or "item"
            leg.specialAction = {
                title = leg.title,
                secureType = ty,
                securePayload = ty == "item" and ("item:" .. id) or id,
                spellID = step.spell,
                itemID = step.item,
                semanticKind = kind,
                activationMode = "portable",
                routeDependency = { kind = ty, id = id }
            }
            local am, ax, ay = Coord(r, to)
            if am then leg.specialAction.arrivalCoords = { mapID = am, x = ax, y = ay } end
        end
        legs[#legs + 1] = leg
    end
    if intent and intent.entrance then
        local name = intent.instanceName or intent.entrance.name
        AppendEndpoint(legs, intent.entrance, name and ("Enter " .. name) or final.title, "carrier", intent.travelType,
            worldEndpoint)
    end
    AppendEndpoint(legs, final, final.title, "destination", nil,
        not (intent and intent.entrance) and worldEndpoint or nil)
    return legs
end

function backend.GetDestinationAreaFloor(record, area)
    local r, state = Runtime(), states[record]
    if not r then return end
    local _, _, z, instance = P.Call(r.Compat, "GetPlayerUnitPosition")
    if instance == area.continent and Finite(z) and z ~= 0 then return z, instance end
    local c, x, y = P.Call(r.Compat, "GetPlayerWorldPosition")
    if state and x and c == area.continent and Finite(area.height) then return Floor(r, state, c, x, y, true), c end
    return nil, c
end

function backend.OnDestinationAreaChanged(record, arrived)
    local state = states[record]
    if not state then return end
    CancelWalk(state)
    if pendingMeasure and pendingMeasure.record == record then CancelMeasure() end
    state.areaRefreshPending = not arrived
    state.owed = not arrived
    state.progressAt = nil
end

local function SameRemainingItinerary(record, state, legs)
    local current = record.currentLeg
    local group = current and (current.polestarPath or current.polestarApproach)
    current = group and group.goal or current
    local previous = state.itinerary
    if not current or not previous then return false end
    local first = 1
    while previous[first] and previous[first] ~= current do first = first + 1 end
    if not previous[first] or #previous - first + 1 ~= #legs then return false end
    for i, leg in ipairs(legs) do
        local old = previous[first + i - 1]
        if old.kind ~= leg.kind or old.routeLegKind ~= leg.routeLegKind or old.routeTravelType ~= leg.routeTravelType
            or old.mapID ~= leg.mapID or math.abs(old.x - leg.x) > 0.000001 or math.abs(old.y - leg.y) > 0.000001
            or old.polestarHandmade ~= leg.polestarHandmade or old.sanctumCrossing ~= leg.sanctumCrossing
            or GeometryKey(old.polestarTo) ~= GeometryKey(leg.polestarTo)
            or (i > 1 or leg.polestarKind ~= "walk" or leg.polestarHandmade)
            and GeometryKey(old.polestarFrom) ~= GeometryKey(leg.polestarFrom) then
            return false
        end
        local a, b = old.specialAction, leg.specialAction
        if (a and a.secureType) ~= (b and b.secureType) or (a and a.securePayload) ~= (b and b.securePayload)
            or (old.taxi and old.taxi.nodeID) ~= (leg.taxi and leg.taxi.nodeID)
            or (old.taxi and old.taxi.offerSerial) ~= (leg.taxi and leg.taxi.offerSerial)
            or (old.taxi and old.taxi.offerMap) ~= (leg.taxi and leg.taxi.offerMap)
            or (old.taxi and old.taxi.offerSource) ~= (leg.taxi and leg.taxi.offerSource) then
            return false
        end
    end
    return true
end

local function PlanRoute(record, mapID, x, y, title)
    if type(record) ~= "table" then return end
    local destination = { mapID = mapID, x = x, y = y, title = title }
    local state = { destination = destination }
    states[record] = state
    record.backend = "polestar"
    local combat = Combat()
    local r = Runtime()
    if NS.UpdateRouteDestinationArea and NS.UpdateRouteDestinationArea(record, true) then
        NS.RouteSpecials.CompletePlan(record, "polestar", "success", Translate(r, nil, destination), "polestar_plan", nil,
            "arrived")
        state.generation = record._routeAcceptedPlanGeneration
        return
    end
    local fingerprint = NS.RouteSpecials.COMBAT_TRAVEL_STATE
    if not combat then
        local valid, fullState = Snapshot()
        if not valid then return NS.RouteSpecials.CompletePlan(record, "polestar", "failed", nil, "state_unavailable") end
        fingerprint = fullState
    end
    if not combat and fingerprint ~= measuredState then
        CancelMeasure()
        measures, measureOrder, measuredState = {}, {}, fingerprint
    end
    local intent = NS.ResolveInstanceRouteIntent and NS.ResolveInstanceRouteIntent(mapID, x, y, title)
    local entrance = intent and intent.entrance
    local planning = entrance or destination
    local context = r and backend.IsAvailable() and
        TravelContext(r, planning.mapID, planning.x, planning.y, title, not entrance and record or nil)
    state.context = context
    state.taxiOfferKey = context and TaxiOfferKey(context.taxiOffer, context.taxiSerial)
    state.walking = r and P.Call(r, "Get", "nav.navRouting") == true
    local route
    if context and backend.IsAvailable() and P.Call(r, "Get", "nav.travel") then
        local cached = not combat and measures[MeasureKey(r, context)]
        if cached then context.walkCost = CostLookup(cached) end
        local ok, result = pcall(r.Nav.PlanRoute, context)
        if not ok then return NS.RouteSpecials.CompletePlan(record, "polestar", "failed", nil, "planner_error") end
        route = result
    elseif context then
        route = { {
            kind = "walk",
            from = { c = context.c, wx = context.wx, wy = context.wy, map = context.map },
            to = context.target,
            label = title
        } }
    end
    if type(route) ~= "table" or #route == 0 then route = nil end
    if combat and context and not route then
        return NS.RouteSpecials.CompletePlan(record, "polestar", "deferred", nil,
            "combat")
    end
    local legs, failure
    if r then legs, failure = Translate(r, route, destination, intent, context and context.target, context) end
    if context and failure == "expired_flight_offer" then
        context.liveTaxi, state.taxiOfferKey = nil, nil
        local ok, result = pcall(r.Nav.PlanRoute, context)
        route = ok and type(result) == "table" and #result > 0 and result or nil
        legs = Translate(r, route, destination, intent, context.target)
    end
    if not legs then
        route = nil; legs = Translate(r, nil, destination, intent)
    end
    if type(legs) ~= "table" then return end
    local owner = record._routePlanAttempt.owner
    local retained = owner.backend == "polestar" and states[owner]
    if retained and not record._routePlanAttempt.geometry and route and retained.walking == state.walking
        and retained.destination.mapID == mapID and retained.destination.x == x and retained.destination.y == y
        and retained.context and context and SameRemainingItinerary(owner, retained, legs) then
        state.refreshGeometry = record._coreResetLegOnNextPlan or retained.context._style ~= context._style
            or retained.graphEpoch ~= graphEpoch or retained.level ~= UnitLevel("player")
        -- The itinerary may stay fixed while the planner discovers another
        -- landing/origin. Let measurement check coverage against this request.
        if not combat then state.route = route end
        state.graphEpoch, state.level = graphEpoch, UnitLevel("player")
        record._routeBackendStateFingerprint = fingerprint
        return NS.RouteSpecials.CompletePlan(record, "polestar", "success", owner.legs,
            "retained_itinerary", nil, "retained")
    end
    state.itinerary, state.graphEpoch, state.level = legs, graphEpoch, UnitLevel("player")
    state.route = route
    record._routeBackendStateFingerprint = fingerprint
    return NS.RouteSpecials.CompletePlan(record, "polestar", route and "success" or "failed",
        route and legs or nil, route and "polestar_plan" or "polestar_nopath")
end

-- ============================================================
-- Starting a plan
-- ============================================================

function backend.BeginPlan(attempt)
    return PlanRoute(attempt.record, attempt.mapID, attempt.x, attempt.y, attempt.title)
end

function backend.CancelPlan(attempt)
    CancelWalk(states[attempt.record])
    if pendingMeasure and pendingMeasure.record == attempt.record then CancelMeasure() end
    states[attempt.record] = nil
end

function backend.ReleasePlan(owner)
    CancelWalk(states[owner])
    ClearWalkBudget(states[owner])
    if pendingMeasure and pendingMeasure.record == owner then CancelMeasure() end
    states[owner] = nil
end

function backend.AdoptPlan(attempt, owner, result)
    owner._routeDestinationAreaState = attempt.record._routeDestinationAreaState
    local s = states[attempt.record]
    if result.mode == "retained" then
        local old = states[owner]
        if old and s then
            if s.refreshGeometry and s.walking then
                InvalidateWalkingGeometry(owner, old)
            end
            old.context, old.destination = s.context, s.destination
            old.taxiOfferKey = s.taxiOfferKey
            old.graphEpoch, old.level = s.graphEpoch, s.level
            old.areaRefreshPending = nil
            if s.route and s.walking and not Combat() then Measure(Runtime(), owner, old, s.context, s.route) end
        end
        states[attempt.record] = nil
    else
        states[owner], states[attempt.record] = s, nil
        if s then
            s.generation = owner._routeAcceptedPlanGeneration
            if not Combat() and s.context and s.route and s.walking then Measure(Runtime(), owner, s, s.context, s.route) end
        end
    end
    owner._routeBackendStateFingerprint = attempt.record._routeBackendStateFingerprint
    if NS.RequestRouteNavigationProgress then NS.RequestRouteNavigationProgress(owner, "polestar_plan") end
end

-- ============================================================
-- Building terrain walks
-- ============================================================

-- The walking engine already straightens its returned polyline. Keep every
-- required corner/floor transition, only exact duplicates and collinear points
-- may disappear. No moving look-ahead target or native follower is involved.
local function AddPathPoint(points, point)
    local last, before = points[#points], points[#points - 1]
    if last and math.abs(last.wx - point.wx) < 0.01 and math.abs(last.wy - point.wy) < 0.01
        and last.z == point.z then
        if point.title then last.title, last.required = point.title, true end
        if point.lift then last.lift = point.lift end
        return
    end
    if before and not last.required and before.z == last.z and last.z == point.z then
        local ax, ay = last.wx - before.wx, last.wy - before.wy
        local bx, by = point.wx - last.wx, point.wy - last.wy
        if math.abs(ax * by - ay * bx) < 0.000001 and ax * bx + ay * by >= 0 then points[#points] = nil end
    end
    points[#points + 1] = point
end

local function ValidWalkPoints(points)
    if type(points) ~= "table" or #points < 2 or #points > 8192 then return false end
    for _, point in ipairs(points) do
        if type(point) ~= "table" or not Finite(point.x) or not Finite(point.y)
            or point.z ~= nil and point.z ~= false and not Finite(point.z) then
            return false
        end
    end
    return true
end

-- Keep a native lift as one directed ride even when the terrain worker
-- supplies extra samples between its decks. Heights alone never create one.
local function LiftStages(points, map)
    local result, index = {}, 1
    while index <= #points do
        local point, receiving = points[index], nil
        local lift = point.lift
        if lift then
            for i = index + 1, #points do
                local candidate = points[i]
                if candidate.title then break end -- another protected passage
                local to, from = lift.to, lift.from
                local endDistance = (candidate.wx - to.wx) ^ 2 + (candidate.wy - to.wy) ^ 2
                if Finite(candidate.z) and math.abs(candidate.z - to.z) <= 3 and endDistance <= 20 ^ 2 then
                    receiving = i; break
                end
                if endDistance > 40 ^ 2 and (candidate.wx - from.wx) ^ 2 + (candidate.wy - from.wy) ^ 2 > 40 ^ 2 then break end
            end
        end
        result[#result + 1] = point
        if receiving then
            local to = lift.to
            result[#result + 1] = {
                c = to.c,
                wx = to.wx,
                wy = to.wy,
                z = to.z,
                map = map,
                required = true,
                ride = lift
            }
            index = receiving + 1
        else
            index = index + 1
        end
    end
    return result
end

local function FixedWalk(r, state, points, px, py, approachOnly)
    if not ValidWalkPoints(points) then return end
    state.xs, state.ys, state.zs, state.left, state.n = {}, {}, {}, {}, #points
    for i, point in ipairs(points) do state.xs[i], state.ys[i], state.zs[i] = point.x, point.y, point.z or false end
    state.left[#points] = 0
    for i = #points - 1, 1, -1 do
        state.left[i] = state.left[i + 1] +
            math.sqrt((state.xs[i + 1] - state.xs[i]) ^ 2 + (state.ys[i + 1] - state.ys[i]) ^ 2)
    end
    local goal = state.goal
    local c = goal.polestarTo.c
    local floor = Floor(r, state, c, px, py)
    -- Keep all protected stages. The shared join operation proves which
    -- ordinary prefix was passed after this asynchronous request began.
    WalkingStages(r, state)
    local fixed, stageIndex = { {
        c = c,
        wx = state.xs[1],
        wy = state.ys[1],
        z = state.zs[1] or nil,
        map = goal.mapID
    } }, 1
    for i = 2, state.n do
        local along = state.left[1] - state.left[i]
        local stage = state.stages[stageIndex]
        while stage and stage.along <= along do
            if stage.along >= 0 then
                AddPathPoint(fixed, {
                    c = c,
                    wx = stage.wx,
                    wy = stage.wy,
                    z = stage.z,
                    title = stage.title,
                    lift = stage.lift,
                    required = true,
                    map = goal.mapID
                })
            end
            stageIndex = stageIndex + 1
            stage = state.stages[stageIndex]
        end
        if along >= 0 then
            AddPathPoint(fixed, {
                c = c,
                wx = state.xs[i],
                wy = state.ys[i],
                z = state.zs[i] or nil,
                map = goal.mapID,
                required = i == state.n
            })
        end
    end
    fixed = LiftStages(fixed, goal.mapID)
    if #fixed > 1 and (fixed[1].wx - state.startX) ^ 2 + (fixed[1].wy - state.startY) ^ 2 <= 5 ^ 2 then
        table.remove(
            fixed, 1)
    end
    if #fixed == 0 then return end
    local tail = fixed[#fixed]
    local exact = goal.polestarTo
    if not approachOnly and ((tail.wx - exact.wx) ^ 2 + (tail.wy - exact.wy) ^ 2 > 1
            or Finite(tail.z) and Finite(exact.z) and math.abs(tail.z - exact.z) > 1) then
        tail.required = true
        fixed[#fixed + 1] = { c = c, wx = exact.wx, wy = exact.wy, z = exact.z, map = goal.mapID, required = true }
    end
    tail = fixed[#fixed]
    local beforeTail = fixed[#fixed - 1] or { wx = px, wy = py, z = floor }
    if not approachOnly and (tail.ride or Finite(tail.z) and Finite(beforeTail.z) and math.abs(tail.z - beforeTail.z) >= 20
            and (tail.wx - beforeTail.wx) ^ 2 + (tail.wy - beforeTail.wy) ^ 2 <= 20 ^ 2) then
        fixed[#fixed + 1] = { c = c, wx = exact.wx, wy = exact.wy, z = exact.z, map = goal.mapID, required = true }
    end
    local group = { goal = goal, points = fixed, total = state.left[1], left = {}, approachOnly = approachOnly == true }
    group.left[#fixed] = 0
    for i = #fixed - 1, 1, -1 do
        local a, b = fixed[i], fixed[i + 1]
        group.left[i] = group.left[i + 1] + math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2)
    end
    local legs, previous = {}, { c = c, wx = state.startX, wy = state.startY, z = state.startZ, map = state.startMap }
    for i, point in ipairs(fixed) do
        local map, x, y = Coord(r, point)
        if not map then return end
        local last = i == #fixed and not approachOnly
        local dz = Finite(point.z) and Finite(previous.z) and point.z - previous.z or 0
        local vertical = not last and math.abs(dz) >= 20 and
            (point.wx - previous.wx) ^ 2 + (point.wy - previous.wy) ^ 2 <=
            20 ^ 2
        local lift = point.ride
        local leg = {}
        if last then for key, value in pairs(goal) do leg[key] = value end end
        leg.mapID, leg.x, leg.y = last and goal.mapID or map, last and goal.x or x, last and goal.y or y
        leg.title = last and goal.title or point.title or
            (lift and (dz > 0 and "Ride the elevator up" or "Ride the elevator down"))
            or (goal.routeLegKind == "carrier" and goal.title) or "Follow the path"
        leg.kind = last and goal.kind or "movement"
        leg.routeLegKind, leg.routeTravelType = last and goal.routeLegKind or "carrier",
            last and goal.routeTravelType or "travel"
        if last then leg.routeTravelType = goal.routeTravelType end
        leg.source, leg.preservePlanOnArrival = "polestar", true
        leg.arrivalRadius = last and goal.arrivalRadius or
            NS.Internal.RouteWalking.ArrivalRadius(previous, point, fixed[i + 1])
        leg.polestarFrom, leg.polestarTo = previous, point
        leg.polestarKind, leg.polestarPath, leg.polestarPathIndex = lift and "lift" or "walk", group, i
        leg.polestarLift = lift or nil
        leg.polestarRequired = point.required == true or vertical or last
        NS.Internal.RouteWalking.Bind(leg, group, previous, point, leg.polestarRequired)
        if not last then
            NS.Internal.RouteWalkingPresentation.Describe(leg, "path", goal, nil, point.title
                or lift and leg.title or goal.routeLegKind == "carrier" and goal.title)
        end
        leg.routeGeometryKey = GeometryKey(previous) ..
            ":" .. GeometryKey(point) .. (leg.polestarRequired and ":stop" or ":fixed")
        legs[#legs + 1], previous = leg, point
    end
    if approachOnly then
        -- The searched geometry ends on its own floor. The remaining bearing
        -- is not evidence of a lift or a walk onto the authored goal's floor.
        local final = {}
        for key, value in pairs(goal) do final[key] = value end
        final.polestarFrom, final.polestarTo = previous, Point(goal.polestarTo)
        final.polestarPath, final.polestarPathIndex, final.walking = nil, nil, nil
        final.polestarApproach, final.polestarRequired, final.preservePlanOnArrival = group, true, true
        final.routeGeometryKey = GeometryKey(previous) .. ":" .. GeometryKey(goal.polestarTo) .. ":unmapped"
        legs[#legs + 1] = final
    else
        -- The final UI coordinate stays exact even if the engine snapped its endpoint.
        legs[#legs].polestarTo = Point(goal.polestarTo)
    end
    group.endpoint = legs[#legs]
    return legs
end

local function ReleasePastGeometry(record, group)
    if not group then return end
    for i = 1, (record.currentLegIndex or 1) - 1 do
        local leg = record.legs[i]
        if leg.polestarPath == group then leg.polestarPath, leg.polestarPathIndex, leg.walking = nil, nil, nil end
    end
end

local CAPITAL_MAPS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
local function CanApproachWithoutHeight(r, goal, group, reason, answer)
    local to = goal.polestarTo
    if reason ~= "no safe walking route" or not to or not Finite(to.z)
        or goal.polestarHandmade or group and not group.approachOnly
        or type(answer) == "table" and answer.blockedReason or CAPITAL_MAPS[goal.mapID] then
        return false
    end
    -- Use the native zone classification, including Undercity beneath Tirisfal.
    -- An unavailable classification cannot authorize dropping a floor constraint.
    local zone = P.Call(r.Nav.travel, "ZoneOf", nil, to.c, to.wx, to.wy)
    if not Finite(zone) or zone <= 0 or CAPITAL_MAPS[zone] then return false end
    if zone == 1420 then
        local x, y = P.Call(r.Compat, "WorldToMap", to.c, to.wx, to.wy, 1458)
        if not Finite(x) or not Finite(y) or x >= 0 and x <= 100 and y >= 0 and y <= 100 then return false end
    end
    return true
end

local function WalkBudgetReady(record, state, leg, x, y)
    local hold = state.walkBudget
    local group = leg.polestarPath or leg.polestarApproach
    if not hold or hold.goal ~= (group and group.goal or leg) then
        ClearWalkBudget(state)
        return true
    end
    if (x - hold.x) ^ 2 + (y - hold.y) ^ 2 < WALK_RECOVERY.retryDistance ^ 2 then return false end
    local delay = hold.untilAt - GetTime()
    if delay <= 0 then return true end
    if not hold.timer then
        hold.timer = C_Timer.NewTimer(delay, function()
            hold.timer = nil
            if Current(record, state) and state.walkBudget == hold and NS.RequestRouteNavigationProgress then
                NS.RequestRouteNavigationProgress(record, "polestar_walk_budget_ready")
            end
        end)
    end
    return false
end

local function RequestWalk(r, record, state, leg, path, c, px, py, recovery)
    if Combat() then
        state.owed = true; return
    end
    local group = leg.polestarPath or leg.polestarApproach
    local goal = group and group.goal or leg
    if group and goal.routeLegKind == "destination" then goal.title = group.endpoint.title end
    local to = goal.polestarTo
    if not to or to.c ~= c or not Finite(to.wx) or not Finite(to.wy) then return end
    ClearWalkBudget(state)
    CancelWalk(state, true)
    state.path, state.leg, state.goal, state.asked, state.startX, state.startY = path, leg, goal, GetTime(), px, py
    state.failX, state.failY, state.owed = px, py, nil
    local token, generation = {}, state.generation
    state.token = token
    if recovery then recovery.cancel = function() if state.token == token then CancelWalk(state) end end end
    local z = Floor(r, state, c, px, py)
    state.startZ, state.startMap = z, NS.GetPlayerMapID()
    local _, _, observedZ = P.Call(r.Compat, "GetPlayerUnitPosition")
    local origin = { c = c, x = px, y = py, z = observedZ }
    local from = { x = px, y = py, z = z }
    if not z and state.surfaceCount and state.surfaceCount > 0 then
        from.floors = {}; for i = 1, state.surfaceCount do from.floors[i] = state.surfaces[i] end
    end
    local options = Options(r, state.context)
    local function Eligible()
        local progress = NS.Internal.RouteProgress
        local currentC, currentX, currentY, currentZ = backend.ReadNavigationProgress()
        if not Current(record, state) or record.currentLeg ~= leg or Combat() or progress and progress.IsBlocked()
            or not Walking.OriginMatches(origin, currentC, currentX, currentY, currentZ) then
            if recovery then Walking.CancelRecovery(state, recovery) end
            state.job, state.token = nil, nil
            state.owed = Current(record, state)
            if state.owed and NS.RequestRouteNavigationProgress then
                NS.RequestRouteNavigationProgress(record,
                    "polestar_deferred_result")
            end
            backend.counters.stale = backend.counters.stale + 1; return false
        end
        return true
    end
    local function Search(approachOnly)
        if not Eligible() then return end
        backend.counters.searches = backend.counters.searches + 1
        local stage = {}
        token.stage = stage
        local destination = { x = to.wx, y = to.wy }
        if not approachOnly then destination.z, destination.reach = to.z, to.z ~= nil and 10 or nil end
        local ok, handle = pcall(path.Find, c, from, destination, function(points, reason, answer)
            if state.token ~= token or token.stage ~= stage then
                backend.counters.stale = backend.counters.stale + 1; return
            end
            state.job = nil
            if not Eligible() then return end
            if not approachOnly and not ValidWalkPoints(points)
                and CanApproachWithoutHeight(r, goal, group, reason, answer) then
                -- This immediate, different search replaces the stationary
                -- retry. The authored endpoint is never changed or re-priced.
                state.quickRetried, state.quickRetryAt = true, nil
                Search(true)
                return
            end
            state.token = nil
            local _, nx, ny = P.Call(r.Compat, "GetPlayerWorldPosition")
            local usable = ValidWalkPoints(points)
            state.walkingStatus = reason == "budget" and not usable and "budget" or usable
                and (approachOnly or type(answer) == "table" and answer.reached) and "partial"
                or usable and "mapped" or "unmapped"
            state.walkingReason = type(reason) == "string" and reason or nil
            state.walkingChecked = type(answer) == "table" and answer.walkChecked == true
            state.walkingHubs = nil
            if type(answer) == "table" and type(answer.hubs) == "table" then
                local names = {}
                for i = 1, math.min(16, #answer.hubs) do
                    local hub = answer.hubs[i]
                    if type(hub) == "table" and type(hub.name) == "string" then names[#names + 1] = hub.name end
                end
                if #names > 0 then state.walkingHubs = table.concat(names, ", ") end
            end
            state.quickRetryAt = not usable and not state.quickRetried and reason == "no safe walking route"
                and not (type(answer) == "table" and answer.blockedReason) and GetTime() + 2 or nil
            local legs = FixedWalk(r, state, points, nx or px, ny or py, approachOnly)
            state.xs, state.ys, state.zs, state.left, state.stages, state.n = nil, nil, nil, nil, nil, nil
            if not legs then
                if reason == "budget" then
                    state.walkBudget = { goal = goal, x = px, y = py, untilAt = GetTime() + WALK_BUDGET_HOLD }
                end
                if recovery then Walking.CompleteRecovery(state, recovery, false, state.walkingReason) end
                state.failed = true; backend.counters.failed = backend.counters.failed + 1; return
            end
            if not NS.ReplaceActiveRouteLegs(record, leg, generation, legs, group and group.endpoint) then
                if Current(record, state) then
                    state.owed = true
                    if NS.RequestRouteNavigationProgress then
                        NS.RequestRouteNavigationProgress(record,
                            "polestar_refinement_retry")
                    end
                end
                backend.counters.stale = backend.counters.stale + 1; return
            end
            if recovery then Walking.CompleteRecovery(state, recovery, true) end
            ReleasePastGeometry(record, group)
            state.generation, state.failed = record._routeAcceptedPlanGeneration, nil
            backend.counters.expanded = backend.counters.expanded + 1
            C_Timer.After(0, function() if Current(record, state) then NS.RecomputeCarrier() end end)
        end, options)
        if ok and state.token == token and token.stage == stage then
            state.job = handle
            if type(handle) == "table" then handle.urgent = true end
        elseif not ok and state.token == token and token.stage == stage then
            if recovery then Walking.CompleteRecovery(state, recovery, false, "terrain_search_error") end
            state.failed, state.token, state.job = true, nil, nil
            backend.counters.failed = backend.counters.failed + 1
        end
    end
    Search(false)
end

-- ============================================================
-- Walking and transport progression
-- ============================================================

local function AdvancePassedWalk(r, record, state, leg, c, x, y, observedAt)
    local group, from, to = leg.polestarPath, leg.polestarFrom, leg.polestarTo
    local nextLeg = record.legs[(record.currentLegIndex or 1) + 1]
    if not group or not from or not to or Combat() or NS.State.routing.specialActionCasting == true
        or NS.IsRouteEquipmentTransactionActive and NS.IsRouteEquipmentTransactionActive()
        or leg.polestarRequired or leg.polestarHandmade or leg.polestarKind ~= "walk"
        or leg.routeLegKind == "destination" or not nextLeg or nextLeg.polestarPath ~= group
        or nextLeg.specialAction then
        state.progressAt, state.catchUp = nil, nil; return false
    end
    return NS.Internal.RouteWalking.Progress(state, record, c, x, y,
        Floor(r, state, c, x, y), observedAt)
end

local function ObservedHeight(r, c)
    local _, _, z, continent = P.Call(r.Compat, "GetPlayerUnitPosition")
    if continent == c and Finite(z) then return z end
end

local function RecoverWalk(r, record, state, leg, c, x, y, z, reason, interval)
    if state.job or leg.polestarHandmade or not WalkBudgetReady(record, state, leg, x, y) then return end
    local ticket = Walking.BeginRecovery(state, record, c, x, y, z, WALK_RECOVERY, reason,
        state.asked and state.asked + (interval or 2))
    if not ticket then return end
    if leg.polestarPath then
        local path = Path(r)
        if path then
            RequestWalk(r, record, state, leg, path, c, x, y, ticket)
        else
            Walking.CompleteRecovery(state, ticket, false, "no_terrain")
        end
    else
        ticket.cancel = function() NS.CancelRouteGeometryRefresh(record, ticket) end
        local started = NS.RequestRouteGeometryRefresh(record, ticket, function(success, failure)
            Walking.CompleteRecovery(state, ticket, success, failure)
        end, function()
            local cc, xx, yy, zz = backend.ReadNavigationProgress()
            return Walking.OriginMatches(ticket, cc, xx, yy, zz, 25)
        end)
        if not started then Walking.CompleteRecovery(state, ticket, false, "planner_busy") end
    end
end

local function LiftEnds(leg)
    local lift = leg and leg.polestarLift
    if lift then return lift.from, lift.to end
    if leg and leg.polestarKind == "lift" then return leg.polestarFrom, leg.polestarTo end
end

-- The native follower owns its own arrow and cannot be started by AWP.
-- Translate its directed lift policy using copied deck data instead. Only a
-- named native lift gets these rules, a steep terrain segment remains a stop.
local function PollLift(r, record, state, leg, c, x, y)
    local from, to = LiftEnds(leg)
    if not from or not to or c ~= from.c or c ~= to.c then return false end
    if state.liftLeg ~= leg then state.liftLeg, state.landingSeen = leg, nil end
    local z = ObservedHeight(r, c)
    local sourceDistance = (x - from.wx) ^ 2 + (y - from.wy) ^ 2
    if not (Finite(z) and Finite(from.z) and Finite(to.z)) then
        if sourceDistance > 30 ^ 2 then
            return NS.AdvanceActiveRouteLeg(record, leg, state.generation, "polestar_lift_departure")
        end
        return false
    end
    local falling = false
    if type(IsFalling) == "function" then
        local ok, value = pcall(IsFalling)
        falling = not ok or Secret(value) or value ~= false
    end
    if falling or P.Call(r.Compat, "IsOnTaxi") or P.Call(r.Compat, "IsSwimming")
        or math.abs(z - to.z) >= math.abs(z - from.z) then
        state.landingSeen = nil
        return false
    end
    local distance = (x - to.wx) ^ 2 + (y - to.wy) ^ 2
    if distance <= 8 ^ 2 and math.abs(z - to.z) <= 3 then state.landingSeen = true end
    if distance > 30 ^ 2 then
        if state.landingSeen and math.abs(z - to.z) <= 20 then
            return NS.AdvanceActiveRouteLeg(record, leg, state.generation, "polestar_lift_arrival")
        end
        -- Missing the receiving-deck observation is not evidence of a ride.
        -- A current-position search can remove the obsolete lift safely.
        RecoverWalk(r, record, state, leg, c, x, y, z, "lift_landing_missed")
    end
    return false
end

local function PollTransport(r, record, state, leg, c, x, y)
    local from, to = leg.polestarFrom, leg.polestarTo
    if NearDock(to, c, x, y, DOCK_RADIUS) and not NearDock(from, c, x, y, 25) then
        state.rideProgress = nil
        return NS.AdvanceActiveRouteLeg(record, leg, state.generation, "polestar_transport_arrival")
    end
    if leg.taxi and leg.taxi.offerSerial and state.boardedTaxiLeg == leg then
        -- Landing away from the planned node ends the protection for this offer.
        state.boardedTaxiLeg = nil
        backend.OnPlanInvalidated("polestar_taxi_landed_elsewhere")
    end
    local ride = leg.polestarRide
    if not ride then return false end
    local progress = state.rideProgress
    if not progress or progress.leg ~= leg then
        if not NearDock(from, c, x, y, DOCK_RADIUS) then return false end
        progress = { leg = leg }
        state.rideProgress = progress
    end
    if progress.carrier then return false end
    if NearDock(from, c, x, y, DOCK_RADIUS) then return false end
    local observation = P.Call(r.Transit, "Riding")
    local hasDestination = type(observation) == "table" and observation.dock ~= nil
    local matches = hasDestination and observation.kind == leg.polestarKind and observation.dock == ride.dock
    if not matches then
        if hasDestination then return false end
        if not P.Call(r.Transit, "Carried") then
            state.rideProgress = nil; return false
        end
        if ride.shared then return false end
    end
    local seconds = matches and observation.arriveIn or ride.seconds
    progress.deadline = Finite(seconds) and seconds > 0 and GetTime() + seconds or nil
    progress.carrier = {
        mapID = ride.mapID,
        x = ride.x,
        y = ride.y,
        title = ride.title,
        kind = leg.kind,
        routeLegKind = leg.routeLegKind,
        routeTravelType = leg.routeTravelType,
    }
    return false, true
end

function backend.GetCarrierLeg(record, leg)
    local s = states[record]
    local ride = s and s.rideProgress
    if ride and ride.leg == leg then return ride.carrier end
end

function backend.GetTransportStatus(record)
    local s = states[record]
    local ride = s and s.rideProgress
    if ride and ride.leg == record.currentLeg and ride.carrier and Current(record, s) then
        return ride.carrier.title, ride.deadline
    end
end

function backend.PollNavigationLeg(record, sampled, c, px, py, height, observedAt)
    if Combat() or NS.State.routing.specialActionCasting
        or NS.IsRouteEquipmentTransactionActive and NS.IsRouteEquipmentTransactionActive() then
        return false
    end
    if NS.UpdateRouteDestinationArea then
        local arrived, changed, transitioned = NS.UpdateRouteDestinationArea(record)
        if arrived or transitioned then return changed or transitioned end
    end
    local state, r = states[record], Runtime()
    local leg = record and record.currentLeg
    if not state or state.areaRefreshPending or not r or not leg or not Current(record, state) then return false end
    if state.observedGroup and state.observedGroup ~= leg.polestarPath then
        ReleasePastGeometry(record,
            state.observedGroup)
    end
    state.observedGroup = leg.polestarPath
    local kind, to, from = leg.polestarKind, leg.polestarTo, leg.polestarFrom
    if kind == "lift" then
        if not sampled then c, px, py = backend.ReadNavigationProgress() end
        if px then return PollLift(r, record, state, leg, c, px, py) end
        return false
    end
    if kind == "walk" and not leg.polestarHandmade and (not leg.polestarApproach or leg.polestarApproachRetry)
        and state.walking and state.context then
        if not sampled then c, px, py = backend.ReadNavigationProgress() end
        if not px or not to or c ~= to.c then return false end
        local nextLeg = record.legs[(record.currentLegIndex or 1) + 1]
        local boarding = LiftEnds(nextLeg)
        if boarding and boarding.c == c and boarding.wx == to.wx and boarding.wy == to.wy
            and (px - to.wx) ^ 2 + (py - to.wy) ^ 2 <= 30 ^ 2 then
            local z = ObservedHeight(r, c)
            if not Finite(z) or not Finite(boarding.z) or math.abs(z - boarding.z) <= 3 then
                return NS.AdvanceActiveRouteLeg(record, leg, state.generation, "polestar_lift_boarding")
            end
        end
        if AdvancePassedWalk(r, record, state, leg, c, px, py, observedAt) then return true end
        if not state.pathTried then
            state.pathTried = true; state.path = Path(r)
        end
        local path = state.path
        if not path or state.job then return false end
        local group = leg.polestarPath
        if state.goal ~= leg and not (group or leg.polestarApproach) then state.quickRetried = nil end
        local quickRetry = not group and state.failed and state.quickRetryAt and GetTime() >= state.quickRetryAt
        if quickRetry then state.quickRetried, state.quickRetryAt = true, nil end
        local budgetRetry = not group and state.walkBudget ~= nil
        local needsPath = not group and
            (budgetRetry or state.leg ~= leg or state.owed or quickRetry or state.failed and GetTime() - state.asked >= 15
                and (px - state.failX) ^ 2 + (py - state.failY) ^ 2 >= 5 ^ 2)
        if group and from then
            local remaining = math.sqrt((px - to.wx) ^ 2 + (py - to.wy) ^ 2) + group.left[leg.polestarPathIndex]
            local reason = Walking.Deviation(leg.walking, c, px, py, ObservedHeight(r, c), 25)
            if reason or state.owed then
                RecoverWalk(r, record, state, leg, c, px, py, ObservedHeight(r, c), reason or "invalidated",
                    remaining > 2000 and 10 or 2)
            else
                Walking.CancelRecovery(state)
            end
            return false
        end
        if needsPath and WalkBudgetReady(record, state, leg, px, py) then
            RequestWalk(r, record, state, leg, path, c, px,
                py)
        end
        return false
    end
    if kind ~= "fly" and kind ~= "boat" and kind ~= "zeppelin" and kind ~= "airship" and kind ~= "tram" and kind ~= "portal" then return false end
    if not to or not from or P.Call(r.Compat, "IsOnTaxi") then return false end
    if not sampled then c, px, py = backend.ReadNavigationProgress() end
    if px then return PollTransport(r, record, state, leg, c, px, py) end
    return false
end

function backend.WantsNavigationProgress(record)
    return record.backend == "polestar" and states[record] ~= nil and record.currentLeg ~= nil
end

function backend.ReadNavigationProgress()
    local r = Runtime()
    local c, x, y = P.Call(r and r.Compat, "GetPlayerWorldPosition")
    local _, _, z = P.Call(r and r.Compat, "GetPlayerUnitPosition")
    return c, x, y, z
end

function backend.StopNavigationProgress(record, generation, reason)
    local s = states[record]
    if not s or s.generation ~= generation then return end
    local leg = record.currentLeg
    if reason == "taxi" and leg and leg.taxi and leg.taxi.offerSerial then s.boardedTaxiLeg = leg end
    local pending = s.job ~= nil
    CancelWalk(s)
    s.liftLeg, s.landingSeen = nil, nil
    s.progressAt, s.catchUp = nil, nil
    if pending or reason == "inactive" then s.owed = true end
end

function backend.GetWalkingDebugLine()
    local record = NS.GetActiveAuthorityRecord and NS.GetActiveAuthorityRecord()
    if not record or record.backend ~= "polestar" or not record.currentLeg then return end
    local leg, state = record.currentLeg, states[record]
    local area, arrival = record.target and record.target.navigationArea, record._routeDestinationAreaState
    local line = string.format(
        "walking=fixed leg=%s/%s point=%s@%.6f,%.6f terrain=%s search=%s generation=%s refresh=%s plan=%s radius=%s stop=%s advance=%s",
        tostring(record.currentLegIndex), tostring(record.legs and #record.legs), tostring(leg.mapID), leg.x, leg.y,
        tostring(leg.polestarPath ~= nil), state and state.job and "pending" or "idle",
        tostring(record._routeAcceptedPlanGeneration), tostring(record._coreLastRefreshReason),
        tostring(record.lastPlanSkipStatus),
        tostring(leg.arrivalRadius), tostring(leg.polestarRequired == true), tostring(record._coreLastAdvanceReason))
    if area then
        line = line .. string.format(" area=%s+%s arrived=%s camp=%s/%s searchArea=%s",
            tostring(area.radius), tostring(area.arrivalRadius), tostring(arrival and arrival.arrived),
            tostring(area.spot), tostring(area.spotCount), tostring(area.search))
    end
    line = line .. string.format(" caughtUp=%s movementLimit=%s rejected=%s",
        tostring(state and state.lastAdvanced), tostring(state and state.movementAllowance),
        tostring(Walking.ProgressReason(record, state)))
    line = line .. " recovery=" .. tostring(state and state.walkRecovery and state.walkRecovery.reason)
        .. " liftLanding=" .. tostring(state and state.landingSeen == true)
    local context = state and state.context
    if context then
        line = line .. string.format(" escort=%s timed=%s probableFlights=%s stone=%s teleports=%d",
            tostring(context._escort), tostring(context._timed), tostring(context.maybe ~= nil),
            tostring(context.noStone == false), context.teleports and #context.teleports or 0)
    end
    if state then
        line = line .. string.format(" walkStatus=%s checked=%s reason=%s hubs=%s goalHeight=%s",
            tostring(state.walkingStatus), tostring(state.walkingChecked), tostring(state.walkingReason),
            tostring(state.walkingHubs), tostring(state.context and state.context.target.z))
    end
    return line
end

function backend.GetNavigationStatus(record)
    local s = states[record]
    local leg = record and record.currentLeg
    if not s or not leg or not Current(record, s) or leg.polestarKind ~= "walk"
        or s.leg ~= leg and not ((leg.polestarPath or leg.polestarApproach)
            and (leg.polestarPath or leg.polestarApproach).goal == s.goal) then
        return
    end
    return s.walkingStatus, s.walkingHubs
end

function backend.CanAdvanceLeg(record, leg)
    if leg.polestarKind == "lift" then return false end
    if leg.taxi and leg.taxi.offerSerial then return false end
    if leg.polestarRide then return false end
    local state = states[record]
    local nextLeg = leg.kind == "entrance" and record.legs and record.legs[(record.currentLegIndex or 1) + 1]
    if nextLeg and nextLeg.mapID ~= leg.mapID and NS.GetPlayerMapID() == nextLeg.mapID then return end
    if state and state.job and state.leg == leg then return false end
    local to = leg.polestarTo
    if leg.polestarPath and to then
        local r = Runtime()
        local c, x, y = P.Call(r and r.Compat, "GetPlayerWorldPosition")
        if not x or c ~= to.c or (x - to.wx) ^ 2 + (y - to.wy) ^ 2 > leg.arrivalRadius ^ 2 then return false end
    end
    if state and to and Finite(to.z) then
        local r = Runtime()
        local c, x, y = P.Call(r and r.Compat, "GetPlayerWorldPosition")
        local z = r and x and Floor(r, state, c, x, y)
        if c ~= to.c or not z or math.abs(z - to.z) > (leg.polestarKind == "lift" and 6 or 10) then return false end
    end
end

function backend.Clear(record)
    if type(record) ~= "table" then return end
    CancelWalk(states[record])
    ClearWalkBudget(states[record])
    if pendingMeasure and pendingMeasure.record == record then CancelMeasure() end
    states[record] = nil
    record._routeDestinationAreaState = nil
    NS.ClearAcceptedRoutePlan(record)
end

function backend.OnPlanInvalidated(reason)
    return NS.RequestRouteBackendStateValidation("polestar", reason,
        (reason == "SPELL_UPDATE_COOLDOWN" or reason == "BAG_UPDATE_COOLDOWN") and "cooldown" or "structural")
end

-- ============================================================
-- Event subscriptions and invalidation
-- ============================================================

function backend.Initialize()
    if not NS.IsWoWForever() then return end
    if backend.frame then return end
    NS.RegisterRouteBackendStateValidator("polestar", Snapshot, NS.ProbeRouteTravelDependency)
    local frame = CreateFrame("Frame")
    backend.frame = frame
    frame:Hide()
    local closeValidation
    local taxiWindow = NS.Internal.TaxiWindow
    if taxiWindow then
        taxiWindow.Subscribe(function(taxiFrame)
            if closeValidation then
                closeValidation:Cancel(); closeValidation = nil
            end
            if taxiFrame then
                backend.OnPlanInvalidated("polestar_flight_window")
                return
            end
            local record = NS.GetActiveAuthorityRecord()
            local leg = record and record.currentLeg
            if record and record.backend == "polestar" and leg and leg.taxi and leg.taxi.offerSerial then
                -- The taxi window can close before the next movement sample
                -- reports the player onboard. Settle once before invalidating.
                closeValidation = C_Timer.NewTimer(0.2, function()
                    closeValidation = nil
                    if NS.IsActiveRouteRecord(record, false) and record.currentLeg == leg then
                        backend.OnPlanInvalidated("polestar_flight_window_closed")
                    end
                end)
            else
                backend.OnPlanInvalidated("polestar_flight_window_closed")
            end
        end)
    end
    local function installGraphHooks()
        local r = Runtime()
        if not r or type(r.Nav) ~= "table" or hookedGraphs[r.Nav] then return end
        hookedGraphs[r.Nav] = true
        P.Call(r, "On", "NAV_TRANSIT", function() backend.OnPlanInvalidated("polestar_transit") end)
        local escort = P.Call(r.Engine, "EscortRunning") == true
        local function checkEscort()
            if Combat() then
                backend.OnPlanInvalidated("polestar_escort"); return
            end
            local current = P.Call(r.Engine, "EscortRunning") == true
            if current ~= escort then
                escort = current; backend.OnPlanInvalidated("polestar_escort")
            end
        end
        P.Call(r, "On", "STEP_UPDATED", checkEscort)
        P.Call(r, "On", "STEP_CHANGED", checkEscort)
        for _, method in ipairs({ "RegisterTravelData", "AddTravelPaths", "RegisterCrossings" }) do
            if type(r.Nav[method]) == "function" then
                hooksecurefunc(r.Nav, method, function()
                    graphEpoch, graphFingerprint = graphEpoch + 1, nil
                    measures, measureOrder = {}, {}
                    CancelMeasure()
                    backend.OnPlanInvalidated("polestar_graph_changed")
                end)
            end
        end
    end
    installGraphHooks()
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED",
        "HEARTHSTONE_BOUND", "PLAYER_LEVEL_UP", "QUEST_LOG_UPDATE",
        "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "ADDON_LOADED" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" then
            local terrain = type(name) == "string" and (name == "Polestar_Nav" or name:match("^Polestar_Nav_") ~= nil)
            if name == "Polestar" or terrain then
                installGraphHooks()
                if terrain then
                    graphEpoch, graphFingerprint = graphEpoch + 1, nil
                    measures, measureOrder = {}, {}
                    CancelMeasure()
                end
                for record, state in pairs(states) do
                    if terrain then
                        InvalidateWalkingGeometry(record, state)
                    else
                        state.pathTried, state.owed = nil, state.walking == true
                    end
                end
                local record = NS.GetActiveAuthorityRecord and NS.GetActiveAuthorityRecord()
                if record and record.backend == backend.id and NS.RequestRouteNavigationProgress then
                    NS.RequestRouteNavigationProgress(record, "polestar_data_ready")
                end
                backend.OnPlanInvalidated("polestar_data_ready")
            end
        elseif event == "PLAYER_LOGOUT" then
            CancelMeasure()
            for _, state in pairs(states) do
                CancelWalk(state)
                ClearWalkBudget(state)
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            CancelMeasure()
            for _, state in pairs(states) do
                local owed = state.job ~= nil
                CancelWalk(state); state.owed = state.owed or owed
                state.progressAt = nil
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            local record = NS.GetActiveAuthorityRecord and NS.GetActiveAuthorityRecord()
            if record and record.backend == backend.id and NS.RequestRouteNavigationProgress then
                NS.RequestRouteNavigationProgress(record, "polestar_combat_rearm")
            end
            return
        else
            backend.OnPlanInvalidated(event)
        end
    end)
end
