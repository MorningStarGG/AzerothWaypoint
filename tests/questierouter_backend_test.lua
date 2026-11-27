local NativePath = dofile("tests/native_path.lua")
local MakeFixture = assert(loadfile("tests/route_planning_fixture.lua"))()

local function Setup(plan)
    local f = MakeFixture("questierouter", true)
    local ns = f.NS
    f.map = 1412
    f.player = { c = 1, x = -1960, y = 3650, z = 0 }
    f.loaded = { QuestieRouter = true, Questie = true, QuestieDB = true, QuestieRouter_Nav = true }
    f.enabled = {}
    f.paths, f.plans, f.surfaces, f.surfaceReads = {}, {}, { 0 }, 0
    local combatTerrainCalls = 0
    local function terrainCall()
        if f.combat then combatTerrainCalls = combatTerrainCalls + 1 end
    end
    f.behavior.zygor = "success"
    ns.IsAddonLoaded = function(name) return f.loaded[name] == true end
    ns.IsAddonEnabledForCurrentCharacter = function(name) return f.enabled[name] == true end
    ns.ResolveSettableUserWaypointTarget = function(map, x, y) return map, x, y end
    ns.ResolveUserWaypointMapCoordsFromWorldPosition = function(north, west)
        assert(north > 3600 and west < 0, "Map discovery received HBD axis order")
        return 1412
    end
    ns.GetPlayerWaypointDistance = function(_, x, y)
        return math.sqrt((-2000 + x * 100 - f.player.x) ^ 2 + (3600 + y * 100 - f.player.y) ^ 2)
    end
    UnitPosition = function() return f.player.y, f.player.x, f.player.z, f.player.c end
    UnitLevel = function() return 12 end
    UnitFactionGroup = function() return "Horde" end
    C_Map = { GetMapInfo = function(map)
        if map == 91 then return { mapType = 5, parentMapID = 1412 } end
        return { mapType = 3, name = "Zone " .. map }
    end }
    hooksecurefunc = function(owner, method, hook)
        local original = owner[method]
        owner[method] = function(...) local a, b = original(...); hook(...); return a, b end
    end
    local q = { ready = true, db = { enabled = true, travel = { enabled = true, gridRoutes = true, routeStyle = "roads" } },
        charDB = { knownTaxi = { [77] = true } }, listeners = {}, Router = {}, Bridge = {},
        HBD = { GetPlayerWorldPosition = function() return f.player.x, f.player.y, f.player.c end,
            GetWorldCoordinatesFromZone = function(_, x, y, map) return -2000 + x * 100, 3600 + y * 100, map == 12 and 0 or 1 end },
        ZoneCoordsFromWorld = function(_, x, y) return (x + 2000) / 100, (y - 3600) / 100 end }
    QuestieRouter = q
    function q:On(event, fn) self.listeners[event] = fn end
    function q:Fire(event, ...) if self.listeners[event] then self.listeners[event](...) end end
    function q.Bridge:FindMapLibs(hbd) q.HBD = hbd end
    function q.Router:Invalidate() end
    function q.Router:Plan(sx, sy, sc, source, gx, gy, gc, destination, walking)
        local from = { x = sx, y = sy, inst = sc, zone = source, start = true }
        local to = { x = gx, y = gy, inst = gc, zone = destination, goal = true }
        f.plans[#f.plans + 1] = { from = from, to = to, walking = walking }
        if plan then return plan(from, to, walking) end
        return { { kind = "walk", from = from, to = to } }, 100
    end
    q.Router.RouteFrom = function() error("The map preview was used as the itinerary API") end
    QuestieRouter_NavEngine = {
        Resident = function() return f.terrainAvailable ~= false end,
        SurfacesAt = function(c, north, west, out, areas)
            assert(c == 1 and north > 3600 and west < 0, "Terrain floor read uses the wrong world coordinates")
            f.surfaceReads = f.surfaceReads + 1
            if not f.surfaces then return nil end
            for i, height in ipairs(f.surfaces) do
                out[i], out[-i] = height, f.surfaceMarks and f.surfaceMarks[i] or 0
                areas[i] = f.surfaceAreas and f.surfaceAreas[i] or 0
            end
            return #f.surfaces
        end,
        AreaName = function(_, id) return f.areaNames and f.areaNames[id] end,
        Available = function() terrainCall(); return f.terrainAvailable ~= false end,
        Find = function(c, from, to, done, options)
            terrainCall()
            local job = { c = c, from = from, to = to, done = done, options = options }
            f.paths[#f.paths + 1] = job
            return job
        end,
        Cancel = function(job)
            job.cancelled = true
            job.done(nil)
        end,
        Sight = function(c, y, x, z, targetY, targetX, targetZ, profile)
            terrainCall()
            assert(y > 3600 and x < 0 and targetY > 3600 and targetX < 0 and type(z) == "number" and profile == "Horde")
            return f.clear
        end,
    }
    assert(loadfile("integrations/guides/questierouter/runtime.lua"))()
    assert(loadfile("bridge/routing/backends/questierouter.lua"))()
    f.q, f.backend = q, ns.RoutingBackend_QuestieRouter
    function f.open(map, x, y, title)
        local record = f.start(map or 1412, x or .5, y or .6, title or "Accept Winterhoof Cleansing")
        ns.ReconcileRoutePlanning(record)
        f.drain()
        ns.Internal.RouteProgress.EnsureLeg(record)
        ns.Internal.RouteProgress.Refresh(record)
        return record
    end
    function f.observe()
        local frame = assert(ns.Internal.RouteProgress.frame)
        frame.scripts.OnUpdate(frame, .2)
        assert(combatTerrainCalls == 0, "Navigation queried terrain during combat")
    end
    return f
end

-- With no authored Sanctum edge, the same QuestieRouter adapter receives
-- a doorway target for its normal planner and retains the verified NPC.
do
    local f = Setup()
    local ns = f.NS
    f.map = 1453
    GetSubZoneText = function() return "Mage Quarter" end
    IsOutdoors = function() return true end
    ns.GetGuideVisibilityState = function() return "visible" end
    assert(ns.RouteViaBackend(1453, .4936, .8592, "Talk to Jennea Cannon", nil, {
        authority = "guide", guideProvider = "questierouter", guideTarget = { navigationNpcID = 5497 },
    }))
    f.drain()
    local record = ns.State.routing.guideRouteState
    assert(record.backend == "questierouter" and #f.plans == 2)
    assert(record.legs[#record.legs - 1].sanctumCrossing.to == "inside")
    assert(record.target.x == .4936 and record.target.y == .8592)
    rawset(_G, "GetSubZoneText", nil)
    rawset(_G, "IsOutdoors", nil)
end

-- Forever returned 0 throughout Hunter Rise. The native engine echoes the
-- requested origin height, then returns measured terrain heights 135 and 137.
do
    local f = Setup()
    f.surfaces = { 135 }
    local r = f.open(1412, .95, .85)
    f.observe()
    local job = assert(f.paths[1])
    assert(job.from.z == 135, "Thunder Bluff used the client placeholder as a path origin")
    job.done({job.from, {x=3650,y=-1950,z=135}, {x=3675,y=-1950,z=137}, job.to})
    f.drain()
    assert(not r.currentLeg.walking.required, "Thunder Bluff ordinary road became a lift")
    for i=1,10 do f.player.x=-1960+i; f.drain(.21); f.observe() end
    for i=1,18 do f.player.y=3650+i; f.drain(.21); f.observe() end
    assert(r.currentLegIndex == 2 and #f.paths == 1, "Stayed on the first pin 18 yards beyond it")
    local reads = f.surfaceReads
    for _=1,30 do f.drain(.21); f.observe() end
    assert(f.surfaceReads == reads, "Repeated an unchanged terrain floor lookup")
end

do
    local f = Setup()
    f.surfaces = { 69, 135 }
    local r = f.open(1412, .95, .85)
    f.observe()
    local job = assert(f.paths[1])
    assert(job.from.z == nil, "Selected a starting floor in a stacked cell")
    job.done({job.from,{x=3650,y=-1950,z=69},{x=3650,y=-1950,z=135},job.to})
    f.drain()
    f.player.x=-1950
    f.observe()
    assert(r.currentLegIndex == 1 and r.currentLeg.walking.required, "Guessed a lift landing from XY")
    f.player.z=69
    f.observe()
    assert(r.currentLegIndex == 2)
    f.player.z=0
    f.observe()
    assert(r.currentLegIndex == 2, "Placeholder crossed the real lift")
    f.player.z=135
    f.observe()
    assert(r.currentLegIndex == 3, "Measured arrival on the upper deck was ignored")
end

-- A cold terrain cell can become readable while the player is stationary.
-- A change of indoor state or subzone at the same position invalidates the
-- sampled floor. Native area names and indoor marks refer to distinct decks.
do
    local f = Setup()
    local wasIndoors, wasSubzone = IsIndoors, GetSubZoneText
    local inside, zone = false, ""
    IsIndoors = function() return inside end
    GetSubZoneText = function() return zone end
    f.surfaces = nil
    local r = f.open(1412, .95, .85)
    f.observe()
    local function height() return select(4, f.backend.ReadNavigationProgress(r)) end
    assert(height() == nil)
    f.surfaces, f.surfaceMarks = {150, 129, 135}, {0, 2, 2}
    f.surfaceAreas, f.areaNames = {32, 0, 0}, {[32]="Upper Deck"}
    local before = f.surfaceReads
    f.drain(.6)
    assert(height() == nil and f.surfaceReads == before + 1, "Cold cell did not retry")
    inside = true
    assert(height() == 129, "Client indoor evidence failed to rule out the outdoor surface")
    zone = "Upper Deck"
    assert(height() == 150, "A matching native subzone did not resolve the deck")
    before = f.surfaceReads
    assert(height() == 150 and f.surfaceReads == before)
    IsIndoors, GetSubZoneText = wasIndoors, wasSubzone
end

-- At 46.507, 65.569 the Kalimdor mesh has three surfaces. The client
-- returned no height even 18 yards past the bend. Ask the terrain planner
-- for the remaining walk from there, preserving the destination.
for _, combat in ipairs({false, true}) do
    local f = Setup()
    f.surfaces = {150, 129, 135}
    local r = f.open(1412, .95, .85)
    f.observe()
    local first = assert(f.paths[1])
    first.done({first.from, {x=3650,y=-1950,z=135}, {x=3674,y=-1950,z=137}, first.to})
    f.drain()
    if combat then f.combat = true; f.event("PLAYER_REGEN_DISABLED") end
    for i=1,10 do f.player.x=-1960+i; f.drain(.21); f.observe() end
    assert(#f.paths == 1 and r.currentLegIndex == 1, "Guessed a deck at the bend")
    for i=1,18 do f.player.y=3650+i; f.drain(.21); f.observe() end
    if combat then
        assert(#f.paths == 1, "Started a native terrain search in combat")
        f.combat = false
        f.event("PLAYER_REGEN_ENABLED"); f.observe()
    end
    local remaining = assert(f.paths[2], "Still pointing back 18 yards past the ambiguous bend")
    assert(remaining.from.z == nil and remaining.from.x > 3650 and remaining.to.x == first.to.x)
    remaining.done({remaining.from, {x=3674,y=-1950,z=137}, remaining.to})
    f.drain(); f.observe()
    assert(r.currentLeg.walking.to.wy == 3674 and #f.plans == 1)
    for _=1,30 do f.drain(.21); f.observe() end
    assert(#f.paths == 2, "Searched again at the same position")
end

-- Farther along that same road the floor is still uncertain, but every
-- surface in this cell is within the ordinary bend's arrival tolerance.
do
    local f = Setup()
    f.surfaces = {138, 130, 130, 141}
    local r = f.open(1412, .95, .85)
    f.observe()
    local job = assert(f.paths[1])
    assert(job.from.z == nil)
    job.done({job.from, {x=3650, y=-1950, z=138}, {x=3674, y=-1950, z=139}, job.to})
    f.drain()
    f.player.x = -1950
    f.observe()
    assert(r.currentLegIndex == 2 and #f.paths == 1, "A bend on compatible surfaces started another search")
    assert(select(4, f.backend.ReadNavigationProgress(r)) == nil, "Arrival invented a planning height")
end

do
    local f = Setup()
    f.player.x, f.player.y = -1995, 3610
    local record = f.open(1412, .95, .75)
    f.observe()
    local job = assert(f.paths[1])
    job.done({job.from, {x=3610,y=-1955,z=0}, {x=3675,y=-1955,z=0}, job.to})
    f.drain()
    dofile("tests/walking_corner_replay.lua")(function(x,y)
        f.player.x, f.player.y = -1995+x, 3610+y
        f.drain(.21)
        f.observe()
    end, record)
    assert(#f.paths == 1 and #f.plans == 1, "QuestieRouter searched a road it had already accepted")
end

do
    local f = Setup()
    f.player.x, f.player.y = -1995, 3610
    local record = f.open(1412, .95, .75)
    f.observe()
    local job = assert(f.paths[1])
    job.done({job.from, {x=3610,y=-1955,z=0}, {x=3675,y=-1955,z=0}, job.to})
    f.drain()
    f.player.x, f.player.y = -1985, 3650
    f.observe()
    local obsolete = assert(f.paths[2], "Off-route recovery did not start")
    f.player.x = -1955
    for y=3650,3657 do
        f.player.y = y
        f.drain(.21); f.observe()
    end
    assert(record.currentLegIndex == 2 and obsolete.cancelled, "Rejoin left the old search alive")
    local leg = record.currentLeg
    obsolete.done({obsolete.from, obsolete.to})
    f.drain(); f.observe()
    assert(record.currentLeg == leg and #f.paths == 2, "Late terrain answer replaced the rejoined road")
end

do
    local f = Setup(function(from, to)
        -- Even without the native goal marker, endpoint identity is in world
        -- coordinates; the inverse map projection may be slightly different.
        to.goal = nil
        return {{kind = "walk", from = from, to = to}}, 100
    end)
    local project = f.q.ZoneCoordsFromWorld
    f.q.ZoneCoordsFromWorld = function(...)
        local x, y = project(...)
        return x, y + .00000153608322
    end
    local record = f.open(1412, .9, .9)
    assert(#record.legs == 1 and record.currentLeg.routeLegKind == "destination"
        and record.currentLeg.x == .9 and record.currentLeg.y == .9,
        "QuestieRouter duplicated or moved the final walk after map projection drift")
end

-- The graph can split the same terrain corner between two native road edges.
-- The next edge is still refined when it becomes active.
for _, clearExit in ipairs({true, false}) do
    local f = Setup(function(from, to)
        local via = { x=-1955, y=3610, inst=1, zone=1412, kind="road" }
        return {{kind="walk",from=from,to=via}, {kind="road",from=via,to=to}}, 120
    end)
    f.player.x, f.player.y, f.player.z = -1995, 3610, 135
    f.surfaces, f.clear = {135}, clearExit
    local r = f.open(1412,.45,.85)
    f.observe()
    local job = assert(f.paths[1])
    job.done({job.from, {x=3610,y=-1955,z=135}})
    f.drain()
    local function move(x,y)
        f.player.x, f.player.y = -1995+x, 3610+y
        f.drain(.21); f.observe()
    end
    if clearExit then
        dofile("tests/walking_corner_replay.lua")(move, r)
        assert(#f.plans==1 and #f.paths==2 and f.paths[2].to.x==3685,
            "Passing the road junction must refine the next native edge")
    else
        for x=1,16 do move(x,0) end
        for i=1,24 do move(16+i,i) end
        assert(r.currentLegIndex==1 and r.currentLeg.walking.required, "Passed an unverified road junction")
    end
end

do
    local f = Setup()
    local wasOutdoors, oldSubzoneText = IsOutdoors, GetSubZoneText
    local outdoors, subzone = true, "Bloodhoof Village"
    IsOutdoors = function() return outdoors end
    GetSubZoneText = function() return subzone end
    local route = f.open(1412, .1, .1, "My Corpse")
    f.observe()
    local job = assert(f.paths[1])
    job.done({job.from, {x=3655, y=-1940, z=0}, job.to})
    f.drain()
    local step = assert(route.currentLeg.walking)
    subzone = "Stonebull Lake"
    f.NS.NoteRouteEnvironmentChanged("ZONE_CHANGED")
    f.drain()
    assert(route.currentLeg.walking == step and #f.plans == 1,
        "Crossing an outdoor subzone discarded the active terrain route to the corpse")
    -- The ghost cuts across the lake. The active corner is now behind it.
    f.player.x, f.player.y = -1988, 3605
    f.observe()
    local recovery = assert(f.paths[2], "A ghost off the accepted path stayed on the old corner")
    assert(route.currentLeg.walking == step and #f.plans == 1 and recovery.from.y == f.player.x)
    for _ = 1, 5 do f.observe() end
    assert(#f.paths == 2)
    f.player.x, f.player.y = -1960, 3650
    f.observe()
    assert(recovery.cancelled, "Rejoining the path left its replacement search running")
    recovery.done({recovery.from, recovery.to})
    assert(route.currentLeg.walking == step)
    f.combat = true
    f.event("PLAYER_REGEN_DISABLED")
    f.player.x, f.player.y = -1988, 3605
    f.observe()
    assert(#f.paths == 2)
    f.combat = false
    f.event("PLAYER_REGEN_ENABLED")
    f.observe()
    recovery = assert(f.paths[3])
    recovery.done({recovery.from, recovery.to})
    f.drain()
    f.observe()
    assert(route.currentLeg.title == "My Corpse" and #f.paths == 3 and #f.plans == 1,
        "A straight replacement kept the old walking corner or restarted the search")
    outdoors = false
    f.NS.NoteRouteEnvironmentChanged("ZONE_CHANGED_INDOORS")
    f.drain()
    assert(#f.plans == 2, "The terrain route survived an indoor transition without validation")
    IsOutdoors, GetSubZoneText = wasOutdoors, oldSubzoneText
end

local f = Setup()
f.q.db.enabled = false
f.clear = true
local record = f.open()
assert(record.backend == "questierouter" and record.routeOutcome == "success")
assert(#f.plans == 1 and f.plans[1].walking == true and f.plans[1].from.x == -1960 and f.plans[1].to.y == 3660)
f.observe()
assert(#f.paths == 0 and #f.messages == 0 and #record.legs == 1 and record.currentLeg.title == "Accept Winterhoof Cleansing")
assert(not f.backend.WantsNavigationProgress(record), "A clear final approach still needs a terrain heartbeat")

f = Setup()
f.clear = false
record = f.open()
assert(#f.paths == 0 and record.backend == "questierouter" and #record.legs == 1,
    "The accepted itinerary waited for terrain")
f.observe()
local search = assert(f.paths[1])
assert(search.from.x == 3650 and search.from.y == -1960 and search.from.z == 0
    and search.to.x == 3660 and search.to.y == -1950 and search.options.style == "roads"
    and search.options.profile == "Horde", "Terrain received the wrong axis, floor, or style")
search.done({ search.from, { x = 3665, y = -1970, z = 0 }, { x = 3660, y = -1950, z = 28 } })
f.drain()
assert(#record.legs == 2 and record.currentLeg.title == "Follow the path" and record.legs[2].title == "Accept Winterhoof Cleansing")
assert(record.legs[2].walking.to.z == 28 and record.legs[2].x == .5 and record.legs[2].y == .6
    and record.legs[2].routeLegKind == "destination", "Refinement lost the actual goal, floor, or presentation")
for _ = 1, 100 do f.observe() end
assert(#f.paths == 1 and #f.plans == 1, "Standing still restarted accepted work")

f.combat = true
f.event("PLAYER_REGEN_DISABLED")
local corner = record.currentLeg
f.player.x, f.player.y, f.player.z = -1970, 3665, 25
f.observe()
assert(record.currentLeg == corner, "Walking corner advanced from the wrong floor")
f.player.z = 0
f.observe()
assert(record.currentLeg == record.legs[2], "Accepted walking corner stalled in combat")
assert(#f.plans == 1 and #f.paths == 1, "Following the combat route repeated a search")

-- Cross several accepted points between two position samples, including the
-- airborne shortcut check that would otherwise query native sight.
f = Setup()
record = f.open(1412, .98, .5)
f.observe()
search = assert(f.paths[1])
search.done({search.from, {x=3650, y=-1950}, {x=3650, y=-1945}, {x=3650, y=-1940}, search.to})
f.drain()
local wasFlying = IsFlying
IsFlying = function() return true end
f.combat = true
f.event("PLAYER_REGEN_DISABLED")
f.observe()
f.player.x = -1930
f.drain(.2)
f.observe()
assert(record.currentLegIndex == 4 and record._coreLastAdvanceReason == "walking_catch_up",
    "Combat stalled progress past accepted walking points")
IsFlying = wasFlying

f = Setup()
record = f.open()
f.observe()
f.clear = true
search = assert(f.paths[1])
search.done({ search.from, { x = 3655, y = -1955 }, search.to })
assert(#record.legs == 1 and not record.currentLeg.walking, "A cold cache kept an unnecessary detour after sight became available")

f = Setup()
record = f.open()
f.observe()
search = assert(f.paths[1])
search.done({ search.from, { x = 3660, y = -1957, z = 22 } })
assert(#record.legs == 2 and record.legs[1].walking.required and record.legs[1].walking.to.z == 22
    and record.legs[2].walking.to.z == nil, "A snapped endpoint overwrote the real destination or its floor")

f = Setup(function(from, to)
    local corner = { x = -1920, y = 3650, inst = 1, zone = 1412 }
    return { { kind = "walk", from = from, to = corner }, { kind = "walk", from = corner, to = to } }, 120
end)
record = f.open(1412, .9, .9)
assert(#record.legs == 2)
f.observe()
search = assert(f.paths[1])
assert(#f.paths == 1 and search.to.y == -1920, "Started terrain for a future walk")
search.done({ search.from, search.to })
f.player.x = -1920
f.observe()
assert(record.currentLeg.routeLegKind == "destination")
f.observe()
assert(#f.paths == 2 and f.paths[2].to.y == -1910, "The next walk was not refined after arrival")

f = Setup()
record = f.open()
f.observe()
search = assert(f.paths[1])
f.drain(8)
assert(search.cancelled and record.backend == "questierouter" and #record.legs == 1 and #f.messages == 0)
f.player.x = -1990
f.observe()
assert(#f.paths == 1, "Movement bypassed the terrain retry cooldown")
f.drain(15)
f.observe()
assert(#f.paths == 2 and f.backend.counters.retries == 1, "Both retry conditions did not start one new search")

f = Setup()
record = f.open()
f.observe()
search = assert(f.paths[1])
f.combat = true
f.event("PLAYER_REGEN_DISABLED")
assert(search.cancelled)
f.player.x = -1990
f.drain(30)
f.observe()
assert(f.backend.counters.failed == 0 and #f.paths == 1, "Combat counted as a terrain timeout")
search.done({ search.from, search.to })
assert(#record.legs == 1 and not record.currentLeg.walking)
f.combat = false
f.event("PLAYER_REGEN_ENABLED")
f.observe()
assert(#f.paths == 2 and f.paths[2].from.y == -1990, "Combat did not resume once from the new position")
local replacement = f.open(1412, .8, .8, "New waypoint")
f.observe()
assert(f.paths[2].cancelled and #f.paths == 3)
f.paths[2].done({ f.paths[2].from, f.paths[2].to })
assert(replacement.currentLeg.title == "New waypoint" and not replacement.currentLeg.walking)

for _, clear in ipairs({ false, true }) do
    f = Setup()
    record = f.open()
    f.observe()
    search = assert(f.paths[1])
    f.combat = true
    f.event("PLAYER_REGEN_DISABLED")
    replacement = f.open(1412, .9, .9, "Replacement in combat")
    f.observe()
    if clear then f.NS.ClearManualRoute("explicit") end
    search.done({ search.from, search.to })
    f.drain(30)
    f.combat = false
    f.event("PLAYER_REGEN_ENABLED")
    f.drain()
    for _ = 1, 10 do f.observe() end
    if clear then
        assert(not f.NS.GetManualAuthority() and #f.paths == 1, "Cleared combat route restarted terrain")
    else
        assert(f.NS.GetManualAuthority() == replacement and #f.paths == 2 and f.paths[2].to.y == -1910,
            "Fresh combat destination lost or duplicated its terrain check")
    end
    assert(#f.plans == 2, "Combat exit unnecessarily replanned the itinerary")
end

f = Setup()
f.terrainAvailable = false
record = f.open()
f.observe()
assert(record.backend == "questierouter" and #record.legs == 1 and #f.paths == 0 and #f.messages == 0)

for _, kind in ipairs({ "flight", "boat", "zeppelin", "airship", "tram", "portal", "door", "road", "border" }) do
    f = Setup(function(from, to, walking)
        if walking then return nil end
        local fromStop = { x = -1960, y = 3650, inst = 1, zone = 1412, nodeId = 77 }
        local stop = { x = -1910, y = 3680, inst = 1, zone = 1413, nodeId = 88 }
        local edges = { { kind = kind, from = fromStop, to = stop }, { kind = "walk", from = stop, to = to } }
        if kind == "flight" then
            local first = { x = -1930, y = 3655, inst = 1, zone = 1413, nodeId = 79 }
            edges[1].to = first
            table.insert(edges, 2, { kind = "flight", from = first, to = stop })
        end
        return edges, 20
    end)
    f.q.db.travel.gridRoutes = false
    record = f.open(1413, .9, .9)
    assert(record.backend == "questierouter" and #record.legs == 2, kind)
    local leg = record.currentLeg
    if kind == "flight" then assert(leg.taxi.nodeID == 88 and leg.activationCoords.x == .4) end
    if leg.activationCoords then
        f.combat = true
        f.event("PLAYER_REGEN_DISABLED")
        f.observe(); assert(record.currentLeg == leg, "Advanced from boarding point")
        f.map = 1413
        f.player.x, f.player.y = -1930, 3640
        f.observe(); assert(record.currentLeg == leg, "Advanced before reaching arrival side")
        f.player.x, f.player.y = -1910, 3680
        f.observe(); assert(record.currentLeg.routeLegKind == "destination", "Transport did not advance on arrival")
    end
end

f = Setup()
f.q.db.travel.gridRoutes = false
f.NS.ResolveInstanceRouteIntent = function()
    return { instanceName = "Test Dungeon", travelType = "dungeon", entrance = { mapID = 91, x = .8, y = .8 } }
end
record = f.open(1413, .9, .9)
assert(f.plans[1].to.zone == 1412 and #record.legs == 2 and record.legs[1].mapID == 91
    and record.legs[1].title == "Enter Test Dungeon" and record.legs[2].mapID == 1413)

f = Setup(function() return nil end)
record = f.open(12)
local status = f.NS.GetRoutePlanningStatus(record)
assert(record.backend == "zygor" and status.reasons.questierouter == "questierouter_no_path")
f = Setup(function() error("native planner exception") end)
record = f.open()
assert(f.NS.GetRoutePlanningStatus(record).reasons.questierouter == "questierouter_planner_error")

f = Setup()
local hbd = f.q.HBD
f.q.ready, f.q.HBD = false, nil
f.backend.Initialize()
record = f.open()
status = f.NS.GetRoutePlanningStatus(record)
assert(record.backend == "direct" and status.waiting == "questierouter_initializing" and #f.paths == 0 and #f.messages == 0)
f.q.ready = true
f.q:Fire("READY")
f.drain()
status = f.NS.GetRoutePlanningStatus(record)
assert(status.waiting and #f.plans == 0)
f.q.Bridge:FindMapLibs(hbd)
f.drain()
assert(record.backend == "questierouter" and #f.plans == 1 and #f.messages == 0, "Late map bridge did not resume the current route quietly")

f = Setup()
f.q.ready = false
f.loaded.QuestieDB = false
record = f.open()
assert(record.backend == "zygor" and f.NS.GetRoutePlanningStatus(record).reasons.questierouter == "QuestieDB_missing_or_disabled")

f = Setup()
local validator, requests
f.NS.RegisterRouteBackendStateValidator = function(_, fn) validator = fn end
f.NS.RequestRouteBackendStateValidation = function() requests = (requests or 0) + 1 end
f.backend.Initialize()
local valid, initial = validator(); assert(valid)
for _ = 1, 20 do f.q:Fire("SETTINGS_CHANGED") end
assert(not requests, "Appearance events queued route scans")
f.q.db.travel.gridRoutes = false; f.q:Fire("SETTINGS_CHANGED")
assert(requests == 1 and select(2, validator()) ~= initial)
local _, beforeRoad = validator(); f.q.db.customRoads = { { 1, { .1, .2, .3, .4 } } }
assert(select(2, validator()) ~= beforeRoad)
local _, beforeTimes = validator(); f.q.db.travel.times = { ["77-88"] = 15 }; f.q:Fire("FLIGHT_CHANGED", false)
assert(requests == 2 and select(2, validator()) ~= beforeTimes)
local _, beforeGraph = validator(); f.q.Router:Invalidate()
assert(requests == 3 and select(2, validator()) ~= beforeGraph)
print("QuestieRouter itinerary, active walks, transport, startup, and route validation passed")

-- Exercise the installed graph planner through AWP as well as synthetic edge
-- responses. Minimal graph data keeps the fixture independent of saved games.
local native = loadfile(NativePath("forever", "QuestieRouter/Guide/Router.lua"))
if native then
    f = Setup()
    local init
    f.q.L = setmetatable({}, { __index = function(_, key) return key end })
    function f.q:RegisterModule(_, callback) init = callback end
    f.q.TravelData = { nodes = {}, paths = {}, sailings = {
        { "boat", "Test Ferry", 3, { 1, 3650, -1955 }, { 0, 3655, -1950 }, 600 },
    } }
    f.q.db.travel.boats, f.q.db.travel.gridRoutes = true, false
    f.q.charDB.knownTaxiVersion = 7
    C_Map.GetMapInfoAtPosition = function(map) return { mapID = map == 1415 and 12 or 1412 } end
    C_Timer.NewTicker = function() end
    wipe = function(map) for key in pairs(map) do map[key] = nil end end
    native("QuestieRouter", f.q)
    init()
    f.combat = true
    record = f.open(12, .9, .9, "Across the sea")
    local ferry
    for _, leg in ipairs(record.legs) do
        if leg.kind == "boat" then ferry = leg end
    end
    assert(record.backend == "questierouter" and ferry and ferry.questieRouterEdge.to.c == 0)
    assert(#f.paths == 0, "Combat itinerary requested terrain work")
    assert(record.legs[#record.legs].mapID == 12 and record.legs[#record.legs].title == "Across the sea")
    print("Installed QuestieRouter planner contract passed")
end

-- A required floor transition can be missed between observations. It stays
-- protected, but the native worker may replace the obsolete approach.
do
    local lifted = Setup()
    local route = lifted.open(1412,.9,.9)
    lifted.observe()
    local job = assert(lifted.paths[1])
    job.done({job.from,{x=3650,y=-1950,z=0},{x=3650,y=-1950,z=100},
        {x=3690,y=-1930,z=100},job.to})
    lifted.drain()
    lifted.player.x,lifted.player.y=-1950,3650
    lifted.observe(); lifted.observe()
    local transition = route.currentLeg
    assert(transition.walking.required and transition.walking.to.z==100)
    lifted.player.z=100
    for distance=5,45,5 do
        lifted.player.x,lifted.player.y=-1950+distance*.4472135955,3650+distance*.894427191
        lifted.observe()
    end
    local recovery=assert(lifted.paths[2],"Missed required transition never requested a new native path")
    assert(route.currentLeg==transition and #lifted.plans==1,"Transition was skipped without a replacement")
    for _=1,10 do lifted.observe() end
    assert(#lifted.paths==2,"Pending transition recovery was duplicated")
    recovery.done({recovery.from,{x=recovery.to.x,y=recovery.to.y,z=100}})
    lifted.drain(); lifted.observe()
    assert(route.currentLeg.routeLegKind=="destination" and route.x==.9 and route.y==.9)
end

do
    local moved = Setup()
    local route = moved.open(1412,.9,.9)
    moved.observe()
    local job=assert(moved.paths[1])
    moved.player.z=100
    job.done({job.from,{x=3670,y=-1940,z=0},job.to})
    assert(not route.currentLeg.walking,"Same-XY old-floor search result was installed")
    moved.observe()
    assert(#moved.paths==2 and moved.paths[2].from.z==100,"A floor-only move never refreshed the origin")
end
print("QuestieRouter missed floor transitions and old-floor result rejection passed")

do
    local moved=Setup()
    moved.open(1412,.1,.1,"My Corpse"); moved.observe()
    local initial=assert(moved.paths[1])
    initial.done({initial.from,{x=3655,y=-1940,z=0},initial.to}); moved.drain()
    moved.player.x,moved.player.y=-1988,3605; moved.observe()
    local old=assert(moved.paths[2])
    moved.player.z=100
    old.done({old.from,{x=old.to.x,y=old.to.y,z=0}})
    moved.observe()
    assert(#moved.paths==3 and moved.paths[3].from.z==100,
        "Changing floors during recovery inherited a failed-search delay")
end
