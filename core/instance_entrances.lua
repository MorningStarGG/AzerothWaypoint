-- ============================================================
-- Instance entrance routing
-- ============================================================
--
-- Resolves entrances for instance routes and identifies their travel icons.
-- The final waypoint keeps its interior coordinates. Blizzard entrance data
-- has priority over Farstrider data. The caller can retry when map information
-- is still unavailable.

local NS = _G.AzerothWaypointNS

local INSTANCE_ROUTE_TRAVEL_TYPES = {
    dungeon = true,
    raid = true,
    delve = true,
    bountiful_delve = true,
}

function NS.IsInstanceRouteTravelType(routeTravelType)
    return type(routeTravelType) == "string" and INSTANCE_ROUTE_TRAVEL_TYPES[routeTravelType] == true
end

-- Map classifications persist for the session. A missing map, parent or journal
-- response can become available on a later lookup.
local routeInstanceInfoCache = {}

-- ============================================================
-- Map classification
-- ============================================================

local function GetRouteInstanceInfo(destinationMapID)
    if type(destinationMapID) ~= "number" or destinationMapID <= 0 then
        return nil
    end

    local cached = routeInstanceInfoCache[destinationMapID]
    if cached ~= nil then
        return cached or nil
    end

    local mapInfo = C_Map.GetMapInfo and C_Map.GetMapInfo(destinationMapID)
    if not mapInfo or not mapInfo.mapType then return nil end
    local mapType = mapInfo.mapType
    if mapType ~= Enum.UIMapType.Dungeon and mapType ~= Enum.UIMapType.Micro then
        routeInstanceInfoCache[destinationMapID] = false
        return nil
    end
    local parentMapID = mapInfo.parentMapID
    if type(parentMapID) ~= "number" or parentMapID <= 0 then return nil end

    local journalInstanceID = EJ_GetInstanceForMap and EJ_GetInstanceForMap(destinationMapID) or nil
    if type(journalInstanceID) ~= "number" or journalInstanceID <= 0 then
        return {
            parentMapID = parentMapID,
            name = mapInfo.name,
            mapType = mapType,
        }
    end

    local instanceName = nil
    local isRaid = false
    if EJ_GetInstanceInfo then
        local _, _, _, _, _, _, _, _, _, _, _, raidFlag
        instanceName, _, _, _, _, _, _, _, _, _, _, raidFlag = EJ_GetInstanceInfo(journalInstanceID)
        isRaid = raidFlag == true
    end

    local info = {
        travelType = isRaid and "raid" or "dungeon",
        parentMapID = parentMapID,
        journalInstanceID = journalInstanceID,
        name = instanceName,
        mapType = mapType,
    }
    if type(instanceName) == "string" and instanceName ~= "" then
        routeInstanceInfoCache[destinationMapID] = info
    end
    return info
end

local AREA_POI_COORD_EPSILON = 0.0025
local ROUTE_INSTANCE_ENTRANCE_COORD_EPSILON = 0.025

local ReadMapPositionCoords = NS.Internal.ReadMapPositionCoords

local function CheckDelvePoiCoordProof(parentMapID, liveMapID, liveX, liveY, expectedPoiID)
    if type(parentMapID) ~= "number" or parentMapID <= 0 then
        return false
    end
    if type(liveMapID) ~= "number" or liveMapID ~= parentMapID then
        return false
    end
    if type(liveX) ~= "number" or type(liveY) ~= "number" then
        return false
    end
    if type(C_AreaPoiInfo) ~= "table"
        or type(C_AreaPoiInfo.GetDelvesForMap) ~= "function"
        or type(C_AreaPoiInfo.GetAreaPOIInfo) ~= "function"
    then
        return false
    end

    expectedPoiID = type(expectedPoiID) == "number" and expectedPoiID > 0 and expectedPoiID or nil

    local delvePOIs = C_AreaPoiInfo.GetDelvesForMap(parentMapID)
    if type(delvePOIs) ~= "table" or #delvePOIs == 0 then
        return false
    end

    local matchCount = 0
    for _, poiID in ipairs(delvePOIs) do
        if not expectedPoiID or poiID == expectedPoiID then
            local poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(parentMapID, poiID)
            local poiX, poiY = ReadMapPositionCoords(poiInfo and poiInfo.position)
            if type(poiX) == "number"
                and type(poiY) == "number"
                and math.abs(poiX - liveX) <= AREA_POI_COORD_EPSILON
                and math.abs(poiY - liveY) <= AREA_POI_COORD_EPSILON
            then
                if expectedPoiID then
                    return true
                end
                matchCount = matchCount + 1
                if matchCount > 1 then
                    return false
                end
            end
        end
    end

    return matchCount == 1
end

-- ============================================================
-- Encounter Journal entrances
-- ============================================================

local function ResolveJournalInstanceTravelType(journalInstanceID)
    if type(journalInstanceID) ~= "number" or journalInstanceID <= 0 then
        return nil
    end

    if type(EJ_GetInstanceInfo) ~= "function" then
        return "dungeon"
    end

    local _, _, _, _, _, _, _, _, _, _, _, isRaid = EJ_GetInstanceInfo(journalInstanceID)
    return isRaid == true and "raid" or "dungeon"
end

local function GetDungeonEntrancesForMap(mapID)
    if type(mapID) ~= "number" or mapID <= 0 then
        return nil
    end
    if type(C_EncounterJournal) ~= "table" or type(C_EncounterJournal.GetDungeonEntrancesForMap) ~= "function" then
        return nil
    end

    local ok, entrances = pcall(C_EncounterJournal.GetDungeonEntrancesForMap, mapID)
    if not ok or type(entrances) ~= "table" or #entrances == 0 then
        return nil
    end
    return entrances
end

local function FindJournalInstanceEntrance(parentMapID, journalInstanceID)
    if type(parentMapID) ~= "number" or parentMapID <= 0 then
        return nil
    end
    if type(journalInstanceID) ~= "number" or journalInstanceID <= 0 then
        return nil
    end

    local entrances = GetDungeonEntrancesForMap(parentMapID)
    if type(entrances) ~= "table" then
        return nil
    end

    local matched
    for _, entrance in ipairs(entrances) do
        if type(entrance) == "table" and entrance.journalInstanceID == journalInstanceID then
            local entranceX, entranceY = ReadMapPositionCoords(entrance.position)
            if type(entranceX) == "number" and type(entranceY) == "number" then
                if matched then
                    return nil
                end
                matched = {
                    mapID = parentMapID,
                    x = entranceX,
                    y = entranceY,
                    journalInstanceID = journalInstanceID,
                    name = entrance.name,
                    areaPoiID = entrance.areaPoiID,
                }
            end
        end
    end

    return matched
end

local function CoordsMatch(mapID, x, y, targetMapID, targetX, targetY, epsilon)
    return type(mapID) == "number"
        and type(x) == "number"
        and type(y) == "number"
        and type(targetMapID) == "number"
        and type(targetX) == "number"
        and type(targetY) == "number"
        and mapID == targetMapID
        and math.abs(x - targetX) <= epsilon
        and math.abs(y - targetY) <= epsilon
end

local function MatchesJournalInstanceEntrance(parentMapID, x, y, journalInstanceID, epsilon)
    if type(parentMapID) ~= "number" or type(journalInstanceID) ~= "number" then
        return false
    end
    local entrances = GetDungeonEntrancesForMap(parentMapID)
    if type(entrances) ~= "table" then
        return false
    end
    for _, entrance in ipairs(entrances) do
        if type(entrance) == "table" and entrance.journalInstanceID == journalInstanceID then
            local entranceX, entranceY = ReadMapPositionCoords(entrance.position)
            if CoordsMatch(parentMapID, x, y, parentMapID, entranceX, entranceY, epsilon) then
                return true
            end
        end
    end
    return false
end

local function ResolveInstanceEntranceTravelType(mapID, x, y)
    if type(mapID) ~= "number" or mapID <= 0 or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end

    local entrances = GetDungeonEntrancesForMap(mapID)
    if type(entrances) ~= "table" then
        return nil
    end

    local matchedTravelType
    for _, entrance in ipairs(entrances) do
        if type(entrance) == "table" then
            local entranceX, entranceY = ReadMapPositionCoords(entrance.position)
            if type(entranceX) == "number"
                and type(entranceY) == "number"
                and math.abs(entranceX - x) <= AREA_POI_COORD_EPSILON
                and math.abs(entranceY - y) <= AREA_POI_COORD_EPSILON
            then
                local travelType = ResolveJournalInstanceTravelType(entrance.journalInstanceID)
                if type(travelType) ~= "string" then
                    return nil
                end
                if matchedTravelType and matchedTravelType ~= travelType then
                    return nil
                end
                matchedTravelType = travelType
            end
        end
    end

    return matchedTravelType
end

-- ============================================================
-- Delve and Farstrider entrance lookup
-- ============================================================

local function NormalizeInstanceName(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:gsub("^the%s+", "")
    value = value:gsub("[%p%s]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function ResolveDelveRouteEntrance(instanceInfo, title)
    if type(instanceInfo) ~= "table"
        or type(instanceInfo.parentMapID) ~= "number"
        or type(C_AreaPoiInfo) ~= "table"
        or type(C_AreaPoiInfo.GetDelvesForMap) ~= "function"
        or type(C_AreaPoiInfo.GetAreaPOIInfo) ~= "function"
    then
        return nil
    end

    local wantedName = NormalizeInstanceName(instanceInfo.name) or NormalizeInstanceName(title)
    if not wantedName then
        return nil
    end

    local delvePOIs = C_AreaPoiInfo.GetDelvesForMap(instanceInfo.parentMapID)
    if type(delvePOIs) ~= "table" or #delvePOIs == 0 then
        return nil
    end

    local matched
    for _, poiID in ipairs(delvePOIs) do
        local poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(instanceInfo.parentMapID, poiID)
        local poiName = NormalizeInstanceName(poiInfo and poiInfo.name)
        if poiName and poiName == wantedName then
            local poiX, poiY = ReadMapPositionCoords(poiInfo.position)
            if type(poiX) == "number" and type(poiY) == "number" then
                if matched then
                    return nil
                end
                matched = {
                    mapID = instanceInfo.parentMapID,
                    x = poiX,
                    y = poiY,
                    areaPoiID = poiID,
                    name = poiInfo.name,
                    atlasName = poiInfo.atlasName,
                }
            end
        end
    end

    return matched
end

local function FindFarstriderInstanceEntrance(instanceInfo, mapID, x, y)
    local api = rawget(_G, "FarstriderLibData_API")
    local lookup = type(api) == "table" and rawget(api, "GetInstanceEntrance")
    if type(lookup) ~= "function" or (not instanceInfo.journalInstanceID and instanceInfo.mapType ~= Enum.UIMapType.Dungeon)
        or not NS.GetWorldPositionFromMapCoords or not NS.ResolveUserWaypointMapCoordsFromWorldPosition
        or not C_Map.GetMapPosFromWorldPos or not CreateVector2D then
        return
    end

    local ok, gameMap, wx, wy = pcall(NS.GetWorldPositionFromMapCoords, mapID, x, y)
    if not ok or issecretvalue and (issecretvalue(gameMap) or issecretvalue(wx) or issecretvalue(wy))
        or type(gameMap) ~= "number" or gameMap <= 1 or type(wx) ~= "number" or type(wy) ~= "number" then
        return
    end
    if IsInInstance and IsInInstance() and GetInstanceInfo then
        local current = select(8, GetInstanceInfo())
        if not (issecretvalue and issecretvalue(current)) and current == gameMap then return end
    end
    local mapped, returnedMap, pos = pcall(C_Map.GetMapPosFromWorldPos, gameMap, CreateVector2D(wx, wy), mapID)
    if not mapped or returnedMap ~= mapID then return end
    local rx, ry = ReadMapPositionCoords(pos)
    if not rx or not ry or math.abs(rx - x) > AREA_POI_COORD_EPSILON or math.abs(ry - y) > AREA_POI_COORD_EPSILON then return end

    local journalLookup = C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap
    if instanceInfo.journalInstanceID and type(journalLookup) == "function" then
        local found, id = pcall(journalLookup, gameMap)
        if not found or id ~= instanceInfo.journalInstanceID then return end
    end

    local found, entrance = pcall(lookup, gameMap)
    if not found or type(entrance) ~= "table" or type(entrance.pos) ~= "table"
        or type(entrance.mapId) ~= "number" or entrance.mapId == gameMap
        or type(entrance.pos.x) ~= "number" or type(entrance.pos.y) ~= "number" then
        return
    end

    local projected, exterior, px, py = pcall(NS.ResolveUserWaypointMapCoordsFromWorldPosition,
        entrance.pos.x, entrance.pos.y, entrance.uiMapHint, entrance.mapId)
    if not projected or not exterior then return end
    local info = C_Map.GetMapInfo(exterior)
    if not info or not info.mapType or info.mapType > Enum.UIMapType.Zone or info.mapType < Enum.UIMapType.Continent then return end
    local exteriorMap, exteriorX, exteriorY = NS.GetWorldPositionFromMapCoords(exterior, px, py)
    if exteriorMap ~= entrance.mapId or not exteriorX or not exteriorY
        or math.abs(exteriorX - entrance.pos.x) > 5 or math.abs(exteriorY - entrance.pos.y) > 5 then
        return
    end
    return { mapID = exterior, x = px, y = py, name = instanceInfo.name }
end

-- ============================================================
-- Route destinations and travel icons
-- ============================================================

function NS.ResolveInstanceRouteIntent(destinationMapID, destinationX, destinationY, title)
    local instanceInfo = GetRouteInstanceInfo(destinationMapID)
    if type(instanceInfo) ~= "table" then
        return nil
    end

    local travelType = instanceInfo.travelType
    local entrance = nil
    if type(instanceInfo.journalInstanceID) == "number" and instanceInfo.journalInstanceID > 0 then
        entrance = FindJournalInstanceEntrance(instanceInfo.parentMapID, instanceInfo.journalInstanceID)
    else
        entrance = ResolveDelveRouteEntrance(instanceInfo, title)
        if type(entrance) == "table" then
            travelType = entrance.atlasName == "delves-bountiful" and "bountiful_delve" or "delve"
        end
    end

    if not entrance then
        entrance = FindFarstriderInstanceEntrance(instanceInfo, destinationMapID, destinationX, destinationY)
    end
    if type(entrance) ~= "table" then
        return nil
    end

    return {
        kind = "instance",
        travelType = travelType or "dungeon",
        parentMapID = instanceInfo.parentMapID,
        journalInstanceID = instanceInfo.journalInstanceID,
        areaPoiID = entrance.areaPoiID,
        instanceName = instanceInfo.name or entrance.name,
        final = {
            mapID = destinationMapID,
            x = destinationX,
            y = destinationY,
            title = title,
        },
        entrance = entrance,
    }
end

function NS.ResolveAreaPoiTravelType(mapID, x, y, areaPoiID)
    local instanceTravelType = ResolveInstanceEntranceTravelType(mapID, x, y)
    if type(instanceTravelType) == "string" then
        return instanceTravelType
    end

    if CheckDelvePoiCoordProof(mapID, mapID, x, y, areaPoiID)
        or CheckDelvePoiCoordProof(mapID, mapID, x, y)
    then
        if type(areaPoiID) == "number" and type(C_AreaPoiInfo.GetAreaPOIInfo) == "function" then
            local poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(mapID, areaPoiID)
            if type(poiInfo) == "table" and poiInfo.atlasName == "delves-bountiful" then
                return "bountiful_delve"
            end
        end
        return "delve"
    end
end

function NS.ResolveInstanceDestinationTravelType(destinationMapID, liveMapID, liveX, liveY, legKind)
    local instanceInfo = GetRouteInstanceInfo(destinationMapID)
    if type(instanceInfo) ~= "table" then
        return nil
    end
    if type(liveMapID) ~= "number" then
        return nil
    end

    local journalInstanceID = instanceInfo.journalInstanceID
    local hasJournalInstance = type(journalInstanceID) == "number" and journalInstanceID > 0

    if legKind == "destination" then
        if liveMapID ~= destinationMapID then
            return nil
        end
        if not hasJournalInstance then
            return nil
        end
    elseif legKind == "carrier" then
        if liveMapID ~= instanceInfo.parentMapID then
            return nil
        end
        if not hasJournalInstance then
            if not CheckDelvePoiCoordProof(instanceInfo.parentMapID, liveMapID, liveX, liveY) then
                return nil
            end
            return "delve", instanceInfo.parentMapID, nil, instanceInfo.name
        end
        if not MatchesJournalInstanceEntrance(
                instanceInfo.parentMapID,
                liveX,
                liveY,
                journalInstanceID,
                ROUTE_INSTANCE_ENTRANCE_COORD_EPSILON
            ) then
            return nil
        end
    else
        return nil
    end

    return instanceInfo.travelType, instanceInfo.parentMapID, journalInstanceID, instanceInfo.name
end
