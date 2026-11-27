-- ============================================================
-- Minimap button and menu
-- ============================================================
--
-- Builds the minimap menu and manages the button's tooltip, position and addon
-- compartment entry points.

local NS = _G.AzerothWaypointNS
local state = NS.State

state.minimapButton = state.minimapButton or {}
local minimapState = state.minimapButton

local ICON = "Interface\\AddOns\\AzerothWaypoint\\media\\icon_small.png"
local BUTTON_SIZE = 32
local SNAP_RADIUS_ADJ = -5

local function GetMinimapSettings()
    return type(NS.GetMinimapButtonSettings) == "function"
        and NS.GetMinimapButtonSettings()
        or { enabled = true }
end

local function OpenOptions()
    if type(NS.OpenOptionsPanel) == "function" then
        NS.OpenOptionsPanel()
    end
end

local function OpenHelp()
    if type(NS.ShowHelp) == "function" then
        NS.ShowHelp("overview")
    end
end

local function OpenQueue()
    if type(NS.ShowQueuePanel) == "function" then
        NS.ShowQueuePanel({ forceQuestLog = true })
    end
end

local function CreateButton(root, text, callback, enabled)
    local item = root:CreateButton(text, callback)
    if item and item.SetEnabled then item:SetEnabled(enabled ~= false) end
    return item
end

local function AddDivider(root)
    if root.CreateDivider then root:CreateDivider() end
end

local guideCommands = {
    {"Make Active", "active"}, {"Route This Step", "route"},
    {"Next Step", "next"}, {"Previous Step", "prev"}, {"Skip Step", "skip"},
    {"Mark Step Complete", "complete"}, {"Choose Task", "tasks"},
    {"Return to Automatic Order", "automatic"}, {"Recheck Progress", "reload"},
    {"Current Guide Steps", "steps"}, {"Native Guide Menu", "menu"}, {"Native Settings", "settings"},
}

local function GuideAvailable(key)
    local provider = NS.GetGuideTrackerViewerProvider and NS.GetGuideTrackerViewerProvider(key)
    if not provider or not provider.controls then return end
    local available = provider.isAvailable
    if available then
        local ok, loaded = pcall(available)
        if not ok or not loaded then return end
    end
    return provider
end

-- ============================================================
-- Guide and service menus
-- ============================================================

local function AddGuideMenu(root, key, provider, anchor)
    local common = NS.Internal.GuideTrackerViewer
    local actions, controls = common.Actions, provider.controls
    local function Command(label, action)
        if type(controls[action]) ~= "function" then return end
        local enabled = actions.GetActionState(key, action)
        CreateButton(root, controls.menuLabels and controls.menuLabels[action] or label, function()
            local ok, reason = actions.Run(key, action, anchor)
            if not ok and reason then NS.Msg(reason) end
        end, enabled)
    end
    for _, entry in ipairs(guideCommands) do Command(entry[1], entry[2]) end
    if common.Tabs.Supports(key) then common.Tabs.AddMenu(key, root, anchor)
    else Command("Open New Guide...", "picker") end
    AddDivider(root)
    for _, option in ipairs({{"enabled", "Show AWP Tracker Viewer"}, {"hideNative", "Hide Native Guide Frame"}}) do
        local field, label = option[1], option[2]
        root:CreateCheckbox(label, function()
            return NS.GetGuideTrackerViewerProviderSettings(key)[field] == true
        end, function()
            if not GuideAvailable(key) then return end
            local settings = NS.GetGuideTrackerViewerProviderSettings(key)
            NS.SetGuideTrackerViewerProviderSetting(key, field, not settings[field])
            NS.ApplyGuideTrackerViewerSettings(key)
        end)
    end
end

function NS.ShowMinimapButtonMenu(anchorFrame)
    local util = rawget(_G, "MenuUtil")
    if not util or not util.CreateContextMenu then OpenOptions(); return end
    local anchor = anchorFrame or UIParent
    local function Generate(_, root)
        root:SetTag("MENU_AWP_MINIMAP")
        NS.Internal.MinimapMenus.HoldDrawer(root, anchor)
        root:CreateTitle("AzerothWaypoint")
        local active = NS.GetActiveGuideProvider and NS.GetActiveGuideProvider()
        local activeProvider = active and GuideAvailable(active)
        if activeProvider then
            local submenu = root:CreateButton("Active Guide: " .. activeProvider.displayName)
            AddGuideMenu(submenu, active, activeProvider, anchor)
        end
        -- Other loaded guides follow Viewer order, including hidden Viewers.
        for _, key in ipairs(NS.GetGuideTrackerViewerOrder and NS.GetGuideTrackerViewerOrder() or {}) do
            if key ~= active then
                local provider = GuideAvailable(key)
                if provider then AddGuideMenu(root:CreateButton(provider.displayName), key, provider, anchor) end
            end
        end
        local search = NS.Internal.ServiceSearch
        local services = search and search.GetCatalog()
        if services and #services > 0 then
            local function AddSearchEntries(parent, entries)
                for _, entry in ipairs(entries) do
                    if entry.children then AddSearchEntries(parent:CreateButton(entry.label), entry.children)
                    else
                        local query = entry.query
                        parent:CreateButton(entry.label, function() search.Request(query) end)
                    end
                end
            end
            AddSearchEntries(root:CreateButton("Search Nearby"), services)
        end
        AddDivider(root)
        local pad = NS.Internal.Controller
        if pad and pad.Enabled() then
            root:CreateButton("Navigate AWP Guides", function() pad.NavigateGuides() end)
            root:CreateButton("Navigate Guide Action Panels", function() pad.NavigateGuides(true) end)
        end
        root:CreateButton("Open AWP Settings", OpenOptions)
        root:CreateButton("Open Help", OpenHelp)
        root:CreateButton("Open Queue", OpenQueue)
        root:CreateButton("Reset Minimap Button Position", function() NS.ResetMinimapButtonPosition() end)
        root:CreateButton("Hide Minimap Button", function() NS.SetMinimapButtonEnabled(false) end)
    end
    -- Keep the mouse menu beside its button when opened from a minimap drawer.
    local menus = NS.Internal.Menus
    local position = not menus.UsesController() and type(CreateAnchor) == "function"
        and CreateAnchor("TOPLEFT", anchor, "TOPRIGHT") or nil
    menus.CreateContextMenu(anchor, Generate, position)
end

-- ============================================================
-- Tooltip and button position
-- ============================================================

local function ShowTooltip(owner)
    if not _G.GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("AzerothWaypoint", 1, 1, 1)
    if NS.VERSION then
        GameTooltip:AddLine("v" .. tostring(NS.VERSION), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Left-click: quick menu", 0, 1, 0)
    GameTooltip:AddLine("Right-click: AWP settings", 0, 1, 0)
    GameTooltip:AddLine("Drag: move button", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function HideTooltip()
    if _G.GameTooltip then GameTooltip:Hide() end
end

local function ApplyDefaultPosition(button)
    button:ClearAllPoints()
    button:SetPoint("CENTER", _G.Minimap or _G.UIParent, "BOTTOMLEFT", 16, 16)
end

local function ApplySavedPosition(button)
    local settings = GetMinimapSettings()
    local pos = settings.position
    button:ClearAllPoints()
    if type(pos) == "table" and pos.point then
        button:SetPoint(pos.point, _G.UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
    else
        ApplyDefaultPosition(button)
    end
end

local function SaveButtonPosition(button)
    if type(NS.SetMinimapButtonSetting) ~= "function" then return end
    if not button or type(button.GetCenter) ~= "function" or not _G.UIParent then return end
    local bx, by = button:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not bx or not by or not ux or not uy then
        NS.SetMinimapButtonSetting("position", nil)
        return
    end
    NS.SetMinimapButtonSetting("position", {
        point = "CENTER",
        relPoint = "CENTER",
        x = bx - ux,
        y = by - uy,
    })
end

local function UpdateDragPosition(button)
    local minimap = _G.Minimap
    if not minimap or type(minimap.GetCenter) ~= "function" then return end

    local radius = (minimap:GetWidth() + button:GetWidth()) / 2
    local width = button:GetWidth()
    local x, y = minimap:GetCenter()
    local scale = minimap:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    if not x or not y or not mx or not my or not scale or scale == 0 then return end

    mx = mx / scale
    my = my / scale
    local dx, dy = mx - x, my - y
    local dist = (dx * dx + dy * dy) ^ 0.5
    if dist == 0 then return end

    local radMin = radius + SNAP_RADIUS_ADJ
    local radSnap = radius + width * 0.2
    local radPull = radius + width * 0.7
    local radFree = radius + width
    local radClamp

    if dist <= radSnap then
        button._awpSnapped = true
        radClamp = radMin
    elseif dist < radPull and button._awpSnapped then
        radClamp = radMin
    elseif dist < radFree and button._awpSnapped then
        radClamp = radMin + (dist - radPull) / 2
    else
        button._awpSnapped = false
    end

    if radClamp then
        dx = dx / (dist / radClamp)
        dy = dy / (dist / radClamp)
        button:ClearAllPoints()
        button:SetPoint("CENTER", minimap, "CENTER", dx, dy)
    end
end

local function FinishDrag(button)
    if button:GetScript("OnUpdate") ~= UpdateDragPosition then return end
    button:SetScript("OnUpdate", nil)
    button:StopMovingOrSizing()
    SaveButtonPosition(button)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            if button:GetScript("OnUpdate") ~= UpdateDragPosition then button._awpSuppressClick = false end
        end)
    else
        button._awpSuppressClick = false
    end
end

-- ============================================================
-- Minimap button and compartment callbacks
-- ============================================================

local function CreateMinimapButton()
    if minimapState.button then return minimapState.button end

    local parent = _G.Minimap or _G.UIParent
    local button = CreateFrame("Button", "AzerothWaypointMinimapButton", parent)
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local normal = button:CreateTexture(nil, "ARTWORK")
    normal:SetTexture(ICON)
    normal:SetAllPoints(button)
    button:SetNormalTexture(normal)

    local pushed = button:CreateTexture(nil, "ARTWORK")
    pushed:SetTexture(ICON)
    pushed:SetAllPoints(button)
    pushed:SetVertexColor(0.75, 0.75, 0.75)
    button:SetPushedTexture(pushed)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(ICON)
    highlight:SetAllPoints(button)
    highlight:SetBlendMode("ADD")
    highlight:SetVertexColor(1, 1, 1, 0.35)
    button:SetHighlightTexture(highlight)

    button:SetScript("OnClick", function(self, mouseButton)
        if self._awpSuppressClick then return end
        HideTooltip()
        if mouseButton == "LeftButton" then
            NS.ShowMinimapButtonMenu(self)
        else
            OpenOptions()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        self._awpSuppressClick = true
        self:StartMoving()
        self:SetScript("OnUpdate", UpdateDragPosition)
    end)
    button:SetScript("OnDragStop", FinishDrag)
    button:SetScript("OnHide", FinishDrag)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", HideTooltip)

    minimapState.button = button
    ApplySavedPosition(button)
    return button
end

function NS.RefreshMinimapButton()
    local button = CreateMinimapButton()
    if button:GetScript("OnUpdate") ~= UpdateDragPosition then ApplySavedPosition(button) end
    if GetMinimapSettings().enabled then
        button:Show()
    else
        button:Hide()
    end
end

function NS.GetMinimapButtonStatus()
    local settings = GetMinimapSettings()
    return settings.enabled and "shown" or "hidden"
end

function AzerothWaypoint_OnAddonCompartmentEnter(_, buttonFrame)
    ShowTooltip(buttonFrame)
end

function AzerothWaypoint_OnAddonCompartmentLeave()
    HideTooltip()
end

function AzerothWaypoint_OnAddonCompartmentClick(_, mouseButton, buttonFrame)
    HideTooltip()
    if mouseButton == "LeftButton" then
        NS.ShowMinimapButtonMenu(buttonFrame)
    else
        OpenOptions()
    end
end
