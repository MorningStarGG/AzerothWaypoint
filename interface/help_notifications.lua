-- ============================================================
-- Startup help notifications
-- ============================================================
--
-- Choose the startup help page and remember delivery per account or character.

local NS = _G.AzerothWaypointNS

local function GetStartupHelpMode()
    return type(NS.GetStartupHelpMode) == "function"
        and NS.GetStartupHelpMode()
        or NS.Constants.STARTUP_HELP_MODE_ACCOUNT
end

local function GetStartupWhatsNewMode()
    return type(NS.GetStartupWhatsNewMode) == "function"
        and NS.GetStartupWhatsNewMode()
        or NS.Constants.STARTUP_HELP_MODE_ACCOUNT
end

local function GetStoredAddonVersionForStartupMode(mode)
    local C = NS.Constants
    if mode == C.STARTUP_HELP_MODE_CHARACTER then
        return type(NS.GetStoredAddonVersionForCurrentCharacter) == "function"
            and NS.GetStoredAddonVersionForCurrentCharacter()
            or nil
    end
    return NS.GetStoredAddonVersion and NS.GetStoredAddonVersion() or nil
end

local function UpdateStoredAddonVersionForStartupMode(mode)
    local C = NS.Constants
    if mode == C.STARTUP_HELP_MODE_DISABLED then
        if type(NS.UpdateStoredAddonVersion) == "function" then
            NS.UpdateStoredAddonVersion()
        end
        if type(NS.UpdateStoredAddonVersionForCurrentCharacter) == "function" then
            NS.UpdateStoredAddonVersionForCurrentCharacter()
        end
        return
    end
    if mode == C.STARTUP_HELP_MODE_CHARACTER then
        if type(NS.UpdateStoredAddonVersionForCurrentCharacter) == "function" then
            NS.UpdateStoredAddonVersionForCurrentCharacter()
        end
        return
    end
    if type(NS.UpdateStoredAddonVersion) == "function" then
        NS.UpdateStoredAddonVersion()
    end
end

local function HasVersionUpgradePending(mode)
    if mode == NS.Constants.STARTUP_HELP_MODE_DISABLED then
        return false
    end

    local previousVersion = GetStoredAddonVersionForStartupMode(mode)
    if type(previousVersion) ~= "string" or previousVersion == "" then
        return false
    end

    return type(NS.CompareAddonVersions) == "function"
        and NS.CompareAddonVersions(previousVersion, NS.VERSION) < 0
        or false
end

local function HasSeenOverviewForStartupMode(mode)
    local C = NS.Constants
    if mode == C.STARTUP_HELP_MODE_CHARACTER then
        return type(NS.HasSeenOverviewOnCurrentCharacter) == "function"
            and NS.HasSeenOverviewOnCurrentCharacter()
            or false
    end
    if mode == C.STARTUP_HELP_MODE_ACCOUNT then
        if type(NS.HasSeenOverviewAccountWide) == "function" and NS.HasSeenOverviewAccountWide() then
            return true
        end
        if type(NS.HasSeenOverviewOnCurrentCharacter) == "function"
            and NS.HasSeenOverviewOnCurrentCharacter()
        then
            if type(NS.MarkOverviewShownAccountWide) == "function" then
                NS.MarkOverviewShownAccountWide()
            end
            return true
        end
    end
    return mode == C.STARTUP_HELP_MODE_DISABLED
end

local function MarkOverviewShownForStartupMode(mode)
    local C = NS.Constants
    if mode == C.STARTUP_HELP_MODE_CHARACTER then
        if type(NS.MarkOverviewShownOnCurrentCharacter) == "function" then
            NS.MarkOverviewShownOnCurrentCharacter()
        end
    elseif mode == C.STARTUP_HELP_MODE_ACCOUNT then
        if type(NS.MarkOverviewShownAccountWide) == "function" then
            NS.MarkOverviewShownAccountWide()
        end
    end
end

local function ShowOverviewNotification()
    NS.Msg("Opening quick-start guide.")
    NS.After(0.2, function()
        if type(NS.ShowHelp) == "function" then
            NS.ShowHelp("overview")
        end
    end)
end

function NS.CheckHelpNotification()
    local mode = GetStartupWhatsNewMode()
    if not HasVersionUpgradePending(mode) then
        return false
    end

    NS.Msg(string.format("Updated to v%s - opening What's New.", NS.VERSION))
    NS.After(0.2, function()
        if type(NS.ShowWhatsNew) == "function" then
            NS.ShowWhatsNew()
        end
    end)

    UpdateStoredAddonVersionForStartupMode(mode)

    return true
end

function NS.CheckStartupHelpNotification()
    local helpMode = GetStartupHelpMode()
    local whatsNewMode = GetStartupWhatsNewMode()
    local hasVersionUpgrade = HasVersionUpgradePending(whatsNewMode)

    if helpMode ~= NS.Constants.STARTUP_HELP_MODE_DISABLED then
        local replayOverview = type(NS.ConsumePendingOverviewReplayForCurrentCharacter) == "function"
            and NS.ConsumePendingOverviewReplayForCurrentCharacter()
            or false
        local hasSeenOverview = HasSeenOverviewForStartupMode(helpMode)

        if replayOverview or not hasSeenOverview then
            MarkOverviewShownForStartupMode(helpMode)

            ShowOverviewNotification()

            if not hasVersionUpgrade then
                UpdateStoredAddonVersionForStartupMode(whatsNewMode)
            end

            return "overview"
        end
    end

    if NS.CheckHelpNotification() then
        return "whats_new"
    end

    UpdateStoredAddonVersionForStartupMode(whatsNewMode)

    return nil
end

NS.CheckChangelogNotification = NS.CheckHelpNotification
