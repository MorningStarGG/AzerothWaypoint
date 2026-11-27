-- ============================================================
-- In-game integration catalog
-- ============================================================
--
-- Defines the integrations catalog and reports availability for the current
-- client and loaded addons.

local NS = _G.AzerothWaypointNS

local function IsAddonLoaded(name)
    return type(NS.IsAddonLoaded) == "function" and NS.IsAddonLoaded(name) == true
end

local function IsWoWForever()
    return type(NS.IsWoWForever) == "function" and NS.IsWoWForever() == true
end

local function IsAnyAddonLoaded(names)
    if type(names) ~= "table" then
        return false
    end
    for _, name in ipairs(names) do
        if IsAddonLoaded(name) then
            return true
        end
    end
    return false
end

local function AreAllAddonsLoaded(names)
    if type(names) ~= "table" or #names == 0 then
        return false
    end
    for _, name in ipairs(names) do
        if not IsAddonLoaded(name) then
            return false
        end
    end
    return true
end

local function IsIntegrationLoaded(entry)
    if type(entry) ~= "table" then
        return false
    end
    if entry.requireAllAddons then
        return AreAllAddonsLoaded(entry.addons)
    end
    return IsAnyAddonLoaded(entry.addons)
end

local function GetAddonLoadState(entry)
    if entry.database and NS.Internal.QuestieData then
        local status = NS.Internal.QuestieData.GetStatus()
        if status.databaseReady then return "Database ready", { 0.42, 1.00, 0.55, 1 } end
        if status.databaseLoaded then return "Database not ready", { 1.00, 0.82, 0.00, 1 } end
    end
    local names = entry and entry.addons or nil
    if type(names) ~= "table" or #names == 0 then
        return "Not addon-based", { 0.72, 0.66, 0.58, 1 }
    end
    if IsIntegrationLoaded(entry) then
        return "Loaded", { 0.42, 1.00, 0.55, 1 }
    end
    return "Not loaded", { 0.72, 0.66, 0.58, 1 }
end

-- ============================================================
-- Integration catalog
-- ============================================================

local CATEGORY_ORDER = {
    "Required Addons",
    "Guide Addons",
    "Travel Planners",
    "Objective Trackers",
    "UI Style",
    "Flight Map & Timing",
    "Map & Waypoint Addons",
    "Quest Information",
    "Built-in Support",
}

-- Add a URL to any entry to enable its Copy Link button in Options > Integrations.
-- For integration bundles that need multiple addon links, use:
-- links = {
--     { label = "Addon Name", url = "https://..." },
-- }
local INTEGRATIONS = {
    {
        category = "Required Addons",
        name = "TomTom",
        addons = { "TomTom" },
        required = true,
        url = "https://www.curseforge.com/wow/addons/tomtom",
        summary = "The only required addon. TomTom provides the on-screen navigation arrow and waypoint support.",
        bullets = {
            "AWP manages navigation, your chosen routing backend plans the route, and TomTom shows the way.",
            "Use TomTom /way commands or imported waypoint lists with AWP routing and queues.",
            "Customize the arrow with AWP skins or use TomTom's original look.",
        },
    },
    {
        category = "Guide Addons",
        name = "Zygor Guides Viewer",
        addons = { "ZygorGuidesViewer", "ZygorGuidesViewerForever" },
        url = "https://zygorguides.com",
        summary =
        "Follow Zygor guides with AWP navigation, optional Tracker Viewer and additional guide-window controls.",
        bullets = {
            "Use any available AWP travel planner, including Zygor's own LibRover.",
            "Keep Zygor's original window, compact it until mouseover, or hide it while the guide continues running.",
            "Choose Zygor's Starlight or Stealth arrow skins for TomTom.",
            "Find nearby services through Search Nearby, /awp search or Zygor's own search menu.",
        },
    },
    {
        category = "Guide Addons",
        name = "Dugi Guides",
        addons = { "DugisGuideViewerZ" },
        url = "https://www.dugiguides.com",
        summary = "Follow Dugi guides on Retail and Forever, with optional Tracker Viewer and Travel System routing.",
        bullets = {
            "Use Dugi's own guide controls and progress. Hide its floating guide window if you prefer the Tracker Viewer.",
            "Manage up to six numbered guide slots.",
            "Find nearby services through Search Nearby, /awp search or Dugi's own service search.",
        },
    },
    {
        category = "Guide Addons",
        name = "RestedXP Guides",
        addons = { "RXPGuides" },
        url = "https://www.restedxp.com",
        summary = "Follow RestedXP guides on Retail and Forever using your chosen AWP travel planner.",
        bullets = {
            "Show current and sticky instructions in an optional Tracker Viewer. RestedXP's pause setting is respected.",
            "Switch between up to six recently used guides without losing progress, or use Go to Step and the original guide chooser.",
            "Back can return to an earlier missing quest acceptance or open step selection when the correct step is unclear.",
        },
    },
    {
        category = "Guide Addons",
        name = "Azeroth Pilot Reloaded",
        addons = { "APR" },
        url = "https://www.curseforge.com/wow/addons/azeroth-pilot-reloaded",
        summary = "Follow APR leveling routes using your chosen AWP travel planner.",
        bullets = {
            "Show guide instructions and objective progress in an optional Tracker Viewer.",
            "Next and the step checkbox skip the current step, Back uses APR's undo. Open New Guide opens APR's route browser.",
            "Use /awp apr help for guide commands.",
        },
    },
    {
        category = "Guide Addons",
        name = "WoWPro",
        addons = { "WoWPro" },
        url = "https://www.curseforge.com/wow/addons/wow-pro",
        summary = "Follow WoWPro guides using your chosen AWP travel planner.",
        bullets = {
            "Show instructions and objective progress in an optional Tracker Viewer.",
            "Switch between up to six recently used guides without losing progress.",
            "Back can recover a missing quest acceptance or offer earlier-step selection. Skips that affect other steps require confirmation.",
            "Use /awp wowpro help for guide commands.",
        },
    },
    {
        category = "Guide Addons",
        name = "Polestar",
        foreverOnly = true,
        addons = { "Polestar" },
        url = "https://www.curseforge.com/wow/addons/polestar",
        summary = "Follow Polestar guides on Forever, with an optional Tracker Viewer and travel planner.",
        bullets = {
            "Use Polestar's own guide tabs, step explanations and goal checkoffs. Back and Next preview steps, the step checkbox skips the step.",
            "Show supported escort and group quest prompts, warnings and the optional left-out quest summary in the Viewer.",
            "Optional Helpers can show Polestar's bag-space action, including its original two-click junk-deletion confirmation.",
            "Hide the original guide window without stopping guide progress, or find nearby services through Search Nearby and /awp search.",
        },
    },
    {
        category = "Guide Addons",
        name = "QuestieRouter",
        foreverOnly = true,
        addons = { "QuestieRouter" },
        url = "https://www.curseforge.com/wow/addons/questierouter",
        summary = "Follow dynamically ordered quest tasks on Forever instead of traditional linear guide steps.",
        bullets = {
            "Choose an eligible task, return to automatic ordering or use the native task menu to skip quests.",
            "The optional Tracker Viewer shows individual quest objectives and completed-quest progress, with up to 14 visible tasks and an optional zone banner.",
            "Switch between up to six recently used guides.",
            "Hide the original guide window without stopping guide progress.",
            "Use your chosen AWP travel planner, including QuestieRouter itself.",
        },
    },
    {
        category = "Travel Planners",
        name = "Zygor / LibRover",
        addons = { "ZygorGuidesViewer", "ZygorGuidesViewerForever" },
        url = "https://zygorguides.com",
        summary = "Use Zygor's travel data to plan routes to any AWP destination, not just Zygor guide steps.",
        bullets = {
            "Combine supported flight paths, portals, boats, other transports, items and spells in one route.",
            "Flight Map Assist can identify the exact landing destination when Zygor provides a matching flight-path ID.",
        },
    },
    {
        category = "Travel Planners",
        name = "FarstriderLib and FarstriderLibData",
        addons = { "FarstriderLib", "FarstriderLibData" },
        requireAllAddons = true,
        links = {
            { label = "FarstriderLib",     url = "https://www.curseforge.com/wow/addons/farstriderlib" },
            { label = "FarstriderLibData", url = "https://www.curseforge.com/wow/addons/farstriderlib-data" },
        },
        summary =
        "A travel planner for flights, portals, boats, zeppelins, spells, items and hearthstones. Both addons are required.",
        bullets = {
            "Use Farstrider's travel data to plan journeys to any AWP destination.",
            "Flight Map Assist can highlight the intended flight destination when a match is available.",
        },
    },
    {
        category = "Travel Planners",
        name = "Mapzeroth",
        addons = { "Mapzeroth" },
        url = "https://www.curseforge.com/wow/addons/mapzeroth",
        summary = "Plan routes using flights, portals, transports, teleports and supported walking paths.",
        bullets = {
            "Use supported wearable teleport items, with equipment restored after travel.",
            "On Forever, follow supported roads and capital streets using Mapzeroth's Walking routes setting. Areas without road coverage keep ordinary guidance.",
            "Mapzeroth quest-tracker, quest-follow and corpse-routing actions can hand navigation to AWP. On Forever, this also includes Route with Mapzeroth in DaylightUI.",
            "Flight Map Assist can highlight the intended flight destination when a match is available.",
        },
    },
    {
        category = "Travel Planners",
        name = "Polestar",
        foreverOnly = true,
        addons = { "Polestar" },
        url = "https://www.curseforge.com/wow/addons/polestar",
        summary =
        "Plan travel on Forever using Polestar's flights, transports, portals, teleports and optional terrain walking.",
        bullets = {
            "Configure travel, class teleports and walking preferences in Polestar. Detailed terrain paths require appropriate navigation data.",
            "Supports probable flight paths and spells.",
            "Accept the follower-arrow recommendation to use AWP navigation instead of Polestar's arrow. Polestar's own arrow preferences apply again when AWP routing is disabled.",
        },
    },
    {
        category = "Travel Planners",
        name = "Dugi Travel System",
        addons = { "DugisGuideViewerZ" },
        url = "https://www.dugiguides.com",
        summary = "Use Dugi's Travel System to plan travel for any AWP destination on Retail and Forever.",
        bullets = {
            "Follows Dugi's preferences for flights, portals, transports, hearthstones and supported class or item teleports and spells.",
        },
    },
    {
        category = "Travel Planners",
        name = "QuestieRouter travel",
        foreverOnly = true,
        addons = { "QuestieRouter" },
        url = "https://www.curseforge.com/wow/addons/questierouter",
        summary =
        "Plan travel to any AWP destination on Forever using QuestieRouter's transport and walking preferences.",
        bullets = {
            "Use supported flights, boats, airships and zeppelins while keeping the exact final destination.",
            "Areas without terrain coverage keep ordinary guidance.",
        },
    },
    {
        category = "Objective Trackers",
        name = "Kaliel's Tracker",
        addons = { "!KalielsTracker" },
        url = "https://www.curseforge.com/wow/addons/kaliels-tracker",
        summary =
        "Dedicated Tracker Viewer support on Retail and Forever. AWP automatically prefers Kaliel's Tracker when available.",
        bullets = {
            "Displays guides directly in Kaliel's tracker.",
            "Follows Kaliel's visibility, collapse, fade and supported quest-tracking settings.",
            "Optionally match header texture, background color, font, title/icon color and button color independently.",
        },
    },
    {
        category = "Objective Trackers",
        name = "Ellesmere UI Quest Tracker",
        addons = { "EllesmereUIQuestTracker" },
        url = "https://www.curseforge.com/wow/addons/ellesmereui",
        summary =
        "Dedicated Tracker Viewer support on Forever with the custom tracker enabled, experimental Blizzard docking otherwise.",
        bullets = {
            "On Forever, with custom tracker enabled guides and quests use the custom tracker.",
            "On Retail, or on Forever with the custom tracker disabled, AWP uses Blizzard docking, which can cause blocked actions or other UI errors.",
        },
    },
    {
        category = "Objective Trackers",
        name = "DaylightUI",
        addons = { "DaylightUI" },
        url = "https://www.curseforge.com/wow/addons/daylightui",
        foreverOnly = true,
        summary = "Dedicated Tracker Viewer support on Forever through DaylightUI's Quests module.",
        bullets = {
            "Enable DaylightUI's Quests module to display guides in the DaylightUI tracker.",
            "Choose Route with AzerothWaypoint from a quest in the tracker or journal menu to start navigation.",
            "UI styling is optional and configured separately.",
        },
    },
    {
        category = "Objective Trackers",
        name = "Questie Tracker",
        addons = { "Questie" },
        url = "https://www.curseforge.com/wow/addons/questie",
        foreverOnly = true,
        summary = "Dedicated Tracker Viewer support on Forever, with guides displayed above Questie's quests.",
        bullets = {
            "Enable Questie's tracker to use it for your Guide Viewers.",
            "Enable Always Show Tracker in Questie to keep guides visible even when no quests are tracked.",
        },
    },
    {
        category = "Objective Trackers",
        name = "GW2 UI",
        addons = { "GW2_UI" },
        url = "https://www.curseforge.com/wow/addons/gw2-ui",
        summary = "Dedicated Tracker Viewer support on Retail and Forever.",
        bullets = {
            "Enable GW2 UI's tracker to display guides in their quest tracker.",
            "UI styling is optional and configured separately.",
        },
    },
    {
        category = "UI Style",
        name = "DaylightUI Style",
        addons = { "DaylightUI" },
        url = "https://www.curseforge.com/wow/addons/daylightui",
        foreverOnly = true,
        summary = "Optional AWP appearance matching on Forever, independent of tracker hosting.",
        bullets = {
            "DaylightUI core provides UI styling for Viewers, action panels, navigation markers and AWP windows.",
            "Choose DaylightUI under General > UI Style. Configure fonts, colors, panels and other appearance options in AWP or DaylightUI > AzerothWaypoint.",
            "The Quests module is not required to use DUI styling.",
        },
    },
    {
        category = "UI Style",
        name = "Ellesmere UI Style",
        addons = { "EllesmereUI", "EllesmereUIBlizzardSkin" },
        url = "https://www.curseforge.com/wow/addons/ellesmereui",
        requireAllAddons = true,
        summary = "Optional AWP appearance matching on Retail and Forever, independent of tracker hosting.",
        bullets = {
            "Match the EUI, Blizzard, Classic or Forever look, with separate window-background and font options.",
            "Customize Viewers, action panels, plaques, navigation labels and AWP windows in either AWP or Ellesmere UI's AzerothWaypoint settings.",
            "Requires Blizzard Skins+ with the AzerothWaypoint skin enabled.",
        },
    },
    {
        category = "UI Style",
        name = "ElvUI Style",
        addons = { "ElvUI" },
        url = "https://tukui.org/elvui",
        summary =
        "Optional AWP appearance matching on Retail and Forever. ElvUI uses Blizzard's objective tracker rather than a separate tracker.",
        bullets = {
            "Match ElvUI fonts, controls and panels for individual Viewers, plaques, navigation labels, action panels and AWP windows.",
            "Configure the same preferences in AWP or ElvUI > AzerothWaypoint.",
            "Tracker hosting is separate from appearance. When using Blizzard's tracker, docking remains experimental and can cause blocked actions or other UI errors.",
        },
    },
    {
        category = "UI Style",
        name = "GW2 UI Style",
        addons = { "GW2_UI" },
        url = "https://www.curseforge.com/wow/addons/gw2-ui",
        summary = "Optional AWP appearance matching on Retail and Forever, independent of tracker hosting.",
        bullets = {
            "Choose GW2 UI under General > UI Style to match its UI style.",
            "Customize each area in AWP or GW2 UI Settings > AzerothWaypoint.",
        },
    },
    {
        category = "Flight Map & Timing",
        name = "InFlight",
        addons = { "InFlight" },
        url = "https://www.curseforge.com/wow/addons/inflight-taxi-timer",
        summary = "The first source of flight times for AWP's Taxi List on Retail and Forever.",
        bullets = {
            "Shows recorded trip times when available, or estimates using connecting flights.",
        },
    },
    {
        category = "Flight Map & Timing",
        name = "DaylightUI Flight Times",
        addons = { "DaylightUI" },
        url = "https://www.curseforge.com/wow/addons/daylightui",
        foreverOnly = true,
        summary = "Adds recorded flight times and estimates to the Taxi List on Forever.",
        bullets = {
            "Uses the last recorded time, shared across characters, or bundled estimates from DaylightUI's QoL module.",
        },
    },
    {
        category = "Flight Map & Timing",
        name = "FarstriderLib Data Flight Times",
        addons = { "FarstriderLibData" },
        url = "https://www.curseforge.com/wow/addons/farstriderlib-data",
        foreverOnly = true,
        summary = "Provides estimated Taxi List flight times from Farstrider's travel data on Forever.",
        bullets = {
            "Uses Farstrider's flight path timing data to estimate travel duration before taking a flight.",
        },
    },
    {
        category = "Flight Map & Timing",
        name = "Ellesmere UI Flight Times",
        addons = { "EllesmereUIForeverEssentials" },
        url = "https://www.curseforge.com/wow/addons/ellesmereui",
        foreverOnly = true,
        summary = "Provides estimated flight times for the AWP Taxi List on WoW Forever.",
        bullets = {
            "Estimates travel duration using flight path distances and accounts for your character's Frequent Flier perk.",
        },
    },
    {
        category = "Map & Waypoint Addons",
        name = "HandyNotes",
        addons = { "HandyNotes" },
        links = {
            { label = "HandyNotes", url = "https://www.curseforge.com/wow/addons/handynotes" },
            { label = "MapNotes",   url = "https://www.curseforge.com/wow/addons/mapnotes" },
        },
        summary = "Navigate to supported HandyNotes map pins without losing your saved destinations.",
        bullets = {
            "Works with supported HandyNotes plugins, including MapNotes, and uses the pin's label when available.",
            "Creates a temporary route, keeping saved waypoint queues intact.",
        },
    },
    {
        category = "Map & Waypoint Addons",
        name = "RareScanner",
        addons = { "RareScanner" },
        url = "https://www.curseforge.com/wow/addons/rarescanner",
        summary = "Follow waypoints created by RareScanner to rare-spawn locations.",
        bullets = {
            "Creates a temporary route without deleting your saved or guide destinations. Previous navigation can resume when the temporary route ends.",
        },
    },
    {
        category = "Map & Waypoint Addons",
        name = "SilverDragon",
        addons = { "SilverDragon" },
        url = "https://www.curseforge.com/wow/addons/silver-dragon",
        summary = "Follow waypoints created by SilverDragon to rare-spawn locations.",
        bullets = {
            "Creates a temporary route without deleting your saved or guide destinations. Previous navigation can resume when the temporary route ends.",
        },
    },
    {
        category = "Map & Waypoint Addons",
        name = "WorldQuestTab",
        addons = { "WorldQuestTab" },
        unavailableOnForever = true,
        unavailableReason = "Not available on WoW Forever",
        url = "https://www.curseforge.com/wow/addons/worldquesttab",
        summary = "Route to world quests selected through WorldQuestTab on Retail.",
        bullets = {
            "Uses available quest details for the destination and keeps your saved waypoints intact.",
            "Not available on WoW Forever.",
        },
    },
    {
        category = "Map & Waypoint Addons",
        name = "Questie",
        foreverOnly = true,
        addons = { "Questie" },
        url = "https://www.curseforge.com/wow/addons/questie",
        summary = "Route to quest destinations selected from Questie's map pins and tracker on Forever.",
        bullets = {
            "Shows the selected available quest or objective information, with live progress from the game.",
            "Available Questie information can also help locate automatically followed quests when a destination is missing.",
            "QuestieDB is a separate optional download and is checked independently.",
        },
    },
    {
        category = "Map & Waypoint Addons",
        name = "BtWQuests",
        addons = { "BtWQuests" },
        url = "https://www.curseforge.com/wow/addons/btw-quests",
        summary = "Route to selected BtWQuests quest locations on Retail and Forever.",
        bullets = {
            "Enable Use TomTom waypoints in BtWQuests to route to the exact selected location, with quest details when available.",
        },
    },
    {
        category = "Quest Information",
        name = "QuestieDB",
        foreverOnly = true,
        database = true,
        addons = { "QuestieDB" },
        url = "https://www.curseforge.com/wow/addons/questiedb",
        summary = "Add localized quest, NPC, object and item information to identified quest destinations on Forever.",
        bullets = {
            "Works independently of Questie, including for destinations selected through other supported sources.",
            "Live quest progress and explicitly selected coordinates remain unchanged. Missing or ambiguous information keeps normal game guidance.",
        },
    },
    {
        category = "Quest Information",
        name = "BtWQuests Expansion Addons",
        addons = { "BtWQuests" },
        url = "https://www.curseforge.com/wow/search?search=btwquests",
        summary = "Adds quest information from loaded BtWQuests packs on Retail and Forever.",
        bullets = {
            "Loaded quest packs can fill missing quest names, acceptance sources and known NPC or object names after QuestieDB. AWP does not automatically load additional packs.",
            "Quest turn-in information is shown only when the finisher is known or the current quest-giver interaction confirms it.",
        },
    },
    {
        category = "Built-in Support",
        name = "Blizzard map, quest, and POI data",
        builtin = true,
        summary = "Navigate to supported game destinations without installing another guide or map addon.",
        bullets = {
            "Supports map waypoints, quest pins, tracked and supertracked quests, rare and event pins, flight masters, gossip destinations, dig sites and housing plots where available.",
            "Shows available quest names, icons and objective progress. Quest routing and automatic clearing follow your AWP settings.",
        },
    },
    {
        category = "Built-in Support",
        name = "Unknown addon waypoint callers",
        builtin = true,
        summary = "Use supported waypoint calls from addons without a dedicated AWP integration.",
        bullets = {
            "Enable adoption under General > Addon Waypoint Adoption. Review detected callers and choose which addons to allow or block.",
        },
    },
}

for _, entry in ipairs(INTEGRATIONS) do
    if entry.category == "Guide Addons" then
        entry.bullets[#entry.bullets + 1] =
        "Each guide has optional action panels, inline buttons, chat output and independent Viewer colors and text sizes. Prepared standard actions can remain usable in combat, inline buttons and native helpers are available outside combat."
    end
end

-- ============================================================
-- Availability and display status
-- ============================================================

function NS.GetIntegrationInfo()
    if not IsWoWForever() then
        local entries = {}
        for _, entry in ipairs(INTEGRATIONS) do
            if not entry.foreverOnly then entries[#entries + 1] = entry end
        end
        return entries, CATEGORY_ORDER
    end
    return INTEGRATIONS, CATEGORY_ORDER
end

function NS.GetIntegrationDisplayStatus(entry)
    if type(entry) ~= "table" then
        return "Unknown", { 0.72, 0.66, 0.58, 1 }
    end
    if entry.required then
        if IsIntegrationLoaded(entry) then
            return "Required, loaded", { 0.42, 1.00, 0.55, 1 }
        end
        return "Required, not loaded", { 1.00, 0.34, 0.28, 1 }
    end
    if entry.unavailableOnForever and IsWoWForever() then
        return entry.unavailableReason or "Not available on WoW Forever", { 1.00, 0.34, 0.28, 1 }
    end
    if entry.builtin then
        return "Built in", { 1.00, 0.82, 0.00, 1 }
    end
    return GetAddonLoadState(entry)
end
