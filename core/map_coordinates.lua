-- ============================================================
-- Map coordinates and waypoint projection
-- ============================================================
--
-- Projects map and world coordinates for routing and the overlay. Map
-- hierarchy lookups are shared by both consumers. Projection is shared by map
-- clicks and the navigation host. Parent and continent lookups belong to the
-- map-coordinate layer.

local NS = _G.AzerothWaypointNS
local C = NS.Constants

local function ReadMapPositionCoords(position)
    if type(position) ~= "table" then
        return nil, nil
    end

    if type(position.GetXY) == "function" then
        local ok, x, y = pcall(position.GetXY, position)
        if ok and type(x) == "number" and type(y) == "number" then
            return x, y
        end
    end

    local x = type(position.x) == "number" and position.x or nil
    local y = type(position.y) == "number" and position.y or nil
    return x, y
end

NS.Internal = NS.Internal or {}
NS.Internal.ReadMapPositionCoords = ReadMapPositionCoords

function NS.GetPlayerMapID()
    if type(C_Map.GetBestMapForUnit) ~= "function" then
        return
    end

    local playerMapID = C_Map.GetBestMapForUnit("player")
    if type(playerMapID) ~= "number" then
        return
    end

    return playerMapID
end

function NS.GetPlayerWaypointDistance(mapID, x, y)
    local HBD = _G.LibStub and LibStub("HereBeDragons-2.0", true)
    if not HBD or type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return
    end

    ---@diagnostic disable-next-line: redundant-parameter
    local ok, px, py, playerMapID = pcall(HBD.GetPlayerZonePosition, HBD, true)
    if not ok or issecretvalue and (issecretvalue(px) or issecretvalue(py) or issecretvalue(playerMapID))
        or not (px and py and playerMapID) then
        return
    end

    local distance = HBD:GetZoneDistance(playerMapID, px, py, mapID, x, y)
    if type(distance) == "number" and not (issecretvalue and issecretvalue(distance)) then
        return distance
    end
end

function NS.GetPlayerMapPosition()
    if type(C_Map.GetPlayerMapPosition) ~= "function" then
        return
    end

    local playerMapID = NS.GetPlayerMapID()
    if type(playerMapID) ~= "number" then
        return
    end

    local position = C_Map.GetPlayerMapPosition(playerMapID, "player")
    local x, y = ReadMapPositionCoords(position)
    if type(x) ~= "number" or type(y) ~= "number" then
        return
    end

    return playerMapID, x, y
end

function NS.GetWorldPositionFromMapCoords(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return
    end
    if type(C_Map.GetWorldPosFromMapPos) ~= "function" or type(CreateVector2D) ~= "function" then
        return
    end

    local worldMapID, worldPosition = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    local worldX, worldY = ReadMapPositionCoords(worldPosition)
    if type(worldMapID) ~= "number" or type(worldX) ~= "number" or type(worldY) ~= "number" then
        return
    end

    return worldMapID, worldX, worldY
end

local function TryGetMapCoordsFromWorldPosition(worldMapID, worldX, worldY, preferredMapID)
    if type(C_Map.GetMapPosFromWorldPos) ~= "function" or type(CreateVector2D) ~= "function" then
        return
    end

    local worldPosition = CreateVector2D(worldX, worldY)
    local uiMapID, mapPosition
    local continentID = type(worldMapID) == "number" and worldMapID or 0
    if type(preferredMapID) == "number" then
        uiMapID, mapPosition = C_Map.GetMapPosFromWorldPos(continentID, worldPosition, preferredMapID)
    else
        uiMapID, mapPosition = C_Map.GetMapPosFromWorldPos(continentID, worldPosition)
    end

    local x, y = ReadMapPositionCoords(mapPosition)
    if type(uiMapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return
    end

    local epsilon = C.COORD_BOUNDS_EPSILON
    if x < -epsilon or x > 1 + epsilon or y < -epsilon or y > 1 + epsilon then
        return
    end

    x = math.max(0, math.min(1, x))
    y = math.max(0, math.min(1, y))
    return uiMapID, x, y
end

function NS.ResolveUserWaypointMapCoordsFromWorldPosition(worldX, worldY, preferredMapID, worldMapID)
    if type(worldX) ~= "number" or type(worldY) ~= "number" then
        return
    end

    local mapID, x, y = TryGetMapCoordsFromWorldPosition(worldMapID, worldX, worldY, preferredMapID)
    if type(mapID) == "number" and type(x) == "number" and type(y) == "number" then
        local settableMapID, settableX, settableY = NS.ResolveSettableUserWaypointTarget(mapID, x, y)
        if type(settableMapID) == "number" and type(settableX) == "number" and type(settableY) == "number" then
            return settableMapID, settableX, settableY
        end
    end

    if type(preferredMapID) == "number" then
        mapID, x, y = TryGetMapCoordsFromWorldPosition(worldMapID, worldX, worldY)
        if type(mapID) == "number" and type(x) == "number" and type(y) == "number" then
            local settableMapID, settableX, settableY = NS.ResolveSettableUserWaypointTarget(mapID, x, y)
            if type(settableMapID) == "number" and type(settableX) == "number" and type(settableY) == "number" then
                return settableMapID, settableX, settableY
            end
        end
    end
end

function NS.ProjectWaypointOntoMap(mapID, x, y, targetMapID)
    local worldMapID, worldX, worldY = NS.GetWorldPositionFromMapCoords(mapID, x, y)
    if not worldMapID then return end
    local projectedMapID, projectedX, projectedY =
        TryGetMapCoordsFromWorldPosition(worldMapID, worldX, worldY, targetMapID)
    if projectedMapID == targetMapID then return projectedX, projectedY end
end

-- Missing map records can become available after a zone change. Cache only
-- complete hierarchy records so an early lookup can be retried.
local hierarchy = {}
local _mapAncestryCache = {}
local _mapContinentCache = {}

-- ============================================================
-- Map hierarchy and projection candidates
-- ============================================================

local function GetHierarchyInfo(mapID)
    if hierarchy[mapID] then return hierarchy[mapID] end
    if type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then return nil end
    local info = C_Map.GetMapInfo(mapID)
    if info and type(info.mapType) == "number" and type(info.parentMapID) == "number" then
        hierarchy[mapID] = { mapType = info.mapType, parentMapID = info.parentMapID }
    end
    return info
end

local function IsNormalizedMapPoint(x, y)
    return type(x) == "number" and x >= 0 and x <= 1
        and type(y) == "number" and y >= 0 and y <= 1
end

-- Outdoor zone maps can show land belonging to a neighboring zone. Look up the
-- click on their common continent, then translate the original point to that zone.
function NS.ResolveMapClickDestination(mapID, x, y)
    local types = Enum and Enum.UIMapType
    if not types or not (C_Map and C_Map.GetMapInfoAtPosition)
        or type(mapID) ~= "number" or not IsNormalizedMapPoint(x, y) then
        return mapID, x, y
    end

    local source = GetHierarchyInfo(mapID)
    if not source then return mapID, x, y end
    local continent = mapID
    if source.mapType == types.Zone then
        continent = source.parentMapID
        local parent = continent and GetHierarchyInfo(continent)
        if not parent or parent.mapType ~= types.Continent then return mapID, x, y end
    elseif source.mapType ~= types.Continent then
        return mapID, x, y
    end

    local hbd = LibStub and LibStub("HereBeDragons-2.0", true)
    if not hbd or type(hbd.TranslateZoneCoordinates) ~= "function" then return mapID, x, y end
    local cx, cy = hbd:TranslateZoneCoordinates(x, y, mapID, continent)
    if not IsNormalizedMapPoint(cx, cy) then return mapID, x, y end
    local zone = C_Map.GetMapInfoAtPosition(continent, cx, cy)
    if not zone or zone.mapID == mapID or zone.mapType ~= types.Zone or zone.parentMapID ~= continent then
        return mapID, x, y
    end
    local zx, zy = hbd:TranslateZoneCoordinates(x, y, mapID, zone.mapID)
    if IsNormalizedMapPoint(zx, zy) then return zone.mapID, zx, zy end
    return mapID, x, y
end

local function BuildMapAncestry(mapID)
    if type(mapID) ~= "number" or mapID <= 0 then
        return nil
    end
    local cached = _mapAncestryCache[mapID]
    if cached ~= nil then
        return cached or nil
    end
    if type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then
        return nil
    end

    local ancestry = { [mapID] = true }
    local currentMapID = mapID
    for _ = 1, C.MAX_PARENT_MAP_DEPTH do
        local mapInfo = GetHierarchyInfo(currentMapID)
        local parentMapID = mapInfo and mapInfo.parentMapID
        if type(parentMapID) ~= "number" then return ancestry end
        if parentMapID <= 0 or ancestry[parentMapID] then
            break
        end
        ancestry[parentMapID] = true
        currentMapID = parentMapID
    end
    _mapAncestryCache[mapID] = ancestry
    return ancestry
end

local function IsContinentOrHigherMapType(mapID)
    if type(Enum) ~= "table" or type(Enum.UIMapType) ~= "table" then
        return false
    end

    if type(mapID) ~= "number" or mapID <= 0 then return false end
    local info = GetHierarchyInfo(mapID)
    local mapType = info and info.mapType
    if mapType == nil then
        return false
    end

    return mapType == Enum.UIMapType.Cosmic
        or mapType == Enum.UIMapType.World
        or mapType == Enum.UIMapType.Continent
end

NS.IsMapContinentOrHigher = IsContinentOrHigherMapType

function NS.GetMapContinentAncestor(mapID)
    if type(mapID) ~= "number" or mapID <= 0 then
        return nil
    end
    local cached = _mapContinentCache[mapID]
    if cached ~= nil then
        return cached or nil
    end
    if type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then
        return nil
    end
    if type(Enum) ~= "table" or type(Enum.UIMapType) ~= "table" then
        return nil
    end

    local current, complete = mapID, true
    for _ = 1, C.MAX_PARENT_MAP_DEPTH do
        local mapInfo = GetHierarchyInfo(current)
        if not mapInfo then return nil end
        if type(mapInfo.mapType) ~= "number" then
            complete = false
        elseif mapInfo.mapType == Enum.UIMapType.Continent then
            if complete then _mapContinentCache[mapID] = current end
            return current
        end
        local parent = mapInfo.parentMapID
        if type(parent) ~= "number" then return nil end
        if parent <= 0 then
            if complete then _mapContinentCache[mapID] = false end
            return nil
        end
        current = parent
    end
    return nil
end

local function MapsShareLineage(mapA, mapB)
    if type(mapA) ~= "number" or type(mapB) ~= "number" then
        return false
    end
    if mapA == mapB then
        return true
    end

    local ancestryA = BuildMapAncestry(mapA)
    local ancestryB = BuildMapAncestry(mapB)
    if not ancestryA or not ancestryB then
        return true
    end

    if ancestryA[mapB] or ancestryB[mapA] then
        return true
    end

    for ancestor in pairs(ancestryA) do
        if ancestryB[ancestor] then
            return true
        end
    end
    return false
end

local function IsValidSurrogateMap(surrogateMapID, targetMapID, playerMapID)
    if type(surrogateMapID) ~= "number" or surrogateMapID <= 0 then
        return false
    end

    if IsContinentOrHigherMapType(surrogateMapID) then
        local targetContinent = NS.GetMapContinentAncestor(targetMapID)
        local playerContinent = NS.GetMapContinentAncestor(playerMapID)
        if targetContinent and playerContinent
            and targetContinent == playerContinent
            and surrogateMapID == targetContinent
        then
            return true
        end
        return false
    end

    if MapsShareLineage(surrogateMapID, targetMapID) then
        return true
    end
    if MapsShareLineage(surrogateMapID, playerMapID) then
        return true
    end
    return false
end

local SURROGATE_ROUND_TRIP_TOLERANCE = 25

-- ============================================================
-- Surrogate waypoint projection
-- ============================================================

local function AddSurrogateMapCandidate(candidates, seen, mapID)
    if type(mapID) ~= "number" or mapID <= 0 or seen[mapID] then
        return false
    end
    candidates[#candidates + 1] = mapID
    seen[mapID] = true
    return true
end

local function AddSurrogateMapLineageCandidates(candidates, seen, mapID)
    if type(mapID) ~= "number" or mapID <= 0 then
        return
    end
    local current = mapID
    for _ = 1, C.MAX_PARENT_MAP_DEPTH do
        AddSurrogateMapCandidate(candidates, seen, current)
        local info = GetHierarchyInfo(current)
        local parent = info and info.parentMapID
        if type(parent) ~= "number" or parent <= 0 or seen[parent] then
            return
        end
        current = parent
    end
end

local function BuildSurrogateMapCandidates(targetMapID, playerMapID, preferredMapID)
    local candidates, seen = {}, {}
    AddSurrogateMapCandidate(candidates, seen, preferredMapID)
    AddSurrogateMapLineageCandidates(candidates, seen, targetMapID)
    AddSurrogateMapLineageCandidates(candidates, seen, playerMapID)
    AddSurrogateMapCandidate(candidates, seen, NS.GetMapContinentAncestor(targetMapID))
    AddSurrogateMapCandidate(candidates, seen, NS.GetMapContinentAncestor(playerMapID))
    return candidates
end

local function FormatSurrogateMapCandidates(candidates)
    if type(candidates) ~= "table" or #candidates == 0 then
        return "-"
    end
    local parts = {}
    for index = 1, math.min(#candidates, 8) do
        parts[#parts + 1] = tostring(candidates[index])
    end
    if #candidates > #parts then
        parts[#parts + 1] = "..."
    end
    return table.concat(parts, ",")
end

local function FailSurrogateProjection(reason, detailA, detailB, detailC, detailD)
    return nil, nil, nil, nil, nil, nil, reason, detailA, detailB, detailC, detailD
end

local function FormatSurrogateProjectionCoord(value)
    return type(value) == "number" and string.format("%.4f", value) or "-"
end

local function ResolveSurrogateMapCoordsFromWorldPosition(
    worldMapID,
    worldX,
    worldY,
    targetMapID,
    playerMapID,
    preferredMapID
)
    local candidates = BuildSurrogateMapCandidates(targetMapID, playerMapID, preferredMapID)
    local candidateList = FormatSurrogateMapCandidates(candidates)
    local lastReason, lastA, lastB, lastC

    for _, candidateMapID in ipairs(candidates) do
        local mapID, x, y = TryGetMapCoordsFromWorldPosition(worldMapID, worldX, worldY, candidateMapID)
        if type(mapID) == "number" and type(x) == "number" and type(y) == "number" then
            local settableMapID, settableX, settableY = NS.ResolveSettableUserWaypointTarget(mapID, x, y)
            if type(settableMapID) == "number" and type(settableX) == "number" and type(settableY) == "number" then
                if IsValidSurrogateMap(settableMapID, targetMapID, playerMapID) then
                    local roundTripWorldMapID, roundTripWorldX, roundTripWorldY =
                        NS.GetWorldPositionFromMapCoords(settableMapID, settableX, settableY)
                    if roundTripWorldMapID == worldMapID
                        and type(roundTripWorldX) == "number"
                        and type(roundTripWorldY) == "number"
                    then
                        local dx = roundTripWorldX - worldX
                        local dy = roundTripWorldY - worldY
                        local delta = math.sqrt(dx * dx + dy * dy)
                        if delta <= SURROGATE_ROUND_TRIP_TOLERANCE then
                            return settableMapID, settableX, settableY
                        end
                        lastReason = "roundtrip_delta"
                        lastA = "m=" .. tostring(settableMapID)
                        lastB = "d=" .. FormatSurrogateProjectionCoord(delta)
                    else
                        lastReason = "roundtrip_world_mismatch"
                        lastA = "m=" .. tostring(settableMapID)
                        lastB = "world=" .. tostring(roundTripWorldMapID or "-")
                    end
                else
                    lastReason = "invalid_surrogate_map"
                    lastA = "s=" .. tostring(settableMapID)
                    lastB = "p=" .. tostring(playerMapID)
                    lastC = "t=" .. tostring(targetMapID)
                end
            else
                lastReason = "candidate_not_settable"
                lastA = "m=" .. tostring(mapID)
            end
        else
            lastReason = "candidate_out_of_bounds"
            lastA = "m=" .. tostring(candidateMapID)
        end
    end

    return nil, nil, nil,
        lastReason or "map_coords_unavailable",
        "world=" .. tostring(worldMapID),
        "candidates=" .. candidateList,
        "point=" .. FormatSurrogateProjectionCoord(worldX) .. "," .. FormatSurrogateProjectionCoord(worldY),
        table.concat({ tostring(lastA or "-"), tostring(lastB or "-"), tostring(lastC or "-") }, "/")
end

function NS.ResolveWorldSpaceSurrogateUserWaypoint(targetMapID, targetX, targetY, surrogateDistance, preferredMapID)
    if type(targetMapID) ~= "number" or type(targetX) ~= "number" or type(targetY) ~= "number" then
        return FailSurrogateProjection("invalid_target")
    end
    if type(surrogateDistance) ~= "number" or surrogateDistance <= 0 then
        return FailSurrogateProjection("invalid_distance", tostring(surrogateDistance or "-"))
    end

    local playerMapID, playerX, playerY = NS.GetPlayerMapPosition()
    if type(playerMapID) ~= "number" or type(playerX) ~= "number" or type(playerY) ~= "number" then
        return FailSurrogateProjection("player_position_unavailable")
    end

    local playerWorldMapID, playerWorldX, playerWorldY = NS.GetWorldPositionFromMapCoords(playerMapID, playerX, playerY)
    local targetWorldMapID, targetWorldX, targetWorldY = NS.GetWorldPositionFromMapCoords(targetMapID, targetX, targetY)
    if type(playerWorldMapID) ~= "number" then
        return FailSurrogateProjection("player_world_unavailable", "p=" .. tostring(playerMapID))
    end
    if type(targetWorldMapID) ~= "number" then
        return FailSurrogateProjection("target_world_unavailable", "t=" .. tostring(targetMapID))
    end
    if playerWorldMapID ~= targetWorldMapID then
        return FailSurrogateProjection(
            "world_map_mismatch",
            "p=" .. tostring(playerMapID) .. "/" .. tostring(playerWorldMapID),
            "t=" .. tostring(targetMapID) .. "/" .. tostring(targetWorldMapID)
        )
    end

    local dx = targetWorldX - playerWorldX
    local dy = targetWorldY - playerWorldY
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance <= 0 then
        return FailSurrogateProjection("zero_distance")
    end

    local travelDistance = math.min(surrogateDistance, distance)
    local scale = travelDistance / distance
    local surrogateWorldX = playerWorldX + dx * scale
    local surrogateWorldY = playerWorldY + dy * scale

    local surrogateMapID, surrogateX, surrogateY,
    surrogateFailureReason, surrogateFailureA, surrogateFailureB, surrogateFailureC, surrogateFailureD =
        ResolveSurrogateMapCoordsFromWorldPosition(
            playerWorldMapID,
            surrogateWorldX,
            surrogateWorldY,
            targetMapID,
            playerMapID,
            preferredMapID
        )
    if type(surrogateMapID) ~= "number" or type(surrogateX) ~= "number" or type(surrogateY) ~= "number" then
        return FailSurrogateProjection(
            surrogateFailureReason or "map_coords_unavailable",
            surrogateFailureA,
            surrogateFailureB,
            surrogateFailureC,
            surrogateFailureD
        )
    end

    if not IsValidSurrogateMap(surrogateMapID, targetMapID, playerMapID) then
        return FailSurrogateProjection(
            "invalid_surrogate_map",
            "s=" .. tostring(surrogateMapID),
            "p=" .. tostring(playerMapID),
            "t=" .. tostring(targetMapID)
        )
    end

    return surrogateMapID, surrogateX, surrogateY, distance, surrogateWorldX, surrogateWorldY
end

-- ============================================================
-- Distance and user waypoint access
-- ============================================================

function NS.GetPlayerWorldDistance(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return
    end

    local playerMapID, playerX, playerY = NS.GetPlayerMapPosition()
    if type(playerMapID) ~= "number" or type(playerX) ~= "number" or type(playerY) ~= "number" then
        return
    end

    local playerWorldMapID, playerWorldX, playerWorldY = NS.GetWorldPositionFromMapCoords(playerMapID, playerX, playerY)
    local targetWorldMapID, targetWorldX, targetWorldY = NS.GetWorldPositionFromMapCoords(mapID, x, y)
    if type(playerWorldMapID) ~= "number"
        or type(targetWorldMapID) ~= "number"
        or playerWorldMapID ~= targetWorldMapID
    then
        return
    end

    local dx = targetWorldX - playerWorldX
    local dy = targetWorldY - playerWorldY
    local distance = math.sqrt(dx * dx + dy * dy)
    if type(distance) == "number" and distance > 0 then
        return distance
    end
end

function NS.GetCurrentUserWaypoint()
    if not (type(C_Map.HasUserWaypoint) == "function" and C_Map.HasUserWaypoint()) then
        return
    end

    local waypoint = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    if not waypoint or not waypoint.uiMapID or not waypoint.position then
        return
    end

    return waypoint.uiMapID, waypoint.position.x, waypoint.position.y
end

function NS.BuildUserWaypointPoint(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return
    end
    if type(CreateVector2D) ~= "function"
        or type(UiMapPoint) ~= "table"
        or type(UiMapPoint.CreateFromVector2D) ~= "function"
    then
        return
    end

    return UiMapPoint.CreateFromVector2D(mapID, CreateVector2D(x, y))
end

-- ============================================================
-- Coordinate utilities
-- ============================================================

function NS.StabilizeCoordForUserWaypoint(v)
    if type(v) ~= "number" then
        return v
    end

    v = v + C.USER_WAYPOINT_COORD_BIAS
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local _settableCacheInMapID, _settableCacheInX, _settableCacheInY
local _settableCacheOutMapID, _settableCacheOutX, _settableCacheOutY
local _settableCacheHasResult = false

function NS.InvalidateSettableUserWaypointCache()
    _settableCacheInMapID = nil
    _settableCacheInX = nil
    _settableCacheInY = nil
    _settableCacheOutMapID = nil
    _settableCacheOutX = nil
    _settableCacheOutY = nil
    _settableCacheHasResult = false
end

function NS.ResolveSettableUserWaypointTarget(mapID, x, y)
    local churn = NS.State.churn
    if churn and churn.active then
        churn.resolveSettableTarget = churn.resolveSettableTarget + 1
    end
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return
    end

    if mapID == _settableCacheInMapID and x == _settableCacheInX and y == _settableCacheInY then
        if _settableCacheHasResult then
            return _settableCacheOutMapID, _settableCacheOutX, _settableCacheOutY
        end
        return
    end

    _settableCacheInMapID = mapID
    _settableCacheInX = x
    _settableCacheInY = y
    _settableCacheHasResult = false
    _settableCacheOutMapID = nil
    _settableCacheOutX = nil
    _settableCacheOutY = nil

    if type(C_Map.CanSetUserWaypointOnMap) ~= "function" then
        _settableCacheOutMapID = mapID
        _settableCacheOutX = x
        _settableCacheOutY = y
        _settableCacheHasResult = true
        return mapID, x, y
    end

    if C_Map.CanSetUserWaypointOnMap(mapID) then
        _settableCacheOutMapID = mapID
        _settableCacheOutX = x
        _settableCacheOutY = y
        _settableCacheHasResult = true
        return mapID, x, y
    end

    if type(C_Map.GetMapInfo) ~= "function"
        or type(C_Map.GetWorldPosFromMapPos) ~= "function"
        or type(CreateVector2D) ~= "function"
    then
        return
    end

    local currentMapID, currentX, currentY = mapID, x, y
    for _ = 1, C.MAX_PARENT_MAP_DEPTH do
        -- Explicit placement invalidation must see the client's current parent and transform.
        local mapInfo = C_Map.GetMapInfo(currentMapID)
        local parentMapID = mapInfo and mapInfo.parentMapID
        if type(parentMapID) ~= "number" then
            NS.InvalidateSettableUserWaypointCache()
            return
        end
        if parentMapID == 0 then
            return
        end

        local _, childOrigin = C_Map.GetWorldPosFromMapPos(currentMapID, CreateVector2D(0, 0))
        local _, childRightEdge = C_Map.GetWorldPosFromMapPos(currentMapID, CreateVector2D(1, 0))
        local _, childBottomEdge = C_Map.GetWorldPosFromMapPos(currentMapID, CreateVector2D(0, 1))
        local _, parentOrigin = C_Map.GetWorldPosFromMapPos(parentMapID, CreateVector2D(0, 0))
        local _, parentRightEdge = C_Map.GetWorldPosFromMapPos(parentMapID, CreateVector2D(1, 0))
        local _, parentBottomEdge = C_Map.GetWorldPosFromMapPos(parentMapID, CreateVector2D(0, 1))
        if not (childOrigin and childRightEdge and childBottomEdge and parentOrigin and parentRightEdge and parentBottomEdge) then
            NS.InvalidateSettableUserWaypointCache()
            return
        end

        local worldX = childOrigin.x
            + currentX * (childRightEdge.x - childOrigin.x)
            + currentY * (childBottomEdge.x - childOrigin.x)
        local worldY = childOrigin.y
            + currentX * (childRightEdge.y - childOrigin.y)
            + currentY * (childBottomEdge.y - childOrigin.y)

        local offsetX = worldX - parentOrigin.x
        local offsetY = worldY - parentOrigin.y
        local parentBasisXx = parentRightEdge.x - parentOrigin.x
        local parentBasisYx = parentBottomEdge.x - parentOrigin.x
        local parentBasisXy = parentRightEdge.y - parentOrigin.y
        local parentBasisYy = parentBottomEdge.y - parentOrigin.y
        local determinant = parentBasisXx * parentBasisYy - parentBasisYx * parentBasisXy
        if determinant == 0 then
            return
        end

        local parentX = (offsetX * parentBasisYy - offsetY * parentBasisYx) / determinant
        local parentY = (offsetY * parentBasisXx - offsetX * parentBasisXy) / determinant
        local epsilon = C.COORD_BOUNDS_EPSILON
        if parentX < -epsilon or parentX > 1 + epsilon
            or parentY < -epsilon or parentY > 1 + epsilon
        then
            return
        end

        parentX = math.max(0, math.min(1, parentX))
        parentY = math.max(0, math.min(1, parentY))

        if C_Map.CanSetUserWaypointOnMap(parentMapID) then
            _settableCacheOutMapID = parentMapID
            _settableCacheOutX = parentX
            _settableCacheOutY = parentY
            _settableCacheHasResult = true
            return parentMapID, parentX, parentY
        end

        currentMapID, currentX, currentY = parentMapID, parentX, parentY
    end
end
