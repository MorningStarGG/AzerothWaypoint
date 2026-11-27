AzerothWaypointNS = {}
assert(loadfile("core/core.lua"))()
assert(loadfile("core/map_coordinates.lua"))()
assert(loadfile("core/util.lua"))()
assert(loadfile("core/instance_entrances.lua"))()
local NS = AzerothWaypointNS
local maps = {
    [10] = { name = "Outdoor", mapType = 3, parentMapID = 1 },
    [11] = { name = "Other faction", mapType = 3, parentMapID = 1 },
    [90] = { name = "Dungeon", mapType = 4, parentMapID = 10 },
    [91] = { name = "Raid", mapType = 4, parentMapID = 10 },
    [92] = { name = "Interior", mapType = 5, parentMapID = 10 },
}
Enum = { UIMapType = { Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 } }
CreateVector2D = function(x, y) return { x = x, y = y } end
local wrongSpace, wrongMap, blizzard, faction, lookups = false, false, true, "Alliance", 0
local journalGameMap = 555
C_Map = {
    GetMapInfo = function(map) return maps[map] end,
    GetWorldPosFromMapPos = function(map, pos)
        return map < 90 and 1 or wrongSpace and 1 or 555, CreateVector2D(pos.x * 1000, pos.y * 1000)
    end,
    GetMapPosFromWorldPos = function(_, pos, map)
        return wrongMap and 10 or map, CreateVector2D(pos.x / 1000, pos.y / 1000)
    end,
    CanSetUserWaypointOnMap = function() return true end,
}
EJ_GetInstanceForMap = function(map) if map == 91 then return 123 end end
EJ_GetInstanceInfo = function() return unpack({ [1] = "Test raid", [12] = true }, 1, 12) end
C_EncounterJournal = {
    GetInstanceForGameMap = function(id) if id == journalGameMap then return 123 end end,
    GetDungeonEntrancesForMap = function()
        if blizzard then return { { journalInstanceID = 123, position = CreateVector2D(.2, .3) } } end
    end,
}
FarstriderLibData_API = { GetInstanceEntrance = function(id)
    assert(id == 555)
    lookups = lookups + 1
    return { mapId = 1, uiMapHint = faction == "Alliance" and 10 or 11, pos = CreateVector2D(350, 470) }
end }
local function route(map)
    return NS.ResolveInstanceRouteIntent(map, .4, .5, "Original waypoint")
end
assert(not route(93))
maps[93] = { mapType = 4 }
assert(not route(93))
maps[93].parentMapID = 10
assert(route(93).entrance.mapID == 10, "Late map or parent data was permanently cached as unavailable")
lookups = 0
assert(route(91).entrance.x == .2 and lookups == 0, "Farstrider replaced a known Blizzard entrance")
blizzard = false
local result = assert(route(90))
assert(result.entrance.x == .35 and result.travelType == "dungeon"
    and result.final.mapID == 90 and result.final.x == .4 and result.final.title == "Original waypoint")
faction = "Horde"
assert(route(91).entrance.mapID == 11 and route(91).travelType == "raid")
journalGameMap = 556
assert(not route(91), "A different journal instance ID was accepted")
wrongMap = true
assert(not route(90), "Wrong UI map round-trip was accepted")
wrongMap, wrongSpace = false, true
assert(not route(90) and not route(92), "Shared outdoor or indoor micro maps used the fallback")
print("Verified instance entrance fallback, Blizzard precedence, faction and map identity passed")
