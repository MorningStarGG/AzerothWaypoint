local f = assert(loadfile("tests/walking_runtime_test.lua"))()
local NS, backend, W = f.NS, f.backend, f.NS.Internal.RouteWalking
local addon, mode, speed = MapzerothAddon, "ground", nil
IsFlying = function() return mode == "flying" end
UnitOnTaxi = function() return mode == "taxi" end
GetUnitSpeed = function() return speed end
local db = NS.GetDB()
NS.GetDB = function() return db end
local path, duringPlan
addon.RoadNet.Expand = function(_, value) return value end
local planCalls = 0
addon.Journey.PlanEntry = function()
    planCalls = planCalls + 1
    if duringPlan then duringPlan() end
    return { cost = 1, steps = {{ method = "walk", fromID = path[1].id,
        nodeID = path[#path].id, text = "Walk to objective", path = path }} }
end
path = {{id="A", mapID=1, x=.1, y=.1}, {id="B", mapID=1, x=.14, y=.1},
    {id="C", mapID=1, x=.14, y=.165}, {id="D", mapID=1, x=.9, y=.1}}
do
    local road = f.start()
    local plans, adds, removes = planCalls, f.counts()
    dofile("tests/walking_corner_replay.lua")(function(x,y) f.setPosition(100+x,100+y); f.tick() end, road)
    f.assertPublished(road)
    local newAdds, newRemoves = f.counts()
    assert(planCalls == plans and newAdds - adds <= 1 and newRemoves - removes <= 2,
        "Ordinary rejoin repeated planning or churned future pins")
end
for _, hold in ipairs({"combat", "loading"}) do
    local road = f.start()
    local frame = NS.Internal.RouteProgress.frame
    if hold == "combat" then f.setCombat(true) else frame.scripts.OnEvent(frame, "LOADING_SCREEN_ENABLED") end
    f.setPosition(140,120); f.tick()
    if hold == "combat" then f.setCombat(false) else frame.scripts.OnEvent(frame, "LOADING_SCREEN_DISABLED") end
    f.tick()
    assert(road.currentLegIndex == 1, "Suspension alone proved passage")
    for y=121,128 do f.setPosition(140,y); f.tick() end
    assert(road.currentLegIndex == 2 and road._coreLastAdvanceReason == "walking_rejoin",
        "Fresh movement after " .. hold .. " did not rejoin")
end
local function points(xs)
    path = {}
    for i, x in ipairs(xs) do path[i] = { id = "P" .. i, mapID = 1, x = x / 1000, y = .1 } end
end
points{100, 102, 105, 110, 130, 900}
local record = f.start()
assert(record.currentLegIndex == 1)
f.setPosition(121,100); f.tick()
assert(record.currentLegIndex == 4 and record._coreLastAdvanceReason == "walking_catch_up",
    "One real movement sample did not catch up through short ordinary legs")
f.assertPublished(record)
local a, r, e = f.counts()
f.tick() -- consume the new leg once
a, r, e = f.counts()
for _ = 1, 50 do f.tick() end
local aa, rr, ee = f.counts()
assert(a == aa and r == rr and e == ee, "Catch-up created idle work")

-- Dense geometry is bounded per tick without losing the remaining proof.
local dense = {100}
for i = 1, 300 do dense[#dense + 1] = 100 + i / 10 end
dense[#dense + 1] = 900
points(dense); record = f.start()
f.setPosition(135,100)
local previous = record.currentLegIndex
for i = 1, 4 do
    f.tick()
    assert(record.currentLegIndex - previous <= 128, "Walking work exceeded its per-tick budget")
    previous = record.currentLegIndex
end
assert(record.currentLeg.x == .9, "Budget continuation lost the remaining passed-point evidence")
points{100, 102, 105, 110, 130, 900}

-- A switch/plan can finish after the player has passed its first points.
duringPlan = function() f.setPosition(107,100) end
record = f.start()
duringPlan = nil
assert(record.currentLegIndex == 3 and record._coreLastAdvanceReason == "walking_join")
f.assertPublished(record)

-- A real mounted-speed observation can justify more than the old 40 yards.
points{100, 130, 160, 190, 900}
record = f.start()
speed = 100
f.setPosition(170,100); f.tick(.8)
assert(record.currentLegIndex == 3, "Measured fast movement was treated as a teleport")
speed = nil
record = f.start()
f.setPosition(170,100); f.tick(.8)
assert(record.currentLegIndex == 1, "Unknown speed justified a discontinuous jump")
assert(W.MovementLimit(1,1000) == 200)

-- Taxi coordinates never establish passage, even when a sample crosses a point.
record = f.start(); mode = "taxi"
f.setPosition(140,100); f.tick()
assert(record.currentLegIndex == 1)
mode = "ground"

-- Native flight connectivity, not IsFlying or a flyable-map flag, approves a shortcut.
local container = { path = "outdoor" }
addon.World.GetNodeContainer = function() return container end
addon.World.GetContainerForMap = function() return container end
local flyAllowed, boundary = true, nil
addon.World.GetFlag = function(_, _, flag)
    return (flag == "fly" and flyAllowed) or (flag == "indoor" and boundary == "interior")
end
addon.World.GetPhase = function() if boundary == "phase" then return "other-phase", 1 end end
addon.World.IsMilestone = function(_, id) return boundary == "milestone" and id == "P3" end
local nativeBuild, flyEdge = addon.Journey.Build, true
addon.Journey.Build = function(...)
    local session = nativeBuild(...)
    session.graph = { phase = {}, adjacency = { P1 = flyEdge and {{ to = path[#path].id, method = "fly" }} or {} } }
    return session
end
local plans, expectedPreference = 0, "mapzeroth"
NS.RequestRoutePlan = function(owner, preferred, _, kind)
    assert(owner == record and preferred == expectedPreference and kind == "refresh")
    plans = plans + 1; return true
end
points{100, 130, 170, 300, 900}
db.followGroundPathsWhileFlying = false
record = f.start()
assert(record.currentLeg.walking.group.airborne, "Native direct flight edge was not copied")
local ground = record.currentLeg
mode = "flying"; f.tick()
assert(record.currentLeg.airborneShortcut and record.currentLeg.x == .9)
f.assertPublished(record)
local generation = record._routeAcceptedPlanGeneration
for _ = 1, 20 do f.tick() end
assert(record._routeAcceptedPlanGeneration == generation and plans == 0, "Idle flight rebuilt the route")
mode = "ground"; f.tick()
assert(not record.currentLeg.airborneShortcut and record.currentLeg == ground and plans == 1)
for _ = 1, 10 do f.tick() end
assert(plans == 1, "Landing repeatedly requested planning")

-- The preference applies immediately at rest; required stops still survive.
mode = "flying"; db.followGroundPathsWhileFlying = true; f.tick()
assert(not record.currentLeg.airborneShortcut)
db.followGroundPathsWhileFlying = false; f.tick()
assert(record.currentLeg.airborneShortcut)
db.followGroundPathsWhileFlying = true; f.tick()
assert(not record.currentLeg.airborneShortcut and plans == 2)

-- No edge, no shortcut. Forever's no-fly flags also fail closed.
mode = "ground"; flyEdge = false; record = f.start()
assert(not record.currentLeg.walking.group.airborne)
mode = "flying"; db.followGroundPathsWhileFlying = false; f.tick()
assert(not record.currentLeg.airborneShortcut)
mode = "ground"; flyEdge = true
flyAllowed = false
record = f.start(); mode = "flying"; f.tick()
assert(not record.currentLeg.airborneShortcut)
flyAllowed = true

-- Interior, phase and milestone boundaries never inherit flight approval.
for _, barrier in ipairs{"interior", "phase", "milestone"} do
    mode = "ground"
    boundary = barrier
    record = f.start(); mode = "flying"; f.tick()
    assert(not record.currentLeg.airborneShortcut, "Flight bypassed " .. barrier)
end
boundary = nil
mode = "ground"; record = f.start()
local playerStart = addon.GetPlayerStart
addon.GetPlayerStart = function() error("unreadable location") end
mode = "flying"; f.tick()
assert(not record.currentLeg.airborneShortcut, "Failed eligibility did not retain ground guidance")
addon.GetPlayerStart = playerStart

-- Mode changes in combat wait; old shortcuts cannot restore a replaced route.
mode = "ground"; record = f.start(); f.setCombat(true)
mode = "flying"; f.tick()
assert(not record.currentLeg.airborneShortcut)
f.setCombat(false); f.tick()
assert(record.currentLeg.airborneShortcut)
mode = "ground"; record = f.start(); f.tick()
assert(not record.currentLeg.airborneShortcut and plans == 2)

-- Landing preserves the user's preferred backend while this is a fallback.
mode = "ground"; record = f.start(); mode = "flying"; f.tick()
assert(record.currentLeg.airborneShortcut)
f.routing.selectedBackend, expectedPreference = "farstrider", "farstrider"
mode = "ground"; f.tick()
assert(plans == 3)
f.routing.selectedBackend, expectedPreference = nil, "mapzeroth"

-- Gliding is actual flight too; secret mode data is unknown, never compared.
IsFlying = function() return false end
C_PlayerInfo = { GetGlidingInfo = function() return true end }
assert(W.ReadMode() == "flying")
C_PlayerInfo = nil
local secret = {}
IsFlying = function() return secret end
local originalProbe = issecretvalue
issecretvalue = function(value) return value == secret end
assert(W.ReadMode() == "unknown")
issecretvalue = originalProbe
print("Walking joins, multi-point catch-up, speed, taxi isolation, native-approved flight, restoration and stale work passed")
