local make = assert(loadfile("tests/route_planning_fixture.lua"))()
local function noop() end

local planners = {
    zygor = function()
        local rover = {
            QueueFindPath = noop,
            startup_thread = coroutine.create(noop),
            StopStartup = function(self) self.startup_thread = nil end,
        }
        _G.ZygorGuidesViewer = { LibRover = rover, db = { profile = { pathfinding = true } } }
        return function(success)
            -- The upstream post-hook runs before StartupStep sets ready.
            rover:StopStartup()
            rover.ready = success
        end
    end,
    dugi = function(forever)
        local dugi = {
            UpdateIconStatus = noop,
            SetSmartWaypoint = noop, GetCreateTable = noop, tPool = noop,
            AddRouteWaypoint = noop, UserSetting = noop, UiMapId2Floor = noop,
            GetPlayerMapPositionDisruptive = noop, UnpackXY = noop,
            Modules = {
                Taxi = { GetBestRoute = noop, RouteBuilders = { Character = { AddWaypoint = noop } } },
                TaxiData = { GetFullData = noop },
            },
        }
        _G.DugisGuideViewer = dugi
        _G.LuaUtils = {}
        local loadingState = forever and dugi or LuaUtils
        loadingState.DugiGuidesIsLoading = true
        assert(loadfile("core/service_search.lua"))()
        assert(loadfile("integrations/guides/dugi/dugi_provider.lua"))()
        return function(success)
            if not success then dugi.Modules.TaxiData.GetFullData = nil end
            loadingState.DugiGuidesIsLoading = false
            dugi:UpdateIconStatus()
        end
    end,
    mapzeroth = function()
        local world = {
            GetNode = noop, LivePhases = noop,
            Build = function(self) self.generation = (self.generation or 0) + 1 end,
        }
        _G.MapzerothAddon = {
            GetPlayerStart = noop, PlaceAt = noop, GetPlayerContext = noop,
            GetKnownTeleports = noop, GetFlightSpeedMultiplier = noop, MeetsRequirements = noop,
            Journey = { Build = noop, PlanEntry = noop }, World = world, TravelGraph = { Build = noop },
        }
        assert(loadfile("tests/mapzeroth_navigation_fixture.lua"))()(MapzerothAddon)
        return function() world:Build() end
    end,
    farstrider = function(_, onRegister)
        local callback
        local graph = {
            allNodes = {},
        }
        _G.FarstriderLib_API = { FindTrailTo = noop, RegisterRebuildCallback = function(fn)
            onRegister()
            callback = fn
        end }
        _G.FarstriderLib = { Pathfinding = graph }
        return function(success)
            if success then graph.allNodes.start = { edges = {} } end
            callback()
        end
    end,
}

local function fixture(id, forever, mode)
    local f = make(id, forever)
    local NS, catalog = f.NS, f.NS.Internal.RoutingBackends
    local hookCount = 0
    local zygorName = forever and "ZygorGuidesViewerForever" or "ZygorGuidesViewer"
    NS.GetZygorAddonName = function() return zygorName end
    local dependencies = catalog.GetAddons(catalog.byID[id])
    local loaded = {}
    for _, name in ipairs(dependencies) do loaded[name] = true end
    NS.IsAddonLoaded = function(name) return loaded[name] == true end
    NS.IsZygorLoaded = function() return NS.IsAddonLoaded(zygorName) end
    NS.RegisterGuideTargetProvider = noop
    NS.RoutingBackend_Dugi.NativePlannerChanged = noop
    _G.C_AddOns = { IsAddOnLoaded = NS.IsAddonLoaded }
    _G.hooksecurefunc = function(object, method, callback)
        hookCount = hookCount + 1
        local original = object[method]
        object[method] = function(...)
            original(...)
            callback(...)
        end
    end

    local finish = planners[id](forever, function() hookCount = hookCount + 1 end)
    if mode == "disabled" then
        loaded[dependencies[1]] = nil
    elseif mode == "travel_disabled" then
        _G.ZygorGuidesViewer.db.profile.pathfinding = false
    end
    local entry = catalog.byID[id]
    local begin = NS[entry.objectKey].BeginPlan
    assert(loadfile("bridge/routing/backends/" .. id .. ".lua"))()
    local backend = NS[entry.objectKey]
    backend.BeginPlan = function(attempt)
        assert(backend.GetReadiness() == "ready")
        return begin(attempt)
    end
    backend.AdoptPlan, backend.CancelPlan = nil, nil
    for _, other in ipairs(catalog.entries) do
        if other.id ~= id and other.id ~= "direct" then f.behavior[other.id] = "unavailable" end
    end
    f.behavior[id] = "success"
    for _, name in ipairs(dependencies) do f.event("ADDON_LOADED", name) end
    f.event("PLAYER_LOGIN")
    assert(hookCount == 1, id .. " should observe its native startup signal once")
    return f, finish
end

for _, forever in ipairs({false, true}) do
    for _, id in ipairs({"zygor", "dugi", "mapzeroth", "farstrider"}) do
        local f, finish = fixture(id, forever)
        local owner = f.start(2, .61, .47, "Exact guide destination")
        f.drain()
        local status = f.NS.GetRoutePlanningStatus(owner)
        assert(status.waiting and owner.backend == "direct" and #f.calls == 0 and #f.messages == 0, id)
        assert(owner.legs[1].x == .61 and owner.legs[1].y == .47 and owner.legs[1].title == "Exact guide destination", id)
        finish(true)
        finish(true)
        assert(#f.calls == 0, "Readiness attempted planning inside the native callback")
        f.drain()
        assert(owner.backend == id and #f.calls == 1 and #f.messages == 0, id .. " did not quietly resume on readiness")
    end
end

for _, id in ipairs({"zygor", "dugi", "farstrider"}) do
    local f, finish = fixture(id, true)
    local owner = f.start()
    f.drain()
    assert(f.NS.GetRoutePlanningStatus(owner).waiting, id)
    finish(false)
    f.drain()
    assert(owner.backend == "direct" and #f.calls == 1 and #f.messages == 1
        and f.messages[1]:find("is unavailable", 1, true), id .. " failed startup waited for the deadline")
end

for _, mode in ipairs({"disabled", "travel_disabled"}) do
    local f = fixture("zygor", false, mode)
    local owner = f.start()
    f.drain()
    assert(owner.backend == "direct" and #f.calls == 1 and #f.messages == 1
        and not f.NS.GetRoutePlanningStatus(owner).waiting, "Disabled LibRover entered the startup wait")
end

local f, finish = fixture("mapzeroth", true)
local owner = f.start()
f.drain()
f.drain(30)
assert(owner.backend == "direct" and #f.messages == 1
    and f.messages[1] == "Mapzeroth is still loading. Using TomTom Direct.")
finish(true)
f.drain()
f.drain()
assert(owner.backend == "mapzeroth" and #f.messages == 2 and f.messages[2] == "Mapzeroth routing restored.")

f, finish = fixture("farstrider", false)
finish(true)
owner = f.start()
f.drain()
assert(owner.backend == "farstrider" and #f.calls == 1 and #f.messages == 0
    and not f.NS.GetRoutePlanningStatus(owner).waiting)

local backend = f.NS.RoutingBackend_Farstrider
local validator = f.NS.RegisterRouteBackendStateValidator
local baseline
f.NS.RegisterRouteBackendStateValidator = function(id, validate, probe)
    local ok
    ok, baseline = validate()
    assert(ok)
    validator(id, validate, probe)
end
backend.Initialize()
owner._routeBackendStateFingerprint = baseline
f.combat = true
finish(true)
finish(true)
f.drain(1)
assert(#f.calls == 1, "Farstrider replanned in combat after a graph rebuild")
f.combat = false
assert(f.NS.FlushDeferredRouteBackendStateValidations())
f.drain()
f.drain()
assert(#f.calls == 2 and owner.backend == "farstrider", "Active Farstrider did not replan once after combat")

f, finish = fixture("farstrider", true)
finish(true)
f.behavior.farstrider = "failed"
owner = f.start()
f.drain()
assert(owner.backend == "direct")
f.behavior.farstrider = "success"
finish(true)
f.drain()
assert(owner.backend == "farstrider", "Farstrider graph rebuild did not wake preferred-backend recovery")

print("Four planner startup signals, both flavors, exact provisional targets and failed startup fallback passed")
