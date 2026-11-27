-- ============================================================
-- QuestieRouter routing backend
-- ============================================================
--
-- Translates QuestieRouter's travel search into route legs and advances its
-- road and transport sections.

local NS = _G.AzerothWaypointNS
local backend = {
    id = "questierouter",
    preserveItinerary = true,
    canFollowRouteInCombat = true,
    counters = { planned = 0, plannerCalls = 0, paths = 0, retries = 0, failed = 0, cancelled = 0, stale = 0 }
}
NS.RoutingBackend_QuestieRouter = backend
local Walking = NS.Internal.RouteWalking
local Coordinates = NS.Internal.QuestieRouterRuntime
local Finite, Call = Coordinates.Number, Coordinates.Call
local progress = setmetatable({}, { __mode = "k" })
local graphRevision, terrainRevision = 0, 0
local routeSettings = { "enabled", "flights", "boats", "routeStyle", "gridRoutes", "taxiSpeed", "axisSwap" }
local navigationPacks = { QuestieRouter_Nav = true, QuestieRouter_Nav_EK = true, QuestieRouter_Nav_Kalimdor = true }
local requiredAddons = NS.Internal.RoutingBackends.byID.questierouter.addons
local Runtime, PlayerWorld, World = Coordinates.Get, Coordinates.PlayerWorld, Coordinates.WorldPoint
local NEAR, SHORT_WALK = 35, 700
local OFF_PATH = 30 -- QuestieRouter's terrain deviation threshold, in yards.
local FLOOR_TOLERANCE = 10
local BEND_APPROACH, BEND_DEPARTURE = 8, 12
local TERRAIN_TIMEOUT, RETRY_SECONDS, RETRY_YARDS = 8, 15, 25
local WALK_RECOVERY = { interval = 2, retrySeconds = RETRY_SECONDS, retryDistance = RETRY_YARDS }

local function Planner()
    if not NS.IsWoWForever() then return nil, "questierouter_wrong_client", "unavailable" end
    local q = Runtime()
    if q and q.ready == true and type(q.db) == "table" then
        if type(q.Router) ~= "table" or type(q.Router.Plan) ~= "function" then
            return nil, "questierouter_missing_router", "unavailable"
        end
        if type(q.HBD) == "table" and type(q.HBD.GetWorldCoordinatesFromZone) == "function"
            and type(q.HBD.GetPlayerWorldPosition) == "function" and type(q.ZoneCoordsFromWorld) == "function" then
            return q
        end
    end
    for _, name in ipairs(requiredAddons) do
        if not NS.IsAddonLoaded(name)
            and (not NS.IsAddonEnabledForCurrentCharacter or not NS.IsAddonEnabledForCurrentCharacter(name)) then
            return nil, name .. "_missing_or_disabled", "unavailable"
        end
    end
    if q and q.ready == true then return nil, "questierouter_missing_map_bridge", "waiting" end
    return nil, "questierouter_initializing", "waiting"
end
function backend.GetReadiness()
    local q, reason, status = Planner()
    return q and "ready" or status, reason
end

function backend.IsAvailable()
    local status, reason = backend.GetReadiness()
    return status == "ready", reason
end

local function Fingerprint(q)
    local cfg, parts = q.db.travel or {}, {}
    for _, key in ipairs(routeSettings) do
        parts[#parts + 1] = key .. "=" .. tostring(cfg[key])
    end
    parts[#parts + 1] = "graph:" .. graphRevision
    -- The itinerary uses these settings and travel data independently of terrain refinement.
    local times = {}
    for key in pairs(cfg.times or {}) do times[#times + 1] = key end
    table.sort(times)
    for _, key in ipairs(times) do parts[#parts + 1] = tostring(key) .. "=" .. tostring(cfg.times[key]) end
    for _, road in ipairs(q.db.customRoads or {}) do
        parts[#parts + 1] = "road:" .. tostring(road[1])
        for _, coord in ipairs(road[2] or {}) do parts[#parts + 1] = tostring(coord) end
    end
    local ids = {}
    for id, value in pairs(q.charDB and q.charDB.knownTaxi or {}) do if value == true then ids[#ids + 1] = tostring(id) end end
    table.sort(ids); for _, id in ipairs(ids) do parts[#parts + 1] = id end
    parts[#parts + 1] = tostring(UnitFactionGroup("player"))
    parts[#parts + 1] = tostring(UnitLevel("player"))
    parts[#parts + 1] = tostring(IsMounted and IsMounted() == true)
    return table.concat(parts, "|")
end

local function Snapshot()
    if InCombatLockdown() then return false, "combat" end
    local q, reason = Planner()
    if not q then return false, reason end
    return true, Fingerprint(q)
end

-- ============================================================
-- Coordinate and endpoint conversion
-- ============================================================

local function Point(q, p)
    if type(p) ~= "table" then return end
    local map, x, y = Coordinates.MapPoint(q, p.inst, p.x, p.y, p.zone)
    if not map then return end
    return {
        c = p.inst,
        wx = p.x,
        wy = p.y,
        mapID = map,
        x = x,
        y = y,
        name = type(p.name) == "string" and p.name or nil,
        nodeID = Finite(p.nodeId) and p.nodeId or nil,
        nodeKind = type(p.kind) == "string" and p.kind or nil,
        zone = Finite(p.zone) and p.zone or nil
    }
end
local function RoutingZone(map)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    -- Router:Plan expects the zone or city containing a submap.
    for _ = 1, 6 do
        if not Finite(map) or map <= 0 then return end
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        if not info or not Finite(info.mapType) or info.mapType <= zoneType then return map end
        if info.parentMapID == map then return map end
        map = info.parentMapID
    end
    return map
end
local movement = { walk = true, road = true, border = true }
local transport = {
    flight = "taxi",
    boat = "ship",
    zeppelin = "zeppelin",
    airship = "airship",
    tram = "travel",
    portal =
    "portal",
    door = "portal"
}
local verbs = {
    flight = "Fly to ",
    boat = "Take the boat to ",
    zeppelin = "Take the zeppelin to ",
    airship = "Take the airship to ",
    tram = "Take the tram to ",
    portal = "Take the portal to ",
    door = "Enter "
}
local function CopyRoute(q, route, origin, goal)
    if type(route) ~= "table" or #route == 0 or #route > 512 then return end
    local out = {}
    for _, edge in ipairs(route) do
        if type(edge) ~= "table" or (not movement[edge.kind] and not transport[edge.kind]) then return end
        local from = type(edge.from) == "table" and edge.from.start and origin or Point(q, edge.from)
        local to = type(edge.to) == "table" and edge.to.goal and goal or Point(q, edge.to)
        if not from or not to then return end
        local previous = out[#out]
        if edge.kind == "flight" and previous and previous.kind == "flight" and previous.to.c == from.c
            and previous.to.wx == from.wx and previous.to.wy == from.wy then
            previous.to = to
        else
            out[#out + 1] = { kind = edge.kind, from = from, to = to }
        end
    end
    return out
end
---@return any
local function Engine()
    local name = "QuestieRouter_Nav"
    if not NS.IsAddonLoaded(name) then
        if not C_AddOns or not C_AddOns.LoadAddOn or not NS.IsAddonEnabledForCurrentCharacter
            or not NS.IsAddonEnabledForCurrentCharacter(name) then
            return
        end
        local ok, loaded = pcall(C_AddOns.LoadAddOn, name)
        if not ok or not loaded then return end
    end
    local path = rawget(_G, "QuestieRouter_NavEngine")
    return type(path) == "table" and type(path.Find) == "function" and type(path.Cancel) == "function" and path or nil
end
local function SquareDistance(point, x, y)
    return (x - point.wx) ^ 2 + (y - point.wy) ^ 2
end

-- Several walkable surfaces can share one XY. Prefer the player's subzone,
-- then an indoor surface when the client reports indoors. Outdoor city
-- streets can carry the indoor mark too, so outdoors alone proves nothing.
local surfaces, areaIDs = {}, {}
local function SurfaceFloor(engine, c, x, y, zone, previous, indoors)
    local ok, n = pcall(engine.SurfacesAt, c, y, x, surfaces, areaIDs)
    if not ok then return nil, "unavailable" end
    if not n then return nil, "pending" end
    if n == 0 then return nil, "unmapped" end
    local rank = 0
    local low, high, nearLow, nearHigh, nearest
    for i = 1, n do
        local h = surfaces[i]
        if not Finite(h) then return nil, "unmapped" end
        local evidence = 1
        if zone and areaIDs[i] and areaIDs[i] ~= 0 and engine.AreaName and engine.AreaName(c, areaIDs[i]) == zone then
            evidence = 3
        elseif indoors and (surfaces[-i] or 0) % 4 >= 2 then
            evidence = 2
        end
        if evidence > rank then
            rank, low, high, nearLow, nearHigh, nearest = evidence, nil, nil, nil, nil, nil
        end
        if evidence == rank then
            low, high = math.min(low or h, h), math.max(high or h, h)
            if previous and math.abs(h - previous) <= FLOOR_TOLERANCE then
                nearLow, nearHigh = math.min(nearLow or h, h), math.max(nearHigh or h, h)
                if not nearest or math.abs(h - previous) < math.abs(nearest - previous) then nearest = h end
            end
        end
    end
    if high - low <= FLOOR_TOLERANCE then
        return nearest or low, rank == 3 and "subzone" or rank == 2 and "indoors" or "terrain"
    end
    if nearest and nearHigh - nearLow <= FLOOR_TOLERANCE then return nearest, "continuity" end
    return nil, "ambiguous", low, high
end

function backend.ReadNavigationProgress(record)
    local c, x, y = PlayerWorld(rawget(_G, "QuestieRouter"))
    if not c then return end
    local _, _, z, instance = UnitPosition("player")
    local state = record and progress[record]
    -- Forever can return zero throughout Thunder Bluff. Passing that zero
    -- to Find creates a fictitious climb from sea level to the first corner.
    if Finite(instance) and instance == c and Finite(z) and z ~= 0 then
        if state then
            state.floorC, state.floorX, state.floorY, state.floorZ, state.floorSource = c, x, y, z, "player"
            state.floorAt = GetTime()
        end
        return c, x, y, z
    end
    local engine = rawget(_G, "QuestieRouter_NavEngine")
    local leg = record and record.currentLeg
    local edge = leg and leg.questieRouterEdge
    if not state or not state.walking or not leg or not leg.walking and not (edge and (edge.kind == "walk" or edge.kind == "road"))
        or not engine or not engine.SurfacesAt or not engine.Resident or not engine.Resident(c)
        or UnitOnTaxi("player") or IsFlying and IsFlying() or IsFalling and IsFalling() then
        if state then state.floorC, state.floorZ, state.floorSource = nil, nil, "unknown" end
        return c, x, y
    end
    local now = GetTime()
    local zone = GetSubZoneText and GetSubZoneText()
    local indoors = IsIndoors and IsIndoors()
    local same = state.floorC == c and state.floorX == x and state.floorY == y
    if same and state.floorSource ~= "player" and state.floorZone == zone and state.floorIndoors == indoors
        and state.floorRevision == terrainRevision
        and (state.floorSource ~= "pending" or now < state.floorAt + .5 or InCombatLockdown()) then
        if state.floorSource ~= "pending" then state.floorAt = now end
        return c, x, y, state.floorZ
    end
    local w = leg.walking
    local previous = state.floorC == c and state.floorZ and now - state.floorAt <= 1
        and not (w and (w.from.floorTransition or w.to.floorTransition))
        and (state.floorX - x) ^ 2 + (state.floorY - y) ^ 2 <= 10 ^ 2 and state.floorZ
    state.floorZ, state.floorSource, state.floorLow, state.floorHigh = SurfaceFloor(engine, c, x, y, zone, previous,
        indoors)
    state.floorC, state.floorX, state.floorY, state.floorAt = c, x, y, now
    state.floorZone, state.floorIndoors, state.floorRevision = zone, indoors, terrainRevision
    return c, x, y, state.floorZ
end

local function DestinationLegs(attempt, intent, target, goal, edges)
    local final = NS.RouteSpecials.MakeDestinationLeg(backend.id, attempt.mapID, attempt.x, attempt.y, attempt.title)
    local endpoint = final
    if intent and intent.entrance then
        endpoint = NS.RouteSpecials.MakeDestinationLeg(backend.id, target.mapID, target.x, target.y,
            "Enter " .. (intent.instanceName or "the instance"))
        endpoint.kind, endpoint.routeLegKind, endpoint.routeTravelType = "entrance", "carrier", intent.travelType
        endpoint.arrivalRadius = 12
    end
    local legs = {}
    for index, edge in ipairs(edges) do
        local moving = movement[edge.kind]
        local to, from = edge.to, edge.from
        local p = moving and to or from
        local walkingTitle = edge.kind == "border" and "Follow the crossing"
            or edge.kind == "road" and "Follow the road" or "Follow the path"
        local leg
        if index == #edges and moving and edge.kind ~= "border" and to.c == goal.c
            and SquareDistance(to, goal.wx, goal.wy) <= 0.00000001 then
            leg = endpoint
            edge.to = goal
        else
            local name = not moving and (to.name or (C_Map and C_Map.GetMapInfo(to.mapID) or {}).name or "destination")
            leg = {
                mapID = p.mapID,
                x = p.x,
                y = p.y,
                title = moving and walkingTitle or verbs[edge.kind] .. name,
                kind = moving and "walk" or edge.kind == "flight" and "taxi" or edge.kind,
                routeLegKind = "carrier",
                routeTravelType = moving and "travel" or transport[edge.kind],
                source = backend.id,
                arrivalRadius = 12
            }
            if not moving then
                leg.activationCoords = { mapID = from.mapID, x = from.x, y = from.y }
                if edge.kind == "flight" then
                    leg.taxi = { sourceNodeID = from.nodeID, nodeID = to.nodeID, name = to.name, operator = backend.id }
                end
            end
        end
        leg.questieRouterEdge = edge
        leg.preservePlanOnArrival = true
        if moving then
            local nextEdge = edges[index + 1]
            local role = nextEdge and
                ({ flight = "the flight master", boat = "the boat", zeppelin = "the zeppelin tower",
                    airship = "the airship", tram = "the tram", portal = "the portal", door = "the entrance" })
                [nextEdge.kind]
            local crossing = edge.kind == "border" and C_Map and C_Map.GetMapInfo(to.zone or to.mapID)
            NS.Internal.RouteWalkingPresentation.Describe(leg, edge.kind == "road" and "road"
                or edge.kind == "border" and "crossing" or "path", leg, to.name or role or crossing and crossing.name)
        end
        legs[#legs + 1] = leg
    end
    if legs[#legs] ~= endpoint then legs[#legs + 1] = endpoint end
    if final ~= endpoint then legs[#legs + 1] = final end
    return legs
end

-- ============================================================
-- Travel planning
-- ============================================================

local function Plan(q, origin, goal, startZone, goalZone, walkOnly)
    backend.counters.plannerCalls = backend.counters.plannerCalls + 1
    return pcall(q.Router.Plan, q.Router, origin.wx, origin.wy, origin.c, startZone,
        goal.wx, goal.wy, goal.c, goalZone, walkOnly)
end

function backend.BeginPlan(attempt)
    local q, unavailable = Planner()
    if not q then return attempt:Complete({ status = "failed", reason = unavailable }) end
    local cfg = q.db.travel or {}
    local intent = NS.ResolveInstanceRouteIntent and
        NS.ResolveInstanceRouteIntent(attempt.mapID, attempt.x, attempt.y, attempt.title)
    local target = intent and intent.entrance or attempt
    local goal = World(q, target.mapID, target.x, target.y)
    local c, px, py = PlayerWorld(q)
    if not goal or not c then return attempt:Complete({ status = "failed", reason = "missing_position" }) end
    local map = NS.GetPlayerMapID()
    local origin = { c = c, wx = px, wy = py, mapID = map }
    local startZone = RoutingZone(Call(q.HBD, "GetPlayerZone")) or RoutingZone(map)
    local goalZone = RoutingZone(goal.mapID)
    local edges
    if cfg.enabled then
        local short = c == goal.c and startZone and startZone == goalZone and
            SquareDistance(goal, px, py) < SHORT_WALK ^ 2
        local ok, native, cost = Plan(q, origin, goal, startZone, goalZone, short == true)
        if not ok then
            return attempt:Complete({
                status = "failed",
                reason = "questierouter_planner_error",
                detail =
                    tostring(native)
            })
        end
        if not native then return attempt:Complete({ status = "failed", reason = "questierouter_no_path" }) end
        edges = CopyRoute(q, native, origin, goal)
        if not edges then return attempt:Complete({ status = "failed", reason = "invalid_route" }) end
        if not short and c == goal.c and Finite(cost) then
            for _, edge in ipairs(edges) do
                if transport[edge.kind] then
                    -- Native transport policy requires a 15% saving over walking.
                    local walked, walk, walkCost = Plan(q, origin, goal, startZone, goalZone, true)
                    if walked and walk and Finite(walkCost) and cost > walkCost * 0.85 then
                        edges = CopyRoute(q, walk, origin, goal) or edges
                    end
                    break
                end
            end
        end
    elseif c == goal.c then
        edges = { { kind = "walk", from = origin, to = goal } }
    else
        edges = {}
    end
    attempt.record._routeBackendStateFingerprint = Fingerprint(q)
    attempt.walking, attempt.style = cfg.gridRoutes ~= false, cfg.routeStyle
    backend.counters.planned = backend.counters.planned + 1
    return attempt:Complete({
        status = "success",
        backendID = backend.id,
        legs = DestinationLegs(attempt, intent, target, goal, edges),
        reason = "questierouter_plan",
        mode = not cfg.enabled and "intentional_direct" or nil
    })
end

local function CancelSearch(state)
    local job = state and state.job
    if not job then return end
    state.job = nil
    if job.timer then job.timer:Cancel() end
    if job.handle then pcall(job.engine.Cancel, job.handle) end
    backend.counters.cancelled = backend.counters.cancelled + 1
end

local function CancelRetry(state)
    if state and state.retry then
        state.retry:Cancel(); state.retry = nil
    end
end

function backend.ReleasePlan(owner)
    Walking.CancelRecovery(progress[owner])
    CancelSearch(progress[owner])
    CancelRetry(progress[owner])
    progress[owner] = nil
    Walking.Forget(owner)
end

function backend.AdoptPlan(attempt, owner)
    progress[owner] = { walking = attempt.walking, style = attempt.style }
    owner._routeBackendStateFingerprint = attempt.record._routeBackendStateFingerprint
    if NS.RequestRouteNavigationProgress then NS.RequestRouteNavigationProgress(owner, "questierouter_plan") end
end

-- Preserve the snapped terrain stop (and its floor) separately when the
-- requested destination is off mesh. The final leg keeps its exact map pin.
local function CopyPath(q, path, edge)
    if type(path) ~= "table" or #path < 2 or #path > 8192 then return end
    local points = {}
    local exact = edge.to
    local hasFloorTransition
    for i, native in ipairs(path) do
        local wx, wy, z = Coordinates.FromTerrain(native)
        if not wx then return end
        local map, x, y = Coordinates.MapPoint(q, exact.c, wx, wy, exact.mapID, edge.from.mapID)
        if not map then return end
        local previous = points[i - 1]
        local changesFloor = previous and Finite(previous.z) and Finite(z)
            and math.abs(previous.z - z) >= 20 and SquareDistance(previous, wx, wy) <= 20 ^ 2
        if changesFloor then
            previous.required, previous.floorTransition = true, true
            hasFloorTransition = true
        end
        points[i] = {
            c = exact.c,
            wx = wx,
            wy = wy,
            mapID = map,
            x = x,
            y = y,
            z = z,
            floorTransition = changesFloor,
            required = changesFloor or i == #path
        }
    end
    local last = points[#points]
    if SquareDistance(exact, last.wx, last.wy) > 1 then
        points[#points + 1] = {
            c = exact.c,
            wx = exact.wx,
            wy = exact.wy,
            mapID = exact.mapID,
            x = exact.x,
            y = exact.y,
            required = true
        }
    else
        last.mapID, last.x, last.y = exact.mapID, exact.x, exact.y
        last.wx, last.wy = exact.wx, exact.wy
    end
    if not hasFloorTransition then points.airborne = { container = "questierouter:" .. exact.c } end
    return points
end

local function HasClearApproach(engine, c, x, y, z, goal)
    if not engine or type(engine.Sight) ~= "function" or not Finite(z) then return end
    local ok, clear = pcall(engine.Sight, c, y, x, z, goal.wy, goal.wx, goal.z, UnitFactionGroup("player"))
    if ok then return clear end
end

local function FollowingRoad(record, section, edge)
    local via = edge.to
    if via.nodeKind ~= "road" or edge.kind ~= "walk" and edge.kind ~= "road" then return end
    local i = record.currentLegIndex
    if section then
        while record.legs[i] and record.legs[i] ~= section.endpoint do i = i + 1 end
    end
    local leg = record.legs[i + 1]
    local nextEdge = leg and leg.questieRouterEdge
    if nextEdge and (nextEdge.kind == "road" or nextEdge.kind == "walk")
        and nextEdge.from.nodeKind == "road" and nextEdge.from.c == via.c and nextEdge.to.c == via.c
        and nextEdge.from.mapID == via.mapID and nextEdge.to.mapID == via.mapID
        and SquareDistance(nextEdge.from, via.wx, via.wy) < .00000001 then
        return leg
    end
end

-- ============================================================
-- Road geometry and progression
-- ============================================================

local function PrepareRoadExit(engine, points, nextLeg)
    local via = points[#points]
    if via.floorTransition or not engine.SurfacesAt then return end
    -- An off-mesh endpoint has a separate required approach before it.
    if #points > 2 and points[#points - 1].required then return end
    local z = via.z or SurfaceFloor(engine, via.c, via.wx, via.wy)
    if not Finite(z) then return end
    local dest = nextLeg.questieRouterEdge.to
    local dx, dy = dest.wx - via.wx, dest.wy - via.wy
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1 then return end
    local fraction = math.min(1, Walking.RejoinDistance / length)
    local probe = { c = via.c, wx = via.wx + dx * fraction, wy = via.wy + dy * fraction }
    probe.z = SurfaceFloor(engine, probe.c, probe.wx, probe.wy)
    if not Finite(probe.z) or not HasClearApproach(engine, via.c, via.wx, via.wy, z, probe) then return end
    via.z, via.required = z, false
    points.continuation = { leg = nextLeg, to = probe }
end

local function CurrentSearch(record, state, job)
    return progress[record] == state and state.job == job
        and record.currentLeg == job.leg and record._routeAcceptedPlanGeneration == job.generation
        and NS.IsActiveRouteRecord(record, false)
end

local function WakeCarrier(record)
    C_Timer.After(0, function()
        if progress[record] and NS.IsActiveRouteRecord(record, false) then NS.RecomputeCarrier() end
    end)
end

local function RequestWalk(record, state, q, edge, c, x, y, z, recovery)
    local leg = record.currentLeg
    local generation = record._routeAcceptedPlanGeneration
    local section = leg.walking and leg.walking.group
    local original = section and section.terrainLeg or leg
    local nextRoad = FollowingRoad(record, section, edge)
    local function Straight(reason)
        if section then
            if not NS.ReplaceActiveRouteLegs(record, leg, generation, { original }, section.endpoint) then
                if recovery then Walking.CompleteRecovery(state, recovery, false, "replacement_rejected") end
                return
            end
            state.leg = record.currentLeg
        end
        state.terrain, state.failedAt = reason, nil
        if recovery then Walking.CompleteRecovery(state, recovery, true, reason) end
        WakeCarrier(record)
    end
    local distance = SquareDistance(edge.to, x, y)
    state.checkedRevision = terrainRevision
    local engine = Engine()
    if not engine then
        state.terrain = "no_terrain"
        if recovery then Walking.CompleteRecovery(state, recovery, false, state.terrain) end
        return
    end
    local ok, available = pcall(engine.Available, c)
    if not ok or not available then
        state.terrain = "no_terrain"
        if recovery then Walking.CompleteRecovery(state, recovery, false, state.terrain) end
        return
    end
    -- Loading the engine can fire a data-pack signal synchronously.
    state.checkedRevision = terrainRevision
    local function Install(points, startX, startY)
        if nextRoad then PrepareRoadExit(engine, points, nextRoad) end
        local endpoint = {}
        for key, value in pairs(original) do endpoint[key] = value end
        local walkingTitle = edge.kind == "road" and "Follow the road" or "Follow the path"
        local legs = Walking.BuildFixedLegs(points, endpoint, backend.id, walkingTitle)
        if #legs == 1 and not endpoint.walking then return Straight("straight") end
        local group = endpoint.walking.group
        group.terrainLeg, group.first, group.startX, group.startY = original, points[1], startX, startY
        if not NS.ReplaceActiveRouteLegs(record, leg, generation, legs, section and section.endpoint) then
            return false
        end
        state.terrain, state.failedAt = "fixed", nil
        if recovery then Walking.CompleteRecovery(state, recovery, true) end
        WakeCarrier(record)
        return true
    end
    local function ClearApproach(startX, startY, startZ)
        if not nextRoad then return Straight("clear_approach") end
        local via = edge.to
        local points = {
            { c = c, wx = startX, wy = startY, z = startZ },
            { c = c, wx = via.wx, wy = via.wy, mapID = via.mapID, x = via.x, y = via.y, z = via.z, required = true },
        }
        if Install(points, startX, startY) == false and recovery then
            Walking.CompleteRecovery(state, recovery, false, "replacement_rejected")
        end
    end
    local clear
    if distance < NEAR ^ 2 then clear = HasClearApproach(engine, c, x, y, z, edge.to) end
    if clear == true then return ClearApproach(x, y, z) end

    local job = { engine = engine, leg = leg, generation = generation, graph = graphRevision }
    if recovery then recovery.cancel = function() if state.job == job then CancelSearch(state) end end end
    local origin = { c = c, x = x, y = y, z = z }
    if state.failedAt then backend.counters.retries = backend.counters.retries + 1 end
    state.job, state.failedAt, state.terrain = job, nil, "searching"
    backend.counters.paths = backend.counters.paths + 1
    local function Fail(reason)
        state.terrain, state.failedAt, state.failX, state.failY, state.failZ = reason, GetTime(), x, y, z
        if recovery then Walking.CompleteRecovery(state, recovery, false, reason) end
        backend.counters.failed = backend.counters.failed + 1
    end
    local function Done(path, reason)
        if not CurrentSearch(record, state, job) then
            if recovery then Walking.CancelRecovery(state, recovery) end
            backend.counters.stale = backend.counters.stale + 1
            return
        end
        state.job = nil
        if job.timer then job.timer:Cancel() end
        local cfg = q.db.travel
        if InCombatLockdown() or NS.Internal.RouteProgress.IsBlocked(record) or job.graph ~= graphRevision
            or cfg and (cfg.gridRoutes == false or cfg.routeStyle ~= state.style) then
            state.checkedRevision = nil
            if recovery then Walking.CancelRecovery(state, recovery) end
            return
        end
        local currentC, currentX, currentY, currentZ = backend.ReadNavigationProgress(record)
        if not Walking.OriginMatches(origin, currentC, currentX, currentY, currentZ, RETRY_YARDS) then
            if recovery and Finite(z) and Finite(currentZ) and math.abs(z - currentZ) > 10 then
                Walking.CancelRecovery(state, recovery)
                state.checkedRevision, state.failedAt, state.terrain = nil, nil, "position_changed"
                NS.RequestRouteNavigationProgress(record, "questierouter_origin_changed")
                return
            end
            Fail("position_changed")
            if not recovery then
                state.checkedRevision = nil
                NS.RequestRouteNavigationProgress(record, "questierouter_origin_changed")
            end
            return
        end
        if clear == nil and SquareDistance(edge.to, currentX, currentY) < NEAR ^ 2
            and HasClearApproach(engine, c, currentX, currentY, currentZ, edge.to) == true then
            ClearApproach(currentX, currentY, currentZ)
            return
        end
        local points = CopyPath(q, path, edge)
        if not points then return Fail(type(reason) == "string" and reason or "no_terrain_path") end
        if Install(points, x, y) == false then Fail("replacement_rejected") end
    end
    local started, handle = pcall(engine.Find, c, Coordinates.ToTerrain(x, y, z),
        Coordinates.ToTerrain(edge.to.wx, edge.to.wy, edge.to.z), Done,
        { profile = UnitFactionGroup("player"), style = state.style, waterWalking = false })
    if state.job ~= job then return end
    if not started or not handle then return Done(nil, "terrain_search_error") end
    job.handle = handle
    job.timer = C_Timer.NewTimer(TERRAIN_TIMEOUT, function()
        if not CurrentSearch(record, state, job) then return end
        CancelSearch(state)
        Fail("terrain_timeout")
    end)
end

local function NeedsNewApproach(state, leg, c, x, y, z)
    local walk = leg.walking
    local a, b, group = walk.from, walk.to, walk.group
    if not group.terrainLeg or c ~= a.c or c ~= b.c then return false end
    -- The engine can snap the first point to reachable terrain. Searching
    -- again from the same origin would give the same approach.
    local reason = Walking.Deviation(walk, c, x, y, z, OFF_PATH)
    if reason == "off_path" and a == group.first
        and (x - group.startX) ^ 2 + (y - group.startY) ^ 2 < RETRY_YARDS ^ 2 then
        return
    end
    if reason then return reason end
    -- A bend on stacked terrain can remain unconfirmed even after the player
    -- walks through it. Have the native planner find the rest of this edge
    -- from the new position. Passing an unknown floor never completes a stop.
    if walk.required or Finite(z) or not Finite(b.z) or state.floorSource ~= "ambiguous" then return end
    local distance = SquareDistance(b, x, y)
    if distance <= BEND_APPROACH ^ 2 then state.nearBend = leg end
    if state.nearBend == leg and distance >= BEND_DEPARTURE ^ 2
        and (x - b.wx) * walk.ux + (y - b.wy) * walk.uy >= -1
        and (x - group.startX) ^ 2 + (y - group.startY) ^ 2 >= BEND_DEPARTURE ^ 2 then
        return "passed_unresolved_bend"
    end
end

-- The terrain worker handles movement within an outdoor map, including a
-- deviation from its path. A subzone name alone does not invalidate it.
function backend.CanRetainOutdoorWalk(record)
    return record.currentLeg and record.currentLeg.walking ~= nil
end

function backend.WantsNavigationProgress(record)
    local leg = record.currentLeg
    local edge = leg and leg.questieRouterEdge
    local state = progress[record]
    if not state or not edge and not (leg and leg.walking) then return false end
    if leg.walking or leg.routeLegKind ~= "destination" then return true end
    return state.walking and (leg ~= state.leg or state.checkedRevision ~= terrainRevision
        or state.job ~= nil or state.failedAt ~= nil)
end

function backend.CanAdvanceLeg(record, leg)
    local edge, walking = leg.questieRouterEdge, leg.walking
    if edge and transport[edge.kind] then
        -- Only PollNavigationLeg may advance a transport. Leaving the source
        -- map alone is insufficient for a ferry, flight or same-map portal.
        return false
    end
    if walking and Finite(walking.to.z) then
        local state = progress[record]
        if not state or state.sampleLeg ~= leg then return false end
        local goal = walking.to.z
        if Finite(state.sampleZ) then return math.abs(state.sampleZ - goal) <= FLOOR_TOLERANCE end
        -- Distance arrival at an ordinary bend is valid when *every* possible
        -- surface meets its height tolerance. This does not assign the player a
        -- height for pathfinding, skipping ahead or completing a lift.
        return not walking.required and state.sampleLow ~= nil
            and state.sampleLow >= goal - FLOOR_TOLERANCE and state.sampleHigh <= goal + FLOOR_TOLERANCE
    end
    local state = progress[record]
    if state and state.job and state.job.leg == leg then return false end
end

local function AdvanceTransport(record, state, leg, edge, c, x, y)
    local from, to = edge.from, edge.to
    local sourceDistance = c == from.c and SquareDistance(from, x, y)
    local arrivalDistance = c == to.c and SquareDistance(to, x, y)
    if sourceDistance and sourceDistance <= 20 ^ 2 and (not arrivalDistance or sourceDistance < arrivalDistance) then
        state.sawSource = true
    end
    if not arrivalDistance or arrivalDistance > 20 ^ 2 then return false end
    if sourceDistance and sourceDistance <= 20 ^ 2 and (not state.sawSource or arrivalDistance >= sourceDistance) then return false end
    return NS.AdvanceActiveRouteLeg(record, leg, record._routeAcceptedPlanGeneration, "questierouter_transport_arrival")
end

function backend.PollNavigationLeg(record, sampled, c, x, y, z, observedAt)
    local leg, state = record.currentLeg, progress[record]
    if not leg or not state or NS.Internal.RouteProgress.IsBlocked() then return false end
    local edge, walking = leg.questieRouterEdge, leg.walking
    if not edge and not walking then return false end
    if not sampled then c, x, y, z = backend.ReadNavigationProgress(record) end
    if not Finite(c) or not Finite(x) or not Finite(y) then return false end
    if state.leg ~= leg then
        Walking.CancelRecovery(state)
        CancelSearch(state)
        CancelRetry(state)
        state.leg, state.checkedRevision, state.failedAt, state.sawSource, state.nearBend = leg, nil, nil, nil, nil
    end
    state.sampleLeg, state.sampleZ = leg, z
    if z == nil and state.floorSource == "ambiguous" then
        state.sampleLow, state.sampleHigh = state.floorLow, state.floorHigh
    else
        state.sampleLow, state.sampleHigh = nil, nil
    end
    if walking then
        if Walking.Progress(state, record, c, x, y, z, observedAt) then return true end
        local reason = NeedsNewApproach(state, leg, c, x, y, z)
        if InCombatLockdown() then return false end
        if not reason then
            Walking.CancelRecovery(state)
            if state.job then
                CancelSearch(state)
                state.checkedRevision, state.terrain = nil, "fixed"
            end
            return false
        end
        edge = walking.group.terrainLeg.questieRouterEdge
        if not state.walking or state.job then return false end
        local ticket = Walking.BeginRecovery(state, record, c, x, y, z, WALK_RECOVERY, reason)
        if ticket then
            local q = Runtime()
            if q then
                RequestWalk(record, state, q, edge, c, x, y, z, ticket)
            else
                Walking.CompleteRecovery(state, ticket, false, "unavailable")
            end
        end
        return false
    end
    if transport[edge.kind] then return AdvanceTransport(record, state, leg, edge, c, x, y) end
    -- The native terrain worker sleeps in combat. Leave this leg eligible
    -- for the normal progress wakeup when the worker can search again.
    if InCombatLockdown() or not state.walking or c ~= edge.to.c or state.job or edge.kind == "border" then return false end
    local movedAfterFailure = state.failedAt and (x - state.failX) ^ 2 + (y - state.failY) ^ 2 >= RETRY_YARDS ^ 2
    local retry = movedAfterFailure and GetTime() - state.failedAt >= RETRY_SECONDS
    if movedAfterFailure and not retry and not state.retry then
        local generation = record._routeAcceptedPlanGeneration
        state.retry = C_Timer.NewTimer(math.max(0, state.failedAt + RETRY_SECONDS - GetTime()), function()
            state.retry = nil
            if progress[record] == state and record.currentLeg == leg and record._routeAcceptedPlanGeneration == generation then
                NS.RequestRouteNavigationProgress(record, "questierouter_retry")
            end
        end)
    end
    if state.checkedRevision ~= terrainRevision or retry then
        CancelRetry(state)
        local q = Runtime()
        if q then
            RequestWalk(record, state, q, edge, c, x, y, z)
            if state.terrain == "no_terrain" and not backend.WantsNavigationProgress(record) then WakeCarrier(record) end
        end
    end
    return false
end

-- ============================================================
-- Progress cleanup and backend registration
-- ============================================================

function backend.StopNavigationProgress(record, generation, reason)
    local state = progress[record]
    if not state then return end
    if state.job then
        CancelSearch(state); state.checkedRevision = nil
    end
    Walking.CancelRecovery(state)
    CancelRetry(state)
    state.floorC = nil
    if reason ~= "combat" then state.nearBend = nil end
    state.progressAt, state.catchUp, state.sampleLeg = nil, nil, nil
end

function backend.CanFlyWalkingSection(record, group)
    local endpoint = group.endpoint and group.endpoint.walking and group.endpoint.walking.to
    if not endpoint then return false end
    local c, x, y, z = backend.ReadNavigationProgress(record)
    return c == endpoint.c and HasClearApproach(rawget(_G, "QuestieRouter_NavEngine"), c, x, y, z, endpoint) == true
end

function backend.GetWalkingDebugLine(record)
    local state, leg = progress[record], record.currentLeg
    if not state or not leg then return end
    return string.format("questierouter leg=%d/%d target=%d@%.6f,%.6f terrain=%s advance=%s",
            record.currentLegIndex or 1, #record.legs, leg.mapID, leg.x, leg.y,
            tostring(state.terrain), tostring(record._coreLastAdvanceReason)) .. " rejected="
        .. tostring(Walking.ProgressReason(record, state)) .. " recovery="
        .. tostring(state.walkRecovery and state.walkRecovery.reason)
        .. " floor=" .. tostring(state.floorZ) .. "/" .. tostring(state.floorSource)
end

function backend.Clear(record)
    backend.ReleasePlan(record); NS.ClearAcceptedRoutePlan(record)
end

function backend.Initialize()
    if not NS.IsWoWForever() or backend.frame then return end
    NS.RegisterRouteBackendStateValidator(backend.id, Snapshot)
    local installed, ready
    local previousSettings = {}
    local routers = setmetatable({}, { __mode = "k" })
    local function UpdateReadiness()
        local current = backend.GetReadiness()
        local changed = ready ~= current
        ready = current
        if changed and NS.NotifyRouteBackendReadiness then NS.NotifyRouteBackendReadiness(backend.id, current) end
    end
    local function SettingsChanged()
        local cfg = installed and installed.db and installed.db.travel
        if not cfg then return false end
        local changed = false
        for _, key in ipairs(routeSettings) do
            if previousSettings[key] ~= cfg[key] then
                previousSettings[key], changed = cfg[key], true
            end
        end
        return changed
    end
    local function Validate(reason)
        NS.RequestRouteBackendStateValidation(backend.id, reason, "structural")
    end
    local function Subscribe()
        local q = rawget(_G, "QuestieRouter")
        if not q or type(q.On) ~= "function" then return end
        local router = q.Router
        if router and not routers[router] and type(router.Invalidate) == "function" then
            routers[router] = true
            hooksecurefunc(router, "Invalidate", function()
                graphRevision = graphRevision + 1
                Validate("questierouter_graph")
            end)
        end
        if installed == q then return end
        installed = q
        SettingsChanged()
        if q.Bridge and type(q.Bridge.FindMapLibs) == "function" then
            hooksecurefunc(q.Bridge, "FindMapLibs", UpdateReadiness)
        end
        q:On("SETTINGS_CHANGED", function()
            UpdateReadiness()
            if SettingsChanged() then Validate("questierouter_settings") end
        end)
        q:On("READY", function()
            Subscribe()
            UpdateReadiness()
            SettingsChanged()
        end)
        q:On("FLIGHT_CHANGED", function(inFlight) if not inFlight then Validate("questierouter_flight_landed") end end)
    end
    local f = CreateFrame("Frame"); backend.frame = f
    for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED",
        "TAXI_NODE_STATUS_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_LEVEL_UP" }) do f:RegisterEvent(event) end
    f:SetScript("OnEvent", function(_, event, addon)
        if event == "ADDON_LOADED" then
            if navigationPacks[addon] then
                terrainRevision = terrainRevision + 1
                local record = NS.GetActiveAuthorityRecord and NS.GetActiveAuthorityRecord()
                if record and progress[record] and NS.RequestRouteNavigationProgress then
                    NS.RequestRouteNavigationProgress(record, "questierouter_terrain_ready")
                end
                return
            end
            if addon ~= "QuestieRouter" and addon ~= "Questie" and addon ~= "QuestieDB" then return end
        end
        Subscribe()
        UpdateReadiness()
        if event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" then Validate(event) end
    end)
    Subscribe()
    ready = backend.GetReadiness()
end
