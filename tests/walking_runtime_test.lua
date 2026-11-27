local replaceMethod = dofile("tests/replace_method.lua")
-- Real core monitor -> backend -> carrier -> projection -> TomTom lifecycle.
assert(loadfile("tests/mapzeroth_presentation_test.lua"))()
local NS = AzerothWaypointNS
local routing, backend = NS.State.routing, NS.RoutingBackend_Mapzeroth
local Queue, progress = NS.RouteQueueInternal, NS.Internal.RouteProgress
local x, y, now, combat, casting, equipment = 100, 100, 500, false, false, false
GetTime = function() return now end
InCombatLockdown = function() return combat end
NS.IsRouteEquipmentTransactionActive = function() return equipment end
NS.GetPlayerMapPosition = function() return 1, x / 1000, y / 1000 end
local projections = 0
NS.GetWorldPositionFromMapCoords = function(_, px, py) projections = projections + 1; return 1, px * 1000, py * 1000 end
NS.GetPlayerWaypointDistance = function(_, px, py) return math.sqrt((x - px * 1000)^2 + (y - py * 1000)^2) end
Queue.GetTimeSafe = GetTime
Queue.EnsureQueueState = function() return routing end
Queue.SameWaypointCoords = function(am, ax, ay, bm, bx, by) return am == bm and ax == bx and ay == by end
local queue = { id = "walking-runtime" }
NS.SyncAuthorityQueueProjection = function(record)
    routing.activeQueueProjection = Queue.BuildRouteProjection(queue, record)
    routing.activeQueueKey = queue.id
end
local adds, removes, arrow, pins = 0, 0, nil, {}
TomTom = { waypoints = {} }
function TomTom:GetKeyArgs(map, px, py, title) return NS.Signature(map, px, py) .. ":" .. tostring(title) end
function TomTom:AddWaypoint(map, px, py, opts)
    local key = self:GetKeyArgs(map, px, py, opts.title)
    self.waypoints[map] = self.waypoints[map] or {}
    local uid = self.waypoints[map][key]
    if uid then return uid end
    uid = { map, px, py, title = opts.title }
    for k, value in pairs(opts) do uid[k] = value end
    self.waypoints[map][key], pins[uid] = uid, true
    adds = adds + 1
    return uid
end
function TomTom:RemoveWaypoint(uid)
    for key, value in pairs(self.waypoints[uid[1]] or {}) do if value == uid then self.waypoints[uid[1]][key] = nil end end
    pins[uid] = nil; removes = removes + 1
end
function TomTom:SetCrazyArrow(uid) arrow = uid end
assert(loadfile("bridge/routing/carrier_tomtom.lua"))()
local function start()
    x, y = 100, 100
    local target = { mapID = 1, x = .9, y = .1, title = "Collect Journal", guideProvider = "rxp",
        semanticKind = "quest", semanticQuestID = 9, iconHintKind = "quest", iconHintQuestID = 9 }
    local record = {}
    for key, value in pairs(target) do record[key] = value end
    record.backend, record.type, record.authority, record.target = "mapzeroth", "guide", "guide", target
    routing.manualAuthority, routing.guideRouteState = nil, record
    backend.PlanRoute(record, 1, .9, .1, target.title)
    NS.RecomputeCarrier()
    return record
end
local function tick(delta)
    now = now + (delta or .21)
    routing.specialActionCasting = casting
    local frame = assert(progress.frame, "Shared progress monitor was never created")
    assert(frame.shown, "Active walking route left the shared monitor hidden")
    frame.scripts.OnUpdate(frame, delta or .21)
end
local function toward(a, b, distance)
    local dx, dy = b.wx - a.wx, b.wy - a.wy
    local length = math.sqrt(dx * dx + dy * dy)
    return a.wx + dx / length * distance, a.wy + dy / length * distance
end
local function assertPublished(record)
    local carrier = routing.carrierState.uid
    assert(pins[carrier] and arrow == carrier)
    assert(carrier[2] == record.currentLeg.x and carrier[3] == record.currentLeg.y)
    for index = 1, record.currentLegIndex - 1 do
        local leg = record.legs[index]
        for uid in pairs(pins) do
            assert(uid[2] ~= leg.x or uid[3] ~= leg.y, "Passed leg retained a live TomTom pin")
        end
    end
end
local record = start()
assert(backend.PollCurrentLeg == nil and type(backend.PollNavigationLeg) == "function")
local oldUID, oldIndex = routing.carrierState.uid, record.currentLegIndex
local from, to = record.currentLeg.walking.from, record.currentLeg.walking.to
local nextPoint = record.legs[oldIndex + 1].walking.to
local future = {}
for key, uid in pairs(routing.publishedQueueState.uidByEntryKey) do future[key] = uid end
local expanded = backend.counters.expanded
x, y = toward(to, from, 7); tick()
x, y = toward(to, nextPoint, 7); tick()
assert(record.currentLegIndex == oldIndex + 1, "Live movement did not invoke Mapzeroth passage handling")
assert(not pins[oldUID], "Advancement did not remove the previous carrier")
assertPublished(record)
for key, uid in pairs(routing.publishedQueueState.uidByEntryKey) do
    assert(uid == future[key], "Advancement rebuilt an unchanged future UID")
end
assert(backend.counters.expanded == expanded, "Movement expanded roads again")
tick() -- A newly active leg gets one observation even without more movement.
local beforeAdds, beforeRemoves, beforeProjections, beforeEvaluation = adds, removes, projections, progress.frame.evaluated
local equipmentSync = NS.SyncRouteEquipmentTransaction
local idleSyncs = 0
NS.SyncRouteEquipmentTransaction = function(...) idleSyncs = idleSyncs + 1; if equipmentSync then return equipmentSync(...) end end
for _ = 1, 100 do tick() end
assert(adds == beforeAdds and removes == beforeRemoves and projections == beforeProjections)
assert(progress.frame.evaluated == beforeEvaluation, "Idle monitor kept evaluating navigation")
assert(idleSyncs == 0, "Idle monitor kept resynchronizing an unchanged route leg")
NS.SyncRouteEquipmentTransaction = equipmentSync
for _ = 1, 100 do assert(NS.RequestRouteNavigationProgress(record, "fixture_data_ready")) end
tick()
assert(progress.frame.evaluated == beforeEvaluation + 1)
for _ = 1, 10 do tick() end
assert(progress.frame.evaluated == beforeEvaluation + 1, "Stationary wake was not consumed once")

-- A native graph anchor is geometry too, not an interaction requiring touch.
local native = MapzerothAddon.Journey.PlanEntry
MapzerothAddon.Journey.PlanEntry = function()
    return { steps = { { method = "walk", path = {
        { mapID = 1, x = .1, y = .1 }, { mapID = 1, x = .1, y = .3, id = "graph_anchor" },
        { mapID = 1, x = .9, y = .3 },
    } } } }
end
local roads = MapzerothAddon.RoadData; MapzerothAddon.RoadData = nil
record = start()
assert(record.currentLeg.walking.to.id == "graph_anchor" and not record.currentLeg.walking.required)
from, to = record.currentLeg.walking.from, record.currentLeg.walking.to
nextPoint = record.legs[record.currentLegIndex + 1].walking.to
x, y = toward(to, from, 7); tick()
x, y = toward(to, nextPoint, 7); tick()
assert(record.currentLegIndex == 2, "Original graph anchor still required exact arrival")

record = start()
from, to = record.currentLeg.walking.from, record.currentLeg.walking.to
nextPoint = record.legs[record.currentLegIndex + 1].walking.to
x, y = toward(to, from, 10); tick()
local idleEvaluations = progress.frame.evaluated
for _ = 1, 25 do tick() end
assert(progress.frame.evaluated == idleEvaluations, "Paused approach reran geometry")
x, y = toward(to, nextPoint, 8); tick()
assert(record.currentLegIndex == 2, "Observed stationary pause made the next movement stale")

for _, gap in ipairs({ 2, .21 }) do
    record = start()
    from, to = record.currentLeg.walking.from, record.currentLeg.walking.to
    nextPoint = record.legs[record.currentLegIndex + 1].walking.to
    x, y = toward(to, from, 10); tick()
    x, y = toward(to, nextPoint, gap == 2 and 8 or 60); tick(gap)
    assert(record.currentLegIndex == 1, "Stale/discontinuous motion advanced an ordinary anchor")
end

local read = NS.GetPlayerMapPosition
record = start()
from, to = record.currentLeg.walking.from, record.currentLeg.walking.to
nextPoint = record.legs[record.currentLegIndex + 1].walking.to
x, y = toward(to, from, 7); tick()
replaceMethod(NS, "GetPlayerMapPosition", function() error("fixture unreadable position") end)
tick()
NS.GetPlayerMapPosition = read
x, y = toward(to, nextPoint, 7); tick()
assert(record.currentLegIndex == 1, "Unreadable sample did not break passage history")
MapzerothAddon.Journey.PlanEntry, MapzerothAddon.RoadData = native, roads

-- Blocking states discard passage history, then rearm on the same position.
for _, block in ipairs({ "combat", "cast", "equipment", "loading" }) do
    record = start()
    local first = record.currentLegIndex
    from, to = record.currentLeg.walking.from, record.currentLeg.walking.to
    nextPoint = record.legs[first + 1].walking.to
    x, y = toward(to, from, 7); tick()
    if block == "combat" then combat = true
    elseif block == "cast" then casting = true
    elseif block == "equipment" then equipment = true
    else progress.frame.scripts.OnEvent(progress.frame, "LOADING_SCREEN_ENABLED") end
    x, y = toward(to, nextPoint, 7); tick()
    assert(record.currentLegIndex == first)
    combat, casting, equipment = false, false, false
    if block == "loading" then progress.frame.scripts.OnEvent(progress.frame, "LOADING_SCREEN_DISABLED") end
    tick()
    assert(record.currentLegIndex == first, "Suspended movement synthesized a pass")
end
local stale = record
record = start()
local before = record.currentLegIndex
assert(not NS.RequestRouteNavigationProgress(stale, "stale"))
tick()
assert(record.currentLegIndex == before, "Old record affected replacement route")
local enabled = NS.IsRoutingEnabled
NS.IsRoutingEnabled = function() return false end
tick()
assert(not progress.frame.shown)
NS.IsRoutingEnabled = enabled
NS.RecomputeCarrier()
tick()
assert(progress.frame.shown and record.currentLegIndex == before, "Routing toggle did not safely rearm progression")
routing.guideRouteState = nil
NS.RecomputeCarrier()
assert(not progress.frame.shown and not progress.frame.record)
assert(next(pins) == nil, "Clearing left carrier or future pins")
print("Live shared walking: movement, ordinary anchors, arrow/marker, pin lifecycle, idle/wake, suspension and replacement passed")

return { NS = NS, routing = routing, backend = backend, start = start, tick = tick,
    setPosition = function(px, py) x, y = px, py end,
    counts = function() return adds, removes, progress.frame.evaluated end,
    assertPublished = assertPublished, setCombat = function(value) combat = value end }
