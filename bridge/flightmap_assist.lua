local NS = _G.AzerothWaypointNS
local C = NS.Constants
local state = NS.State
local SafeCall = NS.SafeCall or function(fn, ...)
    if type(fn) == "function" then
        return fn(...)
    end
    return nil
end

state.flightMapAssist = state.flightMapAssist or {}

local assist = state.flightMapAssist
local TAXI_ATLAS = "Taxi_Frame_Yellow"
local TAXI_ICON_TEXTURE = "Interface\\TaxiFrame\\UI-Taxi-Icon-Yellow"
local PIN_TEMPLATE = "FlightMap_FlightPointPinTemplate"
local STRONG_MATCH_EPSILON = type(NS.GetTaxiCoordEpsilon) == "function" and NS.GetTaxiCoordEpsilon() or 0.0015
local REFIND_INTERVAL_SECONDS = 0.25
local RETRY_DELAYS = { 0, 0.08, 0.18, 0.35, 0.70 }
local MARKER_FALLBACK_SIZE = 24
local MARKER_MIN_SIZE = 12
local MARKER_MAX_SIZE = 36

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

local function ReadPosition(position)
    if type(position) ~= "table" then
        return nil, nil
    end
    if type(position.GetXY) == "function" then
        local ok, x, y = pcall(position.GetXY, position)
        if ok and type(x) == "number" and type(y) == "number" then
            return x > 1 and x / 100 or x, y > 1 and y / 100 or y
        end
    end
    local x = type(position.x) == "number" and position.x or type(position[1]) == "number" and position[1] or nil
    local y = type(position.y) == "number" and position.y or type(position[2]) == "number" and position[2] or nil
    if type(x) ~= "number" or type(y) ~= "number" then
        return nil, nil
    end
    if x > 1 then
        x = x / 100
    end
    if y > 1 then
        y = y / 100
    end
    return x, y
end

local function IsReachableTaxiState(value)
    if value == nil then
        return false
    end
    if type(Enum) == "table" and type(Enum.FlightPathState) == "table" then
        local reachable = Enum.FlightPathState.Reachable
        if reachable ~= nil and value == reachable then
            return true
        end
    end
    if type(value) == "string" then
        local key = value:lower()
        return key == "reachable" or key == "available"
    end
    return false
end

local function IsCurrentTaxiState(value)
    if value == nil then
        return false
    end
    if type(Enum) == "table" and type(Enum.FlightPathState) == "table" then
        local current = Enum.FlightPathState.Current
        if current ~= nil and value == current then
            return true
        end
    end
    return type(value) == "string" and value:lower() == "current"
end

local function IsTaxiLeg(leg)
    if type(leg) ~= "table" then
        return false
    end
    return type(leg.taxi) == "table"
        or leg.kind == "taxi"
        or leg.routeTravelType == "taxi"
end

local function GetOpenFlightMapFrame()
    local frame = rawget(_G, "FlightMapFrame")
    if type(frame) ~= "table" then
        return nil
    end
    if type(frame.IsShown) == "function" and not frame:IsShown() then
        return nil
    end
    return frame
end

local function GetFlightMapCanvas(frame)
    if frame and type(frame.GetMap) == "function" then
        local ok, map = pcall(frame.GetMap, frame)
        if ok and type(map) == "table" then
            return map
        end
    end
    return frame
end

local function GetDisplayedMapID(frame)
    if not frame then
        return nil
    end
    if type(frame.GetMapID) == "function" then
        local ok, mapID = pcall(frame.GetMapID, frame)
        if ok and type(mapID) == "number" then
            return mapID
        end
    end
    local map = GetFlightMapCanvas(frame)
    if map ~= frame and type(map.GetMapID) == "function" then
        local ok, mapID = pcall(map.GetMapID, map)
        if ok and type(mapID) == "number" then
            return mapID
        end
    end
    return type(frame.mapID) == "number" and frame.mapID or nil
end

local function EnumerateActivePins(frame, out)
    local seen = {}
    local function addPin(pin)
        if type(pin) == "table" and not seen[pin] then
            seen[pin] = true
            out[#out + 1] = pin
        end
    end

    local pools = type(frame.pinPools) == "table" and frame.pinPools or nil
    local pool = pools and pools[PIN_TEMPLATE] or nil
    if pool and type(pool.EnumerateActive) == "function" then
        for pin in pool:EnumerateActive() do
            addPin(pin)
        end
    end

    local map = GetFlightMapCanvas(frame)
    if map and type(map.EnumeratePinsByTemplate) == "function" then
        for pin in map:EnumeratePinsByTemplate(PIN_TEMPLATE) do
            addPin(pin)
        end
    end
end

local function IsPinVisible(pin)
    if type(pin) ~= "table" then
        return false
    end
    if type(pin.IsShown) == "function" and not pin:IsShown() then
        return false
    end
    if type(pin.IsVisible) == "function" and not pin:IsVisible() then
        return false
    end
    return true
end

local function ReadPinNodeData(pin)
    local data = pin and (pin.taxiNodeData or pin.nodeData or pin.data) or nil
    if type(data) ~= "table" then
        return nil
    end
    local x, y = ReadPosition(data.position)
    return {
        nodeID = tonumber(data.nodeID or data.taxinodeID or data.taxiNodeID),
        slotIndex = tonumber(data.slotIndex or data.slot),
        name = TrimString(data.name),
        state = data.state,
        x = x,
        y = y,
        pin = pin,
    }
end

local function MergeTaxiMapData(nodesByID, displayedMapID)
    if type(displayedMapID) ~= "number" then
        return
    end
    if type(C_TaxiMap) ~= "table" or type(C_TaxiMap.GetTaxiNodesForMap) ~= "function" then
        return
    end
    local nodes = C_TaxiMap.GetTaxiNodesForMap(displayedMapID)
    if type(nodes) ~= "table" then
        return
    end
    for index = 1, #nodes do
        local source = nodes[index]
        if type(source) == "table" then
            local nodeID = tonumber(source.nodeID)
            local target = nodeID and nodesByID[nodeID] or nil
            if target then
                target.slotIndex = target.slotIndex or tonumber(rawget(source, "slotIndex"))
                target.name = target.name or TrimString(source.name)
                target.state = target.state or rawget(source, "state")
                if not target.x or not target.y then
                    target.x, target.y = ReadPosition(source.position)
                end
            end
        end
    end
end

local function BuildVisibleReachableNodes(frame)
    local pins = {}
    local nodes = {}
    local byNodeID = {}

    EnumerateActivePins(frame, pins)
    for index = 1, #pins do
        local pin = pins[index]
        if IsPinVisible(pin) then
            local node = ReadPinNodeData(pin)
            if node and node.nodeID then
                nodes[#nodes + 1] = node
                byNodeID[node.nodeID] = node
            end
        end
    end

    MergeTaxiMapData(byNodeID, GetDisplayedMapID(frame))

    local reachable = {}
    local reachableByID = {}
    for index = 1, #nodes do
        local node = nodes[index]
        if IsReachableTaxiState(node.state) and not IsCurrentTaxiState(node.state) then
            reachable[#reachable + 1] = node
            reachableByID[node.nodeID] = node
        end
    end

    return reachable, reachableByID
end

local function CoordsClose(aX, aY, bX, bY)
    return type(aX) == "number"
        and type(aY) == "number"
        and type(bX) == "number"
        and type(bY) == "number"
        and math.abs(aX - bX) <= STRONG_MATCH_EPSILON
        and math.abs(aY - bY) <= STRONG_MATCH_EPSILON
end

local function MatchLeg(frame, leg, reachable, reachableByID)
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

    local displayedMapID = GetDisplayedMapID(frame)
    if type(displayedMapID) ~= "number" or leg.mapID ~= displayedMapID then
        return nil
    end
    local titleName = GetUsableDestinationName(leg.title)
    local candidates = {}
    for index = 1, #reachable do
        local node = reachable[index]
        if CoordsClose(leg.x, leg.y, node.x, node.y) then
            if not titleName or NamesAgree(titleName, node.name) then
                candidates[#candidates + 1] = node
            end
        end
    end
    if #candidates ~= 1 then
        return nil
    end

    local node = candidates[1]
    return {
        confidence = "strong",
        leg = leg,
        node = node,
        nodeID = node.nodeID,
        slotIndex = node.slotIndex,
        pin = node.pin,
    }
end

local function CollectTaxiRun(record)
    local legs = type(record) == "table" and record.legs or nil
    if type(legs) ~= "table" or #legs == 0 then
        return nil
    end

    local current = math.max(1, tonumber(record.currentLegIndex) or 1)
    local firstTaxi = nil
    for index = current, #legs do
        if IsTaxiLeg(legs[index]) then
            firstTaxi = index
            break
        end
    end
    if not firstTaxi then
        return nil
    end

    local run = {}
    for index = firstTaxi, #legs do
        local leg = legs[index]
        if not IsTaxiLeg(leg) then
            break
        end
        run[#run + 1] = leg
    end
    return run
end

local function ResolveTaxiMatch(frame)
    if type(NS.IsRoutingEnabled) == "function" and not NS.IsRoutingEnabled() then
        return nil, "routing_disabled"
    end
    if type(NS.GetActiveAuthorityRecord) ~= "function" then
        return nil, "no_authority_api"
    end

    local record = NS.GetActiveAuthorityRecord()
    local run = CollectTaxiRun(record)
    if type(run) ~= "table" or #run == 0 then
        return nil, "no_taxi_run"
    end

    local reachable, reachableByID = BuildVisibleReachableNodes(frame)
    if #reachable == 0 then
        return nil, "no_reachable_nodes"
    end

    local function tryList(preferFinal)
        for index = #run, 1, -1 do
            local leg = run[index]
            local taxi = type(leg.taxi) == "table" and leg.taxi or nil
            local isFinal = taxi and taxi.final == true or false
            if isFinal == preferFinal then
                local match = MatchLeg(frame, leg, reachable, reachableByID)
                if match then
                    return match
                end
            end
        end
        return nil
    end

    return tryList(true) or tryList(false), "no_match"
end

local function EnsureMarker()
    if assist.marker then
        return assist.marker
    end

    local marker = CreateFrame("Frame", "AWPFlightMapAssistMarker", UIParent)
    marker:SetSize(MARKER_FALLBACK_SIZE, MARKER_FALLBACK_SIZE)
    marker:SetFrameStrata("HIGH")
    marker:Hide()

    local icon = marker:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints(marker)
    local atlasSet = false
    if type(icon.SetAtlas) == "function" then
        local ok = pcall(icon.SetAtlas, icon, TAXI_ATLAS, false)
        atlasSet = ok == true
    end
    if not atlasSet then
        icon:SetTexture(TAXI_ICON_TEXTURE)
    end
    marker.Icon = icon

    local pulse = marker:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.62)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.55)
    alpha:SetSmoothing("IN_OUT")
    marker.Pulse = pulse
    pulse:Play()

    assist.marker = marker
    return marker
end

local function ClampMarkerSize(size)
    size = tonumber(size) or MARKER_FALLBACK_SIZE
    if size < MARKER_MIN_SIZE then
        return MARKER_MIN_SIZE
    end
    if size > MARKER_MAX_SIZE then
        return MARKER_MAX_SIZE
    end
    return size
end

local function ReadRegionSize(region)
    if type(region) ~= "table" then
        return nil, nil
    end
    if type(region.GetSize) == "function" then
        local ok, width, height = pcall(region.GetSize, region)
        if ok and type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
            return width, height
        end
    end
    local width = type(region.GetWidth) == "function" and region:GetWidth() or nil
    local height = type(region.GetHeight) == "function" and region:GetHeight() or nil
    if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        return width, height
    end
    return nil, nil
end

local function ResolvePinMarkerSize(pin)
    local width, height = ReadRegionSize(pin)
    local best = width and height and math.max(width, height) or nil

    if type(pin) == "table" and type(pin.GetRegions) == "function" then
        local regions = { pin:GetRegions() }
        for index = 1, #regions do
            local regionWidth, regionHeight = ReadRegionSize(regions[index])
            if regionWidth and regionHeight then
                local regionSize = math.max(regionWidth, regionHeight)
                if regionSize > 0 and (not best or regionSize < best) then
                    best = regionSize
                end
            end
        end
    end

    return ClampMarkerSize(best)
end

local function ResolvePinRelativeScale(pin, parent)
    if type(pin) ~= "table" or type(parent) ~= "table" then
        return 1
    end
    if type(pin.GetEffectiveScale) == "function" and type(parent.GetEffectiveScale) == "function" then
        local pinScale = pin:GetEffectiveScale()
        local parentScale = parent:GetEffectiveScale()
        if type(pinScale) == "number" and type(parentScale) == "number" and parentScale > 0 then
            return pinScale / parentScale
        end
    end
    if type(pin.GetScale) == "function" then
        local scale = pin:GetScale()
        if type(scale) == "number" and scale > 0 then
            return scale
        end
    end
    return 1
end

local function ClearMarker(reason)
    assist.lastMatchSig = nil
    assist.currentMatch = nil
    assist.lastClearReason = reason
    if assist.marker then
        assist.marker:Hide()
        assist.marker:ClearAllPoints()
        assist.marker:SetScale(1)
        assist.marker:SetParent(UIParent)
    end
end

local function BuildMatchSig(match)
    if type(match) ~= "table" then
        return nil
    end
    local leg = match.leg or {}
    return table.concat({
        tostring(match.confidence or "-"),
        tostring(match.nodeID or "-"),
        tostring(match.slotIndex or "-"),
        tostring(leg.mapID or "-"),
        tostring(leg.x or "-"),
        tostring(leg.y or "-"),
    }, "|")
end

local function SanitizeMatch(match)
    if type(match) ~= "table" then
        return nil
    end
    local node = type(match.node) == "table" and match.node or nil
    return {
        nodeID = tonumber(match.nodeID),
        slotIndex = tonumber(match.slotIndex),
        name = TrimString(node and node.name) or StripDisplayMarkup(match.leg and match.leg.title) or "Flight Path",
        confidence = match.confidence,
        state = node and node.state or nil,
    }
end

local function AnchorMarker(frame, match)
    local pin = match and match.pin or nil
    if type(pin) ~= "table" or not IsPinVisible(pin) then
        ClearMarker("pin_unavailable")
        return false
    end

    local marker = EnsureMarker()
    local parent = type(pin.GetParent) == "function" and pin:GetParent() or nil
    local strata = type(pin.GetFrameStrata) == "function" and pin:GetFrameStrata() or nil
    local level = type(pin.GetFrameLevel) == "function" and pin:GetFrameLevel() or nil
    marker:SetParent(parent or frame or UIParent)
    marker:SetFrameStrata(strata or "HIGH")
    marker:SetFrameLevel((level or 10) + 20)
    marker:SetScale(ResolvePinRelativeScale(pin, marker:GetParent()))
    local markerSize = ResolvePinMarkerSize(pin)
    marker:SetSize(markerSize, markerSize)
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", pin, "CENTER", 0, 0)
    marker:Show()

    assist.lastMatchSig = BuildMatchSig(match)
    assist.lastMatchConfidence = match.confidence
    assist.lastMatchNodeID = match.nodeID
    assist.currentMatch = SanitizeMatch(match)
    assist.lastClearReason = nil
    return true
end

local function IsAutoTakeAllowedForMatch(match, settings)
    local mode = settings and settings.autoTakeMode or C.FLIGHT_MAP_AUTO_TAKE_DISABLED
    if mode == C.FLIGHT_MAP_AUTO_TAKE_DISABLED then
        return false
    end
    if not match or not match.slotIndex then
        return false
    end
    if mode == C.FLIGHT_MAP_AUTO_TAKE_EXACT and match.confidence ~= "exact" then
        return false
    end
    if mode ~= C.FLIGHT_MAP_AUTO_TAKE_EXACT and mode ~= C.FLIGHT_MAP_AUTO_TAKE_STRONG then
        return false
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return false
    end
    if type(UnitOnTaxi) == "function" and UnitOnTaxi("player") then
        return false
    end
    if type(IsAltKeyDown) == "function" and IsAltKeyDown() then
        return false
    end
    if not IsReachableTaxiState(match.node and match.node.state) then
        return false
    end
    return true
end

local function MaybeAutoTake(match, settings)
    if not IsAutoTakeAllowedForMatch(match, settings) then
        return
    end
    local openSerial = tonumber(assist.openSerial) or 0
    local nodeID = tonumber(match.nodeID) or 0
    local takeSig = tostring(openSerial) .. ":" .. tostring(nodeID)
    if assist.lastAutoTakeSig == takeSig then
        return
    end
    assist.lastAutoTakeSig = takeSig

    if type(IsMounted) == "function" and IsMounted() and type(Dismount) == "function" then
        SafeCall(Dismount)
    end
    if type(TakeTaxiNode) == "function" then
        SafeCall(TakeTaxiNode, match.slotIndex)
        if type(NS.RecordFlightMapCatalogRecent) == "function" and match.node and match.node.name then
            NS.RecordFlightMapCatalogRecent(match.node.name)
        end
    end
end

local function RefreshInternal(reason)
    local settings = type(NS.GetFlightMapAssistSettings) == "function" and NS.GetFlightMapAssistSettings() or nil
    local frame = GetOpenFlightMapFrame()
    if not settings or settings.marker ~= true or not frame then
        ClearMarker(not settings and "no_settings" or not frame and "map_hidden" or "marker_disabled")
        return false
    end

    local match, missReason = ResolveTaxiMatch(frame)
    if not match then
        ClearMarker(missReason or reason or "no_match")
        return false
    end

    if AnchorMarker(frame, match) then
        MaybeAutoTake(match, settings)
        return true
    end
    return false
end

local function ScheduleRefresh(reason)
    assist.retrySerial = (tonumber(assist.retrySerial) or 0) + 1
    local serial = assist.retrySerial
    for index = 1, #RETRY_DELAYS do
        local delay = RETRY_DELAYS[index]
        if type(NS.After) == "function" then
            NS.After(delay, function()
                if assist.retrySerial == serial then
                    RefreshInternal(reason or "retry")
                end
            end)
        elseif type(C_Timer) == "table" and type(C_Timer.After) == "function" then
            C_Timer.After(delay, function()
                if assist.retrySerial == serial then
                    RefreshInternal(reason or "retry")
                end
            end)
        else
            RefreshInternal(reason or "retry")
            return
        end
    end
end

local function HookFlightMapHide()
    if assist.hideHooked then
        return
    end
    local frame = rawget(_G, "FlightMapFrame")
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" then
        return
    end
    frame:HookScript("OnHide", function()
        ClearMarker("flightmap_hide")
    end)
    assist.hideHooked = true
end

function NS.RefreshFlightMapAssist()
    if not assist.initialized then
        return false
    end
    local frame = GetOpenFlightMapFrame()
    local refreshed = false
    if frame then
        HookFlightMapHide()
        refreshed = RefreshInternal("external")
    else
        ClearMarker("map_hidden")
    end
    if type(NS.RefreshFlightMapCatalog) == "function" then
        NS.RefreshFlightMapCatalog()
    end
    return refreshed
end

function NS.GetFlightMapAssistMatch()
    local frame = GetOpenFlightMapFrame()
    if not frame then
        assist.currentMatch = nil
        return nil, "map_hidden"
    end
    local match, reason = ResolveTaxiMatch(frame)
    assist.currentMatch = SanitizeMatch(match)
    return assist.currentMatch, reason
end

function NS.GetFlightMapAssistStatus()
    local settings = type(NS.GetFlightMapAssistSettings) == "function" and NS.GetFlightMapAssistSettings() or nil
    local marker = settings and settings.marker and "on" or "off"
    local auto = settings and settings.autoTakeMode or C.FLIGHT_MAP_AUTO_TAKE_DISABLED
    local active = assist.marker and type(assist.marker.IsShown) == "function" and assist.marker:IsShown()
    local activeText = active and "shown" or "hidden"
    return string.format("marker %s, auto %s, marker frame %s", marker, auto, activeText)
end

function NS.InitializeFlightMapAssist()
    if assist.initialized then
        return
    end
    assist.initialized = true
    assist.openSerial = 0

    local frame = CreateFrame("Frame")
    assist.eventFrame = frame
    frame:RegisterEvent("TAXIMAP_OPENED")
    frame:RegisterEvent("TAXIMAP_CLOSED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "TAXIMAP_OPENED" then
            assist.openSerial = (tonumber(assist.openSerial) or 0) + 1
            HookFlightMapHide()
            ScheduleRefresh("taximap_opened")
        elseif event == "TAXIMAP_CLOSED" then
            assist.retrySerial = (tonumber(assist.retrySerial) or 0) + 1
            ClearMarker("taximap_closed")
        end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        if not GetOpenFlightMapFrame() then
            return
        end
        assist.refindElapsed = (assist.refindElapsed or 0) + (tonumber(elapsed) or 0)
        if assist.refindElapsed < REFIND_INTERVAL_SECONDS then
            return
        end
        assist.refindElapsed = 0
        RefreshInternal("refind")
    end)

    HookFlightMapHide()
    if GetOpenFlightMapFrame() then
        ScheduleRefresh("init")
    end
end
