local fixture = assert(loadfile("tests/rxp_integration_test.lua"))()
local NS, target = AzerothWaypointNS, nil
local API = NS.Internal.RXPProvider
local rxp = API.GetRuntime()
local adapter = fixture.provider
local step = rxp.currentGuide.steps[1]
step.elements = {
    { tag = "goto", zone = 2405, x = 51.22, y = 72.88, arrow = true, textOnly = true, step = step },
    { tag = "collect", id = 100, questId = 9, text = "Collect Journal", rawtext = "Collect Journal in The Ridge", step = step },
}
rxp.arrowFrame.element = step.elements[1]
rxp.RXPFrame.activeSteps = { step }
NS.Internal.RXPPresentation.Invalidate()
API.Schedule("output"); fixture.drain()
target = adapter.extractTarget()
assert(target and target.title == "Collect Journal" and not target.subtext)
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
NS.RegisterGuideTargetProvider("rxp", adapter)
NS.RegisterGuideTargetProvider("zygor", { isLoaded = function() return true end })
NS.State.routing = { activeGuideProvider = "zygor", guideRouteStates = {} }
NS.SyncGuideQueueProjection = function() end
NS.UpdateGuideTarget("rxp", target, false)
NS.State.routing.activeGuideProvider = "rxp"
local record = NS.GetActiveGuideRouteState()
assert(record and record.title == "Collect Journal" and not record.subtext)
NS.State.routing.carrierState = {
    source = "guide", kind = "guide", routeLegKind = "destination", title = target.title,
    sig = "rxp_fixture", finalMapID = target.mapID, finalX = target.x, finalY = target.y,
}
NS.IsInstanceRouteTravelType = function() return false end
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("bridge/routing/presentation.lua"))()
NS.GetDB().worldOverlayShowCoordinateFallback = false
local result = NS.ResolvePresentation()
assert(result.carrierTitle == target.title and result.overlayTitle == target.title
    and result.pinpointSubtext == nil and result.semanticQuestID == 9, "Arrow/plaque/overlay output diverged")
local plans, presentations = 0, 0
record.legs = { { mapID = target.mapID, x = target.x, y = target.y, routeLegKind = "destination", title = target.title } }
record.currentLegIndex = 1
NS.GetEffectiveBackendID = function() return "direct" end
NS.RouteViaBackend = function() plans = plans + 1; return true end
NS.RecomputeCarrier = function() presentations = presentations + 1 end
local textOnly = {}; for key, value in pairs(target) do textOnly[key] = value end
textOnly.title = "Collect localized Journal"
NS.UpdateGuideTarget("rxp", textOnly, false)
assert(plans == 0 and presentations == 1, "Text-only change replanned instead of refreshing presentation")
NS.UpdateGuideTarget("rxp", target, false)
local carrier = NS.State.routing.carrierState
carrier.kind, carrier.routeLegKind, carrier.routeTravelType, carrier.title = "route", "carrier", "travel", "Take the boat to the Ridge"
result = NS.ResolvePresentation()
assert(result.overlayTitle == "Take the boat to the Ridge" and not result.pinpointSubtext,
    "Intermediate travel leg inherited the final objective")
NS.RouteQueueInternal = {
    TrimString = function(value) return type(value) == "string" and value ~= "" and value or nil end,
    GetWaypointSig = function() return "sig" end,
}
assert(loadfile("bridge/routing/queues/projection.lua"))()
local queue = NS.RouteQueueInternal
local projected = queue.ResolveGuideFinalProjectionSnapshot(record)
assert(projected.mirrorTitle == target.title and not projected.pinpointSubtext and projected.semanticQuestID == 9,
    "Queue projection changed the resolved goal")
local entry = {}; queue.CopyGuidePresentationFields(entry, projected)
assert(entry.title == target.title and entry.subtext == nil and entry.guideProvider == "rxp", "Queue label lost source ownership")
print("RXP arrow, plaque, overlay, queue and intermediate travel-leg output passed")
