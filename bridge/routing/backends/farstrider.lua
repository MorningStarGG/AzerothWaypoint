-- ============================================================
-- Farstrider routing backend
-- ============================================================
--
-- Converts Farstrider's graph edges, instance entrances and travel actions
-- into route legs.

local NS = _G.AzerothWaypointNS
local RouteSpecials = NS.RouteSpecials or {}

-- ============================================================
-- Planner constants and graph state
-- ============================================================

local backend = {}
NS.RoutingBackend_Farstrider = backend

backend.id = "farstrider"

local MOVEMENT_ADVANCE_YARDS = 55
local INSTANCE_NODE_COORD_EPSILON = 0.025
local COORD_BOUNDS_EPSILON = 0.0001
local FARSTRIDER_LOCA_ENTER_WIZARDS_SANCTUM = 9
local GRAPH_REBUILT = "farstrider_graph_rebuilt"
local COMBAT_TRAVEL_STATE = RouteSpecials.COMBAT_TRAVEL_STATE

local FARSTRIDER_INVALIDATION_EVENTS = {
    BAG_UPDATE_DELAYED = true,
    HEARTHSTONE_BOUND = true,
    PLAYER_ENTERING_WORLD = true,
    SPELL_UPDATE_COOLDOWN = true,
    SPELLS_CHANGED = true,
    TOYS_UPDATED = true,
}

local EdgeType = {
    TRAVEL         = 1000,
    FLIGHTPATH     = 1001,
    PORTAL         = 1002,
    BOAT           = 1003,
    ZEPPELIN       = 1004,
    ITEM           = 1005,
    SPELL          = 1006,
    LEAVE_INSTANCE = 1007,
    TRAM           = 1008,
}

local transportTypes = { [EdgeType.BOAT] = "ship", [EdgeType.ZEPPELIN] = "zeppelin", [EdgeType.TRAM] = "tram" }

local function GetFarstriderAPI()
    local api = rawget(_G, "FarstriderLib_API")
    if type(api) == "table" and type(api.FindTrailTo) == "function" then
        return api
    end
    return nil
end

local function GetFarstriderPathfinding()
    local farstrider = rawget(_G, "FarstriderLib")
    local pathfinding = type(farstrider) == "table" and farstrider.Pathfinding or nil
    if type(pathfinding) == "table" and type(pathfinding.allNodes) == "table" then
        return pathfinding
    end
    return nil
end

local graphRevision, travelRevision = 0, 0
local travelState, combatGraph

local function IndexTravelState(nodes)
    local indexed = { nodes = nodes, revision = graphRevision, conditions = {}, arrivals = {} }
    local seenConditions = {}
    for _, node in pairs(nodes) do
        for _, edge in ipairs(node.edges) do
            local condition = edge.condition
            if type(condition) == "function" and not seenConditions[condition] then
                seenConditions[condition] = true
                indexed.conditions[#indexed.conditions + 1] = { read = condition }
            end
        end
        -- The dynamic origin tracks the player. Only changing landings affect the itinerary.
        if node.isDynamic and node.key ~= "dynamic:from" then
            indexed.arrivals[#indexed.arrivals + 1] = { read = node.getLocation }
        end
    end
    return indexed
end

local function UpdateArrivalState(arrival)
    local ok, location = pcall(arrival.read)
    if not ok then return false end
    local pos = location and location.pos
    local map, x, y, z, isUI
    if pos then map, x, y, z, isUI = location.mapId, pos.x, pos.y, pos.z, location.isUI end
    if arrival.map == map and arrival.x == x and arrival.y == y and arrival.z == z and arrival.isUI == isUI then
        return false
    end
    arrival.map, arrival.x, arrival.y, arrival.z, arrival.isUI = map, x, y, z, isUI
    return true
end

local function GetFarstriderTravelStateFingerprint(selectedActionChanged)
    local pathfinding = GetFarstriderPathfinding()
    if not pathfinding then return nil end
    if combatGraph == pathfinding then pathfinding._validTravelNodesCache = nil end
    combatGraph = nil
    local changed = false
    if not travelState or travelState.nodes ~= pathfinding.allNodes or travelState.revision ~= graphRevision then
        travelState = IndexTravelState(pathfinding.allNodes)
        changed = true
    end

    for _, condition in ipairs(travelState.conditions) do
        local ok, value = pcall(condition.read)
        if ok then
            local usable = not not value
            if condition.usable ~= usable then
                condition.usable = usable
                changed = true
            end
        end
    end
    for _, arrival in ipairs(travelState.arrivals) do
        if UpdateArrivalState(arrival) then changed = true end
    end
    if changed or selectedActionChanged then
        travelRevision = travelRevision + 1
        travelState.fingerprint = tostring(travelRevision)
        -- Farstrider has a separate two-second eligibility cache. Expire
        -- it on a real change and retain the graph's map and geometry caches.
        pathfinding._validTravelNodesCache = nil
    end
    return travelState.fingerprint
end

local function ValidateTravelState(_, _, requestClass)
    local fingerprint = GetFarstriderTravelStateFingerprint(requestClass == "selected_action")
    return fingerprint ~= nil, fingerprint
end

local function IsFarstriderWizardsSanctumNode(node)
    return type(node) == "table" and node.wizardsSanctum == true
end

local function IsFarstriderWizardsSanctumEntryEdge(edge)
    return type(edge) == "table"
        and IsFarstriderWizardsSanctumNode(edge.to)
        and not IsFarstriderWizardsSanctumNode(edge.from)
end

local function IsFarstriderWizardsSanctumSourceEdge(edge)
    return type(edge) == "table" and IsFarstriderWizardsSanctumNode(edge.from)
end

local observedRebuildState, rebuiltGraph

function backend.GetReadiness()
    if not NS.IsAddonLoaded("FarstriderLib") then
        return "unavailable", "farstrider_not_loaded"
    end
    if not NS.IsAddonLoaded("FarstriderLibData") then return "unavailable", "farstrider_data_not_loaded" end
    local graph = GetFarstriderPathfinding()
    local api = GetFarstriderAPI()
    if not api or type(api.RegisterRebuildCallback) ~= "function" or not graph then
        return "unavailable", "farstrider_missing_planner"
    end
    if next(graph.allNodes) ~= nil then return "ready" end
    if graph == rebuiltGraph then return "unavailable", "farstrider_empty_graph" end
    return "waiting", "farstrider_graph_initializing"
end

-- ============================================================
-- Planner availability
-- ============================================================

function backend.IsAvailable()
    return backend.GetReadiness() == "ready"
end

function backend.InstallReadinessHooks(notify)
    local api = GetFarstriderAPI()
    if not api or type(api.RegisterRebuildCallback) ~= "function" then return end
    local callbackState = api.State or api
    if observedRebuildState == callbackState then return end
    api.RegisterRebuildCallback(function()
        rebuiltGraph = GetFarstriderPathfinding()
        graphRevision = graphRevision + 1
        travelState = nil
        notify()
        backend.OnPlanInvalidated(GRAPH_REBUILT)
    end)
    observedRebuildState = callbackState
end

function backend.GetFlightDataStatus(mapID)
    local api = rawget(_G, "FarstriderLibData_API")
    if type(mapID) ~= "number" or type(api) ~= "table" or type(api.HasFlightData) ~= "function" then return nil end
    local ok, available = pcall(api.HasFlightData, mapID)
    if ok and type(available) == "boolean" then return available end
end

local function GetTaxiPaths()
    local data = rawget(_G, "FarstriderLibData")
    local paths = type(data) == "table" and rawget(data, "TaxiPaths")
    return type(paths) == "table" and paths or nil
end

function backend.HasTaxiTimes() return GetTaxiPaths() ~= nil end

local taxiPaths, taxiTimes
function backend.GetTaxiTime(path)
    local paths = GetTaxiPaths()
    if not paths or not path or #path < 2 then return end
    if taxiPaths ~= paths then
        taxiPaths, taxiTimes = paths, {}
        for _, hop in pairs(paths) do
            local from = type(hop) == "table" and hop[1]
            local to = type(hop) == "table" and hop[2]
            local seconds = type(hop) == "table" and hop[3]
            if type(from) == "number" and type(to) == "number" and type(seconds) == "number"
                and seconds > 0 and seconds < math.huge then
                local key = from .. ":" .. to
                local previous = taxiTimes[key]
                taxiTimes[key] = (previous == nil or previous == seconds) and seconds or false
            end
        end
    end
    local total = 0
    for i = 2, #path do
        local seconds = taxiTimes[path[i - 1] .. ":" .. path[i]]
        if not seconds then return end
        total = total + seconds
    end
    return total
end

local taxiNodeData, taxiNodeRevision, taxiNodeKeys
local function ReadTaxiNodeID(node)
    if type(node) ~= "table" or type(node.key) ~= "string" then return end
    local data, runtime = rawget(_G, "FarstriderLibData"), rawget(_G, "FarstriderLib")
    local nodes = type(data) == "table" and rawget(data, "TaxiNodes")
    local navNode = type(runtime) == "table" and rawget(runtime, "NavNode")
    local graph = GetFarstriderPathfinding()
    if type(nodes) ~= "table" or type(navNode) ~= "table" or type(navNode.makeNavKey) ~= "function"
        or not graph or type(graph.GetNavMapPosFromWorldPos) ~= "function" then
        return
    end
    if taxiNodeData ~= nodes or taxiNodeRevision ~= graphRevision then
        taxiNodeData, taxiNodeRevision, taxiNodeKeys = nodes, graphRevision, {}
        for id, entry in pairs(nodes) do
            local z = entry[4]
            local ok, map, pos = pcall(graph.GetNavMapPosFromWorldPos, graph,
                { mapId = entry[1], pos = { x = entry[2], y = entry[3], z = z }, isUI = false })
            if ok and type(map) == "number" and pos and type(z) == "number" then
                local x, y = pos.x, pos.y
                if type(x) == "number" and type(y) == "number" then
                    local key = navNode.makeNavKey(map, { x = x, y = y, z = z })
                    taxiNodeKeys[key] = taxiNodeKeys[key] == nil and id or false
                end
            end
        end
    end
    return taxiNodeKeys[node.key] or nil
end

local function ResolveSpellName(spellID)
    if type(spellID) ~= "number" then return nil end
    if type(C_Spell) == "table" and type(C_Spell.GetSpellName) == "function" then
        return C_Spell.GetSpellName(spellID)
    end
    return nil
end

local function SpellLooksLikePortal(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    return lower:find("portal", 1, true) ~= nil
        or lower:find("teleport", 1, true) ~= nil
end

local function TrimString(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    return value
end

local function TitleLooksLikePortal(title)
    title = TrimString(title)
    if not title then return false end
    local lower = title:lower()
    return lower:find("take the portal", 1, true) ~= nil
        or lower:find("use the portal", 1, true) ~= nil
        or lower:find("enter the portal", 1, true) ~= nil
        or lower:find("click the portal", 1, true) ~= nil
        or lower:find("go through the portal", 1, true) ~= nil
        or lower:find("portal to", 1, true) ~= nil
end

local function ResolveItemName(itemID)
    if type(itemID) ~= "number" then return nil end
    if type(C_Item) == "table" and type(C_Item.GetItemNameByID) == "function" then
        return C_Item.GetItemNameByID(itemID)
    end
    local getItemInfo = rawget(_G, "GetItemInfo")
    if type(getItemInfo) == "function" then
        local itemName = getItemInfo(itemID)
        return TrimString(itemName)
    end
    return nil
end

local function ReadVector2XY(vector)
    if type(vector) ~= "table" then
        return nil, nil
    end
    local x = vector.x
    local y = vector.y
    if (type(x) ~= "number" or type(y) ~= "number") and type(vector.GetXY) == "function" then
        local ok, vx, vy = pcall(vector.GetXY, vector)
        if ok then
            x, y = vx, vy
        end
    end
    return x, y
end

local function CoordsAreInBounds(x, y)
    return type(x) == "number"
        and type(y) == "number"
        and x >= -COORD_BOUNDS_EPSILON
        and x <= 1 + COORD_BOUNDS_EPSILON
        and y >= -COORD_BOUNDS_EPSILON
        and y <= 1 + COORD_BOUNDS_EPSILON
end

local function ClampCoord(value)
    return math.max(0, math.min(1, value))
end

local function ReadLocCoords(loc)
    if type(loc) ~= "table" then return nil, nil, nil end
    local pos = type(loc.pos) == "table" and loc.pos or nil
    local mapID = loc.mapId
    local x = pos and pos.x or nil
    local y = pos and pos.y or nil
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil, nil, nil
    end

    if loc.isUI == true then
        return mapID, x, y
    end

    if type(C_Map) ~= "table"
        or type(C_Map.GetMapPosFromWorldPos) ~= "function"
        or type(CreateVector2D) ~= "function"
    then
        return nil, nil, nil
    end

    local worldPosition = CreateVector2D(x, y)
    local ok, uiMapID, mapPosition
    if type(loc.uiMapHint) == "number" then
        ok, uiMapID, mapPosition = pcall(C_Map.GetMapPosFromWorldPos, mapID, worldPosition, loc.uiMapHint)
    else
        ok, uiMapID, mapPosition = pcall(C_Map.GetMapPosFromWorldPos, mapID, worldPosition)
    end
    if not ok then
        return nil, nil, nil
    end
    local uiX, uiY = ReadVector2XY(mapPosition)
    if type(uiMapID) ~= "number" or not CoordsAreInBounds(uiX, uiY) then
        return nil, nil, nil
    end

    return uiMapID, ClampCoord(uiX), ClampCoord(uiY)
end

local function IsExplicitWizardsSanctumEntryEdge(edge)
    return type(edge) == "table" and edge.locaId == FARSTRIDER_LOCA_ENTER_WIZARDS_SANCTUM
end

local function ShouldUseMageTowerEntryFallback(edge, mapID)
    return IsExplicitWizardsSanctumEntryEdge(edge)
        and type(NS.IsMapContinentOrHigher) == "function"
        and NS.IsMapContinentOrHigher(mapID)
end

local function ApplyWizardsSanctumEntryPresentation(edge, step, mapID, x, y, kind, routeTravelType, arrivalRadius)
    if not IsExplicitWizardsSanctumEntryEdge(edge) then
        -- Edges arriving inside the Wizard's Sanctum that are not the local
        -- Stormwind entry edge are remote portals such as Stair of Destiny.
        -- Keep their source-side coords instead of rewriting them to Stormwind.
        return mapID, x, y, "portal", "portal", 20
    end

    kind = "entrance"
    routeTravelType = "travel"
    arrivalRadius = 15
    if ShouldUseMageTowerEntryFallback(edge, mapID) then
        mapID, x, y = RouteSpecials.GetMageTowerEntryFallback()
    end
    return mapID, x, y, kind, routeTravelType, arrivalRadius
end

local function MakeCoords(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end
    return { mapID = mapID, x = x, y = y }
end

-- ============================================================
-- Entrance and destination matching
-- ============================================================

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

local function IsMageTowerEntryLeg(leg)
    return type(RouteSpecials.IsMageTowerEntryLeg) == "function"
        and RouteSpecials.IsMageTowerEntryLeg(leg, nil, nil, nil, INSTANCE_NODE_COORD_EPSILON)
        or false
end

local function EnsureMageTowerEntryBeforeWizardsSanctumLeg(legs)
    RouteSpecials.EnsureMageTowerEntryBeforeWizardsSanctumLeg(legs, "farstrider", nil, nil, nil, IsMageTowerEntryLeg)
end

local function IsInstancePlanningTarget(target)
    return type(target) == "table" and type(target.instanceRouteIntent) == "table"
end

local function BuildPlanningTarget(mapID, x, y, title)
    local target = {
        mapID = mapID,
        x = x,
        y = y,
        title = title,
        reason = "farstrider_plan",
    }

    local intent = type(NS.ResolveInstanceRouteIntent) == "function"
        and NS.ResolveInstanceRouteIntent(mapID, x, y, title)
        or nil

    local entrance = type(intent) == "table" and intent.entrance or nil
    if type(entrance) ~= "table"
        or type(entrance.mapID) ~= "number"
        or type(entrance.x) ~= "number"
        or type(entrance.y) ~= "number"
    then
        return target
    end

    local instanceName = type(intent) == "table" and intent.instanceName or nil

    target.mapID = entrance.mapID
    target.x = entrance.x
    target.y = entrance.y

    local coordTitle
    local mapInfo = type(_G.C_Map) == "table" and type(_G.C_Map.GetMapInfo) == "function"
        and _G.C_Map.GetMapInfo(entrance.mapID)
    if type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
        coordTitle = string.format("%s %.0f, %.0f", mapInfo.name, entrance.x * 100, entrance.y * 100)
    end
    target.title = (instanceName and ("Enter " .. instanceName)) or coordTitle or title or "Route"
    target.finalMapID = mapID
    target.finalX = x
    target.finalY = y
    target.finalTitle = title
    target.instanceRouteIntent = intent
    target.reason = "farstrider_instance_entrance_plan"

    return target
end

local function MarkInstanceEntranceLeg(legs, target)
    if type(legs) ~= "table" or not IsInstancePlanningTarget(target) then
        return
    end

    local last = legs[#legs]
    if type(last) ~= "table" then
        return
    end

    if not CoordsMatch(
            last.mapID,
            last.x,
            last.y,
            target.mapID,
            target.x,
            target.y,
            INSTANCE_NODE_COORD_EPSILON
        ) then
        return
    end

    last.kind = "portal"
    last.routeLegKind = "carrier"
    last.routeTravelType = target.instanceRouteIntent.travelType
    last.arrivalRadius = 15
    last.title = target.title or last.title
end

local function AppendInstanceDestinationLeg(legs, target)
    if type(legs) ~= "table" or not IsInstancePlanningTarget(target) then
        return
    end

    local intent = target.instanceRouteIntent
    local final = type(intent.final) == "table" and intent.final or nil

    local finalMapID = type(final) == "table" and final.mapID or target.finalMapID
    local finalX = type(final) == "table" and final.x or target.finalX
    local finalY = type(final) == "table" and final.y or target.finalY
    local finalTitle = type(final) == "table" and final.title or target.finalTitle

    if type(finalMapID) ~= "number"
        or type(finalX) ~= "number"
        or type(finalY) ~= "number"
    then
        return
    end

    local last = legs[#legs]
    if type(last) == "table"
        and CoordsMatch(last.mapID, last.x, last.y, finalMapID, finalX, finalY, INSTANCE_NODE_COORD_EPSILON)
    then
        return
    end

    local leg = RouteSpecials.MakeDestinationLeg("farstrider", finalMapID, finalX, finalY,
        finalTitle or target.finalTitle or target.title)
    leg.routeTravelType, leg.arrivalRadius = intent.travelType, 15
    legs[#legs + 1] = leg
end

local function ReadEdgeLocaArgs(edge)
    if type(edge) ~= "table" or type(edge.locaArgs) ~= "function" then
        return nil
    end
    local ok, args = pcall(edge.locaArgs)
    if ok and type(args) == "table" then
        return args
    end
    return nil
end

local function ResolveActionPresentation(step, edge, fallbackActionName)
    local args = ReadEdgeLocaArgs(edge)
    local actionName = TrimString(type(args) == "table" and args[1] or nil)
        or TrimString(fallbackActionName)
    local destinationName = TrimString(type(args) == "table" and args[2] or nil)

    return TrimString(step and step.loca) or actionName, destinationName
end

local function IsUsableItemID(itemID)
    if type(itemID) ~= "number" then
        return false
    end

    local farstriderData = rawget(_G, "FarstriderLibData")
    local farstriderUtil = type(farstriderData) == "table" and farstriderData.Util or nil
    if type(farstriderUtil) == "table" and type(farstriderUtil.CanUseItem) == "function" then
        local ok, canUse = pcall(farstriderUtil.CanUseItem, itemID)
        if ok then
            return canUse == true
        end
    end

    local hasItemOrToy = false
    if type(PlayerHasToy) == "function" then
        local ok, hasToy = pcall(PlayerHasToy, itemID)
        hasItemOrToy = ok and hasToy == true
    end
    if not hasItemOrToy and type(C_Item) == "table" and type(C_Item.GetItemCount) == "function" then
        local ok, count = pcall(C_Item.GetItemCount, itemID)
        hasItemOrToy = ok and type(count) == "number" and count > 0
    end
    if not hasItemOrToy then
        local getItemCount = rawget(_G, "GetItemCount")
        if type(getItemCount) == "function" then
            local ok, count = pcall(getItemCount, itemID)
            hasItemOrToy = ok and type(count) == "number" and count > 0
        end
    end
    if not hasItemOrToy then
        return false
    end

    if type(C_Item) == "table" and type(C_Item.IsUsableItem) == "function" then
        local ok, usable = pcall(C_Item.IsUsableItem, itemID)
        if ok and usable ~= true then
            return false
        end
    end
    local isUsableItem = rawget(_G, "IsUsableItem")
    if type(isUsableItem) == "function" then
        local ok, usable = pcall(isUsableItem, itemID)
        if ok and usable ~= true then
            return false
        end
    end

    if type(NS.ProbeRouteTravelDependency) == "function" then
        local readiness = NS.ProbeRouteTravelDependency(nil, { kind = "item", id = itemID })
        return readiness ~= "unavailable"
    end
    return true
end

-- ============================================================
-- Travel actions and optimized edges
-- ============================================================

local function SelectFarstriderAction(actionOptions)
    if type(actionOptions) ~= "table" then
        return nil
    end

    local firstAction = nil
    for index = 1, #actionOptions do
        local action = actionOptions[index]
        if type(action) == "table" then
            firstAction = firstAction or action
            if action.allowAny == true and action.type == "item" and IsUsableItemID(action.data) then
                return action
            end
        end
    end
    return firstAction
end

local function IsFarstriderHearthstoneAction(action, edge)
    return type(action) == "table"
        and action.type == "item"
        and action.allowAny == true
        and type(edge) == "table"
        and type(edge.to) == "table"
        and edge.to.isDynamic == true
end

local function IsFlightpathEdge(edge)
    return type(edge) == "table" and edge.locaId == EdgeType.FLIGHTPATH
end

local function BuildOptimizedEdges(edges, path)
    local optimizedEdges, flightOrigins = {}, {}
    if type(edges) ~= "table" then
        return optimizedEdges, flightOrigins
    end

    local virtualGoalKey = nil
    if type(path) == "table" and type(path[#path]) == "table" then
        virtualGoalKey = path[#path].key
    end

    -- Mirror FarstriderLib's optimized-path filtering. The final edge is
    -- intentionally kept even when it is a direct TRAVEL edge.
    local flightOrigin
    for index = 1, #edges do
        local edge = edges[index]
        local skip = false
        if type(edge) ~= "table" then
            skip = true
        elseif index == #edges
            or (virtualGoalKey ~= nil and type(edge.to) == "table" and edge.to.key == virtualGoalKey)
        then
            skip = false
        elseif edge.skipOptimized then
            skip = true
        elseif edge.locaId == EdgeType.TRAVEL then
            skip = true
        elseif IsFlightpathEdge(edge) and index + 1 < #edges and IsFlightpathEdge(edges[index + 1]) then
            skip = true
        end

        if not IsFlightpathEdge(edge) then
            flightOrigin = nil
        elseif not flightOrigin then
            flightOrigin = edge.from
        end
        if not skip then
            optimizedEdges[#optimizedEdges + 1] = edge
            flightOrigins[#optimizedEdges] = flightOrigin
            flightOrigin = nil
        end
    end

    return optimizedEdges, flightOrigins
end

local function BuildSpecialAction(semanticKind, secureType, securePayload, name, destinationName, dependencyID)
    return {
        semanticKind          = semanticKind,
        secureType            = secureType,
        securePayload         = securePayload,
        name                  = name,
        title                 = name,
        destinationName       = destinationName,
        activationMode        = "portable",
        activationCoords      = nil,
        activationRadiusYards = 15,
        sourceBackend         = "farstrider",
        routeDependency       = type(dependencyID) == "number" and {
            kind = secureType,
            id = dependencyID,
        } or nil,
    }
end

local FARSTRIDER_GENERIC_TITLES = {
    ["Reach the destination"] = true,
}

local function BuildFarstriderLegTitle(mapID, x, y, rawTitle)
    if not rawTitle or not FARSTRIDER_GENERIC_TITLES[rawTitle] then
        return rawTitle
    end
    local mapInfo = type(_G.C_Map) == "table" and type(_G.C_Map.GetMapInfo) == "function"
        and _G.C_Map.GetMapInfo(mapID)
    if type(mapInfo) == "table" and type(mapInfo.name) == "string" and mapInfo.name ~= "" then
        return string.format("%s %.0f, %.0f", mapInfo.name, x * 100, y * 100)
    end
    return rawTitle
end

local function StepToLeg(step, edge, isLast, target, startsInsideInstance, flightOrigin)
    if type(step) ~= "table" then return nil end

    local edgeType                   = type(edge) == "table" and edge.locaId or nil
    local isWizardsSanctumEntryEdge  = IsFarstriderWizardsSanctumEntryEdge(edge)
    local isWizardsSanctumSourceEdge = IsFarstriderWizardsSanctumSourceEdge(edge)
    local actionOptions              = step.actionOptions
    local action                     = SelectFarstriderAction(actionOptions)
    local actionType                 = type(action) == "table" and action.type or nil

    local mapID, x, y
    local kind
    local routeTravelType            = nil
    local arrivalRadius              = MOVEMENT_ADVANCE_YARDS
    local specialAction              = nil
    local activationCoords           = nil
    local taxi, leaveInstanceMapID, transportDestination
    local routeLegKind               = isLast and "destination" or "carrier"

    if isLast then
        -- Farstrider can project continent coordinates onto a zone map.
        mapID, x, y = target.mapID, target.x, target.y
        kind = "destination"
        arrivalRadius = 15

        if actionType == "item" then
            local itemID = action and action.data or nil
            if type(itemID) == "number" then
                local sk = IsFarstriderHearthstoneAction(action, edge) and "hearth" or "item"
                local actionTitle, destinationName = ResolveActionPresentation(step, edge, ResolveItemName(itemID))
                specialAction = BuildSpecialAction(sk, "item", itemID, actionTitle, destinationName, itemID)
                routeTravelType = sk == "hearth" and "hearth" or nil
                kind = sk
            end
        elseif actionType == "spell" then
            local spellID = action and action.data or nil
            if type(spellID) == "number" then
                local spellName = ResolveSpellName(spellID) or tostring(spellID)
                local sk = SpellLooksLikePortal(spellName) and "portal" or "spell"
                local actionTitle, destinationName = ResolveActionPresentation(step, edge, spellName)
                specialAction = BuildSpecialAction(sk, "spell", spellName, actionTitle, destinationName, spellID)
                routeTravelType = sk == "portal" and "portal" or nil
                kind = sk
            end
        end

        if type(mapID) ~= "number" then return nil end
    elseif actionType == "item" then
        local itemID = action and action.data or nil
        if type(itemID) ~= "number" then return nil end
        local sk                           = IsFarstriderHearthstoneAction(action, edge) and "hearth" or "item"
        local actionTitle, destinationName = ResolveActionPresentation(step, edge, ResolveItemName(itemID))
        specialAction                      = BuildSpecialAction(sk, "item", itemID, actionTitle, destinationName, itemID)
        routeTravelType                    = sk == "hearth" and "hearth" or nil
        kind                               = sk
        mapID, x, y                        = ReadLocCoords(step.loc)
        if type(mapID) ~= "number" then
            mapID, x, y = ReadLocCoords(step.completionLoc)
        end
        if type(mapID) ~= "number" then return nil end
        if not startsInsideInstance then activationCoords = MakeCoords(mapID, x, y) end
    elseif actionType == "spell" then
        local spellID = action and action.data or nil
        if type(spellID) ~= "number" then return nil end
        local spellName                    = ResolveSpellName(spellID) or tostring(spellID)
        local sk                           = SpellLooksLikePortal(spellName) and "portal" or "spell"
        local actionTitle, destinationName = ResolveActionPresentation(step, edge, spellName)
        specialAction                      = BuildSpecialAction(sk, "spell", spellName, actionTitle, destinationName,
            spellID)
        routeTravelType                    = sk == "portal" and "portal" or nil
        kind                               = sk
        mapID, x, y                        = ReadLocCoords(step.loc)
        if type(mapID) ~= "number" then
            mapID, x, y = ReadLocCoords(step.completionLoc)
        end
        if type(mapID) ~= "number" then return nil end
        if not startsInsideInstance then activationCoords = MakeCoords(mapID, x, y) end
    elseif actionType == "housing" or actionType == "housing_return" then
        kind          = "carrier"
        arrivalRadius = 55
        mapID, x, y   = ReadLocCoords(step.loc)
        if type(mapID) ~= "number" then return nil end
    elseif edgeType == EdgeType.FLIGHTPATH then
        kind            = "taxi"
        routeTravelType = "taxi"
        arrivalRadius   = 15
        mapID, x, y     = ReadLocCoords(step.loc)
        if type(mapID) ~= "number" then return nil end
        local landingMap, landingX, landingY = ReadLocCoords(step.completionLoc)
        if landingMap then
            local args = ReadEdgeLocaArgs(edge)
            taxi = {
                sourceNodeID = ReadTaxiNodeID(flightOrigin),
                nodeID = ReadTaxiNodeID(edge.to),
                departure = MakeCoords(mapID, x, y),
                destination = MakeCoords(landingMap, landingX, landingY),
                name = args and TrimString(args[1]),
                operator = "farstrider",
                final = true
            }
        end
    elseif edgeType == EdgeType.PORTAL then
        kind            = "portal"
        routeTravelType = "portal"
        arrivalRadius   = 20
        mapID, x, y     = ReadLocCoords(step.loc)
        if type(mapID) ~= "number" then return nil end
    elseif edgeType == EdgeType.LEAVE_INSTANCE and action and actionType == "leave_instance" and type(action.data) == "number" then
        kind, routeTravelType = "leave_instance", "travel"
        leaveInstanceMapID = action.data
        mapID, x, y = ReadLocCoords(step.loc)
        if type(mapID) ~= "number" then return nil end
    elseif transportTypes[edgeType] then
        routeTravelType = transportTypes[edgeType]
        kind            = edgeType == EdgeType.BOAT and "boat" or routeTravelType
        arrivalRadius   = 55
        mapID, x, y     = ReadLocCoords(step.loc)
        if type(mapID) ~= "number" then return nil end
        transportDestination = MakeCoords(ReadLocCoords(step.completionLoc))
        if not transportDestination then return nil end
    else
        kind            = "carrier"
        routeTravelType = "travel"
        mapID, x, y     = ReadLocCoords(step.loc)
        if type(mapID) ~= "number" then return nil end
    end

    if isWizardsSanctumEntryEdge then
        specialAction = nil
        activationCoords = nil
        mapID, x, y, kind, routeTravelType, arrivalRadius =
            ApplyWizardsSanctumEntryPresentation(edge, step, mapID, x, y, kind, routeTravelType, arrivalRadius)
    elseif routeLegKind == "carrier" and TitleLooksLikePortal(step.loca) then
        kind = "portal"
        routeTravelType = "portal"
        arrivalRadius = 20
    end

    local legTitle
    if routeLegKind == "destination" then
        legTitle = TrimString(target.finalTitle or target.title) or TrimString(step.loca)
    else
        legTitle = BuildFarstriderLegTitle(mapID, x, y, step.loca)
    end

    local leg = {
        mapID                = mapID,
        x                    = x,
        y                    = y,
        kind                 = kind,
        routeLegKind         = routeLegKind,
        title                = legTitle,
        source               = "farstrider",
        routeTravelType      = routeTravelType,
        arrivalRadius        = arrivalRadius,
        activationCoords     = activationCoords,
        taxi                 = taxi,
        leaveInstanceMapID   = leaveInstanceMapID,
        transportDestination = transportDestination,
        arrivalGate          = isWizardsSanctumSourceEdge and RouteSpecials.MakeWizardsSanctumArrivalGate() or nil,
        specialAction        = specialAction,
    }
    if edgeType == EdgeType.TRAVEL and not specialAction and kind == "carrier" and not leg.arrivalGate then
        NS.Internal.RouteWalkingPresentation.Describe(leg, "path", leg, nil, leg.title)
    end
    return leg
end

-- ============================================================
-- Plan acceptance and requests
-- ============================================================

local function AcceptPlan(record, legs, reason)
    return RouteSpecials.CompletePlan(record, "farstrider", "success", legs, reason)
end

local function ReportFailure(record, reason)
    RouteSpecials.CompletePlan(record, "farstrider", "failed", nil, reason)
end

local function PlanRoute(record, mapID, x, y, title, meta)
    if type(record) ~= "table" or type(mapID) ~= "number"
        or type(x) ~= "number" or type(y) ~= "number"
    then
        return
    end

    local api = GetFarstriderAPI()
    if not api then
        ReportFailure(record, "farstrider_missing")
        return
    end

    local target = BuildPlanningTarget(mapID, x, y, title)

    local combat = InCombatLockdown and InCombatLockdown()
    if combat then
        -- Farstrider evaluates the usable edges for this search itself. Its
        -- two-second cache can still contain out-of-combat spell eligibility.
        combatGraph = GetFarstriderPathfinding()
        if combatGraph then combatGraph._validTravelNodesCache = nil end
        record._routeBackendStateFingerprint = COMBAT_TRAVEL_STATE
    else
        record._routeBackendStateFingerprint = GetFarstriderTravelStateFingerprint()
    end
    local ok, optimizedPath, path, edges = pcall(api.FindTrailTo, target.mapID, target.x, target.y, 0)
    if not ok or type(optimizedPath) ~= "table" or #optimizedPath == 0 then
        if combat and ok then
            RouteSpecials.CompletePlan(record, "farstrider", "deferred", nil, "combat")
        else
            ReportFailure(record, "farstrider_nopath_fallback")
        end
        return
    end

    local optimizedEdges, flightOrigins = BuildOptimizedEdges(edges, path)
    record._farstriderLastStepCount = #optimizedPath
    record._farstriderLastEdgeCount = type(edges) == "table" and #edges or 0
    record._farstriderLastOptimizedEdgeCount = #optimizedEdges
    record._farstriderLastCorrelationMismatch = #optimizedEdges ~= #optimizedPath or nil

    local legs = {}
    local needsWizardsSanctumEntry = type(RouteSpecials.PlayerNeedsWizardsSanctumEntry) == "function"
        and RouteSpecials.PlayerNeedsWizardsSanctumEntry()
        or false
    local wizardsSanctumEntryQueued = false
    local originKey = type(path) == "table" and path[1] and path[1].key
    local startsInsideInstance = type(originKey) == "string" and originKey:match("^instance:%d+$") ~= nil
    for i = 1, #optimizedPath do
        local leg = StepToLeg(
            optimizedPath[i],
            optimizedEdges[i],
            i == #optimizedPath,
            target,
            i == 1 and startsInsideInstance,
            flightOrigins[i]
        )
        local edge = optimizedEdges[i]
        if not leg and edge and transportTypes[edge.locaId] then
            ReportFailure(record, "farstrider_transport_unresolved")
            return
        end
        if leg then
            if leg.kind == "entrance" then
                wizardsSanctumEntryQueued = true
            elseif leg.arrivalGate and needsWizardsSanctumEntry and not wizardsSanctumEntryQueued then
                EnsureMageTowerEntryBeforeWizardsSanctumLeg(legs)
                wizardsSanctumEntryQueued = true
            end
            legs[#legs + 1] = leg
        end
    end

    if #legs == 0 then
        ReportFailure(record, "farstrider_nopath_fallback")
        return
    end

    MarkInstanceEntranceLeg(legs, target)
    AppendInstanceDestinationLeg(legs, target)

    AcceptPlan(record, legs, target.reason or "farstrider_plan")
end

function backend.BeginPlan(attempt)
    return PlanRoute(attempt.record, attempt.mapID, attempt.x, attempt.y, attempt.title, attempt.meta)
end

function backend.AdoptPlan(attempt, owner)
    local record = attempt.record
    owner._routeBackendStateFingerprint = record._routeBackendStateFingerprint
    owner._farstriderLastStepCount, owner._farstriderLastEdgeCount = record._farstriderLastStepCount,
        record._farstriderLastEdgeCount
    owner._farstriderLastOptimizedEdgeCount = record._farstriderLastOptimizedEdgeCount
    owner._farstriderLastCorrelationMismatch = record._farstriderLastCorrelationMismatch
end

function backend.Clear(record)
    if type(record) ~= "table" then return end
    record._farstriderPendingSig = nil
    record._farstriderLastStepCount = nil
    record._farstriderLastEdgeCount = nil
    record._farstriderLastOptimizedEdgeCount = nil
    record._farstriderLastCorrelationMismatch = nil
    NS.ClearAcceptedRoutePlan(record)
end

function backend.OnPlanInvalidated(reason)
    if type(NS.RequestRouteBackendStateValidation) == "function" then
        local requestClass = reason == "SPELL_UPDATE_COOLDOWN" and "cooldown" or "structural"
        return NS.RequestRouteBackendStateValidation(
            "farstrider",
            reason or "farstrider_invalidated",
            requestClass)
    end
    return false
end

function backend.Initialize()
    if backend._eventFrame then
        return
    end

    local frame = CreateFrame("Frame")
    backend._eventFrame = frame
    if type(NS.RegisterRouteBackendStateValidator) == "function" then
        NS.RegisterRouteBackendStateValidator(
            "farstrider",
            ValidateTravelState,
            NS.ProbeRouteTravelDependency)
    end
    for event in pairs(FARSTRIDER_INVALIDATION_EVENTS) do
        frame:RegisterEvent(event)
    end
    frame:SetScript("OnEvent", function(_, event)
        backend.OnPlanInvalidated(event)
    end)
end
