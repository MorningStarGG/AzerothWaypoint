-- Standalone Lua 5.1 fixture tests. Run from the addon root with:
--   lua tests/client_flavor_test.lua

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local interfaceVersion = 120105
local loadedAddons = {}

_G.GetBuildInfo = function()
    return "fixture", "0", "date", interfaceVersion, "fixture product"
end
_G.C_AddOns = {
    IsAddOnLoaded = function(name)
        return loadedAddons[name] == true
    end,
}
_G.AzerothWaypointNS = {
    Constants = {},
    State = {},
}

assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("core/map_coordinates.lua"))()
assert(loadfile("core/util.lua"))()
local NS = _G.AzerothWaypointNS

expect(NS.GetClientFlavor() == "retail", "Retail interface was not detected")
expect(NS.IsWoWForever() == false, "Retail was reported as WoW Forever")
expect(NS.GetZygorAddonName() == "ZygorGuidesViewer", "Retail Zygor identity was wrong")
expect(NS.GetZygorAssetPath("Arrows/Starlight/arrow.tga") ==
    "Interface\\AddOns\\ZygorGuidesViewer\\Arrows\\Starlight\\arrow.tga",
    "Retail Zygor fallback asset root was wrong")

interfaceVersion = 16001
expect(NS.GetClientFlavor() == "forever", "WoW Forever interface was not detected")
expect(NS.IsWoWForever() == true, "WoW Forever helper returned false")
expect(NS.GetZygorAddonName() == "ZygorGuidesViewerForever", "Forever Zygor identity was wrong")

loadedAddons.ZygorGuidesViewerForever = true
_G.ZGV = { DIR = "Interface\\AddOns\\ZygorGuidesViewerForever\\" }
expect(NS.IsZygorLoaded(), "Forever Zygor runtime was not recognized")
expect(NS.GetZygorAssetPath("Skins/icon.tga") ==
    "Interface\\AddOns\\ZygorGuidesViewerForever\\Skins\\icon.tga",
    "Zygor runtime asset root was not preferred")
_G.ZGV = nil

local function Choose(enabledNames)
    return NS.GetInitialRoutingBackendID(function(name)
        return enabledNames[name] == true
    end)
end

expect(Choose({ ZygorGuidesViewerForever = true, FarstriderLib = true, FarstriderLibData = true, Mapzeroth = true }) == "zygor",
    "Forever did not prefer its Zygor addon")
expect(Choose({ FarstriderLib = true, FarstriderLibData = true, Mapzeroth = true }) == "farstrider",
    "Forever did not prefer Farstrider over Mapzeroth")
expect(Choose({ FarstriderLib = true, FarstriderLibData = true }) == "farstrider",
    "Forever did not select Farstrider")

interfaceVersion = 120105
loadedAddons.ZygorGuidesViewerForever = nil
expect(Choose({ FarstriderLib = true, FarstriderLibData = true, Mapzeroth = true }) == "farstrider",
    "Retail backend priority changed")
expect(Choose({ Mapzeroth = true }) == "mapzeroth", "Retail Mapzeroth default was not selected")
expect(Choose({}) == "direct", "Direct fallback was not selected")
expect(Choose({ DugisGuideViewerZ = true }) == "dugi", "Retail did not prefer Dugi over Direct")
expect(Choose({ DugisGuideViewerZ = true, Mapzeroth = true }) == "mapzeroth", "Dugi changed Mapzeroth priority")
expect(Choose({ Polestar = true }) == "direct", "Retail selected a Forever-only backend")
expect(Choose({ Polestar = true, Mapzeroth = true }) == "mapzeroth", "Polestar changed established backend priority")

interfaceVersion = 16001
expect(Choose({ Polestar = true }) == "polestar", "Forever did not prefer Polestar over Direct")
expect(Choose({ DugisGuideViewerZ = true }) == "dugi", "Forever did not prefer Dugi over Direct")
expect(Choose({ DugisGuideViewerZ = true, Polestar = true }) == "polestar", "Dugi changed Polestar priority")
loadedAddons.FarstriderLib = true
loadedAddons.FarstriderLibData = true
assert(loadfile("docs/integrations_data.lua"))()
local integrations = NS.GetIntegrationInfo()
local statuses = {}
for _, entry in ipairs(integrations) do
    statuses[entry.name] = NS.GetIntegrationDisplayStatus(entry)
end
expect(statuses["FarstriderLib and FarstriderLibData"] == "Loaded",
    "Farstrider integration did not report loaded on Forever")
expect(statuses.WorldQuestTab == "Not available on WoW Forever",
    "WorldQuestTab integration did not report Forever unavailability")

local frameCreations = 0
local registeredEvents = {}
local eventHandler = nil
local registeredValidator = nil
_G.FarstriderLib_API = {
    FindTrailTo = function() end,
    RegisterRebuildCallback = function() end,
}
_G.FarstriderLib = {
    Pathfinding = { allNodes = { fixture = true }, Rebuild = function() end, GetValidTravelNodes = function() return {} end },
}
_G.CreateFrame = function()
    frameCreations = frameCreations + 1
    return {
        RegisterEvent = function(_, event)
            registeredEvents[event] = true
        end,
        SetScript = function(_, scriptType, handler)
            if scriptType == "OnEvent" then
                eventHandler = handler
            end
        end,
    }
end
NS.RegisterRouteBackendStateValidator = function(backendID, validator, dependencyProbe)
    registeredValidator = {
        backendID = backendID,
        validator = validator,
        dependencyProbe = dependencyProbe,
    }
end
assert(loadfile("bridge/routing/shared.lua"))()
assert(loadfile("bridge/routing/backends/farstrider.lua"))()
local plannerFixture = assert(loadfile("tests/planner_attempt_fixture.lua"))().Install(NS.RoutingBackend_Farstrider)
expect(NS.RoutingBackend_Farstrider.IsAvailable() == true,
    "Farstrider backend was unavailable on WoW Forever")
NS.RoutingBackend_Farstrider.Initialize()
expect(frameCreations == 1, "Farstrider event coordinator did not initialize on WoW Forever")
expect(type(eventHandler) == "function", "Farstrider event coordinator did not install its handler")
expect(registeredEvents.SPELL_UPDATE_COOLDOWN == true and registeredEvents.SPELLS_CHANGED == true,
    "Farstrider event coordinator did not register validation events")
expect(type(registeredValidator) == "table" and registeredValidator.backendID == "farstrider",
    "Farstrider state validator was not registered on WoW Forever")

print("client_flavor_test: ok")
