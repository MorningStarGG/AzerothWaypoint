-- ============================================================
-- Shared route leg helpers
-- ============================================================
--
-- Builds route legs and compares walking endpoints for the travel backends.

local NS = _G.AzerothWaypointNS

-- ============================================================
-- Shared route presentation helpers
-- ============================================================

local RouteSpecials = NS.RouteSpecials or {}
NS.RouteSpecials = RouteSpecials

-- Each call owns a fresh scalar-only endpoint. Backend-specific travel kinds,
-- radii, metadata and endpoint merge rules remain with that backend.
function RouteSpecials.MakeDestinationLeg(source, mapID, x, y, title)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return nil end
    return {
        mapID = mapID,
        x = x,
        y = y,
        title = title,
        source = source,
        kind = "destination",
        routeLegKind = "destination"
    }
end

local function EndpointNumber(value)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
        and value == value and math.abs(value) < math.huge
end

-- Destination height is optional, in the same world frame as the planner.
-- An authored height of zero is valid, an unreadable player height is not.
function RouteSpecials.GetNavigationHeight(record)
    if type(record) ~= "table" then return end
    local target = type(record.target) == "table" and record.target
        or type(record.destination) == "table" and record.destination
        or type(record.meta) == "table" and record.meta or record
    local height, continent = target.navigationHeight, target.navigationContinent
    if not EndpointNumber(height) or not EndpointNumber(continent) then
        height, continent = record.navigationHeight, record.navigationContinent
    end
    if EndpointNumber(height) and EndpointNumber(continent) then return height, continent end
end

local function SameWorldEndpoint(c, x, y, goalC, goalX, goalY)
    if not EndpointNumber(c) or not EndpointNumber(goalC) or c ~= goalC
        or not EndpointNumber(x) or not EndpointNumber(y)
        or not EndpointNumber(goalX) or not EndpointNumber(goalY) then
        return false
    end
    -- Numerical identity, in yards, never an arrival radius or a path shortcut.
    return (x - goalX) ^ 2 + (y - goalY) ^ 2 <= 0.1 ^ 2
end

-- Final-walk reconciliation is shared by planner adapters. Prefer the copied
-- world goal used by the search over a lossy world-to-map round trip. Callers
-- retain transport actions, required stops and the exact requested map point.
function RouteSpecials.SameWalkingEndpoint(point, destination, worldPoint, worldDestination)
    if type(point) ~= "table" or type(destination) ~= "table"
        or not EndpointNumber(point.mapID) or not EndpointNumber(destination.mapID) or point.mapID ~= destination.mapID
        or not EndpointNumber(point.x) or not EndpointNumber(point.y)
        or not EndpointNumber(destination.x) or not EndpointNumber(destination.y) then
        return false
    end
    if type(worldPoint) == "table" and type(worldDestination) == "table" then
        if EndpointNumber(worldPoint.z) and EndpointNumber(worldDestination.z)
            and math.abs(worldPoint.z - worldDestination.z) > 0.1 then
            return false
        end
        return SameWorldEndpoint(worldPoint.c, worldPoint.wx, worldPoint.wy,
            worldDestination.c, worldDestination.wx, worldDestination.wy)
    end
    if point.x == destination.x and point.y == destination.y then return true end
    local project = NS.GetWorldPositionFromMapCoords
    if type(project) == "function" then
        local ok, c, x, y = pcall(project, point.mapID, point.x, point.y)
        local goalOK, goalC, goalX, goalY = pcall(project, destination.mapID, destination.x, destination.y)
        if ok and goalOK and EndpointNumber(c) and EndpointNumber(goalC)
            and EndpointNumber(x) and EndpointNumber(y) and EndpointNumber(goalX) and EndpointNumber(goalY) then
            return SameWorldEndpoint(c, x, y, goalC, goalX, goalY)
        end
    end
    -- Without projection data, recognize only ordinary Lua arithmetic noise.
    -- Missing map data must never turn a nearby route point into the goal.
    return math.abs(point.x - destination.x) <= 0.0000000001
        and math.abs(point.y - destination.y) <= 0.0000000001
end

function NS.IsActiveRouteRecord(record, allowPendingManual)
    if type(record) ~= "table" then return false end
    if record._routePlanAttempt then return record._routePlanAttempt:IsCurrent() end
    return NS.GetActiveAuthorityRecord() == record
        or allowPendingManual == true and NS.State.routing.pendingManualAuthority == record
end

-- A reduced itinerary is revalidated against full travel eligibility after combat.
RouteSpecials.COMBAT_TRAVEL_STATE = "combat"

-- Planner results never publish navigation. The coordinator owns acceptance,
-- queue completion and handoff, reason strings are diagnostic text only.
function RouteSpecials.CompletePlan(record, backendID, status, legs, reason, serial, mode)
    return record._routePlanAttempt:Complete({
        backendID = backendID,
        status = status,
        legs = legs,
        reason = reason,
        serial = serial,
        mode = mode
    })
end

-- ============================================================
-- Hearthstones and the Stormwind portal room
-- ============================================================

local HEARTHSTONE_ITEM_ID = 6948
local STORMWIND_MAP_ID = 84
local WIZARDS_SANCTUM_AREA_ID = 10523
local WIZARDS_SANCTUM_FALLBACK_NAME = "Wizard's Sanctum"
local MAGE_TOWER_ENTRY_FALLBACK = {
    mapID = STORMWIND_MAP_ID,
    x = 0.4951,
    y = 0.8666,
}

RouteSpecials.STORMWIND_MAP_ID = STORMWIND_MAP_ID

local function TextEquals(left, right)
    return type(left) == "string" and not (issecretvalue and issecretvalue(left)) and left ~= "" and left == right
end

function RouteSpecials.IsHearthstoneItemID(itemID)
    return tonumber(itemID) == HEARTHSTONE_ITEM_ID
end

function RouteSpecials.GetWizardsSanctumName()
    local name = type(C_Map) == "table"
        and type(C_Map.GetAreaInfo) == "function"
        and C_Map.GetAreaInfo(WIZARDS_SANCTUM_AREA_ID)
        or nil
    return type(name) == "string" and name ~= "" and name or WIZARDS_SANCTUM_FALLBACK_NAME
end

function RouteSpecials.IsPlayerInWizardsSanctum()
    local sanctumName = RouteSpecials.GetWizardsSanctumName()
    return TextEquals(type(GetSubZoneText) == "function" and GetSubZoneText() or nil, sanctumName)
        or TextEquals(type(GetMinimapZoneText) == "function" and GetMinimapZoneText() or nil, sanctumName)
end

function RouteSpecials.PlayerNeedsWizardsSanctumEntry(location)
    local locationMapID = type(location) == "table" and location.mapID or nil
    local playerMapID = type(NS.GetPlayerMapID) == "function" and NS.GetPlayerMapID() or nil
    return (locationMapID == STORMWIND_MAP_ID or playerMapID == STORMWIND_MAP_ID)
        and not RouteSpecials.IsPlayerInWizardsSanctum()
end

function RouteSpecials.MakeWizardsSanctumArrivalGate()
    return {
        indoors = true,
        subzone = RouteSpecials.GetWizardsSanctumName(),
    }
end

function RouteSpecials.GetMageTowerEntryFallback()
    return MAGE_TOWER_ENTRY_FALLBACK.mapID, MAGE_TOWER_ENTRY_FALLBACK.x, MAGE_TOWER_ENTRY_FALLBACK.y
end

function RouteSpecials.CoordsMatch(mapID, x, y, targetMapID, targetX, targetY, epsilon)
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

function RouteSpecials.IsMageTowerEntryLeg(leg, mapID, x, y, epsilon)
    if type(leg) ~= "table" then
        return false
    end
    if leg.kind == "entrance" then
        return true
    end
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        mapID, x, y = RouteSpecials.GetMageTowerEntryFallback()
    end
    return RouteSpecials.CoordsMatch(leg.mapID, leg.x, leg.y, mapID, x, y, epsilon)
end

function RouteSpecials.MarkMageTowerEntryLeg(leg, title)
    if type(leg) ~= "table" then
        return
    end
    leg.kind = "entrance"
    leg.routeLegKind = "carrier"
    leg.routeTravelType = "travel"
    leg.arrivalRadius = 15
    leg.title = leg.title or title or "Enter the Mage Tower"
    leg.specialAction = nil
    leg.activationCoords = nil
end

function RouteSpecials.MakeMageTowerEntryLeg(source, mapID, x, y, title)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        mapID, x, y = RouteSpecials.GetMageTowerEntryFallback()
    end
    return {
        mapID = mapID,
        x = x,
        y = y,
        kind = "entrance",
        routeLegKind = "carrier",
        title = title or "Enter the Mage Tower",
        source = source,
        routeTravelType = "travel",
        arrivalRadius = 15,
    }
end

function RouteSpecials.EnsureMageTowerEntryBeforeWizardsSanctumLeg(legs, source, mapID, x, y, isEntryLeg)
    if type(legs) ~= "table" then
        return
    end
    local previous = legs[#legs]
    local isPreviousEntry = type(isEntryLeg) == "function"
        and isEntryLeg(previous)
        or RouteSpecials.IsMageTowerEntryLeg(previous, mapID, x, y, 0.025)
    if isPreviousEntry then
        RouteSpecials.MarkMageTowerEntryLeg(previous)
        return
    end
    legs[#legs + 1] = RouteSpecials.MakeMageTowerEntryLeg(source, mapID, x, y)
end

-- ============================================================
-- Wizard's Sanctum crossings
-- ============================================================

-- These are physical boundaries in Stormwind. Provider waypoints and graph
-- data stay in their adapters. In Forever the lower chamber shares the city
-- map with the tower, but its receiving floor is far below the upper portal.
local Sanctum = {}
RouteSpecials.Sanctum = Sanctum
local RETAIL_STORMWIND, FOREVER_STORMWIND = 84, 1453
local function Crossing(id, mapID, from, to, x, y, title)
    return { id = id, mapID = mapID, from = from, to = to, x = x, y = y, title = title }
end
local retailEntry = Crossing("retail_tower_entry", RETAIL_STORMWIND, "street", "inside",
    MAGE_TOWER_ENTRY_FALLBACK.x, MAGE_TOWER_ENTRY_FALLBACK.y, "Enter the Mage Tower")
local retailExit = Crossing("retail_tower_exit", RETAIL_STORMWIND, "inside", "street",
    .4921, .8709, "Exit the Mage Tower")
local foreverEntry = Crossing("forever_tower_entry", FOREVER_STORMWIND, "street", "inside",
    .4944, .8677, "Enter the Mage Tower")
local foreverExit = Crossing("forever_tower_exit", FOREVER_STORMWIND, "inside", "street",
    .4936, .8693, "Exit the Mage Tower")
local descend = Crossing("forever_chamber_entry", FOREVER_STORMWIND, "tower", "chamber",
    .4848, .8842, "Take the portal to the Wizard's Sanctum")
descend.height = 148.6
local ascend = Crossing("forever_chamber_exit", FOREVER_STORMWIND, "chamber", "tower",
    .4780, .8870, "Take the portal back to the Mage Tower")
ascend.height = 29.6

local function CityMap()
    return NS.IsWoWForever and NS.IsWoWForever() and FOREVER_STORMWIND or RETAIL_STORMWIND
end

local function InChamberFootprint(continent, x, y)
    return EndpointNumber(continent) and continent == 0 and EndpointNumber(x) and EndpointNumber(y)
        and x >= -9030 and x <= -8975 and y >= 840 and y <= 900
end

local function HeightPlace(continent, x, y, z)
    if not InChamberFootprint(continent, x, y) or not EndpointNumber(z) then return end
    if z >= 10 and z <= 50 then return "chamber" end
    if z >= 130 and z <= 170 then return "tower" end
end

local function PlayerPlace(mapID, outsideCity)
    if not NS.GetPlayerMapID then return end
    local map = NS.GetPlayerMapID()
    if not EndpointNumber(map) then return end
    if map ~= mapID then
        if outsideCity then return "street" end
        return
    end
    local indoor = RouteSpecials.IsPlayerInWizardsSanctum()
    if mapID == FOREVER_STORMWIND and type(UnitPosition) == "function" then
        local ok, x, y, z, continent = pcall(UnitPosition, "player")
        if ok then
            local place = HeightPlace(continent, x, y, z)
            if place == "chamber" or place == "tower" and indoor then return place end
        end
    end
    if indoor then return "inside" end
    local name = type(GetSubZoneText) == "function" and GetSubZoneText() or nil
    if type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= ""
        and type(IsOutdoors) == "function" and IsOutdoors() == true then
        return "street"
    end
end

local function AtPlace(place, wanted)
    return place ~= nil and (place == wanted
        or wanted == "inside" and (place == "tower" or place == "chamber"))
end

function Sanctum.HasArrived(crossing)
    return AtPlace(PlayerPlace(crossing.mapID), crossing.to)
end

function Sanctum.AtDestination(place)
    return AtPlace(PlayerPlace(CityMap()), place)
end

function Sanctum.ForeverDoorway(entering)
    return entering and foreverEntry or foreverExit
end

local foreverPortalArrival = Crossing("forever_tower_portal_arrival", FOREVER_STORMWIND, "remote", "inside")
function Sanctum.ForeverPortalArrival()
    return foreverPortalArrival
end

function Sanctum.ForeverChamber(entering)
    return entering and descend or ascend
end

function Sanctum.SetCrossing(leg, crossing)
    leg.sanctumCrossing = crossing
    leg.preservePlanOnArrival = true
end

function Sanctum.MakeCrossingLeg(source, crossing)
    local kind = crossing.to == "chamber" or crossing.from == "chamber"
    local leg = {
        mapID = crossing.mapID,
        x = crossing.x,
        y = crossing.y,
        title = crossing.title,
        kind = kind and "portal" or "entrance",
        routeLegKind = "carrier",
        routeTravelType = kind and "portal" or "travel",
        source = source,
    }
    Sanctum.SetCrossing(leg, crossing)
    leg.sanctumResume = true
    return leg
end

function Sanctum.DestinationPlace(owner, mapID, x, y)
    if mapID ~= CityMap() then return end
    local target = owner.target or owner.destination or owner
    -- This trainer's coordinates in Forever vary slightly by guide. The
    -- entity and point must agree so another step for the same quest stays put.
    if mapID == FOREVER_STORMWIND and target.navigationNpcID == 5497
        and math.abs(x - .4936) <= .004 and math.abs(y - .8592) <= .002 then
        return "chamber"
    end
    if mapID == RETAIL_STORMWIND then
        if target.navigationNpcID == 216129
            and math.abs(x - .4865) <= .001 and math.abs(y - .8700) <= .001 then
            return "inside"
        end
        return
    end
    local z, continent = RouteSpecials.GetNavigationHeight(owner)
    if z == nil or not NS.GetWorldPositionFromMapCoords then return end
    local c, wx, wy = NS.GetWorldPositionFromMapCoords(mapID, x, y)
    if c == continent then return HeightPlace(c, wx, wy, z) end
end

-- An authored portal arriving inside is also a crossing. Simulating native
-- legs in order keeps the real approach and avoids adding a second doorway.
function Sanctum.FindMissingCrossing(wanted, mapID, legs)
    local city = CityMap()
    local playerMap = NS.GetPlayerMapID and NS.GetPlayerMapID()
    local canNeedExit = city == FOREVER_STORMWIND and EndpointNumber(playerMap) and playerMap == city and mapID ~= city
    if wanted == nil and canNeedExit then wanted = "street" end
    if wanted == nil then
        for _, leg in ipairs(legs) do
            if leg.sanctumDeparture then
                wanted = false; break
            end
        end
        if wanted == nil then return end
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    local place = PlayerPlace(city, true)
    if not place then return end
    local function NextCrossing(needed)
        if not needed or AtPlace(place, needed) then return end
        if place == "street" then return city == FOREVER_STORMWIND and foreverEntry or retailEntry end
        if place == "tower" and needed == "chamber" then return descend end
        if place == "chamber" then return ascend end
        if needed == "street" then return city == FOREVER_STORMWIND and foreverExit or retailExit end
    end
    local previousCrossing
    for index, leg in ipairs(legs) do
        local crossing = leg.sanctumCrossing
        local needed = leg.sanctumDeparture
        if needed then
            local missing = NextCrossing(needed)
            if missing then return missing, previousCrossing end
        end
        if crossing then
            place = (crossing == foreverEntry or crossing == foreverPortalArrival) and "tower" or crossing.to
            previousCrossing = index
        elseif canNeedExit and (leg.kind == "spell" or leg.kind == "hearthstone")
            and leg.specialAction and leg.specialAction.activationMode == "portable" then
            -- A usable portable action can depart from inside. Leave its
            -- exit and onward itinerary to the selected planner.
            return
        end
    end
    return NextCrossing(wanted), previousCrossing
end
