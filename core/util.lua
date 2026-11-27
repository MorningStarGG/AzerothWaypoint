-- ============================================================
-- Client APIs and waypoint metadata
-- ============================================================
--
-- Provides client and addon accessors and identifies waypoint, quest and
-- travel metadata for routing.

local NS = _G.AzerothWaypointNS

local ZYGOR_RETAIL_ADDON = "ZygorGuidesViewer"
local ZYGOR_FOREVER_ADDON = "ZygorGuidesViewerForever"

local function GetInterfaceVersion()
    if type(GetBuildInfo) ~= "function" then
        return nil
    end
    local _, _, _, interfaceVersion = GetBuildInfo()
    return tonumber(interfaceVersion)
end

function NS.GetClientFlavor()
    local interfaceVersion = GetInterfaceVersion()
    if interfaceVersion and interfaceVersion >= 16000 and interfaceVersion < 17000 then
        return "forever"
    end
    return "retail"
end

function NS.IsWoWForever()
    return NS.GetClientFlavor() == "forever"
end

-- ============================================================
-- Addon accessors
-- ============================================================

function NS.GetTomTom()
    return _G["TomTom"]
end

function NS.GetTomTomArrow()
    return _G["TomTomCrazyArrow"]
end

local function FocusTomTomPasteWindow(window)
    if type(window) ~= "table" then
        return
    end
    if type(window.Raise) == "function" then
        window:Raise()
    end

    local editBox = window.EditBox and window.EditBox.ScrollingEditBox or nil
    if type(editBox) == "table" and type(editBox.SetFocus) == "function" then
        editBox:SetFocus()
    end
end

local function GetTomTomPasteWindow(tomtom)
    return (type(tomtom) == "table" and tomtom.pasteWindow) or _G["TomTomPaste"]
end

function NS.OpenTomTomPasteWindow()
    local tomtom = type(NS.GetTomTom) == "function" and NS.GetTomTom() or _G["TomTom"]
    local window = GetTomTomPasteWindow(tomtom)
    if type(window) == "table" and type(window.Show) == "function" then
        window:Show()
        FocusTomTomPasteWindow(window)
        return true
    end

    local slashHandler = type(SlashCmdList) == "table" and SlashCmdList["TOMTOM_PASTE"] or nil
    if type(slashHandler) == "function" then
        slashHandler("")
        window = GetTomTomPasteWindow(tomtom)
        if type(window) == "table" and type(window.Show) == "function" then
            window:Show()
            FocusTomTomPasteWindow(window)
            return true
        end
    end

    if type(NS.Msg) == "function" then
        NS.Msg("TomTom paste window is unavailable.")
    end
    return false
end

function NS.IsAddonLoaded(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    return type(C_AddOns) == "table"
        and type(C_AddOns.IsAddOnLoaded) == "function"
        and C_AddOns.IsAddOnLoaded(name)
        or false
end

function NS.GetZygorAddonName()
    if NS.IsAddonLoaded(ZYGOR_FOREVER_ADDON) then
        return ZYGOR_FOREVER_ADDON
    end
    if NS.IsAddonLoaded(ZYGOR_RETAIL_ADDON) then
        return ZYGOR_RETAIL_ADDON
    end
    return NS.IsWoWForever() and ZYGOR_FOREVER_ADDON or ZYGOR_RETAIL_ADDON
end

function NS.GetZygorAssetPath(relativePath)
    if type(relativePath) ~= "string" or relativePath == "" then
        return nil
    end
    relativePath = relativePath:gsub("^[\\/]", ""):gsub("/", "\\")

    local zygor = rawget(_G, "ZGV") or rawget(_G, "ZygorGuidesViewer")
    local root = type(zygor) == "table" and type(zygor.DIR) == "string" and zygor.DIR or nil
    if not root or root == "" then
        root = "Interface\\AddOns\\" .. NS.GetZygorAddonName()
    end
    return root:gsub("[\\/]$", "") .. "\\" .. relativePath
end

function NS.IsZygorLoaded()
    if not NS.IsAddonLoaded(NS.GetZygorAddonName()) then return false end
    return rawget(_G, "ZygorGuidesViewer") ~= nil or rawget(_G, "ZGV") ~= nil
end

function NS.IsMapzerothLoaded()
    if not NS.IsAddonLoaded("Mapzeroth") then return false end
    return type(rawget(_G, "MapzerothAddon")) == "table"
end

function NS.IsFarstriderLoaded()
    local api = rawget(_G, "FarstriderLib_API")
    return type(api) == "table" and type(api.FindTrailTo) == "function"
end

function NS.IsAPRLoaded()
    if not NS.IsAddonLoaded("APR") then return false end
    return type(rawget(_G, "APR")) == "table"
end

function NS.IsWoWProLoaded()
    if not NS.IsAddonLoaded("WoWPro") then return false end
    return type(rawget(_G, "WoWPro")) == "table"
end

function NS.IsDugiLoaded()
    if not NS.IsAddonLoaded("DugisGuideViewerZ") then return false end
    return type(rawget(_G, "DugisGuideViewer")) == "table"
end

-- ============================================================
-- Guide provider registry
-- Future guide addons register here so display code is provider-aware
-- without hardcoding names/icons anywhere else.
-- ============================================================

local guideProviderRegistry = {}
local guideProviderRegistryRevision = 0

local function NormalizeGuideProviderKey(key)
    if type(key) ~= "string" then return nil end
    key = key:gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then return nil end
    return key:lower()
end

function NS.RegisterGuideProvider(key, def)
    if type(key) ~= "string" or type(def) ~= "table" then return end
    key = NormalizeGuideProviderKey(key)
    if not key then return end
    guideProviderRegistry[key] = def
    guideProviderRegistryRevision = guideProviderRegistryRevision + 1
end

function NS.GetGuideProviderInfo(key)
    key = NormalizeGuideProviderKey(key)
    return key and guideProviderRegistry[key] or nil
end

function NS.GetGuideProviderRegistryRevision()
    return guideProviderRegistryRevision
end

function NS.GetCurrentCharacterName()
    if type(UnitNameUnmodified) == "function" then
        return UnitNameUnmodified("player")
    end
    if type(UnitName) == "function" then
        return UnitName("player")
    end
    return nil
end

function NS.IsAddonEnabledForCurrentCharacter(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    if type(C_AddOns) ~= "table" or type(C_AddOns.GetAddOnEnableState) ~= "function" then
        return NS.IsAddonLoaded(name)
    end

    local characterName = NS.GetCurrentCharacterName()
    if type(characterName) ~= "string" or characterName == "" then
        return NS.IsAddonLoaded(name)
    end

    return (tonumber(C_AddOns.GetAddOnEnableState(name, characterName)) or 0) > 0
end

function NS.DisableAddonForCurrentCharacter(name)
    if type(name) ~= "string" or name == "" then
        return false
    end

    local characterName = NS.GetCurrentCharacterName()
    if type(characterName) ~= "string" or characterName == "" then
        return false
    end

    if type(C_AddOns) == "table" and type(C_AddOns.DisableAddOn) == "function" then
        return pcall(C_AddOns.DisableAddOn, name, characterName)
    end

    return false
end

-- ============================================================
-- Text utilities
-- ============================================================

function NS.IsBlankText(value)
    return type(value) ~= "string" or value:match("^%s*$") ~= nil
end

-- ============================================================
-- Waypoint introspection
-- ============================================================

function NS.ReadWaypointCoords(waypoint)
    if type(waypoint) ~= "table" then
        return
    end

    return waypoint.map or waypoint.mapid or waypoint.mapID or waypoint.m,
        waypoint.x or waypoint.mapx or waypoint.wx,
        waypoint.y or waypoint.mapy or waypoint.wy
end

local _normalizeTitleCache = {}
local _normalizeTitleCacheSize = 0
local NORMALIZE_TITLE_CACHE_MAX = 64

function NS.NormalizeWaypointTitle(title)
    if title == nil then
        return
    end

    local key = tostring(title)
    local cached = _normalizeTitleCache[key]
    if cached ~= nil then
        return cached ~= "" and cached or nil
    end

    local result = key
    result = result:gsub("[\r\n]+", " ")
    result = result:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    result = result:gsub("%s*%d+[%.,]%s*%d+%s*,?%s*", " ")
    result = result:gsub("%s*%d+[%.,]%s*%d+%s*$", " ")
    result = result:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

    if _normalizeTitleCacheSize >= NORMALIZE_TITLE_CACHE_MAX then
        _normalizeTitleCache = {}
        _normalizeTitleCacheSize = 0
    end

    if result == "" then
        _normalizeTitleCache[key] = ""
        _normalizeTitleCacheSize = _normalizeTitleCacheSize + 1
        return
    end

    _normalizeTitleCache[key] = result
    _normalizeTitleCacheSize = _normalizeTitleCacheSize + 1
    return result
end

function NS.ResolveWaypointOwner(waypoint)
    if type(waypoint) ~= "table" then
        return
    end

    local surrogate = waypoint.surrogate_for
    if type(surrogate) == "table" then
        return surrogate
    end

    local sourceWaypoint = waypoint.pathnode and waypoint.pathnode.waypoint
    if type(sourceWaypoint) == "table" then
        return sourceWaypoint
    end

    return waypoint
end

function NS.IsWaypointOwnedBy(waypoint, owner)
    if type(waypoint) ~= "table" or type(owner) ~= "table" then
        return false
    end

    return NS.ResolveWaypointOwner(waypoint) == owner
end

local function GetGoalMapID(goal)
    return goal and (goal.map or goal.mapid or goal.mapID) or nil
end

local function GetWaypointSig(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return
    end

    return NS.Signature(mapID, x, y)
end

local function IsLivePointerSource(source)
    return type(source) == "string" and source:find("^pointer%.") ~= nil
end

-- Zygor clears the active route set before LibRover rebuilds it, briefly exposing
-- the same focused-step goal as a plain "way" waypoint. Keep that target classified
-- as route while the rebuild is in flight so the bridge never sees a fake kind flip.
local function IsPendingCurrentGoalRouteRebuild(waypoint, source)
    if type(waypoint) ~= "table" or not IsLivePointerSource(source) then
        return false
    end

    local bridge = NS.State and NS.State.bridge or nil
    if type(bridge) ~= "table"
        or bridge.lastAppliedKind ~= "route"
        or type(bridge.lastSig) ~= "string"
    then
        return false
    end

    local Z = type(NS.ZGV) == "function" and NS.ZGV() or nil
    local pointer = Z and Z.Pointer or nil
    local rover = Z and Z.LibRover or nil
    local step = Z and Z.CurrentStep or nil
    if type(pointer) ~= "table"
        or type(rover) ~= "table"
        or type(step) ~= "table"
        or type(step.goals) ~= "table"
        or not (Z and Z.db and Z.db.profile and Z.db.profile.pathfinding)
    then
        return false
    end

    local destination = pointer.DestinationWaypoint
    if type(destination) ~= "table" then
        return false
    end

    local destinationOwner = NS.ResolveWaypointOwner(destination)
    local destinationOwnerType = destinationOwner and destinationOwner.type or nil
    if destinationOwnerType == "manual" or destinationOwnerType == "corpse" then
        return false
    end

    local canonical = NS.ResolveCanonicalGuideGoal(step)
    local currentGoalNum = canonical and canonical.canonicalGoalNum or nil
    local currentGoal = type(currentGoalNum) == "number" and step.goals[currentGoalNum] or nil
    local currentGoalSig = GetWaypointSig(
        GetGoalMapID(currentGoal),
        type(currentGoal) == "table" and currentGoal.x or nil,
        type(currentGoal) == "table" and currentGoal.y or nil
    )
    if type(currentGoalSig) ~= "string" or bridge.lastSig ~= currentGoalSig then
        return false
    end

    local waypointMapID, waypointX, waypointY = NS.ReadWaypointCoords(waypoint)
    local destinationMapID, destinationX, destinationY = NS.ReadWaypointCoords(destination)
    local waypointSig = GetWaypointSig(waypointMapID, waypointX, waypointY)
    local destinationSig = GetWaypointSig(destinationMapID, destinationX, destinationY)
    if waypointSig ~= currentGoalSig or destinationSig ~= currentGoalSig then
        return false
    end

    local delayedJobs = type(rover.delayeddata) == "table" and #rover.delayeddata or 0
    return rover.calculating == true or rover.delayfindpath_timer ~= nil or delayedJobs > 0
end

function NS.ResolveIngressWaypointKind(waypoint, source)
    if IsPendingCurrentGoalRouteRebuild(waypoint, source) then
        return "route"
    end

    return NS.GetWaypointKind(waypoint, source)
end

function NS.GetWaypointKind(waypoint, source)
    local owner = NS.ResolveWaypointOwner(waypoint)
    local ownerType = owner and owner.type or nil
    if ownerType == "manual" then
        return "manual"
    end
    if ownerType == "corpse" then
        return "corpse"
    end

    if type(waypoint) == "table" then
        local waypointType = waypoint.type
        if waypointType == "route" or waypointType == "path" or waypoint.pathnode or waypoint.in_set then
            return "route"
        end
    end

    if type(source) == "string" and (source:find("^step%.goal#") or source == "text+playerMap") then
        return "guide"
    end

    return "guide"
end

local function IsRouteLikeWaypoint(waypoint)
    if type(waypoint) ~= "table" then
        return false
    end

    local waypointType = waypoint.type
    return waypointType == "route" or waypointType == "path" or waypoint.pathnode ~= nil or waypoint.in_set ~= nil
end

-- ============================================================
-- Travel classification
-- ============================================================

local function GetWaypointTravelNode(waypoint)
    if type(waypoint) ~= "table" then
        return
    end

    if type(waypoint.pathnode) == "table" then
        return waypoint.pathnode, "pathnode"
    end

    local surrogate = waypoint.surrogate_for
    if type(surrogate) == "table" then
        if type(surrogate.pathnode) == "table" then
            return surrogate.pathnode, "surrogate.pathnode"
        end

        local surrogateSourceWaypoint = surrogate.pathnode and surrogate.pathnode.waypoint
        if type(surrogateSourceWaypoint) == "table" and type(surrogateSourceWaypoint.pathnode) == "table" then
            return surrogateSourceWaypoint.pathnode, "surrogate.pathnode.waypoint.pathnode"
        end
    end

    local sourceWaypoint = waypoint.pathnode and waypoint.pathnode.waypoint
    if type(sourceWaypoint) == "table" and type(sourceWaypoint.pathnode) == "table" then
        return sourceWaypoint.pathnode, "pathnode.waypoint.pathnode"
    end
end

local function GetTravelField(node, key)
    if type(node) ~= "table" then
        return
    end

    if node[key] ~= nil then
        return node[key], "node." .. key
    end

    local link = node.link
    if type(link) == "table" and link[key] ~= nil then
        return link[key], "node.link." .. key
    end
end

local function NormalizeTravelMode(mode)
    if type(mode) ~= "string" then
        return
    end

    mode = mode:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if mode == "" then
        return
    end

    return mode
end

local function NormalizeTravelToken(value)
    return NormalizeTravelMode(value)
end

local function GetTravelNodeType(node)
    if type(node) ~= "table" then
        return
    end

    return NormalizeTravelToken(node.subtype or node.type)
end

local function GetTravelNodeNextType(node)
    if type(node) ~= "table" or type(node.next) ~= "table" then
        return
    end

    return NormalizeTravelToken(node.next.subtype or node.next.type)
end

local function GetTravelNodeTemplate(node)
    local template = GetTravelField(node, "template")
    return NormalizeTravelToken(template)
end

local function GetTravelNodeContext(node)
    if type(node) ~= "table" then
        return
    end

    return NormalizeTravelToken(node.a_b__c_d or node.a_b)
end

local function ContainsTravelToken(value, token)
    return type(value) == "string"
        and type(token) == "string"
        and token ~= ""
        and value:find(token, 1, true) ~= nil
end

local function IsPortalContextPattern(context)
    return ContainsTravelToken(context, "__portal_")
        or ContainsTravelToken(context, "__portalauto_")
        or ContainsTravelToken(context, "__portaldungeonenter_")
        or ContainsTravelToken(context, "__portaldungeonexit_")
        or ContainsTravelToken(context, "__pinkportal_")
        or ContainsTravelToken(context, "__darkportal_")
        or ContainsTravelToken(context, "__darkportalred_")
        or ContainsTravelToken(context, "__cityportal_")
end

local function DetectTravelTypeFromNodeSemantics(node)
    local nodeType = GetTravelNodeType(node)
    if nodeType == "portal" then
        return "portal", "high", true, "node-type"
    end
    if NS.IsVehicleTravelType(nodeType) then
        return NS.NormalizeTravelType(nodeType), "high", true, "node-type"
    end

    local nodeTemplate = GetTravelNodeTemplate(node)
    if ContainsTravelToken(nodeTemplate, "portal") then
        return "portal", "high", true, "node-template"
    end

    local nodeContext = GetTravelNodeContext(node)
    if IsPortalContextPattern(nodeContext) then
        return "portal", "high", true, "node-context"
    end

    local nextType = GetTravelNodeNextType(node)
    if nextType == "portal" then
        return "portal", "high", true, "node-next-type"
    end

    return nil
end

local function NormalizeTravelTitle(title)
    title = NS.NormalizeWaypointTitle(title)
    return type(title) == "string" and title:lower() or nil
end

local function DetectTravelTypeFromTitle(title)
    local normalizedTitle = NormalizeTravelTitle(title)
    if type(normalizedTitle) ~= "string" then
        return nil, nil, false
    end

    if normalizedTitle:find("click the portal", 1, true)
        or normalizedTitle:find("enter the portal", 1, true)
        or normalizedTitle:find("take the portal", 1, true)
        or normalizedTitle:find("portal to", 1, true)
        or normalizedTitle:find("use the portal", 1, true)
    then
        return "portal", "high", true
    end

    if normalizedTitle:find("take a flight", 1, true)
        or normalizedTitle:find("fly to", 1, true)
        or normalizedTitle:find("flight to", 1, true)
        or normalizedTitle:find("take the flight", 1, true)
        or normalizedTitle:find("begin flying", 1, true)
        or normalizedTitle:find("flying to", 1, true)
    then
        return "taxi", "high", true
    end

    if normalizedTitle:find("queue", 1, true)
        or normalizedTitle:find("dungeon", 1, true)
    then
        return "travel", "high", true
    end

    if normalizedTitle:find("taxi", 1, true) or normalizedTitle:find("flight", 1, true) then
        return "taxi", "medium", false
    end

    return nil, nil, false
end

local function TitleContainsToken(title, token)
    return type(title) == "string"
        and type(token) == "string"
        and token ~= ""
        and title:find(token, 1, true) ~= nil
end

local function LooksLikeExplicitPortalInteractionTitle(title)
    if type(title) ~= "string" then
        return false
    end

    return TitleContainsToken(title, "click the portal")
        or TitleContainsToken(title, "enter the portal")
        or TitleContainsToken(title, "take the portal")
        or TitleContainsToken(title, "use the portal")
        or TitleContainsToken(title, "go through the portal")
        or TitleContainsToken(title, "pass through the portal")
        or TitleContainsToken(title, "portal back")
        or TitleContainsToken(title, "entrance portal")
        or TitleContainsToken(title, "exit portal")
        or TitleContainsToken(title, "swirling portal")
        or TitleContainsToken(title, "scenic getaway portal")
        or TitleContainsToken(title, "spatial rift")
        or TitleContainsToken(title, "click the rift to")
        or (TitleContainsToken(title, "walk into the") and TitleContainsToken(title, "portal"))
end

local function LooksLikeExplicitTransportInteractionTitle(title)
    if type(title) ~= "string" then
        return false
    end

    return TitleContainsToken(title, "talk to ")
        or TitleContainsToken(title, "board the drill")
        or TitleContainsToken(title, "mole machine")
        or TitleContainsToken(title, "teleporter")
        or TitleContainsToken(title, "teleport pad")
        or TitleContainsToken(title, "teleportation pad")
        or TitleContainsToken(title, "teleportation unit")
        or TitleContainsToken(title, "beacon")
        or TitleContainsToken(title, "tablet")
        or TitleContainsToken(title, "control panel")
        or TitleContainsToken(title, "transport pad")
        or TitleContainsToken(title, "transporter")
        or TitleContainsToken(title, "tunnel to")
        or TitleContainsToken(title, "walk into the tunnel")
        or TitleContainsToken(title, "enter the tunnel")
        or TitleContainsToken(title, "riftstone")
        or TitleContainsToken(title, "ability on-screen")
        or TitleContainsToken(title, "jump to ")
end

local function DetectNonPortalTravelTypeFromTitle(title)
    local normalizedTitle = NormalizeTravelTitle(title)
    if type(normalizedTitle) ~= "string" then
        return nil
    end

    if normalizedTitle:find("take a flight", 1, true)
        or normalizedTitle:find("fly to", 1, true)
        or normalizedTitle:find("flight to", 1, true)
        or normalizedTitle:find("take the flight", 1, true)
        or normalizedTitle:find("begin flying", 1, true)
        or normalizedTitle:find("flying to", 1, true)
    then
        return "taxi"
    end

    if normalizedTitle:find("queue", 1, true)
        or normalizedTitle:find("dungeon", 1, true)
    then
        return "travel"
    end

    if LooksLikeExplicitTransportInteractionTitle(normalizedTitle) then
        return "travel"
    end

    return nil
end

local function ValidatePortalTravelTypeCandidate(travelType, confidence, isExplicit, sourceKind, title)
    if travelType ~= "portal" then
        return travelType, confidence, isExplicit, sourceKind
    end

    local normalizedTitle = NormalizeTravelTitle(title)
    if type(normalizedTitle) ~= "string" then
        return travelType, confidence, isExplicit, sourceKind
    end

    if LooksLikeExplicitPortalInteractionTitle(normalizedTitle) then
        return travelType, confidence, isExplicit, sourceKind
    end

    local nonPortalTravelType = DetectNonPortalTravelTypeFromTitle(normalizedTitle)
    if type(nonPortalTravelType) == "string" then
        local validatedSourceKind = type(sourceKind) == "string" and sourceKind or "portal-candidate"
        return nonPortalTravelType, "high", true, validatedSourceKind .. ":transport-title"
    end

    return travelType, confidence, isExplicit, sourceKind
end

-- ============================================================
-- C_TaxiMap coord proof
-- ============================================================

local TAXI_COORD_EPSILON = 0.0015

local function ResolveTaxiNodeAtCoord(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end
    if type(C_TaxiMap) ~= "table" or type(C_TaxiMap.GetTaxiNodesForMap) ~= "function" then
        return nil
    end
    local nodes = C_TaxiMap.GetTaxiNodesForMap(mapID)
    if type(nodes) ~= "table" then
        return nil
    end
    local match = nil
    for _, node in ipairs(nodes) do
        local pos = node.position
        if type(pos) == "table" then
            local nx = pos.x
            local ny = pos.y
            if type(nx) == "number" and type(ny) == "number"
                and nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1
                and math.abs(nx - x) <= TAXI_COORD_EPSILON
                and math.abs(ny - y) <= TAXI_COORD_EPSILON
            then
                if match then
                    return nil
                end
                match = node
            end
        end
    end
    return match
end

function NS.ResolveTaxiNodeAtCoord(mapID, x, y)
    return ResolveTaxiNodeAtCoord(mapID, x, y)
end

function NS.GetTaxiCoordEpsilon()
    return TAXI_COORD_EPSILON
end

local function CheckTaxiNodeCoordProof(mapID, x, y)
    return ResolveTaxiNodeAtCoord(mapID, x, y) ~= nil
end

local function ClassifyTravelSemanticsImpl(action, mapID, x, y, rawArrowTitle, detailText)
    if NS.IsVehicleTravelType(action) then return NS.NormalizeTravelType(action) end
    if action == "fly" or action == "fpath" or action == "ontaxi" or action == "offtaxi" then
        return "taxi"
    end
    if action == "home" then
        return "inn"
    end
    if action == "hearth" then
        return "hearth"
    end
    if action == "portal" then
        return "portal"
    end

    if CheckTaxiNodeCoordProof(mapID, x, y) then
        return "taxi"
    end

    local lowerArrow = rawArrowTitle and NormalizeTravelTitle(rawArrowTitle) or nil
    local lowerDetail = detailText and NormalizeTravelTitle(detailText) or nil

    local function inAny(token)
        return (lowerArrow and lowerArrow:find(token, 1, true) ~= nil)
            or (lowerDetail and lowerDetail:find(token, 1, true) ~= nil)
    end

    if inAny("portal") then
        return "portal"
    end
    if inAny("queue") or inAny("dungeon") then
        return "travel"
    end
    if inAny("take a flight") or inAny("fly to") or inAny("flight to") or inAny("take the flight")
        or inAny("begin flying") or inAny("flying to")
    then
        return "taxi"
    end
    if inAny("taxi") or inAny("flight") then
        return "taxi"
    end

    return nil
end

function NS.ClassifyTravelSemantics(action, mapID, x, y, rawArrowTitle, detailText)
    return ClassifyTravelSemanticsImpl(action, mapID, x, y, rawArrowTitle, detailText)
end

function NS.GetWaypointTravelMode(waypoint)
    local node = GetWaypointTravelNode(waypoint)
    local mode = GetTravelField(node, "mode")
    return NormalizeTravelMode(mode)
end

local waypointTravelDescriptor = {}

local function ResolveWaypointTravelDescriptorFields(waypoint, source, title, routeTravelType, routeLegKind, routeSource)
    if type(waypoint) ~= "table" then
        return nil
    end

    local owner = NS.ResolveWaypointOwner(waypoint)
    local ownerType = owner and owner.type or waypoint.type
    if (ownerType == "manual" or ownerType == "corpse") and not IsRouteLikeWaypoint(waypoint) then
        return nil
    end

    local node = GetWaypointTravelNode(waypoint)
    local mode = NormalizeTravelMode(GetTravelField(node, "mode"))
    local spell = GetTravelField(node, "spell")
    local item = GetTravelField(node, "item")
    local toy = GetTravelField(node, "toy")
    local arrivalToy = GetTravelField(node, "arrivaltoy")
    local initFunc = GetTravelField(node, "initfunc")
    local atlas = GetTravelField(node, "atlas")

    local travelType, confidence, isExplicit, sourceKind = DetectTravelTypeFromNodeSemantics(node)

    if type(travelType) ~= "string" then
        local wm, wx, wy = NS.ReadWaypointCoords(waypoint)
        if CheckTaxiNodeCoordProof(wm, wx, wy) then
            travelType = "taxi"
            confidence = "high"
            isExplicit = true
            sourceKind = "taximap-coord"
        end
    end

    if type(travelType) ~= "string" then
        travelType, confidence, isExplicit = DetectTravelTypeFromTitle(title)
        sourceKind = type(confidence) == "string" and "title" or nil
    end

    if spell ~= nil or item ~= nil or toy ~= nil or arrivalToy ~= nil or initFunc ~= nil or atlas ~= nil then
        if type(travelType) ~= "string" then
            if mode == "hearth" then
                travelType = "hearth"
            elseif type(mode) == "string" and mode:find("portal", 1, true) then
                travelType = "portal"
            else
                travelType = "travel"
            end
        end
        confidence = "high"
        isExplicit = true
        sourceKind = "node"
    end

    if type(travelType) ~= "string" and type(mode) == "string" then
        if NS.IsVehicleTravelType(mode) then
            travelType, confidence, isExplicit, sourceKind = NS.NormalizeTravelType(mode), "high", true, "mode"
        elseif mode == "hearth" or mode:find("hearth", 1, true) then
            travelType = "hearth"
            confidence = "high"
            isExplicit = true
            sourceKind = "mode"
        elseif mode:find("portal", 1, true) then
            travelType = "portal"
            confidence = "high"
            isExplicit = true
            sourceKind = "mode"
        elseif mode == "spell" or mode == "item" or mode == "toy" then
            travelType = "travel"
            confidence = "high"
            isExplicit = true
            sourceKind = "mode"
        elseif mode:find("taxi", 1, true) or mode:find("flight", 1, true) then
            travelType = "taxi"
            confidence = "low"
            isExplicit = false
            sourceKind = "mode"
        elseif mode:find("fly", 1, true) then
            -- "fly" is a broad LibRover graph-mode token. Keep the
            -- fallback so route legs still get a generic travel icon,
            -- but do not over-classify it as a taxi/flightpath without
            -- stronger node/title/coord proof.
            travelType = "travel"
            confidence = "low"
            isExplicit = false
            sourceKind = "mode"
        end
    end

    if type(routeTravelType) == "string"
        and (
            type(travelType) ~= "string"
            or (travelType == "travel" and sourceKind == "title")
        )
    then
        local routeSourceKind = "route-instance"
        if type(routeLegKind) == "string" and routeLegKind ~= "" then
            routeSourceKind = routeSourceKind .. ":" .. routeLegKind
        end
        return routeTravelType, "high", true, routeSourceKind, mode, routeSource or source
    end

    if type(travelType) ~= "string" then
        return nil
    end

    travelType, confidence, isExplicit, sourceKind = ValidatePortalTravelTypeCandidate(
        travelType,
        confidence,
        isExplicit,
        sourceKind,
        title
    )

    return travelType, confidence or "low", isExplicit == true, sourceKind or "unknown", mode, source
end

NS.GetWaypointTravelDescriptorFields = ResolveWaypointTravelDescriptorFields

function NS.GetWaypointTravelDescriptor(waypoint, source, title)
    local travelType, confidence, isExplicit, sourceKind, mode, descriptorSource =
        ResolveWaypointTravelDescriptorFields(waypoint, source, title)
    if type(travelType) ~= "string" then
        return nil
    end

    waypointTravelDescriptor.travelType = travelType
    waypointTravelDescriptor.confidence = confidence
    waypointTravelDescriptor.isExplicit = isExplicit
    waypointTravelDescriptor.sourceKind = sourceKind
    waypointTravelDescriptor.mode = mode
    waypointTravelDescriptor.source = descriptorSource
    return waypointTravelDescriptor
end

function NS.IsZygorSpecialTravelIconWaypoint(waypoint)
    if type(waypoint) ~= "table" then
        return false
    end

    local owner = NS.ResolveWaypointOwner(waypoint)
    local ownerType = owner and owner.type or waypoint.type
    if ownerType == "manual" or ownerType == "corpse" then
        return false
    end

    local node = GetWaypointTravelNode(waypoint)
    if type(node) ~= "table" then
        return false
    end

    local spell = GetTravelField(node, "spell")
    local item = GetTravelField(node, "item")
    local toy = GetTravelField(node, "toy")
    local arrivalToy = GetTravelField(node, "arrivaltoy")
    local initFunc = GetTravelField(node, "initfunc")
    local atlas = GetTravelField(node, "atlas")
    local mode = GetTravelField(node, "mode")

    if spell ~= nil or item ~= nil or toy ~= nil or arrivalToy ~= nil or initFunc ~= nil or atlas ~= nil then
        return true
    end

    if type(mode) == "string" then
        mode = mode:lower()
        if mode == "hearth" or mode == "spell" or mode == "item" or mode == "toy" or mode == "portal" then
            return true
        end
    end

    return false
end

-- ============================================================
-- Neutral special-action state accessors
-- ============================================================
--
-- Lightweight readers of state.routing.specialActionState. They live in
-- core/util.lua (loaded before overlay and routing modules) so consumers like
-- world_overlay/runtime/host.lua can bind them as file-local upvalues at
-- file load time without ordering against bridge/routing/special_actions.lua.
-- bridge/routing/special_actions.lua owns the secure frame and apply/disarm
-- logic only — these read accessors are intentionally split out.

function NS.IsActiveSpecialActionPresenting()
    local routing = NS.State and NS.State.routing
    return routing ~= nil and routing.specialActionPresented == true or false
end

function NS.GetActiveSpecialActionSignature()
    local routing = NS.State and NS.State.routing
    if routing and routing.specialActionPresented == true then
        return routing.specialActionPresentedSig
    end
    return nil
end

-- ============================================================
-- Internal Blizzard user-waypoint / supertrack mutations
-- ============================================================
--
-- The native overlay host uses C_Map.SetUserWaypoint/ClearUserWaypoint as
-- a hidden navigation host. Those calls must not be adopted back as
-- explicit manual Blizzard waypoints by the user-waypoint takeover hooks.

function NS.IsInternalUserWaypointMutation()
    local internal = NS.State and NS.State.internalUserWaypointMutation
    return type(internal) == "number" and internal > 0
end

function NS.WithInternalUserWaypointMutation(fn, ...)
    if type(fn) ~= "function" then
        return false
    end

    NS.State.internalUserWaypointMutation = (NS.State.internalUserWaypointMutation or 0) + 1
    local results = { pcall(fn, ...) }
    NS.State.internalUserWaypointMutation = math.max((NS.State.internalUserWaypointMutation or 1) - 1, 0)
    return unpack(results)
end

function NS.IsInternalSuperTrackMutation()
    local internal = NS.State and NS.State.internalSuperTrackMutation
    return type(internal) == "number" and internal > 0
end

function NS.WithInternalSuperTrackMutation(fn, ...)
    if type(fn) ~= "function" then
        return false
    end

    NS.State.internalSuperTrackMutation = (NS.State.internalSuperTrackMutation or 0) + 1
    local results = { pcall(fn, ...) }
    NS.State.internalSuperTrackMutation = math.max((NS.State.internalSuperTrackMutation or 1) - 1, 0)
    return unpack(results)
end

-- ============================================================
-- Zygor pointer access
-- ============================================================

function NS.GetZygorPointer()
    local Z = NS.ZGV()
    local P = Z and Z.Pointer
    if not P then
        return
    end

    return Z, P
end

function NS.GetArrowFrame()
    local Z, P = NS.GetZygorPointer()
    local frame = P and P.ArrowFrame
    if not frame then
        return
    end

    return Z, P, frame
end

function NS.ResolveWaypointBySource(source)
    local _, pointer, arrowFrame = NS.GetArrowFrame()
    if not pointer then
        _, pointer = NS.GetZygorPointer()
        arrowFrame = pointer and pointer.ArrowFrame or nil
    end
    if type(pointer) ~= "table" then
        return nil
    end

    if source == "pointer.ArrowFrame.waypoint" then
        return arrowFrame and arrowFrame.waypoint or nil
    end
    if source == "pointer.arrow.waypoint" then
        return pointer.arrow and pointer.arrow.waypoint or nil
    end
    if source == "pointer.DestinationWaypoint" then
        return pointer.DestinationWaypoint
    end
    if source == "pointer.waypoint" then
        return pointer.waypoint
    end
    if source == "pointer.current_waypoint" then
        return pointer.current_waypoint
    end
    if source == "pointer.waypoints[1]" then
        return type(pointer.waypoints) == "table" and pointer.waypoints[1] or nil
    end

    return nil
end

function NS.SafeCall(fn, ...)
    if type(fn) ~= "function" then
        return
    end

    return fn(...)
end

local _sigCacheM, _sigCacheX, _sigCacheY, _sigCacheResult

function NS.Signature(m, x, y)
    if type(x) == "number" then
        x = math.floor(x * 10000 + 0.5) / 10000
    end
    if type(y) == "number" then
        y = math.floor(y * 10000 + 0.5) / 10000
    end
    if m == _sigCacheM and x == _sigCacheX and y == _sigCacheY then
        return _sigCacheResult
    end
    local result = string.format("%s:%.4f:%.4f", tostring(m), x or 0, y or 0)
    _sigCacheM = m
    _sigCacheX = x
    _sigCacheY = y
    _sigCacheResult = result
    return result
end
