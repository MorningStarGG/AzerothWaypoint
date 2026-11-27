local timers, combat, scans, invalidations = {}, false, 0, 0
local fingerprint, failed = "state-a", false
local db = { routingBackend = "direct" }
local NS = { State = { routing = {} } }
_G.AzerothWaypointNS = NS
_G.GetTime = function() return 100 end
_G.InCombatLockdown = function() return combat end
NS.IsWoWForever = function() return true end
NS.GetDB = function() return db end
NS.GetPlayerMapID = function() return 1 end
NS.IsRoutingEnabled = function() return true end
NS.SafeCall = function(fn, ...) if fn then return pcall(fn, ...) end end
NS.After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end
NS.RoutingBackend_Polestar = { id = "polestar", preserveItinerary = true, IsAvailable = function() return true end }
NS.RoutingBackend_Direct = { id = "direct", IsAvailable = function() return true end }
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
NS.RecomputeCarrier = function() end
NS.NoteRouteBackendInvalidated = function() invalidations = invalidations + 1 end
assert(NS.SetBackend("polestar") and db.routingBackend == "polestar", "Backend selection rejected Polestar")
assert(not NS.SetBackend("unknown"), "Unknown backend was accepted")
local record = { backend = "polestar", mapID = 1, x = .8, y = .9, title = "Final" }
NS.State.routing.manualAuthority = record
local function leg(key)
    return { mapID = 1, x = .2, y = .3, kind = "walk", title = "Walk", routeLegKind = "carrier", routeGeometryKey = key }
end
assert(NS.AcceptBackendPlan(record, "polestar", { leg("floor-a") }, "polestar_plan"))
assert(record.routeOutcome == "success", "Successful plan misclassified")
record.currentLeg, record.currentLegIndex = record.legs[1], 1
local old = record.legs
assert(NS.AcceptBackendPlan(record, "polestar", { leg("floor-a") }, "polestar_plan"))
assert(record.lastPlanSkipStatus == "equivalent" and record.legs == old, "Equivalent-plan contract changed")
assert(NS.AcceptBackendPlan(record, "polestar", { leg("floor-b") }, "polestar_plan"))
assert(record.legs ~= old, "Stacked-floor route incorrectly treated as equivalent")
assert(NS.AcceptBackendPlan(record, "polestar", { leg("floor-b") }, "polestar_combat_continuity"))
assert(record.routeOutcome == "planning", "Combat continuity misclassified")
record._routeBackendStateFingerprint = fingerprint
NS.RegisterRouteBackendStateValidator("polestar", function()
    scans = scans + 1
    return not failed, failed and nil or fingerprint
end)
local function drain()
    local pending = timers; timers = {}
    for _, timer in ipairs(pending) do timer.fn() end
end
local signatures = 0
local sign = NS.RoutePlanningCore.GetValidationDestinationSignature
NS.RoutePlanningCore.GetValidationDestinationSignature = function(owner)
    signatures = signatures + 1
    return sign(owner)
end
for i = 1, 100 do assert(NS.RequestRouteBackendStateValidation("polestar", "SPELL_UPDATE_COOLDOWN", "cooldown")) end
assert(signatures == 1, "Unchanged burst rebuilt its validation signature")
assert(#timers == 1 and timers[1].delay == .5 and scans == 0, "Cooldown window extended or scanned on receipt")
drain(); assert(scans == 1 and invalidations == 0, "Unchanged state replanned")
NS.RequestRouteBackendStateValidation("polestar", "cooldown", "cooldown")
NS.RequestRouteBackendStateValidation("polestar", "equipment", "structural")
assert(#timers == 2 and timers[2].delay == 0)
fingerprint = "state-b"
drain(); assert(scans == 2 and invalidations == 1, "Priority promotion executed twice or lost change")
failed = true
NS.RequestRouteBackendStateValidation("polestar", "failed", "structural")
drain(); assert(record._routeBackendStateFingerprint == "state-b" and invalidations == 1, "Failed validation invalidated accepted state")
failed = false
combat = true
for i = 1, 20 do NS.RequestRouteBackendStateValidation("polestar", "cooldown", "cooldown") end
assert(#timers == 0 and scans == 3, "Combat event scanned backend")
combat = false
assert(NS.FlushDeferredRouteBackendStateValidations())
drain(); assert(scans == 4, "Combat events did not produce exactly one validation")
combat = true
NS.RequestRouteBackendStateValidation("polestar", "cooldown", "cooldown")
combat = false
NS.FlushDeferredRouteBackendStateValidations()
NS.CancelRouteBackendStateValidations("polestar", record)
drain(); assert(scans == 4, "Superseding full replan left a discovery callback alive")
NS.RequestRouteBackendStateValidation("polestar", "stale", "structural")
record._routeAcceptedPlanGeneration = record._routeAcceptedPlanGeneration + 1
drain(); assert(scans == 4, "Replaced plan executed stale validation")
-- Two routes can use the same backend before its discovery timer fires.
local validated = {}
NS.RegisterRouteBackendStateValidator("polestar", function(owner, reason)
    validated[#validated + 1] = {owner, reason}
    return true, fingerprint
end)
local replacement = {backend="polestar", mapID=2, x=.2, y=.4, title="Replacement"}
for _, deferred in ipairs({false, true}) do
    combat = deferred
    NS.State.routing.manualAuthority = record
    NS.RequestRouteBackendStateValidation("polestar", "old route", "selected_action")
    NS.State.routing.manualAuthority = replacement
    NS.RequestRouteBackendStateValidation("polestar", "new route", "structural")
    combat = false
    if deferred then assert(NS.FlushDeferredRouteBackendStateValidations()) end
    drain()
    assert(#validated == 1 and validated[1][1] == replacement and validated[1][2] == "new route",
        "Old request displaced the replacement route's validation")
    validated = {}
end
NS.State.routing.manualAuthority = record
NS.State.routing.specialActionCasting = true
NS.RequestRouteBackendStateValidation("polestar", "prior destination", "selected_action")
record.x = .75
NS.RequestRouteBackendStateValidation("polestar", "updated destination", "cooldown")
assert(not NS.FlushDeferredRouteBackendStateValidations())
NS.State.routing.specialActionCasting = false
assert(NS.FlushDeferredRouteBackendStateValidations())
drain()
assert(#validated == 1 and validated[1][2] == "updated destination")
record.x = .8
for _, field in ipairs({"title", "sig"}) do
    local original = record[field]
    NS.RequestRouteBackendStateValidation("polestar", "stale identity", "structural")
    record[field] = "changed"
    drain()
    assert(#validated == 1, "Validation accepted a changed " .. field)
    record[field] = original
end
NS.RequestRouteBackendStateValidation("polestar", "rounded point", "structural")
record.x = .80000001
drain()
assert(#validated == 2 and validated[2][2] == "rounded point", "Equivalent provider coordinates went stale")
record.x = .8
local priorState = record._routeBackendStateFingerprint
NS.RegisterRouteBackendStateValidator("polestar", function()
    NS.State.routing.manualAuthority = replacement
    return true, "obsolete scan"
end)
NS.RequestRouteBackendStateValidation("polestar", "replace during scan", "structural")
drain()
assert(record._routeBackendStateFingerprint == priorState and invalidations == 1)
NS.State.routing.manualAuthority = record
-- A walking refinement replaces exactly its active range, retaining completed
-- transport legs and all future actions. Matching its final endpoint must not
-- jump over the newly inserted corner.
local prefix = { mapID = 1, x = .05, y = .05, kind = "portal", title = "Completed portal", routeLegKind = "carrier" }
local walkGoal = { mapID = 1, x = .8, y = .9, kind = "walk", title = "Goal", routeLegKind = "carrier" }
local suffix = { mapID = 2, x = .5, y = .5, kind = "taxi", title = "Future taxi", routeLegKind = "carrier" }
NS.AcceptBackendPlan(record, "polestar", { prefix, walkGoal, suffix }, "polestar_plan")
record.currentLegIndex, record.currentLeg = 2, record.legs[2]
local corner = { mapID = 1, x = .3, y = .4, kind = "movement", title = "Path corner", routeLegKind = "carrier", preservePlanOnArrival = true }
local goal = { mapID = 1, x = .8, y = .9, kind = "walk", title = "Goal", routeLegKind = "carrier", routeGeometryKey = "fixed" }
local generation = record._routeAcceptedPlanGeneration
assert(NS.ReplaceActiveRouteLegs(record, walkGoal, generation, { corner, goal }))
assert(record.currentLegIndex == 2 and record.currentLeg == corner and record.legs[1] == prefix and record.legs[4] == suffix,
    "Refinement replayed completed travel or skipped its first corner")
assert(not NS.ReplaceActiveRouteLegs(record, walkGoal, generation, { corner, goal }), "Stale generation replaced current path")
local nextCorner = { mapID = 1, x = .4, y = .6, kind = "movement", title = "Replacement", routeLegKind = "carrier" }
assert(NS.ReplaceActiveRouteLegs(record, corner, record._routeAcceptedPlanGeneration, { nextCorner, goal }, goal))
assert(#record.legs == 4 and record.currentLeg == nextCorner and record.legs[4] == suffix,
    "Replacement kept the stale walking tail or dropped future travel")
combat = true
assert(not NS.ReplaceActiveRouteLegs(record, nextCorner, record._routeAcceptedPlanGeneration, { corner, goal }, goal),
    "Combat replaced accepted geometry")
combat = false
local retainedGeneration = record._routeAcceptedPlanGeneration
record._corePlanning, record._coreRoutePending = true, true
assert(NS.RetainBackendPlan(record, "polestar", "retained_itinerary"))
assert(record.currentLeg == nextCorner and record.currentLegIndex == 2 and record._routeAcceptedPlanGeneration == retainedGeneration,
    "Retention changed accepted path progress")
assert(not record._corePlanning and not record._coreRoutePending, "Retention left stale planning/pending flags")
print("Polestar core selection, atomic walking refinement, floor identity and validation coordinator passed")
