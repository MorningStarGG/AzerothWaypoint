-- ============================================================
-- Zygor Viewer event bindings
-- ============================================================
--
-- Connects Zygor's guide and goal messages to viewer refresh, chat output and
-- guide commands.

local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

local M = NS.Internal and NS.Internal.ZygorTrackerViewer
if not M then return end

local state = NS.State
state.zygorTrackerViewerBinding = state.zygorTrackerViewerBinding or {
    subscribed = false,
    pollerInstalled = false,
}

local binding = state.zygorTrackerViewerBinding

local function CommandGuides()
    local out, active, hasCurrent = {}, M.GetActiveZygorGuideTab(), false
    for _, tab in ipairs(M.GetZygorGuideTabs() or {}) do
        if type(tab.guide) == "table" and type(tab.guide.title) == "string" then
            out[#out + 1] = { id = tab.guide.title, label = M.GetZygorGuideTitle(tab), active = tab == active }
            if tab == active then hasCurrent = true end
        end
    end
    local Z = M.GetZygor()
    local current = Z and Z.CurrentGuide
    if not hasCurrent and current and type(current.title) == "string" then
        out[#out + 1] = { id = current.title, label = current.title_short or current.title, active = true }
    end
    return out
end
local function FindCommandTab(entry)
    for _, tab in ipairs(M.GetZygorGuideTabs() or {}) do
        if type(tab.guide) == "table" and tab.guide.title == entry.id then return tab end
    end
end

local function SetCompactMode(arg)
    local enabled = NS.IsGuideStepsOnlyHoverEnabled()
    arg = (arg or "status"):lower()
    if arg ~= "status" then
        if arg == "on" then
            enabled = true
        elseif arg == "off" then
            enabled = false
        elseif arg == "toggle" then
            enabled = not enabled
        else
            return false, "Use /awp zygor compact on|off|toggle|status."
        end
        NS.SetGuideStepsOnlyHoverEnabled(enabled)
        NS.Internal.Interface.options.RefreshViewerChromeMode()
    end
    return true, enabled and "Compact mode enabled." or "Compact mode disabled."
end

local commandControls = {
    commandLabels = { compact = "compact on|off|toggle|status" },
    compact = SetCompactMode,
    hasGuide = function()
        local z = M.GetZygor()
        return z ~= nil and z.CurrentGuide ~= nil
    end,
    next = M.NextZygorStep,
    prev = M.PreviousZygorStep,
    skip = M.SkipZygorStep,
    complete = M.SkipZygorStep,
    picker = M.OpenZygorNewGuide,
    settings = M.OpenZygorSettings,
    menu = function() return M.OpenZygorViewerMenu(UIParent) end,
    active = function() return NS.SelectGuideProvider("zygor", "ZygorCommandMakeActive") ~= false end,
    route = function() return NS.ActivateGuideProvider("zygor", "ZygorCommandRoute", { explicit = true }) ~= false end,
    output = M.OutputCurrentZygorStepToChat,
    load = function(input)
        local title, step = input:match("^(.-)%s+[sS][tT][eE][pP]%s+(%d+)$")
        return M.LoadZygorGuide(title or input, tonumber(step))
    end,
    reload = function()
        local Z = M.GetZygor()
        if type(Z.ReloadGuide) ~= "function" then return false, "native_reload_unavailable" end
        local ok, result = pcall(Z.ReloadGuide, Z); return ok and result ~= false
    end,
    guides = CommandGuides,
    switch = function(entry) return M.ActivateZygorTab(FindCommandTab(entry)) end,
    close = function(entry)
        local tab = FindCommandTab(entry)
        if tab then return M.CloseZygorTab(tab) end
        local Z = M.GetZygor()
        if Z and Z.CurrentGuide and Z.CurrentGuide.title == entry.id then return M.ClearCurrentZygorGuide() end
        return false, "stale_guide"
    end,
    reset = function()
        NS.SetGuideTrackerViewerProviderSetting("zygor", "hideNative", false)
        NS.ApplyGuideTrackerViewerSettings("zygor")
        local Z = M.GetZygor()
        if Z.Frame and type(Z.Frame.ResetWindow) == "function" then
            local ok, result = pcall(Z.Frame.ResetWindow, Z.Frame); return ok and result ~= false
        end
        return true, "Native viewer uncloaked, native window reset is unavailable."
    end,
}

if type(NS.RegisterGuideTrackerViewerProvider) == "function" then
    NS.RegisterGuideTrackerViewerProvider("zygor", {
        displayName = "Zygor Guides",
        controls = commandControls,
        isAvailable = NS.IsZygorLoaded,
        moduleName = "AwpZygorTrackerModule",
        applySettings = function()
            if type(M.ApplySettings) == "function" then M.ApplySettings() end
        end,
        refresh = function()
            if type(M.Refresh) == "function" then M.Refresh() end
        end,
        isAttached = function()
            local tracker = M.TrackerModule
            return tracker and type(tracker.IsAttached) == "function" and tracker.IsAttached() or false
        end,
    })
end

-- ============================================================
-- Native guide and frame updates
-- ============================================================

local function GetZ()
    return type(NS.ZGV) == "function" and NS.ZGV() or rawget(_G, "ZygorGuidesViewer") or rawget(_G, "ZGV")
end

local function SafeRefresh()
    if type(M.Refresh) == "function" then M.Refresh() end
end

local function SafeRefreshStep()
    if type(M.RefreshStep) == "function" then M.RefreshStep() end
end

local function SafeStepChatOutput()
    if type(M.QueueStepChatOutputOnStepChange) == "function" then
        M.QueueStepChatOutputOnStepChange()
    end
end

local function ApplyOnGuideLoaded()
    local settings = type(NS.GetGuideTrackerViewerSettings) == "function"
        and NS.GetGuideTrackerViewerSettings("zygor")
        or nil
    if not settings or not settings.enabled then return end
    if type(M.Show) == "function" then M.Show() end
end

local function IsEnabled()
    local settings = type(NS.GetGuideTrackerViewerSettings) == "function"
        and NS.GetGuideTrackerViewerSettings("zygor")
        or nil
    return settings and settings.enabled == true
end

local function InstallStartupPoller()
    if binding.pollerInstalled then return end
    if type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end

    binding.pollerInstalled = true
    local attempts = 0
    binding.startupTicker = C_Timer.NewTicker(0.5, function(ticker)
        attempts = attempts + 1

        if IsEnabled() and type(M.ApplySettings) == "function" then
            M.ApplySettings()
        end

        local Z = GetZ()
        if not Z or Z.initialized or Z.loading == nil or attempts >= 60 then
            ticker:Cancel()
            binding.startupTicker = nil
        end
    end)
end

-- ============================================================
-- Guide events and startup
-- ============================================================

local function OnGuideStateChanged()
    ApplyOnGuideLoaded()
    SafeRefreshStep()
end

local function SubscribeMessages()
    if binding.subscribed then return true end

    local Z = GetZ()
    if not Z then return false end

    if type(Z.AddMessageHandler) == "function" then
        pcall(Z.AddMessageHandler, Z, "ZGV_STEP_CHANGED", function()
            SafeRefreshStep()
            SafeStepChatOutput()
        end)
        pcall(Z.AddMessageHandler, Z, "ZGV_LOADING", OnGuideStateChanged)
        pcall(Z.AddMessageHandler, Z, "GUIDE_CHANGED", OnGuideStateChanged)
        pcall(Z.AddMessageHandler, Z, "ZGV_GUIDE_LOADED", OnGuideStateChanged)
        pcall(Z.AddMessageHandler, Z, "ZGV_INITIAL_GUIDE_LOADED", OnGuideStateChanged)
        pcall(Z.AddMessageHandler, Z, "ZGV_GUIDES_PARSED", OnGuideStateChanged)
        pcall(Z.AddMessageHandler, Z, "ZGV_GOAL_PROGRESS", function() SafeRefresh() end)
        pcall(Z.AddMessageHandler, Z, "ZGV_GOAL_COMPLETED", function() SafeRefresh() end)
        pcall(Z.AddMessageHandler, Z, "ZGV_GOAL_UNCOMPLETED", function() SafeRefresh() end)
        binding.subscribed = true
        return true
    end

    if type(Z.RegisterMessage) == "function" then
        pcall(Z.RegisterMessage, Z, "ZGV_STEP_CHANGED", function()
            SafeRefreshStep()
            SafeStepChatOutput()
        end)
        pcall(Z.RegisterMessage, Z, "ZGV_LOADING", OnGuideStateChanged)
        pcall(Z.RegisterMessage, Z, "GUIDE_CHANGED", OnGuideStateChanged)
        pcall(Z.RegisterMessage, Z, "ZGV_GUIDE_LOADED", OnGuideStateChanged)
        pcall(Z.RegisterMessage, Z, "ZGV_INITIAL_GUIDE_LOADED", OnGuideStateChanged)
        pcall(Z.RegisterMessage, Z, "ZGV_GUIDES_PARSED", OnGuideStateChanged)
        pcall(Z.RegisterMessage, Z, "ZGV_GOAL_PROGRESS", function() SafeRefresh() end)
        pcall(Z.RegisterMessage, Z, "ZGV_GOAL_COMPLETED", function() SafeRefresh() end)
        pcall(Z.RegisterMessage, Z, "ZGV_GOAL_UNCOMPLETED", function() SafeRefresh() end)
        binding.subscribed = true
        return true
    end

    return false
end

local function HookNativeFrameVisibility()
    local Z = GetZ()
    local frame = Z and Z.Frame
    if not frame or frame._awpTrackerViewerVisHooked then return end
    if type(frame.HookScript) ~= "function" then return end

    frame:HookScript("OnShow", function()
        if type(M.ApplyHideNativeFrameState) == "function" then
            M.ApplyHideNativeFrameState()
        end
    end)

    frame._awpTrackerViewerVisHooked = true
end

local function TryInitialize()
    if not SubscribeMessages() then return false end
    HookNativeFrameVisibility()
    if type(M.ApplySettings) == "function" then
        M.ApplySettings()
    end
    InstallStartupPoller()
    return true
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(self, event)
    if TryInitialize() then
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            self:UnregisterEvent("PLAYER_LOGIN")
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end
    end
end)

if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(2, function()
        if not binding.subscribed then TryInitialize() end
    end)
end
