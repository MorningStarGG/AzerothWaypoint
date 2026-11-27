-- ============================================================
-- Ellesmere Forever tracker host
-- ============================================================
--
-- Places AWP guide modules alongside Ellesmere's own quest list on Forever.
-- The custom host owns its registration and native frame access.
-- Ellesmere retains its saved settings.

local NS = _G.AzerothWaypointNS

NS.Internal = NS.Internal or {}
NS.Internal.GuideTrackerViewer = NS.Internal.GuideTrackerViewer or {}

local Custom = NS.Internal.GuideTrackerViewer.CustomHost
local Host = { moduleToContainerMap = {} }
NS.Internal.GuideTrackerViewer.EllesmereHost = Host
local container, state, attachmentFailure

function Host.IsSelected()
    local eui = rawget(_G, "EllesmereUI")
    local ns = eui and eui._ModuleNS and eui._ModuleNS.EllesmereUIQuestTracker
    if not ns or type(ns.UseCustomTracker) ~= "function" then return false end
    local ok, custom = pcall(ns.UseCustomTracker)
    return ok and custom == true
end

function Host.GetRoot() return rawget(_G, "EUI_CustomQuestTracker") end

local function Config(s, key, default)
    local value = s.eqt.Cfg(key)
    if value == nil then return default end
    return value
end

local function SavePoints(frame)
    local points = {}
    for index = 1, frame:GetNumPoints() do points[index] = { frame:GetPoint(index) } end
    return points
end

local function RestorePoints(frame, points)
    frame:ClearAllPoints()
    for index = 1, #points do frame:SetPoint(unpack(points[index])) end
end

local function ScrollRange(s)
    return math.max(0, s.content:GetHeight() - s.scroll:GetHeight())
end

local function PaintScroll(s)
    local range = ScrollRange(s)
    s.position = math.max(0, math.min(s.position, range))
    s.originalScroll(s.scroll, s.position)
    local mode = Config(s, "customScrollbar", "always")
    local shown = range > 0 and mode ~= "hidden"
        and (mode ~= "hover" or s.root:IsMouseOver() or s.dragging)
    if shown then s.originalBarShow(s.bar) else s.originalBarHide(s.bar) end
    if not shown then return end
    local view = s.scroll:GetHeight()
    local height = math.min(view, math.max(20, view * view / math.max(s.content:GetHeight(), 1)))
    s.originalThumbHeight(s.thumb, height)
    s.originalThumbClear(s.thumb)
    s.originalThumbPoint(s.thumb, "TOP", s.bar, "TOP", 0,
        range > 0 and -(view - height) * s.position / range or 0)
end

-- ============================================================
-- Viewport and container
-- ============================================================

-- The original wheel callback also hides the quest-click overlay and updates
-- Ellesmere's separately positioned secure item buttons. Keep that callback
-- in the path (with zero wheel delta), while supplying our combined offset.
local function SetScroll(s, position)
    if state ~= s then return end
    s.position = math.max(0, math.min(position, ScrollRange(s)))
    s.originalWheel(s.scroll, 0)
    PaintScroll(s)
end

local function CombinedHeight(s)
    local eui = rawget(_G, "EllesmereUI")
    local maximum = Config(s, "customMaxHeight", 450)
    if eui and eui._unlockActive then return maximum end
    local body = s.questHeight + s.guideHeight
    return math.min(24 + (body > 0 and body + 8 or 0), maximum)
end

local function PositionContent(s)
    s.content:SetHeight(math.max(1, s.questHeight + s.guideHeight))
    -- Guides precede quests, existing quest row anchors remain relative to
    -- Ellesmere's own content frame, including recipe rows and item buttons.
    s.quest:ClearAllPoints()
    s.quest:SetPoint("TOPLEFT", s.content, "TOPLEFT", 0, -s.guideHeight)
    local height = CombinedHeight(s)
    if s.root:GetHeight() ~= height then
        s.originalRootHeight(s.root, height)
        local eui = rawget(_G, "EllesmereUI")
        if eui and type(eui.ReapplyOwnAnchor) == "function" then eui.ReapplyOwnAnchor("EQT_Tracker") end
    end
    PaintScroll(s)
end

local function Layout(s)
    if state ~= s then return end
    s.scheduled = false
    local width = s.quest:GetWidth()
    s.width = width
    s.content:SetWidth(width)
    s.guideHeight = Custom.Layout(container, width)
    PositionContent(s)
    SetScroll(s, s.position)
end

local function ScheduleLayout()
    local s = state
    if not s or s.scheduled then return end
    s.scheduled = true
    C_Timer.After(0, function() Layout(s) end)
end

function Host.GetContainer()
    if container then return container end
    container = CreateFrame("Frame", "AwpEllesmereGuideContainer", UIParent)
    container:Hide()
    container.modules = {}
    container.MarkDirty = ScheduleLayout
    container.IsCollapsed = function() return false end
    container.ForceExpand = ScheduleLayout
    container.RemoveModule = function(_, module) Host.RemoveModule(module) end
    return container
end

local function FindFrames(root)
    local scroll, bar, thumb
    local children = { root:GetChildren() }
    for index = 1, #children do
        local child = children[index]
        if child:GetObjectType() == "ScrollFrame" and child:GetScrollChild() then
            if scroll then return end
            scroll = child
        end
    end
    if not scroll then return end
    for index = 1, #children do
        local child = children[index]
        local top, bottom
        for pointIndex = 1, child:GetNumPoints() do
            local point, relative, relativePoint = child:GetPoint(pointIndex)
            if relative == scroll then
                if point == "TOPRIGHT" and relativePoint == "TOPRIGHT" then top = true end
                if point == "BOTTOMRIGHT" and relativePoint == "BOTTOMRIGHT" then bottom = true end
            end
        end
        local candidate = child:GetChildren()
        -- Frame dimensions are floating point under UI scaling. Identify the
        -- track by its anchors and drag thumb, never an exact pixel width.
        if top and bottom and child:GetNumChildren() == 1 and candidate
            and type(candidate:GetScript("OnMouseDown")) == "function"
            and type(candidate:GetScript("OnMouseUp")) == "function"
        then
            if bar then return end
            bar = child
            thumb = candidate
        end
    end
    if bar and thumb then return scroll, scroll:GetScrollChild(), bar, thumb end
end

-- Another addon may hook a method while the host is active. If its wrapper
-- keeps ours in the chain after detach, ours must become a transparent call.
local function GuardMethod(s, original, active)
    return function(...)
        if state == s then return active(...) end
        if original then return original(...) end
    end
end

-- ============================================================
-- Layout and scroll handling
-- ============================================================

local function IgnoreGeometry() end

local function Start()
    if state then return true end
    local root = Host.GetRoot()
    local eqt = rawget(_G, "EllesmereUIQuestTracker")
    if not root or not eqt or type(eqt.Cfg) ~= "function" then
        return false, "Waiting for Ellesmere's custom tracker initialization."
    end
    local scroll, quest, bar, thumb = FindFrames(root)
    if not scroll or not quest or not bar or not thumb or type(scroll:GetScript("OnMouseWheel")) ~= "function" then
        return false, "Ellesmere's quest viewport or scrollbar could not be identified."
    end
    if root:IsProtected() or scroll:IsProtected() or quest:IsProtected() then
        return false, "Ellesmere's tracker or quest viewport is protected."
    end
    local container = Host.GetContainer()
    local content = container._awpCombinedContent
    if not content then
        content = CreateFrame("Frame", nil, scroll)
        container._awpCombinedContent = content
    end
    local s = {
        root = root,
        eqt = eqt,
        scroll = scroll,
        quest = quest,
        bar = bar,
        thumb = thumb,
        content = content,
        questHeight = quest:GetHeight() > 1 and quest:GetHeight() or 0,
        guideHeight = 0,
        position = scroll:GetVerticalScroll(),
        questParent = quest:GetParent(),
        questPoints = SavePoints(quest),
        originalRootHeight = root.SetHeight,
        originalScroll = scroll.SetVerticalScroll,
        originalBarShown = bar.SetShown,
        originalBarShow = bar.Show,
        originalBarHide = bar.Hide,
        originalThumbHeight = thumb.SetHeight,
        originalThumbClear = thumb.ClearAllPoints,
        originalThumbPoint = thumb.SetPoint,
        originalWheel = scroll:GetScript("OnMouseWheel"),
        originalDown = thumb:GetScript("OnMouseDown"),
        originalUp = thumb:GetScript("OnMouseUp"),
        originalUpdate = thumb:GetScript("OnUpdate"),
    }
    state = s
    content:SetParent(scroll)
    content:Show()
    content:SetSize(quest:GetWidth(), math.max(quest:GetHeight(), 1))
    scroll:SetScrollChild(content)
    quest:SetParent(content)
    container:SetParent(content)
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT")
    container:Show()

    -- These substitutions are confined to this unprotected addon-owned
    -- viewport. Ellesmere's private quest-only scroll calculations still run,
    -- but cannot overwrite the combined geometry or clamp to the quest range.
    s.scrollWrapper = GuardMethod(s, s.originalScroll, function() s.originalScroll(scroll, s.position) end)
    scroll.SetVerticalScroll = s.scrollWrapper
    s.heightWrapper = function(_, height)
        if state == s then height = CombinedHeight(s) end
        s.originalRootHeight(root, height)
    end
    root.SetHeight = s.heightWrapper
    local function Paint() PaintScroll(s) end
    s.barShownWrapper = GuardMethod(s, s.originalBarShown, Paint)
    s.barShowWrapper = GuardMethod(s, s.originalBarShow, Paint)
    s.barHideWrapper = GuardMethod(s, s.originalBarHide, Paint)
    bar.SetShown, bar.Show, bar.Hide = s.barShownWrapper, s.barShowWrapper, s.barHideWrapper
    s.thumbHeightWrapper = GuardMethod(s, s.originalThumbHeight, IgnoreGeometry)
    s.thumbClearWrapper = GuardMethod(s, s.originalThumbClear, IgnoreGeometry)
    s.thumbPointWrapper = GuardMethod(s, s.originalThumbPoint, IgnoreGeometry)
    thumb.SetHeight, thumb.ClearAllPoints, thumb.SetPoint = s.thumbHeightWrapper, s.thumbClearWrapper,
        s.thumbPointWrapper
    s.wheelWrapper = GuardMethod(s, s.originalWheel, function(_, delta) SetScroll(s, s.position - delta * 40) end)
    scroll:SetScript("OnMouseWheel", s.wheelWrapper)
    s.drag = GuardMethod(s, s.originalUpdate, function(self)
        local _, cursorY = GetCursorPosition()
        local free = scroll:GetHeight() - self:GetHeight()
        if free > 0 then
            SetScroll(s, s.startScroll + (s.startY - cursorY / self:GetEffectiveScale()) * ScrollRange(s) / free)
        end
    end)
    s.down = GuardMethod(s, s.originalDown, function(self)
        local _, cursorY = GetCursorPosition()
        s.startY, s.startScroll, s.dragging = cursorY / self:GetEffectiveScale(), s.position, true
        self:SetScript("OnUpdate", s.drag)
    end)
    s.up = GuardMethod(s, s.originalUp, function(self)
        s.dragging = false
        self:SetScript("OnUpdate", nil)
        PaintScroll(s)
    end)
    thumb:SetScript("OnMouseDown", s.down)
    thumb:SetScript("OnMouseUp", s.up)
    thumb:SetScript("OnUpdate", nil)

    -- Hooks persist on WoW frames, so install once and consult current state.
    if not quest._awpEllesmereHooks then
        quest._awpEllesmereHooks = true
        hooksecurefunc(quest, "SetHeight", function(self, height)
            local active = state
            if not active or active.quest ~= self then return end
            active.questHeight = height > 1 and height or 0
            PositionContent(active)
            ScheduleLayout()
        end)
        hooksecurefunc(quest, "SetWidth", function(self, width)
            if state and state.quest == self and state.width ~= width then ScheduleLayout() end
        end)
        local function RefreshHover(self)
            if state and state.root == self then PaintScroll(state) end
        end
        root:HookScript("OnEnter", RefreshHover)
        root:HookScript("OnLeave", RefreshHover)
    end
    ScheduleLayout()
    return true
end

-- ============================================================
-- Restoring the native tracker
-- ============================================================

local function RestoreMethod(object, key, replacement, original)
    if object[key] == replacement then object[key] = original end
end

local function Stop()
    local s = state
    if not s then return end
    state = nil
    RestoreMethod(s.root, "SetHeight", s.heightWrapper, s.originalRootHeight)
    RestoreMethod(s.scroll, "SetVerticalScroll", s.scrollWrapper, s.originalScroll)
    RestoreMethod(s.bar, "SetShown", s.barShownWrapper, s.originalBarShown)
    RestoreMethod(s.bar, "Show", s.barShowWrapper, s.originalBarShow)
    RestoreMethod(s.bar, "Hide", s.barHideWrapper, s.originalBarHide)
    RestoreMethod(s.thumb, "SetHeight", s.thumbHeightWrapper, s.originalThumbHeight)
    RestoreMethod(s.thumb, "ClearAllPoints", s.thumbClearWrapper, s.originalThumbClear)
    RestoreMethod(s.thumb, "SetPoint", s.thumbPointWrapper, s.originalThumbPoint)
    if s.scroll:GetScript("OnMouseWheel") == s.wheelWrapper then s.scroll:SetScript("OnMouseWheel", s.originalWheel) end
    if s.thumb:GetScript("OnMouseDown") == s.down then s.thumb:SetScript("OnMouseDown", s.originalDown) end
    if s.thumb:GetScript("OnMouseUp") == s.up then s.thumb:SetScript("OnMouseUp", s.originalUp) end
    if s.thumb:GetScript("OnUpdate") == s.drag or s.thumb:GetScript("OnUpdate") == nil then
        s.thumb:SetScript("OnUpdate", s.originalUpdate)
    end
    container:Hide()
    container:SetParent(UIParent)
    s.quest:SetParent(s.questParent)
    s.scroll:SetScrollChild(s.quest)
    RestorePoints(s.quest, s.questPoints)
    s.content:Hide()
    s.originalScroll(s.scroll, math.min(s.position, math.max(0, s.questHeight - s.scroll:GetHeight())))
    if type(s.eqt.RefreshCustom) == "function" then s.eqt.RefreshCustom() end
end

Host.PrepareModule = Custom.PrepareModule

function Host:GetContainerForModule(module) return self.moduleToContainerMap[module] end

function Host:SetModuleContainer(module, target)
    if target ~= Host.GetContainer() then return false end
    local started, reason = Start()
    if not started then
        attachmentFailure = reason; return false, reason
    end
    if self.moduleToContainerMap[module] == target then return true end
    Custom.Add(self, target, module)
    attachmentFailure = nil
    module.isDirty = true
    ScheduleLayout()
    return true
end

local function RemoveModule(_, module)
    Custom.Remove(Host, container, module)
    if #container.modules == 0 then Stop() else ScheduleLayout() end
end

function Host.RemoveModule(module) RemoveModule(container, module) end

function Host.UpdateAll() ScheduleLayout() end

function Host.GetStatus()
    return state and "attached" or "waiting", state and #container.modules or 0, attachmentFailure
end

function Host.NoteAttachmentFailure(reason) attachmentFailure = tostring(reason) end
