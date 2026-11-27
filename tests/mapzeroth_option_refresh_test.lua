local replaceMethod = dofile("tests/replace_method.lua")
local NativePath = dofile("tests/native_path.lua")
assert(loadfile("tests/mapzeroth_roads_test.lua"))()
local addon = MapzerothAddon
addon.DEFAULT_LOADING_SCREEN_TAX, addon.DEFAULT_REAGENT_SAVING, addon.RULESET = 5, 120, "forever"
MapzerothRebuildDB = { settings = { roadPreference = 5 } }
assert(loadfile(NativePath("forever", "Mapzeroth/Options.lua")))("Mapzeroth", addon)
local f = assert(loadfile("tests/route_planning_fixture.lua"))()("mapzeroth", true)
local NS = f.NS
local create = CreateFrame
CreateFrame = function(...)
    local frame = create(...)
    frame.RegisterUnitEvent = frame.RegisterEvent
    return frame
end
assert(loadfile("bridge/routing/walking.lua"))()
assert(loadfile("bridge/routing/walking_presentation.lua"))()
assert(loadfile("bridge/routing/backends/mapzeroth.lua"))()
local backend = NS.RoutingBackend_Mapzeroth
backend.Initialize()
local record = f.start(1, .9, .1, "Road preference")
f.drain()
assert(record.backend == "mapzeroth" and #record.legs > 2)
local stateFingerprint = record._routeBackendStateFingerprint
addon.Options:Set("askWaypointRoute", false)
f.drain(0); f.drain(.36)
assert(record._coreLastBackendValidationReason == nil, "Native waypoint offers should not invalidate an AWP plan")
addon.Options:Set("reagentSaving", 90)
f.drain(0); f.drain(.36)
assert(record._coreLastBackendValidationReason == "MAPZEROTH_OPTION_reagentSaving"
    and record._routeBackendStateFingerprint ~= stateFingerprint, "Native reagent threshold should validate the active plan")
local fingerprint = record.planFingerprint
addon.Options:Set("roadPreference", 1)
f.drain(0); f.drain(.36)
assert(record.planFingerprint ~= fingerprint and #record.legs == 1,
    "Native Walking routes change did not replace the active road geometry")
addon.Options:Set("roadPreference", 5)
f.drain(0); f.drain(.36)
assert(#record.legs > 2, "Changing back to roads did not restore geometry")
local previous = record.planFingerprint
f.combat = true
addon.Options:Set("roadPreference", 1)
f.drain(1)
assert(record.planFingerprint == previous, "Setting change replanned during combat")
f.combat = false
f.event("PLAYER_REGEN_ENABLED"); NS.FlushDeferredRouteBackendStateValidations(); f.drain(.36); f.drain(.36)
assert(#record.legs == 1, "Deferred road preference was lost after combat")

-- A projected graph endpoint can be a carrier before AWP's exact final
-- destination. It must not make acceptance skip newly inserted road legs.
addon.Options:Set("roadPreference", 1)
replaceMethod(addon.Journey,"PlanEntry",function()
    return { steps = { { method = "walk", path = {
        { mapID = 1, x = .1, y = .1 }, { mapID = 1, x = .9, y = .1 }, { mapID = 1, x = .9, y = .5 },
    } } } }
end)
record = f.start(1, .91, .51, "Exact off-graph destination")
f.drain(1)
NS.Internal.RouteProgress.EnsureLeg(record)
assert(record.currentLeg.routeLegKind == "carrier" and record.currentLeg.walking.to.anchor)
addon.Options:Set("roadPreference", 5)
f.drain(0); f.drain(.36)
NS.Internal.RouteProgress.EnsureLeg(record)
assert(record.currentLegIndex == 1 and record.currentLeg.fixedWalkingGeometry,
    "Route acceptance skipped the new road geometry by matching its old walking endpoint")

-- An ordinary route can be active when spirit is released. If there is no
-- walking path, hold a direct heading and recover the planner when alive.
local ghost, ghostPlans = false, 0
UnitIsGhost = function() return ghost end
local context, planEntry = addon.GetPlayerContext, addon.Journey.PlanEntry
addon.GetPlayerContext = function(self)
    local ctx = context(self)
    ctx.ghost, ctx.ghostSpeed = ghost, ghost and 8.2 or nil
    return ctx
end
replaceMethod(addon.Journey,"PlanEntry",function(self, session, entry)
    if ghost then ghostPlans = ghostPlans + 1; return nil end
    return planEntry(self, session, entry)
end)
f.behavior.zygor = "success"
record = f.start(1, .91, .51, "Life state changes")
f.drain(1)
assert(record.backend == "mapzeroth")
ghost = true
backend.OnLifeStateChanged()
backend.OnLifeStateChanged()
f.drain(1); f.drain(1)
assert(record.backend == "direct" and ghostPlans == 1, "Ghost fallback did not retain a direct heading")
ghost = false
backend.OnLifeStateChanged()
f.drain(1); f.drain(1)
assert(record.backend == "mapzeroth", "Resurrection did not recover Mapzeroth without a zone change")
addon.GetPlayerContext, addon.Journey.PlanEntry = context, planEntry

-- Use the installed Forever Mulgore roads and client-derived zone bounds,
-- not just the small synthetic graph, across a live option refresh.
local nativeData
assert(loadfile(NativePath("forever", "Polestar/Nav/TravelData.lua")))("Polestar", {
    Nav = { RegisterTravelData = function() end, RegisterCrossings = function(data) nativeData = data end },
})
local bounds = nativeData.zones[1412]
assert(loadfile(NativePath("forever", "Mapzeroth/Data/Forever/Roads.lua")))("Mapzeroth", addon)
addon.RoadNet:Reset()
addon.TravelGraph.WorldPosition = function(point)
    if point.world then return point.world.x, point.world.y, point.world.continent end
    return bounds.top + (bounds.bottom - bounds.top) * point.y,
        bounds.left + (bounds.right - bounds.left) * point.x, bounds.c
end
addon.Navigation.MapPoint = function(point, map)
    if map ~= 1412 then return end
    if point.mapID == map then return point.x, point.y end
    return (point.world.y - bounds.left) / (bounds.right - bounds.left),
        (point.world.x - bounds.top) / (bounds.bottom - bounds.top)
end
local from
addon.GetPlayerStart = function() return from end
addon.PlaceAt = function(_, map, x, y) return { id = "goal", mapID = map, x = x, y = y } end
replaceMethod(addon.Journey, "PlanEntry", function(_, session, entry)
    return { steps = { { method = "walk", path = { session.start, entry.dest } } } }
end)
f.map = 1412
local differences = 0
for _, pair in ipairs({ { .55, .43, .587, .813 }, { .466, .61, .60, .80 }, { .35, .25, .60, .65 } }) do
    from = { id = "player", mapID = 1412, x = pair[1], y = pair[2] }
    addon.Options:Set("roadPreference", 1)
    record = f.start(1412, pair[3], pair[4], "Mulgore preference")
    f.drain(1)
    local across = record.planFingerprint
    addon.Options:Set("roadPreference", 5)
    f.drain(0); f.drain(.36)
    if record.planFingerprint ~= across then differences = differences + 1 end
end
assert(differences > 0, "Mulgore native road preferences did not affect accepted geometry")
print("Native Mapzeroth Walking routes changes refresh accepted geometry and defer through combat")
