-- ============================================================
-- APR Viewer
-- ============================================================
--
-- Connects APR guide hooks and viewer settings to the shared source viewer.

local NS = _G.AzerothWaypointNS
local viewer = NS.Internal.GuideTrackerViewer.SourceViewer.Register({
    key = "apr",
    addon = "APR",
    api = NS.Internal.APRProvider,
    isLoaded = NS.IsAPRLoaded,
    skipHeader = true,
    frames = function()
        local frames = {}
        for _, name in ipairs({ "CurrentStepScreenPanel", "FillersScreenPanel" }) do
            local frame = rawget(_G, name)
            if frame then frames[#frames + 1] = frame end
        end
        return frames
    end,
})
NS.GetAPRTrackerViewerStatus = viewer.GetStatus

local Recommend = NS.Internal.StartupNotices.RegisterArrow("AWP_APR_ARROW", {
    deferCombat = true,
    check = function()
        local native = NS.Internal.APRProvider.GetRuntime()
        local profile = native and native.settings and native.settings.profile
        local db = rawget(_G, "AzerothWaypointCharDB")
        local snapshot = NS.Internal.APRProvider.GetSnapshot()
        return NS.IsAPRLoaded() and profile and profile.showArrow ~= false and db and not db.aprArrowPromptShown
            and snapshot.state == "ready" and snapshot.target ~= nil
            and NS.IsRoutingEnabled() and NS.GetActiveGuideProvider() == "apr"
    end,
    dialog = {
        text = "AWP is navigating APR guide targets. Turn off APR's own arrow to avoid two navigation arrows?",
        button1 = "Turn Off APR Arrow",
        button2 = "Keep Enabled",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            local native = NS.Internal.APRProvider.GetRuntime()
            if native and native.settings and native.settings.profile then
                native.settings.profile.showArrow = false
                if native.Arrow and type(native.Arrow.RefreshActivity) == "function" then native.Arrow:RefreshActivity() end
            end
            AzerothWaypointCharDB.aprArrowPromptShown = true
        end,
        OnCancel = function() AzerothWaypointCharDB.aprArrowPromptShown = true end,
    },
})
NS.Internal.APRProvider.Subscribe(function() Recommend() end)
