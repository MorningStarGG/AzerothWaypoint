local f = assert(loadfile("tests/polestar_integration_test.lua"))()
local NS, r, backend = AzerothWaypointNS, f.runtime, f.backend
---@alias MeasurementTestCost fun(c: number, x: number, y: number, start?: boolean, z?: number): number|boolean|nil, number|nil, boolean|nil
---@type {walkCost?: MeasurementTestCost}|nil
local context
local requests, callbacks = 0, {}
NS.ScheduleActiveRouteRefresh = function() end
local policy = 2
local secret = {}
local secretChecks = false
issecretvalue = function(value) return secretChecks and value == secret end
r.Compat.GetPlayerWorldPosition = function() return 1, 0, 0 end
r.Compat.GetPlayerUnitPosition = function() return nil end
r.Nav.walk.Floor = function() return 20 end
r.Nav.danger = { Level = function() return 10 end, ZoneAt = function() return 1 end,
    Table = function() return { [2] = policy } end }
local origins = {
    { wx = 0, wy = 0, z = 20, start = true }, { wx = 100, wy = 0, z = 100 },
    { wx = 200, wy = 0 }, { wx = 300, wy = 0 }, { wx = 400, wy = 0 },
    { wx = 500, wy = 0 }, { wx = 600, wy = 0 }, { wx = 700, wy = 0 }, { wx = 800, wy = 0 },
}
r.Nav.PlanRoute = function(value)
    context = value
    for i, point in ipairs(origins) do value.places[i] = point end
    return {{ kind = "walk", from = { c = 1, wx = 0, wy = 0, z = 20, map = 1 }, to = value.target }}
end
Polestar_NavEngine.FindMany = function(_, _, points, done)
    requests = requests + 1
    callbacks[#callbacks + 1] = { points = points, done = done }
    return {}
end
local function plan(record, x)
    NS.record = record
    backend.PlanRoute(record, 1, x or .85, .85, "Measured destination")
end
local function current() return assert(context, "Native planner context was not captured") end
local function prices() return assert(current().walkCost, "Completed measurements were not supplied to the planner") end
local record = { navigationHeight = 0, navigationContinent = 1 }
plan(record)
local batch = callbacks[#callbacks]
local costs, yards = {}, {}
for i, point in ipairs(batch.points) do
    if point.x == 0 then costs[i], yards[i] = 12, 84
    elseif point.x == 100 then costs[i] = false
    elseif point.x == 300 then costs[i], yards[i] = 0, 0
    elseif point.x == 400 then costs[i] = 0 / 0
    elseif point.x == 500 then costs[i] = -1
    elseif point.x == 600 then costs[i] = math.huge
    elseif point.x == 700 then costs[i] = "invalid"
    elseif point.x == 800 then costs[i] = secret end
end
secretChecks = true
batch.done(costs, nil, { yards = yards, walkChecked = true, capped = true })
secretChecks = false
plan(record)
local lookup = prices()
assert(lookup(1, 200, 0, nil, nil) == nil, "An unmeasured origin became a verified refusal")
assert(lookup(1, 100, 0, nil, 100) == false, "An explicit refusal lost its meaning")
local cost, distance, checked = lookup(1, 0, 0, true, 20)
assert(cost == 12 and distance == 84 and checked, "Verified measurement metadata changed")
cost, distance = lookup(1, 300, 0, nil, nil)
assert(cost == 0 and distance == 0, "Zero cost/distance was treated as missing")
for _, x in ipairs({400, 500, 600, 700, 800}) do
    assert(lookup(1, x, 0, nil, nil) == nil, "Malformed cost entered the planner")
end
assert(lookup(1, 0, 0, true, 100) == nil, "Measurement escaped its origin floor")
costs[1], yards[1] = 999, 999
for _ = 1, 20 do plan(record) end
assert(requests == 1, "Completed unknown origins were searched repeatedly")
assert(prices()(1, 0, 0, true, 20) == 12, "Native result mutation changed the cached answer")

-- Policy changes invalidate even when the destination and all origins match.
policy = 3
plan(record)
assert(requests == 2 and current().walkCost == nil, "Changed danger policy reused old prices")
callbacks[#callbacks].done({}, nil, { unjoined = true, walkChecked = true })
plan(record)
assert(requests == 2 and prices()(1, 100, 0, nil, 100) == nil,
    "Completed unjoined batch was retried or turned into refusal")

origins[#origins + 1] = { wx = 150, wy = 0, z = 0 }
plan(record)
assert(requests == 3, "A newly requested origin was incorrectly covered")
local late = callbacks[#callbacks]
record.navigationHeight = 100
plan(record)
assert(requests == 4 and current().walkCost == nil, "Changed target floor reused old measurements")
local stale = backend.counters.stale
late.done({1}, nil, {walkChecked = true})
assert(backend.counters.stale == stale + 1, "Superseded measurement was accepted")
backend.Clear(record)
callbacks[#callbacks].done({}, nil, {capped = true})
assert(backend.counters.stale == stale + 2, "Cleared owner accepted a late batch")

record = {}; plan(record, .8)
local abandoned = callbacks[#callbacks]
local before = requests
record = {}; plan(record, .8)
assert(requests == before + 1, "Equal coordinates coalesced searches belonging to different route owners")
stale = backend.counters.stale
abandoned.done({}, nil, {walkChecked = true})
assert(backend.counters.stale == stale + 1, "Replaced owner published an equal-coordinate batch")
callbacks[#callbacks].done(nil, nil, {walkChecked = true})
plan(record, .8)
assert(prices()(1, 100, 0, nil, 100) == nil, "Malformed batch became an explicit refusal")
before = requests
backend.frame.event(nil, "ADDON_LOADED", "Polestar_Nav_EK")
plan(record, .8)
assert(requests == before + 1 and current().walkCost == nil,
    "New terrain data reused a completed unknown measurement")
callbacks[#callbacks].done({}, nil, {unjoined = true})

-- The existing cache remains bounded, including completed unknown batches.
for i = 1, 5 do
    record = {}; plan(record, .7 + i / 100)
    callbacks[#callbacks].done({}, nil, {capped = true})
end
local count = requests
record = {}; plan(record, .71)
assert(requests == count + 1, "Measurement cache exceeded its four-entry bound")
print("Polestar sparse measurements, verified refusals, policy/floor/origin invalidation and bounded reuse passed")
