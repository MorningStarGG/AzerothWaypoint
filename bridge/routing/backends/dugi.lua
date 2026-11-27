-- ============================================================
-- Dugi routing backend
-- ============================================================
--
-- Runs Dugi's native planner in bounded coroutine slices and converts the
-- result to AWP travel legs. Each job owns its native pooled allocations
-- until completion or cancellation. A result must still belong to the
-- current route before it can publish any legs.

local NS = _G.AzerothWaypointNS
-- ============================================================
-- Backend registration and planner state
-- ============================================================

local backend = {
    id = "dugi",
    preserveItinerary = true,
    canFollowRouteInCombat = true,
    counters = { started = 0, completed = 0, cancelled = 0, failed = 0, timedOut = 0, cycles = 0, entries = 0 }
}
NS.RoutingBackend_Dugi = backend
local jobs = setmetatable({}, { __mode = "k" })
local hooks = {}
local running, active, index, dataEpoch = nil, nil, nil, 0
local frame = CreateFrame("Frame")
frame:Hide()
local initialized = false
local SLICE_MS, TIMEOUT, MAX_DEPTH, MAX_ENTRIES = 2, 3, 50, 20000
local settingsKeys = { "DGV_USETAXISYSTEM", "DGV_TAXISYSTEM_BOATS", "DGV_TAXISYSTEM_WHISTLE",
    "DGV_TAXISYSTEM_ZONE_PORTALS", "DGV_TAXISYSTEM_CLASS_PORTALS", "DGV_TAXISYSTEM_PLAYER_PORTALS",
    "DGV_TAXIFLIGHTMASTERS" }
local graphKeys = { "ZoneTransData", "InstancePortals", "StaticPortalData", "LocalPortalData", "BoatData",
    "UnboundTeleportData", "NonZeroOpenWorldFloors" }
-- ============================================================
-- Native runtime and job helpers
-- ============================================================

local function Combat() return InCombatLockdown() == true end
local function Number(v)
    return not (type(issecretvalue) == "function" and issecretvalue(v))
        and type(v) == "number" and v == v and math.abs(v) < math.huge
end
---@return any
local function Runtime()
    local r = rawget(_G, "DugisGuideViewer")
    return type(r) == "table" and r or nil
end
local function Call(owner, method, ...)
    local fn = owner and owner[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end
local function Owned()
    return running and coroutine.running() == running.thread and running or nil
end
local function Checkpoint(job)
    if job.cancelled then error("cancelled", 0) end
    if GetTime() - job.started > TIMEOUT then error("timeout", 0) end
    if debugprofilestop() - job.slice >= SLICE_MS then coroutine.yield() end
end
local function Wearable(id)
    local _, _, _, location = Call(C_Item, "GetItemInfoInstant", id)
    return type(location) == "string" and location ~= "" and location ~= "INVTYPE_NON_EQUIP"
end
local function CanUseItem(id)
    local _, _, _, location = Call(C_Item, "GetItemInfoInstant", id)
    if type(location) ~= "string" then return false end
    if not Wearable(id) then return true end
    return NS.CanExecuteRouteEquipmentItem and NS.CanExecuteRouteEquipmentItem(id) == true
end
local function Hook(owner, key, make)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then return end
    local methods = hooks[key]
    if not methods then
        methods = setmetatable({}, { __mode = "kv" }); hooks[key] = methods
    end
    if methods[owner] == owner[key] then return end
    local wrapped = make(owner[key])
    methods[owner], owner[key] = wrapped, wrapped
end

-- ============================================================
-- Native hooks and planner readiness
-- ============================================================

-- The native allocator and Character geometry publisher are scoped by the
-- currently running worker, never by a flag left enabled across a yield.
local function Install(r, taxi)
    Hook(r, "GetCreateTable", function(original)
        local release = r.tPool
        return function(...)
            local job = Owned()
            if job then Checkpoint(job) end
            local value = original(...)
            if job then value:BindToAutoroutineLifetime(release) end
            return value
        end
    end)
    Hook(r, "AddRouteWaypoint", function(original)
        return function(self, map, floor, x, y, title, cue)
            local job = Owned()
            if not job then return original(self, map, floor, x, y, title, cue) end
            if job.phase ~= "walking" then error("unexpected_native_publication", 0) end
            Checkpoint(job)
            if not Number(map) or map <= 0 or not Number(x) or not Number(y) or x < 0 or x > 1 or y < 0 or y > 1 then
                error("invalid_walking_point", 0)
            end
            local point = {
                mapID = map,
                floor = floor,
                x = x,
                y = y,
                cue = type(cue) == "string" and cue ~= "" and cue or
                    nil
            }
            job.points[#job.points + 1] = point
            return point
        end
    end)
    Hook(r, "GetCurrentMapID", function(original)
        return function(...)
            local job = Owned()
            if job then return job.playerMap end
            return original(...)
        end
    end)
    Hook(taxi.RouteBuilders.UnboundTeleport, "Build", function(original)
        return function(self, ...)
            local job = Owned()
            local id, data = select(11, ...), select(12, ...)
            if job and Number(id) and type(data) == "string" and id ~= tonumber(data:match("^(%d+):"))
                and not CanUseItem(id) then
                return nil
            end
            return original(self, ...)
        end
    end)
end

local function HasPlanner(r)
    local taxi = r and r.Modules and r.Modules.Taxi
    return type(r) == "table" and type(taxi) == "table" and type(taxi.GetBestRoute) == "function" and
        type(taxi.RouteBuilders) == "table"
        and type(r.SetSmartWaypoint) == "function" and type(r.GetCreateTable) == "function"
        and type(r.tPool) == "function" and type(r.AddRouteWaypoint) == "function"
        and type(r.UserSetting) == "function" and type(r.UiMapId2Floor) == "function"
        and type(r.GetPlayerMapPositionDisruptive) == "function" and type(r.UnpackXY) == "function"
        and type(r.Modules.TaxiData) == "table" and type(r.Modules.TaxiData.GetFullData) == "function"
        and type(taxi.RouteBuilders.Character) == "table" and
        type(taxi.RouteBuilders.Character.AddWaypoint) == "function"
end

function backend.GetReadiness()
    local r = Runtime()
    if not NS.IsAddonLoaded("DugisGuideViewerZ") or not r then return "unavailable", "dugi_not_loaded" end
    local provider = NS.Internal.DugiProvider
    if provider and provider.IsInitializing(r) then return "waiting", "dugi_taxi_initializing" end
    if HasPlanner(r) then return "ready" end
    return "unavailable", "dugi_missing_taxi_planner"
end

function backend.IsAvailable()
    return backend.GetReadiness() == "ready"
end

function backend.InstallReadinessHooks(notify)
    local provider = NS.Internal and NS.Internal.DugiProvider
    if provider then provider.ObserveAvailability(Runtime(), notify) end
end

-- ============================================================
-- Travel dependencies and validation snapshots
-- ============================================================

local function Stable(value, parts, seen, job)
    if type(issecretvalue) == "function" and issecretvalue(value) then error("inaccessible_state", 0) end
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        parts[#parts + 1] = tostring(value); return
    end
    if kind ~= "table" or seen[value] then return end
    seen[value] = true
    local keys = {}
    for key, v in pairs(value) do
        if (type(key) == "string" or type(key) == "number") and type(v) ~= "function" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        if job then Checkpoint(job) end
        parts[#parts + 1] = tostring(key); Stable(value[key], parts, seen, job)
    end
end
local function Hash(parts, job)
    local hash = 5381
    for _, part in ipairs(parts) do
        for i = 1, #part do
            if job and i % 256 == 0 then Checkpoint(job) end
            hash = (hash * 33 + part:byte(i)) % 2147483647
        end
        hash = (hash * 33 + 31) % 2147483647
    end
    return tostring(hash)
end
-- Compile immutable data dependencies once per native data initialization.
-- Cooldown validation reads this index, not the complete route graph.
local function BuildIndex(job)
    local r = job.runtime
    local data = r.Modules.TaxiData
    local result = { epoch = dataEpoch, data = data, spells = {}, items = {}, quests = {} }
    for _, id in ipairs({ 556, 126895, 50977, 193753 }) do result.spells[id] = true end
    for _, id in ipairs({ 6948, 172179, 64488, 142542, 54452, 37118, 44314, 44315, 141605 }) do result.items[id] = true end
    local parts, seen = {}, {}
    local function dependencies(value)
        Checkpoint(job)
        if type(value) == "string" then
            for list in value:gmatch("n?qid:([%d,]+)") do for id in list:gmatch("%d+") do result.quests[tonumber(id)] = true end end
            for id in value:gmatch("spell:(%d+)") do result.spells[tonumber(id)] = true end
        elseif type(value) == "table" and not seen[value] then
            seen[value] = true
            for _, v in pairs(value) do dependencies(v) end
        end
    end
    for _, key in ipairs(graphKeys) do
        parts[#parts + 1] = key
        local collection = rawget(_G, "TaxiDataCollection")
        local value = key == "ZoneTransData" and collection and collection.ZoneTransData or data and data[key]
        Stable(value, parts, {}, job)
        dependencies(value)
    end
    for _, entries in pairs(data and data.UnboundTeleportData or {}) do
        for key, value in pairs(entries) do
            local id = tonumber(tostring(key):match("^%d+"))
            local spell = type(value) == "string" and tonumber(value:match("^(%d+):"))
            if id then (id == spell and result.spells or result.items)[id] = true end
        end
    end
    result.graph = Hash(parts, job)
    index = result
end
local flightDirty, flightFingerprint, reputationDirty, reputationFingerprint = true, "", true, ""
local movementDirty = false
local function Snapshot()
    if Combat() or not backend.IsAvailable() or not index then return false end
    -- Native reinitialization is itself a known semantic change. Rebuild the
    -- dependency index in the next owned planning job, not in this validator.
    if index.epoch ~= dataEpoch then return true, "dugi_data_epoch:" .. dataEpoch end
    local r = Runtime()
    if movementDirty then
        local taxi = r.Modules.Taxi
        if type(taxi.ResetMovementCache) == "function" then taxi:ResetMovementCache() end
        movementDirty = false
    end
    local parts = { index.graph, tostring(dataEpoch) }
    for _, key in ipairs(settingsKeys) do
        local id = rawget(_G, key)
        if id then parts[#parts + 1] = tostring(r:UserSetting(id)) end
    end
    for id in pairs(index.spells) do
        local known = C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell and C_SpellBook.FindSpellBookSlotForSpell(id)
        local cd = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
        if cd and (not Number(cd.startTime) or not Number(cd.duration)) then return false end
        parts[#parts + 1] = "s" ..
            id ..
            ":" ..
            tostring(known ~= nil) ..
            ":" .. tostring(not cd or cd.startTime == 0 or cd.duration <= 1.5 or cd.startTime + cd.duration <= GetTime())
    end
    for id in pairs(index.items) do
        local count = C_Item.GetItemCount(id)
        local start, duration = C_Item.GetItemCooldown(id)
        if not Number(count) or not Number(start) or not Number(duration) then return false end
        parts[#parts + 1] = "i" ..
            id .. ":" .. count .. ":" .. tostring(start == 0 or duration <= 1.5 or start + duration <= GetTime())
            ..
            ":" ..
            tostring(PlayerHasToy and PlayerHasToy(id)) ..
            ":" .. tostring(C_Item.IsEquippedItem and C_Item.IsEquippedItem(id))
    end
    for id in pairs(index.quests) do
        parts[#parts + 1] = "q" ..
            id .. ":" .. tostring(C_QuestLog.IsQuestFlaggedCompleted(id))
    end
    local user = rawget(_G, "DugisGuideUser") or {}
    for _, key in ipairs({ "ZenPilgrimageReturnPoint", "LFGWorldLocation", "covenantFeatures" }) do
        Stable(user[key],
            parts, {})
    end
    parts[#parts + 1] = "beacon:" .. tostring(r.Modules.TaxiData.currentBeaconMode)
    parts[#parts + 1] = "mounted:" .. tostring(IsMounted and IsMounted())
    parts[#parts + 1] = "form:" .. tostring(GetShapeshiftFormID and GetShapeshiftFormID())
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    parts[#parts + 1] = table.concat(
        { tostring(NS.GetPlayerMapID()), tostring(UnitLevel("player")), tostring(class), tostring(race),
            tostring(UnitFactionGroup("player")), tostring(GetBindLocation()) }, ":")
    if flightDirty then
        local values = {}; Stable(rawget(_G, "DugisFlightmasterDataTable"), values, {})
        Stable((rawget(_G, "TaxiDataCollection") or {}).BindLocations, values, {})
        flightFingerprint, flightDirty = Hash(values), false
    end
    if reputationDirty then
        local values = {}
        if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
            for i = 1, C_Reputation.GetNumFactions() do
                local f = C_Reputation.GetFactionDataByIndex(i)
                if f then values[#values + 1] = tostring(f.factionID) .. ":" .. tostring(f.currentStanding) end
            end
        end
        reputationFingerprint, reputationDirty = Hash(values), false
    end
    parts[#parts + 1], parts[#parts + 2] = flightFingerprint, reputationFingerprint
    table.sort(parts)
    return true, Hash(parts)
end

-- ============================================================
-- Converting native routes
-- ============================================================

local function AddLeg(job, point, title, kind, travel, arrival)
    if not point or not Number(point.mapID) or point.mapID <= 0 or not Number(point.x) or not Number(point.y)
        or point.x < 0 or point.x > 1 or point.y < 0 or point.y > 1 then
        error("invalid_leg", 0)
    end
    local leg = {
        mapID = point.mapID,
        x = point.x,
        y = point.y,
        title = title,
        kind = kind or "movement",
        routeLegKind = "carrier",
        routeTravelType = travel or "travel",
        source = "dugi",
        arrivalRadius = 10,
        preservePlanOnArrival = true,
        dugiFloor = point.floor
    }
    if arrival then
        leg.dugiArrival = arrival; leg.activationCoords = { mapID = point.mapID, x = point.x, y = point.y }
    end
    job.legs[#job.legs + 1] = leg
    return leg
end
local function Point(route, source)
    if source then return { mapID = route.mSource, floor = route.fSource, x = route.xSouce, y = route.ySource } end
    return {
        mapID = route.mPort or route.m,
        floor = route.fPort or route.f,
        x = route.xPort or route.x,
        y = route.yPort or
            route.y
    }
end
local function MapName(r, map) return Call(r, "GetMapNameFromID", r, map) or "destination" end

-- Character routes can mix ordinary map breadcrumbs with authored stair and
-- zone transitions. Only bind a continuous run on a verified map floor.
local function WalkingPoint(r, map, floor, x, y)
    if not Number(map) or not Number(floor) or not Number(x) or not Number(y)
        or Call(r, "UiMapId2Floor", map) ~= floor then
        return
    end
    local c, wx, wy = Call(NS, "GetWorldPositionFromMapCoords", map, x, y)
    if Number(c) and Number(wx) and Number(wy) then
        return { mapID = map, floor = floor, c = c, wx = wx, wy = wy }
    end
end

local function BindCharacterWalk(job, route, first)
    if #job.legs <= first then return end
    local previous = WalkingPoint(job.runtime, route[2], route[3], route[4], route[5])
    local group
    for i = first, #job.legs do
        Checkpoint(job)
        local leg = job.legs[i]
        local point = WalkingPoint(job.runtime, leg.mapID, leg.dugiFloor, leg.x, leg.y)
        if point and previous and not leg.dugiCue and previous.mapID == point.mapID
            and previous.floor == point.floor and previous.c == point.c
            and (previous.wx ~= point.wx or previous.wy ~= point.wy) then
            if group then
                job.legs[i - 1].walking.required = false
            else
                -- A Character stretch can start after a transport. Its saved
                -- origin is not a player observation for initial catch-up.
                group = { joined = true }
            end
            NS.Internal.RouteWalking.Bind(leg, group, previous, point, true)
            leg.routeGeometryKey = table.concat({ "dugi", point.mapID, point.floor, previous.wx, previous.wy,
                point.wx, point.wy }, ":")
        else
            group = nil
        end
        previous = point
    end
end
local function ActionLeg(job, route, kind)
    local r = job.runtime
    local id, ty = route.spell or route.item, route.spell and "spell" or "item"
    if not Number(id) or id <= 0 then error("invalid_action", 0) end
    if ty == "item" and PlayerHasToy and PlayerHasToy(id) then ty = "toy" end
    local name = ty == "spell" and Call(C_Spell, "GetSpellName", id) or Call(C_Item, "GetItemNameByID", id)
    local title = (kind == "BoundTeleport" and "Hearth to " .. MapName(r, route.m) or "Use " .. (name or tostring(id)))
    local arrival = Point(route)
    local portable = { mapID = job.playerMap, x = job.playerX, y = job.playerY }
    local action = {
        title = title,
        secureType = ty,
        securePayload = id,
        spellID = route.spell,
        itemID = route.item,
        semanticKind = kind == "BoundTeleport" and "hearthstone" or "spell",
        activationMode = "portable",
        arrivalCoords = arrival,
        routeDependency = { kind = ty, id = id }
    }
    if route.item and Wearable(id) and not (C_Item.IsEquippedItem and C_Item.IsEquippedItem(id)) then
        if not CanUseItem(id) then error("unusable_equipment", 0) end
        local equip = AddLeg(job, portable, "Equip " .. (name or tostring(id)), "movement", "travel")
        equip.specialAction = {
            executionType = "equip",
            itemID = id,
            title = equip.title,
            routeDependency = { kind = "item", id = id }
        }
    end
    local leg = AddLeg(job, portable, title, kind == "BoundTeleport" and "hearthstone" or "spell", "travel", arrival)
    leg.specialAction = action
end
local function Translate(job, route, seen)
    Checkpoint(job)
    if not route or seen[route] then error("invalid_route_tree", 0) end
    seen[route] = true
    local kind = job.builderNames[route.builder]
    if kind == "Character" then
        job.points, job.phase = {}, "walking"
        route.builder:AddWaypoint(route, "Follow the path")
        job.phase = "query"
        local endpoint = Point(route)
        local first = #job.legs + 1
        if NS.RouteSpecials.SameWalkingEndpoint(endpoint, job.destination) then endpoint.routeLegKind = "destination" end
        for _, p in ipairs(job.points) do
            local leg = AddLeg(job, p,
                p.cue == "upstairs" and "Go upstairs" or p.cue == "downstairs" and "Go downstairs" or "Follow the path")
            leg.dugiCue = p.cue
            NS.Internal.RouteWalkingPresentation.Describe(leg, "path", endpoint, nil,
                (p.cue == "upstairs" or p.cue == "downstairs") and leg.title)
        end
        BindCharacterWalk(job, route, first)
        job.points = nil
    elseif kind == "FlightMaster" then
        Translate(job, route[1], seen)
        local data = job.runtime.Modules.TaxiData:GetFullData()
        local target = data[route.c] and data[route.c][route.tailId]
        if not target then error("missing_flight_destination", 0) end
        local x, y = job.runtime:UnpackXY(target.coord)
        local known = rawget(_G, "DugisFlightmasterDataTable")
        known = known and known[route.c] and known[route.c][route.tailId]
        local name = known and type(known.name) == "string" and known.name or MapName(job.runtime, target.m)
        local head = data[route.c] and data[route.c][route.headId]
        local travel = head and (head.isBeacon or head.isPhase or head.isGateway or head.isSpaceship) and "portal"
            or head and head.isBoat and "ship" or "taxi"
        local point = job.legs[#job.legs]
        if not point then error("missing_flight_origin", 0) end
        if point.walkingDescription then
            local departure = known and known[route.c] and known[route.c][route.headId]
            point.walkingDescription.endpoint.destinationName = departure and departure.name or "the flight master"
        end
        local leg = AddLeg(job, point, (travel == "taxi" and "Fly to " or "Travel to ") .. name, travel, travel,
            { mapID = target.m, x = x, y = y, floor = target.f })
        leg.dugiDestinationNPC = route.tailId
        if travel == "taxi" then leg.taxi = { name = name, destination = { mapID = target.m, x = x, y = y } } end
        Translate(job, route[#route], seen)
    elseif kind == "FlightHop" then
        AddLeg(job, { mapID = route.m2, x = route.x2, y = route.y2, floor = route.f2 }, "Continue the flight", "taxi",
            "taxi")
    elseif kind == "BoundTeleport" or kind == "UnboundTeleport" or kind == "ZenPilgrimageReturn" or kind == "FlightMasterWhistle" then
        ActionLeg(job, route, kind); Translate(job, route.tail, seen)
    elseif kind == "InstanceExit" and not route.head then
        local leg = AddLeg(job, { mapID = job.playerMap, x = job.playerX, y = job.playerY },
            "Use the LFG teleport to leave the instance", "portal", "portal", Point(route))
        leg.specialAction = {
            title = leg.title,
            secureType = "macro",
            securePayload = "/run LFGTeleport(1)",
            semanticKind =
            "portal",
            activationMode = "portable",
            arrivalCoords = Point(route)
        }
        Translate(job, route.tail, seen)
    elseif kind == "StaticPortals" or kind == "LocalPortals" or kind == "InstancePortals" or kind == "InstanceExit" or kind == "Boats" then
        Translate(job, route.head, seen)
        local travel = kind == "Boats" and
            (tostring(route.engVehicle):lower():find("zeppelin", 1, true) and "zeppelin" or "ship") or "portal"
        local departure, arrival = Point(route, true), Point(route)
        local leg = AddLeg(job, departure,
            (travel == "portal" and "Take the portal to " or "Take the " .. travel .. " to ") ..
            MapName(job.runtime, route.mPort), travel, travel, arrival)
        if leg and travel == "portal" and departure.mapID == 84 and arrival.mapID == 2339
            and NS.RouteSpecials.CoordsMatch(departure.mapID, departure.x, departure.y, 84, .4808, .9196, .0005) then
            leg.sanctumDeparture = "inside"
        elseif leg and travel == "portal" and departure.mapID == 1416 and arrival.mapID == 1453
            and NS.RouteSpecials.CoordsMatch(arrival.mapID, arrival.x, arrival.y, 1453, .499, .867, .0005) then
            local sanctum = NS.RouteSpecials.Sanctum
            if sanctum then sanctum.SetCrossing(leg, sanctum.ForeverPortalArrival()) end
        end
        Translate(job, route.tail, seen)
    else
        error("unsupported_builder:" .. tostring(kind), 0)
    end
    seen[route] = nil
end

-- ============================================================
-- Native planning and recursion limits
-- ============================================================

local combatActions = { "BoundTeleport", "UnboundTeleport", "ZenPilgrimageReturn", "FlightMasterWhistle" }

-- The Dugi integration intercepts the native planner for this job. Recursion
-- stays in Lua, so native yields never cross pcall/hooksecurefunc boundaries.
function backend.RunNativePlanner(original, taxi, parent,
                                  sourceMapID, sourceFloor, sourceX, sourceY, targetMapID, targetFloor, targetX, targetY, ...)
    local job = Owned()
    if not job or taxi ~= job.taxi then
        return nil
    end
    Checkpoint(job)
    job.entries = job.entries + 1
    backend.counters.entries = backend.counters.entries + 1
    if job.entries > MAX_ENTRIES then
        error("entry_limit", 0)
    end
    if job.depth >= MAX_DEPTH then
        error("depth_limit", 0)
    end
    local mask, excluded = 0, {}
    for i = 1, select("#", ...) do
        local builder = select(i, ...)
        if not excluded[builder] then
            mask = mask + (job.builderBits[builder] or 0)
            excluded[builder] = true
        end
    end
    local skip
    if job.combat then
        -- Native recursive calls each supply their own exclusions.
        skip = { ... }
        for _, name in ipairs(combatActions) do
            local builder = job.builders[name]
            if builder and not excluded[builder] then
                skip[#skip + 1] = builder
                mask = mask + job.builderBits[builder]
            end
        end
    end
    local key = table.concat({
        tostring(sourceMapID), tostring(sourceFloor), string.format("%.17g", sourceX), string.format("%.17g", sourceY),
        tostring(targetMapID), tostring(targetFloor), string.format("%.17g", targetX), string.format("%.17g", targetY),
        mask,
    }, ":")
    if job.ancestors[key] then
        backend.counters.cycles = backend.counters.cycles + 1
        return nil
    end
    job.ancestors[key], job.depth = true, job.depth + 1
    local result
    if skip then
        result = original(taxi, parent, sourceMapID, sourceFloor, sourceX, sourceY,
            targetMapID, targetFloor, targetX, targetY, unpack(skip))
    else
        result = original(taxi, parent, sourceMapID, sourceFloor, sourceX, sourceY,
            targetMapID, targetFloor, targetX, targetY, ...)
    end
    job.ancestors[key], job.depth = nil, job.depth - 1
    if parent then
        return result
    end
    if result then
        Translate(job, result, {})
        job.found = true
    end
    return nil -- SetSmartWaypoint must not publish a native trip.
end

-- ============================================================
-- Job ownership, completion and cancellation
-- ============================================================

local function DestinationCurrent(job)
    local target, destination = job.record.target or job.record, job.destination
    return not target.mapID
        or target.mapID == destination.mapID and target.x == destination.x and target.y == destination.y
end
local function HasAuthority(job)
    return NS.IsActiveRouteRecord(job.record, true)
end
local function IsCurrentJob(job)
    return DestinationCurrent(job) and job.record._corePlanning == true and not job.cancelled
        and jobs[job.record] == job and job.record.backend == "dugi"
        and job.record._dugiSerial == job.serial and NS.IsRoutingEnabled() and HasAuthority(job)
        and Runtime() == job.runtime and job.runtime.Modules.Taxi == job.taxi
        and job.taxi.GetBestRoute == job.planner and job.taxi.RouteBuilders == job.builders
        and job.runtime.SetSmartWaypoint == job.smart and job.runtime.GetCreateTable == job.allocate
        and job.runtime.tPool == job.pool
end

-- Native pooled route and temporary tables belong to the suspended job. Use
-- its lifetime helpers so completion, cancellation and stale results all
-- return those objects to Dugi without touching another caller's pool.
local function Release(job)
    if not job.boundObjects then
        return
    end
    local previous = job.runtime.currentAutoroutine
    job.runtime.currentAutoroutine = job
    for object, dispose in pairs(job.boundObjects) do dispose(object) end
    job.runtime.currentAutoroutine = previous
    job.boundObjects, job.thread, job.ancestors, job.points, job.builderNames, job.builderBits =
        nil, nil, nil, nil, nil, nil
end

local function Cancel(job)
    if not job or job.cancelled or not job.thread then
        return
    end
    job.record._corePlanning, job.record._coreRoutePending = nil, nil
    job.cancelled = true
    backend.counters.cancelled = backend.counters.cancelled + 1
    Release(job)
end

local function Fallback(record, destination, reason, mode)
    local legs = mode == "intentional_direct" and {
            NS.RouteSpecials.MakeDestinationLeg("dugi", destination.mapID, destination.x, destination.y,
                destination.title) } or
        nil
    return NS.RouteSpecials.CompletePlan(record, "dugi", legs and "success" or "failed", legs, reason, nil, mode)
end
-- A superseded job still has to return its pooled objects. Only the job
-- that passes the current-route and native-runtime checks can complete a plan.
local function Finish(job, ok, reason)
    local current = IsCurrentJob(job)
    if current then
        local record = job.record
        record._corePlanning, record._coreRoutePending = nil, nil
        if ok and job.found then
            local destination, legs = job.destination, job.legs
            if job.intent and job.intent.entrance then
                local entrance = job.intent.entrance
                AddLeg(job, entrance, "Enter " .. (job.intent.instanceName or "the instance"),
                    "entrance", job.intent.travelType)
            end
            local last = legs[#legs]
            local endpoint = NS.RouteSpecials.MakeDestinationLeg("dugi",
                destination.mapID, destination.x, destination.y, destination.title)
            endpoint.kind, endpoint.arrivalRadius = "walk", 10
            if last and last.kind == "movement" and not last.dugiArrival and not last.specialAction and not last.dugiCue
                and NS.RouteSpecials.SameWalkingEndpoint(last, destination) then
                table.remove(legs)
                endpoint.walking, endpoint.routeGeometryKey = last.walking, last.routeGeometryKey
            end
            legs[#legs + 1] = endpoint
            if job.combat then
                record._routeBackendStateFingerprint = NS.RouteSpecials.COMBAT_TRAVEL_STATE
            else
                local valid, success, fingerprint = pcall(Snapshot)
                if valid and success then
                    record._routeBackendStateFingerprint = fingerprint
                end
            end
            NS.RouteSpecials.CompletePlan(record, "dugi", "success", legs, "dugi_plan", job.serial)
            backend.counters.completed = backend.counters.completed + 1
        elseif ok and job.combat then
            NS.RouteSpecials.CompletePlan(record, "dugi", "deferred", nil, "combat")
        else
            backend.counters.failed = backend.counters.failed + 1
            if reason == "timeout" then
                backend.counters.timedOut = backend.counters.timedOut + 1
            end
            Fallback(record, job.destination, "dugi_" .. tostring(reason or "no_path"))
        end
    end
    Release(job)
    if jobs[job.record] == job then jobs[job.record] = nil end
    if active == job then
        active = nil
        frame:Hide()
    end
    if current then NS.RecomputeCarrier() end
end
-- ============================================================
-- Starting a planning attempt
-- ============================================================

local serial = 0
local function PlanRoute(record, mapID, x, y, title)
    if not record or not Number(mapID) or mapID <= 0 or not Number(x) or not Number(y)
        or x < 0 or x > 1 or y < 0 or y > 1 then
        return
    end
    local priorJob = jobs[record]
    -- Reuse the running search when only the destination label changes.
    if priorJob and priorJob.thread and not priorJob.cancelled
        and priorJob.destination.mapID == mapID and priorJob.destination.x == x and priorJob.destination.y == y
    then
        priorJob.destination.title = title
        return
    end
    if active then
        Cancel(active)
        jobs[active.record] = nil; active = nil
    end
    Cancel(priorJob)
    serial = serial + 1
    local destination = { mapID = mapID, x = x, y = y, title = title }
    record.backend, record._dugiSerial = "dugi", serial
    local job = {
        record = record,
        destination = destination,
        serial = serial,
        combat = Combat(),
        runtime = Runtime(),
        boundObjects = {},
        entries = 0,
        depth = 0,
        ancestors = {},
        legs = {}
    }
    jobs[record] = job
    if not backend.IsAvailable() then
        jobs[record] = nil
        Fallback(record, destination, "dugi_unavailable_fallback")
        return
    end
    local runtime = job.runtime
    if type(runtime) ~= "table" then
        return
    end
    if not runtime:UserSetting(rawget(_G, "DGV_USETAXISYSTEM")) then
        jobs[record] = nil
        Fallback(record, destination, "dugi_planning_disabled", "intentional_direct")
        return
    end
    job.taxi = runtime.Modules.Taxi
    job.planner, job.builders = job.taxi.GetBestRoute, job.taxi.RouteBuilders
    Install(runtime, job.taxi)
    job.smart, job.allocate, job.pool = runtime.SetSmartWaypoint, runtime.GetCreateTable, runtime.tPool
    job.playerMap, job.playerX, job.playerY = NS.GetPlayerMapPosition()
    if not Number(job.playerMap) or not Number(job.playerX) or not Number(job.playerY) then
        jobs[record] = nil
        Fallback(record, destination, "dugi_missing_start_fallback")
        return
    end
    job.intent = NS.ResolveInstanceRouteIntent and NS.ResolveInstanceRouteIntent(mapID, x, y, title)
    local target = job.intent and job.intent.entrance or destination
    job.builderNames, job.builderBits = {}, {}
    local names = {}
    for name in pairs(job.taxi.RouteBuilders) do
        names[#names + 1] = name
    end
    table.sort(names)
    for i, name in ipairs(names) do
        job.builderNames[job.taxi.RouteBuilders[name]], job.builderBits[job.taxi.RouteBuilders[name]] =
            name, 2 ^ (i - 1)
    end
    job.started, job.phase = GetTime(), "query"
    job.thread = coroutine.create(function()
        if not index or index.epoch ~= dataEpoch or index.data ~= runtime.Modules.TaxiData then BuildIndex(job) end
        job.smart(runtime, target.mapID, runtime.UiMapId2Floor(target.mapID), target.x * 100, target.y * 100, title,
            job.playerMap, runtime.UiMapId2Floor(job.playerMap), job.playerX * 100, job.playerY * 100, true, nil, true)
    end)
    record._corePlanning, record._coreRoutePending = true, true
    active = job
    frame:Show()
    backend.counters.started = backend.counters.started + 1
end

function backend.BeginPlan(attempt)
    PlanRoute(attempt.record, attempt.mapID, attempt.x, attempt.y, attempt.title)
    local job = jobs[attempt.record]
    if job and job.thread and not job.cancelled then
        return "pending"
    end
end

function backend.CancelPlan(attempt)
    local record = attempt.record
    Cancel(jobs[record])
    jobs[record] = nil
    if active and active.record == record then
        active = nil
        frame:Hide()
    end
    record._dugiSerial = nil
end

function backend.AdoptPlan(attempt, owner)
    owner._routeBackendStateFingerprint = attempt.record._routeBackendStateFingerprint
    owner._dugiWalkProgress = nil
end

-- ============================================================
-- Walking progress and required arrivals
-- ============================================================

-- Shared walking progression can skip ordinary breadcrumbs. Authored
-- floor changes and arrival cues need their own checks before advancing.
function backend.WantsNavigationProgress(record)
    local w = record.currentLeg and record.currentLeg.walking
    return w and not w.required
end

function backend.ReadNavigationProgress()
    return Call(NS, "GetPlayerMapPosition")
end

function backend.StopNavigationProgress(record)
    record._dugiWalkProgress = nil
end

function backend.PollNavigationLeg(record, sampled, map, x, y, _, observedAt)
    local leg = record.currentLeg
    local w = leg and leg.walking
    if w and not w.required then
        if not sampled then map, x, y = backend.ReadNavigationProgress() end
        if Number(map) and map == w.to.mapID and Number(x) and Number(y) then
            local c, wx, wy = Call(NS, "GetWorldPositionFromMapCoords", map, x, y)
            if Number(c) and c == w.to.c and Number(wx) and Number(wy) then
                local state = record._dugiWalkProgress or {}
                record._dugiWalkProgress = state
                return NS.Internal.RouteWalking.Progress(state, record, c, wx, wy, nil, observedAt)
            end
        end
        record._dugiWalkProgress = nil
        return false
    end
    local arrival = leg and leg.dugiArrival
    if not arrival then return false end
    local distance = NS.GetPlayerWaypointDistance(arrival.mapID, arrival.x, arrival.y)
    if Number(distance) and distance <= 20 then
        return NS.AdvanceActiveRouteLeg(record, leg, record._routeAcceptedPlanGeneration, "dugi_transition_arrival")
    end
    return false
end

function backend.CanAdvanceLeg(record, leg)
    if leg.dugiArrival then return false end
    local r = Runtime()
    if leg.dugiCue and leg.dugiFloor and r and r.UiMapId2Floor(NS.GetPlayerMapID()) ~= leg.dugiFloor then return false end
end

-- ============================================================
-- Clearing a route
-- ============================================================

function backend.Clear(record)
    if type(record) ~= "table" then return end
    Cancel(jobs[record]); jobs[record] = nil
    if active and active.record == record then
        active = nil; frame:Hide()
    end
    record._dugiSerial, record._dugiWalkProgress = nil, nil
    NS.ClearAcceptedRoutePlan(record)
end

-- ============================================================
-- Invalidation and diagnostics
-- ============================================================

function backend.OnPlanInvalidated(reason)
    return NS.RequestRouteBackendStateValidation("dugi", reason,
        (reason == "SPELL_UPDATE_COOLDOWN" or reason == "BAG_UPDATE_COOLDOWN") and "cooldown" or "structural")
end

function backend.NativePlannerChanged()
    dataEpoch = dataEpoch + 1
    flightDirty = true
    local record = NS.GetActiveAuthorityRecord and NS.GetActiveAuthorityRecord()
    if record and record.backend ~= "dugi" and NS.GetSelectedBackendID() == "dugi" then
        NS.SignalPreferredRouteRecovery("dugi", "DugiPlannerInitialized")
    else
        backend.OnPlanInvalidated("DugiPlannerInitialized")
    end
end

function backend.GetDebugLine(record)
    local line = "Dugi planner: " .. (active and ("pending entries=" .. active.entries) or "idle")
    local leg = record and record.currentLeg
    if leg and leg.walking then
        local state = record._dugiWalkProgress
        line = line .. " advance=" .. tostring(record._coreLastAdvanceReason)
            .. " walking=" .. tostring(NS.Internal.RouteWalking.ProgressReason(record, state))
    end
    return line
end

function backend.Initialize()
    if initialized then return end
    initialized = true
    NS.RegisterRouteBackendStateValidator("dugi", Snapshot, NS.ProbeRouteTravelDependency)
    frame:SetScript("OnUpdate", function()
        local job = active
        if not job then
            frame:Hide(); return
        end
        if not IsCurrentJob(job) then
            job.record._routePlanAttempt:Complete({ status = "failed", reason = "stale_planner" })
            Cancel(job); jobs[job.record] = nil; active = nil; frame:Hide(); return
        end
        if Combat() ~= job.combat then
            -- A suspended search owns its eligibility and pooled candidates.
            -- Restart before resuming with different travel methods available.
            Cancel(job)
            local d = job.destination
            PlanRoute(job.record, d.mapID, d.x, d.y, d.title)
            return
        end
        if NS.State.routing.specialActionCasting == true
            or NS.IsRouteEquipmentTransactionActive and NS.IsRouteEquipmentTransactionActive() then
            job.pausedAt = job.pausedAt or GetTime()
            return
        end
        if job.pausedAt then
            job.started = job.started + GetTime() - job.pausedAt; job.pausedAt = nil
        end
        if GetTime() - job.started > TIMEOUT then
            Finish(job, false, "timeout"); return
        end
        if job.runtime.currentAutoroutine then return end
        local previous = job.runtime.currentAutoroutine
        job.runtime.currentAutoroutine, running, job.slice = job, job, debugprofilestop()
        local ok, reason = coroutine.resume(job.thread)
        running, job.runtime.currentAutoroutine = nil, previous
        if not ok or coroutine.status(job.thread) == "dead" then Finish(job, ok, reason) end
    end)
    for _, event in ipairs({ "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "TOYS_UPDATED",
        "HEARTHSTONE_BOUND", "CONFIRM_BINDER", "TAXIMAP_OPENED", "TAXI_NODE_STATUS_CHANGED", "NEW_TAXI_PATH", "PLAYER_CONTROL_GAINED",
        "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_MOUNT_DISPLAY_CHANGED", "QUEST_LOG_UPDATE", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
        "PLAYER_LOGOUT", "ADDON_LOADED" }) do pcall(frame.RegisterEvent, frame, event) end
    frame:SetScript("OnEvent", function(_, event, name)
        if event == "PLAYER_LOGOUT" then
            if active then
                local job = active
                Cancel(job); jobs[job.record] = nil; active = nil
            end
            frame:Hide(); return
        end
        if event == "ADDON_LOADED" then
            if name ~= "DugisGuideViewerZ" then return end
            dataEpoch = dataEpoch + 1
        end
        if event == "UPDATE_FACTION" then reputationDirty = true end
        if event == "TAXIMAP_OPENED" or event == "NEW_TAXI_PATH" or event == "TAXI_NODE_STATUS_CHANGED"
            or event == "HEARTHSTONE_BOUND" or event == "CONFIRM_BINDER" or event == "PLAYER_ENTERING_WORLD" then
            flightDirty = true
        end
        if event == "SPELLS_CHANGED" or event == "PLAYER_CONTROL_GAINED"
            or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
            movementDirty = true
        end
        backend.OnPlanInvalidated(event)
    end)
end
