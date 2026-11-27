local f = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS, r, backend, routing = AzerothWaypointNS, f.runtime, f.backend, f.routing
local target, run = f.target, f.run
GetTime = function() return 200 end
local c, wx, wy, observedRide, carried = 1, 0, 0, nil, false
r.Compat.GetPlayerWorldPosition = function() return c, wx, wy end
r.Transit.Riding = function() return observedRide end
r.Transit.Carried = function() return carried end
local from = { c = 1, wx = 0, wy = 0, map = 1, name = "Departure" }
local to = { c = 2, wx = 700, wy = 800, map = 2, name = "Receiving dock" }
local transport = { kind = "zeppelin", a = from, b = to }
r.Nav.GetTravelData = function()
    return { transports = { transport, { kind = "zeppelin", a = from,
        b = { c = 2, wx = 20, wy = 100, map = 2, name = "Other dock" } } } }
end
local goal = target("Beyond the dock"); goal.mapID = 2
local record = run(goal, function()
    return { { kind = "zeppelin", from = from, to = to, transport = transport,
        label = "Board the zeppelin", rideLabel = "Riding to the receiving dock", ride = 65 } }
end)
local leg, generation = record.currentLeg, record._routeAcceptedPlanGeneration
assert(leg.polestarRide and leg.polestarRide.shared and routing.carrierState.mapID == 1)
wx = 75; NS.RecomputeCarrier()
assert(record.currentLeg == leg and routing.carrierState.mapID == 1, "Walking away from the dock was treated as boarding")
wx = 2; NS.RecomputeCarrier()
wx, carried = 80, true
observedRide = { kind = "zeppelin", dock = "Other dock", arriveIn = 44 }
NS.RecomputeCarrier()
assert(routing.carrierState.mapID == 1 and not backend.GetTransportStatus(record), "Wrong ride changed the carrier")
observedRide = { kind = "zeppelin", dock = "Receiving dock", arriveIn = 59 }
NS.RecomputeCarrier()
local title, deadline = backend.GetTransportStatus(record)
assert(title == "Riding to the receiving dock" and deadline == GetTime() + 59)
assert(routing.carrierState.mapID == 2 and routing.carrierState.title == title)
c, wx, wy = 2, 150, 200
NS.RecomputeCarrier()
assert(record.currentLeg == leg and record._routeAcceptedPlanGeneration == generation, "A map crossing skipped the receiving dock")
wx, wy = 700, 800
NS.RecomputeCarrier()
assert(record.currentLeg ~= leg and not backend.GetTransportStatus(record))
print("Polestar transport progress, carrier and arrival passed")
