-- Passed route legs may remain in route history, but must never be published
-- again as TomTom pins after their carrier has advanced.
local NS = { State = { routing = {} }, Internal = {}, RouteQueueInternal = {} }
AzerothWaypointNS = NS
local routing, Queue = NS.State.routing, NS.RouteQueueInternal
GetTime = function() return 100 end
Queue.GetTimeSafe = GetTime
Queue.TrimString = function(v) return v end
Queue.EnsureQueueState = function() return routing end
Queue.SameWaypointCoords = function(am, ax, ay, bm, bx, by) return am == bm and ax == bx and ay == by end
NS.Signature = function(map, x, y) return map .. ":" .. x .. ":" .. y end
local pins, adds, removes = {}, 0, 0
TomTom = {
    AddWaypoint = function(_, map, x, y, opts)
        adds = adds + 1
        local uid = { map = map, x = x, y = y, opts = opts, title = opts.title }
        pins[uid] = true
        return uid
    end,
    RemoveWaypoint = function(_, uid) pins[uid] = nil; removes = removes + 1 end,
}
assert(loadfile("bridge/routing/queues/projection.lua"))()
assert(loadfile("bridge/routing/carrier_tomtom.lua"))()
local record = { mapID = 1, x = .8, y = .8, title = "Final", currentLegIndex = 1, legs = {} }
for i = 1, 4 do
    record.legs[i] = { mapID = 1, x = i * .2, y = i * .2, title = "Leg " .. i,
        routeLegKind = i == 4 and "destination" or "carrier", kind = "movement" }
end
local queue = { id = "fixture" }
local function publish(index)
    record.currentLegIndex = index
    routing.activeQueueProjection = Queue.BuildRouteProjection(queue, record)
    routing.activeQueueKey = queue.id
    assert(NS.PublishQueueProjectionPins())
    local count = 0
    for uid in pairs(pins) do
        count = count + 1
        assert(uid.x > record.legs[index].x, "A passed/head leg was republished as a map/minimap pin")
    end
    assert(count == 4 - index, "Future route pin disappeared")
    assert(#routing.activeQueueProjection.entries == 4, "Pin cleanup destroyed route history")
end
publish(1)
local firstPins = {}
for uid in pairs(pins) do firstPins[uid.x] = uid end
publish(2)
assert(pins[firstPins[3 * .2]] and pins[firstPins[.8]], "Advancement rebuilt unchanged future pins")
assert(routing.activeQueueProjection.entries[1].isPassed, "Passed leg lost its projection state")
local beforeAdds, beforeRemoves = adds, removes
assert(NS.PublishQueueProjectionPins())
assert(adds == beforeAdds and removes == beforeRemoves, "Unchanged pin projection churned TomTom waypoints")
publish(3)

-- Persistent destination queues apply the same filter to their travel legs,
-- while preserving the other top-level queued destinations.
queue.items = { { mapID = 1, x = .8, y = .8, title = "Final" }, { mapID = 2, x = .5, y = .5, title = "Next destination" } }
queue.activeItemIndex = 1
local projection = Queue.BuildDestinationQueueProjection(queue, record)
assert(#projection.publishedEntries == 2, "Destination queue retained passed legs or lost a future destination")
assert(projection.publishedEntries[1].mapID == 1 and projection.publishedEntries[1].x == .8)
assert(projection.publishedEntries[2].mapID == 2, "Top-level queued destination was removed")
routing.activeQueueProjection = projection
NS.PublishQueueProjectionPins()
assert(removes > 0, "Old projection UIDs were never removed")
print("Passed route pin removal, future pins, stable publication and destination queue projection passed")
