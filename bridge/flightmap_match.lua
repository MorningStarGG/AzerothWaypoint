-- ============================================================
-- Flight route matching
-- ============================================================
--
-- Matches the active route to a reachable node in the current taxi window.
-- Backend instructions take precedence over guide suggestions. Matching
-- selects an offer without drawing a marker or taking the flight.

local NS = _G.AzerothWaypointNS
local state = NS.State
local TaxiWindow = NS.Internal.TaxiWindow

-- ============================================================
-- Destination names and taxi node identity
-- ============================================================

local STRONG_MATCH_EPSILON = type(NS.GetTaxiCoordEpsilon) == "function" and NS.GetTaxiCoordEpsilon() or 0.0015
local GENERIC_TITLE_PATTERNS = {
    "^talk to the flight master$",
    "^talk to flight master$",
    "^take flight to$",
    "^take a flight to$",
    "^take the flight to$",
    "^fly to$",
    "^flight path$",
    "^flightpath$",
    "^taxi$",
    "^travel$",
    "^go to$",
    "^follow the path$",
}

local function TrimString(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function StripDisplayMarkup(value)
    value = TrimString(value)
    if not value then
        return nil
    end
    value = value:gsub("|c%x%x%x%x%x%x%x%x", "")
    value = value:gsub("|r", "")
    value = value:gsub("|T.-|t", "")
    value = value:gsub("|A.-|a", "")
    value = value:gsub("|H.-|h(.-)|h", "%1")
    value = value:gsub("|K.-|k", "")
    return TrimString(value)
end

local function NormalizeName(value)
    value = StripDisplayMarkup(value)
    if not value then
        return nil
    end
    value = value:lower()
    value = value:gsub("%b()", " ")
    value = value:gsub("[%[%]{}<>\"'`]", " ")
    value = value:gsub("[,;:%.%!%?]", " ")
    value = value:gsub("%s+", " ")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function IsCoordinateTitle(value)
    value = StripDisplayMarkup(value)
    if not value then
        return false
    end
    if value:match("^%s*[%d%.]+%s*,%s*[%d%.]+%s*$") then
        return true
    end
    if value:match("^%s*[%d%.]+%s+[%d%.]+%s*$") then
        return true
    end
    return false
end

local function GetUsableDestinationName(title)
    local normalized = NormalizeName(title)
    if not normalized or IsCoordinateTitle(title) then
        return nil
    end
    for index = 1, #GENERIC_TITLE_PATTERNS do
        if normalized:find(GENERIC_TITLE_PATTERNS[index]) then
            return nil
        end
    end
    normalized = normalized:gsub("^take flight to%s+", "")
    normalized = normalized:gsub("^take a flight to%s+", "")
    normalized = normalized:gsub("^take the flight to%s+", "")
    normalized = normalized:gsub("^fly to%s+", "")
    normalized = normalized:gsub("^taxi to%s+", "")
    normalized = normalized:gsub("^go to%s+", "")
    normalized = normalized:gsub("^travel to%s+", "")
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" or normalized:match("^%d+$") then
        return nil
    end
    return normalized
end

local function NamesAgree(titleName, nodeName)
    local node = NormalizeName(nodeName)
    if not titleName or not node then
        return false
    end
    return titleName == node
        or titleName:find(node, 1, true) ~= nil
        or node:find(titleName, 1, true) ~= nil
end

local function IsTaxiLeg(leg)
    if type(leg) ~= "table" then
        return false
    end
    return type(leg.taxi) == "table"
        or leg.kind == "taxi"
        or leg.routeTravelType == "taxi"
end

local function CoordsClose(aX, aY, bX, bY)
    return type(aX) == "number"
        and type(aY) == "number"
        and type(bX) == "number"
        and type(bY) == "number"
        and math.abs(aX - bX) <= STRONG_MATCH_EPSILON
        and math.abs(aY - bY) <= STRONG_MATCH_EPSILON
end

local function MatchLeg(displayedMapID, leg, reachable, reachableByID)
    if type(leg) ~= "table" then
        return nil
    end

    local taxi = type(leg.taxi) == "table" and leg.taxi or nil
    local nodeID = taxi and tonumber(taxi.nodeID) or nil
    if nodeID then
        local node = reachableByID[nodeID]
        if node then
            return {
                confidence = "exact",
                leg = leg,
                node = node,
                nodeID = nodeID,
                slotIndex = node.slotIndex,
                pin = node.pin,
            }
        end
        return nil
    end

    local destination = taxi and taxi.destination or leg
    local mapID, x, y = destination.mapID, destination.x, destination.y
    if type(displayedMapID) ~= "number" then return nil end
    if mapID ~= displayedMapID then
        if not taxi or not taxi.destination then return nil end
        -- A flight map can display a continent where Blizzard won't set a pin.
        x, y = NS.ProjectWaypointOntoMap(mapID, x, y, displayedMapID)
        if not x or not y then return nil end
    end
    local titleName = GetUsableDestinationName(taxi and taxi.name or leg.title)
    local node
    for _, candidate in ipairs(reachable) do
        if CoordsClose(x, y, candidate.x, candidate.y) and (not titleName or NamesAgree(titleName, candidate.name)) then
            if node then return nil end
            node = candidate
        end
    end
    if not node then return nil end

    return {
        confidence = "strong",
        leg = leg,
        node = node,
        nodeID = node.nodeID,
        slotIndex = node.slotIndex,
        pin = node.pin,
    }
end

-- ============================================================
-- Consecutive taxi legs and destination matching
-- ============================================================

local function CollectTaxiRun(record)
    local legs = type(record) == "table" and record.legs or nil
    if type(legs) ~= "table" or #legs == 0 then
        return nil
    end

    local current = math.max(1, tonumber(record.currentLegIndex) or 1)
    local firstTaxi = nil
    for index = current, #legs do
        local leg = legs[index]
        if IsTaxiLeg(leg) then
            firstTaxi = index
            break
        end
        if not leg or leg.kind ~= "walk" or leg.routeTravelType and leg.routeTravelType ~= "travel"
            or leg.specialAction or leg.arrivalGate
            or leg.transportDestination or leg.leaveInstanceMapID then
            return
        end
    end
    if not firstTaxi then
        return nil
    end

    local run = {}
    for index = firstTaxi, #legs do
        local leg = legs[index]
        if index ~= firstTaxi then
            local previous = run[#run].taxi
            local taxi = IsTaxiLeg(leg) and leg.taxi
            if not previous or not previous.nodeID or not taxi or taxi.sourceNodeID ~= previous.nodeID then break end
        end
        run[#run + 1] = leg
    end
    return run, firstTaxi == current
end

-- nil means the route or client did not supply proof. False is a known
-- different departure, which should not advertise this route's flight.
local function MatchDeparture(window, leg)
    local taxi = leg.taxi
    local id = taxi and taxi.sourceNodeID
    if id and window.sourceNodeID then return id == window.sourceNodeID end
    local point = taxi and taxi.departure or leg.activationCoords
    local source = window.source
    if not point or not source or not source.x or not source.y then return end
    local x, y = point.x, point.y
    if point.mapID ~= window.mapID then
        if not NS.ProjectWaypointOntoMap or type(window.mapID) ~= "number" then return end
        x, y = NS.ProjectWaypointOntoMap(point.mapID, x, y, window.mapID)
    end
    if not x or not y then return end
    if not CoordsClose(x, y, source.x, source.y) then return false end
    for _, node in pairs(window.bySlot) do
        if node ~= source and CoordsClose(x, y, node.x, node.y) then return end
    end
    return true
end

local function TicketPassesThrough(window, match, run, last)
    if last == 1 then return true end
    local hops = TaxiWindow.GetRouteNodePath(window, match.slotIndex, match.nodeID)
    if not hops then return false end
    local stop = 1
    for i = 2, #hops do
        if hops[i] == run[stop].taxi.nodeID then
            if stop == last then return true end
            stop = stop + 1
        end
    end
    return false
end

-- ============================================================
-- Guide flight suggestions
-- ============================================================

local GUIDE_TRANSPORT_TYPES = {
    taxi = true,
    flight = true,
    portal = true,
    ship = true,
    boat = true,
    zeppelin = true,
    tram = true,
    transport = true,
    hearth = true,
    teleport = true,
}

local function GuideFlightNameMatches(name, requested)
    if not requested or type(name) ~= "string" then return false end
    if NormalizeName(name) == requested then return true end
    for component in name:gmatch("[^,]+") do
        if NormalizeName(component) == requested then return true end
    end
    return false
end

local function MatchGuideFlight(record, window, assist)
    if record and (record._coreRoutePending or record._corePlanning) then return nil, "planning_pending" end
    local legs = record and record.legs
    if legs then
        for index = record.currentLegIndex or 1, #legs do
            local leg = legs[index]
            if leg.specialAction or leg.taxi or leg.routeLegKind == "carrier"
                or GUIDE_TRANSPORT_TYPES[leg.kind] or GUIDE_TRANSPORT_TYPES[leg.routeTravelType] then
                return nil, "backend_transport_instruction"
            end
        end
    end
    local intent = NS.GetActiveGuideTravelIntent and NS.GetActiveGuideTravelIntent()
    if not intent or intent.kind ~= "flight" or not intent.destinationName then return nil, "no_guide_flight" end
    -- Native guide intent and the taxi snapshot must both still be current.
    -- Cache misses as well as matches to avoid rescanning an unchanged window.
    local cache = assist.guideMatchCache
    if not cache or cache.intent ~= intent or cache.window ~= window then
        cache = { intent = intent, window = window }
        local name = NormalizeName(intent.destinationName)
        local count = 0
        for _, node in ipairs(window.visible) do
            local matched = intent.nodeID and node.nodeID == intent.nodeID
                or not intent.nodeID and GuideFlightNameMatches(node.name, name)
            if matched then
                count = count + 1; cache.node = node
            end
        end
        if count ~= 1 then
            cache.node = nil
            cache.reason = count > 1 and "ambiguous_guide_flight" or "guide_flight_unreachable"
        end
        assist.guideMatchCache = cache
    end
    local node = cache.node
    if not node then return nil, cache.reason end
    local provider = NS.GetGuideTargetProvider and NS.GetGuideTargetProvider(NS.GetActiveGuideProvider())
    return {
        confidence = "guide",
        source = "guide",
        providerLabel = provider and provider.label or "Guide",
        intent = intent,
        node = node,
        nodeID = node.nodeID,
        slotIndex = node.slotIndex,
        pin = node.pin
    }
end

-- ============================================================
-- Resolving an offer for the active route
-- ============================================================

function TaxiWindow.ResolveRouteMatch(frame, assist)
    if type(NS.IsRoutingEnabled) == "function" and not NS.IsRoutingEnabled() then
        return nil, "routing_disabled"
    end
    if type(NS.GetActiveAuthorityRecord) ~= "function" then
        return nil, "no_authority_api"
    end

    local record = NS.GetActiveAuthorityRecord()
    local pending = state.routing and state.routing.pendingManualAuthority
    if pending and pending ~= record or record and (record._coreRoutePending or record._corePlanning) then
        return nil, "planning_pending"
    end
    local window = TaxiWindow.GetSnapshot(frame)
    if not window then return nil, "map_hidden" end
    local reachable, reachableByID = window.visible, window.visibleByID
    local currentTaxi = record and record.currentLeg and record.currentLeg.taxi
    if currentTaxi and currentTaxi.offerSerial then
        if not TaxiWindow.IsCurrentOffer(window, currentTaxi.offerSerial, currentTaxi.offerMap, currentTaxi.offerSource) then
            return nil, "expired_flight_offer"
        end
        local match = MatchLeg(window.mapID, record.currentLeg, reachable, reachableByID)
        if match then
            match.authority, match.window, match.departureVerified = record, window, true
            return match
        end
        return nil, "offered_flight_unreachable"
    end
    if #reachable == 0 then
        return nil, "no_reachable_nodes"
    end
    local run, active = CollectTaxiRun(record)
    if not run then
        return MatchGuideFlight(record, window, assist)
    end

    local departure = MatchDeparture(window, run[1])
    if departure == false or not active and departure ~= true then return nil, "wrong_flight_departure" end
    local last = departure and #run or 1
    for index = last, 1, -1 do
        local match = MatchLeg(window.mapID, run[index], reachable, reachableByID)
        if match and TicketPassesThrough(window, match, run, index) then
            match.authority, match.window, match.departureVerified = record, window, departure == true
            return match
        end
    end
    return nil, "no_match"
end

-- ============================================================
-- Flight offer details for display
-- ============================================================

-- Return a summary without passing native pins or route records to the UI.
function TaxiWindow.DescribeRouteMatch(match)
    if type(match) ~= "table" then
        return nil
    end
    local node = type(match.node) == "table" and match.node or nil
    return {
        nodeID = tonumber(match.nodeID),
        slotIndex = tonumber(match.slotIndex),
        name = TrimString(node and node.name) or StripDisplayMarkup(match.leg and match.leg.title) or "Flight Path",
        confidence = match.confidence,
        source = match.source or "route",
        providerLabel = match.providerLabel,
        state = node and node.state or nil,
    }
end
