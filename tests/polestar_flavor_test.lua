-- A stray Polestar installation must not expose its integration on Retail.
for _, version in ipairs({ 120105, 16001 }) do
    _G.GetBuildInfo = function() return "fixture", "0", "date", version end
    _G.AzerothWaypointNS, _G.AzerothWaypointDB, _G.AzerothWaypointCharDB = {}, nil, nil
    _G.C_AddOns = {
        IsAddOnLoaded = function(name) return name == "Polestar" end,
        GetAddOnInfo = function(name) if name == "Polestar" then return name, name, "", true end end,
        GetAddOnEnableState = function() return 2 end,
    }
    local frames, registered = 0, 0
    _G.CreateFrame = function()
        frames = frames + 1
        return { RegisterEvent = function() end, SetScript = function() end, Hide = function() end, Show = function() end }
    end
    _G.hooksecurefunc = function() end
    _G.Polestar = { On = function() end, Off = function() end, Get = function() return false end,
        Engine = {}, Nav = { walk = { Floor = function() end, Floors = function() end }, PlanRoute = function() end, GetTravelData = function() return {} end },
        Compat = { MapToWorld = function() end, WorldToMap = function() end } }
    for _, key in ipairs({ "GetGuide", "GetStepIndex", "GetStepView", "GetWaypoint", "GetTabs", "Prev", "Next", "Skip", "AimGoal" }) do
        Polestar.Engine[key] = function() end
    end
    assert(loadfile("core/core.lua"))()
    assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("core/map_coordinates.lua"))()
assert(loadfile("core/util.lua"))()
    assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
    local NS = AzerothWaypointNS
    local forever = version == 16001
    NS.RegisterExternalWaypointSource = function() registered = registered + 1 end
    NS.RegisterGuideTargetProvider = function() registered = registered + 1 end
    NS.RegisterRouteBackendStateValidator = function() registered = registered + 1 end
    assert(loadfile("integrations/guides/presentation.lua"))()
    assert(loadfile("integrations/guides/source_runtime.lua"))()
    assert(loadfile("integrations/guides/polestar/polestar_presentation.lua"))()
    assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/service_search.lua"))()
assert(loadfile("integrations/guides/polestar/polestar_provider.lua"))()
    assert(NS.IsPolestarLoaded() == forever, "Wrong client runtime availability")
    assert(loadfile("bridge/routing/shared.lua"))()
assert(loadfile("bridge/routing/backends/polestar.lua"))()
local plannerFixture = assert(loadfile("tests/planner_attempt_fixture.lua"))().Install(NS.RoutingBackend_Polestar)
    assert(NS.RoutingBackend_Polestar.IsAvailable() == forever, "Wrong client backend availability")
    NS.RoutingBackend_Polestar.Initialize()
    assert((frames > 0) == forever and (registered > 0) == forever, "Retail installed Polestar events or provider registration")
    if not forever then
        NS.RegisterGuideTrackerViewerProvider = function() error("Retail registered Polestar Viewer") end
        assert(loadfile("integrations/guides/viewer_chat.lua"))()
assert(loadfile("interface/startup_notices.lua"))()
assert(loadfile("integrations/guides/polestar/viewer.lua"))()
        assert(NS.GetPolestarTrackerViewerStatus == nil, "Retail exposed Polestar Viewer")
    end
    assert(loadfile("docs/integrations_data.lua"))()
    local card
    for _, entry in ipairs(NS.GetIntegrationInfo()) do if entry.name == "Polestar" then card = entry end end
    assert((card ~= nil) == forever, "Wrong client integration card visibility")
    assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("interface/startup_notices.lua"))()
assert(loadfile("interface/options/shared.lua"))()
    local option
    for _, entry in ipairs(NS.Internal.Interface.options.CreateRoutingBackendOptions()) do
        if entry.value == "polestar" then option = entry end
    end
    assert((option ~= nil) == forever, "Wrong client backend option visibility")
    NS.Internal.Appearance = { GetProviders = function() return {} end }
    assert(loadfile("interface/options/canvas_data.lua"))()
    local search
    local options = NS.Internal.Interface.canvas.Data.GetOptions()
    for _, entry in ipairs(options) do
        if entry.key == "polestar" then search = entry end
    end
    assert((search ~= nil) == forever, "Wrong client option search visibility")
    assert(NS.GetInitialRoutingBackendID(function(name) return name == "Polestar" end) == (forever and "polestar" or "direct"))
end
print("Polestar Forever-only runtime, registration, backend, cards and option search passed")
