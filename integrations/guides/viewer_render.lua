-- ============================================================
-- Guide Viewer row layout
-- ============================================================
--
-- Lays out guide rows, action decorations and tips and resets bindings when a
-- pooled row is reused.

local NS = _G.AzerothWaypointNS

NS.Internal = NS.Internal or {}
NS.Internal.GuideTrackerViewer = NS.Internal.GuideTrackerViewer or {}

local Common = NS.Internal.GuideTrackerViewer
local Host = Common.Host
local Styles = Common.Styles
local Render = {}
Common.Render = Render

-- Decorations take their vertical slot from a tracker block, but share the
-- header's horizontal bounds. Quest-row indentation remains owned by the host.
function Render.AnchorModuleDecoration(frame, module, block)
    local bounds = module.Header
    if frame._awpBlock == block and frame._awpDecorationBounds == bounds then return end
    frame._awpPositioning = true
    frame:ClearAllPoints()
    frame:SetPoint("TOP", block, "TOP", 0, 0)
    frame:SetPoint("LEFT", bounds, "LEFT", 0, 0)
    frame:SetPoint("RIGHT", bounds, "RIGHT", 0, 0)
    frame._awpBlock, frame._awpDecorationBounds = block, bounds
    frame._awpPositioning = nil
end

function Render.ReleaseModuleDecoration(frame)
    frame._awpPositioning = true
    frame:ClearAllPoints()
    frame._awpBlock, frame._awpDecorationBounds = nil, nil
    frame._awpPositioning = nil
end

function Render.ShowTipGroupTooltip(anchor, title, tips)
    if not _G.GameTooltip or type(tips) ~= "table" or #tips == 0 then return end
    _G.GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    _G.GameTooltip:SetText(title or "Guide notes", 1, 0.82, 0.2)
    for _, tip in ipairs(tips) do
        local r, g, b = Styles.StatusToRGB(tip.status, tip.kind, tip.goal or tip.action, Styles.GetProviderKey(anchor),
            tip.colorRole)
        _G.GameTooltip:AddLine(tip.text, r, g, b, true)
    end
    _G.GameTooltip:Show()
end

local function OnTipEnter(line) Render.ShowTipGroupTooltip(line, line._awpTipTitle, line._awpTips) end
local function OnTipLeave() if _G.GameTooltip then _G.GameTooltip:Hide() end end

function Render.WireTipTooltip(line, title, tips)
    if not line or type(line.SetScript) ~= "function" then return end
    if type(tips) == "table" and #tips > 0 then
        line._awpTipTitle, line._awpTips = title, tips
        line:SetScript("OnEnter", OnTipEnter)
        line:SetScript("OnLeave", OnTipLeave)
    else
        line._awpTipTitle, line._awpTips = nil, nil
        line:SetScript("OnEnter", nil)
        line:SetScript("OnLeave", nil)
    end
end

-- ============================================================
-- Row styling and bindings
-- ============================================================

function Render.ApplyLineColor(line, status, kind, action)
    local text = line and (line.Text or line.text or line)
    if type(text) ~= "table" or type(text.SetTextColor) ~= "function" then return end
    local style = Styles.GetTrackerColorStyle(status, kind, action, Styles.GetProviderKey(line), line._awpColorRole)
    pcall(text.SetTextColor, text, style.r, style.g, style.b)
    text.colorStyle = style
end

function Render.ForceFullHeightWrap(line, block, text, reflowRole, fullHeight)
    if not (Host.IsKTLoaded() or reflowRole) or not line or not line.Text then return end
    local fontString = line.Text
    local oldHeight = type(line.GetHeight) == "function" and line:GetHeight() or 0
    if fullHeight ~= false and type(fontString.SetWordWrap) == "function" then fontString:SetWordWrap(true) end
    if type(fontString.SetMaxLines) == "function" then fontString:SetMaxLines(fullHeight == false and 2 or 0) end
    if type(fontString.SetHeight) == "function" then fontString:SetHeight(0) end
    fontString:SetText(text or "")
    local height = type(fontString.GetStringHeight) == "function" and fontString:GetStringHeight() or 0
    if type(height) ~= "number" or height <= 0 then return end
    height = math.ceil(height)
    if type(line.SetHeight) == "function" then line:SetHeight(height) end
    if type(block.height) == "number" then block.height = block.height + height - oldHeight end
end

-- Only scripts installed on AWP-rendered rows are ours to reset. Native host
-- scripts on a freshly acquired line remain untouched.
function Render.ResetLineBindings(line)
    if not line then return end
    if Common.QuestDetails then Common.QuestDetails.Clear(line) end
    if Common.GuideActions then Common.GuideActions.ReleaseRow(line) end
    if line._awpGuideBindings then
        if type(line.SetScript) == "function" then
            line:SetScript("OnMouseUp", nil)
            line:SetScript("OnEnter", nil)
            line:SetScript("OnLeave", nil)
        end
        if type(line.EnableMouse) == "function" then line:EnableMouse(false) end
    end
    line._awpGuideBindings = true
    line._awpMoreMenu = nil
    line._awpTipTitle, line._awpTips = nil, nil
    Common.Controls.SetStepCheckbox(line, line.Text, nil)
end

function Render.AddObjective(block, lineIndex, row)
    if type(block) ~= "table" or type(block.AddObjective) ~= "function" then return nil end
    local actions = Common.GuideActions
    if actions and type(block.GetExistingLine) == "function" then
        actions.ReleaseRow(block:GetExistingLine(lineIndex))
    end
    row = type(row) == "table" and row or {}
    local decorative = row.role == "heading" or row.role == "support"
    local colorRole = row.colorRole or (row.role == "heading" and "heading" or nil)
    local showActions = actions and not row.hideActions
    local fullHeight = row.fullHeight == true or row.useFullHeight == true
    local key = Styles.GetProviderKey(block)
    local owner = row.objectiveKey or row.ownerStepIndex or row.stepIndex or block._awpOwnerStepIndex
    local firstWithoutTitle = block._awpHiddenGuideTitle and not block._awpFirstLine
    local strip = showActions and actions.LayoutLeadingStepStrip(block, key, row.actionStepOwner or owner)
    if strip and firstWithoutTitle then
        strip:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
        block.height = math.max(0, (block.height or 0) - (block.parentModule.lineSpacing or 4))
    end
    local style = Styles.GetTrackerColorStyle(row.status or "incomplete", row.kind or "goal", row.action, key, colorRole)
    local ok, line = pcall(block.AddObjective, block, lineIndex, row.text or "", nil,
        fullHeight, nil, style)
    if not ok then return nil end
    local reflowRole = line and (row.role ~= nil or line._awpDisplayRole ~= nil)
    Render.ResetLineBindings(line)
    if line and firstWithoutTitle then
        block._awpFirstLine = line
        if not strip then
            line:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
            block.height = math.max(0, (block.height or 0) - (block.parentModule.lineSpacing or 4))
        end
    end
    if line then
        line._awpDisplayRole = row.role
        line._awpColorRole = colorRole
        -- A decorative line owns layout space, never the step's checkbox or
        -- goal actions. Hidden guide titles still anchor those to a real row.
        if block._awpHiddenGuideTitle and not block._awpFirstObjective and not decorative then
            block._awpFirstObjective, block._awpFirstObjectiveHasCheckbox = line, row.checkbox ~= nil
            local check = block._awpCheck
            if check and check._awpBinding then Common.Controls.SetStepCheckbox(block, line, check._awpBinding) end
        end
        line._awpGuideProvider = key
        if Common.QuestDetails and not decorative then Common.QuestDetails.BindRow(line, block, row, key) end
        if NS.Internal.Appearance and line._awpGuideProvider then
            NS.Internal.Appearance.Text(line.Text, "guide." .. line._awpGuideProvider, nil, nil,
                row.role == "heading" and "heading" or row.kind == "tip" and "tip" or "body")
        end
    end
    -- Heading fonts can differ in height. Measure after applying the role,
    -- including when a pooled heading becomes a normal objective again.
    local reflowSize = NS.GetGuideTrackerViewerTextSize
    and
        NS.GetGuideTrackerViewerTextSize(key,
            row.role == "heading" and "heading" or row.kind == "tip" and "tip" or "body") ~= nil
    if fullHeight or reflowRole or reflowSize then
        Render.ForceFullHeightWrap(line, block, row.text, reflowRole or reflowSize, fullHeight)
    end
    if line and showActions and not decorative and (row.kind == "goal" or row.kind == nil) then
        actions.BindRow(line, key, owner, block.parentModule, block, row.actionStepOwner)
    end
    local pad = NS.Internal.Controller
    if line and pad and pad.BindGuideRow then pad.BindGuideRow(line, key, owner, row.actionStepOwner, decorative) end
    Render.ApplyLineColor(line, row.status or "incomplete", row.kind or "goal", row.action)
    if line then
        Common.Controls.SetStepCheckbox(line, line.Text, not decorative and row.checkbox or nil)
        if line.Dash then
            if row.checkbox or decorative then line.Dash:Hide() else line.Dash:Show() end
        end
    end
    return line
end

function Render.EnsureBlockHeight(block, minimum)
    block.height = math.max(block.height or 0, block._awpHiddenGuideTitle and 1 or minimum)
end
