local NS = _G.AzerothWaypointNS

NS.RegisterExternalWaypointSource("rarescanner", {
    displayName = "RareScanner",
    stackMatches = {
        "rarescanner\\rarescanner.lua",
        "rarescanner\\core\\service\\rswaypoints.lua",
        "rarescanner\\core\\service\\addons\\rstomtom.lua",
    },
    transient = true,
    iconKey = "rarescanner",
})

local BUTTON_NAME = "RARESCANNER_BUTTON"
local clickPhase = nil
local hooksInstalled = false

function NS.GetRareScannerClickPhase()
    return clickPhase
end

function NS.IsRareScannerClickPhaseDown()
    return clickPhase == "down"
end

local function InstallRareScannerClickPhaseHooks()
    if hooksInstalled then
        return true
    end
    local button = _G[BUTTON_NAME]
    if not button or type(button.HookScript) ~= "function" then
        return false
    end

    hooksInstalled = true
    button:HookScript("PreClick", function(_, _, down)
        clickPhase = down and "down" or "up"
    end)
    button:HookScript("PostClick", function()
        clickPhase = nil
    end)
    return true
end

local function ScheduleRareScannerClickPhaseHook()
    if InstallRareScannerClickPhaseHooks() then
        return
    end

    local frame = type(CreateFrame) == "function" and CreateFrame("Frame") or nil
    if not frame then
        return
    end
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self, event, addonName)
        if event == "ADDON_LOADED" and addonName ~= "RareScanner" then
            return
        end
        if InstallRareScannerClickPhaseHooks() then
            self:UnregisterEvent("ADDON_LOADED")
            self:UnregisterEvent("PLAYER_LOGIN")
        elseif type(NS.After) == "function" then
            NS.After(0, InstallRareScannerClickPhaseHooks)
        end
    end)

    if type(NS.After) == "function" then
        NS.After(0, InstallRareScannerClickPhaseHooks)
    end
end

ScheduleRareScannerClickPhaseHook()
