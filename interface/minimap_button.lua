local NS = _G.AzerothWaypointNS
local state = NS.State

state.minimapButton = state.minimapButton or {}
local minimapState = state.minimapButton

local ICON = "Interface\\AddOns\\AzerothWaypoint\\media\\icon_small.png"
local BUTTON_SIZE = 32
local SNAP_RADIUS_ADJ = -5
local TRANSPARENT_ALPHA = 0.05

local function GetSharedZygor()
    local internal = NS.Internal and NS.Internal.ZygorTrackerViewer
    if type(internal) == "table" then return internal end
    return nil
end

local function GetZygorSettings()
    return type(NS.GetZygorTrackerViewerSettings) == "function"
        and NS.GetZygorTrackerViewerSettings()
        or nil
end

local function ApplyZygorTrackerSettings()
    if type(NS.ApplyZygorTrackerViewerSettings) == "function" then
        NS.ApplyZygorTrackerViewerSettings()
    end
end

local function ToggleTrackerViewer()
    local settings = GetZygorSettings()
    if not settings or type(NS.SetZygorTrackerViewerSetting) ~= "function" then return end
    NS.SetZygorTrackerViewerSetting("enabled", not settings.enabled)
    ApplyZygorTrackerSettings()
end

local function ToggleHideNativeViewer()
    local settings = GetZygorSettings()
    if not settings or type(NS.SetZygorTrackerViewerSetting) ~= "function" then return end
    NS.SetZygorTrackerViewerSetting("hideZygorFrame", not settings.hideZygorFrame)
    ApplyZygorTrackerSettings()
end

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

local function IsZygorAvailable()
    local shared = GetSharedZygor()
    return shared and type(shared.GetZygor) == "function" and shared.GetZygor() ~= nil
end

local function CreateButton(root, text, callback, enabled)
    local item = root:CreateButton(text, callback)
    if enabled == false and item and type(item.SetEnabled) == "function" then
        item:SetEnabled(false)
    end
    return item
end

local function AddDivider(root)
    if type(root.CreateDivider) == "function" then
        root:CreateDivider()
    end
end

local function AddZygorGuideMenu(root, anchorFrame)
    local shared = GetSharedZygor()
    local zygorAvailable = IsZygorAvailable()
    local submenu = root:CreateButton("Zygor Guide")
    if not submenu or type(submenu.CreateButton) ~= "function" then
        if zygorAvailable and shared and type(shared.OpenZygorViewerMenu) == "function" then
            root:CreateButton("Zygor Guide", function() shared.OpenZygorViewerMenu(anchorFrame) end)
        end
        return
    end

    if not zygorAvailable or not shared then
        if type(submenu.CreateTitle) == "function" then
            submenu:CreateTitle("Zygor is not loaded")
        else
            local item = submenu:CreateButton("Zygor is not loaded")
            if item and type(item.SetEnabled) == "function" then item:SetEnabled(false) end
        end
        return
    end

    CreateButton(submenu, "Next Step", function() shared.NextZygorStep() end, type(shared.NextZygorStep) == "function")
    CreateButton(submenu, "Previous Step", function() shared.PreviousZygorStep() end, type(shared.PreviousZygorStep) == "function")
    CreateButton(submenu, "Skip / Force Next Step", function() shared.SkipZygorStep() end, type(shared.SkipZygorStep) == "function")
    AddDivider(submenu)

    CreateButton(submenu, "Open New Guide", function() shared.OpenZygorNewGuide() end, type(shared.OpenZygorNewGuide) == "function")
    local openGuides = submenu:CreateButton("Currently Open Guides")
    if openGuides and type(openGuides.CreateButton) == "function" and type(shared.AddOpenGuidesSubmenu) == "function" then
        shared.AddOpenGuidesSubmenu(openGuides)
    elseif type(shared.ShowGuideDropdown) == "function" then
        submenu:CreateButton("Open Guides...", function() shared.ShowGuideDropdown(anchorFrame) end)
    end

    local activeTab = type(shared.GetActiveZygorGuideTab) == "function" and shared.GetActiveZygorGuideTab() or nil
    if activeTab and type(shared.CloseZygorTab) == "function" then
        submenu:CreateButton("Close Current Guide", function() shared.CloseZygorTab(activeTab) end)
    end
    AddDivider(submenu)

    CreateButton(submenu, "Zygor Viewer Menu", function() shared.OpenZygorViewerMenu(anchorFrame) end, type(shared.OpenZygorViewerMenu) == "function")
    CreateButton(submenu, "Zygor Settings", function() shared.OpenZygorSettings() end, type(shared.OpenZygorSettings) == "function")
end

function NS.ShowMinimapButtonMenu(anchorFrame)
    local MenuUtil = rawget(_G, "MenuUtil")
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then
        OpenOptions()
        return
    end

    MenuUtil.CreateContextMenu(anchorFrame or _G.UIParent, function(_, root)
        root:SetTag("MENU_AWP_MINIMAP")
        root:CreateTitle("AzerothWaypoint")

        local settings = GetZygorSettings() or {}
        CreateButton(root,
            settings.enabled and "Disable Tracker Viewer" or "Enable Tracker Viewer",
            ToggleTrackerViewer,
            type(NS.SetZygorTrackerViewerSetting) == "function")
        CreateButton(root,
            settings.hideZygorFrame and "Show Zygor's Native Frame" or "Hide Zygor's Native Frame",
            ToggleHideNativeViewer,
            type(NS.SetZygorTrackerViewerSetting) == "function")

        AddZygorGuideMenu(root, anchorFrame)
        AddDivider(root)

        root:CreateButton("Open AWP Settings", OpenOptions)
        root:CreateButton("Open Help", OpenHelp)
        root:CreateButton("Open Queue", OpenQueue)
        root:CreateButton("Reset Minimap Button Position", function()
            if type(NS.ResetMinimapButtonPosition) == "function" then
                NS.ResetMinimapButtonPosition()
            end
        end)
        root:CreateButton("Hide Minimap Button", function()
            if type(NS.SetMinimapButtonEnabled) == "function" then
                NS.SetMinimapButtonEnabled(false)
            end
        end)
    end)
end

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

local function OnUpdate(button)
    if not button:IsDragging() then return end
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
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveButtonPosition(self)
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, function() self._awpSuppressClick = false end)
        else
            self._awpSuppressClick = false
        end
    end)
    button:SetScript("OnUpdate", OnUpdate)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", HideTooltip)

    minimapState.button = button
    ApplySavedPosition(button)
    return button
end

function NS.RefreshMinimapButton()
    local button = CreateMinimapButton()
    ApplySavedPosition(button)
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

local function GetTrackerFrame()
    local kt = rawget(_G, "KT_ObjectiveTrackerFrame")
    if kt then
        return kt, "Kaliel's Tracker"
    end
    return rawget(_G, "ObjectiveTrackerFrame"), "Blizzard Objective Tracker"
end

function NS.GetObjectiveTrackerVisibilityStatus()
    local frame, host = GetTrackerFrame()
    local status = {
        host = host,
        frame = frame,
        exists = frame ~= nil,
        shown = false,
        visible = false,
        hardHidden = false,
        alpha = nil,
        transparent = false,
    }

    if not frame then
        status.visibility = "missing"
        status.opacity = "unknown"
        return status
    end

    local okShown, shown = pcall(frame.IsShown, frame)
    local okVisible, visible = pcall(frame.IsVisible, frame)
    status.shown = okShown and shown == true
    status.visible = okVisible and visible == true
    status.hardHidden = not status.shown or not status.visible
    status.visibility = status.hardHidden and "hidden" or "visible"

    local alpha
    if type(frame.GetEffectiveAlpha) == "function" then
        local ok, value = pcall(frame.GetEffectiveAlpha, frame)
        if ok and type(value) == "number" then alpha = value end
    end
    if alpha == nil and type(frame.GetAlpha) == "function" then
        local ok, value = pcall(frame.GetAlpha, frame)
        if ok and type(value) == "number" then alpha = value end
    end

    status.alpha = alpha
    status.transparent = alpha ~= nil and alpha <= TRANSPARENT_ALPHA
    status.opacity = status.transparent and "transparent" or "normal"
    return status
end

function NS.IsObjectiveTrackerHardHidden()
    local status = NS.GetObjectiveTrackerVisibilityStatus()
    return status and status.hardHidden == true
end

function NS.MaybeWarnObjectiveTrackerVisibility()
    local settings = GetZygorSettings()
    if not settings or not settings.enabled then return end

    local status = NS.GetObjectiveTrackerVisibilityStatus()
    if not status or not status.exists then return end

    if status.hardHidden then
        NS.Msg("|cffffcc00AzerothWaypoint:|r Tracker Viewer is enabled, but the objective tracker is hidden. Guide steps cannot display until it is shown.")
    elseif status.transparent then
        NS.Msg("|cffffcc00AzerothWaypoint:|r Tracker Viewer is enabled, but the objective tracker appears transparent. Guide steps may be present but invisible.")
    end
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
