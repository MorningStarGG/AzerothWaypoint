local replaceMethod = dofile("tests/replace_method.lua")
local NativePath = dofile("tests/native_path.lua")
local fixture = assert(loadfile("tests/mapzeroth_backend_test.lua"))()
local NS, addon = AzerothWaypointNS, MapzerothAddon
local backend, private = fixture.backend, fixture.private
local nativeRoot = NativePath("forever", "Mapzeroth/")
local roadPreference = 5
local oldGet = addon.Options.Get
addon.Options.Get = function(self, key)
    if key == "roadPreference" then return roadPreference end
    return oldGet(self, key)
end
addon.TravelGraph.WorldPosition = function(point)
    if point.world then return point.world.x, point.world.y, point.world.continent end
    return point.x * 1000, point.y * 1000, 1
end
addon.Navigation = { MapPoint = function(point, map)
    if point.mapID == map then return point.x, point.y end
    if point.world and (map == 1 or map == 2) then return point.world.x / 1000, point.world.y / 1000 end
end }
assert(loadfile("tests/mapzeroth_navigation_fixture.lua"))()(addon)
addon.Cities = { city = { mapID = 2 } }
addon.RoadData = { [1] = { { 100, 100, 100, 300, 900, 300, 900, 100 } } }
addon.CityPaths = { [2] = { { .1, .1, .1, .3, .9, .3, .9, .1 } } }
assert(loadfile(nativeRoot .. "RoadNet.lua"))("Mapzeroth", addon)
local start = { id = "road_start", mapID = 1, x = .1, y = .1 }
local destination = { id = "road_end", mapID = 1, x = .9, y = .1 }
---@type (table|false)[]
local path = { start, destination }
local steps = { { method = "walk", fromID = start.id, nodeID = destination.id,
    text = "Walk to the objective", path = path } }
fixture.setSteps(steps)
local function plan()
    local ok, value = private.PlanRoute({ mapID = 1, x = .9, y = .1, title = "Objective" })
    assert(ok, value and value.code)
    return value
end
fixture.setCombat(false)
local result = plan()
local points = assert(result.steps[1].walking)
assert(#points >= 4 and points[1].required and points[#points].required)
assert(not points[2].required and points[2].wx and points[2].mapID == 1)
assert(not steps[1].walking and not steps[1].drawnPath, "Copying modified the native step")
local oldValue = points[2].x
points[2].x = 0
assert(plan().steps[1].walking[2].x == oldValue, "AWP retained mutable native geometry")
local highCount = #plan().steps[1].walking
local _, highFingerprint = private.SnapshotState()
roadPreference = 1
local low = plan()
assert(#low.steps[1].walking < highCount, "Native walking preference ignored")
local _, lowFingerprint = private.SnapshotState()
assert(lowFingerprint ~= highFingerprint, "Road preference missing from validation")
roadPreference = 5

local record = { backend = "mapzeroth", target = { mapID = 1, x = .9, y = .1, title = "Collect Journal" } }
backend.PlanRoute(record, 1, .9, .1, "Collect Journal")
local first, final = record.legs[1], record.legs[#record.legs]
assert(first.fixedWalkingGeometry and first.title == "Follow the road" and first.arrivalRadius <= 5)
assert(final.mapID == 1 and final.x == .9 and final.y == .1 and final.title == "Collect Journal")
assert(final.routeLegKind == "destination")
local count = backend.counters.expanded
for _ = 1, 5 do assert(private.SnapshotState()) end
assert(backend.counters.expanded == count, "Validation expanded roads")

-- City geometry uses the native city's streets, not roads on the ground above.
start.mapID, destination.mapID = 2, 2
local city = plan().steps[1].walking
assert(city and #city >= 4 and city[2].mapID == 2)
start.mapID, destination.mapID = 1, 1
local expand = addon.RoadNet.Expand
addon.RoadNet.Expand = function() error("fixture inaccessible geometry") end
assert(#plan().steps[1].walking == 2, "Failed refinement retained a partial road")
table.insert(steps[1].path, 2, { mapID = 1, x = .5, y = .1, id = "required_anchor" })
local original = plan().steps[1].walking
assert(#original == 3 and not original[2].required and original[2].anchor and original[2].id == "required_anchor", "Failed refinement lost native anchors")
table.remove(steps[1].path, 2)
replaceMethod(addon.RoadNet, "Expand", function(_, path)
    return { path[1], { world = { x = 1200, y = 0, continent = 1 } }, path[2] }
end)
assert(#plan().steps[1].walking == 2, "Out-of-bounds projection was joined across")
replaceMethod(addon.RoadNet, "Expand", function(_, path)
    return { path[1], { world = { x = 400, y = 400, continent = 2 } }, path[2] }
end)
assert(#plan().steps[1].walking == 2, "Different continents joined")
addon.RoadNet.Expand = expand
steps[1].path[2] = false
assert(not plan().steps[1].walking, "Malformed native path escaped refinement validation")
steps[1].path[2] = destination
local data = addon.RoadData
addon.RoadData = nil
assert(#plan().steps[1].walking == 2, "Missing roads lost the original walking path")
addon.RoadData = data
fixture.setCombat(true)
local combatRoute = plan()
assert(#combatRoute.steps[1].walking == highCount and combatRoute.stateFingerprint == NS.RouteSpecials.COMBAT_TRAVEL_STATE,
    "Combat route lost the selected road geometry")
fixture.setCombat(false)

print("Installed Mapzeroth roads: preferences, city paths, fixed legs, exact endpoints, failures and combat passed")
