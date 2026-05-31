local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer
local hooksecurefunc = _G.hooksecurefunc

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Util = Shared.TrackerUtil
local Host = Shared.TrackerHost
local Controls = Shared.TrackerControls
local Render = {}
Shared.TrackerRender = Render

-- ============================================================
-- Block header color — authoritative against the host tracker
-- ============================================================
--
-- Both Blizzard's and Kaliel's block mixins repaint the block header from a
-- FIXED palette (Blizzard gold / Kaliel orange) on hover and on every layout
-- refresh, ignoring the per-fontString colorStyle for the header. So we can't
-- hand them a colorStyle and expect it to stick. Instead we post-hook each
-- AWP-owned block's header entry points with hooksecurefunc and re-assert OUR
-- header color after the native repaint, preserving the hover affordance:
--   * not hovered -> our base header blue
--   * hovered     -> a lighter shade of that blue
--   * on leave    -> back to our base blue (not the tracker's gold/orange)
-- hooksecurefunc keeps native behavior (e.g. objective-line hover lightening)
-- intact. Scoped to our own pooled blocks; other addons are untouched.

local function HeaderRGB(highlighted)
    local r, g, b = Shared.GetTrackerHeaderRGB()
    if highlighted then
        r = r + (1 - r) * 0.18
        g = g + (1 - g) * 0.18
        b = b + (1 - b) * 0.18
    end
    return r, g, b
end

local function ApplyHeaderColor(block, highlighted)
    local headerText = block and block.HeaderText
    if type(headerText) ~= "table" or type(headerText.SetTextColor) ~= "function" then return end
    pcall(headerText.SetTextColor, headerText, HeaderRGB(highlighted))
end

-- Read the real hover state from the header button rather than the block's
-- cached isHighlighted flag, which can stick across block-pool reuse and leave
-- a non-hovered header stranded on the lighter (highlight) shade.
local function BlockIsHovered(block)
    local hb = block and block.HeaderButton
    if hb and type(hb.IsMouseOver) == "function" then return hb:IsMouseOver() == true end
    if block and type(block.IsMouseOver) == "function" then return block:IsMouseOver() == true end
    return false
end

local function EnsureHeaderColorGuard(block)
    if type(block) ~= "table" or block._awpHeaderColorGuard then return end
    if type(hooksecurefunc) ~= "function" then return end

    local hooked = false
    -- Hover lifts to a lighter shade of OUR blue; leaving returns to OUR base
    -- blue rather than the tracker's gold/orange Header color.
    if type(block.OnHeaderEnter) == "function" then
        hooksecurefunc(block, "OnHeaderEnter", function(self) ApplyHeaderColor(self, true) end)
        hooked = true
    end
    if type(block.OnHeaderLeave) == "function" then
        hooksecurefunc(block, "OnHeaderLeave", function(self) ApplyHeaderColor(self, false) end)
        hooked = true
    end
    -- UpdateHighlight also fires during layout/refresh; re-assert our color for
    -- the block's current highlight state so a refresh never strands the header
    -- on the tracker's palette color.
    if type(block.UpdateHighlight) == "function" then
        hooksecurefunc(block, "UpdateHighlight", function(self)
            ApplyHeaderColor(self, BlockIsHovered(self))
        end)
        hooked = true
    end

    -- Only latch the guard once we actually installed a hook, so a block whose
    -- mixin methods aren't ready yet gets re-tried on the next layout pass.
    if hooked then
        block._awpHeaderColorGuard = true
    end
end

-- ============================================================
-- Objective row colors (lines keep normal hover/reverse behavior)
-- ============================================================

local function ApplyTextStatusColor(target, status, kind, goal)
    if type(target) == "table" and type(target.SetTextColor) == "function" then
        local colorStyle = type(Shared.GetTrackerColorStyle) == "function"
            and Shared.GetTrackerColorStyle(status, kind, goal) or nil
        local r, g, b
        if colorStyle then
            r, g, b = colorStyle.r, colorStyle.g, colorStyle.b
        else
            r, g, b = Shared.StatusToRGB(status, kind, goal)
        end
        pcall(target.SetTextColor, target, r, g, b)
        if colorStyle then
            target.colorStyle = colorStyle
        end
    end
end

local function ApplyLineStatusColor(line, status, kind, goal)
    if type(line) ~= "table" then return end
    ApplyTextStatusColor(line.Text or line.text or line, status, kind, goal)
end

local function ForceKTFullHeightWrap(line, block, text)
    if not Host.IsKTLoaded() or not line or not line.Text then return end

    local fontString = line.Text
    local oldHeight = 0
    if type(line.GetHeight) == "function" then
        local okHeight, height = pcall(line.GetHeight, line)
        if okHeight and type(height) == "number" then oldHeight = height end
    end

    if type(fontString.SetWordWrap) == "function" then
        pcall(fontString.SetWordWrap, fontString, true)
    end
    if type(fontString.SetMaxLines) == "function" then
        pcall(fontString.SetMaxLines, fontString, 0)
    end
    if type(fontString.SetHeight) == "function" then
        pcall(fontString.SetHeight, fontString, 0)
    end
    if type(fontString.SetText) == "function" then
        pcall(fontString.SetText, fontString, text or "")
    end

    local newHeight = 0
    if type(fontString.GetStringHeight) == "function" then
        local okStringHeight, height = pcall(fontString.GetStringHeight, fontString)
        if okStringHeight and type(height) == "number" then newHeight = height end
    end
    if newHeight <= 0 and type(fontString.GetHeight) == "function" then
        local okHeight, height = pcall(fontString.GetHeight, fontString)
        if okHeight and type(height) == "number" then newHeight = height end
    end
    if newHeight <= 0 then return end

    newHeight = math.ceil(newHeight)
    if type(line.SetHeight) == "function" then
        pcall(line.SetHeight, line, newHeight)
    end
    if block and type(block.height) == "number" then
        block.height = block.height + (newHeight - oldHeight)
    end
end

-- ============================================================
-- Goal line click + tooltip wiring
-- ============================================================

local function ShowTipGroupTooltip(anchor, title, tips)
    if not _G.GameTooltip or type(tips) ~= "table" or #tips == 0 then return end

    _G.GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    _G.GameTooltip:SetText(title or "Zygor notes", 1.0, 0.82, 0.2)
    for _, tip in ipairs(tips) do
        local r, g, b = Shared.StatusToRGB(tip.status, tip.kind, tip.goal)
        _G.GameTooltip:AddLine(tip.text, r, g, b, true)
    end
    _G.GameTooltip:Show()
end

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

local function WireGoalLineClick(line, block, tooltipTitle, tips, confirmGoal)
    if not line then return end

    if type(line.EnableMouse) == "function" then
        pcall(line.EnableMouse, line, true)
    end
    if type(line.SetScript) == "function" then
        line:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton == "RightButton" then
                Controls.ShowContextMenu(block)
            elseif Util.IsConfirmGoal(confirmGoal) then
                ClickConfirmGoal(confirmGoal)
            end
        end)

        if type(tips) == "table" and #tips > 0 then
            line:SetScript("OnEnter", function(self)
                ShowTipGroupTooltip(self, tooltipTitle, tips)
            end)
            line:SetScript("OnLeave", function()
                if _G.GameTooltip then _G.GameTooltip:Hide() end
            end)
        else
            line:SetScript("OnEnter", nil)
            line:SetScript("OnLeave", nil)
        end
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
    if block._awpCheck then return block._awpCheck end

    -- Chk anchors RIGHT to its next element's LEFT in the *negative-x* region
    -- to the left of HeaderText.
    -- HeaderText is provided by Blizzard's ObjectiveTrackerAnimBlockTemplate
    -- and we don't reposition it; the checkbox sits in the negative-x space.
    local check = CreateFrame("CheckButton", nil, block, "UICheckButtonTemplate")
    check:SetSize(15, 15)
    check:SetFrameLevel((block:GetFrameLevel() or 0) + 5)
    if block.HeaderText then
        check:SetPoint("RIGHT", block.HeaderText, "LEFT", -3, 0)
    else
        check:SetPoint("TOPLEFT", block, "TOPLEFT", -20, -1)
    end

    check:SetScript("OnClick", function(self)
        -- Do-and-reset: clicking marks the step complete and Zygor advances
        -- to the next step. The block is then rebuilt for the new step, so we
        -- never want the checked state to persist.
        self:SetChecked(false)
        Controls.ZygorSkip()
    end)
    check:SetScript("OnEnter", function(self)
        if _G.GameTooltip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText("Mark step complete", 1, 1, 1)
            _G.GameTooltip:AddLine("Skips to the next valid step.", 0.85, 0.85, 0.85, true)
            _G.GameTooltip:Show()
        end
    end)
    check:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)

    block._awpCheck = check
    return check
end

-- ============================================================
-- Block header + row rendering + layout finalization
-- ============================================================

local function SetBlockHeaderText(block, headerText)
    if type(block) ~= "table" then return end

    EnsureHeaderColorGuard(block)

    local r, g, b = Shared.GetTrackerHeaderRGB()
    local colorStyle = { r = r, g = g, b = b }

    if block.HeaderText and type(block.SetStringText) == "function" then
        if type(block.HeaderText.SetPoint) == "function" then
            pcall(block.HeaderText.SetPoint, block.HeaderText, "RIGHT", block.rightEdgeOffset or 0, 0)
        end
        local ok, height = pcall(block.SetStringText, block, block.HeaderText, headerText, true, colorStyle, false)
        if ok and type(height) == "number" then
            block.height = height
        end
        ApplyHeaderColor(block, false)
    elseif type(block.SetHeader) == "function" then
        pcall(block.SetHeader, block, headerText)
        ApplyHeaderColor(block, false)
    elseif block.HeaderText and type(block.HeaderText.SetText) == "function" then
        block.HeaderText:SetText(headerText)
        ApplyHeaderColor(block, false)
    end
end

local function RenderRowsIntoBlock(self, block, rows)
    local lineCount = 0
    for _, row in ipairs(rows or {}) do
        lineCount = lineCount + 1
        local line
        if type(block.AddObjective) == "function" then
            local colorStyle = type(Shared.GetTrackerColorStyle) == "function"
                and Shared.GetTrackerColorStyle(row.status, row.kind, row.goal) or nil
            local okAdd, result = pcall(block.AddObjective, block, lineCount, row.text, nil, row.useFullHeight == true, nil, colorStyle)
            if okAdd then line = result end
        end
        if row.useFullHeight == true then
            ForceKTFullHeightWrap(line, block, row.text)
        end
        ApplyLineStatusColor(line, row.status, row.kind, row.goal)
        WireGoalLineClick(line, block, row.tooltipTitle, row.tips, row.confirmGoal)
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
        local headerH = 22
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
