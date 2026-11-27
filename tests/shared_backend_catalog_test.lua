local forever, available, initialized, cleared = false, {}, {}, {}
local db = { routingBackend = "dugi" }
local NS = { Internal = {}, State = { routing = {} },
    IsWoWForever = function() return forever end,
    GetZygorAddonName = function() return forever and "ZygorGuidesViewerForever" or "ZygorGuidesViewer" end,
    GetDB = function() return db end,
    SafeCall = function(fn, ...) return fn(...) end,
}
_G.AzerothWaypointNS = NS
_G.CreateFrame = function() return { RegisterEvent=function() end, SetScript=function() end } end
assert(loadfile("core/routing_backends.lua"))()
local C = NS.Internal.RoutingBackends
local expected = { "zygor", "farstrider", "mapzeroth", "polestar", "dugi", "questierouter", "direct" }
for i, entry in ipairs(C.entries) do
    assert(entry.id == expected[i], "Fallback order changed")
    local id = entry.id
    NS[entry.objectKey] = { id = id, IsAvailable = function() return available[id] == true end,
        Initialize = function() initialized[#initialized + 1] = id end,
        Clear = function(record) cleared[#cleared + 1] = record end }
end
assert(loadfile("bridge/routing/shared.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("bridge/routing/core.lua"))()
assert(loadfile("bridge/routing/validation.lua"))()
assert(loadfile("bridge/routing/progress.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("bridge/routing/planning.lua"))()
NS.InitializeRoutingCore()
assert(table.concat(initialized, ",") == "direct,zygor,mapzeroth,farstrider,polestar,dugi,questierouter", "Initialization order changed")
for _, id in ipairs(expected) do available[id] = true end
assert(NS.GetEffectiveBackendID() == "dugi", "Saved backend was ignored")
available.dugi = false
assert(NS.GetEffectiveBackendID() == "zygor", "Fallback priority changed")
available.zygor, available.farstrider, available.mapzeroth = false, false, false
assert(NS.GetEffectiveBackendID() == "direct", "Retail selected Forever-only backend")
forever = true; assert(NS.GetEffectiveBackendID() == "polestar")
assert(C.GetAddons(C.byID.zygor)[1] == "ZygorGuidesViewerForever")
assert(C.Usage() == "direct|zygor|mapzeroth|farstrider|dugi|polestar|questierouter")
assert(NS.GetInitialRoutingBackendID(function(name) return name == "DugisGuideViewerZ" end) == "dugi")
assert(NS.GetInitialRoutingBackendID(function(name) return name == "FarstriderLib" end) == "direct",
    "Missing data dependency passed initial selection")
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
assert(loadfile("bridge/routing/authority.lua"))()
NS.SyncGuideVisualState, NS.RecomputeCarrier, NS.PersistManualAuthority = function() end, function() end, function() end
local guide, manual = {backend="dugi"}, {backend="dugi"}
NS.State.routing.guideRouteStates = { dugi = guide }
NS.State.routing.activeGuideProvider = "dugi"
NS.State.routing.manualAuthority = manual
NS.ClearGuideRouteState("dugi"); NS.ClearManualAuthority()
assert(cleared[1] == guide and cleared[2] == manual, "Guide/manual teardown omitted Dugi backend")
print("Backend catalog priority, dependencies, initialization, flavor and teardown passed")
