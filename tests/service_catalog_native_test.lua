local path = dofile("tests/native_path.lua")
local native = dofile("tests/guide_parity/native_function.lua")
local function SetOrder(namespace, key)
    namespace.GetGuideTrackerViewerOrder = function() return {key} end
end
local function Has(catalog, service, subject)
    local search = AzerothWaypointNS.Internal.ServiceSearch
    local key = search.Key(assert(search.Query(service, subject)))
    for _, entry in ipairs(catalog) do
        if entry.children then
            for _, child in ipairs(entry.children) do if search.Key(child.query) == key then return true end end
        elseif search.Key(entry.query) == key then return true end
    end
    return false
end
for _, client in ipairs({ "retail", "forever" }) do
    local f = dofile("tests/service_search_fixture.lua")()
    local search = f.search
    f.NS.IsWoWForever = function() return client == "forever" end
    UnitClass = function() return "Rogue", "ROGUE" end
    local z, ww = f.z, f.ww
    z.IsRetail, z.IsForever = client == "retail", client == "forever"
    z.IconSets = { WorldQuest = {} }
    local function Copy(value)
        if type(value) ~= "table" then return value end
        local copy = {}; for k,v in pairs(value) do copy[k] = Copy(v) end; return copy
    end
    z.F = { DeepCopy = Copy }
    local coords = setmetatable({}, { __index = function() return {0,1,0,1} end })
    local addon = client == "forever" and "ZygorGuidesViewerForever" or "ZygorGuidesViewer"
    native(client, addon .. "/WhoWhere.lua", "WW:SetupMenuArray", { WW = ww, ZGV = z, CLASS_ICON_TCOORDS = coords })
    ww:SetupMenuArray()
    local data = assert(loadfile(path(client, addon .. (client == "forever" and "/Data-Forever/NPCData.lua" or "/Data-Retail/NPCData.lua"))))
    data(addon, z)
    z.NPCData.raw = z._NPCData
    local catalog = search.GetCatalog()
    assert(Has(catalog, "trainer", "alchemy") and Has(catalog, "repair"))
    local function CheckMenus(entries)
        for _, entry in ipairs(entries) do
            if entry.menuList then CheckMenus(entry.menuList)
            elseif not entry.nofunc then
                local name = entry.type or entry.text
                if name == "Poisons" then assert(Has(catalog, "poisons")) end
                if name == "Reagents" then assert(Has(catalog, "reagents")) end
                if name == "Mage" then assert(Has(catalog, "class", "MAGE")) end
            end
        end
    end
    CheckMenus(ww.Types)
    assert(not Has(catalog, "class", "MAGE") or client == "forever")
    assert(search.GetCatalog() == catalog and #f.callbacks == 0 and #f.calls == 0)
end

dofile("tests/dugi_provider_test.lua")
local NS, dugi = AzerothWaypointNS, assert(rawget(_G, "DugisGuideViewer"))
local search = NS.Internal.ServiceSearch
SetOrder(NS, "dugi")
UnitClass = function() return "Rogue", "ROGUE" end
UnitFactionGroup = function() return "Horde" end
local npcSearches = 0
dugi.IterateAllFindNearestPoints = function() npcSearches=npcSearches+1;error("Catalog iterated native NPC searches") end
dugi.Modules.WorldMapTracking.GetDistance = function() error("Catalog calculated distance") end
for _, client in ipairs({ "retail", "forever" }) do
    local env = {}
    local data = assert(loadfile(path(client, "DugisGuideViewerZ/WorldMapTrackingPoints.lua")))
    setfenv(data, setmetatable(env, { __index = _G }))()
    _G.DugisWorldMapTrackingPoints = assert(env.DugisWorldMapTrackingPoints)
    _G.CollectedWorldMapTrackingPoints_v2 = { Horde = { [1412] = {} } }
    local catalog = search.GetCatalog()
    assert(Has(catalog, "trainer", "alchemy") and Has(catalog, "food") and Has(catalog, "reagents"))
    assert(Has(catalog, "class", "ROGUE") and not Has(catalog, "class", "MAGE"))
    assert(search.GetCatalog() == catalog)
    local list = CollectedWorldMapTrackingPoints_v2.Horde[1412]
    list[#list + 1] = "10:coords:1:Dragonriding"
    assert(Has(search.GetCatalog(), "training", "name:Dragonriding"))
    assert(not search.Request(search.Query("class", "MAGE"), "dugi"), "Dugi substituted the player's class")
    assert(npcSearches==0, "An incompatible class request reached Dugi's native search")
end

local r = dofile("tests/polestar_integration_test.lua").runtime
NS, search = AzerothWaypointNS, AzerothWaypointNS.Internal.ServiceSearch
SetOrder(NS, "polestar")
local input = assert(io.open(path("forever", "Polestar/Nav/Nearby.lua")))
local source = input:read("*a"); input:close()
local literal = assert(source:match("local KINDS = (%b{})"))
local chunk = assert(loadstring("return " .. literal))
setfenv(chunk, { L = setmetatable({}, { __index = function(_, key) return key end }) })
local loaded, installed, enabled, finds, loads = false, true, true, 0, 0
C_AddOns = { DoesAddOnExist = function() return installed end }
NS.IsAddonEnabledForCurrentCharacter = function() return enabled end
r.Codex = { IsLoaded = function() return loaded end, Load = function() loads = loads + 1; error("Catalog loaded the Codex") end }
r.Compat.GetPlayerInfo = function() return { class = "ROGUE", faction = "Horde", level = 20 } end
r.Compat.SKILL_LINES = {alchemy = 171, ["first aid"] = 129}
r.Nav.nearby = { KINDS = chunk(), Find = function() finds = finds + 1 end,
    Fits = function(kind) return kind.key ~= "bullets" end,
    Weapons = function() return {{line = 173, label = "Daggers"}} end }
local catalog = search.GetCatalog()
assert(Has(catalog, "class", "ROGUE") and Has(catalog, "trainer", "alchemy") and Has(catalog, "weapon", 173))
assert(not Has(catalog, "class", "MAGE") and not Has(catalog, "bullets") and not Has(catalog, "poisons"))
for _ = 1, 100 do assert(search.GetCatalog() == catalog) end
assert(loads == 0 and finds == 0 and not loaded, "Menu warmed the native search/database")
enabled = false
assert(not Has(search.GetCatalog(), "trainer", "alchemy"))
installed, enabled, loaded = false, true, true
assert(Has(search.GetCatalog(), "trainer", "alchemy"), "Loaded Codex was discarded")
assert(not search.Request(search.Query("class", "MAGE"), "polestar") and finds == 0)
assert(not search.Request(search.Query("weapon", 43), "polestar") and finds == 0,
    "Ineligible weapon request reached native search")
print("Installed service metadata, class identity, Dugi collection caching and Polestar demand-loaded capabilities passed")
