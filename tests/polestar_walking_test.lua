local replaceMethod = dofile("tests/replace_method.lua")
-- Fixed paths through the real route core, carrier projection and icon policy.
local fixture = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS, r, backend, routing = AzerothWaypointNS, fixture.runtime, fixture.backend, fixture.routing
local x, y, z, now, combat = 0, 0, 0, 200, false
local originalMapToWorld, originalWorldToMap = r.Compat.MapToWorld, r.Compat.WorldToMap
local playerMap = 1
GetTime = function() return now end
InCombatLockdown = function() return combat end
r.Compat.GetPlayerWorldPosition = function() return 1, x, y end
r.Compat.GetPlayerUnitPosition = function() return x, y, z, 1 end
NS.GetPlayerMapID = function() return playerMap end
NS.GetPlayerWaypointDistance = function(_, px, py) return math.sqrt((px * 1000 - x)^2 + (py * 1000 - y)^2) end
local pathPoints, searches, plans, pending, pathReason = {}, 0, 0, nil, nil
local asynchronous = false
Polestar_NavEngine.Find = function(_, _, _, callback)
    assert(not combat, "Path search ran during combat")
    searches = searches + 1
    if asynchronous then pending = callback else callback(pathPoints, pathReason) end
    return {}
end
r.Nav.PlanRoute = function(context)
    assert(not combat, "Planner ran during combat")
    plans = plans + 1
    return { { kind = "walk", from = { c = 1, wx = x, wy = y, map = 1 }, to = context.target, label = "Final quest" } }
end
backend.frame = nil
backend.Initialize()
local function tick(delta)
    now = now + (delta or .21)
    local frame = NS.Internal.RouteProgress.frame
    if frame and frame.shown then frame.scripts.OnUpdate(frame, delta or .21) end
end
local function plan(points, tx, ty)
    pathPoints = points
    local goal = fixture.target("Final quest")
    goal.x, goal.y = tx / 1000, ty / 1000
    local record = fixture.run(goal, r.Nav.PlanRoute)
    tick()
    fixture.fixture.drain()
    return record
end
do
    local road = plan({{x=0,y=0,z=0},{x=40,y=0,z=0},{x=40,y=65,z=0},{x=90,y=65,z=0}}, 90, 65)
    local beforePlans, beforeSearches = plans, searches
    dofile("tests/walking_corner_replay.lua")(function(px,py) x,y=px,py; tick() end, road)
    assert(plans == beforePlans and searches == beforeSearches, "Polestar searched a road it had already accepted")
    x, y = 0, 0
end
local record = plan({ { x = 0, y = 0, z = 0 }, { x = 100, y = 0, z = 0 },
    { x = 100, y = 100, z = 0 }, { x = 500, y = 100, z = 0 } }, 500, 100)
assert(#record.legs == 3 and record.currentLeg.x == .1 and record.currentLeg.y == 0, "Corners did not become fixed legs")
assert(record.legs[3].x == .5 and record.legs[3].routeLegKind == "destination", "Exact final destination was replaced")
assert(routing.carrierState.x == .1 and routing.presentationState.iconHintKind == "travel", "Normal carrier/marker did not use current walking leg")
local leg, uid, generation, count, planCount = record.currentLeg, routing.carrierState.uid, record._routeAcceptedPlanGeneration, searches, plans
for i = 1, 100 do tick(.21) end
assert(searches == count and plans == planCount and record.currentLeg == leg and record._routeAcceptedPlanGeneration == generation,
    "Idle fixed path searched, replanned, or moved")
assert(routing.carrierState.uid == uid, "Idle fixed path replaced carrier")
-- Replanning the same itinerary must not publish a coarse final destination
-- between fixed path results (the reported travel/destination flicker).
backend.PlanRoute(record, 1, .5, .1, "Final quest")
NS.RecomputeCarrier(); fixture.fixture.drain()
assert(record.currentLeg == leg and record._routeAcceptedPlanGeneration == generation
    and routing.carrierState.x == .1 and searches == count, "Unchanged refresh flickered to the destination/researched")
record.title, record.target.title = "Final quest (1/12)", "Final quest (1/12)"
backend.PlanRoute(record, 1, .5, .1, record.title)
NS.RecomputeCarrier(); fixture.fixture.drain()
assert(record.currentLeg == leg and record._routeAcceptedPlanGeneration == generation
    and routing.carrierState.x == .1 and searches == count, "Text-only refresh dropped fixed legs")
local known = r.Nav.GetKnownTaxiNodes
r.Nav.GetKnownTaxiNodes = function() error("temporarily inaccessible state") end
backend.PlanRoute(record, 1, .5, .1, record.title)
NS.RecomputeCarrier()
assert(record.currentLeg == leg and record._routeAcceptedPlanGeneration == generation
    and routing.carrierState.x == .1, "Failed state scan replaced usable fixed legs")
r.Nav.GetKnownTaxiNodes = known
record._coreResetLegOnNextPlan = true
backend.PlanRoute(record, 1, .5, .1, record.title)
assert(record.currentLeg == leg and routing.carrierState.x == .1, "Environment refresh published a coarse destination")
tick(); fixture.fixture.drain()
assert(record.currentLeg.polestarPath and routing.carrierState.x == .1, "Refreshed geometry did not retain its travel point")
leg, generation, count = record.currentLeg, record._routeAcceptedPlanGeneration, searches
planCount = plans
x = 30; tick()
assert(record.currentLeg == leg and routing.carrierState.x == .1, "Waypoint moved while approaching the corner")
x = 100; tick(); fixture.fixture.drain()
assert(record.currentLegIndex == 2 and record.currentLeg.x == .1 and record.currentLeg.y == .1, "Arrival did not advance to next fixed corner")
assert(plans == planCount and searches == count, "Walking-point arrival restarted planning")
y = 100; tick(); fixture.fixture.drain()
assert(record.currentLegIndex == 3 and routing.presentationState.iconHintKind == "quest", "Final leg did not restore quest presentation")
assert(record.mapID == 1 and record.x == .5 and record.y == .1, "Destination authority changed")

-- Duplicate/collinear samples are removed without skipping actual turns.
-- A near miss can join the adjacent outgoing segment without visiting the
-- exact corner. It advances only the shared route index, with no new search.
x, y, z = 0, 0, 0
local corners = { { x = 0, y = 0, z = 0 }, { x = 100, y = 0, z = 0 },
    { x = 100, y = 100, z = 0 }, { x = 500, y = 100, z = 0 } }
record = plan(corners, 500, 100)
count, planCount = searches, plans
x = 90; tick()
x, y = 100, 8; tick()
assert(record.currentLegIndex == 2 and record._coreLastAdvanceReason == "walking_passed_point",
    "Missed arrival circle did not advance onto outgoing segment")
assert(routing.carrierState.x == .1 and routing.carrierState.y == .1 and searches == count and plans == planCount,
    "Passing point diverged from shared carrier or replanned")
for i = 1, 20 do tick() end
assert(record.currentLegIndex == 2 and searches == count and plans == planCount, "Idle passing state advanced/searched")

-- A single fast sample can cross a small arrival circle without either
-- sampled endpoint being inside it.
x, y = 0, 0
record = plan({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 200, y = 1 }, { x = 500, y = 100 } }, 500, 100)
x = 90; tick()
x, y = 110, .1; tick()
assert(record.currentLegIndex == 2 and record._coreLastAdvanceReason == "walking_swept_arrival", "Fast crossing missed arrival circle")

-- Merely being on a nearby later segment, or moving backwards along the
-- outgoing segment, does not establish passage through this corner.
x, y = 0, 0
record = plan(corners, 500, 100)
x, y = 100, 19; tick() -- Discontinuous relocation, not an observed approach.
y = 8; tick()
assert(record.currentLegIndex == 1, "Reverse movement skipped a missed corner")
x, y = 0, 0
record = plan({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 100, y = 100 },
    { x = 10, y = 100 }, { x = 10, y = 5 }, { x = 300, y = 5 } }, 300, 5)
x, y = 10, 5; tick()
assert(record.currentLegIndex == 1, "Nearby later segment skipped the ordered path")
x, y = 0, 0
record = plan({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 10, y = 3 }, { x = 200, y = 100 } }, 200, 100)
x = 90; tick()
y = 4; tick()
assert(record.currentLegIndex == 1, "Sharp turnback accepted ambiguous corridor progress")

-- A wrong floor, a long observation gap or a large position jump must not
-- become synthetic walking progress.
x, y, z = 0, 0, 30
record = plan(corners, 500, 100)
x = 90; tick()
x, y = 100, 8; tick()
assert(record.currentLegIndex == 1, "Wrong floor passed an ordinary point")
x, y, z = 0, 0, 0
record = plan(corners, 500, 100)
x = 90; tick()
x, y = 100, 8; tick(2)
assert(record.currentLegIndex == 1, "Stale movement sample advanced a point")
x, y = 0, 0
record = plan(corners, 500, 100)
x = 90; tick()
x, y = 100, 60; tick()
assert(record.currentLegIndex == 1, "Discontinuous jump was treated as walking")

-- Required passage stops and the snapped endpoint remain strict even when
-- movement would otherwise pass through their arrival circles.
PolestarNavChokepoints = { [1] = { { wx = 100, wy = 0, kind = "tunnel", name = "Required Tunnel", z = 0, r = 15 } } }
x, y = 0, 0
record = plan(corners, 500, 100)
x = 90; tick()
x, y = 100, 8; tick()
assert(record.currentLegIndex == 1 and record.currentLeg.polestarRequired, "Required passage used ordinary passing corridor")
y = 0; tick()
assert(record.currentLegIndex == 2, "Required passage no longer accepted actual arrival")
PolestarNavChokepoints = nil
x, y = 0, 0
record = plan({ { x = 0, y = 0 }, { x = 480, y = 0 } }, 500, 0)
x = 470; tick()
x = 490; tick()
assert(record.currentLegIndex == 1 and record.currentLeg.x == .48, "Required endpoint accepted swept passage")

-- Combat invalidates pre-combat movement observations; actual post-combat
-- arrival still works through the normal strict-distance path.
x, y = 0, 0
record = plan({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 200, y = 1 }, { x = 500, y = 100 } }, 500, 100)
x = 90; tick()
combat = true; backend.frame.event(nil, "PLAYER_REGEN_DISABLED")
x, y = 110, .1; tick()
combat = false; backend.frame.event(nil, "PLAYER_REGEN_ENABLED"); tick()
assert(record.currentLegIndex == 1, "Pre-combat observation produced post-combat swept progress")
x, y = 100, 0; tick()
assert(record.currentLegIndex == 2, "Normal post-combat arrival broke")

-- Duplicate/collinear samples are removed without skipping actual turns.
x, y = 0, 0
record = plan({ { x = 0, y = 0 }, { x = 20, y = 0 }, { x = 20, y = 0 },
    { x = 50, y = 0 }, { x = 100, y = 0 }, { x = 100, y = 100 } }, 100, 100)
assert(#record.legs == 2 and record.legs[1].x == .1 and record.legs[1].y == 0, "Redundant points survived or corner was dropped")

-- Passage points remain explicit stops even on a straight polyline.
PolestarNavChokepoints = { [1] = { { wx = 100, wy = 0, kind = "tunnel", name = "Test Tunnel", z = 0, r = 15 } } }
record = plan({ { x = 0, y = 0, z = 0 }, { x = 500, y = 0, z = 0 } }, 500, 0)
assert(#record.legs == 2 and record.currentLeg.title == "Go through Test Tunnel", "Passage was not a fixed travel leg")
assert(record.currentLeg.x == .1 and record.currentLeg.arrivalRadius <= 5, "Passage aim kept moving or used a large skip radius")

-- Lifts use real floor-gated movement legs, followed by destination semantics.
PolestarNavChokepoints = { [1] = {
    { wx = 100, wy = 0, z = 0, kind = "lift", name = "Lift", pair = 2, liftEnd = "bottom" },
    { wx = 100, wy = 0, z = 100, kind = "lift", name = "Lift", pair = 1, liftEnd = "top" },
} }
record = plan({ { x = 0, y = 0, z = 0 }, { x = 90, y = 0, z = 0 },
    { x = 100, y = 0, z = 0 }, { x = 100, y = 0, z = 100 }, { x = 500, y = 0, z = 100 } }, 500, 0)
x = 100
for i = 1, 3 do tick() end
assert(record.currentLeg.polestarKind == "lift" and record.currentLeg.title == "Ride the elevator up", "Lift lost travel leg/caption")
assert(backend.CanAdvanceLeg(record, record.currentLeg) == false, "Lift advanced on wrong floor")
z = 100; tick()
assert(record.currentLeg.polestarKind == "lift", "Receiving deck was treated as walking away from the lift")
x = 135; tick()
assert(record.currentLeg.routeLegKind == "destination", "Lift arrival did not advance to destination")
PolestarNavChokepoints = nil

-- The native path's snapped endpoint must not replace the exact final target.
x, y, z = 0, 0, 0
record = plan({ { x = 0, y = 0 }, { x = 480, y = 0 } }, 500, 0)
assert(#record.legs == 2 and record.legs[1].x == .48 and record.legs[2].x == .5, "Snapped endpoint lost its exact final leg")

-- Searches can finish late: join the appropriate fixed segment once, without
-- adopting the current player position as the actual destination.
asynchronous = true
record = plan({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 300, y = 0 }, { x = 500, y = 0 } }, 500, 0)
assert(pending and record.currentLeg.polestarPath == nil, "Pending path published invented points")
x = 220
pending(pathPoints); fixture.fixture.drain()
assert(record.currentLeg.x >= .3 and record.currentLeg.x <= .5, "Late path sent player back to its start")
local stale = pending
local oldLegs = record.legs
backend.Clear(record)
stale(pathPoints)
assert(not record.legs and oldLegs, "Stale result resurrected cleared route")
asynchronous = false

-- A result can arrive after a travel cast/equipment hold starts but before
-- the next monitor tick. It must remain deferred, then rearm once at rest.
local equipmentCheck = NS.IsRouteEquipmentTransactionActive
for _, hold in ipairs({ "cast", "equipment" }) do
    asynchronous = true
    x, y, z = 0, 0, 0
    record = plan(corners, 500, 100)
    local held = true
    NS.State.routing.specialActionCasting = hold == "cast"
    NS.IsRouteEquipmentTransactionActive = function() return hold == "equipment" and held end
    local generation = record._routeAcceptedPlanGeneration
    local complete = pending
    complete(pathPoints)
    assert(record._routeAcceptedPlanGeneration == generation and not record.currentLeg.polestarPath,
        "Asynchronous result replaced a held route")
    NS.State.routing.specialActionCasting, held = nil, false
    count = searches
    tick()
    assert(searches == count + 1, "Deferred result did not rearm once while stationary")
    pending(pathPoints); fixture.fixture.drain()
    assert(record.currentLeg.polestarPath, "Rearmed path was not installed")
end
NS.IsRouteEquipmentTransactionActive = equipmentCheck
asynchronous = false

-- Cached legs remain fixed during combat and searches resume outside combat.
x, y, z = 0, 0, 0
record = plan({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 100, y = 100 }, { x = 500, y = 100 } }, 500, 100)
count, planCount = searches, plans
combat = true
backend.PlanRoute(record, 1, .5, .1, "Final quest")
x = 100; tick()
assert(searches == count and plans == planCount and record.currentLegIndex == 1, "Combat advanced/replanned fixed path")
combat = false
backend.frame.event(nil, "PLAYER_REGEN_ENABLED"); fixture.fixture.drain()
tick(); fixture.fixture.drain()
assert(record.currentLegIndex == 2, "Post-combat fixed leg did not advance")

-- Walking points can span zone maps. A child-map change must not jump over
-- the intervening ordered path to the later destination on that map.
x, y, z, playerMap = 0, 0, 0, 2
local worldToMap, maps = r.Compat.WorldToMap, C_Map
C_Map = { GetMapInfo = function(map) if map == 1 then return { parentMapID = 10 } end end }
r.Compat.WorldToMap = function(_, wx, wy, map)
    if map == 1 and wx < 300 or map == 2 and wx > 200 then return nil end
    return wx / 10, wy / 10
end
record = plan({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 100, y = 100 },
    { x = 250, y = 100 }, { x = 250, y = 200 }, { x = 500, y = 200 } }, 500, 200)
assert(record.legs[1].mapID == 2 and record.legs[3].mapID == 10 and record.legs[#record.legs].mapID == 1,
    "Cross-zone walking points lost map projection")
x, playerMap = 100, 1; tick()
assert(record.currentLegIndex == 2, "Child-map transition skipped ordered walking corners")
r.Compat.WorldToMap, C_Map, playerMap = worldToMap, maps, 1

-- A deviation drops the old, unvisited walking tail while retaining completed
-- leg history without retaining the abandoned path's geometry cache.
x, y = 0, 0
record = plan({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 100, y = 100 }, { x = 500, y = 100 } }, 500, 100)
x = 100; tick()
local past = record.legs[1]
pathPoints = { { x = 160, y = 50 }, { x = 200, y = 50 }, { x = 200, y = 100 }, { x = 500, y = 100 } }
x, y = 160, 50; tick(3); fixture.fixture.drain()
assert(record.legs[1] == past and past.polestarPath == nil and record.currentLeg.x == .2 and record.currentLeg.y == .05,
    "Deviation replayed old points or retained the abandoned geometry cache")

-- Deviation replaces only the remaining walking section, with native long-walk
-- search throttling. It does not restart for every movement sample.
x, y = 0, 0
r.Compat.MapToWorld = function(map, mx, my) return map, mx * 100, my * 100 end
replaceMethod(r.Compat, "WorldToMap", function(_, wx, wy) return wx / 100, wy / 100 end)
record = plan({ { x = 0, y = 0 }, { x = 5000, y = 0 } }, 500, 0)
count = searches
y = 60; tick(3)
assert(searches == count, "Long-walk deviation searched before its 10s window")
tick(8)
-- Stationary positions do not trigger searches even when their timer expires.
assert(searches == count, "Idle deviation retried without movement")
y = 61; tick()
assert(searches == count + 1, "Moved deviation did not search after its throttle window")

-- Hidden/inactive routes must stop their scoped movement monitor.
routing.manualAuthority, routing.guideRouteState = nil, nil
NS.ClearCarrierWaypoint = function() routing.carrierState = nil end
NS.RecomputeCarrier()
assert(not NS.Internal.RouteProgress.frame.shown and NS.Internal.RouteProgress.frame.record == nil, "Inactive route left shared monitor running")
assert(NS.GetPublishedRouteNavigation == nil and backend.GetNavigationAim == nil, "Moving steering API survived cleanup")
r.Compat.MapToWorld, r.Compat.WorldToMap = originalMapToWorld, originalWorldToMap
-- The common cursor catches up through short terrain points in one sample.
x, y, z = 0, 0, 0
record = plan({ { x = 0, y = 0 }, { x = 2, y = 0 }, { x = 5, y = 1 },
    { x = 8, y = 0 }, { x = 12, y = 1 }, { x = 100, y = 0 } }, 100, 0)
x, y = 11, 1; tick()
assert(record.currentLegIndex >= 4, "Polestar retained ordinary points behind one movement observation")

-- A late result cannot use closest-segment joining to skip a required stage.
x, y, z = 0, 0, 0
PolestarNavChokepoints = { [1] = { { wx = 100, wy = 0, kind = "tunnel", name = "Required Tunnel", z = 0, r = 15 } } }
asynchronous = true
record = plan({ { x = 0, y = 0, z = 0 }, { x = 100, y = 0, z = 0 },
    { x = 300, y = 0, z = 0 }, { x = 500, y = 0, z = 0 } }, 500, 0)
x = 220
pending(pathPoints); fixture.fixture.drain()
assert(record.currentLeg.polestarRequired and record.currentLeg.x == .1,
    "Late shared join skipped a required tunnel")
PolestarNavChokepoints, asynchronous = nil, false

-- The global terrain work cap is distinct from an unmapped walk. Movement
-- alone, time alone, and a repeated observation cannot spend another budget.
x, y, z, pathReason = 0, 0, 0, "budget"
record = plan(nil, 600, 35)
local pausedLeg, pausedGeneration = record.currentLeg, record._routeAcceptedPlanGeneration
assert(backend.GetNavigationStatus(record) == "budget")
count = searches
x = 3; tick(61)
assert(searches == count and record.currentLeg == pausedLeg and record._routeAcceptedPlanGeneration == pausedGeneration)
pathReason, pathPoints = nil, { { x = 6, y = 0 }, { x = 30, y = 25 }, { x = 600, y = 35 } }
x = 6; tick(); fixture.fixture.drain()
assert(searches == count + 1 and record.currentLeg ~= pausedLeg)

x, y = 0, 0
record = plan({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 100, y = 100 }, { x = 650, y = 100 } }, 650, 100)
pathPoints, pathReason = nil, "budget"
pausedLeg = record.currentLeg
count = searches
y = 80; tick(3)
assert(searches == count + 1 and record.currentLeg == pausedLeg)
y = 91; tick(20)
assert(searches == count + 1, "Off-route repair tried again inside the budget hold")
tick(41)
assert(searches == count + 1, "An unchanged origin spent another budget")
y = 92; tick()
assert(searches == count + 2, "Eligible movement did not retry the paused repair")
print("Fixed Polestar corners, shared carrier presentation, passage/lift legs, async safety, combat and idle churn passed")
