-- ============================================================
-- Queue map placement
-- ============================================================
--
-- Positions the queue tab and panel beside the map while accounting for
-- neighboring addon panels. Rescan for neighboring panels while the map is
-- open and reuse the last placement until its inputs change.

local NS = _G.AzerothWaypointNS
local M = NS.Internal.QueueUI
local MapHost = {}
M.MapHost = MapHost

local GAP = 8
local watched = setmetatable({}, { __mode = "k" })
local subscribed = false
local watchedMapzeroth

local function GetMapzerothFrame()
    return rawget(_G, "MapzerothRebuildPanel")
end

local function GetJournal(questMap)
    local journal = rawget(_G, "DaylightUIQuestJournal")
    if questMap and type(journal) == "table" and type(journal.GetParent) == "function" and journal:GetParent() == questMap then
        return journal
    end
end

local function HasGW2MapSkin(worldMap)
    -- GW2_UI creates this edge when it skins the map and reuses it for side tabs.
    return worldMap ~= nil and rawget(_G, "GW2_ADDON") ~= nil and worldMap.gwBodyEdge ~= nil
end

function MapHost.UsesCompanion(worldMap, questMap)
    if HasGW2MapSkin(worldMap) then return true end
    local journal = NS.IsWoWForever() and GetJournal(questMap)
    return journal and journal:IsShown() or false
end

function MapHost.UsesDetachedControls()
    if not NS.IsWoWForever() then return false end
    if InputUtil and type(InputUtil.IsGamepadUIEnabled) == "function" then
        local ok, enabled = pcall(InputUtil.IsGamepadUIEnabled)
        if ok then return enabled == true end
    end
    return type(GetCVar) == "function" and GetCVar("InputDeviceInterfaceStyle") == "1"
end

local function WatchFrame(frame, requestLayout, ...)
    if not frame or watched[frame] then return false end
    watched[frame] = true
    for index = 1, select("#", ...) do
        frame:HookScript(select(index, ...), requestLayout)
    end
    return true
end

local function WatchMapzeroth(requestLayout)
    WatchFrame(GetMapzerothFrame(), requestLayout, "OnShow", "OnHide", "OnSizeChanged")
    local addon = rawget(_G, "MapzerothAddon")
    local panel = addon and addon.Panel
    if not panel or panel == watchedMapzeroth or type(hooksecurefunc) ~= "function" then return end
    watchedMapzeroth = panel

    -- ============================================================
    -- Dock changes and map bounds
    -- ============================================================

    -- The frame is built on demand. Docking and scaling can also move a
    -- visible panel without an OnShow or a change in its unscaled size.
    local function DockChanged()
        if MapHost.UsesDetachedControls() then return end
        WatchFrame(GetMapzerothFrame(), requestLayout, "OnShow", "OnHide", "OnSizeChanged")
        requestLayout()
    end
    for _, method in ipairs({ "Reanchor", "SetDocked", "ApplyScale" }) do
        if type(panel[method]) == "function" then hooksecurefunc(panel, method, DockChanged) end
    end
end

function MapHost.Watch(worldMap, questMap, requestLayout, onMapHide)
    if MapHost.UsesDetachedControls() then return end
    local forever = NS.IsWoWForever()
    local journal = forever and GetJournal(questMap) or nil
    local daylight = NS.Internal.Daylight
    local api = forever and daylight and daylight.GetAPI()
    if not worldMap or not (journal or api or HasGW2MapSkin(worldMap)) then return end

    if WatchFrame(worldMap, requestLayout, "OnSizeChanged") then
        worldMap:HookScript("OnHide", onMapHide)
        -- Map skins can move the map from a separate drag handle.
        if hooksecurefunc and worldMap.StopMovingOrSizing then
            pcall(hooksecurefunc, worldMap, "StopMovingOrSizing", requestLayout)
        end
    end
    WatchFrame(questMap, requestLayout, "OnShow", "OnHide", "OnSizeChanged")
    WatchFrame(journal, requestLayout, "OnShow", "OnHide")
    WatchFrame(rawget(_G, "SpokenPlacesPanel"), requestLayout, "OnShow", "OnHide", "OnSizeChanged")
    WatchFrame(rawget(_G, "SpokenPlacesPanelToggle"), requestLayout, "OnShow", "OnHide")
    WatchMapzeroth(requestLayout)

    if api and type(api.On) == "function" and not subscribed then
        local ok, handle = pcall(api.On, "SettingChanged", function(scope, path)
            if scope == "Quests" and path == "journal" then requestLayout() end
        end, "AzerothWaypoint")
        subscribed = ok and handle ~= nil
        if subscribed then pcall(api.On, "Login", requestLayout, "AzerothWaypoint") end
    end
end

-- Compare frames and screen bounds in UIParent units even when the map is scaled.
local function GetRect(frame, uiScale)
    if not frame or not frame:IsVisible() then return end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then return end
    local scale = frame:GetEffectiveScale() / uiScale
    return { left = left * scale, right = right * scale, top = top * scale, bottom = bottom * scale }
end

local function Overlaps(rect, left, right, top, bottom)
    return rect.left < right and rect.right > left and rect.bottom < top and rect.top > bottom
end

local function IsReadable(frame)
    return type(frame) == "table" and (not frame.IsForbidden or not frame:IsForbidden())
end

-- A frame can have multiple parents/anchors leading to different branches.
-- A dependency on our controls wins over a map anchor to prevent feedback.
local function MapAttachment(frame, roots, own, seen, origin, depth)
    if own[frame] then return -1 end
    if roots[frame] then return 1 end
    if depth == 0 or not IsReadable(frame) or seen[frame] == origin then return 0 end
    seen[frame] = origin
    local parent = frame.GetParent and frame:GetParent()
    local match = parent ~= UIParent and MapAttachment(parent, roots, own, seen, origin, depth - 1) or 0
    if match < 0 then return match end
    for index = 1, frame.GetNumPoints and frame:GetNumPoints() or 0 do
        local _, anchor = frame:GetPoint(index)
        local branch = anchor ~= UIParent and MapAttachment(anchor, roots, own, seen, origin, depth - 1) or 0
        if branch < 0 then return branch end
        match = math.max(match, branch)
    end
    return match
end

local function CollectDetachedNeighbors(worldMap, questMap, tab, panel)
    local roots, own, found, neighbors, chrome = {}, {}, {}, {}, {}
    local hosts = { worldMap, questMap or false, worldMap.BorderFrame or false, worldMap.MiniBorderFrame or false }
    -- Native focus art and the map backdrop never reserve a side slot.
    if worldMap.BlackoutFrame then chrome[worldMap.BlackoutFrame] = true end
    for _, host in ipairs(hosts) do
        if host then
            roots[host] = true
            if host.FrameGlow then chrome[host.FrameGlow] = true end
        end
    end
    own[tab] = true
    if panel then own[panel] = true end

    -- Each candidate has its own traversal mark. Shared anchors must be
    -- reconsidered for the next candidate, and may change by the next scan.
    local seen = {}
    local function IsMapNeighbor(frame)
        return IsReadable(frame) and type(frame.IsVisible) == "function"
            and (not frame.GetObjectType or frame:GetObjectType() ~= "GameTooltip")
            and (not frame.GetFrameStrata or frame:GetFrameStrata() ~= "TOOLTIP")
            and MapAttachment(frame, roots, own, seen, frame, 12) == 1
    end
    local function Inspect(frame, attached)
        if found[frame] or roots[frame] or own[frame] or chrome[frame] then return end
        found[frame] = true
        local ok, matches = pcall(IsMapNeighbor, frame)
        if ok and matches then neighbors[frame] = attached end
    end

    for _, host in ipairs(hosts) do
        if host and host.GetChildren then
            for _, child in ipairs({ host:GetChildren() }) do Inspect(child, true) end
        end
    end
    for _, child in ipairs({ UIParent:GetChildren() }) do Inspect(child, false) end
    return neighbors
end

-- ============================================================
-- Detached neighbors and available space
-- ============================================================

local function SurroundsMap(rect, map)
    return rect.left <= map.left + GAP and rect.right >= map.right - GAP
        and rect.bottom <= map.bottom + GAP and rect.top >= map.top - GAP
end

-- Keep all layout math in UIParent units, and skip widgets with temporarily
-- unavailable or restricted geometry. Never change an obstacle's anchors.
local function DetachedObstacles(neighbors, map, edge, uiScale)
    local obstacles = {}
    local mapzeroth = GetMapzerothFrame()
    local function Read(frame)
        if not IsReadable(frame) or frame:GetEffectiveAlpha() <= 0 then return end
        local rect = GetRect(frame, uiScale)
        if rect and rect.right > rect.left and rect.top > rect.bottom
            and rect.left > -math.huge and rect.right < math.huge
            and rect.bottom > -math.huge and rect.top < math.huge then return rect end
    end
    for frame, attached in pairs(neighbors) do
        local ok, rect = pcall(Read, frame)
        -- Skins can add their own surrounds as children or detached frames.
        -- Their full bounds cover the map even when only the rim is painted.
        if ok and rect and rect.bottom < map.top and rect.top > map.bottom and not SurroundsMap(rect, map)
            and (not attached or rect.left < map.left or rect.right > edge or frame == mapzeroth) then
            obstacles[#obstacles + 1] = rect
        end
    end
    return obstacles
end

local function FreeTabTop(rects, left, width, height, top, bottom)
    while top - height >= bottom do
        local nextTop = top
        for _, rect in ipairs(rects) do
            if Overlaps(rect, left, left + width, top, top - height) then
                nextTop = math.min(nextTop, rect.bottom - GAP)
            end
        end
        if nextTop == top then return top end
        top = nextTop
    end
end

local function LargestStrip(rects, left, right, top, bottom)
    local blocks = {}
    for _, rect in ipairs(rects) do
        if Overlaps(rect, left, right, top, bottom) then blocks[#blocks + 1] = rect end
    end
    table.sort(blocks, function(a, b) return a.left < b.left end)
    local bestLeft, bestWidth = left, 0
    for _, rect in ipairs(blocks) do
        local width = rect.left - GAP - left
        if width > bestWidth then bestLeft, bestWidth = left, width end
        left = math.max(left, rect.right + GAP)
    end
    if right - left > bestWidth then return left, right - left end
    return bestLeft, bestWidth
end

local function SetDetachedPosition(frame, anchor, rect, left, top, uiScale)
    local scale = frame:GetEffectiveScale() / uiScale
    local x, y = (left - rect.left) / scale, (top - rect.top) / scale
    local point, relative, target, oldX, oldY = frame:GetPoint(1)
    if point == "TOPLEFT" and relative == anchor and target == "TOPLEFT"
        and math.abs((oldX or 0) - x) < 0.01 and math.abs((oldY or 0) - y) < 0.01 then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
end

local function FitDetachedPanel(panel, width, height, floating)
    if math.abs(panel:GetWidth() - width) >= 0.01 or math.abs(panel:GetHeight() - height) >= 0.01 then
        panel:SetSize(width, height)
    end
    if panel:IsClampedToScreen() ~= floating then panel:SetClampedToScreen(floating) end
end

local function FollowMapLayer(frame, map, level)
    local strata = map:GetFrameStrata()
    if frame:GetFrameStrata() ~= strata then frame:SetFrameStrata(strata) end
    if frame:GetFrameLevel() ~= level then frame:SetFrameLevel(level) end
end

function MapHost.PlaceStandalone(panel)
    local scale = UIParent:GetEffectiveScale()
    local screen = GetRect(UIParent, scale)
    if not screen then return end
    local width = math.min(400, screen.right - screen.left - 2 * GAP)
    local height = math.min(650, screen.top - screen.bottom - 2 * GAP)
    if width <= 0 or height <= 0 then return end
    FollowMapLayer(panel, UIParent, 10)
    FitDetachedPanel(panel, width, height, true)
    if not panel._awpMoved then
        SetDetachedPosition(panel, UIParent, screen, (screen.left + screen.right - width) / 2,
            (screen.top + screen.bottom + height) / 2, scale)
    end
end

local function PlaceDetachedTab(tab, worldMap, screen, map, insideLeft, insideRight, edge, obstacles, uiScale)
    local scale = worldMap:GetEffectiveScale() / uiScale
    if tab:GetScale() ~= scale then tab:SetScale(scale) end
    local width, height = tab:GetWidth() * scale, tab:GetHeight() * scale
    local bottom = math.max(map.bottom, screen.bottom)
    local preferredTop = math.min(map.top - 60, screen.top)
    local left, top
    local columns = { edge, map.left - width }
    if insideRight - width >= insideLeft then columns[3] = insideRight - width end
    for _, column in ipairs(columns) do
        if column >= screen.left and column + width <= screen.right then
            top = FreeTabTop(obstacles, column, width, height, preferredTop, bottom)
            if top then left = column; break end
        end
    end
    if not left or not top then tab:Hide(); return end
    SetDetachedPosition(tab, worldMap, map, left, top, uiScale)
    if not tab:IsShown() then tab:Show() end
    return { left = left, right = left + width, top = top, bottom = top - height }
end

-- ============================================================
-- Fitting and anchoring the panel
-- ============================================================

local function FitDock(obstacles, left, width, minimum, maximum, top, bottom, direction)
    while left >= minimum and left + width <= maximum do
        local nextLeft = left
        for _, rect in ipairs(obstacles) do
            if Overlaps(rect, left, left + width, top, bottom) then
                if direction == 1 then nextLeft = math.max(nextLeft, rect.right + GAP)
                else nextLeft = math.min(nextLeft, rect.left - GAP - width) end
            end
        end
        if nextLeft == left then return left end
        left = nextLeft
    end
end

function MapHost.LayoutDetached(worldMap, questMap, tab, host, panelOpen, observation, rediscover)
    local uiScale = UIParent:GetEffectiveScale()
    local screen, map = GetRect(UIParent, uiScale), GetRect(worldMap, uiScale)
    if not screen or not map then tab:Hide(); return end
    if rediscover or not observation.neighbors then
        observation.neighbors = CollectDetachedNeighbors(worldMap, questMap, tab, host)
    end

    local quest = GetRect(questMap, uiScale)
    local canvas = GetRect(worldMap.ScrollContainer, uiScale) or map
    local edge = math.max(map.right, quest and quest.right or map.right)
    local insideLeft = math.max(canvas.left, screen.left + GAP)
    local insideRight = math.min(canvas.right, screen.right - GAP)
    if quest and quest.left > canvas.left and Overlaps(quest, canvas.left, insideRight, canvas.top, canvas.bottom) then
        insideRight = quest.left - GAP
    end
    local obstacles = DetachedObstacles(observation.neighbors, map, edge, uiScale)
    local level = math.max(worldMap:GetFrameLevel(), questMap and questMap:GetFrameLevel() or 0) + 10
    FollowMapLayer(tab, worldMap, level)
    local tabRect = PlaceDetachedTab(tab, worldMap, screen, map, insideLeft, insideRight, edge, obstacles, uiScale)
    if not panelOpen then return end
    if tabRect then obstacles[#obstacles + 1] = tabRect end

    FollowMapLayer(host, worldMap, level)
    if host._awpDragging or host._awpMoved then return true end
    local minimum, maximum = screen.left + GAP, screen.right - GAP
    local width = math.min(math.max(quest and (quest.right - quest.left) or 360, 320), maximum - minimum)
    local height = math.min(map.top - map.bottom, screen.top - screen.bottom - 2 * GAP)
    if width <= 0 or height <= 0 then return end
    local top = math.min(math.max(map.top, screen.bottom + height + GAP), screen.top - GAP)
    local bottom = top - height
    local left = FitDock(obstacles, edge + GAP, width, minimum, maximum, top, bottom, 1)
        or FitDock(obstacles, map.left - GAP - width, width, minimum, maximum, top, bottom, -1)
    if left then
        FitDetachedPanel(host, width, height, false)
        SetDetachedPosition(host, worldMap, map, left, top, uiScale)
        return false
    end

    local stripLeft, stripWidth = LargestStrip(obstacles, insideLeft, insideRight, top, bottom)
    if stripWidth >= math.min(width, 320) then
        width = math.min(width, stripWidth)
        FitDetachedPanel(host, width, height, true)
        SetDetachedPosition(host, UIParent, screen, stripLeft + (stripWidth - width) / 2, top, uiScale)
    else
        MapHost.PlaceStandalone(host)
    end
    return true
end

local function PlaceAt(frame, relative, rect, left, top, uiScale)
    local scale = frame:GetEffectiveScale() / uiScale
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", relative, "TOPLEFT", (left - rect.left) / scale, (top - rect.top) / scale)
end

local function CollectSideTabs(parent, tab, panel, edge, uiScale, tabs)
    if not parent then return end
    local spoken = rawget(_G, "SpokenPlacesPanel")
    local toggle = rawget(_G, "SpokenPlacesPanelToggle")
    local mapzeroth = GetMapzerothFrame()
    for _, child in ipairs({ parent:GetChildren() }) do
        if child ~= tab and child ~= panel and child ~= spoken and child ~= mapzeroth and child:GetEffectiveAlpha() > 0 then
            local rect = GetRect(child, uiScale)
            if rect and rect.left >= edge.right - 12 and rect.right > edge.right
                and rect.top - rect.bottom < (edge.top - edge.bottom) / 2
                and rect.bottom < edge.top and rect.top > edge.bottom
            then
                -- Spoken already places its own toggle below AWP when both are shown.
                rect.followsTabs = child == toggle
                tabs[#tabs + 1] = rect
            end
        end
    end
end

function MapHost.Layout(worldMap, questMap, tab, panel)
    local uiScale = UIParent:GetEffectiveScale()
    local screen = GetRect(UIParent, uiScale)
    local map = GetRect(worldMap, uiScale)
    if not screen or not map then return end

    local quest = GetRect(questMap, uiScale)
    local canvas = GetRect(worldMap.ScrollContainer, uiScale) or map
    local canvasLeft = math.max(canvas.left, screen.left + GAP)
    local canvasRight = math.min(canvas.right, screen.right - GAP)
    if quest and quest.left > canvasLeft
        and Overlaps(quest, canvasLeft, canvasRight, canvas.top, canvas.bottom) then
        canvasRight = quest.left - GAP
    end
    local edge = {
        right = math.max(map.right, quest and quest.right or map.right),
        top = map.top,
        bottom = map.bottom,
    }
    local tabs = {}
    CollectSideTabs(worldMap, tab, panel, edge, uiScale, tabs)
    CollectSideTabs(worldMap.BorderFrame, tab, panel, edge, uiScale, tabs)
    CollectSideTabs(questMap, tab, panel, edge, uiScale, tabs)

    local scale = tab:GetEffectiveScale() / uiScale
    local tabWidth, tabHeight = tab:GetWidth() * scale, tab:GetHeight() * scale
    local tabTop = math.min(edge.top - 60, screen.top)
    local reach = edge.right
    for _, rect in ipairs(tabs) do
        reach = math.max(reach, rect.right)
    end

    -- Find an empty slot using geometry. Anchoring to another addon's tab can form a cycle.
    local previousTop
    repeat
        previousTop = tabTop
        for _, rect in ipairs(tabs) do
            if not rect.followsTabs and Overlaps(rect, edge.right, edge.right + tabWidth, tabTop, tabTop - tabHeight) then
                tabTop = rect.bottom - GAP
            end
        end
    until tabTop == previousTop

    local tabLeft = edge.right
    if tabLeft + tabWidth > screen.right or tabTop - tabHeight < math.max(edge.bottom, screen.bottom) then
        tabLeft = math.max(screen.left, canvasRight - tabWidth)
        tabTop = math.min(math.max((canvas.top + canvas.bottom + tabHeight) / 2, screen.bottom + tabHeight), screen.top)
    else
        reach = math.max(reach, tabLeft + tabWidth)
    end
    PlaceAt(tab, worldMap, map, tabLeft, tabTop, uiScale)

    if not panel then return end
    if panel._awpDragging then return true end
    local width = quest and (quest.right - quest.left) or 360
    width = math.min(math.max(width, 320), screen.right - screen.left - 2 * GAP)
    local height = math.min(map.top - map.bottom, screen.top - screen.bottom - 2 * GAP)
    if width <= 0 or height <= 0 then return end
    local top = math.min(math.max(map.top, screen.bottom + height + GAP), screen.top - GAP)
    local spoken = GetRect(rawget(_G, "SpokenPlacesPanel"), uiScale)
    local mapzerothFrame = GetMapzerothFrame()
    local mapzeroth = mapzerothFrame and mapzerothFrame:GetParent() == worldMap and GetRect(mapzerothFrame, uiScale)
    local docks = { spoken or false, mapzeroth or false }
    local left = reach + GAP
    -- Clearing one dock can put the queue in the way of the other. Each
    -- adjustment moves right, while our anchor stays relative to the map.
    local previousLeft
    repeat
        previousLeft = left
        for _, rect in ipairs(docks) do
            if rect and Overlaps(rect, left, left + width, top, top - height) then
                left = rect.right + GAP
            end
        end
    until left == previousLeft
    if left + width > screen.right - GAP then
        left = map.left - GAP - width
    end

    local floating = (worldMap.IsMaximized and worldMap:IsMaximized()) or left < screen.left + GAP
    if floating and not panel._awpMoved then
        -- In a narrow layout Mapzeroth can dock inside the map. Center an
        -- automatically placed queue in the largest remaining strip.
        if mapzeroth and Overlaps(mapzeroth, canvasLeft, canvasRight, top, top - height) then
            local before, after = mapzeroth.left - GAP, mapzeroth.right + GAP
            if before > canvasLeft and before - canvasLeft >= canvasRight - after then
                canvasRight = before
            elseif after < canvasRight then
                canvasLeft = after
            end
        end
        if canvasRight > canvasLeft then width = math.min(width, canvasRight - canvasLeft) end
    end
    local parent = floating and UIParent or worldMap
    if panel:GetParent() ~= parent then panel:SetParent(parent) end
    panel:SetScale(uiScale / parent:GetEffectiveScale())
    panel:SetFrameStrata(worldMap:GetFrameStrata())
    panel:SetFrameLevel(worldMap:GetFrameLevel() + 10)
    panel:SetSize(width, height)
    panel:SetClampedToScreen(floating)
    if floating then
        if not panel._awpMoved then
            left = math.max(canvasLeft, (canvasLeft + canvasRight - width) / 2)
            PlaceAt(panel, UIParent, screen, left, top, uiScale)
        end
    else
        panel._awpMoved = nil
        PlaceAt(panel, worldMap, map, left, top, uiScale)
    end
    return floating
end
