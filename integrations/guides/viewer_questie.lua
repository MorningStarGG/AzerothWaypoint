-- ============================================================
-- Questie tracker host
-- ============================================================
--
-- Places AWP guide modules in Questie's tracker and restores its geometry when
-- the last guide detaches.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Host = { moduleToContainerMap = {} }
Common.QuestieHost = Host

if not NS.IsWoWForever() then
    function Host.IsSelected() return false end

    return
end

local Custom = Common.CustomHost
local callbacks, hooked = {}, {}
local container, active, failure, subscribedAPI, wasSelected
local waitingForCombat

local function Locked() return InCombatLockdown() == true end

local function GetQuestie()
    if NS.IsAddonLoaded("Questie") then return rawget(_G, "Questie") end
end

function Host.IsSelected()
    local questie = GetQuestie()
    if not questie then return false end
    local profile = questie.db and questie.db.profile
    local tracker = NS.Internal.QuestieData.GetLoadedModule("QuestieTracker")
    return (not profile or profile.trackerEnabled == true) and (not tracker or not tracker.disableHooks)
end

function Host.GetRoot() return rawget(_G, "Questie_BaseFrame") end

function Host.IsLayoutLocked()
    if not Locked() then return false end
    waitingForCombat = true
    return true
end

local function GetFirstAnchor(first, child)
    if not first or type(first.GetPoint) ~= "function" or first:GetParent() ~= child or first:GetNumPoints() ~= 1 then return end
    local point, relative, relativePoint, x, y = first:GetPoint(1)
    if point == "TOPLEFT" and relative == child and relativePoint == "TOPLEFT"
        and type(x) == "number" and type(y) == "number" then
        return x, y
    end
end

local function Resolve()
    local questie = GetQuestie()
    local api = questie and questie.API
    if not api or type(api.RegisterOnReady) ~= "function" then
        return nil, "Questie's tracker readiness API is unavailable."
    end
    if not api.isReady then
        return nil, "Waiting for Questie's tracker initialization.", true
    end
    local tracker = NS.Internal.QuestieData.GetLoadedModule("QuestieTracker")
    local pool = NS.Internal.QuestieData.GetLoadedModule("TrackerLinePool")
    local base = NS.Internal.QuestieData.GetLoadedModule("TrackerBaseFrame")
    local root, questFrame, header = Host.GetRoot(), rawget(_G, "TrackedQuests"), rawget(_G, "Questie_HeaderFrame")
    local scroll = questFrame and questFrame.ScrollFrame
    local child = questFrame and questFrame.ScrollChildFrame
    if not tracker or not tracker.started or type(tracker.UpdateHeight) ~= "function"
        or type(tracker.UpdateFormatting) ~= "function" or not base
        or not pool or type(pool.GetFirstLine) ~= "function" or type(pool.GetCurrentLine) ~= "function"
        or not root or not header or header:GetParent() ~= root or not questFrame or questFrame:GetParent() ~= root
        or not child or not scroll or type(scroll.GetScrollChild) ~= "function"
        or scroll:GetParent() ~= questFrame or scroll:GetScrollChild() ~= child
        or not questie.db or not questie.db.profile or not questie.db.char
        or type(questie.db.profile.TrackerHeight) ~= "number" or type(questie.db.profile.trackerHeightRatio) ~= "number"
        or type(questie.db.profile.TrackerWidth) ~= "number" or type(questie.db.profile.trackerWidthRatio) ~= "number"
        or type(questie.db.profile.trackerFontSizeZone) ~= "number"
        or not GetFirstAnchor(pool.GetFirstLine(), child) then
        return nil, "Questie's tracker layout is unsupported."
    end
    return tracker, nil, false, questie, pool, base, root, questFrame, header, scroll, child
end

-- ============================================================
-- Host readiness
-- ============================================================

function Host.GetAvailability()
    if failure then return false, failure end
    if Host.IsLayoutLocked() then return false, "Waiting for combat to end.", true end
    local tracker, reason, waiting = Resolve()
    return tracker ~= nil, reason, waiting == true
end

local ready = NS.Internal.Scheduling.CreateCoalescer(function()
    for index = 1, #callbacks do callbacks[index]() end
end)

local function RefreshSelection()
    local selected = Host.IsSelected()
    if selected or wasSelected then ready:Request() end
    wasSelected = selected
end

function Host.RegisterReadyCallback(callback) callbacks[#callbacks + 1] = callback end

local function Same(a, b)
    return a == b or a ~= nil and b ~= nil and math.abs(a - b) < 0.01
end

local function SetHeight(frame, height)
    if not Same(frame:GetHeight(), height) then frame:SetHeight(height) end
end

local function HasRows(s)
    return s.pool.GetCurrentLine() ~= nil and s.first:IsShown()
end

local function CaptureNativeGeometry(s)
    s.nativeContent = s.child:GetHeight()
    s.nativeViewport = s.questFrame:GetHeight()
    s.nativeRoot = s.root:GetHeight()
    s.appliedContent, s.appliedViewport, s.appliedRoot = nil, nil, nil
end

-- ============================================================
-- Native tracker geometry
-- ============================================================

local function RestoreEmptyWidth(s)
    local width = s.emptyWidth
    if not width then return end
    if Same(s.root:GetWidth(), width) then s.root:SetWidth(s.nativeRootWidth) end
    if Same(s.questFrame:GetWidth(), width) then s.questFrame:SetWidth(s.nativeQuestWidth) end
    if Same(s.child:GetWidth(), width) then s.child:SetWidth(s.nativeChildWidth) end
    s.emptyWidth = nil
end

local function GetLayoutWidth(s, hasRows)
    local width = s.child:GetWidth()
    if hasRows or s.emptyWidth or width >= s.header:GetWidth() then return width end
    -- A fresh tracker with no native rows can still be at its creation size.
    local profile = s.questie.db.profile
    local preferred = profile.TrackerWidth > 0 and profile.TrackerWidth or
    math.min(240, GetScreenWidth() * profile.trackerWidthRatio)
    return math.max(width, preferred, s.header:GetWidth() + 10)
end

local function SetEmptyWidth(s, width)
    s.nativeRootWidth, s.nativeQuestWidth, s.nativeChildWidth = s.root:GetWidth(), s.questFrame:GetWidth(),
        s.child:GetWidth()
    s.emptyWidth = width
    s.root:SetWidth(width)
    s.questFrame:SetWidth(width)
    s.child:SetWidth(width)
end

local function SetScroll(s, offset)
    s.scroll:UpdateScrollChildRect()
    offset = math.max(0, math.min(offset, s.scroll:GetVerticalScrollRange()))
    if not Same(s.scroll:GetVerticalScroll(), offset) then s.scroll:SetVerticalScroll(offset) end
    s.scrollOffset = offset
end

local function RestoreGeometry(s)
    RestoreEmptyWidth(s)
    local x, y = GetFirstAnchor(s.first, s.child)
    if Same(x, s.x) and s.appliedY and Same(y, s.appliedY) then
        s.first:SetPoint("TOPLEFT", s.child, "TOPLEFT", s.x, s.y)
    end
    local offset = s.scroll:GetVerticalScroll()
    if Same(s.child:GetHeight(), s.appliedContent) then SetHeight(s.child, s.nativeContent) end
    if Same(s.questFrame:GetHeight(), s.appliedViewport) then SetHeight(s.questFrame, s.nativeViewport) end
    if Same(s.root:GetHeight(), s.appliedRoot) then SetHeight(s.root, s.nativeRoot) end
    if s.scroll:GetScrollChild() == s.child then SetScroll(s, offset) end
end

local function Stop()
    local s = active
    active = nil
    container:Hide()
    container:ClearAllPoints()
    container:SetParent(UIParent)
    if s.wheel and s.scroll:GetScript("OnMouseWheel") == s.wheel then
        s.scroll:SetScript("OnMouseWheel", nil)
        s.scroll:EnableMouseWheel(s.wheelEnabled)
    end
    RestoreGeometry(s)
end

-- Questie measures its own row heights, AWP adds its guide height once.
local function ApplyGeometry(s, hasRows)
    local profile = s.questie.db.profile
    local headerHeight = s.header:GetHeight()
    local hasHeader = s.header:IsShown()
    local chrome = hasHeader and headerHeight + 20 or 20
    local content = (hasRows and s.nativeContent or 0) + s.height
    local limit = profile.TrackerHeight > 0 and profile.TrackerHeight or GetScreenHeight() * profile.trackerHeightRatio
    local height = content + chrome
    if height > limit then
        local minimum = headerHeight + profile.trackerFontSizeZone + 23
        if hasHeader and limit < minimum + 10 then
            height = minimum
        else
            height = math.max(limit, profile.trackerFontSizeZone + 22)
        end
    end
    local viewport = math.max(1, height - chrome)
    if Same(s.child:GetHeight(), content) and Same(s.questFrame:GetHeight(), viewport)
        and Same(s.root:GetHeight(), height) then
        return
    end

    s.applying = true
    SetHeight(s.child, content)
    SetHeight(s.questFrame, viewport)
    SetHeight(s.root, height)
    s.appliedContent, s.appliedViewport, s.appliedRoot = content, viewport, height
    SetScroll(s, s.scrollOffset)
    s.applying = nil
end

local function Flush()
    local s = active
    if not s then return end
    if Locked() then
        s.deferred = true; return
    end
    if #container.modules == 0 then
        Stop(); return
    end
    if s.base.isSizing or not Host.IsSelected() or not s.root:IsShown() or not s.questFrame:IsShown()
        or not s.questie.db.char.isTrackerExpanded then
        return
    end

    local x, y = GetFirstAnchor(s.first, s.child)
    if s.scroll:GetScrollChild() ~= s.child or s.pool.GetFirstLine() ~= s.first or not Same(x, s.x)
        or not (Same(y, s.y) or Same(y, s.appliedY)) then
        failure = "Questie's tracker layout changed while docked."
        Stop()
        return
    end

    s.hasRows = HasRows(s)
    local width = GetLayoutWidth(s, s.hasRows)
    for _, module in ipairs(container.modules) do
        if module._awpQuestieCollapsePending then
            module._awpQuestieCollapsePending = nil
            module:ToggleCollapsed()
        end
    end
    if s.dirty or not Same(s.width, width) then
        s.width = width
        s.height = Custom.Layout(container, width)
        s.dirty = nil
    end
    if s.height <= 0 then
        if s.appliedY or s.appliedRoot or s.emptyWidth then RestoreGeometry(s) end
        s.appliedY, s.appliedRoot, s.appliedViewport, s.appliedContent = nil, nil, nil, nil
        container:Hide()
        return
    end

    if not s.hasRows and not Same(width, s.child:GetWidth()) then SetEmptyWidth(s, width) end
    local top = s.y - s.height
    if not Same(y, top) then s.first:SetPoint("TOPLEFT", s.child, "TOPLEFT", s.x, top) end
    s.appliedY = top
    ApplyGeometry(s, s.hasRows)
    container:Show()
end

local layout = NS.Internal.Scheduling.CreateCoalescer(Flush)

-- ============================================================
-- Scheduling layout and observing scroll
-- ============================================================

local function MarkDirty()
    if not active then return end
    active.dirty = true
    layout:Request()
end

function Host.GetContainer()
    if failure then return end
    if container then return container end
    container = CreateFrame("Frame", "AwpQuestieGuideContainer", UIParent)
    container:Hide()
    container.modules = {}
    container.MarkDirty, container.ForceExpand = MarkDirty, MarkDirty
    container.IsCollapsed = function() return false end
    container.RemoveModule = function(_, module) Host.RemoveModule(module) end
    container.DeferModuleCollapse = function(_, module)
        if not Locked() then return false end
        module._awpQuestieCollapsePending = not module._awpQuestieCollapsePending
        if active then active.deferred = true end
        return true
    end
    return container
end

local function ObserveTracker(tracker, base, questFrame)
    if hooked[tracker] then return end
    hooked[tracker] = true
    hooksecurefunc(tracker, "UpdateHeight", function()
        local s = active
        if not s or s.tracker ~= tracker then return end
        -- An expanded empty tracker returns without writing heights. The
        -- collapsed pass does write its compact height, even with no rows.
        local hasRows = HasRows(s)
        if hasRows or not s.questie.db.char.isTrackerExpanded then CaptureNativeGeometry(s) end
        if hasRows then s.emptyWidth = nil end
        if s.height > 0 and s.questie.db.char.isTrackerExpanded then layout:Request() end
    end)
    hooksecurefunc(tracker, "UpdateFormatting", function()
        local s = active
        if not s or s.tracker ~= tracker then return end
        local hasRows = HasRows(s)
        if s.hasRows ~= hasRows or not Same(s.width, GetLayoutWidth(s, hasRows)) then layout:Request() end
    end)
    if type(base.OnResizeStop) == "function" then
        hooksecurefunc(base, "OnResizeStop", function()
            if active and active.base == base then layout:Request() end
        end)
    end
    questFrame:HookScript("OnShow", function(frame)
        if active and active.questFrame == frame then layout:Request() end
    end)
end

local function ObserveScroll(s)
    local scroll = s.scroll
    if not hooked[scroll] then
        hooked[scroll] = true
        scroll:HookScript("OnVerticalScroll", function(frame, offset)
            local current = active
            if current and current.scroll == frame and not current.applying
                and Same(current.child:GetHeight(), current.appliedContent)
                and Same(current.questFrame:GetHeight(), current.appliedViewport) then
                current.scrollOffset = offset
            end
        end)
    end
    if not scroll:GetScript("OnMouseWheel") then
        s.wheelEnabled = scroll:IsMouseWheelEnabled()
        s.wheel = function(frame, delta)
            if Locked() or active ~= s then return end
            local offset = math.max(0, math.min(frame:GetVerticalScroll() - delta * 40, frame:GetVerticalScrollRange()))
            frame:SetVerticalScroll(offset)
        end
        scroll:SetScript("OnMouseWheel", s.wheel)
        scroll:EnableMouseWheel(true)
    end
end

local function Start()
    if active then return true end
    local tracker, reason, _, questie, pool, base, root, questFrame, header, scroll, child = Resolve()
    if not tracker or not pool or not scroll then return false, reason end
    local first = pool.GetFirstLine()
    local x, y = GetFirstAnchor(first, child)
    local s = {
        tracker = tracker,
        questie = questie,
        pool = pool,
        base = base,
        root = root,
        questFrame = questFrame,
        header = header,
        scroll = scroll,
        child = child,
        first = first,
        x = x,
        y = y,
        height = 0,
        scrollOffset = scroll:GetVerticalScroll()
    }
    CaptureNativeGeometry(s)
    active = s
    ObserveTracker(tracker, base, questFrame)
    ObserveScroll(s)
    container:SetParent(child)
    container:SetPoint("TOPLEFT", child, "TOPLEFT")
    return true
end

-- ============================================================
-- Module attachment
-- ============================================================

function Host:GetContainerForModule(module) return self.moduleToContainerMap[module] end

function Host:SetModuleContainer(module, target)
    if not target or target ~= container or Host.IsLayoutLocked() then return false end
    local ok, reason = Start()
    if not ok then
        failure = reason; return false, reason
    end
    Custom.Add(self, target, module)
    MarkDirty()
    return true
end

function Host.RemoveModule(module)
    if not container then return end
    module._awpQuestieCollapsePending = nil
    Custom.Remove(Host, container, module)
    MarkDirty()
end

function Host.NoteAttachmentFailure(reason) failure = tostring(reason) end

local function OnQuestieReady()
    local tracker = NS.Internal.QuestieData.GetLoadedModule("QuestieTracker")
    if tracker and type(tracker.Toggle) == "function" then hooksecurefunc(tracker, "Toggle", RefreshSelection) end
    RefreshSelection()
end

local function Subscribe()
    local questie = GetQuestie()
    local api = questie and questie.API
    if api and api ~= subscribedAPI and type(api.RegisterOnReady) == "function" then
        subscribedAPI = api
        api.RegisterOnReady(OnQuestieReady)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_REGEN_ENABLED" then
        if active and active.deferred then
            active.deferred = nil; layout:Request()
        end
        if waitingForCombat then
            waitingForCombat = nil; ready:Request()
        end
        return
    end
    if event == "ADDON_LOADED" and addon ~= "Questie" then return end
    Subscribe()
    RefreshSelection()
end)
Subscribe()
