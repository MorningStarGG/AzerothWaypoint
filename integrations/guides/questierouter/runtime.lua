-- ============================================================
-- QuestieRouter coordinate access
-- ============================================================
--
-- Converts QuestieRouter world, map and terrain coordinates for the guide and
-- travel adapters.

local NS = _G.AzerothWaypointNS
local Runtime = {}
NS.Internal.QuestieRouterRuntime = Runtime

function Runtime.Number(value)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
        and value == value and math.abs(value) < math.huge
end

function Runtime.Call(owner, name, ...)
    local method = type(owner) == "table" and owner[name]
    if type(method) ~= "function" then return end
    local ok, a, b, c = pcall(method, owner, ...)
    if ok then return a, b, c end
end

function Runtime.Get()
    if not NS.IsWoWForever() or not NS.IsAddonLoaded("QuestieRouter") then return end
    local addon = rawget(_G, "QuestieRouter")
    if type(addon) == "table" then return addon end
end

local Number, Call = Runtime.Number, Runtime.Call

local function Project(addon, c, west, north, map)
    if not Number(map) or map <= 0 then return end
    local x, y = Call(addon, "ZoneCoordsFromWorld", west, north, c, map)
    if Number(x) and Number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        return NS.ResolveSettableUserWaypointTarget(map, x, y)
    end
end

-- QuestieRouter and HBD use west, north. The game world API and the
-- terrain engine both use north, west.
function Runtime.MapPoint(addon, c, west, north, preferred, alternate)
    if not Number(c) or not Number(west) or not Number(north) then return end
    local map, x, y = Project(addon, c, west, north, preferred)
    if map then return map, x, y end
    if alternate ~= preferred then
        map, x, y = Project(addon, c, west, north, alternate)
        if map then return map, x, y end
    end
    if type(NS.ResolveUserWaypointMapCoordsFromWorldPosition) == "function" then
        map = NS.ResolveUserWaypointMapCoordsFromWorldPosition(north, west, preferred, c)
        if map ~= preferred and map ~= alternate then return Project(addon, c, west, north, map) end
    end
end

function Runtime.WorldPoint(addon, map, x, y)
    local west, north, c = Call(addon.HBD, "GetWorldCoordinatesFromZone", x, y, map)
    if Number(c) and Number(west) and Number(north) then
        return { c = c, wx = west, wy = north, mapID = map, x = x, y = y }
    end
end

function Runtime.PlayerWorld(addon)
    local west, north, c = Call(addon and addon.HBD, "GetPlayerWorldPosition")
    if Number(c) and Number(west) and Number(north) then return c, west, north end
end

function Runtime.ToTerrain(west, north, z)
    return { x = north, y = west, z = z }
end

function Runtime.FromTerrain(point)
    if type(point) == "table" and Number(point.x) and Number(point.y) then
        return point.y, point.x, Number(point.z) and point.z or nil
    end
end
