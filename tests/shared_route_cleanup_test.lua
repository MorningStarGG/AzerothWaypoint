local NS = { State = { routing = {} } }
_G.AzerothWaypointNS = NS
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/shared.lua"))()
assert(loadfile("bridge/routing/walking.lua"))()
assert(loadfile("bridge/routing/walking_presentation.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("bridge/routing/core.lua"))()
assert(loadfile("bridge/routing/validation.lua"))()
assert(loadfile("bridge/routing/progress.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("bridge/routing/planning.lua"))()
local active, pending, other = {}, {}, {}
active.backend = "dugi"
NS.GetActiveAuthorityRecord = function() return active end
NS.State.routing.pendingManualAuthority = pending
assert(NS.IsActiveRouteRecord(active, false))
assert(not NS.IsActiveRouteRecord(pending, false) and NS.IsActiveRouteRecord(pending, true))
assert(not NS.IsActiveRouteRecord(other, true) and not NS.IsActiveRouteRecord(nil, true))
local cancelled, equipment = {}, 0
NS.CancelRouteBackendStateValidations = function(id, record) cancelled[#cancelled + 1] = { id, record } end
NS.CancelRouteEquipmentTransaction = function(record) assert(record == active); equipment = equipment + 1 end
local fields = { "legs", "currentLegIndex", "currentLeg", "specialAction", "_corePlanning", "_coreRoutePending",
    "planFingerprint", "_routeBackendStateFingerprint", "lastPlanSkippedAt", "lastPlanSkipReason", "lastPlanSkipStatus",
    "lastPlanSkippedFingerprint", "routeOutcome", "routeOutcomeReason", "routeOutcomeAt", "replanReason",
    "_routeTravelDependencies", "_routeTravelDependencyStates" }
for _, key in ipairs(fields) do active[key] = {} end
active.target = { mapID = 1, x = 0, y = .5 }; active._dugiPrivateToken = 9
NS.ClearAcceptedRoutePlan(active)
for _, key in ipairs(fields) do assert(active[key] == nil, "Cleanup retained " .. key) end
assert(equipment == 1 and cancelled[1][1] == "dugi" and cancelled[1][2] == active)
assert(active.target.mapID == 1 and active._dugiPrivateToken == 9, "Common cleanup erased backend/target ownership")
local make = NS.RouteSpecials.MakeDestinationLeg
local a, b = make("dugi", 1, 0, .5, "Exact"), make("dugi", 1, 0, .5, "Exact")
a.x = .2
assert(b.x == 0 and b.kind == "destination" and b.routeLegKind == "destination" and b.source == "dugi")
assert(make("dugi", nil, 0, .5) == nil)
print("Shared route authority, cleanup, dependencies and copied endpoints passed")
