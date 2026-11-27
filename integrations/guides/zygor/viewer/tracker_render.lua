-- ============================================================
-- Zygor tracker rendering
-- ============================================================
--
-- Connects Zygor goal rows to their native click actions and lays out each
-- tracker block.

local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

local C_Timer = _G.C_Timer

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Util = Shared.TrackerUtil
local Controls = Shared.TrackerControls
local CommonControls = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.Controls
local CommonRender = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.Render
local Render = {}
Shared.TrackerRender = Render

local ApplyLineStatusColor = CommonRender.ApplyLineColor
local ForceKTFullHeightWrap = CommonRender.ForceFullHeightWrap

-- ============================================================
-- Goal line click + tooltip wiring
-- ============================================================


local function ClickConfirmGoal(goal)
    local clicked = false
    if Util.IsConfirmGoal(goal) and type(goal.OnClick) == "function" then
        local ok = pcall(goal.OnClick, goal, "LeftButton")
        clicked = ok
    end
    if not clicked then
        Controls.ZygorNext()
    end

    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            if Shared.TrackerModule and type(Shared.TrackerModule.MarkDirty) == "function" then
                Shared.TrackerModule.MarkDirty()
            end
        end)
    elseif Shared.TrackerModule and type(Shared.TrackerModule.MarkDirty) == "function" then
        Shared.TrackerModule.MarkDirty()
    end
end

local function ResolveRowGoal(d)
    local z = Shared.GetZygor and Shared.GetZygor()
    local guide = z and z.CurrentGuide
    if not guide or guide.title ~= d.guide or Shared.TrackerRows.GetGuideRevision(guide) ~= d.revision then return end
    local step = z.CurrentStep
    if Util.GetStepNum(step) ~= d.step then
        step = nil
        for _, sticky in ipairs(z.CurrentStickies or {}) do
            if Util.GetStepNum(sticky) == d.step then
                step = sticky; break
            end
        end
    end
    local goal = step and step.goals and step.goals[d.goal]
    if goal and goal.action == d.action and goal.loadguide == d.target and goal.loadguidestep == d.targetStep then
        return
            goal
    end
end

if NS.Internal.GuideTrackerViewer.Actions then
    NS.Internal.GuideTrackerViewer.Actions.RegisterRowProvider("zygor", {
        available = function(d)
            if d.action == "loadguide" and InCombatLockdown() then
                return false,
                    "Guide loading is unavailable during combat."
            end
            return ResolveRowGoal(d) ~= nil, "The guide action changed."
        end,
        run = function(d)
            local goal = ResolveRowGoal(d)
            if not goal then return false end
            if d.action == "confirm" then
                ClickConfirmGoal(goal); return true
            end
            if type(goal.OnClick) ~= "function" then return false, "Native guide loading is unavailable." end
            goal:OnClick("LeftButton")
            return true
        end,
    })
end

local function WireGoalLineClick(line, block, tooltipTitle, tips, confirmGoal, interaction)
    if not line then return end
    if interaction and NS.Internal.GuideTrackerViewer.Actions then
        NS.Internal.GuideTrackerViewer.Actions.BindRowAction(line, interaction,
            function() Controls.ShowContextMenu(line) end)
        CommonRender.WireTipTooltip(line, tooltipTitle, tips)
        return
    end

    if type(line.EnableMouse) == "function" then
        pcall(line.EnableMouse, line, true)
    end
    if type(line.SetScript) == "function" then
        line:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton == "RightButton" then
                Controls.ShowContextMenu(line)
            elseif Util.IsConfirmGoal(confirmGoal) then
                ClickConfirmGoal(confirmGoal)
            end
        end)

        CommonRender.WireTipTooltip(line, tooltipTitle, tips)
    end
end

local function WireGuidePickerLineClick(line, block)
    if not line then return end

    if type(line.EnableMouse) == "function" then
        pcall(line.EnableMouse, line, true)
    end
    if type(line.SetScript) == "function" then
        line:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton == "RightButton" then
                Controls.ShowContextMenu(block)
            else
                Controls.OpenZygorNewGuide()
            end
        end)
        line:SetScript("OnEnter", nil)
        line:SetScript("OnLeave", nil)
    end
end

-- ============================================================
-- Per-block checkbox (one per step, click to mark done)
-- ============================================================

local function EnsureBlockCheckbox(block)
    return CommonControls.SetStepCheckbox(block, block.HeaderText, {
        checked = false,
        tooltip = "Mark step complete",
        detail = "Skips to the next valid step.",
        onClick = Controls.ZygorSkip,
    })
end

-- ============================================================
-- Block header + row rendering + layout finalization
-- ============================================================

local SetBlockHeaderText = CommonControls.SetBlockHeaderText

local function RenderRowsIntoBlock(self, block, rows)
    local lineCount = 0
    local actions = NS.Internal.GuideTrackerViewer.GuideActions
    local provider = actions and actions.providers.zygor
    local goalOwner = provider and provider.goalOwner
    for _, row in ipairs(rows or {}) do
        lineCount = lineCount + 1
        local line = CommonRender and CommonRender.AddObjective(block, lineCount, {
            text = row.text,
            status = row.status,
            kind = row.kind,
            action = row.goal,
            questID = row.questID,
            objectiveKey = goalOwner and goalOwner(row.goal, block._awpOwnerStepIndex),
            actionStepOwner = block._awpOwnerStepIndex,
            fullHeight = row.useFullHeight == true,
        }) or nil
        WireGoalLineClick(line, block, row.tooltipTitle, row.tips, row.confirmGoal, row.interaction)
    end
    return lineCount
end

local function PrepareBlockForLayout(block, isCurrentStepBlock, hasStep)
    if not block then return end

    if isCurrentStepBlock then
        local check = EnsureBlockCheckbox(block)
        if check then
            if hasStep then check:Show() else check:Hide() end
        end
    elseif block._awpCheck then
        block._awpCheck:Hide()
    end

    block.parentModule = Shared.GetModuleFrame and Shared.GetModuleFrame() or nil
    if block.HeaderButton and type(block.HeaderButton.RegisterForClicks) == "function" then
        pcall(block.HeaderButton.RegisterForClicks, block.HeaderButton,
            "LeftButtonUp", "RightButtonUp")
    end

    block._awpOpenGuidePicker = false
end

local function FinalizeBlockLayout(self, block, lineCount)
    if type(block.height) ~= "number" or block.height <= 0 then
        local headerH = block._awpHiddenGuideTitle and 1 or 22
        if block.HeaderText and type(block.HeaderText.GetHeight) == "function" then
            local h = block.HeaderText:GetHeight()
            if type(h) == "number" and h > 0 then headerH = h end
        end
        block.height = headerH
    end
    if lineCount > 0 then
        block.height = block.height + (self.lineSpacing or 4)
    end

    if type(self.LayoutBlock) == "function" then
        pcall(self.LayoutBlock, self, block)
    end
end

Render.SetBlockHeaderText = SetBlockHeaderText
Render.RenderRowsIntoBlock = RenderRowsIntoBlock
Render.PrepareBlockForLayout = PrepareBlockForLayout
Render.FinalizeBlockLayout = FinalizeBlockLayout
Render.EnsureBlockCheckbox = EnsureBlockCheckbox
Render.WireGuidePickerLineClick = WireGuidePickerLineClick
Render.WireGoalLineClick = WireGoalLineClick
Render.ApplyLineStatusColor = ApplyLineStatusColor
Render.ForceKTFullHeightWrap = ForceKTFullHeightWrap
