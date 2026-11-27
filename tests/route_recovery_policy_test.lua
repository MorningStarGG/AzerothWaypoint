local make=assert(loadfile("tests/route_planning_fixture.lua"))()
local f=make("mapzeroth",true)
f.behavior.farstrider="success"
local owner=f.start(); f.drain()
local base=#f.calls
f.moving=true; f.px=101
for _=1,10000 do f.NS.ObserveRouteRecovery(owner) end
assert(#f.calls==base and #f.timers==1,"Movement hot path searched/allocated duplicate timers")
f.drain(9); assert(#f.calls==base)
f.drain(1); assert(#f.calls==base+1)
local status=f.NS.GetRoutePlanningStatus(owner)
assert(status.nextRecoveryAt==f.now+20,"Recovery failure did not back off to 20 seconds")
f.px=202; f.NS.ObserveRouteRecovery(owner)
local timers=#f.timers
for _=1,10000 do f.NS.SignalPreferredRouteRecovery("mapzeroth","SPELL_UPDATE_COOLDOWN") end
assert(#f.timers==timers,"Raw cooldown events bypassed recovery budget")
f.NS.SignalPreferredRouteRecovery("mapzeroth","BAG_UPDATE_DELAYED"); f.drain(1)
assert(#f.calls==base+1,"Ordinary inventory event bypassed recovery backoff")
f.NS.SignalPreferredRouteRecovery("mapzeroth","HEARTHSTONE_BOUND")
for _=1,100 do f.NS.SignalPreferredRouteRecovery("mapzeroth","HEARTHSTONE_BOUND") end
f.drain(); assert(#f.calls==base+2,"Confirmed state change did not bypass/coalesce")
assert(f.NS.GetRoutePlanningStatus(owner).nextRecoveryAt==f.now+40)
f.behavior.mapzeroth="success"
f.NS.NoteRoutePlanningEnvironment("PLAYER_CONTROL_GAINED"); f.drain()
assert(#f.calls==base+2,"Unrelated control event bypassed cooldown")
f.map=3; f.NS.NoteRoutePlanningEnvironment("ZONE_CHANGED_NEW_AREA"); f.drain()
assert(owner.backend=="mapzeroth" and #f.calls==base+3,"Actual map change did not bypass backoff")
assert(#f.messages==2,"Unchanged fallbacks spammed chat")

f=make("zygor",false); f.behavior.zygor="success"; f.combat=true
owner=f.start(); f.drain()
assert(#f.calls==0 and owner.backend=="direct" and owner.routeOutcome=="planning")
for _=1,100 do f.NS.RequestRoutePlan(owner,"zygor",nil,"refresh") end
assert(#f.calls==0)
f.combat=false; f.event("PLAYER_REGEN_ENABLED"); f.drain()
assert(#f.calls==1 and owner.backend=="zygor", "Combat did not resume exactly one plan")

f=make("zygor",false); f.behavior.farstrider="success"; owner=f.start(); f.drain()
f.behavior.zygor=function(a) f.probe=a; return "pending" end
f.NS.SignalPreferredRouteRecovery("zygor","HEARTHSTONE_BOUND"); f.drain()
local stale=f.probe
f.combat=true; f.event("PLAYER_REGEN_DISABLED"); f.drain()
assert(owner.backend=="farstrider" and not stale:Complete({status="success",legs=owner.legs}))
f.behavior.zygor="success"; f.combat=false; f.event("PLAYER_REGEN_ENABLED"); f.drain()
assert(owner.backend=="zygor","Interrupted recovery was lost after combat")

f=make("mapzeroth",true); f.behavior.farstrider="success"; owner=f.start(); f.drain()
f.behavior.mapzeroth="success"; f.taxi=true
f.NS.SignalPreferredRouteRecovery("mapzeroth","HEARTHSTONE_BOUND"); f.drain()
assert(owner.backend=="farstrider","Recovery changed guidance on a taxi")
f.taxi=false; f.NS.NoteRoutePlanningEnvironment("PLAYER_CONTROL_GAINED"); f.drain()
assert(owner.backend=="mapzeroth","Taxi completion failed to resume recovery")
print("Movement budget, state bypass, noise rejection, combat and taxi recovery passed")

local p=make("mapzeroth",true)
p.behavior.farstrider="success"
local active=p.start(); p.drain(); p.moving=true
collectgarbage("collect"); collectgarbage("stop")
local memory=collectgarbage("count")
for i=1,10000 do
    p.now=p.now+1; p.px=i*101
    p.NS.ObserveRouteRecovery(active)
    p.NS.SignalPreferredRouteRecovery("mapzeroth","SPELL_UPDATE_COOLDOWN")
end
local growth=collectgarbage("count")-memory
collectgarbage("restart")
assert(growth<4,"Movement/cooldown hot path allocated "..growth.." KB")
assert(#p.calls==3,"Movement observation invoked a planner synchronously")
print("Recovery hot-path allocations under 4 KB across 10,000 moving/noisy observations passed")

f=make("mapzeroth",true); f.behavior.farstrider="success"; owner=f.start(); f.drain()
f.behavior.mapzeroth="success"
f.NS.State.routing.specialActionCasting=true
f.NS.SignalPreferredRouteRecovery("mapzeroth","HEARTHSTONE_BOUND"); f.drain()
assert(owner.backend=="farstrider","Travel cast did not freeze recovery")
f.NS.State.routing.specialActionCasting=false
f.NS.ScheduleActiveRouteRefresh("post_cast"); f.drain(1)
assert(owner.backend=="mapzeroth","Cast-end refresh did not resume deferred recovery")
f=make("mapzeroth",true); f.behavior.farstrider="success"; owner=f.start(); f.drain()
local equipment=true
f.NS.IsRouteEquipmentTransactionActive=function() return equipment end
f.behavior.mapzeroth="success"
f.NS.SignalPreferredRouteRecovery("mapzeroth","HEARTHSTONE_BOUND"); f.drain()
assert(owner.backend=="farstrider")
equipment=false
assert(f.NS.FlushDeferredRouteActionRefresh())
f.drain(1); assert(owner.backend=="mapzeroth","Equipment restoration did not resume deferred recovery")
print("Travel cast and equipment transaction freeze/resume passed")
