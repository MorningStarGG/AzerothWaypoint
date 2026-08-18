local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Host = Shared.TrackerHost

local Proxy = {}
Shared.TrackerCombatProxy = Proxy

-- Blizzard's quest header buttons are unprotected, so a secure script wrapper
-- cannot suppress their OnClick handler during combat. Keep Blizzard's frames
-- and scripts untouched: while combat-locked, AWP-owned transparent buttons
-- sit over active native quest headers and consume the click before it enters
-- the tainted map-opening path. Outside combat every proxy is hidden.
local TRACKER_NAMES = {
    "CampaignQuestObjectiveTracker",
    "QuestObjectiveTracker",
}

local COMBAT_MESSAGE = "This action cannot be completed during combat."
local REFRESH_INTERVAL = 0.20

local eventFrame
local installed = false
local overlays = {}
local refreshElapsed = 0

local function IsBlizzardHost()
    if not Host or type(Host.IsKTLoaded) ~= "function" then return false end
    if Host.IsKTLoaded() then return false end
    if type(Host.GetTrackerFrame) ~= "function" then return false end
    return Host.GetTrackerFrame() == rawget(_G, "ObjectiveTrackerFrame")
end

local function IsCombatLocked()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function ShowCombatMessage()
    local errorsFrame = rawget(_G, "UIErrorsFrame")
    if errorsFrame and type(errorsFrame.AddExternalErrorMessage) == "function" then
        errorsFrame:AddExternalErrorMessage(COMBAT_MESSAGE)
        return
    end
    if errorsFrame and type(errorsFrame.AddMessage) == "function" then
        errorsFrame:AddMessage(COMBAT_MESSAGE, 1, 0.1, 0.1, 1)
        return
    end
    if type(NS.Msg) == "function" then
        NS.Msg(COMBAT_MESSAGE)
    end
end

local function HideOverlay(overlay)
    if not overlay then return end
    overlay:Hide()
    overlay.block = nil
    overlay.header = nil
    overlay:ClearAllPoints()
end

local function HideAllOverlays()
    for _, overlay in ipairs(overlays) do
        HideOverlay(overlay)
    end
end

local function CreateOverlay()
    local overlay = CreateFrame("Button", nil, rawget(_G, "UIParent"))
    overlay:Hide()
    overlay:EnableMouse(true)
    if type(overlay.EnableMouseMotion) == "function" then
        -- Keep the native quest hover/tooltip path available. This proxy owns
        -- click interception only.
        overlay:EnableMouseMotion(false)
    end
    overlay:RegisterForClicks("AnyUp")
    overlay:SetScript("OnClick", function()
        if IsCombatLocked() then
            ShowCombatMessage()
        end
    end)
    overlays[#overlays + 1] = overlay
    return overlay
end

local function GetOverlay(index)
    return overlays[index] or CreateOverlay()
end

local function IsHeaderVisible(header)
    if not header or type(header.IsVisible) ~= "function" then return false end
    local ok, visible = pcall(header.IsVisible, header)
    return ok and visible == true
end

local function PlaceOverlay(overlay, block)
    local header = block and block.HeaderButton
    if not IsHeaderVisible(header) then
        HideOverlay(overlay)
        return false
    end

    overlay.block = block
    overlay.header = header
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", header, "TOPLEFT")
    overlay:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT")

    if type(header.GetFrameStrata) == "function" then
        local ok, strata = pcall(header.GetFrameStrata, header)
        if ok and type(strata) == "string" then
            overlay:SetFrameStrata(strata)
        end
    end
    if type(header.GetFrameLevel) == "function" then
        local ok, level = pcall(header.GetFrameLevel, header)
        if ok and type(level) == "number" then
            overlay:SetFrameLevel(level + 1)
        end
    end

    overlay:Show()
    return true
end

local function CollectActiveBlocks()
    local blocks = {}
    local seen = {}

    local function AddBlock(block)
        if not block or seen[block] or not block.HeaderButton then return end
        seen[block] = true
        blocks[#blocks + 1] = block
    end

    for _, trackerName in ipairs(TRACKER_NAMES) do
        local tracker = rawget(_G, trackerName)
        if tracker and type(tracker.EnumerateActiveBlocks) == "function" then
            pcall(tracker.EnumerateActiveBlocks, tracker, AddBlock)
        end
    end

    return blocks
end

function Proxy.Refresh()
    if not installed or not IsBlizzardHost() or not IsCombatLocked() then
        HideAllOverlays()
        return
    end

    local activeBlocks = CollectActiveBlocks()
    local overlayIndex = 0
    for _, block in ipairs(activeBlocks) do
        local overlay = GetOverlay(overlayIndex + 1)
        if PlaceOverlay(overlay, block) then
            overlayIndex = overlayIndex + 1
        end
    end

    for index = overlayIndex + 1, #overlays do
        HideOverlay(overlays[index])
    end
end

local function SetCombatRefreshEnabled(enabled)
    if not eventFrame then return end
    refreshElapsed = 0
    if enabled then
        eventFrame:SetScript("OnUpdate", function(_, elapsed)
            refreshElapsed = refreshElapsed + elapsed
            if refreshElapsed < REFRESH_INTERVAL then return end
            refreshElapsed = 0
            Proxy.Refresh()
        end)
    else
        eventFrame:SetScript("OnUpdate", nil)
    end
end

local function EnsureEventFrame()
    if eventFrame then return eventFrame end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            SetCombatRefreshEnabled(true)
            Proxy.Refresh()
        elseif event == "PLAYER_REGEN_ENABLED" then
            SetCombatRefreshEnabled(false)
            HideAllOverlays()
        elseif IsCombatLocked() then
            Proxy.Refresh()
        end
    end)
    return eventFrame
end

function Proxy.Install()
    if installed then
        Proxy.Refresh()
        return true
    end
    if not IsBlizzardHost() then
        HideAllOverlays()
        return false
    end

    installed = true
    local frame = EnsureEventFrame()
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:RegisterEvent("QUEST_WATCH_LIST_CHANGED")

    if IsCombatLocked() then
        SetCombatRefreshEnabled(true)
    end
    Proxy.Refresh()
    return true
end

function Proxy.Uninstall()
    installed = false
    SetCombatRefreshEnabled(false)
    HideAllOverlays()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end
end

function Proxy.IsInstalled()
    return installed == true
end

function Proxy.GetStatus()
    local shown = 0
    for _, overlay in ipairs(overlays) do
        if overlay:IsShown() then
            shown = shown + 1
        end
    end
    return installed == true, IsCombatLocked(), shown, #overlays
end
