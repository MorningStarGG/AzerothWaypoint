local f = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS, r, backend = AzerothWaypointNS, f.runtime, f.backend
local x, y, now, searches = 0, 0, 1000, 0
---@type number|nil
local z = 0
local falling, swimming, async, pending = false, false, false, nil
local dense, failSearch = false, false
GetTime = function() return now end
IsFalling = function() return falling end
IsFlying = function() return false end
UnitOnTaxi = function() return false end
r.Compat.IsOnTaxi = function() return false end
r.Compat.IsSwimming = function() return swimming end
r.Compat.GetPlayerWorldPosition = function() return 1,x,y end
r.Compat.GetPlayerUnitPosition = function() return x,y,z,1 end
NS.GetPlayerWaypointDistance = function(_, px, py) return math.sqrt((x-px*1000)^2+(y-py*1000)^2) end
Polestar_NavEngine.FindMany = nil
local requests = {}
Polestar_NavEngine.Find = function(_, from, to, done)
    searches = searches + 1
    requests[#requests+1] = {from=from,to=to}
    if failSearch then done(nil,"no safe walking route"); return {} end
    local points = from.z and from.z >= 100 and {{x=from.x,y=from.y,z=from.z},{x=500,y=0,z=100}}
        or {{x=from.x,y=from.y,z=0},{x=100,y=0,z=0},{x=100,y=0,z=100},{x=500,y=0,z=100}}
    if dense and from.z~=100 then
        points={{x=from.x,y=from.y,z=0},{x=100,y=0,z=0},{x=100,y=0,z=10},
            {x=100,y=0,z=40},{x=100,y=0,z=70},{x=100,y=0,z=100},{x=500,y=0,z=100}}
    end
    if async then pending = function() done(points) end else done(points) end
    return {}
end
local function tick(delta)
    now=now+(delta or .21)
    local frame=NS.Internal.RouteProgress.frame
    if frame and frame.shown then frame.scripts.OnUpdate(frame,delta or .21) end
    f.fixture.drain()
end
local function plan(knownLift)
    x,y,z=0,0,0
    PolestarNavChokepoints = {[1]={
        {wx=100,wy=0,z=0,kind="lift",pair=2,liftEnd="bottom",name="Lift"},
        {wx=100,wy=0,z=100,kind="lift",pair=1,liftEnd="top",name="Lift"},
    }}
    if knownLift==false then PolestarNavChokepoints=nil end
    local goal=f.target("Final quest"); goal.x,goal.y=.5,0
    local record=f.run(goal,function(context)
        return {{kind="walk",from={c=1,wx=x,wy=y,z=z,map=1},to=context.target}}
    end)
    tick()
    return record
end
local record=plan()
x=80; tick()
assert(record.currentLeg.polestarKind=="lift", "Native boarding range still required a tiny waypoint circle")
x=100; z=100; tick()
assert(record.currentLeg.polestarKind=="lift")
local count=searches
x=135; tick()
assert(record.currentLeg.routeLegKind=="destination" and searches==count,
    "Observed lift departure searched again or kept the old ride")

record=plan(); x=80; tick(); x=135; tick()
assert(record.currentLeg.polestarKind=="lift", "Walking away on the boarding floor completed a lift")
record=plan(); x=80; tick(); z=nil; x=135; tick()
assert(record.currentLeg.routeLegKind=="destination", "Native unavailable-height departure was lost")

-- No sample inside the upper landing: recover with a real search from above.
record=plan(); x=80; tick(); x,z=125,100; tick(); count=searches
x=140; tick(3); tick()
assert(searches==count+1 and requests[#requests].from.x==140 and requests[#requests].from.z==100)
assert(record.currentLeg.routeLegKind=="destination" and record.currentLeg.x==.5,
    "A missed lift landing kept the old lift or changed the quest destination")
assert(f.routing.presentationState.iconHintKind=="quest" and f.routing.carrierState.x==.5)
for _=1,30 do tick() end
assert(searches==count+1, "Stationary lift recovery repeated its search")

record=plan(); x=80; tick(); x,z=140,150; count=searches; tick(3); tick()
assert(searches==count+1 and requests[#requests].from.z==150
    and record.currentLeg.routeLegKind=="destination","Climbing above the receiving deck left the old lift active")

record=plan(); x=80; tick(); async=true; x,z=140,100; tick(3); tick()
local oldRecovery=assert(pending)
z=150; oldRecovery(); tick(3); tick()
assert(requests[#requests].from.z==150,"A changed floor inherited the failed-search backoff")
assert(pending)(); tick(); async=false

record=plan(); x=80; tick(); x,z=100,100; falling=true; tick(); x=140; tick(3)
assert(record.currentLeg.polestarKind=="lift", "Falling established a receiving-deck observation")
falling=false
record=plan(); x=80; tick(); x,z=100,100; swimming=true; tick(); x=140; tick(3)
assert(record.currentLeg.polestarKind=="lift", "Swimming established lift completion")
swimming=false

dense=true; record=plan(); x=80; tick()
assert(record.currentLeg.polestarKind=="lift" and record.currentLeg.polestarTo.z==100,
    "Intermediate terrain samples split a named native lift into separate rides")
x,z=100,40; tick()
assert(record.currentLeg.polestarKind=="lift")
z=100; tick(); x=140; tick()
assert(record.currentLeg.routeLegKind=="destination")
dense=false
record=plan(false); x=100; tick()
assert(record.currentLeg.polestarRequired and not record.currentLeg.polestarLift
    and record.currentLeg.polestarKind=="walk","Height geometry alone invented a lift")

record=plan(); x=80; tick(); x,z=140,100; failSearch=true; count=searches
tick(3); tick()
assert(searches==count+1 and record.currentLeg.polestarKind=="lift")
for _=1,100 do tick() end
assert(searches==count+1,"A failed lift recovery retried while stationary")
x=170; tick()
assert(searches==count+2,"Movement after the failure backoff did not retry recovery")
failSearch=false

record=plan(); x=80; tick(); async=true; x,z=140,100; tick(3); tick()
local generation=record._routeAcceptedPlanGeneration
local cancel=Polestar_NavEngine.Cancel
Polestar_NavEngine.Cancel=function() assert(pending)() end
backend.StopNavigationProgress(record,generation,"suspended")
assert(record.currentLeg.polestarKind=="lift" and record._routeAcceptedPlanGeneration==generation,
    "Synchronous cancellation callback installed a retired terrain result")
Polestar_NavEngine.Cancel=cancel; async=false

-- An outstanding lower-floor search must not be installed above it at the
-- same XY, nor relabel its original first segment with the player's new floor.
async=true; record=plan(); local old=assert(pending)
z=100; old(); tick()
assert(not record.currentLeg.polestarPath and requests[#requests].from.z==100,
    "Old-floor terrain result was accepted or not re-requested")
assert(pending)(); tick()
assert(record.currentLeg.polestarPath and record.currentLeg.walking.from.z==100)
async=false
PolestarNavChokepoints=nil
print("Polestar native lift boarding/departure, missed observations, floor ownership and idle recovery passed")
