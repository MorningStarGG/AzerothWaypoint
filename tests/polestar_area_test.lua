-- Area/camp arrival uses the real provider, route core and fixed-leg backend.
local f = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS, r, b, routing = AzerothWaypointNS, f.runtime, f.backend, f.routing
local x, y, now, combat = 0, 0, 500, false
---@type number?
local z = 30
GetTime = function() return now end
InCombatLockdown = function() return combat end
r.Compat.GetPlayerWorldPosition = function() return 1, x, y end
r.Compat.GetPlayerUnitPosition = function() return x, y, z, 1 end
UnitPosition = r.Compat.GetPlayerUnitPosition
NS.GetPlayerMapID = function() return 1 end
NS.GetPlayerWaypointDistance = function(_, px, py) return math.sqrt((px * 1000 - x)^2 + (py * 1000 - y)^2) end
NS.After = C_Timer.After
-- Only copied scalar camp metadata may leave the native provider.
local nativeWaypoint = r.Engine.GetWaypoint
local spots = { {}, {}, {}, {}, {}, {}, {}, {}, {} }
local waypoint = { stepIndex = 1, goalIndex = 1, map = 1, x = 50, y = 10, area = 42, r = 8, spot = 5, spots = spots, z = 30 }
r.Engine.GetWaypoint = function() return waypoint end
local provider = NS.Internal.PolestarProvider
provider.Schedule("WAYPOINT_CHANGED"); f.fixture.drain()
local published = assert(f.fixture.provider.extractTarget())
assert(published.navigationArea.radius == 42 and published.navigationArea.arrivalRadius == 8
    and published.navigationArea.spot == 5 and published.navigationArea.spotCount == 9
    and published.navigationArea.search == false and published.navigationArea.continent == 1, "Native area metadata was lost")
for _, value in pairs(published.navigationArea) do assert(type(value) ~= "table", "Mutable native camp table escaped") end
local builds = provider.counters.built
provider.Schedule("WAYPOINT_CHANGED"); f.fixture.drain()
assert(provider.counters.built == builds and f.fixture.provider.extractTarget() == published, "Unchanged camp rebuilt snapshot")
waypoint.r, waypoint.spot, waypoint.search = 10, 6, true
provider.Schedule("WAYPOINT_CHANGED"); f.fixture.drain()
assert(provider.counters.built == builds + 1 and published.navigationArea.arrivalRadius == 8
    and f.fixture.provider.extractTarget().navigationArea.search, "Camp changes were missed or mutated old snapshot")
r.Engine.GetWaypoint = nativeWaypoint
provider.Schedule("WAYPOINT_CHANGED"); f.fixture.drain()
local searches, plans, pending, async = 0, 0, nil, false
Polestar_NavEngine.Find = function(_, from, to, callback)
    assert(not combat, "Area search ran during combat")
    searches = searches + 1
    local points = { { x = from.x, y = from.y, z = 30 }, { x = 100, y = 0, z = 30 },
        { x = 100, y = to.y, z = 30 }, { x = to.x, y = to.y, z = 30 } }
    if async then pending = function() callback(points) end else callback(points) end
    return {}
end
local function planner(context)
    assert(not combat, "Area planner ran during combat")
    plans = plans + 1
    return { { kind = "walk", from = { c = 1, wx = x, wy = y, map = 1 }, to = context.target, label = "Walk" } }
end
local function area(id)
    return { id = id or "guide:9:3:5", radius = 42, arrivalRadius = 8, height = 30, continent = 1,
        search = false, spot = 5, spotCount = 9 }
end
local function target(id)
    local t = f.target("Collect the belts (1/12)", "polestar")
    t.x, t.y, t.navigationArea = .5, .1, area(id)
    return t
end
b.frame = nil
b.Initialize()
local function tick()
    now = now + .21
    local frame = NS.Internal.RouteProgress.frame
    if frame and frame.shown then frame.scripts.OnUpdate(frame, .21) end
    f.fixture.drain()
end
local record = f.run(target(), planner)
tick()
assert(record.currentLeg.polestarPath and record.currentLegIndex < #record.legs, "No approach path")
local beforeSearch, beforePlan = searches, plans
x, y = 450, 100 -- Exactly 42 + 8 yards from the selected camp center.
tick()
assert(record.currentLegIndex == #record.legs and record._routeDestinationAreaState.arrived, "Area boundary did not retire travel")
assert(routing.presentationState.iconHintKind == "quest" and routing.presentationState.overlayTitle == record.target.title,
    "Arrival did not restore objective presentation")
assert(record.target and record.target.semanticQuestID == 9, "Area arrival completed/cleared the objective")
local uid, generation = routing.carrierState.uid, record._routeAcceptedPlanGeneration
for i = 1, 25 do x = 450 + i % 7; tick() end
for i = 1, 25 do tick() end
assert(searches == beforeSearch and plans == beforePlan and routing.carrierState.uid == uid
    and record._routeAcceptedPlanGeneration == generation, "Inside-area roaming/idle rebuilt travel or carrier")
x = 445; tick() -- Native hysteresis remains arrived through 55 yards.
assert(record._routeDestinationAreaState.arrived and plans == beforePlan, "Arrival hysteresis was lost")
x = 444.9; tick()
assert(not record._routeDestinationAreaState.arrived and plans == beforePlan + 1,
    "Leaving the area did not schedule exactly one itinerary refresh")
assert(searches <= beforeSearch + 1, "Leaving the area started competing walking searches")

-- Starting inside the camp must not build a graph, itinerary or walking path.
x, y = 470, 100
beforeSearch, beforePlan = searches, plans
local taxi = r.Nav.GetKnownTaxiNodes
r.Nav.GetKnownTaxiNodes = function() error("An arrived route must not enumerate travel state") end
record = f.run(target("initial"), planner)
tick()
assert(#record.legs == 1 and searches == beforeSearch and plans == beforePlan, "Initial area arrival planned travel")
r.Nav.GetKnownTaxiNodes = taxi
-- A text-only objective refresh stays arrived without changing navigation.
record.target.title = "Collect the belts (2/12)"
b.PlanRoute(record, 1, .5, .1, record.target.title)
NS.RecomputeCarrier(); tick()
assert(plans == beforePlan and searches == beforeSearch, "Progress rebuilt a route inside the area")
x = 430; tick()
assert(plans == beforePlan + 1, "A route created inside an area could not resume after leaving")

-- Native camp changes are authoritative, including overlapping camps.
x = 470
record = f.run(target("camp5"), planner); tick()
local nextTarget = target("camp6")
nextTarget.x = .8
record.target, record.mapID, record.x, record.y = nextTarget, 1, .8, .1
beforePlan = plans
b.PlanRoute(record, 1, .8, .1, nextTarget.title)
NS.RecomputeCarrier(); tick()
assert(not record._routeDestinationAreaState.arrived and plans == beforePlan + 1, "New camp inherited old arrival")
nextTarget.x = .49
record.x = .49
beforePlan = plans
b.PlanRoute(record, 1, .49, .1, nextTarget.title)
NS.RecomputeCarrier(); tick()
assert(record._routeDestinationAreaState.arrived and plans == beforePlan, "Overlapping camp needlessly planned")

-- A known wrong floor blocks arrival; unavailable/zero heights are unknown.
local t = target("floor")
x, y, z = 470, 100, 50
record = f.run(t, planner)
assert(not record._routeDestinationAreaState.arrived, "Known wrong floor accepted arrival")
z = 38
NS.RecomputeCarrier()
assert(record._routeDestinationAreaState.arrived, "Eight-yard floor tolerance differed from native")
z = nil
NS.RecomputeCarrier()
assert(record._routeDestinationAreaState.arrived, "Unknown floor manufactured a mismatch")
z = 0
NS.RecomputeCarrier()
assert(record._routeDestinationAreaState.arrived, "Native unreadable zero height manufactured a mismatch")
z = 30

-- Entry cancels asynchronous walking; its late callback cannot restore travel.
x, y, async = 0, 0, true
record = f.run(target("async"), planner); tick()
local late = assert(pending)
local cancellations = b.counters.cancelled
x, y = 450, 100; tick()
assert(b.counters.cancelled > cancellations and record._routeDestinationAreaState.arrived, "Entry did not cancel owned search")
generation = record._routeAcceptedPlanGeneration
late(); f.fixture.drain()
assert(record.currentLegIndex == #record.legs and record._routeAcceptedPlanGeneration == generation,
    "Late search revived walking inside the area")
async = false
beforePlan, beforeSearch = plans, searches
combat, x = true, 420
tick()
assert(plans == beforePlan and searches == beforeSearch, "Combat area movement planned travel")
combat = false; tick()
assert(plans == beforePlan + 1, "Post-combat area departure did not resume once")

-- The guide source's area policy also works with another selected backend.
local frames, create = {}, CreateFrame
CreateFrame = function(...) local frame = create(...); frames[#frames + 1] = frame; return frame end
local directPlans = 0
NS.GetDB = function() return {routingBackend="direct"} end
NS.RoutingBackend_Direct = { id = "direct", BeginPlan = function(a)
    directPlans = directPlans + 1
    a:Complete({status="success", reason="direct_plan", legs={{mapID=a.mapID,x=a.x,y=a.y,title=a.title,
        kind="walk",routeLegKind="destination"}}})
end }

x, y = 470, 100
record = { backend = "direct", target = target("direct"), guideProvider = "polestar", authority = "guide" }
routing.guideRouteState, routing.manualAuthority = record, nil
NS.AcceptBackendPlan(record, "direct", {
    { mapID = 1, x = .1, y = 0, title = "Approach", kind = "walk", routeLegKind = "carrier" },
    { mapID = 1, x = .5, y = .1, title = record.target.title, kind = "walk", routeLegKind = "destination" },
}, "direct_plan")
NS.RecomputeCarrier()
local monitor = assert(NS.Internal.RouteProgress.frame)
assert(monitor.shown and not b.frame.shown and record.currentLegIndex == #record.legs and record.currentLeg.x == .5, "Shared area policy depended on Polestar backend: "
    .. tostring(monitor.shown) .. "/" .. tostring(b.frame.shown) .. "/" .. tostring(record.currentLegIndex))
x = 430; monitor.scripts.OnUpdate(monitor, .21); f.fixture.drain()
assert(directPlans == 1, "Shared area monitor did not resume other backend")
monitor.scripts.OnUpdate(monitor, .21) -- Observe the newly accepted plan once.
local checked = NS.UpdateRouteDestinationArea
local checks = 0
NS.UpdateRouteDestinationArea = function(...) checks = checks + 1; return checked(...) end
for i = 1, 40 do monitor.scripts.OnUpdate(monitor, .21) end
assert(checks == 0, "Stationary shared area monitor kept evaluating routes")
NS.UpdateRouteDestinationArea = checked
routing.guideRouteState = nil
NS.ClearCarrierWaypoint = function() end
NS.RecomputeCarrier()
assert(not monitor.shown, "Area monitor remained active without a route")
CreateFrame = create
print("Polestar area boundaries, hysteresis, camps, floors, async/combat safety and shared-backend arrival passed")
