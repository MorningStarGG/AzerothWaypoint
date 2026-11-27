local NativePath = dofile("tests/native_path.lua")
local forever = true
local NS = { Internal = {}, IsWoWForever = function() return forever end,
    GetGuideTrackerViewerOrder = function() return {} end }
AzerothWaypointNS = NS
assert(loadfile("core/core.lua"))()
assert(loadfile("core/map_coordinates.lua"))()
assert(loadfile("core/instance_entrances.lua"))()
assert(loadfile("core/service_search.lua"))()
assert(loadfile("integrations/mapzeroth_data.lua"))()

Enum = { UIMapType = { Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 } }
CreateVector2D = function(x, y) return { x = x, y = y } end
local maps, gameMaps, journal, journalByGameMap = {}, {}, {}, {}
local faction, inside, badMap, blizzard, scans = "Alliance", nil, nil, false, 0
UnitFactionGroup = function() return faction end
IsInInstance = function() return inside ~= nil end
GetInstanceInfo = function() return nil, nil, nil, nil, nil, nil, nil, inside end
EJ_GetInstanceForMap = function(id) return journal[id] end
C_EncounterJournal = {
    GetInstanceForGameMap = function(id) return journalByGameMap[id] end,
    GetDungeonEntrancesForMap = function()
        if blizzard then return { { journalInstanceID = 742, position = CreateVector2D(.1, .2) } } end
    end,
}
C_Map = {
    GetMapInfo = function(id) return maps[id] end,
    GetWorldPosFromMapPos = function(id, position)
        return gameMaps[id], CreateVector2D(position.x * 1000, position.y * 1000)
    end,
    GetMapPosFromWorldPos = function(_, position, id)
        return id == badMap and -1 or id, CreateVector2D(position.x / 1000, position.y / 1000)
    end,
    CanSetUserWaypointOnMap = function() return true end,
}

local function loadWorld(client, files)
    local addon = { RULESET = client == "forever" and "forever" or "modern" }
    local root = NativePath(client, "Mapzeroth/")
    assert(loadfile(root .. "World.lua"))("Mapzeroth", addon)
    for _, file in ipairs(files) do assert(loadfile(root .. file))("Mapzeroth", addon) end
    local iterate = addon.World.ForEachNode
    function addon.World:ForEachNode(callback)
        scans = scans + 1
        return iterate(self, callback)
    end
    MapzerothAddon = addon
    return addon
end

local function outdoor(id)
    maps[id] = { name = "Exterior", mapType = 3 }
    gameMaps[id] = 0
end
local function interior(uiMap, gameMap, exterior, ejID)
    maps[uiMap] = { name = "Instance", mapType = 4, parentMapID = exterior }
    gameMaps[uiMap], journal[uiMap] = gameMap, ejID
    journalByGameMap[gameMap] = ejID
end
local function route(uiMap)
    return NS.ResolveInstanceRouteIntent(uiMap, .4, .5, "Final destination")
end

local addon = loadWorld("forever", { "Data/Forever/Pois.lua" })
local foreverCases = {
    { 2994, 1445 }, { 2974, 1447 }, { 3001, 1449 }, { 3039, 2548 },
    { 2970, 1434 }, { 36, 1436 }, -- Deadmines predates the five new dungeons
}
for i, case in ipairs(foreverCases) do
    outdoor(case[2])
    interior(10000 + i, case[1], case[2])
end
assert(not route(10001) and scans == 0, "Mapzeroth's world was used before it was ready")
addon.World:Build()
for i, case in ipairs(foreverCases) do
    local result = assert(route(10000 + i))
    assert(result.entrance.mapID == case[2] and result.travelType == "dungeon")
    assert(result.final.mapID == 10000 + i and result.final.x == .4 and result.final.title == "Final destination")
end
assert(scans == 1, "Instance lookups repeatedly read Mapzeroth's full world")
inside = 2994
assert(not route(10001), "An entrance was returned while inside that instance")
inside, badMap = nil, 10001
assert(not route(10001), "An unverified interior was accepted")
badMap = 1445
assert(not route(10001), "An unverified exterior was accepted")
badMap = nil
interior(10007, 469, 1428) -- The Forever Blackwing Lair record has no game-map ID.
assert(not route(10007), "An unkeyed raid was matched to an interior")
addon.World:Build()
assert(route(10001) and scans == 2, "A world rebuild did not invalidate the entrance index")

forever = false
addon = loadWorld("retail", { "Data/Modern/Nodes_EK.lua", "Data/Modern/Nodes_BfA.lua",
    "Data/Modern/Nodes_Kalimdor.lua", "Data/Modern/Nodes_Pandaria.lua", "Data/Modern/Instances.lua" })
addon.World:Build()
for _, id in ipairs({ 33, 895, 249, 390 }) do outdoor(id) end
interior(20001, 469, 33, 742) -- Blackwing Lair
interior(20002, 1822, 895, 1023) -- Siege of Boralus
interior(20003, 2217, 249, 1180) -- Ny'alotha has multiple exterior records.
FarstriderLibData_API = { GetInstanceEntrance = function()
    return { mapId = 0, uiMapHint = 33, pos = CreateVector2D(350, 470) }
end }
blizzard = true
assert(route(20001).entrance.x == .1 and scans == 2, "Mapzeroth replaced Blizzard's entrance")
blizzard = false
assert(route(20001).entrance.x == .35 and scans == 2, "Mapzeroth replaced Farstrider's entrance")
FarstriderLibData_API.GetInstanceEntrance = function() return nil end
local raid = assert(route(20001))
assert(raid.travelType == "raid" and raid.entrance.mapID == 33 and raid.entrance.x == .6432)
FarstriderLibData_API = nil
assert(route(20002).entrance.x == .72)
faction = "Horde"
assert(route(20002).entrance.x == .88 and scans == 3, "The entrance reused another faction's result")
assert(not route(20003), "The resolver guessed between two entrances")
journalByGameMap[469] = 999
assert(not route(20001), "Conflicting game-map and journal identities were accepted")

-- The same mechanism handles Mapzeroth's phase metadata using current art.
local liveSide
addon.Nodes.testPhases = {
    { id = "phase_a", kind = "instance", journal = 1246, container = "test.a", mapID = 249, x = .4, y = .1 },
    { id = "phase_b", kind = "instance", journal = 1246, container = "test.b", mapID = 249, x = .6, y = .1 },
}
addon.Containers = {
    ["test.a"] = { phaseGroup = "test", phaseSide = 10, phaseMap = 249 },
    ["test.b"] = { phaseGroup = "test", phaseSide = 20, phaseMap = 249 },
}
addon.GetPlayerContext = function() return { mapArtID = function() return liveSide end } end
addon.World:Build()
interior(20004, 1412, 249, 1246)
assert(not route(20004), "A phased entrance was accepted without phase evidence")
liveSide = 10
assert(route(20004).entrance.x == .4)
liveSide = 20
assert(route(20004).entrance.x == .6)
print("Mapzeroth entrances verified against both datasets, with source priority, identity, phase and faction")
