local info, reads = {}, 0
local ns = { Constants = {MAX_PARENT_MAP_DEPTH=8, COORD_BOUNDS_EPSILON=0.0001}, State = {} }
AzerothWaypointNS = ns
Enum = { UIMapType = {Zone=3, Continent=2, World=1, Cosmic=0} }
C_Map = { GetMapInfo = function(id) reads = reads + 1; return info[id] end }
local root = arg[2] or "."
assert(loadfile(root .. "/core/map_coordinates.lua"))()
assert(ns.GetMapContinentAncestor(10) == nil)
info[10] = {mapType=3, parentMapID=20}
assert(ns.GetMapContinentAncestor(10) == nil)
info[20] = {mapType=2, parentMapID=0}
assert(ns.GetMapContinentAncestor(10) == 20 and ns.IsMapContinentOrHigher(20))
local before = reads
assert(ns.GetMapContinentAncestor(10) == 20 and reads == before)
info[11] = {parentMapID=20}
assert(ns.GetMapContinentAncestor(11) == 20)
info[11].mapType = 2
assert(ns.GetMapContinentAncestor(11) == 11)

CreateVector2D = function(x,y) return {x=x,y=y} end
C_Map.CanSetUserWaypointOnMap = function(id) return id == 20 end
local transformsReady = false
C_Map.GetWorldPosFromMapPos = function(id, pos)
    if id == 30 and not transformsReady then return end
    return 1, pos
end
assert(ns.ResolveSettableUserWaypointTarget(30, .2, .8) == nil)
info[30] = {mapType=3, parentMapID=20}
assert(ns.ResolveSettableUserWaypointTarget(30, .2, .8) == nil)
transformsReady = true
local map, x, y = ns.ResolveSettableUserWaypointTarget(30, .2, .8)
assert(map == 20 and x == .2 and y == .8)

local maps = assert(loadfile("tests/map_click_fixture.lua"))()
local function CheckClick(from, px, py, expectedMap, expectedX)
    local id, zx, zy = ns.ResolveMapClickDestination(from, px, py)
    assert(id == expectedMap and math.abs(zx - expectedX) < 1e-10 and zy == py)
end
local clickX, clickY = .24276480065767, .65001007427801
CheckClick(1413, clickX, clickY, 1412, clickX + .25)
CheckClick(1412, .625, .5, 1413, .375)
CheckClick(1412, .4, .5, 1412, .4)
CheckClick(1414, .5, .5, 1412, .375)
local zoneAtPosition
C_Map.GetMapInfoAtPosition = function() return zoneAtPosition end
CheckClick(1413, clickX, clickY, 1413, clickX)
zoneAtPosition = maps[1413]
CheckClick(1412, .1, .5, 1412, .1) -- Translation falls outside the suggested map.
maps[90] = {mapID=90, mapType=3, parentMapID=1412}
CheckClick(90, .5, .5, 90, .5) -- A nested map has its own coordinate system.

local hidden = {}
issecretvalue = function(v) return v == hidden end
local restricted = true
_G.LibStub = function()
    return {
        GetPlayerZonePosition = function() return restricted and hidden or .2, .4, 1412 end,
        GetZoneDistance = function()
            assert(not restricted, "projected an inaccessible coordinate")
            return hidden
        end,
    }
end
assert(ns.GetPlayerWaypointDistance(1412, .4, .5) == nil)
restricted = false
assert(ns.GetPlayerWaypointDistance(1412, .4, .5) == nil)
