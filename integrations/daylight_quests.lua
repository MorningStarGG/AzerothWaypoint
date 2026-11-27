-- ============================================================
-- DaylightUI quest menu
-- ============================================================
--
-- Adds the AWP routing action to DaylightUI's quest menu when its quest module
-- is ready.

local NS = _G.AzerothWaypointNS
if not NS.IsWoWForever() then return end

local QuestRoutes = NS.Internal.BlizzardTakeovers

local function RegisterQuestMenu()
    local daylight = rawget(_G, "DaylightUI")
    local api = daylight and daylight.API
    local plugin = api and type(api.For) == "function" and api.For("AzerothWaypoint")
    if not plugin or type(plugin.AddQuestMenu) ~= "function" then return false end

    return plugin.AddQuestMenu("route", {
        label = "Route with AzerothWaypoint",
        show = NS.IsRoutingEnabled,
        onClick = function(quest)
            QuestRoutes.RouteQuestExplicitly(quest.questID)
        end,
    })
end

if RegisterQuestMenu() or NS.IsAddonLoaded("DaylightUI") then return end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "DaylightUI" then return end
    self:UnregisterEvent("ADDON_LOADED")
    RegisterQuestMenu()
end)
