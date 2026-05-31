local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

local FW = NS.Internal and NS.Internal.Interface and NS.Internal.Interface.Framework
local state = NS.State

local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local InCombatLockdown = _G.InCombatLockdown
local hooksecurefunc = _G.hooksecurefunc
local C_Timer = _G.C_Timer

local DEFAULT_WIDTH  = 320
local DEFAULT_HEIGHT = 220
local TITLE_H        = 28
local FOOTER_H       = 32
local ROW_HEIGHT     = 18
local ROW_SPACING    = 4
local ROW_INSET      = 8

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}
local Shared = NS.Internal.ZygorTrackerViewer
local M = Shared

state.zygorTrackerViewer = state.zygorTrackerViewer or {
    frame              = nil,
    shell              = nil,
    titleText          = nil,
    stepText           = nil,
    bodyFrame          = nil,
    scrollFrame        = nil,
    scrollChild        = nil,
    goalRows           = {},
    footerFrame        = nil,
    prevButton         = nil,
    nextButton         = nil,
    completeButton     = nil,
    waypointButton     = nil,
    guidesButton       = nil,
    currentStepKey     = nil,
    dockMode           = "tracker",
    readerOpen         = false,
    hideNativeHookInstalled = false,
    hideNativeUpdateHookInstalled = false,
    nativeFrameCloak   = nil,
    pendingDockApply   = nil,
}

local viewer = state.zygorTrackerViewer

local ACTION_ICONS = {
    accept  = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnin  = "Interface\\GossipFrame\\ActiveQuestIcon",
    kill    = "Interface\\Icons\\ABILITY_WARRIOR_SAVAGEBLOW",
    goto    = "Interface\\Minimap\\Tracking\\Target",
    talk    = "Interface\\GossipFrame\\GossipGossipIcon",
    home    = "Interface\\Icons\\INV_Misc_Rune_01",
    fpath   = "Interface\\TaxiFrame\\UI-Taxi-Icon-Yellow",
    use     = "Interface\\Icons\\INV_Misc_Bag_08",
    buy     = "Interface\\Icons\\INV_Misc_Coin_01",
    confirm = "Interface\\Buttons\\UI-CheckBox-Check",
    note    = "Interface\\Icons\\INV_Misc_Note_01",
    tip     = "Interface\\Icons\\INV_Misc_Note_01",
}

local function TrimText(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then return nil end
    return value
end

local function GetZ()
    return type(NS.ZGV) == "function" and NS.ZGV() or rawget(_G, "ZygorGuidesViewer") or rawget(_G, "ZGV")
end

local function GetSettings()
    return type(NS.GetZygorTrackerViewerSettings) == "function"
        and NS.GetZygorTrackerViewerSettings()
        or { enabled = false, dockMode = "tracker", hideZygorFrame = false }
end

local function SetSetting(key, value)
    if type(NS.SetZygorTrackerViewerSetting) == "function" then
        NS.SetZygorTrackerViewerSetting(key, value)
    end
end

-- ============================================================
-- Goal row pool
-- ============================================================

local function CreateGoalRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetJustifyV("TOP")
    row.text:SetWordWrap(true)
    row.text:SetSpacing(2)

    row.wayButton = CreateFrame("Button", nil, row)
    row.wayButton:SetSize(16, 16)
    row.wayButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
    row.wayButton:Hide()

    local wayTex = row.wayButton:CreateTexture(nil, "ARTWORK")
    wayTex:SetAllPoints(row.wayButton)
    wayTex:SetTexture("Interface\\Minimap\\Tracking\\Target")
    row.wayButton.tex = wayTex

    row.wayButton:SetScript("OnEnter", function(self)
        self.tex:SetVertexColor(1.0, 0.82, 0.2, 1)
        if _G.GameTooltip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            _G.GameTooltip:SetText("Route to this goal", 1, 1, 1)
            _G.GameTooltip:Show()
        end
    end)
    row.wayButton:SetScript("OnLeave", function(self)
        self.tex:SetVertexColor(1, 1, 1, 1)
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    return row
end

local function GetGoalRow(index, parent)
    local row = viewer.goalRows[index]
    if row then return row end
    row = CreateGoalRow(parent)
    viewer.goalRows[index] = row
    return row
end

local function HideUnusedRows(fromIndex)
    for i = fromIndex, #viewer.goalRows do
        local row = viewer.goalRows[i]
        if row then row:Hide() end
    end
end

-- ============================================================
-- Step rendering
-- ============================================================

local function GoalHasWaypoint(goal)
    if type(goal) ~= "table" then return false end
    local mapID = goal.map or goal.mapid or goal.mapID
    local x, y = goal.x, goal.y
    if type(mapID) == "number" and type(x) == "number" and type(y) == "number" then
        return true
    end
    local marker = type(goal.mapmarker) == "table" and goal.mapmarker or nil
    if marker
        and type(marker.map or marker.mapid or marker.mapID) == "number"
        and type(marker.x) == "number" and type(marker.y) == "number"
    then
        return true
    end
    return false
end

local function BuildTargetFromGoal(goal, fallbackTitle)
    if type(goal) ~= "table" then return nil end
    local marker = type(goal.mapmarker) == "table" and goal.mapmarker or nil
    local mapID = goal.map or goal.mapid or goal.mapID or (marker and (marker.map or marker.mapid or marker.mapID))
    local x = goal.x or (marker and marker.x)
    local y = goal.y or (marker and marker.y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end
    return {
        mapID = mapID,
        x = x,
        y = y,
        title = TrimText(fallbackTitle) or "Guide goal",
        source = "awp.zygor.trackerviewer",
        kind = "guide_goal",
        guideProvider = "zygor",
    }
end

local function RouteToTarget(target)
    if type(target) ~= "table" then return false end
    if type(NS.IsValidGuideRouteTarget) ~= "function" or not NS.IsValidGuideRouteTarget(target) then
        return false
    end
    if type(NS.UpdateGuideTarget) ~= "function" then return false end
    NS.UpdateGuideTarget("zygor", target, false, { explicit = true, reason = "awp_trackerviewer_goal_click" })
    if type(NS.RecomputeCarrier) == "function" then NS.RecomputeCarrier() end
    return true
end

local function ComputeStepKey(guide, step)
    if not guide or not step then return nil end
    local title = tostring(guide.title or guide.guid or guide.name or guide)
    local stepNum = step.num or step.stepnum or 0
    return title .. "|" .. tostring(stepNum)
end

local function PopulateRow(row, goal, text, status, kind)
    row.goal = goal
    row.kind = kind

    local action = type(goal) == "table" and type(goal.action) == "string" and goal.action:lower() or nil
    local iconPath = ACTION_ICONS[kind == "tip" and "tip" or action]
        or ACTION_ICONS[action]
        or "Interface\\GossipFrame\\BinderGossipIcon"
    row.icon:SetTexture(iconPath)
    row.icon:SetVertexColor(1, 1, 1, 1)

    local r, g, b = Shared.StatusToRGB(status, kind, goal)
    row.text:SetTextColor(r, g, b, 1)
    row.text:SetText(text or "")

    if kind == "goal" and GoalHasWaypoint(goal) then
        row.wayButton:Show()
        row.wayButton:SetScript("OnClick", function()
            local target = BuildTargetFromGoal(goal, text)
            if target then RouteToTarget(target) end
        end)
        row.text:SetPoint("RIGHT", row.wayButton, "LEFT", -4, 0)
    else
        row.wayButton:Hide()
        row.wayButton:SetScript("OnClick", nil)
        row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    end

    local textHeight = math.ceil(row.text:GetStringHeight() or ROW_HEIGHT)
    row:SetHeight(math.max(ROW_HEIGHT, textHeight + 4))
end

local function LayoutRows()
    local body = viewer.scrollChild
    if not body then return end

    local y = 0
    for i = 1, #viewer.goalRows do
        local row = viewer.goalRows[i]
        if row and row:IsShown() then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", body, "TOPLEFT", ROW_INSET, -y)
            row:SetPoint("RIGHT", body, "RIGHT", -ROW_INSET, 0)
            y = y + (row:GetHeight() or ROW_HEIGHT) + ROW_SPACING
        end
    end
    body:SetHeight(math.max(1, y))
end

local function RenderCurrentStep()
    if not viewer.frame then return end
    local Z = GetZ()
    if not Z or not Z.CurrentGuide or not Z.CurrentStep then
        if viewer.titleText then viewer.titleText:SetText("No active guide") end
        if viewer.stepText then viewer.stepText:SetText("") end
        for _, row in ipairs(viewer.goalRows) do row:Hide() end
        viewer.currentStepKey = nil
        return
    end

    local guide = Z.CurrentGuide
    local step  = Z.CurrentStep
    local stepKey = ComputeStepKey(guide, step)
    local stepCount = type(guide.steps) == "table" and #guide.steps or 0

    local title = TrimText(guide.title_short) or TrimText(guide.title) or "Guide"
    if viewer.titleText then viewer.titleText:SetText(title) end
    if viewer.stepText then viewer.stepText:SetText(string.format("Step %d / %d", step.num or 0, stepCount)) end

    -- Always do a full rebuild for now — Zygor's status can change row text,
    -- waypoint availability, and even insert/remove rows mid-step.
    viewer.currentStepKey = stepKey

    local rowIndex = 1
    Shared.IterateRenderableGoalLines(step, function(goal, text, status, kind)
        local row = GetGoalRow(rowIndex, viewer.scrollChild)
        row:Show()
        PopulateRow(row, goal, text, status, kind)
        rowIndex = rowIndex + 1
    end)
    HideUnusedRows(rowIndex)
    LayoutRows()
end

M.Render = RenderCurrentStep

-- ============================================================
-- Button actions
-- ============================================================

local function OnPrev()
    local Z = GetZ()
    if Z and type(Z.PreviousStep) == "function" then
        pcall(Z.PreviousStep, Z, false, true)
    end
end

local function OnNext()
    local Z = GetZ()
    if Z and type(Z.SkipStep) == "function" then
        pcall(Z.SkipStep, Z, false, false, true)
    end
end

local function OnComplete()
    local Z = GetZ()
    if not Z then return end
    if type(Z.SkipStep) == "function" then
        pcall(Z.SkipStep, Z, false, false, true)
    end
end

local function OnWaypoint()
    if type(NS.ExtractGuideRouteTargetFromZygor) ~= "function" then return end
    local target = NS.ExtractGuideRouteTargetFromZygor()
    if not target then return end
    target.kind = target.kind or "guide_goal"
    target.guideProvider = "zygor"
    RouteToTarget(target)
end

local function OnGuides()
    Shared.OpenZygorGuidePicker()
end

-- ============================================================
-- Frame creation
-- ============================================================

local function SavePosition()
    if not viewer.frame then return end
    if viewer.dockMode == "tracker" then return end
    local point, _, relPoint, x, y = viewer.frame:GetPoint(1)
    if not point then return end
    SetSetting("position", { point = point, relPoint = relPoint or "CENTER", x = x or 0, y = y or 0 })
end

local function ApplyStandalonePosition()
    if not viewer.frame then return end
    local settings = GetSettings()
    local pos = settings.position
    viewer.frame:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        viewer.frame:SetPoint(pos.point, UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
    else
        viewer.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    end
end

local function GetTrackerModule()
    return Shared.TrackerModule
end

local function ApplyDockMode(mode)
    if not viewer.frame then return end
    if InCombatLockdown and InCombatLockdown() then
        viewer.pendingDockApply = mode
        return
    end

    viewer.dockMode = mode

    if mode == "tracker" then
        local TM = GetTrackerModule()
        if TM and type(TM.SetAttachSucceededCallback) == "function" then
            TM.SetAttachSucceededCallback(function()
                if viewer.dockMode == "tracker" and viewer.frame then
                    viewer.frame:Hide()
                end
            end)
        end
        local attachedNow, pendingAttach = nil, nil
        if TM and type(TM.Attach) == "function" then
            attachedNow, pendingAttach = TM.Attach()
        end
        if attachedNow then
            viewer.frame:Hide()
            return
        end
        if pendingAttach then
            -- Keep the hidden frame available for rendering state while the
            -- tracker module finishes delayed registration.
            viewer.frame:Hide()
            return
        end
        viewer.frame:Hide()
        if type(NS.Msg) == "function" then
            NS.Msg("Tracker dock unavailable.")
        end
        return
    end

    -- standalone
    local TM = GetTrackerModule()
    if TM and type(TM.SetAttachSucceededCallback) == "function" then
        TM.SetAttachSucceededCallback(nil)
    end
    if TM and type(TM.Detach) == "function" then TM.Detach() end
    viewer.frame:SetParent(UIParent)
    ApplyStandalonePosition()
    viewer.frame:Show()
end

local function CreateFooterButtons(footerFrame)
    local function makeBtn(text, width, tooltip, onClick)
        local btn = FW.CreatePanelButton(footerFrame, {
            height = 22,
            labelInsetLeft = 4,
            labelInsetRight = 4,
        })
        btn:SetSize(width, 22)
        btn:SetDisplayText(text)
        btn:SetScript("OnClick", onClick)
        if tooltip then
            btn:HookScript("OnEnter", function(self)
                if _G.GameTooltip then
                    _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    _G.GameTooltip:SetText(tooltip, 1, 1, 1)
                    _G.GameTooltip:Show()
                end
            end)
            btn:HookScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)
        end
        return btn
    end

    viewer.prevButton     = makeBtn("<<",     34, "Previous step",          OnPrev)
    viewer.nextButton     = makeBtn(">>",     34, "Next step",              OnNext)
    viewer.completeButton = makeBtn("Done",   46, "Mark step complete",     OnComplete)
    viewer.waypointButton = makeBtn("Way",    42, "Route to current step",  OnWaypoint)
    viewer.guidesButton   = makeBtn("Guides", 56, "Open Zygor guide chooser", OnGuides)

    local pad = 4
    viewer.prevButton:SetPoint("LEFT", footerFrame, "LEFT", 6, 0)
    viewer.nextButton:SetPoint("LEFT", viewer.prevButton, "RIGHT", pad, 0)
    viewer.completeButton:SetPoint("LEFT", viewer.nextButton, "RIGHT", pad, 0)
    viewer.waypointButton:SetPoint("LEFT", viewer.completeButton, "RIGHT", pad, 0)
    viewer.guidesButton:SetPoint("RIGHT", footerFrame, "RIGHT", -6, 0)
end

local function CreateBody(bodyFrame)
    local scroll = CreateFrame("ScrollFrame", "AwpZygorTrackerViewerScroll", bodyFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", bodyFrame, "TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", bodyFrame, "BOTTOMRIGHT", -22, 4)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    local function SyncChildWidth()
        local w = scroll:GetWidth()
        if w and w > 0 then child:SetWidth(w) end
    end
    scroll:HookScript("OnSizeChanged", SyncChildWidth)
    SyncChildWidth()

    viewer.scrollFrame = scroll
    viewer.scrollChild = child

    if FW and type(FW.StyleScrollBar) == "function" then
        pcall(FW.StyleScrollBar, scroll, { width = 6 })
    end
end

local function CreateFrameSafe()
    if viewer.frame then return viewer.frame end
    if not FW or type(FW.CreatePanelShell) ~= "function" then return nil end

    local frame = CreateFrame("Frame", "AwpZygorTrackerViewer", UIParent, "BackdropTemplate")
    frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetToplevel(true)
    frame:Hide()

    local shell = FW.CreatePanelShell(frame, {
        title = "Zygor Tracker",
        titleHeight = TITLE_H,
        footerHeight = FOOTER_H,
        movable = true,
        closeButton = true,
        closeSize = 18,
        closeOffsetX = -6,
        onClose = function()
            if viewer.readerOpen then
                viewer.readerOpen = false
                frame:Hide()
                return
            end
            SetSetting("enabled", false)
            frame:Hide()
        end,
    })

    viewer.frame = frame
    viewer.shell = shell
    viewer.titleText = shell.titleText
    viewer.bodyFrame = shell.bodyFrame
    viewer.footerFrame = shell.footerFrame

    if shell.titleText and shell.titleText.ClearAllPoints then
        shell.titleText:ClearAllPoints()
        shell.titleText:SetPoint("LEFT", shell.titleFrame, "LEFT", 10, 0)
        shell.titleText:SetJustifyH("LEFT")
    end

    viewer.stepText = shell.titleFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    viewer.stepText:SetPoint("RIGHT", shell.titleFrame, "RIGHT", -28, 0)
    viewer.stepText:SetTextColor(0.85, 0.85, 0.85, 1)
    viewer.stepText:SetText("")

    CreateBody(shell.bodyFrame)
    CreateFooterButtons(shell.footerFrame)

    if shell.titleFrame and type(shell.titleFrame.HookScript) == "function" then
        shell.titleFrame:HookScript("OnDragStop", SavePosition)
    end
    frame:HookScript("OnHide", function() SavePosition() end)

    local function OnCombatEnded()
        if viewer.pendingDockApply then
            local mode = viewer.pendingDockApply
            viewer.pendingDockApply = nil
            ApplyDockMode(mode)
        end
    end

    local combatWatcher = CreateFrame("Frame")
    combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatWatcher:SetScript("OnEvent", OnCombatEnded)

    return frame
end

-- ============================================================
-- Native Zygor viewer cloaking
-- ============================================================

local ApplyHideNativeFrameState

local function ShouldHideNativeFrame()
    local settings = GetSettings()
    if not settings.hideZygorFrame then return false end
    return true
end

local function GetNativeViewerFrame()
    local Z = GetZ()
    local nativeFrame = Z and Z.Frame
    if not nativeFrame then
        nativeFrame = rawget(_G, "ZygorGuidesViewerFrame") or rawget(_G, "ZygorGuidesViewerFrameMaster")
    end
    return nativeFrame, Z
end

local function CaptureFramePoints(frame)
    local points = {}
    if not frame or type(frame.GetNumPoints) ~= "function" or type(frame.GetPoint) ~= "function" then
        return points
    end

    for i = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(i)
        points[#points + 1] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs,
        }
    end

    return points
end

local function RestoreFramePoints(frame, points)
    if not frame or type(frame.ClearAllPoints) ~= "function" or type(frame.SetPoint) ~= "function" then return end

    frame:ClearAllPoints()
    if type(points) == "table" and #points > 0 then
        for _, point in ipairs(points) do
            if point.point then
                frame:SetPoint(point.point, point.relativeTo, point.relativePoint, point.xOfs or 0, point.yOfs or 0)
            end
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    end
end

local function CaptureNativeFrameCloakState(frame)
    local cloak = {
        frame = frame,
        points = CaptureFramePoints(frame),
    }

    if type(frame.GetAlpha) == "function" then
        cloak.alpha = frame:GetAlpha()
    end
    if type(frame.GetClampedToScreen) == "function" then
        cloak.clampedToScreen = frame:GetClampedToScreen()
    end
    if type(frame.IsMouseEnabled) == "function" then
        cloak.mouseEnabled = frame:IsMouseEnabled()
    end

    return cloak
end

local function RestoreNativeFrameCloak()
    local cloak = viewer.nativeFrameCloak
    if not cloak then return end

    local frame = cloak.frame
    viewer.nativeFrameCloak = nil

    if not frame then return end

    if type(frame.SetAlpha) == "function" then
        frame:SetAlpha(cloak.alpha or 1)
    end
    if type(frame.SetClampedToScreen) == "function" and cloak.clampedToScreen ~= nil then
        frame:SetClampedToScreen(cloak.clampedToScreen and true or false)
    end
    RestoreFramePoints(frame, cloak.points)
    if type(frame.EnableMouse) == "function" and cloak.mouseEnabled ~= nil then
        frame:EnableMouse(cloak.mouseEnabled and true or false)
    end
end

local function ApplyNativeFrameCloak(nativeFrame, Z)
    if not nativeFrame then return end

    if type(nativeFrame.IsShown) == "function"
        and not nativeFrame:IsShown()
        and type(nativeFrame.Show) == "function"
    then
        nativeFrame:Show()
    end

    if Z and Z.db and Z.db.profile then
        Z.db.profile.enable_viewer = true
    end

    if not viewer.nativeFrameCloak or viewer.nativeFrameCloak.frame ~= nativeFrame then
        RestoreNativeFrameCloak()
        viewer.nativeFrameCloak = CaptureNativeFrameCloakState(nativeFrame)
    end

    if type(nativeFrame.SetAlpha) == "function" then
        nativeFrame:SetAlpha(0.1)
    end
    if type(nativeFrame.EnableMouse) == "function" then
        nativeFrame:EnableMouse(false)
    end
    if type(nativeFrame.SetClampedToScreen) == "function" then
        nativeFrame:SetClampedToScreen(false)
    end
    if type(nativeFrame.ClearAllPoints) == "function" and type(nativeFrame.SetPoint) == "function" then
        nativeFrame:ClearAllPoints()
        nativeFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 1000, -1000)
    end
end

local function ScheduleNativeFrameCloak()
    if not ShouldHideNativeFrame() then return end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            if type(ApplyHideNativeFrameState) == "function" then
                ApplyHideNativeFrameState()
            end
        end)
    elseif type(ApplyHideNativeFrameState) == "function" then
        ApplyHideNativeFrameState()
    end
end

local function InstallNativeFrameHook(nativeFrame, Z)
    if nativeFrame and not viewer.hideNativeHookInstalled and type(nativeFrame.Show) == "function" then
        hooksecurefunc(nativeFrame, "Show", function()
            ScheduleNativeFrameCloak()
        end)

        viewer.hideNativeHookInstalled = true
    end

    if Z and not viewer.hideNativeUpdateHookInstalled and type(Z.UpdateFrame) == "function" then
        hooksecurefunc(Z, "UpdateFrame", function()
            ScheduleNativeFrameCloak()
        end)

        viewer.hideNativeUpdateHookInstalled = true
    end
end

ApplyHideNativeFrameState = function()
    local nativeFrame, Z = GetNativeViewerFrame()
    if not nativeFrame then return end

    if ShouldHideNativeFrame() then
        InstallNativeFrameHook(nativeFrame, Z)
        ApplyNativeFrameCloak(nativeFrame, Z)
    else
        RestoreNativeFrameCloak()
    end
end

M.ApplyHideNativeFrameState = ApplyHideNativeFrameState

-- ============================================================
-- Public API
-- ============================================================

function M.Show()
    local frame = CreateFrameSafe()
    if not frame then return end
    viewer.readerOpen = false
    local settings = GetSettings()
    ApplyDockMode(settings.dockMode or "tracker")
    RenderCurrentStep()
    if Shared.TrackerModule and type(Shared.TrackerModule.MarkDirty) == "function" then
        Shared.TrackerModule.MarkDirty()
    end
    ApplyHideNativeFrameState()
end

function M.ShowCurrentStepReader()
    local frame = CreateFrameSafe()
    if not frame then return false end

    viewer.readerOpen = true
    RenderCurrentStep()
    frame:SetParent(UIParent)
    ApplyStandalonePosition()
    frame:Show()
    return true
end

function M.Hide()
    viewer.readerOpen = false
    if viewer.frame then viewer.frame:Hide() end
    if Shared.TrackerModule and type(Shared.TrackerModule.Detach) == "function" then
        Shared.TrackerModule.Detach()
    end
    ApplyHideNativeFrameState()
end

function M.Refresh()
    if viewer.frame and viewer.frame:IsShown() then
        RenderCurrentStep()
    end
    if Shared.TrackerModule and type(Shared.TrackerModule.IsAttached) == "function" and Shared.TrackerModule.IsAttached() then
        Shared.TrackerModule.MarkDirty()
    end
end

function M.RefreshStep()
    if viewer.frame and viewer.frame:IsShown() then
        RenderCurrentStep()
    end
    if Shared.TrackerModule and type(Shared.TrackerModule.IsAttached) == "function" and Shared.TrackerModule.IsAttached() then
        Shared.TrackerModule.MarkDirty()
    end
end

function M.ApplyDockMode(mode)
    if mode ~= "tracker" and mode ~= "standalone" then return end
    ApplyDockMode(mode)
end

function M.ApplySettings()
    local settings = GetSettings()
    if settings.enabled then
        if not viewer.frame then CreateFrameSafe() end
        if viewer.frame then
            ApplyDockMode(settings.dockMode or "tracker")
            RenderCurrentStep()
        end
        if Shared.TrackerModule and type(Shared.TrackerModule.MarkDirty) == "function" then
            Shared.TrackerModule.MarkDirty()
        end
        ApplyHideNativeFrameState()
    else
        M.Hide()
    end
end

function M.IsActive()
    return viewer.frame ~= nil and viewer.frame:IsShown()
end

NS.ShowZygorTrackerViewer          = M.Show
NS.HideZygorTrackerViewer          = M.Hide
NS.RefreshZygorTrackerViewer       = M.Refresh
NS.ApplyZygorTrackerViewerSettings = M.ApplySettings
