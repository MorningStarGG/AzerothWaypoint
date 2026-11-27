-- ============================================================
-- Zygor tracker controls
-- ============================================================
--
-- Maps Zygor's tracker header controls and guide menus to its native step and
-- guide commands.

local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Controls = {}
Shared.TrackerControls = Controls
local CommonControls = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.Controls

-- Late-bound accessor for the tracker module frame (owned by the coordinator,
-- created after this file loads). Only used at click/menu time.
local function GetModuleFrame()
    return Shared.GetModuleFrame and Shared.GetModuleFrame() or nil
end

-- ============================================================
-- Zygor step actions (shared across header controls + context menu)
-- ============================================================

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
    if type(NS.GetGuideTrackerViewerSettings) ~= "function" then return end
    local s = NS.GetGuideTrackerViewerSettings("zygor")
    if type(NS.SetGuideTrackerViewerProviderSetting) == "function" then
        NS.SetGuideTrackerViewerProviderSetting("zygor", "hideNative", not s.hideZygorFrame)
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

local function ShowGuideDropdown(anchorFrame)
    local MenuUtil = rawget(_G, "MenuUtil")
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then
        OpenZygorNewGuide()
        return
    end

    NS.Internal.Menus.CreateContextMenu(anchorFrame or _G.UIParent, function(_, root)
        root:SetTag("MENU_AWP_ZYGOR_GUIDES")
        root:CreateTitle("Open Guides")
        root:CreateButton("Make Zygor Active", function()
            NS.SelectGuideProvider("zygor", "ZygorTrackerMakeActive")
        end)

        Shared.AddOpenGuidesSubmenu(root)
    end)
end

local function IsZygorLoading(Z)
    if not Z or Z.initialized then return false end
    return Z.loading ~= nil and Z.loading ~= false and Z.loading ~= ""
end

-- Header controls and progress rendering are shared by every guide provider.
-- This file supplies only Zygor's callbacks and menus.
local function CreateHeaderControls(frame)
    if type(CommonControls) ~= "table" or type(CommonControls.Create) ~= "function" then return end
    CommonControls.Create(frame, {
        settingsTooltip = "Zygor menu",
        menuTooltip = "Switch or open guide",
        previousTooltip = "Previous step",
        nextTooltip = "Next step",
        onSettings = Shared.OpenZygorViewerMenu,
        onMenu = function(button) ShowGuideDropdown(button) end,
        onPrevious = ZygorPrev,
        onNext = ZygorNext,
    })
end

local function UpdateHeaderControls(frame, step, stepCount)
    if type(CommonControls) ~= "table" or type(CommonControls.Update) ~= "function" then return end
    local current = step and (step.num or step.stepnum) or 0
    CommonControls.Update(frame, current, stepCount)
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

    NS.Internal.Menus.CreateContextMenu(parent, function(_, root)
        root:SetTag("MENU_AWP_ZYGOR_TRACKER")
        root:CreateTitle("Zygor Tracker Viewer")
        local details = NS.Internal.GuideTrackerViewer.QuestDetails
        if details then details.AddMenu(root, anchorFrame) end

        root:CreateButton("Make Zygor Active", function()
            if type(NS.SelectGuideProvider) == "function" then
                NS.SelectGuideProvider("zygor", "ZygorTrackerMakeActive")
            end
        end)
        root:CreateButton("Open Guide Picker", function() Shared.OpenZygorGuidePicker() end)
        root:CreateButton("Clear Current Guide", function() ClearZygorGuide() end)
        root:CreateButton("Skip This Step", function() ZygorSkip() end)
        root:CreateButton("Previous Step", function() ZygorPrev() end)

        local settings = type(NS.GetGuideTrackerViewerSettings) == "function"
            and NS.GetGuideTrackerViewerSettings("zygor") or {}
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
Controls.OpenZygorViewerSettingsMenu = Shared.OpenZygorViewerMenu
Controls.IsZygorLoading = IsZygorLoading
Controls.ZygorNext = ZygorNext
Controls.ZygorPrev = ZygorPrev
Controls.ZygorSkip = ZygorSkip
