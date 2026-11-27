-- ============================================================
-- Flight map destination list
-- ============================================================
--
-- Builds the searchable flight list, fare display and hover marker for the
-- open taxi window. Rows and hover artwork consume the taxi window snapshot.
-- Selecting a row still goes through that window's flight-selection checks.

local NS = _G.AzerothWaypointNS
local C = NS.Constants
local state = NS.State
local TaxiWindow = NS.Internal.TaxiWindow
local Appearance = NS.Internal.Appearance
local APPEARANCE_SURFACE = "windows.taxi"

state.flightMapCatalog = state.flightMapCatalog or {}

local catalog = state.flightMapCatalog
local TAXI_YELLOW_ATLAS = "Taxi_Frame_Yellow"
local TAXI_GRAY_ATLAS = "Taxi_Frame_Gray"
local TAXI_YELLOW_TEXTURE = "Interface\\TaxiFrame\\UI-Taxi-Icon-Yellow"
local TAXI_GRAY_TEXTURE = "Interface\\TaxiFrame\\UI-Taxi-Icon-Gray"
local STAR_TEXTURE = "Interface\\Common\\ReputationStar"
local PANEL_WIDTH = 300
local PANEL_TOP_INSET = 18
local PANEL_BOTTOM_INSET = 34
local PANEL_MIN_HEIGHT_RATIO = 0.50
local PANEL_MIN_HEIGHT_FLOOR = 260
local PANEL_CHROME_HEIGHT = 74
local ROW_HEIGHT = 30
local HEADER_HEIGHT = 22
local LAYOUT_CHECK_INTERVAL_SECONDS = 0.10
local LAYOUT_EPSILON = 0.5
local HOVER_MARKER_FALLBACK_SIZE = 24
local HOVER_MARKER_MIN_SIZE = 12
local HOVER_MARKER_MAX_SIZE = 40
local HOVER_MARKER_SIZE_MULTIPLIER = 1.15

-- The panel's search callback refreshes the list, and the first refresh creates the panel.
local RefreshInternal

local COLORS = {
    panel = { 0.018, 0.014, 0.010, 0.94 },
    header = { 1.00, 0.82, 0.05, 1 },
    text = { 0.96, 0.92, 0.84, 1 },
    dim = { 0.66, 0.61, 0.52, 1 },
    route = { 0.98, 0.82, 0.18, 1 },
    favorite = { 1.00, 0.72, 0.20, 1 },
    recent = { 0.58, 0.88, 1.00, 1 },
    normal = { 0.78, 0.95, 1.00, 1 },
    hoverBlue = { 0.22, 0.72, 1.00, 1 },
    green = { 0.45, 1.00, 0.42, 1 },
}

local HOVER_COLORS = {
    route = COLORS.hoverBlue,
    favorite = COLORS.hoverBlue,
    recent = COLORS.hoverBlue,
    normal = COLORS.hoverBlue,
}

local function GetCatalogFontSize(settings)
    local fontSize = settings and settings.fontSize
    if type(NS.NormalizeFlightMapCatalogFontSize) == "function" then
        return NS.NormalizeFlightMapCatalogFontSize(fontSize)
    end
    return tonumber(fontSize) or (C and C.FLIGHT_MAP_CATALOG_FONT_SIZE_DEFAULT) or 12
end

local function GetCatalogSublineFontSize(fontSize)
    return math.max(8, (tonumber(fontSize) or 12) - 2)
end

local function GetNodeRowHeight(fontSize)
    local titleSize = tonumber(fontSize) or 12
    local sublineSize = GetCatalogSublineFontSize(titleSize)
    return math.max(ROW_HEIGHT, math.ceil(titleSize + sublineSize + 8))
end

local function SetFontStringSize(fontString, fontFile, fontSize, fontFlags)
    if not fontString or not fontFile or not fontSize then
        return
    end
    fontString:SetFont(fontFile, fontSize, fontFlags)
end

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

local function NormalizeSearch(value)
    value = TrimString(value)
    if not value then
        return ""
    end
    value = value:lower():gsub("[%-%_]+", " "):gsub("%s+", " ")
    return TrimString(value) or ""
end

local function SearchMatches(haystack, needle)
    if needle == "" then
        return true
    end
    haystack = NormalizeSearch(haystack)
    return haystack:find(needle, 1, true) ~= nil
end

local function NormalizeZoneName(value)
    value = TrimString(value)
    if not value then
        return nil
    end
    value = value:lower():gsub("[%-%_]+", " "):gsub("%s+", " ")
    return TrimString(value)
end

local function GetCurrentZoneName()
    local zone = nil
    if type(GetRealZoneText) == "function" then
        zone = TrimString(GetRealZoneText())
    end
    if not zone and type(GetZoneText) == "function" then
        zone = TrimString(GetZoneText())
    end
    return zone
end

local function IsCurrentZoneNode(node, currentZoneKey)
    if type(node) ~= "table" or not currentZoneKey then
        return false
    end
    return NormalizeZoneName(node.zone) == currentZoneKey
end

local function HydrateFlightTime(node)
    if type(node) ~= "table" then
        return nil
    end
    if node.flightTime == nil and type(NS.GetFlightMapTaxiTime) == "function" then
        node.flightTime = NS.GetFlightMapTaxiTime(node.slotIndex, node.nodeID) or false
    end
    return node.flightTime ~= false and node.flightTime or nil
end

local function FormatFlightTime(node)
    local info = HydrateFlightTime(node)
    if type(NS.FormatFlightMapTaxiTime) ~= "function" then
        return nil
    end
    return NS.FormatFlightMapTaxiTime(info)
end

local function FormatFare(fare, fontSize)
    if type(fare) == "string" then return fare end
    if fare == 0 then return rawget(_G, "FREE") or "Free" end
    if type(fare) == "number" and C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(fare, fontSize)
    end
end

local function BuildNodeSubline(node, extraText)
    local parts = {}
    extraText = TrimString(extraText)
    if extraText then
        parts[#parts + 1] = extraText
    end
    local zone = TrimString(node and node.zone)
    if zone and zone ~= "Other" then
        parts[#parts + 1] = zone
    end
    local timeText = FormatFlightTime(node)
    if timeText then
        parts[#parts + 1] = timeText
    end
    return table.concat(parts, " - ")
end

local function SetTexture(texture, atlas, fallback, tint)
    if not texture then
        return
    end
    local atlasSet = false
    if atlas and type(texture.SetAtlas) == "function" then
        atlasSet = pcall(texture.SetAtlas, texture, atlas, false) == true
    end
    if not atlasSet and fallback then
        texture:SetTexture(fallback)
    end
    texture:SetTexCoord(0, 1, 0, 1)
    if type(texture.SetDesaturated) == "function" then
        texture:SetDesaturated(false)
    end
    texture:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1, tint and tint[4] or 1)
end

local function SetColor(texture, color)
    if texture and type(texture.SetColorTexture) == "function" then
        texture:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
    end
end

local function GetFrameHeight(frame)
    if type(frame) == "table" and type(frame.GetHeight) == "function" then
        local height = tonumber(frame:GetHeight())
        if height and height > 0 then
            return height
        end
    end
    return 520
end

local function IsUsableLayoutFrame(candidate, parentHeight)
    if type(candidate) ~= "table" then
        return false
    end
    if type(candidate.IsShown) == "function" and not candidate:IsShown() then
        return false
    end
    local height = GetFrameHeight(candidate)
    return height >= math.max(120, (tonumber(parentHeight) or 520) * 0.45)
end

local function GetFlightMapLayoutFrame(frame)
    local frameHeight = GetFrameHeight(frame)
    local candidate = frame and rawget(frame, "ScrollContainer")
    if IsUsableLayoutFrame(candidate, frameHeight) then
        return candidate
    end
    candidate = frame and rawget(frame, "mapCanvas")
    if IsUsableLayoutFrame(candidate, frameHeight) then
        return candidate
    end
    candidate = frame and rawget(frame, "MapCanvas")
    if IsUsableLayoutFrame(candidate, frameHeight) then
        return candidate
    end
    candidate = TaxiWindow.GetCanvas(frame)
    if IsUsableLayoutFrame(candidate, frameHeight) then
        return candidate
    end
    return frame
end

local function GetLayoutYOffset(frame, layoutFrame)
    if type(frame) ~= "table" or type(layoutFrame) ~= "table" or frame == layoutFrame then
        return 0
    end
    if type(frame.GetTop) ~= "function" or type(frame.GetBottom) ~= "function" or
        type(layoutFrame.GetTop) ~= "function" or type(layoutFrame.GetBottom) ~= "function"
    then
        return 0
    end

    local frameTop, frameBottom = frame:GetTop(), frame:GetBottom()
    local layoutTop, layoutBottom = layoutFrame:GetTop(), layoutFrame:GetBottom()
    if not frameTop or not frameBottom or not layoutTop or not layoutBottom then
        return 0
    end

    return ((layoutTop + layoutBottom) / 2) - ((frameTop + frameBottom) / 2)
end

local function ParseTaxiName(fullName)
    fullName = TrimString(fullName) or "Flight Path"
    local place, zone = fullName:match("^(.-),%s*([^,]+)$")
    place = TrimString(place)
    zone = TrimString(zone)
    if place and zone then
        return place, zone
    end
    return fullName, "Other"
end

-- ============================================================
-- Reachable flights in the current taxi window
-- ============================================================

local function BuildReachableNodes(frame)
    local window = TaxiWindow.GetSnapshot(frame)
    local cached = catalog.reachableNodes
    if cached and cached.window == window then return cached.nodes, cached.byName, cached.bySlot, cached.byID end
    local nodes, byName, bySlot, byID = {}, {}, {}, {}
    for _, taxi in ipairs(window.reachable) do
        local place, zone = ParseTaxiName(taxi.name)
        local node = {
            fullName = taxi.name,
            place = place,
            zone = zone,
            slotIndex = taxi.slotIndex,
            nodeID = taxi.nodeID,
            fare = TaxiWindow.GetFare(window, taxi.slotIndex)
        }
        HydrateFlightTime(node)
        nodes[#nodes + 1] = node
        byName[node.fullName], bySlot[node.slotIndex] = node, node
        if node.nodeID then byID[node.nodeID] = node end
    end
    table.sort(nodes, function(a, b)
        local az, bz = a.zone:lower(), b.zone:lower()
        if az ~= bz then return az < bz end
        return a.place:lower() < b.place:lower()
    end)
    catalog.reachableNodes = { window = window, nodes = nodes, byName = byName, bySlot = bySlot, byID = byID }
    return nodes, byName, bySlot, byID
end

local function NormalizeFavorites(favorites)
    if type(favorites) ~= "table" then
        return {}
    end
    local normalized = {}
    local changed = false
    for key, value in pairs(favorites) do
        if value == true and type(key) == "string" then
            normalized[key] = true
        elseif type(value) == "string" then
            normalized[value] = true
            changed = true
        else
            changed = true
        end
    end
    if changed then
        for key in pairs(favorites) do
            favorites[key] = nil
        end
        for key, value in pairs(normalized) do
            favorites[key] = value
        end
    end
    return favorites
end

local function NormalizeRecent(recent, maxCount)
    if type(recent) ~= "table" then
        return {}
    end
    maxCount = math.max(1, tonumber(maxCount) or 12)
    local seen = {}
    local writeIndex = 0
    for readIndex = 1, #recent do
        local value = TrimString(recent[readIndex])
        if value and not seen[value] then
            writeIndex = writeIndex + 1
            recent[writeIndex] = value
            seen[value] = true
        end
    end
    while #recent > writeIndex do
        table.remove(recent)
    end
    while #recent > maxCount do
        table.remove(recent)
    end
    return recent
end

local function GetNodeKey(node)
    if type(node) ~= "table" then
        return nil
    end
    return node.nodeID and ("node:" .. tostring(node.nodeID))
        or node.slotIndex and ("slot:" .. tostring(node.slotIndex))
        or node.fullName and ("name:" .. node.fullName)
        or nil
end

local function MarkUsed(used, node)
    local key = GetNodeKey(node)
    if key then
        used[key] = true
    end
end

local function IsUsed(used, node)
    local key = GetNodeKey(node)
    return key and used[key] == true or false
end

local function FindRouteNode(match, byName, bySlot, byNodeID)
    if type(match) ~= "table" then
        return nil
    end
    local node = match.nodeID and byNodeID[match.nodeID]
        or match.slotIndex and bySlot[match.slotIndex]
        or match.name and byName[match.name]
        or nil
    if node then
        node.routeConfidence = match.confidence
        node.routeSource, node.routeProviderLabel = match.source, match.providerLabel
        return node
    end
    if match.slotIndex then
        local fullName = TrimString(match.name) or "Flight Path"
        local place, zone = ParseTaxiName(fullName)
        return {
            fullName = fullName,
            place = place,
            zone = zone,
            slotIndex = match.slotIndex,
            nodeID = match.nodeID,
            fare = TaxiWindow.GetFare(TaxiWindow.GetSnapshot(), match.slotIndex),
            routeConfidence = match.confidence,
            routeSource = match.source,
            routeProviderLabel = match.providerLabel,
        }
    end
    return nil
end

local function BuildDisplayRows(frame)
    local rows = {}
    local nodes, byName, bySlot, byNodeID = BuildReachableNodes(frame)
    local settings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or {}
    local favorites = NormalizeFavorites(settings.favorites)
    local recent = NormalizeRecent(settings.recent, settings.recentMax)
    local search = NormalizeSearch(catalog.searchText or "")
    local used = {}
    local lowerMatchCount = 0

    local function addHeader(text)
        rows[#rows + 1] = { type = "header", text = text }
    end

    local function addNode(kind, node, extraText)
        HydrateFlightTime(node)
        rows[#rows + 1] = {
            type = "node",
            kind = kind,
            node = node,
            extraText = extraText,
            favorite = node and favorites[node.fullName] == true,
        }
        if kind ~= "route" then
            lowerMatchCount = lowerMatchCount + 1
        end
        MarkUsed(used, node)
    end

    local routeMatch = type(NS.GetFlightMapAssistMatch) == "function" and NS.GetFlightMapAssistMatch() or nil
    local routeNode = FindRouteNode(routeMatch, byName, bySlot, byNodeID)
    if routeNode then
        local guideLabel = routeNode.routeSource == "guide" and
            ((routeNode.routeProviderLabel or "Guide") .. " Guide Suggestion")
        addHeader(guideLabel or "Route Destination")
        addNode("route", routeNode,
            guideLabel or (routeNode.routeConfidence == "exact" and "Exact taxi match" or "Strong flight-map match"))
    end

    local favoriteNodes = {}
    for index = 1, #nodes do
        local node = nodes[index]
        if favorites[node.fullName] == true and not IsUsed(used, node) and
            (SearchMatches(node.fullName, search) or SearchMatches(node.zone, search))
        then
            favoriteNodes[#favoriteNodes + 1] = node
        end
    end
    table.sort(favoriteNodes, function(a, b)
        return (a.fullName or ""):lower() < (b.fullName or ""):lower()
    end)
    if #favoriteNodes > 0 then
        addHeader("Favorites")
        for index = 1, #favoriteNodes do
            addNode("favorite", favoriteNodes[index], "Favorite")
        end
    end

    local recentNodes = {}
    for index = 1, #recent do
        local node = byName[recent[index]]
        if node and not IsUsed(used, node) and
            (SearchMatches(node.fullName, search) or SearchMatches(node.zone, search))
        then
            recentNodes[#recentNodes + 1] = node
        end
    end
    if #recentNodes > 0 then
        addHeader("Recent")
        for index = 1, #recentNodes do
            addNode("recent", recentNodes[index], "Recent flight")
        end
    end

    local currentZoneName = GetCurrentZoneName()
    local currentZoneKey = NormalizeZoneName(currentZoneName)
    local currentZoneNodes = {}
    for index = 1, #nodes do
        local node = nodes[index]
        if not IsUsed(used, node)
            and IsCurrentZoneNode(node, currentZoneKey)
            and (SearchMatches(node.fullName, search) or SearchMatches(node.zone, search))
        then
            currentZoneNodes[#currentZoneNodes + 1] = node
        end
    end
    if #currentZoneNodes > 0 then
        addHeader("Current Zone")
        for index = 1, #currentZoneNodes do
            addNode("normal", currentZoneNodes[index])
        end
    end

    local currentZone = nil
    for index = 1, #nodes do
        local node = nodes[index]
        if not IsUsed(used, node) and (SearchMatches(node.fullName, search) or SearchMatches(node.zone, search)) then
            if node.zone ~= currentZone then
                currentZone = node.zone
                addHeader(currentZone or "Other")
            end
            addNode("normal", node)
        end
    end

    if #rows == 0 or (routeNode and lowerMatchCount == 0 and search ~= "") then
        rows[#rows + 1] = {
            type = "empty",
            text = search ~= "" and "No matching reachable flight paths." or "No reachable flight paths available.",
        }
    end

    return rows
end

local function MeasureRowsHeight(rows, fontSize)
    local height = 0
    rows = type(rows) == "table" and rows or nil
    if not rows then
        return height
    end
    local rowHeight = GetNodeRowHeight(fontSize)
    for index = 1, #rows do
        height = height + (rows[index].type == "header" and HEADER_HEIGHT or rowHeight)
    end
    return height
end

local function ResolvePanelHeight(frame, rows, layoutFrame, settings)
    local frameHeight = GetFrameHeight(frame)
    local layoutHeight = GetFrameHeight(layoutFrame or frame)

    local maxHeight = math.max(PANEL_MIN_HEIGHT_FLOOR, frameHeight - PANEL_TOP_INSET - PANEL_BOTTOM_INSET)
    local minHeight = math.max(PANEL_MIN_HEIGHT_FLOOR, math.floor((layoutHeight * PANEL_MIN_HEIGHT_RATIO) + 0.5))
    minHeight = math.min(minHeight, maxHeight)

    local contentHeight = PANEL_CHROME_HEIGHT + MeasureRowsHeight(rows, GetCatalogFontSize(settings))
    if contentHeight <= minHeight then
        return minHeight
    end
    if contentHeight >= maxHeight then
        return maxHeight
    end
    return contentHeight
end

local function ResolvePanelSide(frame, requested)
    requested = type(NS.NormalizeFlightMapCatalogSide) == "function" and NS.NormalizeFlightMapCatalogSide(requested) or
        "auto"
    if requested == "left" or requested == "right" then
        return requested
    end

    local parent = UIParent
    local rightSpace = 0
    local leftSpace = 0
    if frame and type(frame.GetRight) == "function" and type(parent.GetRight) == "function" then
        rightSpace = (parent:GetRight() or 0) - (frame:GetRight() or 0)
    end
    if frame and type(frame.GetLeft) == "function" then
        leftSpace = frame:GetLeft() or 0
    end
    if rightSpace >= PANEL_WIDTH + 18 then
        return "right"
    end
    if leftSpace >= PANEL_WIDTH + 18 then
        return "left"
    end
    return "right"
end

local function ReadFrameMetric(frame, method)
    if type(frame) == "table" and type(frame[method]) == "function" then
        return tonumber(frame[method](frame))
    end
    return nil
end

local function MetricChanged(previous, current)
    if previous == nil or current == nil then
        return previous ~= current
    end
    return math.abs(previous - current) > LAYOUT_EPSILON
end

local function CaptureLayoutSnapshot(frame, layoutFrame)
    local parent = UIParent
    catalog.layoutFrame = frame
    catalog.layoutAnchorFrame = layoutFrame
    catalog.layoutLeft = ReadFrameMetric(frame, "GetLeft")
    catalog.layoutRight = ReadFrameMetric(frame, "GetRight")
    catalog.layoutTop = ReadFrameMetric(frame, "GetTop")
    catalog.layoutBottom = ReadFrameMetric(frame, "GetBottom")
    catalog.layoutWidth = ReadFrameMetric(frame, "GetWidth")
    catalog.layoutHeight = ReadFrameMetric(frame, "GetHeight")
    catalog.layoutAnchorTop = ReadFrameMetric(layoutFrame, "GetTop")
    catalog.layoutAnchorBottom = ReadFrameMetric(layoutFrame, "GetBottom")
    catalog.layoutParentRight = ReadFrameMetric(parent, "GetRight")
end

local function IsLayoutSnapshotChanged(frame)
    if type(frame) ~= "table" then
        return false
    end
    local layoutFrame = GetFlightMapLayoutFrame(frame)
    local parent = UIParent
    return catalog.layoutFrame ~= frame
        or catalog.layoutAnchorFrame ~= layoutFrame
        or MetricChanged(catalog.layoutLeft, ReadFrameMetric(frame, "GetLeft"))
        or MetricChanged(catalog.layoutRight, ReadFrameMetric(frame, "GetRight"))
        or MetricChanged(catalog.layoutTop, ReadFrameMetric(frame, "GetTop"))
        or MetricChanged(catalog.layoutBottom, ReadFrameMetric(frame, "GetBottom"))
        or MetricChanged(catalog.layoutWidth, ReadFrameMetric(frame, "GetWidth"))
        or MetricChanged(catalog.layoutHeight, ReadFrameMetric(frame, "GetHeight"))
        or MetricChanged(catalog.layoutAnchorTop, ReadFrameMetric(layoutFrame, "GetTop"))
        or MetricChanged(catalog.layoutAnchorBottom, ReadFrameMetric(layoutFrame, "GetBottom"))
        or MetricChanged(catalog.layoutParentRight, ReadFrameMetric(parent, "GetRight"))
end

-- ============================================================
-- Hover marker and node interaction
-- ============================================================

local function EnsureHoverMarker()
    if catalog.hoverMarker then
        return catalog.hoverMarker
    end
    local marker = CreateFrame("Frame", "AWPFlightMapCatalogHoverMarker", UIParent)
    marker:SetSize(28, 28)
    marker:SetFrameStrata("HIGH")
    marker:Hide()

    marker.icon = marker:CreateTexture(nil, "OVERLAY")
    marker.icon:SetAllPoints()
    marker.icon:SetBlendMode("ADD")
    SetTexture(marker.icon, TAXI_GRAY_ATLAS, TAXI_GRAY_TEXTURE, COLORS.normal)

    marker.pulse = marker:CreateAnimationGroup()
    marker.pulse:SetLooping("BOUNCE")
    local alpha = marker.pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.38)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.42)
    alpha:SetSmoothing("IN_OUT")
    marker.pulse:Play()

    catalog.hoverMarker = marker
    return marker
end

function NS.HideFlightMapCatalogHover()
    if catalog.hoverMarker then
        catalog.hoverMarker:Hide()
        catalog.hoverMarker:ClearAllPoints()
        catalog.hoverMarker:SetScale(1)
        catalog.hoverMarker:SetParent(UIParent)
    end
end

function NS.ShowFlightMapCatalogHover(slotIndex, nodeID, rowKind)
    local frame = TaxiWindow.GetOpenFrame()
    if not frame then
        NS.HideFlightMapCatalogHover()
        return false
    end
    local pin = TaxiWindow.GetAnchor(frame, tonumber(slotIndex), tonumber(nodeID))
    if not pin then
        NS.HideFlightMapCatalogHover()
        return false
    end

    local marker = EnsureHoverMarker()
    local parent = type(pin.GetParent) == "function" and pin:GetParent() or frame
    local level = type(pin.GetFrameLevel) == "function" and pin:GetFrameLevel() or 10
    local color = HOVER_COLORS[rowKind] or HOVER_COLORS.normal
    marker:SetParent(parent or frame)
    marker:SetFrameLevel(level + 25)
    marker:SetScale(TaxiWindow.GetPinRelativeScale(pin, marker:GetParent()))
    local size = TaxiWindow.MeasurePin(pin) or HOVER_MARKER_FALLBACK_SIZE
    local markerSize = math.max(HOVER_MARKER_MIN_SIZE,
        math.min(HOVER_MARKER_MAX_SIZE, size * HOVER_MARKER_SIZE_MULTIPLIER))
    marker:SetSize(markerSize, markerSize)
    marker.icon:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    marker:ClearAllPoints()
    marker:SetPoint("CENTER", pin, "CENTER", 0, 0)
    marker:Show()
    if marker.pulse and not marker.pulse:IsPlaying() then
        marker.pulse:Play()
    end
    return true
end

local function RecordRecent(fullName)
    fullName = TrimString(fullName)
    if not fullName then
        return
    end
    local settings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
    if not settings then
        return
    end
    local recent = NormalizeRecent(settings.recent, settings.recentMax)
    for index = #recent, 1, -1 do
        if recent[index] == fullName then
            table.remove(recent, index)
        end
    end
    table.insert(recent, 1, fullName)
    while #recent > settings.recentMax do
        table.remove(recent)
    end
    if type(NS.SetFlightMapCatalogSetting) == "function" then
        NS.SetFlightMapCatalogSetting("recent", recent)
    end
end

function NS.RecordFlightMapCatalogRecent(fullName)
    RecordRecent(fullName)
end

local function ToggleFavorite(fullName)
    fullName = TrimString(fullName)
    if not fullName then
        return
    end
    local settings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
    if not settings then
        return
    end
    local favorites = NormalizeFavorites(settings.favorites)
    favorites[fullName] = favorites[fullName] ~= true or nil
    if type(NS.SetFlightMapCatalogSetting) == "function" then
        NS.SetFlightMapCatalogSetting("favorites", favorites)
    end
end

local function TakeNode(node)
    if node and TaxiWindow.Take(node.slotIndex, node.nodeID, node.fullName) then
        RecordRecent(node.fullName)
    end
end

local function ShowRowTooltip(row)
    if not GameTooltip or not row or not row.node then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.node.fullName or "Flight Path", 1, 1, 1)
    if row.node.zone and row.node.place and row.node.zone ~= "Other" then
        GameTooltip:AddLine(row.node.zone, 0.75, 0.70, 0.62, true)
    end
    local fareText = FormatFare(row.node.fare, 14)
    if fareText then GameTooltip:AddLine("Fare: " .. fareText, 1, 1, 1, true) end
    local timeText = FormatFlightTime(row.node)
    if timeText then
        local label = row.node.flightTime and row.node.flightTime.estimated and "Estimated flight time: " or
            "Flight time: "
        GameTooltip:AddLine(label .. timeText, 0.58, 0.88, 1.00, true)
    end
    GameTooltip:AddLine("Left-click to take this flight.", 0.55, 0.85, 1, true)
    GameTooltip:AddLine(row.favorite and "Right-click to remove favorite." or "Right-click to favorite.", 1, 0.82, 0.16,
        true)
    GameTooltip:Show()
end

-- ============================================================
-- Catalog rows and panel layout
-- ============================================================

local function ClearRowHover()
    local row = catalog.hoveredRow
    catalog.hoveredRow = nil
    NS.HideFlightMapCatalogHover()
    if row and GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function ShowRowHover(row, showTooltip)
    catalog.hoveredRow = row
    NS.ShowFlightMapCatalogHover(row.node.slotIndex, row.node.nodeID, row.kind)
    if showTooltip then ShowRowTooltip(row) end
end

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    SetColor(row.bg, { 0, 0, 0, 0 })

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.icon:SetSize(18, 18)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.titleFontFile, row.titleFontSize, row.titleFontFlags = row.title:GetFont()

    row.fare = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.fare:SetPoint("TOPRIGHT", row, "TOPRIGHT", -24, -4)
    row.fare:SetJustifyH("RIGHT")
    row.fare:SetWordWrap(false)
    row.fare:Hide()

    row.subline = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.subline:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
    row.subline:SetPoint("RIGHT", row, "RIGHT", -24, 0)
    row.subline:SetJustifyH("LEFT")
    row.subline:SetWordWrap(false)
    row.subline:SetTextColor(unpack(COLORS.dim))
    row.sublineFontFile, row.sublineFontSize, row.sublineFontFlags = row.subline:GetFont()

    row.favoriteIcon = row:CreateTexture(nil, "ARTWORK")
    row.favoriteIcon:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.favoriteIcon:SetSize(14, 14)
    row.favoriteIcon:SetTexture(STAR_TEXTURE)

    row.headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.headerText:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.headerText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.headerText:SetJustifyH("LEFT")
    row.headerText:SetTextColor(COLORS.header[1], COLORS.header[2], COLORS.header[3], COLORS.header[4])
    if Appearance then
        Appearance.Text(row.headerText, APPEARANCE_SURFACE, "TITLE")
        Appearance.RegisterVisual(row, { kind = "menuRow", regions = { row:GetHighlightTexture() } })
    end

    row:SetScript("OnEnter", function(self)
        if self.node then
            ShowRowHover(self, true)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if catalog.hoveredRow == self then ClearRowHover() end
    end)
    row:SetScript("OnClick", function(self, button)
        if not self.node then
            return
        end
        if button == "RightButton" then
            ToggleFavorite(self.node.fullName)
        else
            TakeNode(self.node)
        end
    end)

    return row
end

local function ApplyRowFontSize(row, fontSize)
    fontSize = tonumber(fontSize) or 12
    if row.catalogFontSize == fontSize then
        return
    end
    row.catalogFontSize = fontSize
    SetFontStringSize(row.title, row.titleFontFile, fontSize, row.titleFontFlags)
    SetFontStringSize(row.fare, row.titleFontFile, fontSize, row.titleFontFlags)
    SetFontStringSize(row.subline, row.sublineFontFile, GetCatalogSublineFontSize(fontSize), row.sublineFontFlags)
    if Appearance then
        Appearance.Text(row.fare, APPEARANCE_SURFACE, "TEXT")
        Appearance.Text(row.subline, APPEARANCE_SURFACE, "LABEL")
    end
    return true
end

local function ApplyRowTitleColor(row, color)
    row.title:SetTextColor(unpack(color))
    if Appearance then Appearance.Text(row.title, APPEARANCE_SURFACE, "TEXT") end
end

local function ApplyNodeRow(row, data, fontSize, width)
    local node = data.node
    local kind = data.kind or "normal"
    if ApplyRowFontSize(row, fontSize) or row.kind ~= kind then
        ApplyRowTitleColor(row, COLORS[kind] or COLORS.text)
    end
    row:SetHeight(GetNodeRowHeight(fontSize))
    row:Enable()
    row.type = data.type
    row.kind = kind
    row.node = node
    row.favorite = data.favorite == true
    row.icon:Show()
    row.title:Show()
    row.subline:Show()
    local fareChanged = row.fareAmount ~= node.fare or row.fareFontSize ~= fontSize
    if fareChanged then
        row.fareAmount, row.fareFontSize = node.fare, fontSize
        row.fareText = FormatFare(node.fare, fontSize)
        row.fare:SetText(row.fareText or "")
    end
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 30, -4)
    row.fare:SetShown(row.fareText ~= nil)
    if row.fareText then
        local file, _, flags = row.fare:GetFont()
        if fareChanged or row.measuredFareFont ~= file or row.measuredFareFlags ~= flags then
            row.measuredFareFont, row.measuredFareFlags = file, flags
            row.fareWidth = math.ceil(row.fare:GetUnboundedStringWidth()) + 1
        end
        row.fare:SetWidth(math.min(row.fareWidth, math.floor(width * 0.4)))
        row.title:SetPoint("TOPRIGHT", row.fare, "TOPLEFT", -8, 0)
    else
        row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -24, -4)
    end
    if row.favorite then
        row.favoriteIcon:Show()
    else
        row.favoriteIcon:Hide()
    end
    row.headerText:Hide()
    SetTexture(row.icon, TAXI_YELLOW_ATLAS, TAXI_YELLOW_TEXTURE)
    row.title:SetText(node.place or node.fullName or "Flight Path")
    row.subline:SetText(BuildNodeSubline(node, data.extraText))
    if kind == "route" then
        SetColor(row.bg, { 0.32, 0.22, 0.04, 0.28 })
    elseif kind == "favorite" then
        SetColor(row.bg, { 0.24, 0.16, 0.04, 0.18 })
    elseif kind == "recent" then
        SetColor(row.bg, { 0.04, 0.12, 0.18, 0.16 })
    else
        SetColor(row.bg, { 0, 0, 0, 0 })
    end
end

local function ApplyHeaderRow(row, data)
    row:SetHeight(HEADER_HEIGHT)
    row:Disable()
    row.type = data.type
    row.kind = nil
    row.node = nil
    row.favorite = false
    row.icon:Hide()
    row.title:Hide()
    row.subline:Hide()
    row.fare:Hide()
    row.favoriteIcon:Hide()
    row.headerText:Show()
    row.headerText:SetText(data.text or "")
    SetColor(row.bg, { 0.20, 0.14, 0.02, 0.30 })
end

local function ApplyEmptyRow(row, data, fontSize)
    if ApplyRowFontSize(row, fontSize) or row.type ~= data.type then
        ApplyRowTitleColor(row, COLORS.dim)
    end
    row:SetHeight(GetNodeRowHeight(fontSize))
    row:Disable()
    row.type = data.type
    row.kind = nil
    row.node = nil
    row.favorite = false
    row.icon:Hide()
    row.title:Show()
    row.title:ClearAllPoints()
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
    row.title:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.title:SetText(data.text or "")
    row.subline:Hide()
    row.fare:Hide()
    row.favoriteIcon:Hide()
    row.headerText:Hide()
    SetColor(row.bg, { 0, 0, 0, 0 })
end

local function RenderRows(frame, rows)
    if not catalog.panel or not catalog.child or not catalog.scroll then
        return
    end

    rows = rows or BuildDisplayRows(frame)
    local settings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
    local fontSize = GetCatalogFontSize(settings)
    local width = math.max((catalog.scroll:GetWidth() or 0), PANEL_WIDTH - 34)
    catalog.child:SetWidth(width)

    local cursorY = 0
    for index = 1, #rows do
        local row = catalog.rows[index]
        if not row then
            row = CreateRow(catalog.child)
            catalog.rows[index] = row
        end
        local data = rows[index]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", catalog.child, "TOPLEFT", 0, -cursorY)
        row:SetPoint("RIGHT", catalog.child, "RIGHT", 0, 0)
        row:Show()
        if data.type == "header" then
            ApplyHeaderRow(row, data)
        elseif data.type == "empty" then
            ApplyEmptyRow(row, data, fontSize)
        else
            ApplyNodeRow(row, data, fontSize, width)
        end
        cursorY = cursorY + row:GetHeight()
    end

    for index = #rows + 1, #catalog.rows do
        catalog.rows[index]:Hide()
    end
    catalog.child:SetHeight(math.max(cursorY, catalog.scroll:GetHeight() or 1))
    -- Pooled rows can change destination under a stationary pointer.
    local hovered = catalog.hoveredRow
    if hovered then
        if hovered:IsVisible() and hovered.node then
            ShowRowHover(hovered, GameTooltip and GameTooltip:IsOwned(hovered))
        else
            ClearRowHover()
        end
    end
end

local function EnsurePanel(frame)
    if catalog.panel then
        return catalog.panel
    end

    local panel = CreateFrame("Frame", "AWPFlightMapCatalogPanel", frame)
    panel:SetSize(PANEL_WIDTH, 480)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:Hide()
    if Appearance then Appearance.Tag(panel, APPEARANCE_SURFACE) end

    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints()
    SetColor(panel.bg, COLORS.panel)
    local border = NS.UIStyle and NS.UIStyle.AddSimpleBorder(panel)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    panel.title:SetText("AWP Taxi List")
    panel.title:SetTextColor(COLORS.header[1], COLORS.header[2], COLORS.header[3], COLORS.header[4])

    local panelUI = NS.Internal.Interface.Framework
    panel.collapse = panelUI.CreateDisclosureButton(panel)
    panel.collapse:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -7)
    panel.collapse:SetScript("OnClick", function()
        if type(NS.SetFlightMapCatalogSetting) == "function" then
            NS.SetFlightMapCatalogSetting("collapsed", true)
        end
    end)

    panel.search = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.search:SetAutoFocus(false)
    panel.search:SetHeight(22)
    panel.search:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -34)
    panel.search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -34)
    panel.search:SetTextInsets(6, 6, 0, 0)
    panel.search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    panel.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    panel.search:SetScript("OnTextChanged", function(self)
        catalog.searchText = self:GetText() or ""
        if catalog.syncingSearchText then
            return
        end
        local mapFrame = TaxiWindow.GetOpenFrame()
        if mapFrame and catalog.panel and catalog.panel:IsShown() then
            RefreshInternal({ skipSearchSync = true })
        end
    end)

    panel.searchHint = panel.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    panel.searchHint:SetPoint("LEFT", panel.search, "LEFT", 8, 0)
    panel.searchHint:SetText("Search")
    panel.search:HookScript("OnTextChanged", function(self)
        panel.searchHint:SetShown((self:GetText() or "") == "")
    end)

    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -62)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 10)
    panel.child = CreateFrame("Frame", nil, panel.scroll)
    panel.child:SetSize(PANEL_WIDTH - 32, 1)
    panel.scroll:SetScrollChild(panel.child)

    panelUI.StyleAttachedListScrollBar(panel.scroll, panel)

    local tab = CreateFrame("Button", "AWPFlightMapCatalogTab", frame)
    tab:SetSize(22, 70)
    tab:SetFrameStrata("HIGH")
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    SetColor(tab.bg, { 0.018, 0.014, 0.010, 0.92 })
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.text:SetPoint("CENTER")
    tab:SetScript("OnClick", function()
        local settings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
        if settings and type(NS.SetFlightMapCatalogSetting) == "function" then
            NS.SetFlightMapCatalogSetting("collapsed", not settings.collapsed)
        end
    end)

    catalog.panel = panel
    catalog.tab = tab
    catalog.scroll = panel.scroll
    catalog.child = panel.child
    catalog.rows = {}
    if Appearance then
        local shellRegions = { panel.bg }
        for _, region in ipairs(border or {}) do shellRegions[#shellRegions + 1] = region end
        Appearance.Shell(panel, APPEARANCE_SURFACE, shellRegions, nil, "window")
        Appearance.Text(panel.title, APPEARANCE_SURFACE, "TITLE")
        Appearance.Text(tab.text, APPEARANCE_SURFACE, "TEXT", "shell")
        Appearance.RegisterVisual(tab,
            { kind = "button", surface = APPEARANCE_SURFACE, text = tab.text, regions = { tab.bg } })
        Appearance.Text(panel.search, APPEARANCE_SURFACE, "TEXT")
        Appearance.Text(panel.searchHint, APPEARANCE_SURFACE, "LABEL")
        local searchArt = {}
        for _, region in ipairs({ panel.search:GetRegions() }) do
            if region:GetObjectType() == "Texture" then searchArt[#searchArt + 1] = region end
        end
        Appearance.RegisterVisual(panel.search, { kind = "input", regions = searchArt })
        Appearance.RegisterReflow(panel, function()
            if catalog.renderedRows then RenderRows(nil, catalog.renderedRows) end
        end)
    end
    return panel
end

local function LayoutPanel(frame, settings, rows)
    local panel = EnsurePanel(frame)
    local tab = catalog.tab
    local side = ResolvePanelSide(frame, settings.side)
    catalog.resolvedSide = side

    panel:SetParent(frame)
    tab:SetParent(frame)

    local layoutFrame = GetFlightMapLayoutFrame(frame)
    local yOffset = GetLayoutYOffset(frame, layoutFrame)
    panel:SetHeight(ResolvePanelHeight(frame, rows, layoutFrame, settings))
    panel:ClearAllPoints()
    if side == "left" then
        panel:SetPoint("RIGHT", frame, "LEFT", -8, yOffset)
    else
        panel:SetPoint("LEFT", frame, "RIGHT", 8, yOffset)
    end

    tab:ClearAllPoints()
    if settings.collapsed then
        if side == "left" then
            tab:SetPoint("RIGHT", frame, "LEFT", -2, yOffset)
            tab.text:SetText("<")
        else
            tab:SetPoint("LEFT", frame, "RIGHT", 2, yOffset)
            tab.text:SetText(">")
        end
    else
        if side == "left" then
            tab:SetPoint("RIGHT", panel, "LEFT", -2, 0)
            tab.text:SetText(">")
        else
            tab:SetPoint("LEFT", panel, "RIGHT", 2, 0)
            tab.text:SetText("<")
        end
    end
    CaptureLayoutSnapshot(frame, layoutFrame)
end

local function RefreshLayoutOnly()
    local settings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
    local frame = TaxiWindow.GetOpenFrame()
    if not settings or settings.enabled ~= true or not frame or not catalog.panel or not catalog.tab then
        return false
    end

    LayoutPanel(frame, settings, not settings.collapsed and catalog.renderedRows or nil)
    catalog.tab:Show()
    catalog.panel:SetShown(settings.collapsed ~= true)
    if settings.collapsed then
        ClearRowHover()
    end
    return true
end

-- ============================================================
-- Window lifecycle and cache invalidation
-- ============================================================

local function HideCatalog()
    catalog.reachableNodes = nil
    catalog.renderedRows = nil
    catalog.layoutFrame = nil
    catalog.layoutAnchorFrame = nil
    if catalog.layoutDriver then catalog.layoutDriver:Hide() end
    if catalog.panel then
        catalog.panel:Hide()
    end
    if catalog.tab then
        catalog.tab:Hide()
    end
    ClearRowHover()
end

RefreshInternal = function(options)
    local settings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
    local frame = TaxiWindow.GetOpenFrame()
    if not settings or settings.enabled ~= true or not frame then
        HideCatalog()
        return false
    end

    if options and options.resetSearch then
        catalog.searchText = ""
    end

    local panel = EnsurePanel(frame)
    if not (options and options.skipSearchSync) and panel.search and panel.search:GetText() ~= (catalog.searchText or "") then
        catalog.syncingSearchText = true
        panel.search:SetText(catalog.searchText or "")
        catalog.syncingSearchText = false
    end

    local rows = not settings.collapsed and BuildDisplayRows(frame) or nil
    catalog.renderedRows = rows
    LayoutPanel(frame, settings, rows)
    catalog.tab:Show()
    catalog.layoutDriver:Show()
    panel:SetShown(settings.collapsed ~= true)
    if settings.collapsed then
        ClearRowHover()
        return true
    end

    RenderRows(frame, rows)
    return true
end

function NS.RefreshFlightMapCatalog(options)
    if not catalog.initialized then
        return false
    end
    return RefreshInternal(options)
end

function NS.GetFlightMapCatalogStatus()
    local settings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
    if not settings then
        return "unavailable"
    end
    local visible = catalog.panel and catalog.panel:IsShown() and "shown" or settings.collapsed and "collapsed" or
        "hidden"
    return string.format("%s, %s, side %s, text %d px",
        settings.enabled and "on" or "off",
        visible,
        settings.side or "auto",
        GetCatalogFontSize(settings))
end

function NS.InitializeFlightMapCatalog()
    if catalog.initialized then
        return
    end
    catalog.initialized = true
    catalog.searchText = catalog.searchText or ""

    local frame = CreateFrame("Frame")
    catalog.layoutDriver = frame
    frame:Hide()
    TaxiWindow.Subscribe(function(mapFrame)
        if mapFrame then
            RefreshInternal()
        else
            HideCatalog()
        end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        catalog.layoutElapsed = (catalog.layoutElapsed or 0) + (tonumber(elapsed) or 0)
        if catalog.layoutElapsed < LAYOUT_CHECK_INTERVAL_SECONDS then
            return
        end
        catalog.layoutElapsed = 0
        local mapFrame = TaxiWindow.GetOpenFrame()
        if mapFrame and IsLayoutSnapshotChanged(mapFrame) then
            RefreshLayoutOnly()
        end
    end)
end
