local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

local M = NS.Internal and NS.Internal.ZygorTrackerViewer
if not M then return end

local state = NS.State
state.zygorTrackerViewerBinding = state.zygorTrackerViewerBinding or {
    subscribed = false,
    pollerInstalled = false,
    pendingApply = false,
}

local binding = state.zygorTrackerViewerBinding

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
    local settings = type(NS.GetZygorTrackerViewerSettings) == "function"
        and NS.GetZygorTrackerViewerSettings()
        or nil
    if not settings or not settings.enabled then return end
    if type(M.Show) == "function" then M.Show() end
end

local function IsEnabled()
    local settings = type(NS.GetZygorTrackerViewerSettings) == "function"
        and NS.GetZygorTrackerViewerSettings()
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
        pcall(Z.AddMessageHandler, Z, "ZGV_GOAL_PROGRESS",    function() SafeRefresh() end)
        pcall(Z.AddMessageHandler, Z, "ZGV_GOAL_COMPLETED",   function() SafeRefresh() end)
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
        pcall(Z.RegisterMessage, Z, "ZGV_GOAL_PROGRESS",    function() SafeRefresh() end)
        pcall(Z.RegisterMessage, Z, "ZGV_GOAL_COMPLETED",   function() SafeRefresh() end)
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
