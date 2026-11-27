local f = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS, r, backend = AzerothWaypointNS, f.runtime, f.backend
local from = { id = 12, c = 1, wx = 0, wy = 0, map = 1, name = "Flight master" }
local to = { id = 34, c = 2, wx = 500, wy = 600, map = 2, name = "Receiving flight master" }
local offer = { map = 1, node = from, reachable = { [to.id] = true } }
local frame, serial, snapshot, onTaxi = {}, 1, { mapID = 1, sourceNodeID = from.id, reachable = { { nodeID = to.id } } }, false
local onWindowChanged
NS.Internal.TaxiWindow = {
    GetOpenFrame = function() return frame end,
    GetOpenSerial = function() return serial end,
    GetSnapshot = function() return snapshot end,
    IsCurrentOffer = function(window, expected, map, source)
        return frame ~= nil and window == snapshot and expected == serial and map == snapshot.mapID and source == snapshot.sourceNodeID
    end,
    Subscribe = function(fn) onWindowChanged = fn end,
}
local c, x, y, height = 1, 0, 0, 10
local now, invalidations = GetTime(), 0
GetTime = function() return now end
NS.NoteRouteBackendInvalidated = function(backendID)
    assert(backendID == "polestar")
    invalidations = invalidations + 1
end
NS.GetPlayerMapPosition = function() return c, x / 1000, y / 1000 end
NS.GetWorldPositionFromMapCoords = function(map, mx, my) return map, mx * 1000, my * 1000 end
UnitOnTaxi = function() return onTaxi end
r.Compat.IsOnTaxi = UnitOnTaxi
r.Compat.GetPlayerUnitPosition = function() return x, y, height, c end
r.Compat.GetPlayerWorldPosition = function() return c, x, y end
r.Nav.travel.BoardingAt = function(_, _, _, z) if frame and z == 10 then return offer end end
local function plan(context)
    if context.liveTaxi then
        return { { kind = "fly", from = from, to = to, stops = { from, to }, taxiOffer = offer, label = "Fly" } }
    end
    return { { kind = "walk", from = from, to = context.target, label = "Continue without the offer", handmade = true } }
end
backend.frame = nil
backend.Initialize()
local goal = f.target("Offered connection"); goal.mapID = 2
local record = f.run(goal, plan, nil, true)
local leg = record.currentLeg
assert(leg.taxi.offerSerial == 1 and leg.taxi.nodeID == to.id)
serial = 2
onWindowChanged(frame)
f.fixture.drain()
assert(invalidations == 1, "A different current window did not invalidate the accepted offer")
backend.PlanRoute(record, goal.mapID, goal.x, goal.y, goal.title)
NS.RecomputeCarrier()
assert(record.currentLeg ~= leg and record.currentLeg.taxi.offerSerial == 2, "The accepted plan kept an expired window")

frame = nil
onWindowChanged()
now = now + 0.21
f.fixture.drain()
assert(invalidations == 2, "Closing without boarding did not invalidate the offer")
backend.PlanRoute(record, goal.mapID, goal.x, goal.y, goal.title)
NS.RecomputeCarrier()
assert(not record.currentLeg.taxi, "An unboarded flight survived closing the window")

frame, serial = {}, 3
record = f.run(goal, plan, nil, true)
leg = record.currentLeg
local generation = record._routeAcceptedPlanGeneration
frame = nil
onWindowChanged()
assert(invalidations == 2, "Closing cleared the offer before the boarding state could settle")
onTaxi = true
backend.StopNavigationProgress(record, generation, "taxi")
now = now + 0.21
f.fixture.drain()
assert(invalidations == 2 and record.currentLeg == leg and record._routeAcceptedPlanGeneration == generation,
    "Closing the window as a flight started replaced the accepted leg")
c, x, y, onTaxi = 2, to.wx, to.wy, false
assert(backend.PollNavigationLeg(record) and record.currentLeg ~= leg)
print("Polestar live flight offer, window replacement, close and boarding passed")
