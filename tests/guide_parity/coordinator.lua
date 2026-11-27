-- Use native-derived targets in the actual asynchronous routing coordinator.
-- Backend search and TomTom's UI are boundaries; guide authority, acceptance,
-- cancellation and destination metadata synchronization are production code.
local make = dofile("tests/route_planning_fixture.lua")
return function(client, provider, first, second)
    local f = make("direct", client == "forever")
    local ns = f.NS
    ns.Constants, ns.RecomputeCarrier = {}, f.recompute
    ns.GetZygorAssetPath = function(path) return path end
    ns.GetWorldOverlaySetting = function() return false end
    ns.ClassifyTravelSemantics = function() end
    dofile("integrations/guides/presentation.lua")
    dofile("bridge/routing/special_actions.lua")
    dofile("bridge/routing/carrier_tomtom.lua")
    dofile("bridge/routing/presentation.lua")
    local current = first
    ns.RegisterGuideTargetProvider(provider, { structuredPresentation = true,
        isLoaded = function() return true end, hasGuide = function() return true end,
        getVisibilityState = function() return "visible" end, extractTarget = function() return current end })
    f.behavior.direct = function() return "pending" end
    assert(ns.SelectGuideProvider(provider)); f.drain(); f.drain()
    local initial = assert(f.lastAttempt)
    current = second
    ns.ScheduleGuideProviderEvaluation(provider, "QUEST_ACCEPTED"); f.drain()
    local latest = assert(f.lastAttempt)
    local leg = ns.RouteSpecials.MakeDestinationLeg("direct", first.mapID, first.x, first.y, first.title)
    leg.semanticQuestID, leg.iconHintQuestID, leg.subtext = first.semanticQuestID, first.iconHintQuestID, "Stale instructions"
    if latest ~= initial then
        assert(not initial:Complete({ status = "success", legs = { leg } }), "An obsolete native step's plan was accepted")
    end
    assert(latest:Complete({ status = "success", legs = { leg } })); f.drain()
    local record = assert(ns.GetActiveGuideRouteState())
    assert(record.currentLeg.title == second.title and record.currentLeg.semanticQuestID == second.semanticQuestID
        and record.currentLeg.subtext == second.subtext, "Plan acceptance restored previous quest metadata")
    local accepted, generation, calls = record.legs, record._routeAcceptedPlanGeneration, #f.calls
    for _ = 1, 20 do ns.ScheduleGuideProviderEvaluation(provider, "unchanged_native_event") end
    f.drain()
    assert(record.legs == accepted and record._routeAcceptedPlanGeneration == generation and #f.calls == calls,
        "Unchanged native events restarted an accepted route")
    f.behavior.direct = "success"
    local manual = f.start(1413, .2, .3, "User's waypoint")
    f.drain()
    ns.ScheduleGuideProviderEvaluation(provider, "guide_update"); f.drain()
    assert(ns.State.routing.manualAuthority == manual and ns.State.routing.carrierState.authority == manual,
        "A native guide refresh stole manual navigation")
end
