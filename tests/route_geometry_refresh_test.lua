local make = assert(loadfile("tests/route_planning_fixture.lua"))()
for _, forever in ipairs({false, true}) do
    local f = make("mapzeroth", forever)
    local NS = f.NS
    f.behavior.mapzeroth = "success"
    local owner = f.start(); f.drain(); NS.Internal.RouteProgress.EnsureLeg(owner)
    local original, generation, calls = owner.currentLeg, owner._routeAcceptedPlanGeneration, #f.calls
    local pending, completed, result
    f.behavior.mapzeroth = function(attempt) pending = attempt; return "pending" end
    local function ticket() return {leg = owner.currentLeg, generation = owner._routeAcceptedPlanGeneration} end
    local request = ticket()
    assert(NS.RequestRouteGeometryRefresh(owner, request, function(ok, reason) completed, result = ok, reason end))
    assert(not NS.RequestRouteGeometryRefresh(owner, ticket(), function() error("Duplicate geometry request") end))
    f.drain()
    assert(owner.currentLeg == original and owner._routeAcceptedPlanGeneration == generation)
    pending:Complete({status = "failed", reason = "no_path"}); f.drain()
    assert(completed == false and result == "no_path" and #f.calls == calls + 1)
    assert(owner.backend == "mapzeroth" and owner.currentLeg == original and f.db.routingBackend == "mapzeroth",
        "Failed walking refresh switched planner or discarded accepted guidance")
    completed = nil; request = ticket()
    assert(NS.RequestRouteGeometryRefresh(owner, request, function(ok) completed = ok end)); f.drain()
    local obsolete = pending
    NS.CancelRouteGeometryRefresh(owner, request)
    assert(completed == false and not obsolete:Complete({status="success",legs={{mapID=2,x=.8,y=.9}}}))
    completed = nil
    assert(NS.RequestRouteGeometryRefresh(owner, ticket(), function(ok) completed = ok end, function() return false end))
    f.drain()
    assert(not pending:Complete({status="success",legs={{mapID=2,x=.8,y=.9}}})); f.drain()
    assert(completed == false and owner.currentLeg == original, "Moved origin accepted old road geometry")
    completed = nil
    assert(NS.RequestRouteGeometryRefresh(owner, ticket(), function(ok) completed = ok end)); f.drain()
    pending:Complete({status="success",legs={{mapID=2,x=.7,y=.8,routeLegKind="carrier"},
        {mapID=2,x=.8,y=.9,routeLegKind="destination"}}}); f.drain()
    assert(completed == true and owner._routeAcceptedPlanGeneration > generation)
    NS.Internal.RouteProgress.EnsureLeg(owner)
    assert(owner.currentLeg ~= original and f.db.routingBackend == "mapzeroth")
    completed=nil
    assert(NS.RequestRouteGeometryRefresh(owner,ticket(),function(ok) completed=ok end)); f.drain()
    obsolete=pending
    NS.RequestRoutePlan(owner,"mapzeroth",nil,"refresh"); f.drain()
    assert(completed==false and pending~=obsolete and not obsolete:Complete({status="success",legs={{mapID=2,x=.8,y=.9}}}),
        "A structural refresh failed to supersede the old geometry request")
end
-- A temporary Mapzeroth request retains its override and global preference.
local f = make("zygor", true)
f.behavior.mapzeroth = "success"
local meta = f.NS.BuildRouteMeta(f.NS.BuildManualIdentity(2, .8, .9), {backendOverride="mapzeroth"})
assert(f.NS.RouteViaBackend(2, .8, .9, "Temporary Mapzeroth", meta))
local owner = f.NS.State.routing.pendingManualAuthority or f.NS.State.routing.manualAuthority
f.drain()
f.NS.Internal.RouteProgress.EnsureLeg(owner)
local selected = f.db.routingBackend
local done
assert(f.NS.RequestRouteGeometryRefresh(owner, {leg=owner.currentLeg,generation=owner._routeAcceptedPlanGeneration},
    function(ok) done=ok end)); f.drain()
assert(done and owner.backendOverride == "mapzeroth" and f.db.routingBackend == selected)
print("Geometry refresh preserves authority, preference, overrides and accepted plans on both clients")
