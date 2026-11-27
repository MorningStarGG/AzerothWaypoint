-- ============================================================
-- Guide Viewer header controls
-- ============================================================
--
-- Builds the shared tracker header and updates its title, progress, active
-- indicator and guide controls.

local NS = _G.AzerothWaypointNS

local CreateFrame = _G.CreateFrame
local hooksecurefunc = _G.hooksecurefunc

NS.Internal = NS.Internal or {}
NS.Internal.GuideTrackerViewer = NS.Internal.GuideTrackerViewer or {}

local API = {}
local Common = NS.Internal.GuideTrackerViewer
NS.Internal.GuideTrackerViewer.Controls = API

local HEADER_EDGE_INSET = 4
local BUTTON_SIZE = 16
local CONTROL_GAP = 3
local STATUS_GAP = 2
local DEFAULT_PROGRESS_WIDTH = 58
local MIN_PROGRESS_WIDTH = 28

local STYLE_LAYOUT = {
    square = { counterYOffset = 0 },
    rounded = { counterYOffset = 0 },
    none = { counterYOffset = 0, hideBar = true },
}

local function SetTextureGroupShown(textures, shown)
    if type(textures) ~= "table" then return end
    for _, texture in ipairs(textures) do
        if texture then
            if shown then texture:Show() else texture:Hide() end
        end
    end
end

local function SetWidgetShown(widget, shown)
    if not widget then return end
    if shown then
        if type(widget.Show) == "function" then widget:Show() end
    elseif type(widget.Hide) == "function" then
        widget:Hide()
    end
end

local function GetProgressStyle(providerKey)
    local settings = type(NS.GetGuideTrackerViewerSettings) == "function"
        and NS.GetGuideTrackerViewerSettings(providerKey)
        or nil
    local style = settings and settings.progressStyle
    if style == "rounded" or style == "none" then return style end
    return "square"
end

local function GetHeaderRGB(providerKey)
    return Common.Styles.StatusToRGB("incomplete", "goal", nil, providerKey, "heading")
end

local function GetHeaderColorStyle(providerKey)
    return Common.Styles.GetTrackerColorStyle("incomplete", "goal", nil, providerKey, "heading")
end

local function ApplyHeaderColor(block, highlighted)
    local header = block and block.HeaderText
    if not header or type(header.SetTextColor) ~= "function" then return end
    local r, g, b = GetHeaderRGB(NS.Internal.GuideTrackerViewer.Styles.GetProviderKey(block))
    if highlighted then
        r = r + (1 - r) * 0.18
        g = g + (1 - g) * 0.18
        b = b + (1 - b) * 0.18
    end
    pcall(header.SetTextColor, header, r, g, b)
end

local function EnsureHeaderColorGuard(block)
    if not block or block._awpHeaderColorGuard or type(hooksecurefunc) ~= "function" then return end
    local hooked = false
    if type(block.OnHeaderEnter) == "function" then
        hooksecurefunc(block, "OnHeaderEnter", function(self) ApplyHeaderColor(self, true) end)
        hooked = true
    end
    if type(block.OnHeaderLeave) == "function" then
        hooksecurefunc(block, "OnHeaderLeave", function(self) ApplyHeaderColor(self, false) end)
        hooked = true
    end
    if type(block.UpdateHighlight) == "function" then
        hooksecurefunc(block, "UpdateHighlight", function(self)
            local button = self.HeaderButton or self
            local highlighted = type(button.IsMouseOver) == "function" and button:IsMouseOver()
            ApplyHeaderColor(self, highlighted == true)
        end)
        hooked = true
    end
    if hooked then block._awpHeaderColorGuard = true end
end

local function SetGuideTooltip(controls, title, hidden)
    controls.progressBar._awpGuideTitle, controls.progressBar._awpShowGuideTitle = title, hidden
    controls.guideBtn._awpGuideTitle, controls.guideBtn._awpShowGuideTitle = title, hidden
end

function API.SetGuideTitleTooltip(module, title, hidden)
    local controls = module and module._awpControls
    if controls then SetGuideTooltip(controls, title, hidden) end
end

function API.SetBlockHeaderText(block, text, isGuideTitle, suppressTitle)
    if not block then return false end
    if Common.QuestDetails then Common.QuestDetails.Clear(block) end
    EnsureHeaderColorGuard(block)
    local header = block.HeaderText
    local providerKey = NS.Internal.GuideTrackerViewer.Styles.GetProviderKey(block)
    local settings = type(NS.GetGuideTrackerViewerSettings) == "function"
        and NS.GetGuideTrackerViewerSettings(providerKey) or nil
    local hideTitle = isGuideTitle and (suppressTitle or settings and settings.hideGuideTitle == true)
    block._awpHiddenGuideTitle = hideTitle == true
    block._awpFirstObjective, block._awpFirstObjectiveHasCheckbox = nil, nil
    block._awpFirstLine = nil
    if isGuideTitle then
        API.SetGuideTitleTooltip(block.parentModule, text, hideTitle)
    end
    if hideTitle then text = "" end
    if NS.Internal.Appearance and providerKey then
        NS.Internal.Appearance.Text(header, "guide." .. providerKey, nil, nil, "heading")
    end
    local colorStyle = GetHeaderColorStyle(providerKey)
    if header and type(header.SetPoint) == "function" then
        pcall(header.SetPoint, header, "RIGHT", block.rightEdgeOffset or 0, 0)
    end
    if header and type(block.SetStringText) == "function" then
        local ok, height = pcall(block.SetStringText, block, header, text, true, colorStyle, false)
        if ok and type(height) == "number" then block.height = height end
    elseif type(block.SetHeader) == "function" then
        pcall(block.SetHeader, block, text)
    elseif header and type(header.SetText) == "function" then
        header:SetText(text)
    else
        return false
    end
    if NS.Internal.Appearance and providerKey and header and header.GetStringHeight then
        local before = header:GetStringHeight()
        NS.Internal.Appearance.Text(header, "guide." .. providerKey, nil, nil, "heading")
        local after = header:GetStringHeight()
        if type(block.height) == "number" and type(before) == "number" and type(after) == "number" then
            block.height = block.height + after - before
        end
    end
    if hideTitle and header then
        header:SetHeight(0)
        block.height = 0
    end
    local check = block._awpCheck
    if check and check._awpBinding then API.SetStepCheckbox(block, header, check._awpBinding) end
    ApplyHeaderColor(block, false)
    return true
end

API.GetHeaderRGB = GetHeaderRGB
API.EnsureHeaderColorGuard = EnsureHeaderColorGuard

-- ============================================================
-- Guide state and header content
-- ============================================================

function API.SetStepCheckbox(owner, anchor, config)
    if not owner then return nil end
    local check = owner._awpCheck
    if not config then
        if check then
            check._awpBinding = nil
            check:Hide()
        end
        return check
    end
    if not check then
        check = CreateFrame("CheckButton", nil, owner, "UICheckButtonTemplate")
        check:SetSize(15, 15)
        check:SetFrameLevel((owner:GetFrameLevel() or 0) + 5)
        check:SetScript("OnClick", function(self)
            local binding = self._awpBinding
            self:SetChecked(binding and binding.checked == true or false)
            if binding and type(binding.onClick) == "function" then binding.onClick() end
        end)
        check:SetScript("OnEnter", function(self)
            local binding = self._awpBinding
            if binding and _G.GameTooltip then
                _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                _G.GameTooltip:SetText(binding.tooltip or "Mark step complete", 1, 1, 1)
                if binding.detail then _G.GameTooltip:AddLine(binding.detail, 0.85, 0.85, 0.85, true) end
                _G.GameTooltip:Show()
            end
        end)
        check:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)
        owner._awpCheck = check
    end
    check._awpBinding = config
    local topAligned = config.topAligned
    if owner._awpHiddenGuideTitle then
        -- Row checkboxes retain their individual actions. The step action is
        -- still available through Next and the guide menu in that case.
        if not owner._awpFirstObjective or owner._awpFirstObjectiveHasCheckbox then
            check:Hide()
            return check
        end
        anchor, topAligned = owner._awpFirstObjective, true
    end
    check:ClearAllPoints()
    if anchor then
        check:SetPoint(topAligned and "TOPRIGHT" or "RIGHT", anchor,
            topAligned and "TOPLEFT" or "LEFT", -3, 0)
    else
        check:SetPoint("TOPLEFT", owner, "TOPLEFT", -20, -1)
    end
    check:SetChecked(config.checked == true)
    if config.disabled then check:Disable() else check:Enable() end
    check:Show()
    return check
end

local function UpdateActiveIndicator(frame)
    local controls = frame and frame._awpControls
    if not controls or not controls.activeIndicator then return end
    local multiple = type(NS.HasMultipleGuideTrackerViewers) == "function" and NS.HasMultipleGuideTrackerViewers()
    local settings = type(NS.GetGuideTrackerViewerSettings) == "function"
        and NS.GetGuideTrackerViewerSettings(frame._awpGuideProvider) or nil
    local compact = not settings or settings.compactActiveIndicator ~= false
    controls.compactIndicator = compact
    local active = multiple and type(NS.GetActiveGuideProvider) == "function"
        and NS.GetActiveGuideProvider() == frame._awpGuideProvider
    controls.indicatorActive = active == true
    if active then controls.activeIndicator:Show() else controls.activeIndicator:Hide() end
    API.LayoutHeader(frame)
end

function API.SetModuleHeader(frame, providerKey, label)
    local text = frame and frame.Header and frame.Header.Text
    if not text or type(text.SetText) ~= "function" then return false end
    frame._awpGuideProvider = providerKey
    local settings = type(NS.GetGuideTrackerViewerSettings) == "function"
        and NS.GetGuideTrackerViewerSettings(providerKey) or nil
    local hideName = settings and settings.hideProviderName == true
    local name = label or providerKey or "Guide"
    text:SetText(hideName and "" or name)
    local controls = frame._awpControls
    if controls then
        controls.progressBar._awpProviderLabel, controls.guideBtn._awpProviderLabel = name, name
    end
    UpdateActiveIndicator(frame)
    return true
end

local function ApplyProgressStyle(bar, providerKey)
    if not bar then return end
    local style = GetProgressStyle(providerKey)
    local layout = STYLE_LAYOUT[style] or STYLE_LAYOUT.square
    local showBar = layout.hideBar ~= true
    local appearance = NS.Internal.Appearance
    local themed = appearance and appearance.IsEnabled("guide." .. providerKey, "progress") or false
    local border = not themed or bar._awpAppearanceKeepProgressBorder == true

    if bar._awpProgressStyle ~= style or bar._awpProgressThemed ~= themed or bar._awpProgressBorder ~= border then
        SetTextureGroupShown(bar._awpSquareBorder, showBar and border and style == "square")
        SetTextureGroupShown(bar._awpRoundedBorder, showBar and border and style == "rounded")
        SetWidgetShown(bar._awpBackground, not themed)
        bar._awpProgressStyle, bar._awpProgressThemed, bar._awpProgressBorder = style, themed, border
    end

    SetWidgetShown(bar, showBar)
    SetWidgetShown(bar._awpCounter, showBar)

    if bar._awpCounter and bar._awpCounterYOffset ~= layout.counterYOffset then
        bar._awpCounter:ClearAllPoints()
        bar._awpCounter:SetPoint("CENTER", bar, "CENTER", 0, layout.counterYOffset)
        bar._awpCounterYOffset = layout.counterYOffset
    end
end

function API.RefreshAppearance(frame)
    local controls = frame._awpControls
    local bar = controls and controls.progressBar
    if not bar then return end
    if frame._awpGuideProvider then
        Common.Styles.ApplyText(controls.counter, frame._awpGuideProvider, "progress", "progress")
        local title = frame.Header and (frame.Header.Text or frame.Header.HeaderText)
        if title and NS.Internal.Appearance then
            NS.Internal.Appearance.Text(title, "guide." .. frame._awpGuideProvider, nil, nil, "heading")
        end
    end
    local appearance = NS.Internal.Appearance
    bar._awpRequestedWidth = appearance and appearance.GetProgressWidth
        and appearance.GetProgressWidth("guide." .. frame._awpGuideProvider) or bar._awpBaseRequestedWidth
    API.LayoutHeader(frame)
    ApplyProgressStyle(bar, frame._awpGuideProvider)
end

-- ============================================================
-- Toolbar layout
-- ============================================================

-- Reflow on actual header/appearance changes, not a ticker. The requested bar
-- width stays separate from its fitted width so widening restores the preference.
function API.LayoutHeader(frame)
    local controls = frame and frame._awpControls
    local header = frame and frame.Header
    if not controls or not header or type(header.GetWidth) ~= "function" then return end
    local width = header:GetWidth()
    if type(width) ~= "number" or width <= 0 then return end
    local bar = controls.progressBar
    local style = bar._awpProgressStyle or GetProgressStyle(frame._awpGuideProvider)
    local layout = STYLE_LAYOUT[style] or STYLE_LAYOUT.square
    local appearance = NS.Internal.Appearance
    local themed = appearance and appearance.IsEnabled("guide." .. frame._awpGuideProvider, "progress") or false
    local themedControls = appearance and appearance.IsEnabled("guide." .. frame._awpGuideProvider, "controls") or false
    local settings = type(NS.GetGuideTrackerViewerSettings) == "function"
        and NS.GetGuideTrackerViewerSettings(frame._awpGuideProvider) or nil
    local hideName = settings and settings.hideProviderName == true or false
    local active, compact = controls.indicatorActive == true, controls.compactIndicator ~= false
    local collapse = header.MinimizeButton
    local hasCollapse = collapse and collapse:IsShown() or false
    local requested = bar._awpRequestedWidth or DEFAULT_PROGRESS_WIDTH
    if controls.layoutWidth == width and controls.layoutStyle == style and controls.layoutThemed == themed
        and controls.layoutThemedControls == themedControls
        and controls.layoutHideName == hideName and controls.layoutActive == active
        and controls.layoutCompact == compact and controls.layoutCollapse == hasCollapse
        and controls.layoutRequested == requested then
        return
    end
    controls.layoutWidth, controls.layoutStyle, controls.layoutThemed = width, style, themed
    controls.layoutThemedControls = themedControls
    controls.layoutHideName, controls.layoutActive, controls.layoutCompact = hideName, active, compact
    controls.layoutCollapse, controls.layoutRequested = hasCollapse, requested

    local showBar = not layout.hideBar
    local barGap = style == "rounded" and not themed and 6 or CONTROL_GAP
    local noNavigation = controls.hideNavigation
    local coreFixed = noNavigation and (BUTTON_SIZE * 2 + CONTROL_GAP + (showBar and barGap or 0))
        or BUTTON_SIZE * 4 + CONTROL_GAP * 2 + (showBar and barGap * 2 or CONTROL_GAP)
    local available = math.max(0, width - HEADER_EDGE_INSET * 2)
    local collapseSpace = hasCollapse and (BUTTON_SIZE + STATUS_GAP) or 0
    local indicatorWidth = compact and 12 or 38
    -- At the host's narrowest widths use the same active dot, retaining room for
    -- the step counter and every clickable control. Restore text as space returns.
    if active and not compact and available - collapseSpace - indicatorWidth - CONTROL_GAP - coreFixed
        < (showBar and MIN_PROGRESS_WIDTH or 0) then
        indicatorWidth = 12
    end
    local statusSpace = collapseSpace + (active and (indicatorWidth + CONTROL_GAP) or 0)
    local nameWidth = not hideName and math.min(48,
        math.max(0, available - statusSpace - coreFixed - (showBar and MIN_PROGRESS_WIDTH or 0) - 7)) or 0
    if nameWidth < 16 then nameWidth = 0 end
    local left = HEADER_EDGE_INSET + (nameWidth > 0 and nameWidth + 7 or 0)
    local right = width - HEADER_EDGE_INSET - statusSpace
    local barWidth = showBar and math.min(requested, math.max(1, right - left - coreFixed)) or 0
    local coreWidth = coreFixed + barWidth
    -- Center the visible strip, making room for status only on its active guide.
    -- A hidden provider name reserves no space on the left.
    local stripWidth = coreWidth + statusSpace
    local stripRight = left + (width - HEADER_EDGE_INSET - left + stripWidth) / 2

    if collapse then
        collapse:ClearAllPoints()
        collapse:SetPoint("RIGHT", header, "RIGHT", stripRight - width, 0)
    end
    controls.activeIndicator:ClearAllPoints()
    controls.activeIndicator:SetPoint("RIGHT", header, "RIGHT", stripRight - width - collapseSpace, 0)
    controls.activeIndicator:SetWidth(indicatorWidth)
    SetWidgetShown(controls.activeDot, indicatorWidth == 12)
    SetWidgetShown(controls.activeText, indicatorWidth ~= 12)
    controls.settingsBtn:ClearAllPoints()
    controls.settingsBtn:SetPoint("RIGHT", header, "LEFT", stripRight - statusSpace, 0)
    controls.guideBtn:ClearAllPoints()
    controls.guideBtn:SetPoint("RIGHT", controls.settingsBtn, "LEFT", -CONTROL_GAP, 0)
    controls.nextBtn:ClearAllPoints()
    controls.nextBtn:SetPoint("RIGHT", controls.guideBtn, "LEFT", -CONTROL_GAP, 0)
    bar:ClearAllPoints()
    bar:SetPoint("RIGHT", noNavigation and controls.guideBtn or controls.nextBtn, "LEFT", -barGap, 0)
    if showBar then bar:SetWidth(barWidth) end
    controls.prevBtn:ClearAllPoints()
    if showBar then
        controls.prevBtn:SetPoint("RIGHT", bar, "LEFT", -barGap, 0)
    else
        controls.prevBtn:SetPoint("RIGHT", controls.nextBtn, "LEFT", -CONTROL_GAP, 0)
    end
    local title = header.Text or header.HeaderText
    if noNavigation and title then
        title:ClearAllPoints(); title:SetPoint("LEFT", header, "LEFT", HEADER_EDGE_INSET, 0); title:SetWidth(nameWidth)
    end
    SetWidgetShown(title, nameWidth > 0)
    local tooltipName = hideName or nameWidth == 0
    bar._awpHideProviderName, controls.guideBtn._awpHideProviderName = tooltipName, tooltipName
end

-- ============================================================
-- Tooltips and control creation
-- ============================================================

local function ShowControlTooltip(anchor, detail, position)
    local tooltip = _G.GameTooltip
    if not tooltip then return end
    tooltip:SetOwner(anchor, position)
    local provider = anchor._awpHideProviderName and anchor._awpProviderLabel
    local guide = anchor._awpShowGuideTitle and anchor._awpGuideTitle
    if provider then
        tooltip:SetText(provider, 1, 1, 1)
        if guide then tooltip:AddLine(guide, 0.85, 0.85, 0.85, true) end
        tooltip:AddLine(detail, 0.85, 0.85, 0.85)
    elseif guide then
        tooltip:SetText(guide, 1, 1, 1)
        tooltip:AddLine(detail, 0.85, 0.85, 0.85)
    else
        tooltip:SetText(detail, 1, 1, 1)
    end
    tooltip:Show()
end

local function MakeIconButton(parent, atlas, rotation, tooltip, onClick)
    local button = NS.Internal.Interface.Framework.CreateIconButton(parent, {
        size = BUTTON_SIZE, atlas = atlas, rotation = rotation,
    })
    button:SetScript("OnClick", function(self, mouseButton)
        if type(onClick) == "function" then onClick(self, mouseButton) end
    end)
    button:HookScript("OnEnter", function(self)
        ShowControlTooltip(self, tooltip or "", "ANCHOR_TOP")
    end)
    button:HookScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    return button
end

function API.Create(frame, config)
    local header = frame and frame.Header
    if not header or frame._awpControls then return frame and frame._awpControls end
    config = type(config) == "table" and config or {}

    local controls = {
        hideNavigation = config.hideNavigation == true,
        progressUnit = config.progressUnit,
        previousEnabled = config.previousEnabled,
        nextEnabled = config.nextEnabled
    }
    local buttonSize = BUTTON_SIZE
    local progressWidth = DEFAULT_PROGRESS_WIDTH
    local headerTextGap = 7
    controls.settingsBtn = MakeIconButton(header, "questlog-icon-setting", nil,
        config.settingsTooltip or "Settings", config.onSettings)
    controls.settingsBtn:SetSize(buttonSize, buttonSize)

    local indicator = CreateFrame("Frame", nil, header)
    indicator:SetSize(38, 16)
    local indicatorText = indicator:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    indicatorText:SetPoint("CENTER")
    indicatorText:SetText("|cff55ff55Active|r")
    local dot = indicator:CreateTexture(nil, "ARTWORK")
    dot:SetSize(8, 8)
    dot:SetPoint("CENTER")
    dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    dot:SetVertexColor(0.33, 1, 0.33)
    controls.activeDot, controls.activeText = dot, indicatorText
    indicator:EnableMouse(true)
    indicator:SetScript("OnEnter", function(self)
        if _G.GameTooltip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
            _G.GameTooltip:SetText("This guide controls AWP navigation.", 1, 1, 1)
            _G.GameTooltip:Show()
        end
    end)
    indicator:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)
    indicator:Hide()
    controls.activeIndicator = indicator

    controls.guideBtn = MakeIconButton(header, "common-dropdown-icon-next", -math.pi / 2,
        config.menuTooltip or "Guide actions", config.onMenu)
    controls.guideBtn:SetSize(buttonSize, buttonSize)

    controls.nextBtn = MakeIconButton(header, config.nextAtlas or "common-dropdown-icon-next", config.nextRotation,
        config.nextTooltip or "Next step", config.onNext)
    controls.nextBtn:SetSize(buttonSize, buttonSize)

    local bar = CreateFrame("StatusBar", nil, header)
    bar._awpControllerVisualOnly = true
    bar:SetSize(progressWidth, 14)
    bar._awpBaseRequestedWidth, bar._awpRequestedWidth = progressWidth, progressWidth
    -- Keep the themed fill above the header and below this percentage text.
    bar:SetFrameLevel((header:GetFrameLevel() or 0) + 2)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0, 0.6, 0, 1)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    local barTexture = bar:GetStatusBarTexture()
    if barTexture and type(barTexture.SetDrawLayer) == "function" then
        barTexture:SetDrawLayer("BORDER")
    end

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.55)
    bar._awpBackground = background
    bar._awpSquareBorder = {}
    bar._awpRoundedBorder = {}

    local function MakeBarEdge(point1, point2, horizontal)
        local texture = bar:CreateTexture(nil, "ARTWORK")
        texture:SetPoint(point1, bar, point1)
        texture:SetPoint(point2, bar, point2)
        if horizontal then texture:SetHeight(1) else texture:SetWidth(1) end
        texture:SetColorTexture(0, 0, 0, 0.85)
        bar._awpSquareBorder[#bar._awpSquareBorder + 1] = texture
    end
    MakeBarEdge("TOPLEFT", "TOPRIGHT", true)
    MakeBarEdge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    MakeBarEdge("TOPLEFT", "BOTTOMLEFT", false)
    MakeBarEdge("TOPRIGHT", "BOTTOMRIGHT", false)

    local roundedTexture = "Interface\\AchievementFrame\\UI-Achievement-ProgressBar-Border"
    local roundedLeft = bar:CreateTexture(nil, "ARTWORK")
    roundedLeft:SetTexture(roundedTexture)
    roundedLeft:SetWidth(16)
    roundedLeft:SetPoint("TOPLEFT", bar, "TOPLEFT", -6, 5)
    roundedLeft:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -6, -5)
    roundedLeft:SetTexCoord(0, 0.0625, 0, 0.75)
    bar._awpRoundedBorder[#bar._awpRoundedBorder + 1] = roundedLeft

    local roundedRight = bar:CreateTexture(nil, "ARTWORK")
    roundedRight:SetTexture(roundedTexture)
    roundedRight:SetWidth(16)
    roundedRight:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 6, 5)
    roundedRight:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -5)
    roundedRight:SetTexCoord(0.812, 0.8745, 0, 0.75)
    bar._awpRoundedBorder[#bar._awpRoundedBorder + 1] = roundedRight

    local roundedCenter = bar:CreateTexture(nil, "ARTWORK")
    roundedCenter:SetTexture(roundedTexture)
    roundedCenter:SetPoint("TOPLEFT", roundedLeft, "TOPRIGHT", 0, 0)
    roundedCenter:SetPoint("BOTTOMRIGHT", roundedRight, "BOTTOMLEFT", 0, 0)
    roundedCenter:SetTexCoord(0.0625, 0.812, 0, 0.75)
    bar._awpRoundedBorder[#bar._awpRoundedBorder + 1] = roundedCenter

    local counter = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    counter:SetPoint("CENTER", bar, "CENTER", 0, STYLE_LAYOUT.square.counterYOffset)
    counter:SetJustifyH("CENTER")
    counter:SetJustifyV("MIDDLE")
    counter:SetDrawLayer("OVERLAY", 7)
    counter:SetText("")
    bar._awpCounter = counter
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        ShowControlTooltip(self, self._awpStepText or "No active guide", "ANCHOR_BOTTOM")
    end)
    bar:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    controls.progressBar = bar
    controls.counter = counter

    controls.prevBtn = MakeIconButton(header, config.previousAtlas or "common-dropdown-icon-back",
        config.previousRotation,
        config.previousTooltip or "Previous step", config.onPrevious)
    controls.prevBtn:SetSize(buttonSize, buttonSize)

    ApplyProgressStyle(bar, frame._awpGuideProvider)
    local titleText = header.Text or header.HeaderText
    if titleText and type(titleText.SetPoint) == "function" then
        titleText:SetPoint("RIGHT", controls.prevBtn, "LEFT", -headerTextGap, 0)
    end
    frame._awpControls = controls
    if type(header.HookScript) == "function" then
        header:HookScript("OnSizeChanged", function() API.LayoutHeader(frame) end)
    end
    if controls.hideNavigation then
        controls.prevBtn:Hide(); controls.nextBtn:Hide()
    end
    API.LayoutHeader(frame)
    local pad = NS.Internal.Controller
    if pad then
        pad.RegisterGuideToolbar(frame, header,
            { controls.prevBtn, controls.nextBtn, controls.guideBtn, controls.settingsBtn, header.MinimizeButton })
    end
    return controls
end

-- ============================================================
-- Enabling header actions
-- ============================================================

local function SetButtonEnabled(button, enabled)
    enabled = enabled == true
    if button and button:IsEnabled() ~= enabled then
        if enabled then button:Enable() else button:Disable() end
    end
end

function API.UpdateHeaderActions(frame, snapshot)
    local controls = frame and frame._awpControls
    if not controls then return end
    if controls.previousEnabled then SetButtonEnabled(controls.prevBtn, controls.previousEnabled(snapshot) == true) end
    if controls.nextEnabled then SetButtonEnabled(controls.nextBtn, controls.nextEnabled(snapshot) == true) end
end

function API.Update(frame, current, total, progressPercent, snapshot)
    local controls = frame and frame._awpControls
    if not controls then return end
    current = tonumber(current) or 0
    total = tonumber(total) or 0
    local percent = tonumber(progressPercent) or (total > 0 and (current / total) * 100 or 0)
    if percent < 0 then percent = 0 elseif percent > 100 then percent = 100 end
    controls.counter:SetText(string.format("%d%%", math.floor(percent + 0.5)))

    local hasStep = current > 0 or controls.progressUnit and total > 0
    if not controls.previousEnabled then SetButtonEnabled(controls.prevBtn, hasStep and current > 1) end
    if not controls.nextEnabled then SetButtonEnabled(controls.nextBtn, hasStep and (total == 0 or current < total)) end
    API.UpdateHeaderActions(frame, snapshot)
    if controls.progressBar then
        if not hasStep then
            SetGuideTooltip(controls, nil, false)
        end
        ApplyProgressStyle(controls.progressBar, frame._awpGuideProvider)
        API.LayoutHeader(frame)
        controls.progressBar:SetValue(percent)
        local themed = controls.progressBar._awpAppearanceBar
        if themed and themed:IsShown() then themed:SetValue(percent) end
        controls.progressBar._awpStepText = (total > 0 and string.format("%d / %d", current, total))
            or (hasStep and string.format("Step %d", current))
            or "No active guide"
        if controls.progressUnit then
            controls.progressBar._awpStepText = total > 0 and string.format("%d / %d quests completed", current, total) or
            "Quest count unavailable"
            if total == 0 then controls.counter:SetText("—") end
        end
    end
end

API.ApplyProgressStyle = ApplyProgressStyle
