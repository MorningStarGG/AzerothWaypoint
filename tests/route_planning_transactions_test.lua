local make=assert(loadfile("tests/route_planning_fixture.lua"))()
local f=make("zygor",true)
local NS=f.NS
local commits, rollbacks=0,0
NS.PrepareManualQueueRouteRequest=function(_,_,_,_,meta)
    return {queueID="queue",strictRouteSuccess=true},meta,{strictRouteSuccess=true}
end
NS.CommitPendingManualQueueTransaction=function(record)
    commits=commits+1; assert(record.installed==record.backend,"Queue committed before backend state adoption")
end
NS.RollbackPendingManualQueueTransaction=function() rollbacks=rollbacks+1 end
f.behavior.zygor=function(a) f.wait=a; return "pending" end
f.behavior.mapzeroth="success"
local owner=f.start(); f.drain()
assert(NS.State.routing.pendingManualAuthority==owner and commits==0 and rollbacks==0)
assert(f.db.manualAuthority == nil, "A pending queue route was persisted before acceptance")
f.wait:Complete({status="failed",reason="timeout"}); f.drain()
assert(owner.backend=="mapzeroth" and commits==1 and rollbacks==0 and not NS.State.routing.pendingManualAuthority)
assert(f.db.manualAuthority.identity.kind == "manual" and f.db.manualAuthority.title == owner.title)
assert(f.db.manualAuthority.backend == owner.backend and f.db.activeRouteSource == "manual")
local fingerprint=owner.planFingerprint
f.behavior.mapzeroth=function(a) f.refresh=a; return "pending" end
NS.RequestRoutePlan(owner,"zygor",nil,"refresh"); f.drain()
assert(owner.backend=="mapzeroth" and owner.planFingerprint==fingerprint and commits==1)
f.refresh:Complete({status="failed",reason="no_path"}); f.drain()
assert(commits==1 and rollbacks==0,"Refresh completed a queue transaction twice")

local cancelled = make("zygor",false)
local cancelRouting = cancelled.NS
cancelRouting.PrepareManualQueueRouteRequest=function(_,_,_,_,meta) return nil,meta,{strictRouteSuccess=true} end
cancelRouting.RollbackPendingManualQueueTransaction=function() rollbacks=rollbacks+1 end
cancelled.behavior.zygor=function(a) cancelled.wait=a; return "pending" end
owner=cancelled.start(); cancelled.drain(); local before=rollbacks
assert(cancelRouting.CancelPendingManualRoute("cancelled")); cancelled.drain()
assert(rollbacks==before+1 and not cancelRouting.State.routing.pendingManualAuthority)
assert(not cancelled.wait:Complete({status="success",legs={{mapID=2,x=.8,y=.9}}}))

local invalid = make("mapzeroth",true)
local invalidRouting = invalid.NS
invalid.behavior.mapzeroth=function() error("Planner failure") end
invalid.behavior.zygor=function(a) return a:Complete({status="success",legs={}}) end
invalid.behavior.farstrider=function(a) return a:Complete({status="success",legs={{mapID=2,x=0/0,y=.9}}}) end
invalid.behavior.polestar="success"
owner=invalid.start(); invalid.drain()
assert(owner.backend=="polestar" and invalid.commits==1,"Bad candidate escaped validation or stopped fallback")
invalidRouting.CancelRoutePlanning(owner); invalidRouting.State.routing.manualAuthority=nil
assert(invalidRouting.GetEffectiveBackendID()=="mapzeroth","Availability resolver was replaced by stale accepted backend")
print("Queue atomicity/cancellation, retained guidance, malformed results and exception fallback passed")

local switching = make("mapzeroth",true)
local switchRouting = switching.NS
switching.behavior.mapzeroth=function(a) switching.wait=a; return "pending" end
owner=switching.start(); switching.drain(); local late=switching.wait
assert(switchRouting.SetBackend("direct")); switching.drain()
assert(owner.backend=="direct" and switching.db.routingBackend=="direct")
assert(not late:Complete({status="success",legs={{mapID=2,x=.8,y=.9}}}),"Backend switch accepted old callback")
f=make("direct",true); f.combat=true
owner=f.start(); f.drain()
assert(owner.routeOutcome=="success" and owner.backend=="direct","Selected Direct was unnecessarily deferred")
print("Explicit backend switching, cancellation and combat Direct behavior passed")

for _, id in ipairs({"dugi", "mapzeroth", "polestar"}) do
    local test = make(id, id == "polestar")
    local ns = test.NS
    local scans = 0
    ns.RegisterRouteBackendStateValidator(id, function()
        scans = scans + 1
        return true, "full"
    end)
    test.behavior[id] = function(attempt)
        attempt.record._routeBackendStateFingerprint = test.combat and ns.RouteSpecials.COMBAT_TRAVEL_STATE or "full"
        return attempt:Complete({status="success", legs={ns.RouteSpecials.MakeDestinationLeg(id, attempt.mapID,
            attempt.x, attempt.y, attempt.title)}})
    end
    test.combat = true
    test.start(2, .2, .2, "First"); test.drain()
    local current = test.start(2, .3, .3, "Replacement"); test.drain()
    assert(#test.calls == 2 and scans == 0 and current.backend == id)
    test.combat = false
    assert(ns.FlushDeferredRouteBackendStateValidations())
    test.drain(); test.drain()
    assert(#test.calls == 3 and scans == 1 and test.lastAttempt.owner == current and
        current._routeBackendStateFingerprint == "full", id .. " revalidated a stale or duplicate combat plan")
end

-- Farstrider can fail over to Zygor, whose Retail worker sleeps in combat.
-- Keep the attempt history when resuming that specific fallback.
local fallback = make("farstrider", false)
fallback.combat = true
fallback.behavior.zygor = "success"
owner = fallback.start()
fallback.drain()
assert(owner.backend == "direct" and #fallback.calls == 1 and fallback.calls[1] == "farstrider")
fallback.combat = false
fallback.event("PLAYER_REGEN_ENABLED")
fallback.drain()
assert(owner.backend == "zygor" and #fallback.calls == 2)

local disabled = make("mapzeroth",true)
local disabledRouting = disabled.NS
disabled.behavior.mapzeroth=function(a) disabled.wait=a; return "pending" end
owner=disabled.start(); disabled.drain(); late=disabled.wait
disabled.routing=false; disabledRouting.ReconcileRoutePlanning(owner,nil); disabled.drain()
assert(not late:Complete({status="success",legs=owner.legs}) and not owner._routePlanning)
disabled.behavior.mapzeroth="success"; disabled.routing=true
disabledRouting.ReconcileRoutePlanning(owner,nil); disabled.drain()
assert(owner.backend=="mapzeroth","Reenabled routing left cancelled continuity permanently active")
print("Routing disable/re-enable cancels and safely restores preferred planning passed")

local function StartingQuestieRouter()
    local fixture = make("questierouter", true)
    fixture.readiness = "waiting"
    fixture.NS.RoutingBackend_QuestieRouter.GetReadiness = function()
        return fixture.readiness, "questie_database"
    end
    fixture.behavior.questierouter, fixture.behavior.farstrider = "success", "success"
    return fixture
end

f = StartingQuestieRouter(); NS = f.NS
NS.GetGuideVisibilityState = function() return "visible" end
assert(NS.RouteViaBackend(1412, .45, .55, "Restored guide", nil, { authority = "guide", guideProvider = "polestar" }))
owner = NS.GetActiveAuthorityRecord()
f.drain()
local waiting = NS.GetRoutePlanningStatus(owner)
assert(waiting.waiting == "questie_database" and owner.backend == "direct" and owner.legs[1].title == "Restored guide")
assert(#f.calls == 0 and #f.messages == 0)
f.behavior.zygor = "success"
f.drain(12)
assert(NS.RouteViaBackend(1412, .55, .65, "Updated guide", nil, { authority = "guide", guideProvider = "polestar" }))
owner = NS.GetActiveAuthorityRecord()
f.drain()
assert(NS.GetRoutePlanningStatus(owner).waitUntil == waiting.waitUntil and #f.calls == 0, "Guide replacement renewed the wait")
f.event("LOADING_SCREEN_ENABLED")
f.readiness = "ready"
NS.NotifyRouteBackendReadiness("questierouter", "ready")
f.drain()
assert(owner.backend == "direct" and #f.calls == 0)
f.combat = true
f.event("LOADING_SCREEN_DISABLED")
f.drain()
assert(owner.backend == "questierouter" and #f.calls == 1)
f.combat = false
f.event("PLAYER_REGEN_ENABLED")
f.drain()
assert(owner.backend == "questierouter" and #f.calls == 1 and #f.messages == 0 and owner.legs[1].title == "Updated guide")

local restored = StartingQuestieRouter()
local restoreRouting = restored.NS
local queueCommits = 0
restoreRouting.PrepareManualQueueRouteRequest = function(_, _, _, _, meta)
    return { queueID = "restored-queue", strictRouteSuccess = true }, meta, { strictRouteSuccess = true }
end
restoreRouting.CommitPendingManualQueueTransaction = function() queueCommits = queueCommits + 1 end
owner = restored.start(1, .4, .5, "Restored queue")
restored.drain()
assert(owner.backend == "direct" and owner.queueID == "restored-queue" and queueCommits == 0)
assert(restoreRouting.State.routing.pendingManualAuthority == owner)
restored.readiness = "ready"
restoreRouting.NotifyRouteBackendReadiness("questierouter", "ready")
restored.drain()
assert(owner.backend == "questierouter" and queueCommits == 1 and #restored.messages == 0 and not restoreRouting.State.routing.pendingManualAuthority)

f = StartingQuestieRouter(); NS = f.NS
owner = f.start(1, .4, .5, "First target")
f.drain()
f.drain(30)
assert(owner.backend == "farstrider" and #f.messages == 1 and f.messages[1] == "QuestieRouter is still loading. Using FarstriderLib.")
assert(NS.GetRoutePlanningStatus(owner).reasons.questierouter == "startup_wait_expired")
f.behavior.zygor = "success"
owner = f.start(1, .45, .55, "New target")
NS.ReconcileRoutePlanning(owner)
f.drain()
assert(owner.backend == "zygor" and #f.messages == 1, "Changing fallback backends announced a second failure")
f.readiness = "ready"
NS.NotifyRouteBackendReadiness("questierouter", "ready")
f.drain()
assert(owner.backend == "questierouter" and #f.messages == 2 and f.messages[2] == "QuestieRouter routing restored.")

f = StartingQuestieRouter(); NS = f.NS
owner = f.start()
f.drain()
assert(NS.SetBackend("direct"))
f.readiness = "ready"
NS.NotifyRouteBackendReadiness("questierouter", "ready")
f.drain(30)
assert(owner.backend == "direct" and #f.messages == 0 and #f.calls == 1 and f.calls[1] == "direct",
    "Old readiness or deadline retried after a backend switch")
print("Startup continuity, queue atomicity, readiness, expiry, combat and outage announcements passed")
