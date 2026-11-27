-- ============================================================
-- Flight Map Assist
-- ============================================================
--
-- Owns the active route marker and automatic flight selection for the open
-- taxi window. The matcher supplies an offer, Assist checks the same offer
-- again before calling the native take-flight action.

local NS = _G.AzerothWaypointNS
local C = NS.Constants
local state = NS.State
local TaxiWindow = NS.Internal.TaxiWindow
local ResolveRouteMatch = TaxiWindow.ResolveRouteMatch
local DescribeRouteMatch = TaxiWindow.DescribeRouteMatch

state.flightMapAssist = state.flightMapAssist or {}

local assist = state.flightMapAssist
local TAXI_ATLAS = "Taxi_Frame_Yellow"
local TAXI_ICON_TEXTURE = "Interface\\TaxiFrame\\UI-Taxi-Icon-Yellow"
local MARKER_FALLBACK_SIZE = 24
local MARKER_MIN_SIZE = 12
local MARKER_MAX_SIZE = 36

-- ============================================================
-- Flight markers
-- ============================================================

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

local function ClearMarker(reason)
    -- The cache holds a snapshot with native pins. Release it when the map closes.
    if reason == "map_hidden" then assist.guideMatchCache = nil end
    assist.currentMatch = nil
    assist.lastClearReason = reason
    if assist.marker then
        assist.marker:Hide()
        assist.marker:ClearAllPoints()
        assist.marker:SetScale(1)
        assist.marker:SetParent(UIParent)
    end
end

local function AnchorMarker(frame, match)
    local pin = match and match.pin or nil
    if type(pin) ~= "table" or not TaxiWindow.IsVisible(pin) then
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
    marker:SetScale(TaxiWindow.GetPinRelativeScale(pin, marker:GetParent()))
    local size = TaxiWindow.MeasurePin(pin) or MARKER_FALLBACK_SIZE
    local markerSize = math.max(MARKER_MIN_SIZE, math.min(MARKER_MAX_SIZE, size))
    marker:SetSize(markerSize, markerSize)
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", pin, "CENTER", 0, 0)
    marker:Show()

    assist.lastMatchConfidence = match.confidence
    assist.lastMatchNodeID = match.nodeID
    assist.currentMatch = DescribeRouteMatch(match)
    assist.lastClearReason = nil
    return true
end

-- ============================================================
-- Automatic flight selection
-- ============================================================

-- A taxi slot belongs to the open window. Recheck the offer and its route
-- immediately before taking it, then allow one successful selection per open.
local function IsAutoTakeAllowedForMatch(match, settings)
    if not match or not match.departureVerified then return false end
    local mode = settings and settings.autoTakeMode or C.FLIGHT_MAP_AUTO_TAKE_DISABLED
    if mode == C.FLIGHT_MAP_AUTO_TAKE_DISABLED then
        return false
    end
    if not match.slotIndex then
        return false
    end
    if mode == C.FLIGHT_MAP_AUTO_TAKE_EXACT and match.confidence ~= "exact" then
        return false
    end
    if mode ~= C.FLIGHT_MAP_AUTO_TAKE_EXACT and mode ~= C.FLIGHT_MAP_AUTO_TAKE_STRONG then
        return false
    end
    if type(IsAltKeyDown) == "function" and IsAltKeyDown() then
        return false
    end
    return true
end

local function MaybeAutoTake(frame, match, settings)
    if not IsAutoTakeAllowedForMatch(match, settings) then
        return
    end
    local openSerial = TaxiWindow.GetOpenSerial(frame)
    if not openSerial or assist.autoTakeSerial == openSerial then return end
    local current = ResolveRouteMatch(frame, assist)
    if not current or not current.departureVerified or current.authority ~= match.authority
        or current.window ~= match.window or current.leg ~= match.leg or current.slotIndex ~= match.slotIndex
        or current.nodeID ~= match.nodeID or TaxiWindow.GetOpenFrame() ~= frame
        or TaxiWindow.GetOpenSerial(frame) ~= openSerial then
        return
    end
    assist.autoTakeSerial = openSerial
    local name = match.node and match.node.name
    if TaxiWindow.Take(match.slotIndex, match.nodeID, name) then
        if name and NS.RecordFlightMapCatalogRecent then NS.RecordFlightMapCatalogRecent(name) end
    else
        assist.autoTakeSerial = nil
    end
end

-- ============================================================
-- Refreshing the marker and current offer
-- ============================================================

local function RefreshInternal(reason)
    local settings = type(NS.GetFlightMapAssistSettings) == "function" and NS.GetFlightMapAssistSettings() or nil
    local frame = TaxiWindow.GetOpenFrame()
    if not settings or settings.marker ~= true or not frame then
        ClearMarker(not settings and "no_settings" or not frame and "map_hidden" or "marker_disabled")
        return false
    end

    local match, missReason = ResolveRouteMatch(frame, assist)
    if not match then
        ClearMarker(missReason or reason or "no_match")
        return false
    end

    if AnchorMarker(frame, match) then
        MaybeAutoTake(frame, match, settings)
        return true
    end
    return false
end

function NS.RefreshFlightMapAssist()
    if not assist.initialized then
        return false
    end
    local frame = TaxiWindow.GetOpenFrame()
    local refreshed = false
    if frame then
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
    local frame = TaxiWindow.GetOpenFrame()
    if not frame then
        assist.currentMatch = nil
        return nil, "map_hidden"
    end
    local match, reason = ResolveRouteMatch(frame, assist)
    assist.currentMatch = DescribeRouteMatch(match)
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
    TaxiWindow.Subscribe(function(frame)
        if frame then RefreshInternal("taximap_changed") else ClearMarker("map_hidden") end
    end)
end
