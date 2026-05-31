local NS = _G.AzerothWaypointNS

local function IsAddonLoaded(name)
    return type(NS.IsAddonLoaded) == "function" and NS.IsAddonLoaded(name) == true
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
    local names = entry and entry.addons or nil
    if type(names) ~= "table" or #names == 0 then
        return "Not addon-based", { 0.72, 0.66, 0.58, 1 }
    end
    if IsIntegrationLoaded(entry) then
        return "Loaded", { 0.42, 1.00, 0.55, 1 }
    end
    return "Not loaded", { 0.72, 0.66, 0.58, 1 }
end

local CATEGORY_ORDER = {
    "Required",
    "Guide Addons",
    "Route Backends",
    "Flight Map",
    "Tracker Addons",
    "Map, POI, and Rare Addons",
    "Blizzard Sources",
}

-- Add a URL to any entry to enable its Copy Link button in Options > Integrations.
-- For integration bundles that need multiple addon links, use:
-- links = {
--     { label = "Addon Name", url = "https://..." },
-- }
local INTEGRATIONS = {
    {
        category = "Required",
        name = "TomTom",
        addons = { "TomTom" },
        required = true,
        url = "https://www.curseforge.com/wow/addons/tomtom",
        summary = "TomTom draws the on-screen arrow that points you to your destination. AzerothWaypoint uses it to show you where to go.",
        bullets = {
            "AzerothWaypoint decides where you're headed; TomTom shows the arrow that points there.",
            "TomTom's /way command can create waypoints while AWP manages routing, queues, and presentation around them.",
            "You can also use AWP's custom arrow skins and the one-click travel buttons for flights and portals along the way.",
        },
    },
    {
        category = "Guide Addons",
        name = "Azeroth Pilot Reloaded",
        addons = { "APR" },
        url = "https://www.curseforge.com/wow/addons/azeroth-pilot-reloaded",
        summary = "If you follow Azeroth Pilot Reloaded guides, AWP can read their step destinations and route them through TomTom and AWP's 3D overlay.",
        bullets = {
            "Reads the guide step you're on and points you to it, with the step's text and goal shown along the way.",
            "Works alongside your own saved destinations, so APR's guidance and your personal markers don't fight each other.",
        },
    },
    {
        category = "Guide Addons",
        name = "WoWPro",
        addons = { "WoWPro" },
        url = "https://www.curseforge.com/wow/addons/wow-pro",
        summary = "If you follow WoWPro guides, AWP can read their step destinations and route them through TomTom and AWP's 3D overlay.",
        bullets = {
            "Reads the guide step you're on and points you to it, with the step's text and goal shown along the way.",
            "Works alongside your own saved destinations, so WoWPro's guidance and your personal markers don't fight each other.",
        },
    },
    {
        category = "Guide Addons",
        name = "Zygor Guides Viewer",
        addons = { "ZygorGuidesViewer" },
        url = "https://zygorguides.com",
        summary = "If you use Zygor's leveling and quest guides, this is AWP's deepest guide integration. It can route Zygor guide steps, show them in the Tracker Viewer, and keep Zygor features available while using AWP presentation.",
        bullets = {
            "Turns each Zygor guide step into an AWP destination, so the arrow and route always match the step you're on.",
            "Can show Zygor guide steps inside the objective tracker using AWP's Tracker Viewer.",
            "Can hide Zygor's native viewer while keeping its guide engine, waypoints, guide picker, menus, and settings available.",
            "Adds optional Zygor-style arrow skins, and lets Zygor searches turn into routes you can travel to using /awp search or via Zygor's guide menu.",
        },
    },
    {
        category = "Route Backends",
        name = "FarstriderLib and FarstriderLibData",
        addons = { "FarstriderLib", "FarstriderLibData" },
        requireAllAddons = true,
        links = {
            { label = "FarstriderLib",     url = "https://www.curseforge.com/wow/addons/farstriderlib" },
            { label = "FarstriderLibData", url = "https://www.curseforge.com/wow/addons/farstriderlib-data" },
        },
        summary = "A route planner for players who want smart travel routes without using Zygor. Requires both FarstriderLib and FarstriderLibData addons installed. This is a VERY close second to Zygor's LibRover.",
        bullets = {
            "Plans routes using flights, portals, boats, items, and spells from Farstrider's travel data.",
            "Can mark the matching flight path on the flight map when enough route data is available.",
        },
    },
    {
        category = "Route Backends",
        name = "Mapzeroth",
        addons = { "Mapzeroth" },
        url = "https://www.curseforge.com/wow/addons/mapzeroth",
        summary = "Another route planner that builds smart travel routes without needing Zygor, using Mapzeroth's pathfinding. This one is good but might not be as accurate.",
        bullets = {
            "Plans travel-aware routes from Mapzeroth's data when it's available.",
            "Can mark the matching flight path on the flight map when enough route data is available.",
        },
    },
    {
        category = "Route Backends",
        name = "Zygor / LibRover",
        addons = { "ZygorGuidesViewer" },
        url = "https://zygorguides.com",
        summary = "A route planner that works out the fastest way to your destination, including flights, portals, and boats, using Zygor's travel data. This is the GOLD standard.",
        bullets = {
            "Builds smart routes that can mix flight paths, portals, transports, and even items or spells when Zygor knows about them.",
            "Can highlight the exact flight master to use on the flight map, so you take the right taxi.",
        },
    },
    {
        category = "Flight Map",
        name = "InFlight",
        addons = { "InFlight" },
        url = "https://www.curseforge.com/wow/addons/inflight-taxi-timer",
        summary = "If you have InFlight, AWP can use its flight-time estimates to show how long each taxi ride takes in AWP's flight list.",
        bullets = {
            "Shows real or estimated flight times next to destinations in AWP's flight-map list.",
        },
    },
    {
        category = "Tracker Addons",
        name = "Kaliel's Tracker",
        addons = { "!KalielsTracker" },
        url = "https://www.curseforge.com/wow/addons/kaliels-tracker",
        summary = "If you use Kaliel's Tracker instead of the Blizzard objective tracker, AWP's Zygor Tracker Viewer guide display can show inside it.",
        bullets = {
            "Shows AWP's Zygor Tracker Viewer guide steps inside Kaliel's Tracker instead of Blizzard's default tracker.",
            "Keeps guide steps, sticky steps, grouped long tips, and the header buttons in Kaliel's tracker.",
            "Follows Kaliel's own show/hide, collapse, and fade settings.",
            "Supports Kaliel's auto watch and tracking behavior where available.",
        },
    },
    {
        category = "Map, POI, and Rare Addons",
        name = "HandyNotes",
        addons = { "HandyNotes" },
        links = {
            { label = "HandyNotes",     url = "https://www.curseforge.com/wow/addons/handynotes" },
            { label = "MapNotes", url = "https://www.curseforge.com/wow/addons/mapnotes" },
        },
        summary = "Clicking a HandyNotes map pin can become a quick, temporary AWP route to that spot.",
        bullets = {
            "Works with HandyNotes plugins that add clickable map pins, such as those added by MapNotes.",
            "Uses the pin's label when it can, so the route is easy to recognize.",
            "Pins become short-lived temporary routes that step aside when you're done, leaving your saved destinations untouched.",
        },
    },    
    {
        category = "Map, POI, and Rare Addons",
        name = "RareScanner",
        addons = { "RareScanner" },
        url = "https://www.curseforge.com/wow/addons/rarescanner",
        summary = "When RareScanner spots a rare and drops a waypoint, AWP can briefly route you to it.",
        bullets = {
            "Turns a rare scan into a quick, temporary route to that rare's location.",
            "Keeps your saved and guide destinations intact while it's active, then hands control back.",
        },
    },
    {
        category = "Map, POI, and Rare Addons",
        name = "SilverDragon",
        addons = { "SilverDragon" },
        url = "https://www.curseforge.com/wow/addons/silver-dragon",
        summary = "When SilverDragon spots a rare and drops a waypoint, AWP can briefly route you to it.",
        bullets = {
            "Sends you toward the rare as a quick, temporary route, without deleting your saved destinations.",
            "Steps aside and goes back to your previous route once you're done.",
        },
    },
    {
        category = "Map, POI, and Rare Addons",
        name = "WorldQuestTab",
        addons = { "WorldQuestTab" },
        url = "https://www.curseforge.com/wow/addons/worldquesttab",
        summary = "If you use WorldQuestTab, clicking one of its world quests can hand the destination straight to AWP.",
        bullets = {
            "Turns a world quest click into a route, using the quest's details when WorldQuestTab shares them.",
            "Sends you to the world quest without wiping out the destinations you've already saved.",
        },
    },
    {
        category = "Blizzard Sources",
        name = "Blizzard map, quest, and POI data",
        builtin = true,
        summary = "AWP can guide you to Blizzard map, quest, and POI sources.",
        bullets = {
            "Points you to map clicks, your own map pins, quest markers, and tracked quests.",
            "Also handles rare and event vignettes, flight masters, NPC dialog targets, dig sites, and housing plots when Blizzard provides usable API data.",
            "Quest destinations can show the quest's name, icon, and progress, and clear themselves once the quest is done.",
        },
    },
    {
        category = "Blizzard Sources",
        name = "Unknown addon waypoint callers",
        builtin = true,
        summary = "AWP can adopt TomTom-style waypoint calls from other addons that do not have dedicated AWP support yet.",
        bullets = {
            "Each detected addon can be allowed or blocked under General > Addon Waypoint Adoption.",
            "Useful for addons that create normal waypoint calls but do not need dedicated integration logic.",
        },
    },
}

function NS.GetIntegrationInfo()
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
    if entry.builtin then
        return "Built in", { 1.00, 0.82, 0.00, 1 }
    end
    return GetAddonLoadState(entry)
end
