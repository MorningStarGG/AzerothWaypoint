local node = { name = "Destination", nodeID = 123, x = .6, y = .7, slotIndex = 4 }
local leg = {
    kind = "taxi", mapID = 1, x = .1, y = .2, title = "Fly to Destination", dugiDestinationNPC = 999,
    taxi = { name = "Destination", destination = { mapID = 2, x = .4, y = .5 } },
}
local record = { legs = { leg }, currentLeg = leg, currentLegIndex = 1 }
local window = { mapID = 1, visible = { node }, visibleByID = { [123] = node } }
local frame, assist = {}, {}
local TaxiWindow = {}
function TaxiWindow.GetSnapshot(requestedFrame)
    assert(requestedFrame == frame)
    return window
end

AzerothWaypointNS = {
    State = {},
    Internal = { TaxiWindow = TaxiWindow },
    GetActiveAuthorityRecord = function() return record end,
    ProjectWaypointOntoMap = function(map, x, y, target)
        assert(map == 2 and x == .4 and y == .5 and target == 1)
        return .6, .7
    end,
}
assert(loadfile("bridge/flightmap_match.lua"))()

local match = TaxiWindow.ResolveRouteMatch(frame, assist)
assert(match and match.nodeID == 123 and match.confidence == "strong", "Destination projection did not match taxi node")
assert(not leg.taxi.nodeID and leg.mapID == 1 and leg.x == .1, "Matching modified route or treated NPC ID as node ID")

window.visible = { node, node }
assert(TaxiWindow.ResolveRouteMatch(frame, assist) == nil, "Ambiguous destination selected automatically")
window.visible = { node }
node.name = "Other"
assert(TaxiWindow.ResolveRouteMatch(frame, assist) == nil, "Mismatched destination name selected automatically")

leg.taxi.nodeID = 123
match = TaxiWindow.ResolveRouteMatch(frame, assist)
assert(match and match.confidence == "exact", "Existing exact-ID route matching regressed")
print("Dugi taxi matching: projected destination, numeric node identity and ambiguous/mismatched rejection passed")
