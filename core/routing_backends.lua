-- ============================================================
-- Routing backend catalog
-- ============================================================
--
-- Declares backend metadata in fallback order. The catalog loads before the
-- planner modules, so availability and runtime objects are resolved on demand.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}

local entries = {
    {
        id = "zygor",
        label = "Zygor",
        objectKey = "RoutingBackend_Zygor",
        addons = function() return { NS.GetZygorAddonName() } end,
        -- Retail LibRover holds queued searches until combat ends.
        combatPlanning = function() return NS.IsWoWForever() end,
        reasons = {
            not_installed = "Install Zygor Guides Viewer to use Zygor's LibRover routing.",
            disabled = "Enable Zygor Guides Viewer for this character to use Zygor's LibRover routing.",
            not_loaded = "Load Zygor Guides Viewer to use Zygor's LibRover routing.",
            unavailable = "Zygor Guides Viewer is installed but LibRover is not available right now.",
        }
    },
    {
        id = "farstrider",
        label = "FarstriderLib",
        objectKey = "RoutingBackend_Farstrider",
        addons = { "FarstriderLib", "FarstriderLibData" },
        combatPlanning = true,
        reasons = {
            not_installed = "Install FarstriderLib and FarstriderLibData to use Farstrider routing.",
            partly_installed = function(names)
                return "Install missing Farstrider dependency: " ..
                    table.concat(names, ", ") .. "."
            end,
            disabled = "Enable FarstriderLib and FarstriderLibData for this character to use Farstrider routing.",
            partly_disabled = function(names)
                return "Enable Farstrider dependency for this character: " ..
                    table.concat(names, ", ") .. "."
            end,
            not_loaded = "Load FarstriderLib and FarstriderLibData to use Farstrider routing.",
            partly_loaded = function(names) return "Load Farstrider dependency: " .. table.concat(names, ", ") .. "." end,
            unavailable =
            "FarstriderLib and FarstriderLibData are loaded, but Farstrider's routing API is not available right now.",
        }
    },
    {
        id = "mapzeroth",
        label = "Mapzeroth",
        objectKey = "RoutingBackend_Mapzeroth",
        addons = { "Mapzeroth" },
        combatPlanning = true,
        reasons = {
            not_installed = "Install Mapzeroth to use Mapzeroth routing.",
            disabled = "Enable Mapzeroth for this character to use Mapzeroth routing.",
            not_loaded = "Load Mapzeroth to use Mapzeroth routing.",
            unavailable = "Mapzeroth is loaded but its routing API is not available right now.",
        }
    },
    {
        id = "polestar",
        label = "Polestar",
        objectKey = "RoutingBackend_Polestar",
        addons = { "Polestar" },
        foreverOnly = true,
        combatPlanning = true,
        reasons = { unavailable = "Polestar is not ready. Its current guide and travel package supports WoW Forever." }
    },
    {
        id = "dugi",
        label = "Dugi",
        objectKey = "RoutingBackend_Dugi",
        addons = { "DugisGuideViewerZ" },
        combatPlanning = true,
        reasons = {
            not_installed = "Install Dugi Guides to use its travel planner.",
            disabled = "Enable Dugi Guides for this character to use its travel planner.",
            not_loaded = "Load Dugi Guides to use its travel planner.",
            unavailable = "Dugi's Taxi System has not initialized its planning capabilities.",
        }
    },
    {
        id = "questierouter",
        label = "QuestieRouter",
        objectKey = "RoutingBackend_QuestieRouter",
        addons = { "QuestieRouter", "Questie", "QuestieDB" },
        foreverOnly = true,
        combatPlanning = true,
        reasons = { unavailable = "QuestieRouter and Questie must finish loading their current database and planning capabilities." }
    },
    { id = "direct", label = "TomTom Direct", objectKey = "RoutingBackend_Direct", addons = {}, combatPlanning = true },
}
local catalog = { entries = entries, byID = {}, initialization = { "direct", "zygor", "mapzeroth", "farstrider", "polestar", "dugi", "questierouter" } }
NS.Internal.RoutingBackends = catalog
for _, entry in ipairs(entries) do catalog.byID[entry.id] = entry end

function catalog.SupportsClient(entry) return not entry.foreverOnly or NS.IsWoWForever() end

function catalog.CanPlanInCombat(id)
    local policy = catalog.byID[id].combatPlanning
    return policy == true or type(policy) == "function" and policy()
end

function catalog.GetAddons(entry) return type(entry.addons) == "function" and entry.addons() or entry.addons end

function NS.GetRoutingBackend(id)
    local entry = catalog.byID[id]
    return entry and NS[entry.objectKey] or nil
end

function catalog.GetReadiness(id)
    local entry = catalog.byID[id]
    if not entry or not catalog.SupportsClient(entry) then return "unavailable", "unsupported_client" end
    if id == "direct" then return "ready" end
    local backend = NS.GetRoutingBackend(id)
    if type(backend) ~= "table" then return "unavailable", "unavailable" end
    if type(backend.GetReadiness) == "function" then return backend.GetReadiness() end
    if type(backend.IsAvailable) ~= "function" then return "unavailable", "unavailable" end
    local available, reason = backend.IsAvailable()
    if available == true then return "ready" end
    return "unavailable", reason or "unavailable"
end

function catalog.IsAvailable(id)
    local status, reason = catalog.GetReadiness(id)
    return status == "ready", reason
end

function catalog.Label(id) return catalog.byID[id] and catalog.byID[id].label or tostring(id or "-") end

function catalog.Usage()
    local ids = { "direct", "zygor", "mapzeroth", "farstrider", "dugi" }
    if NS.IsWoWForever() then
        ids[#ids + 1] = "polestar"; ids[#ids + 1] = "questierouter"
    end
    return table.concat(ids, "|")
end

function NS.GetInitialRoutingBackendID(isEnabled)
    isEnabled = isEnabled or NS.IsAddonLoaded
    for _, entry in ipairs(entries) do
        if catalog.SupportsClient(entry) then
            local available = true
            for _, name in ipairs(catalog.GetAddons(entry)) do
                if not isEnabled(name) then
                    available = false; break
                end
            end
            if available then return entry.id end
        end
    end
    return "direct"
end
