local f = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS, r, backend = AzerothWaypointNS, f.runtime, f.backend
local now, px, py, pz, combat = 1000, 0, 0, 0, false
---@type number|nil
local zone = 1437
---@type number|nil
local undercity
local requests = {}
local synchronous, classificationCombat = false, false
GetTime = function() return now end
InCombatLockdown = function() return combat end
NS.GetPlayerWaypointDistance = function(_, x, y) return math.sqrt((px - x * 1000)^2 + (py - y * 1000)^2) end
r.Compat.GetPlayerWorldPosition = function() return 1, px, py end
r.Compat.GetPlayerUnitPosition = function() return px, py, pz, 1 end
r.Compat.MapToWorld = function(_, x, y) return 1, x * 10, y * 10 end
r.Compat.WorldToMap = function(_, x, y, map)
    if map == 1458 and zone == 1420 then
        if undercity == nil then return nil end
        return undercity, undercity
    end
    return x / 10, y / 10
end
r.Nav.travel.ZoneOf = function()
    if classificationCombat then combat = true end
    return zone
end
Polestar_NavEngine.FindMany = nil
Polestar_NavEngine.Cancel = function(job) job.cancelled = true end
Polestar_NavEngine.Find = function(_, from, to, done, options)
    assert(not combat, "Approach search started in combat")
    local request = { from = from, to = to, done = done, options = options, job = {} }
    requests[#requests + 1] = request
    if synchronous then
        if to.z ~= nil then done(nil, "no safe walking route", {})
        else done({{x = from.x, y = from.y, z = 0}, {x = to.x, y = to.y, z = 0}}, nil, {walkChecked = true}) end
    end
    return request.job
end
local function planner(context)
    return {{kind = "walk", from = {c = 1, wx = px, wy = py, z = pz, map = 1}, to = context.target}}
end
local function plan(map, height)
    px, py, pz = 0, 0, 0
    local goal = f.target("Exact ledge destination")
    goal.mapID, goal.x, goal.y = map or 1, .5, .1
    goal.navigationHeight, goal.navigationContinent = height, 1
    local record = f.run(goal, planner, nil, true)
    backend.PollNavigationLeg(record)
    return record, requests[#requests]
end
local function refuse(request, blocked)
    request.done(nil, "no safe walking route", blocked and {blockedReason = "policy"} or {})
end
local function finish(request)
    request.done({{x = request.from.x, y = request.from.y, z = 0}, {x = request.to.x, y = request.to.y, z = 0}},
        nil, {walkChecked = true})
end

local record, strict = plan(1, 100)
local original, count = record.currentLeg, #requests
assert(strict.to.z == 100 and strict.to.reach == 10)
refuse(strict)
assert(#requests == count + 1, "Strict failure did not start an immediate approach search")
local relaxed = requests[#requests]
assert(relaxed.to.z == nil and relaxed.to.reach == nil and relaxed.job.urgent,
    "Retry retained a height constraint or lost per-job urgency")
assert(strict.to.z == 100 and original.polestarTo.z == 100 and record.navigationHeight == 100,
    "Retry mutated the authored endpoint")
local stale = backend.counters.stale
finish(strict)
assert(backend.counters.stale == stale + 1 and record.currentLeg == original,
    "Old strict callback displaced the pending approach")
finish(relaxed); f.fixture.drain()
assert(record._fixtureResult.status == "success" and record.backend == "polestar")
assert(#record.legs == 2 and record.legs[1].routeLegKind == "carrier"
    and record.legs[1].polestarTo.z == 0, "Approach lost its actual mapped endpoint")
local final = record.legs[2]
assert(final.routeLegKind == "destination" and final.x == .5 and final.y == .1 and final.polestarTo.z == 100,
    "Approach replaced the exact final destination/floor")
assert(final.polestarApproach and not final.polestarPath and not final.walking
    and record.legs[1].polestarKind == "walk" and final.polestarKind == "walk",
    "Unmapped vertical gap became a path or elevator")
assert(backend.GetNavigationStatus(record) == "partial")
px, py = 500, 100
assert(backend.CanAdvanceLeg(record, record.legs[1]) ~= false, "Mapped approach retained the authored goal's floor gate")
record.currentLegIndex, record.currentLeg = 2, final
assert(backend.GetNavigationStatus(record) == "partial", "Final gap lost its qualification")
assert(backend.CanAdvanceLeg(record, final) == false, "Unmapped final destination arrived on the wrong floor")
count = #requests
for _ = 1, 40 do now = now + 1; backend.PollNavigationLeg(record) end
backend.frame.event(nil, "ADDON_LOADED", "Polestar_Options")
backend.PlanRoute(record, 1, .5, .1, record.title)
backend.PollNavigationLeg(record)
assert(#requests == count and record.currentLeg == final, "Unchanged final gap restarted its terrain search")
f.fixture.settings["nav.routeStyle"] = "balanced"
backend.PlanRoute(record, 1, .5, .1, record.title)
backend.PollNavigationLeg(record)
assert(#requests == count + 1 and requests[#requests].to.z == 100,
    "Changed walking policy did not recheck the unmapped tail at its real height")
refuse(requests[#requests]); finish(requests[#requests]); f.fixture.drain()
final = record.legs[#record.legs]
count = #requests
backend.PlanRoute(record, 1, .5, .1, record.title); backend.PollNavigationLeg(record)
assert(#requests == count and final.polestarApproach,
    "Policy recheck lost the canonical itinerary and restarted the accepted approach")
backend.frame.event(nil, "ADDON_LOADED", "Polestar_Nav_EK")
backend.PlanRoute(record, 1, .5, .1, record.title); backend.PollNavigationLeg(record)
assert(#requests == count + 1, "New terrain data did not recheck an unmapped final gap")
refuse(requests[#requests]); finish(requests[#requests]); f.fixture.drain()
final = record.legs[#record.legs]
pz = 100
assert(backend.CanAdvanceLeg(record, final) ~= false, "Exact destination never accepted its real floor")
f.fixture.settings["nav.routeStyle"] = "roads"

-- The stationary retry is replaced by the immediate approach, not added to it.
record, strict = plan(1, 0)
count = #requests
refuse(strict); assert(#requests == count + 1, "Zero target height did not qualify")
refuse(requests[#requests])
now = now + 3; backend.PollNavigationLeg(record)
assert(#requests == count + 1, "Failed pair repeated as a stationary quick retry")
now = now + 16; backend.PollNavigationLeg(record)
assert(#requests == count + 1, "Failed pair retried without movement")
px = 6; backend.PollNavigationLeg(record)
assert(#requests == count + 2, "Moved failure lost the existing backoff retry")

-- Capitals retain their floors, including points using another map frame.
for _, map in ipairs({1453, 1454, 1455, 1456, 1457, 1458}) do
    record, strict = plan(map, 100); count = #requests; refuse(strict)
    assert(#requests == count, "A capital map allowed a heightless retry")
end
zone = 1455
record, strict = plan(1, 100); count = #requests; refuse(strict)
assert(#requests == count, "A capital expressed through another map lost its floor")
zone, undercity = 1420, 50
record, strict = plan(1, 100); count = #requests; refuse(strict)
assert(#requests == count, "Undercity was mistaken for outdoor Tirisfal")
undercity = nil
record, strict = plan(1, 100); count = #requests; refuse(strict)
assert(#requests == count, "Missing Undercity projection authorized a retry")
undercity = 150
record, strict = plan(1, 100); count = #requests; refuse(strict)
assert(#requests == count + 1, "Outdoor Tirisfal was treated as Undercity")
zone = nil
record, strict = plan(1, 100); count = #requests; refuse(strict)
assert(#requests == count, "Unknown zone classification authorized a retry")
zone = 1437
record, strict = plan(1, 100); count = #requests; refuse(strict, true)
assert(#requests == count, "Policy refusal was retried without its floor")
record, strict = plan(1, nil); count = #requests; refuse(strict)
assert(#requests == count, "Heightless target received another immediate search")
now = now + 3; backend.PollNavigationLeg(record)
assert(#requests == count + 1, "Ordinary heightless failure lost its bounded quick retry")

-- A known strict path can fail to refine without being replaced by an approach.
record, strict = plan(1, 100)
strict.done({{x = 0, y = 0, z = 0}, {x = 500, y = 100, z = 100}}, nil, {walkChecked = true})
f.fixture.drain()
local verified = record.legs
px, py = 0, 500; now = now + 20
backend.PollNavigationLeg(record); strict = requests[#requests]; count = #requests
refuse(strict)
assert(#requests == count and record.legs == verified, "A failed refinement replaced verified geometry with an approach")

-- Ownership/combat gates apply independently at both stages.
record, strict = plan(1, 100); count = #requests
combat = true; refuse(strict)
assert(#requests == count and record.currentLeg.polestarPath == nil, "Combat allowed the second stage")
combat = false; backend.PollNavigationLeg(record)
assert(#requests == count + 1 and requests[#requests].to.z == 100, "Post-combat retry did not restart safely")
refuse(requests[#requests]); relaxed = requests[#requests]
combat = true; finish(relaxed)
assert(record.currentLeg.polestarPath == nil, "Approach was installed during combat")
combat = false
record, strict = plan(1, 100); count = #requests
classificationCombat = true
refuse(strict)
assert(#requests == count, "Combat between classification and retry start was ignored")
combat = false
classificationCombat = false
record, strict = plan(1, 100); refuse(strict); relaxed = requests[#requests]
backend.Clear(record)
assert(relaxed.job.cancelled, "Clearing the route did not cancel its second stage")
finish(relaxed)
assert(record.legs == nil, "Late approach resurrected a cleared route")
record, strict = plan(1, 100); refuse(strict); relaxed = requests[#requests]
local newer = plan(1, 200)
finish(relaxed)
assert(newer.currentLeg.polestarTo.z == 200 and not newer.currentLeg.polestarPath,
    "Old-height approach replaced a new destination")

-- Approaching a transport never relaxes its actual boarding-floor gate or
-- discards the rest of the itinerary.
px, py, pz = 0, 0, 0
local goal = f.target("Destination beyond flight")
goal.x, goal.y = .5, .1
record = f.run(goal, function(context)
    local dock = {c = 1, wx = 200, wy = 100, z = 100, map = 1}
    return {{kind = "walk", from = {c = 1, wx = 0, wy = 0, z = 0, map = 1}, to = dock},
        {kind = "fly", from = dock, to = context.target, stops = {{id = 123}}}}
end, nil, true)
backend.PollNavigationLeg(record); refuse(requests[#requests]); finish(requests[#requests]); f.fixture.drain()
assert(#record.legs == 4 and record.legs[2].routeLegKind == "carrier" and record.legs[2].polestarTo.z == 100
    and record.legs[3].polestarKind == "fly" and record.legs[4].routeLegKind == "destination",
    "Transport approach changed its role, boarding floor or remaining itinerary")
assert(backend.CanAdvanceLeg(record, record.legs[2]) == false, "Unmapped approach authorized boarding on another floor")

synchronous = true
record = plan(1, 100); f.fixture.drain()
assert(record.legs[#record.legs].polestarApproach, "Synchronous two-stage result was lost")
px, py = 500, 100
assert(backend.CanAdvanceLeg(record, record.legs[1]) ~= false, "Synchronous retry retained a phantom pending job")
print("Polestar bounded height approaches, capital/floor protection, final gaps and two-stage cancellation passed")

local owner = {backend="questierouter"}
local wakes, validations = 0, 0
NS.GetActiveAuthorityRecord = function() return owner end
NS.RequestRouteNavigationProgress = function(current)
    assert(owner == current and current.backend == "polestar", "Polestar woke another backend's route")
    wakes = wakes + 1
end
backend.OnPlanInvalidated = function() validations = validations + 1 end
backend.frame.event(nil, "ADDON_LOADED", "Polestar_Options")
assert(validations == 0)
backend.frame.event(nil, "ADDON_LOADED", "Polestar_Nav_EK")
backend.frame.event(nil, "PLAYER_REGEN_ENABLED")
assert(wakes == 0 and validations == 1, "Navigation data must still signal preferred planner recovery")
owner.backend = "polestar"
backend.frame.event(nil, "ADDON_LOADED", "Polestar_Nav_Kalimdor")
backend.frame.event(nil, "PLAYER_REGEN_ENABLED")
assert(wakes == 2 and validations == 2)
