local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

local CreateFrame = _G.CreateFrame

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Controls = {}
Shared.TrackerControls = Controls

-- Late-bound accessor for the tracker module frame (owned by the coordinator,
-- created after this file loads). Only used at click/menu time.
local function GetModuleFrame()
    return Shared.GetModuleFrame and Shared.GetModuleFrame() or nil
end

-- ============================================================
-- Zygor step actions (shared across header controls + context menu)
-- ============================================================

local function GetZ()
    return type(Shared.GetZygor) == "function" and Shared.GetZygor()
        or type(NS.ZGV) == "function" and NS.ZGV()
        or rawget(_G, "ZygorGuidesViewer")
        or rawget(_G, "ZGV")
end

local function ZygorNext()
    if type(Shared.NextZygorStep) == "function" then Shared.NextZygorStep() end
end

local function ZygorPrev()
    if type(Shared.PreviousZygorStep) == "function" then Shared.PreviousZygorStep() end
end

local function ZygorSkip()
    if type(Shared.SkipZygorStep) == "function" then Shared.SkipZygorStep() end
end

local function ClearZygorGuide()
    if type(Shared.ClearCurrentZygorGuide) == "function" then Shared.ClearCurrentZygorGuide() end
end

local function ToggleHideNative()
    if type(NS.GetZygorTrackerViewerSettings) ~= "function" then return end
    local s = NS.GetZygorTrackerViewerSettings()
    if type(NS.SetZygorTrackerViewerSetting) == "function" then
        NS.SetZygorTrackerViewerSetting("hideZygorFrame", not s.hideZygorFrame)
    end
    if type(NS.ApplyZygorTrackerViewerSettings) == "function" then
        NS.ApplyZygorTrackerViewerSettings()
    end
end

local function OpenZygorNewGuide()
    return type(Shared.OpenZygorNewGuide) == "function"
        and Shared.OpenZygorNewGuide()
        or Shared.OpenZygorGuidePicker()
end

local function OpenZygorSettings()
    return type(Shared.OpenZygorSettings) == "function"
        and Shared.OpenZygorSettings()
        or Shared.OpenZygorGuidePicker("Options")
end

local function CloseZygorTab(tab)
    if type(Shared.CloseZygorTab) == "function" then Shared.CloseZygorTab(tab) end
end

local function GetZygorGuideTabs()
    if type(Shared.GetZygorGuideTabs) == "function" then
        return Shared.GetZygorGuideTabs()
    end
    return nil, GetZ(), nil
end

local function AddGuideDropdownEntry(root, tab, active)
    if type(Shared.AddGuideDropdownEntry) == "function" then
        Shared.AddGuideDropdownEntry(root, tab, active)
    end
end

local function ShowGuideDropdown(anchorFrame)
    local MenuUtil = rawget(_G, "MenuUtil")
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then
        OpenZygorNewGuide()
        return
    end

    MenuUtil.CreateContextMenu(anchorFrame or _G.UIParent, function(_, root)
        root:SetTag("MENU_AWP_ZYGOR_GUIDES")
        root:CreateTitle("Open Guides")

        local pool, Z, tabs = GetZygorGuideTabs()
        local count = 0
        local activeTab
        if type(pool) == "table" then
            for _, tab in ipairs(pool) do
                if type(tab) == "table" and tab.guide then
                    count = count + 1
                    local active = tab == (tabs and tabs.ActiveTab) or tab.isActive or tab.guide == (Z and Z.CurrentGuide)
                    if active then activeTab = tab end
                    AddGuideDropdownEntry(root, tab, active)
                end
            end
        end

        if count == 0 then
            root:CreateTitle("No open guides")
        end

        if type(root.CreateDivider) == "function" then
            root:CreateDivider()
        end
        if activeTab then
            root:CreateButton("Close Current Guide", function() CloseZygorTab(activeTab) end)
        end
        root:CreateButton("|A:common-button-dropdown-closed:14:14|a Open New Guide...", function() OpenZygorNewGuide() end)
    end)
end

local function IsZygorLoading(Z)
    if not Z or Z.initialized then return false end
    return Z.loading ~= nil and Z.loading ~= false and Z.loading ~= ""
end

local function AddZygorMenuIcon(item, iconKey)
    local Z = GetZ()
    local iconset = Z and Z.ButtonSets and Z.ButtonSets.TitleButtons
    local icon = iconset and iconset[iconKey]
    local texcoord = icon and icon.texcoords
    if not iconset or not iconset.file or type(texcoord) ~= "table" or type(texcoord[1]) ~= "table" then
        return item
    end

    item.iconset = iconset
    item.iconkey = iconKey
    item.icon = iconset.file
    item.tCoordLeft = texcoord[1][1]
    item.tCoordRight = texcoord[1][2]
    item.tCoordTop = texcoord[1][3]
    item.tCoordBottom = texcoord[1][4]
    return item
end

local zygorSettingsMenuHost
local function GetZygorSettingsMenuHost(anchorFrame)
    if zygorSettingsMenuHost then
        return zygorSettingsMenuHost
    end

    local parent = GetModuleFrame() or anchorFrame or _G.UIParent
    local ok, host = pcall(CreateFrame, "Frame", nil, parent, "UIDropDownForkTemplate")
    if not ok or not host then
        host = CreateFrame("Frame", nil, parent)
    end

    zygorSettingsMenuHost = host
    return host
end

local function OpenZygorViewerSettingsMenu(anchorFrame)
    if type(Shared.OpenZygorViewerMenu) == "function" then
        Shared.OpenZygorViewerMenu(anchorFrame)
        return
    end

    local Z = GetZ()
    local EasyFork = rawget(_G, "EasyFork")
    local SetAnchor = rawget(_G, "UIDropDownFork_SetAnchor")
    if not Z or type(EasyFork) ~= "function" or type(SetAnchor) ~= "function" then
        OpenZygorSettings()
        return
    end

    local host = GetZygorSettingsMenuHost(anchorFrame)
    local dropdown = rawget(_G, "DropDownForkList1")
    local close = rawget(_G, "CloseDropDownForks")
    if dropdown and type(dropdown.IsShown) == "function" and dropdown:IsShown()
        and dropdown.dropdown == host
    then
        if type(close) == "function" then close() end
        return
    end

    local L = Z.L or {}
    local separator = rawget(_G, "UIDropDownFork_separatorInfo") or false
    local menu = {
        AddZygorMenuIcon({
            text = L.menu_GuideMenu or "Guide Menu",
            func = function()
                if Z.GuideMenu and type(Z.GuideMenu.Show) == "function" then
                    Z.GuideMenu:Show()
                end
            end,
            notCheckable = 1,
            paddingbottom = 8,
        }, "LIST"),
        AddZygorMenuIcon({
            text = L.menu_Startup or "Startup Guide Wizard",
            func = function()
                if Z.Modules and Z.Modules.IntroWizard and type(Z.Modules.IntroWizard.Checklist) == "function" then
                    Z.Modules.IntroWizard:Checklist()
                end
            end,
            notCheckable = 1,
        }, "WAND"),
        separator,
        AddZygorMenuIcon({
            text = L.menu_LockViewer or "Lock Viewer",
            func = function()
                if Z.db and Z.db.profile then
                    Z.db.profile.windowlocked = not Z.db.profile.windowlocked
                end
                if type(Z.UpdateLocking) == "function" then Z:UpdateLocking() end
            end,
            checked = function() return Z.db and Z.db.profile and Z.db.profile.windowlocked end,
            isNotRadio = 1,
            keepShownOnClick = 1,
            paddingbottom = 8,
        }, "LOCK_ON"),
        AddZygorMenuIcon({
            text = L.menu_EnableTransparency or "Enable Transparency",
            func = function()
                if Z.db and Z.db.profile then
                    Z.db.profile.opacitytoggle = not Z.db.profile.opacitytoggle
                    if type(Z.SetSkin) == "function" then
                        Z:SetSkin(Z.db.profile.skin, Z.db.profile.skinstyle)
                    end
                end
            end,
            checked = function() return Z.db and Z.db.profile and Z.db.profile.opacitytoggle end,
            isNotRadio = 1,
            keepShownOnClick = 1,
        }, "FRAME"),
        separator,
        AddZygorMenuIcon({
            text = (L.pointer_arrowmenu_findnearest or "Find NPC/Object"),
            hasArrow = true,
            menuList = Z.WhoWhere and Z.WhoWhere.Types,
            notCheckable = true,
            disabled = Z.loading or not (Z.WhoWhere and Z.WhoWhere.Types),
        }, "TRAINER"),
        separator,
        AddZygorMenuIcon({
            text = L.menu_Reset or "Reset window",
            func = function()
                if Z.Frame and type(Z.Frame.ResetWindow) == "function" then
                    Z.Frame:ResetWindow()
                end
            end,
            notCheckable = 1,
            paddingbottom = 8,
        }, "CLOSE"),
        AddZygorMenuIcon({
            text = L.menu_Reload or "Reload",
            func = function() if type(_G.ReloadUI) == "function" then _G.ReloadUI() end end,
            notCheckable = 1,
        }, "RELOAD"),
        separator,
        AddZygorMenuIcon({
            text = L.menu_Settings or "Settings",
            func = function() OpenZygorSettings() end,
            notCheckable = 1,
        }, "SETTINGS"),
    }

    if Z.IsClassic or Z.IsClassicTBC or Z.IsClassicWOTLK then
        table.insert(menu, 7, AddZygorMenuIcon({
            text = L.menu_ShowSkills or "Show Skills",
            func = function()
                if Z.Skills and type(Z.Skills.ShowSkillPopup) == "function" then
                    Z.Skills:ShowSkillPopup(nil, nil, "forceShow")
                end
            end,
            notCheckable = 1,
        }, "FINDNPC"))
    end

    local compactMenu = {}
    for _, item in ipairs(menu) do
        if item then
            item.maxWidth = 170
            compactMenu[#compactMenu + 1] = item
        end
    end

    local anchorOk = pcall(SetAnchor, host, 0, -2, "TOPRIGHT", anchorFrame or _G.UIParent, "BOTTOMRIGHT")
    local menuOk = anchorOk and pcall(EasyFork, compactMenu, host, nil, 0, 0, "MENU", 10)
    if not menuOk then
        OpenZygorSettings()
        return
    end

    dropdown = rawget(_G, "DropDownForkList1")
    if dropdown and anchorFrame and type(dropdown.ClearAllPoints) == "function" then
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -2)
    end
end

-- ============================================================
-- Header controls (Prev / Counter / Next / Skip overlay)
-- ============================================================

local function MakeAtlasButton(parent, normalAtlas, pushedAtlas, disabledAtlas, tooltip, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    btn:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)
    pcall(btn.SetNormalAtlas, btn, normalAtlas, false)
    if pushedAtlas then pcall(btn.SetPushedAtlas, btn, pushedAtlas, false) end
    if disabledAtlas then pcall(btn.SetDisabledAtlas, btn, disabledAtlas, false) end
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    btn:SetScript("OnClick", function(self, button) onClick(self, button) end)
    btn:SetScript("OnEnter", function(self)
        if _G.GameTooltip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
            _G.GameTooltip:SetText(tooltip, 1, 1, 1)
            _G.GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)

    return btn
end

local function SetTextureGroupShown(textures, shown)
    if type(textures) ~= "table" then return end
    for _, tex in ipairs(textures) do
        if tex then
            if shown then tex:Show() else tex:Hide() end
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

local function GetProgressBarStyle()
    local settings = type(NS.GetZygorTrackerViewerSettings) == "function"
        and NS.GetZygorTrackerViewerSettings()
        or nil
    local style = settings and settings.progressStyle
    if style == "rounded" or style == "none" then
        return style
    end
    return "square"
end

local PROGRESS_BAR_STYLE_LAYOUT = {
    square = {
        barYOffset = 0,
        counterYOffset = -1,
    },
    rounded = {
        barYOffset = 1,
        counterYOffset = -1.5,
    },
    none = {
        barYOffset = 0,
        counterYOffset = -1,
        hideBar = true,
    },
}

local function ApplyProgressBarStyle(bar)
    if not bar then return end
    local style = GetProgressBarStyle()
    local layout = PROGRESS_BAR_STYLE_LAYOUT[style] or PROGRESS_BAR_STYLE_LAYOUT.square
    local showBar = layout.hideBar ~= true

    if bar._awpProgressStyle ~= style then
        SetTextureGroupShown(bar._awpSquareBorder, showBar and style == "square")
        SetTextureGroupShown(bar._awpRoundedBorder, showBar and style == "rounded")
        bar._awpProgressStyle = style
    end

    SetWidgetShown(bar, showBar)
    SetWidgetShown(bar._awpCounter, showBar)

    if bar._awpAnchorFrame and bar._awpBarYOffset ~= layout.barYOffset then
        bar:ClearAllPoints()
        bar:SetPoint("RIGHT", bar._awpAnchorFrame, "LEFT", bar._awpAnchorX or -3, layout.barYOffset)
        bar._awpBarYOffset = layout.barYOffset
    end

    if bar._awpCounter and bar._awpCounterYOffset ~= layout.counterYOffset then
        bar._awpCounter:ClearAllPoints()
        bar._awpCounter:SetPoint("CENTER", bar, "CENTER", 0, layout.counterYOffset)
        bar._awpCounterYOffset = layout.counterYOffset
    end

    local prevAnchor = layout.hideBar and bar._awpAnchorFrame or bar
    local prevAnchorKey = layout.hideBar and "next" or "bar"
    local prevX = layout.hideBar and (bar._awpAnchorX or -3) or (bar._awpPrevButtonX or -3)
    local prevY = layout.hideBar and 0 or -layout.barYOffset
    if bar._awpPrevButton
        and (bar._awpPrevButtonAnchorKey ~= prevAnchorKey
            or bar._awpPrevButtonXApplied ~= prevX
            or bar._awpPrevButtonYOffset ~= prevY)
    then
        bar._awpPrevButton:ClearAllPoints()
        bar._awpPrevButton:SetPoint("RIGHT", prevAnchor, "LEFT", prevX, prevY)
        bar._awpPrevButtonAnchorKey = prevAnchorKey
        bar._awpPrevButtonXApplied = prevX
        bar._awpPrevButtonYOffset = prevY
    end
end

local function CreateHeaderControls(frame)
    local header = frame.Header
    if not header or frame._awpControls then return end

    local controls = {}

    -- Layout cluster anchored to the RIGHT of the header:
    -- with the step counter overlaid centered on the progress bar so the
    -- entire control set fits on one horizontal line.

    local buttonSize = 16
    local progressWidth = 58
    local headerTextGap = 7
    local controlYOffset = -1
    local stepControlYOffset = 2

    controls.settingsBtn = MakeAtlasButton(header,
        "common-dropdown-a-button-settings-shadowless",
        "common-dropdown-a-button-settings-pressed-shadowless-",
        "common-dropdown-a-button-settings-disabled-shadowless",
        "Zygor menu", function(self) OpenZygorViewerSettingsMenu(self) end)
    controls.settingsBtn:SetSize(buttonSize, buttonSize)
    controls.settingsBtn:SetPoint("RIGHT", header, "RIGHT", -16, controlYOffset)
    controls.guideBtn = MakeAtlasButton(header,
        "common-dropdown-a-button",
        "common-dropdown-a-button-pressed",
        "common-dropdown-a-button-disabled",
        "Switch or open guide", function(self) ShowGuideDropdown(self) end)
    controls.guideBtn:SetSize(buttonSize, buttonSize)
    controls.guideBtn:SetPoint("RIGHT", controls.settingsBtn, "LEFT", -3, 0)
    -- Next button
    controls.nextBtn = MakeAtlasButton(header,
        "perks-nextbutton",
        "perks-nextbutton-down",
        "perks-nextbutton-disabled",
        "Next step", ZygorNext)
    controls.nextBtn:SetSize(buttonSize, buttonSize)
    controls.nextBtn:SetPoint("RIGHT", controls.guideBtn, "LEFT", -3, stepControlYOffset)

    -- Progress bar between the buttons (the "middle" of the cluster)
    local bar = CreateFrame("StatusBar", nil, header)
    bar:SetSize(progressWidth, 14)
    bar._awpAnchorFrame = controls.nextBtn
    bar._awpAnchorX = -3
    bar:SetPoint("RIGHT", bar._awpAnchorFrame, "LEFT", bar._awpAnchorX, 0)
    bar:SetFrameLevel((header:GetFrameLevel() or 0) + 2)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0, 0.6, 0, 1)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    local barTexture = bar:GetStatusBarTexture()
    if barTexture and type(barTexture.SetDrawLayer) == "function" then
        barTexture:SetDrawLayer("BORDER")
    end

    -- Dark background behind the bar so the empty portion is visible
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.55)

    bar._awpSquareBorder = {}
    bar._awpRoundedBorder = {}

    -- Subtle square border around the bar so it reads as a deliberate widget
    local borderColor = { 0, 0, 0, 0.85 }
    local function MakeBarEdge(point1, point2, isHorizontal)
        local tex = bar:CreateTexture(nil, "ARTWORK")
        tex:SetPoint(point1, bar, point1)
        tex:SetPoint(point2, bar, point2)
        if isHorizontal then tex:SetHeight(1) else tex:SetWidth(1) end
        tex:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        bar._awpSquareBorder[#bar._awpSquareBorder + 1] = tex
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

    -- Step counter text centered over the bar
    local counterText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    counterText:SetPoint("CENTER", bar, "CENTER", 0, PROGRESS_BAR_STYLE_LAYOUT.square.counterYOffset)
    counterText:SetJustifyH("CENTER")
    counterText:SetJustifyV("MIDDLE")
    counterText:SetDrawLayer("OVERLAY", 7)
    counterText:SetText("")
    bar._awpCounter = counterText

    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        if _G.GameTooltip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            _G.GameTooltip:SetText(self._awpStepText or "No active guide", 1, 1, 1)
            _G.GameTooltip:Show()
        end
    end)
    bar:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)

    controls.progressBar = bar
    controls.counter = counterText

    -- Prev button on the far left of the cluster
    controls.prevBtn = MakeAtlasButton(header,
        "perks-backbutton",
        "perks-backbutton-down",
        "perks-backbutton-disabled",
        "Previous step", ZygorPrev)
    controls.prevBtn:SetSize(buttonSize, buttonSize)
    bar._awpPrevButton = controls.prevBtn
    bar._awpPrevButtonX = -3
    controls.prevBtn:SetPoint("RIGHT", bar, "LEFT", bar._awpPrevButtonX, 0)

    ApplyProgressBarStyle(bar)

    local titleText = header.Text or header.HeaderText
    if titleText and type(titleText.SetPoint) == "function" then
        titleText:SetPoint("RIGHT", controls.prevBtn, "LEFT", -headerTextGap, 0)
    end

    frame._awpControls = controls
end

local function UpdateHeaderControls(frame, step, stepCount)
    local controls = frame._awpControls
    if not controls then return end

    local curr = step and (step.num or step.stepnum) or 0
    local total = stepCount or 0
    local pct = (total > 0) and ((curr / total) * 100) or 0
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    local roundedPct = math.floor(pct + 0.5)
    controls.counter:SetText(string.format("%d%%", roundedPct))

    local hasStep = step ~= nil
    local hasPrev = hasStep and curr > 1
    local hasNext = hasStep and (total == 0 or curr < total)

    if controls.prevBtn then
        if hasPrev then controls.prevBtn:Enable() else controls.prevBtn:Disable() end
    end
    if controls.nextBtn then
        if hasNext then controls.nextBtn:Enable() else controls.nextBtn:Disable() end
    end

    if controls.progressBar then
        ApplyProgressBarStyle(controls.progressBar)
        controls.progressBar:SetValue(pct)
        controls.progressBar._awpStepText = total > 0
            and string.format("Step %d / %d", curr, total)
            or string.format("Step %d", curr)
    end
end

-- ============================================================
-- Right-click context menu (modern Blizzard MenuUtil API)
-- ============================================================
--

local function ShowContextMenu(anchorFrame)
    local MenuUtil = rawget(_G, "MenuUtil")
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then
        return
    end

    local module = GetModuleFrame()
    local parent = anchorFrame
    if not parent and module and type(module.GetContextMenuParent) == "function" then
        local ok, p = pcall(module.GetContextMenuParent, module)
        if ok then parent = p end
    end
    if not parent then parent = _G.UIParent end

    MenuUtil.CreateContextMenu(parent, function(_, root)
        root:SetTag("MENU_AWP_ZYGOR_TRACKER")
        root:CreateTitle("Zygor Tracker Viewer")

        root:CreateButton("Open Guide Picker", function() Shared.OpenZygorGuidePicker() end)
        root:CreateButton("Clear Current Guide", function() ClearZygorGuide() end)
        root:CreateButton("Skip This Step",      function() ZygorSkip()        end)
        root:CreateButton("Previous Step",       function() ZygorPrev()        end)

        local settings = type(NS.GetZygorTrackerViewerSettings) == "function"
            and NS.GetZygorTrackerViewerSettings() or {}
        local hideTitle = settings.hideZygorFrame
            and "Show Zygor's Native Frame"
            or "Hide Zygor's Native Frame"
        root:CreateButton(hideTitle, function() ToggleHideNative() end)
    end)
end

Controls.CreateHeaderControls = CreateHeaderControls
Controls.UpdateHeaderControls = UpdateHeaderControls
Controls.ShowGuideDropdown = ShowGuideDropdown
Controls.ShowContextMenu = ShowContextMenu
Controls.OpenZygorNewGuide = OpenZygorNewGuide
Controls.OpenZygorViewerSettingsMenu = OpenZygorViewerSettingsMenu
Controls.IsZygorLoading = IsZygorLoading
Controls.ZygorNext = ZygorNext
Controls.ZygorPrev = ZygorPrev
Controls.ZygorSkip = ZygorSkip
