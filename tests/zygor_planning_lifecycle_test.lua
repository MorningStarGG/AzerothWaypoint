local make=assert(loadfile("tests/route_planning_fixture.lua"))()
local function CreateZygorFixture(queueFindPath, forever)
    local fixture = make("zygor", forever ~= false)
    local ns = fixture.NS
    ns.IsZygorLoaded = function() return true end
    ns.ZGV = function() return {LibRover = {ready = true, QueueFindPath = queueFindPath}} end
    ns.BuildSpecialActionFromZygorNode = function() end
    assert(loadfile("bridge/routing/backends/zygor.lua"))()
    return fixture
end

local handlers = {}
local f = CreateZygorFixture(function(_, _, _, _, _, _, _, handler)
    handlers[#handlers + 1] = handler
end)
local NS = f.NS
f.behavior.farstrider="success"
local owner=f.start(); f.drain()
assert(#handlers==1 and owner.backend=="direct")
handlers[1]("progress"); f.drain()
assert(owner.routeOutcome=="planning")
handlers[1]("failure"); f.drain()
assert(owner.backend=="farstrider" and #f.messages==1)
NS.SignalPreferredRouteRecovery("zygor","HEARTHSTONE_BOUND"); f.drain()
assert(#handlers==2 and owner.backend=="farstrider")
handlers[2]("success",{{m=2,x=.8,y=.9,type="end"}}); f.drain()
assert(owner.backend=="zygor" and #f.messages==2,"Real LibRover recovery did not commit")
local legs=owner.legs
NS.RequestRoutePlan(owner,"zygor",nil,"refresh"); f.drain()
assert(#handlers==3 and owner.legs==legs)
f.drain(3)
assert(owner.backend=="farstrider","Timeout with an accepted route did not report terminal failure")
handlers[3]("success",{{m=2,x=.8,y=.9,type="end"}}); f.drain()
assert(owner.backend=="farstrider","Timed-out native callback replaced fallback")
NS.SignalPreferredRouteRecovery("zygor","HEARTHSTONE_BOUND"); f.drain()
handlers[4]("success",{}); f.drain()
assert(owner.backend=="farstrider","Empty native result was accepted as a complete route")
NS.GetPlayerWaypointDistance=function() return 0 end
f.drain(2); NS.SignalPreferredRouteRecovery("zygor","HEARTHSTONE_BOUND"); f.drain()
handlers[5]("arrival"); f.drain()
assert(owner.backend=="zygor","Confirmed native arrival failed to complete")
print("Real Zygor pending/progress/failure/success/timeout/late/empty/arrival lifecycle passed")

local requests = 0
f = CreateZygorFixture(function(_, _, _, _, _, _, _, handler)
    requests = requests + 1
    handler("failure")
end)
NS = f.NS
f.behavior.farstrider="success"; owner=f.start(); f.drain()
local before=requests
NS.RequestRoutePlan(owner,"zygor",{routeInvalidated=true},"initial"); f.drain()
assert(NS.GetRoutePlanningStatus(owner).attempting=="zygor", "Synchronous native failure prematurely ended bounded retries")
f.drain(.75); f.drain(.75)
assert(requests==before+3 and owner.backend=="farstrider" and #f.messages==1)
print("Synchronous LibRover failure preserves bounded retries and existing fallback passed")

for _, forever in ipairs({true, false}) do
    local client = CreateZygorFixture(function(_, _, _, _, _, _, _, callback)
        callback("success", {{m = 2, x = .79999968719482, y = .90000153608322, type = "end"}})
    end, forever)
    local target = client.start()
    client.drain()
    assert(target.backend == "zygor" and #target.legs == 1 and target.legs[1].routeLegKind == "destination",
        "LibRover's final walking node became a duplicate travel leg after coordinate conversion")
end

for _, forever in ipairs({true, false}) do
    local callbacks = {}
    local client = CreateZygorFixture(function(_, _, _, _, _, _, _, callback)
        callbacks[#callbacks + 1] = callback
    end, forever)
    local target = client.start()
    client.drain()
    client.combat = true
    client.event("PLAYER_REGEN_DISABLED")
    callbacks[1]("success", {{m=2, x=.8, y=.9, type="end"}})
    client.drain(10)
    assert(target.backend == (forever and "zygor" or "direct") and #callbacks == 1)
    client.combat = false
    client.event("PLAYER_REGEN_ENABLED")
    client.drain()
    assert(#callbacks == (forever and 1 or 2), "Combat entry lost or duplicated a LibRover search")
end

-- The installed Retail corridor has an ordinary outside approach and an
-- indoor arrival node. Carry the native gate through acceptance and refresh.
do
    local inside = false
    GetSubZoneText = function() return inside and "Wizard's Sanctum" or "Mage Quarter" end
    IsIndoors = function() return inside end
    local client = CreateZygorFixture(function(_, _, _, _, _, _, _, callback)
        callback("success", {
            {m = 84, x = .4944, y = .8679, type = "walk", title = "Enter the Mage Tower"},
            {m = 84, x = .4921, y = .8709, type = "walk", subzone = "Wizard's Sanctum", indoors = 1},
            {m = 84, x = .4813, y = .9195, type = "end"},
        })
    end, false)
    client.map = 84
    local destination = client.start(84, .4813, .9195, "Portal room")
    client.drain()
    local entrance, indoor = destination.legs[1], destination.legs[2]
    assert(entrance.title == "Enter the Mage Tower" and indoor.arrivalGate.indoors)
    assert(not client.NS.RouteArrivalGateMatches(indoor))
    inside = true
    assert(client.NS.RouteArrivalGateMatches(indoor))
    client.NS.RequestRoutePlan(destination, "zygor", nil, "refresh")
    client.drain()
    assert(destination.backend == "zygor" and destination.legs[2].arrivalGate.subzone == "Wizard's Sanctum")
    rawset(_G, "GetSubZoneText", nil)
    rawset(_G, "IsIndoors", nil)
end
