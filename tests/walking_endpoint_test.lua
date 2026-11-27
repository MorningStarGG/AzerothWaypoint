-- Precision is independent of player proximity, route arrival and map size.
_G.AzerothWaypointNS = {}
assert(loadfile("bridge/routing/shared.lua"))()
local NS = AzerothWaypointNS
local same = NS.RouteSpecials.SameWalkingEndpoint
local destination = { mapID = 1456, x = .603, y = .5168 }
local roundTrip = { mapID = 1456, x = .60299968719482, y = .51680153608322 }
local goalWorld = { c = 1, wx = -1200, wy = 3400, z = 20 }
local pointWorld = { c = 1, wx = -1200, wy = 3400, z = 20 }
assert(same(roundTrip, destination, pointWorld, goalWorld), "A known world goal was rejected after map conversion")
pointWorld.wy = 3402
assert(not same(destination, destination, pointWorld, goalWorld), "Map equality overrode a distinct world endpoint")
pointWorld.wy, pointWorld.z = 3400, 50
assert(not same(roundTrip, destination, pointWorld, goalWorld), "A different floor was collapsed")
pointWorld.z, pointWorld.c = 20, 0
assert(not same(roundTrip, destination, pointWorld, goalWorld), "Different continents were collapsed")
pointWorld.c = 1
assert(not same({mapID = 1412, x = destination.x, y = destination.y}, destination, pointWorld, goalWorld),
    "A different native map was collapsed")

local projections, projectionMode = 0, "ready"
NS.GetWorldPositionFromMapCoords = function(_, x, y)
    projections = projections + 1
    if projectionMode == "missing" then return nil end
    if projectionMode == "error" then error("map data unavailable") end
    return 1, x * 10000, y * 10000
end
assert(same(roundTrip, destination), "A sub-yard conversion error created an extra approach leg")
assert(not same({mapID = 1456, x = .603, y = .517}, destination), "A genuine two-yard approach was collapsed")
assert(same({mapID = 1456, x = 0, y = 1}, {mapID = 1456, x = 0, y = 1}), "Map edges were rejected")
local before = projections
assert(same(roundTrip, destination, pointWorld, goalWorld) and projections == before,
    "Copied planner world coordinates caused an unnecessary map projection")
projectionMode = "missing"
assert(not same(roundTrip, destination), "Unavailable projection guessed that an approach was the destination")
assert(same(destination, destination), "Exact coordinates depended on map data")
projectionMode = "error"
assert(not same(roundTrip, destination), "A failed projection guessed endpoint identity")
local secret = {}
_G.issecretvalue = function(value) return value == secret end
assert(not same({mapID = secret, x = .603, y = .5168}, destination))
assert(not same({mapID = 1456, x = 0/0, y = .5168}, destination))
assert(not same({mapID = 1456, x = math.huge, y = .5168}, destination))
assert(not same({mapID = 1456, x = secret, y = .5168}, destination))
print("Walking endpoint identity: conversion precision, exact coordinates, maps, floors and missing data passed")
