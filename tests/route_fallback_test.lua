local make=assert(loadfile("tests/route_planning_fixture.lua"))()
local f=make("mapzeroth",true)
f.behavior.farstrider="success"
local owner=f.start()
assert(owner.routeOutcome=="planning" and owner.backend=="direct")
f.drain()
assert(table.concat(f.calls,",")=="mapzeroth,zygor,farstrider")
assert(owner.backend=="farstrider" and f.db.routingBackend=="mapzeroth" and owner.installed=="farstrider")
assert(#f.messages==1 and f.messages[1]:find("Using FarstriderLib",1,true))
local legs,index,fingerprint=owner.legs,owner.currentLegIndex,owner.planFingerprint
f.behavior.mapzeroth=function(attempt) f.probe=attempt; attempt.record.title="Sandbox only"; return "pending" end
f.moving=true; f.px=101
f.NS.ObserveRouteRecovery(owner); f.drain(10)
assert(f.probe and owner.legs==legs and owner.title=="Final" and owner.planFingerprint==fingerprint)
f.probe:Complete({status="failed",reason="no_path"}); f.drain()
assert(owner.backend=="farstrider" and owner.legs==legs and #f.messages==1)
f.behavior.mapzeroth="success"
f.NS.SignalPreferredRouteRecovery("mapzeroth","HEARTHSTONE_BOUND"); f.drain()
assert(owner.backend=="mapzeroth" and owner.installed=="mapzeroth" and #f.messages==2)
assert(f.messages[2]=="Mapzeroth routing restored.")
local report=f.NS.State.churn.routePlanning
assert(report.mapzeroth.recoveryAttempt==2 and report.mapzeroth.recovered==1)

f=make("mapzeroth",false); owner=f.start(); f.drain()
assert(table.concat(f.calls,",")=="mapzeroth,zygor,farstrider,dugi,direct", "Fallback order/client gate changed")
assert(owner.backend=="direct" and #f.messages==1)
f=make("direct",true); owner=f.start(); f.drain()
assert(#f.calls==1 and f.calls[1]=="direct" and #f.messages==0)
f=make("dugi",true); f.behavior.dugi="intentional_direct"; owner=f.start(); f.drain()
assert(owner.backend=="dugi" and #f.calls==1 and #f.messages==0, "Ignored selected native direct intent")

f=make("zygor",false); f.behavior.zygor=function(a) f.pending=a; return "pending" end
owner=f.start(); f.drain(); local old=f.pending
local replacement=f.start(3,.3,.4,"Replacement"); f.drain()
assert(not old:Complete({status="success",legs={{mapID=2,x=.8,y=.9}}}),"Stale target result accepted")
assert(replacement.title=="Replacement" and replacement.backend=="direct")
f.NS.CancelRoutePlanning(replacement)
assert(not f.pending:Complete({status="success",legs={{mapID=3,x=.3,y=.4}}}))
print("Fallback order, atomic recovery, native intent, direct floor and stale attempts passed")

local stale=make("mapzeroth",true); stale.behavior.farstrider="success"; owner=stale.start(); stale.drain()
stale.behavior.mapzeroth=function(a) stale.probe=a; return "pending" end
stale.NS.SignalPreferredRouteRecovery("mapzeroth","HEARTHSTONE_BOUND"); stale.drain()
owner._routeAcceptedPlanGeneration=owner._routeAcceptedPlanGeneration+1
assert(not stale.probe:Complete({status="success",legs=owner.legs})); stale.drain()
assert(owner.backend=="farstrider" and owner._coreRoutePending==nil,
    "Stale plan generation left an attempt permanently pending")
print("Accepted-generation change rejects and disposes staged recovery passed")

for _,forever in ipairs({false,true}) do
    for _,id in ipairs({"zygor","farstrider","mapzeroth","polestar","dugi"}) do
        if forever or id~="polestar" then
            local matrix=make(id,forever)
            local route=matrix.start(); matrix.drain()
            local order={id}
            for _,entry in ipairs(matrix.NS.Internal.RoutingBackends.entries) do
                if entry.id~=id and (forever or not entry.foreverOnly) then order[#order+1]=entry.id end
            end
            assert(table.concat(matrix.calls,",")==table.concat(order,","),"Wrong fallback sequence from "..id)
            assert(route.backend=="direct" and matrix.db.routingBackend==id and #matrix.messages==1)
        end
    end
end
print("Every preferred backend/client traverses the complete fallback order once passed")

f=make("mapzeroth",true); f.behavior.farstrider="success"
f.start(); f.drain()
f.start(3,.4,.5,"Next guide target"); f.drain()
assert(#f.messages==1,"Same fallback mapping spammed across consecutive destinations")
f.behavior.mapzeroth="success"
f.start(4,.6,.7,"Preferred now works"); f.drain()
assert(#f.messages==2 and f.messages[2]=="Mapzeroth routing restored.")
print("Consecutive destinations deduplicate unchanged fallback announcements passed")
