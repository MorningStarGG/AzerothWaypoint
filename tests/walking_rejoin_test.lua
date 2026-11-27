-- Movement-only cases, independent of provider coordinate systems and clocks.
local now = 100
GetTime = function() return now end
AzerothWaypointNS = { Internal = {} }
local NS = AzerothWaypointNS
assert(loadfile("bridge/routing/walking.lua"))()
local Walking = NS.Internal.RouteWalking
NS.AdvanceActiveWalkingLegs = function(record, leg, generation, index, reason)
    assert(leg == record.currentLeg and generation == record._routeAcceptedPlanGeneration)
    record.currentLeg, record.currentLegIndex = record.legs[index], index
    record.reason, record.advances = reason, record.advances + 1
    return true
end
local function route(coords)
    local group, record, state = {}, {legs={}, currentLegIndex=1, _routeAcceptedPlanGeneration=1, advances=0}, {}
    local previous
    for i, p in ipairs(coords) do
        local point = {c=1, wx=p[1], wy=p[2], z=p[3]}
        if previous then
            local leg = {arrivalRadius=3, routeLegKind=i==#coords and "destination" or "carrier"}
            Walking.Bind(leg, group, previous, point, p.required or i==#coords)
            record.legs[#record.legs+1] = leg
        end
        previous = point
    end
    record.currentLeg = record.legs[1]
    group.joined = true -- Tests begin after acceptance, including at an already missed corner.
    local function sample(x,y,z,delta,observedAt)
        now = now + (delta or .2)
        return Walking.Progress(state, record, 1, x,y,z,observedAt)
    end
    return record, sample
end

-- Several short bends on a continuous lane form one forward rejoin.
local bends = {{0,0},{40,0},{42,4},{39,9},{40,14},{40,65},{80,65}}
local record, sample = route(bends)
for y=18,24 do sample(40,y) end
assert(record.currentLegIndex == 5 and record.advances == 1 and record.reason == "walking_rejoin")

-- A shallow turn with the player just outside the ordinary passing corridor.
record, sample = route({{0,0},{40,0},{80,20},{140,20}})
for x=58,69 do sample(x,(x-40)/2+4) end
assert(record.currentLegIndex == 2 and record.advances == 1)

local corner = {{0,0,0},{40,0,0},{40,65,0},{80,65,0}}
record, sample = route(corner)
for y=28,18,-1 do sample(40,y,0) end
assert(record.advances == 0, "Reverse travel counted as a rejoin")
for y=18,28 do sample(40,y,24) end
assert(record.advances == 0, "Same XY on another floor counted as a rejoin")
record, sample = route({{0,0,0},{40,0,0},{40,65,32.5},{80,65,32.5}})
for y=25,32 do sample(40,y,y/2) end
assert(record.currentLegIndex == 2, "Rejoining a gradual slope used the elevation of the old corner")

-- Approaching a parallel lane around a compact U, or crossing its road
-- perpendicularly, does not skip the intervening turns.
record, sample = route({{0,0},{40,0},{40,15},{0,15},{0,40}})
for x=27,15,-1 do sample(x,15) end
assert(record.advances == 0, "Nearby return lane skipped a switchback")
record, sample = route(corner)
for x=31,49 do sample(x,22,0) end
assert(record.advances == 0, "Crossing the outgoing road counted as following it")

-- Never project past a required point, across a huge movement/observation
-- gap, or beyond the local search window to a distant near-parallel road.
record, sample = route({{0,0},{40,0},{40,10,required=true},{40,65},{80,65}})
for y=18,27 do sample(40,y) end
assert(record.currentLegIndex <= 2, "Rejoin bypassed a required stop")
record, sample = route({{0,0},{40,0},{40,130},{80,130}})
for y=75,90 do sample(40,y) end
assert(record.advances == 0, "Rejoin exceeded the along-road search window")
record, sample = route(corner)
sample(0,0,0); sample(40,22,0)
assert(record.advances == 0, "Relocation alone advanced the route")
sample(40,23,0); sample(40,24,0)
sample(40,27,0,2)
assert(record.advances == 0, "Stale sample confirmed an earlier movement")
sample(40,28,0)
for _=1,20 do sample(40,28,0) end
assert(record.advances == 0, "Stationary observations confirmed a rejoin")
for y=29,33 do sample(40,y,0,.2,now) end
assert(record.advances == 1, "Fresh forward movement after a pause failed to rejoin")
print("Bounded walking rejoin, branch and floor protection, suspension and stationary evidence passed")
